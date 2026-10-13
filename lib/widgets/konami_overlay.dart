import 'dart:async';

import 'package:flutter/material.dart';

/// Up, up, down, down, left, right, left, right, B, A — said to the panel.
///
/// It does what the code has always done, which is nothing you could not
/// have managed without it: thirty lives, in arcade pixels, for a few
/// seconds over whatever is on screen.
class KonamiOverlay extends StatefulWidget {
  const KonamiOverlay({super.key});

  /// Counts the times the code has been said; each one shows it again.
  static final ValueNotifier<int> said = ValueNotifier(0);

  @override
  State<KonamiOverlay> createState() => _KonamiOverlayState();
}

class _KonamiOverlayState extends State<KonamiOverlay>
    with SingleTickerProviderStateMixin {
  static const _arrows = [
    Icons.arrow_upward_rounded,
    Icons.arrow_upward_rounded,
    Icons.arrow_downward_rounded,
    Icons.arrow_downward_rounded,
    Icons.arrow_back_rounded,
    Icons.arrow_forward_rounded,
    Icons.arrow_back_rounded,
    Icons.arrow_forward_rounded,
  ];

  // Ten steps, one for each press of the code, then held, then gone.
  late final AnimationController _play = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
  );

  @override
  void initState() {
    super.initState();
    KonamiOverlay.said.addListener(_said);
    _play.addStatusListener((status) {
      if (status == AnimationStatus.completed) _play.value = 0;
    });
  }

  void _said() => unawaited(_play.forward(from: 0));

  @override
  void dispose() {
    KonamiOverlay.said.removeListener(_said);
    _play.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _play,
          builder: (context, _) {
            final t = _play.value;
            if (t == 0) return const SizedBox.shrink();
            // The code goes in over the first third, a press at a time.
            final pressed = (t / 0.3 * 10).floor().clamp(0, 10);
            final lives = pressed == 10;
            // Blinks as a credit does, and fades at the very end.
            final blink = ((t * 5200) ~/ 260).isEven;
            final fade = t > 0.92 ? (1 - t) / 0.08 : 1.0;
            const green = Color(0xFF7CFC6A);
            Widget key(String letter, bool on) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                letter,
                style: TextStyle(
                  fontFamily: 'PressStart2P',
                  // Above the Navigator, so with no Material to say so.
                  decoration: TextDecoration.none,
                  fontSize: 44,
                  color: on ? green : Colors.white12,
                ),
              ),
            );
            return Opacity(
              opacity: fade.clamp(0.0, 1.0),
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.88),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (i, arrow) in _arrows.indexed)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(
                              arrow,
                              size: 64,
                              color: i < pressed ? green : Colors.white12,
                            ),
                          ),
                        key('B', pressed > 8),
                        key('A', pressed > 9),
                      ],
                    ),
                    const SizedBox(height: 70),
                    Opacity(
                      opacity: lives && blink ? 1 : 0,
                      child: const Text(
                        '+30 LIVES',
                        style: TextStyle(
                          fontFamily: 'PressStart2P',
                          decoration: TextDecoration.none,
                          fontSize: 86,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
