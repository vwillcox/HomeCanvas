import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/widgets.dart';

/// The installer offers the widgets and themes from
/// deploy/installer/catalogue.json, since it runs before there is an app to
/// ask. This keeps that file the app's own list. When it fails, write the
/// file again from the app:
///
///   UPDATE_INSTALLER_CATALOGUE=1 flutter test test/installer_catalogue_test.dart
void main() {
  test('the installer\'s catalogue is the app\'s widgets and themes', () {
    registerBuiltInWidgets();
    final categories = [
      WidgetCategory.timeAndDay,
      WidgetCategory.weather,
      WidgetCategory.photosAndMedia,
      WidgetCategory.house,
      WidgetCategory.gettingOut,
      WidgetCategory.reference,
      WidgetCategory.network,
      WidgetCategory.unifi,
      WidgetCategory.homey,
      WidgetCategory.homeLab,
      WidgetCategory.other,
    ];
    final widgets =
        WidgetRegistry.all
            .where((t) => t.category != WidgetCategory.custom)
            .toList()
          ..sort((a, b) => a.type.compareTo(b.type));
    final catalogue = {
      'about':
          'Written by test/installer_catalogue_test.dart from the app. '
          'Do not edit by hand.',
      'categories': categories,
      'widgets': [
        for (final t in widgets)
          {
            'type': t.type,
            'name': t.name,
            'description': t.description,
            'category': t.category,
            'width': t.defaultWidth,
            'height': t.defaultHeight,
          },
      ],
      'themes': [
        for (final t in kBuiltInThemes)
          {
            for (final e in t.toJson().entries)
              if (const {
                'id', 'name', 'style', 'background', 'surface', 'border', //
                'textPrimary', 'textSecondary', 'accent', 'palette', 'glow',
              }.contains(e.key))
                e.key: e.value,
          },
      ],
    };
    final text = '${const JsonEncoder.withIndent('  ').convert(catalogue)}\n';
    final file = File('deploy/installer/catalogue.json');
    if (Platform.environment['UPDATE_INSTALLER_CATALOGUE'] == '1') {
      file.writeAsStringSync(text);
    }
    expect(
      file.existsSync() ? file.readAsStringSync() : '',
      text,
      reason:
          'deploy/installer/catalogue.json is out of date: run '
          'UPDATE_INSTALLER_CATALOGUE=1 flutter test '
          'test/installer_catalogue_test.dart',
    );
  });
}
