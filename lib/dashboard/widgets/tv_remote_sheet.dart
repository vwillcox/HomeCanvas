import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../screens/dashboard_screen.dart' show DashboardTile;
import '../dashboard_model.dart';
import '../dashboard_theme.dart';

bool _open = false;

/// Opens the TV remote over whatever is on screen, as large as the panel.
///
/// The TV remote widget itself, not another remote: the same buttons in the
/// same places as on the dashboard, with the row of inputs, drawn large
/// enough to use from an arm's length without looking for it. Asked for
/// aloud — "open the remote" — and put away with the close button, a tap
/// beside it, or "close".
///
/// Asked for again while it is open, it stays as it is.
Future<void> showTvRemote(
  BuildContext context,
  DashboardTheme theme,
  DashboardSettings settings,
) async {
  if (_open) return;
  _open = true;
  // The dashboard's own remote, if it has one, so its settings carry over.
  final placed = settings.widgets.where((w) => w.type == 'tv').firstOrNull;
  final tile = DashboardWidgetConfig(
    id: 'tv-remote-sheet',
    type: 'tv',
    x: 0,
    y: 0,
    width: DashboardGrid.columns,
    height: DashboardGrid.rows,
    fontFamily: placed?.fontFamily ?? '',
    // The pad, whatever a small tile on the dashboard does without, and
    // the inputs: there is room for both here.
    options: {...?placed?.options, 'compact': false, 'inputs': true},
  );
  try {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: tr('widget.tv.closeTheRemote', 'Close the remote'),
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, _, _) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Stack(
            children: [
              Positioned.fill(
                child: LayoutBuilder(
                  // Laid out at half the size and drawn at twice it: the
                  // widget's buttons and words are sized for a tile.
                  builder: (context, c) => FittedBox(
                    child: SizedBox(
                      width: c.maxWidth / 2,
                      height: c.maxHeight / 2,
                      // On the theme's own background: a tile may be glass,
                      // and whatever was on screen would show through it.
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.background.first,
                          borderRadius: BorderRadius.circular(
                            settings.radiusOver(theme.cornerRadius),
                          ),
                        ),
                        child: DashboardTile(
                          config: tile,
                          theme: theme,
                          settings: settings,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                // On a disc of its own: whatever the theme draws in that
                // corner, the way out can be seen against it.
                child: Material(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: const CircleBorder(),
                  child: IconButton(
                    iconSize: 40,
                    color: Colors.white,
                    tooltip: tr('widget.tv.closeTheRemote', 'Close the remote'),
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      ),
    );
  } finally {
    _open = false;
  }
}
