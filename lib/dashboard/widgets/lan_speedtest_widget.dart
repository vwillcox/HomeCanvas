import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/lan_speedtest_service.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'speed_gauge.dart';

/// Speed between this panel and another machine on the network.
///
/// The companion to the Ookla widget rather than a replacement: that one
/// measures the path to the internet, this the path to a machine in the house.
/// When the internet test is slow, this is what tells you whether the problem
/// is your line or your own wiring.
class DashboardLanSpeedtestWidget extends StatefulWidget {
  const DashboardLanSpeedtestWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<DashboardLanSpeedtestWidget> createState() =>
      _DashboardLanSpeedtestWidgetState();
}

class _DashboardLanSpeedtestWidgetState
    extends State<DashboardLanSpeedtestWidget> {
  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final service = context.watch<LanSpeedtestService>();
    final s = service.state;

    final server = widget.w.option('server', '');
    final name = widget.w.option('name', '');
    final maxMbps = (widget.w.option('maxMbps', 2500)).toDouble();

    final centre = switch (s.phase) {
      LanPhase.upload => s.uploadMbps,
      _ => s.downloadMbps,
    };

    final label = switch (s.phase) {
      LanPhase.idle => s.hasResult ? 'tap to retest' : 'tap to start',
      LanPhase.download => 'download',
      LanPhase.upload => 'upload',
      LanPhase.done => 'tap to retest',
      LanPhase.failed => 'failed',
    };

    if (server.isEmpty) {
      return Center(
        child: Text(
          'Set the server address in the widget settings',
          textAlign: TextAlign.center,
          style: TextStyle(color: t.textSecondary, fontSize: 14),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: s.running ? service.cancel : () => unawaited(service.run(server)),
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth > c.maxHeight * 1.5;
          final gauge = SpeedGauge(
            downloadMbps: s.downloadMbps,
            uploadMbps: s.uploadMbps,
            maxMbps: maxMbps,
            colour: t.accent,
            uploadColour: _uploadColour(t),
            trackColour: t.textSecondary.withValues(alpha: 0.15),
            textColour: t.textPrimary,
            mutedColour: t.textSecondary,
            label: label,
            centreValue: centre,
          );
          final readout = _Readout(
            theme: t,
            state: s,
            target: name.isNotEmpty ? name : _hostOf(server),
          );

          if (wide) {
            return Row(
              children: [
                Expanded(flex: 3, child: gauge),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: readout),
              ],
            );
          }
          // The readout gets a share of the height rather than whatever it
          // asks for, so it can scale to fill its part of the tile.
          return Column(
            children: [
              Expanded(flex: 3, child: gauge),
              const SizedBox(height: 8),
              Expanded(flex: 2, child: readout),
            ],
          );
        },
      ),
    );
  }

  static String _hostOf(String url) {
    final u = Uri.tryParse(url);
    return u?.host.isNotEmpty == true ? u!.host : url;
  }

  static Color _uploadColour(DashboardTheme t) {
    final hsl = HSLColor.fromColor(t.accent);
    return hsl
        .withHue((hsl.hue + 140) % 360)
        .withLightness((hsl.lightness + 0.08).clamp(0.0, 1.0))
        .toColor();
  }
}

class _Readout extends StatelessWidget {
  const _Readout({
    required this.theme,
    required this.state,
    required this.target,
  });

  final DashboardTheme theme;
  final LanSpeedtestState state;
  final String target;

  @override
  Widget build(BuildContext context) {
    // Scaled to fill its share of the tile, as the internet test's is.
    return FitCanvas(
      designHeight: 120,
      maxScale: 2.2,
      builder: (context, _) {
        if (state.phase == LanPhase.failed) {
          return Center(
            child: Text(
              state.error ?? 'Test failed',
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.textSecondary, fontSize: 13),
            ),
          );
        }
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _readoutLine(
              theme,
              Icons.download,
              'Down',
              _mbps(state.downloadMbps),
              active: state.phase == LanPhase.download,
              colour: theme.accent,
            ),
            const SizedBox(height: 6),
            _readoutLine(
              theme,
              Icons.upload,
              'Up',
              _mbps(state.uploadMbps),
              active: state.phase == LanPhase.upload,
              colour: _DashboardLanSpeedtestWidgetState._uploadColour(theme),
            ),
            const Divider(height: 16),
            Text(
              'to $target',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.textSecondary, fontSize: 12),
            ),
            Text(
              'on your own network',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.textSecondary, fontSize: 11),
            ),
          ],
        );
      },
    );
  }

  static String _mbps(double v) => v <= 0
      ? '—'
      : (v >= 1000
            ? '${(v / 1000).toStringAsFixed(2)} Gb'
            : v.toStringAsFixed(0));
}

/// Text that shrinks to its share of a row rather than running past the end.
Widget _shrink(Widget child, {bool right = false}) => FittedBox(
  fit: BoxFit.scaleDown,
  alignment: right ? Alignment.centerRight : Alignment.centerLeft,
  child: child,
);

/// A name and a value on one line, each in its own share of the row.
Widget _readoutLine(
  DashboardTheme theme,
  IconData icon,
  String name,
  String value, {
  required bool active,
  required Color colour,
}) {
  return Row(
    children: [
      Icon(icon, size: 18, color: active ? colour : theme.textSecondary),
      const SizedBox(width: 6),
      Expanded(
        flex: 4,
        child: _shrink(
          Text(
            name,
            style: TextStyle(color: theme.textSecondary, fontSize: 13),
          ),
        ),
      ),
      Expanded(
        flex: 5,
        child: _shrink(
          Text(
            value,
            style: TextStyle(
              color: active ? colour : theme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          right: true,
        ),
      ),
    ],
  );
}

final lanSpeedtestWidgetType = DashboardWidgetType(
  type: 'lan_speedtest',
  category: WidgetCategory.network,
  name: 'LAN speed test',
  description:
      'Speed between this panel and another machine on your network, using a '
      'self-hosted OpenSpeedTest server. Tap to run. Measures your own wiring '
      'rather than your internet connection.',
  glyph: '🔁',
  defaultWidth: 4,
  defaultHeight: 4,
  minWidth: 1,
  minHeight: 1,
  options: const [
    WidgetOption(
      key: 'server',
      label: 'Server address',
      kind: OptionKind.text,
      defaultValue: '',
      help:
          'The OpenSpeedTest server, e.g. http://10.0.0.218:3000 — run it '
          'with: docker run -d --restart=unless-stopped --name openspeedtest '
          '-p 3000:3000 -p 3001:3001 openspeedtest/latest',
    ),
    WidgetOption(
      key: 'name',
      label: 'Call it',
      kind: OptionKind.text,
      defaultValue: '',
      help:
          'A friendly name for the other machine. Its address is used if '
          'this is empty.',
    ),
    WidgetOption(
      key: 'maxMbps',
      label: 'Top of the dial (Mbps)',
      kind: OptionKind.number,
      defaultValue: 2500,
      help:
          'The scale is logarithmic, so this only needs the right order of '
          'magnitude. 2500 suits a 2.5 Gb link, 1000 a gigabit one.',
    ),
  ],
  preview: const [
    PreviewLine('1.42', scale: 0.30, accent: true, centre: true),
    PreviewLine('Gb/s', scale: 0.10, muted: true, centre: true),
    PreviewLine('↓ 1420   ↑ 980', scale: 0.11, centre: true),
    PreviewLine('to Mac mini', scale: 0.09, muted: true, centre: true),
  ],
  fitsItself: true,
  build: (context, w) => DashboardLanSpeedtestWidget(w: w),
);
