import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/railcam_widget.dart';
import 'package:home_canvas/dashboard/widgets/widgets.dart';
import 'package:home_canvas/services/railcam_service.dart';
import 'package:home_canvas/services/video_link.dart';
import 'package:home_canvas/services/video_stream.dart';
import 'package:home_canvas/services/yt_dlp.dart' show VideoException;

import 'new_widgets_fit_test.dart' show shapes, tile;

/// Two cards of the site's Dashboard page, as it writes them.
const _dashboard = '''
<div class="col-sm-2" style="padding:10px;">
  <div style="background-color:#333322; font-size:10px;">
    <span style="color: #ffffff; ">Main Line C to D<br>Crewe</span>
  </div>
  <div style="border: 0px solid #666;padding:5px; background-color: #004020">
    <a href="#!" onclick="openCam('RCCrewe1', 'Crewe1')" style="color: #ccc;">Crewe1</a>
  </div>
  <div><div style="float: left">Supporter</div></div>
</div>
<div class="col-sm-2" style="padding:10px;">
  <div style="background-color:#333322; font-size:10px;">
    <span style="color: #ffffff; ">Heritage<br>Romney, Hythe &amp; Dymchurch</span>
  </div>
  <div style="border: 0px solid #666;padding:5px; background-color: #004020">
    <a href="#!" onclick="openCam('RHDRHythe', 'Hythe')" style="color: #ccc;">Hythe</a>
  </div>
</div>
<script>function openCam(camName, camTitle) {}</script>
''';

const _map = '''
var Lblurb = '<div class="popupContainer"><img src="images/camera_thumbs/RCCrewe1.png"><br>Crewe 1 - Chester Lines</div>';
var Lblurb = '<div class="popupContainer"><img src="images/camera_thumbs/RCMaryport.png"><br>Maryport</div>';
''';

const _crewe = '''
<title>Crewe 1 - Chester Lines</title>
<style>td.offLine { background-image:url('https://railcam.uk/images/offLine.jpg'); }</style>
<iframe name="fp" id="fp" src="https://maybach.railcam.co.uk/Crewe1_69241/embed.html?realtime=true" allowfullscreen></iframe>
''';

/// The site, as far as the service asks of it: members' pages redirect and
/// cameras say "No Access" until the form has been posted the right password.
class _Site implements HttpClientAdapter {
  final List<String> asked = [];
  var signIns = 0;

  /// As PHP does: a request without a session is handed a new one, and it
  /// is the session the form was posted from that is signed in.
  var _sessions = 0;
  final Set<String> _signedIn = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    asked.add('${options.method} $path');
    final had = RegExp(
      r'PHPSESSID=(\w+)',
    ).firstMatch('${options.headers['Cookie'] ?? ''}')?[1];
    final session = had ?? 's${++_sessions}';
    // The later a session was handed out, the later its answer arrives —
    // after the sign-in, for the last of several asked for at once.
    if (had == null) {
      await Future<void>.delayed(Duration(milliseconds: 5 * _sessions));
    }
    final signedIn = _signedIn.contains(session);
    ResponseBody page(String html, {int status = 200}) =>
        ResponseBody.fromBytes(
          utf8.encode(html),
          status,
          headers: {
            if (had == null) 'set-cookie': ['PHPSESSID=$session; path=/'],
            if (status == 302)
              'location': ['https://railcam.uk/RCnoaccess.php'],
          },
        );
    if (path == '/camsMap.php') return page(_map);
    if (path == '/account/login.php') {
      signIns++;
      final body = utf8.decode(await requestStream!.expand((b) => b).toList());
      if (!body.contains('password=right')) {
        return page('<form name="siteloklogin">Please check…</form>');
      }
      _signedIn.add(session);
      return page('', status: 302);
    }
    if (path == '/cameras/dashboard.php') {
      return signedIn ? page(_dashboard) : page('', status: 302);
    }
    if (path == '/site/watch/anycam.php') {
      return page(
        signedIn ? _crewe : 'No Access : from URL <title>Crewe</title>',
      );
    }
    return page('', status: 404);
  }

  @override
  void close({bool force = false}) {}
}

RailcamService _service(_Site site) => RailcamService(
  dio: Dio(
    BaseOptions(
      baseUrl: 'https://railcam.uk',
      followRedirects: false,
      validateStatus: (s) => s != null && s < 400,
      responseType: ResponseType.bytes,
    ),
  )..httpClientAdapter = site,
);

Future<VideoStream> _noYouTube(VideoLink link) =>
    throw StateError('not a YouTube camera');

void main() {
  test('the Dashboard page: each camera with its area and place', () {
    final cams = RailcamService.parseDashboard(_dashboard);
    expect(cams.map((c) => c.id), ['RCCrewe1', 'RHDRHythe']);
    expect(cams.first.area, 'Main Line C to D');
    expect(cams.first.place, 'Crewe');
    // Already starts with its place, so the place is not said twice.
    expect(cams.first.label, 'Crewe1');
    expect(cams.last.label, 'Romney, Hythe & Dymchurch: Hythe');
  });

  test('the public map: each marker’s camera and its name', () {
    final cams = RailcamService.parseMap(_map);
    expect(cams.map((c) => c.id), ['RCCrewe1', 'RCMaryport']);
    expect(cams.first.name, 'Crewe 1 - Chester Lines');
  });

  test('a camera’s page: its stream, wherever it is carried', () {
    final crewe = RailcamService.parsePlayer(_crewe);
    expect(crewe.title, 'Crewe 1 - Chester Lines');
    expect(crewe.hls, 'https://maybach.railcam.co.uk/Crewe1_69241/index.m3u8');
    // The page's style sheet talks of off-line cameras; this one is not.
    expect(crewe.offline, isFalse);
    expect(crewe.noAccess, isFalse);

    final onYouTube = RailcamService.parsePlayer(
      '<iframe src="https://www.youtube.com/embed/4XYbh4Pegzw?autoplay=1">',
    );
    expect(onYouTube.youtube, '4XYbh4Pegzw');
    expect(onYouTube.hls, isNull);

    final elsewhere = RailcamService.parsePlayer(
      "hls.loadSource('https://stream1.example.no/bt/Finse.stream/playlist.m3u8');",
    );
    expect(
      elsewhere.hls,
      'https://stream1.example.no/bt/Finse.stream/playlist.m3u8',
    );

    final off = RailcamService.parsePlayer(
      "<td class = 'offLineKnown' width=\"600\"><h3>OFF-LINE</h3></td>",
    );
    expect(off.offline, isTrue);
    expect(off.hls, isNull);

    expect(
      RailcamService.parsePlayer(
        'No Access : from URL <title>x</title>',
      ).noAccess,
      isTrue,
    );
  });

  test('a stream with several versions: the best the screen can show', () {
    final at = Uri.parse('https://cdn.example/live/cam/index.m3u8');
    String inf(int w, int h, int rate, String uri) =>
        '#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=1,BANDWIDTH=$rate,'
        'RESOLUTION=${w}x$h,FRAME-RATE=25.000\r\n$uri\r\n';
    final three =
        '#EXTM3U\r\n${inf(1280, 720, 2000000, 'hd/mono.m3u8')}'
        '${inf(3840, 2160, 9000000, 'uhd/mono.m3u8')}'
        '${inf(1920, 1080, 4000000, '/abs/fhd.m3u8?t=1')}';
    expect(
      RailcamService.pickVersion(three, at, 1080),
      'https://cdn.example/abs/fhd.m3u8?t=1',
    );
    expect(
      RailcamService.pickVersion(three, at, 720),
      'https://cdn.example/live/cam/hd/mono.m3u8',
    );
    // All too tall: the least of them.
    expect(
      RailcamService.pickVersion(three, at, 480),
      'https://cdn.example/live/cam/hd/mono.m3u8',
    );
    // A version that is not on the web is not one mpv is handed.
    expect(
      RailcamService.pickVersion(
        '#EXTM3U\n${inf(1280, 720, 2000000, 'file:///etc/passwd')}'
        '${inf(3840, 2160, 9000000, 'uhd/mono.m3u8')}',
        at,
        1080,
      ),
      isNull,
    );
    // One version, as railcam's own cameras have: nothing to choose.
    expect(
      RailcamService.pickVersion(
        '#EXTM3U\n${inf(1920, 1080, 2580000, 'tracks-v1a1/mono.m3u8')}',
        at,
        1080,
      ),
      isNull,
    );
    // Sound listed apart from the picture: left whole, for mpv.
    expect(
      RailcamService.pickVersion(
        '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",URI="a.m3u8"\n$three',
        at,
        1080,
      ),
      isNull,
    );
  });

  test('live in the tile: more as video when it has the page to itself', () {
    const still = RailcamLive.still;
    const frames = RailcamLive.frames;
    const video = RailcamLive.video;
    expect(railcamLive('off', 3, alone: true), [still, still, still]);
    expect(railcamLive('frames', 2, alone: false), [frames, frames]);
    expect(railcamLive('video', 6, alone: true), List.filled(6, video));
    expect(railcamLive('video', 14, alone: true), [
      ...List.filled(6, video),
      ...List.filled(6, frames),
      still,
      still,
    ]);
    // Sharing its page: two as video, and eight streams in all.
    expect(railcamLive('video', 9, alone: false), [
      video,
      video,
      ...List.filled(6, frames),
      still,
    ]);
    expect(railcamLive('frames', 13, alone: true).last, still);
    // A setting from some other version: pictures, not streams.
    expect(railcamLive('', 1, alone: true), [still]);
  });

  test('six tiles asking at once: one sign-in, and none turned away', () async {
    final site = _Site();
    final railcam = _service(site)..useAccount('me', 'right');
    addTearDown(railcam.dispose);
    final streams = await Future.wait([
      for (var i = 0; i < 6; i++)
        railcam.find(
          const RailcamLink('RCCrewe1'),
          maxHeight: 360,
          youtube: _noYouTube,
        ),
    ]);
    expect(streams, hasLength(6));
    expect(site.signIns, 1);
  });

  test('signed out, only the map’s cameras; signed in, all of them', () async {
    final site = _Site();
    final railcam = _service(site);
    addTearDown(railcam.dispose);

    await railcam.ensure();
    expect(railcam.cams!.map((c) => c.id), ['RCCrewe1', 'RCMaryport']);
    expect(site.signIns, 0);

    railcam.useAccount('me', 'right');
    final choices = await railcam.choices();
    expect(site.signIns, 1);
    // The Dashboard's cameras, with the map's fuller name where it has one.
    expect(choices, {
      'RCCrewe1': 'Crewe 1 - Chester Lines',
      'RHDRHythe': 'Romney, Hythe & Dymchurch: Hythe',
    });
    expect(railcam.error, isNull);
  });

  test('a camera opened: signed in once, then its stream', () async {
    final site = _Site();
    final railcam = _service(site)..useAccount('me', 'right');
    addTearDown(railcam.dispose);

    const link = RailcamLink('RCCrewe1');
    final stream = await railcam.find(
      link,
      maxHeight: 1080,
      youtube: _noYouTube,
    );
    expect(stream.uri, 'https://maybach.railcam.co.uk/Crewe1_69241/index.m3u8');
    expect(stream.isLive, isTrue);
    expect(stream.title, 'Crewe 1 - Chester Lines');
    expect(site.signIns, 1);

    // The session is kept: no second sign-in for the next camera.
    await railcam.find(link, maxHeight: 1080, youtube: _noYouTube);
    expect(site.signIns, 1);
  });

  test('a wrong password is tried once, and said plainly', () async {
    final site = _Site();
    final railcam = _service(site)..useAccount('me', 'wrong');
    addTearDown(railcam.dispose);

    for (var i = 0; i < 2; i++) {
      await expectLater(
        railcam.find(
          const RailcamLink('RCCrewe1'),
          maxHeight: 1080,
          youtube: _noYouTube,
        ),
        throwsA(
          isA<VideoException>().having(
            (e) => e.message,
            'message',
            contains('did not accept'),
          ),
        ),
      );
    }
    expect(site.signIns, 1);

    await railcam.ensure();
    expect(railcam.error, contains('did not accept'));
    // The map's cameras are still there to pick from.
    expect(railcam.cams, hasLength(2));

    // A new password is a new attempt.
    railcam.useAccount('me', 'right');
    await railcam.ensure();
    expect(site.signIns, 2);
    expect(railcam.error, isNull);
  });

  test('no account: asked for one rather than refused', () async {
    final railcam = _service(_Site());
    addTearDown(railcam.dispose);
    await expectLater(
      railcam.find(
        const RailcamLink('RCCrewe1'),
        maxHeight: 1080,
        youtube: _noYouTube,
      ),
      throwsA(
        isA<VideoException>().having(
          (e) => e.message,
          'message',
          contains('username and password'),
        ),
      ),
    );
  });

  testWidgets('the tile fits every shape, and names its cameras', (
    tester,
  ) async {
    registerBuiltInWidgets();
    tester.view.physicalSize = const Size(1920, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final railcam = _service(_Site());
    addTearDown(railcam.dispose);
    railcam.debugSet(const [
      RailCam(id: 'RCCrewe1', name: 'Crewe 1 - Chester Lines', place: 'Crewe'),
      RailCam(id: 'RHDRHythe', name: 'Hythe', place: 'RH&DR'),
    ]);
    final t = WidgetRegistry.find('railcam')!;

    Future<void> draw(Size size, Map<String, dynamic> options) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<RailcamService>.value(
          value: railcam,
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox.fromSize(
                  size: size,
                  child: Builder(
                    builder: (context) => t.build(
                      context,
                      DashboardWidgetContext(
                        theme: kBuiltInThemes.first,
                        config: DashboardWidgetConfig(
                          id: 'x',
                          type: 'railcam',
                          x: 0,
                          y: 0,
                          width: 4,
                          height: 3,
                          options: options,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    const picked = {
      'cameras': [
        {'camera': 'RCCrewe1'},
        {'camera': 'RHDRHythe', 'name': 'The little railway'},
        {'camera': ''},
      ],
    };
    for (final (w, h) in shapes) {
      if (w < t.minWidth || h < t.minHeight) continue;
      await draw(tile(w, h), picked);
      expect(tester.takeException(), isNull, reason: 'railcam ${w}x$h');
    }
    await draw(tile(4, 3), picked);
    expect(find.text('Crewe 1 - Chester Lines'), findsOneWidget);
    expect(find.text('The little railway'), findsOneWidget);

    await draw(tile(4, 3), const {});
    expect(find.textContaining('Pick cameras'), findsOneWidget);
    // Nothing ticking left behind.
    await tester.pumpWidget(const SizedBox());
  });
}
