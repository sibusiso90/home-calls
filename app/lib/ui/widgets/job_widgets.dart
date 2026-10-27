import 'package:fade_call/core/format.dart';
import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/ui/widgets/badges.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:flutter/material.dart';

/// A job in a list.
class JobListCard extends StatelessWidget {
  const JobListCard({
    required this.job,
    required this.counterpart,
    required this.onTap,
    super.key,
  });

  final Job job;

  /// The other party's name: the client for barbers, the barber for clients.
  final String counterpart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Panel(
    onTap: onTap,
    child: Row(
      children: [
        _DateBlock(time: job.slotStart),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                job.cut.isEmpty ? 'Haircut' : job.cut,
                style: context.text.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '$counterpart · ${formatTime(job.slotStart)} · ${rand(job.quoteZar)}',
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: Gap.sm),
              StatusPill.job(job.status),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, color: context.colors.outline),
      ],
    ),
  );
}

class _DateBlock extends StatelessWidget {
  const _DateBlock({required this.time});

  final DateTime? time;

  @override
  Widget build(BuildContext context) {
    final t = time?.toLocal();
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return Container(
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: Gap.sm),
      decoration: BoxDecoration(
        color: Palette.forest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            t == null ? '—' : months[t.month - 1],
            style: context.text.labelSmall?.copyWith(
              color: Palette.brass,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          Text(
            t == null ? '' : '${t.day}',
            style: context.text.headlineSmall?.copyWith(color: Palette.cream),
          ),
        ],
      ),
    );
  }
}

/// The header card on a job detail screen.
class JobHeaderCard extends StatelessWidget {
  const JobHeaderCard({
    required this.job,
    required this.counterpart,
    super.key,
  });

  final Job job;
  final String counterpart;

  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.all(Gap.lg - 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                job.cut.isEmpty ? 'Haircut' : job.cut,
                style: context.text.headlineSmall,
              ),
            ),
            const SizedBox(width: Gap.sm),
            StatusPill.job(job.status),
          ],
        ),
        const SizedBox(height: Gap.md),
        DetailLine(icon: Icons.person_outline_rounded, text: counterpart),
        DetailLine(
          icon: Icons.event_rounded,
          text: formatSlotRange(job.slotStart, job.slotEnd),
        ),
        DetailLine(icon: Icons.place_outlined, text: job.address),
        DetailLine(
          icon: Icons.timer_outlined,
          text:
              '${job.minutes} min'
              '${job.travelBand == null ? '' : ' · travel band ${job.travelBand}'}',
        ),
        const SizedBox(height: Gap.md),
        Row(
          children: [
            Text(
              rand(job.quoteZar),
              style: context.text.headlineSmall?.copyWith(
                color: context.colors.primary,
              ),
            ),
            const Spacer(),
            if (job.status == JobStatus.cancelled &&
                job.paymentStatus == PaymentStatus.depositPending)
              const StatusPill(label: 'No deposit', tone: Tone.neutral)
            else
              StatusPill.payment(job.paymentStatus),
          ],
        ),
      ],
    ),
  );
}
