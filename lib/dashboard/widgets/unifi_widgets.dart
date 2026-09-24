import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/throughput_history.dart';
import '../../services/unifi_models.dart';
import '../../services/unifi_service.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'fit_canvas.dart';

/// Five views onto a UniFi console, sharing one service and one poll.
///
/// Separate widgets rather than one configurable panel because they answer
/// different questions and belong in different places: "is the internet up"
/// wants to be glanceable from the sofa, "which port is that switch using"
/// does not.

/// Shown by every one of them until the console has answered.
class _Waiting extends StatelessWidget {
  const _Waiting({required this.theme, required this.service});

  final DashboardTheme theme;
  final UnifiService service;

  @override
  Widget build(BuildContext context) {
    final s = service.settings;
    final message = !s.enabled
        ? 'UniFi is switched off in Settings'
        : s.apiKey.isEmpty
        ? 'No API key set'
        : service.error != null
        ? 'Waiting for the console…'
        : 'Reading the network…';
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: theme.textSecondary, fontSize: 14),
      ),
    );
  }
}

/// A label above a value, which is most of what these widgets are.
class _Stat extends StatelessWidget {
  const _Stat({
    required this.theme,
    required this.label,
    required this.value,
    this.colour,
    this.scale = 1,
  });

  final DashboardTheme theme;
  final String label;
  final String value;
  final Color? colour;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: theme.textSecondary, fontSize: 12 * scale),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              color: colour ?? theme.textPrimary,
              fontSize: 26 * scale,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 1. Network health
// ---------------------------------------------------------------------------

/// How [UnifiHealthWidget] arranges itself for a tile of a given shape.
enum HealthLayout {
  /// A long, thin strip: the status above one row of all five figures.
  strip,

  /// The usual tile: status, then down and up large, then the smaller three.
  stacked,

  /// Taller than wide: one figure to a line.
  column,
}

/// The arrangement that suits a tile [aspect] (width over height) best.
HealthLayout healthLayoutFor(double aspect) {
  if (aspect >= 3.4) return HealthLayout.strip;
  if (aspect >= 1.05) return HealthLayout.stacked;
  return HealthLayout.column;
}

/// Is the internet up, and is anything wrong.
///
/// Fills its tile: everything is drawn on a [FitCanvas], so the figures grow
/// with the tile, and the arrangement follows its shape — a strip, the usual
/// stack, or a column — rather than one layout shrunk to fit all of them.
class UnifiHealthWidget extends StatelessWidget {
  const UnifiHealthWidget({super.key, required this.w});
  final DashboardWidgetContext w;

  @override
  Widget build(BuildContext context) {
    final t = w.theme;
    final unifi = context.watch<UnifiService>();
    if (!unifi.hasContent) return _Waiting(theme: t, service: unifi);

    final stats = unifi.gatewayStats;
    final offline = unifi.offlineDevices;
    final updates = unifi.updatableDevices;

    // "Up" is taken from the uplink reporting at all, not from a rate above
    // zero: a quiet connection is not a broken one.
    final wanUp = stats.txRateBps != null || stats.rxRateBps != null;
    final good = wanUp && offline.isEmpty;
    final statusText = good
        ? 'Network healthy'
        : (!wanUp ? 'WAN down' : '${offline.length} device(s) offline');
    final statusColour = good ? const Color(0xFF4ADE80) : Colors.orangeAccent;

    String pct(double? v) => v == null ? '—' : '${v.toStringAsFixed(0)}%';
    final down = ('Down', formatBps(stats.rxRateBps), t.accent);
    final up = ('Up', formatBps(stats.txRateBps), null);
    final small = [
      ('Clients', '${unifi.clients.length}', null),
      ('CPU', pct(stats.cpuPct), null),
      ('Memory', pct(stats.memoryPct), null),
    ];

    return FitCanvas(
      builder: (context, design) {
        // The status line sizes itself from its row; the number is kept so
        // the three layouts below still read alike.
        Widget status(double _) => _FitStatus(
          icon: good ? Icons.check_circle : Icons.error,
          iconColour: statusColour,
          text: statusText,
          textColour: t.textPrimary,
        );

        Widget stat((String, String, Color?) s, double label, double value) =>
            _FitStat(
              theme: t,
              label: s.$1,
              value: s.$2,
              colour: s.$3,
              labelSize: label,
              valueSize: value,
            );

        Widget updatesLine(double _) => LayoutBuilder(
          builder: (context, c) => _Fit(
            Text(
              '${updates.length} firmware update(s) available',
              style: TextStyle(
                color: t.textSecondary,
                fontSize: c.maxHeight * 0.7,
                height: 1.15,
              ),
            ),
          ),
        );

        switch (healthLayoutFor(design.width / design.height)) {
          case HealthLayout.strip:
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 30, child: status(18)),
                Expanded(
                  flex: 62,
                  child: Row(
                    children: [
                      for (final s in [down, up, ...small])
                        Expanded(child: stat(s, 13, 30)),
                    ],
                  ),
                ),
                if (updates.isNotEmpty)
                  Expanded(flex: 12, child: updatesLine(10)),
              ],
            );
          case HealthLayout.stacked:
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 20, child: status(15)),
                Expanded(
                  flex: 42,
                  child: Row(
                    children: [
                      Expanded(child: stat(down, 10, 28)),
                      Expanded(child: stat(up, 10, 28)),
                    ],
                  ),
                ),
                Expanded(
                  flex: 30,
                  child: Row(
                    children: [
                      for (final s in small) Expanded(child: stat(s, 9, 19)),
                    ],
                  ),
                ),
                if (updates.isNotEmpty)
                  Expanded(flex: 10, child: updatesLine(8)),
              ],
            );
          case HealthLayout.column:
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 14, child: status(11)),
                for (final s in [down, up, ...small])
                  Expanded(
                    flex: 15,
                    child: LayoutBuilder(
                      builder: (context, c) => Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: _Fit(
                              Text(
                                s.$1,
                                style: TextStyle(
                                  color: t.textSecondary,
                                  fontSize: c.maxHeight * 0.45,
                                  height: 1.15,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 6,
                            child: _Fit(
                              Text(
                                s.$2,
                                style: TextStyle(
                                  color: s.$3 ?? t.textPrimary,
                                  fontSize: c.maxHeight * 0.72,
                                  fontWeight: FontWeight.w700,
                                  height: 1.15,
                                ),
                              ),
                              alignment: Alignment.centerRight,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (updates.isNotEmpty)
                  Expanded(flex: 10, child: updatesLine(7)),
              ],
            );
        }
      },
    );
  }
}

/// Text that shrinks to fit its width, and never grows.
///
/// Inside a [FitCanvas] the sizes are already right for the tile; this only
/// catches the long value — "1.24 Gb/s" in a narrow column — that would
/// otherwise run off the edge.
class _Fit extends StatelessWidget {
  const _Fit(this.child, {this.alignment = Alignment.centerLeft});

  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) =>
      FittedBox(fit: BoxFit.scaleDown, alignment: alignment, child: child);
}

/// A label over a value, sized from the height it is given.
///
/// Sized from its own box rather than in fixed canvas units: fixed units that
/// added up to a hair more than a row's share overflowed by a pixel or two at
/// some tile sizes. As fractions of the box, with line spacing counted, the
/// pair always fits. [labelSize] and [valueSize] set the proportion between
/// the two.
class _FitStat extends StatelessWidget {
  const _FitStat({
    required this.theme,
    required this.label,
    required this.value,
    required this.labelSize,
    required this.valueSize,
    this.colour,
  });

  final DashboardTheme theme;
  final String label;
  final String value;
  final double labelSize;
  final double valueSize;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final share = c.maxHeight * 0.86 / (labelSize + valueSize);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Fit(
              Text(
                label,
                style: TextStyle(
                  color: theme.textSecondary,
                  fontSize: share * labelSize / 1.17,
                  height: 1.17,
                ),
              ),
            ),
            _Fit(
              Text(
                value,
                style: TextStyle(
                  color: colour ?? theme.textPrimary,
                  fontSize: share * valueSize / 1.1,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// An icon and a line of text, sized from the height it is given — the
/// status line, which has to fit its share of the canvas at any size.
class _FitStatus extends StatelessWidget {
  const _FitStatus({
    required this.icon,
    required this.iconColour,
    required this.text,
    required this.textColour,
  });

  final IconData icon;
  final Color iconColour;
  final String text;
  final Color textColour;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight;
        // Limited by the width as well: on a tile one cell wide and six tall
        // the row is narrower than it is high, and an icon sized from the
        // height alone left no room for the text at all.
        final icon = math.min(h * 0.78, c.maxWidth * 0.3);
        final gap = math.min(h * 0.3, c.maxWidth * 0.08);
        return Row(
          children: [
            Icon(this.icon, color: iconColour, size: icon),
            SizedBox(width: gap),
            Expanded(
              child: _Fit(
                Text(
                  text,
                  style: TextStyle(
                    color: textColour,
                    fontSize: h * 0.62,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Who's home
// ---------------------------------------------------------------------------

/// Named devices currently on the network.
///
/// Presence, not location: this says a phone is associated to your own WiFi,
/// which for a household is the question actually being asked.
class UnifiPresenceWidget extends StatelessWidget {
  const UnifiPresenceWidget({super.key, required this.w});
  final DashboardWidgetContext w;

  @override
  Widget build(BuildContext context) {
    final t = w.theme;
    final unifi = context.watch<UnifiService>();
    if (!unifi.hasContent) return _Waiting(theme: t, service: unifi);

    final watch = w
        .option('watch', '')
        .split(',')
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toList();

    final wirelessOnly = w.option('wirelessOnly', true);
    var list = unifi.clients.where((c) => !wirelessOnly || c.wireless).toList();

    if (watch.isNotEmpty) {
      // A named list is the useful mode: thirty clients is an inventory, five
      // people's phones is a question you might actually ask.
      list = list
          .where(
            (c) => watch.any(
              (wanted) =>
                  c.displayName.toLowerCase().contains(wanted) ||
                  c.macAddress.toLowerCase() == wanted,
            ),
          )
          .toList();
    }
    list.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );

    if (list.isEmpty) {
      return Center(
        child: Text(
          watch.isEmpty ? 'Nobody connected' : 'None of those are here',
          style: TextStyle(color: t.textSecondary, fontSize: 14),
        ),
      );
    }

    // Names present are the point; whoever is watched but absent is shown
    // greyed rather than omitted, so the list does not change shape.
    final missing = watch
        .where(
          (wanted) => !list.any(
            (c) =>
                c.displayName.toLowerCase().contains(wanted) ||
                c.macAddress.toLowerCase() == wanted,
          ),
        )
        .toList();

    return ListView(
      children: [
        for (final c in list)
          _PresenceRow(
            theme: t,
            name: c.displayName,
            here: true,
            detail: c.connectedFor == null
                ? (c.wireless ? 'wireless' : 'wired')
                : 'for ${formatUptime(c.connectedFor!)}',
          ),
        for (final name in missing)
          _PresenceRow(theme: t, name: name, here: false, detail: 'away'),
      ],
    );
  }
}

class _PresenceRow extends StatelessWidget {
  const _PresenceRow({
    required this.theme,
    required this.name,
    required this.here,
    required this.detail,
  });

  final DashboardTheme theme;
  final String name;
  final bool here;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: here ? const Color(0xFF4ADE80) : theme.textSecondary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: here ? theme.textPrimary : theme.textSecondary,
                fontSize: 16,
                fontWeight: here ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            detail,
            style: TextStyle(color: theme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Devices and firmware
// ---------------------------------------------------------------------------

/// Every adopted UniFi device, with its state, model and uptime.
///
/// Spreads its entries across the tile rather than listing them down one
/// edge: two devices on a wide, one-row strip sit side by side, each as large
/// as the strip allows. The text is sized from each entry's share of the
/// tile, so it fills a big tile and still fits a small one. Only when there
/// are too many to show legibly at once does it fall back to a scrolling
/// list at a fixed, readable size.
class UnifiDevicesWidget extends StatelessWidget {
  const UnifiDevicesWidget({super.key, required this.w});
  final DashboardWidgetContext w;

  /// Below this a grid entry's name would be too small to read across a
  /// room, and the list scrolls instead.
  static const double minEntryHeight = 44;

  /// An entry's shape, width over height: a name and a detail line beside
  /// an icon want roughly this.
  static const double entryAspect = 3.2;

  @override
  Widget build(BuildContext context) {
    final t = w.theme;
    final unifi = context.watch<UnifiService>();
    if (!unifi.hasContent) return _Waiting(theme: t, service: unifi);
    final devices = unifi.devices;
    if (devices.isEmpty) {
      return Center(
        child: Text(
          'No devices',
          style: TextStyle(color: t.textSecondary, fontSize: 16),
        ),
      );
    }

    String detail(UnifiDevice d) => [
      d.model,
      if (d.firmwareVersion.isNotEmpty) d.firmwareVersion,
      if (unifi.statsFor(d.id).uptimeSec != null)
        'up ${formatUptime(Duration(seconds: unifi.statsFor(d.id).uptimeSec!))}',
    ].join(' · ');

    return LayoutBuilder(
      builder: (context, c) {
        final grid = bestGrid(
          devices.length,
          c.biggest,
          cellAspect: entryAspect,
        );
        final cellW = c.maxWidth / grid.columns;
        final cellH = c.maxHeight / grid.rows;

        if (cellH < minEntryHeight) {
          return ListView(
            children: [
              for (final d in devices)
                SizedBox(
                  height: minEntryHeight + 8,
                  child: _DeviceEntry(theme: t, device: d, detail: detail(d)),
                ),
            ],
          );
        }

        return Column(
          children: [
            for (var r = 0; r < grid.rows; r++)
              Expanded(
                child: Row(
                  children: [
                    for (var col = 0; col < grid.columns; col++)
                      Expanded(
                        child: r * grid.columns + col < devices.length
                            ? Padding(
                                padding: EdgeInsets.all(
                                  math.min(cellW, cellH) * 0.04,
                                ),
                                child: _DeviceEntry(
                                  theme: t,
                                  device: devices[r * grid.columns + col],
                                  detail: detail(
                                    devices[r * grid.columns + col],
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One device, drawn to fill whatever box it is given.
class _DeviceEntry extends StatelessWidget {
  const _DeviceEntry({
    required this.theme,
    required this.device,
    required this.detail,
  });

  final DashboardTheme theme;
  final UnifiDevice device;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final d = device;
    // A 50-unit canvas: name 17, detail 11, icon 22. Capped so a large tile
    // with two devices does not draw names a hand high.
    return FitCanvas(
      designHeight: 50,
      maxScale: 3,
      builder: (context, _) => Row(
        children: [
          Icon(
            d.online ? Icons.router : Icons.router_outlined,
            size: 22,
            color: d.online ? t.accent : Colors.orangeAccent,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Fit(
                  Text(
                    d.name,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                ),
                _Fit(
                  Text(
                    detail,
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 11,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (d.firmwareUpdatable) ...[
            const SizedBox(width: 6),
            Icon(Icons.system_update_alt, size: 16, color: t.accent),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Client detail
// ---------------------------------------------------------------------------

/// Every client, and what it is connected through.
///
/// Note what this deliberately does *not* claim: the official API reports no
/// signal strength or per-client throughput, so there is no "experience"
/// figure here. Showing one would mean inventing it.
class UnifiClientsWidget extends StatelessWidget {
  const UnifiClientsWidget({super.key, required this.w});
  final DashboardWidgetContext w;

  @override
  Widget build(BuildContext context) {
    final t = w.theme;
    final unifi = context.watch<UnifiService>();
    if (!unifi.hasContent) return _Waiting(theme: t, service: unifi);

    final byId = {for (final d in unifi.devices) d.id: d};
    final clients = [...unifi.clients]
      ..sort((a, b) {
        // Newest arrivals first: what just joined is the interesting end.
        final x = a.connectedAt, y = b.connectedAt;
        if (x == null && y == null) return 0;
        if (x == null) return 1;
        if (y == null) return -1;
        return y.compareTo(x);
      });

    return ListView(
      children: [
        for (final c in clients)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  c.wireless ? Icons.wifi : Icons.settings_ethernet,
                  size: 16,
                  color: t.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Text(
                    c.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.textPrimary, fontSize: 14),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    byId[c.uplinkDeviceId]?.name ?? c.ipAddress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(color: t.textSecondary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 5. Throughput
// ---------------------------------------------------------------------------

class UnifiThroughputWidget extends StatelessWidget {
  const UnifiThroughputWidget({super.key, required this.w});
  final DashboardWidgetContext w;

  @override
  Widget build(BuildContext context) {
    final t = w.theme;
    final unifi = context.watch<UnifiService>();
    if (!unifi.hasContent) return _Waiting(theme: t, service: unifi);

    final window =
        windows[w.option('window', '1h')] ?? const Duration(hours: 1);
    final showVolume = w.option('showVolume', true);
    final up = _uploadColour(t);

    // Listens to the history rather than the service, so a sample a second
    // repaints this graph and nothing else on the dashboard.
    return ListenableBuilder(
      listenable: unifi.history,
      builder: (context, _) {
        final h = unifi.history;
        final latest = h.latest;
        final volume = showVolume ? h.volume(window) : null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    theme: t,
                    label: 'Down',
                    value: formatBps(latest?.rx),
                    colour: t.accent,
                  ),
                ),
                Expanded(
                  child: _Stat(
                    theme: t,
                    label: 'Up',
                    value: formatBps(latest?.tx),
                    colour: up,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  // One point per pixel column at most: handing a 400-pixel
                  // graph 1,440 values only overdraws the same columns.
                  final points = h.series(
                    window,
                    math.max(2, c.maxWidth.floor()),
                  );
                  if (points.length < 2) {
                    return Center(
                      child: Text(
                        'Collecting…',
                        style: TextStyle(color: t.textSecondary, fontSize: 13),
                      ),
                    );
                  }
                  return CustomPaint(
                    size: Size.infinite,
                    painter: _ThroughputPainter(
                      points: points,
                      downColour: t.accent,
                      upColour: up,
                      gridColour: t.textSecondary.withValues(alpha: 0.15),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  // The window asked for, and how much there actually is — a
                  // panel up ten minutes cannot show a day, and saying so
                  // beats a graph that looks mysteriously short.
                  h.span < window
                      ? '${_label(window)} · ${formatUptime(h.span)} so far'
                      : _label(window),
                  style: TextStyle(color: t.textSecondary, fontSize: 11),
                ),
                const Spacer(),
                if (volume != null)
                  Text(
                    '↓ ${formatBytes(volume.rxBytes)}  ↑ ${formatBytes(volume.txBytes)}',
                    style: TextStyle(color: t.textSecondary, fontSize: 11),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// The windows offered. Ten minutes and under come from the per-second
  /// samples; longer spans from per-minute peaks.
  static const Map<String, Duration> windows = {
    '5m': Duration(minutes: 5),
    '15m': Duration(minutes: 15),
    '1h': Duration(hours: 1),
    '6h': Duration(hours: 6),
    '24h': Duration(hours: 24),
  };

  static String _label(Duration d) =>
      d.inHours >= 1 ? 'last ${d.inHours}h' : 'last ${d.inMinutes}m';

  static Color _uploadColour(DashboardTheme t) {
    final hsl = HSLColor.fromColor(t.accent);
    return hsl.withHue((hsl.hue + 140) % 360).toColor();
  }
}

/// Two filled areas on a shared scale, so the asymmetry of a domestic line is
/// the obvious feature rather than something to work out.
class _ThroughputPainter extends CustomPainter {
  _ThroughputPainter({
    required this.points,
    required this.downColour,
    required this.upColour,
    required this.gridColour,
  });

  final List<ThroughputPoint> points;
  final Color downColour;
  final Color upColour;
  final Color gridColour;

  @override
  void paint(Canvas canvas, Size size) {
    var peak = 0.0;
    for (final p in points) {
      peak = math.max(peak, math.max(p.tx, p.rx));
    }
    // A floor on the scale, so an idle line is a flat trace along the bottom
    // rather than noise amplified to fill the graph.
    peak = math.max(peak, 1000000);

    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()
        ..color = gridColour
        ..strokeWidth = 1,
    );

    void trace(double Function(ThroughputPoint) pick, Color colour) {
      final path = Path()..moveTo(0, size.height);
      for (var i = 0; i < points.length; i++) {
        final x = size.width * (i / (points.length - 1));
        final y = size.height * (1 - (pick(points[i]) / peak).clamp(0.0, 1.0));
        path.lineTo(x, y);
      }
      path
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(path, Paint()..color = colour.withValues(alpha: 0.28));

      final line = Path();
      for (var i = 0; i < points.length; i++) {
        final x = size.width * (i / (points.length - 1));
        final y = size.height * (1 - (pick(points[i]) / peak).clamp(0.0, 1.0));
        i == 0 ? line.moveTo(x, y) : line.lineTo(x, y);
      }
      canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = colour,
      );
    }

    trace((p) => p.rx, downColour);
    trace((p) => p.tx, upColour);
  }

  @override
  bool shouldRepaint(_ThroughputPainter old) => true;
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------

const _needsKey =
    'Needs a UniFi API key — Network → Settings → Control Plane → Integrations.';

final unifiHealthWidgetType = DashboardWidgetType(
  type: 'unifi_health',
  name: 'Network health',
  description:
      'Whether the internet is up, current WAN speeds, client count, and any '
      'device offline or needing firmware. $_needsKey',
  glyph: '🛜',
  defaultWidth: 4,
  defaultHeight: 3,
  minWidth: 1,
  minHeight: 1,
  preview: const [
    PreviewLine('Network healthy', scale: 0.16, accent: true),
    PreviewLine('↓ 24.1 Mb/s   ↑ 1.2 Mb/s', scale: 0.13),
    PreviewLine('30 clients · CPU 34% · Mem 72%', scale: 0.10, muted: true),
  ],
  fitsItself: true,
  build: (context, w) => UnifiHealthWidget(w: w),
);

final unifiPresenceWidgetType = DashboardWidgetType(
  type: 'unifi_presence',
  name: "Who's home",
  description:
      'Which devices are on the network right now. Presence on your own WiFi '
      '— not a location. $_needsKey',
  glyph: '🏠',
  defaultWidth: 3,
  defaultHeight: 4,
  minWidth: 1,
  minHeight: 1,
  options: const [
    WidgetOption(
      key: 'watch',
      label: 'Only these, comma separated',
      kind: OptionKind.text,
      defaultValue: '',
      help:
          'Part of a device name, or a MAC address. Leave empty to list '
          'everything. Anything named here but absent is shown greyed out, so '
          'the list keeps its shape.',
    ),
    WidgetOption(
      key: 'wirelessOnly',
      label: 'Wireless clients only',
      kind: OptionKind.boolean,
      defaultValue: true,
      help: 'People carry phones; servers and TVs are wired and always here.',
    ),
  ],
  preview: const [
    PreviewLine('● Vincent’s phone   for 4h', scale: 0.13, px: 16),
    PreviewLine('● Jo’s watch   for 2h', scale: 0.13, px: 16),
    PreviewLine('○ Guest phone   away', scale: 0.13, muted: true, px: 16),
  ],
  build: (context, w) => UnifiPresenceWidget(w: w),
);

final unifiDevicesWidgetType = DashboardWidgetType(
  type: 'unifi_devices',
  name: 'UniFi devices',
  description:
      'Your router, switches and access points with model, firmware and '
      'uptime, and a marker against anything with an update. $_needsKey',
  glyph: '📡',
  defaultWidth: 4,
  defaultHeight: 3,
  minWidth: 1,
  minHeight: 1,
  preview: const [
    PreviewLine('Dream Router 7', scale: 0.14),
    PreviewLine('UDR7 · 5.1.19 · up 57d', scale: 0.10, muted: true),
    PreviewLine('USW Flex 2.5G 5', scale: 0.14),
  ],
  fitsItself: true,
  build: (context, w) => UnifiDevicesWidget(w: w),
);

final unifiClientsWidgetType = DashboardWidgetType(
  type: 'unifi_clients',
  name: 'Network clients',
  description:
      'Everything connected, newest first, and which device each is connected '
      'through. The API reports no signal strength, so none is shown. '
      '$_needsKey',
  glyph: '🔌',
  defaultWidth: 4,
  defaultHeight: 4,
  minWidth: 1,
  minHeight: 1,
  preview: const [
    PreviewLine('Vincents-Mini        Dream Router 7', scale: 0.11, px: 14),
    PreviewLine('Hisense Vision       USW Flex 2.5G', scale: 0.11, px: 14),
    PreviewLine(
      'KP303                Dream Router 7',
      scale: 0.11,
      muted: true,
      px: 14,
    ),
  ],
  build: (context, w) => UnifiClientsWidget(w: w),
);

final unifiThroughputWidgetType = DashboardWidgetType(
  type: 'unifi_throughput',
  name: 'WAN throughput',
  description:
      'Live up and down rates on the internet connection, graphed over about '
      'the chosen window. $_needsKey',
  glyph: '📈',
  defaultWidth: 4,
  defaultHeight: 3,
  minWidth: 1,
  minHeight: 1,
  options: const [
    WidgetOption(
      key: 'window',
      label: 'Show',
      kind: OptionKind.choice,
      defaultValue: '1h',
      choices: {
        '5m': 'Last 5 minutes',
        '15m': 'Last 15 minutes',
        '1h': 'Last hour',
        '6h': 'Last 6 hours',
        '24h': 'Last 24 hours',
      },
      help:
          'Ten minutes and under is drawn from the per-second samples and '
          'moves as you watch. Longer spans use per-minute peaks. How far back '
          'history is kept at all is set in Settings → UniFi.',
    ),
    WidgetOption(
      key: 'showVolume',
      label: 'Show total moved',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
  ],
  preview: const [
    PreviewLine('↓ 24.1 Mb/s      ↑ 1.2 Mb/s', scale: 0.14, accent: true),
    PreviewLine('▁▂▅▇▆▃▂▁▂▄▆▇▅▂▁', scale: 0.20, centre: true),
  ],
  fitsItself: true,
  build: (context, w) => UnifiThroughputWidget(w: w),
);

// ---------------------------------------------------------------------------
// 6. The console's own ISP speed test
// ---------------------------------------------------------------------------

/// The result of the router's built-in speed test.
///
/// Distinct from the Ookla widget, and worth having both: this one is what
/// your line achieved when the router tested itself, unaffected by whatever
/// the Pi's own WiFi or USB adapter were doing at the time. The Ookla widget
/// measures the path to the panel; this measures the path to the internet.
class UnifiIspWidget extends StatelessWidget {
  const UnifiIspWidget({super.key, required this.w});
  final DashboardWidgetContext w;

  @override
  Widget build(BuildContext context) {
    final t = w.theme;
    final unifi = context.watch<UnifiService>();
    final isp = unifi.ispTest;
    if (isp == null || !isp.hasResult) {
      return Center(
        child: Text(
          unifi.hasContent
              ? 'The router has not run a speed test yet'
              : 'Reading the network…',
          textAlign: TextAlign.center,
          style: TextStyle(color: t.textSecondary, fontSize: 14),
        ),
      );
    }

    final age = isp.age;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Icon(
              isp.ok ? Icons.speed : Icons.warning_amber,
              size: 20,
              color: isp.ok ? t.accent : Colors.orangeAccent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'ISP speed test',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _Stat(
                theme: t,
                label: 'Down',
                value: isp.downMbps == null
                    ? '—'
                    : '${isp.downMbps!.toStringAsFixed(0)} Mb/s',
                colour: t.accent,
              ),
            ),
            Expanded(
              child: _Stat(
                theme: t,
                label: 'Up',
                value: isp.upMbps == null
                    ? '—'
                    : '${isp.upMbps!.toStringAsFixed(0)} Mb/s',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _Stat(
                theme: t,
                label: 'Ping',
                value: isp.pingMs == null
                    ? '—'
                    : '${isp.pingMs!.toStringAsFixed(0)} ms',
                scale: 0.8,
              ),
            ),
            Expanded(
              child: _Stat(
                theme: t,
                label: 'Tested',
                // Age rather than a timestamp: "3h ago" answers the question
                // "is this still true", which a clock time does not.
                value: age == null ? '—' : '${formatUptime(age)} ago',
                scale: 0.8,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

final unifiIspWidgetType = DashboardWidgetType(
  type: 'unifi_isp',
  name: 'ISP speed test',
  description:
      "The router's own built-in speed test — what the line achieved, "
      'measured by the router rather than by this panel. Read only: the '
      'console runs it on its own schedule and cannot be asked to run one '
      'with an API key. $_needsKey',
  glyph: '🚀',
  defaultWidth: 3,
  defaultHeight: 2,
  minWidth: 1,
  minHeight: 1,
  preview: const [
    PreviewLine('ISP speed test', scale: 0.14),
    PreviewLine('↓ 941 Mb/s   ↑ 93 Mb/s', scale: 0.16, accent: true),
    PreviewLine('18 ms · tested 3h ago', scale: 0.10, muted: true),
  ],
  build: (context, w) => UnifiIspWidget(w: w),
);
