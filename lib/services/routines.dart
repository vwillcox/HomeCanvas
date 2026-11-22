/// Something the house does when told one thing — "I'm going to bed" —
/// that is several things: the lights off, the TV off, the music stopped,
/// the panel dark.
///
/// Kept in the config (`routines`), edited in Settings → Screen → Voice
/// control → Routines, and heard by `VoiceCommands`, which matches what was
/// said against [phrases] — see [HomeRoutine.answersTo].
library;

/// What a routine can do. Each is something the panel does itself; anything
/// else is in [HomeRoutine.ask], said to Home Assistant.
enum RoutineStep {
  /// Every light Home Assistant's Assist can see.
  lightsOff,
  lightsOn,

  /// The television in Settings → TV.
  tvOff,
  tvOn,

  /// The Art Matrix LED display in Settings → Art Matrix.
  artMatrixOff,
  artMatrixOn,

  /// Whatever is playing: Spotify or a phone's music, and the radio.
  musicOff,

  /// The panel's own screen, a few seconds after, so the reply is seen.
  screenOff,
}

/// A white light's colour, as Home Assistant takes it: in kelvin.
enum LightWhite {
  warm(2700),
  neutral(4000),
  cool(6500);

  const LightWhite(this.kelvin);
  final int kelvin;
}

/// Lights a routine puts on, as it says: "the lounge lights to 80%, warm
/// white". Through Home Assistant, by name — not through Assist, which can
/// set a brightness but not a white.
class RoutineLights {
  RoutineLights({List<String>? targets, this.brightness, this.white})
    : targets = targets ?? [];

  /// The lights: entity ids ("light.lounge_1"), and whole rooms as
  /// "area:" and Home Assistant's id for them ("area:living_room").
  List<String> targets;

  /// Percent, 1 to 100; null leaves it as the light last had it.
  int? brightness;

  /// Null leaves the colour as it was.
  LightWhite? white;

  static const areaPrefix = 'area:';

  List<String> get entities => [
    for (final t in targets)
      if (!t.startsWith(areaPrefix)) t,
  ];

  List<String> get areas => [
    for (final t in targets)
      if (t.startsWith(areaPrefix)) t.substring(areaPrefix.length),
  ];

  /// What Home Assistant's `light.turn_on` is given.
  Map<String, Object?> get serviceData => {
    if (entities.isNotEmpty) 'entity_id': entities,
    if (areas.isNotEmpty) 'area_id': areas,
    'brightness_pct': ?brightness,
    'color_temp_kelvin': ?white?.kelvin,
  };

  RoutineLights copy() => RoutineLights(
    targets: [...targets],
    brightness: brightness,
    white: white,
  );

  static RoutineLights? fromJson(Object? j) {
    if (j is! Map) return null;
    final targets = [
      for (final t in (j['targets'] as List? ?? const []))
        if ('$t'.trim().isNotEmpty) '$t'.trim(),
    ];
    if (targets.isEmpty) return null;
    final b = j['brightness'];
    return RoutineLights(
      targets: targets,
      brightness: b is num ? b.round().clamp(1, 100) : null,
      white: LightWhite.values.where((w) => w.name == j['white']).firstOrNull,
    );
  }

  Map<String, dynamic> toJson() => {
    'targets': targets,
    'brightness': ?brightness,
    'white': ?white?.name,
  };
}

/// Something a routine asks out loud and acts on the answer to: "Do you
/// want the heater on or off?" — and switches [entity] to what is said, or
/// to what is touched on the screen. Nothing said leaves it as it was.
class RoutineQuestion {
  RoutineQuestion({required this.prompt, required this.entity, this.name = ''});

  /// As it is said: "Do you want the heater on or off?"
  String prompt;

  /// What the answer switches, through Home Assistant's
  /// `homeassistant.turn_on` and `turn_off`, which reach a heater, a fan, a
  /// switch or a light alike: "climate.heater".
  String entity;

  /// What it is called, for saying what was done: "heater".
  String name;

  RoutineQuestion copy() =>
      RoutineQuestion(prompt: prompt, entity: entity, name: name);

  static RoutineQuestion? fromJson(Object? j) {
    if (j is! Map) return null;
    final prompt = '${j['prompt'] ?? ''}'.trim();
    final entity = '${j['entity'] ?? ''}'.trim();
    if (prompt.isEmpty || !entity.contains('.')) return null;
    return RoutineQuestion(
      prompt: prompt,
      entity: entity,
      name: '${j['name'] ?? ''}'.trim(),
    );
  }

  Map<String, dynamic> toJson() => {
    'prompt': prompt,
    'entity': entity,
    if (name.isNotEmpty) 'name': name,
  };

  /// Words for on, and for off, in an answer. "Yes" is on and "no" off:
  /// asked "on or off?", "no" is not wanting it.
  static const _on = {
    'on', 'yes', 'yeah', 'yep', 'yup', 'please', 'sure', 'ok', 'okay', //
  };
  static const _off = {'off', 'of', 'no', 'nope', 'nah', 'not', 'dont'};

  /// What [said] — as words — answers: true for on, false for off, null for
  /// neither or both: "leave it", or the question itself heard back.
  static bool? answer(List<String> said) {
    final on = said.any(_on.contains);
    final off = said.any(_off.contains);
    return on == off ? null : on;
  }
}

class HomeRoutine {
  HomeRoutine({
    required this.name,
    List<String>? phrases,
    Set<RoutineStep>? steps,
    List<String>? ask,
    List<RoutineLights>? lights,
    this.otherLightsOff = false,
    List<RoutineQuestion>? questions,
    this.reply = '',
  }) : phrases = phrases ?? [],
       steps = steps ?? {},
       ask = ask ?? [],
       lights = lights ?? [],
       questions = questions ?? [];

  /// What it is called in Settings: "Bedtime".
  String name;

  /// What sets it off, after the wake words: "I'm going to bed", "goodnight".
  List<String> phrases;

  /// What it does itself.
  Set<RoutineStep> steps;

  /// What it asks of Home Assistant besides, each as it would be said —
  /// "turn off the purifier", "activate PC mode".
  List<String> ask;

  /// Lights put on as it says: "the lounge lights to 80%, warm white".
  List<RoutineLights> lights;

  /// Every other light switched off — every one Home Assistant shows, but
  /// for those in [lights].
  bool otherLightsOff;

  /// Asked out loud once the rest is done, one at a time.
  List<RoutineQuestion> questions;

  /// What it says once it has started: "Goodnight". Nothing when empty.
  String reply;

  /// The one there is to begin with, for the end of the day.
  factory HomeRoutine.bedtime() => HomeRoutine(
    name: 'Bedtime',
    phrases: [
      "I'm going to bed",
      "I'm off to bed",
      'Goodnight',
      'Night night',
      'Bedtime',
      'Time for bed',
    ],
    steps: {
      RoutineStep.lightsOff,
      RoutineStep.tvOff,
      RoutineStep.artMatrixOff,
      RoutineStep.musicOff,
      RoutineStep.screenOff,
    },
    reply: 'Goodnight',
  );

  /// The routines a config without any starts with. A config that has the
  /// key keeps what it has, none included: a routine deleted stays deleted.
  static List<HomeRoutine> defaults() => [HomeRoutine.bedtime()];

  factory HomeRoutine.fromJson(Map<String, dynamic> j) => HomeRoutine(
    name: '${j['name'] ?? ''}',
    phrases: [
      for (final p in (j['phrases'] as List? ?? const []))
        if ('$p'.trim().isNotEmpty) '$p'.trim(),
    ],
    steps: {
      for (final s in (j['steps'] as List? ?? const []))
        ?RoutineStep.values.where((v) => v.name == s).firstOrNull,
    },
    ask: [
      for (final a in (j['ask'] as List? ?? const []))
        if ('$a'.trim().isNotEmpty) '$a'.trim(),
    ],
    lights: [
      for (final l in (j['lights'] as List? ?? const []))
        ?RoutineLights.fromJson(l),
    ],
    otherLightsOff: j['otherLightsOff'] == true,
    questions: [
      for (final q in (j['questions'] as List? ?? const []))
        ?RoutineQuestion.fromJson(q),
    ],
    reply: '${j['reply'] ?? ''}',
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'phrases': phrases,
    // In the order they are listed, so the file reads the same each time.
    'steps': [
      for (final s in RoutineStep.values)
        if (steps.contains(s)) s.name,
    ],
    'ask': ask,
    if (lights.isNotEmpty) 'lights': [for (final l in lights) l.toJson()],
    if (otherLightsOff) 'otherLightsOff': true,
    if (questions.isNotEmpty)
      'questions': [for (final q in questions) q.toJson()],
    'reply': reply,
  };

  /// Words that come with a phrase and change nothing: "I'm going to bed
  /// now", "I am going to bed", "goodnight everyone, thanks".
  static const _loose = {
    'i', 'im', 'am', 'ill', 'id', 'a', 'the', 'my', 'me', 'to', 'now', //
    'please', 'just', 'going', 'gonna', 'go', 'heading', 'head', 'its', 'it',
    'is', 'for', 'we', 'were', 'us', 'everyone', 'everybody', 'all', 'okay',
    'ok', 'right', 'then', 'so', 'thank', 'thanks', 'you', 'and',
  };

  /// What is left of [words] to tell one phrase from another, run together
  /// — so "good night" is "goodnight", and "bed time" is "bedtime".
  static String gist(Iterable<String> words) =>
      words.where((w) => !_loose.contains(w)).join();

  /// Whether [said] — as words, without the wake words — is one of
  /// [phrases]: the same, but for the [_loose] words. The whole of it, not
  /// some of it: "turn off the bed light" is not "bed".
  bool answersTo(List<String> said, List<String> Function(String) words) {
    final heard = gist(said);
    if (heard.isEmpty) return false;
    return phrases.any((p) => gist(words(p)) == heard);
  }
}
