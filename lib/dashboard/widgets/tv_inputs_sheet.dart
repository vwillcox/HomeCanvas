import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/tv_service.dart';
import '../../services/vidaa_client.dart' show TvSource;
import '../dashboard_theme.dart';

/// Pops up the television's inputs to pick from.
///
/// The inputs row on the remote is an option, and off by default, because a
/// dashboard tile rarely has the room for it. This is the version that fits
/// any tile: one button on the remote, and the choice made full size.
///
/// Closes itself once an input is picked — the point was to change it, and
/// the television is the confirmation — and after [autoClose] if left open.
Future<void> showTvInputs(
  BuildContext context,
  DashboardTheme theme, {
  Duration autoClose = const Duration(seconds: 45),
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close the inputs',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (context, _, _) =>
        TvInputsSheet(theme: theme, autoClose: autoClose),
    transitionBuilder: (context, animation, _, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return AnimatedBuilder(
        animation: curved,
        builder: (context, _) => BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: 10 * curved.value,
            sigmaY: 10 * curved.value,
          ),
          child: FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween(begin: 0.96, end: 1.0).animate(curved),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}

/// The list of inputs. Public so it can be tested on its own.
class TvInputsSheet extends StatefulWidget {
  const TvInputsSheet({
    super.key,
    required this.theme,
    this.autoClose = const Duration(seconds: 45),
  });

  final DashboardTheme theme;
  final Duration autoClose;

  @override
  State<TvInputsSheet> createState() => _TvInputsSheetState();
}

class _TvInputsSheetState extends State<TvInputsSheet> {
  Timer? _timer;
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.autoClose, _close);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _close() {
    if (mounted) Navigator.of(context).maybePop();
  }

  void _pick(TvService tv, TvSource s) {
    tv.changeSource(s.id);
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final tv = context.watch<TvService>();
    final sources = tv.sources;
    final screen = MediaQuery.sizeOf(context);

    return SafeArea(
      child: Center(
        child: GestureDetector(
          // Taps on the card itself must not reach the barrier behind it.
          onTap: () {},
          child: Container(
            width: math.min(screen.width * 0.9, 960),
            constraints: BoxConstraints(maxHeight: screen.height * 0.85),
            padding: const EdgeInsets.fromLTRB(32, 24, 24, 28),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                t.surface,
                t.background.first.withValues(alpha: 0.98),
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: t.border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 50,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.input, color: t.accent, size: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Switch input',
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 30,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      _RoundButton(
                        theme: t,
                        icon: Icons.close,
                        label: 'Close',
                        onPressed: _close,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (sources.isEmpty)
                    _Empty(
                      theme: t,
                      connected: tv.isConnected,
                      asked: _asked,
                      onAsk: () {
                        setState(() => _asked = true);
                        tv.refreshSources();
                      },
                    )
                  else
                    Flexible(
                      child: _Grid(
                        theme: t,
                        sources: sources,
                        onPick: (s) => _pick(tv, s),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.theme,
    required this.sources,
    required this.onPick,
  });

  final DashboardTheme theme;
  final List<TvSource> sources;
  final void Function(TvSource) onPick;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // Two or three across depending on the room, each a generous
        // rectangle: this is picked from the sofa end of the room, and the
        // television does not take kindly to being told twice.
        final columns = c.maxWidth > 760 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          itemCount: sources.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            mainAxisExtent: 112,
          ),
          itemBuilder: (context, i) => _InputTile(
            theme: theme,
            source: sources[i],
            onTap: () => onPick(sources[i]),
          ),
        );
      },
    );
  }
}

class _InputTile extends StatelessWidget {
  const _InputTile({
    required this.theme,
    required this.source,
    required this.onTap,
  });

  final DashboardTheme theme;
  final TvSource source;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final s = source;
    final active = s.isActive;
    final status = inputStatus(s);
    final dot = switch (status) {
      InputStatus.live => const Color(0xFF4ADE80),
      InputStatus.asleep => const Color(0xFFF59E0B),
      InputStatus.empty => t.textSecondary.withValues(alpha: 0.6),
    };

    return Semantics(
      button: true,
      selected: active,
      label: '${s.name}${s.deviceName.isEmpty ? '' : ', ${s.deviceName}'}'
          '${active ? ', showing now' : ''}',
      child: Material(
        color: active
            ? t.accent.withValues(alpha: 0.20)
            : t.textPrimary.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: active ? t.accent : t.textPrimary.withValues(alpha: 0.10),
            width: active ? 2.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                Icon(inputIcon(s), color: active ? t.accent : t.textPrimary,
                    size: 36),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                                color: dot, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              active
                                  ? 'Showing now'
                                  : inputSubtitle(s),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: active ? t.accent : t.textSecondary,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
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

class _Empty extends StatelessWidget {
  const _Empty({
    required this.theme,
    required this.connected,
    required this.asked,
    required this.onAsk,
  });

  final DashboardTheme theme;
  final bool connected;
  final bool asked;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final text = !connected
        ? 'The remote is not connected to the television, so it cannot list '
            'the inputs yet.'
        : asked
            ? 'Asked — the list will appear here as soon as the television '
                'answers.'
            : 'The television has not listed its inputs yet.';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: t.textSecondary, fontSize: 22),
          ),
          if (connected && !asked) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAsk,
              icon: const Icon(Icons.refresh, size: 26),
              label: const Text('Ask the television',
                  style: TextStyle(fontSize: 22)),
              style: FilledButton.styleFrom(
                backgroundColor: t.accent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              // Said up front because it looks like a fault otherwise: the
              // set runs its pairing check whenever it is asked for inputs.
              'It may flash a pairing code on screen while it answers — '
              'nothing needs entering.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: t.textSecondary.withValues(alpha: 0.8), fontSize: 17),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.theme,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final DashboardTheme theme;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: theme.textPrimary.withValues(alpha: 0.08),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 60,
            height: 60,
            child: Icon(icon, color: theme.textPrimary, size: 32),
          ),
        ),
      ),
    );
  }
}

// --- the decisions, kept apart so they can be tested ------------------------

/// Whether anything is on the end of an input.
enum InputStatus {
  /// Something plugged in and powered.
  live,

  /// The television remembers a device here but sees no signal — usually
  /// something switched off at the wall.
  asleep,

  /// Nothing known.
  empty,
}

InputStatus inputStatus(TvSource s) {
  if (s.hasSignal) return InputStatus.live;
  if (s.knownButAsleep) return InputStatus.asleep;
  return InputStatus.empty;
}

/// The line under an input's name: what is attached, or that nothing is.
String inputSubtitle(TvSource s) {
  final device = s.deviceName.trim();
  switch (inputStatus(s)) {
    case InputStatus.live:
      return device.isEmpty ? 'Signal' : device;
    case InputStatus.asleep:
      return '$device · off';
    case InputStatus.empty:
      return 'Nothing connected';
  }
}

/// An icon for an input, from its name.
///
/// VIDAA names its inputs plainly — "HDMI1", "AV", "TV" — so the name is
/// enough to tell a tuner from a socket from an app.
IconData inputIcon(TvSource s) {
  final n = s.name.toLowerCase();
  if (n.startsWith('hdmi')) return Icons.settings_input_hdmi;
  if (n == 'tv' || n.contains('antenna') || n.contains('dtv') ||
      n.contains('atv')) {
    return Icons.live_tv;
  }
  if (n.startsWith('av') || n.contains('component') || n.contains('scart')) {
    return Icons.settings_input_composite;
  }
  if (n.contains('usb') || n.contains('media')) return Icons.usb;
  return Icons.apps;
}
