import 'package:flutter/material.dart';

import '../dashboard_theme.dart';

/// Good, warning and bad, in shades that read on the theme's background.
///
/// The pastel versions that sit well on the dark themes all but vanish on
/// Paper's near-white, so a light theme gets deeper ones.
class StatusColours {
  const StatusColours._(this.good, this.warn, this.bad);

  final Color good;
  final Color warn;
  final Color bad;

  static StatusColours of(DashboardTheme t) {
    final light = t.background.first.computeLuminance() > 0.5;
    return light
        ? const StatusColours._(
            Color(0xFF1F8A4C),
            Color(0xFFB26A00),
            Color(0xFFC0392B),
          )
        : const StatusColours._(
            Color(0xFF7EE2A8),
            Color(0xFFFFD27A),
            Color(0xFFFF8A8A),
          );
  }
}

/// A small heading for a tile: an icon, a name, and something on the right —
/// usually a [StatusChip]. Sized by the caller, in whatever units it is
/// drawing in.
class TileLabel extends StatelessWidget {
  const TileLabel({
    super.key,
    required this.icon,
    required this.text,
    required this.theme,
    this.size = 14,
    this.trailing,
  });

  final IconData icon;
  final String text;
  final DashboardTheme theme;
  final double size;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: size * 1.2, color: theme.textSecondary),
        SizedBox(width: size * 0.45),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: theme.textSecondary, fontSize: size),
          ),
        ),
        // Shrinks rather than pushing the row off the edge of a narrow tile.
        if (trailing != null) ...[
          SizedBox(width: size * 0.5),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(fit: BoxFit.scaleDown, child: trailing),
            ),
          ),
        ],
      ],
    );
  }
}

/// A rounded pill of state: "Put out tonight", "All up".
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.text,
    required this.colour,
    this.size = 12,
  });

  final String text;
  final Color colour;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: size * 0.75,
        vertical: size * 0.2,
      ),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 2),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(
          color: colour,
          fontSize: size,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// A plain message for a tile with nothing to show yet, in the theme's
/// quieter colour — "Add your bins in the widget settings".
class TileMessage extends StatelessWidget {
  const TileMessage(this.text, {super.key, required this.theme});

  final String text;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.textSecondary,
              fontSize: 15,
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }
}
