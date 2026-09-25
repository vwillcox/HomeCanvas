import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/immich_models.dart';
import '../services/immich_service.dart';
import '../widgets/remote_image.dart';

/// Your Immich photos behind the dashboard, one after another, darkened so
/// the tiles in front stay readable.
///
/// A slow cross-fade and a long hold, so it reads as a room with a changing
/// view rather than a slideshow competing with the widgets.
class PhotoBackdrop extends StatefulWidget {
  const PhotoBackdrop({
    super.key,
    required this.albumId,
    required this.dim,
    required this.every,
    required this.base,
  });

  /// Empty for photos from the whole library.
  final String albumId;
  final double dim;
  final Duration every;

  /// The theme's background, shown until the first photo arrives.
  final Color base;

  /// The photo behind the dashboard now, for the editor's preview to show.
  static String? current;

  @override
  State<PhotoBackdrop> createState() => _PhotoBackdropState();
}

class _PhotoBackdropState extends State<PhotoBackdrop> {
  final _rng = Random();
  List<Asset> _pool = const [];
  int _index = 0;
  Timer? _timer;
  Timer? _retry;
  String _loadedFor = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _restart();
  }

  @override
  void didUpdateWidget(covariant PhotoBackdrop old) {
    super.didUpdateWidget(old);
    if (old.albumId != widget.albumId) unawaited(_load());
    if (old.every != widget.every) _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _retry?.cancel();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.every, (_) => _advance());
  }

  Future<void> _load() async {
    final key = widget.albumId;
    _loadedFor = key;
    try {
      final immich = context.read<ImmichService>();
      final assets = key.isEmpty
          ? await immich.getRandomAssets(count: 40)
          : await immich.getAlbumAssets(key);
      if (!mounted || _loadedFor != key) return;
      final images = assets.where((a) => a.isImage).toList()..shuffle(_rng);
      setState(() {
        _pool = images;
        _index = 0;
      });
      PhotoBackdrop.current = images.isEmpty ? null : images.first.id;
    } catch (_) {
      // Try again shortly: the theme's own background shows meanwhile.
      _retry?.cancel();
      _retry = Timer(const Duration(minutes: 1), () {
        if (mounted) unawaited(_load());
      });
    }
  }

  void _advance() {
    if (!mounted || _pool.isEmpty) return;
    // Near the end of a random pool, fetch another rather than repeat.
    if (widget.albumId.isEmpty && _index >= _pool.length - 2) {
      unawaited(_load());
      return;
    }
    setState(() => _index = (_index + 1) % _pool.length);
    PhotoBackdrop.current = _pool[_index].id;
  }

  @override
  Widget build(BuildContext context) {
    final media = context.read<ImmichService>();
    final asset = _pool.isEmpty ? null : _pool[_index];
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: widget.base),
          if (asset != null)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 2400),
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                children: [...previous, ?current],
              ),
              child: RemoteImage(
                key: ValueKey(asset.id),
                url: media.previewUrl(asset.id),
                fallbackUrl: media.originalUrl(asset.id),
                headers: media.authHeaders,
              ),
            ),
          // Darker at the top, where the greeting and the bar sit, and a
          // steady dim everywhere else.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(
                    alpha: (widget.dim + 0.2).clamp(0, 0.95),
                  ),
                  Colors.black.withValues(alpha: widget.dim),
                  Colors.black.withValues(alpha: widget.dim),
                ],
                stops: const [0, 0.22, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
