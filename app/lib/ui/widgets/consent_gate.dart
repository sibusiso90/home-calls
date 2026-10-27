import 'package:fade_call/core/theme.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a consent notice covers.
enum ConsentTopic {
  barberOnboarding('barber_onboarding', 'Before you record or upload', [
    'Your voice note is transcribed to build your profile. You check it before anything is saved.',
    'Only upload photos of clients who have agreed to be photographed for your portfolio.',
    'Photos and voice notes are stored privately and only shown through short-lived links.',
    'We never build a face database or search faces across jobs.',
  ]),
  quotePhotos('quote_photos', 'Before you take photos', [
    'Your selfie and reference photo are used only to name the cut and price this quote.',
    'They are stored privately and shown only through short-lived links.',
    'Faces are never searched, matched to other people or made public.',
  ]),
  proofCapture('proof_capture', 'Proof-of-job photos', [
    'Ask the client before you take each photo. If they say no, stop and contact the operator.',
    'Use the live camera at the booking address. Time and GPS are recorded at the shutter.',
    'Before and after photos are compared only within this job, then deleted after the verdict.',
  ]);

  const ConsentTopic(this.key, this.title, this.points);
  final String key;
  final String title;
  final List<String> points;
}

/// Shows a consent screen until the user agrees, then shows [child].
class ConsentGate extends ConsumerWidget {
  const ConsentGate({required this.topic, required this.child, super.key});

  final ConsentTopic topic;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agreed = ref.watch(consentProvider(topic.key));
    if (agreed) return child;
    return ConsentCard(
      topic: topic,
      onAgree: () => ref.read(consentProvider(topic.key).notifier).accept(),
    );
  }
}

class ConsentCard extends StatelessWidget {
  const ConsentCard({
    required this.topic,
    required this.onAgree,
    super.key,
    this.agreeLabel = 'I understand and agree',
  });

  final ConsentTopic topic;
  final VoidCallback onAgree;
  final String agreeLabel;

  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.all(Gap.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.privacy_tip_outlined, color: context.colors.secondary),
            const SizedBox(width: Gap.sm),
            Text(
              'YOUR CONSENT',
              style: context.text.labelMedium?.copyWith(
                letterSpacing: 1.2,
                fontWeight: FontWeight.w800,
                color: context.colors.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.sm),
        Text(topic.title, style: context.text.headlineSmall),
        const SizedBox(height: Gap.md),
        for (final p in topic.points)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm + 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: context.colors.primary,
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Expanded(child: Text(p, style: context.text.bodyMedium)),
              ],
            ),
          ),
        const SizedBox(height: Gap.sm),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: onAgree, child: Text(agreeLabel)),
        ),
      ],
    ),
  );
}
