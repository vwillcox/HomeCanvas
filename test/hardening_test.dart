import 'package:flutter_test/flutter_test.dart';
import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/widgets/widgets.dart';
import 'package:home_canvas/services/dashboard_service.dart';
import 'package:home_canvas/services/service_checks.dart';

void main() {
  setUpAll(registerBuiltInWidgets);

  const mask = DashboardService.secretMask;

  DashboardWidgetConfig railcam(String id, Map<String, dynamic> options) =>
      DashboardWidgetConfig.fromJson({
        'id': id,
        'type': 'railcam',
        'x': 0,
        'y': 0,
        'width': 2,
        'height': 2,
        'options': options,
      });

  group('secret settings never leave the panel', () {
    test('the editor is sent dots for a key, and the rest as it is', () {
      final saved = railcam('a', {'username': 'me', 'password': 'hunter2'});
      final json = DashboardService.maskSecrets({
        'themeId': 'midnight',
        'widgets': [saved.toJson()],
      });
      final options = (json['widgets'] as List).single['options'] as Map;
      expect(options['password'], mask);
      expect(options['username'], 'me');
      expect(json['themeId'], 'midnight');
      // The saved tile itself is untouched.
      expect(saved.options['password'], 'hunter2');
    });

    test('an empty key stays empty rather than looking set', () {
      final json = DashboardService.maskSecrets({
        'widgets': [
          railcam('a', {'password': ''}).toJson(),
        ],
      });
      expect((json['widgets'] as List).single['options']['password'], '');
    });

    test('dots sent back keep the key saved for that tile', () {
      final saved = [
        railcam('a', {'password': 'hunter2'}),
      ];
      final back = railcam('a', {'password': mask});
      DashboardService.keepSecrets(back, saved);
      expect(back.options['password'], 'hunter2');
    });

    test('a new key replaces the saved one', () {
      final back = railcam('a', {'password': 'new'});
      DashboardService.keepSecrets(back, [
        railcam('a', {'password': 'hunter2'}),
      ]);
      expect(back.options['password'], 'new');
    });

    test('another tile cannot borrow a key by sending the dots', () {
      final back = railcam('b', {'password': mask});
      DashboardService.keepSecrets(back, [
        railcam('a', {'password': 'hunter2'}),
      ]);
      expect(back.options.containsKey('password'), isFalse);
    });
  });

  group('ping is only ever given a host', () {
    for (final target in ['-f', '-i 0.002 10.0.0.1', '10.0.0.1 -c 9999']) {
      test('"$target" is refused without running ping', () async {
        final result = await const ServiceChecker().check(
          ServiceTarget(name: 'x', target: target),
        );
        expect(result.state, CheckState.down);
        expect(result.detail, 'not a host');
      });
    }
  });
}
