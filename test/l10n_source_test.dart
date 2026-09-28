import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/dashboard/dashboard_fonts.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/widgets.dart';
import 'package:home_canvas/l10n/l10n.dart';

/// `l10n/en-GB.arb` is every string the app shows, by key, in British
/// English — the file every language pack translates. It is written from the
/// code, never by hand:
///
///     L10N_WRITE=1 flutter test test/l10n_source_test.dart
///
/// Without L10N_WRITE this checks it is up to date, and that every pack in
/// `assets/l10n/` only has keys the source has, with the same placeholders.
void main() {
  setUpAll(registerBuiltInWidgets);

  test('the source pack lists every string in the app', () {
    final source = sourceStrings();
    final file = File('l10n/en-GB.arb');
    final written = const JsonEncoder.withIndent('  ').convert({
      '@@locale': 'en-GB',
      '@@x-source': 'Written from the code by test/l10n_source_test.dart — '
          'do not edit by hand.',
      ...source,
    });
    if (Platform.environment['L10N_WRITE'] == '1') {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('$written\n');
    }
    expect(
      file.existsSync() ? file.readAsStringSync().trim() : '',
      written.trim(),
      reason: 'l10n/en-GB.arb is out of date. Write it again with '
          'L10N_WRITE=1 flutter test test/l10n_source_test.dart',
    );
  });

  test('every pack translates keys the app has, placeholders intact', () {
    final source = sourceStrings();
    for (final f in Directory('assets/l10n').listSync().whereType<File>()) {
      if (!f.path.endsWith('.arb')) continue;
      final pack = L10n.parsePack(f.readAsStringSync());
      final json = jsonDecode(f.readAsStringSync()) as Map;
      expect(json['@@x-ai-created'], isNotNull,
          reason: '${f.path} must say whether an AI created it');
      for (final e in pack.entries) {
        expect(source, contains(e.key), reason: '${f.path}: ${e.key} is not in the app');
        final english = source[e.key];
        if (english == null) continue;
        expect(
          placeholders(e.value),
          placeholders(english),
          reason: '${f.path}: ${e.key} must keep the placeholders of "$english"',
        );
      }
    }
  });
}

/// The names in a string's placeholders: {name}, {count, plural, …}.
Set<String> placeholders(String s) => {
  for (final m in RegExp(r'\{\s*(\w+)\s*[,}]').allMatches(s)) m[1]!,
};

Map<String, String> sourceStrings() {
  final out = <String, String>{};
  void add(String key, String english, String where) {
    final had = out[key];
    if (had != null && had != english) {
      fail('$key is "$had" in one place and "$english" in $where');
    }
    out[key] = english;
  }

  // Widgets' names, descriptions and settings, and the palette's groups.
  for (final t in WidgetRegistry.all) {
    for (final (key, english) in t.texts()) {
      add(key, english, 'widget ${t.type}');
    }
  }
  for (final f in kDashboardFonts) {
    for (final (key, english) in f.texts()) {
      add(key, english, 'font ${f.family}');
    }
  }
  for (final c in WidgetCategory.order) {
    add('category.${c.toLowerCase()}', c, 'WidgetCategory');
  }

  // tr('key', 'British', …) in the Dart code, with adjacent literals joined.
  final call = RegExp(
    r"""\btr\(\s*'([\w.\-]+)'\s*,\s*((?:(?:'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")\s*)+)""",
  );
  final literal = RegExp(
    r"'((?:[^'\\]|\\.)*)'" '|' r'"((?:[^"\\]|\\.)*)"',
  );
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    // Comments explain tr() with examples; they are not strings to show.
    final code = f
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    for (final m in call.allMatches(code)) {
      final english = literal
          .allMatches(m[2]!)
          .map((l) => _unescape(l[1] ?? l[2]!))
          .join();
      add(m[1]!, english, f.path);
    }
  }

  // The web pages: data-t="key">British< and t("key", "British").
  final marked = RegExp(r'<\w[^<>]*\sdata-t="([\w.\-]+)"[^<>]*>([^<]*)<');
  // In either quote: t("key", "British") or t('key', 'British').
  final scripted = RegExp(
    r'''\bt\(\s*(["'])([\w.\-]+)\1\s*,\s*(["'])((?:(?!\3)[^\\]|\\.)*)\3''',
  );
  for (final f in Directory('assets/dashboard').listSync().whereType<File>()) {
    if (!f.path.endsWith('.html')) continue;
    final html = f.readAsStringSync();
    for (final m in marked.allMatches(html)) {
      add(m[1]!, m[2]!.replaceAll(RegExp(r'\s+'), ' ').trim(), f.path);
    }
    // Sentences with markup: data-t-html="key" on an element, its inner HTML
    // the British text, spaces run together as a browser shows them.
    final withMarkup = RegExp(
      r'<(\w+)\b[^<>]*\sdata-t-html="([\w.\-]+)"[^<>]*>(.*?)</\1>',
      dotAll: true,
    );
    for (final m in withMarkup.allMatches(html)) {
      add(m[2]!, m[3]!.replaceAll(RegExp(r'\s+'), ' ').trim(), f.path);
    }
    // Words in attributes: data-t-placeholder="key" beside placeholder="…",
    // and the same for title and aria-label.
    for (final tag in RegExp(r'<\w[^<>]*>').allMatches(html)) {
      final t = tag[0]!;
      for (final (marker, attr) in [
        ('data-t-placeholder', 'placeholder'),
        ('data-t-title', 'title'),
        ('data-t-aria', 'aria-label'),
      ]) {
        final key = RegExp('$marker="([\\w.\\-]+)"').firstMatch(t);
        final english = RegExp('\\s$attr="([^"]*)"').firstMatch(t);
        if (key != null && english != null) add(key[1]!, english[1]!, f.path);
      }
    }
    for (final m in scripted.allMatches(html)) {
      add(m[2]!, _unescape(m[4]!), f.path);
    }
  }
  return Map.fromEntries(
    out.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

String _unescape(String s) => s
    .replaceAll(r"\'", "'")
    .replaceAll(r'\"', '"')
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\$', r'$')
    .replaceAll(r'\\', r'\');
