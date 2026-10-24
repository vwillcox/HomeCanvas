import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../l10n/l10n.dart';
import '../../services/radio_service.dart';
import '../../services/radio_stations.dart';
import '../../time_format.dart';
import '../../widgets/audio_visualiser.dart';
import '../../widgets/lcars.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'scrolling_text.dart';
import 'tile_bits.dart';

/// Internet radio: the stations picked in the settings, a tap on one to tune
/// in, and the transport to stop it or step through them.
///
/// Four looks. Compact fits any tile; the other three are for a tile with
/// room — a page to itself, say — and give way to Compact on one too small
/// for them:
///
/// - Studio: the song's cover (or the station's badge) large, the song and
///   artist, what played before it, and the music drawn as it plays.
/// - Tuning dial: an old set's dial, the stations along it and a needle
///   that glides to the one tuned in.
/// - Station grid: every station as a card to tap, the one on air pulsing.
class RadioWidget extends StatelessWidget {
  const RadioWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  Widget build(BuildContext context) {
    final t = w.theme;
    final radio = context.watch<RadioService>();
    final stations = radioStationsFrom(w.config.options['stations']);
    if (stations.isEmpty) {
      return TileMessage(
        tr(
          'widget.radio.addStations',
          'Pick some stations in the widget settings',
        ),
        theme: t,
      );
    }
    final r = _Radio(
      theme: t,
      radio: radio,
      stations: stations,
      volume: w.option<double>('volume', 35),
    );
    final look = w.option('look', 'auto');
    final showList = w.option('list', true);
    final visualiser = w.option('visualiser', true);

    return LayoutBuilder(
      builder: (context, c) {
        final big = c.maxWidth >= 560 && c.maxHeight >= 360;
        final roomy = c.maxWidth >= 380 && c.maxHeight >= 260;
        final chosen = look == 'auto' ? (big ? 'studio' : 'compact') : look;
        switch (chosen) {
          case 'studio' when roomy:
            return _StudioLook(r: r, size: c.biggest, visualiser: visualiser);
          case 'dial' when roomy:
            return _DialLook(r: r, size: c.biggest);
          case 'grid' when roomy:
            return _GridLook(r: r, size: c.biggest);
        }
        return _CompactLook(r: r, size: c.biggest, showList: showList);
      },
    );
  }
}

/// What every look is drawn from: the service, the tile's stations, and
/// which of them is on.
class _Radio {
  _Radio({
    required this.theme,
    required this.radio,
    required this.stations,
    required this.volume,
  }) {
    final on = radio.station;
    index = on == null ? -1 : stations.indexWhere((s) => s.url == on.url);
  }

  final DashboardTheme theme;
  final RadioService radio;
  final List<RadioStation> stations;

  /// The level a station starts at, from the settings.
  final double volume;

  /// Which of [stations] is on, or was last; -1 for none of this tile's.
  late final int index;

  bool get ours => index >= 0;

  /// The station on now if it is this tile's; otherwise the first, ready
  /// for play.
  RadioStation get current => ours ? stations[index] : stations.first;
  bool get playing => ours && radio.playing;
  bool get loading => ours && radio.loading;
  bool get live => playing || loading;
  String? get error => ours ? radio.error : null;
  String? get title => playing ? radio.title : null;
  String? get art => playing ? radio.artUrl : null;
  bool get many => stations.length > 1;

  void toggle() => radio.toggle(current, volume: volume);
  void tune(RadioStation s) => radio.toggle(s, volume: volume);
  void step(int by) {
    final next = radio.stepFrom(stations, by);
    if (next != null) radio.play(next, volume: volume);
  }

  void quieter() => radio.setVolume(radio.volume - 10);
  void louder() => radio.setVolume(radio.volume + 10);

  /// The line under the station's name: what is playing, or what is
  /// happening instead.
  String get detail =>
      error ??
      (loading
          ? tr('widget.radio.tuning', 'Tuning in…')
          : playing
          ? (radio.title ?? current.country)
          : tr('widget.radio.tapToListen', 'Tap play to listen'));

  Color get detailColour =>
      error != null ? StatusColours.of(theme).bad : theme.textSecondary;
}

// --- Compact ------------------------------------------------------------------

class _CompactLook extends StatelessWidget {
  const _CompactLook({
    required this.r,
    required this.size,
    required this.showList,
  });

  final _Radio r;
  final Size size;
  final bool showList;

  @override
  Widget build(BuildContext context) {
    final t = r.theme;
    final h = size.height;
    final control = (h * 0.24).clamp(40.0, 88.0);
    // The list of stations only where there is room for it under the
    // transport, and more than one to choose between.
    final roomForList = showList && r.many && h >= 190;
    final top = SizedBox(
      width: size.width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TileLabel(
            icon: Icons.radio,
            text: tr('widget.radio.radio', 'Radio'),
            theme: t,
            trailing: _Trailing(r: r),
          ),
          const SizedBox(height: 8),
          Text(
            tileCased(t, r.current.name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: (h * 0.13).clamp(16.0, 34.0),
              fontWeight: FontWeight.w600,
              height: 1.15,
            ),
          ),
          SizedBox(
            height: 22,
            child: ScrollingText(
              r.detail,
              style: TextStyle(color: r.detailColour, fontSize: 14),
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: _Transport(r: r, size: control),
          ),
        ],
      ),
    );
    // Without the list, a short tile shrinks the lot rather than cutting
    // the buttons off.
    if (!roomForList) {
      return Align(
        alignment: Alignment.topLeft,
        child: FittedBox(fit: BoxFit.scaleDown, child: top),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        top,
        const SizedBox(height: 10),
        Expanded(
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (i, s) in r.stations.indexed)
                  _StationChip(
                    r: r,
                    station: s,
                    on: r.live && i == r.index,
                    seed: i,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// --- Studio -------------------------------------------------------------------

class _StudioLook extends StatelessWidget {
  const _StudioLook({
    required this.r,
    required this.size,
    required this.visualiser,
  });

  final _Radio r;
  final Size size;
  final bool visualiser;

  @override
  Widget build(BuildContext context) {
    final t = r.theme;
    final h = size.height;
    final w = size.width;
    final title = r.title;
    final parts = title == null ? null : splitRadioTitle(title);
    // What played before the song on now, on a tile wide enough to keep it
    // beside the cover rather than squeezing the song's name.
    final history = r.radio.history
        .where((s) => s.title != title)
        .take(8)
        .toList();
    // A console keeps its panel there before anything has played, rather
    // than leaving a hole in the page.
    final showHistory = w >= 1000 && (history.isNotEmpty || t.isLcars);
    final strip = r.many && h >= 480;
    final bars = visualiser && h >= 420;
    final art = (h * (strip ? 0.5 : 0.62)).clamp(120.0, w * 0.4);
    final song = (h * 0.075).clamp(22.0, 64.0);

    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            if (r.live)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: StatusChip(
                  text: tr('widget.radio.onAir', 'On air'),
                  colour: StatusColours.of(t).bad,
                  size: 14,
                ),
              ),
            Flexible(
              child: Text(
                tileCased(t, r.current.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.accent,
                  fontSize: song * 0.48,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: song * 0.3),
        Text(
          parts?.song ?? r.detail,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: parts == null && r.error != null
                ? StatusColours.of(t).bad
                : t.textPrimary,
            fontSize: song,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
        if (parts?.artist case final artist?) ...[
          SizedBox(height: song * 0.2),
          Text(
            artist,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: song * 0.55,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        SizedBox(height: song * 0.6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: _Transport(
            r: r,
            size: (h * 0.11).clamp(48.0, 96.0),
            showLevel: true,
          ),
        ),
      ],
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // The cover, faintly, behind it all: under a wash of the theme's
        // own background rather than made see-through, which the panel's
        // tile pictures did not honour. Not blurred: a blur this size is
        // far more work for the panel than it is worth.
        if (r.art != null && !t.isLcars)
          RepaintBoundary(
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: r.art!,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
                ColoredBox(
                  color: t.background.first.withValues(
                    alpha: t.isLight ? 0.9 : 0.84,
                  ),
                ),
              ],
            ),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: art,
                    child: _Cover(r: r, size: art),
                  ),
                  SizedBox(width: w * 0.035),
                  Expanded(child: words),
                  if (showHistory) ...[
                    SizedBox(width: w * 0.03),
                    SizedBox(
                      width: (w * (t.isLcars ? 0.3 : 0.26)).clamp(260.0, 560.0),
                      child: _History(r: r, songs: history),
                    ),
                  ],
                ],
              ),
            ),
            if (bars) ...[
              const SizedBox(height: 12),
              RepaintBoundary(
                child: AudioVisualiser(
                  style: VisualiserStyle.bars,
                  height: (h * 0.14).clamp(60.0, 150.0),
                  active: r.playing,
                  palette: t.palette.length >= 2
                      ? t.palette
                      : kVisualiserPalette,
                ),
              ),
            ],
            if (strip) ...[
              const SizedBox(height: 14),
              SizedBox(
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: r.stations.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => _StationChip(
                    r: r,
                    station: r.stations[i],
                    on: r.live && i == r.index,
                    seed: i,
                    badge: true,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// The song's cover where one was found; otherwise the station's badge.
class _Cover extends StatelessWidget {
  const _Cover({required this.r, required this.size});

  final _Radio r;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = r.theme;
    final badge = _Badge(
      letters: r.current.letters,
      seed: r.ours ? r.index : 0,
      theme: t,
      size: size,
    );
    final art = r.art;
    final radius = BorderRadius.circular(tileCorner(t, t.cornerRadius));
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      child: art == null
          ? KeyedSubtree(key: ValueKey('badge:${r.current.url}'), child: badge)
          : ClipRRect(
              key: ValueKey(art),
              borderRadius: radius,
              child: CachedNetworkImage(
                imageUrl: art,
                fit: BoxFit.cover,
                width: size,
                height: size,
                placeholder: (_, _) => badge,
                errorWidget: (_, _, _) => badge,
              ),
            ),
    );
  }
}

/// Songs played before this one, with when.
class _History extends StatelessWidget {
  const _History({required this.r, required this.songs});

  final _Radio r;
  final List<RadioSong> songs;

  @override
  Widget build(BuildContext context) {
    final t = r.theme;
    final heading = tr('widget.radio.earlier', 'Earlier');
    if (t.isLcars) return _console(t, heading);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          heading,
          style: TextStyle(
            color: t.textSecondary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        for (final s in songs)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    hhmm(s.at),
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 17,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    s.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 19,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// On a console, a panel the height of the page: its name on the bar,
  /// and each song a readout — its time on a block, the latest lit.
  Widget _console(DashboardTheme t, String heading) {
    return SizedBox.expand(
      child: LcarsPanel(
        theme: t,
        label: lcarsCaps(heading),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: songs.isEmpty
              ? Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    lcarsCaps(tr('widget.radio.noSongsYet', 'No songs yet')),
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 22,
                      letterSpacing: 1,
                    ),
                  ),
                )
              // As many as the panel has room for; the oldest go first.
              : SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, s) in songs.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 100,
                                height: 40,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: i == 0 ? lcarsLit : t.block(i),
                                  borderRadius: const BorderRadius.horizontal(
                                    left: Radius.circular(20),
                                  ),
                                ),
                                child: Text(
                                  hhmm(s.at),
                                  style: const TextStyle(
                                    color: lcarsInk,
                                    fontSize: 21,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 5),
                                  child: Text(
                                    lcarsCaps(s.title),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: i == 0 ? t.accent : t.textPrimary,
                                      fontSize: 24,
                                      height: 1.2,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

// --- Tuning dial --------------------------------------------------------------

class _DialLook extends StatelessWidget {
  const _DialLook({required this.r, required this.size});

  final _Radio r;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final t = r.theme;
    final h = size.height;
    final name = (h * 0.09).clamp(22.0, 60.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tileCased(t, r.current.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: name,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                  SizedBox(
                    height: name * 0.7,
                    child: ScrollingText(
                      r.detail,
                      style: TextStyle(
                        color: r.detailColour,
                        fontSize: name * 0.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _Trailing(r: r, size: 15),
          ],
        ),
        SizedBox(height: h * 0.04),
        Expanded(child: _Dial(r: r)),
        SizedBox(height: h * 0.04),
        Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: _Transport(
              r: r,
              size: (h * 0.13).clamp(48.0, 100.0),
              showLevel: true,
            ),
          ),
        ),
      ],
    );
  }
}

/// The dial: a lit glass band with a scale along it, the stations marked
/// on it in order, and a needle that glides to the one tuned in.
class _Dial extends StatelessWidget {
  const _Dial({required this.r});

  final _Radio r;

  /// The lamp behind an old set's dial.
  static const _lamp = Color(0xFFFFB347);
  static const _needle = Color(0xFFE53935);

  @override
  Widget build(BuildContext context) {
    final t = r.theme;
    final n = r.stations.length;
    // Two rows of names, alternating, once there are too many for one.
    final rows = n > 6 ? 2 : 1;
    final glow = r.live ? _lamp : t.textSecondary;
    // Resting on the station that play would start, until one is on.
    final tuned = r.ours ? r.index : 0;
    final radius = BorderRadius.circular(tileCorner(t, t.cornerRadius));
    // The names off the station, quietly: a light theme's own text colour
    // can be too pale for this.
    final quiet = t.isLcars || t.isLight
        ? t.textSecondary
        : t.textPrimary.withValues(alpha: 0.8);

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final label = (c.maxHeight * 0.1).clamp(13.0, 24.0);
        // Where [x], -1 to 1, is on the dial in pixels.
        double at(double x) => w * (x + 1) / 2;
        // Room for a name: the gap to its neighbour in the same row.
        final slot = (n <= 1 ? w * 0.6 : w * 0.85 / (n - 1) * rows) - 12;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: glow.withValues(alpha: r.live ? 0.55 : 0.25),
              width: 2,
            ),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                glow.withValues(alpha: r.live ? 0.20 : 0.06),
                glow.withValues(alpha: r.live ? 0.07 : 0.02),
              ],
            ),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ScalePainter(
                      colour: glow.withValues(alpha: 0.6),
                      marks: [for (var i = 0; i < n; i++) _x(i, n)],
                    ),
                  ),
                ),
                // Each name centred under its own mark, kept on the dial.
                for (final (i, s) in r.stations.indexed)
                  Positioned(
                    left: (at(_x(i, n)) - slot / 2).clamp(0.0, w - slot),
                    width: slot,
                    top: 0,
                    bottom: 0,
                    child: Align(
                      alignment: Alignment(
                        0,
                        rows == 2 && i.isOdd ? 0.45 : -0.25,
                      ),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => r.tune(s),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 400),
                            style: TextStyle(
                              color: i == tuned
                                  ? (r.live ? _lamp : t.accent)
                                  : quiet,
                              fontSize: label,
                              fontWeight: i == tuned
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              fontFamily: t.fontFamily,
                            ),
                            child: Text(
                              tileCased(t, s.name),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                // The needle, gliding past the stations between.
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeInOutCubic,
                  left: at(_x(tuned, n)) - 2,
                  width: 4,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: r.live
                            ? _needle
                            : _needle.withValues(alpha: 0.55),
                        boxShadow: [
                          if (r.live)
                            BoxShadow(
                              color: _needle.withValues(alpha: 0.7),
                              blurRadius: 12,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Where station [i] of [n] sits on the dial, -1 to 1, with a margin at
  /// each end.
  static double _x(int i, int n) => n <= 1 ? 0 : -0.85 + 1.7 * i / (n - 1);
}

/// The dial's scale: fine ticks along the top and bottom edges, and a
/// longer one at each station.
class _ScalePainter extends CustomPainter {
  _ScalePainter({required this.colour, required this.marks});

  final Color colour;
  final List<double> marks;

  @override
  void paint(Canvas canvas, Size size) {
    final fine = Paint()
      ..color = colour.withValues(alpha: colour.a * 0.5)
      ..strokeWidth = 1;
    final bold = Paint()
      ..color = colour
      ..strokeWidth = 2;
    const ticks = 80;
    for (var i = 0; i <= ticks; i++) {
      final x = size.width * (0.04 + 0.92 * i / ticks);
      final long = i % 10 == 0;
      final len = size.height * (long ? 0.09 : 0.05);
      final paint = long ? bold : fine;
      canvas
        ..drawLine(Offset(x, 0), Offset(x, len), paint)
        ..drawLine(Offset(x, size.height), Offset(x, size.height - len), paint);
    }
    for (final m in marks) {
      final x = size.width * (m + 1) / 2;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height * 0.16), bold);
    }
  }

  @override
  bool shouldRepaint(_ScalePainter old) =>
      old.colour != colour || old.marks.length != marks.length;
}

// --- Station grid -------------------------------------------------------------

class _GridLook extends StatelessWidget {
  const _GridLook({required this.r, required this.size});

  final _Radio r;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final t = r.theme;
    final h = size.height;
    final bar = (h * 0.16).clamp(64.0, 120.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: bar,
          child: Row(
            children: [
              _Cover(r: r, size: bar),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      tileCased(t, r.current.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: bar * 0.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(
                      height: bar * 0.32,
                      child: ScrollingText(
                        r.detail,
                        style: TextStyle(
                          color: r.detailColour,
                          fontSize: bar * 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              FittedBox(
                child: _Transport(r: r, size: bar * 0.7),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              // The number of columns that makes the cards largest and
              // squarest while all of them fit. With more stations than
              // fit even as wide, short cards, the grid scrolls.
              final n = r.stations.length;
              const gap = 12.0;
              var cols = 1;
              var best = 0.0;
              for (var k = 1; k <= n; k++) {
                final cw = (c.maxWidth - (k - 1) * gap) / k;
                final ch =
                    (c.maxHeight - ((n / k).ceil() - 1) * gap) / (n / k).ceil();
                final side = math.min(cw, ch);
                if (side > best && cw >= 150) {
                  best = side;
                  cols = k;
                }
              }
              final rows = (n / cols).ceil();
              final cell = (c.maxWidth - (cols - 1) * gap) / cols;
              final fitH = (c.maxHeight - (rows - 1) * gap) / rows;
              final height = fitH.clamp(cell / 2.2, cell * 1.2);
              return GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: gap,
                  crossAxisSpacing: gap,
                  childAspectRatio: cell / height,
                ),
                itemCount: n,
                itemBuilder: (_, i) => _StationCard(
                  r: r,
                  station: r.stations[i],
                  seed: i,
                  on: r.live && i == r.index,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StationCard extends StatelessWidget {
  const _StationCard({
    required this.r,
    required this.station,
    required this.seed,
    required this.on,
  });

  final _Radio r;
  final RadioStation station;
  final int seed;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final t = r.theme;
    final radius = BorderRadius.circular(tileCorner(t, t.cornerRadius * 0.8));
    return LayoutBuilder(
      builder: (context, c) {
        final badge = math.max(
          32.0,
          math.min(c.maxHeight * 0.5, c.maxWidth * 0.6),
        );
        return Material(
          color: on
              ? t.accent.withValues(alpha: 0.18)
              : t.textSecondary.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: on ? t.accent : Colors.transparent,
              width: 2,
            ),
          ),
          child: InkWell(
            customBorder: RoundedRectangleBorder(borderRadius: radius),
            onTap: () => r.tune(station),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _Badge(
                        letters: station.letters,
                        seed: seed,
                        theme: t,
                        size: badge,
                      ),
                      if (on)
                        Positioned(
                          right: -6,
                          bottom: -6,
                          child: _OnAirBars(
                            colour: t.accent,
                            size: badge * 0.42,
                            moving: r.playing,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // One line, made smaller to fit rather than broken
                  // mid-word: StreamingSoundtracks.com is all one word.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      tileCased(t, station.name),
                      maxLines: 1,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: (c.maxHeight * 0.1).clamp(12.0, 26.0),
                        fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                        height: 1.15,
                      ),
                    ),
                  ),
                  if (station.country.isNotEmpty && c.maxHeight > 150)
                    Text(
                      station.country,
                      maxLines: 1,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: (c.maxHeight * 0.05).clamp(12.0, 18.0),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Three bars bouncing on the card that is on air; still while it is only
/// tuning in. Its ticker stops with the page, as every ticker does.
class _OnAirBars extends StatefulWidget {
  const _OnAirBars({
    required this.colour,
    required this.size,
    required this.moving,
  });

  final Color colour;
  final double size;
  final bool moving;

  @override
  State<_OnAirBars> createState() => _OnAirBarsState();
}

class _OnAirBarsState extends State<_OnAirBars>
    with SingleTickerProviderStateMixin {
  late final _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.moving) _beat.repeat();
  }

  @override
  void didUpdateWidget(_OnAirBars old) {
    super.didUpdateWidget(old);
    if (widget.moving && !_beat.isAnimating) _beat.repeat();
    if (!widget.moving) _beat.stop();
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  /// How high a bar [phase] through the beat stands, 0.3 to 1: up and
  /// down once a beat, each bar a third of a beat behind the one before.
  double _height(double phase) {
    if (!widget.moving) return 0.65;
    final x = (_beat.value + phase) % 1;
    return 0.3 + 0.7 * (1 - (x * 2 - 1).abs());
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Container(
      width: s,
      height: s,
      padding: EdgeInsets.all(s * 0.22),
      decoration: BoxDecoration(color: widget.colour, shape: BoxShape.circle),
      child: AnimatedBuilder(
        animation: _beat,
        builder: (context, _) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final phase in const [0.0, 0.33, 0.66])
              Container(
                width: s * 0.12,
                height: s * 0.56 * _height(phase),
                color: Colors.white,
              ),
          ],
        ),
      ),
    );
  }
}

// --- Shared pieces ------------------------------------------------------------

/// A station's badge: its letters on a square of its own colour, picked
/// from the theme's palette by its place in the list, so neighbours differ.
class _Badge extends StatelessWidget {
  const _Badge({
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

/// A station as a chip that tunes in to it: filled in the accent while it
/// is the one on, with its badge in front when [badge].
class _StationChip extends StatelessWidget {
  const _StationChip({
    required this.r,
    required this.station,
    required this.on,
    required this.seed,
    this.badge = false,
  });

  final _Radio r;
  final RadioStation station;
  final bool on;
  final int seed;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final t = r.theme;
    if (t.isLcars) {
      return TileBlock(
        colour: t.block(seed),
        lit: on,
        height: 40,
        onTap: () => r.tune(station),
        child: Text(
          lcarsCaps(station.name),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      );
    }
    final radius = BorderRadius.circular(tileCorner(t, 22));
    return Material(
      color: on ? t.accent : t.textSecondary.withValues(alpha: 0.14),
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: () => r.tune(station),
        child: Padding(
          padding: EdgeInsets.fromLTRB(badge ? 6 : 16, 6, 16, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badge) ...[
                _Badge(
                  letters: station.letters,
                  seed: seed,
                  theme: t,
                  size: 30,
                ),
                const SizedBox(width: 8),
              ],
              // Shortened rather than run off a narrow tile.
              Flexible(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: badge ? 0 : 5),
                  child: Text(
                    station.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: on ? t.background.first : t.textPrimary,
                      fontSize: 15,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The top right of a compact tile or the dial: Live while a station is on.
class _Trailing extends StatelessWidget {
  const _Trailing({required this.r, this.size = 12});

  final _Radio r;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!r.playing) return const SizedBox.shrink();
    return StatusChip(
      text: tr('widget.radio.live', 'Live'),
      colour: StatusColours.of(r.theme).bad,
      size: size,
    );
  }
}

/// Which of the transport's keys a key is: play is the big one, and sleep
/// says when it will stop.
enum _Key { plain, play, sleep }

class _Transport extends StatelessWidget {
  const _Transport({
    required this.r,
    required this.size,
    this.showLevel = false,
  });

  final _Radio r;
  final double size;

  /// The volume as a figure between its two buttons.
  final bool showLevel;

  @override
  Widget build(BuildContext context) {
    final t = r.theme;
    final sleepAt = r.radio.sleepAt;
    // The sleep timer is one of the keys, drawn as they are: a tap steps it
    // through off, 15, 30, 60 and 90 minutes. Once set, it says when the
    // radio will stop — a time rather than a countdown, so it need not be
    // drawn again every minute.
    final keys = <(IconData, VoidCallback?, double, _Key)>[
      if (r.many) (Icons.skip_previous, () => r.step(-1), 1.0, _Key.plain),
      (
        r.playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
        r.toggle,
        1.3,
        _Key.play,
      ),
      if (r.many) (Icons.skip_next, () => r.step(1), 1.0, _Key.plain),
      (Icons.volume_down_rounded, r.quieter, 0.85, _Key.plain),
      (Icons.volume_up_rounded, r.louder, 0.85, _Key.plain),
      (
        sleepAt == null ? Icons.bedtime_outlined : Icons.bedtime,
        // Nothing to stop while nothing is on.
        r.live ? r.radio.cycleSleep : null,
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
      child: figure('${r.radio.volume.round()}', t.textSecondary),
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
                    _Key.play => r.playing ? lcarsLit : t.accent,
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
          if (k.$4 == _Key.play && r.loading)
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

final radioWidgetType = DashboardWidgetType(
  type: 'radio',
  name: 'Radio',
  description:
      'Internet radio on the panel’s speakers. Pick stations from around '
      'the world, or add any stream by its address, then tap one to tune in. '
      'It keeps playing when the dashboard turns the page. Given a page to '
      'itself it can show the song’s cover and what played before, an old '
      'set’s tuning dial, or a grid of stations.',
  glyph: '📻',
  category: WidgetCategory.photosAndMedia,
  defaultWidth: 4,
  defaultHeight: 3,
  minWidth: 2,
  minHeight: 1,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'stations',
      label: 'Stations',
      kind: OptionKind.list,
      addLabel: 'Add a station',
      defaultValue: [
        {'station': 'bbc_radio_4', 'name': '', 'url': ''},
        {'station': 'bbc_6music', 'name': '', 'url': ''},
        {'station': 'classic_fm', 'name': '', 'url': ''},
      ],
      help:
          'Choose from the list, or leave it and give a stream’s address '
          'instead — an Icecast, Shoutcast or HLS link ending .mp3, .aac or '
          '.m3u8, say, as a station’s “listen” page or radio-browser.info '
          'gives it.',
      fields: [
        WidgetOption(
          key: 'station',
          label: 'Station',
          kind: OptionKind.choice,
          choicesFrom: 'radioStations',
          defaultValue: '',
        ),
        WidgetOption(
          key: 'name',
          label: 'Name',
          defaultValue: '',
          help: 'Optional — the station’s own name otherwise.',
        ),
        WidgetOption(
          key: 'url',
          label: 'Stream address',
          defaultValue: '',
          help: 'Only for a station not in the list. Used in place of it.',
        ),
      ],
    ),
    WidgetOption(
      key: 'look',
      label: 'Look',
      kind: OptionKind.choice,
      defaultValue: 'auto',
      choices: {
        'auto': 'Automatic — Studio when the tile is big, Compact otherwise',
        'compact': 'Compact',
        'studio': 'Studio — the song’s cover, and what played before',
        'dial': 'Tuning dial',
        'grid': 'Station grid',
      },
      help:
          'Studio, the dial and the grid are for a big tile — a page to '
          'itself is best. On a small one they give way to Compact.',
    ),
    WidgetOption(
      key: 'volume',
      label: 'Starting volume',
      kind: OptionKind.number,
      defaultValue: 35,
      help:
          'Out of 100, for the very first station only. Once the volume is '
          'changed with the tile’s buttons, or by voice, the radio keeps '
          'that level for every station after — restarts too.',
    ),
    WidgetOption(
      key: 'list',
      label: 'Show the stations as buttons',
      kind: OptionKind.boolean,
      defaultValue: true,
      help:
          'In the Compact look, on a tile tall enough. Without them, step '
          'through with the arrows.',
    ),
    WidgetOption(
      key: 'visualiser',
      label: 'Draw the music',
      kind: OptionKind.boolean,
      defaultValue: true,
      help:
          'Bars that move with the sound, in the Studio look, while they '
          'are on screen.',
    ),
  ],
  preview: const [
    PreviewLine('📻 Radio', scale: .1, muted: true),
    PreviewLine('BBC Radio 4', scale: .14),
    PreviewLine('⏮  ▶  ⏭', scale: .14, accent: true),
  ],
  build: (context, w) => RadioWidget(w: w),
);
