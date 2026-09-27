import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../look.dart';
import 'package:provider/provider.dart';

import '../models/immich_models.dart';
import '../services/locked_folder_service.dart';
import '../services/media_source.dart';
import '../widgets/remote_image.dart';
import '../widgets/glass.dart';
import 'gallery_screen.dart';

/// Shows the assets in Immich's server-side Locked Folder. Assumes the session
/// is already unlocked (navigated here after a successful PIN unlock). Re-locks
/// when the screen is popped — and closes itself when nobody has touched the
/// panel for [lockAfter], so a folder left open on a wall in a shared house
/// does not stay open for whoever comes past next.
class LockedFolderScreen extends StatefulWidget {
  const LockedFolderScreen({super.key});

  /// Long enough for a video watched without touching the screen; short
  /// enough that a folder walked away from is not open all evening.
  static const Duration lockAfter = Duration(minutes: 10);

  @override
  State<LockedFolderScreen> createState() => _LockedFolderScreenState();
}

class _LockedFolderScreenState extends State<LockedFolderScreen> {
  late final LockedFolderService _locked = context.read<LockedFolderService>();
  List<Asset>? _assets;
  String? _error;

  /// Touches anywhere count, not just on this screen: a photo or video
  /// opened from here is a screen of its own on top.
  DateTime _lastTouch = DateTime.now();
  Timer? _idleCheck;

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_touched);
    _idleCheck = Timer.periodic(const Duration(seconds: 30), (_) {
      final idle = DateTime.now().difference(_lastTouch);
      if (idle >= LockedFolderScreen.lockAfter) {
        _closeForIdle();
      }
    });
    _load();
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_touched);
    _idleCheck?.cancel();
    super.dispose();
  }

  void _touched(PointerEvent _) => _lastTouch = DateTime.now();

  /// Back past anything opened from here, then out, which locks it again.
  void _closeForIdle() {
    _idleCheck?.cancel();
    if (!mounted) return;
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    navigator.popUntil((r) => r == route);
    navigator.pop();
  }

  Future<void> _load() async {
    setState(() {
      _assets = null;
      _error = null;
    });
    try {
      final a = await _locked.getLockedAssets();
      if (mounted) setState(() => _assets = a);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _relockAndLeave() async {
    await _locked.lock();
  }

  Future<void> _openAt(int index) async {
    await _locked.ensureElevated();
    final source = _locked.mediaSource;
    if (source == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GalleryScreen(
          assets: _assets!,
          initialIndex: index,
          source: source,
          onBeforeVideo: _locked.ensureElevated,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final source = _locked.mediaSource;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) => _relockAndLeave(),
      child: ModernScaffold(
        header: ScreenHeader(
          onBack: () => Navigator.of(context).maybePop(),
          title: 'Locked Folder',
          subtitle: 'Locks again when you leave',
          actions: [
            Padding(
              padding: EdgeInsets.all(15),
              child: Icon(Icons.lock_outline, color: context.look.textPrimary, size: 30),
            ),
          ],
        ),
        body: _buildBody(source),
      ),
    );
  }

  Widget _buildBody(MediaSource? source) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: context.look.textSecondary),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final assets = _assets;
    if (assets == null || source == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (assets.isEmpty) {
      return Center(
        child: Text(
          'The Locked Folder is empty',
          style: TextStyle(fontSize: 20, color: context.look.textSecondary),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: assets.length,
      itemBuilder: (context, i) {
        final a = assets[i];
        return GestureDetector(
          onTap: () => _openAt(i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                RemoteImage(
                  url: source.thumbUrl(a.id),
                  fallbackUrl: a.isImage ? source.originalUrl(a.id) : null,
                  headers: source.authHeaders,
                ),
                if (a.isVideo)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.play_circle_fill,
                        color: context.look.textPrimary,
                        size: 22,
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
}
