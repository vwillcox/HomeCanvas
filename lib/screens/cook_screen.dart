import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../dashboard/dashboard_theme.dart';
import '../l10n/l10n.dart';
import '../look.dart';
import '../services/config_service.dart';
import '../services/cook_voice.dart';
import '../services/kitchen.dart';
import '../services/recipe.dart';
import '../services/screen_idle_service.dart';
import '../services/timer_service.dart';
import '../time_format.dart';
import '../widgets/glass.dart';
import '../widgets/lcars.dart';
import '../widgets/remote_image.dart';
import 'link_viewer_screen.dart';

/// Opens the recipe on the page at [url] to cook from — or, when the page
/// has none, offers the page itself. [read] reads each step out as it
/// comes, as it does when asked for out loud.
Future<void> openRecipeAt(
  BuildContext context,
  String url, {
  bool read = false,
}) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => _RecipeLoader(url: url, read: read),
  ),
);

/// Opens [recipe] to cook from.
Future<void> openRecipe(
  BuildContext context,
  Recipe recipe, {
  bool read = false,
}) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => CookScreen(recipe: recipe, read: read),
  ),
);

/// Every recipe cooked here, to cook again.
Future<void> openRecipeBook(BuildContext context, {String? missing}) =>
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RecipeBookScreen(missing: missing)),
    );

/// A recipe to cook from, a step at a time, from across the kitchen.
///
/// The step fills the screen in type to read from the hob. Its times are
/// timers to touch — "simmer for 20 minutes" starts a Simmer timer, which
/// counts down in the step itself — and the ingredients it uses are lit in
/// the list beside it. Cooking for more or fewer than the recipe says scales
/// every amount, the method's too.
///
/// And it listens: "hey canvas, next", "go back", "how much flour?", "start
/// the timer", "for six people" — hands in the dough, eyes on the pan.
class CookScreen extends StatefulWidget {
  const CookScreen({super.key, required this.recipe, this.read = false});

  final Recipe recipe;

  /// Read each step aloud as it comes up.
  final bool read;

  @override
  State<CookScreen> createState() => _CookScreenState();
}

class _CookScreenState extends State<CookScreen> {
  late final Kitchen _kitchen = context.read<Kitchen>();
  late final TimerService _timers = context.read<TimerService>();
  late final List<Ingredient> _ingredients = [
    for (final line in widget.recipe.ingredients) Ingredient.parse(line),
  ];
  late SavedRecipe _entry;
  late int _step;
  late int? _people;
  late bool _reading = widget.read;
  final Set<int> _ticked = {};

  /// The ingredients just asked about, lit for a few seconds.
  Set<int> _asked = const {};
  Timer? _askedFade;

  /// The timer started from each of a step's times: "step:index" to id.
  final Map<String, int> _started = {};
  Timer? _awake;
  late final String? Function(String) _listener = _heard;

  Recipe get _recipe => widget.recipe;
  int get _count => _recipe.steps.length;
  double get _factor {
    final base = _recipe.servings;
    final people = _people;
    if (base == null || people == null || base <= 0) return 1;
    return people / base;
  }

  @override
  void initState() {
    super.initState();
    final had = _kitchen.savedAs(_recipe);
    // Put away part-way within the day: back where it was left.
    final recent =
        had?.cooked != null &&
        DateTime.now().difference(had!.cooked!) < const Duration(hours: 18);
    _entry = _kitchen.open(_recipe);
    _step = recent ? _entry.step.clamp(0, _count - 1) : 0;
    _people = (recent ? _entry.people : null) ?? _recipe.servings;
    Kitchen.listening = _listener;
    // A recipe being cooked is a panel in use, however long between
    // touches: the screen stays on.
    _awake = Timer.periodic(const Duration(seconds: 50), (_) {
      if (mounted) context.read<ScreenIdleService>().noteInteraction();
    });
    if (_reading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _readStep());
    }
  }

  @override
  void dispose() {
    if (Kitchen.listening == _listener) Kitchen.listening = null;
    _awake?.cancel();
    _askedFade?.cancel();
    unawaited(_kitchen.quiet());
    _kitchen.leftAt(
      _entry,
      step: _step >= _count - 1 ? 0 : _step,
      people: _people,
    );
    super.dispose();
  }

  void _go(int to, {bool read = false}) {
    final next = to.clamp(0, _count - 1);
    if (next == _step) {
      if (read) _readStep();
      return;
    }
    setState(() => _step = next);
    _kitchen.leftAt(_entry, step: next, people: _people);
    if (_reading || read) {
      _readStep();
    } else {
      unawaited(_kitchen.quiet());
    }
  }

  void _readStep() {
    final s = _recipe.steps[_step];
    final pieces = stepPieces(s.text, _factor).map((p) => p.text).join();
    final head = tr('cook.stepSaid', 'Step {n}.', {'n': _step + 1});
    final last = _step == _count - 1
        ? ' ${tr('cook.lastStepSaid', 'That is the last step.')}'
        : '';
    unawaited(_kitchen.say('$head ${s.heading ?? ''} $pieces$last'));
  }

  void _setPeople(int n) {
    if (_recipe.servings == null) return;
    setState(() => _people = n.clamp(1, 99));
    _kitchen.leftAt(_entry, step: _step, people: _people);
  }

  /// Starts the timer for the [i]th time in the current step — or, when it
  /// is already running, leaves it be.
  KioskTimer? _startTimer(int step, int i) {
    final times = _recipe.steps[step].times;
    if (i >= times.length) return null;
    final key = '$step:$i';
    final had = _timerFor(key);
    if (had != null) return had;
    final t = times[i];
    final label = t.label.isNotEmpty
        ? t.label
        : tr('cook.stepTimer', 'Step {n}', {'n': step + 1});
    final timer = _timers.start(t.length, label: label, sound: 'chime');
    setState(() => _started[key] = timer.id);
    return timer;
  }

  KioskTimer? _timerFor(String key) {
    final id = _started[key];
    if (id == null) return null;
    for (final t in _timers.timers) {
      if (t.id == id) return t;
    }
    return null;
  }

  void _close() => Navigator.of(context).maybePop();

  /// What was said, if it is for the recipe: done, and what was done said
  /// back; null to let the panel's other commands have it.
  String? _heard(String heard) {
    if (!mounted) return null;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return null;
    final wake = context.read<ConfigService>().config.screen.wakeWord;
    final ask = CookCommands.parse(heard, wake: wake);
    if (ask == null) return null;
    switch (ask) {
      case CookStep(:final by):
        if (by > 0 && _step == _count - 1) {
          unawaited(
            _kitchen.say(
              tr('cook.noMoreSteps', 'That was the last step. Enjoy!'),
            ),
          );
          return 'last step';
        }
        _go(_step + by, read: true);
        return by > 0 ? 'next step' : 'step back';
      case CookGoTo(:final step):
        final to = step == 0 ? _count - 1 : step - 1;
        if (to >= _count) return null;
        _go(to, read: true);
        return 'step ${to + 1}';
      case CookRepeat():
        _readStep();
        return 'step ${_step + 1}';
      case CookIngredients():
        final lines = [for (final i in _ingredients) '${i.spoken(_factor)}.'];
        unawaited(_kitchen.say(lines.join(' ')));
        return 'ingredients';
      case CookHowMuch(:final asked):
        final found = ingredientsAsked(asked, _ingredients);
        if (found.isEmpty) {
          unawaited(
            _kitchen.say(
              tr('cook.notInIt', 'There is no {what} in this recipe.', {
                'what': asked.join(' '),
              }),
            ),
          );
          return 'not in it';
        }
        _light(found.toSet());
        unawaited(
          _kitchen.say(
            found.map((i) => _ingredients[i].spoken(_factor)).join(', and '),
          ),
        );
        return asked.join(' ');
      case CookTimer():
        final times = _recipe.steps[_step].times;
        if (times.isEmpty) {
          unawaited(
            _kitchen.say(tr('cook.noTime', 'This step has no time in it.')),
          );
          return 'no time';
        }
        // The first not already running.
        var i = 0;
        while (i < times.length - 1 && _timerFor('$_step:$i') != null) {
          i++;
        }
        final t = _startTimer(_step, i);
        if (t != null) {
          unawaited(
            _kitchen.say(
              tr('cook.timerStarted', '{label}, {time}. Started.', {
                'label': t.label,
                'time': TimerService.describe(t.total),
              }),
            ),
          );
        }
        return 'timer';
      case CookTimeLeft():
        final running = _timers.timers.where((t) => !t.finished).toList();
        if (running.isEmpty) {
          // No timer going: how long the step says, then.
          final times = _recipe.steps[_step].times;
          unawaited(
            _kitchen.say(
              times.isEmpty
                  ? tr('cook.noTimers', 'No timers running.')
                  : tr('cook.stepSays', 'This step says {time}.', {
                      'time': TimerService.describe(times.first.length),
                    }),
            ),
          );
          return 'time left';
        }
        final now = _timers.now;
        unawaited(
          _kitchen.say(
            running
                .map((t) => '${t.label}: ${_said(t.remaining(now))}')
                .join('. '),
          ),
        );
        return 'time left';
      case CookServe(:final people, :final times):
        if (_recipe.servings == null) return null;
        final n = people ?? ((_people ?? _recipe.servings!) * times!).round();
        _setPeople(n);
        unawaited(
          _kitchen.say(tr('cook.nowFor', 'Now for {n}.', {'n': _people})),
        );
        return 'for $_people';
      case CookQuiet():
        if (!_kitchen.speaking) return null;
        unawaited(_kitchen.quiet());
        return 'quiet';
      case CookDone():
        _close();
        return 'done cooking';
    }
  }

  /// "4 minutes 30", "45 seconds".
  static String _said(Duration d) {
    if (d.inMinutes == 0) return '${d.inSeconds} seconds';
    final s = d.inSeconds % 60;
    final m = TimerService.describe(Duration(minutes: d.inMinutes));
    return s == 0 || d.inMinutes >= 10 ? m : '$m $s';
  }

  void _light(Set<int> which) {
    _askedFade?.cancel();
    setState(() => _asked = which);
    _askedFade = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _asked = const {});
    });
  }

  @override
  Widget build(BuildContext context) {
    // Ticking with the timers, so a running one counts down in the step.
    context.watch<TimerService>();
    final look = context.look;
    final step = _recipe.steps[_step];
    final uses = ingredientsIn(step.text, _ingredients);
    return look.isLcars
        ? _console(context, look, step, uses)
        : _glass(context, look, step, uses);
  }

  // Glass, and every other theme.

  Widget _glass(
    BuildContext context,
    DashboardTheme look,
    RecipeStep step,
    Set<int> uses,
  ) {
    return ModernScaffold(
      header: ScreenHeader(
        onBack: _close,
        backIcon: Icons.close_rounded,
        backTooltip: tr('cook.closeRecipe', 'Close the recipe'),
        titleWidget: _GlassTitle(recipe: _recipe, people: _people),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_recipe.servings != null) ...[
              _PeopleStepper(
                people: _people ?? _recipe.servings!,
                makes: _makes(_recipe),
                onChange: _setPeople,
              ),
              const SizedBox(width: 14),
            ],
            PillIconButton(
              icon: _reading
                  ? Icons.record_voice_over_rounded
                  : Icons.voice_over_off_rounded,
              selected: _reading,
              tooltip: _reading
                  ? tr('cook.readingOn', 'Reading each step aloud')
                  : tr('cook.readingOff', 'Read each step aloud'),
              onPressed: () {
                setState(() => _reading = !_reading);
                if (_reading) {
                  _readStep();
                } else {
                  unawaited(_kitchen.quiet());
                }
              },
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(28, 4, 28, 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 500,
              child: Glass(
                radius: look.cornerRadius.clamp(0, 28),
                padding: const EdgeInsets.fromLTRB(26, 22, 18, 12),
                child: _IngredientList(
                  ingredients: _ingredients,
                  factor: _factor,
                  ticked: _ticked,
                  uses: uses,
                  asked: _asked,
                  onTick: (i) => setState(
                    () => _ticked.contains(i)
                        ? _ticked.remove(i)
                        : _ticked.add(i),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Glass(
                radius: look.cornerRadius.clamp(0, 28),
                padding: const EdgeInsets.fromLTRB(44, 30, 36, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StepHeading(
                      step: _step,
                      count: _count,
                      heading: step.heading,
                      section: step.section,
                      onJump: (i) => _go(i),
                    ),
                    const SizedBox(height: 22),
                    Expanded(
                      child: _Swipe(
                        onSwipe: (by) => _go(_step + by),
                        child: _StepText(
                          key: ValueKey(_step),
                          text: step.text,
                          factor: _factor,
                          timerFor: (i) => _timerFor('$_step:$i'),
                          onTime: (i) => _startTimer(_step, i),
                          onTimer: _timerTapped,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _GlassFooter(
                      first: _step == 0,
                      last: _step == _count - 1,
                      onBack: () => _go(_step - 1),
                      onNext: _step == _count - 1
                          ? _close
                          : () => _go(_step + 1),
                      timers: _timers,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A running timer touched in the step: paused or carried on; a finished
  /// one, put away.
  void _timerTapped(KioskTimer t) {
    if (t.finished) {
      _timers.remove(t.id);
    } else {
      _timers.togglePause(t.id);
    }
  }

  // LCARS.

  Widget _console(
    BuildContext context,
    DashboardTheme look,
    RecipeStep step,
    Set<int> uses,
  ) {
    final inside = Padding(
      padding: const EdgeInsets.fromLTRB(26, 10, 6, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 470,
            child: _IngredientList(
              ingredients: _ingredients,
              factor: _factor,
              ticked: _ticked,
              uses: uses,
              asked: _asked,
              onTick: (i) => setState(
                () => _ticked.contains(i) ? _ticked.remove(i) : _ticked.add(i),
              ),
            ),
          ),
          Container(
            width: lcarsLine * 2,
            margin: const EdgeInsets.symmetric(horizontal: 22),
            color: look.block(4).withValues(alpha: 0.6),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StepHeading(
                  step: _step,
                  count: _count,
                  heading: step.heading,
                  section: step.section,
                  onJump: (i) => _go(i),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: _Swipe(
                    onSwipe: (by) => _go(_step + by),
                    child: _StepText(
                      key: ValueKey(_step),
                      text: step.text,
                      factor: _factor,
                      timerFor: (i) => _timerFor('$_step:$i'),
                      onTime: (i) => _startTimer(_step, i),
                      onTimer: _timerTapped,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _ConsoleFooter(
                  look: look,
                  first: _step == 0,
                  last: _step == _count - 1,
                  people: _recipe.servings == null
                      ? null
                      : (_people ?? _recipe.servings!),
                  makes: _makes(_recipe),
                  reading: _reading,
                  onPeople: _setPeople,
                  onReading: () {
                    setState(() => _reading = !_reading);
                    if (_reading) {
                      _readStep();
                    } else {
                      unawaited(_kitchen.quiet());
                    }
                  },
                  onBack: () => _go(_step - 1),
                  onNext: _step == _count - 1 ? _close : () => _go(_step + 1),
                  onClose: _close,
                  timers: _timers,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: LcarsPanel(
            theme: look,
            heavy: true,
            label: lcarsCaps(_recipe.name),
            // A block down the side for each step, the one being cooked
            // lit — as long as there are few enough to letter.
            child: _count <= 14
                ? LcarsSide(
                    blocks: [
                      for (var i = 0; i < _count; i++)
                        LcarsSideBlock(
                          label:
                              _recipe.steps[i].heading ??
                              tr('cook.stepBlock', 'Step {n}', {'n': i + 1}),
                          selected: i == _step,
                          onTap: () => _go(i),
                        ),
                    ],
                    child: inside,
                  )
                : inside,
          ),
        ),
      ),
    );
  }
}

/// The recipe's name, and how many, how long and from where.
class _GlassTitle extends StatelessWidget {
  const _GlassTitle({required this.recipe, required this.people});

  final Recipe recipe;
  final int? people;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final time = recipe.time;
    final bits = [
      if (time != null) _duration(time),
      ?recipe.author,
      ?_site(recipe.url),
    ];
    return Row(
      children: [
        if (recipe.image != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 76,
              height: 76,
              child: RemoteImage(
                url: recipe.image!,
                headers: const {},
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 20),
        ],
        Expanded(
          child: HeaderTitle(
            title: recipe.name,
            subtitle: bits.join('  ·  '),
            colour: look.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// The site a recipe is from, "bbcgoodfood.com" — not an address with no
/// name.
String? _site(String? url) {
  final host = Uri.tryParse(url ?? '')?.host ?? '';
  if (host.isEmpty ||
      host == 'localhost' ||
      RegExp(r'^[\d.]+$|:').hasMatch(host)) {
    return null;
  }
  return host.replaceFirst(RegExp(r'^www\.'), '');
}

/// Whether [r] says what it makes, "Makes 12", rather than who it serves.
bool _makes(Recipe r) =>
    (r.yieldText ?? '').toLowerCase().trimLeft().startsWith('makes');

/// "1 hr 15 min", "45 min".
String _duration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  if (h == 0) return tr('common.min', '{n} min', {'n': m});
  if (m == 0) return tr('cook.hours', '{n} hr', {'n': h});
  return tr('cook.hoursMinutes', '{h} hr {m} min', {'h': h, 'm': m});
}

/// − Serves 4 +
class _PeopleStepper extends StatelessWidget {
  const _PeopleStepper({
    required this.people,
    required this.onChange,
    this.makes = false,
  });

  final int people;

  /// Counted in what it makes — 12 pancakes — rather than who it feeds.
  final bool makes;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    return Glass(
      radius: 999,
      strip: true,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            iconSize: 30,
            color: look.textPrimary,
            tooltip: tr('cook.fewer', 'Fewer'),
            onPressed: people > 1 ? () => onChange(people - 1) : null,
            icon: const Icon(Icons.remove_rounded),
          ),
          SizedBox(
            width: 120,
            child: Text(
              makes
                  ? tr('cook.makes', 'Makes {n}', {'n': people})
                  : tr('cook.serves', 'Serves {n}', {'n': people}),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: look.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            iconSize: 30,
            color: look.textPrimary,
            tooltip: tr('cook.more', 'More'),
            onPressed: () => onChange(people + 1),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}

/// The ingredients, to tick off as they are got out; those the step uses
/// lit, and those just asked about lit brighter.
class _IngredientList extends StatelessWidget {
  const _IngredientList({
    required this.ingredients,
    required this.factor,
    required this.ticked,
    required this.uses,
    required this.asked,
    required this.onTick,
  });

  final List<Ingredient> ingredients;
  final double factor;
  final Set<int> ticked;
  final Set<int> uses;
  final Set<int> asked;
  final ValueChanged<int> onTick;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final lcars = look.isLcars;
    final title = tr('cook.ingredients', 'Ingredients');
    final ready = ticked.isEmpty
        ? (factor == 1
              ? tr('cook.tickHint', 'Touch each one as it is out')
              : tr('cook.scaled', 'Scaled for you'))
        : tr('cook.ready', '{n} of {total} out', {
            'n': ticked.length,
            'total': ingredients.length,
          });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lcars)
          Row(
            children: [
              LcarsBlock(
                colour: look.block(1),
                ends: LcarsEnds.start,
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Text(
                  lcarsCaps(title),
                  style: const TextStyle(fontSize: 20),
                ),
              ),
              const SizedBox(width: lcarsLine * 2),
              Expanded(
                child: Text(
                  lcarsCaps(ready),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: look.block(1),
                    fontSize: 18,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          )
        else ...[
          Text(
            title,
            style: TextStyle(
              color: look.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            ready,
            style: TextStyle(color: look.textSecondary, fontSize: 17),
          ),
        ],
        const SizedBox(height: 14),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: ingredients.length,
            itemBuilder: (context, i) => _IngredientRow(
              ingredient: ingredients[i],
              factor: factor,
              ticked: ticked.contains(i),
              used: uses.contains(i),
              asked: asked.contains(i),
              colour: look.block(i),
              onTap: () => onTick(i),
            ),
          ),
        ),
      ],
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({
    required this.ingredient,
    required this.factor,
    required this.ticked,
    required this.used,
    required this.asked,
    required this.colour,
    required this.onTap,
  });

  final Ingredient ingredient;
  final double factor;
  final bool ticked;
  final bool used;
  final bool asked;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final lcars = look.isLcars;
    final amount = ingredient.amountText(factor);
    final rest = ingredient.restText(factor);
    final lit = used || asked;
    final ink = ticked
        ? look.textSecondary.withValues(alpha: 0.5)
        : lit
        ? look.textPrimary
        : look.textPrimary.withValues(alpha: lcars ? 0.75 : 0.82);
    final mark = lcars ? colour : look.accent;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lcars)
            // A console's tick: a block lit near-white once it is out.
            Container(
              width: 30,
              height: 26,
              margin: const EdgeInsets.only(top: 2, right: 16),
              decoration: BoxDecoration(
                color: ticked
                    ? lcarsLit
                    : (lit ? colour : colour.withValues(alpha: 0.35)),
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(13),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 1, right: 14),
              child: Icon(
                ticked
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 28,
                color: ticked ? look.accent : look.textSecondary,
              ),
            ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (amount.isNotEmpty)
                    TextSpan(
                      text: '$amount ',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: ticked ? ink : (factor != 1 ? mark : ink),
                      ),
                    ),
                  TextSpan(text: rest),
                ],
              ),
              style: TextStyle(
                color: ink,
                fontSize: lit ? 23 : 21,
                height: 1.25,
                fontWeight: lit ? FontWeight.w600 : FontWeight.w400,
                decoration: ticked ? TextDecoration.lineThrough : null,
                decorationColor: ink,
              ),
            ),
          ),
        ],
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: lcars ? 0 : 220),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: asked
              ? mark.withValues(alpha: 0.28)
              : used && !ticked
              ? mark.withValues(alpha: lcars ? 0.0 : 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(lcars ? 0 : 12),
          border: lcars && lit && !ticked
              ? Border(left: BorderSide(color: colour, width: 4))
              : null,
        ),
        child: row,
      ),
    );
  }
}

/// "Step 3 of 8", what the step is called, and a mark for every step to
/// jump to.
class _StepHeading extends StatelessWidget {
  const _StepHeading({
    required this.step,
    required this.count,
    required this.onJump,
    this.heading,
    this.section,
  });

  final int step;
  final int count;
  final String? heading;
  final String? section;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final lcars = look.isLcars;
    final of = tr('cook.stepOf', 'Step {n} of {total}', {
      'n': step + 1,
      'total': count,
    });
    final name = [?section, ?heading].join('  ·  ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              lcars ? lcarsCaps(of) : of,
              style: TextStyle(
                color: lcars ? look.block(2) : look.accent,
                fontSize: lcars ? 30 : 24,
                fontWeight: FontWeight.w800,
                letterSpacing: lcars ? 2 : 0.4,
              ),
            ),
            if (name.isNotEmpty) ...[
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  lcars ? lcarsCaps(name) : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: look.textSecondary,
                    fontSize: lcars ? 24 : 22,
                    letterSpacing: lcars ? 1.5 : 0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        // A mark for each step: those done filled, this one lit, those to
        // come dim. Touch one to go there.
        SizedBox(
          height: lcars ? 18 : 10,
          child: Row(
            children: [
              for (var i = 0; i < count; i++) ...[
                if (i > 0) SizedBox(width: lcars ? lcarsLine : 6),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onJump(i),
                    child: Container(
                      decoration: BoxDecoration(
                        color: i == step
                            ? (lcars ? lcarsLit : look.accent)
                            : i < step
                            ? (lcars
                                  ? look.block(i)
                                  : look.accent.withValues(alpha: 0.5))
                            : (lcars
                                  ? look.block(i).withValues(alpha: 0.28)
                                  : look.textPrimary.withValues(alpha: 0.14)),
                        borderRadius: BorderRadius.circular(lcars ? 0 : 99),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Turns the step on a swipe across it.
class _Swipe extends StatelessWidget {
  const _Swipe({required this.onSwipe, required this.child});

  final ValueChanged<int> onSwipe;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v.abs() < 300) return;
        onSwipe(v < 0 ? 1 : -1);
      },
      child: child,
    );
  }
}

/// The step, large: its amounts scaled and marked, its times touchable —
/// and, once touched, counting down where they were.
class _StepText extends StatelessWidget {
  const _StepText({
    super.key,
    required this.text,
    required this.factor,
    required this.timerFor,
    required this.onTime,
    required this.onTimer,
  });

  final String text;
  final double factor;
  final KioskTimer? Function(int i) timerFor;
  final ValueChanged<int> onTime;
  final ValueChanged<KioskTimer> onTimer;

  /// As large as fits: a short step in type to read from across the room,
  /// a long one as large as the room on screen allows.
  static double fit(
    List<StepPiece> pieces,
    TextStyle style,
    Size room, {
    double most = 68,
    double least = 28,
  }) {
    // A time is a chip: an icon and room round its words.
    final approx = pieces
        .map((p) => p.time == null ? p.text : 'MM ${p.text} M')
        .join();
    for (var size = most; size > least; size -= 2) {
      final tp = TextPainter(
        text: TextSpan(
          text: approx,
          style: style.copyWith(fontSize: size),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: room.width);
      final fits = tp.height <= room.height;
      tp.dispose();
      if (fits) return size;
    }
    return least;
  }

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final lcars = look.isLcars;
    final pieces = stepPieces(text, factor);
    final base = TextStyle(
      color: look.textPrimary,
      height: 1.32,
      fontWeight: FontWeight.w500,
      fontFamily: lcars ? look.fontFamily : null,
      letterSpacing: lcars ? 0.6 : -0.2,
    );
    return LayoutBuilder(
      builder: (context, c) {
        final size = fit(
          pieces,
          base,
          Size(c.maxWidth - 8, c.maxHeight * 0.94),
        );
        var timeIndex = 0;
        final spans = <InlineSpan>[];
        for (final p in pieces) {
          if (p.time != null) {
            final i = timeIndex++;
            spans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _TimeChip(
                  said: p.text,
                  time: p.time!,
                  size: size,
                  timer: timerFor(i),
                  onStart: () => onTime(i),
                  onTimer: onTimer,
                ),
              ),
            );
          } else if (p.scaled) {
            spans.add(
              TextSpan(
                text: p.text,
                style: TextStyle(
                  color: lcars ? look.block(1) : look.accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            );
          } else {
            spans.add(TextSpan(text: p.text));
          }
        }
        final body = SingleChildScrollView(
          child: Text.rich(
            TextSpan(children: spans),
            style: base.copyWith(fontSize: size),
          ),
        );
        if (lcars) return body;
        // A gentle arrival, the way glass moves; a console just shows it.
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(24 * (1 - t), 0),
              child: child,
            ),
          ),
          child: body,
        );
      },
    );
  }
}

/// A time in a step: touch it for a timer, which then counts down here.
class _TimeChip extends StatelessWidget {
  const _TimeChip({
    required this.said,
    required this.time,
    required this.size,
    required this.timer,
    required this.onStart,
    required this.onTimer,
  });

  final String said;
  final StepTime time;
  final double size;
  final KioskTimer? timer;
  final VoidCallback onStart;
  final ValueChanged<KioskTimer> onTimer;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final lcars = look.isLcars;
    final t = timer;
    final now = context.read<TimerService>().now;
    final text = t == null
        ? said
        : t.finished
        ? tr('cook.timerDone', '{label} done', {'label': t.label})
        : _clock(t.remaining(now));
    final colour = lcars
        ? (t == null ? look.block(3) : (t.finished ? lcarsLit : look.block(5)))
        : (t?.finished ?? false)
        ? look.accent
        : look.accent.withValues(alpha: t == null ? 0.22 : 0.32);
    final ink = lcars
        ? lcarsInk
        : (t?.finished ?? false)
        ? Colors.white
        : look.textPrimary;
    final icon = t == null
        ? Icons.timer_outlined
        : t.finished
        ? Icons.notifications_active_rounded
        : t.paused
        ? Icons.play_arrow_rounded
        : Icons.pause_rounded;
    final chipSize = size * 0.8;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: colour,
        shape: lcars
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(chipSize * 0.7),
              )
            : StadiumBorder(
                side: BorderSide(
                  color: look.accent.withValues(alpha: 0.7),
                  width: 2,
                ),
              ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: t == null ? onStart : () => onTimer(t),
          splashFactory: lcars ? NoSplash.splashFactory : null,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: chipSize * 0.42,
              vertical: chipSize * 0.08,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (t != null && !t.finished) ...[
                  SizedBox(
                    width: chipSize * 0.8,
                    height: chipSize * 0.8,
                    child: CircularProgressIndicator(
                      value: t.fraction(now),
                      strokeWidth: chipSize * 0.11,
                      color: ink,
                      backgroundColor: ink.withValues(alpha: 0.2),
                    ),
                  ),
                  SizedBox(width: chipSize * 0.25),
                ] else ...[
                  Icon(icon, size: chipSize * 0.9, color: ink),
                  SizedBox(width: chipSize * 0.2),
                ],
                Text(
                  lcars ? lcarsCaps(text) : text,
                  style: TextStyle(
                    color: ink,
                    fontSize: chipSize,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "12:04", "1:02:30".
String _clock(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// Back, every timer running, and Next — or Done on the last step.
class _GlassFooter extends StatelessWidget {
  const _GlassFooter({
    required this.first,
    required this.last,
    required this.onBack,
    required this.onNext,
    required this.timers,
  });

  final bool first;
  final bool last;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final TimerService timers;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: first ? null : onBack,
          icon: const Icon(Icons.arrow_back_rounded, size: 30),
          label: Text(tr('cook.back', 'Back')),
          style: OutlinedButton.styleFrom(
            foregroundColor: look.textPrimary,
            side: BorderSide(
              color: look.textPrimary.withValues(alpha: 0.3),
              width: 2,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 22),
            textStyle: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
            shape: const StadiumBorder(),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(child: _TimerStrip(timers: timers)),
        const SizedBox(width: 18),
        FilledButton.icon(
          onPressed: onNext,
          icon: Icon(
            last ? Icons.check_rounded : Icons.arrow_forward_rounded,
            size: 32,
          ),
          label: Text(last ? tr('cook.done', 'Done') : tr('cook.next', 'Next')),
          style: FilledButton.styleFrom(
            backgroundColor: look.accent,
            foregroundColor: look.accent.computeLuminance() > 0.45
                ? Colors.black
                : Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 24),
            textStyle: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
            shape: const StadiumBorder(),
          ),
        ),
      ],
    );
  }
}

/// Every kitchen timer running, from this recipe or not: touch one to
/// pause it, or put it away once it has gone off.
class _TimerStrip extends StatelessWidget {
  const _TimerStrip({required this.timers});

  final TimerService timers;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final lcars = look.isLcars;
    final all = timers.timers;
    if (all.isEmpty) {
      return Text(
        tr(
          'cook.voiceHint',
          'Say “next”, “how much flour?” or “start the timer”',
        ),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: lcars ? look.block(4) : look.textSecondary,
          fontSize: lcars ? 18 : 17,
          letterSpacing: lcars ? 1 : 0,
        ),
      );
    }
    final now = timers.now;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final (i, t) in all.indexed) ...[
            if (i > 0) const SizedBox(width: 10),
            _TimerPill(
              timer: t,
              now: now,
              colour: lcars ? look.block(i + 5) : look.accent,
              onTap: () =>
                  t.finished ? timers.remove(t.id) : timers.togglePause(t.id),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimerPill extends StatelessWidget {
  const _TimerPill({
    required this.timer,
    required this.now,
    required this.colour,
    required this.onTap,
  });

  final KioskTimer timer;
  final DateTime now;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final lcars = look.isLcars;
    final t = timer;
    final text = t.finished
        ? tr('cook.timerDone', '{label} done', {'label': t.label})
        : '${t.label}  ${_clock(t.remaining(now))}';
    if (lcars) {
      return LcarsBlock(
        colour: t.finished ? lcarsLit : colour,
        height: 52,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Text(
          lcarsCaps(text),
          style: const TextStyle(
            fontSize: 22,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      );
    }
    return Material(
      color: t.finished ? colour : colour.withValues(alpha: 0.18),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 20, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: t.finished
                    ? const Icon(
                        Icons.notifications_active_rounded,
                        color: Colors.white,
                        size: 26,
                      )
                    : CircularProgressIndicator(
                        value: t.fraction(now),
                        strokeWidth: 4,
                        color: colour,
                        backgroundColor: colour.withValues(alpha: 0.2),
                      ),
              ),
              const SizedBox(width: 12),
              Text(
                text,
                style: TextStyle(
                  color: t.finished ? Colors.white : look.textPrimary,
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A console's footer: close, how many, the voice, the timers, back and
/// next — blocks in a row.
class _ConsoleFooter extends StatelessWidget {
  const _ConsoleFooter({
    required this.look,
    required this.first,
    required this.last,
    required this.people,
    this.makes = false,
    required this.reading,
    required this.onPeople,
    required this.onReading,
    required this.onBack,
    required this.onNext,
    required this.onClose,
    required this.timers,
  });

  final DashboardTheme look;
  final bool first;
  final bool last;
  final int? people;
  final bool makes;
  final bool reading;
  final ValueChanged<int> onPeople;
  final VoidCallback onReading;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onClose;
  final TimerService timers;

  @override
  Widget build(BuildContext context) {
    const h = 64.0;
    const type = TextStyle(fontSize: 24);
    return Row(
      children: [
        LcarsBlock(
          colour: look.block(6),
          ends: LcarsEnds.start,
          height: h,
          width: 130,
          onTap: onClose,
          child: Text(lcarsCaps(tr('cook.close', 'Close')), style: type),
        ),
        const SizedBox(width: lcarsLine * 2),
        if (people != null) ...[
          LcarsBlock(
            colour: look.block(7),
            ends: LcarsEnds.none,
            height: h,
            width: 64,
            onTap: people! > 1 ? () => onPeople(people! - 1) : null,
            child: const Icon(Icons.remove_rounded, color: lcarsInk, size: 32),
          ),
          const SizedBox(width: lcarsLine),
          Container(
            height: h,
            width: 150,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(
                  color: look.block(7),
                  width: lcarsLine * 2,
                ),
              ),
            ),
            child: Text(
              lcarsCaps(
                makes
                    ? tr('cook.makes', 'Makes {n}', {'n': two(people!)})
                    : tr('cook.serves', 'Serves {n}', {'n': two(people!)}),
              ),
              style: TextStyle(
                color: look.block(7),
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(width: lcarsLine),
          LcarsBlock(
            colour: look.block(7),
            ends: LcarsEnds.none,
            height: h,
            width: 64,
            onTap: () => onPeople(people! + 1),
            child: const Icon(Icons.add_rounded, color: lcarsInk, size: 32),
          ),
          const SizedBox(width: lcarsLine * 2),
        ],
        LcarsBlock(
          colour: reading ? lcarsLit : look.block(8),
          ends: LcarsEnds.none,
          height: h,
          width: 130,
          onTap: onReading,
          child: Text(
            lcarsCaps(
              reading
                  ? tr('cook.voiceOn', 'Voice on')
                  : tr('cook.voice', 'Voice'),
            ),
            style: type,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(child: _TimerStrip(timers: timers)),
        const SizedBox(width: 14),
        LcarsBlock(
          colour: first ? look.block(2).withValues(alpha: 0.35) : look.block(2),
          ends: LcarsEnds.none,
          height: h,
          width: 150,
          onTap: first ? null : onBack,
          child: Text(lcarsCaps(tr('cook.back', 'Back')), style: type),
        ),
        const SizedBox(width: lcarsLine * 2),
        LcarsBlock(
          colour: last ? lcarsLit : look.block(0),
          ends: LcarsEnds.end,
          height: h,
          width: 190,
          onTap: onNext,
          child: Text(
            lcarsCaps(last ? tr('cook.done', 'Done') : tr('cook.next', 'Next')),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// Reading the page for its recipe, then the recipe — or, when there is
/// none, the page.
class _RecipeLoader extends StatefulWidget {
  const _RecipeLoader({required this.url, required this.read});

  final String url;
  final bool read;

  @override
  State<_RecipeLoader> createState() => _RecipeLoaderState();
}

class _RecipeLoaderState extends State<_RecipeLoader> {
  bool _none = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final recipe = await context.read<Kitchen>().recipeAt(widget.url);
    if (!mounted) return;
    if (recipe == null) {
      setState(() => _none = true);
      return;
    }
    unawaited(
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CookScreen(recipe: recipe, read: widget.read),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final host = Uri.tryParse(widget.url)?.host.replaceFirst('www.', '') ?? '';
    final words = _none
        ? tr('cook.noRecipe', 'No recipe on that page')
        : tr('cook.reading', 'Reading the recipe…');
    return ModernScaffold(
      header: ScreenHeader(
        onBack: () => Navigator.of(context).maybePop(),
        title: words,
        subtitle: host,
      ),
      body: Center(
        child: _none
            ? FilledButton.icon(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => LinkViewerScreen(url: widget.url),
                  ),
                ),
                icon: const Icon(Icons.open_in_browser_rounded, size: 30),
                label: Text(tr('cook.openPage', 'Open the page')),
                style: whitePillButton(context),
              )
            : look.isLcars
            ? SizedBox(
                width: 420,
                child: LcarsSegments(theme: look, value: 0.6, height: 22),
              )
            : CircularProgressIndicator(color: look.accent),
      ),
    );
  }
}

/// Every recipe cooked on the panel, the latest first, to cook again —
/// shared from a phone once, kept here for good.
class RecipeBookScreen extends StatelessWidget {
  const RecipeBookScreen({super.key, this.missing});

  /// What was asked for and not found, to say so.
  final String? missing;

  @override
  Widget build(BuildContext context) {
    final kitchen = context.watch<Kitchen>();
    final look = context.look;
    final book = kitchen.book;
    final subtitle = missing != null
        ? tr('cook.notFound', 'No recipe called “{name}” yet', {
            'name': missing,
          })
        : book.isEmpty
        ? tr(
            'cook.bookEmptyHint',
            'Share a recipe from your phone and it is kept here',
          )
        : tr('cook.bookCount', '{n, plural, one{# recipe} other{# recipes}}', {
            'n': book.length,
          });
    return ModernScaffold(
      header: ScreenHeader(
        onBack: () => Navigator.of(context).maybePop(),
        title: tr('cook.book', 'Recipes'),
        subtitle: subtitle,
      ),
      body: book.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(60),
                child: Text(
                  tr(
                    'cook.bookEmpty',
                    'Find a recipe on your phone and share it to the panel with the HomeCanvas app. It opens here to cook from, a step at a time — and stays, to cook again.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: look.textSecondary,
                    fontSize: 24,
                    height: 1.4,
                  ),
                ),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(40, 8, 40, 40),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 440,
                mainAxisSpacing: 22,
                crossAxisSpacing: 22,
                childAspectRatio: 1.15,
              ),
              itemCount: book.length,
              itemBuilder: (context, i) => _RecipeCard(
                entry: book[i],
                index: i,
                onTap: () => openRecipe(context, book[i].recipe),
                onForget: () => kitchen.forget(book[i]),
              ),
            ),
    );
  }
}

class _RecipeCard extends StatefulWidget {
  const _RecipeCard({
    required this.entry,
    required this.index,
    required this.onTap,
    required this.onForget,
  });

  final SavedRecipe entry;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onForget;

  @override
  State<_RecipeCard> createState() => _RecipeCardState();
}

class _RecipeCardState extends State<_RecipeCard> {
  /// Held: asking whether to take it out of the book.
  bool _asking = false;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final lcars = look.isLcars;
    final r = widget.entry.recipe;
    final time = r.time;
    final detail = [
      if (r.servings != null)
        r.yieldText ?? tr('cook.serves', 'Serves {n}', {'n': r.servings}),
      if (time != null) _duration(time),
    ].join('  ·  ');
    final radius = lcars ? 0.0 : look.cornerRadius.clamp(0.0, 24.0);
    final colour = look.block(widget.index);
    final picture = r.image == null
        ? Container(
            color: lcars ? colour.withValues(alpha: 0.25) : look.wash(0.08),
            alignment: Alignment.center,
            child: Icon(
              Icons.restaurant_rounded,
              size: 72,
              color: lcars ? colour : look.textSecondary,
            ),
          )
        : RemoteImage(url: r.image!, headers: const {}, fit: BoxFit.cover);
    return GestureDetector(
      onTap: _asking ? null : widget.onTap,
      onLongPress: () => setState(() => _asking = true),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            picture,
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 30, 20, 16),
                decoration: BoxDecoration(
                  color: lcars ? Colors.black : null,
                  border: lcars
                      ? Border(left: BorderSide(color: colour, width: 14))
                      : null,
                  gradient: lcars
                      ? null
                      : const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xD9000000)],
                        ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      lcars ? lcarsCaps(r.name) : r.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: lcars ? colour : Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                    if (detail.isNotEmpty)
                      Text(
                        lcars ? lcarsCaps(detail) : detail,
                        style: TextStyle(
                          color: lcars ? look.textSecondary : Colors.white70,
                          fontSize: 18,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_asking)
              Container(
                color: Colors.black.withValues(alpha: 0.78),
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      tr('cook.forgetAsk', 'Take it out of the book?'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 24),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () => setState(() => _asking = false),
                          child: Text(
                            tr('cook.keep', 'Keep'),
                            style: const TextStyle(
                              fontSize: 22,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        const SizedBox(width: 18),
                        FilledButton(
                          onPressed: widget.onForget,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFD9534F),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 26,
                              vertical: 16,
                            ),
                          ),
                          child: Text(
                            tr('cook.forget', 'Take out'),
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
