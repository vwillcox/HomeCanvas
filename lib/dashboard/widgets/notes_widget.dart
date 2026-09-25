import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/dashboard_service.dart';
import '../../services/notes_service.dart';
import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';

/// Sticky notes for the household, sent from a phone.
///
/// Tap a note to pick it; tap Done on it to take it down.
class NotesWidget extends StatefulWidget {
  const NotesWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<NotesWidget> createState() => _NotesWidgetState();
}

class _NotesWidgetState extends State<NotesWidget> {
  String? _picked;

  /// Paper colours, as sticky notes come. Dark text on all of them, so they
  /// read the same whatever the theme behind them.
  static const _papers = [
    Color(0xFFFFE7A3),
    Color(0xFFCFE6FF),
    Color(0xFFD9F5DE),
    Color(0xFFFFD6E0),
    Color(0xFFE8DCFF),
  ];

  /// Notes smaller than this on screen stop being readable across a room;
  /// past it, the oldest wait their turn instead of all shrinking.
  static const _minNoteHeight = 110.0;

  /// The same number for the same note on every run — a String's own
  /// hashCode changes between runs, which would recolour every note after a
  /// restart.
  static int _stable(String s) =>
      s.codeUnits.fold(7, (h, c) => (h * 31 + c) & 0x3fffffff);

  static String ago(DateTime at, DateTime now) {
    final d = now.difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) {
      return '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    }
    if (d.inDays == 1) return 'yesterday';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return d.inDays < 7 ? days[at.weekday - 1] : '${at.day}/${at.month}';
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final notes = context.watch<NotesService>().notes;
    if (notes.isEmpty) {
      final address = context.read<DashboardService>().editorAddress;
      return TileMessage(
        'No notes. Share some text from the phone app, or add one at '
        '$address/notes',
        theme: t,
      );
    }
    final now = DateTime.now();

    return LayoutBuilder(
      builder: (context, c) {
        // As many as fit at a readable size, newest first.
        var count = notes.length;
        var grid = bestGrid(count, c.biggest, cellAspect: 1.25);
        while (count > 1 && c.maxHeight / grid.rows < _minNoteHeight) {
          count--;
          grid = bestGrid(count, c.biggest, cellAspect: 1.25);
        }
        final gap = math.min(c.maxWidth, c.maxHeight) * 0.035;
        final cellH = (c.maxHeight - gap * (grid.rows - 1)) / grid.rows;
        // Never wider than a sticky note is: one note on a wide board stays a
        // note, not a banner.
        final cellW = math.min(
          (c.maxWidth - gap * (grid.columns - 1)) / grid.columns,
          cellH * 1.6,
        );
        final shown = notes.take(count).toList();

        return Stack(
          children: [
            for (var i = 0; i < shown.length; i++)
              Positioned(
                left: (i % grid.columns) * (cellW + gap),
                top: (i ~/ grid.columns) * (cellH + gap),
                width: cellW,
                height: cellH,
                child: _Note(
                  note: shown[i],
                  paper: _papers[_stable(shown[i].id) % _papers.length],
                  // A slight, steady tilt per note, as if stuck on by hand.
                  tilt: ((_stable(shown[i].id) ~/ 7 % 5) - 2) * 0.006,
                  when: ago(shown[i].at, now),
                  picked: _picked == shown[i].id,
                  onTap: () => setState(
                    () => _picked = _picked == shown[i].id ? null : shown[i].id,
                  ),
                  onDone: () {
                    context.read<NotesService>().remove(shown[i].id);
                    setState(() => _picked = null);
                  },
                ),
              ),
            if (notes.length > count)
              Positioned(
                right: 0,
                bottom: 0,
                child: StatusChip(
                  text: '+${notes.length - count} more',
                  colour: t.textSecondary,
                  size: 12,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({
    required this.note,
    required this.paper,
    required this.tilt,
    required this.when,
    required this.picked,
    required this.onTap,
    required this.onDone,
  });

  final HouseNote note;
  final Color paper;
  final double tilt;
  final String when;
  final bool picked;
  final VoidCallback onTap;
  final VoidCallback onDone;

  static const _ink = Color(0xFF2A2419);

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: tilt,
      child: GestureDetector(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: paper,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color(0x59000000),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              FitCanvas(
                designHeight: 100,
                maxScale: 3.2,
                builder: (context, size) => Padding(
                  padding: const EdgeInsets.fromLTRB(9, 8, 9, 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Text(
                          note.text,
                          overflow: TextOverflow.fade,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 14,
                            height: 1.22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        [if (note.from.isNotEmpty) note.from, when].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _ink.withValues(alpha: 0.62),
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Picked: a big target to take it down, sized to the note so it
              // is as easy to hit on a small tile as on a large one. A tap
              // anywhere else on the note puts it back.
              if (picked)
                LayoutBuilder(
                  builder: (context, c) {
                    final size = math.min(c.maxWidth, c.maxHeight);
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        color: _ink.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: GestureDetector(
                          onTap: onDone,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: size * 0.12,
                              vertical: size * 0.06,
                            ),
                            decoration: BoxDecoration(
                              color: paper,
                              borderRadius: BorderRadius.circular(size),
                            ),
                            child: Text(
                              'Done ✓',
                              style: TextStyle(
                                color: _ink,
                                fontSize: size * 0.13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

final notesWidgetType = DashboardWidgetType(
  type: 'notes',
  category: WidgetCategory.house,
  name: 'Notes',
  description:
      'Sticky notes for the household. Share text from the phone '
      'app, or post one from any phone on the home network at the editor’s '
      'address followed by /notes. Tap a note, then Done, to take it down.',
  glyph: '📝',
  defaultWidth: 5,
  defaultHeight: 3,
  minWidth: 2,
  minHeight: 1,
  fitsItself: true,
  preview: const [
    PreviewLine('Dentist moved to Thursday 4pm', scale: 0.15),
    PreviewLine('Vincent · 08:02', scale: 0.09, muted: true),
    PreviewLine('Parcel is in the shed', scale: 0.15),
  ],
  build: (context, w) => NotesWidget(w: w),
);
