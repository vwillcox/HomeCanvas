import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../screens/dashboard_screen.dart';
import '../services/dashboard_service.dart';
import 'dashboard_model.dart';
import 'dashboard_theme.dart';

/// One tile to draw for the web editor.
@immutable
class TileRenderRequest {
  const TileRenderRequest({
    required this.config,
    required this.theme,
    required this.settings,
    required this.size,
  });

  final DashboardWidgetConfig config;
  final DashboardTheme theme;
  final DashboardSettings settings;

  /// In the panel's own pixels.
  final Size size;
}

/// Draws dashboard tiles off screen, with the real widgets, for the web
/// editor's preview.
///
/// The editor used to preview each widget as a few lines of text the widget
/// described itself with. That could never look like the widget — no dials,
/// no graphs, no album art — so instead the kiosk draws the widget exactly as
/// it would on the wall, at the tile's size, in the chosen theme, and hands
/// the editor a picture of it.
///
/// Lives in the app's tree, beside the screens, so the widgets it builds find
/// the same services the dashboard's do. Built only while there is something
/// to draw, one tile at a time, and taken down straight after: a widget with
/// timers or streams runs for a second, not for as long as the editor is
/// open.
class TileRenderHost extends StatefulWidget {
  const TileRenderHost({super.key});

  /// How long to let a widget settle before taking its picture — long enough
  /// for a photo or a cover to arrive from the cache, short enough that
  /// dragging a tile gets its new picture promptly.
  static const settle = Duration(milliseconds: 700);

  /// Give up on a tile after this. The panel might not be drawing frames at
  /// all; the editor falls back to its text preview.
  static const timeout = Duration(seconds: 6);

  /// A backlog longer than this is the editor asking faster than the Pi can
  /// draw, and the older requests are stale anyway.
  static const maxQueued = 24;

  @override
  State<TileRenderHost> createState() => _TileRenderHostState();
}

class _Job {
  _Job(this.request, this.id);
  final TileRenderRequest request;
  final int id;
  final done = Completer<List<int>?>();
}

class _TileRenderHostState extends State<TileRenderHost> {
  final _queue = Queue<_Job>();
  final _boundary = GlobalKey();
  _Job? _current;
  int _ids = 0;
  DashboardService? _service;

  @override
  void initState() {
    super.initState();
    _service = context.read<DashboardService>()..renderTile = _render;
  }

  @override
  void dispose() {
    if (_service?.renderTile == _render) _service!.renderTile = null;
    for (final job in _queue) {
      job.done.complete(null);
    }
    _current?.done.complete(null);
    super.dispose();
  }

  Future<List<int>?> _render(TileRenderRequest request) {
    if (_queue.length >= TileRenderHost.maxQueued) {
      _queue.removeFirst().done.complete(null);
    }
    final job = _Job(request, ++_ids);
    _queue.add(job);
    if (_current == null) _next();
    return job.done.future;
  }

  Future<void> _next() async {
    if (!mounted || _queue.isEmpty) {
      if (mounted) setState(() => _current = null);
      return;
    }
    final job = _queue.removeFirst();
    setState(() => _current = job);
    try {
      job.done.complete(
        await _capture().timeout(TileRenderHost.timeout, onTimeout: () => null),
      );
    } catch (e) {
      debugPrint('TileRenderHost: ${job.request.config.type} failed: $e');
      if (!job.done.isCompleted) job.done.complete(null);
    }
    unawaited(_next());
  }

  Future<List<int>?> _capture() async {
    // Two frames: one to build and lay out, one for anything the first frame
    // asked for (a LayoutBuilder's second pass, an image already in cache).
    await SchedulerBinding.instance.endOfFrame;
    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(TileRenderHost.settle);
    await SchedulerBinding.instance.endOfFrame;
    if (!mounted) return null;
    final boundary = _boundary.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = _current;
    if (job == null) return const SizedBox.shrink();
    final r = job.request;
    // Well off the left of the panel, so it is laid out and painted — which
    // a picture needs — but never seen, and never in the way of a touch.
    return Positioned(
      left: -r.size.width - 4000,
      top: 0,
      width: r.size.width,
      height: r.size.height,
      child: IgnorePointer(
        child: RepaintBoundary(
          key: _boundary,
          // Its own Overlay and Material, as a screen would have, so a widget
          // that shows a tooltip or an ink splash has somewhere to put it.
          child: Material(
            type: MaterialType.transparency,
            child: Overlay(
              key: ValueKey(job.id),
              initialEntries: [
                OverlayEntry(
                  builder: (_) => DashboardTile(
                    config: r.config,
                    theme: r.theme,
                    settings: r.settings,
                    framed: false,
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
