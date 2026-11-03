import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'plain_text.dart';

/// A recipe, as the page it is on describes it to search engines.
///
/// Nearly every recipe site — BBC Good Food, Allrecipes, Serious Eats,
/// RecipeTin Eats, the blogs on WordPress's recipe plugins — puts the whole
/// recipe in the page as schema.org `Recipe` data, in a JSON-LD script: the
/// name, the ingredients one per line, the method step by step. That is
/// read here, so a recipe needs no scraping of anyone's page layout, and
/// none of the story above it.
///
/// Pure: a page in, a recipe out.
@immutable
class Recipe {
  const Recipe({
    required this.name,
    required this.ingredients,
    required this.steps,
    this.url,
    this.image,
    this.servings,
    this.yieldText,
    this.total,
    this.prep,
    this.cook,
    this.author,
  });

  final String name;

  /// One line each, as written: "100g plain flour".
  final List<String> ingredients;
  final List<RecipeStep> steps;

  /// Where it came from, and its picture.
  final String? url;
  final String? image;

  /// How many it serves, or makes, as written ([yieldText]) and as a number
  /// to scale from.
  final int? servings;
  final String? yieldText;

  final Duration? total;
  final Duration? prep;
  final Duration? cook;
  final String? author;

  /// The whole of the time it takes: as given, or prep and cooking added.
  Duration? get time =>
      total ??
      (prep == null && cook == null
          ? null
          : (prep ?? Duration.zero) + (cook ?? Duration.zero));

  /// The recipe in [html], or null when the page has none — or one with no
  /// method to cook from.
  static Recipe? fromHtml(String html, {String? url}) {
    for (final m in _ldJson.allMatches(html)) {
      final body = m[1]!.trim();
      if (body.isEmpty) continue;
      Object? json;
      try {
        json = jsonDecode(body);
      } catch (_) {
        // Some pages leave raw newlines inside strings; JSON says no, but
        // a browser would read it. Try once more without them.
        try {
          json = jsonDecode(body.replaceAll(RegExp(r'[\r\n\t]+'), ' '));
        } catch (_) {
          continue;
        }
      }
      final recipe = fromJsonLd(json, url: url);
      if (recipe != null) return recipe;
    }
    return null;
  }

  static final _ldJson = RegExp(
    r'''<script[^>]*type\s*=\s*["']?application/ld\+json["']?[^>]*>([\s\S]*?)</script>''',
    caseSensitive: false,
  );

  /// The first `Recipe` anywhere in [json] — on its own, in a list, or in
  /// an `@graph` with the page's other things.
  static Recipe? fromJsonLd(Object? json, {String? url}) {
    final found = _findRecipe(json, 0);
    if (found == null) return null;
    final name = _text(found['name'] ?? found['headline']);
    final ingredients = [
      for (final line in _list(
        found['recipeIngredient'] ?? found['ingredients'],
      ))
        if (cleanIngredient(_text(line)) case final s when s.isNotEmpty) s,
    ];
    final steps = _steps(found['recipeInstructions']);
    if (name.isEmpty || steps.isEmpty) return null;
    final yields = _list(found['recipeYield']).map(_text).toList();
    final (servings, yieldText) = _yield(yields);
    final pageUrl = _text(found['url']);
    return Recipe(
      name: name,
      ingredients: ingredients,
      steps: steps,
      url: url ?? (pageUrl.startsWith('http') ? pageUrl : null),
      image: _image(found['image']),
      servings: servings,
      yieldText: yieldText,
      total: isoDuration(_text(found['totalTime'])),
      prep: isoDuration(_text(found['prepTime'])),
      cook: isoDuration(_text(found['cookTime'])),
      author: _author(found['author']),
    );
  }

  static Map<String, dynamic>? _findRecipe(Object? json, int depth) {
    if (depth > 8) return null;
    if (json is Map) {
      final type = json['@type'];
      final isRecipe = type is List
          ? type.any((t) => '$t' == 'Recipe')
          : '$type' == 'Recipe';
      if (isRecipe) return json.cast<String, dynamic>();
      for (final v in json.values) {
        final r = _findRecipe(v, depth + 1);
        if (r != null) return r;
      }
    } else if (json is List) {
      for (final v in json) {
        final r = _findRecipe(v, depth + 1);
        if (r != null) return r;
      }
    }
    return null;
  }

  static List<Object?> _list(Object? v) => v == null
      ? const []
      : v is List
      ? v
      : [v];

  static String _text(Object? v) {
    if (v == null) return '';
    if (v is Map) return _text(v['text'] ?? v['name'] ?? '');
    if (v is List) return v.isEmpty ? '' : _text(v.first);
    return plainText('$v');
  }

  static String? _image(Object? v) {
    if (v == null) return null;
    if (v is String) return v.startsWith('http') ? v : null;
    if (v is List) {
      for (final i in v) {
        final s = _image(i);
        if (s != null) return s;
      }
      return null;
    }
    if (v is Map) return _image(v['url'] ?? v['contentUrl']);
    return null;
  }

  static String? _author(Object? v) {
    final s = v is List
        ? v.map(_text).where((s) => s.isNotEmpty).join(', ')
        : _text(v);
    return s.isEmpty ? null : s;
  }

  /// "Serves 4", "Makes 12", ["4", "4 servings"], 8.
  static (int?, String?) _yield(List<String> yields) {
    int? n;
    String? words;
    for (final y in yields) {
      final m = RegExp(r'\d+').firstMatch(y);
      if (m == null) continue;
      n ??= int.tryParse(m[0]!);
      if (words == null && RegExp('[A-Za-z]').hasMatch(y)) words = y;
    }
    if (n == null || n <= 0 || n > 500) return (null, null);
    return (n, words);
  }

  /// The method, step by step, however it was given: one string with a
  /// line to a step, a list of strings, or `HowToStep`s, perhaps in named
  /// `HowToSection`s.
  static List<RecipeStep> _steps(Object? v) {
    final out = <RecipeStep>[];
    void add(String text, {String? name, String? section}) {
      final t = text.replaceFirst(_numbering, '').trim();
      if (t.isEmpty) return;
      var heading = name != null && name.isNotEmpty && !t.startsWith(name)
          ? name
          : null;
      var body = t;
      // RecipeTin Eats and others start a step with its own short title:
      // "Brown the chicken - Heat the oil…".
      final dash = _titleDash.firstMatch(t);
      if (heading == null && dash != null) {
        heading = dash[1]!.trim();
        body = t.substring(dash.end).trim();
      }
      out.add(RecipeStep(text: body, heading: heading, section: section));
    }

    void walk(Object? item, String? section, int depth) {
      if (depth > 6 || item == null) return;
      if (item is String) {
        for (final line in _splitMethod(
          plainText(
            item.replaceAll(
              RegExp(r'<br\s*/?>|</p>|</li>', caseSensitive: false),
              '\n',
            ),
          ),
        )) {
          add(line, section: section);
        }
        return;
      }
      if (item is List) {
        for (final i in item) {
          walk(i, section, depth + 1);
        }
        return;
      }
      if (item is Map) {
        final type = '${item['@type']}';
        final inner = item['itemListElement'];
        if (type.contains('HowToSection') ||
            (inner != null && item['text'] == null)) {
          walk(
            inner,
            _text(item['name']).isEmpty ? section : _text(item['name']),
            depth + 1,
          );
          return;
        }
        final text = _text(item['text'] ?? item['description']);
        final name = item['text'] != null ? _text(item['name']) : null;
        add(
          text.isEmpty ? _text(item['name']) : text,
          name: name,
          section: section,
        );
      }
    }

    // A short version first, and then the recipe in full — keep the full.
    if (v is List && v.length > 1) {
      final sections = v
          .whereType<Map>()
          .where((m) => '${m['@type']}'.contains('HowToSection'))
          .toList();
      if (sections.length > 1) {
        v = [
          for (final i in v)
            if (!(i is Map && _abridged.hasMatch(_text(i['name'])))) i,
        ];
      }
    }
    walk(v, null, 0);
    return out;
  }

  /// A step's own "1." or "Step 1:" in front, which the screen numbers
  /// for itself.
  static final _numbering = RegExp(
    r'^\s*(?:step\s*)?\d{1,2}\s*[.):\-]\s+',
    caseSensitive: false,
  );

  static final _titleDash = RegExp(r'^([^.!?\-–]{3,42}?)\s+[-–]\s+(?=\S)');

  static final _abridged = RegExp(
    r'abbreviated|short version|quick version|at a glance|summary|overview',
    caseSensitive: false,
  );

  /// A method given as one block of text: a line to a step, or "1. … 2. …"
  /// run together.
  static List<String> _splitMethod(String s) {
    final lines = s
        .split(RegExp(r'\n+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.length > 1) return lines;
    final numbered = s.split(RegExp(r'\s+(?=\d{1,2}[.)]\s+[A-Z])'));
    return numbered.length > 1 ? numbered : lines;
  }

  /// An ISO 8601 duration — "PT1H30M", "P0DT0H20M" — or null.
  static Duration? isoDuration(String s) {
    final m = RegExp(
      r'^P(?:(\d+)D)?(?:T(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?)?$',
      caseSensitive: false,
    ).firstMatch(s.trim());
    if (m == null) return null;
    double n(int i) => double.tryParse(m[i] ?? '') ?? 0;
    final seconds = n(1) * 86400 + n(2) * 3600 + n(3) * 60 + n(4);
    return seconds <= 0 ? null : Duration(seconds: seconds.round());
  }

  /// An ingredient line tidied of what recipe plugins leave in it: notes
  /// to footnotes ("(Note 1)"), brackets doubled, and brackets that start
  /// with a comma — "onions (, sliced)".
  static String cleanIngredient(String s) {
    var out = s;
    out = out.replaceAll(
      RegExp(r'\(\s*(?:see\s+)?notes?\s*\d*\s*\)', caseSensitive: false),
      '',
    );
    String before;
    do {
      before = out;
      out = out
          .replaceAllMapped(
            RegExp(r'\(\s*\(([^()]*)\)\s*\)'),
            (m) => '(${m[1]})',
          )
          .replaceAll(RegExp(r'\(\s*\)'), '');
    } while (out != before);
    out = _unwrapCommaBracket(out);
    return out
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(' ,', ',')
        .replaceAll(RegExp(r',\s*,'), ',')
        .replaceAll(RegExp(r'\(\s+'), '(')
        .replaceAll(RegExp(r'\s+\)'), ')')
        .trim();
  }

  /// "(, sliced)" is ", sliced": the bracket and its partner go.
  static String _unwrapCommaBracket(String s) {
    var out = s;
    for (var guard = 0; guard < 6; guard++) {
      final m = RegExp(r'\(\s*,').firstMatch(out);
      if (m == null) break;
      var depth = 0;
      var close = -1;
      for (var i = m.start; i < out.length; i++) {
        if (out[i] == '(') depth++;
        if (out[i] == ')') {
          depth--;
          if (depth == 0) {
            close = i;
            break;
          }
        }
      }
      if (close < 0) break;
      final inner = out.substring(m.end, close).trim();
      out =
          '${out.substring(0, m.start).trimRight()}, $inner${out.substring(close + 1)}';
    }
    return out;
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'ingredients': ingredients,
    'steps': [for (final s in steps) s.toJson()],
    if (url != null) 'url': url,
    if (image != null) 'image': image,
    if (servings != null) 'servings': servings,
    if (yieldText != null) 'yield': yieldText,
    if (total != null) 'total': total!.inSeconds,
    if (prep != null) 'prep': prep!.inSeconds,
    if (cook != null) 'cook': cook!.inSeconds,
    if (author != null) 'author': author,
  };

  static Recipe? fromJson(Map<String, dynamic> j) {
    final name = '${j['name'] ?? ''}';
    final steps = [
      for (final s in (j['steps'] as List? ?? const []))
        if (s is Map) RecipeStep.fromJson(s.cast<String, dynamic>()),
    ];
    if (name.isEmpty || steps.isEmpty) return null;
    Duration? secs(Object? v) => v is num ? Duration(seconds: v.round()) : null;
    return Recipe(
      name: name,
      ingredients: [
        for (final i in (j['ingredients'] as List? ?? const [])) '$i',
      ],
      steps: steps,
      url: j['url'] as String?,
      image: j['image'] as String?,
      servings: (j['servings'] as num?)?.toInt(),
      yieldText: j['yield'] as String?,
      total: secs(j['total']),
      prep: secs(j['prep']),
      cook: secs(j['cook']),
      author: j['author'] as String?,
    );
  }
}

/// One step of the method, and the part of the recipe it is in.
@immutable
class RecipeStep {
  const RecipeStep({required this.text, this.heading, this.section});

  final String text;

  /// Its own short title, where the recipe gives one.
  final String? heading;

  /// The part of the recipe it belongs to: "For the sauce".
  final String? section;

  /// The times it mentions, each a timer to be started.
  List<StepTime> get times => StepTime.find(text);

  Map<String, Object?> toJson() => {
    'text': text,
    if (heading != null) 'heading': heading,
    if (section != null) 'section': section,
  };

  factory RecipeStep.fromJson(Map<String, dynamic> j) => RecipeStep(
    text: '${j['text'] ?? ''}',
    heading: j['heading'] as String?,
    section: j['section'] as String?,
  );
}

/// A length of time a step mentions — "for 20-25 minutes", "1½ hours" —
/// where it is in the text, and what the timer for it should be called.
@immutable
class StepTime {
  const StepTime({
    required this.start,
    required this.end,
    required this.length,
    required this.label,
    this.longest,
  });

  /// Where it is in the step's text.
  final int start;
  final int end;

  /// How long the timer runs: the shorter end of a range, since it is
  /// easier to give a few minutes more than to take them back.
  final Duration length;

  /// The longer end of a range — "20-25 minutes" — or null.
  final Duration? longest;

  /// What the timer is called: what is being done for that long, "Simmer",
  /// or empty when the step does not say.
  final String label;

  static const _words = {
    'a': 1, 'an': 1, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, //
    'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11,
    'twelve': 12, 'fifteen': 15, 'twenty': 20, 'thirty': 30, 'forty': 40,
    'forty-five': 45, 'fifty': 50, 'sixty': 60, 'ninety': 90,
    'a couple of': 2, 'couple of': 2,
  };

  static final _number =
      r'(?:\d+(?:[.,]\d+)?(?:\s*(?:[½¼¾⅓⅔]|and\s+a\s+half|\d/\d))?|[½¼¾]|half\s+an?|a\s+couple\s+of|forty-five|an?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|twenty|thirty|forty|fifty|sixty|ninety)';

  static final _pattern = RegExp(
    '(?<![\\w/])($_number)'
    r'(?:\s*(?:-|–|to|or)\s*(\d+(?:[.,]\d+)?))?'
    r'[\s-]*(hours?|hrs?|minutes?|mins?|seconds?|secs?)\b'
    r'(?:\s*(?:and\s+)?(\d+)\s*(minutes?|mins?))?',
    caseSensitive: false,
  );

  /// Every time [text] mentions, in order.
  static List<StepTime> find(String text) {
    final out = <StepTime>[];
    for (final m in _pattern.allMatches(text)) {
      final unit = _unitSeconds(m[3]!);
      final low = _value(m[1]!);
      if (low == null || low <= 0) continue;
      final high = m[2] == null
          ? null
          : double.tryParse(m[2]!.replaceAll(',', '.'));
      var seconds = low * unit;
      if (m[4] != null) seconds += (int.tryParse(m[4]!) ?? 0) * 60;
      // Days of marinating and weeks in a jar are not for a kitchen timer.
      if (seconds < 5 || seconds > 12 * 3600) continue;
      out.add(
        StepTime(
          start: m.start,
          end: m.end,
          length: Duration(seconds: seconds.round()),
          longest: high != null && high > low
              ? Duration(seconds: (high * unit).round())
              : null,
          label: _labelFor(text, m.start),
        ),
      );
    }
    return out;
  }

  static double _unitSeconds(String unit) {
    final u = unit.toLowerCase();
    if (u.startsWith('h')) return 3600;
    if (u.startsWith('m')) return 60;
    return 1;
  }

  static double? _value(String said) {
    var s = said.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.startsWith('half a')) return 0.5;
    final w = _words[s];
    if (w != null) return w.toDouble();
    var extra = 0.0;
    for (final (frac, v) in [
      ('½', 0.5),
      ('¼', 0.25),
      ('¾', 0.75),
      ('⅓', 1 / 3),
      ('⅔', 2 / 3),
    ]) {
      if (s.contains(frac)) {
        extra = v;
        s = s.replaceAll(frac, '').trim();
      }
    }
    if (s.contains('and a half')) {
      extra = 0.5;
      s = s.replaceAll('and a half', '').trim();
    }
    final mixed = RegExp(r'^(\d+)\s+(\d)/(\d)$').firstMatch(s);
    if (mixed != null) {
      return int.parse(mixed[1]!) + int.parse(mixed[2]!) / int.parse(mixed[3]!);
    }
    if (s.isEmpty) return extra == 0 ? null : extra;
    final n = double.tryParse(s.replaceAll(',', '.'));
    return n == null ? null : n + extra;
  }

  /// What is done for the time: the last cooking word in the clause before
  /// it — "simmer, covered, for 10 minutes" is a Simmer timer.
  static String _labelFor(String text, int at) {
    var from = at;
    while (from > 0 && !'.;!?'.contains(text[from - 1])) {
      from--;
    }
    final clause = text.substring(from, at).toLowerCase();
    String? best;
    var bestAt = -1;
    for (final e in _verbs.entries) {
      final m = RegExp('\\b${e.key}\\b').allMatches(clause).lastOrNull;
      if (m != null && m.start > bestAt) {
        bestAt = m.start;
        best = e.value;
      }
    }
    return best ?? '';
  }

  /// Cooking words, and the timer each one names.
  static const _verbs = {
    'bake': 'Bake',
    'baking': 'Bake',
    'roast': 'Roast',
    'roasting': 'Roast',
    'simmer': 'Simmer',
    'simmering': 'Simmer',
    'boil': 'Boil',
    'boiling': 'Boil',
    'fry': 'Fry',
    'frying': 'Fry',
    'sauté': 'Sauté',
    'saute': 'Sauté',
    'sear': 'Sear',
    'grill': 'Grill',
    'steam': 'Steam',
    'poach': 'Poach',
    'rest': 'Rest',
    'resting': 'Rest',
    'chill': 'Chill',
    'refrigerate': 'Chill',
    'fridge': 'Chill',
    'cool': 'Cool',
    'freeze': 'Freeze',
    'marinate': 'Marinate',
    'soak': 'Soak',
    'prove': 'Prove',
    'rise': 'Prove',
    'knead': 'Knead',
    'whisk': 'Whisk',
    'beat': 'Beat',
    'stir': 'Stir',
    'cook': 'Cook',
    'cooking': 'Cook',
    'brown': 'Brown',
    'reduce': 'Reduce',
    'toast': 'Toast',
    'microwave': 'Microwave',
    'blend': 'Blend',
    'mix': 'Mix',
    'melt': 'Melt',
    'heat': 'Heat',
    'caramelise': 'Caramelise',
    'caramelize': 'Caramelise',
    'stand': 'Stand',
    'set aside': 'Rest',
    'leave': 'Rest',
    'steep': 'Steep',
    'infuse': 'Infuse',
    'braise': 'Braise',
    'stew': 'Stew',
    'blanch': 'Blanch',
    'soften': 'Soften',
    'bubble': 'Bubble',
  };
}

/// An ingredient line read for its amount: "2 1/2 cups beef stock" is 2.5
/// cups of beef stock — to scale for more people, and to say out loud.
@immutable
class Ingredient {
  const Ingredient({
    required this.line,
    required this.name,
    this.amount,
    this.upTo,
    this.unit,
    this.amountEnd = 0,
    this.alt,
  });

  /// As written.
  final String line;

  /// What it is, without the amount: "plain flour", "chicken thighs,
  /// bone-in".
  final String name;

  /// How much, and the top of a range — "2-3 tbsp" — when it is one. Null
  /// for "salt, to taste".
  final double? amount;
  final double? upTo;

  /// Its measure, as written ("tbsp", "g"), or null for a count: "2 eggs".
  final String? unit;

  /// Where the amount and its measure end in [line].
  final int amountEnd;

  /// The same amount in another measure, given beside it: "400g / 14oz".
  final ({double amount, String unit})? alt;

  static const _fractions = {
    '½': '1/2', '⅓': '1/3', '⅔': '2/3', '¼': '1/4', '¾': '3/4', //
    '⅕': '1/5', '⅖': '2/5', '⅗': '3/5', '⅘': '4/5', '⅙': '1/6',
    '⅚': '5/6', '⅛': '1/8', '⅜': '3/8', '⅝': '5/8', '⅞': '7/8',
  };

  /// [s] with ½ written 1/2, so there is one kind of fraction to read.
  static String plainFractions(String s) {
    var out = s.replaceAll('⁄', '/');
    for (final e in _fractions.entries) {
      out = out.replaceAllMapped(
        RegExp('(\\d?)${e.key}'),
        (m) => m[1]!.isEmpty ? e.value : '${m[1]} ${e.value}',
      );
    }
    return out;
  }

  static const _qty = r'(\d+\s+\d+/\d+|\d+/\d+|\d+(?:[.,]\d+)?)';

  static final _partOf = RegExp(
    r'^((?:for|to) (?:the )?[^:]{2,30}):\s*',
    caseSensitive: false,
  );

  /// Measures, longest first, so "tbsp" is not read as "t".
  static const units = [
    'tablespoons', 'tablespoon', 'teaspoons', 'teaspoon', 'kilograms', //
    'kilogram', 'millilitres', 'milliliters', 'millilitre', 'milliliter',
    'handfuls', 'handful', 'bunches', 'bunch', 'pinches', 'pinch',
    'dashes', 'dash', 'splashes', 'splash', 'packets', 'packet', 'sprigs',
    'sprig', 'cloves', 'clove', 'slices', 'slice', 'sticks', 'stick',
    'ounces', 'ounce', 'pounds', 'pound', 'litres', 'liters', 'litre',
    'liter', 'grams', 'gram', 'quarts', 'quart', 'pints', 'pint', 'cups',
    'cup', 'cans', 'can', 'tins', 'tin', 'jars', 'jar', 'knobs', 'knob',
    'sheets', 'sheet', 'heads', 'head', 'stalks', 'stalk', 'drops', 'drop',
    'fl oz',
    'tbsp',
    'tbsp.',
    'tbs',
    'tsp',
    'tsp.',
    'lbs',
    'lb',
    'oz',
    'kg',
    'mg',
    'ml',
    'cl', 'dl', 'g', 'l',
  ];

  static final _unitPattern = units.map((u) => RegExp.escape(u)).join('|');

  static final _lead = RegExp(
    '^\\s*$_qty(?:\\s*(?:-|–|to)\\s*$_qty)?\\s*(?:($_unitPattern)(?![a-z]))?\\.?',
    caseSensitive: false,
  );

  static final _altAfter = RegExp(
    '^\\s*/\\s*$_qty\\s*($_unitPattern)(?![a-z])',
    caseSensitive: false,
  );

  static double? number(String s) {
    final t = s.trim().replaceAll(',', '.');
    final mixed = RegExp(r'^(\d+)\s+(\d+)/(\d+)$').firstMatch(t);
    if (mixed != null) {
      final d = int.parse(mixed[3]!);
      return d == 0 ? null : int.parse(mixed[1]!) + int.parse(mixed[2]!) / d;
    }
    final frac = RegExp(r'^(\d+)/(\d+)$').firstMatch(t);
    if (frac != null) {
      final d = int.parse(frac[2]!);
      return d == 0 ? null : int.parse(frac[1]!) / d;
    }
    return double.tryParse(t);
  }

  factory Ingredient.parse(String written) {
    var line = plainFractions(written).replaceAll(RegExp(r'\s+'), ' ').trim();
    // "For the drizzle: 175g sugar" is 175g sugar, for the drizzle.
    final part = _partOf.firstMatch(line);
    if (part != null && part.end < line.length) {
      line = '${line.substring(part.end)} (${part[1]!.toLowerCase()})';
    }
    final m = _lead.firstMatch(line);
    if (m == null || m[1] == null) {
      return Ingredient(line: line, name: _nameOf(line));
    }
    final amount = number(m[1]!);
    final upTo = m[2] == null ? null : number(m[2]!);
    var end = m.end;
    ({double amount, String unit})? alt;
    final unit = m[3];
    if (unit != null) {
      final a = _altAfter.firstMatch(line.substring(end));
      final altAmount = a == null ? null : number(a[1]!);
      if (a != null && altAmount != null) {
        alt = (amount: altAmount, unit: a[2]!);
        end += a.end;
      }
    }
    final rest = line
        .substring(end)
        .trim()
        .replaceFirst(RegExp(r'^of\s+', caseSensitive: false), '');
    return Ingredient(
      line: line,
      name: _nameOf(rest),
      amount: amount,
      upTo: upTo,
      unit: unit?.replaceAll('.', ''),
      amountEnd: end,
      alt: alt,
    );
  }

  /// What it is, without what is done to it: up to the first comma or
  /// bracket.
  static String _nameOf(String rest) {
    final bare = rest
        .replaceAll(RegExp(r'\([^()]*\)'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final cut = bare.indexOf(RegExp(r'[,(]'));
    return (cut > 0 ? bare.substring(0, cut) : bare).trim();
  }

  /// The amount for [factor] times as many, as written on screen:
  /// "200g", "1½ cups", "3". Empty when there is no amount.
  String amountText(double factor) {
    final a = amount;
    if (a == null) return '';
    if (factor == 1) return pretty(line.substring(0, amountEnd).trim());
    final u = unit;
    final main = upTo == null
        ? showAmount(a * factor, u)
        : '${showAmount(a * factor, u)}–${showAmount(upTo! * factor, u)}';
    final measure = u == null
        ? ''
        : _tight(u)
        ? u
        : ' ${_unitFor(u, (upTo ?? a) * factor)}';
    final second = alt == null
        ? ''
        : ' / ${showAmount(alt!.amount * factor, alt!.unit)}${_tight(alt!.unit) ? '' : ' '}${alt!.unit}';
    return '$main$measure$second';
  }

  /// [unit] for [n] of it, where it is a word: "2 tablespoons", not "2
  /// tablespoon"; abbreviations stay as they are.
  static String _unitFor(String unit, double n) {
    if (unit.length <= 4 &&
        !const {
          'cup',
          'cups',
          'can',
          'cans',
          'tin',
          'tins',
          'jar',
          'jars',
        }.contains(unit.toLowerCase())) {
      return unit;
    }
    final w = _spokenUnit(unit);
    if (w == null) return unit;
    return n > 1 ? w.$2 : w.$1;
  }

  static const _glyphs = {
    '1/2': '½', '1/3': '⅓', '2/3': '⅔', '1/4': '¼', '3/4': '¾', //
    '1/8': '⅛', '3/8': '⅜', '5/8': '⅝', '7/8': '⅞',
  };

  /// "2 1/2 cups" as a cook writes it: "2½ cups".
  static String pretty(String s) =>
      s.replaceAllMapped(RegExp(r'(\d+\s+)?(\d)/(\d)(?!\d)'), (m) {
        final glyph = _glyphs['${m[2]}/${m[3]}'];
        if (glyph == null) return m[0]!;
        return '${m[1]?.trim() ?? ''}$glyph';
      });

  /// The rest of the line after the amount, with any amounts in brackets
  /// scaled too — "(2 sticks; 225g)" — unless they are each or per one.
  String restText(double factor) {
    var rest = line.substring(amount == null ? 0 : amountEnd).trim();
    if (factor == 1 || amount == null) return rest;
    // One egg for two people is two eggs for four.
    final last = RegExp(r'^[A-Za-z-]+').firstMatch(rest);
    if (unit == null &&
        amount! <= 1 &&
        amount! * factor > 1 &&
        last != null &&
        name == last[0]) {
      rest = '${plural(last[0]!)}${rest.substring(last.end)}';
    }
    return rest.replaceAllMapped(RegExp(r'\(([^()]*)\)'), (m) {
      final inner = m[1]!;
      if (RegExp(
        r'\beach\b|\bper\b|\bx\b',
        caseSensitive: false,
      ).hasMatch(inner)) {
        return m[0]!;
      }
      return '(${scaleAmounts(inner, factor).map((s) => s.text).join()})';
    });
  }

  /// [w] for more than one: eggs, tomatoes, berries.
  static String plural(String w) {
    final l = w.toLowerCase();
    if (l.endsWith('s')) return w;
    if (RegExp(r'[^aeiou]y$').hasMatch(l)) {
      return '${w.substring(0, w.length - 1)}ies';
    }
    if (l.endsWith('o') || l.endsWith('ch') || l.endsWith('sh')) {
      return '${w}es';
    }
    return '${w}s';
  }

  /// How much, said: "two hundred grams of plain flour" is left to the
  /// voice — this gives "200 grams of plain flour", "half a teaspoon of
  /// salt", "2 large eggs".
  String spoken(double factor) {
    final a = amount;
    final rest = name.isEmpty ? line : name;
    if (a == null) return line;
    final u = unit == null ? null : _spokenUnit(unit!);
    final value = a * factor;
    final top = upTo == null ? null : upTo! * factor;
    final plural = (top ?? value) > 1;
    if (u == null) {
      final n = top == null
          ? sayNumber(value)
          : '${sayNumber(value)} to ${sayNumber(top)}';
      final many = plural && a <= 1 && !rest.contains(' ')
          ? Ingredient.plural(rest)
          : rest;
      return '$n $many';
    }
    final unitWord = plural ? u.$2 : u.$1;
    if (top == null && value < 1) {
      // "Half a teaspoon of salt", "a quarter of a cup of milk".
      final f = _fractionWords(value);
      if (f != null) return '$f $unitWord of $rest';
    }
    final n = top == null
        ? sayNumber(value)
        : '${sayNumber(value)} to ${sayNumber(top)}';
    return '$n $unitWord of $rest';
  }

  static (String, String)? _spokenUnit(String unit) {
    final u = unit.toLowerCase().replaceAll('.', '');
    const words = {
      'g': ('gram', 'grams'),
      'gram': ('gram', 'grams'),
      'grams': ('gram', 'grams'),
      'kg': ('kilo', 'kilos'),
      'mg': ('milligram', 'milligrams'),
      'ml': ('millilitre', 'millilitres'),
      'l': ('litre', 'litres'),
      'cl': ('centilitre', 'centilitres'),
      'dl': ('decilitre', 'decilitres'),
      'tsp': ('teaspoon', 'teaspoons'),
      'tbsp': ('tablespoon', 'tablespoons'),
      'tbs': ('tablespoon', 'tablespoons'),
      'oz': ('ounce', 'ounces'),
      'fl oz': ('fluid ounce', 'fluid ounces'),
      'lb': ('pound', 'pounds'),
      'lbs': ('pound', 'pounds'),
    };
    final w = words[u];
    if (w != null) return w;
    // A word already: "cups", "cloves", "pinch".
    final single = u.endsWith('ches') || u.endsWith('shes')
        ? u.substring(0, u.length - 2)
        : u.endsWith('s') && !u.endsWith('ss')
        ? u.substring(0, u.length - 1)
        : u;
    final many = single.endsWith('ch') || single.endsWith('sh')
        ? '${single}es'
        : '${single}s';
    return (single, many);
  }

  static String? _fractionWords(double v) {
    const near = 0.02;
    for (final (f, w) in [
      (0.5, 'half a'),
      (0.25, 'a quarter of a'),
      (0.75, 'three quarters of a'),
      (1 / 3, 'a third of a'),
      (2 / 3, 'two thirds of a'),
      (0.125, 'an eighth of a'),
    ]) {
      if ((v - f).abs() < near) return w;
    }
    return null;
  }

  /// [v] said: "2", "one and a half", "2 and three quarters", "0.3".
  static String sayNumber(double v) {
    final whole = v.floor();
    final part = v - whole;
    String? frac;
    for (final (f, w) in [
      (0.5, 'a half'),
      (0.25, 'a quarter'),
      (0.75, 'three quarters'),
      (1 / 3, 'a third'),
      (2 / 3, 'two thirds'),
    ]) {
      if ((part - f).abs() < 0.02) frac = w;
    }
    if (part < 0.02) return '$whole';
    if (part > 0.98) return '${whole + 1}';
    if (frac == null) return _trim(v, 1);
    if (whole == 0) return frac;
    return whole == 1 ? 'one and $frac' : '$whole and $frac';
  }

  /// Written straight after the number: "200g", "300ml".
  static bool _tight(String unit) => const {
    'g',
    'kg',
    'mg',
    'ml',
    'l',
    'cl',
    'dl',
    'oz',
    'lb',
  }.contains(unit.toLowerCase());

  /// Measures that are weighed or poured by the metric system: shown as
  /// whole, rounded numbers, never fractions.
  static bool _metric(String? unit) =>
      unit != null &&
      const {
        'g',
        'gram',
        'grams',
        'kg',
        'kilogram',
        'kilograms',
        'mg',
        'ml',
        'millilitre',
        'millilitres',
        'milliliter',
        'milliliters',
        'l',
        'litre',
        'litres',
        'liter',
        'liters',
        'cl',
        'dl',
      }.contains(unit.toLowerCase());

  /// [v] as a cook would write it: grams rounded — 455g, not 454.5 — and
  /// spoons and cups in the fractions they come in.
  static String showAmount(double v, String? unit) {
    if (_metric(unit)) {
      if (v >= 100) return '${(v / 5).round() * 5}';
      if (v >= 10) return '${v.round()}';
      return _trim(v, 1);
    }
    return vulgar(v);
  }

  /// [v] with its fraction as a cook writes it: 1½, ¾, ⅓, 2⅔.
  static String vulgar(double v) {
    if (v >= 20) return '${v.round()}';
    final whole = v.floor();
    final part = v - whole;
    const marks = [
      (0.0, ''),
      (0.125, '⅛'),
      (0.25, '¼'),
      (1 / 3, '⅓'),
      (0.5, '½'),
      (2 / 3, '⅔'),
      (0.75, '¾'),
      (1.0, ''),
    ];
    var best = marks.first;
    for (final m in marks) {
      if ((part - m.$1).abs() < (part - best.$1).abs()) best = m;
    }
    final w = best.$1 == 1.0 ? whole + 1 : whole;
    if (best.$2.isEmpty) return '$w';
    return w == 0 ? best.$2 : '$w${best.$2}';
  }

  static String _trim(double v, int places) {
    final s = v.toStringAsFixed(places);
    return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
  }

  /// The words that name it, for finding it in a step or a question:
  /// "plain flour" is flour, "large free-range eggs" eggs.
  Set<String> get keywords => keywordsOf(name.isEmpty ? line : name);

  static Set<String> keywordsOf(String s) => {
    for (final w in s.toLowerCase().split(RegExp(r'[^a-zà-ÿ]+')))
      if (w.length >= 3 && !_plain.contains(w)) stem(w),
  };

  /// One word for its plural and its singular: "eggs" and "egg",
  /// "tomatoes" and "tomato", "berries" and "berry".
  static String stem(String w) {
    if (w.length > 4 && w.endsWith('ies')) {
      return '${w.substring(0, w.length - 3)}y';
    }
    if (w.length > 4 && w.endsWith('oes')) return w.substring(0, w.length - 2);
    if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) {
      return w.substring(0, w.length - 1);
    }
    return w;
  }

  /// Words that say how it is bought or cut, not what it is.
  static const _plain = {
    'fresh', 'large', 'small', 'medium', 'chopped', 'sliced', 'diced', //
    'minced', 'finely', 'roughly', 'thinly', 'ground', 'unsalted', 'salted',
    'extra', 'virgin', 'cold', 'warm', 'hot', 'whole', 'optional', 'taste',
    'dried', 'cooking', 'kosher', 'and', 'for', 'the', 'with', 'into',
    'plus', 'little', 'more', 'needed', 'good', 'quality', 'free', 'range',
    'organic', 'low', 'sodium', 'beaten', 'softened', 'melted', 'room',
    'temperature', 'about', 'each', 'peeled', 'grated', 'cup', 'cups',
    'tsp', 'tbsp', 'serve', 'serving', 'garnish', 'halved', 'quartered',
    'trimmed', 'shredded', 'crushed', 'packed', 'heaped', 'level', 'rounded',
    'bone', 'skin', 'boneless', 'skinless', 'frying', 'other', 'any',
    'some', 'your', 'favourite', 'favorite', 'brown', 'white', 'yellow',
    'black', 'red', 'green', 'sea', 'fine', 'coarse', 'flaky', 'light',
    'dark', 'pinch', 'handful', 'bunch', 'can', 'tin', 'jar', 'clove',
    'cloves', 'sprig', 'sprigs', 'stick', 'sticks', 'slice', 'slices',
    'baby', 'mature', 'ripe', 'block', 'pack', 'packet', 'sheet', 'sheets',
    'approx', 'plain', 'self', 'raising', 'rising', 'purpose',
    'all', 'not', 'from', 'such', 'like', 'lightly', 'well', 'just',
    'teaspoon', 'teaspoons', 'tablespoon', 'tablespoons', 'ounce', 'ounces',
    'gram', 'grams', 'inch', 'knife', 'chunk', 'chunks', 'piece', 'pieces',
  };

  /// Words that say what kind, and on their own say nothing about which
  /// ingredient a step means: "baking" is in "baking sheet" too.
  static const kinds = {
    'baking', 'dry', 'standard', 'table', 'granulated', 'creamy', 'mashed', //
    'caster', 'icing', 'double', 'single', 'whipping', 'soft', 'hard',
    'smoked', 'diamond', 'crystal', 'sweet', 'sour', 'mixed', 'spring',
  };
}

/// Part of a step's text: as written, an amount scaled for more or fewer
/// people, or a time to start a timer for.
@immutable
class StepPiece {
  const StepPiece(this.text, {this.scaled = false, this.time});
  final String text;
  final bool scaled;
  final StepTime? time;
}

/// [text] in pieces: amounts with a measure ("100g", "2 tbsp") scaled by
/// [factor] and marked, times marked to be touched. Lengths ("a 20cm
/// tin"), temperatures and counts are left alone: "2 eggs" in the method
/// may not be all the eggs.
List<StepPiece> stepPieces(String text, double factor) {
  final times = StepTime.find(text);
  final out = <StepPiece>[];
  var at = 0;
  for (final t in times) {
    if (t.start > at) {
      out.addAll(scaleAmounts(text.substring(at, t.start), factor));
    }
    out.add(StepPiece(text.substring(t.start, t.end), time: t));
    at = t.end;
  }
  if (at < text.length) out.addAll(scaleAmounts(text.substring(at), factor));
  return out;
}

final _stepAmount = RegExp(
  r'(?<![\w/.])(\d+\s+\d/\d|\d/\d|\d+(?:\.\d+)?|[½¼¾⅓⅔])\s?(kg|g|mg|ml|l|cl|tbsp|tsp|tablespoons?|teaspoons?|cups?|oz|ounces?|lbs?|pounds?|sticks?|cloves?|tins?|cans?)(?![a-zA-Z])',
);

/// [text] with each amount and measure in it scaled by [factor].
List<StepPiece> scaleAmounts(String text, double factor) {
  if (factor == 1) return [StepPiece(text)];
  final out = <StepPiece>[];
  var at = 0;
  for (final m in _stepAmount.allMatches(text)) {
    final n = Ingredient.number(Ingredient.plainFractions(m[1]!).trim());
    if (n == null) continue;
    if (m.start > at) out.add(StepPiece(text.substring(at, m.start)));
    final unit = m[2]!;
    final tight = !m[0]!.contains(' ') && Ingredient._tight(unit);
    out.add(
      StepPiece(
        '${Ingredient.showAmount(n * factor, unit)}${tight ? '' : ' '}$unit',
        scaled: true,
      ),
    );
    at = m.end;
  }
  if (at < text.length) out.add(StepPiece(text.substring(at)));
  return out;
}

/// The ingredients [step] uses, by their place in [ingredients]: any whose
/// name has a word the step says.
Set<int> ingredientsIn(String step, List<Ingredient> ingredients) {
  final said = Ingredient.keywordsOf(step);
  return {
    for (final (i, ing) in ingredients.indexed)
      if (ing.keywords.any(
        (k) => !Ingredient.kinds.contains(k) && said.contains(k),
      ))
        i,
  };
}

/// The ingredients asked about — "flour", "the butter" — best match first:
/// those named by every word asked, else by most of them.
List<int> ingredientsAsked(List<String> asked, List<Ingredient> ingredients) {
  final want = Ingredient.keywordsOf(asked.join(' '));
  if (want.isEmpty) return const [];
  var best = 0;
  final scores = <int, int>{};
  for (final (i, ing) in ingredients.indexed) {
    final have = Ingredient.keywordsOf(ing.line);
    final score = want.where(have.contains).length;
    if (score > 0) scores[i] = score;
    best = math.max(best, score);
  }
  if (best == 0) return const [];
  return [
    for (final e in scores.entries)
      if (e.value == best) e.key,
  ];
}
