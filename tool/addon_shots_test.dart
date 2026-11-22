// Draws the picture each add-on is listed with in the editor's Add-ons
// page: its tiles as the editor previews them, with their stand-in content,
// in the Glass theme's colours.
//
//   ADDONS_DIR=../HomeCanvas-Widgets/widgets ADDON_SHOTS=all \
//     flutter test tool/addon_shots_test.dart
//
// ADDON_SHOTS is `all`, or the names to draw, with commas between. Each is
// written to <ADDONS_DIR>/<name>/screenshot.png. The add-ons written in
// Dart must be built in first (HOMECANVAS_ADDONS=… scripts/widget-build.sh
// generate); the catalogue's own tools/shots.sh does both.
//
// A picture drawn from stand-in content has nobody's calendar or address in
// it, which a photograph of a panel would.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/dashboard/custom_widget_spec.dart';
import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/custom_widget.dart';
import 'package:home_canvas/dashboard/widgets/widgets.dart';

const _width = 640.0;
const _height = 400.0;

/// Fonts for what Inter has no glyph for: the emoji and symbols the
/// previews use. Wherever this machine keeps them.
const _fallbacks = {
  'Emoji': [
    '/usr/share/fonts/noto/NotoColorEmoji.ttf',
    '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf',
    '/usr/share/fonts/google-noto-color-emoji-fonts/NotoColorEmoji.ttf',
  ],
  'Symbols': [
    '/usr/share/fonts/noto/NotoSansSymbols-Regular.ttf',
    '/usr/share/fonts/truetype/noto/NotoSansSymbols-Regular.ttf',
  ],
  // Block elements: the bars of a chart drawn in text.
  'Blocks': [
    '/usr/share/fonts/TTF/DejaVuSans.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/noto/NotoSansMono-Regular.ttf',
  ],
  'Symbols2': [
    '/usr/share/fonts/noto/NotoSansSymbols2-Regular.ttf',
    '/usr/share/fonts/truetype/noto/NotoSansSymbols2-Regular.ttf',
  ],
};

void main() {
  final dir = Platform.environment['ADDONS_DIR'];
  final asked = Platform.environment['ADDON_SHOTS'] ?? '';

  testWidgets('draws the add-ons\' pictures', (tester) async {
    if (dir == null || asked.isEmpty) {
      markTestSkipped('Set ADDONS_DIR and ADDON_SHOTS: see the top of file.');
      return;
    }
    final fallback = <String>[];
    await tester.runAsync(() async {
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter.ttf'))).load();
      for (final e in _fallbacks.entries) {
        final file = e.value.map(File.new).where((f) => f.existsSync());
        if (file.isEmpty) continue;
        final bytes = file.first.readAsBytesSync();
        await (FontLoader(
          e.key,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        fallback.add(e.key);
      }
    });
    registerBuiltInWidgets();
    final theme = kBuiltInThemes.first;
    tester.view
      ..physicalSize = const Size(_width, _height)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final ids = asked == 'all'
        ? [
            for (final d in Directory(dir).listSync().whereType<Directory>())
              d.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
          ]
        : asked.split(',');
    ids.sort();
    for (final id in ids) {
      final folder = '$dir/$id';
      final manifest =
          jsonDecode(File('$folder/addon.json').readAsStringSync()) as Map;
      final types = <DashboardWidgetType>[];
      if (manifest['kind'] == 'json') {
        final file = Directory(folder).listSync().whereType<File>().firstWhere(
          (f) => f.path.endsWith('.json') && !f.path.endsWith('addon.json'),
        );
        types.add(
          customWidgetType(CustomWidgetSpec.parse(file.readAsStringSync())),
        );
      } else {
        for (final t in manifest['types'] as List) {
          final type = WidgetRegistry.find('$t');
          if (type == null) {
            fail('$id: "$t" is not built in. Build the add-ons in first.');
          }
          types.add(type);
        }
      }
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: _Picture(
            theme: theme,
            types: types.take(4).toList(),
            fallback: fallback,
          ),
        ),
      );
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final png = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1.5);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return data!.buffer.asUint8List();
      });
      File('$folder/screenshot.png').writeAsBytesSync(png!);
    }
  });
}

/// Up to four of an add-on's tiles on the Glass theme's background.
class _Picture extends StatelessWidget {
  const _Picture({
    required this.theme,
    required this.types,
    required this.fallback,
  });

  final DashboardTheme theme;
  final List<DashboardWidgetType> types;
  final List<String> fallback;

  @override
  Widget build(BuildContext context) {
    final columns = types.length == 1 ? 1 : 2;
    final rows = (types.length / columns).ceil();
    const gap = 14.0, edge = 28.0;
    final cellW = (_width - edge * 2 - gap * (columns - 1)) / columns;
    final cellH = (_height - edge * 2 - gap * (rows - 1)) / rows;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: DecoratedBox(
        decoration: BoxDecoration(color: theme.background.first),
        child: Padding(
          padding: const EdgeInsets.all(edge),
          child: Column(
            children: [
              for (var r = 0; r < rows; r++) ...[
                if (r > 0) const SizedBox(height: gap),
                Expanded(
                  child: Row(
                    children: [
                      for (var c = 0; c < columns; c++) ...[
                        if (c > 0) const SizedBox(width: gap),
                        Expanded(
                          child: r * columns + c < types.length
                              ? Center(
                                  child: _tile(
                                    types[r * columns + c],
                                    Size(cellW, cellH),
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
          ),
        ),
      ),
    );
  }

  /// One tile, the shape it is on the panel by default, as big as fits.
  Widget _tile(DashboardWidgetType type, Size room) {
    // A panel's cell is a little wider than it is tall.
    final shape = (type.defaultWidth * 1.17) / type.defaultHeight;
    var w = room.width, h = w / shape;
    if (h > room.height) {
      h = room.height;
      w = h * shape;
    }
    // A strip would be a sliver: let it be no thinner than this.
    h = math.max(h, math.min(room.height, 96));
    final lines = type.preview.isEmpty
        ? [PreviewLine(type.name, muted: true)]
        : type.preview;
    final list = lines.any((l) => l.px != null);
    final pad = h * 0.09;
    // Fixed sizes are for a tile on the panel, where a list has room to run
    // on. Here they are made as big as lets every line be read: the lines
    // filling most of the tile, none taller than a sixth of it.
    final fixed = [for (final l in lines) l.px ?? 0.0];
    final grow = fixed.every((px) => px == 0)
        ? 1.0
        : math.min(
            (h - pad * 2) * 0.8 / (fixed.reduce((a, b) => a + b) * 1.3),
            h / 6 / fixed.reduce(math.max),
          );
    String words(PreviewLine l) => l.text
        .replaceAll('{time}', '10:08')
        .replaceAll('{date}', 'Sunday 22 November');
    TextStyle style(PreviewLine l, double shrink) => TextStyle(
      fontFamily: 'Inter',
      fontFamilyFallback: fallback,
      height: 1.3,
      fontWeight: l.muted ? FontWeight.w400 : FontWeight.w600,
      fontSize: (l.px != null ? l.px! * grow : l.scale * h) * shrink,
      color: l.accent
          ? theme.accent
          : l.muted
          ? theme.textSecondary
          : theme.textPrimary,
    );
    // Shrunk together until the widest line fits — to a point: past that
    // a long line fades out at the edge, as it does on the panel.
    var widest = 0.0, tall = 0.0;
    for (final l in lines) {
      final painter = TextPainter(
        text: TextSpan(text: words(l), style: style(l, 1)),
        textDirection: TextDirection.ltr,
      )..layout();
      widest = math.max(widest, painter.width);
      tall += painter.height;
      painter.dispose();
    }
    final shrink = math
        .min(1.0, math.min((w - pad * 2) / widest, (h - pad * 2) / tall))
        .clamp(0.55, 1.0);
    return Container(
      width: w,
      height: h,
      padding: EdgeInsets.all(pad),
      clipBehavior: Clip.hardEdge,
      alignment: list ? Alignment.topLeft : Alignment.centerLeft,
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final l in lines)
            Text(
              words(l),
              textAlign: l.centre ? TextAlign.center : TextAlign.left,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: style(l, shrink),
            ),
        ],
      ),
    );
  }
}
