import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// What the kiosk can be asked to do by the other apps on the panel.
enum KioskCommand { photos, dashboard, settings, lockedFolder, camera }

/// What the kiosk tells the other apps, so they can draw the same control
/// bar it does — only the buttons that would work.
@immutable
class KioskState {
  const KioskState({
    required this.dashboard,
    required this.lockedFolder,
    required this.camera,
    required this.cameraOpen,
    required this.dnd,
  });

  final bool dashboard;
  final bool lockedFolder;
  final bool camera;
  final bool cameraOpen;
  final bool dnd;

  Map<String, dynamic> toJson() => {
        'dashboard': dashboard,
        'lockedFolder': lockedFolder,
        'camera': camera,
        'cameraOpen': cameraOpen,
        'dnd': dnd,
      };
}

/// A small control surface for the TV remote app, on the panel itself.
///
/// The remote is a separate program, so its copy of the kiosk's control bar
/// cannot reach into the kiosk to open the dashboard or Settings. It asks
/// here instead, then brings the kiosk's window to the front.
///
/// Bound to the loopback address only. Nothing on the network can reach it:
/// the only callers are programs already running on the Pi as the same user,
/// which could do anything this does and more. It only ever opens screens
/// the kiosk's own buttons open, and the Locked Folder still asks for its PIN.
///
///     GET  /state               what the bar should show
///     POST /open/<place>        photos, dashboard, settings, locked-folder
///     POST /camera              show or hide the camera
///     POST /dnd?muted=true      the notifications switch
class KioskControlService {
  KioskControlService({
    required this.state,
    required this.run,
    required this.setDnd,
    this.port = defaultPort,
  });

  /// One up from screen_control.py's 8765, which is the other local service.
  static const int defaultPort = 8766;

  final int port;
  final KioskState Function() state;
  final void Function(KioskCommand) run;
  final void Function(bool muted) setDnd;

  HttpServer? _server;

  Future<void> start() async {
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    } catch (e) {
      // Another copy running, most likely. The kiosk works without this;
      // only the remote's shortcuts into it stop working.
      debugPrint('KioskControlService: could not listen on $port: $e');
      return;
    }
    _server!.listen(handle);
  }

  Future<void> stop() async => _server?.close(force: true);

  /// The port actually listened on — differs from [port] only when that was
  /// 0, which tests use to be given a free one.
  int? get boundPort => _server?.port;

  /// Where each place is asked for.
  static const Map<String, KioskCommand> places = {
    'photos': KioskCommand.photos,
    'dashboard': KioskCommand.dashboard,
    'settings': KioskCommand.settings,
    'locked-folder': KioskCommand.lockedFolder,
  };

  @visibleForTesting
  Future<void> handle(HttpRequest request) async {
    final res = request.response;
    Future<void> reply(int code, Object body) async {
      res.statusCode = code;
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode(body));
      await res.close();
    }

    // Belt and braces: the socket is loopback-only already.
    if (!request.connectionInfo!.remoteAddress.isLoopback) {
      return reply(HttpStatus.forbidden, {'error': 'local only'});
    }

    final path = request.uri.path;
    try {
      if (request.method == 'GET' && path == '/state') {
        return reply(HttpStatus.ok, state().toJson());
      }
      if (request.method != 'POST') {
        return reply(HttpStatus.methodNotAllowed, {'error': 'use POST'});
      }
      if (path.startsWith('/open/')) {
        final place = places[path.substring('/open/'.length)];
        if (place == null) {
          return reply(HttpStatus.notFound, {'error': 'no such place'});
        }
        run(place);
        return reply(HttpStatus.ok, state().toJson());
      }
      if (path == '/camera') {
        run(KioskCommand.camera);
        return reply(HttpStatus.ok, state().toJson());
      }
      if (path == '/dnd') {
        final muted = request.uri.queryParameters['muted'];
        if (muted != 'true' && muted != 'false') {
          return reply(HttpStatus.badRequest, {'error': 'muted=true|false'});
        }
        setDnd(muted == 'true');
        return reply(HttpStatus.ok, state().toJson());
      }
      return reply(HttpStatus.notFound, {'error': 'not found'});
    } catch (e) {
      return reply(HttpStatus.internalServerError, {'error': '$e'});
    }
  }
}
