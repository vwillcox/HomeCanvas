import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../app_paths.dart';
import '../services/computer_power.dart';
import '../services/home_assistant_service.dart';
import '../services/local_network.dart';
import '../services/private_file.dart';
import '../services/routines.dart';
import 'deck_model.dart';

/// A flash on a key: it worked, it did not, or it is under way.
enum DeckFx { ok, alert, busy }

/// The panel's side of StreamerDeck: the computer's daemon connects in on
/// the Share Inbox's port (`GET /deck`, with a sender's token), sends the
/// deck drawn out, and is told when a key it runs is pressed.
///
/// Everything else happens here: moving between pages, folders and
/// profiles, and the keys the panel runs itself — its Home Assistant, its
/// routines, switching the computer on — so those work with it off.
///
/// Costs nothing while the deck is closed: the socket waits, and the one
/// timer (Home Assistant states for the keys that show them) runs only
/// while the deck is open.
class DeckLink extends ChangeNotifier {
  DeckLink({
    required this.home,
    required this.routines,
    required this.runRoutine,
    required this.computer,
    this.keepAwake,
    String? folder,
    String? cacheFolder,
  }) : _file = File(p.join(folder ?? AppPaths.config, 'deck.json')),
       _ownerFile = File(p.join(folder ?? AppPaths.config, 'deck_owner.json')),
       _images = Directory(p.join(cacheFolder ?? AppPaths.cache, 'deck'));

  final HomeAssistantService home;
  final List<HomeRoutine> Function() routines;
  final String Function(HomeRoutine) runRoutine;
  final Future<PcSwitch> Function(bool on) computer;

  /// Told now and then while the deck is open, so the screen stays on.
  final void Function()? keepAwake;

  final File _file;
  final File _ownerFile;
  final Directory _images;

  /// The sender whose computer drives the deck: the first to connect.
  String? _owner;
  String? get owner => _owner;

  WebSocket? _socket;
  String? _pcName;
  DeckSnapshot? _snapshot;
  final Map<String, int> _states = {};
  final Set<String> _have = {};
  final Map<String, (DeckFx, DateTime)> _fx = {};
  bool _open = false;
  Timer? _poll;

  /// What the computer is called, once one has connected.
  String? get pcName => _pcName;
  bool get connected => _socket != null;
  DeckSnapshot? get snapshot => _snapshot;
  bool get isOpen => _open;

  /// Whether there is anything to show: a deck has come at some time.
  bool get known => _snapshot != null || connected;

  // --- Where the deck is -------------------------------------------------

  String? _profileId;
  final List<String> _path = [];
  final Map<String, int> _pageOf = {};

  DeckProfile? get profile => _snapshot?.profile(_profileId);

  /// The folder keys on the way down to the page shown.
  List<DeckKey> get folders {
    final out = <DeckKey>[];
    var pages = profile?.pages ?? const <DeckPage>[];
    for (final id in _path) {
      DeckKey? found;
      for (final page in pages) {
        for (final k in page.keys) {
          if (k.id == id && k.isFolder) found = k;
        }
      }
      if (found == null) break;
      out.add(found);
      pages = found.pages!;
    }
    return out;
  }

  /// The pages shown now — the profile's or the open folder's — and whose.
  (String, List<DeckPage>) get _container {
    final f = folders;
    if (f.isNotEmpty) return (f.last.id, f.last.pages!);
    return (profile?.id ?? '', profile?.pages ?? const []);
  }

  List<DeckPage> get pages => _container.$2;
  bool get inFolder => folders.isNotEmpty;

  int get pageIndex {
    final (id, pages) = _container;
    if (pages.isEmpty) return 0;
    return (_pageOf[id] ?? 0).clamp(0, pages.length - 1);
  }

  DeckPage? get page {
    final ps = pages;
    return ps.isEmpty ? null : ps[pageIndex];
  }

  void showPage(int i) {
    final (id, pages) = _container;
    if (pages.isEmpty) return;
    _pageOf[id] = i % pages.length; // Dart's % is never negative here.
    _viewChanged();
  }

  void nextPage() => showPage(pageIndex + 1);
  void previousPage() => showPage(pageIndex - 1);

  void showProfile(String id, {int page = 0}) {
    final s = _snapshot;
    if (s == null || !s.profiles.any((p) => p.id == id)) return;
    _profileId = id;
    _path.clear();
    _pageOf[id] = page;
    _send({'t': 'profile', 'profile': id});
    _viewChanged();
  }

  void openFolder(DeckKey folder) {
    if (!folder.isFolder) return;
    _path.add(folder.id);
    _pageOf[folder.id] = 0;
    _viewChanged();
  }

  void back() {
    if (_path.isEmpty) return;
    _path.removeLast();
    _viewChanged();
  }

  void _viewChanged() {
    if (_open) _send({'t': 'view', ..._view});
    notifyListeners();
  }

  Map<String, Object?> get _view => {
    'profile': profile?.id,
    'path': List<String>.of(_path),
    'page': pageIndex,
  };

  // --- Keys ----------------------------------------------------------------

  int stateOf(DeckKey key) {
    if (key.action == 'hc.ha.toggle') {
      final e = home.entity(key.setting('entity'));
      if (e != null) return e.on ? 1 : 0;
    }
    return _states[key.id] ?? key.state;
  }

  /// A flash on [key], while it lasts.
  DeckFx? fxOf(DeckKey key) {
    final f = _fx[key.id];
    if (f == null) return null;
    if (f.$1 != DeckFx.busy && DateTime.now().difference(f.$2) > const Duration(milliseconds: 1600)) {
      _fx.remove(key.id);
      return null;
    }
    return f.$1;
  }

  void _flash(String id, DeckFx fx) {
    _fx[id] = (fx, DateTime.now());
    notifyListeners();
    if (fx != DeckFx.busy) {
      Timer(const Duration(milliseconds: 1700), notifyListeners);
    }
  }

  void _settle(String id, bool ok) => _flash(id, ok ? DeckFx.ok : DeckFx.alert);

  /// A key pressed: moved to, done here, or handed to the computer.
  void press(DeckKey key) {
    switch (key.runs) {
      case DeckRuns.nav:
        _navigate(key.action, key.settings, key: key);
      case DeckRuns.panel:
        unawaited(_runHere(key.id, key.action, key.settings, key.steps));
      case DeckRuns.pc:
        if (!_send({'t': 'down', 'id': key.id})) {
          _flash(key.id, DeckFx.alert);
          return;
        }
        _send({'t': 'up', 'id': key.id});
    }
  }

  void _navigate(String action, Map<String, Object?> s, {DeckKey? key}) {
    int? number(Object? v) => v is num ? v.toInt() : int.tryParse('$v');
    switch (action) {
      case 'deck.folder':
        if (key != null) openFolder(key);
      case 'deck.page.next' || 'deck.page.indicator':
        nextPage();
      case 'deck.page.prev':
        previousPage();
      case 'deck.page.goto':
        showPage((number(s['page']) ?? 1) - 1);
      case 'deck.profile':
        final id = '${s['profile'] ?? ''}';
        if (id.isNotEmpty) showProfile(id, page: ((number(s['page']) ?? 1) - 1).clamp(0, 99));
    }
  }

  /// Does a panel action. Says on the key how it went, and tells the
  /// computer when it failed, for its editor.
  Future<void> _runHere(String id, String action, Map<String, Object?> s, List<Map<String, Object?>>? steps) async {
    String text(String k) => '${s[k] ?? ''}'.trim();
    Future<bool> step() async {
      switch (action) {
        case 'hc.ha.toggle':
          final entity = text('entity');
          if (entity.isEmpty) return false;
          final e = home.entity(entity);
          if (e != null && e.switchable) {
            await home.toggle(e);
            return home.error == null;
          }
          return home.service('homeassistant', 'toggle', {'entity_id': entity});
        case 'hc.ha.scene':
          final entity = text('entity');
          final domain = entity.split('.').first;
          if (domain != 'scene' && domain != 'script') return false;
          return home.service(domain, 'turn_on', {'entity_id': entity});
        case 'hc.ha.service':
          final parts = text('service').split('.');
          if (parts.length != 2 || parts.any((x) => x.isEmpty)) return false;
          final data = <String, Object?>{};
          final raw = text('data');
          if (raw.isNotEmpty) {
            final d = jsonDecode(raw);
            if (d is! Map) return false;
            data.addAll(d.cast<String, Object?>());
          }
          if (text('entity').isNotEmpty) data['entity_id'] ??= text('entity');
          return home.service(parts[0], parts[1], data);
        case 'hc.routine':
          final name = text('routine').toLowerCase();
          final r = routines().where((r) => r.name.toLowerCase() == name).firstOrNull;
          if (r == null) return false;
          runRoutine(r);
          return true;
        case 'hc.pc':
          _flash(id, DeckFx.busy);
          final on = text('do') != 'off';
          final r = await computer(on);
          return r == PcSwitch.done || r == PcSwitch.already;
        case 'deck.delay':
          final ms = s['ms'] is num ? (s['ms'] as num).toInt() : 500;
          await Future<void>.delayed(Duration(milliseconds: ms.clamp(0, 60000)));
          return true;
        case 'deck.multi':
          for (final st in steps ?? const <Map<String, Object?>>[]) {
            final a = '${st['action'] ?? ''}';
            final ss = st['settings'] is Map ? (st['settings'] as Map).cast<String, Object?>() : <String, Object?>{};
            if (a.startsWith('deck.page') || a == 'deck.profile') {
              _navigate(a, ss);
              continue;
            }
            final ok = await _do(a, ss, '${st['id'] ?? ''}');
            if (!ok) return false;
          }
          return true;
        default:
          if (action.startsWith('deck.page') || action == 'deck.profile') {
            _navigate(action, s);
            return true;
          }
          return false;
      }
    }

    bool ok;
    try {
      ok = await step();
    } catch (e) {
      debugPrint('Deck: $action: $e');
      ok = false;
    }
    _settle(id, ok);
    if (!ok) {
      _send({'t': 'error', 'id': id, 'message': 'The panel could not do that (${action.replaceFirst('hc.', '')})'});
    }
  }

  /// One step of a multi action the panel runs, without a flash of its own.
  Future<bool> _do(String action, Map<String, Object?> s, String id) async {
    final before = _fx[id];
    await _runHere(id, action, s, null);
    final after = _fx[id];
    _fx.remove(id);
    if (before != null) _fx[id] = before;
    return after?.$1 != DeckFx.alert;
  }

  // --- Opening and closing ---------------------------------------------------

  /// The deck is on screen: tell the computer (its plugins start), and
  /// keep Home Assistant's states fresh for the keys that show them.
  void open() {
    if (_open) return;
    _open = true;
    _send({'t': 'open', ..._view});
    unawaited(home.refresh());
    _poll = Timer.periodic(const Duration(seconds: 5), (t) {
      if (t.tick % 12 == 0) keepAwake?.call();
      if (_showsHomeState) unawaited(home.refresh());
    });
    keepAwake?.call();
    home.addListener(notifyListeners);
  }

  /// Off the screen: nothing more runs for it.
  void close() {
    if (!_open) return;
    _open = false;
    _poll?.cancel();
    _poll = null;
    home.removeListener(notifyListeners);
    _send({'t': 'close'});
  }

  bool get _showsHomeState => page?.keys.any((k) => k.action == 'hc.ha.toggle') ?? false;

  // --- The computer's link ---------------------------------------------------------

  /// Reads the last deck and the images kept with it.
  Future<void> load() async {
    try {
      if (await _ownerFile.exists()) {
        final o = jsonDecode(await _ownerFile.readAsString());
        if (o is Map && o['sender'] is String) _owner = o['sender'] as String;
      }
      if (await _file.exists()) {
        _snapshot = DeckSnapshot.fromJson(jsonDecode(await _file.readAsString()));
        _profileId ??= _snapshot?.active;
      }
      if (await _images.exists()) {
        await for (final f in _images.list()) {
          if (f is File) _have.add(p.basename(f.path));
        }
      }
    } catch (e) {
      debugPrint('Deck: could not read the last deck: $e');
    }
    notifyListeners();
  }

  /// Takes the computer's connection (`GET /deck`), which [sender]'s token
  /// let in.
  ///
  /// More is at stake than with a share — the computer's keys run whatever
  /// it says, and through the panel it can work the lights — so a token
  /// alone is not enough: the computer must be on the home network, not
  /// come through a proxy from outside, and be the sender that first drove
  /// the deck. Anyone else holding a sender's token (a phone) is refused.
  Future<void> accept(HttpRequest request, String sender) async {
    Future<void> refuse(int status, String why) async {
      debugPrint('Deck: refused $sender from ${request.connectionInfo?.remoteAddress.address}: $why');
      request.response
        ..statusCode = status
        ..write(why);
      await request.response.close();
    }

    final proxied = request.headers.value('x-forwarded-for') != null || request.headers.value('forwarded') != null;
    if (proxied || !isLocalAddress(request.connectionInfo?.remoteAddress)) {
      return refuse(HttpStatus.forbidden, 'The deck is for the home network only.');
    }
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      return refuse(HttpStatus.upgradeRequired, 'A WebSocket is needed.');
    }
    if (_owner != null && _owner != sender) {
      return refuse(HttpStatus.forbidden, 'The deck is driven by another sender’s computer.');
    }
    if (_owner == null) {
      _owner = sender;
      try {
        await writePrivateFile(_ownerFile.path, jsonEncode({'sender': sender}));
      } catch (e) {
        debugPrint('Deck: could not keep who drives it: $e');
      }
    }
    var name = 'Computer';
    try {
      name = Uri.decodeComponent(request.headers.value('x-deck-name') ?? name).trim();
    } on ArgumentError {
      // Kept as "Computer".
    }
    if (name.length > 60) name = name.substring(0, 60);
    final ws = await WebSocketTransformer.upgrade(request);
    ws.pingInterval = const Duration(seconds: 30);
    final old = _socket;
    _socket = ws;
    _pcName = name.isEmpty ? sender : name;
    unawaited(old?.close(4000, 'Another computer took over'));
    debugPrint('Deck: $_pcName connected');
    _send({'t': 'hello', 'v': 1, 'name': 'HomeCanvas'});
    if (_open) _send({'t': 'open', ..._view});
    notifyListeners();
    ws.listen(
      (data) => _received(data),
      onDone: () => _lost(ws),
      onError: (_) => _lost(ws),
      cancelOnError: true,
    );
  }

  void _lost(WebSocket ws) {
    if (_socket != ws) return;
    _socket = null;
    _states.clear();
    _fx.removeWhere((_, f) => f.$1 == DeckFx.busy);
    debugPrint('Deck: $_pcName went');
    notifyListeners();
  }

  bool _send(Map<String, Object?> m) {
    final ws = _socket;
    if (ws == null) return false;
    try {
      ws.add(jsonEncode(m));
      return true;
    } catch (_) {
      return false;
    }
  }

  void _received(Object? data) {
    if (data is List<int>) {
      unawaited(_image(Uint8List.fromList(data)));
      return;
    }
    if (data is! String) return;
    Object? m;
    try {
      m = jsonDecode(data);
    } on FormatException {
      return;
    }
    if (m is! Map) return;
    switch (m['t']) {
      case 'deck':
        unawaited(_deck(m, data));
      case 'state':
        final id = '${m['id']}';
        final s = m['state'];
        if (s is num) {
          _states[id] = s.toInt();
          notifyListeners();
        }
      case 'fx':
        _flash('${m['id']}', switch (m['fx']) {
          'ok' => DeckFx.ok,
          'busy' => DeckFx.busy,
          _ => DeckFx.alert,
        });
      case 'run':
        final k = m['key'];
        if (k is Map) {
          final s = k['settings'] is Map ? (k['settings'] as Map).cast<String, Object?>() : <String, Object?>{};
          final steps = k['steps'] is List ? [for (final x in k['steps'] as List) if (x is Map) x.cast<String, Object?>()] : null;
          unawaited(_runHere('${k['id'] ?? ''}', '${k['action'] ?? ''}', s, steps));
        }
      case 'show':
        final id = '${m['profile'] ?? ''}';
        if (id.isNotEmpty) showProfile(id, page: m['page'] is num ? (m['page'] as num).toInt() : 0);
      case 'ask':
        unawaited(_answer(m['id'], '${m['what']}'));
    }
  }

  Future<void> _deck(Map m, String raw) async {
    final s = DeckSnapshot.fromJson(m);
    if (s == null) return;
    final first = _snapshot == null;
    _snapshot = s;
    if (first || !s.profiles.any((p) => p.id == _profileId)) {
      _profileId = s.active;
      _path.clear();
    }
    // Folders that are gone are left.
    if (folders.length != _path.length) _path.removeRange(folders.length, _path.length);
    notifyListeners();
    final want = s.images;
    final missing = want.difference(_have).toList();
    for (var i = 0; i < missing.length; i += 200) {
      _send({'t': 'need', 'ids': missing.sublist(i, (i + 200).clamp(0, missing.length))});
    }
    try {
      await writePrivateFile(_file.path, raw);
      await _tidyImages(want);
    } catch (e) {
      debugPrint('Deck: could not keep the deck: $e');
    }
  }

  /// Images no key shows any more are let go.
  Future<void> _tidyImages(Set<String> want) async {
    if (!await _images.exists()) return;
    for (final name in _have.difference(want).toList()) {
      try {
        await File(p.join(_images.path, name)).delete();
      } catch (_) {}
      _have.remove(name);
    }
  }

  static final _safeName = RegExp(r'^[0-9a-zA-Z._-]{4,120}$');

  /// One image: its name's length, its name, then the bytes.
  Future<void> _image(Uint8List frame) async {
    if (frame.isEmpty) return;
    final n = frame[0];
    if (frame.length < 1 + n) return;
    final name = ascii.decode(frame.sublist(1, 1 + n), allowInvalid: true);
    if (!_safeName.hasMatch(name) || name.contains('..')) return;
    try {
      await _images.create(recursive: true);
      await File(p.join(_images.path, name)).writeAsBytes(frame.sublist(1 + n), flush: true);
      _have.add(name);
      _imagesChanged();
    } catch (e) {
      debugPrint('Deck: could not keep an image: $e');
    }
  }

  // Images often come in a run: one redraw for the lot.
  Timer? _redraw;
  void _imagesChanged() {
    _redraw ??= Timer(const Duration(milliseconds: 60), () {
      _redraw = null;
      notifyListeners();
    });
  }

  /// The file for an image, if it is here yet.
  File? imageFile(String? name) {
    if (name == null || !_have.contains(name)) return null;
    return File(p.join(_images.path, name));
  }

  Future<void> _answer(Object? id, String what) async {
    Object? data;
    switch (what) {
      case 'entities':
        await home.refresh();
        final choices = await home.entityChoices(const {
          'light', 'switch', 'fan', 'input_boolean', 'automation', 'cover', 'lock', 'media_player', 'climate',
          'humidifier', 'siren', 'vacuum', 'scene', 'script', 'button', 'input_button',
        });
        data = [
          for (final c in choices)
            {'id': c.id, 'name': c.name, 'area': c.area, 'state': home.entity(c.id)?.state},
        ];
      case 'routines':
        data = [
          for (final r in routines()) {'name': r.name, 'says': r.phrases.isEmpty ? '' : '“${r.phrases.first}”'},
        ];
    }
    _send({'t': 'answer', 'id': id, 'data': data});
  }

  /// Lets another sender's computer drive the deck: the next to connect.
  Future<void> forgetOwner() async {
    _owner = null;
    try {
      await _ownerFile.delete();
    } catch (_) {}
    notifyListeners();
  }

  @override
  void dispose() {
    close();
    _redraw?.cancel();
    unawaited(_socket?.close());
    super.dispose();
  }
}
