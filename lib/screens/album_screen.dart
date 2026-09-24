import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/immich_models.dart';
import '../services/config_service.dart';
import '../services/immich_service.dart';
import '../services/media_cache.dart';
import '../services/media_source.dart';
import '../widgets/glass.dart';
import '../widgets/remote_image.dart';
import 'gallery_screen.dart';
import 'slideshow_screen.dart';

class AlbumScreen extends StatefulWidget {
  final Album album;
  const AlbumScreen({super.key, required this.album});

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  late final ImmichService _immich = context.read<ImmichService>();
  List<Asset>? _assets;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFast();
  }

  /// Paint from the disk cache first, then refresh from the server.
  Future<void> _loadFast() async {
    final cached = await _immich.getCachedAlbumAssets(widget.album.id);
    if (cached != null && cached.isNotEmpty && mounted) {
      setState(() => _assets = cached);
    }
    await _load(silent: cached != null && cached.isNotEmpty);
  }

  Future<void> _load({bool silent = false, bool force = false}) async {
    if (!silent) {
      setState(() {
        _assets = null;
        _error = null;
      });
    }
    try {
      final a = await _immich.getAlbumAssets(
        widget.album.id,
        forceRefresh: force,
      );
      if (mounted) {
        setState(() {
          _assets = a;
          _error = null;
        });
        _warmThumbnails(a);
      }
    } catch (e) {
      if (mounted && _assets == null) setState(() => _error = '$e');
    }
  }

  /// Pull this album's thumbnails into the cache so scrolling is instant, and
  /// pre-warm the first few full-size previews for the viewer.
  void _warmThumbnails(List<Asset> assets) {
    for (final a in assets) {
      precacheImage(
        CachedNetworkImageProvider(
          _immich.thumbUrl(a.id),
          headers: _immich.authHeaders,
          cacheManager: ImmichKioskPiCache.manager,
        ),
        context,
      );
    }
    unawaited(_warmPreviews(assets.where((a) => a.isImage).take(12).toList()));
  }

  Future<void> _warmPreviews(List<Asset> assets) async {
    for (final a in assets) {
      try {
        await ImmichKioskPiCache.manager.downloadFile(
          _immich.previewUrl(a.id),
          authHeaders: _immich.authHeaders,
        );
      } catch (_) {
        // Best effort — it will simply load on demand instead.
      }
    }
  }

  void _openAt(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GalleryScreen(
          assets: _assets!,
          initialIndex: index,
          source: _immich,
        ),
      ),
    );
  }

  void _startSlideshow() {
    final images = _assets!.where((a) => a.isImage).toList();
    if (images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No photos in this album for a slideshow'),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SlideshowScreen(
          images: images,
          source: _immich,
          settings: context.read<ConfigService>().slideshow,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final assets = _assets;
    final photos = assets?.where((a) => a.isImage).length ?? 0;
    final videos = assets?.where((a) => a.isVideo).length ?? 0;
    return ModernScaffold(
      header: ScreenHeader(
        onBack: () => Navigator.of(context).maybePop(),
        title: widget.album.name,
        subtitle: assets == null
            ? plural(widget.album.assetCount, 'item')
            : [
                if (photos > 0) plural(photos, 'photo'),
                if (videos > 0) plural(videos, 'video'),
                if (dateSpan(assets) case final span?) span,
              ].join('  ·  '),
        padding: const EdgeInsets.fromLTRB(28, 20, 40, 16),
        trailing: assets != null && assets.any((a) => a.isImage)
            ? FilledButton.icon(
                onPressed: _startSlideshow,
                icon: const Icon(Icons.play_arrow_rounded, size: 30),
                label: const Text('Slideshow'),
                style: whitePillButton(),
              )
            : null,
      ),
      body: _buildBody(assets),
    );
  }

  Widget _buildBody(List<Asset>? assets) {
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: () => _load(force: true));
    }
    if (assets == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (assets.isEmpty) {
      return const Center(
        child: Text(
          'This album is empty',
          style: TextStyle(fontSize: 24, color: Colors.white60),
        ),
      );
    }

    // A photo wall, grouped by month in the album's own order: the gaps are
    // thin so the pictures carry the page, and the month headings give a long
    // album somewhere to find your place.
    const grid = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 220,
      crossAxisSpacing: 6,
      mainAxisSpacing: 6,
    );
    final groups = groupAssets(assets);
    return CustomScrollView(
      slivers: [
        for (final g in groups) ...[
          if (g.label != null)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(40, g.start == 0 ? 4 : 28, 40, 14),
              sliver: SliverToBoxAdapter(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      g.label!,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      plural(g.end - g.start, 'item'),
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              40,
              0,
              40,
              g.end == assets.length ? 48 : 0,
            ),
            sliver: SliverGrid(
              gridDelegate: grid,
              delegate: SliverChildBuilderDelegate(
                childCount: g.end - g.start,
                (context, i) {
                  final index = g.start + i;
                  return _AssetTile(
                    asset: assets[index],
                    source: _immich,
                    onTap: () => _openAt(index),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A run of consecutive photos from the same month.
class MonthGroup {
  const MonthGroup(this.label, this.start, this.end);

  /// "September 2026", or null for photos with no date.
  final String? label;

  /// Indexes into the album, [start] inclusive, [end] exclusive.
  final int start;
  final int end;
}

/// Split [assets] into headed runs that are worth a heading.
///
/// Months first, since that is how most people remember photos. A month full
/// enough to fill a row keeps its own heading. Thin months next to each other
/// are gathered under one — "May – July 2026", "2019 – 2024" — so an album
/// collected over decades does not become a heading over every lone picture,
/// with most of a wide panel empty beside it. The Family album is the case:
/// 36 months, 19 of them holding fewer than four photos, one holding 392.
///
/// A full month is never folded into a range, however thin its neighbours:
/// the months with the most photos are the ones worth finding by name.
List<MonthGroup> groupAssets(List<Asset> assets, {int minPerGroup = 8}) {
  final out = <MonthGroup>[];
  var thinStart = -1;
  var thinEnd = -1;

  void flushThin() {
    if (thinStart < 0) return;
    out.add(
      MonthGroup(
        dateSpan(assets.sublist(thinStart, thinEnd)),
        thinStart,
        thinEnd,
      ),
    );
    thinStart = -1;
  }

  for (final g in groupByMonth(assets)) {
    final full = g.end - g.start >= minPerGroup;
    // Undated photos are never merged with dated ones: a range heading over
    // them would claim a date they do not have.
    if (full || g.label == null) {
      flushThin();
      out.add(g);
      continue;
    }
    if (thinStart < 0) thinStart = g.start;
    thinEnd = g.end;
    if (thinEnd - thinStart >= minPerGroup) flushThin();
  }
  flushThin();
  return out;
}

/// Split [assets] into runs by the month each was taken, keeping their order.
///
/// Runs, not buckets: the album's order is the owner's choice — oldest first,
/// newest first, or arranged by hand — and regrouping would override it. A
/// month that appears twice in a hand-arranged album gets two headings,
/// which is the honest picture of that order.
List<MonthGroup> groupByMonth(List<Asset> assets) => _runs(
  assets,
  (t) => t.year * 12 + t.month - 1,
  (t) => '${monthNames[t.month - 1]} ${t.year}',
);

List<MonthGroup> _runs(
  List<Asset> assets,
  int Function(DateTime) keyOf,
  String Function(DateTime) labelOf,
) {
  final groups = <MonthGroup>[];
  int? key(Asset a) => a.taken == null ? null : keyOf(a.taken!);

  var start = 0;
  for (var i = 1; i <= assets.length; i++) {
    if (i == assets.length || key(assets[i]) != key(assets[start])) {
      final t = assets[start].taken;
      groups.add(MonthGroup(t == null ? null : labelOf(t), start, i));
      start = i;
    }
  }
  return groups;
}

/// "2019 – 2026", "March 2024", or "March – June 2024": when the album covers.
String? dateSpan(List<Asset> assets) {
  DateTime? lo, hi;
  for (final a in assets) {
    final t = a.taken;
    if (t == null) continue;
    if (lo == null || t.isBefore(lo)) lo = t;
    if (hi == null || t.isAfter(hi)) hi = t;
  }
  if (lo == null || hi == null) return null;
  if (lo.year != hi.year) return '${lo.year} – ${hi.year}';
  if (lo.month == hi.month) return '${monthNames[lo.month - 1]} ${lo.year}';
  return '${monthNames[lo.month - 1]} – ${monthNames[hi.month - 1]} ${lo.year}';
}

class _AssetTile extends StatelessWidget {
  final Asset asset;
  final MediaSource source;
  final VoidCallback onTap;
  const _AssetTile({
    required this.asset,
    required this.source,
    required this.onTap,
  });

  String _dur(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    return PressScale(
      scale: 0.95,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              RemoteImage(
                url: source.thumbUrl(asset.id),
                fallbackUrl: asset.isImage
                    ? source.originalUrl(asset.id)
                    : null,
                headers: source.authHeaders,
              ),
              if (asset.isVideo)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Glass(
                    tint: 0.18,
                    blur: 10,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        if (asset.duration != null) ...[
                          const SizedBox(width: 3),
                          Text(
                            _dur(asset.duration!),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
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

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.white54),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
