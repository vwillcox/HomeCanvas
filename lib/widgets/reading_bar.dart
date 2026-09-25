import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../look.dart';
import '../services/article_reader.dart';
import 'glass.dart';

/// What is being read aloud, along the bottom of whatever screen is up:
/// the headline, how far through, and pause, next paragraph and stop.
///
/// Over every screen rather than inside the news tile, because a reading
/// outlives the page it started on — turn the dashboard's page, or go to the
/// photos, and it carries on, with its controls still to hand.
class ReadingBar extends StatelessWidget {
  const ReadingBar({super.key});

  @override
  Widget build(BuildContext context) {
    final reader = context.watch<ArticleReader>();
    final look = context.look;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 28,
      child: IgnorePointer(
        ignoring: !reader.active,
        child: AnimatedSlide(
          offset: reader.active ? Offset.zero : const Offset(0, 1.6),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: reader.active ? 1 : 0,
            duration: const Duration(milliseconds: 220),
            child: Center(
              child: Material(
                type: MaterialType.transparency,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Glass(
                    // Nearly solid: this floats over photos and pages alike,
                    // and has to read over all of them.
                    tint: 0.5,
                    padding: const EdgeInsets.fromLTRB(22, 6, 8, 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.record_voice_over_rounded,
                          color: look.accent,
                          size: 28,
                        ),
                        const SizedBox(width: 16),
                        Flexible(child: _Words(reader: reader)),
                        const SizedBox(width: 12),
                        PillIconButton(
                          icon: reader.status == ReaderStatus.paused
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                          tooltip: reader.status == ReaderStatus.paused
                              ? 'Carry on reading'
                              : 'Pause',
                          colour: look.textPrimary,
                          onPressed: reader.status == ReaderStatus.fetching
                              ? null
                              : () => reader.status == ReaderStatus.paused
                                  ? reader.resume()
                                  : reader.pause(),
                        ),
                        PillIconButton(
                          icon: Icons.skip_next_rounded,
                          tooltip: 'Next paragraph',
                          colour: look.textPrimary,
                          onPressed: reader.status == ReaderStatus.fetching
                              ? null
                              : reader.skip,
                        ),
                        PillIconButton(
                          icon: Icons.stop_rounded,
                          tooltip: 'Stop reading',
                          colour: look.textPrimary,
                          onPressed: reader.stop,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Words extends StatelessWidget {
  const _Words({required this.reader});

  final ArticleReader reader;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final detail = switch (reader.status) {
      ReaderStatus.fetching => 'Getting the article…',
      ReaderStatus.paused => 'Paused',
      _ when reader.summaryOnly => 'Reading the summary',
      _ when reader.total > 0 =>
        'Reading aloud · ${reader.position + 1} of ${reader.total}',
      _ => 'Reading aloud',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          reader.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: look.textPrimary,
            fontSize: 19,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: look.textSecondary, fontSize: 15),
              ),
            ),
            if (reader.total > 0) ...[
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (reader.position + 1) / reader.total,
                    minHeight: 3,
                    backgroundColor: look.wash(0.15),
                    valueColor: AlwaysStoppedAnimation(look.accent),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
