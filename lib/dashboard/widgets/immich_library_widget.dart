import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/immich_service.dart';
import '../../services/system_stats.dart' show shortSize;
import '../../widgets/remote_image.dart';
import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';

/// The Immich library in numbers — photos, videos, how much space, what has
/// arrived lately — over a strip of the newest photos.
class ImmichLibraryWidget extends StatefulWidget {
  const ImmichLibraryWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  /// The last figures, kept between tiles and page flips — the numbers move
  /// slowly. Settable so tests can show figures without asking Immich.
  @visibleForTesting
  static LibraryStats? last;

  /// Off stops it asking Immich at all, for tests.
  @visibleForTesting
  static bool fetch = true;

  @override
  State<ImmichLibraryWidget> createState() => _ImmichLibraryWidgetState();
}

class _ImmichLibraryWidgetState extends State<ImmichLibraryWidget> {
  LibraryStats? _stats = ImmichLibraryWidget.last;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!ImmichLibraryWidget.fetch) return;
    try {
      final s = await context.read<ImmichService>().libraryStats();
      ImmichLibraryWidget.last = s;
      if (mounted) {
        setState(() {
          _stats = s;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not reach Immich');
    }
  }

  static String _count(int n) {
    final s = n.toString();
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final s = _stats;
    if (s == null) return TileMessage(_error ?? 'Asking Immich…', theme: t);
    final media = context.read<ImmichService>();
    final showStrip =
        widget.w.option('showLatest', true) && s.latest.isNotEmpty;

    Widget figure(String value, String label) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          maxLines: 1,
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            height: 1.1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(label, style: TextStyle(color: t.textSecondary, fontSize: 10)),
      ],
    );

    return LayoutBuilder(
      builder: (context, c) {
        final strip = showStrip && c.maxHeight > 200;
        final numbers = FitCanvas(
          designHeight: 84,
          maxScale: 3,
          builder: (context, size) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TileLabel(
                icon: Icons.photo_library_outlined,
                text: 'Immich library',
                theme: t,
                size: 11,
              ),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    figure(_count(s.photos), 'photos'),
                    const SizedBox(width: 18),
                    figure(_count(s.videos), 'videos'),
                    if (s.bytes != null) ...[
                      const SizedBox(width: 18),
                      figure(shortSize(s.bytes!), 'in all'),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              Text(
                s.addedRecently == 0
                    ? 'Nothing new in the last ${s.recentDays} days'
                    : '${s.addedCapped ? 'Over ' : ''}${_count(s.addedRecently)} '
                          'added in the last ${s.recentDays} days',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.accent, fontSize: 11),
              ),
            ],
          ),
        );
        if (!strip) return numbers;
        final count = (c.maxWidth / (c.maxHeight * 0.34)).floor().clamp(
          2,
          s.latest.length,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 5, child: numbers),
            SizedBox(height: c.maxHeight * 0.04),
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  for (var i = 0; i < count; i++) ...[
                    if (i > 0) SizedBox(width: c.maxWidth * 0.02),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: RemoteImage(
                          url: media.thumbUrl(s.latest[i].id),
                          fallbackUrl: media.previewUrl(s.latest[i].id),
                          headers: media.authHeaders,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

final immichLibraryWidgetType = DashboardWidgetType(
  type: 'immich_library',
  category: WidgetCategory.photosAndMedia,
  name: 'Immich library',
  description:
      'Your Immich library in numbers — photos, videos, how much '
      'space it takes, how many added lately — with the newest photos along '
      'the bottom.',
  glyph: '🗂️',
  defaultWidth: 4,
  defaultHeight: 3,
  minWidth: 2,
  minHeight: 1,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'showLatest',
      label: 'Show the newest photos',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
  ],
  preview: const [
    PreviewLine('5,429 photos · 301 videos', scale: 0.15),
    PreviewLine('22 GB in all', scale: 0.1, muted: true),
  ],
  build: (context, w) => ImmichLibraryWidget(w: w),
);
