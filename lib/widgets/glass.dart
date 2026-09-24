import 'dart:async';
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
    this.selected = false,
    this.selectedColour,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? colour;

  /// Lit: a soft disc of [selectedColour] behind the icon — "you are here".
  final bool selected;
  final Color? selectedColour;

  @override
  Widget build(BuildContext context) {
    final lit = selectedColour ?? Theme.of(context).colorScheme.primary;
    return Semantics(
      selected: selected,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, color: colour ?? Colors.white),
        iconSize: 30,
        style: IconButton.styleFrom(
          minimumSize: const Size(60, 60),
          padding: const EdgeInsets.all(12),
          backgroundColor: selected
              ? lit.withValues(alpha: 0.22)
              : Colors.transparent,
        ),
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

/// The top of every screen: a big title, and the controls in glass.
///
/// One widget so the home screen, albums, settings, the dashboard and the
/// rest cannot drift apart — the top bar is where a mismatch shows first.
///
/// Give it [onBack] for a round back button on the left; [actions] for icon
/// buttons, which are gathered into one frosted pill on the right; and
/// [trailing] for anything else there, such as a single highlighted button.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    this.title,
    this.titleWidget,
    this.subtitle,
    this.onBack,
    this.backIcon = Icons.arrow_back_rounded,
    this.backTooltip = 'Back',
    this.actions = const [],
    this.trailing,
    this.padding,
    this.iconColour,
  }) : assert(title != null || titleWidget != null);

  final String? title;

  /// In place of [title] and [subtitle], for a title that is more than text.
  final Widget? titleWidget;
  final String? subtitle;
  final VoidCallback? onBack;
  final IconData backIcon;
  final String backTooltip;
  final List<Widget> actions;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  /// The back button's colour. White unless a theme says otherwise.
  final Color? iconColour;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          padding ?? EdgeInsets.fromLTRB(onBack != null ? 28 : 40, 20, 28, 12),
      child: Row(
        children: [
          if (onBack != null) ...[
            GlassIconButton(
              icon: backIcon,
              tooltip: backTooltip,
              onPressed: onBack,
              colour: iconColour,
            ),
            const SizedBox(width: 24),
          ],
          Expanded(
            child:
                titleWidget ?? HeaderTitle(title: title!, subtitle: subtitle),
          ),
          if (trailing != null) ...[const SizedBox(width: 16), trailing!],
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 16),
            Glass(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: actions),
            ),
          ],
        ],
      ),
    );
  }
}

/// A screen's title and the line under it, in the header's type.
class HeaderTitle extends StatelessWidget {
  const HeaderTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.colour = Colors.white,
    this.secondary = Colors.white60,
  });

  final String title;
  final String? subtitle;

  /// White on the kiosk's own screens; the dashboard passes its theme's, so
  /// the bar stays readable on a light theme too.
  final Color colour;
  final Color secondary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 44,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
            height: 1.1,
            color: colour,
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 20, color: secondary),
          ),
        ],
      ],
    );
  }
}

/// "Good afternoon" over today's date and whatever [detail] adds.
///
/// Keeps its own one-minute timer, so the greeting turns over at noon and
/// the date at midnight without rebuilding the screen around it.
class GreetingTitle extends StatefulWidget {
  const GreetingTitle({
    super.key,
    this.detail,
    this.colour = Colors.white,
    this.secondary = Colors.white60,
  });

  final String? detail;
  final Color colour;
  final Color secondary;

  @override
  State<GreetingTitle> createState() => _GreetingTitleState();
}

class _GreetingTitleState extends State<GreetingTitle> {
  late final Timer _tick;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HeaderTitle(
    colour: widget.colour,
    secondary: widget.secondary,
    title: greetingFor(_now),
    subtitle: [
      longDate(_now),
      if (widget.detail != null) widget.detail!,
    ].join('  ·  '),
  );
}

/// The white, pill-shaped button used for a screen's one main action —
/// Slideshow, Try again, Save.
ButtonStyle whitePillButton() => FilledButton.styleFrom(
  backgroundColor: Colors.white,
  foregroundColor: const Color(0xFF0B0C10),
  shape: const StadiumBorder(),
  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
  textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
);

/// A titled group of rows on a glass card — settings, lists of options.
class GlassSection extends StatelessWidget {
  const GlassSection({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: Colors.white,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Material(
                type: MaterialType.transparency,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The background, header and body every full screen shares.
///
/// Screens pass their [header] and [body]; the ambient glow and the safe
/// area are handled here so no screen can forget them.
class ModernScaffold extends StatelessWidget {
  const ModernScaffold({
    super.key,
    required this.header,
    required this.body,
    this.overlays = const [],
  });

  final Widget header;
  final Widget body;

  /// Drawn over everything — the now-playing player, for one.
  final List<Widget> overlays;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C10),
      body: Stack(
        children: [
          Positioned.fill(child: AmbientBackground(accent: accent)),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                Expanded(child: body),
              ],
            ),
          ),
          ...overlays,
        ],
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
