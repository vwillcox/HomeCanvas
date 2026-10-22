import 'dart:math';

/// The words that wake the panel — "hey canvas", or ones chosen in the
/// installer — and what they have been heard as.
///
/// The hearing is the listener's (`deploy/voice_listener.py`, with
/// `deploy/wake_word.py`); this is the same reckoning for the kiosk, which
/// needs to know where the wake words end in something typed to it, and to
/// take them off before a request goes to Home Assistant.
/// `test/fixtures/wake_words.json` holds the cases both are checked against.
class WakeWord {
  WakeWord({
    String phrase = defaultPhrase,
    List<String>? lookalikes,
    List<String> variants = const [],
  }) : this._(
         _words(phrase).isEmpty ? _words(defaultPhrase) : _words(phrase),
         lookalikes,
         variants,
       );

  WakeWord._(List<String> said, List<String>? lookalikes, List<String> variants)
    : name = said.last,
      greeting = said.sublist(0, said.length - 1),
      lookalikes = {
        for (final l
            in lookalikes ??
                (said.join(' ') == defaultPhrase ? canvasLookalikes : const []))
          ..._words(l).take(1),
      }.toList()..sort(),
      variants = _variantsOf(variants);

  factory WakeWord.fromJson(Object? j) {
    if (j is! Map) return WakeWord();
    return WakeWord(
      phrase: '${j['phrase'] ?? defaultPhrase}',
      lookalikes: j.containsKey('lookalikes')
          ? [for (final w in (j['lookalikes'] as List? ?? const [])) '$w']
          : null,
      variants: [for (final v in (j['variants'] as List? ?? const [])) '$v'],
    );
  }

  static const defaultPhrase = 'hey canvas';

  /// What "canvas" has been heard as, after a "hey", that is not within a
  /// letter or two of it. All of them from recordings at the panel.
  static const canvasLookalikes = [
    'cambus', 'campus', 'congress', 'douglas', 'countless', 'compass', //
  ];

  /// What a greeting word has been heard as.
  static const greetingForms = {
    'hey': {'hey', 'hay', 'hi', 'he', 'a', 'eh', 'hate', 'hedy', 'hake', 'hae'},
    'hi': {'hi', 'hey', 'high', 'hai'},
    'okay': {'okay', 'ok', 'o', 'k'},
    'ok': {'okay', 'ok', 'o', 'k'},
  };

  /// The last word of the phrase: "canvas".
  final String name;

  /// The words before it, if any: "hey".
  final List<String> greeting;

  /// Words heard in place of [name], after the greeting.
  final List<String> lookalikes;

  /// Whole phrases heard in place of the phrase.
  final List<List<String>> variants;

  String get phrase => [...greeting, name].join(' ');

  Map<String, dynamic> toJson() => {
    'phrase': phrase,
    'lookalikes': lookalikes,
    'variants': [for (final v in variants) v.join(' ')],
  };

  static List<List<String>> _variantsOf(List<String> variants) {
    final seen = <List<String>>[];
    for (final v in variants) {
      final said = _words(v);
      if (said.isNotEmpty &&
          said.length <= 5 &&
          !seen.any((s) => s.join(' ') == said.join(' '))) {
        seen.add(said);
      }
    }
    return seen;
  }

  /// [text] as words, as the listener has them.
  static List<String> _words(String text) => text
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp('[’\']'), '')
      .replaceAll(RegExp('[^a-z0-9]+'), ' ')
      .trim()
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList();

  Set<String> get _nameForms => {name, '${name}s', '${name}es'};

  /// Whether [word], at the start of something said, is one of the wake
  /// words as they might be heard — for taking them off the front.
  bool isWakeWord(String word) =>
      _nameForms.contains(word) ||
      greeting.any((g) => _greets(word, g)) ||
      lookalikes.contains(word);

  bool _greets(String heard, String want) =>
      heard == want ||
      (greetingForms[want]?.contains(heard) ?? false) ||
      (want.length >= 4 && _slips(heard, want) <= 1);

  /// Where the wake words end in [text], counted in words; 0 for none. As
  /// `WakeWord.ends` in deploy/wake_word.py.
  int ends(String text) {
    final said = _words(text);
    final whole = [...greeting, name];
    final all = [...variants, whole]
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final v in all) {
      for (final start in [0, 1]) {
        if (start + v.length <= said.length &&
            said.sublist(start, start + v.length).join(' ') == v.join(' ')) {
          return start + v.length;
        }
      }
    }
    if (name.length >= 4) {
      final near = max(4, greeting.length + 2);
      for (final (i, w) in said.take(near).indexed) {
        if (_nameForms.contains(w)) return i + 1;
      }
    }
    final g = greeting.length;
    if (said.length > g &&
        greeting.indexed.every((e) => _greets(said[e.$1], e.$2))) {
      final heard = said[g];
      if (lookalikes.contains(heard) ||
          (name.length >= 5 && _slips(heard, name) <= 2)) {
        return g + 1;
      }
    }
    return 0;
  }

  /// How many letters apart [a] and [b] are.
  static int _slips(String a, String b) {
    var row = [for (var j = 0; j <= b.length; j++) j];
    for (var i = 1; i <= a.length; i++) {
      final next = [i];
      for (var j = 1; j <= b.length; j++) {
        final swap = row[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
        next.add([row[j] + 1, next[j - 1] + 1, swap].reduce(min));
      }
      row = next;
    }
    return row.last;
  }
}
