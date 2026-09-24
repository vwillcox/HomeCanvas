import 'package:flutter_test/flutter_test.dart';

import 'package:immich_kiosk_pi/dashboard/widget_registry.dart';
import 'package:immich_kiosk_pi/dashboard/widgets/widgets.dart';

/// What the browser editor reads to draw its preview. It is the only
/// consumer, and it is JavaScript, so nothing else would notice a field
/// going missing.
void main() {
  setUpAll(registerBuiltInWidgets);

  test('every widget type tells the editor whether it fits itself', () {
    for (final t in WidgetRegistry.all) {
      expect(t.toJson()['fitsItself'], t.fitsItself, reason: t.type);
    }
    expect(WidgetRegistry.find('unifi_health')!.toJson()['fitsItself'], isTrue);
    expect(WidgetRegistry.find('news')!.toJson()['fitsItself'], isFalse);
  });

  test('a preview line gives a fixed size only when it has one', () {
    expect(
      const PreviewLine('a', scale: 0.1).toJson().containsKey('px'),
      isFalse,
    );
    expect(const PreviewLine('a', px: 15).toJson()['px'], 15);
  });

  test('fixed-size text previews at its real size', () {
    // Lists draw their text at fixed sizes on a tile of any height; sized as
    // a share of the tile instead, a tall news tile previewed its headlines
    // three times too big.
    for (final type in [
      'news',
      'calendar',
      'spotify',
      'unifi_presence',
      'unifi_clients',
    ]) {
      final lines = WidgetRegistry.find(type)!.preview;
      expect(lines, isNotEmpty, reason: type);
      for (final line in lines) {
        if (line.text.startsWith('▬') || line.text.startsWith('⏮')) continue;
        expect(line.px, isNotNull, reason: '$type: ${line.text}');
      }
    }
  });
}
