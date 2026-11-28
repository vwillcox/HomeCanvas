import '../dashboard/dashboard_model.dart';
import '../dashboard/schedule.dart';
import '../dashboard/widget_registry.dart';
import 'radio_stations.dart';
import 'routines.dart';
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

/// Bring a tile close — see `TileSpotlight` — after turning to its [page]:
/// [tile] is the widget's id.
class VoiceLiftTile extends VoiceAction {
  const VoiceLiftTile(this.page, this.tile);
  final int page;
  final String tile;
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

/// Every dashboard page at once, to choose one from — see `PageOverview`.
/// Put away again with "back", as anything opened is.
class VoiceOverview extends VoiceAction {
  const VoiceOverview();
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

/// What can be asked of the radio.
enum VoiceRadioAsk { play, stop, next, previous }

/// Tune the radio in, step it along its stations, or stop it.
class VoiceRadio extends VoiceAction {
  const VoiceRadio(this.ask, [this.station]);
  final VoiceRadioAsk ask;

  /// The station as it was said — "radio four" — for [VoiceRadioAsk.play].
  /// Null for whichever was on last.
  final String? station;
}

/// Photos asked for in words — "show me photos of Ellie at the beach" —
/// found in the whole library: [asked] is what was said after the asking,
/// "ellie at the beach", read by `PhotoQuery` once the people and places
/// Immich knows are to hand. With [slideshow], shown as one.
class VoiceFindPhotos extends VoiceAction {
  const VoiceFindPhotos(this.asked, {this.slideshow = false});
  final String asked;
  final bool slideshow;
}

/// A recipe to cook from, by what it is called — "let's cook the
/// chasseur" — among those cooked here before; with no [name], the book of
/// them all.
class VoiceCook extends VoiceAction {
  const VoiceCook([this.name]);
  final String? name;
}

/// What in the house can be switched by name, with no room said.
enum HomeThing {
  /// The television in Settings → TV.
  tv,

  /// Every light Home Assistant's Assist can see.
  lights,

  /// A computer that collects links from the panel — see `ComputerPower`.
  computer,

  /// The Art Matrix LED display in Settings → Art Matrix: "the Art Matrix",
  /// or "Arty".
  artMatrix,
}

/// Switch [things] on, or off: "turn the TV off", "lights on", "turn off
/// the TV and the lights". Only ever the whole of them: a room or a name
/// said with them — "the bedroom lights" — is left to Home Assistant.
class VoiceSwitch extends VoiceAction {
  const VoiceSwitch(this.things, {required this.on, this.computer});
  final Set<HomeThing> things;
  final bool on;

  /// The computer by its name, when one was said: "the omarchy PC".
  final String? computer;
}

/// The Art Matrix's display to [level] percent, 1 to 100, which puts it on
/// as well: "Art Matrix brightness 40", "set the Art Matrix to forty
/// percent".
class VoiceArtMatrixBrightness extends VoiceAction {
  const VoiceArtMatrixBrightness(this.level);
  final int level;
}

/// One of the routines in the config, by what sets it off: "I'm going to
/// bed".
class VoiceRoutine extends VoiceAction {
  const VoiceRoutine(this.routine);
  final HomeRoutine routine;
}

/// Up, up, down, down, left, right, left, right, B, A.
class VoiceKonami extends VoiceAction {
  const VoiceKonami();
}

/// The commands that need nothing said after them.
/// Somewhere to go, or something to put up over where you are. [today] is
/// the day at a glance, read out — see `showDayBrief`.
enum VoicePlace { back, photos, dashboard, remote, forecast, today }

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
    this.routines = const [],
    this.computers = const [],
  }) : wake = wake ?? WakeWord(),
       _nameOf = nameOf ?? ((type) => WidgetRegistry.find(type)?.name),
       _now = now ?? DateTime.now();

  factory VoiceCommands.of(
    DashboardSettings settings, {
    DateTime? now,
    WakeWord? wake,
    List<HomeRoutine> routines = const [],
    List<String> computers = const [],
  }) => VoiceCommands(
    pageCount: settings.pageCount,
    pages: settings.pages,
    widgets: settings.widgets,
    now: now,
    wake: wake,
    routines: routines,
    computers: computers,
  );

  final int pageCount;
  final List<DashboardPage> pages;
  final List<DashboardWidgetConfig> widgets;

  /// What "I'm going to bed" and the like set off — see [HomeRoutine].
  final List<HomeRoutine> routines;

  /// What the computers that can be switched are called: "omarchy".
  final List<String> computers;

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
    'radio': ['wireless', 'stations'],
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
    'parcels': ['parcel', 'packages', 'deliveries', 'delivery', 'post'],
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

  /// Words that ask for a tile brought close rather than its page: "the
  /// news closer", "zoom in on the calendar", "make the weather bigger".
  static const _closer = {
    'closer', 'bigger', 'larger', 'enlarge', 'zoom', 'magnify', 'expand', //
  };

  /// What comes with them and means nothing more: "zoom in", "make it
  /// bigger", "up close".
  static const _closerFiller = {'in', 'into', 'make', 'up', 'close', 'it'};

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
    // Every page at once. "Show me all the pages" is "all pages" by the
    // time the asking and the filler are gone.
    'all pages': VoiceOverview(),
    'every page': VoiceOverview(),
    'overview': VoiceOverview(),
    'page overview': VoiceOverview(),
    'zoom out': VoiceOverview(),
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
    // The day at a glance, read out. As heard less the asking and the
    // filler: "what's my day" is "whats day", "what's on today" "whats
    // today".
    'day': VoiceGo(VoicePlace.today),
    'today': VoiceGo(VoicePlace.today),
    'whats day': VoiceGo(VoicePlace.today),
    'whats today': VoiceGo(VoicePlace.today),
    'what is today': VoiceGo(VoicePlace.today),
    'whats happening today': VoiceGo(VoicePlace.today),
    'what is happening today': VoiceGo(VoicePlace.today),
    'whats plan': VoiceGo(VoicePlace.today),
    'whats plan today': VoiceGo(VoicePlace.today),
    'hows day looking': VoiceGo(VoicePlace.today),
    'how is day looking': VoiceGo(VoicePlace.today),
    'hows day': VoiceGo(VoicePlace.today),
    'whats day looking': VoiceGo(VoicePlace.today),
    'what is day looking': VoiceGo(VoicePlace.today),
    'what is day': VoiceGo(VoicePlace.today),
    'whats day look': VoiceGo(VoicePlace.today),
    'plan today': VoiceGo(VoicePlace.today),
    'day ahead': VoiceGo(VoicePlace.today),
    'briefing': VoiceGo(VoicePlace.today),
    'brief': VoiceGo(VoicePlace.today),
    'daily briefing': VoiceGo(VoicePlace.today),
    'morning briefing': VoiceGo(VoicePlace.today),
    'rundown': VoiceGo(VoicePlace.today),
    'run down': VoiceGo(VoicePlace.today),
    'good morning': VoiceGo(VoicePlace.today),
    // The music. "Play", "pause", "stop" and "skip" on their own are the
    // music's; the pages are held and let go with "hold" and "resume".
    // The radio, by name; a station by its own name is "play" and the name,
    // worked out in _resolve.
    'play radio': VoiceRadio(VoiceRadioAsk.play),
    'start radio': VoiceRadio(VoiceRadioAsk.play),
    'listen radio': VoiceRadio(VoiceRadioAsk.play),
    'stop radio': VoiceRadio(VoiceRadioAsk.stop),
    'radio off': VoiceRadio(VoiceRadioAsk.stop),
    'off radio': VoiceRadio(VoiceRadioAsk.stop),
    'next station': VoiceRadio(VoiceRadioAsk.next),
    'change station': VoiceRadio(VoiceRadioAsk.next),
    'previous station': VoiceRadio(VoiceRadioAsk.previous),
    'last station': VoiceRadio(VoiceRadioAsk.previous),
    'station before': VoiceRadio(VoiceRadioAsk.previous),
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
    final request = words(afterWake(heard, wake: wake));
    final home = _homeOf(request);
    if (home != null) return home;
    final pages = !_forElsewhere(request);
    for (var from = 0; from < said.length; from++) {
      final action = _resolve(said.sublist(from), pages: pages);
      if (action != null) return action;
    }
    return null;
  }

  /// A routine, or the TV or the lights switched, in [request]: what was
  /// said after the wake words.
  ///
  /// On the request as a whole, never on what is left of it with words
  /// given up from the front, as [resolve] does for pages: "bedroom TV off",
  /// said after a pause, would end as "TV off" and switch the other
  /// television. The listener passes nothing on without the wake words
  /// made out, so there is no misheard "hey canvas" to give up here.
  VoiceAction? _homeOf(List<String> request) {
    var said = request;
    while (said.isNotEmpty && wake.isWakeWord(said.first)) {
      said = said.sublist(1);
    }
    if (said.isEmpty) return null;
    for (final routine in routines) {
      if (routine.answersTo(said, words)) return VoiceRoutine(routine);
    }
    final level = _artMatrixLevelOf(said);
    if (level != null) return level;
    return _switchOf(said, computers: computers);
  }

  static const _tvWords = {'tv', 'television', 'telly', 'tele', 'telley'};
  static const _lightWords = {'light', 'lights'};
  static const _computerWords = {'pc', 'computer', 'desktop'};

  /// The Art Matrix by name: "art matrix", made one word by
  /// [_artMatrixJoined], and "Arty", its name on the network, as a
  /// recogniser may spell it. "Art" or "matrix" on its own is neither.
  static const _artMatrixWords = {'artmatrix', 'arty', 'artie', 'artys'};

  /// What may come with them in a switching, besides the asking and the
  /// filler: "power off the TV", "shut all the lights off in the house".
  ///
  /// Not "upstairs" or "downstairs": "the lights upstairs" are some of them,
  /// and Home Assistant knows which floor is which. Taken as all of them, as
  /// they once were, they switched off every light in the house.
  static const _switchLoose = {
    'all', 'every', 'both', 'power', 'shut', 'in', 'house', 'everywhere', //
    'whole', 'home', 'them', 'it',
  };

  /// "Turn the TV off", "lights on", "switch off the telly and the lights":
  /// the TV, the lights or both, on or off. Null for anything else said
  /// with them — a room, a name, a number — which is Home Assistant's to
  /// make sense of: "turn off the lounge lights", "the TV volume up".
  static VoiceSwitch? _switchOf(
    List<String> said, {
    List<String> computers = const [],
  }) {
    // "P C", as a recogniser may spell it out.
    said = [
      for (var i = 0; i < said.length; i++)
        if (said[i] == 'p' && i + 1 < said.length && said[i + 1] == 'c')
          'pc'
        else if (!(said[i] == 'c' && i > 0 && said[i - 1] == 'p'))
          said[i],
    ];
    said = _artMatrixJoined(said);
    // A computer's own name, word by word: "the omarchy PC".
    final named = {
      for (final c in computers) words(c).join(' '): words(c).toSet(),
    };
    final nameWords = <String>{};
    var saidComputer = false;
    final on = said.contains('on');
    // "Lights out", "kill the lights".
    final off = said.any(const {'off', 'out', 'kill'}.contains);
    if (on == off) return null;
    final things = <HomeThing>{};
    for (final w in said) {
      if (_tvWords.contains(w)) {
        things.add(HomeThing.tv);
      } else if (_lightWords.contains(w)) {
        things.add(HomeThing.lights);
      } else if (_computerWords.contains(w)) {
        things.add(HomeThing.computer);
        saidComputer = true;
      } else if (_artMatrixWords.contains(w)) {
        things.add(HomeThing.artMatrix);
      } else if (named.values.any((name) => name.contains(w))) {
        things.add(HomeThing.computer);
        nameWords.add(w);
      } else if (!const {'on', 'off', 'out', 'kill'}.contains(w) &&
          !_asking.contains(w) &&
          !_filler.contains(w) &&
          !_switchLoose.contains(w)) {
        return null;
      }
    }
    // The computer the most of whose name was said: "the kids laptop" is
    // the kids', not whichever laptop's name came first. Two as good — "the
    // laptop", with two — is neither, rather than a guess at one.
    String? computer;
    if (nameWords.isNotEmpty) {
      var best = 0;
      var tied = false;
      for (final MapEntry(:key, :value) in named.entries) {
        final heard = value.intersection(nameWords).length;
        if (heard > best) {
          best = heard;
          computer = key;
          tied = false;
        } else if (heard == best) {
          tied = true;
        }
      }
      if (tied) return null;
    }
    // A computer's name with the lights or the TV, and no "PC": a name like
    // any other — "the office lights" — for Home Assistant.
    if (computer != null && !saidComputer && things.length > 1) return null;
    return things.isEmpty
        ? null
        : VoiceSwitch(things, on: on, computer: computer);
  }

  /// [said] with "art matrix" — "art matrix's" too — as the one word
  /// "artmatrix".
  static List<String> _artMatrixJoined(List<String> said) {
    bool matrix(String w) => w == 'matrix' || w == 'matrixs';
    return [
      for (var i = 0; i < said.length; i++)
        if (said[i] == 'art' && i + 1 < said.length && matrix(said[i + 1]))
          'artmatrix'
        else if (!(matrix(said[i]) && i > 0 && said[i - 1] == 'art'))
          said[i],
    ];
  }

  /// Words that say a level is wanted, not some other number.
  static const _levelSaid = {
    'brightness', 'bright', 'level', 'percent', 'cent', 'set', 'dim', //
    'brighten',
  };

  /// What may come with the Art Matrix and a level, besides the asking and
  /// the filler: "set the Art Matrix brightness to 40 per cent", "Arty up
  /// to eighty".
  static const _levelLoose = {
    ..._levelSaid, 'per', 'change', 'make', 'at', 'up', 'down', //
  };

  /// "Art Matrix brightness 40", "set the Art Matrix to forty percent": the
  /// Art Matrix and one level, 1 to 100, with nothing else said — another
  /// thing, "off", a room. Null otherwise, for [_switchOf] or Home Assistant.
  /// A number said only after "to" or "at" needs nothing more to be a level:
  /// "turn the Art Matrix to 40".
  static VoiceArtMatrixBrightness? _artMatrixLevelOf(List<String> said) {
    said = _artMatrixJoined(said);
    if (!said.any(_artMatrixWords.contains)) return null;
    int? level;
    var at = -1;
    for (var i = 0; i < said.length; i++) {
      if (!_isLevelWord(said[i])) continue;
      // Two numbers: no telling which is meant.
      if (level != null) return null;
      var end = i;
      while (end + 1 < said.length && _isLevelWord(said[end + 1])) {
        end++;
      }
      level = _spokenLevel(said.sublist(i, end + 1));
      if (level == null) return null;
      at = i;
      i = end;
    }
    if (level == null) return null;
    final asked =
        said.any(_levelSaid.contains) ||
        (at > 0 && (said[at - 1] == 'to' || said[at - 1] == 'at'));
    if (!asked) return null;
    for (final w in said) {
      if (!_artMatrixWords.contains(w) &&
          !_isLevelWord(w) &&
          !_levelLoose.contains(w) &&
          !_asking.contains(w) &&
          !_filler.contains(w)) {
        return null;
      }
    }
    return VoiceArtMatrixBrightness(level.clamp(1, 100));
  }

  /// Numbers as said, for a level — as `PhotoQuery` has them for a year.
  static const _levelOnes = {
    'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, //
    'seven': 7, 'eight': 8, 'nine': 9,
  };

  static const _levelTeens = {
    'ten': 10, 'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14, //
    'fifteen': 15, 'sixteen': 16, 'seventeen': 17, 'eighteen': 18,
    'nineteen': 19,
  };

  static const _levelTens = {
    'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50, 'sixty': 60, //
    'seventy': 70, 'eighty': 80, 'ninety': 90,
  };

  static bool _isLevelWord(String w) =>
      int.tryParse(w) != null ||
      _levelOnes.containsKey(w) ||
      _levelTeens.containsKey(w) ||
      _levelTens.containsKey(w) ||
      w == 'hundred';

  /// The number [said] is — "40", "forty", "forty five", "one hundred" —
  /// or null for words that make no one number: "two forty".
  static int? _spokenLevel(List<String> said) {
    if (said.length == 1) {
      final w = said.single;
      return int.tryParse(w) ??
          _levelOnes[w] ??
          _levelTeens[w] ??
          _levelTens[w] ??
          (w == 'hundred' ? 100 : null);
    }
    if (said.length == 2) {
      final tens = _levelTens[said[0]];
      final ones = _levelOnes[said[1]];
      if (tens != null && ones != null) return tens + ones;
      if (said[0] == 'one' && said[1] == 'hundred') return 100;
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

    // "Photos of the beach", "a slideshow of Ellie": anything said with
    // photos is looked for in them, before it can be a page.
    final photos = _photosOf(said);
    if (photos != null) return photos;

    // "Let's cook the chasseur", "the pancake recipe", "recipes".
    final cook = _cookOf(said);
    if (cook != null) return cook;

    // "Turn the radio on": "on" is filler everywhere else.
    if (asked.length == 1 && asked.single == 'radio' && said.contains('on')) {
      return const VoiceRadio(VoiceRadioAsk.play);
    }
    // "Play Radio 4", "listen to six music" — but only a station there is:
    // "play the news" is still the news page.
    if ((asked.first == 'play' || asked.first == 'listen') &&
        asked.length > 1) {
      final name = asked.skip(1).join(' ');
      if (stationFor(name) != null) {
        return VoiceRadio(VoiceRadioAsk.play, name);
      }
    }

    if (!pages) return null;
    // "Bring the news closer", "the calendar up close": the tile, not only
    // its page. Said of nothing on the dashboard, it is left to be a page
    // or to go to Home Assistant, as it was before.
    final upClose = _closer.any(asked.contains) || _saidUpClose(asked);
    if (upClose) {
      final tile = _tileFor([
        for (final w in asked)
          if (!_closer.contains(w) &&
              !_closerFiller.contains(w) &&
              w != 'page' &&
              w != 'pages')
            w,
      ]);
      if (tile != null) return VoiceLiftTile(tile.page, tile.id);
    }
    final page = _pageFor(asked.where((w) => w != 'page' && w != 'pages'));
    return page == null ? null : VoiceShowPage(page);
  }

  /// Words that say photos are wanted.
  static const _photoWords = {
    'photo', 'photos', 'photograph', 'photographs', 'picture', 'pictures', //
    'pic', 'pics', 'snaps', 'snapshots', 'slideshow',
  };

  /// Photos asked for by what is in them, who, where or when: what was
  /// said around the word "photos", less the asking before it. Null when
  /// nothing is said but photos — "show the photos" is the albums — or
  /// when a tile is to be brought closer: "the photo bigger".
  static VoiceFindPhotos? _photosOf(List<String> said) {
    // "Slide show", as recognisers often hear it.
    final words = <String>[];
    for (final w in said) {
      if (w == 'show' && words.isNotEmpty && words.last == 'slide') {
        words.last = 'slideshow';
      } else {
        words.add(w);
      }
    }
    final at = words.indexWhere(_photoWords.contains);
    if (at < 0 || words.any(_closer.contains)) return null;
    // Before the word, only what follows the asking: "show me beach
    // photos" is the beach.
    var from = 0;
    for (var i = 0; i < at; i++) {
      if (_asking.contains(words[i]) || words[i] == 'play') from = i + 1;
    }
    while (from < at && _filler.contains(words[from])) {
      from++;
    }
    final asked = [...words.sublist(from, at), ...words.sublist(at + 1)];
    final meant = [
      for (final w in asked)
        if (!_filler.contains(w) &&
            !_asking.contains(w) &&
            !_photoWords.contains(w) &&
            !_photoLoose.contains(w))
          w,
    ];
    if (meant.isEmpty) return null;
    return VoiceFindPhotos(
      asked.join(' '),
      slideshow: words.contains('slideshow'),
    );
  }

  /// Words that say a recipe is wanted.
  static const _cookWords = {
    'cook', 'cooking', 'recipe', 'recipes', 'cookbook', 'cookery', //
  };

  /// What comes with them and says nothing about which: "let's cook
  /// something", "what can I cook".
  static const _cookLoose = {
    'lets', 'let', 'book', 'something', 'what', 'whats', 'can', 'could', //
    'shall', 'should', 'we', 'i', 'tonight', 'today', 'again', 'some', 'all',
    'saved', 'list', 'them', 'up', 'start', 'is', 'are', 'there', 'do', 'have',
  };

  /// A recipe asked for by name, or the book of them. Not "stop cooking",
  /// which an open recipe hears for itself.
  static VoiceCook? _cookOf(List<String> said) {
    if (!said.any(_cookWords.contains)) return null;
    if (said.any(
      const {'stop', 'close', 'exit', 'done', 'finished', 'timer'}.contains,
    )) {
      return null;
    }
    final name = [
      for (final w in said)
        if (!_cookWords.contains(w) &&
            !_cookLoose.contains(w) &&
            !_asking.contains(w) &&
            !_filler.contains(w))
          w,
    ];
    return VoiceCook(name.isEmpty ? null : name.join(' '));
  }

  /// What says nothing about which photos: "all the photos from...".
  static const _photoLoose = {
    'all', 'some', 'any', 'from', 'in', 'at', 'taken', 'by', 'start', //
    'play', 'videos', 'video', 'album', 'albums',
  };

  /// "Up close" or "close up", together, in [asked]: "close" on its own is
  /// "back".
  static bool _saidUpClose(List<String> asked) {
    for (var i = 0; i + 1 < asked.length; i++) {
      final pair = {asked[i], asked[i + 1]};
      if (pair.contains('up') && pair.contains('close')) return true;
    }
    return false;
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
      for (final name in _namesOf(w)) {
        yield (w.page, name);
      }
    }
  }

  /// What [w] answers to: its name, its type, and its other names.
  Iterable<List<String>> _namesOf(DashboardWidgetConfig w) sync* {
    for (final phrase in [
      ?_nameOf(w.type),
      w.type.replaceAll('_', ' '),
      ...?aliases[w.type],
    ]) {
      final name = _meaning(phrase);
      if (name.isNotEmpty) yield name;
    }
  }

  /// The widget on a page showing now that answers best to [asked]; the
  /// earliest, by page and then by place in the list, between equals.
  DashboardWidgetConfig? _tileFor(Iterable<String> asked) {
    final want = asked.map(_stem).toList();
    if (want.isEmpty) return null;
    final showing = visiblePages(pageCount, pages, _now).toSet();
    DashboardWidgetConfig? best;
    var bestScore = 0;
    for (final w in widgets) {
      if (!showing.contains(w.page)) continue;
      for (final name in _namesOf(w)) {
        final score = _score(want, name.map(_stem).toList());
        if (score > bestScore ||
            (score == bestScore && score > 0 && w.page < best!.page)) {
          best = w;
          bestScore = score;
        }
      }
    }
    return best;
  }

  /// The stations of the dashboard's Radio tiles, in order.
  List<RadioStation> get radioStationsHere => [
    for (final w in widgets)
      if (w.type == 'radio') ...radioStationsFrom(w.options['stations']),
  ];

  /// The station [said] names: one of the Radio tiles' first, by any part
  /// of its name, then any in the catalogue by the whole of it — or "play
  /// the news" would be NPR News.
  RadioStation? stationFor(String said) =>
      matchRadioStation(said, radioStationsHere) ??
      matchRadioStation(said, radioStations, whole: true);

  /// Every phrase the dashboard answers to as it stands — for a listener
  /// that does better when told what it might hear.
  List<String> get phrases => {
    for (final (_, name) in _answersTo()) name.join(' '),
    ..._fixed.keys,
    for (final r in routines) ...r.phrases.map((p) => words(p).join(' ')),
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
