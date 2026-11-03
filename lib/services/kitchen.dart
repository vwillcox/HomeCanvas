import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../app_paths.dart';
import 'article_reader.dart';
import 'article_text.dart';
import 'http_client.dart';
import 'plain_text.dart';
import 'private_file.dart';
import 'recipe.dart';

/// A recipe cooked on the panel, kept for next time — and where it was
/// left, so a recipe put away half-way through comes back at that step.
class SavedRecipe {
  SavedRecipe({
    required this.recipe,
    required this.added,
    this.cooked,
    this.step = 0,
    this.people,
  });

  final Recipe recipe;
  final DateTime added;
  DateTime? cooked;

  /// The step it was left at, counted from zero, and for how many.
  int step;
  int? people;

  Map<String, Object?> toJson() => {
    ...recipe.toJson(),
    'added': added.toIso8601String(),
    if (cooked != null) 'cooked': cooked!.toIso8601String(),
    'at': step,
    if (people != null) 'people': people,
  };

  static SavedRecipe? fromJson(Map<String, dynamic> j) {
    final recipe = Recipe.fromJson(j);
    if (recipe == null) return null;
    return SavedRecipe(
      recipe: recipe,
      added: DateTime.tryParse('${j['added']}') ?? DateTime.now(),
      cooked: DateTime.tryParse('${j['cooked']}'),
      step: (j['at'] as num?)?.toInt() ?? 0,
      people: (j['people'] as num?)?.toInt(),
    );
  }
}

/// The kitchen: the recipes cooked here, finding the recipe in a page, and
/// a voice to read a step out while hands are busy.
///
/// Recipes are kept in `recipes.json` beside the settings — the most
/// recently cooked first, at most [keep] of them — so "hey canvas, let's
/// cook the chasseur" finds one again, without the site, or the network.
class Kitchen extends ChangeNotifier {
  Kitchen({
    this.output,
    double Function()? volume,
    bool Function()? muted,
    Future<String> Function(String url)? fetch,
    String? path,
  }) : _volume = volume ?? (() => 100),
       _muted = muted ?? (() => false),
       _fetch = fetch ?? _fetchPage,
       _path = path ?? p.join(AppPaths.config, 'recipes.json');

  /// Where the voice is made and played. Null for none — a test.
  final SpeechOutput? output;
  final double Function() _volume;
  final bool Function() _muted;
  final Future<String> Function(String url) _fetch;
  final String _path;

  static const keep = 60;

  /// What an open recipe makes of words said to the panel, before anything
  /// else does: "next", "how much flour". Set by the recipe on screen; null
  /// when none is.
  static String? Function(String heard)? listening;

  final List<SavedRecipe> _book = [];
  List<SavedRecipe> get book => List.unmodifiable(_book);

  Future<void> load() async {
    try {
      final f = File(_path);
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      _book
        ..clear()
        ..addAll([
          for (final r in (j is Map ? j['recipes'] as List? : null) ?? const [])
            if (r is Map) ?SavedRecipe.fromJson(r.cast<String, dynamic>()),
        ]);
      notifyListeners();
    } catch (e) {
      debugPrint('Kitchen: could not read recipes: $e');
    }
  }

  /// The last save asked for, done once those before it are: a step
  /// turned and the book reordered at once must not land in the wrong
  /// order, older over newer.
  Future<void> _saving = Future.value();

  /// Done when everything asked for so far is on disk.
  @visibleForTesting
  Future<void> get saved => _saving;

  Future<void> _save() {
    return _saving = _saving.then((_) async {
      try {
        // As the book is when its turn comes, which is the newest.
        await writePrivateFile(
          _path,
          const JsonEncoder.withIndent(' ').convert({
            'recipes': [for (final r in _book) r.toJson()],
          }),
        );
      } catch (e) {
        debugPrint('Kitchen: could not save recipes: $e');
      }
    });
  }

  /// The saved recipe that [recipe] is: the same page, or the same name.
  SavedRecipe? savedAs(Recipe recipe) {
    for (final s in _book) {
      if (recipe.url != null && s.recipe.url == recipe.url) return s;
    }
    for (final s in _book) {
      if (s.recipe.url == null && s.recipe.name == recipe.name) return s;
    }
    return null;
  }

  /// Keeps [recipe] at the top of the book — opened now — and returns its
  /// entry, with the step it was left at.
  SavedRecipe open(Recipe recipe) {
    final had = savedAs(recipe);
    final entry =
        had ?? SavedRecipe(recipe: recipe, added: DateTime.now(), people: null);
    _book
      ..remove(entry)
      ..insert(0, entry);
    entry.cooked = DateTime.now();
    if (_book.length > keep) _book.removeRange(keep, _book.length);
    notifyListeners();
    unawaited(_save());
    return entry;
  }

  /// Where [entry] was left, and for how many.
  void leftAt(SavedRecipe entry, {required int step, int? people}) {
    entry
      ..step = step
      ..people = people;
    unawaited(_save());
  }

  void forget(SavedRecipe entry) {
    _book.remove(entry);
    notifyListeners();
    unawaited(_save());
  }

  /// The saved recipe [said] names best — "the chasseur", "pancakes" —
  /// or null when none has any of its words; with [all], every one of
  /// them: "fish and chips" is not the chips recipe.
  SavedRecipe? named(String said, {bool all = false}) {
    final want = Ingredient.keywordsOf(said)
      ..removeAll(const {'recipe', 'cook', 'make', 'let'});
    if (want.isEmpty) return null;
    SavedRecipe? best;
    var bestScore = 0.0;
    for (final s in _book) {
      final have = Ingredient.keywordsOf(s.recipe.name);
      final hits = want.where(have.contains).length;
      if (hits == 0 || (all && hits < want.length)) continue;
      // All of what was said, then as little else in the name as can be.
      final score = hits / want.length + hits / (have.length + 1) * 0.1;
      if (score > bestScore) {
        best = s;
        bestScore = score;
      }
    }
    return best;
  }

  final Map<String, Future<Recipe?>> _looking = {};

  /// The recipe on the page at [url] — the saved one, if it was cooked
  /// before — or null when the page has none. Asked once per address; a
  /// second ask while the first is out waits on the same answer.
  Future<Recipe?> recipeAt(String url) {
    final had = _looking[url];
    if (had != null) return had;
    if (_looking.length > 12) _looking.remove(_looking.keys.first);
    // The same future every time for the same page, so a card waiting on
    // it is not started over at each redraw.
    Recipe? saved;
    for (final s in _book) {
      if (s.recipe.url == url) saved = s.recipe;
    }
    return _looking[url] = saved != null
        ? Future.value(saved)
        : url.startsWith('http')
        ? _find(url)
        : Future.value(null);
  }

  Future<Recipe?> _find(String url) async {
    try {
      final html = await _fetch(url);
      return Recipe.fromHtml(html, url: url);
    } catch (e) {
      // Kept as none for now: a card redrawn must not fetch it again.
      debugPrint('Kitchen: no recipe from $url: $e');
      return null;
    }
  }

  /// A browser's user agent: recipe sites serve a cut-down page, or none,
  /// to anything else.
  static final Dio _dio = httpClient(
    responseType: ResponseType.bytes,
    connect: const Duration(seconds: 6),
    receive: const Duration(seconds: 10),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (X11; Linux aarch64; rv:128.0) Gecko/20100101 '
          'Firefox/128.0',
      'Accept': 'text/html,application/xhtml+xml',
      'Accept-Language': 'en-GB,en;q=0.8',
    },
  );

  static const int _maxPage = 6 * 1024 * 1024;

  static Future<String> _fetchPage(String url) async {
    final cancel = CancelToken();
    final r = await _dio.get<List<int>>(
      url,
      cancelToken: cancel,
      onReceiveProgress: (got, _) {
        if (got > _maxPage) cancel.cancel('page too large');
      },
    );
    final bytes = r.data;
    return bytes == null ? '' : utf8.decode(bytes, allowMalformed: true);
  }

  // The voice.

  bool _speaking = false;
  bool get speaking => _speaking;
  int _run = 0;

  /// Says [text], stopping anything it was saying first. A piece at a
  /// time, the next made while one is heard, so the first words come
  /// quickly even for a long step.
  Future<void> say(String text) async {
    final out = output;
    final run = ++_run;
    if (out == null) return;
    await out.stop();
    if (_muted() || run != _run) return;
    final pieces = speakableChunks([speakable(plainText(text))], max: 180);
    if (pieces.isEmpty) return;
    _setSpeaking(true);
    try {
      Future<File?>? next = out.synthesise(pieces.first);
      for (var i = 0; i < pieces.length; i++) {
        final file = await next;
        next = i + 1 < pieces.length ? out.synthesise(pieces[i + 1]) : null;
        if (run != _run) {
          _discard(file);
          unawaited(next?.then(_discard));
          return;
        }
        if (file == null) continue;
        await out.play(file, _volume());
        _discard(file);
      }
    } catch (e) {
      debugPrint('Kitchen: could not say it: $e');
    } finally {
      if (run == _run) _setSpeaking(false);
    }
  }

  /// Stops the voice part-way.
  Future<void> quiet() async {
    _run++;
    _setSpeaking(false);
    await output?.stop();
  }

  void _setSpeaking(bool v) {
    if (_speaking == v) return;
    _speaking = v;
    notifyListeners();
  }

  static void _discard(File? f) {
    if (f == null) return;
    f.delete().catchError((_) => f);
  }
}
