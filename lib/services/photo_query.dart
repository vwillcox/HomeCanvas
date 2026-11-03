/// Photos asked for in words — "Ellie at the beach in 2019" — as a search
/// of Immich: who is in them, where and when they were taken, and what is in
/// them, which Immich's own image model (CLIP) finds by looking.
///
/// Pure: the people and places it knows are passed in, so it is tested
/// without a server. English only, like the voice commands it serves.
library;

import '../l10n/dates.dart';
import '../l10n/l10n.dart';
import 'immich_service.dart' show Person;

/// A place Immich has photos from, as its search suggests them.
class PhotoPlace {
  const PhotoPlace(this.kind, this.name);

  final PhotoPlaceKind kind;

  /// As Immich has it: "Southend-on-Sea".
  final String name;

  @override
  bool operator ==(Object other) =>
      other is PhotoPlace && other.kind == kind && other.name == name;

  @override
  int get hashCode => Object.hash(kind, name);

  @override
  String toString() => '${kind.name}:$name';
}

/// The field of Immich's search a place is matched in.
enum PhotoPlaceKind { city, state, country }

/// When the photos were taken: from [after], up to but not including
/// [before], and how to say so.
class PhotoWhen {
  const PhotoWhen(this.after, this.before, this.label);

  final DateTime after;
  final DateTime before;

  /// "2019", "Summer 2019", "March 2024", "The 1990s".
  final String label;

  @override
  bool operator ==(Object other) =>
      other is PhotoWhen &&
      other.after == after &&
      other.before == before &&
      other.label == label;

  @override
  int get hashCode => Object.hash(after, before, label);

  @override
  String toString() => '$label [$after, $before)';
}

/// What was asked for.
class PhotoQuery {
  const PhotoQuery({
    this.asked = '',
    this.text = '',
    this.people = const [],
    this.place,
    this.when,
    this.videos = false,
    this.likeId,
  });

  /// Photos that look like the one with id [id].
  const PhotoQuery.like(String id) : this(likeId: id);

  /// Photos of [person], newest first.
  PhotoQuery.of(Person person) : this(asked: person.name, people: [person]);

  /// As typed or said, for putting back in the search field.
  final String asked;

  /// What is in them, for Immich's image model: "dog in the snow". Empty
  /// when only who, where or when was asked.
  final String text;
  final List<Person> people;
  final PhotoPlace? place;
  final PhotoWhen? when;

  /// Only videos: "videos of Ellie".
  final bool videos;

  /// Photos like this one, by its id.
  final String? likeId;

  /// Whether Immich's image model chooses, and ranks them closest first.
  /// Otherwise they are newest first.
  bool get byLooks => text.isNotEmpty || likeId != null;

  /// What it asks for, in a line: "Ellie & Sam · Beach · 2019".
  String get label {
    if (likeId != null) return tr('find.likeThisOne', 'Like this one');
    final named = people.length == 1
        ? people.single.name
        : people.map((p) => p.name.split(' ').first).join(' & ');
    return [
      if (people.isNotEmpty) named,
      if (text.isNotEmpty) text[0].toUpperCase() + text.substring(1),
      ?place?.name,
      ?when?.label,
    ].join(' · ');
  }

  /// The body of Immich's search for page [page] of [size]: its image
  /// model's (`/search/smart`) when [byLooks], otherwise by the photos'
  /// details (`/search/metadata`).
  ///
  /// Only ever the timeline's photos: never the Locked Folder's, nor the
  /// archive's, whoever is standing at the panel.
  Map<String, Object> body({int page = 1, int size = 60}) => {
    if (text.isNotEmpty) 'query': text,
    'queryAssetId': ?likeId,
    if (people.isNotEmpty) 'personIds': [for (final p in people) p.id],
    if (place case final p?) p.kind.name: p.name,
    if (when case final w?) ...{
      'takenAfter': _utc(w.after),
      'takenBefore': _utc(w.before),
    },
    if (videos) 'type': 'VIDEO',
    'visibility': 'timeline',
    if (!byLooks) 'order': 'desc',
    'page': page,
    'size': size,
  };

  /// A wall-clock date as the UTC instant Immich's dates are compared to.
  /// A photo taken at a quarter to midnight on New Year's Eve in another
  /// time zone may land in the year next door, which is close enough.
  static String _utc(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).toIso8601String();

  /// [asked] as a search, knowing the [people] Immich has named (in its
  /// order: the most photographed first) and the [places] it has photos
  /// from. Null when it asks for nothing: "show me photos".
  static PhotoQuery? parse(
    String asked, {
    List<Person> people = const [],
    List<PhotoPlace> places = const [],
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final words = wordsOf(asked);
    // Whatever asks without saying what for: "show me", "can you find".
    var start = 0;
    while (start < words.length && _leadIn.contains(words[start])) {
      start++;
    }
    final said = words.sublist(start);
    final used = List<bool>.filled(said.length, false);

    var videos = false;
    var stills = false;
    for (final (i, w) in said.indexed) {
      if (_photoWords.contains(w)) {
        used[i] = stills = true;
      } else if (_videoWords.contains(w)) {
        used[i] = videos = true;
      } else if (w == 'slide' && i + 1 < said.length && said[i + 1] == 'show') {
        used[i] = used[i + 1] = stills = true;
      }
    }

    // Taken up a span at a time, and the "in", "at" or "with" before it
    // with it: what is left reads as a phrase, "snow with the dog" rather
    // than "snow at with the dog".
    void take(int from, int length) {
      for (var i = from; i < from + length; i++) {
        used[i] = true;
      }
      if (from > 0 && !used[from - 1] && _joins.contains(said[from - 1])) {
        used[from - 1] = true;
      }
    }

    // When, first: "summer 2019" is a season before Summer is anyone's
    // name, and "June 2020" a month before it is June's.
    PhotoWhen? when;
    for (var i = 0; i < said.length && when == null; i++) {
      if (used[i]) continue;
      final found = _whenAt(said, i, today);
      if (found == null) continue;
      when = found.$1;
      take(found.$2, found.$3);
    }

    PhotoPlace? place;
    for (var i = 0; i < said.length && place == null; i++) {
      if (used[i]) continue;
      final found = _placeAt(said, used, i, places);
      if (found == null) continue;
      place = found.$1;
      take(i, found.$2);
    }

    final who = <Person>[];
    for (var i = 0; i < said.length; i++) {
      if (used[i]) continue;
      final found = _personAt(said, used, i, people);
      if (found == null) continue;
      if (!who.any((p) => p.id == found.$1.id)) who.add(found.$1);
      take(i, found.$2);
      i += found.$2 - 1;
    }

    final rest = [
      for (final (i, w) in said.indexed)
        if (!used[i]) w,
    ];
    while (rest.isNotEmpty && _loose.contains(rest.first)) {
      rest.removeAt(0);
    }
    while (rest.isNotEmpty && _loose.contains(rest.last)) {
      rest.removeLast();
    }
    final text = rest.join(' ');
    if (text.isEmpty && who.isEmpty && place == null && when == null) {
      return null;
    }
    return PhotoQuery(
      asked: _withoutAsking(asked),
      text: text,
      people: who,
      place: place,
      when: when,
      videos: videos && !stills,
    );
  }

  /// [asked] as it was put, less the asking in front: "of the beach" is
  /// "beach", "show me Ellie's photos" "Ellie's photos".
  static String _withoutAsking(String asked) {
    final put = asked.trim().split(RegExp(r'\s+'));
    var from = 0;
    while (from < put.length && wordsOf(put[from]).every(_leadIn.contains)) {
      from++;
    }
    return put.sublist(from).join(' ');
  }

  /// [s] as words: lower case, no punctuation, apostrophes dropped so
  /// "Ellie's" is "ellies".
  static List<String> wordsOf(String s) => s
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp('[’\']'), '')
      .split(RegExp('[^a-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();

  /// Words that ask, at the start of what was said.
  static const _leadIn = {
    'hey', 'show', 'me', 'us', 'find', 'search', 'for', 'look', 'looking', //
    'get', 'give', 'bring', 'open', 'display', 'play', 'start', 'see', 'any',
    'some', 'all', 'our', 'my', 'the', 'a', 'an', 'of', 'please', 'can',
    'could', 'you', 'i', 'id', 'want', 'to', 'lets', 'let', 'have', 'we',
    'got', 'do', 'would', 'like', 'up', 'pull',
  };

  static const _photoWords = {
    'photo', 'photos', 'photograph', 'photographs', 'picture', 'pictures', //
    'pic', 'pics', 'snaps', 'snapshots', 'image', 'images', 'slideshow',
  };

  static const _videoWords = {'video', 'videos', 'clips'};

  /// The words that tie who, where or when to the rest: taken with them.
  static const _joins = {
    'in', 'at', 'from', 'with', 'of', 'during', 'near', 'by', 'and', 'on', //
    'the', 'around',
  };

  /// Words that mean nothing at either end of what is left to look for.
  static const _loose = {
    ..._joins, 'a', 'an', 'to', 'taken', 'when', 'where', 'together', //
    'some', 'any', 'all', 'our', 'my', 'me', 'us', 'please', 'that', 'this',
    'those', 'these', 'was', 'were', 'we', 'for', 'is', 'are',
  };

  // ---- Who ---------------------------------------------------------------

  /// The person [said] names at [i], and how many words it took: the
  /// longest name said, whole ("Ellie Parker") or first name only
  /// ("Ellie"), the first of [people] between equals. "Ellie's" is Ellie.
  static (Person, int)? _personAt(
    List<String> said,
    List<bool> used,
    int i,
    List<Person> people,
  ) {
    (Person, int)? best;
    for (final p in people) {
      final name = wordsOf(p.name);
      if (name.isEmpty) continue;
      for (final n in {name.length, if (name.length > 1) 1}) {
        if (best != null && n <= best.$2) continue;
        final part = name.sublist(0, n);
        // A name of a letter or two is too easily said by accident.
        if (n == 1 && part.single.length < 3) continue;
        if (_saidAt(said, used, i, part, possessive: true)) best = (p, n);
      }
    }
    return best;
  }

  // ---- Where -------------------------------------------------------------

  static (PhotoPlace, int)? _placeAt(
    List<String> said,
    List<bool> used,
    int i,
    List<PhotoPlace> places,
  ) {
    (PhotoPlace, int)? best;
    for (final p in places) {
      final name = wordsOf(p.name);
      if (name.isEmpty || (best != null && name.length <= best.$2)) continue;
      if (_saidAt(said, used, i, name)) best = (p, name.length);
    }
    return best;
  }

  /// Whether [said] has [name] at [i], each word as it is or one slip from
  /// it (recognisers mishear), and the last with an "s" on it when
  /// [possessive].
  static bool _saidAt(
    List<String> said,
    List<bool> used,
    int i,
    List<String> name, {
    bool possessive = false,
  }) {
    if (i + name.length > said.length) return false;
    for (var k = 0; k < name.length; k++) {
      if (used[i + k]) return false;
      final w = said[i + k];
      final want = name[k];
      if (w == want || nearlySame(w, want)) continue;
      if (possessive && k == name.length - 1 && w == '${want}s') continue;
      return false;
    }
    return true;
  }

  // ---- When --------------------------------------------------------------

  /// The time [said] gives at [i]: when, and the span of words saying so
  /// (which may start before [i], for "last" or "the").
  static (PhotoWhen, int, int)? _whenAt(
    List<String> said,
    int i,
    DateTime today,
  ) {
    final w = said[i];
    final next = i + 1 < said.length ? said[i + 1] : null;
    final before = i > 0 ? said[i - 1] : null;

    // "Last year", "this month", "last summer", "this week".
    if (w == 'last' || w == 'this') {
      final last = w == 'last';
      switch (next) {
        case 'year':
          final y = today.year - (last ? 1 : 0);
          return (_year(y), i, 2);
        case 'month':
          final m = DateTime(today.year, today.month - (last ? 1 : 0));
          return (_month(m.year, m.month), i, 2);
        case 'week':
          // The seven days to today, or the seven before those.
          final start = DateTime(
            today.year,
            today.month,
            today.day - (last ? 13 : 6),
          );
          return (
            PhotoWhen(
              start,
              DateTime(start.year, start.month, start.day + 7),
              last
                  ? tr('find.lastWeek', 'Last week')
                  : tr('find.thisWeek', 'This week'),
            ),
            i,
            2,
          );
        case final s? when _seasons.containsKey(s):
          return (_lastSeason(s, today, thisOne: !last), i, 2);
        case final m? when _months.containsKey(m):
          final month = _months[m]!;
          // Last March: the one before this year's, if this year's has
          // been; this March: this year's.
          var y = today.year;
          if (last && month >= today.month) y--;
          return (_month(y, month), i, 2);
      }
      return null;
    }
    if (w == 'today' || w == 'yesterday') {
      final d = DateTime(
        today.year,
        today.month,
        today.day - (w == 'today' ? 0 : 1),
      );
      return (
        PhotoWhen(
          d,
          DateTime(d.year, d.month, d.day + 1),
          w == 'today'
              ? tr('find.today', 'Today')
              : tr('find.yesterday', 'Yesterday'),
        ),
        i,
        1,
      );
    }

    // "Five years ago", "a year ago" — whose "a" may have gone with the
    // asking, at the start.
    if (w == 'year' && next == 'ago') return (_year(today.year - 1), i, 2);
    if ((next == 'year' || next == 'years') &&
        i + 2 < said.length &&
        said[i + 2] == 'ago') {
      final n = w == 'a' || w == 'one' ? 1 : int.tryParse(w) ?? _ones[w];
      if (n != null && n > 0) return (_year(today.year - n), i, 3);
    }

    // The nineties, the 1990s, the 90s.
    final decade = _decade(w);
    if (decade != null && decade <= today.year) {
      final from = before == 'the' ? i - 1 : i;
      return (
        PhotoWhen(
          DateTime(decade),
          DateTime(decade + 10),
          tr('find.decade', 'The {decade}s', {'decade': decade}),
        ),
        from,
        i - from + 1,
      );
    }

    // A season or month with a year: "summer 2019", "March twenty
    // twenty four". A month on its own only after "in" or "during", where
    // it cannot be someone called April.
    if (_seasons.containsKey(w) || _months.containsKey(w)) {
      final year = next == null ? null : _yearAt(said, i + 1, today);
      if (year != null) {
        final when = _seasons.containsKey(w)
            ? _season(w, year.$1)
            : _month(year.$1, _months[w]!);
        return (when, i, 1 + year.$2);
      }
      if (_months.containsKey(w) && (before == 'in' || before == 'during')) {
        final month = _months[w]!;
        final y = month > today.month ? today.year - 1 : today.year;
        return (_month(y, month), i, 1);
      }
      return null;
    }

    final year = _yearAt(said, i, today);
    if (year != null) return (_year(year.$1), i, year.$2);
    return null;
  }

  static PhotoWhen _year(int y) =>
      PhotoWhen(DateTime(y), DateTime(y + 1), '$y');

  static PhotoWhen _month(int y, int m) =>
      PhotoWhen(DateTime(y, m), DateTime(y, m + 1), monthYear(DateTime(y, m)));

  /// Spring is March to May, and winter December to February — the winter
  /// of 2019 the one that starts in it.
  static PhotoWhen _season(String name, int y) {
    final first = _seasons[name]!;
    return PhotoWhen(
      DateTime(y, first),
      DateTime(y, first + 3),
      switch (first) {
        3 => tr('find.spring', 'Spring {year}', {'year': y}),
        6 => tr('find.summer', 'Summer {year}', {'year': y}),
        9 => tr('find.autumn', 'Autumn {year}', {'year': y}),
        _ => tr('find.winter', 'Winter {year}', {'year': y}),
      },
    );
  }

  /// "Last summer": the last one to have been and gone — in November, this
  /// year's; in July, last year's. "This summer" ([thisOne]): the one going
  /// on, or else this year's.
  static PhotoWhen _lastSeason(
    String name,
    DateTime today, {
    bool thisOne = false,
  }) {
    final first = _seasons[name]!;
    // The latest to have begun. Winter is named for the year it starts
    // in, so in January it is last year's.
    var y = today.year;
    if (DateTime(y, first).isAfter(today)) y--;
    final going = today.isBefore(DateTime(y, first + 3));
    if (thisOne) return _season(name, going ? y : today.year);
    return _season(name, going ? y - 1 : y);
  }

  static const _seasons = {
    'spring': 3,
    'summer': 6,
    'autumn': 9,
    'fall': 9,
    'winter': 12,
  };

  static const _months = {
    'january': 1, 'february': 2, 'march': 3, 'april': 4, 'may': 5, //
    'june': 6, 'july': 7, 'august': 8, 'september': 9, 'october': 10,
    'november': 11, 'december': 12, 'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4,
    'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'sept': 9, 'oct': 10, 'nov': 11,
    'dec': 12,
  };

  /// A year said at [i], and in how many words: "2019", "twenty nineteen",
  /// "nineteen ninety nine", "two thousand and nine". Only one that has
  /// been.
  static (int, int)? _yearAt(List<String> said, int i, DateTime today) {
    int? y;
    var n = 0;
    final w = said[i];
    if (RegExp(r'^(19|20)\d\d$').hasMatch(w)) {
      y = int.parse(w);
      n = 1;
    } else if ((w == 'nineteen' || w == 'twenty') && i + 1 < said.length) {
      final rest = _twoDigits(said, i + 1);
      if (rest != null) {
        y = (w == 'nineteen' ? 1900 : 2000) + rest.$1;
        n = 1 + rest.$2;
      }
    } else if (w == 'two' && i + 1 < said.length && said[i + 1] == 'thousand') {
      var j = i + 2;
      if (j < said.length && said[j] == 'and') j++;
      final one = j < said.length ? _ones[said[j]] : null;
      final rest = one != null
          ? (one, 1)
          : j < said.length
          ? _twoDigits(said, j)
          : null;
      y = 2000 + (rest?.$1 ?? 0);
      n = rest == null ? 2 : j - i + rest.$2;
    }
    if (y == null || y < 1900 || y > today.year) return null;
    return (y, n);
  }

  /// A number from 0 to 99 said at [i] — "nineteen", "ninety nine", "oh
  /// five" — and in how many words.
  static (int, int)? _twoDigits(List<String> said, int i) {
    final w = said[i];
    final next = i + 1 < said.length ? said[i + 1] : null;
    if (w == 'oh' && next != null && _ones.containsKey(next)) {
      return (_ones[next]!, 2);
    }
    if (_teens.containsKey(w)) return (_teens[w]!, 1);
    if (_tens.containsKey(w)) {
      if (next != null && _ones.containsKey(next)) {
        return (_tens[w]! + _ones[next]!, 2);
      }
      return (_tens[w]!, 1);
    }
    return null;
  }

  /// The first year of the decade [w] names: "nineties", "1990s", "90s".
  static int? _decade(String w) {
    final named = _decades[w];
    if (named != null) return named;
    final full = RegExp(r'^(19|20)(\d)0s$').firstMatch(w);
    if (full != null) return int.parse(w.substring(0, 4));
    final short = RegExp(r'^(\d)0s$').firstMatch(w);
    if (short != null) {
      final d = int.parse(short.group(1)!) * 10;
      return d >= 30 ? 1900 + d : 2000 + d;
    }
    return null;
  }

  static const _decades = {
    'fifties': 1950, 'sixties': 1960, 'seventies': 1970, 'eighties': 1980, //
    'nineties': 1990, 'noughties': 2000, 'naughties': 2000,
  };

  static const _ones = {
    'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, //
    'seven': 7, 'eight': 8, 'nine': 9,
  };

  static const _teens = {
    'ten': 10, 'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14, //
    'fifteen': 15, 'sixteen': 16, 'seventeen': 17, 'eighteen': 18,
    'nineteen': 19,
  };

  static const _tens = {
    'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50, 'sixty': 60, //
    'seventy': 70, 'eighty': 80, 'ninety': 90,
  };
}

/// Whether [a] is [b] but for one slip — a letter wrong, missing, added or
/// swapped with its neighbour. Only for words long enough that one letter is
/// not most of the word.
bool nearlySame(String a, String b) {
  if (a.length < 5 || b.length < 5) return false;
  if ((a.length - b.length).abs() > 1) return false;
  if (a.length == b.length) {
    final wrong = [
      for (var i = 0; i < a.length; i++)
        if (a[i] != b[i]) i,
    ];
    if (wrong.length == 1) return true;
    return wrong.length == 2 &&
        wrong[1] == wrong[0] + 1 &&
        a[wrong[0]] == b[wrong[1]] &&
        a[wrong[1]] == b[wrong[0]];
  }
  final long = a.length > b.length ? a : b;
  final short = a.length > b.length ? b : a;
  for (var i = 0; i < long.length; i++) {
    if (long.substring(0, i) + long.substring(i + 1) == short) return true;
  }
  return false;
}
