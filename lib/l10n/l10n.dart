import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';

/// A language the panel can be shown in.
@immutable
class Language {
  const Language(this.code, this.name, this.english, {this.aiCreated = false});

  /// "en-GB", "fr" — also the name of its pack, `assets/l10n/<code>.arb`.
  final String code;

  /// What it calls itself: "Français".
  final String name;

  /// What it is called in English: "French".
  final String english;

  /// Translated by an AI and not yet checked by a person. Shown beside its
  /// name wherever a language is chosen, and recorded in its pack.
  final bool aiCreated;

  /// For Flutter's own widgets and for plural rules: "en_GB", "nb".
  String get intlCode => code.replaceAll('-', '_');

  Locale get locale {
    final parts = code.split('-');
    return parts.length > 1 ? Locale(parts[0], parts[1]) : Locale(parts[0]);
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'name': name,
    'english': english,
    'aiCreated': aiCreated,
  };
}

/// Every language on offer. British English is the one the app is written
/// in; every other is a pack of translations over it.
const kLanguages = [
  Language('en-GB', 'English (UK)', 'English (UK)'),
  Language('en-US', 'English (US)', 'English (US)', aiCreated: true),
  Language('fr', 'Français', 'French', aiCreated: true),
  Language('de', 'Deutsch', 'German', aiCreated: true),
  Language('es', 'Español', 'Spanish', aiCreated: true),
  Language('it', 'Italiano', 'Italian', aiCreated: true),
  Language('nl', 'Nederlands', 'Dutch', aiCreated: true),
  Language('pt', 'Português', 'Portuguese', aiCreated: true),
  Language('pl', 'Polski', 'Polish', aiCreated: true),
  Language('sv', 'Svenska', 'Swedish', aiCreated: true),
  Language('nb', 'Norsk bokmål', 'Norwegian', aiCreated: true),
  Language('da', 'Dansk', 'Danish', aiCreated: true),
  Language('cy', 'Cymraeg', 'Welsh', aiCreated: true),
  Language('ga', 'Gaeilge', 'Irish', aiCreated: true),
];

const kSourceLanguage = 'en-GB';

/// The words the panel shows, in the language chosen for it.
///
/// Every string is written in the code in British English, with a key:
/// `tr('settings.title', 'Settings')`. A pack supplies the same keys in
/// another language; anything it lacks falls back to the British text, so a
/// half-finished translation shows English rather than blanks.
///
/// Strings may carry ICU-style placeholders — `{name}` — and plurals:
/// `{count, plural, one{# share} other{# shares}}`, with each language's own
/// plural forms (Polish has "few" and "many", Welsh and Irish more).
class L10n extends ChangeNotifier {
  L10n._();

  /// The one the whole app reads through [tr].
  static final L10n instance = L10n._();

  Language _language = kLanguages.first;
  Map<String, String> _strings = const {};

  Language get language => _language;
  String get code => _language.code;

  /// Every translated string in the current language, by key — for the
  /// browser editor, which translates itself from the same packs.
  Map<String, String> get strings => _strings;

  /// Switches to [code], or to British English if there is no such pack.
  Future<void> use(String code, {AssetBundle? bundle}) async {
    final language = kLanguages.firstWhere(
      (l) => l.code == code,
      orElse: () => kLanguages.first,
    );
    var strings = const <String, String>{};
    if (language.code != kSourceLanguage) {
      try {
        final raw = await (bundle ?? rootBundle).loadString(
          'assets/l10n/${language.code}.arb',
        );
        strings = parsePack(raw);
      } catch (e) {
        debugPrint('L10n: no pack for ${language.code}: $e');
      }
    }
    _language = language;
    _strings = strings;
    notifyListeners();
  }

  /// Uses [strings] as the pack for [code] — for tests.
  @visibleForTesting
  void debugUse(String code, Map<String, String> strings) {
    _language = kLanguages.firstWhere(
      (l) => l.code == code,
      orElse: () => Language(code, code, code),
    );
    _strings = strings;
    notifyListeners();
  }

  /// [english] in the current language, by [key], with [args] filled in.
  String t(String key, String english, [Map<String, Object?> args = const {}]) =>
      format(_strings[key] ?? english, args, locale: _language.intlCode);

  /// The translation of [key], or null where the pack has none — for text
  /// whose British original lives somewhere else, like a widget's settings.
  String? lookup(String key) => _strings[key];

  /// The strings of an ARB pack: every key not starting with "@".
  static Map<String, String> parsePack(String raw) {
    final json = jsonDecode(raw);
    if (json is! Map) return const {};
    return {
      for (final e in json.entries)
        if (e.key is String && !(e.key as String).startsWith('@') && e.value is String)
          e.key as String: e.value as String,
    };
  }
}

/// [english], translated by [key] into the panel's language.
String tr(String key, String english, [Map<String, Object?> args = const {}]) =>
    L10n.instance.t(key, english, args);

/// Fills in an ICU-style [pattern]: `{name}` from [args], and
/// `{n, plural, =0{…} one{…} few{…} other{…}}` by [locale]'s plural rules,
/// with `#` inside standing for the number. Anything it can't make sense of
/// is left as written rather than thrown.
String format(
  String pattern,
  Map<String, Object?> args, {
  String locale = 'en_GB',
}) {
  if (!pattern.contains('{')) return pattern;
  final out = StringBuffer();
  var i = 0;
  while (i < pattern.length) {
    final open = pattern.indexOf('{', i);
    if (open < 0) {
      out.write(pattern.substring(i));
      break;
    }
    out.write(pattern.substring(i, open));
    final close = _matching(pattern, open);
    if (close < 0) {
      out.write(pattern.substring(open));
      break;
    }
    out.write(_argument(pattern.substring(open + 1, close), args, locale));
    i = close + 1;
  }
  return out.toString();
}

/// The index of the brace closing the one at [open], or -1.
int _matching(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    if (s[i] == '{') depth++;
    if (s[i] == '}' && --depth == 0) return i;
  }
  return -1;
}

String _argument(String body, Map<String, Object?> args, String locale) {
  final comma = body.indexOf(',');
  if (comma < 0) {
    final name = body.trim();
    return args.containsKey(name) ? '${args[name]}' : '{$body}';
  }
  final name = body.substring(0, comma).trim();
  final rest = body.substring(comma + 1);
  final comma2 = rest.indexOf(',');
  if (comma2 < 0) return '{$body}';
  final kind = rest.substring(0, comma2).trim();
  final cases = _cases(rest.substring(comma2 + 1));
  final value = args[name];

  String pick(String? chosen) =>
      format(chosen ?? cases['other'] ?? '', args, locale: locale);

  if (kind == 'plural') {
    final n = value is num ? value : num.tryParse('$value');
    if (n == null) return pick(null);
    final exact = cases['=${n is int || n == n.roundToDouble() ? n.round() : n}'];
    final chosen = exact ??
        Intl.pluralLogic<String?>(
          n,
          locale: locale,
          zero: cases['zero'],
          one: cases['one'],
          two: cases['two'],
          few: cases['few'],
          many: cases['many'],
          other: cases['other'],
        );
    // In the language's own style: 5,881 in English, 5.881 in German.
    String shown;
    try {
      shown = NumberFormat.decimalPattern(locale).format(n);
    } catch (_) {
      shown = n == n.roundToDouble() ? '${n.round()}' : '$n';
    }
    return pick(chosen).replaceAll('#', shown);
  }
  if (kind == 'select') return pick(cases['$value']);
  return '{$body}';
}

/// "one{# share} other{# shares}" → {one: "# share", other: "# shares"}.
Map<String, String> _cases(String s) {
  final out = <String, String>{};
  var i = 0;
  while (i < s.length) {
    final open = s.indexOf('{', i);
    if (open < 0) break;
    final close = _matching(s, open);
    if (close < 0) break;
    out[s.substring(i, open).trim()] = s.substring(open + 1, close);
    i = close + 1;
  }
  return out;
}

/// Asks every widget on screen to build again — after the language changes,
/// so text read through [tr] is read afresh. Nothing is remounted: screens
/// stay open and state is kept.
void rebuildEverything() {
  void mark(Element e) {
    e.markNeedsBuild();
    e.visitChildren(mark);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(mark);
}

/// The locale for Flutter's own widgets: [code]'s if Flutter translates
/// them, and British English if not.
Locale materialLocale(String code) {
  final language = kLanguages.firstWhere(
    (l) => l.code == code,
    orElse: () => kLanguages.first,
  );
  return GlobalMaterialLocalizations.delegate.isSupported(language.locale)
      ? language.locale
      : kLanguages.first.locale;
}
