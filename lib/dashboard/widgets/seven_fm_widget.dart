import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../l10n/l10n.dart';
import '../../services/radio_service.dart';
import '../../services/seven_fm.dart';
import '../../widgets/audio_visualiser.dart';
import '../../widgets/lcars.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'radio_bits.dart';
import 'scrolling_text.dart';
import 'tile_bits.dart';

/// StreamingSoundtracks.com — or another of the 24seven.FM stations — with
/// all the station says about what it plays: the album and its cover, how
/// far through the track is, what is coming up and who asked for it, and
/// what played before.
///
/// Played on the same player as the Radio tile, so the two never talk over
/// each other, at the volume that tile keeps.
class SevenFmWidget extends StatefulWidget {
  const SevenFmWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<SevenFmWidget> createState() => _SevenFmWidgetState();
}

class _SevenFmWidgetState extends State<SevenFmWidget> {
  SevenFmService? _service;
  SevenFeed? _feed;

  SevenStation get _station => sevenStation(widget.w.option('station', 'sst'));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _service ??= context.read<SevenFmService>();
    _follow();
  }

  @override
  void didUpdateWidget(SevenFmWidget old) {
    super.didUpdateWidget(old);
    _follow();
  }

  /// The feed for the station picked, given up for the one before.
  void _follow() {
    final station = _station;
    if (_feed?.station.id == station.id) return;
    final before = _feed;
    if (before != null) _service!.unwatch(before.station);
    _feed = _service!.watch(station);
  }

  @override
  void dispose() {
    final feed = _feed;
    if (feed != null) _service?.unwatch(feed.station);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radio = context.watch<RadioService>();
    final feed = _feed!;
    final w = widget.w;
    return ListenableBuilder(
      listenable: feed,
      builder: (context, _) {
        final s = _Seven(
          theme: w.theme,
          radio: radio,
          feed: feed,
          volume: w.option<double>('volume', 35),
        );
        final lists = w.option('lists', true);
        final visualiser = w.option('visualiser', true);
        return LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth >= 560 && c.maxHeight >= 360) {
              return _BigLook(
                s: s,
                size: c.biggest,
                lists: lists,
                visualiser: visualiser,
              );
            }
            return _SmallLook(s: s, size: c.biggest);
          },
        );
      },
    );
  }
}

/// What both looks are drawn from.
class _Seven {
  _Seven({
    required this.theme,
    required this.radio,
    required this.feed,
    required this.volume,
  });

  final DashboardTheme theme;
  final RadioService radio;
  final SevenFeed feed;
  final double volume;

  SevenStation get station => feed.station;
  bool get ours => radio.station?.url == station.stream;
  bool get playing => ours && radio.playing;
  bool get loading => ours && radio.loading;
  bool get live => playing || loading;
  String? get error => ours ? radio.error : null;

  void toggle() => radio.toggle(station.radio, volume: volume);

  /// The track to show. The station's feed runs on the station's clock and
  /// the panel hears it a little later, so while it plays here, the one the
  /// stream itself names wins: at a change of track the feed is ahead.
  SevenTrack? get track {
    final now = feed.now;
    final heard = playing ? radio.title : null;
    if (heard == null || now == null) return now;
    final song = splitRadioTitle(heard).song;
    if (sameName(now.title, song)) return now;
    for (final t in feed.before.take(2)) {
      if (sameName(t.title, song)) return t;
    }
    return now;
  }

  /// The line under the track, or in place of one.
  String get status =>
      error ??
      (loading
          ? tr('widget.radio.tuning', 'Tuning in…')
          : feed.offline
          ? tr('widget.sevenFm.offline', 'The station cannot be reached')
          : feed.now == null
          ? tr('widget.sevenFm.nothing', 'The station is between tracks')
          : tr('widget.radio.tapToListen', 'Tap play to listen'));

  /// Album and artist, as one line, as the station's site gives them.
  static String? albumLine(SevenTrack t) => switch ((t.album, t.artist)) {
    (final a?, final b?) => '$a — $b',
    (final a?, null) => a,
    (null, final b?) => b,
    _ => null,
  };
}

// --- Small --------------------------------------------------------------------

class _SmallLook extends StatelessWidget {
  const _SmallLook({required this.s, required this.size});

  final _Seven s;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    final h = size.height;
    final track = s.track;
    final cover = (h - 8).clamp(0.0, size.width * 0.3);
    final withCover = h >= 120 && cover >= 80 && size.width >= 360;
    // The station's full name only where the label has room for it.
    final narrow = size.width - (withCover ? cover + 14 : 0) < 320;
    final words = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TileLabel(
          icon: Icons.movie_filter_outlined,
          text: narrow ? s.station.badge : s.station.name,
          theme: t,
          trailing: s.playing
              ? StatusChip(
                  text: tr('widget.radio.live', 'Live'),
                  colour: StatusColours.of(t).bad,
                )
              : null,
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: (h * 0.16).clamp(20.0, 40.0) * 1.3,
          child: ScrollingText(
            track?.title ?? s.status,
            style: TextStyle(
              color: track == null && s.error != null
                  ? StatusColours.of(t).bad
                  : t.textPrimary,
              fontSize: (h * 0.16).clamp(16.0, 40.0),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (track != null && _Seven.albumLine(track) != null)
          SizedBox(
            height: 22,
            child: ScrollingText(
              _Seven.albumLine(track)!,
              style: TextStyle(color: t.textSecondary, fontSize: 14),
            ),
          ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: _transport(s, (h * 0.24).clamp(40.0, 88.0)),
        ),
      ],
    );
    return Row(
      children: [
        if (withCover) ...[
          SizedBox.square(
            dimension: cover,
            child: _Cover(s: s, size: cover),
          ),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: size.width - (withCover ? cover + 14 : 0),
                child: words,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

RadioTransport _transport(_Seven s, double size, {bool level = false}) =>
    RadioTransport(
      theme: s.theme,
      radio: s.radio,
      size: size,
      showLevel: level,
      playing: s.playing,
      loading: s.loading,
      live: s.live,
      onToggle: s.toggle,
    );

// --- Big ----------------------------------------------------------------------

/// For a page to itself: the cover large, the track, album and composer,
/// how far through it is, and beside them what is coming up and what played.
class _BigLook extends StatelessWidget {
  const _BigLook({
    required this.s,
    required this.size,
    required this.lists,
    required this.visualiser,
  });

  final _Seven s;
  final Size size;
  final bool lists;
  final bool visualiser;

  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    final w = size.width;
    final h = size.height;
    final track = s.track;
    final side = lists && w >= 1000;
    final bars = visualiser && h >= 420;
    final art = (h * (bars ? 0.62 : 0.72)).clamp(120.0, w * 0.36);
    final big = (h * 0.075).clamp(22.0, 64.0);
    final status = StatusColours.of(t);

    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            if (s.live)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: StatusChip(
                  text: tr('widget.radio.onAir', 'On air'),
                  colour: status.bad,
                  size: 14,
                ),
              ),
            Flexible(
              child: Text(
                tileCased(t, s.station.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.accent,
                  fontSize: big * 0.48,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: big * 0.3),
        Text(
          track?.title ?? s.status,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: track == null && s.error != null
                ? status.bad
                : t.textPrimary,
            fontSize: big,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
        if (track?.album case final album?) ...[
          SizedBox(height: big * 0.2),
          Text(
            album,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textPrimary.withValues(alpha: 0.85),
              fontSize: big * 0.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        if (track?.artist case final artist?) ...[
          SizedBox(height: big * 0.12),
          Text(
            artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: t.textSecondary, fontSize: big * 0.45),
          ),
        ],
        if (track?.started != null && track?.length != null) ...[
          SizedBox(height: big * 0.4),
          _Progress(theme: t, track: track!, size: big * 0.34),
        ],
        // On a tile with no room beside it for the list, the next track
        // at least.
        if (!side && s.feed.next.isNotEmpty) ...[
          SizedBox(height: big * 0.3),
          Text(
            tr('widget.sevenFm.nextIs', 'Next: {title}', {
              'title': s.feed.next.first.title,
            }),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: t.textSecondary, fontSize: big * 0.36),
          ),
        ],
        SizedBox(height: big * 0.5),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: _transport(s, (h * 0.11).clamp(48.0, 96.0), level: true),
        ),
      ],
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // The cover faintly behind it all, as the Radio tile's Studio has.
        if (track?.art case final cover? when !t.isLcars)
          RepaintBoundary(
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: cover,
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
                    child: _Cover(s: s, size: art),
                  ),
                  SizedBox(width: w * 0.035),
                  Expanded(child: words),
                  if (side) ...[
                    SizedBox(width: w * 0.03),
                    SizedBox(
                      width: (w * (t.isLcars ? 0.32 : 0.28)).clamp(
                        280.0,
                        600.0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _Tracks(
                              theme: t,
                              heading: tr('widget.sevenFm.upNext', 'Up next'),
                              tracks: s.feed.next,
                              seed: 0,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Expanded(
                            child: _Tracks(
                              theme: t,
                              heading: tr('widget.radio.earlier', 'Earlier'),
                              tracks: s.feed.before,
                              seed: 3,
                            ),
                          ),
                        ],
                      ),
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
                  active: s.playing,
                  palette: t.palette.length >= 2
                      ? t.palette
                      : kVisualiserPalette,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// The album's cover, or the station's badge without one.
class _Cover extends StatelessWidget {
  const _Cover({required this.s, required this.size});

  final _Seven s;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = s.theme;
    final badge = RadioBadge(
      letters: s.station.badge,
      seed: sevenStations.indexOf(s.station),
      theme: t,
      size: size,
    );
    final art = s.track?.art;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      child: art == null
          ? KeyedSubtree(key: ValueKey('badge:${s.station.id}'), child: badge)
          : ClipRRect(
              key: ValueKey(art),
              borderRadius: BorderRadius.circular(
                tileCorner(t, t.cornerRadius),
              ),
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

/// How far through the track is: a bar, and the time gone and the length.
/// Moved on once a second, on its own layer.
class _Progress extends StatefulWidget {
  const _Progress({
    required this.theme,
    required this.track,
    required this.size,
  });

  final DashboardTheme theme;
  final SevenTrack track;
  final double size;

  @override
  State<_Progress> createState() => _ProgressState();
}

class _ProgressState extends State<_Progress> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  static String _mmss(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final length = widget.track.length!;
    var gone = DateTime.now().difference(widget.track.started!);
    if (gone.isNegative) gone = Duration.zero;
    if (gone > length) gone = length;
    final figures = TextStyle(
      color: t.textSecondary,
      fontSize: widget.size,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return RepaintBoundary(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Row(
          children: [
            Text(_mmss(gone), style: figures),
            const SizedBox(width: 12),
            Expanded(
              child: TileProgress(
                theme: t,
                value: gone.inMilliseconds / length.inMilliseconds,
                height: (widget.size * 0.3).clamp(4.0, 10.0),
              ),
            ),
            const SizedBox(width: 12),
            Text(_mmss(length), style: figures),
          ],
        ),
      ),
    );
  }
}

/// A list of tracks — coming up, or played — each with its cover, and who
/// asked for it when somebody did. On a console, a panel of readouts.
class _Tracks extends StatelessWidget {
  const _Tracks({
    required this.theme,
    required this.heading,
    required this.tracks,
    required this.seed,
  });

  final DashboardTheme theme;
  final String heading;
  final List<SevenTrack> tracks;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final rows = tracks.isEmpty
        ? Text(
            tileCased(t, tr('widget.sevenFm.none', 'Nothing yet')),
            style: TextStyle(color: t.textSecondary, fontSize: 20),
          )
        // As many whole rows as there is room for.
        : LayoutBuilder(
            builder: (context, c) {
              final fit = (c.maxHeight / _rowHeight).floor();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, track) in tracks.take(fit).indexed)
                    _row(t, track, i),
                ],
              );
            },
          );
    if (t.isLcars) {
      return LcarsPanel(
        theme: t,
        label: lcarsCaps(heading),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Align(alignment: Alignment.topLeft, child: rows),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
        Expanded(
          child: Align(alignment: Alignment.topLeft, child: rows),
        ),
      ],
    );
  }

  static const _cover = 52.0;
  static const _gap = 12.0;
  static const _rowHeight = _cover + _gap;

  Widget _row(DashboardTheme t, SevenTrack track, int i) {
    const cover = _cover;
    final lcars = t.isLcars;
    final under = [
      ?track.album,
      if (track.requestedBy case final who?)
        tr('widget.sevenFm.askedBy', 'for {who}', {'who': who}),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: _gap),
      child: SizedBox(
        height: cover,
        child: Row(
          children: [
            if (lcars)
              Container(
                width: 16,
                height: cover,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: track.requestedBy != null
                      ? lcarsLit
                      : t.block(seed + i),
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(8),
                  ),
                ),
              ),
            ClipRRect(
              borderRadius: BorderRadius.circular(lcars ? 0 : 6),
              child: SizedBox.square(
                dimension: cover,
                child: track.art == null
                    ? ColoredBox(color: t.block(seed + i))
                    : CachedNetworkImage(
                        imageUrl: track.art!,
                        fit: BoxFit.cover,
                        memCacheWidth: 104,
                        errorWidget: (_, _, _) =>
                            ColoredBox(color: t.block(seed + i)),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tileCased(t, track.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: lcars && i == 0 ? t.accent : t.textPrimary,
                      fontSize: lcars ? 22 : 19,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      letterSpacing: lcars ? 0.6 : 0,
                    ),
                  ),
                  if (under.isNotEmpty)
                    Text(
                      tileCased(t, under),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: track.requestedBy != null
                            ? t.accent
                            : t.textSecondary,
                        fontSize: lcars ? 17 : 15,
                        height: 1.2,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final sevenFmWidgetType = DashboardWidgetType(
  type: 'sevenFm',
  name: 'StreamingSoundtracks',
  description:
      'StreamingSoundtracks.com — film, game and TV scores — on the panel’s '
      'speakers, with the album and its cover, how far through the track '
      'is, what is coming up and who asked for it, and what played before. '
      'Or one of its sister stations: 1980s.FM, Adagio.FM, Death.FM or '
      'Entranced.FM.',
  glyph: '🎬',
  category: WidgetCategory.photosAndMedia,
  defaultWidth: 4,
  defaultHeight: 2,
  minWidth: 2,
  minHeight: 1,
  fitsItself: true,
  options: [
    WidgetOption(
      key: 'station',
      label: 'Station',
      kind: OptionKind.choice,
      defaultValue: 'sst',
      choices: {for (final s in sevenStations) s.id: '${s.name} — ${s.about}'},
    ),
    const WidgetOption(
      key: 'volume',
      label: 'Starting volume',
      kind: OptionKind.number,
      defaultValue: 35,
      help:
          'Out of 100, until the volume is changed with the buttons. After '
          'that it keeps the level last set, as the Radio tile does.',
    ),
    const WidgetOption(
      key: 'lists',
      label: 'Show what is up next and what played',
      kind: OptionKind.boolean,
      defaultValue: true,
      help: 'Beside the track, on a tile wide enough — a page to itself.',
    ),
    const WidgetOption(
      key: 'visualiser',
      label: 'Draw the music',
      kind: OptionKind.boolean,
      defaultValue: true,
      help: 'Bars that move with the sound, on a big tile.',
    ),
  ],
  preview: const [
    PreviewLine('🎬 StreamingSoundtracks', scale: .1, muted: true),
    PreviewLine('Main Title', scale: .14),
    PreviewLine('▶  🔉 🔊', scale: .14, accent: true),
  ],
  build: (context, w) => SevenFmWidget(w: w),
);
