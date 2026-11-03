import 'voice_commands.dart';
import 'wake_word.dart';

/// What can be asked of the kitchen while a recipe is open — with flour on
/// both hands, out loud.
sealed class CookAsk {
  const CookAsk();
}

/// The next step, or the one before: [by] is 1 or -1.
class CookStep extends CookAsk {
  const CookStep(this.by);
  final int by;
}

/// A step by its number, counted from one; 0 for the last.
class CookGoTo extends CookAsk {
  const CookGoTo(this.step);
  final int step;
}

/// The step said again.
class CookRepeat extends CookAsk {
  const CookRepeat();
}

/// Every ingredient read out.
class CookIngredients extends CookAsk {
  const CookIngredients();
}

/// "How much flour?" — [asked] is what it is of: ["flour"].
class CookHowMuch extends CookAsk {
  const CookHowMuch(this.asked);
  final List<String> asked;
}

/// A timer started for the step's time.
class CookTimer extends CookAsk {
  const CookTimer();
}

/// How long the timers have left.
class CookTimeLeft extends CookAsk {
  const CookTimeLeft();
}

/// Cooking for a different number: [people], or [times] as many as now.
class CookServe extends CookAsk {
  const CookServe({this.people, this.times});
  final int? people;
  final double? times;
}

/// Quiet: the voice stops part-way.
class CookQuiet extends CookAsk {
  const CookQuiet();
}

/// Done cooking: the recipe put away.
class CookDone extends CookAsk {
  const CookDone();
}

/// Works out what was asked of an open recipe. Pure, like [VoiceCommands]:
/// words in, an ask out — null for anything that is not about the cooking,
/// which then goes to the panel's other commands as usual.
class CookCommands {
  static const _lead = {
    'ok', 'okay', 'right', 'alright', 'so', 'and', 'now', 'please', 'um', //
    'er', 'erm', 'uh', 'well', 'hey', 'then', 'yes', 'yeah', 'cool', 'great',
    'thanks', 'thank', 'you', 'can', 'could', 'would', 'will', 'i', 'we',
    'lets', 'let', 'us', 'me', 'just', 'go', 'the', 'a', 'to',
  };

  static const _next = {
    'next', 'next step', 'next one', 'done', 'done that', 'did that', //
    'whats next', 'what next', 'what now', 'whats now', 'on', 'go on',
    'carry on', 'continue', 'ready', 'got it', 'forward', 'move on',
    'onwards', 'onward', 'next please', 'step forward', 'skip', 'finished that',
    'and then', 'then what', 'what then', 'what do i do next',
  };

  static const _back = {
    'back', 'go back', 'back one', 'back step', 'previous', 'previous step', //
    'last step', 'step back', 'step before', 'before', 'one back',
    'back a step', 'go back a step', 'go back one', 'undo',
  };

  static const _again = {
    'again', 'repeat', 'repeat that', 'say again', 'say that again', //
    'read it', 'read that', 'read again', 'read it again', 'read step',
    'read this', 'read this step', 'read the step', 'pardon', 'sorry',
    'what', 'come again', 'what was that', 'whats that', 'what did you say',
    'what step', 'which step', 'where was i', 'where am i', 'where were we',
    'this step', 'step', 'current step',
  };

  static const _ingredients = {
    'ingredients', 'ingredient', 'ingredients list', 'list ingredients', //
    'read ingredients', 'read the ingredients', 'what do i need',
    'what do we need', 'what goes in', 'what goes in it', 'whats in it',
    'what is in it', 'shopping list', 'what i need',
  };

  static const _timer = {
    'timer', 'start timer', 'set timer', 'start timing', 'time it', //
    'set a timer', 'start a timer', 'start the timer', 'set the timer',
    'start clock', 'start the clock', 'timer on', 'go timer', 'time this',
    'set timer for this', 'timer for this', 'timer for that', 'time that',
  };

  static const _left = {
    'how long', 'how long left', 'how long now', 'time left', //
    'how much time', 'how much longer', 'how long to go', 'hows timer',
    'how is timer', 'how is the timer', 'hows the timer', 'timer left',
    'how long is left', 'how much time left', 'how long has it got',
  };

  static const _quiet = {
    'quiet', 'be quiet', 'shush', 'shh', 'hush', 'stop talking', 'silence', //
    'enough', 'thats enough', 'stop reading', 'stop',
  };

  static const _done = {
    'done cooking', 'finished cooking', 'stop cooking', 'all done', //
    'close recipe', 'close the recipe', 'exit', 'close', 'im done',
    'im finished', 'were done', 'were finished', 'finished', 'end',
    'thats it', 'put recipe away', 'close cooking', 'exit recipe',
    'leave recipe', 'quit', 'quit cooking', 'bon appetit',
  };

  static const _numbers = {
    'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, //
    'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11,
    'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15,
    'sixteen': 16, 'twenty': 20, 'first': 1, 'second': 2, 'third': 3,
    'fourth': 4, 'fifth': 5, 'sixth': 6, 'seventh': 7, 'eighth': 8,
    'ninth': 9, 'tenth': 10, 'won': 1, 'too': 2, 'for': 4, 'ate': 8,
  };

  /// What a recogniser makes of a number, and is also a word of its own.
  static const _soundsLike = {'won', 'too', 'for', 'ate'};

  /// What [heard] asks of the recipe, the wake words left off; null when
  /// it is about something else.
  static CookAsk? parse(String heard, {WakeWord? wake}) {
    var said = VoiceCommands.words(VoiceCommands.afterWake(heard, wake: wake));
    final w = wake ?? WakeWord();
    while (said.isNotEmpty && w.isWakeWord(said.first)) {
      said = said.sublist(1);
    }
    if (said.isEmpty) return null;
    final whole = said.join(' ');

    // "How much flour", "how many eggs do I need" — but "how much time"
    // and "how much longer" are the timers.
    final how = _howMuch(said);
    if (how != null) return how;

    // "How long is left", "how much time", "how long do I bake it".
    if (said.contains('how') &&
        said.any(const {'long', 'longer', 'time'}.contains)) {
      return const CookTimeLeft();
    }

    final serve = _serve(said);
    if (serve != null) return serve;

    final step = _stepNumber(said);
    if (step != null) return step;

    // The rest, as said and with the "ok, so, now" in front taken off.
    var rest = said;
    while (rest.length > 1 && _lead.contains(rest.first)) {
      rest = rest.sublist(1);
    }
    while (rest.length > 1 &&
        (rest.last == 'please' || rest.last == 'thanks')) {
      rest = rest.sublist(0, rest.length - 1);
    }
    for (final form in {whole, rest.join(' '), _compact(rest)}) {
      if (_left.contains(form)) return const CookTimeLeft();
      if (_timer.contains(form)) return const CookTimer();
      if (_done.contains(form)) return const CookDone();
      if (_quiet.contains(form)) return const CookQuiet();
      if (_ingredients.contains(form)) return const CookIngredients();
      if (_next.contains(form)) return const CookStep(1);
      if (_back.contains(form)) return const CookStep(-1);
      if (_again.contains(form)) return const CookRepeat();
      if (const {
        'start',
        'start again',
        'from the top',
        'beginning',
        'top',
        'first step',
        'start over',
        'go to start',
        'restart',
      }.contains(form)) {
        return const CookGoTo(1);
      }
      if (const {
        'last',
        'final step',
        'the end',
        'last one',
        'final one',
      }.contains(form)) {
        return const CookGoTo(0);
      }
    }
    return null;
  }

  /// [said] without the words that never change what is meant.
  static String _compact(List<String> said) => said
      .where(
        (w) => !const {
          'the',
          'a',
          'an',
          'my',
          'this',
          'that',
          'it',
          'please',
          'to',
        }.contains(w),
      )
      .join(' ');

  static CookHowMuch? _howMuch(List<String> said) {
    for (var i = 0; i + 1 < said.length; i++) {
      if (said[i] != 'how') continue;
      if (said[i + 1] != 'much' && said[i + 1] != 'many') continue;
      final asked = [
        for (final w in said.sublist(i + 2))
          if (!const {
            'of', 'the', 'do', 'does', 'i', 'we', 'you', 'need', 'is', 'are', //
            'there', 'it', 'use', 'should', 'put', 'in', 'goes', 'go', 'add',
            'again', 'was', 'were', 'did', 'say', 'want', 'have', 'get',
            'please', 'for', 'this', 'that', 'some', 'into',
          }.contains(w))
            w,
      ];
      if (asked.isEmpty) return null;
      // "How much time is left", "how much longer": the timers'.
      if (asked.contains('time') || asked.contains('longer')) return null;
      return CookHowMuch(asked);
    }
    // "What's the flour", "flour how much".
    return null;
  }

  static CookServe? _serve(List<String> said) {
    final whole = said.join(' ');
    if (RegExp(r'\b(double|twice)\b').hasMatch(whole)) {
      return const CookServe(times: 2);
    }
    if (RegExp(r'\b(halve|half)\b').hasMatch(whole) &&
        !whole.contains('hour')) {
      return const CookServe(times: 0.5);
    }
    if (RegExp(r'\btriple\b').hasMatch(whole)) return const CookServe(times: 3);
    // "For six people", "serves four", "make it for 8", "enough for ten",
    // "six servings".
    final asksPeople = RegExp(
      r'\b(people|persons|servings|portions|serves|serving|feed|feeds|cooking for|make it for|enough for|scale)\b',
    ).hasMatch(whole);
    if (!asksPeople) return null;
    // A number said as one first: "for" is more often "for" than four.
    for (final loose in [false, true]) {
      for (final w in said) {
        if (_soundsLike.contains(w) != loose) continue;
        final n = int.tryParse(w) ?? _numbers[w];
        if (n != null && n > 0 && n <= 100) return CookServe(people: n);
      }
    }
    return null;
  }

  static CookGoTo? _stepNumber(List<String> said) {
    final at = said.indexOf('step');
    if (at < 0) return null;
    final rest = [
      for (final w in said)
        if (!const {
          'go',
          'to',
          'step',
          'number',
          'the',
          'show',
          'me',
          'read',
          'skip',
          'jump',
          'back',
          'on',
          'what',
          'whats',
          'is',
        }.contains(w))
          w,
    ];
    if (rest.length != 1) return null;
    final n = int.tryParse(rest.single) ?? _numbers[rest.single];
    if (n == null || n < 1) return null;
    return CookGoTo(n);
  }
}
