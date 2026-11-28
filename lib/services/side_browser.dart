import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

import 'kiosk_browser.dart';

/// A web page shown inside a tile, as though it were part of it.
///
/// Flutter has no web view on Linux, and Firefox — the engine wanted here,
/// for its cookie-banner handling and its tracking protection — cannot be
/// built into another program: Mozilla dropped the means years ago. So the
/// page is a real Firefox window with none of its own furniture, placed by
/// the compositor exactly over a hole the tile leaves for it and kept above
/// the kiosk. The tile draws the frame around the hole and the buttons that
/// steer the page. Those reach Firefox through WebDriver BiDi, the remote
/// control it has built in, so going back, reloading and showing another
/// page all happen in the same window rather than a new one each time.
///
/// Wayland gives a program no say in where its windows go, so the placing is
/// a labwc window rule, written into `rc.xml` for the hole's position and
/// size and re-read by labwc when that changes. Anywhere else — no labwc, no
/// Firefox — [available] is false, and the page opens the old way instead,
/// in a window of its own.
class SideBrowser extends ChangeNotifier {
  SideBrowser._();

  static final SideBrowser instance = SideBrowser._();

  /// The window's Wayland app_id, which the window rule matches on.
  static const String appId = 'homecanvas-side';

  static const String _profile = 'side-page';

  @visibleForTesting
  static bool? availableOverride;

  Process? _proc;
  BidiClient? _bidi;
  Future<BidiClient?>? _bidiReady;
  Rect? _rect;
  Object? _owner;
  String? _url;
  bool _loading = false;
  bool _hidden = false;
  Future<void> _queue = Future.value();

  /// Whether a page is up (or on its way).
  bool get isOpen => _proc != null;

  /// Where it is, in the kiosk's logical pixels.
  Rect? get rect => _rect;

  /// The address it is showing, as Firefox last reported it.
  String? get url => _url;

  bool get loading => _loading;
  bool get hidden => _hidden;

  /// Whether Back and Reload can reach it. Not until Firefox has answered,
  /// a second or two after it starts.
  bool get steerable => _bidi != null;

  /// Whether [owner] opened the page that is up.
  bool isOwnedBy(Object owner) => isOpen && identical(_owner, owner);

  /// Whether a page can be shown inside a tile here at all.
  Future<bool> available() async {
    final asked = availableOverride;
    if (asked != null) return asked;
    if (!Platform.isLinux || _labwcPid == null) return false;
    if (await KioskBrowser.resolve() != 'firefox') return false;
    return await _rcFile() != null;
  }

  /// Shows [url] over [rect], for [owner].
  ///
  /// Another page from the same place reuses the window; anywhere else, or
  /// before Firefox can be steered, it starts afresh. False if it could not
  /// be shown at all, when the caller should fall back to a window of its
  /// own.
  Future<bool> show(String url, Rect rect, {required Object owner}) =>
      _serial(() async {
        if (!KioskBrowser.isWebAddress(url)) return false;
        final r = snap(rect);
        if (r.width < 240 || r.height < 160) return false;
        _owner = owner;

        if (_proc != null && _rect == r) {
          final bidi = _bidi ?? await _bidiReady;
          if (bidi != null && await bidi.navigate(url)) {
            if (_hidden) await _reveal();
            _url = url;
            _loading = true;
            notifyListeners();
            return true;
          }
        }

        await _stop();
        if (!await _place(r)) return false;
        final dir = KioskBrowser.profileDir('firefox', _profile);
        if (dir == null) return false;
        // The last page's session, so there is nothing for Firefox to offer
        // to bring back: a page in a tile starts with the page asked for.
        for (final name in ['sessionstore.jsonlz4', 'sessionstore-backups']) {
          try {
            await FileSystemEntity.isDirectory('$dir/$name')
                ? await Directory('$dir/$name').delete(recursive: true)
                : await File('$dir/$name').delete();
          } catch (_) {}
        }
        await KioskBrowser.writeProfile(
          dir,
          window: r.size,
          chromeless: true,
          extraPrefs: prefs,
        );

        final Process proc;
        try {
          proc = await Process.start(
            'firefox',
            [
              '--new-instance',
              '--profile',
              dir,
              '--name',
              appId,
              // Any free port: Firefox says which on stderr.
              '--remote-debugging-port',
              '0',
              url,
            ],
            environment: const {'MOZ_ENABLE_WAYLAND': '1'},
          );
        } catch (e) {
          debugPrint('SideBrowser: could not start Firefox: $e');
          return false;
        }
        _proc = proc;
        _rect = r;
        _url = url;
        _loading = true;
        _hidden = false;
        // Another browser window would open underneath this one, which stays on
        // top; only one page at a time, then.
        KioskBrowser.beforeOpen = () => close();

        final heard = Completer<String?>();
        unawaited(proc.stdout.drain<void>().catchError((_) {}));
        proc.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              (line) {
                final m = _listening.firstMatch(line);
                if (m != null && !heard.isCompleted) heard.complete(m.group(1));
              },
              onDone: () {
                if (!heard.isCompleted) heard.complete(null);
              },
              onError: (_) {},
            );
        unawaited(proc.exitCode.then((_) => _gone(proc)));
        _bidiReady = heard.future
            .timeout(const Duration(seconds: 30), onTimeout: () => null)
            .then((ws) async {
              if (ws == null || !identical(_proc, proc)) return null;
              final bidi = await BidiClient.connect(ws, onEvent: _onEvent);
              if (!identical(_proc, proc)) {
                bidi?.dispose();
                return null;
              }
              _bidi = bidi;
              if (bidi != null) _loading = await bidi.stillLoading();
              notifyListeners();
              return bidi;
            });
        notifyListeners();
        return true;
      });

  /// Back a page, as the browser's own Back button would.
  Future<void> back() async => _bidi?.traverse(-1);

  Future<void> reload() async => _bidi?.reload();

  /// Takes the page off the screen without closing it — while something
  /// else is in front of the tile, which the page would otherwise cover.
  Future<void> hide() async {
    if (_proc == null || _hidden) return;
    _hidden = true;
    notifyListeners();
    await _wlrctl(['toplevel', 'minimize', 'app_id:$appId']);
  }

  /// Puts back a page [hide] took away.
  Future<void> reveal() => _serial(_reveal);

  Future<void> _reveal() async {
    if (_proc == null || !_hidden) return;
    _hidden = false;
    notifyListeners();
    await _wlrctl(['toplevel', 'focus', 'app_id:$appId']);
  }

  /// Closes the page, if [owner] opened it — or whoever did, without one.
  Future<void> close({Object? owner}) => _serial(() async {
    if (owner != null && !identical(owner, _owner)) return;
    final had = _proc != null;
    await _stop();
    if (had) await KioskBrowser.focusKiosk();
  });

  Future<T> _serial<T>(Future<T> Function() job) {
    final next = _queue.then((_) => job());
    _queue = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<void> _stop() async {
    final proc = _proc;
    if (proc == null) return;
    final bidi = _bidi;
    _forget();
    if (bidi != null) {
      await bidi.closeBrowser();
      bidi.dispose();
    } else {
      proc.kill();
    }
    // Its profile stays locked until it has gone, and a second Firefox on a
    // locked profile asks the screen whether to wait — nobody would answer.
    var code = await proc.exitCode.timeout(
      const Duration(seconds: 4),
      onTimeout: () => -1,
    );
    if (code == -1) {
      proc.kill(ProcessSignal.sigkill);
      code = await proc.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () => -1,
      );
    }
  }

  void _forget() {
    _proc = null;
    _bidi = null;
    _bidiReady = null;
    _url = null;
    _loading = false;
    _hidden = false;
    _owner = null;
    KioskBrowser.beforeOpen = null;
    notifyListeners();
  }

  /// Firefox went by itself: closed by the page, or crashed.
  void _gone(Process proc) {
    if (!identical(_proc, proc)) return;
    _bidi?.dispose();
    _forget();
    unawaited(KioskBrowser.focusKiosk());
  }

  void _onEvent(String method, Map<String, dynamic> params) {
    switch (method) {
      case 'browsingContext.navigationStarted':
        _loading = true;
      case 'browsingContext.load':
        _loading = false;
      default:
        return;
    }
    final url = params['url'];
    if (url is String && url.isNotEmpty) _url = url;
    notifyListeners();
  }

  static final RegExp _listening = RegExp(
    r'WebDriver BiDi listening on (ws://\S+)',
  );

  static int? get _labwcPid =>
      int.tryParse(Platform.environment['LABWC_PID'] ?? '');

  /// [rect] shrunk to whole pixels, so the window never pokes out of the
  /// hole by a fraction.
  static Rect snap(Rect rect) => Rect.fromLTRB(
    rect.left.ceilToDouble(),
    rect.top.ceilToDouble(),
    rect.right.floorToDouble(),
    rect.bottom.floorToDouble(),
  );

  /// The `user.js` lines for a page in a tile.
  @visibleForTesting
  static const String prefs = '''
// --- A page inside a tile -------------------------------------------------
// A link that wants a new window opens in this one: there is no tab bar to
// find another tab in, and Back has to lead somewhere.
user_pref("browser.link.open_newwindow", 1);
user_pref("browser.link.open_newwindow.restriction", 0);
// Remote control is how the tile's buttons reach the page, not a test run:
// none of the preferences Firefox sets for automated testing, then.
user_pref("remote.prefs.recommended", false);
''';

  static const String _begin = '<!-- homecanvas-side -->';
  static const String _end = '<!-- /homecanvas-side -->';

  /// The window rule that puts the page at [r].
  @visibleForTesting
  static String ruleXml(Rect r) =>
      '''
    $_begin
    <!-- Written by HomeCanvas: a web page shown inside a tile, placed over
         the hole the tile leaves for it. Rewritten when that moves. -->
    <windowRule identifier="$appId" serverDecoration="no">
      <action name="MoveTo" x="${r.left.round()}" y="${r.top.round()}"/>
      <action name="ResizeTo" width="${r.width.round()}" height="${r.height.round()}"/>
      <action name="ToggleAlwaysOnTop"/>
    </windowRule>
    $_end
''';

  /// [rc] with the page's window rule at [r] in place of any earlier one, or
  /// null if it is not a labwc configuration this can safely edit.
  @visibleForTesting
  static String? withRule(String rc, Rect r) {
    var s = rc
        // As written last time.
        .replaceAll(
          RegExp(
            '[ \\t]*${RegExp.escape(_begin)}.*?${RegExp.escape(_end)}[ \\t]*\\n?',
            dotAll: true,
          ),
          '',
        )
        // And any written by hand for the same window, which would fight it.
        .replaceAll(
          RegExp(
            '[ \\t]*<windowRule\\b[^>]*identifier="$appId"[^>]*/>[ \\t]*\\n?',
          ),
          '',
        )
        .replaceAll(
          RegExp(
            '[ \\t]*<windowRule\\b[^>]*identifier="$appId"[^>]*>.*?</windowRule>[ \\t]*\\n?',
            dotAll: true,
          ),
          '',
        );
    final block = ruleXml(r);
    final rules = s.lastIndexOf('</windowRules>');
    if (rules >= 0) {
      final line = s.lastIndexOf('\n', rules) + 1;
      return s.substring(0, line) + block + s.substring(line);
    }
    final end = s.lastIndexOf('</openbox_config>');
    if (end < 0) return null;
    final line = s.lastIndexOf('\n', end) + 1;
    s =
        '${s.substring(0, line)}  <windowRules>\n$block  </windowRules>\n'
        '${s.substring(line)}';
    return s;
  }

  static const String _emptyRc =
      '<?xml version="1.0"?>\n'
      '<openbox_config xmlns="http://openbox.org/3.4/rc">\n'
      '</openbox_config>\n';

  /// The user's labwc configuration, or null if there is none this may
  /// write: without one, labwc uses the system's, and a file holding only
  /// this rule would replace it — unless labwc merges the two, as Raspberry
  /// Pi OS starts it to.
  static Future<File?> _rcFile() async {
    final env = Platform.environment;
    final home = env['HOME'];
    final base =
        env['XDG_CONFIG_HOME'] ?? (home == null ? null : '$home/.config');
    if (base == null) return null;
    final file = File('$base/labwc/rc.xml');
    if (await file.exists()) return file;
    return await _labwcMerges() ? file : null;
  }

  static Future<bool> _labwcMerges() async {
    final pid = _labwcPid;
    if (pid == null) return false;
    try {
      final args = (await File(
        '/proc/$pid/cmdline',
      ).readAsString()).split('\u0000');
      return args.contains('-m') || args.contains('--merge-config');
    } catch (_) {
      return false;
    }
  }

  /// Writes the rule for [r] and has labwc read it, if it has changed.
  Future<bool> _place(Rect r) async {
    final file = await _rcFile();
    final pid = _labwcPid;
    if (file == null || pid == null) return false;
    try {
      final exists = await file.exists();
      final old = exists ? await file.readAsString() : _emptyRc;
      final updated = withRule(old, r);
      if (updated == null) {
        debugPrint('SideBrowser: ${file.path} is not one I can edit');
        return false;
      }
      if (updated == old) return true;
      await file.parent.create(recursive: true);
      final backup = File('${file.path}.before-homecanvas-side');
      if (exists && !await backup.exists()) await file.copy(backup.path);
      final tmp = File('${file.path}.homecanvas');
      await tmp.writeAsString(updated);
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('SideBrowser: could not write the window rule: $e');
      return false;
    }
    // labwc re-reads its configuration on SIGHUP; `labwc --reconfigure`
    // does the same through LABWC_PID, which is all this is.
    Process.killPid(pid, ProcessSignal.sighup);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return true;
  }

  static Future<void> _wlrctl(List<String> args) async {
    try {
      await Process.run('wlrctl', args);
    } catch (_) {}
  }
}

/// Firefox's remote control, as much of it as the tile's buttons need.
///
/// WebDriver BiDi over a WebSocket: commands with ids and their answers,
/// and events in between, all JSON.
class BidiClient {
  BidiClient._(this._socket, this._onEvent) {
    _socket.listen(
      _received,
      onDone: _failAll,
      onError: (_) => _failAll(),
      cancelOnError: true,
    );
  }

  final WebSocket _socket;
  final void Function(String method, Map<String, dynamic> params)? _onEvent;
  final Map<int, Completer<Map<String, dynamic>>> _waiting = {};
  int _id = 0;

  /// The page's own browsing context — the tab, as it were.
  String? context;

  /// Kept apart from the page's own scripts, which cannot see it.
  static const String _sandbox = 'homecanvas';

  /// Connects to Firefox at [base] and opens a session, or null.
  static Future<BidiClient?> connect(
    String base, {
    void Function(String method, Map<String, dynamic> params)? onEvent,
  }) async {
    final WebSocket socket;
    try {
      socket = await WebSocket.connect(
        '$base/session',
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('SideBrowser: no remote control: $e');
      return null;
    }
    final client = BidiClient._(socket, onEvent);
    try {
      await client.send('session.new', {'capabilities': <String, Object>{}});
      final tree = await client.send('browsingContext.getTree', {
        'maxDepth': 0,
      });
      final contexts = tree['contexts'] as List;
      client.context = (contexts.first as Map)['context'] as String;
      await client.send('session.subscribe', {
        'events': ['browsingContext.navigationStarted', 'browsingContext.load'],
      });
      return client;
    } catch (e) {
      debugPrint('SideBrowser: remote control would not start: $e');
      client.dispose();
      return null;
    }
  }

  /// Sends [method] and waits for its answer's `result`. Throws
  /// [BidiError] for an error answer.
  Future<Map<String, dynamic>> send(
    String method,
    Map<String, Object?> params, {
    Duration timeout = const Duration(seconds: 15),
  }) {
    final id = ++_id;
    final answer = Completer<Map<String, dynamic>>();
    _waiting[id] = answer;
    try {
      _socket.add(jsonEncode({'id': id, 'method': method, 'params': params}));
    } catch (e) {
      _waiting.remove(id);
      return Future.error(BidiError('closed', '$e'));
    }
    return answer.future.timeout(
      timeout,
      onTimeout: () {
        _waiting.remove(id);
        throw BidiError('timeout', method);
      },
    );
  }

  void _received(dynamic data) {
    if (data is! String) return;
    final Map<String, dynamic> message;
    try {
      message = (jsonDecode(data) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    final id = message['id'];
    if (id is int) {
      final answer = _waiting.remove(id);
      if (answer == null) return;
      if (message['type'] == 'error') {
        answer.completeError(
          BidiError('${message['error']}', '${message['message'] ?? ''}'),
        );
      } else {
        answer.complete(
          ((message['result'] as Map?) ?? const {}).cast<String, dynamic>(),
        );
      }
      return;
    }
    final method = message['method'];
    final params = message['params'];
    // The page itself, not the frames inside it: an advert's iframe loading
    // is not the page loading.
    if (method is String && params is Map && params['context'] == context) {
      _onEvent?.call(method, params.cast<String, dynamic>());
    }
  }

  void _failAll() {
    for (final answer in _waiting.values) {
      if (!answer.isCompleted) {
        answer.completeError(BidiError('closed', 'connection closed'));
      }
    }
    _waiting.clear();
  }

  Future<bool> _try(String method, Map<String, Object?> params) async {
    try {
      await send(method, params);
      return true;
    } catch (e) {
      debugPrint('SideBrowser: $method: $e');
      return false;
    }
  }

  /// Shows [url], without waiting for it to load.
  Future<bool> navigate(String url) => _try('browsingContext.navigate', {
    'context': context,
    'url': url,
    'wait': 'none',
  });

  /// Back ([delta] -1) or forward through the page's history.
  Future<bool> traverse(int delta) => _try('browsingContext.traverseHistory', {
    'context': context,
    'delta': delta,
  });

  Future<bool> reload() =>
      _try('browsingContext.reload', {'context': context, 'wait': 'none'});

  /// Whether the page is still on its way.
  Future<bool> stillLoading() async {
    final value = await _evaluate('document.readyState');
    return value != null && value != 'complete';
  }

  Future<Object?> _evaluate(String expression) async {
    try {
      final r = await send('script.evaluate', {
        'expression': expression,
        'target': {'context': context, 'sandbox': _sandbox},
        'awaitPromise': false,
      });
      final result = r['result'];
      return result is Map ? result['value'] : null;
    } catch (_) {
      return null;
    }
  }

  /// Asks Firefox to close, which ends it. Its answer may never come — the
  /// connection goes with it — so this does not wait long.
  Future<void> closeBrowser() async {
    try {
      await send(
        'browser.close',
        const {},
        timeout: const Duration(seconds: 2),
      );
    } catch (_) {}
  }

  void dispose() {
    _failAll();
    unawaited(_socket.close().catchError((_) {}));
  }
}

class BidiError implements Exception {
  BidiError(this.error, this.message);
  final String error;
  final String message;

  @override
  String toString() => 'BidiError($error: $message)';
}
