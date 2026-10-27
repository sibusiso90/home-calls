import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/api_exception.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/router.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/widgets/booking_changes.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:fade_call/ui/widgets/evidence_view.dart';
import 'package:fade_call/ui/widgets/fade_app_bar.dart';
import 'package:fade_call/ui/widgets/job_timeline.dart';
import 'package:fade_call/ui/widgets/job_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class BarberJobScreen extends ConsumerStatefulWidget {
  const BarberJobScreen({required this.jobId, super.key});

  final String jobId;

  @override
  ConsumerState<BarberJobScreen> createState() => _BarberJobScreenState();
}

class _BarberJobScreenState extends ConsumerState<BarberJobScreen> {
  bool _busy = false;

  Future<void> _confirm() async {
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _busy = true);
    try {
      await container.read(apiProvider).confirmJob(widget.jobId);
      refreshJobIn(container, widget.jobId);
      if (mounted) {
        showSnack(context, 'Job confirmed. The client has been told.');
      }
    } on Object catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _capture({required bool after}) async {
    final container = ProviderScope.containerOf(context, listen: false);
    await context.push<bool>(Routes.proof(widget.jobId, after: after));
    refreshJobIn(container, widget.jobId);
  }

  @override
  Widget build(BuildContext context) {
    final job = ref.watch(jobProvider(widget.jobId));
    return Scaffold(
      appBar: const FadeAppBar(title: 'Job'),
      body: AsyncView(
        value: job,
        onRetry: () => ref.invalidate(jobProvider(widget.jobId)),
        builder: (j) => PageList(
          onRefresh: () => ref.refresh(jobProvider(widget.jobId).future),
          children: [
            JobHeaderCard(job: j, counterpart: 'Client: ${j.client.name}'),
            const SizedBox(height: Gap.md),
            _ActionPanel(
              job: j,
              busy: _busy,
              onConfirm: _confirm,
              onCapture: _capture,
            ),
            if (j.evidence case final e?) ...[
              const SectionHeader(title: 'Proof of job'),
              EvidenceView(
                evidence: e,
                onExpired: () => ref.invalidate(jobProvider(widget.jobId)),
              ),
            ],
            if (j.isChangeable) ...[
              const SizedBox(height: Gap.md),
              BookingChangesPanel(job: j, role: Role.barber),
            ],
            const SectionHeader(title: 'Progress'),
            Panel(child: JobTimeline(job: j)),
          ],
        ),
      ),
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.job,
    required this.busy,
    required this.onConfirm,
    required this.onCapture,
  });

  final Job job;
  final bool busy;
  final VoidCallback onConfirm;
  final Future<void> Function({required bool after}) onCapture;

  @override
  Widget build(BuildContext context) {
    final (title, body, label, icon, action) = switch (job.status) {
      JobStatus.booked => (
        'New booking',
        'Confirm you can make this slot. The client is notified straight away.',
        'Confirm job',
        Icons.check_circle_outline_rounded,
        onConfirm,
      ),
      JobStatus.confirmed => (
        'At the door: before photo',
        'When you arrive, take a live photo of the client before you start. '
            'Time and GPS are recorded at the shutter.',
        'Capture before photo',
        Icons.photo_camera_rounded,
        () => onCapture(after: false),
      ),
      JobStatus.inProgress => (
        'After the cut: after photo',
        'Take the after photo from a similar angle. We then check it is the '
            'same person, the hair changed and the cut matches the order.',
        'Capture after photo',
        Icons.photo_camera_rounded,
        () => onCapture(after: true),
      ),
      _ => (null, null, null, null, null),
    };
    if (title == null) return const SizedBox.shrink();
    // The backend refuses proof until the client has paid the deposit.
    final waitingForDeposit =
        job.status == JobStatus.confirmed &&
        job.paymentStatus == PaymentStatus.depositPending;
    return Panel(
      borderColor: Palette.brass,
      color: Palette.brassSoft.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: context.text.titleMedium),
          const SizedBox(height: Gap.xs),
          Text(body!, style: context.text.bodyMedium),
          const SizedBox(height: Gap.md),
          FilledButton.icon(
            onPressed: busy || waitingForDeposit ? null : action,
            icon: Icon(icon),
            label: Text(label!),
          ),
          if (waitingForDeposit) ...[
            const SizedBox(height: Gap.sm),
            Row(
              key: const ValueKey('waiting-deposit'),
              children: [
                Icon(
                  Icons.hourglass_top_rounded,
                  size: 18,
                  color: context.status.review,
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    "Waiting for the client's deposit",
                    style: context.text.bodyMedium?.copyWith(
                      color: context.status.review,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
