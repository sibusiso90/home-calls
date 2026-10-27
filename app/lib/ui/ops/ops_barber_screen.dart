import 'package:fade_call/core/format.dart';
import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/ops/ops_common.dart';
import 'package:fade_call/ui/ops/ops_jobs_screen.dart';
import 'package:fade_call/ui/widgets/badges.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:fade_call/ui/widgets/fade_app_bar.dart';
import 'package:fade_call/ui/widgets/portfolio_scores.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Operator view of one barber: profile, tier, track record, ratings, jobs
/// and the graded portfolio with every score and reason.
class OpsBarberScreen extends ConsumerWidget {
  const OpsBarberScreen({required this.barberId, super.key});

  final String barberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(opsBarberProvider(barberId));
    return Scaffold(
      appBar: FadeAppBar(title: detail.value?.barber.name ?? 'Barber'),
      body: AsyncView(
        value: detail,
        onRetry: () => ref.invalidate(opsBarberProvider(barberId)),
        builder: (d) => BarberDetailView(
          detail: d,
          onRefresh: () => ref.refresh(opsBarberProvider(barberId).future),
          onExpired: () => ref.invalidate(opsBarberProvider(barberId)),
        ),
      ),
    );
  }
}

class BarberDetailView extends StatelessWidget {
  const BarberDetailView({
    required this.detail,
    super.key,
    this.onRefresh,
    this.onExpired,
  });

  final BarberDetail detail;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onExpired;

  @override
  Widget build(BuildContext context) {
    final b = detail.barber;
    final avg = b.portfolio.isEmpty
        ? null
        : b.portfolio.map((p) => p.overall).reduce((a, c) => a + c) /
              b.portfolio.length;
    return PageList(
      maxWidth: opsMaxWidth,
      onRefresh: onRefresh,
      children: [
        Panel(
          padding: const EdgeInsets.all(Gap.lg - 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Monogram(name: b.name, size: 56),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.name, style: context.text.headlineSmall),
                        Text(
                          [
                            b.areaName ?? 'No area',
                            if (b.yearsCutting != null) '${b.yearsCutting} yrs',
                            if (b.languages.isNotEmpty) b.languages.join(', '),
                          ].join(' · '),
                          style: context.text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.md),
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                children: [
                  TierBadge(tier: b.tier),
                  StatusPill.barber(b.status),
                ],
              ),
              const SizedBox(height: Gap.md),
              Wrap(
                spacing: Gap.xl,
                runSpacing: Gap.md,
                children: [
                  Stat(
                    label: 'Verified jobs',
                    value: '${b.verifiedJobs}',
                    icon: Icons.verified_outlined,
                  ),
                  Stat(
                    label: detail.ratings.isEmpty
                        ? 'Rating'
                        : 'Rating · ${detail.ratings.length} '
                              '${detail.ratings.length == 1 ? 'review' : 'reviews'}',
                    value: formatRating(b.rating),
                    icon: Icons.star_rounded,
                  ),
                  Stat(
                    label: 'Portfolio average',
                    value: avg == null ? '—' : avg.toStringAsFixed(1),
                  ),
                  Stat(
                    label: 'Price band',
                    value: switch (b.priceBand) {
                      final p? => randRange(p.minZar, p.maxZar),
                      null => '—',
                    },
                  ),
                ],
              ),
              if (b.styles.isNotEmpty) ...[
                const SizedBox(height: Gap.md),
                Wrap(
                  spacing: Gap.sm,
                  runSpacing: Gap.sm,
                  children: [for (final s in b.styles) Chip(label: Text(s))],
                ),
              ],
              if ((b.availability ?? '').isNotEmpty)
                DetailLine(icon: Icons.schedule_rounded, text: b.availability!),
            ],
          ),
        ),
        SectionHeader(
          title: 'Ratings',
          subtitle: detail.ratings.isEmpty
              ? 'Ratings unlock only after verified jobs.'
              : null,
        ),
        for (final r in detail.ratings) ...[
          Panel(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StarRating(stars: r.stars, size: 18),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((r.comment ?? '').isNotEmpty)
                        Text(r.comment!, style: context.text.bodyMedium),
                      Text(
                        '${r.clientName} · ${formatDay(r.createdAt)}',
                        style: context.text.labelSmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.sm),
        ],
        SectionHeader(
          title: 'Jobs',
          subtitle: detail.jobs.isEmpty ? 'No bookings yet.' : null,
        ),
        for (final j in detail.jobs) ...[
          OpsJobRow(job: j),
          const SizedBox(height: Gap.sm),
        ],
        SectionHeader(
          title: 'Portfolio',
          subtitle: '${b.portfolio.length} pairs scored by Muse Spark',
        ),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 1000
                ? 3
                : c.maxWidth >= 640
                ? 2
                : 1;
            final w = (c.maxWidth - Gap.md * (cols - 1)) / cols;
            return Wrap(
              spacing: Gap.md,
              runSpacing: Gap.md,
              children: [
                for (final (i, item) in b.portfolio.indexed)
                  SizedBox(
                    width: w,
                    child: PortfolioCard(
                      item: item,
                      index: i,
                      onExpired: onExpired,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
