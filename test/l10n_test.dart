import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/widgets.dart';
import 'package:home_canvas/l10n/l10n.dart';

void main() {
  tearDown(() => L10n.instance.debugUse('en-GB', const {}));

  test('placeholders and plurals, by each language\'s rules', () {
    expect(format('Hello {name}', {'name': 'Vince'}), 'Hello Vince');
    expect(format('Left {missing}', {}), 'Left {missing}');

    const shares = '{n, plural, =0{none} one{# share} other{# shares}}';
    expect(format(shares, {'n': 0}), 'none');
    expect(format(shares, {'n': 1}), '1 share');
    expect(format(shares, {'n': 12}), '12 shares');

    // Polish: one, few (2–4, 22–24…), many.
    const akcje = '{n, plural, one{# akcja} few{# akcje} many{# akcji} other{# akcji}}';
    expect(format(akcje, {'n': 1}, locale: 'pl'), '1 akcja');
    expect(format(akcje, {'n': 3}, locale: 'pl'), '3 akcje');
    expect(format(akcje, {'n': 5}, locale: 'pl'), '5 akcji');
    expect(format(akcje, {'n': 22}, locale: 'pl'), '22 akcje');

    // Welsh has a form for two.
    const cy = '{n, plural, zero{dim} one{un} two{dau} few{tri} many{chwech} other{#}}';
    expect(format(cy, {'n': 2}, locale: 'cy'), 'dau');
    expect(format(cy, {'n': 6}, locale: 'cy'), 'chwech');
  });

  test('a pack translates what it has and leaves the rest in British', () {
    L10n.instance.debugUse('fr', {'settings.language.title': 'Langue'});
    expect(tr('settings.language.title', 'Language'), 'Langue');
    expect(tr('settings.language.choose', 'Choose a language'),
        'Choose a language');
  });

  test('widget settings reach the editor translated by key', () {
    registerBuiltInWidgets();
    L10n.instance.debugUse('fr', {
      'widget.news.name': 'Actualités',
      'widget.news.option.sources.label': 'Flux',
      'widget.news.option.layout.choice.tabs': 'Un onglet par flux',
      'category.news & reference': 'Actualités et références',
    });
    final json = WidgetRegistry.find('news')!.toJson();
    expect(json['name'], 'Actualités');
    expect(json['categoryName'], 'Actualités et références');
    final options = <String, Map>{
      for (final o in (json['options'] as List).cast<Map>()) '${o['key']}': o,
    };
    expect(options['sources']!['label'], 'Flux');
    // Untranslated text stays as written.
    expect(options['sources']!['addLabel'], 'Add a feed');
    expect((options['layout']!['choices'] as Map)['tabs'], 'Un onglet par flux');
  });

  test('a pack is loaded from assets, or British English if there is none',
      () async {
    final bundle = _Bundle({
      'assets/l10n/de.arb':
          '{"@@locale": "de", "@@x-ai-created": true, "a.b": "Hallo"}',
    });
    await L10n.instance.use('de', bundle: bundle);
    expect(L10n.instance.code, 'de');
    expect(L10n.instance.language.aiCreated, isTrue);
    expect(tr('a.b', 'Hello'), 'Hallo');

    await L10n.instance.use('xx', bundle: bundle);
    expect(L10n.instance.code, 'en-GB');
    expect(tr('a.b', 'Hello'), 'Hello');
  });

  test('every language is offered by its own name, and AI ones say so', () {
    expect(kLanguages.first.code, kSourceLanguage);
    expect(kLanguages.first.aiCreated, isFalse);
    for (final l in kLanguages.skip(1)) {
      expect(l.aiCreated, isTrue, reason: l.code);
    }
    expect({for (final l in kLanguages) l.code}, hasLength(kLanguages.length));
  });
}

class _Bundle extends CachingAssetBundle {
  _Bundle(this.files);
  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final s = files[key];
    if (s == null) throw StateError('no $key');
    return ByteData.sublistView(Uint8List.fromList(s.codeUnits));
  }
}
