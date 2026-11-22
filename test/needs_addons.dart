/// For the tests that use the catalogue's widgets as their examples.
///
/// The widgets live in a repository of their own (vwillcox/HomeCanvas-
/// Widgets) and are built in from there. A checkout with none linked can
/// still run the suite: these tests say they were skipped rather than fail.
/// To link them, see "Working on add-ons" in
/// `lib/dashboard/widgets/README.md`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Whether the add-ons the app's own tests lean on are built in.
bool get addonsLinked =>
    const [
      'clock',
      'news',
      'weather',
      'timers',
      'unifi',
      'spotify',
      'homey',
    ].every(
      (id) => File(
        'lib/dashboard/widgets/custom/addons/$id/addon.json',
      ).existsSync(),
    );

/// First line of a test that needs them: true when it should stop there.
bool skippedWithoutAddons() {
  if (addonsLinked) return false;
  markTestSkipped(
    'Needs the add-ons built in: HOMECANVAS_ADDONS=<catalogue>/widgets '
    'scripts/widget-build.sh generate',
  );
  return true;
}
