import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../dashboard_theme.dart';
import 'fit_canvas.dart';
import '../../l10n/dates.dart';
import '../../l10n/l10n.dart';

/// One video in a [VideoGrid].
class VideoGridItem {
  const VideoGridItem({
    required this.title,
    required this.onTap,
    this.subtitle = '',
    this.thumbnailUrl,
  });

  final String title;
  final String subtitle;
  final String? thumbnailUrl;
  final VoidCallback onTap;
}

/// Latest videos as a grid of thumbnails, touch one to play it: the
/// YouTube subscriptions tile and the Floatplane tile both draw this.
class VideoGrid extends StatelessWidget {
  const VideoGrid({super.key, required this.theme, required this.items});

  final DashboardTheme theme;
  final List<VideoGridItem> items;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return LayoutBuilder(builder: (context, c) {
      final count = items.length;
      final grid = bestGrid(count, c.biggest, cellAspect: 16 / 9);
      final gap = math.min(c.maxWidth, c.maxHeight) * 0.03;
      final cellW = (c.maxWidth - gap * (grid.columns - 1)) / grid.columns;
      final cellH = (c.maxHeight - gap * (grid.rows - 1)) / grid.rows;
      // Thumbnails are decoded no wider than they are drawn — covering the
      // cell, whichever way it is out of 16:9 — rather than at whatever size
      // the site serves, which for Nebula is full HD.
      final decodeWidth = (math.max(cellW, cellH * 16 / 9) *
              MediaQuery.devicePixelRatioOf(context))
          .round();
      return Stack(
        children: [
          for (var i = 0; i < count; i++)
            Positioned(
              left: (i % grid.columns) * (cellW + gap),
              top: (i ~/ grid.columns) * (cellH + gap),
              width: cellW,
              height: cellH,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: items[i].onTap,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(t.cornerRadius * 0.4),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: t.wash(0.08)),
                      if (items[i].thumbnailUrl != null)
                        Image.network(items[i].thumbnailUrl!,
                            fit: BoxFit.cover,
                            cacheWidth: decodeWidth,
                            errorBuilder: (_, _, _) => const SizedBox.shrink()),
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: VideoCaption(
                          title: items[i].title,
                          subtitle: items[i].subtitle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// A title, and a line under it, over the bottom of a picture.
class VideoCaption extends StatelessWidget {
  const VideoCaption({super.key, required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 22, 12, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.2)),
          if ((subtitle ?? '').isNotEmpty)
            Text(subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}

/// Fetches a feed again now, for anyone who has just seen a new video go up
/// and does not want to wait for the next automatic refresh.
class TileRefreshButton extends StatelessWidget {
  const TileRefreshButton(
      {super.key, required this.busy, required this.onRefresh});

  final bool busy;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onRefresh,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                : const Icon(Icons.refresh, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}

/// A short "how long ago" for a video's release: 5 min, 3 h, 2 d, 12 Mar.
String releasedAgo(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.inMinutes < 60) return tr('widget.videos.minAgo', '{inMinutes} min ago', {'inMinutes': math.max(1, d.inMinutes)});
  if (d.inHours < 24) return tr('widget.videos.hAgo', '{inHours} h ago', {'inHours': d.inHours});
  if (d.inDays < 7) return tr('widget.videos.dAgo', '{inDays} d ago', {'inDays': d.inDays});
  return dayMonth(at);
}
