import 'package:fade_call/core/format.dart';
import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/ui/widgets/badges.dart';
import 'package:flutter/material.dart';

/// One proof-of-job check: result icon, label, model reason and confidence.
class CheckRow extends StatelessWidget {
  const CheckRow({required this.label, required this.check, super.key});

  final String label;

  /// Null while the check has not run yet (e.g. after checks before the
  /// after photo is in).
  final EvidenceCheck? check;

  @override
  Widget build(BuildContext context) {
    final c = check;
    final (tone, icon, word) = switch (c?.result) {
      CheckResult.pass => (Tone.pass, Icons.check_circle_rounded, 'Pass'),
      CheckResult.fail => (Tone.fail, Icons.cancel_rounded, 'Fail'),
      CheckResult.uncertain => (Tone.review, Icons.help_rounded, 'Uncertain'),
      null => (Tone.neutral, Icons.schedule_rounded, 'Pending'),
    };
    final (fg, _) = context.toneColors(tone);
    final extras = [
      if (c?.confidence case final conf?) 'Confidence ${formatPercent(conf)}',
      if (c?.changeRatio case final ratio?) 'Change ${formatPercent(ratio)}',
      if (c?.distanceM case final d? when !(c?.reason.contains(' m ') ?? false))
        '${d.round()} m from address',
    ];
    return Semantics(
      label: '$label: $word',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.sm + 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: fg, size: 24),
            const SizedBox(width: Gap.sm + 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(label, style: context.text.titleSmall),
                      ),
                      Text(
                        word,
                        style: context.text.labelMedium?.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  if (c != null && c.reason.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      c.reason,
                      style: context.text.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (extras.isNotEmpty) ...[
                    const SizedBox(height: Gap.xs),
                    Wrap(
                      spacing: Gap.xs,
                      runSpacing: Gap.xs,
                      children: [
                        for (final e in extras)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: context.colors.surfaceContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              child: Text(e, style: context.text.labelSmall),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
