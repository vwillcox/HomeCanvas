import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../services/custom_widgets.dart';
import '../../widgets/pause_when_hidden.dart';
import '../../widgets/shown_timers.dart';
import '../custom_widget_spec.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';

/// The registry's entry for a widget installed from a file.
DashboardWidgetType customWidgetType(CustomWidgetSpec spec) =>
    DashboardWidgetType(
      type: spec.type,
      category: WidgetCategory.custom,
      name: spec.name,
      description: spec.description,
      glyph: spec.glyph,
      defaultWidth: spec.defaultWidth,
      defaultHeight: spec.defaultHeight,
      minWidth: math.min(spec.minWidth, spec.defaultWidth),
      minHeight: math.min(spec.minHeight, spec.defaultHeight),
      fitsItself: true,
      options: spec.options,
      preview: [
        for (final line in spec.preview.isEmpty ? [spec.name] : spec.preview)
          PreviewLine(line, scale: 0.14),
      ],
      build: (context, w) => CustomWidgetTile(spec: spec, w: w),
    );

/// A widget drawn from its description: fetches what the file says to, and
/// lays it out as the file says.
class CustomWidgetTile extends StatefulWidget {
  const CustomWidgetTile({super.key, required this.spec, required this.w});

  final CustomWidgetSpec spec;
  final DashboardWidgetContext w;

  @override
  State<CustomWidgetTile> createState() => _CustomWidgetTileState();
}

class _CustomWidgetTileState extends State<CustomWidgetTile>
    with PauseWhenHidden, ShownTimers {
  /// The settings, with the file's defaults where one has not been set.
  Map<String, dynamic> get _options => {
    for (final o in widget.spec.options) o.key: o.defaultValue,
    ...widget.w.config.options,
  };

  /// Where to fetch from, with the settings filled in.
  String? get _url {
    final url = widget.spec.url;
    return url == null
        ? null
        : customFill(url, options: _options, encode: true);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    // The service decides whether it is time; this only gives it the chance.
    everyWhileShown(const Duration(seconds: 15), _sync);
  }

  @override
  void didUpdateWidget(covariant CustomWidgetTile old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final url = _url;
    if (!mounted || url == null) return;
    final options = _options;
    unawaited(
      context.read<CustomWidgets>().ensure(
        url,
        headers: {
          for (final h in widget.spec.headers.entries)
            h.key: customFill(h.value, options: options).replaceAll('—', ''),
        },
        every: widget.spec.every,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final spec = widget.spec;
    final url = _url;
    final answer = url == null
        ? null
        : context.watch<CustomWidgets>().answer(url);
    if (url != null && answer?.data == null) {
      return TileMessage(
        answer?.error ?? tr('widget.custom.fetching', 'Fetching…'),
        theme: t,
      );
    }
    final data = answer?.data;
    final options = _options;
    String fill(String template, [Object? item]) =>
        customFill(template, data: data, options: options, item: item);

    switch (spec.show.layout) {
      case CustomLayout.value:
        return _Value(
          title: fill(spec.show.title),
          value: fill(spec.show.value),
          detail: fill(spec.show.detail),
          theme: t,
        );
      case CustomLayout.cards:
        return _Cards(
          cards: [
            for (final c in spec.show.cards)
              CustomCard(
                glyph: c.glyph,
                label: fill(c.label),
                value: fill(c.value),
              ),
          ],
          theme: t,
        );
      case CustomLayout.list:
        final items = customLookup(data, spec.show.items);
        final rows = items is List ? items : const [];
        if (rows.isEmpty) {
          return TileMessage(
            tr('widget.custom.nothing', 'Nothing to show.'),
            theme: t,
          );
        }
        return _Rows(
          rows: [
            for (final item in rows.take(spec.show.limit))
              (
                title: fill(spec.show.title, item),
                trailing: fill(spec.show.trailing, item),
              ),
          ],
          theme: t,
        );
    }
  }
}

/// A figure, with a line above it and one below.
class _Value extends StatelessWidget {
  const _Value({
    required this.title,
    required this.value,
    required this.detail,
    required this.theme,
  });

  final String title;
  final String value;
  final String detail;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) => FitCanvas(
    designHeight: 100,
    builder: (context, size) => Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty)
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: theme.textSecondary, fontSize: 13),
          ),
        // Shrinks to the tile's width rather than running off it.
        SizedBox(
          height: 46,
          width: size.width,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                color: theme.textPrimary,
                fontSize: 38,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        if (detail.isNotEmpty)
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: theme.textSecondary, fontSize: 12),
          ),
      ],
    ),
  );
}

/// Small cards, as many across and down as lets each be largest.
class _Cards extends StatelessWidget {
  const _Cards({required this.cards, required this.theme});

  final List<CustomCard> cards;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final grid = bestGrid(cards.length, c.biggest, cellAspect: 2.1);
      final gap = math.min(c.maxWidth, c.maxHeight) * 0.035;
      final cellW = (c.maxWidth - gap * (grid.columns - 1)) / grid.columns;
      final cellH = (c.maxHeight - gap * (grid.rows - 1)) / grid.rows;
      return Stack(
        children: [
          for (var i = 0; i < cards.length; i++)
            Positioned(
              left: (i % grid.columns) * (cellW + gap),
              top: (i ~/ grid.columns) * (cellH + gap),
              width: cellW,
              height: cellH,
              child: Container(
                decoration: theme.isLcars
                    ? lcarsCard(theme, lit: false)
                    : BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: theme.textSecondary.withValues(alpha: 0.07),
                      ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: FitCanvas(
                  designHeight: 54,
                  maxScale: 3,
                  builder: (context, size) => Row(
                    children: [
                      if (cards[i].glyph.isNotEmpty && size.width >= 70) ...[
                        Text(
                          cards[i].glyph,
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (cards[i].label.isNotEmpty)
                              Text(
                                cards[i].label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.textSecondary,
                                  fontSize: 10,
                                ),
                              ),
                            Text(
                              cards[i].value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// Lines of text, each with something at its end: as many as are
/// comfortable to read, and no part of one.
class _Rows extends StatelessWidget {
  const _Rows({required this.rows, required this.theme});

  final List<({String title, String trailing})> rows;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final row = (c.maxHeight / rows.length).clamp(24.0, 46.0);
      final fit = math.max(1, c.maxHeight ~/ row);
      final height = c.maxHeight / math.min(fit, rows.length);
      final size = math.min(row, height);
      return Column(
        children: [
          for (final r in rows.take(fit))
            SizedBox(
              height: height,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      r.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontSize: size * 0.42,
                      ),
                    ),
                  ),
                  if (r.trailing.isNotEmpty && c.maxWidth > 140) ...[
                    SizedBox(width: size * 0.3),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: c.maxWidth / 2),
                      child: Text(
                        r.trailing,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.textSecondary,
                          fontSize: size * 0.38,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      );
    },
  );
}
