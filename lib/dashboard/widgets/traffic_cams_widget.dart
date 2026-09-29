import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../services/traffic_cams_service.dart';
import '../../widgets/pause_when_hidden.dart';
import '../../widgets/shown_timers.dart';
import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';

/// A camera as a tile shows it: TfL's, or any still image address.
typedef _Shown = ({String name, String url, String view});

/// [url] with a marker that changes each minute, so a still the camera has
/// renewed is fetched again rather than taken from the cache.
String _fresh(String url, DateTime now) {
  final minute = now.millisecondsSinceEpoch ~/ 60000;
  return '$url${url.contains('?') ? '&' : '?'}hc=$minute';
}

/// Live stills from traffic cameras — London's from TfL, found by name or
/// nearness to home, or any other camera whose picture has an address.
class TrafficCamsWidget extends StatefulWidget {
  const TrafficCamsWidget({super.key, required this.w});
  final DashboardWidgetContext w;

  @override
  State<TrafficCamsWidget> createState() => _TrafficCamsWidgetState();
}

class _TrafficCamsWidgetState extends State<TrafficCamsWidget>
    with PauseWhenHidden, ShownTimers {
  Timer? _refresh;
  Timer? _cycle;
  int _index = 0;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
    // TfL renews its stills every few minutes; a minute keeps up.
    _refresh = everyWhileShown(const Duration(minutes: 1), _tick);
    _startCycle();
  }

  @override
  void didUpdateWidget(covariant TrafficCamsWidget old) {
    super.didUpdateWidget(old);
    _cycle?.cancel();
    _startCycle();
  }

  void _startCycle() {
    if (widget.w.option<String>('layout', 'grid') != 'cycle') return;
    final every = widget.w.option('every', 10).clamp(3, 600);
    _cycle = everyWhileShown(Duration(seconds: every), () {
      if (mounted) setState(() => _index++);
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _cycle?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    unawaited(context.read<TrafficCamsService>().ensure());
    setState(() => _now = DateTime.now());
  }

  /// The cameras listed in the settings, or the nearest to home if none.
  List<_Shown> _cameras(TrafficCamsService service) {
    final rows = widget.w.rows('cameras');
    final all = service.cams ?? const <TrafficCam>[];
    final out = <_Shown>[];
    for (final r in rows) {
      final typed = '${r['camera'] ?? ''}'.trim();
      final name = '${r['name'] ?? ''}'.trim();
      if (typed.isEmpty) continue;
      if (typed.startsWith('https://') || typed.startsWith('http://')) {
        out.add((
          name: name.isNotEmpty ? name : Uri.tryParse(typed)?.host ?? typed,
          url: typed,
          view: '',
        ));
        continue;
      }
      final c = TrafficCamsService.find(all, typed);
      if (c != null) {
        out.add((
          name: name.isNotEmpty ? name : c.name,
          url: c.imageUrl,
          view: c.view,
        ));
      }
    }
    if (rows.isNotEmpty) return out;
    return [
      for (final c in service.nearest(
        widget.w.option('nearest', 4).clamp(1, 12),
      ))
        (name: c.name, url: c.imageUrl, view: c.view),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final service = context.watch<TrafficCamsService>();
    final listed = widget.w.rows('cameras').isNotEmpty;
    final cams = _cameras(service);
    if (cams.isEmpty) {
      return TileMessage(
        service.cams == null
            ? (service.error ?? tr('widget.cams.loading', 'Finding cameras…'))
            : listed
            ? tr(
                'widget.cams.noneFound',
                'None of those cameras was found. Try part of a road name, such as “A406 Billet”.',
              )
            : service.home() == null
            ? tr(
                'widget.cams.needsPlace',
                'Set a place in Settings → Weather, or list cameras in the widget settings.',
              )
            : tr('widget.cams.noneNear', 'No cameras found.'),
        theme: t,
      );
    }
    final captions = widget.w.option('captions', true);
    if (widget.w.option<String>('layout', 'grid') == 'cycle') {
      final c = cams[_index % cams.length];
      return _CamView(
        key: ValueKey(c.url),
        cam: c,
        now: _now,
        caption: captions,
        onTap: () => _open(context, c),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        // TfL's stills are 352 × 288.
        final grid = bestGrid(cams.length, box.biggest, cellAspect: 1.22);
        const gap = 6.0;
        return Column(
          children: [
            for (var row = 0; row < grid.rows; row++) ...[
              if (row > 0) const SizedBox(height: gap),
              Expanded(
                child: Row(
                  children: [
                    for (var col = 0; col < grid.columns; col++) ...[
                      if (col > 0) const SizedBox(width: gap),
                      Expanded(
                        child: row * grid.columns + col < cams.length
                            ? _CamView(
                                cam: cams[row * grid.columns + col],
                                now: _now,
                                caption: captions,
                                onTap: () => _open(
                                  context,
                                  cams[row * grid.columns + col],
                                ),
                              )
                            : const SizedBox(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// The camera large, still renewing every minute, until tapped away.
  void _open(BuildContext context, _Shown cam) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(40),
        child: GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: _LargeCam(cam: cam),
        ),
      ),
    );
  }
}

class _CamView extends StatelessWidget {
  const _CamView({
    super.key,
    required this.cam,
    required this.now,
    required this.caption,
    required this.onTap,
  });

  final _Shown cam;
  final DateTime now;
  final bool caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: Colors.black,
              child: _CamImage(url: _fresh(cam.url, now)),
            ),
            if (caption)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 5),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xB0000000)],
                    ),
                  ),
                  child: Text(
                    [cam.name, if (cam.view.isNotEmpty) cam.view].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CamImage extends StatelessWidget {
  const _CamImage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) => Image.network(
    url,
    fit: BoxFit.cover,
    // The last picture stays up while the next one loads.
    gaplessPlayback: true,
    errorBuilder: (context, _, _) => Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.videocam_off_outlined,
                color: Colors.white54,
                size: 28,
              ),
              const SizedBox(height: 4),
              Text(
                tr('widget.cams.unavailable', 'Camera unavailable'),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _LargeCam extends StatefulWidget {
  const _LargeCam({required this.cam});
  final _Shown cam;

  @override
  State<_LargeCam> createState() => _LargeCamState();
}

class _LargeCamState extends State<_LargeCam> {
  late final Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cam = widget.cam;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: AspectRatio(
            aspectRatio: 1.22,
            child: _CamImage(url: _fresh(cam.url, _now)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            [cam.name, if (cam.view.isNotEmpty) cam.view].join(' · '),
            style: const TextStyle(color: Colors.white, fontSize: 22),
          ),
        ),
      ],
    );
  }
}

final trafficCamsWidgetType = DashboardWidgetType(
  type: 'traffic_cams',
  category: WidgetCategory.gettingOut,
  name: 'Traffic cameras',
  description:
      'Live pictures from the roads: any of London’s 900 TfL JamCams, found '
      'by road name or nearest home, or any other camera whose picture has '
      'a web address. Tap one to see it large. No key needed.',
  glyph: '📷',
  defaultWidth: 4,
  defaultHeight: 3,
  minWidth: 2,
  minHeight: 2,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'cameras',
      label: 'Cameras',
      kind: OptionKind.list,
      addLabel: 'Add a camera',
      help:
          'Part of a TfL camera’s name — “A406 Billet”, “Blackwall Tunnel” — '
          'or the address of any camera’s picture (https://…jpg). Leave empty '
          'for the TfL cameras nearest home.',
      fields: [
        WidgetOption(key: 'camera', label: 'Camera', defaultValue: ''),
        WidgetOption(
          key: 'name',
          label: 'Caption',
          defaultValue: '',
          help: 'Optional — the camera’s own name otherwise.',
        ),
      ],
    ),
    WidgetOption(
      key: 'nearest',
      label: 'Nearest cameras to show',
      kind: OptionKind.number,
      defaultValue: 4,
      help: 'When no cameras are listed above.',
    ),
    WidgetOption(
      key: 'layout',
      label: 'Layout',
      kind: OptionKind.choice,
      defaultValue: 'grid',
      choices: {'grid': 'All at once', 'cycle': 'One at a time, in turn'},
    ),
    WidgetOption(
      key: 'every',
      label: 'Seconds on each',
      kind: OptionKind.number,
      defaultValue: 10,
      help: 'One at a time only.',
    ),
    WidgetOption(
      key: 'captions',
      label: 'Show names',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
  ],
  preview: const [
    PreviewLine(
      '📷 A406 Billet Upass    📷 Blackwall Tunnel',
      scale: .11,
      px: 14,
    ),
  ],
  build: (context, w) => TrafficCamsWidget(w: w),
);
