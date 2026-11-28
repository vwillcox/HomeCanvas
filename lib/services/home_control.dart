import 'dart:async';

import 'package:flutter/foundation.dart';

import 'art_matrix_service.dart' show ArtMatrixResult;
import 'computer_power.dart' show PcSwitch;
import 'routines.dart';
import 'tv_service.dart' show TvSwitch;
import 'voice_commands.dart' show HomeThing;

/// Does what "turn the TV off", "lights on" and "I'm going to bed" ask for:
/// the television through `TvService`, the lights through Home Assistant's
/// Assist, the rest on the panel itself.
///
/// Everything it reaches is passed in, so it can be tested with none of it
/// there. Each call says at once what it is doing, for the voice indicator,
/// and does it after; only what went wrong is said out loud, through [say].
class HomeControl {
  HomeControl({
    required this.tvReady,
    required this.tv,
    required this.assistReady,
    required this.assist,
    required this.stopPlaying,
    required this.screenOff,
    required this.say,
    this.computerReady = _never,
    this.computerNames = _noNames,
    this.computer = _noComputer,
    this.artMatrixReady = _never,
    this.artMatrix = _noArtMatrix,
    this.artMatrixBrightness = _noArtMatrixLevel,
    this.service = _noService,
    this.lightsOnBesides = _noLights,
    this.question = _noAnswer,
    this.screenDelay = const Duration(seconds: 5),
  });

  static bool _never() => false;
  static Future<bool> _noService(String d, String s, Map<String, Object?> m) =>
      Future.value(false);
  static Future<List<String>?> _noLights(List<String> keep) =>
      Future.value(null);
  static Future<bool?> _noAnswer(RoutineQuestion q) => Future.value(null);
  static List<String> _noNames() => const [];
  static Future<PcSwitch> _noComputer(bool on, String? named) async =>
      PcSwitch.none;
  static Future<ArtMatrixResult> _noArtMatrix(bool on) async =>
      ArtMatrixResult.notSetUp;
  static Future<ArtMatrixResult> _noArtMatrixLevel(int level) async =>
      ArtMatrixResult.notSetUp;

  /// Whether there is a television in Settings → TV.
  final bool Function() tvReady;

  /// Switches the television: see `TvService.setPower`.
  final Future<TvSwitch> Function(bool on) tv;

  /// Whether Home Assistant is set up: the lights, and a routine's own
  /// requests, go through its Assist.
  final bool Function() assistReady;

  /// Says [text] to Home Assistant's Assist; its answer, or null for none.
  final Future<String?> Function(String text) assist;

  /// Stops whatever the panel is playing: music, the radio, a video.
  final Future<void> Function() stopPlaying;

  /// Darkens the panel's screen.
  final Future<void> Function() screenOff;

  /// Says something out loud — a problem, or a routine's reply.
  final void Function(String text) say;

  /// Whether a computer collects links from the panel, to be switched.
  final bool Function() computerReady;

  /// What the computers are called, for the voice to know them by.
  final List<String> Function() computerNames;

  /// Switches a computer, by name or the only one: see `ComputerPower`.
  final Future<PcSwitch> Function(bool on, String? named) computer;

  /// Whether there is an Art Matrix in Settings → Art Matrix.
  final bool Function() artMatrixReady;

  /// Switches the Art Matrix's display: see `ArtMatrixService.setPower`.
  final Future<ArtMatrixResult> Function(bool on) artMatrix;

  /// Sets the Art Matrix's brightness, which puts it on too: see
  /// `ArtMatrixService.setBrightness`.
  final Future<ArtMatrixResult> Function(int level) artMatrixBrightness;

  /// Calls a Home Assistant service with its data as given — the lights to
  /// a brightness and a white — and says whether it was taken.
  final Future<bool> Function(
    String domain,
    String service,
    Map<String, Object?> data,
  )
  service;

  /// The lights on now, but for those in a routine's — see
  /// `HomeAssistantService.lightsOnBesides`. Null when it could not tell.
  final Future<List<String>?> Function(List<String> keep) lightsOnBesides;

  /// Asks [RoutineQuestion.prompt] out loud and waits for the answer, said
  /// or touched: true for on, false for off, null for none.
  final Future<bool?> Function(RoutineQuestion q) question;

  /// How long the screen stays lit after a routine, so its reply is seen.
  final Duration screenDelay;

  /// What Assist is told for the lights: all of them, which it takes as
  /// every light exposed to it. Only "all" works without a room — asked
  /// to "turn the lights off" it finds nothing to turn off.
  static String lightsAsk(bool on) =>
      'turn ${on ? 'on' : 'off'} all the lights';

  /// Switches [things] on or off, and says what that is — "TV and lights
  /// off" — or null when none of them is set up here, for Home Assistant to
  /// be asked instead.
  String? switchThings(
    Set<HomeThing> things, {
    required bool on,
    String? computer,
  }) {
    final doing = [
      if (things.contains(HomeThing.tv) && tvReady()) HomeThing.tv,
      if (things.contains(HomeThing.lights) && assistReady()) HomeThing.lights,
      if (things.contains(HomeThing.computer) && computerReady())
        HomeThing.computer,
      if (things.contains(HomeThing.artMatrix) && artMatrixReady())
        HomeThing.artMatrix,
    ];
    if (doing.isEmpty) return null;
    unawaited(_switch(doing, on: on, computer: computer));
    final names = [
      for (final t in doing)
        switch (t) {
          HomeThing.tv => 'TV',
          HomeThing.lights => 'lights',
          HomeThing.computer => 'PC',
          HomeThing.artMatrix => 'Art Matrix',
        },
    ].join(' and ');
    return '$names ${on ? 'on' : 'off'}';
  }

  Future<void> _switch(
    List<HomeThing> things, {
    required bool on,
    String? computer,
  }) async {
    final problems = await Future.wait([
      if (things.contains(HomeThing.tv)) _tv(on, quietIfGone: false),
      if (things.contains(HomeThing.lights)) _lights(on),
      if (things.contains(HomeThing.computer)) _computer(on, computer),
      if (things.contains(HomeThing.artMatrix))
        _artMatrix(() => artMatrix(on), quietIfGone: false),
    ]);
    for (final p in problems.nonNulls) {
      say(p);
    }
  }

  /// Sets the Art Matrix to [level] percent, 1 to 100, which puts it on as
  /// well, and says what that is — "Art Matrix 40%" — or null when there is
  /// none set up here, for Home Assistant to be asked instead.
  String? setArtMatrixBrightness(int level) {
    if (!artMatrixReady()) return null;
    final to = level.clamp(1, 100);
    unawaited(_artMatrixLevel(to));
    return 'Art Matrix $to%';
  }

  Future<void> _artMatrixLevel(int level) async {
    final problem = await _artMatrix(
      () => artMatrixBrightness(level),
      quietIfGone: false,
    );
    if (problem != null) say(problem);
  }

  /// Starts [routine], and says what to show for it: its reply, or its
  /// name when it has none.
  String runRoutine(HomeRoutine routine) {
    unawaited(_routine(routine));
    final reply = routine.reply.trim();
    return reply.isNotEmpty ? reply : routine.name;
  }

  Future<void> _routine(HomeRoutine r) async {
    final steps = r.steps;
    // The playing first, so the reply is not said over music.
    if (steps.contains(RoutineStep.musicOff)) {
      await _guard('stop playing', stopPlaying);
    }
    final reply = r.reply.trim();
    if (reply.isNotEmpty) say(reply);
    final tvOn = steps.contains(RoutineStep.tvOn);
    final tvOff = steps.contains(RoutineStep.tvOff);
    final lightsOn = steps.contains(RoutineStep.lightsOn);
    final lightsOff = steps.contains(RoutineStep.lightsOff);
    final artMatrixOn = steps.contains(RoutineStep.artMatrixOn);
    final artMatrixOff = steps.contains(RoutineStep.artMatrixOff);
    // The house's lights one after another, while the TV and the Art Matrix
    // go at once: all of them on or off first, then what is asked, then the
    // lights set. "The lights off" with "the bedside lamp at 10%" leaves
    // the lamp on; together, Assist's "all off" landed after it and put it
    // out. In the order given too, a scene then a light in it.
    Future<List<String?>> house() async => [
      if ((lightsOn || lightsOff) && assistReady()) await _lights(!lightsOff),
      if (r.ask.isNotEmpty && assistReady()) await _asks(r.ask),
      if ((r.lights.isNotEmpty || r.otherLightsOff) && assistReady())
        await _setLights(r),
    ];
    final others = Future.wait([
      // Off, if both are ticked: the safer of the two to have done.
      if ((tvOn || tvOff) && tvReady())
        // A set that cannot be reached when it is to go off very likely is
        // off already; nothing to say about it at bedtime.
        _tv(!tvOff, quietIfGone: tvOff),
      // As the TV: off if both, and one not answering at bedtime is very
      // likely unplugged, which is off enough.
      if ((artMatrixOn || artMatrixOff) && artMatrixReady())
        _artMatrix(() => artMatrix(!artMatrixOff), quietIfGone: artMatrixOff),
    ]);
    final lit = house();
    final problems = [...await others, ...await lit];
    for (final p in problems.nonNulls) {
      say(p);
    }
    // Asked once the rest is done and said, so nothing the panel says is
    // heard as the answer.
    if (assistReady()) {
      for (final q in r.questions) {
        await _ask(q);
      }
    }
    if (steps.contains(RoutineStep.screenOff)) {
      await Future<void>.delayed(screenDelay);
      await _guard('switch the screen off', screenOff);
    }
  }

  /// [HomeRoutine.lights] put on as they say, and with
  /// [HomeRoutine.otherLightsOff] every other light that is on put off;
  /// what to say about it if it went wrong.
  Future<String?> _setLights(HomeRoutine r) async {
    final keep = [for (final l in r.lights) ...l.targets];
    // Which are on is asked before any is switched: the routine's own
    // lights, just put on, are not to be put off again.
    final others = r.otherLightsOff ? await _try(lightsOnBesides(keep)) : null;
    final done = await Future.wait([
      for (final l in r.lights)
        if (l.targets.isNotEmpty)
          _try(service('light', 'turn_on', l.serviceData)),
      if (others != null && others.isNotEmpty)
        _try(service('light', 'turn_off', {'entity_id': others})),
    ]);
    debugPrint(
      'Home: lights for ${r.name}: ${done.join(', ')}; '
      'off: ${others ?? 'unknown'}',
    );
    if (done.any((d) => d != true) || (r.otherLightsOff && others == null)) {
      return "Home Assistant couldn't set all the lights.";
    }
    return null;
  }

  /// Asks [q], and switches its thing to the answer — and says so. Nothing
  /// said, nothing switched.
  Future<void> _ask(RoutineQuestion q) async {
    final what = q.name.isNotEmpty ? q.name : 'it';
    final bool? on;
    try {
      on = await question(q);
    } catch (e) {
      debugPrint('Home: asking "${q.prompt}": $e');
      return;
    }
    debugPrint('Home: "${q.prompt}": ${on ?? 'no answer'}');
    if (on == null) {
      say('Leaving the $what as it is.');
      return;
    }
    final ok = await _try(
      service('homeassistant', on ? 'turn_on' : 'turn_off', {
        'entity_id': q.entity,
      }),
    );
    final state = on ? 'on' : 'off';
    say(
      ok == true
          ? '${_capital(what)} $state.'
          : "Home Assistant couldn't turn the $what $state.",
    );
  }

  static String _capital(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// [f]'s value, or null when it threw.
  static Future<T?> _try<T>(Future<T> f) async {
    try {
      return await f;
    } catch (e) {
      debugPrint('Home: $e');
      return null;
    }
  }

  /// The television switched; what to say about it if it went wrong.
  Future<String?> _tv(bool on, {required bool quietIfGone}) async {
    final TvSwitch result;
    try {
      result = await tv(on);
    } catch (e) {
      debugPrint('Home: TV: $e');
      return "Couldn't reach the TV.";
    }
    debugPrint('Home: TV ${on ? 'on' : 'off'}: ${result.name}');
    return switch (result) {
      TvSwitch.done || TvSwitch.already || TvSwitch.woken => null,
      TvSwitch.unreachable when quietIfGone => null,
      TvSwitch.unreachable => "The TV isn't answering.",
      TvSwitch.unknown =>
        "The TV wouldn't say whether it was on, so I left it.",
      TvSwitch.needsPairing =>
        'The TV needs pairing again: in Settings, under TV.',
      TvSwitch.notSetUp => null,
    };
  }

  /// The Art Matrix switched, or set to a brightness, by [ask]; what to say
  /// about it if it went wrong.
  Future<String?> _artMatrix(
    Future<ArtMatrixResult> Function() ask, {
    required bool quietIfGone,
  }) async {
    final ArtMatrixResult result;
    try {
      result = await ask();
    } catch (e) {
      debugPrint('Home: Art Matrix: $e');
      return "Couldn't reach the Art Matrix.";
    }
    debugPrint('Home: Art Matrix: ${result.name}');
    return switch (result) {
      ArtMatrixResult.done || ArtMatrixResult.notSetUp => null,
      ArtMatrixResult.unreachable when quietIfGone => null,
      ArtMatrixResult.unreachable => "The Art Matrix isn't answering.",
      ArtMatrixResult.refused => "The Art Matrix didn't take that.",
      ArtMatrixResult.notLocal =>
        "The Art Matrix's address isn't on your home network.",
    };
  }

  /// A computer switched; what to say about it. Unlike the TV, whether it
  /// was already so is said too: the computer is seldom in the room.
  Future<String?> _computer(bool on, String? named) async {
    final PcSwitch result;
    try {
      result = await computer(on, named);
    } catch (e) {
      debugPrint('Home: PC: $e');
      return "Couldn't reach the PC.";
    }
    debugPrint('Home: PC ${on ? 'on' : 'off'}: ${result.name}');
    return switch (result) {
      PcSwitch.done || PcSwitch.none => null,
      PcSwitch.already => 'The PC is already ${on ? 'on' : 'off'}.',
      PcSwitch.notWoken => "The PC didn't wake up.",
      PcSwitch.cannotWake => "The PC hasn't told the panel how to wake it yet.",
    };
  }

  /// The lights switched; what to say about it if it went wrong.
  Future<String?> _lights(bool on) async {
    try {
      final answer = await assist(lightsAsk(on));
      debugPrint('Home: lights ${on ? 'on' : 'off'}: $answer');
      return answer == null
          ? "Home Assistant couldn't switch the lights."
          : null;
    } catch (e) {
      debugPrint('Home: lights: $e');
      return "Couldn't reach Home Assistant for the lights.";
    }
  }

  Future<String?> _asks(List<String> asks) async {
    final missed = <String>[];
    for (final text in asks) {
      try {
        final answer = await assist(text);
        debugPrint('Home: "$text": $answer');
        if (answer == null) missed.add(text);
      } catch (e) {
        debugPrint('Home: "$text": $e');
        missed.add(text);
      }
    }
    return missed.isEmpty
        ? null
        : "Home Assistant couldn't do: ${missed.join(', ')}.";
  }

  static Future<void> _guard(String what, Future<void> Function() step) async {
    try {
      await step();
    } catch (e) {
      debugPrint('Home: could not $what: $e');
    }
  }
}
