import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../look.dart';
import '../services/voice_service.dart';
import 'glass.dart';

/// That the panel heard "hey canvas", and what it made of the rest — at
/// the top of whatever screen is up, for a few seconds.
///
/// Mostly this is the answer: listening, then the words as they were heard,
/// or that nothing was made of them. Seeing "show socks" is how you find
/// out why the stocks did not appear. What Home Assistant says back, when
/// it was asked, is shown under the words. A question the panel asks — a
/// routine's "Do you want the heater on or off?" — is shown with its
/// answers to touch, for when saying them is no good.
class VoiceIndicator extends StatelessWidget {
  const VoiceIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final voice = context.watch<VoiceService>();
    final look = context.look;
    final status = voice.status;
    final showing =
        status == VoiceStatus.awake ||
        status == VoiceStatus.asking ||
        status == VoiceStatus.done ||
        status == VoiceStatus.missed ||
        status == VoiceStatus.answering;
    final asking = status == VoiceStatus.answering;
    final words = switch (status) {
      VoiceStatus.asking => '${voice.heard}…',
      VoiceStatus.done => voice.heard,
      VoiceStatus.missed when voice.heard.isEmpty => tr(
        'voice.heardNothing',
        'Didn’t catch that',
      ),
      VoiceStatus.missed => tr(
        'voice.notUnderstood',
        'Didn’t understand “{heard}”',
        {'heard': voice.heard},
      ),
      VoiceStatus.answering => voice.question,
      _ => tr('voice.listening', 'Listening…'),
    };
    final answer = status == VoiceStatus.done ? voice.answer : '';
    return Positioned(
      left: 0,
      right: 0,
      top: 96,
      // Touchable only while it asks something: otherwise it floats over
      // whatever is under it and must not take its touches.
      child: IgnorePointer(
        ignoring: !asking,
        child: AnimatedSlide(
          offset: showing ? Offset.zero : const Offset(0, -0.6),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: showing ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: Center(
              child: Material(
                type: MaterialType.transparency,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Glass(
                    // Nearly solid: it floats over photos and pages alike.
                    tint: 0.5,
                    padding: const EdgeInsets.fromLTRB(20, 12, 26, 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: asking
                          ? CrossAxisAlignment.start
                          : CrossAxisAlignment.center,
                      children: [
                        Icon(
                          status == VoiceStatus.missed
                              ? Icons.mic_off_rounded
                              : Icons.mic_rounded,
                          color: status == VoiceStatus.missed
                              ? look.textSecondary
                              : look.accent,
                          size: 30,
                        ),
                        const SizedBox(width: 14),
                        Flexible(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                words,
                                maxLines: asking ? 2 : 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: answer.isEmpty
                                      ? look.textPrimary
                                      : look.textSecondary,
                                  fontSize: answer.isEmpty ? 22 : 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (answer.isNotEmpty)
                                Text(
                                  answer,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: look.textPrimary,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              if (asking && voice.choices.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Wrap(
                                    spacing: 12,
                                    runSpacing: 8,
                                    children: [
                                      for (final c in voice.choices)
                                        FilledButton.tonal(
                                          style: FilledButton.styleFrom(
                                            minimumSize: const Size(120, 56),
                                            textStyle: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          onPressed: () => voice.choose(c),
                                          child: Text(c),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
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
