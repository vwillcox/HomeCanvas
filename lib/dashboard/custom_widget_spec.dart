import 'dart:convert';

import 'widget_registry.dart';
import '../time_format.dart';

/// A widget somebody wrote without rebuilding the app: a JSON file saying
/// what it is called, what settings it has, where its data comes from and
/// how to show it. See `lib/dashboard/widgets/README.md`.
///
/// It is a description, not a program. The panel reads it and draws what it
/// says; nothing in it is run. That is what lets it be uploaded from the
/// editor and work at once — a compiled app cannot take new code, but it can
/// take new instructions.
class CustomWidgetSpec {
  CustomWidgetSpec._({
    required this.id,
    required this.name,
    required this.description,
    required this.glyph,
    required this.defaultWidth,
    required this.defaultHeight,
    required this.minWidth,
    required this.minHeight,
    required this.options,
    required this.preview,
    required this.url,
    required this.headers,
    required this.every,
    required this.show,
    required this.source,
  });

  /// The name it was given in the file: `sea_state`.
  final String id;
  final String name;
  final String description;
  final String glyph;
  final int defaultWidth;
  final int defaultHeight;
  final int minWidth;
  final int minHeight;
  final List<WidgetOption> options;
  final List<String> preview;

  /// Where its data is fetched from, as a template — or null for a widget
  /// that only shows its settings.
  final String? url;
  final Map<String, String> headers;
  final Duration every;
  final CustomShow show;

  /// The file as it was uploaded, to be kept and handed back.
  final String source;

  /// What a dashboard saves it as. Prefixed, so a widget somebody uploads
  /// can never be mistaken for — or take the place of — one of the app's.
  String get type => '$typePrefix$id';
  static const typePrefix = 'custom_';

  /// The largest file taken: generous for a description, small for a
  /// mistake.
  static const maxBytes = 64 * 1024;

  static final _id = RegExp(r'^[a-z][a-z0-9_]{1,39}$');
  static final _key = RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,39}$');

  /// Reads a file. Throws a [FormatException] saying what is wrong with it,
  /// in words for whoever wrote it.
  factory CustomWidgetSpec.parse(String source) {
    if (utf8.encode(source).length > maxBytes) {
      throw const FormatException('The file is over 64 KB.');
    }
    final Object? j;
    try {
      j = jsonDecode(source);
    } on FormatException catch (e) {
      throw FormatException('Not valid JSON: ${e.message}');
    }
    if (j is! Map) {
      throw const FormatException('The file must be a JSON object.');
    }
    final Map<dynamic, dynamic> m = j;

    String text(String key, {String? or, int max = 400}) {
      final v = m[key] ?? or;
      if (v is! String || v.trim().isEmpty) {
        throw FormatException('"$key" is needed, as text.');
      }
      if (v.length > max) throw FormatException('"$key" is too long.');
      return v.trim();
    }

    int size(String key, int or) {
      final v = m[key] ?? or;
      if (v is! num || v < 1 || v > 12) {
        throw FormatException('"$key" must be a number from 1 to 12.');
      }
      return v.toInt();
    }

    var id = text('type', max: 60);
    if (id.startsWith(typePrefix)) id = id.substring(typePrefix.length);
    if (!_id.hasMatch(id)) {
      throw const FormatException(
        '"type" must be lower-case letters, digits and underscores, '
        'starting with a letter: sea_state.',
      );
    }

    final options = <WidgetOption>[];
    final listed = m['options'] ?? const [];
    if (listed is! List || listed.length > 30) {
      throw const FormatException('"options" must be a list of up to 30.');
    }
    for (final o in listed) {
      if (o is! Map) {
        throw const FormatException('Each option must be an object.');
      }
      final key = o['key'];
      if (key is! String || !_key.hasMatch(key)) {
        throw const FormatException(
          'Each option needs a "key" of letters, digits and underscores.',
        );
      }
      final kind = _kinds[o['kind'] ?? 'text'];
      if (kind == null) {
        throw FormatException(
          'Option "$key": "kind" must be one of ${_kinds.keys.join(', ')}.',
        );
      }
      final choices = o['choices'] ?? const {};
      if (choices is! Map) {
        throw FormatException('Option "$key": "choices" must be an object.');
      }
      if (kind == OptionKind.choice && choices.isEmpty) {
        throw FormatException('Option "$key" is a choice with no "choices".');
      }
      final fallback = o['default'] ?? o['defaultValue'];
      options.add(
        WidgetOption(
          key: key,
          label: o['label'] is String ? o['label'] as String : key,
          kind: kind,
          defaultValue: switch (kind) {
            OptionKind.number => fallback is num ? fallback : 0,
            OptionKind.boolean => fallback == true,
            _ => fallback == null ? '' : '$fallback',
          },
          choices: {for (final e in choices.entries) '${e.key}': '${e.value}'},
          help: o['help'] is String ? o['help'] as String : null,
        ),
      );
    }

    String? url;
    var headers = const <String, String>{};
    var every = const Duration(minutes: 5);
    final from = m['source'];
    if (from != null) {
      if (from is! Map || from['url'] is! String) {
        throw const FormatException('"source" needs a "url".');
      }
      url = (from['url'] as String).trim();
      if (!RegExp(r'^(https?://|\{\{)').hasMatch(url)) {
        throw const FormatException(
          '"source.url" must start with http:// or https://.',
        );
      }
      final h = from['headers'] ?? const {};
      if (h is! Map || h.length > 10) {
        throw const FormatException('"source.headers" must be an object.');
      }
      headers = {for (final e in h.entries) '${e.key}': '${e.value}'};
      final seconds = from['every'] ?? 300;
      if (seconds is! num) {
        throw const FormatException('"source.every" must be seconds.');
      }
      // Never oftener than twice a minute: it is somebody else's server.
      every = Duration(seconds: seconds.toInt().clamp(30, 86400));
    }

    final preview = m['preview'] ?? const [];
    if (preview is! List) {
      throw const FormatException('"preview" must be a list of lines.');
    }

    return CustomWidgetSpec._(
      id: id,
      name: text('name', max: 60),
      description: text('description', or: 'A custom widget.'),
      glyph: text('glyph', or: '🧩', max: 16),
      defaultWidth: size('defaultWidth', 3),
      defaultHeight: size('defaultHeight', 2),
      minWidth: size('minWidth', 1),
      minHeight: size('minHeight', 1),
      options: options,
      preview: [for (final p in preview.take(4)) '$p'],
      url: url,
      headers: headers,
      every: every,
      show: CustomShow.parse(m['show'], hasSource: url != null),
      source: source,
    );
  }

  /// The kinds of setting a file may ask for. Not `list`, whose rows of
  /// fields a template has no way to walk.
  static const _kinds = {
    'text': OptionKind.text,
    'number': OptionKind.number,
    'boolean': OptionKind.boolean,
    'choice': OptionKind.choice,
    'multiline': OptionKind.multiline,
    'secret': OptionKind.secret,
    'date': OptionKind.date,
  };

  /// For the editor's list of what is installed.
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'name': name,
    'glyph': glyph,
    'description': description,
  };
}

/// How a custom widget lays out what it has.
enum CustomLayout { value, cards, list }

/// One card of a `cards` layout, or the lines of a `value` one.
class CustomCard {
  const CustomCard({this.glyph = '', this.label = '', this.value = ''});

  final String glyph;
  final String label;
  final String value;
}

class CustomShow {
  const CustomShow._({
    required this.layout,
    this.title = '',
    this.value = '',
    this.detail = '',
    this.cards = const [],
    this.items = '',
    this.limit = 6,
    this.trailing = '',
  });

  final CustomLayout layout;

  /// `value`: a line above, the figure, a line below. `list`: each row's
  /// text, and what goes at its end.
  final String title;
  final String value;
  final String detail;
  final String trailing;

  final List<CustomCard> cards;

  /// `list`: the path to the array the rows come from.
  final String items;
  final int limit;

  static String _text(Object? v) => v is String ? v : '';

  factory CustomShow.parse(Object? j, {required bool hasSource}) {
    if (j is! Map) {
      throw const FormatException('"show" is needed: how to draw it.');
    }
    switch (j['kind']) {
      case 'value':
        if (j['value'] is! String) {
          throw const FormatException('A "value" layout needs a "value".');
        }
        return CustomShow._(
          layout: CustomLayout.value,
          title: _text(j['title']),
          value: j['value'] as String,
          detail: _text(j['detail']),
        );
      case 'cards':
        final cards = j['cards'];
        if (cards is! List || cards.isEmpty || cards.length > 12) {
          throw const FormatException(
            'A "cards" layout needs 1 to 12 "cards".',
          );
        }
        return CustomShow._(
          layout: CustomLayout.cards,
          cards: [
            for (final c in cards)
              if (c is Map && c['value'] is String)
                CustomCard(
                  glyph: _text(c['glyph']),
                  label: _text(c['label']),
                  value: c['value'] as String,
                )
              else
                throw const FormatException('Each card needs a "value".'),
          ],
        );
      case 'list':
        if (!hasSource || j['items'] is! String || j['title'] is! String) {
          throw const FormatException(
            'A "list" layout needs a "source", and "items" — the path to '
            'the list — and a "title" for each row.',
          );
        }
        final limit = j['limit'] ?? 6;
        return CustomShow._(
          layout: CustomLayout.list,
          items: j['items'] as String,
          title: j['title'] as String,
          trailing: _text(j['trailing']),
          limit: limit is num ? limit.toInt().clamp(1, 20) : 6,
        );
    }
    throw const FormatException('"show.kind" must be value, cards or list.');
  }
}

/// Finds [path] — `current.wave_height`, `hourly.time[0]`, `rows.2.name` —
/// in decoded JSON. Null where there is nothing there.
Object? customLookup(Object? data, String path) {
  Object? at = data;
  for (final part in path.replaceAll('[', '.').replaceAll(']', '').split('.')) {
    if (part.isEmpty) continue;
    if (at is Map) {
      at = at[part];
    } else if (at is List) {
      final i = int.tryParse(part);
      at = i == null || i < 0 || i >= at.length ? null : at[i];
    } else {
      return null;
    }
  }
  return at;
}

final _slot = RegExp(r'\{\{(.*?)\}\}');
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Fills in a template. `{{current.wave_height}}` is looked up in [data];
/// `{{option.place}}` in the widget's settings; `{{item.name}}` in the row
/// being drawn. After a bar, what to do with it: `{{x | number:1}}`,
/// `{{x | percent}}`, `{{x | times:3.6 | round}}`, `{{x | time}}`,
/// `{{x | date}}`, `{{x | upper}}`, `{{x | or:nothing}}`. What is missing
/// is a dash — or, with [encode] for a URL, nothing.
String customFill(
  String template, {
  Object? data,
  Map<String, dynamic> options = const {},
  Object? item,
  bool encode = false,
}) => template.replaceAllMapped(_slot, (m) {
  final steps = m[1]!.split('|').map((s) => s.trim()).toList();
  final path = steps.first;
  Object? v = path.startsWith('option.')
      ? options[path.substring(7)]
      : path == 'item'
      ? item
      : path.startsWith('item.')
      ? customLookup(item, path.substring(5))
      : customLookup(data, path);
  for (final step in steps.skip(1)) {
    final colon = step.indexOf(':');
    final name = colon < 0 ? step : step.substring(0, colon).trim();
    final arg = colon < 0 ? '' : step.substring(colon + 1).trim();
    final n = v is num ? v : num.tryParse('${v ?? ''}');
    final at = v is String ? DateTime.tryParse(v)?.toLocal() : null;
    v = switch (name) {
      'number' => n?.toStringAsFixed(int.tryParse(arg) ?? 0),
      'round' => n?.round(),
      'percent' => n == null ? null : '${(n * 100).round()}%',
      'times' => n == null ? null : n * (num.tryParse(arg) ?? 1),
      'plus' => n == null ? null : n + (num.tryParse(arg) ?? 0),
      'upper' => v?.toString().toUpperCase(),
      'lower' => v?.toString().toLowerCase(),
      'time' => at == null ? v : hhmm(at),
      'date' => at == null ? v : '${at.day} ${_months[at.month - 1]}',
      'or' => v == null || '$v'.isEmpty ? arg : v,
      _ => v,
    };
  }
  if (v == null) return encode ? '' : '—';
  // 21.0 reads as 21; a figure with more to it is left alone.
  final text = v is double && v == v.roundToDouble() ? '${v.round()}' : '$v';
  return encode ? Uri.encodeQueryComponent(text) : text;
});
