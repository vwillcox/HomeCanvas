import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Small pieces of the photo browser's look, shared by the home screen and the
/// album view so the two read as one app.
///
/// "Glass" here is the frosted, translucent surface current phone and desktop
/// UIs use for controls that float over content: a blur of whatever is behind,
/// a faint white fill, and a hairline edge. It keeps controls legible over any
/// photograph without a solid bar cutting across the top of the screen.

/// A frosted, rounded surface.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 999,
    this.padding = EdgeInsets.zero,
    this.blur = 18,
    this.tint = 0.08,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double blur;

  /// How much white to lay over the blur, 0–1.
  final double tint;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: tint),
            borderRadius: shape,
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// A round glass button for an icon. Sized for a thumb, not a cursor.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 60,
    this.colour,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final button = Glass(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: size * 0.46, color: colour ?? Colors.white),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// An icon button with no surface of its own, for use inside a [Glass] pill.
class PillIconButton extends StatelessWidget {
  const PillIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.colour,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, color: colour ?? Colors.white),
      iconSize: 30,
      style: IconButton.styleFrom(
        minimumSize: const Size(60, 60),
        padding: const EdgeInsets.all(12),
      ),
    );
  }
}

/// Shrinks its child slightly while a finger is on it.
///
/// The feedback a touchscreen gives for free on a phone and not at all on a
/// wall panel: without it a tap on a large photo tile feels like it missed
/// until the next screen appears.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.scale = 0.965});

  final Widget child;
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// A pill-shaped choice, for sort orders and the like.
class ChoicePill extends StatelessWidget {
  const ChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final a = accent ?? Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? Colors.white : Colors.white.withValues(alpha: 0.07),
        shape: StadiumBorder(
          side: BorderSide(
            color: selected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.14),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: a.withValues(alpha: 0.2),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? const Color(0xFF0B0C10) : Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A soft glow of colour behind a screen, so the background is not a flat
/// black slab. Drawn once; costs nothing while scrolling.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0B0C10),
        gradient: RadialGradient(
          center: const Alignment(-0.85, -1.1),
          radius: 1.4,
          colors: [accent.withValues(alpha: 0.16), const Color(0xFF0B0C10)],
          stops: const [0.0, 0.7],
        ),
      ),
    );
  }
}

// --- words for dates, without pulling in intl for two lists -----------------

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "Good morning" and so on, by the hour.
String greetingFor(DateTime t) {
  final h = t.hour;
  if (h >= 5 && h < 12) return 'Good morning';
  if (h >= 12 && h < 17) return 'Good afternoon';
  if (h >= 17 && h < 22) return 'Good evening';
  return 'Good night';
}

/// "Thursday 24 September".
String longDate(DateTime t) =>
    '${_weekdays[t.weekday - 1]} ${t.day} ${monthNames[t.month - 1]}';

/// "1,204" — thousands grouped, for counts that can run large.
String grouped(int n) {
  final s = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

/// "3 items", "1 item".
String plural(int n, String one, [String? many]) =>
    '${grouped(n)} ${n == 1 ? one : (many ?? '${one}s')}';
