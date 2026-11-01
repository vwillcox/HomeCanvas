import 'dart:async';

import 'package:flutter/material.dart';

import '../look.dart';
import '../services/lyrics.dart';
import '../services/now_playing_service.dart';
import '../services/playback_source.dart';
import '../time_format.dart';
import 'lcars.dart';
import 'pause_when_hidden.dart';

/// A song's words beside the full player, the line being sung lit and
/// carried to a fixed height on the screen, so the words can be read from
/// across the room and sung along to.
///
/// Timed words follow the music to the tenth of a second: the source reports
/// where the song is about once a second, and between reports the view keeps
/// its own count from the last one. A break — the intro, a solo — is a row
/// that fills as it passes, so the next line never takes anyone by surprise.
/// With a source that can seek, a line is a button: touch it and the song
/// goes there. Untimed words scroll with the song, as far down as the song
/// has got.
///
/// Drag the words to read ahead; a few seconds after letting go they come
/// back to the line being sung.
///
/// On a console the line steps up a row at a time, the time of each line on
/// a block down the side — lit for the line being sung, unlit once sung, a
/// colour to a verse — and a break counts across in segments. Everywhere
/// else the words glide, the lines around the one being sung dimmed.
class LyricsView extends StatefulWidget {
  const LyricsView({super.key, required this.lyrics, required this.service});

  final Lyrics lyrics;
  final PlaybackSource service;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView>
    with PauseWhenHidden<LyricsView> {
  /// How early a line lights before its time: enough to have read it as it
  /// is sung, not so much that it is lit through the end of the last.
  static const _lead = Duration(milliseconds: 250);

  /// How long the words stay where they were dragged to.
  static const _readAhead = Duration(seconds: 4);

  /// Where on the view the line being sung sits, from the top.
  static const _eyeLine = 0.36;

  final _scroll = ScrollController();
  late List<GlobalKey> _keys;

  /// Which verse each line is in, counted at the breaks between them.
  late List<int> _verses;

  void _measure() {
    _keys = [for (final _ in _lyrics.lines) GlobalKey()];
    var verse = 0;
    _verses = [for (final l in _lyrics.lines) l.isBreak ? ++verse : verse];
  }

  // The song's position: the last reported, and the time since it was.
  Duration _base = Duration.zero;
  Duration _reported = const Duration(days: 1);
  final _since = Stopwatch();
  bool _playing = false;

  int _index = -1;

  /// How far through the break being shown, 0 to 1.
  double _breakDone = 0;

  Timer? _tick;
  Timer? _comeBack;
  DateTime? _draggedAt;
  bool _dragging = false;
  double _dragFrom = 0;

  Lyrics get _lyrics => widget.lyrics;

  @override
  void initState() {
    super.initState();
    _measure();
    _report(widget.service.now);
    _index = _lineNow();
    _breakDone = _breakProgress(_index);
    _follow(jump: true);
    _startTicking();
  }

  @override
  void didUpdateWidget(LyricsView old) {
    super.didUpdateWidget(old);
    if (!identical(old.lyrics, widget.lyrics)) {
      _measure();
      _reported = const Duration(days: 1);
      _index = -1;
      _draggedAt = null;
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
    _report(widget.service.now);
    _step(force: !identical(old.lyrics, widget.lyrics));
    _startTicking();
  }

  @override
  void onShownChanged(bool shown) => _startTicking();

  @override
  void dispose() {
    _tick?.cancel();
    _comeBack?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// Takes a new position from the source, when it has one.
  void _report(NowPlaying n) {
    if (n.position == _reported && n.isPlaying == _playing) return;
    _reported = n.position;
    _base = n.position;
    _playing = n.isPlaying;
    _since
      ..reset()
      ..start();
  }

  Duration get _position => _playing ? _base + _since.elapsed : _base;

  int _lineNow() => _lyrics.lineAt(_position + _lead);

  double _breakProgress(int i) {
    if (i < 0 || i >= _lyrics.lines.length || !_lyrics.lines[i].isBreak) {
      return 0;
    }
    final start = _lyrics.lines[i].at;
    final end = _lyrics.nextAt(i);
    if (end == null || end <= start) return 1;
    final f =
        (_position + _lead - start).inMilliseconds /
        (end - start).inMilliseconds;
    return f.clamp(0.0, 1.0);
  }

  /// A tenth of a second at a time while the song plays and the words can
  /// be seen; nothing while it is paused, or out of sight.
  void _startTicking() {
    final want = shown && _playing && _lyrics.lines.isNotEmpty;
    if (want && _tick == null) {
      _tick = Timer.periodic(
        Duration(milliseconds: _lyrics.synced ? 100 : 1000),
        (_) => _step(),
      );
    } else if (!want) {
      _tick?.cancel();
      _tick = null;
    }
  }

  void _step({bool force = false}) {
    if (!mounted) return;
    if (!_lyrics.synced) {
      _follow();
      return;
    }
    var i = _lineNow();
    // The source's next report can land a moment behind the count kept
    // between reports. That is no reason to light the last line again —
    // only a real move back, a seek, is.
    if (!force &&
        i == _index - 1 &&
        _index < _lyrics.lines.length &&
        _lyrics.lines[_index].at - (_position + _lead) <
            const Duration(milliseconds: 1500)) {
      i = _index;
    }
    final done = _breakProgress(i);
    // A break fills in quarters on a console, finer elsewhere: either way,
    // a rebuild only when what is drawn would change.
    final steps = context.look.isLcars ? 24 : 48;
    final moved = i != _index;
    if (moved || (done * steps).floor() != (_breakDone * steps).floor()) {
      setState(() {
        _index = i;
        _breakDone = done;
      });
    }
    if (moved || force) _follow(jump: force);
  }

  bool get _reading =>
      _dragging ||
      (_draggedAt != null &&
          DateTime.now().difference(_draggedAt!) < _readAhead);

  /// Brings the line being sung to the eye line, once it is laid out.
  void _follow({bool jump = false}) {
    // A frame to run it after, even where nothing else is being drawn.
    WidgetsBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || _reading) return;
      final lcars = context.look.isLcars;
      final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      final duration = jump || lcars || still
          ? Duration.zero
          : const Duration(milliseconds: 650);
      if (!_lyrics.synced) {
        // Untimed: as far down the words as the song is through.
        final n = widget.service.now;
        final target = _scroll.position.maxScrollExtent * n.progress;
        if ((target - _scroll.offset).abs() < 2) return;
        duration == Duration.zero
            ? _scroll.jumpTo(target)
            : _scroll.animateTo(
                target,
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeInOut,
              );
        return;
      }
      final i = _index.clamp(0, _keys.length - 1);
      final line = _keys[i].currentContext;
      if (line == null) return;
      Scrollable.ensureVisible(
        line,
        alignment: _eyeLine,
        duration: duration,
        curve: Curves.easeInOutCubic,
      );
    });
  }

  bool _onScroll(ScrollNotification n) {
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _dragging = true;
      _dragFrom = n.metrics.pixels;
    } else if (n is ScrollEndNotification && _dragging) {
      _dragging = false;
      // A touch that didn't move the words was no reading ahead.
      if ((n.metrics.pixels - _dragFrom).abs() < 4) return false;
      _draggedAt = DateTime.now();
      // Back to the line being sung once the reading is done.
      _comeBack?.cancel();
      _comeBack = Timer(_readAhead + const Duration(milliseconds: 50), () {
        if (mounted && !_reading) _follow();
      });
    }
    return false;
  }

  void _seek(int i) {
    final at = _lyrics.lines[i].at;
    widget.service.seek(at);
    // Straight there, rather than waiting for the source to say so.
    _base = at;
    _reported = const Duration(days: 1);
    _since
      ..reset()
      ..start();
    _draggedAt = null;
    _step(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final lcars = context.look.isLcars;
    final canSeek = _lyrics.synced && widget.service.canSeek;
    return LayoutBuilder(
      builder: (context, c) {
        final top = c.maxHeight * _eyeLine;
        Widget words = SingleChildScrollView(
          controller: _scroll,
          padding: EdgeInsets.only(
            top: _lyrics.synced ? top : 24,
            bottom: _lyrics.synced ? c.maxHeight - top - 40 : 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _lyrics.lines.length; i++)
                KeyedSubtree(
                  key: _keys[i],
                  child: lcars
                      ? _ConsoleLine(
                          line: _lyrics.lines[i],
                          verse: _verses[i],
                          state: _stateOf(i),
                          breakDone: i == _index ? _breakDone : 0,
                          timed: _lyrics.synced,
                          onTap: canSeek ? () => _seek(i) : null,
                        )
                      : _GlideLine(
                          line: _lyrics.lines[i],
                          state: _stateOf(i),
                          breakDone: i == _index ? _breakDone : 0,
                          onTap: canSeek ? () => _seek(i) : null,
                        ),
                ),
            ],
          ),
        );
        if (!lcars) {
          // The words fade out at the top and bottom rather than being cut
          // off by the edge of the view.
          words = ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x00000000),
                Color(0xFF000000),
                Color(0xFF000000),
                Color(0x00000000),
              ],
              stops: [0.0, 0.14, 0.82, 1.0],
            ).createShader(r),
            child: words,
          );
        }
        return NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          // No scroll bar: the words are dragged by a finger, and a bar
          // beside them would only be one more thing moving.
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            // Its own layer: the player round it redraws every second for
            // the progress bar, the words only when a line changes.
            child: RepaintBoundary(child: words),
          ),
        );
      },
    );
  }

  _LineState _stateOf(int i) {
    if (!_lyrics.synced) return _LineState.untimed;
    if (i == _index) return _LineState.now;
    return i < _index ? _LineState.sung : _LineState.ahead;
  }
}

enum _LineState { sung, now, ahead, untimed }

/// A line as the glassy, glossy and flat themes draw it: large and bold,
/// the one being sung full strength and a touch bigger, those around it
/// dimmed — more for the lines already sung.
class _GlideLine extends StatelessWidget {
  const _GlideLine({
    required this.line,
    required this.state,
    required this.breakDone,
    this.onTap,
  });

  final LyricLine line;
  final _LineState state;
  final double breakDone;
  final VoidCallback? onTap;

  static const _speed = Duration(milliseconds: 380);

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final now = state == _LineState.now;
    final alpha = switch (state) {
      _LineState.now => 1.0,
      _LineState.sung => 0.26,
      _LineState.ahead => 0.42,
      _LineState.untimed => 0.82,
    };
    final Widget body = line.isBreak
        ? _BreakDots(done: breakDone, lit: now, colour: look.accent)
        : AnimatedDefaultTextStyle(
            duration: _speed,
            curve: Curves.easeOut,
            style: TextStyle(
              color: look.textPrimary.withValues(alpha: alpha),
              fontSize: state == _LineState.untimed ? 36 : 46,
              fontWeight: FontWeight.w700,
              height: 1.18,
              letterSpacing: -0.3,
            ),
            child: Text(line.text),
          );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: state == _LineState.untimed ? 6 : 13,
        ),
        child: AnimatedScale(
          scale: now || state == _LineState.untimed ? 1 : 0.9,
          alignment: Alignment.centerLeft,
          duration: _speed,
          curve: Curves.easeOutCubic,
          child: body,
        ),
      ),
    );
  }
}

/// A break: three dots that light one by one as it passes, and swell a
/// little while it is the one going on.
class _BreakDots extends StatelessWidget {
  const _BreakDots({
    required this.done,
    required this.lit,
    required this.colour,
  });

  final double done;
  final bool lit;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final dim = context.look.wash(lit ? 0.32 : 0.18);
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          for (var k = 0; k < 3; k++)
            Padding(
              padding: const EdgeInsets.only(right: 18),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                width: lit ? 22 : 16,
                height: lit ? 22 : 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: lit && done > k / 3 + 0.02 ? colour : dim,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A line as a console draws it: the time it is sung on a block down the
/// side, lettered in its corner, and the words beside it.
///
/// The blocks are one column, a colour to a verse; the one being sung is
/// lit, those sung are unlit. Its words are in the accent while sung, the
/// theme's second colour ahead and dimmed behind. A break is a row of
/// segments counting across as it passes.
class _ConsoleLine extends StatelessWidget {
  const _ConsoleLine({
    required this.line,
    required this.verse,
    required this.state,
    required this.breakDone,
    required this.timed,
    this.onTap,
  });

  final LyricLine line;
  final int verse;
  final _LineState state;
  final double breakDone;
  final bool timed;
  final VoidCallback? onTap;

  static const _side = 116.0;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final now = state == _LineState.now;
    final colour = look.block(verse + 1);
    final block = now
        ? lcarsLit
        : state == _LineState.sung
        ? colour.withValues(alpha: 0.4)
        : colour;
    final ink = switch (state) {
      _LineState.now => look.accent,
      _LineState.sung => look.textSecondary.withValues(alpha: 0.42),
      _ => look.textSecondary,
    };
    final Widget words = line.isBreak
        ? Align(
            alignment: Alignment.centerLeft,
            // Counting across while it goes on; spent, all unlit as one.
            child: LcarsSegments(
              theme: look,
              value: now ? breakDone : (state == _LineState.sung ? 1 : 0),
              colour: state == _LineState.sung
                  ? look.textSecondary.withValues(alpha: 0.28)
                  : null,
              height: 16,
            ),
          )
        : Text(
            line.text,
            style: TextStyle(
              color: ink,
              fontSize: 44,
              height: 1.12,
              letterSpacing: 0.4,
            ),
          );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: lcarsLine),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: _side,
                constraints: const BoxConstraints(minHeight: 58),
                color: block,
                padding: const EdgeInsets.fromLTRB(8, 4, 12, 6),
                alignment: Alignment.bottomRight,
                child: timed
                    ? Text(
                        line.isBreak && line.at == Duration.zero
                            ? '00:00'
                            : playTime(line.at),
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          color: lcarsInk,
                          fontSize: 20,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 22),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: words,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
