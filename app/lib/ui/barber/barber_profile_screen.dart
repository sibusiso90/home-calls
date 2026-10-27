import 'package:fade_call/core/format.dart';
import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/state/barber_state.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/barber/onboarding_flow.dart';
import 'package:fade_call/ui/widgets/ai_attribution.dart';
import 'package:fade_call/ui/widgets/badges.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:fade_call/ui/widgets/fade_app_bar.dart';
import 'package:fade_call/ui/widgets/portfolio_scores.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Onboarding stepper until graded, then the barber's profile card.
class BarberProfileScreen extends ConsumerWidget {
  const BarberProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final barber = ref.watch(myBarberProvider);
    return Scaffold(
      appBar: FadeAppBar(
        title: barber.value?.isOnboarded ?? true ? 'Profile' : 'Get verified',
      ),
      body: AsyncView(
        value: barber,
        onRetry: () => ref.invalidate(myBarberProvider),
        loadingMessage: 'Loading your profile…',
        builder: (b) => b.isOnboarded
            ? ProfileCardView(barber: b)
            : OnboardingFlow(barber: b),
      ),
    );
  }
}

class ProfileCardView extends ConsumerWidget {
  const ProfileCardView({required this.barber, super.key});

  final Barber barber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grade = ref.watch(gradeResultProvider);
    final b = barber;
    void reload() => ref.invalidate(myBarberProvider);
    return PageList(
      onRefresh: () => ref.refresh(myBarberProvider.future),
      children: [
        _ProfileHero(barber: b),
        const SizedBox(height: Gap.md),
        switch (b.status) {
          BarberStatus.pendingApproval => Callout.warning(
            context,
            'An operator checks every new barber. You will show up in client '
            'searches once you are approved.',
            title: 'Awaiting operator approval',
          ),
          BarberStatus.rejected => Callout(
            icon: Icons.block_rounded,
            color: context.status.fail,
            background: context.status.failContainer,
            title: 'Not approved yet',
            text:
                'An operator could not approve your profile. Contact Fade Call '
                'support to find out what to fix.',
          ),
          BarberStatus.approved => Callout(
            icon: Icons.verified_rounded,
            color: context.status.pass,
            background: context.status.passContainer,
            title: 'You are live',
            text: 'Clients in your area can find and book you.',
          ),
          BarberStatus.onboarding => const SizedBox.shrink(),
        },
        if (grade != null) ...[
          const SectionHeader(title: 'What the grader said'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      grade.average.toStringAsFixed(1),
                      style: context.text.displaySmall?.copyWith(
                        color: context.colors.primary,
                      ),
                    ),
                    const SizedBox(width: Gap.sm),
                    Text(
                      'average\nacross 5 pairs',
                      style: context.text.bodySmall,
                    ),
                    const Spacer(),
                    TierBadge(tier: grade.tier, large: true),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                Text(grade.summary, style: context.text.bodyMedium),
                const SizedBox(height: Gap.sm),
                const AiAttribution(
                  models: [MetaModel.spark],
                  prefix: 'From scores by',
                ),
              ],
            ),
          ),
        ],
        const SectionHeader(title: 'Track record'),
        Panel(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Stat(
                label: 'Verified jobs',
                value: '${b.verifiedJobs}',
                icon: Icons.verified_outlined,
              ),
              Stat(
                label: 'Rating',
                value: formatRating(b.rating),
                icon: Icons.star_rounded,
              ),
              Stat(
                label: 'Years cutting',
                value: b.yearsCutting?.toString() ?? '—',
                icon: Icons.content_cut_rounded,
              ),
            ],
          ),
        ),
        const SectionHeader(title: 'About'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (b.styles.isNotEmpty)
                Wrap(
                  spacing: Gap.sm,
                  runSpacing: Gap.sm,
                  children: [for (final s in b.styles) Chip(label: Text(s))],
                ),
              const SizedBox(height: Gap.sm),
              if (b.languages.isNotEmpty)
                DetailLine(
                  icon: Icons.translate_rounded,
                  text: b.languages.join(', '),
                ),
              if ((b.availability ?? '').isNotEmpty)
                DetailLine(icon: Icons.schedule_rounded, text: b.availability!),
              if (b.areaName != null)
                DetailLine(icon: Icons.place_outlined, text: b.areaName!),
            ],
          ),
        ),
        if (b.portfolio.isNotEmpty) ...[
          SectionHeader(
            title: 'Portfolio',
            subtitle: '${b.portfolio.length} graded pairs',
          ),
          for (final (i, item) in b.portfolio.indexed) ...[
            PortfolioCard(item: item, index: i, onExpired: reload),
            const SizedBox(height: Gap.sm + 4),
          ],
        ],
      ],
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.barber});

  final Barber barber;

  @override
  Widget build(BuildContext context) {
    final b = barber;
    final light = Palette.cream.withValues(alpha: 0.78);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Palette.forest, Palette.forestDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.name,
                        style: context.text.headlineMedium?.copyWith(
                          color: Palette.cream,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        b.areaName ?? 'Area not set',
                        style: context.text.bodyMedium?.copyWith(color: light),
                      ),
                    ],
                  ),
                ),
                TierBadge(tier: b.tier, large: true),
              ],
            ),
            const SizedBox(height: Gap.lg),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HOME-CALL PRICE BAND',
                        style: context.text.labelSmall?.copyWith(
                          color: Palette.brass,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        switch (b.priceBand) {
                          final p? => randRange(p.minZar, p.maxZar),
                          null => '—',
                        },
                        style: context.text.headlineSmall?.copyWith(
                          color: Palette.cream,
                        ),
                      ),
                    ],
                  ),
                ),
                StatusPill.barber(b.status),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
