import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/api_exception.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/ops/ops_common.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:fade_call/ui/widgets/evidence_view.dart';
import 'package:fade_call/ui/widgets/fade_app_bar.dart';
import 'package:fade_call/ui/widgets/job_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OpsReviewsScreen extends ConsumerWidget {
  const OpsReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(reviewJobsProvider);
    return Scaffold(
      appBar: const FadeAppBar(title: 'Jobs needing review'),
      body: AsyncView(
        value: jobs,
        onRetry: () => ref.invalidate(reviewJobsProvider),
        isEmpty: (l) => l.isEmpty,
        empty: const MessageView(
          icon: Icons.task_alt_rounded,
          title: 'All clear',
          message: 'No job is waiting for a decision.',
        ),
        builder: (list) => PageList(
          maxWidth: opsMaxWidth,
          onRefresh: () => ref.refresh(reviewJobsProvider.future),
          children: [
            for (final j in list) ...[
              ReviewJobCard(job: j),
              const SizedBox(height: Gap.xl),
            ],
          ],
        ),
      ),
    );
  }
}

/// Job header, decision buttons and the evidence, side by side when wide.
class ReviewJobCard extends ConsumerStatefulWidget {
  const ReviewJobCard({required this.job, super.key});

  final Job job;

  @override
  ConsumerState<ReviewJobCard> createState() => _ReviewJobCardState();
}

class _ReviewJobCardState extends ConsumerState<ReviewJobCard> {
  bool _busy = false;
  late bool _demo = widget.job.consentedDemo;
  bool _savingDemo = false;

  @override
  void didUpdateWidget(ReviewJobCard old) {
    super.didUpdateWidget(old);
    if (old.job.consentedDemo != widget.job.consentedDemo) {
      _demo = widget.job.consentedDemo;
    }
  }

  Future<void> _setDemo(bool value) async {
    setState(() {
      _demo = value;
      _savingDemo = true;
    });
    try {
      final job = await ref
          .read(apiProvider)
          .setConsentedDemo(widget.job.id, value: value);
      if (mounted) setState(() => _demo = job.consentedDemo);
    } on Object catch (e) {
      if (mounted) {
        setState(() => _demo = !value);
        showSnack(context, friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _savingDemo = false);
    }
  }

  Future<void> _decide({required bool pass}) async {
    final reason = await askReason(
      context,
      title: pass ? 'Pass this job?' : 'Fail this job?',
      confirmLabel: pass ? 'Pass and release payment' : 'Fail',
      hint: pass
          ? 'e.g. Same client, clear fade; GPS drift in a complex'
          : 'e.g. Different person in the after photo',
      destructive: !pass,
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(apiProvider)
          .opsVerdict(widget.job.id, pass: pass, reason: reason);
      refreshOps(ref);
      if (mounted) {
        showSnack(
          context,
          pass
              ? 'Passed. Payment released.'
              : 'Marked as failed. Payment held.',
        );
      }
    } on Object catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final j = widget.job;
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        JobHeaderCard(
          job: j,
          counterpart: '${j.barber.name} → ${j.client.name}',
        ),
        const SizedBox(height: Gap.md),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: context.status.pass),
          onPressed: _busy ? null : () => _decide(pass: true),
          icon: const Icon(Icons.verified_rounded),
          label: const Text('Pass'),
        ),
        const SizedBox(height: Gap.sm),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: context.status.fail,
            side: BorderSide(color: context.status.fail),
          ),
          onPressed: _busy ? null : () => _decide(pass: false),
          icon: const Icon(Icons.gpp_bad_outlined),
          label: const Text('Fail'),
        ),
        const SizedBox(height: Gap.md),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 4),
          child: SwitchListTile(
            key: const ValueKey('consented-demo'),
            contentPadding: EdgeInsets.zero,
            title: Text('Consented demo job', style: context.text.titleSmall),
            subtitle: Text(
              'Keep these photos after the verdict. Only with signed consent.',
              style: context.text.bodySmall,
            ),
            value: _demo,
            onChanged: _savingDemo ? null : _setDemo,
          ),
        ),
      ],
    );
    final evidence = switch (j.evidence) {
      final e? => EvidenceView(
        evidence: e,
        onExpired: () => ref.invalidate(reviewJobsProvider),
      ),
      null => const Callout(text: 'No evidence attached to this job yet.'),
    };
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth >= 900
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 340, child: summary),
                const SizedBox(width: Gap.lg),
                Expanded(child: evidence),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                summary,
                const SizedBox(height: Gap.md),
                evidence,
              ],
            ),
    );
  }
}
