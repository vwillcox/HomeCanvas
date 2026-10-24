import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../services/radio_service.dart';
import '../../time_format.dart';
import '../../widgets/audio_visualiser.dart';
import '../../widgets/lcars.dart';
import '../dashboard_theme.dart';
import 'tile_bits.dart';

// Pieces the Radio and StreamingSoundtracks tiles share, so the two look
// and work alike.

/// A station's badge: its letters on a square of its own colour, picked
/// from the theme's palette by its place in the list, so neighbours differ.
class RadioBadge extends StatelessWidget {
  const RadioBadge({
    super.key,
    required this.letters,
    required this.seed,
    required this.theme,
    required this.size,
  });

  final String letters;
  final int seed;
  final DashboardTheme theme;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final text = Text(
      letters,
      maxLines: 1,
      style: TextStyle(
        color: t.isLcars ? lcarsInk : Colors.white,
        fontSize: size * (letters.length > 3 ? 0.26 : 0.36),
        fontWeight: FontWeight.w800,
        fontFamily: t.fontFamily,
      ),
    );
    if (t.isLcars) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        color: t.block(seed),
        child: text,
      );
    }
    final palette = t.palette.length >= 2 ? t.palette : kVisualiserPalette;
    final colour = palette[seed % palette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tileCorner(t, size * 0.18)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colour, Color.lerp(colour, Colors.black, 0.45)!],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.08),
        child: FittedBox(fit: BoxFit.scaleDown, child: text),
      ),
    );
  }
}

/// Which of the transport's keys a key is: play is the big one, and sleep
/// says when it will stop.
enum _Key { plain, play, sleep }

class RadioTransport extends StatelessWidget {
  const RadioTransport({
    super.key,
    required this.theme,
    required this.radio,
    required this.size,
    required this.playing,
    required this.loading,
    required this.live,
    required this.onToggle,
    this.onStep,
    this.showLevel = false,
  });

  final DashboardTheme theme;
  final RadioService radio;
  final double size;

  /// Whether what this transport plays is on, starting, or either.
  final bool playing;
  final bool loading;
  final bool live;
  final VoidCallback onToggle;

  /// Back or on through the stations by one; no keys for it when null.
  final void Function(int by)? onStep;

  /// The volume as a figure between its two buttons.
  final bool showLevel;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final sleepAt = radio.sleepAt;
    final step = onStep;
    // The sleep timer is one of the keys, drawn as they are: a tap steps it
    // through off, 15, 30, 60 and 90 minutes. Once set, it says when the
    // radio will stop — a time rather than a countdown, so it need not be
    // drawn again every minute.
    final keys = <(IconData, VoidCallback?, double, _Key)>[
      if (step != null) (Icons.skip_previous, () => step(-1), 1.0, _Key.plain),
      (
        playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
        onToggle,
        1.3,
        _Key.play,
      ),
      if (step != null) (Icons.skip_next, () => step(1), 1.0, _Key.plain),
      (
        Icons.volume_down_rounded,
        () => radio.setVolume(radio.volume - 10),
        0.85,
        _Key.plain,
      ),
      (
        Icons.volume_up_rounded,
        () => radio.setVolume(radio.volume + 10),
        0.85,
        _Key.plain,
      ),
      (
        sleepAt == null ? Icons.bedtime_outlined : Icons.bedtime,
        // Nothing to stop while nothing is on.
        live ? radio.cycleSleep : null,
        0.85,
        _Key.sleep,
      ),
    ];
    final volumeUp = keys.length - 2;
    final sleepLabel = sleepAt == null
        ? tr('widget.radio.sleepTimer', 'Sleep timer')
        : tr('widget.radio.offAt', 'Off at {time}', {'time': hhmm(sleepAt)});
    Text figure(String text, Color colour) => Text(
      text,
      style: TextStyle(
        color: colour,
        fontSize: size * 0.3,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    final level = Padding(
      padding: EdgeInsets.symmetric(horizontal: size * 0.1),
      child: figure('${radio.volume.round()}', t.textSecondary),
    );

    if (t.isLcars) {
      // One strip of blocks, rounded at its two ends, play lit while on and
      // sleep lit while set, with its time on it.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, k) in keys.indexed) ...[
            if (showLevel && i == volumeUp) level,
            Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : lcarsLine),
              child: Semantics(
                button: true,
                label: k.$4 == _Key.sleep ? sleepLabel : null,
                child: LcarsBlock(
                  colour: switch (k.$4) {
                    _Key.play => playing ? lcarsLit : t.accent,
                    _Key.sleep => sleepAt != null ? lcarsLit : t.block(i + 1),
                    _Key.plain => t.block(i + 1),
                  },
                  onTap: k.$2,
                  width:
                      size *
                      k.$3 *
                      (k.$4 == _Key.sleep && sleepAt != null ? 1.9 : 1),
                  height: size * 0.72,
                  ends: i == 0
                      ? LcarsEnds.start
                      : i == keys.length - 1
                      ? LcarsEnds.end
                      : LcarsEnds.none,
                  child: k.$4 == _Key.sleep && sleepAt != null
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(k.$1, size: size * 0.36),
                            SizedBox(width: size * 0.06),
                            figure(hhmm(sleepAt), lcarsInk),
                          ],
                        )
                      : Icon(k.$1, size: size * 0.44),
                ),
              ),
            ),
          ],
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, k) in keys.indexed) ...[
          if (showLevel && i == volumeUp) level,
          if (k.$4 == _Key.play && loading)
            SizedBox(
              width: size * k.$3,
              height: size * k.$3,
              child: Padding(
                padding: EdgeInsets.all(size * 0.3),
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: t.accent,
                ),
              ),
            )
          else
            Semantics(
              label: k.$4 == _Key.sleep ? sleepLabel : null,
              child: _Round(
                icon: k.$1,
                colour: switch (k.$4) {
                  _Key.play => t.accent,
                  _Key.sleep when sleepAt != null => t.accent,
                  _Key.sleep when k.$2 == null => t.textSecondary.withValues(
                    alpha: 0.4,
                  ),
                  _ => t.textPrimary,
                },
                target: size * k.$3,
                onPressed: k.$2,
              ),
            ),
          if (k.$4 == _Key.sleep && sleepAt != null)
            Padding(
              padding: EdgeInsets.only(right: size * 0.1),
              child: figure(hhmm(sleepAt), t.accent),
            ),
        ],
      ],
    );
  }
}

/// A round control sized for a finger, as the Now playing tile's are.
class _Round extends StatelessWidget {
  const _Round({
    required this.icon,
    required this.colour,
    required this.onPressed,
    required this.target,
  });

  final IconData icon;
  final Color colour;

  /// Null for a key with nothing to do now.
  final VoidCallback? onPressed;
  final double target;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: target,
          height: target,
          child: Icon(icon, color: colour, size: target * 0.62),
        ),
      ),
    );
  }
}
