import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/api_exception.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/client/dispute_section.dart';
import 'package:fade_call/ui/client/rating_section.dart';
import 'package:fade_call/ui/widgets/booking_changes.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:fade_call/ui/widgets/evidence_view.dart';
import 'package:fade_call/ui/widgets/fade_app_bar.dart';
import 'package:fade_call/ui/widgets/job_timeline.dart';
import 'package:fade_call/ui/widgets/job_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ClientJobScreen extends ConsumerWidget {
  const ClientJobScreen({
    required this.jobId,
    super.key,
    this.justBooked = false,
  });

  final String jobId;
  final bool justBooked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(jobProvider(jobId));
    return Scaffold(
      appBar: const FadeAppBar(title: 'Booking'),
      body: AsyncView(
        value: job,
        onRetry: () => ref.invalidate(jobProvider(jobId)),
        builder: (j) => PageList(
          onRefresh: () => ref.refresh(jobProvider(jobId).future),
          children: [
            if (justBooked && j.status == JobStatus.booked) ...[
              const _BookedBanner(),
              const SizedBox(height: Gap.md),
            ],
            JobHeaderCard(job: j, counterpart: 'Barber: ${j.barber.name}'),
            if (j.paymentStatus == PaymentStatus.depositPending &&
                j.status != JobStatus.cancelled) ...[
              const SizedBox(height: Gap.md),
              _DepositPanel(job: j),
            ],
            if (j.isChangeable) ...[
              const SizedBox(height: Gap.md),
              BookingChangesPanel(job: j, role: Role.client),
            ],
            if (j.evidence case final e?) ...[
              const SectionHeader(title: 'Proof of job'),
              EvidenceView(
                evidence: e,
                onExpired: () => ref.invalidate(jobProvider(jobId)),
              ),
            ],
            if (j.status != JobStatus.cancelled) ...[
              const SectionHeader(title: 'Rating'),
              RatingSection(job: j),
            ],
            if (_canDispute(j) || j.dispute != null) ...[
              const SectionHeader(title: 'Problem with this job?'),
              DisputeSection(job: j),
            ],
            const SectionHeader(title: 'Progress'),
            Panel(child: JobTimeline(job: j)),
          ],
        ),
      ),
    );
  }

  static bool _canDispute(Job j) => switch (j.status) {
    JobStatus.inProgress ||
    JobStatus.verifying ||
    JobStatus.verified ||
    JobStatus.needsReview ||
    JobStatus.failed => true,
    _ => false,
  };
}

class _BookedBanner extends StatelessWidget {
  const _BookedBanner();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Palette.forest, Palette.forestDeep],
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.all(Gap.lg - 4),
      child: Row(
        children: [
          const Icon(Icons.celebration_rounded, color: Palette.brass, size: 32),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "You're booked",
                  style: context.text.titleLarge?.copyWith(
                    color: Palette.cream,
                  ),
                ),
                Text(
                  'We have let your barber know. Pay the deposit to hold the slot.',
                  style: context.text.bodyMedium?.copyWith(
                    color: Palette.cream.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _DepositPanel extends ConsumerStatefulWidget {
  const _DepositPanel({required this.job});

  final Job job;

  @override
  ConsumerState<_DepositPanel> createState() => _DepositPanelState();
}

class _DepositPanelState extends ConsumerState<_DepositPanel> {
  bool _paying = false;

  Future<void> _pay() async {
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _paying = true);
    try {
      await container.read(apiProvider).payDeposit(widget.job.id);
      refreshJobIn(container, widget.job.id);
      if (mounted) {
        showSnack(context, 'Deposit paid (mock). Your slot is held.');
      }
    } on Object catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) => Panel(
    borderColor: Palette.brass,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Deposit', style: context.text.titleMedium),
        const SizedBox(height: Gap.xs),
        Text(
          'Payments are mocked for the demo. No money moves.',
          style: context.text.bodySmall,
        ),
        if (widget.job.depositUrl case final url?) ...[
          const SizedBox(height: Gap.sm),
          SelectableText(
            url,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        ],
        const SizedBox(height: Gap.md),
        FilledButton.icon(
          onPressed: _paying ? null : _pay,
          icon: const Icon(Icons.lock_rounded),
          label: const Text('Pay deposit (mock)'),
        ),
      ],
    ),
  );
}
