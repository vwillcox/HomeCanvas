import 'dart:async';

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

/// The volume as a slider: the level follows the finger, and is kept once
/// it lifts. On a console it is a transporter's touch slider — upright
/// ([Axis.vertical]) beside the track where there is room for one, lying in
/// the transport's strip where there is not.
class RadioVolume extends StatelessWidget {
  const RadioVolume({
    super.key,
    required this.theme,
    required this.radio,
    this.axis = Axis.horizontal,
    this.size = 56,
    this.showLevel = false,
  });

  final DashboardTheme theme;
  final RadioService radio;

  /// Upright fills the box it is given; lying down it is [size] tall and
  /// three and a bit times as long.
  final Axis axis;
  final double size;

  /// The level as a figure after it, lying down. Upright it always has one.
  final bool showLevel;

  /// While the finger moves, only as the level changes by a whole step:
  /// each step is a rebuild of the tile.
  void _slide(double v) {
    final level = (v * 100).roundToDouble();
    if (level != radio.volume) unawaited(radio.setVolume(level, keep: false));
  }

  void _lift(double v) => unawaited(radio.setVolume((v * 100).roundToDouble()));

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final level = radio.volume.round();
    final name = tr('widget.radio.volume', 'Volume');
    if (t.isLcars && axis == Axis.vertical) {
      return LcarsTransporter(
        theme: t,
        value: radio.volume / 100,
        onChanged: _slide,
        onChangeEnd: _lift,
        colour: t.block(2),
        label: name,
        readout: '$level',
      );
    }
    final figure = Padding(
      padding: EdgeInsets.only(left: size * 0.12),
      child: Text(
        '$level',
        style: TextStyle(
          color: t.textSecondary,
          fontSize: size * 0.3,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
    final Widget slider;
    if (t.isLcars) {
      slider = SizedBox(
        width: size * 3.2,
        height: size * 0.72,
        child: LcarsTransporter(
          theme: t,
          value: radio.volume / 100,
          onChanged: _slide,
          onChangeEnd: _lift,
          colour: t.block(2),
          axis: Axis.horizontal,
          label: name,
        ),
      );
    } else {
      slider = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            level == 0
                ? Icons.volume_mute_rounded
                : level < 50
                ? Icons.volume_down_rounded
                : Icons.volume_up_rounded,
            color: t.textSecondary,
            size: size * 0.42,
          ),
          SizedBox(
            width: size * 2.8,
            height: size,
            child: Material(
              type: MaterialType.transparency,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: (size * 0.12).clamp(4.0, 10.0),
                  activeTrackColor: t.accent,
                  inactiveTrackColor: t.wash(0.24),
                  thumbColor: t.accent,
                  overlayColor: t.accent.withValues(alpha: 0.16),
                  thumbShape: RoundSliderThumbShape(
                    enabledThumbRadius: (size * 0.2).clamp(8.0, 18.0),
                  ),
                  overlayShape: RoundSliderOverlayShape(
                    overlayRadius: (size * 0.4).clamp(16.0, 32.0),
                  ),
                ),
                child: Slider(
                  value: radio.volume / 100,
                  onChanged: _slide,
                  onChangeEnd: _lift,
                  semanticFormatterCallback: (v) =>
                      '$name ${(v * 100).round()}',
                ),
              ),
            ),
          ),
        ],
      );
    }
    final lying = Row(
      mainAxisSize: MainAxisSize.min,
      children: [slider, if (showLevel) figure],
    );
    // Upright off a console: the same slider, turned.
    return axis == Axis.vertical
        ? RotatedBox(quarterTurns: 3, child: lying)
        : lying;
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
    this.volume = true,
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

  /// The volume as a figure after its slider.
  final bool showLevel;

  /// The volume's slider, before the sleep key; false where the tile has
  /// it somewhere else.
  final bool volume;

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
        sleepAt == null ? Icons.bedtime_outlined : Icons.bedtime,
        // Nothing to stop while nothing is on.
        live ? radio.cycleSleep : null,
        0.85,
        _Key.sleep,
      ),
    ];
    final sleep = keys.length - 1;
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
    final slider = volume
        ? RadioVolume(theme: t, radio: radio, size: size, showLevel: showLevel)
        : null;

    if (t.isLcars) {
      // One strip of blocks, rounded at its two ends, play lit while on and
      // sleep lit while set, with its time on it.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, k) in keys.indexed) ...[
            if (slider != null && i == sleep)
              Padding(
                padding: const EdgeInsets.only(left: lcarsLine),
                child: slider,
              ),
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
          if (slider != null && i == sleep) ...[
            slider,
            SizedBox(width: size * 0.1),
          ],
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
