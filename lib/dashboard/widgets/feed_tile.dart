import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../screens/video_sign_in.dart';
import '../../services/dashboard_service.dart';
import '../../services/video_player_service.dart';
import '../../services/video_site.dart';
import '../widget_registry.dart';
import 'tile_bits.dart';
import 'video_grid.dart';

/// The latest videos from a signed-in [VideoSite] — [T] — with a refresh
/// button. Touch one to watch it on the panel.
///
/// The YouTube subscriptions tile, the Floatplane tile and the Nebula tile
/// are all this; they differ only in which site they read.
class SiteFeedTile<T extends VideoSite> extends StatelessWidget {
  const SiteFeedTile({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  Widget build(BuildContext context) {
    final t = w.theme;
    final site = context.watch<T>();
    if (!site.signedIn) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => signInOnPanel(context, site),
        child: TileMessage(
          'Tap to sign in to ${site.name} and show your subscriptions here — '
          'or sign in from a computer at '
          '${context.read<DashboardService>().editorAddress}/${site.id}',
          theme: t,
        ),
      );
    }

    final videos = site.videos();
    final player = context.read<VideoPlayerService>();
    final now = DateTime.now();
    final count = w.option('count', 6).clamp(1, 30).toInt();
    return ClipRRect(
      borderRadius: BorderRadius.circular(t.cornerRadius * 0.6),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (videos == null)
            TileMessage(site.error ?? 'Fetching from ${site.name}…', theme: t)
          else if (videos.isEmpty)
            TileMessage(
                site.error ?? 'Nothing new from your ${site.name} '
                    'subscriptions.',
                theme: t)
          else
            VideoGrid(
              theme: t,
              items: [
                for (final video in videos.take(count))
                  VideoGridItem(
                    title: video.title,
                    subtitle: [
                      if (video.channel.isNotEmpty) video.channel,
                      if (video.released != null)
                        releasedAgo(video.released!, now),
                    ].join(' · '),
                    thumbnailUrl: video.link.thumbnailUrl,
                    onTap: () => player.play(video.link),
                  ),
              ],
            ),
          // Over whatever the tile shows, even an error or an empty list —
          // those are exactly when someone wants to try again.
          Positioned(
            top: 6,
            right: 6,
            child: TileRefreshButton(busy: site.loading, onRefresh: site.refresh),
          ),
        ],
      ),
    );
  }
}

/// The widget type for a site's feed tile: a [SiteFeedTile] of [T], and how
/// many videos to show.
DashboardWidgetType siteFeedWidgetType<T extends VideoSite>({
  required String type,
  required String name,
  required String description,
  required String glyph,
}) =>
    DashboardWidgetType(
      type: type,
      category: WidgetCategory.photosAndMedia,
      name: name,
      description: description,
      glyph: glyph,
      defaultWidth: 4,
      defaultHeight: 3,
      minWidth: 2,
      minHeight: 2,
      fitsItself: true,
      options: [
        WidgetOption(
          key: 'count',
          label: 'Videos',
          kind: OptionKind.number,
          defaultValue: 6,
          help: 'How many of the latest to show. The panel needs signing in '
              'to $name — in Settings → Music → Videos, by tapping the tile, '
              'or from a computer at the editor’s address followed by '
              '/$type.',
        ),
      ],
      preview: [PreviewLine(name, scale: 0.2, centre: true)],
      build: (context, w) => SiteFeedTile<T>(w: w),
    );
