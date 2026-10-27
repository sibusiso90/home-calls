import 'package:fade_call/core/format.dart';
import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/state/quote_state.dart';
import 'package:fade_call/ui/client/booking_sheet.dart';
import 'package:fade_call/ui/widgets/badges.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:fade_call/ui/widgets/fade_app_bar.dart';
import 'package:fade_call/ui/widgets/price_breakdown.dart';
import 'package:fade_call/ui/widgets/signed_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Approved barbers in travel range, best match first.
class MatchesScreen extends ConsumerWidget {
  const MatchesScreen({required this.quoteId, super.key});

  final String quoteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(matchesProvider(quoteId));
    final quote = ref.watch(quoteControllerProvider).quote;
    return Scaffold(
      appBar: const FadeAppBar(title: 'Your matches'),
      body: AsyncView(
        value: matches,
        onRetry: () => ref.invalidate(matchesProvider(quoteId)),
        loadingMessage: 'Finding verified barbers in range…',
        isEmpty: (list) => list.isEmpty,
        empty: const MessageView(
          icon: Icons.person_search_rounded,
          title: 'No barbers in range yet',
          message:
              'No approved barber is within 20 km of your suburb right now. '
              'Try a nearby suburb or check back soon.',
        ),
        builder: (list) => PageList(
          onRefresh: () => ref.refresh(matchesProvider(quoteId).future),
          children: [
            if (quote != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.md),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '${list.length} verified barbers for a '),
                      TextSpan(
                        text: quote.cutName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      TextSpan(text: ' (${quote.minutes} min)'),
                    ],
                  ),
                  style: context.text.bodyMedium,
                ),
              ),
            for (final (i, m) in list.indexed) ...[
              MatchCard(
                match: m,
                rank: i + 1,
                minutes: quote?.minutes,
                onRefresh: () => ref.invalidate(matchesProvider(quoteId)),
                onBook: () => showBookingSheet(
                  context,
                  quoteId: quoteId,
                  match: m,
                  areaId: quote?.areaId,
                ),
              ),
              const SizedBox(height: Gap.md),
            ],
          ],
        ),
      ),
    );
  }
}

class MatchCard extends StatelessWidget {
  const MatchCard({
    required this.match,
    required this.rank,
    required this.onBook,
    super.key,
    this.minutes,
    this.onRefresh,
  });

  final BarberMatch match;
  final int rank;
  final int? minutes;
  final VoidCallback onBook;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final b = match.barber;
    return Panel(
      borderColor: rank == 1 ? Palette.brass : null,
      padding: const EdgeInsets.all(Gap.md + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rank == 1)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm + 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.emoji_events_rounded,
                    size: 16,
                    color: Palette.brass,
                  ),
                  const SizedBox(width: Gap.xs),
                  Text(
                    'BEST MATCH',
                    style: context.text.labelSmall?.copyWith(
                      color: Palette.brass,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              SizedBox.square(
                dimension: 56,
                child: b.thumbnailUrl == null
                    ? Monogram(name: b.name, size: 56)
                    : SignedImage(
                        url: b.thumbnailUrl,
                        aspectRatio: 1,
                        radius: 28,
                        onExpired: onRefresh,
                      ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            b.name,
                            style: context.text.titleLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: Gap.sm),
                        TierBadge(tier: b.tier),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        '★ ${formatRating(b.rating)}',
                        '${b.verifiedJobs} verified jobs',
                        if (b.areaName != null) b.areaName!,
                      ].join(' · '),
                      style: context.text.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
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
              _InfoChip(
                icon: Icons.near_me_outlined,
                text:
                    '${formatKm(match.distanceKm)} · band ${match.travelBand}',
              ),
              _InfoChip(
                icon: Icons.event_available_rounded,
                text: match.nextSlot == null
                    ? 'No open slot'
                    : 'Next: ${formatSlot(match.nextSlot)}',
              ),
              for (final s in b.styles.take(2))
                _InfoChip(icon: Icons.content_cut_rounded, text: s),
            ],
          ),
          const SizedBox(height: Gap.md),
          DecoratedBox(
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(Gap.sm + 4),
              child: PriceBreakdown(
                price: match.price,
                tier: b.tier,
                minutes: minutes,
                travelBand: match.travelBand,
                distanceKm: match.distanceKm,
              ),
            ),
          ),
          const SizedBox(height: Gap.md),
          FilledButton(
            onPressed: match.nextSlot == null ? null : onBook,
            child: Text(
              'Book ${b.name.split(' ').first} for ${rand(match.price.totalZar)}',
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: context.colors.primary),
          const SizedBox(width: 5),
          Text(text, style: context.text.labelMedium),
        ],
      ),
    ),
  );
}
