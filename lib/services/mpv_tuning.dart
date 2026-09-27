import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// mpv settings that make video play smoothly on the panel.
///
/// Every player here draws through media_kit's software output — its OpenGL
/// one shows a solid blue picture on this Pi — so each frame is converted
/// from YUV to RGB on the CPU before Flutter uploads it. How that is done
/// decides whether 1080p60 keeps up. Measured on the panel with the same
/// 60fps video, frames dropped per minute:
///
///   mpv's default (zimg)                       ~380
///   zimg, four threads, fast                   ~225
///   libswscale, fast                             23  (and 70% less CPU)
///
/// libswscale has hand-written ARM code for exactly this conversion; zimg is
/// the more accurate of the two, which on a wall panel across a room is not
/// the part anyone notices. No scaling happens at full screen — the video's
/// own size is drawn — so the scaler named here matters only for tiles.
///
/// Also where media_kit's own choices are overridden, when they do not suit
/// streaming on the panel — see the buffer sizes.
class MpvTuning {
  MpvTuning._();

  static const Map<String, String> options = {
    'sws-allow-zimg': 'no',
    'sws-fast': 'yes',
    'sws-scaler': 'fast-bilinear',
    // mpv's own buffer sizes, in place of the 32 MB media_kit sets both to.
    // A 1080p60 stream fills 32 MB in under a minute, and with it that full
    // the first seek outside it froze the picture for ten seconds while the
    // sound went on; with mpv's sizes it takes two. Measured on the panel
    // with a 6.6 Mbit/s Nebula video. The Pi has memory to spare.
    'demuxer-max-bytes': '150MiB',
    'demuxer-max-back-bytes': '50MiB',
  };

  /// Dev aid, like `HOMECANVAS_TEST_*`: `HOMECANVAS_MPV=name=value,…` adds
  /// or overrides options, for measuring one on the panel before building it
  /// in. `ao=null` silences a test run.
  static Map<String, String> get _dev {
    final raw = Platform.environment['HOMECANVAS_MPV'] ?? '';
    return {
      for (final pair in raw.split(','))
        if (pair.contains('='))
          pair.substring(0, pair.indexOf('=')).trim():
              pair.substring(pair.indexOf('=') + 1).trim(),
    };
  }

  /// Applies [options] to [player]. Call before it opens anything.
  static Future<void> apply(Player player) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    for (final e in {...options, ..._dev}.entries) {
      try {
        await platform.setProperty(e.key, e.value);
      } catch (err) {
        debugPrint('mpv would not take ${e.key}=${e.value}: $err');
      }
    }
  }
}
