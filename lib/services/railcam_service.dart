import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../l10n/l10n.dart';
import 'video_link.dart';
import 'video_stream.dart';
import 'youtube_link.dart';
import 'yt_dlp.dart' show VideoException;

/// One of railcam.uk's cameras.
@immutable
class RailCam {
  const RailCam({
    required this.id,
    required this.name,
    this.place = '',
    this.area = '',
  });

  /// What the site calls it in its addresses: "RCCrewe1".
  final String id;

  /// "Crewe 1 - Chester Lines".
  final String name;

  /// Where the site files it: "Crewe", "East Lancs Railway", "USA L to P".
  final String place;

  /// "Main Line C to D", "Heritage", "International".
  final String area;

  /// For a list of every camera, where its place is what it is found by.
  String get label =>
      place.isEmpty || name.startsWith(place) ? name : '$place: $name';

  /// The site's own small picture of the view — a still kept for its menus,
  /// not a live one.
  String get thumbnailUrl => RailcamLink(id).thumbnailUrl;
}

/// What a camera's page on the site has to say about it.
@immutable
class RailcamPage {
  const RailcamPage({
    this.title = '',
    this.hls,
    this.youtube,
    this.offline = false,
    this.noAccess = false,
  });

  final String title;

  /// The stream, when the camera is on railcam's own servers or another's.
  final String? hls;

  /// The video's id, when the camera is carried by YouTube.
  final String? youtube;
  final bool offline;

  /// Turned away: signed out, or a supporters' camera and not a supporter.
  final bool noAccess;
}

/// railcam.uk's lineside cameras, as the account signed in sees them.
///
/// The site has no API to speak of, so this reads the pages a browser would.
/// Which cameras there are comes from its Dashboard page — one page for all
/// of them — with their fuller names from the map anyone can see, which also
/// stands in while nobody is signed in. A camera's stream is named by its
/// own page, asked for when the camera is opened: railcam's own are plain
/// HLS, which mpv plays as it is, and the rest are on YouTube.
///
/// Signing in is the site's own form, with the username and password from
/// the widget's settings. The session is kept in memory and renewed when the
/// site stops honouring it.
class RailcamService extends ChangeNotifier {
  RailcamService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: _site,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
              // Its "signed out" is a redirect, so those are read, not
              // followed; and its pages are not all the UTF-8 they claim.
              followRedirects: false,
              validateStatus: (s) => s != null && s < 400,
              responseType: ResponseType.bytes,
              headers: const {
                'User-Agent': 'HomeCanvas/1.0 (home dashboard panel)',
              },
            ),
          );

  static const _site = 'https://railcam.uk';

  final Dio _dio;
  final Map<String, String> _cookies = {};

  String _username = '';
  String _password = '';

  /// The site said no to this username and password, so they are not tried
  /// again until they change.
  bool _rejected = false;
  DateTime? _signedInAt;
  Future<bool>? _signingIn;

  /// What each camera's page said, for ten minutes: a camera playing in a
  /// tile and then touched is the same stream, and need not be asked about
  /// twice. Only pages with something to play — an off-line camera may be
  /// back the next time.
  final Map<String, (DateTime, RailcamPage)> _pages = {};
  final Map<String, (DateTime, String)> _playlists = {};

  List<RailCam>? _cams;
  bool _full = false;
  DateTime? _fetched;
  bool _busy = false;
  String? _error;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _dio.close();
    super.dispose();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// The cameras, or null until the list has arrived. Only those on the
  /// site's map until the account is signed in.
  List<RailCam>? get cams => _cams;
  String? get error => _error;
  bool get hasAccount => _username.isNotEmpty && _password.isNotEmpty;

  RailCam? cam(String id) {
    for (final c in _cams ?? const <RailCam>[]) {
      if (c.id == id) return c;
    }
    return null;
  }

  @visibleForTesting
  void debugSet(List<RailCam> list) {
    _cams = list;
    _full = true;
    _fetched = DateTime.now();
    _changed();
  }

  /// The account, from the widget's settings. Says nothing to listeners —
  /// it is called while tiles are being built; [ensure] follows it.
  void useAccount(String username, String password) {
    username = username.trim();
    if (username == _username && password == _password) return;
    _username = username;
    _password = password;
    _rejected = false;
    _signedInAt = null;
    _cookies.clear();
    _pages.clear();
    _playlists.clear();
    _error = null;
    // The list is the new account's to fetch.
    _full = false;
    _fetched = null;
  }

  /// Fetches the list of cameras if it is a day old, or sooner while it is
  /// not the full one.
  Future<void> ensure() async {
    final last = _fetched;
    if (_busy ||
        (last != null &&
            DateTime.now().difference(last) <
                (_full
                    ? const Duration(hours: 24)
                    : const Duration(minutes: 15)))) {
      return;
    }
    _busy = true;
    try {
      final onMap = parseMap(await _get('/camsMap.php') ?? '');
      var cams = onMap;
      var full = false;
      String? error;
      if (hasAccount) {
        final listed = parseDashboard(
          await _asMember('/cameras/dashboard.php') ?? '',
        );
        if (listed.isNotEmpty) {
          final names = {for (final c in onMap) c.id: c.name};
          cams = [
            for (final c in listed)
              RailCam(
                id: c.id,
                name: names[c.id] ?? c.name,
                place: c.place,
                area: c.area,
              ),
          ];
          full = true;
        } else if (_rejected) {
          error = _notAccepted;
        }
      }
      if (cams.isNotEmpty) _cams = cams;
      _full = full;
      _error = error;
    } catch (e) {
      debugPrint('Railcam: $e');
      _error = tr('widget.railcam.unreachable', 'Could not reach railcam.uk');
    } finally {
      _fetched = DateTime.now();
      _busy = false;
      _changed();
    }
  }

  /// Every camera, id to name, for the editor's picker.
  Future<Map<String, String>> choices() async {
    await ensure();
    final cams = [...?_cams]..sort((a, b) => a.label.compareTo(b.label));
    return {for (final c in cams) c.id: c.label};
  }

  /// What mpv should open for the camera [link] names. A camera carried by
  /// YouTube is handed to [youtube], which has yt-dlp to find its stream.
  /// Either way the version is the best no taller than [maxHeight].
  Future<VideoStream> find(
    VideoLink link, {
    required int maxHeight,
    required Future<VideoStream> Function(YouTubeLink link) youtube,
  }) async {
    final kept = _pages[link.id];
    final RailcamPage page;
    if (kept != null &&
        DateTime.now().difference(kept.$1) < const Duration(minutes: 10)) {
      page = kept.$2;
    } else {
      final String? html;
      try {
        html = await _asMember(link.url);
      } on DioException catch (e) {
        debugPrint('Railcam: ${link.id}: $e');
        throw VideoException(
          tr('widget.railcam.unreachable', 'Could not reach railcam.uk'),
        );
      }
      page = parsePlayer(html ?? '');
      if (html == null || page.noAccess) {
        throw VideoException(
          _rejected
              ? _notAccepted
              : hasAccount
              ? tr(
                  'widget.railcam.noAccess',
                  'Railcam would not show this camera to your account. Some '
                      'are for supporters only.',
                )
              : tr(
                  'widget.railcam.needsAccount',
                  'Enter your railcam.uk username and password in this '
                      'widget’s settings in the editor.',
                ),
        );
      }
      if (page.hls != null || page.youtube != null) {
        _pages[link.id] = (DateTime.now(), page);
      }
    }
    final yt = page.youtube;
    if (yt != null) return youtube(YouTubeLink(yt));
    final hls = page.hls;
    if (hls != null) {
      return VideoStream(
        title: page.title.isNotEmpty
            ? page.title
            : cam(link.id)?.name ?? link.id,
        channel: link.siteName,
        uri: await _version(hls, maxHeight),
        isLive: true,
        hls: true,
      );
    }
    throw VideoException(
      page.offline
          ? tr('widget.railcam.offline', 'This camera is off line just now.')
          : tr(
              'widget.railcam.noStream',
              'Railcam’s page for this camera has no stream the panel can '
                  'play.',
            ),
    );
  }

  /// [hls], or the one of its versions that suits a screen [maxHeight]
  /// tall, when it offers several. Railcam's own cameras have one each — most
  /// 1080p, some 720p — but left to itself mpv takes the largest of any
  /// stream's, and a 4K one is more than the Pi can decode.
  Future<String> _version(String hls, int maxHeight) async {
    try {
      // Kept, so the tile's small picture and the full screen's large one
      // are chosen from one asking. Asked for without the account's
      // cookies: not every stream is railcam's.
      // No longer than the page that named it: a version's address can
      // carry a pass that runs out.
      final kept = _playlists[hls];
      var playlist =
          kept != null &&
              DateTime.now().difference(kept.$1) < const Duration(minutes: 10)
          ? kept.$2
          : null;
      if (playlist == null) {
        final r = await _dio.get<List<int>>(hls);
        playlist = utf8.decode(r.data ?? const [], allowMalformed: true);
        _playlists[hls] = (DateTime.now(), playlist);
      }
      return pickVersion(playlist, Uri.parse(hls), maxHeight) ?? hls;
    } catch (e) {
      debugPrint('Railcam: could not read the versions of $hls: $e');
      return hls;
    }
  }

  static final RegExp _versionLine = RegExp(
    r'#EXT-X-STREAM-INF:([^\n]*)\n\s*([^#\s][^\n]*)',
  );

  /// The address of the tallest version in a master [playlist] that is no
  /// taller than [maxHeight] — the shortest, when all of them are. Null when
  /// there is no choice to make, or the sound is listed apart from the
  /// picture, which only the whole playlist puts back together.
  @visibleForTesting
  static String? pickVersion(String playlist, Uri at, int maxHeight) {
    if (playlist.contains('#EXT-X-MEDIA:')) return null;
    final versions = <({int height, int bitrate, String uri})>[];
    for (final m in _versionLine.allMatches(playlist.replaceAll('\r', ''))) {
      final height = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(m[1]!)?[1];
      if (height == null) continue;
      final bitrate = RegExp(r'[:,]BANDWIDTH=(\d+)').firstMatch(m[1]!)?[1];
      versions.add((
        height: int.parse(height),
        bitrate: int.tryParse(bitrate ?? '') ?? 0,
        uri: m[2]!.trim(),
      ));
    }
    if (versions.length < 2) return null;
    final fits = versions.where((v) => v.height <= maxHeight).toList();
    final best = (fits.isNotEmpty ? fits : versions).reduce((a, b) {
      if (a.height != b.height) {
        return (a.height > b.height) == fits.isNotEmpty ? a : b;
      }
      return a.bitrate >= b.bitrate ? a : b;
    });
    // Handed straight to mpv, so nothing but a stream on the web: a
    // playlist is somebody else's words, and mpv opens far more than that.
    final uri = at.resolve(best.uri);
    return uri.isScheme('http') || uri.isScheme('https') ? '$uri' : null;
  }

  String get _notAccepted => tr(
    'widget.railcam.notAccepted',
    'Railcam did not accept that username and password. The username is '
        'not your email address.',
  );

  // --- The site ---------------------------------------------------------------

  /// [path] as the account sees it. The site has no plain "signed out": a
  /// members' page answers with a redirect and a camera's with "No Access".
  /// Either way the account is signed in — once — and the page asked for
  /// again.
  Future<String?> _asMember(String path) async {
    final asked = DateTime.now();
    final body = await _get(path);
    if (body != null && !parsePlayer(body).noAccess) return body;
    final at = _signedInAt;
    // Signed in while this was on its way — several tiles ask at once —
    // so only the asking needs doing again.
    if (at != null && at.isAfter(asked)) return _get(path);
    // Just signed in and still turned away: it is the camera, not the session.
    if (at != null && asked.difference(at) < const Duration(minutes: 1)) {
      return body;
    }
    if (!await _signIn()) return body;
    return _get(path);
  }

  /// The page at [path], or null when the site answers with a redirect.
  Future<String?> _get(String path) async {
    final sent = Map.of(_cookies);
    final r = await _dio.get<List<int>>(path, options: _withCookies());
    _keepCookies(r, sent);
    if ((r.statusCode ?? 0) >= 300) return null;
    return utf8.decode(r.data ?? const [], allowMalformed: true);
  }

  Options _withCookies() => Options(
    headers: {
      if (_cookies.isNotEmpty)
        'Cookie': _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
    },
  );

  /// Keeps the cookies [r] sets — unless they have changed since its
  /// request went out with [sent]. Six tiles asking at once, before there
  /// is a session, are each handed a new one; the last of those answers
  /// must not replace the session that has since signed in.
  void _keepCookies(Response<dynamic> r, Map<String, String> sent) {
    for (final c in r.headers['set-cookie'] ?? const <String>[]) {
      final pair = c.split(';').first;
      final i = pair.indexOf('=');
      if (i <= 0) continue;
      final name = pair.substring(0, i).trim();
      if (_cookies[name] == sent[name]) _cookies[name] = pair.substring(i + 1);
    }
  }

  /// Signs in with the site's own form. One attempt at a time, however many
  /// pages are waiting on it.
  Future<bool> _signIn() {
    if (!hasAccount || _rejected) return Future.value(false);
    return _signingIn ??= _postSignIn().whenComplete(() => _signingIn = null);
  }

  Future<bool> _postSignIn() async {
    final sent = Map.of(_cookies);
    final r = await _dio.post<List<int>>(
      '/account/login.php',
      data: {
        'username': _username,
        'password': _password,
        'loginformused': '1',
        'forgotpassword': '',
      },
      options: _withCookies().copyWith(
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
    _keepCookies(r, sent);
    // Turned down, the form comes back with a word about it; taken, the
    // site sends the account on to its pages.
    final body = utf8.decode(r.data ?? const [], allowMalformed: true);
    final ok = (r.statusCode ?? 0) >= 300 || !body.contains('siteloklogin');
    _rejected = !ok;
    _signedInAt = ok ? DateTime.now() : null;
    if (!ok) debugPrint('Railcam: the sign-in was not accepted');
    return ok;
  }

  // --- Reading its pages ------------------------------------------------------

  static final RegExp _open = RegExp(r"openCam\('([^']+)',\s*'([^']*)'\)");
  static final RegExp _heading = RegExp(
    r'<span[^>]*>([^<]*)<br>([^<]*)</span>',
  );

  /// Every camera on the site's Dashboard page: each is a card headed with
  /// its area and place, over a link that opens it.
  @visibleForTesting
  static List<RailCam> parseDashboard(String html) {
    final out = <String, RailCam>{};
    for (final m in _open.allMatches(html)) {
      final before = html.substring(m.start > 700 ? m.start - 700 : 0, m.start);
      final heading = _heading.allMatches(before).lastOrNull;
      out[m[1]!] = RailCam(
        id: m[1]!,
        name: _text(m[2]!).isEmpty ? m[1]! : _text(m[2]!),
        area: _text(heading?[1] ?? ''),
        place: _text(heading?[2] ?? ''),
      );
    }
    return out.values.toList();
  }

  static final RegExp _marker = RegExp(
    r'camera_thumbs/([^."/]+)\.png"[^>]*><br>([^<]*)<',
  );

  /// The cameras on the site's public map: a marker each, whose pop-up is
  /// the camera's picture over its name.
  @visibleForTesting
  static List<RailCam> parseMap(String html) => [
    for (final m in _marker.allMatches(html))
      if (_text(m[2]!).isNotEmpty) RailCam(id: m[1]!, name: _text(m[2]!)),
  ];

  static final RegExp _title = RegExp(r'<title>([^<]*)');
  static final RegExp _flussonic = RegExp(
    r'''src=["'](https://[^"'\s]+)/embed\.html''',
  );
  static final RegExp _m3u8 = RegExp(r'''https://[^"'\s<>]+\.m3u8[^"'\s<>]*''');
  static final RegExp _youtube = RegExp(
    r'youtube(?:-nocookie)?\.com/embed/([A-Za-z0-9_-]{11})',
  );
  static final RegExp _offLine = RegExp(
    r'''<td\s+class\s*=\s*["']\w*off\w*["']''',
    caseSensitive: false,
  );

  /// A camera's own page. Railcam's servers are Flussonic, embedded as their
  /// player; the stream is beside it under the same name.
  @visibleForTesting
  static RailcamPage parsePlayer(String html) {
    final embed = _flussonic.firstMatch(html)?[1];
    return RailcamPage(
      title: _text(_title.firstMatch(html)?[1] ?? ''),
      hls: embed != null ? '$embed/index.m3u8' : _m3u8.firstMatch(html)?[0],
      youtube: _youtube.firstMatch(html)?[1],
      offline: _offLine.hasMatch(html),
      noAccess: html.contains('No Access'),
    );
  }

  static String _text(String html) => html
      .replaceAll('&amp;', '&')
      .replaceAll('&#39;', '’')
      .replaceAll('&quot;', '"')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
