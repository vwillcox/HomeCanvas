import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

import 'dashboard_model.dart';
import 'live_preview.dart';
import 'dashboard_theme.dart';

/// The kind of control the web editor should offer for an option.
///
/// [list] is a repeating group: the option holds a list of records, each with
/// the fields named in [WidgetOption.fields], and the editor gives it a plus
/// to add a row and a cross to remove one. Generic rather than specific to
/// the calendar's several feeds, so the next widget that needs a repeating
/// setting gets one for free.
///
/// [secret] is text the editor shows as dots — an API key or token — so it is
/// not on show to whoever is looking at the screen while the dashboard is set
/// up. It is stored like any other option.
///
/// [date] is a day, picked from the browser's calendar and stored as
/// `YYYY-MM-DD`.
enum OptionKind {
  text,
  number,
  boolean,
  choice,
  multiline,
  colour,
  list,
  secret,
  date,
}

/// One setting a widget type accepts.
///
/// The editor builds its form from these, so a new widget's settings appear
/// in the browser without a line of editor code. Keep [key] stable: it is
/// what ends up in the saved configuration.
class WidgetOption {
  final String key;
  final String label;
  final OptionKind kind;
  final Object? defaultValue;

  /// For [OptionKind.choice]: the allowed values, and what to call them.
  final Map<String, String> choices;

  /// For [OptionKind.choice]: the name of a list the *kiosk* supplies, rather
  /// than one written here — currently only `albums`.
  ///
  /// Needed because some choices are not knowable when the widget is
  /// declared: which albums exist is a property of somebody's Immich server,
  /// changes without this app being rebuilt, and cannot be a const map.
  /// The editor fills these from the schema at render time.
  final String? choicesFrom;

  /// Shown under the field. Say what the setting is for, not what it is.
  final String? help;

  /// For [OptionKind.list]: the fields of one row.
  final List<WidgetOption> fields;

  /// For [OptionKind.list]: what to call a row on the button that adds one.
  final String addLabel;

  const WidgetOption({
    required this.key,
    this.choicesFrom,
    required this.label,
    this.kind = OptionKind.text,
    this.defaultValue,
    this.choices = const {},
    this.help,
    this.fields = const [],
    this.addLabel = 'Add',
  });

  /// For the editor, with the text in the panel's language where its pack
  /// has it. [at] is the stem of this option's keys —
  /// `widget.news.option.sources` — or null to leave it in British English.
  Map<String, dynamic> toJson({String? at}) {
    String t(String what, String english) =>
        at == null ? english : (L10n.instance.lookup('$at.$what') ?? english);
    return {
      'key': key,
      'label': t('label', label),
      'kind': kind.name,
      'default': defaultValue,
      'choices': {
        for (final e in choices.entries) e.key: t('choice.${e.key}', e.value),
      },
      'choicesFrom': choicesFrom,
      'help': help == null ? null : t('help', help!),
      'fields': [
        for (final f in fields)
          f.toJson(at: at == null ? null : '$at.field.${f.key}'),
      ],
      'addLabel': t('addLabel', addLabel),
    };
  }

  /// Every piece of this option's text, by key, in British English — what a
  /// language pack translates.
  Iterable<(String, String)> texts(String at) sync* {
    yield ('$at.label', label);
    if (help != null) yield ('$at.help', help!);
    if (kind == OptionKind.list) yield ('$at.addLabel', addLabel);
    for (final e in choices.entries) {
      yield ('$at.choice.${e.key}', e.value);
    }
    for (final f in fields) {
      yield* f.texts('$at.field.${f.key}');
    }
  }
}

/// Everything a widget's builder is handed.
class DashboardWidgetContext {
  final DashboardWidgetConfig config;
  final DashboardTheme theme;

  const DashboardWidgetContext({required this.config, required this.theme});

  /// Read an option, falling back to the type's declared default and then to
  /// [fallback]. Widgets should always go through this rather than reading
  /// `config.options` directly, so a config saved before an option existed
  /// still behaves.
  T option<T>(String key, T fallback) {
    final v = config.options[key];
    if (v is T) return v;
    // JSON numbers arrive as int or double depending on how they were written.
    if (T == double && v is num) return v.toDouble() as T;
    if (T == int && v is num) return v.toInt() as T;
    return fallback;
  }

  /// Rows of an [OptionKind.list] option.
  List<Map<String, dynamic>> rows(String key) =>
      (config.options[key] as List?)
          ?.whereType<Map>()
          .map((r) => r.cast<String, dynamic>())
          .toList() ??
      const [];
}

/// The groups the editor's palette sorts widgets into, in the order it shows
/// them. A type names its own, so a new widget lands in the right group
/// without the editor being touched.
class WidgetCategory {
  WidgetCategory._();

  static const timeAndDay = 'Time & day';
  static const weather = 'Weather & air';
  static const photosAndMedia = 'Photos, music & TV';
  static const house = 'Around the house';
  static const gettingOut = 'Getting out';
  static const reference = 'News & reference';
  static const network = 'Network';

  /// Ubiquiti's own: a brand has its group, so its tiles are found together.
  static const unifi = 'UniFi';
  static const homeLab = 'Home lab';
  static const other = 'Other';

  /// [category]'s name in the panel's language. The British name is also
  /// its id — saved in nothing, but the editor groups by it.
  static String localName(String category) =>
      L10n.instance.lookup('category.${category.toLowerCase()}') ?? category;

  static const order = [
    timeAndDay,
    weather,
    photosAndMedia,
    house,
    gettingOut,
    reference,
    network,
    unifi,
    homeLab,
    other,
  ];
}

/// A line of stand-in content for the browser editor's preview.
///
/// Declared by the widget type rather than drawn by the editor, so a new
/// widget previews itself without the editor learning anything about it.
/// [scale] is relative to the tile's height, which is what keeps a preview
/// honest as the tile is resized — for text that grows with its tile.
///
/// Text drawn at a fixed size gives [px] instead: its font size on the panel,
/// before the widget's text size and any shrink. A news headline is 15 points
/// on a tile of any height, and previewing it as a share of a tall tile drew
/// it three times too big.
///
/// `{time}` and `{date}` are substituted with the real ones, so a clock
/// preview shows the actual time rather than a fixed 09:41.
class PreviewLine {
  final String text;
  final double scale;
  final bool muted;
  final bool accent;
  final double? px;

  /// Centred rather than ranged left, matching how the widget itself lays the
  /// line out.
  final bool centre;

  const PreviewLine(
    this.text, {
    this.scale = 0.14,
    this.muted = false,
    this.accent = false,
    this.centre = false,
    this.px,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'scale': scale,
    if (px != null) 'px': px,
    'muted': muted,
    'accent': accent,
    'centre': centre,
  };
}

/// A widget type the dashboard can show.
class DashboardWidgetType {
  /// Stable identifier stored in the config. Never rename one in place.
  final String type;

  final String name;
  final String description;

  /// Shown in the web editor's palette. An emoji keeps the editor free of
  /// icon fonts and dependencies.
  final String glyph;

  final int defaultWidth;
  final int defaultHeight;
  final int minWidth;
  final int minHeight;

  final List<WidgetOption> options;

  /// Stand-in content for the editor's preview, used when [live] is absent
  /// or has nothing yet.
  final List<PreviewLine> preview;

  /// The real thing, for the editor's preview: what this widget would be
  /// showing right now. Returning an empty list falls back to [preview].
  final List<PreviewLine> Function(
    DashboardWidgetConfig config,
    PreviewData data,
  )?
  live;

  final Widget Function(BuildContext context, DashboardWidgetContext w) build;

  /// The widget sizes its own text from the space it is given, so the tile
  /// should not also shrink it by [contentScale].
  ///
  /// The generic shrink judges by whichever dimension shrank most, which
  /// suits a widget with fixed type. It is exactly wrong for one that fills
  /// its tile: a list on a wide, one-row strip was cut to 45% for being short,
  /// and rendered its names at seven pixels on a tile with room for forty.
  final bool fitsItself;

  /// Which group of the editor's palette it is listed under — one of
  /// [WidgetCategory]'s.
  final String category;

  const DashboardWidgetType({
    required this.type,
    required this.name,
    required this.description,
    required this.glyph,
    required this.build,
    this.defaultWidth = 3,
    this.defaultHeight = 2,
    this.minWidth = 1,
    this.minHeight = 1,
    this.options = const [],
    this.preview = const [],
    this.live,
    this.fitsItself = false,
    this.category = WidgetCategory.other,
  });

  /// How much to shrink this widget's contents at [width]x[height] cells.
  ///
  /// Widgets declare a default size that their fixed font sizes and paddings
  /// suit. Placed smaller than that — and every widget can now go down to
  /// 1x1 — those sizes no longer fit, so text is scaled by however much the
  /// tile has shrunk.
  ///
  /// Taken from whichever dimension shrank *most*, since text that fits the
  /// width but not the height is no better off.
  ///
  /// Only ever shrinks. Growing the text on a larger tile sounds symmetrical
  /// and is not: widgets that should fill a big tile already do it themselves
  /// with FittedBox or a LayoutBuilder, and scaling their fixed sizes up on
  /// top of that would overflow layouts that were fine.
  ///
  /// Floored, because past a point smaller text stops being readable and the
  /// honest answer is that the widget is too small — better to clip something
  /// legible than to render everything at two points.
  double contentScale(int width, int height) {
    final byWidth = width / (defaultWidth <= 0 ? 1 : defaultWidth);
    final byHeight = height / (defaultHeight <= 0 ? 1 : defaultHeight);
    final smallest = byWidth < byHeight ? byWidth : byHeight;
    return smallest.clamp(0.45, 1.0);
  }

  /// The stem of this type's keys in a language pack: `widget.news`.
  String get _at => 'widget.$type';

  /// Its name in the panel's language.
  String get localName => L10n.instance.lookup('$_at.name') ?? name;

  Map<String, dynamic> toJson() => {
    'type': type,
    'name': localName,
    'description': L10n.instance.lookup('$_at.description') ?? description,
    'glyph': glyph,
    'category': category,
    'categoryName': WidgetCategory.localName(category),
    'defaultWidth': defaultWidth,
    'defaultHeight': defaultHeight,
    'minWidth': minWidth,
    'minHeight': minHeight,
    // So the editor's preview skips the shrink the panel skips.
    'fitsItself': fitsItself,
    'options': [
      for (final o in options) o.toJson(at: '$_at.option.${o.key}'),
    ],
    'preview': preview.map((p) => p.toJson()).toList(),
  };

  /// Every piece of this type's text, by key, in British English.
  Iterable<(String, String)> texts() sync* {
    yield ('$_at.name', name);
    yield ('$_at.description', description);
    for (final o in options) {
      yield* o.texts('$_at.option.${o.key}');
    }
  }
}

/// Every widget type the build knows about.
///
/// To add one: write the widget, then register it here. Nothing else needs
/// touching — the editor's palette, its settings form, and the saved
/// configuration all follow from the descriptor. See
/// `lib/dashboard/widgets/README.md`.
class WidgetRegistry {
  WidgetRegistry._();

  static final Map<String, DashboardWidgetType> _types = {};

  static void register(DashboardWidgetType type) {
    _types[type.type] = type;
  }

  static void registerAll(Iterable<DashboardWidgetType> types) {
    for (final t in types) {
      register(t);
    }
  }

  static DashboardWidgetType? find(String type) => _types[type];

  static List<DashboardWidgetType> get all => _types.values.toList();

  /// Options filled in with their declared defaults, for a newly added widget.
  static Map<String, dynamic> defaultsFor(String type) {
    final t = _types[type];
    if (t == null) return {};
    return {
      for (final o in t.options)
        if (o.defaultValue != null) o.key: o.defaultValue,
    };
  }
}
