import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/immich_models.dart';
import '../../services/immich_service.dart';
import '../../services/retry_schedule.dart';
import '../../widgets/remote_image.dart';
import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';

/// Your photos from this date in past years, from Immich's own memories.
///
/// A slow slideshow with how long ago and where. On a day with no memories
/// it can fall back to photos from the whole library, so the tile is never
/// just a message.
class MemoriesWidget extends StatefulWidget {
  const MemoriesWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<MemoriesWidget> createState() => _MemoriesWidgetState();
}

class _Shown {
  const _Shown(this.asset, this.year);
  final Asset asset;

  /// The year it is a memory of; null for a fallback photo.
  final int? year;
}

class _MemoriesWidgetState extends State<MemoriesWidget> {
  List<_Shown> _photos = const [];
  int _index = 0;
  bool _loading = true;
  String? _error;
  DateTime? _loadedFor;
  Timer? _timer;
  Timer? _retryTimer;
  final Map<String, String?> _places = {};
  final RetrySchedule _retry = RetrySchedule(
    settled: const Duration(minutes: 30),
  );

  // A choice, so the editor saves it as text.
  int get _everySeconds =>
      int.tryParse('${widget.w.config.options['everySeconds'] ?? 15}') ?? 15;
  bool get _fallback => widget.w.option('fallback', true);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _restartTimer();
  }

  @override
  void didUpdateWidget(covariant MemoriesWidget old) {
    super.didUpdateWidget(old);
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    final s = _everySeconds;
    if (s <= 0) return;
    _timer = Timer.periodic(Duration(seconds: s), (_) => _step(1));
  }

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  Future<void> _load() async {
    final day = _today();
    _loadedFor = day;
    try {
      final immich = context.read<ImmichService>();
      var photos = [
        for (final m in await immich.getMemories(day)) _Shown(m.asset, m.year),
      ];
      if (photos.isEmpty && _fallback) {
        photos = [
          for (final a in await immich.getRandomAssets(count: 12))
            _Shown(a, null),
        ];
      }
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _index = 0;
        _loading = false;
        _error = null;
      });
      unawaited(_lookUpPlace());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
      _retryTimer?.cancel();
      _retryTimer = Timer(_retry.next(hasContent: false), () {
        if (mounted) unawaited(_load());
      });
    }
  }

  void _step(int by) {
    if (!mounted) return;
    // A new day brings new memories.
    if (_loadedFor != _today()) {
      unawaited(_load());
      return;
    }
    if (_photos.length < 2) return;
    setState(() => _index = (_index + by) % _photos.length);
    unawaited(_lookUpPlace());
  }

  Future<void> _lookUpPlace() async {
    if (_photos.isEmpty) return;
    final id = _photos[_index].asset.id;
    if (_places.containsKey(id)) return;
    final place = await context.read<ImmichService>().placeOf(id);
    if (mounted) setState(() => _places[id] = place);
  }

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    if (_loading && _photos.isEmpty) {
      return Center(
        child: SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: t.textSecondary,
          ),
        ),
      );
    }
    if (_photos.isEmpty) {
      return TileMessage(
        _error != null ? 'Waiting for Immich…' : 'No memories today',
        theme: t,
      );
    }
    final shown = _photos[_index];
    final media = context.read<ImmichService>();
    final now = DateTime.now();
    final taken = shown.asset.taken;
    final years = shown.year == null ? null : now.year - shown.year!;
    final place = _places[shown.asset.id];
    final headline = years == null
        ? 'From your library'
        : years == 1
        ? 'A year ago'
        : '$years years ago';
    final detail = [
      if (taken != null)
        '${taken.day} ${_months[taken.month - 1]} ${taken.year}',
      ?place,
    ].join(' · ');

    return GestureDetector(
      onTap: () => _step(1),
      onHorizontalDragEnd: (d) => _step((d.primaryVelocity ?? 0) > 0 ? -1 : 1),
      child: LayoutBuilder(
        builder: (context, c) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 700),
                  // Filling, not centred: the default layout hands the photo loose
                  // constraints, and it sat at its own small size mid-tile.
                  layoutBuilder: (current, previous) => Stack(
                    fit: StackFit.expand,
                    children: [...previous, ?current],
                  ),
                  child: RemoteImage(
                    key: ValueKey(shown.asset.id),
                    url: media.previewUrl(shown.asset.id),
                    fallbackUrl: media.originalUrl(shown.asset.id),
                    headers: media.authHeaders,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: c.maxHeight * 0.42,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xB8000000)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: c.maxHeight * 0.34,
                  child: FitCanvas(
                    designHeight: 70,
                    maxScale: 3,
                    builder: (context, size) => Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            headline,
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                              shadows: [Shadow(blurRadius: 8)],
                            ),
                          ),
                          if (detail.isNotEmpty)
                            Text(
                              detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xDDFFFFFF),
                                fontSize: 11,
                              ),
                            ),
                          if (_photos.length > 1) ...[
                            const SizedBox(height: 6),
                            _Dots(count: _photos.length, current: _index),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    // Past a dozen, dots stop meaning anything; a count says it better.
    if (count > 12) {
      return Text(
        '${current + 1} of $count',
        style: const TextStyle(color: Color(0xAAFFFFFF), fontSize: 9),
      );
    }
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.only(right: 3),
            width: i == current ? 12 : 4,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: i == current ? 1 : 0.45),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}

final memoriesWidgetType = DashboardWidgetType(
  type: 'memories',
  category: WidgetCategory.photosAndMedia,
  name: 'On this day',
  description:
      'Your photos from this date in past years, from Immich’s '
      'memories, with how long ago and where. Tap or swipe for the next.',
  glyph: '📸',
  defaultWidth: 4,
  defaultHeight: 6,
  minWidth: 2,
  minHeight: 2,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'everySeconds',
      label: 'Change photo every',
      kind: OptionKind.choice,
      defaultValue: '15',
      choices: {
        '8': '8 seconds',
        '15': '15 seconds',
        '30': '30 seconds',
        '60': 'A minute',
        '0': 'Only when tapped',
      },
    ),
    WidgetOption(
      key: 'fallback',
      label: 'Show other photos on days without memories',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
  ],
  preview: const [
    PreviewLine('📸', scale: 0.3, centre: true),
    PreviewLine('3 years ago', scale: 0.12, centre: true),
    PreviewLine('24 September 2023', scale: 0.08, muted: true, centre: true),
  ],
  build: (context, w) => MemoriesWidget(w: w),
);
