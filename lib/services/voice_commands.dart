import '../dashboard/dashboard_model.dart';
import '../dashboard/schedule.dart';
import '../dashboard/widget_registry.dart';
import 'wake_word.dart';

/// What the panel was asked to do, out loud.
sealed class VoiceAction {
  const VoiceAction();
}

/// Turn the dashboard to [page] — its number as saved, counted from zero.
class VoiceShowPage extends VoiceAction {
  const VoiceShowPage(this.page);
  final int page;
}

/// The next dashboard page, or the one before: [by] is 1 or -1.
class VoiceTurnPage extends VoiceAction {
  const VoiceTurnPage(this.by);
  final int by;
}

/// Hold the automatic page turn, or let it run again.
class VoicePausePages extends VoiceAction {
  const VoicePausePages(this.paused);
  final bool paused;
}

/// Show the camera, or put it away.
class VoiceCamera extends VoiceAction {
  const VoiceCamera(this.open);
  final bool open;
}

/// What can be asked of whatever is playing: Spotify, or a phone's music.
enum VoiceMusicAsk {
  play,
  pause,
  next,
  previous,
  louder,
  quieter,
  mute,
  unmute,
}

class VoiceMusic extends VoiceAction {
  const VoiceMusic(this.ask);
  final VoiceMusicAsk ask;
}

/// Up, up, down, down, left, right, left, right, B, A.
class VoiceKonami extends VoiceAction {
  const VoiceKonami();
}

/// The commands that need nothing said after them.
enum VoicePlace { back, photos, dashboard, remote, forecast }

class VoiceGo extends VoiceAction {
  const VoiceGo(this.place);
  final VoicePlace place;
}

/// Works out what was meant by something said to the panel.
///
/// Pure: words in, an action out, so every phrase can be tested without a
/// microphone. The listener only hears; what the words mean is decided here,
/// against the dashboard as it is now — its page names and the widgets on
/// each page — so the vocabulary follows the dashboard as it is edited.
///
/// British English only, for now: widgets are matched by the names they
/// have in the source language, whatever language the panel is showing.
///
/// Deliberately not here: the Locked Folder, and Settings. Neither is for
/// whoever happens to be speaking in the room.
class VoiceCommands {
  VoiceCommands({
    required this.pageCount,
    required this.pages,
    required this.widgets,
    String? Function(String type)? nameOf,
    DateTime? now,
    WakeWord? wake,
  }) : wake = wake ?? WakeWord(),
       _nameOf = nameOf ?? ((type) => WidgetRegistry.find(type)?.name),
       _now = now ?? DateTime.now();

  factory VoiceCommands.of(
    DashboardSettings settings, {
    DateTime? now,
    WakeWord? wake,
  }) => VoiceCommands(
    pageCount: settings.pageCount,
    pages: settings.pages,
    widgets: settings.widgets,
    now: now,
    wake: wake,
  );

  final int pageCount;
  final List<DashboardPage> pages;
  final List<DashboardWidgetConfig> widgets;

  /// The words that wake the panel, to be passed over in what was said.
  final WakeWord wake;
  final String? Function(String type) _nameOf;
  final DateTime _now;

  /// Other things a widget is called, by type. Its own name, and any part
  /// of it, already work: "fuel" finds Fuel prices without being listed.
  static const Map<String, List<String>> aliases = {
    'youtube': ['videos'],
    'floatplane': ['videos', 'float plane'],
    'nebula': ['videos'],
    'stocks': ['shares', 'markets', 'stock market'],
    'crypto': ['bitcoin', 'cryptocurrency'],
    'spotify': ['music', 'spotify'],
    'news': ['headlines'],
    'calendar': ['diary', 'events'],
    'immich': ['pictures'],
    'servers': ['home lab'],
    'services': ['home lab'],
    'certs': ['certs'],
    'github': ['git hub'],
    'omarchy': ['shortcuts', 'keyboard shortcuts'],
    'grid_carbon': ['carbon intensity', 'grid'],
    'ha_energy': ['energy', 'power', 'meter', 'bright', 'smart meter'],
    'fuel': ['petrol', 'diesel'],
    'planes': ['flights', 'aircraft', 'aeroplanes'],
    'trains': ['travel', 'railway'],
    'transit': ['travel'],
    'tfl_arrivals': ['travel', 'tube', 'buses', 'underground'],
    'tfl_lines': ['travel', 'tube', 'underground'],
    'railcam': ['rail cam', 'railway camera'],
    'traffic_cams': ['traffic cams'],
    'bins': ['bins', 'rubbish', 'recycling'],
    'sun_moon': ['sunrise', 'sunset'],
    'air_quality': ['air quality'],
    'meals': ['meals', 'dinner', 'menu'],
    'timers': ['timer'],
    'tv': ['television', 'telly'],
    'unifi_health': ['network', 'unifi', 'wifi'],
    'unifi_presence': ['network', 'unifi'],
    'unifi_devices': ['network', 'wifi'],
    'unifi_clients': ['unifi', 'wifi'],
    'unifi_throughput': ['network', 'unifi', 'internet'],
    'unifi_isp': ['network', 'unifi', 'internet'],
    'speedtest': ['internet'],
    'homey': ['smart home'],
    'homey_room': ['smart home'],
    'homey_house': ['smart home'],
    'homey_lights': ['smart home'],
    'home_assistant': ['smart home'],
    'ha_bridge': ['bridge', 'console', 'lcars', 'rooms'],
  };

  static const _konami = 'up up down down left right left right';

  /// Words that ask without saying what for.
  static const _asking = {
    'show', 'open', 'go', 'switch', 'display', 'see', 'view', 'bring', //
    'give', 'take', 'put', 'turn', 'get', 'find', 'load', 'want', 'like',
  };

  /// Words that carry nothing: "show me the stocks, please".
  static const _filler = {
    'the', 'a', 'an', 'my', 'me', 'us', 'our', 'please', 'to', 'of', 'on', //
    'and', 'for', 'with', 'i', 'id', 'would', 'can', 'could', 'you',
    'widget', 'widgets', 'tile', 'tiles', 'screen', 'panel', 'now', 'over',
  };

  static const _numbers = {
    'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, //
    'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11, 'twelve': 12,
    'first': 1, 'second': 2, 'third': 3, 'fourth': 4, 'fifth': 5, 'sixth': 6,
    'seventh': 7, 'eighth': 8, 'ninth': 9, 'tenth': 10, 'eleventh': 11,
    'twelfth': 12,
    // What a recogniser makes of them often enough to be worth knowing.
    'won': 1, 'too': 2, 'for': 4, 'ate': 8,
  };

  /// What is said, less the asking, to what it does. Looked up before any
  /// page or widget, so "photos" is always the albums and never a Photo tile.
  static const Map<String, VoiceAction> _fixed = {
    'next': VoiceTurnPage(1),
    'next page': VoiceTurnPage(1),
    'next one': VoiceTurnPage(1),
    'forward': VoiceTurnPage(1),
    'forwards': VoiceTurnPage(1),
    'page forward': VoiceTurnPage(1),
    'previous': VoiceTurnPage(-1),
    'previous page': VoiceTurnPage(-1),
    'previous one': VoiceTurnPage(-1),
    'last page': VoiceTurnPage(-1),
    'page back': VoiceTurnPage(-1),
    'back page': VoiceTurnPage(-1),
    'back one': VoiceTurnPage(-1),
    'back one page': VoiceTurnPage(-1),
    'backwards': VoiceTurnPage(-1),
    'back': VoiceGo(VoicePlace.back),
    'close': VoiceGo(VoicePlace.back),
    'close that': VoiceGo(VoicePlace.back),
    'close it': VoiceGo(VoicePlace.back),
    'close this': VoiceGo(VoicePlace.back),
    'exit': VoiceGo(VoicePlace.back),
    'photos': VoiceGo(VoicePlace.photos),
    'photographs': VoiceGo(VoicePlace.photos),
    'albums': VoiceGo(VoicePlace.photos),
    'photo albums': VoiceGo(VoicePlace.photos),
    'home': VoiceGo(VoicePlace.photos),
    'dashboard': VoiceGo(VoicePlace.dashboard),
    'remote': VoiceGo(VoicePlace.remote),
    'remote control': VoiceGo(VoicePlace.remote),
    'remote panel': VoiceGo(VoicePlace.remote),
    'tv remote': VoiceGo(VoicePlace.remote),
    'television remote': VoiceGo(VoicePlace.remote),
    'forecast': VoiceGo(VoicePlace.forecast),
    'weather forecast': VoiceGo(VoicePlace.forecast),
    // The music. "Play", "pause", "stop" and "skip" on their own are the
    // music's; the pages are held and let go with "hold" and "resume".
    'play': VoiceMusic(VoiceMusicAsk.play),
    'play music': VoiceMusic(VoiceMusicAsk.play),
    'play spotify': VoiceMusic(VoiceMusicAsk.play),
    'play song': VoiceMusic(VoiceMusicAsk.play),
    'play something': VoiceMusic(VoiceMusicAsk.play),
    'resume music': VoiceMusic(VoiceMusicAsk.play),
    'start music': VoiceMusic(VoiceMusicAsk.play),
    'unpause': VoiceMusic(VoiceMusicAsk.play),
    'pause': VoiceMusic(VoiceMusicAsk.pause),
    'pause music': VoiceMusic(VoiceMusicAsk.pause),
    'pause spotify': VoiceMusic(VoiceMusicAsk.pause),
    'pause song': VoiceMusic(VoiceMusicAsk.pause),
    'pause it': VoiceMusic(VoiceMusicAsk.pause),
    'stop': VoiceMusic(VoiceMusicAsk.pause),
    'stop music': VoiceMusic(VoiceMusicAsk.pause),
    'stop spotify': VoiceMusic(VoiceMusicAsk.pause),
    'stop playing': VoiceMusic(VoiceMusicAsk.pause),
    'stop it': VoiceMusic(VoiceMusicAsk.pause),
    'skip': VoiceMusic(VoiceMusicAsk.next),
    'skip this': VoiceMusic(VoiceMusicAsk.next),
    'skip it': VoiceMusic(VoiceMusicAsk.next),
    'skip song': VoiceMusic(VoiceMusicAsk.next),
    'skip track': VoiceMusic(VoiceMusicAsk.next),
    'skip this one': VoiceMusic(VoiceMusicAsk.next),
    'skip this song': VoiceMusic(VoiceMusicAsk.next),
    'skip this track': VoiceMusic(VoiceMusicAsk.next),
    'next song': VoiceMusic(VoiceMusicAsk.next),
    'next track': VoiceMusic(VoiceMusicAsk.next),
    'next tune': VoiceMusic(VoiceMusicAsk.next),
    'previous song': VoiceMusic(VoiceMusicAsk.previous),
    'previous track': VoiceMusic(VoiceMusicAsk.previous),
    'last song': VoiceMusic(VoiceMusicAsk.previous),
    'last track': VoiceMusic(VoiceMusicAsk.previous),
    'skip back': VoiceMusic(VoiceMusicAsk.previous),
    'song before': VoiceMusic(VoiceMusicAsk.previous),
    'volume up': VoiceMusic(VoiceMusicAsk.louder),
    'it up': VoiceMusic(VoiceMusicAsk.louder),
    'music up': VoiceMusic(VoiceMusicAsk.louder),
    'louder': VoiceMusic(VoiceMusicAsk.louder),
    'volume down': VoiceMusic(VoiceMusicAsk.quieter),
    'it down': VoiceMusic(VoiceMusicAsk.quieter),
    'music down': VoiceMusic(VoiceMusicAsk.quieter),
    'quieter': VoiceMusic(VoiceMusicAsk.quieter),
    'mute': VoiceMusic(VoiceMusicAsk.mute),
    'mute music': VoiceMusic(VoiceMusicAsk.mute),
    'mute it': VoiceMusic(VoiceMusicAsk.mute),
    'unmute': VoiceMusic(VoiceMusicAsk.unmute),
    'unmute music': VoiceMusic(VoiceMusicAsk.unmute),
    'unmute it': VoiceMusic(VoiceMusicAsk.unmute),
    'pause pages': VoicePausePages(true),
    'hold': VoicePausePages(true),
    'hold page': VoicePausePages(true),
    'hold this page': VoicePausePages(true),
    'stay here': VoicePausePages(true),
    'stay this page': VoicePausePages(true),
    'stop turning': VoicePausePages(true),
    'resume': VoicePausePages(false),
    'resume pages': VoicePausePages(false),
    'carry': VoicePausePages(false),
    'continue': VoicePausePages(false),
    'start turning': VoicePausePages(false),
    'camera': VoiceCamera(true),
    'hide camera': VoiceCamera(false),
    'close camera': VoiceCamera(false),
  };

  /// [heard] as words: lower case, no punctuation, "&" spoken as "and".
  static List<String> words(String heard) => heard
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp('[’\']'), '')
      .replaceAll(RegExp('[^a-z0-9]+'), ' ')
      .trim()
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList();

  /// The words of [text] that say what is meant.
  static List<String> _meaning(String text) => [
    for (final w in words(text))
      if (!_filler.contains(w) && w != 'page' && w != 'pages') w,
  ];

  /// [heard] without the wake words in front, for something that wants
  /// only the request — Home Assistant's Assist, which would make nothing
  /// of "hey canvas turn on the lamp". As the listener finds them — see
  /// [WakeWord.ends]; "hey canvas" unless [wake] says otherwise.
  /// Heard without them — said after a pause — it is all request. The rest
  /// is left as it was heard, "what's" and all: Assist reads it as written.
  static String afterWake(String heard, {WakeWord? wake}) {
    var ends = (wake ?? WakeWord()).ends(heard);
    // As many of the words as heard as make up the wake words.
    final heardAs = heard.trim().split(RegExp(r'\s+'));
    var dropped = 0;
    while (ends > 0 && dropped < heardAs.length) {
      ends -= words(heardAs[dropped++]).length;
    }
    return heardAs
        .sublist(dropped)
        .join(' ')
        .replaceFirst(RegExp(r'^[^A-Za-z0-9]+'), '');
  }

  /// What [heard] asks for, or null when it asks for nothing known.
  ///
  /// The listener passes the wake words on with the rest, and what a
  /// recogniser makes of "hey canvas" can be anything — "hacambus", once.
  /// So when the whole of it means nothing, the start is given up a word at
  /// a time: the command is whatever the end of it says.
  VoiceAction? resolve(String heard) {
    final said = words(heard);
    // The directions are enough: "B, A" is two letters, and a recogniser
    // makes "be a", "bee hay" or nothing of them.
    if (said.join(' ').contains(_konami)) return const VoiceKonami();
    final pages = !_forElsewhere(words(afterWake(heard, wake: wake)));
    for (var from = 0; from < said.length; from++) {
      final action = _resolve(said.sublist(from), pages: pages);
      if (action != null) return action;
    }
    return null;
  }

  /// Words that start a question: "what's the weather" is asked, not a
  /// request for the page the weather is on.
  static const _questions = {
    'what', 'whats', 'how', 'hows', 'is', 'are', 'who', 'whos', 'where', //
    'when', 'why', 'will', 'does', 'do', 'did', 'tell',
  };

  /// Words that switch something: "lounge one off", "dim the lamp".
  static const _switching = {
    'off', 'set', 'dim', 'brighten', 'lock', 'unlock', 'add', //
  };

  /// Whether [said], without the wake words, is a question or a switching
  /// of something — for Home Assistant, should the panel have no command
  /// of its own by those words. Such a thing is never taken for a page,
  /// which any word of it might otherwise name: "what's the weather" is
  /// not the weather widget's page.
  static bool _forElsewhere(List<String> said) {
    if (said.isEmpty) return false;
    if (_questions.contains(said.first)) return true;
    if (said.any(_switching.contains)) return true;
    // "Turn the lamp on", "switch on the fan" — but not "switch to the
    // stocks" or "turn to page three", which are the panel's.
    return (said.first == 'turn' || said.first == 'switch') &&
        (said.last == 'on' || (said.length > 1 && said[1] == 'on'));
  }

  /// [heard] as Home Assistant's Assist should have it: without the wake
  /// words, and with what "turn" is most often misheard as at the start
  /// put right — "term lounge one off".
  static String forAssist(String heard, {WakeWord? wake}) {
    final request = afterWake(heard, wake: wake);
    return request.replaceFirst(
      RegExp(r'^(term|tern|turned|tum|tom)\b', caseSensitive: false),
      'turn',
    );
  }

  VoiceAction? _resolve(List<String> said, {bool pages = true}) {
    // The wake words themselves, heard as themselves.
    while (said.isNotEmpty && wake.isWakeWord(said.first)) {
      said = said.sublist(1);
    }
    final numbered = _numberedPage(said);
    if (numbered != null) return numbered;

    final asked = [
      for (final w in said)
        if (!_asking.contains(w) && !_filler.contains(w)) w,
    ];
    if (asked.isEmpty) return null;
    final fixed =
        _fixed[asked.join(' ')] ??
        _fixed[asked.where((w) => w != 'page' && w != 'pages').join(' ')];
    if (fixed != null) return fixed;

    if (!pages) return null;
    final page = _pageFor(asked.where((w) => w != 'page' && w != 'pages'));
    return page == null ? null : VoiceShowPage(page);
  }

  /// "Page three", "the third page", "page number 3".
  VoiceAction? _numberedPage(List<String> said) {
    if (!said.contains('page')) return null;
    final rest = [
      for (final w in said)
        if (w != 'page' && w != 'number' && !_asking.contains(w))
          // "For" is filler, and also what "four" is often heard as.
          if (!_filler.contains(w) || _numbers.containsKey(w)) w,
    ];
    if (rest.length != 1) return null;
    final n = int.tryParse(rest.single) ?? _numbers[rest.single];
    if (n == null || n < 1 || n > pageCount) return null;
    return VoiceShowPage(n - 1);
  }

  /// Everything a page answers to: its name, and its widgets' names.
  Iterable<(int, List<String>)> _answersTo() sync* {
    final showing = visiblePages(pageCount, pages, _now).toSet();
    for (final (i, page) in pages.indexed) {
      if (!showing.contains(i)) continue;
      final name = _meaning(page.name);
      if (name.isNotEmpty) yield (i, name);
    }
    for (final w in widgets) {
      if (!showing.contains(w.page)) continue;
      final spoken = [
        ?_nameOf(w.type),
        w.type.replaceAll('_', ' '),
        ...?aliases[w.type],
      ];
      for (final phrase in spoken) {
        final name = _meaning(phrase);
        if (name.isNotEmpty) yield (w.page, name);
      }
    }
  }

  /// Every phrase the dashboard answers to as it stands — for a listener
  /// that does better when told what it might hear.
  List<String> get phrases => {
    for (final (_, name) in _answersTo()) name.join(' '),
    ..._fixed.keys,
  }.toList();

  /// The page that answers best to [asked]; the earliest, between equals.
  int? _pageFor(Iterable<String> asked) {
    final want = asked.map(_stem).toList();
    if (want.isEmpty) return null;
    int? best;
    var bestScore = 0;
    for (final (page, name) in _answersTo()) {
      final score = _score(want, name.map(_stem).toList());
      if (score > bestScore ||
          (score == bestScore && score > 0 && page < best!)) {
        best = page;
        bestScore = score;
      }
    }
    return best;
  }

  /// How well [want] names [name]: 4 said exactly, 3 said in part ("fuel"
  /// for Fuel prices), and one less for either when a word was only nearly
  /// right — recognisers mishear, and people misremember. 0 is no match.
  static int _score(List<String> want, List<String> name) {
    var near = false;
    for (final w in want) {
      if (name.contains(w)) continue;
      if (!name.any((n) => _nearly(w, n))) return 0;
      near = true;
    }
    final whole = want.length == name.length;
    return (whole ? 4 : 3) - (near ? 1 : 0);
  }

  /// Plurals said either way: "stock" and "stocks", "video" and "videos".
  static String _stem(String w) =>
      w.length > 3 && w.endsWith('s') && !w.endsWith('ss')
      ? w.substring(0, w.length - 1)
      : w;

  /// Whether [a] is [b] but for one slip — a letter wrong, missing, added
  /// or swapped with its neighbour. Only for words long enough that one
  /// letter is not most of the word.
  static bool _nearly(String a, String b) {
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
}
