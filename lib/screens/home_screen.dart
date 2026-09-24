import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/immich_models.dart';
import '../services/immich_service.dart';
import '../services/config_service.dart';
import '../services/now_playing_service.dart';
import '../services/playback_source.dart';
import '../services/spotify_service.dart';
import '../widgets/glass.dart';
import '../widgets/module_bar.dart';
import '../widgets/now_playing_overlay.dart';
import '../widgets/remote_image.dart';
import 'album_screen.dart';
import 'slideshow_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ImmichService _immich = context.read<ImmichService>();
  List<Album>? _albums;
  String? _error;

  /// Ids of albums picked for a combined slideshow. Non-empty = selection mode.
  final Set<String> _selected = {};
  bool get _selectionMode => _selected.isNotEmpty;

  AlbumSort _sort = AlbumSort.recent;

  /// The mini player in the page, which the full player grows out of and
  /// shrinks back into.
  final GlobalKey _miniPlayer = GlobalKey();
  final NowPlayingOverlayController _player = NowPlayingOverlayController();

  @override
  void initState() {
    super.initState();
    _loadFast();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  /// Paint from the disk cache immediately (instant cold start), then refresh
  /// from the server in the background.
  Future<void> _loadFast() async {
    final cached = await _immich.getCachedAlbums();
    if (cached != null && cached.isNotEmpty && mounted) {
      setState(() => _albums = cached);
    }
    await _load(silent: cached != null && cached.isNotEmpty);
  }

  Future<void> _load({bool silent = false, bool force = false}) async {
    if (!silent) {
      setState(() {
        _albums = null;
        _error = null;
      });
    }
    try {
      final a = await _immich.getAlbums(forceRefresh: force);
      if (mounted) {
        setState(() {
          _albums = a;
          _error = null;
        });
      }
      // Warm every album cover into the disk cache in the background so the
      // whole grid is populated before it's scrolled.
      unawaited(_immich.warmAlbumCovers(a));
    } catch (e) {
      // Keep showing cached content if we have it; only surface a hard error
      // when there's nothing on screen.
      if (mounted && _albums == null) setState(() => _error = '$e');
    }
  }

  void _openAlbum(Album album) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => AlbumScreen(album: album)));
  }

  // ---- Multi-select -----------------------------------------------------

  void _toggleSelect(Album album) {
    setState(() {
      if (!_selected.remove(album.id)) _selected.add(album.id);
    });
  }

  void _clearSelection() => setState(_selected.clear);

  /// Gather every photo from the selected albums into one slideshow.
  Future<void> _slideshowFromSelection() => _slideshowFrom(_selected.toList());

  /// Every photo from [ids], as one slideshow.
  Future<void> _slideshowFrom(List<String> ids) async {
    if (ids.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final images = <Asset>[];
    final seen = <String>{};
    try {
      final results = await Future.wait(
        ids.map((id) => _immich.getAlbumAssets(id)),
      );
      for (final assets in results) {
        for (final a in assets) {
          if (a.isImage && seen.add(a.id)) images.add(a);
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        _snack('Could not load the selected albums: $e');
      }
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop(); // dismiss loading

    if (images.isEmpty) {
      _snack('No photos in the selected albums');
      return;
    }
    final count = ids.length;
    _clearSelection();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SlideshowScreen(
          images: images,
          source: _immich,
          settings: context.read<ConfigService>().slideshow,
          title: '$count album${count == 1 ? '' : 's'}',
        ),
      ),
    );
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    // The weather overlay is deliberately not shown here — it's for the
    // slideshow (photo-frame mode) only. The now-playing player, on the other
    // hand, takes over full-screen here when music is playing and no
    // slideshow is running — there's nothing better to show — but stays out
    // of the way while picking albums for a multi-select slideshow.
    //
    // The header is fixed rather than scrolled away: Settings has to stay
    // reachable when Immich is down and there is nothing to scroll.
    return ModernScaffold(
      header: _selectionMode ? _selectionHeader() : _header(),
      body: _buildBody(),
      overlays: [
        if (!_selectionMode)
          NowPlayingOverlay(
            startExpanded: true,
            anchor: _miniPlayer,
            controller: _player,
          ),
      ],
    );
  }

  Widget _header() {
    final albums = visibleAlbums(_albums ?? const <Album>[]);
    final photos = albums.fold<int>(0, (n, a) => n + a.assetCount);
    return ScreenHeader(
      titleWidget: GreetingTitle(
        detail: albums.isEmpty
            ? null
            : '${plural(albums.length, 'album')} · ${plural(photos, 'item')}',
      ),
      trailing: ModuleBar(
        current: KioskModule.photos,
        onRefresh: () => _load(force: true),
      ),
    );
  }

  Widget _selectionHeader() {
    return ScreenHeader(
      onBack: _clearSelection,
      backIcon: Icons.close,
      backTooltip: 'Cancel selection',
      title: '${_selected.length} selected',
      subtitle: 'Tap more albums to add them to one slideshow',
      trailing: FilledButton.icon(
        onPressed: _slideshowFromSelection,
        icon: const Icon(Icons.play_arrow_rounded, size: 30),
        label: const Text('Slideshow'),
        style: whitePillButton(),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 64,
                color: Colors.white38,
              ),
              const SizedBox(height: 16),
              const Text(
                'Could not reach Immich',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 17),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _load(force: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
                style: whitePillButton(),
              ),
            ],
          ),
        ),
      );
    }
    final albums = _albums;
    if (albums == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (albums.isEmpty) {
      return const Center(
        child: Text(
          'No albums yet',
          style: TextStyle(fontSize: 24, color: Colors.white60),
        ),
      );
    }

    final shown = visibleAlbums(albums);
    if (shown.isEmpty) {
      return const Center(
        child: Text(
          'No albums with anything in them yet',
          style: TextStyle(fontSize: 24, color: Colors.white60),
        ),
      );
    }
    final sorted = sortAlbums(shown, _sort);
    final playing = _selectionMode ? null : showablePlayback(context);

    return RefreshIndicator(
      onRefresh: () => _load(silent: true, force: true),
      child: CustomScrollView(
        slivers: [
          if (playing != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(40, 8, 40, 0),
              sliver: SliverToBoxAdapter(
                child: _MiniPlayer(
                  key: _miniPlayer,
                  source: playing,
                  onOpen: _player.expand,
                ),
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(40, playing != null ? 36 : 12, 40, 18),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  const Text(
                    'Albums',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  for (final s in AlbumSort.values) ...[
                    const SizedBox(width: 10),
                    ChoicePill(
                      label: s.label,
                      selected: _sort == s,
                      onTap: () => setState(() => _sort = s),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(40, 0, 40, 48),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 300,
                crossAxisSpacing: 20,
                mainAxisSpacing: 20,
                childAspectRatio: 0.82,
              ),
              delegate: SliverChildBuilderDelegate(childCount: sorted.length, (
                context,
                i,
              ) {
                final album = sorted[i];
                return _AlbumTile(
                  album: album,
                  immich: _immich,
                  selected: _selected.contains(album.id),
                  selectionMode: _selectionMode,
                  // In selection mode a tap toggles; otherwise it opens
                  // the album.
                  onTap: () =>
                      _selectionMode ? _toggleSelect(album) : _openAlbum(album),
                  onLongPress: () => _toggleSelect(album),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

/// How the album grid is ordered.
enum AlbumSort {
  recent('Recent'),
  name('A–Z'),
  size('Most items');

  const AlbumSort(this.label);
  final String label;
}

/// [albums] in [sort] order. Stable, so equal albums keep Immich's order.
List<Album> sortAlbums(List<Album> albums, AlbumSort sort) {
  final indexed = [for (var i = 0; i < albums.length; i++) (i, albums[i])];
  int byIndex((int, Album) a, (int, Album) b) => a.$1.compareTo(b.$1);
  switch (sort) {
    case AlbumSort.recent:
      final never = DateTime.fromMillisecondsSinceEpoch(0);
      indexed.sort((a, b) {
        final c = (b.$2.updatedAt ?? never).compareTo(a.$2.updatedAt ?? never);
        return c != 0 ? c : byIndex(a, b);
      });
    case AlbumSort.name:
      indexed.sort((a, b) {
        final c = a.$2.name.toLowerCase().compareTo(b.$2.name.toLowerCase());
        return c != 0 ? c : byIndex(a, b);
      });
    case AlbumSort.size:
      indexed.sort((a, b) {
        final c = b.$2.assetCount.compareTo(a.$2.assetCount);
        return c != 0 ? c : byIndex(a, b);
      });
  }
  return [for (final e in indexed) e.$2];
}

/// The albums worth showing: those with something in them.
///
/// An empty album on a wall of photographs is a grey placeholder tile that
/// opens onto "This album is empty". Immich keeps them for good reasons — an
/// album made ready for a trip, one whose photos were moved — but none of
/// those reasons is a reason to show it here.
List<Album> visibleAlbums(List<Album> albums) => [
  for (final a in albums)
    if (a.assetCount > 0) a,
];

/// Whatever is playing, when the now-playing player is switched on and has
/// something to show — by the same rules as the pop-up player itself, so the
/// two can never disagree about whether there is music.
PlaybackSource? showablePlayback(BuildContext context) {
  final settings = context.watch<ConfigService>().config.nowPlaying;
  final spotify = context.watch<SpotifyService>();
  final avrcp = context.watch<NowPlayingService>();
  final PlaybackSource source = spotify.available ? spotify : avrcp;
  if (!settings.enabled ||
      !source.available ||
      !source.now.hasTrack ||
      source.idleHidden) {
    return null;
  }
  return source;
}

/// The small player, as part of the page.
///
/// Where the old corner card floated over the album grid, this takes a row of
/// its own above it. A tap anywhere but the buttons opens the full player,
/// which grows out of this card and shrinks back into it.
class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({super.key, required this.source, required this.onOpen});

  final PlaybackSource source;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final n = source.now;
    final art = source.artUrl;
    final accent = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      label: 'Now playing: ${n.title}, ${n.artist}. Open the player.',
      child: PressScale(
        scale: 0.99,
        child: GestureDetector(
          onTap: onOpen,
          child: Glass(
            radius: 28,
            tint: 0.07,
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: 104,
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      width: 104,
                      height: 104,
                      child: art == null
                          ? const ColoredBox(
                              color: Color(0xFF1A1C23),
                              child: Icon(
                                Icons.music_note_rounded,
                                size: 44,
                                color: Colors.white30,
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: art,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) =>
                                  const ColoredBox(color: Color(0xFF1A1C23)),
                            ),
                    ),
                  ),
                  const SizedBox(width: 22),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              source.sourceIcon,
                              size: 20,
                              color: Colors.white54,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                n.deviceName.isEmpty
                                    ? 'Now playing'
                                    : n.deviceName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          n.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          n.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 19,
                            color: Colors.white70,
                          ),
                        ),
                        // No bar while Spotify's DJ is talking: there is no
                        // track, so no length to show progress through.
                        if (n.duration > Duration.zero) ...[
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: n.progress,
                              minHeight: 4,
                              backgroundColor: Colors.white12,
                              valueColor: AlwaysStoppedAnimation(accent),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  _TransportButton(
                    icon: Icons.skip_previous_rounded,
                    label: 'Previous',
                    onPressed: source.previous,
                  ),
                  const SizedBox(width: 8),
                  _TransportButton(
                    icon: n.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    label: n.isPlaying ? 'Pause' : 'Play',
                    onPressed: source.playPause,
                    primary: true,
                  ),
                  const SizedBox(width: 8),
                  _TransportButton(
                    icon: Icons.skip_next_rounded,
                    label: 'Next',
                    onPressed: source.next,
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final size = primary ? 84.0 : 68.0;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: primary ? Colors.white : Colors.white.withValues(alpha: 0.08),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: size * 0.55,
              color: primary ? const Color(0xFF0B0C10) : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _AlbumTile extends StatelessWidget {
  final Album album;
  final ImmichService immich;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _AlbumTile({
    required this.album,
    required this.immich,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  static const _radius = 24.0;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return PressScale(
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          // The selection ring sits outside the photo, so choosing an album
          // does not crop into its cover.
          padding: EdgeInsets.all(selected ? 5 : 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_radius + 5),
            color: selected ? accent : Colors.transparent,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_radius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                album.thumbnailAssetId != null
                    ? RemoteImage(
                        url: immich.thumbUrl(album.thumbnailAssetId!),
                        fallbackUrl: immich.previewUrl(album.thumbnailAssetId!),
                        headers: immich.authHeaders,
                      )
                    : const ColoredBox(
                        color: Color(0xFF1A1C23),
                        child: Icon(
                          Icons.photo_album_outlined,
                          size: 56,
                          color: Colors.white24,
                        ),
                      ),
                // A scrim under the words only, so the photo stays the photo.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xD9000000)],
                      stops: [0.42, 1.0],
                    ),
                  ),
                ),
                // A hairline edge: without it a dark photo's corners melt into
                // the dark background and the card loses its shape.
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_radius),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        album.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        plural(album.assetCount, 'item'),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selectionMode)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: AnimatedScale(
                      scale: selected ? 1.0 : 0.85,
                      duration: const Duration(milliseconds: 150),
                      child: Container(
                        decoration: BoxDecoration(
                          color: selected ? accent : Colors.black45,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        padding: const EdgeInsets.all(5),
                        child: Icon(
                          selected ? Icons.check : Icons.circle_outlined,
                          size: 24,
                          color: Colors.white,
                        ),
                      ),
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
