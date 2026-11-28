import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:home_canvas/services/cook_voice.dart';
import 'package:home_canvas/services/kitchen.dart';
import 'package:home_canvas/services/recipe.dart';
import 'package:home_canvas/services/voice_commands.dart';

/// A page as a recipe site serves it: the recipe in JSON-LD among the
/// page's other things, as WordPress recipe plugins write it. The recipe is
/// made up.
String page(Object recipe, {bool graph = true}) =>
    '''
<html><head>
<script type="application/ld+json">{"@context":"https://schema.org","@type":"WebSite","name":"A blog"}</script>
<script type="application/ld+json">${jsonEncode(graph ? {
            '@context': 'https://schema.org',
            '@graph': [
              {'@type': 'Organization', 'name': 'A blog'},
              recipe,
            ],
          } : recipe)}</script>
</head><body><p>Once upon a time, in a kitchen…</p></body></html>
''';

final stew = {
  '@type': 'Recipe',
  'name': 'Sam&#39;s Winter Stew',
  'image': [
    {'@type': 'ImageObject', 'url': 'https://example.com/stew.jpg'},
  ],
  'recipeYield': ['4', '4 servings'],
  'prepTime': 'PT15M',
  'cookTime': 'PT1H30M',
  'author': {'@type': 'Person', 'name': 'Sam Parker'},
  'recipeIngredient': [
    '500g / 1lb  stewing beef ((Note 1))',
    '2  onions (, sliced)',
    '1 1/2 tbsp plain flour',
    '½ tsp salt',
    '2-3 carrots',
    '1 egg',
    '400ml beef stock',
    'Crusty bread, to serve',
  ],
  'recipeInstructions': [
    {
      '@type': 'HowToSection',
      'name': 'Abbreviated Recipe',
      'itemListElement': [
        {'@type': 'HowToStep', 'text': 'Brown, stew, eat.'},
      ],
    },
    {
      '@type': 'HowToSection',
      'name': 'The stew',
      'itemListElement': [
        {
          '@type': 'HowToStep',
          'text':
              'Brown the beef - Toss the beef in the flour and fry for 5-6 minutes until browned.',
        },
        {
          '@type': 'HowToStep',
          'text':
              'Add the onions and 400ml stock, then simmer, covered, for 1 hour 20 minutes.',
        },
      ],
    },
    {
      '@type': 'HowToSection',
      'name': 'To finish',
      'itemListElement': [
        {
          '@type': 'HowToStep',
          'text': 'Leave to rest for half an hour. Serve with the bread.',
        },
      ],
    },
  ],
};

void main() {
  group('Recipe.fromHtml', () {
    test('finds the recipe in a page among its other things', () {
      final r = Recipe.fromHtml(page(stew), url: 'https://example.com/stew')!;
      expect(r.name, "Sam's Winter Stew");
      expect(r.image, 'https://example.com/stew.jpg');
      expect(r.servings, 4);
      expect(r.time, const Duration(hours: 1, minutes: 45));
      expect(r.author, 'Sam Parker');
      expect(r.url, 'https://example.com/stew');
    });

    test('drops the short version when the full one follows', () {
      final r = Recipe.fromHtml(page(stew))!;
      expect(r.steps, hasLength(3));
      expect(r.steps.first.section, 'The stew');
      expect(r.steps.last.section, 'To finish');
    });

    test("takes a step's own title off its front", () {
      final step = Recipe.fromHtml(page(stew))!.steps.first;
      expect(step.heading, 'Brown the beef');
      expect(step.text, startsWith('Toss the beef'));
    });

    test('tidies what recipe plugins leave in an ingredient line', () {
      final r = Recipe.fromHtml(page(stew))!;
      expect(r.ingredients[0], '500g / 1lb stewing beef');
      expect(r.ingredients[1], '2 onions, sliced');
    });

    test('reads a method given as one block of text, and plain strings', () {
      final r = Recipe.fromHtml(
        page({
          '@type': ['Recipe', 'NewsArticle'],
          'name': 'Toast',
          'recipeIngredient': ['1 slice bread'],
          'recipeInstructions': '1. Toast the bread. 2. Butter it.',
        }, graph: false),
      )!;
      expect(r.steps.map((s) => s.text), ['Toast the bread.', 'Butter it.']);
      final lines = Recipe.fromJsonLd({
        '@type': 'Recipe',
        'name': 'Tea',
        'recipeInstructions': ['Boil the kettle.', 'Step 2: Pour.'],
      })!;
      expect(lines.steps.map((s) => s.text), ['Boil the kettle.', 'Pour.']);
    });

    test('a page without a recipe, or with no method, has none', () {
      expect(Recipe.fromHtml('<html><p>Hello</p></html>'), isNull);
      expect(
        Recipe.fromJsonLd({'@type': 'Recipe', 'name': 'Nothing to do'}),
        isNull,
      );
    });

    test('kept and read back the same', () {
      final r = Recipe.fromHtml(page(stew), url: 'https://example.com/stew')!;
      final back = Recipe.fromJson(
        jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>,
      )!;
      expect(back.name, r.name);
      expect(back.ingredients, r.ingredients);
      expect(back.steps.map((s) => s.heading), r.steps.map((s) => s.heading));
      expect(back.time, r.time);
    });

    test('ISO durations', () {
      expect(Recipe.isoDuration('PT20M'), const Duration(minutes: 20));
      expect(Recipe.isoDuration('P0DT1H5M'), const Duration(minutes: 65));
      expect(Recipe.isoDuration('PT0S'), isNull);
      expect(Recipe.isoDuration('soon'), isNull);
    });
  });

  group('Ingredient', () {
    test('reads the amount, the measure and what it is', () {
      final i = Ingredient.parse('1 1/2 tbsp plain flour');
      expect(i.amount, 1.5);
      expect(i.unit, 'tbsp');
      expect(i.name, 'plain flour');
      expect(Ingredient.parse('½ tsp salt').amount, 0.5);
      expect(Ingredient.parse('300ml milk').unit, 'ml');
      expect(Ingredient.parse('2 garlic cloves').unit, isNull);
      expect(Ingredient.parse('Crusty bread, to serve').amount, isNull);
    });

    test('scales for more people, as a cook writes it', () {
      expect(
        Ingredient.parse('500g / 1lb stewing beef').amountText(2),
        '1000g / 2lb',
      );
      expect(
        Ingredient.parse('1 1/2 tbsp plain flour').amountText(2),
        '3 tbsp',
      );
      expect(Ingredient.parse('3/4 cup milk').amountText(2), '1½ cups');
      expect(
        Ingredient.parse('1 tablespoon sugar').amountText(2),
        '2 tablespoons',
      );
      expect(Ingredient.parse('2-3 carrots').amountText(2), '4–6');
      expect(Ingredient.parse('7g yeast').amountText(1.5), '11g');
      expect(Ingredient.parse('5g yeast').amountText(1.5), '7.5g');
      expect(Ingredient.parse('454g butter').amountText(1), '454g');
    });

    test('a part of the recipe named in front goes after', () {
      final i = Ingredient.parse('For the drizzle: 175g granulated sugar');
      expect(i.amount, 175);
      expect(i.amountText(2), '350g');
      expect(i.restText(2), 'granulated sugar (for the drizzle)');
    });

    test('one egg for two is two eggs for four', () {
      expect(Ingredient.parse('1 egg').restText(2), 'eggs');
      expect(Ingredient.parse('1 egg').spoken(2), '2 eggs');
    });

    test('amounts in brackets scale too, unless each', () {
      expect(
        Ingredient.parse('8 ounces butter (2 sticks; 225g)').restText(2),
        'butter (4 sticks; 450g)',
      );
      expect(
        Ingredient.parse('4 chicken thighs (~250g each)').restText(2),
        'chicken thighs (~250g each)',
      );
    });

    test('said out loud', () {
      expect(
        Ingredient.parse('100g plain flour').spoken(1),
        '100 grams of plain flour',
      );
      expect(
        Ingredient.parse('½ tsp salt').spoken(1),
        'half a teaspoon of salt',
      );
      expect(
        Ingredient.parse('1 1/2 cups milk').spoken(1),
        'one and a half cups of milk',
      );
      expect(Ingredient.parse('2 large eggs').spoken(1), '2 large eggs');
    });
  });

  group('StepTime', () {
    test('finds the times in a step, and what each is for', () {
      final times = StepTime.find(
        'Fry for 5-6 minutes, then simmer, covered, for 1 hour 20 minutes.',
      );
      expect(times, hasLength(2));
      expect(times[0].length, const Duration(minutes: 5));
      expect(times[0].longest, const Duration(minutes: 6));
      expect(times[0].label, 'Fry');
      expect(times[1].length, const Duration(minutes: 80));
      expect(times[1].label, 'Simmer');
    });

    test('words and fractions', () {
      Duration first(String s) => StepTime.find(s).single.length;
      expect(first('Rest for half an hour.'), const Duration(minutes: 30));
      expect(first('Bake for 1½ hours.'), const Duration(minutes: 90));
      expect(first('Boil for a minute.'), const Duration(minutes: 1));
      expect(first('Whisk for 30 seconds.'), const Duration(seconds: 30));
      expect(first('Chill for ten minutes.'), const Duration(minutes: 10));
    });

    test('not days, and not a measure', () {
      expect(StepTime.find('Marinate for 2 days.'), isEmpty);
      expect(StepTime.find('Use a 20cm tin and 200g flour.'), isEmpty);
    });
  });

  test('step amounts scale, lengths and counts do not', () {
    final pieces = stepPieces(
      'Mix 100g flour and 2 eggs in a 20cm tin for 5 minutes.',
      2,
    );
    expect(pieces.where((p) => p.scaled).map((p) => p.text), ['200g']);
    expect(pieces.where((p) => p.time != null), hasLength(1));
    expect(
      pieces.map((p) => p.text).join(),
      'Mix 200g flour and 2 eggs in a 20cm tin for 5 minutes.',
    );
  });

  test('the ingredients a step uses, and those asked about', () {
    final ings = [
      for (final l in [
        '100g plain flour',
        '2 large eggs',
        '1/2 tsp baking powder',
        '30g butter',
        '30g butter, cold and cubed',
      ])
        Ingredient.parse(l),
    ];
    expect(ingredientsIn('Whisk the eggs into the flour.', ings), {0, 1});
    // "Baking" in "baking sheet" is not the baking powder.
    expect(ingredientsIn('Line a baking sheet.', ings), isEmpty);
    expect(ingredientsAsked(['butter'], ings), [3, 4]);
    expect(ingredientsAsked(['the', 'eggs'], ings), [1]);
    expect(ingredientsAsked(['saffron'], ings), isEmpty);
  });

  group('CookCommands', () {
    CookAsk? ask(String s) => CookCommands.parse(s);

    test('steps', () {
      expect(
        ask('hey canvas next'),
        isA<CookStep>().having((a) => a.by, 'by', 1),
      );
      expect(ask("okay what's next"), isA<CookStep>());
      expect(ask('go back'), isA<CookStep>().having((a) => a.by, 'by', -1));
      expect(
        ask('step four'),
        isA<CookGoTo>().having((a) => a.step, 'step', 4),
      );
      expect(
        ask('go to step 2'),
        isA<CookGoTo>().having((a) => a.step, 'step', 2),
      );
      expect(ask('read that again'), isA<CookRepeat>());
      expect(
        ask('start again'),
        isA<CookGoTo>().having((a) => a.step, 'step', 1),
      );
    });

    test('questions', () {
      expect(
        ask('how much flour do I need'),
        isA<CookHowMuch>().having((a) => a.asked, 'asked', ['flour']),
      );
      expect(
        ask('how many eggs'),
        isA<CookHowMuch>().having((a) => a.asked, 'asked', ['eggs']),
      );
      expect(ask('how much time is left'), isA<CookTimeLeft>());
      expect(ask('what do I need'), isA<CookIngredients>());
    });

    test('timers, people and the end', () {
      expect(ask('start the timer'), isA<CookTimer>());
      expect(
        ask('make it for 6 people'),
        isA<CookServe>().having((a) => a.people, 'people', 6),
      );
      expect(
        ask('cooking for four'),
        isA<CookServe>().having((a) => a.people, 'people', 4),
      );
      expect(
        ask('double it'),
        isA<CookServe>().having((a) => a.times, 'times', 2),
      );
      expect(ask('stop cooking'), isA<CookDone>());
      expect(ask('shush'), isA<CookQuiet>());
    });

    test('anything else is left for the panel', () {
      expect(ask('play radio four'), isNull);
      expect(ask('show me the weather'), isNull);
    });
  });

  group('voice', () {
    final commands = VoiceCommands(
      pageCount: 1,
      pages: const [],
      widgets: const [],
    );

    test('a recipe by name, or the book', () {
      expect(
        commands.resolve("hey canvas let's cook the winter stew"),
        isA<VoiceCook>().having((a) => a.name, 'name', 'winter stew'),
      );
      expect(
        commands.resolve('show me my recipes'),
        isA<VoiceCook>().having((a) => a.name, 'name', isNull),
      );
      expect(
        commands.resolve('what can I cook'),
        isA<VoiceCook>().having((a) => a.name, 'name', isNull),
      );
    });
  });

  group('Kitchen', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('kitchen'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('keeps what is cooked, latest first, and finds it by name', () async {
      var fetched = 0;
      final kitchen = Kitchen(
        path: '${dir.path}/recipes.json',
        fetch: (url) async {
          fetched++;
          return page(stew);
        },
      );
      final r = (await kitchen.recipeAt('https://example.com/stew'))!;
      await kitchen.recipeAt('https://example.com/stew');
      expect(fetched, 1);
      final entry = kitchen.open(r);
      kitchen.leftAt(entry, step: 2, people: 6);
      final toast = Recipe.fromJsonLd({
        '@type': 'Recipe',
        'name': 'Cheese on toast',
        'recipeInstructions': ['Toast.'],
      })!;
      kitchen.open(toast);
      expect(kitchen.book.map((s) => s.recipe.name), [
        'Cheese on toast',
        "Sam's Winter Stew",
      ]);
      expect(kitchen.named('the stew')?.recipe.name, "Sam's Winter Stew");
      expect(kitchen.named('toast')?.recipe.name, 'Cheese on toast');
      expect(kitchen.named('lasagne'), isNull);

      await kitchen.saved;
      final again = Kitchen(path: '${dir.path}/recipes.json');
      await again.load();
      expect(again.book, hasLength(2));
      final stewBack = again.book.last;
      expect(stewBack.step, 2);
      expect(stewBack.people, 6);
      // Saved, it needs no page: asked again, it is the kept one.
      expect(
        (await again.recipeAt('https://example.com/stew'))?.name,
        "Sam's Winter Stew",
      );
    });

    test('a page with no recipe is none', () async {
      final kitchen = Kitchen(
        path: '${dir.path}/recipes.json',
        fetch: (url) async => '<html>nothing</html>',
      );
      expect(await kitchen.recipeAt('https://example.com/news'), isNull);
      expect(await kitchen.recipeAt('not a link'), isNull);
    });
  });
}
