import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../dashboard/dashboard_theme.dart';
import '../l10n/l10n.dart';
import '../look.dart';
import '../widgets/lcars.dart';
import 'deck_link.dart';
import 'deck_model.dart';

/// The deck: StreamerDeck's keys, the whole screen, until it is closed.
///
/// Keys are drawn as the Stream Deck draws them — black, rounded, the image
/// edge to edge and the title over it — inside a frame in the panel's own
/// theme. A key acts on a tap; a swipe across turns the page. Left alone a
/// few minutes the screen dims, and the touch that wakes it does nothing
/// else. Closed, it runs nothing at all.
class DeckScreen extends StatefulWidget {
  const DeckScreen({super.key});

  static Route<void> route() => PageRouteBuilder<void>(
    pageBuilder: (_, _, _) => const DeckScreen(),
    transitionDuration: const Duration(milliseconds: 180),
    reverseTransitionDuration: const Duration(milliseconds: 140),
    transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
  );

  /// Left untouched this long, the screen dims.
  static const dimAfter = Duration(minutes: 3);

  @override
  State<DeckScreen> createState() => _DeckScreenState();
}

/// Where the keys go in the space there is.
class DeckGeometry {
  DeckGeometry(Size area, this.cols, this.rows) {
    const g = 0.14;
    key = max(8, min(area.width / (cols + (cols - 1) * g), area.height / (rows + (rows - 1) * g)));
    gap = key * g;
    final w = cols * key + (cols - 1) * gap, h = rows * key + (rows - 1) * gap;
    origin = Offset((area.width - w) / 2, (area.height - h) / 2);
  }

  final int cols, rows;
  late final double key, gap;
  late final Offset origin;

  Offset at(int c, int r) => origin + Offset(c * (key + gap), r * (key + gap));

  /// The key under [p], or null between keys and outside.
  (int, int)? hit(Offset p) {
    final q = p - origin;
    final c = (q.dx / (key + gap)).floor(), r = (q.dy / (key + gap)).floor();
    if (c < 0 || r < 0 || c >= cols || r >= rows) return null;
    final inX = q.dx - c * (key + gap), inY = q.dy - r * (key + gap);
    return inX <= key && inY <= key ? (c, r) : null;
  }
}

class _DeckScreenState extends State<DeckScreen> {
  late final DeckLink _link = context.read<DeckLink>();
  Timer? _dimTimer;
  bool _dim = false;

  // The finger on the keys.
  int? _pointer;
  Offset? _downAt;
  (int, int)? _pressed;
  bool _moved = false;
  bool _waking = false;

  @override
  void initState() {
    super.initState();
    _link.open();
    _armDim();
  }

  @override
  void dispose() {
    _dimTimer?.cancel();
    _link.close();
    super.dispose();
  }

  void _armDim() {
    _dimTimer?.cancel();
    _dimTimer = Timer(DeckScreen.dimAfter, () {
      if (mounted) setState(() => _dim = true);
    });
  }

  // --- Touch ----------------------------------------------------------------

  void _down(PointerDownEvent e, DeckGeometry g) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _armDim();
    if (_dim) {
      // This touch only wakes it.
      _waking = true;
      setState(() => _dim = false);
      return;
    }
    _downAt = e.localPosition;
    _moved = false;
    setState(() => _pressed = g.hit(e.localPosition));
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer || _waking || _downAt == null) return;
    if (!_moved && (e.localPosition - _downAt!).distance > 22) {
      setState(() {
        _moved = true;
        _pressed = null;
      });
    }
  }

  void _up(PointerUpEvent e, DeckGeometry g) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    if (_waking) {
      _waking = false;
      return;
    }
    final from = _downAt;
    final pressed = _pressed;
    setState(() => _pressed = null);
    if (from == null) return;
    final d = e.localPosition - from;
    if (_moved) {
      if (d.dx.abs() > 60 && d.dx.abs() > d.dy.abs() * 1.4) {
        d.dx < 0 ? _link.nextPage() : _link.previousPage();
      }
      return;
    }
    if (pressed == null || g.hit(e.localPosition) != pressed) return;
    _act(pressed.$1, pressed.$2);
  }

  void _cancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _waking = false;
    setState(() => _pressed = null);
  }

  void _act(int c, int r) {
    if (_link.inFolder && c == 0 && r == 0) return _link.back();
    final key = _link.page?.at(c, r);
    if (key != null) _link.press(key);
  }

  // --- Drawing ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final link = context.watch<DeckLink>();
    final look = context.look;
    final profile = link.profile;
    final body = profile == null
        ? _NotSetUp(look: look)
        : look.isLcars
        ? _lcars(context, link, profile, look)
        : _plain(context, link, profile, look);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          body,
          IgnorePointer(
            ignoring: !_dim,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) {
                _armDim();
                setState(() => _dim = false);
              },
              child: AnimatedOpacity(
                opacity: _dim ? 0.72 : 0,
                duration: const Duration(milliseconds: 600),
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(DeckLink link, DeckProfile profile, DashboardTheme look) {
    final page = link.page;
    final folder = link.inFolder;
    final pages = link.pages.length;
    return LayoutBuilder(
      builder: (context, box) {
        final g = DeckGeometry(box.biggest, profile.cols, profile.rows);
        final children = <Widget>[];
        for (var r = 0; r < profile.rows; r++) {
          for (var c = 0; c < profile.cols; c++) {
            final at = g.at(c, r);
            final pressed = _pressed == (c, r);
            Widget key;
            if (folder && c == 0 && r == 0) {
              key = _BackKey(size: g.key, pressed: pressed);
            } else {
              final k = page?.at(c, r);
              key = k == null
                  ? _EmptyKey(size: g.key)
                  : DeckKeyView(
                      deckKey: k,
                      link: link,
                      size: g.key,
                      pressed: pressed,
                      pageLabel: '${link.pageIndex + 1}/$pages',
                    );
            }
            children.add(Positioned(left: at.dx, top: at.dy, width: g.key, height: g.key, child: key));
          }
        }
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _down(e, g),
          onPointerMove: _move,
          onPointerUp: (e) => _up(e, g),
          onPointerCancel: _cancel,
          child: Stack(children: children),
        );
      },
    );
  }

  String _where(DeckLink link, DeckProfile profile) {
    final f = link.folders;
    final names = [
      profile.name,
      for (final k in f) k.look(0).title.isNotEmpty ? k.look(0).title.replaceAll('\n', ' ') : tr('deck.folder', 'Folder'),
    ];
    return names.join('  ›  ');
  }

  String _pcLine(DeckLink link) => link.connected
      ? (link.pcName ?? tr('deck.computer', 'Computer'))
      : tr('deck.computerOff', 'Computer offline');

  // A console: the keys in a panel of bars, blocks along the foot.
  Widget _lcars(BuildContext context, DeckLink link, DeckProfile profile, DashboardTheme look) {
    final pages = link.pages.length;
    final font = TextStyle(fontFamily: look.fontFamily, fontSize: 22, letterSpacing: 1.5);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Column(
          children: [
            Expanded(
              child: LcarsPanel(
                theme: look,
                heavy: true,
                label: _where(link, profile).toUpperCase(),
                child: Padding(padding: const EdgeInsets.all(14), child: _grid(link, profile, look)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  if (link.inFolder) ...[
                    LcarsBlock(
                      colour: look.block(5),
                      width: 150,
                      ends: LcarsEnds.start,
                      onTap: link.back,
                      child: Text('BACK', style: font),
                    ),
                    const SizedBox(width: 6),
                  ],
                  for (var i = 0; i < pages; i++) ...[
                    LcarsBlock(
                      colour: i == link.pageIndex ? lcarsLit : look.block(i + 1),
                      width: 84,
                      ends: !link.inFolder && i == 0 ? LcarsEnds.start : LcarsEnds.none,
                      onTap: () => link.showPage(i),
                      child: Text((i + 1).toString().padLeft(2, '0'), style: font),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: LcarsBlock(
                      colour: look.block(3),
                      ends: pages == 0 && !link.inFolder ? LcarsEnds.start : LcarsEnds.none,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 18),
                      onTap: () => _chooseProfile(context, link),
                      child: Text(_pcLine(link).toUpperCase(), style: font, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 6),
                  LcarsBlock(
                    colour: look.block(0),
                    width: 170,
                    ends: LcarsEnds.end,
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Text('CLOSE', style: font),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Any other theme: the keys on black, a quiet strip above and the pages below.
  Widget _plain(BuildContext context, DeckLink link, DeckProfile profile, DashboardTheme look) {
    final pages = link.pages.length;
    final text = look.textPrimary;
    return Container(
      decoration: look.backgroundDecoration,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
          child: Column(
            children: [
              SizedBox(
                height: 52,
                child: Row(
                  children: [
                    if (link.inFolder)
                      IconButton(
                        iconSize: 30,
                        color: text,
                        tooltip: tr('deck.back', 'Back'),
                        onPressed: link.back,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _chooseProfile(context, link),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  _where(link, profile),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: text, fontSize: 22, fontWeight: FontWeight.w600, fontFamily: look.fontFamily),
                                ),
                              ),
                              if (link.snapshot!.profiles.length > 1) Icon(Icons.expand_more, color: text.withValues(alpha: 0.6)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    _PcChip(link: link, look: look),
                    const SizedBox(width: 10),
                    IconButton(
                      iconSize: 32,
                      color: text,
                      tooltip: tr('deck.close', 'Close'),
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: look.border.withValues(alpha: 0.5)),
                  ),
                  child: Padding(padding: const EdgeInsets.all(22), child: _grid(link, profile, look)),
                ),
              ),
              SizedBox(
                height: 44,
                child: pages < 2
                    ? null
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < pages; i++)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => link.showPage(i),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  width: i == link.pageIndex ? 30 : 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: i == link.pageIndex ? look.accent : text.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseProfile(BuildContext context, DeckLink link) async {
    final profiles = link.snapshot?.profiles ?? const <DeckProfile>[];
    if (profiles.length < 2) return;
    final look = context.look;
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: look.solidSurface,
        title: Text(tr('deck.profiles', 'Profiles'), style: TextStyle(color: look.textPrimary)),
        children: [
          for (final p in profiles)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, p.id),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Text(
                p.name,
                style: TextStyle(
                  color: p.id == link.profile?.id ? look.accent : look.textPrimary,
                  fontSize: 22,
                  fontWeight: p.id == link.profile?.id ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
    if (chosen != null) link.showProfile(chosen);
  }
}

class _PcChip extends StatelessWidget {
  const _PcChip({required this.link, required this.look});

  final DeckLink link;
  final DashboardTheme look;

  @override
  Widget build(BuildContext context) {
    final on = link.connected;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: look.textPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: on ? const Color(0xFF22C55E) : const Color(0xFF6B7280)),
          ),
          const SizedBox(width: 8),
          Text(
            on ? (link.pcName ?? tr('deck.computer', 'Computer')) : tr('deck.computerOff', 'Computer offline'),
            style: TextStyle(color: look.textPrimary, fontSize: 17),
          ),
        ],
      ),
    );
  }
}

/// The fonts a key's title can ask for, as the panel has them.
const Map<String, String?> deckFonts = {
  '': null,
  'Sans': 'Inter',
  'Serif': 'Lora',
  'Monospace': 'JetBrainsMono',
  'Condensed': 'Antonio',
  'Rounded': 'Nunito',
};

/// One key, as the Stream Deck draws one.
class DeckKeyView extends StatelessWidget {
  const DeckKeyView({
    super.key,
    required this.deckKey,
    required this.link,
    required this.size,
    this.pressed = false,
    this.pageLabel = '',
  });

  final DeckKey deckKey;
  final DeckLink link;
  final double size;
  final bool pressed;
  final String pageLabel;

  @override
  Widget build(BuildContext context) {
    final state = link.stateOf(deckKey);
    final look = deckKey.look(state);
    final file = link.imageFile(look.image);
    final fx = link.fxOf(deckKey);
    final offline = deckKey.runs == DeckRuns.pc && !link.connected;
    final radius = BorderRadius.circular(size * 0.16);
    var title = look.title;
    var align = look.align;
    var fontSize = look.size;
    var bold = look.bold;
    if (deckKey.action == 'deck.page.indicator' && title.isEmpty) {
      title = pageLabel;
      align = 'middle';
      fontSize = 18;
      bold = true;
    }
    final scale = size / 72;
    final titleStyle = TextStyle(
      color: look.titleColor,
      fontSize: fontSize * scale,
      height: 1.1,
      fontFamily: deckFonts[look.family] ?? (deckFonts.containsKey(look.family) ? null : look.family),
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      fontStyle: look.italic ? FontStyle.italic : FontStyle.normal,
      decoration: look.underline ? TextDecoration.underline : null,
      decorationColor: look.titleColor,
      shadows: const [
        Shadow(blurRadius: 2),
        Shadow(blurRadius: 4),
        Shadow(offset: Offset(0, 1), blurRadius: 2),
      ],
    );
    return AnimatedScale(
      scale: pressed ? 0.93 : 1,
      duration: const Duration(milliseconds: 70),
      child: Opacity(
        opacity: offline ? 0.42 : 1,
        child: ClipRRect(
          borderRadius: radius,
          child: Container(
            // Black like the hardware's keys, a shade lighter while the
            // image is still on its way; a faint edge, so a black key keeps
            // its shape on a black console.
            color: look.color ?? (look.image != null && file == null ? const Color(0xFF161A22) : Colors.black),
            foregroundDecoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: const Color(0x1AFFFFFF)),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (file != null)
                  Image.file(
                    file,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, _, _) => const SizedBox(),
                  ),
                if (look.showTitle && title.isNotEmpty)
                  Positioned(
                    left: size * 0.04,
                    right: size * 0.04,
                    top: align == 'top' ? size * 0.05 : (align == 'middle' ? 0 : null),
                    bottom: align == 'bottom' ? size * 0.06 : (align == 'middle' ? 0 : null),
                    child: Align(
                      alignment: Alignment.center,
                      child: Text(title, textAlign: TextAlign.center, style: titleStyle, maxLines: 4, overflow: TextOverflow.clip),
                    ),
                  ),
                if (pressed) const ColoredBox(color: Color(0x22FFFFFF)),
                if (fx != null) _Fx(fx: fx, size: size),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A key's flash: the Stream Deck's tick and warning sign.
class _Fx extends StatelessWidget {
  const _Fx({required this.fx, required this.size});

  final DeckFx fx;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (fx == DeckFx.busy) {
      return Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: EdgeInsets.all(size * 0.08),
          child: SizedBox(
            width: size * 0.18,
            height: size * 0.18,
            child: const CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
          ),
        ),
      );
    }
    final ok = fx == DeckFx.ok;
    return ColoredBox(
      color: const Color(0x99000000),
      child: Center(
        child: Icon(
          ok ? Icons.check_circle_rounded : Icons.warning_rounded,
          size: size * 0.5,
          color: ok ? const Color(0xFF4ADE80) : const Color(0xFFFBBF24),
        ),
      ),
    );
  }
}

class _EmptyKey extends StatelessWidget {
  const _EmptyKey({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF0C0E13),
      borderRadius: BorderRadius.circular(size * 0.16),
      border: Border.all(color: const Color(0xFF1A1E27)),
    ),
  );
}

class _BackKey extends StatelessWidget {
  const _BackKey({required this.size, required this.pressed});

  final double size;
  final bool pressed;

  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: pressed ? 0.93 : 1,
    duration: const Duration(milliseconds: 70),
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.16),
        gradient: const RadialGradient(
          center: Alignment(0, -0.4),
          radius: 0.9,
          colors: [Color(0xFF263042), Color(0xFF0B0D12)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.arrow_back_rounded, color: Colors.white, size: size * 0.42),
          Text(
            tr('deck.back', 'Back'),
            style: TextStyle(color: Colors.white, fontSize: 12 * size / 72, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    ),
  );
}

/// Before any computer has sent a deck: how to get one.
class _NotSetUp extends StatelessWidget {
  const _NotSetUp({required this.look});

  final DashboardTheme look;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Stack(
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.grid_view_rounded, size: 96, color: look.accent),
                const SizedBox(height: 24),
                Text(
                  tr('deck.notSetUpTitle', 'No deck yet'),
                  style: TextStyle(color: look.textPrimary, fontSize: 34, fontWeight: FontWeight.w700, fontFamily: look.fontFamily),
                ),
                const SizedBox(height: 14),
                Text(
                  tr(
                    'deck.notSetUpBody',
                    'Install StreamerDeck on your computer. It connects here with a Share Inbox sender’s token, and its keys appear on this screen.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: look.textSecondary, fontSize: 21, height: 1.4),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 12,
          right: 16,
          child: IconButton(
            iconSize: 34,
            color: look.textPrimary,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ),
      ],
    ),
  );
}
