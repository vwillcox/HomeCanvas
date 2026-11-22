import 'dart:ui' show Color;

/// The deck as StreamerDeck on the computer draws it out for the panel:
/// every profile, every page, each key's look in each state — enough to
/// show any of it, and move between them, with the computer off.
///
/// Sent whole as `{"t": "deck", …}` whenever it changes; kept on disk as
/// it came, so the deck opens with the last one even before the computer
/// has said anything. See the StreamerDeck repository's docs/PROTOCOL.md.
class DeckSnapshot {
  const DeckSnapshot({required this.active, required this.profiles});

  final String active;
  final List<DeckProfile> profiles;

  static DeckSnapshot? fromJson(Object? j) {
    if (j is! Map) return null;
    final profiles = [
      for (final p in (j['profiles'] as List? ?? const []))
        if (DeckProfile.fromJson(p) case final DeckProfile d) d,
    ];
    if (profiles.isEmpty) return null;
    return DeckSnapshot(active: '${j['active'] ?? ''}', profiles: profiles);
  }

  DeckProfile profile(String? id) =>
      profiles.firstWhere((p) => p.id == id, orElse: () => profiles.firstWhere((p) => p.id == active, orElse: () => profiles.first));

  /// Every image any key shows, for asking the computer for those not here.
  Set<String> get images => {
    for (final p in profiles)
      for (final page in p.pages) ...page.images,
  };

  /// A key anywhere, by id.
  DeckKey? key(String id) {
    for (final p in profiles) {
      for (final page in p.pages) {
        final k = page.find(id);
        if (k != null) return k;
      }
    }
    return null;
  }
}

class DeckProfile {
  const DeckProfile({
    required this.id,
    required this.name,
    required this.cols,
    required this.rows,
    required this.pages,
  });

  final String id;
  final String name;
  final int cols;
  final int rows;
  final List<DeckPage> pages;

  static DeckProfile? fromJson(Object? j) {
    if (j is! Map) return null;
    final pages = [
      for (final p in (j['pages'] as List? ?? const []))
        if (DeckPage.fromJson(p) case final DeckPage d) d,
    ];
    final cols = _int(j['cols'], 5).clamp(1, 16);
    final rows = _int(j['rows'], 3).clamp(1, 12);
    return DeckProfile(
      id: '${j['id'] ?? ''}',
      name: '${j['name'] ?? ''}',
      cols: cols,
      rows: rows,
      pages: pages.isEmpty ? [const DeckPage(id: '', name: '', keys: [])] : pages,
    );
  }
}

class DeckPage {
  const DeckPage({required this.id, required this.name, required this.keys});

  final String id;
  final String name;
  final List<DeckKey> keys;

  static DeckPage? fromJson(Object? j) {
    if (j is! Map) return null;
    return DeckPage(
      id: '${j['id'] ?? ''}',
      name: '${j['name'] ?? ''}',
      keys: [
        for (final k in (j['keys'] as List? ?? const []))
          if (DeckKey.fromJson(k) case final DeckKey d) d,
      ],
    );
  }

  DeckKey? at(int col, int row) {
    for (final k in keys) {
      if (k.col == col && k.row == row) return k;
    }
    return null;
  }

  DeckKey? find(String id) {
    for (final k in keys) {
      if (k.id == id) return k;
      for (final p in k.pages ?? const <DeckPage>[]) {
        final f = p.find(id);
        if (f != null) return f;
      }
    }
    return null;
  }

  Iterable<String> get images sync* {
    for (final k in keys) {
      for (final l in k.looks) {
        if (l.image != null) yield l.image!;
      }
      for (final p in k.pages ?? const <DeckPage>[]) {
        yield* p.images;
      }
    }
  }
}

/// Where a key's action is done.
enum DeckRuns {
  /// On the computer: the panel only says it was pressed.
  pc,

  /// Here, on the panel: its lights, its routines.
  panel,

  /// Moving between pages, folders and profiles, here.
  nav,
}

class DeckKey {
  const DeckKey({
    required this.id,
    required this.col,
    required this.row,
    required this.action,
    required this.runs,
    required this.state,
    required this.looks,
    this.settings = const {},
    this.pages,
    this.steps,
  });

  final String id;
  final int col;
  final int row;

  /// The action's id: `deck.hotkey`, `hc.ha.toggle`, a plugin's own.
  final String action;
  final DeckRuns runs;
  final int state;

  /// One per state.
  final List<DeckLook> looks;

  /// What it needs to do its work here; empty for a computer's key.
  final Map<String, Object?> settings;

  /// A folder's own pages.
  final List<DeckPage>? pages;

  /// A multi action the panel runs: each step's action and settings.
  final List<Map<String, Object?>>? steps;

  bool get isFolder => pages != null;

  DeckLook look(int state) =>
      looks.isEmpty ? DeckLook.blank : looks[state.clamp(0, looks.length - 1)];

  String setting(String k) => '${settings[k] ?? ''}'.trim();

  static DeckKey? fromJson(Object? j) {
    if (j is! Map) return null;
    final pos = j['pos'];
    if (pos is! List || pos.length != 2) return null;
    final pages = j['pages'];
    final steps = j['steps'];
    final settings = j['settings'];
    return DeckKey(
      id: '${j['id'] ?? ''}',
      col: _int(pos[0], 0),
      row: _int(pos[1], 0),
      action: '${j['action'] ?? ''}',
      runs: switch (j['runs']) {
        'panel' => DeckRuns.panel,
        'nav' => DeckRuns.nav,
        _ => DeckRuns.pc,
      },
      state: _int(j['state'], 0),
      looks: [
        for (final l in (j['looks'] as List? ?? const []))
          if (l is Map) DeckLook.fromJson(l),
      ],
      settings: settings is Map ? settings.cast<String, Object?>() : const {},
      pages: pages is List
          ? [
              for (final p in pages)
                if (DeckPage.fromJson(p) case final DeckPage d) d,
            ]
          : null,
      steps: steps is List
          ? [
              for (final s in steps)
                if (s is Map) s.cast<String, Object?>(),
            ]
          : null,
    );
  }
}

/// How a key looks in one state — sizes as on a 72-pixel key, scaled to
/// the key it is drawn on.
class DeckLook {
  const DeckLook({
    this.image,
    this.color,
    this.title = '',
    this.showTitle = true,
    this.titleColor = const Color(0xFFFFFFFF),
    this.align = 'bottom',
    this.size = 12,
    this.style = '',
    this.family = '',
    this.underline = false,
  });

  static const blank = DeckLook();

  final String? image;
  final Color? color;
  final String title;
  final bool showTitle;
  final Color titleColor;
  final String align;
  final double size;
  final String style;
  final String family;
  final bool underline;

  bool get bold => style.contains('Bold');
  bool get italic => style.contains('Italic');

  factory DeckLook.fromJson(Map j) => DeckLook(
    image: j['img'] is String && (j['img'] as String).isNotEmpty ? j['img'] as String : null,
    color: parseColour(j['color']),
    title: '${j['title'] ?? ''}',
    showTitle: j['show'] != false,
    titleColor: parseColour(j['tcolor']) ?? const Color(0xFFFFFFFF),
    align: '${j['align'] ?? 'bottom'}',
    size: (j['size'] is num) ? (j['size'] as num).toDouble().clamp(4, 80) : 12,
    style: '${j['style'] ?? ''}',
    family: '${j['family'] ?? ''}',
    underline: j['underline'] == true,
  );
}

/// "#rrggbb" or "#rrggbbaa"; null for anything else.
Color? parseColour(Object? v) {
  if (v is! String) return null;
  final h = v.trim().replaceFirst('#', '');
  if (!RegExp(r'^([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(h)) return null;
  final n = int.parse(h, radix: 16);
  return h.length == 6 ? Color(0xFF000000 | n) : Color(((n & 0xFF) << 24) | (n >> 8));
}

int _int(Object? v, int fallback) => v is num ? v.toInt() : int.tryParse('$v') ?? fallback;
