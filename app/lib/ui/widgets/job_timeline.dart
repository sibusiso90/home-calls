import 'package:fade_call/core/format.dart';
import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:flutter/material.dart';

/// Booked → Confirmed → In progress → Verifying → Verified (or review/failed),
/// with cancellation and reschedule details.
class JobTimeline extends StatelessWidget {
  const JobTimeline({required this.job, super.key});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final status = job.status;
    if (status == JobStatus.cancelled) {
      final who = switch (job.cancelledBy) {
        'client' => 'the client',
        'barber' => 'the barber',
        _ => null,
      };
      return Column(
        key: const ValueKey('timeline-cancelled'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_busy_rounded, color: context.status.fail),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  who == null ? 'Cancelled' : 'Cancelled by $who',
                  style: context.text.titleSmall?.copyWith(
                    color: context.status.fail,
                  ),
                ),
              ),
            ],
          ),
          if (job.cancelledAt != null)
            Text(formatSlot(job.cancelledAt), style: context.text.labelSmall),
          if ((job.cancelReason ?? '').isNotEmpty) ...[
            const SizedBox(height: Gap.xs),
            Text('“${job.cancelReason}”', style: context.text.bodyMedium),
          ],
          const SizedBox(height: Gap.xs),
          Text(switch (job.paymentStatus) {
            PaymentStatus.refunded => 'The deposit is refunded.',
            PaymentStatus.forfeited =>
              'The deposit is kept (cancelled less than 2 hours before the slot).',
            _ => 'No deposit was paid.',
          }, style: context.text.bodySmall),
        ],
      );
    }
    final steps = [...JobStatus.timeline];
    final terminal = switch (status) {
      JobStatus.needsReview => JobStatus.needsReview,
      JobStatus.failed => JobStatus.failed,
      _ => JobStatus.verified,
    };
    steps[steps.length - 1] = terminal;
    final current = switch (status) {
      JobStatus.needsReview || JobStatus.failed => steps.length - 1,
      _ => steps.indexOf(status),
    };
    final endColor = switch (status) {
      JobStatus.needsReview => context.status.review,
      JobStatus.failed => context.status.fail,
      _ => context.status.pass,
    };

    return Column(
      children: [
        if (job.rescheduledAt != null)
          Padding(
            key: const ValueKey('timeline-rescheduled'),
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: Row(
              children: [
                const Icon(
                  Icons.update_rounded,
                  size: 18,
                  color: Palette.brass,
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    'Rescheduled ${formatSlot(job.rescheduledAt)} to '
                    '${formatSlot(job.slotStart)}',
                    style: context.text.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        for (var i = 0; i < steps.length; i++)
          _Step(
            label: steps[i].label,
            done: i < current || (i == current && i == steps.length - 1),
            active: i == current,
            last: i == steps.length - 1,
            color: i == steps.length - 1 ? endColor : context.colors.primary,
          ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.label,
    required this.done,
    required this.active,
    required this.last,
    required this.color,
  });

  final String label;
  final bool done;
  final bool active;
  final bool last;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.outlineVariant;
    final dotColor = done || active ? color : muted;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: done ? dotColor : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: dotColor, width: 2.5),
                  ),
                  child: SizedBox.square(
                    dimension: 18,
                    child: done
                        ? const Icon(Icons.check, size: 12, color: Colors.white)
                        : null,
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(width: 2, color: done ? color : muted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Gap.sm + 4),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : Gap.md),
              child: Text(
                label,
                style: context.text.bodyMedium?.copyWith(
                  fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                  color: done || active
                      ? context.colors.onSurface
                      : context.colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
