import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/dashboard_service.dart';
import '../../services/shopping_service.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'tile_bits.dart';

/// The household shopping list. Tap an item to tick it off; add to it from
/// any phone at the editor's address followed by /list.
class ShoppingWidget extends StatelessWidget {
  const ShoppingWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  Widget build(BuildContext context) {
    final t = w.theme;
    final list = context.watch<ShoppingService>();
    final items = list.items;
    if (items.isEmpty) {
      final address = context.read<DashboardService>().editorAddress;
      return TileMessage(
        'Nothing to get. Add things from your phone at $address/list',
        theme: t,
      );
    }
    final status = StatusColours.of(t);

    return LayoutBuilder(
      builder: (context, c) {
        final labelH = (c.maxHeight * 0.1).clamp(18.0, 34.0);
        final listH = c.maxHeight - labelH * 1.4;
        // Rows share the height up to a comfortable size, and scroll beyond it
        // rather than shrinking into something too small to tap.
        final rowH = (listH / items.length).clamp(34.0, 64.0);
        final font = rowH * 0.44;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: labelH,
              child: TileLabel(
                icon: Icons.shopping_basket_outlined,
                text: 'Shopping',
                theme: t,
                size: labelH * 0.6,
                trailing: StatusChip(
                  text: list.toGet == 0 ? 'All got' : '${list.toGet} to get',
                  colour: list.toGet == 0 ? status.good : t.accent,
                  size: labelH * 0.5,
                ),
              ),
            ),
            SizedBox(height: labelH * 0.4),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                physics: rowH * items.length > listH
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                children: [
                  for (final item in items)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => list.toggle(item.id),
                      child: SizedBox(
                        height: rowH,
                        child: Row(
                          children: [
                            _Check(
                              done: item.done,
                              size: font * 1.15,
                              theme: t,
                            ),
                            SizedBox(width: font * 0.6),
                            Expanded(
                              child: Text(
                                item.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: item.done
                                      ? t.textSecondary.withValues(alpha: 0.6)
                                      : t.textPrimary,
                                  fontSize: font,
                                  decoration: item.done
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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

class _Check extends StatelessWidget {
  const _Check({required this.done, required this.size, required this.theme});

  final bool done;
  final double size;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    final accent = theme.accent;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? accent : Colors.transparent,
        border: Border.all(
          color: done ? accent : theme.textSecondary,
          width: size * 0.1,
        ),
      ),
      child: done
          ? Icon(
              Icons.check_rounded,
              size: size * 0.75,
              color: theme.background.first,
            )
          : null,
    );
  }
}

final shoppingWidgetType = DashboardWidgetType(
  type: 'shopping',
  category: WidgetCategory.house,
  name: 'Shopping list',
  description:
      'One list the whole house shares. Add to it from any phone on '
      'the home network at the editor’s address followed by /list; tap an '
      'item on the panel to tick it off. Ticked items clear themselves after '
      'half a day.',
  glyph: '🧺',
  defaultWidth: 4,
  defaultHeight: 4,
  minWidth: 2,
  minHeight: 2,
  fitsItself: true,
  preview: const [
    PreviewLine('○ Milk', scale: 0.13),
    PreviewLine('○ Bread', scale: 0.13),
    PreviewLine('● Coffee beans', scale: 0.13, muted: true),
  ],
  build: (context, w) => ShoppingWidget(w: w),
);
