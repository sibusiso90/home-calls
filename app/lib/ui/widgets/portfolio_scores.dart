import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/ui/widgets/ai_attribution.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:fade_call/ui/widgets/signed_image.dart';
import 'package:flutter/material.dart';

/// A portfolio pair with its four scores and the model's reasons.
class PortfolioCard extends StatelessWidget {
  const PortfolioCard({
    required this.item,
    super.key,
    this.index,
    this.onDelete,
    this.onExpired,
    this.compact = false,
  });

  final PortfolioItem item;
  final int? index;
  final VoidCallback? onDelete;
  final VoidCallback? onExpired;
  final bool compact;

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                index == null ? 'Before / after' : 'Pair ${index! + 1}',
                style: context.text.titleMedium,
              ),
            ),
            _OverallChip(score: item.overall),
            if (onDelete != null)
              IconButton(
                tooltip: 'Remove pair',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
          ],
        ),
        AiAttribution.fromVersions(
          item.modelVersions,
          elapsedMs: item.elapsedMs,
          prefix: 'Scored by',
        ),
        const SizedBox(height: Gap.sm + 4),
        Row(
          children: [
            Expanded(
              child: SignedImage(
                url: item.beforeUrl,
                label: 'BEFORE',
                aspectRatio: 1,
                onExpired: onExpired,
              ),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: SignedImage(
                url: item.afterUrl,
                label: 'AFTER',
                aspectRatio: 1,
                onExpired: onExpired,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.md),
        for (final c in ScoreCriterion.values)
          ScoreBar(
            label: c.label,
            score: item.score(c),
            reason: compact ? null : item.reason(c),
          ),
      ],
    ),
  );
}

class _OverallChip extends StatelessWidget {
  const _OverallChip({required this.score});

  final double score;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Palette.forest,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Text(
        '${score.toStringAsFixed(1)} / 10',
        style: context.text.labelLarge?.copyWith(color: Palette.cream),
      ),
    ),
  );
}

/// A 0–10 score with a bar and an optional reason.
class ScoreBar extends StatelessWidget {
  const ScoreBar({
    required this.label,
    required this.score,
    super.key,
    this.reason,
  });

  final String label;
  final double? score;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final s = score;
    final color = s == null
        ? context.colors.outline
        : s >= 8
        ? context.status.pass
        : s >= 6.5
        ? context.colors.primary
        : context.status.review;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 92,
                child: Text(label, style: context.text.labelLarge),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: s == null ? 0 : s / 10,
                    minHeight: 8,
                    color: color,
                    backgroundColor: context.colors.surfaceContainerHigh,
                  ),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  s == null ? '—' : s.toStringAsFixed(s % 1 == 0 ? 0 : 1),
                  textAlign: TextAlign.end,
                  style: context.text.titleSmall,
                ),
              ),
            ],
          ),
          if (reason != null && reason!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 92),
              child: Text(
                reason!,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
