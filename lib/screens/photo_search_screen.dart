import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../look.dart';
import '../models/immich_models.dart';
import '../services/config_service.dart';
import '../services/immich_service.dart';
import '../services/photo_query.dart';
import '../widgets/glass.dart';
import '../widgets/lcars.dart';
import '../widgets/pause_when_hidden.dart';
import '../widgets/remote_image.dart';
import 'gallery_screen.dart';
import 'slideshow_screen.dart';

/// Photos found by asking: "Ellie at the beach", "snow in 2019", "the
/// nineties". Who, where and when narrow the search; what is in them is
/// found by Immich's own image model, which looks at every photo — no album,
/// no tag, nothing named beforehand.
///
/// Opened from the albums' Find photos, by voice ("show me photos of the
/// beach"), or from a photo's More like this — and every photo found has
/// its own More like this, so one leads to the next.
class PhotoSearchScreen extends StatefulWidget {
  const PhotoSearchScreen({
    super.key,
    this.asked,
    this.query,
    this.slideshow = false,
  });

  /// As typed or said, to be read once the people and places are known.
  final String? asked;

  /// Already worked out: someone's photos, or photos like one.
  final PhotoQuery? query;

  /// Straight into a slideshow of what is found: "a slideshow of Ellie".
  final bool slideshow;

  @override
  State<PhotoSearchScreen> createState() => _PhotoSearchScreenState();
}

class _PhotoSearchScreenState extends State<PhotoSearchScreen> {
  late final ImmichService _immich = context.read<ImmichService>();
  late final TextEditingController _field = TextEditingController(
    text: widget.asked ?? widget.query?.asked ?? '',
  );
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();

  List<Person> _people = const [];
  List<PhotoPlace> _places = const [];

  PhotoQuery? _query;
  List<Asset>? _found;
  int? _next;
  bool _searching = false;
  bool _more = false;
  String? _error;

  /// Which search is current, so an older one that answers late is dropped.
  int _search = 0;

  late bool _slideshowWanted = widget.slideshow;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_nearEnd);
    unawaited(_start());
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final given = widget.query;
    if (given != null) {
      unawaited(_run(given));
    } else if ((widget.asked ?? '').trim().isNotEmpty) {
      // Asked out loud, so start at once: who and where are waited for
      // only because they change what is looked for.
      setState(() => _searching = true);
    }
    final known = await _immich.searchable();
    if (!mounted) return;
    setState(() {
      _people = known.people;
      _places = known.places;
    });
    if (given == null && (widget.asked ?? '').trim().isNotEmpty) {
      _ask(widget.asked!);
    }
  }

  /// Search for what is in the field.
  void _ask(String asked) {
    final q = PhotoQuery.parse(asked, people: _people, places: _places);
    if (q == null) {
      setState(() {
        _searching = false;
        _query = null;
        _found = null;
      });
      return;
    }
    unawaited(_run(q));
  }

  Future<void> _run(PhotoQuery q) async {
    final mine = ++_search;
    _focus.unfocus();
    // What is being looked for, as it was asked: a voice's "of the beach"
    // is "beach" there.
    if (_field.text != q.asked) _field.text = q.asked;
    setState(() {
      _query = q;
      _found = null;
      _next = null;
      _error = null;
      _searching = true;
    });
    try {
      final page = await _immich.findPhotos(q);
      if (!mounted || mine != _search) return;
      setState(() {
        _found = page.assets;
        _next = page.next;
        _searching = false;
      });
      // Asked for as a slideshow: the first search's photos, at once.
      if (_slideshowWanted) {
        _slideshowWanted = false;
        unawaited(_slideshow());
      }
    } catch (e) {
      if (!mounted || mine != _search) return;
      setState(() {
        _error = '$e';
        _searching = false;
      });
    }
  }

  /// The next page, as the wall nears its end.
  void _nearEnd() {
    if (_more || _next == null || _query == null) return;
    if (_scroll.position.extentAfter > 1200) return;
    unawaited(_loadMore());
  }

  Future<void> _loadMore() async {
    final q = _query, next = _next, mine = _search;
    if (q == null || next == null) return;
    _more = true;
    try {
      final page = await _immich.findPhotos(q, page: next);
      if (!mounted || mine != _search) return;
      setState(() {
        _found = [...?_found, ...page.assets];
        _next = page.next;
      });
    } catch (_) {
      // Tried again on the next scroll.
    } finally {
      _more = false;
    }
  }

  void _open(int index) {
    final found = List.of(_found!);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GalleryScreen(
          assets: found,
          initialIndex: index,
          source: _immich,
          onMoreLike: (a) => openMoreLike(context, a),
        ),
      ),
    );
  }

  Future<void> _slideshow() async {
    final q = _query;
    if (q == null || _found == null) return;
    // Someone's photos, or a year's, are all as good as each other: up to a
    // few hundred of them. By looks, only the closest are worth showing.
    while (!q.byLooks && _next != null && _found!.length < 360) {
      final mine = _search;
      await _loadMore();
      if (!mounted || mine != _search) return;
    }
    final images = _found!.where((a) => a.isImage).toList();
    if (images.isEmpty || !mounted) return;
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SlideshowScreen(
            images: images,
            source: _immich,
            settings: context.read<ConfigService>().slideshow,
            title: q.label,
          ),
        ),
      ),
    );
  }

  void _clear() {
    _search++;
    _field.clear();
    setState(() {
      _query = null;
      _found = null;
      _searching = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _query;
    final found = _found;
    final images = found?.where((a) => a.isImage).length ?? 0;
    return ModernScaffold(
      header: ScreenHeader(
        onBack: () => Navigator.of(context).maybePop(),
        title: q == null || q.label.isEmpty
            ? tr('find.title', 'Find photos')
            : q.label,
        subtitle: _subtitle(q, found),
        trailing: images > 0
            ? FilledButton.icon(
                onPressed: _slideshow,
                icon: const Icon(Icons.play_arrow_rounded, size: 30),
                label: Text(tr('album.slideshow', 'Slideshow')),
                style: whitePillButton(context),
              )
            : null,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 4, 40, 18),
            child: _SearchBar(
              controller: _field,
              focus: _focus,
              onSubmit: (s) => s.trim().isEmpty ? _clear() : _ask(s),
              onClear: _clear,
              someone: _people.firstOrNull?.name.split(' ').first,
            ),
          ),
          Expanded(child: _body(q, found)),
        ],
      ),
    );
  }

  String _subtitle(PhotoQuery? q, List<Asset>? found) {
    if (q == null) {
      return tr(
        'find.subtitle',
        'Who, where, when, or what is in them — your photos, looked through',
      );
    }
    if (found == null) return tr('find.looking', 'Looking…');
    final n = found.length;
    final count = _next != null ? '$n+' : '$n';
    return q.byLooks
        ? tr('find.closestFirst', '{count} found, closest first', {
            'count': count,
          })
        : tr('find.newestFirst', '{count} found, newest first', {
            'count': count,
          });
  }

  Widget _body(PhotoQuery? q, List<Asset>? found) {
    if (_searching) return _Working(label: q?.label ?? _field.text);
    if (_error != null) {
      return _Message(
        icon: Icons.cloud_off_rounded,
        text: tr('home.couldNotReachImmich', 'Could not reach Immich'),
        detail: _error,
      );
    }
    if (q == null || found == null) {
      return _Suggestions(
        people: _people,
        places: _places,
        onAsk: (s) {
          _field.text = s;
          _ask(s);
        },
        onPerson: (p) {
          _field.text = p.name;
          unawaited(_run(PhotoQuery.of(p)));
        },
        onPlace: (p) {
          _field.text = p.name;
          unawaited(_run(PhotoQuery(asked: p.name, place: p)));
        },
      );
    }
    if (found.isEmpty) {
      return _Message(
        icon: Icons.image_search_rounded,
        text: tr('find.nothing', 'No photos like that'),
        detail: q.when != null || q.place != null || q.people.isNotEmpty
            ? tr(
                'find.nothingTry',
                'Try asking for less: a person, a place or a year on its own',
              )
            : null,
      );
    }
    final round = context.look.isLcars ? 0.0 : 10.0;
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 48),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: found.length,
      itemBuilder: (context, i) => _Found(
        asset: found[i],
        immich: _immich,
        radius: round,
        onTap: () => _open(i),
      ),
    );
  }
}

/// Photos that look like [asset], one more step through the library.
void openMoreLike(BuildContext context, Asset asset) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PhotoSearchScreen(query: PhotoQuery.like(asset.id)),
    ),
  );
}

/// The field: what to look for, typed on the panel's own keyboard.
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focus,
    required this.onSubmit,
    required this.onClear,
    this.someone,
  });

  /// A first name for the example.
  final String? someone;
  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onSubmit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    // With the name of someone in the photos, when there is one: the
    // most photographed.
    final hint = someone == null
        ? tr('find.hint', 'Dogs in the snow, the beach in 2019, sunsets…')
        : tr('find.hintWho', '{name} at the beach, snow in 2019, sunsets…', {
            'name': someone,
          });
    if (look.isLcars) {
      // A console's query line: a capped block to say what it is, the
      // words in the accent on black, and a block to send it.
      return Row(
        children: [
          LcarsBlock(
            colour: look.block(2),
            ends: LcarsEnds.start,
            onTap: focus.requestFocus,
            height: 64,
            width: 180,
            padding: const EdgeInsets.only(left: 30),
            alignment: Alignment.centerLeft,
            child: Text(
              lcarsCaps(tr('find.library', 'Library')),
              style: const TextStyle(fontSize: 22),
            ),
          ),
          const SizedBox(width: lcarsLine * 2),
          Expanded(
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: look.block(2), width: lcarsLine * 2),
                  bottom: BorderSide(
                    color: look.block(2),
                    width: lcarsLine * 2,
                  ),
                ),
              ),
              alignment: Alignment.centerLeft,
              child: _field(
                look.accent,
                look.accent.withValues(alpha: 0.45),
                lcarsCaps(hint),
                caps: true,
              ),
            ),
          ),
          const SizedBox(width: lcarsLine * 2),
          LcarsBlock(
            colour: look.block(5),
            ends: LcarsEnds.none,
            height: 64,
            width: 96,
            onTap: onClear,
            child: Text(
              lcarsCaps(tr('find.clear', 'Clear')),
              style: const TextStyle(fontSize: 20),
            ),
          ),
          const SizedBox(width: lcarsLine * 2),
          LcarsBlock(
            colour: look.block(0),
            ends: LcarsEnds.end,
            height: 64,
            width: 150,
            onTap: () => onSubmit(controller.text),
            child: Text(
              lcarsCaps(tr('find.search', 'Search')),
              style: const TextStyle(fontSize: 22),
            ),
          ),
        ],
      );
    }
    return Glass(
      radius: 999,
      tint: 0.1,
      padding: const EdgeInsets.fromLTRB(26, 4, 8, 4),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 32, color: look.textSecondary),
          const SizedBox(width: 16),
          Expanded(child: _field(look.textPrimary, look.textSecondary, hint)),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => controller.text.isEmpty
                ? const SizedBox(height: 60)
                : IconButton(
                    iconSize: 30,
                    padding: const EdgeInsets.all(14),
                    tooltip: tr('find.clear', 'Clear'),
                    color: look.textSecondary,
                    onPressed: onClear,
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _field(Color ink, Color hintInk, String hint, {bool caps = false}) =>
      TextField(
        controller: controller,
        focusNode: focus,
        textInputAction: TextInputAction.search,
        onSubmitted: onSubmit,
        textCapitalization: TextCapitalization.none,
        style: TextStyle(
          fontSize: 26,
          color: ink,
          letterSpacing: caps ? 1.5 : 0,
          fontWeight: caps ? FontWeight.w700 : FontWeight.w500,
        ),
        cursorColor: ink,
        decoration: InputDecoration(
          isCollapsed: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          hintText: hint,
          hintStyle: TextStyle(
            fontSize: 24,
            color: hintInk,
            letterSpacing: caps ? 1.5 : 0,
          ),
        ),
      );
}

/// Before anything is asked: what might be, and who and where there is.
class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.people,
    required this.places,
    required this.onAsk,
    required this.onPerson,
    required this.onPlace,
  });

  final List<Person> people;
  final List<PhotoPlace> places;
  final ValueChanged<String> onAsk;
  final ValueChanged<Person> onPerson;
  final ValueChanged<PhotoPlace> onPlace;

  /// Things the image model finds well in most families' photos.
  static List<String> get ideas => [
    tr('find.idea.beach', 'The beach'),
    tr('find.idea.snow', 'Snow'),
    tr('find.idea.sunsets', 'Sunsets'),
    tr('find.idea.birthdays', 'Birthday cakes'),
    tr('find.idea.christmas', 'Christmas trees'),
    tr('find.idea.dogs', 'Dogs'),
    tr('find.idea.cats', 'Cats'),
    tr('find.idea.mountains', 'Mountains'),
    tr('find.idea.flowers', 'Flowers'),
    tr('find.idea.food', 'Food'),
    tr('find.idea.babies', 'Babies'),
    tr('find.idea.fireworks', 'Fireworks'),
  ];

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    // The most photographed first, as Immich lists them.
    final faces = people.take(24).toList();
    final names = faceNames(faces);
    return ListView(
      padding: const EdgeInsets.fromLTRB(40, 6, 40, 48),
      children: [
        _Heading(tr('find.tryHeading', 'Try')),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final idea in ideas)
              ChoicePill(
                label: idea,
                selected: false,
                onTap: () => onAsk(idea),
              ),
          ],
        ),
        if (faces.isNotEmpty) ...[
          _Heading(tr('find.people', 'People')),
          Wrap(
            spacing: look.isLcars ? 12 : 22,
            runSpacing: look.isLcars ? 12 : 18,
            children: [
              for (final (i, p) in faces.indexed)
                _Face(
                  person: p,
                  name: names[i],
                  seed: i,
                  onTap: () => onPerson(p),
                ),
            ],
          ),
        ],
        if (places.isNotEmpty) ...[
          _Heading(tr('find.places', 'Places')),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final p in places.take(40))
                ChoicePill(
                  label: p.name,
                  selected: false,
                  onTap: () => onPlace(p),
                ),
            ],
          ),
        ],
        const SizedBox(height: 34),
        Text(
          tr(
            'find.sayIt',
            'Or ask out loud: “show me photos of the beach in 2019”',
          ),
          style: TextStyle(fontSize: 20, color: look.textSecondary),
        ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    return Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 14),
      child: look.isLcars
          ? Text(
              lcarsCaps(text),
              style: TextStyle(
                fontSize: 24,
                color: look.accent,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            )
          : Text(
              text,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
    );
  }
}

/// What to call each of [people] under their face: without the surname
/// most of them share — a family's photos are mostly the family — and in
/// full where that would make two the same: "Nan" and "Nan Willcox".
List<String> faceNames(List<Person> people) {
  final counts = <String, int>{};
  for (final p in people) {
    final words = p.name.split(' ');
    if (words.length > 1) counts[words.last] = (counts[words.last] ?? 0) + 1;
  }
  final shared = counts.entries
      .where((e) => e.value >= 3)
      .fold<MapEntry<String, int>?>(
        null,
        (best, e) => best == null || e.value > best.value ? e : best,
      )
      ?.key;
  final short = [
    for (final p in people)
      shared != null && p.name.endsWith(' $shared')
          ? p.name.substring(0, p.name.length - shared.length - 1)
          : p.name,
  ];
  return [
    for (final (i, s) in short.indexed)
      short.where((o) => o == s).length > 1 ? people[i].name : s,
  ];
}

/// Someone Immich knows, by the face it found for them.
class _Face extends StatelessWidget {
  const _Face({
    required this.person,
    required this.name,
    required this.seed,
    required this.onTap,
  });

  final Person person;

  /// What to call them here: see [faceNames].
  final String name;
  final int seed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final immich = context.read<ImmichService>();
    final face = RemoteImage(
      url: immich.personThumbUrl(person.id),
      headers: immich.authHeaders,
    );
    if (look.isLcars) {
      // A block with the face in a black square at its start.
      return LcarsBlock(
        colour: look.block(seed),
        onTap: onTap,
        height: 64,
        padding: const EdgeInsets.only(left: 30, right: 26),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 52, height: 52, child: face),
            const SizedBox(width: 14),
            Text(lcarsCaps(name), style: const TextStyle(fontSize: 20)),
          ],
        ),
      );
    }
    return PressScale(
      scale: 0.94,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 112,
          child: Column(
            children: [
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: look.wash(0.16), width: 2),
                ),
                child: ClipOval(child: face),
              ),
              const SizedBox(height: 8),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: look.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One photo found.
class _Found extends StatelessWidget {
  const _Found({
    required this.asset,
    required this.immich,
    required this.radius,
    required this.onTap,
  });

  final Asset asset;
  final ImmichService immich;
  final double radius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      scale: 0.95,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              RemoteImage(
                url: immich.thumbUrl(asset.id),
                fallbackUrl: asset.isImage
                    ? immich.originalUrl(asset.id)
                    : null,
                headers: immich.authHeaders,
              ),
              if (asset.isVideo)
                const Positioned(
                  right: 8,
                  bottom: 8,
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    color: Colors.white,
                    size: 34,
                    shadows: [Shadow(blurRadius: 8)],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.detail});

  final IconData icon;
  final String text;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: look.wash(0.38)),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: TextStyle(color: look.textSecondary, fontSize: 18),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// While the library is looked through. On a console the computer is
/// "working": a row of blocks lit one after another, in steps, and the
/// request lettered over them; elsewhere, a quiet spinner.
class _Working extends StatefulWidget {
  const _Working({required this.label});

  final String label;

  @override
  State<_Working> createState() => _WorkingState();
}

class _WorkingState extends State<_Working> with PauseWhenHidden<_Working> {
  static const _blocks = 12;
  Timer? _timer;
  int _lit = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 110), (_) {
      if (shown && mounted) setState(() => _lit = (_lit + 1) % _blocks);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    if (!look.isLcars) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 22),
            Text(
              tr('find.lookingThrough', 'Looking through your photos…'),
              style: TextStyle(fontSize: 22, color: look.textSecondary),
            ),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            lcarsCaps(tr('find.working', 'Working')),
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w700,
              letterSpacing: 6,
              color: look.accent,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _blocks; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: lcarsLine),
                  child: SizedBox(
                    width: 46,
                    height: 26,
                    child: ColoredBox(
                      color: i == _lit
                          ? lcarsLit
                          : look
                                .block(i)
                                .withValues(alpha: i < _lit ? 0.9 : 0.35),
                    ),
                  ),
                ),
            ],
          ),
          if (widget.label.trim().isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              lcarsCaps(widget.label),
              style: TextStyle(
                fontSize: 22,
                letterSpacing: 2,
                color: look.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
