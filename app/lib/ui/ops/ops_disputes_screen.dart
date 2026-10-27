import 'package:fade_call/core/format.dart';
import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/api_exception.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/ops/ops_common.dart';
import 'package:fade_call/ui/widgets/badges.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:fade_call/ui/widgets/evidence_view.dart';
import 'package:fade_call/ui/widgets/fade_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OpsDisputesScreen extends ConsumerWidget {
  const OpsDisputesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disputes = ref.watch(disputesProvider);
    return Scaffold(
      appBar: const FadeAppBar(title: 'Disputes'),
      body: AsyncView(
        value: disputes,
        onRetry: () => ref.invalidate(disputesProvider),
        isEmpty: (l) => l.isEmpty,
        empty: const MessageView(
          icon: Icons.sentiment_satisfied_alt_rounded,
          title: 'No disputes',
          message: 'Client voice complaints show up here as case summaries.',
        ),
        builder: (list) {
          final sorted = [...list]
            ..sort((a, b) => (a.isOpen ? 0 : 1).compareTo(b.isOpen ? 0 : 1));
          return PageList(
            maxWidth: opsMaxWidth,
            onRefresh: () => ref.refresh(disputesProvider.future),
            children: [
              for (final d in sorted) ...[
                _DisputeCard(dispute: d),
                const SizedBox(height: Gap.lg),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DisputeCard extends ConsumerStatefulWidget {
  const _DisputeCard({required this.dispute});

  final Dispute dispute;

  @override
  ConsumerState<_DisputeCard> createState() => _DisputeCardState();
}

class _DisputeCardState extends ConsumerState<_DisputeCard> {
  late DisputeOutcome _outcome =
      widget.dispute.suggestedOutcome ?? DisputeOutcome.partialRefund;
  bool _busy = false;
  bool _showTranscript = false;
  bool _showEvidence = false;

  Future<void> _resolve() async {
    final reason = await askReason(
      context,
      title: 'Resolve: ${_outcome.label}',
      confirmLabel: 'Resolve',
      hint: 'Reason, shared with both sides',
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(apiProvider)
          .resolveDispute(widget.dispute.id, outcome: _outcome, reason: reason);
      refreshOps(ref);
      if (mounted) showSnack(context, 'Dispute resolved.');
    } on Object catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dispute;
    final job = d.job;
    return Panel(
      padding: const EdgeInsets.all(Gap.lg - 4),
      borderColor: d.isOpen ? context.status.review : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  job == null
                      ? 'Job ${d.jobId.substring(0, d.jobId.length.clamp(0, 8))}'
                      : '${job.cut} · ${job.barber.name} → ${job.client.name}',
                  style: context.text.titleMedium,
                ),
              ),
              StatusPill(
                label: d.isOpen ? 'Open' : 'Resolved: ${d.outcome!.label}',
                tone: d.isOpen ? Tone.review : Tone.pass,
              ),
            ],
          ),
          if (d.createdAt != null)
            Text(formatSlot(d.createdAt), style: context.text.bodySmall),
          if (!d.isOpen && (d.resolutionReason ?? '').isNotEmpty) ...[
            const SizedBox(height: Gap.sm),
            Callout(
              icon: Icons.gavel_rounded,
              color: context.status.pass,
              background: context.status.passContainer,
              text:
                  '${d.resolutionReason!}'
                  '${d.resolvedAt == null ? '' : ' · ${formatSlot(d.resolvedAt)}'}',
            ),
          ],
          const SectionHeader(title: 'Case summary'),
          Text(d.summary, style: context.text.bodyLarge),
          if ((d.clientClaim ?? '').isNotEmpty) ...[
            const SectionHeader(title: 'Client says'),
            Text(d.clientClaim!, style: context.text.bodyMedium),
          ],
          if ((d.evidenceNotes ?? '').isNotEmpty) ...[
            const SectionHeader(title: 'Evidence notes'),
            Text(d.evidenceNotes!, style: context.text.bodyMedium),
          ],
          if (d.suggestedOutcome != null) ...[
            const SizedBox(height: Gap.md),
            Callout(
              icon: Icons.lightbulb_outline_rounded,
              text: 'Suggested outcome: ${d.suggestedOutcome!.label}',
            ),
          ],
          const SizedBox(height: Gap.sm),
          Wrap(
            spacing: Gap.sm,
            children: [
              TextButton.icon(
                onPressed: () =>
                    setState(() => _showTranscript = !_showTranscript),
                icon: Icon(
                  _showTranscript
                      ? Icons.expand_less_rounded
                      : Icons.notes_rounded,
                ),
                label: Text(_showTranscript ? 'Hide transcript' : 'Transcript'),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _showEvidence = !_showEvidence),
                icon: Icon(
                  _showEvidence
                      ? Icons.expand_less_rounded
                      : Icons.photo_library_outlined,
                ),
                label: Text(_showEvidence ? 'Hide evidence' : 'Evidence'),
              ),
            ],
          ),
          if (_showTranscript)
            DecoratedBox(
              decoration: BoxDecoration(
                color: context.colors.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Text(
                  '“${d.transcript}”',
                  style: context.text.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          if (_showEvidence) ...[
            const SizedBox(height: Gap.md),
            _DisputeEvidence(dispute: d),
          ],
          if (d.isOpen) ...[
            const Divider(height: Gap.xl),
            Wrap(
              spacing: Gap.md,
              runSpacing: Gap.md,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<DisputeOutcome>(
                  showSelectedIcon: false,
                  segments: [
                    for (final o in DisputeOutcome.values)
                      ButtonSegment(value: o, label: Text(o.label)),
                  ],
                  selected: {_outcome},
                  onSelectionChanged: (s) => setState(() => _outcome = s.first),
                ),
                FilledButton(
                  onPressed: _busy ? null : _resolve,
                  child: const Text('Resolve'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Uses the embedded job when present, otherwise fetches it.
class _DisputeEvidence extends ConsumerWidget {
  const _DisputeEvidence({required this.dispute});

  final Dispute dispute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget evidenceFor(Job job, VoidCallback reload) => switch (job.evidence) {
      final e? => EvidenceView(evidence: e, onExpired: reload),
      null => const Callout(text: 'No proof-of-job photos for this job.'),
    };
    // Embedded URLs may have expired; always prefer a fresh fetch.
    final fresh = ref.watch(jobProvider(dispute.jobId));
    return switch (fresh) {
      AsyncData(:final value) => evidenceFor(
        value,
        () => ref.invalidate(jobProvider(dispute.jobId)),
      ),
      AsyncError() when dispute.job != null => evidenceFor(
        dispute.job!,
        () => ref.invalidate(disputesProvider),
      ),
      AsyncError(:final error) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(jobProvider(dispute.jobId)),
      ),
      _ => const LoadingView(),
    };
  }
}
