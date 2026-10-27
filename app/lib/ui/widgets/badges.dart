import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:flutter/material.dart';

/// Starter / Pro / Elite.
class TierBadge extends StatelessWidget {
  const TierBadge({required this.tier, super.key, this.large = false});

  final Tier? tier;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (tier) {
      Tier.elite => (Palette.brass, Palette.charcoal, Icons.workspace_premium),
      Tier.pro => (Palette.forest, Palette.cream, Icons.verified_rounded),
      Tier.starter => (
        Palette.sand,
        Palette.charcoal,
        Icons.content_cut_rounded,
      ),
      null => (Palette.sand, Palette.ink, Icons.hourglass_empty_rounded),
    };
    final label = tier?.label ?? 'Ungraded';
    final style = (large ? context.text.titleMedium : context.text.labelMedium)
        ?.copyWith(color: fg, fontWeight: FontWeight.w800, letterSpacing: 0.4);
    return Semantics(
      label: '$label tier',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(large ? 14 : 999),
          gradient: tier == Tier.elite
              ? const LinearGradient(
                  colors: [Color(0xFFE2B866), Palette.brass],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
        ),
        child: Padding(
          padding: large
              ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8)
              : const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: large ? 20 : 14, color: fg),
              SizedBox(width: large ? 6 : 4),
              Text(label.toUpperCase(), style: style),
            ],
          ),
        ),
      ),
    );
  }
}

enum Tone { pass, review, fail, info, neutral }

extension ToneColors on BuildContext {
  (Color fg, Color bg) toneColors(Tone tone) => switch (tone) {
    Tone.pass => (status.pass, status.passContainer),
    Tone.review => (status.review, status.reviewContainer),
    Tone.fail => (status.fail, status.failContainer),
    Tone.info => (colors.primary, colors.primaryContainer),
    Tone.neutral => (colors.onSurfaceVariant, colors.surfaceContainerHigh),
  };
}

/// A small coloured status label.
class StatusPill extends StatelessWidget {
  const StatusPill({required this.label, required this.tone, super.key});

  factory StatusPill.job(JobStatus status, {Key? key}) => StatusPill(
    key: key,
    label: status.label,
    tone: switch (status) {
      JobStatus.verified => Tone.pass,
      JobStatus.needsReview || JobStatus.verifying => Tone.review,
      JobStatus.failed || JobStatus.cancelled => Tone.fail,
      JobStatus.booked => Tone.neutral,
      JobStatus.confirmed || JobStatus.inProgress => Tone.info,
    },
  );

  factory StatusPill.barber(BarberStatus status, {Key? key}) => StatusPill(
    key: key,
    label: status.label,
    tone: switch (status) {
      BarberStatus.approved => Tone.pass,
      BarberStatus.pendingApproval => Tone.review,
      BarberStatus.rejected => Tone.fail,
      BarberStatus.onboarding => Tone.neutral,
    },
  );

  factory StatusPill.payment(PaymentStatus status, {Key? key}) => StatusPill(
    key: key,
    label: status.label,
    tone: switch (status) {
      PaymentStatus.released => Tone.pass,
      PaymentStatus.held => Tone.review,
      PaymentStatus.refunded || PaymentStatus.partiallyRefunded => Tone.fail,
      PaymentStatus.forfeited => Tone.review,
      PaymentStatus.depositPaid => Tone.info,
      PaymentStatus.depositPending => Tone.neutral,
    },
  );

  final String label;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = context.toneColors(tone);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
              child: const SizedBox.square(dimension: 7),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: context.text.labelMedium?.copyWith(
                color: fg,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Five stars, optionally interactive.
class StarRating extends StatelessWidget {
  const StarRating({
    required this.stars,
    super.key,
    this.onChanged,
    this.size = 28,
  });

  final int stars;
  final ValueChanged<int>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 1; i <= 5; i++)
        onChanged == null
            ? Icon(
                i <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
                size: size,
                color: Palette.brass,
              )
            : IconButton(
                tooltip: '$i star${i == 1 ? '' : 's'}',
                onPressed: () => onChanged!(i),
                icon: Icon(
                  i <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: size,
                  color: Palette.brass,
                ),
              ),
    ],
  );
}

/// Barber initials in a forest circle.
class Monogram extends StatelessWidget {
  const Monogram({required this.name, super.key, this.size = 44});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = name
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Palette.forest,
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(
        dimension: size,
        child: Center(
          child: Text(
            initials.isEmpty ? '?' : initials,
            style: context.text.titleMedium?.copyWith(
              color: Palette.cream,
              fontSize: size * 0.38,
            ),
          ),
        ),
      ),
    );
  }
}
