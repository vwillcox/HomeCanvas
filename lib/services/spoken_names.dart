import 'home_assistant_service.dart' show AssistReply;
import 'voice_commands.dart';
import 'voice_service.dart' show VoiceAnswer;

/// Asks Home Assistant's Assist about one thing said, [heard] as each
/// recogniser made it out, best first — each as [request] has it.
///
/// The first hearing it does something with is the answer. Failing that,
/// each is tried again with the device in it put right by the [names] Home
/// Assistant has — see [SpokenNames]; and failing that, the first refusal
/// is the answer ("not aware of any device called you one"), for it says
/// what went wrong. Null when Assist made nothing of any of it.
///
/// [names] is only asked for once every hearing has failed.
Future<VoiceAnswer?> askAssist(
  List<String> heard, {
  required String Function(String heard) request,
  required Future<AssistReply?> Function(String request) ask,
  required Future<SpokenNames> Function() names,
}) async {
  VoiceAnswer? refusal;
  for (final h in heard) {
    final reply = await ask(request(h));
    if (reply == null) continue;
    if (reply.done) return (heard: h, answer: reply.speech);
    refusal ??= (heard: h, answer: reply.speech);
  }
  final known = await names();
  final tried = <String>{};
  for (final h in heard) {
    final fixed = known.correct(request(h));
    if (fixed == null || !tried.add(fixed)) continue;
    final reply = await ask(fixed);
    if (reply != null && reply.done) {
      return (heard: fixed, answer: reply.speech);
    }
  }
  return refusal;
}

/// Puts right the name of a device misheard in a request to switch it:
/// "turn around you one on" is "turn on lounge one", when Lounge 1 is
/// what Home Assistant has and nothing sounds more like it.
///
/// The recognisers know no names. "Lounge" said across a room has come out
/// as "around you", "lunch" and "launch", and Assist, asked about a light
/// called any of those, can only say it has none. This compares what was
/// heard with the names it does have, by how they sound, and offers the one
/// that is clearly nearest — or nothing, when none is.
///
/// Only ever a second try: the panel asks Assist with the words as heard
/// first, so an alias Assist knows and this does not ("hall light") is
/// never rewritten into something else.
class SpokenNames {
  SpokenNames(Iterable<String> names, {Iterable<String> areas = const []})
    : _areas = {
        for (final a in areas)
          if (_spoken(a) case final w when w.isNotEmpty) w.join(' '),
      },
      _names = {
        for (final n in [...names, ...areas])
          if (_spoken(n) case final w when w.isNotEmpty) w.join(' '): w,
      }.values.toList();

  final List<List<String>> _names;

  /// Which of them are rooms: "the living rum lights" is the living room's
  /// lights, not the whole room.
  final Set<String> _areas;

  /// How alike, from 0 to 1, the nearest must sound — and how much nearer
  /// than the next it must be. Tried against the names in the house: the
  /// mishearings of "lounge one" come out at 0.6 and above, the next name
  /// at 0.36 at most, and words that name nothing there ("kettle") at 0.42.
  static const _enough = 0.55;
  static const _clearly = 0.15;

  static const _numbers = {
    '0': 'zero', '1': 'one', '2': 'two', '3': 'three', '4': 'four', //
    '5': 'five', '6': 'six', '7': 'seven', '8': 'eight', '9': 'nine',
    '10': 'ten', '11': 'eleven', '12': 'twelve',
  };

  /// What a number at the end of a name is heard as: "socket to".
  static const _soundsLikeNumber = {
    'won': 'one', 'to': 'two', 'too': 'two', 'for': 'four', 'fore': 'four', //
    'ate': 'eight', 'tree': 'three',
  };

  /// [name] as words, numbers as said: "Lounge 1" is "lounge one".
  static List<String> _spoken(String name) => [
    for (final w in VoiceCommands.words(name)) _numbers[w] ?? w,
  ];

  static bool _isNumber(String w) => _numbers.containsValue(w);

  /// [request] with the device in it put right — "turn on lounge one" —
  /// or null when it is not a request to switch something, it names
  /// something already, or nothing sounds clearly like it.
  String? correct(String request) {
    final said = VoiceCommands.words(request);
    if (said.isEmpty) return null;
    // "Turn on X", "switch X off", "X off".
    var rest = said;
    if (const {'turn', 'switch', 'put', 'power'}.contains(rest.first)) {
      rest = rest.sublist(1);
    }
    if (rest.length < 2) return null;
    final String onOff;
    if (rest.first == 'on' || rest.first == 'off') {
      onOff = rest.first;
      rest = rest.sublist(1);
    } else if (rest.last == 'on' || rest.last == 'off') {
      onOff = rest.last;
      rest = rest.sublist(0, rest.length - 1);
    } else {
      return null;
    }
    while (rest.isNotEmpty && const {'the', 'my', 'a'}.contains(rest.first)) {
      rest = rest.sublist(1);
    }
    // "All the lights" is everything, and no name.
    if (rest.isEmpty || rest.contains('all')) return null;
    // "The bedroom lights": a room's lights, or a light by its name.
    final lights =
        rest.length > 1 && const {'light', 'lights'}.contains(rest.last);
    if (lights) rest = rest.sublist(0, rest.length - 1);
    final heard = [
      for (final (i, w) in rest.indexed)
        i == rest.length - 1
            ? _numbers[w] ?? _soundsLikeNumber[w] ?? w
            : _numbers[w] ?? w,
    ];
    final name = nearest(heard);
    // Said as it is called already, the words were not the trouble. As
    // said, not as made out: "lounge won" is worth asking again as "lounge
    // one".
    if (name == null || name == rest.join(' ')) return null;
    return 'turn $onOff $name${lights && _areas.contains(name) ? ' lights' : ''}';
  }

  /// The name [heard] sounds clearly most like, or null. A number at the
  /// end is not guessed at: "lounge five" is not Lounge 4.
  String? nearest(List<String> heard) {
    final number = heard.isNotEmpty && _isNumber(heard.last)
        ? heard.last
        : null;
    final base = number == null ? heard : heard.sublist(0, heard.length - 1);
    if (base.isEmpty) return null;
    final scored = <(double, String)>[];
    for (final name in _names) {
      final theirs = _isNumber(name.last) ? name.last : null;
      if (theirs != number) continue;
      final rest = theirs == null ? name : name.sublist(0, name.length - 1);
      if (rest.isEmpty) continue;
      scored.add((alike(base, rest), name.join(' ')));
    }
    if (scored.isEmpty) return null;
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    final (best, name) = scored.first;
    final next = scored.length > 1 ? scored[1].$1 : 0.0;
    return best >= _enough && best - next >= _clearly ? name : null;
  }

  /// How alike [a] and [b] sound, from 0 to 1: see [sound].
  static double alike(List<String> a, List<String> b) {
    final x = sound(a), y = sound(b);
    final longest = x.length > y.length ? x.length : y.length;
    return longest == 0 ? 0 : 1 - _apart(x, y) / longest;
  }

  /// [words] run together and spelled roughly as they sound: the usual
  /// English spellings of one sound made one ("lounge" and "loundj"),
  /// doubled letters single, and every run of vowels one "a" — for vowels
  /// are what a recogniser most often gets wrong, and what matters least.
  static String sound(List<String> words) {
    var s = words.join();
    for (final (from, to) in const [
      ('ph', 'f'), ('ck', 'k'), ('tch', 'ch'), ('dge', 'j'), ('dg', 'j'), //
      ('wh', 'w'), ('kn', 'n'), ('gh', ''), ('qu', 'kw'), ('x', 'ks'),
      ('q', 'k'),
    ]) {
      s = s.replaceAll(from, to);
    }
    s = s
        .replaceAll(RegExp('c(?=[eiy])'), 's')
        .replaceAll('c', 'k')
        .replaceAll(RegExp('g(?=[eiy])'), 'j')
        // "Around you": the d and the y run together, as in "lounge".
        .replaceAll(RegExp('d(?=y[aeiou])'), 'j')
        .replaceAll('jy', 'j')
        .replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!)
        .replaceAll(RegExp('[aeiouy]+'), 'a');
    return s;
  }

  /// Sounds near enough that one is often heard for the other.
  static const _near = ['rl', 'mn', 'bp', 'dt', 'gk', 'fv', 'sz', 'jg', 'sj'];

  /// How far apart [a] and [b] are: letters changed, added or dropped, half
  /// as much for a vowel added or dropped and for a sound swapped for one
  /// near it.
  static double _apart(String a, String b) {
    double swap(String x, String y) {
      if (x == y) return 0;
      for (final pair in _near) {
        if (pair.contains(x) && pair.contains(y)) return 0.5;
      }
      return 1;
    }

    var row = [for (var j = 0; j <= b.length; j++) j.toDouble()];
    for (var i = 1; i <= a.length; i++) {
      final next = [i.toDouble()];
      for (var j = 1; j <= b.length; j++) {
        final drop = a[i - 1] == 'a' ? 0.5 : 1.0;
        final add = b[j - 1] == 'a' ? 0.5 : 1.0;
        next.add(
          [
            row[j] + drop,
            next[j - 1] + add,
            row[j - 1] + swap(a[i - 1], b[j - 1]),
          ].reduce((m, v) => v < m ? v : m),
        );
      }
      row = next;
    }
    return row.last;
  }
}
