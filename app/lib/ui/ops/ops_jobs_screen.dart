import 'package:fade_call/core/format.dart';
import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/api_exception.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/router.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/ops/ops_common.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:fade_call/ui/widgets/evidence_view.dart';
import 'package:fade_call/ui/widgets/fade_app_bar.dart';
import 'package:fade_call/ui/widgets/job_timeline.dart';
import 'package:fade_call/ui/widgets/job_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The job filters on the operator jobs page, in display order.
enum JobFilter {
  needsReview('Needs review', {JobStatus.needsReview}),
  all('All', {}),
  booked('Booked', {JobStatus.booked}),
  confirmed('Confirmed', {JobStatus.confirmed}),
  inProgress('In progress', {JobStatus.inProgress, JobStatus.verifying}),
  verified('Verified', {JobStatus.verified}),
  failed('Failed', {JobStatus.failed}),
  cancelled('Cancelled', {JobStatus.cancelled});

  const JobFilter(this.label, this.statuses);
  final String label;
  final Set<JobStatus> statuses;

  bool matches(Job j) => statuses.isEmpty || statuses.contains(j.status);
}

/// Filters [jobs] by status chip and a free-text search over barber, client,
/// cut and address.
List<Job> filterJobs(List<Job> jobs, JobFilter filter, String query) {
  final q = query.trim().toLowerCase();
  return [
    for (final j in jobs)
      if (filter.matches(j) &&
          (q.isEmpty ||
              j.barber.name.toLowerCase().contains(q) ||
              j.client.name.toLowerCase().contains(q) ||
              j.cut.toLowerCase().contains(q) ||
              j.address.toLowerCase().contains(q)))
        j,
  ];
}

class OpsJobsScreen extends ConsumerStatefulWidget {
  const OpsJobsScreen({super.key});

  @override
  ConsumerState<OpsJobsScreen> createState() => _OpsJobsScreenState();
}

class _OpsJobsScreenState extends ConsumerState<OpsJobsScreen> {
  JobFilter _filter = JobFilter.needsReview;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jobs = ref.watch(opsJobsProvider);
    return Scaffold(
      appBar: const FadeAppBar(title: 'Jobs'),
      body: AsyncView(
        value: jobs,
        onRetry: () => ref.invalidate(opsJobsProvider),
        builder: (all) {
          final shown = filterJobs(all, _filter, _search.text);
          return PageList(
            maxWidth: opsMaxWidth,
            onRefresh: () => ref.refresh(opsJobsProvider.future),
            children: [
              TextField(
                key: const ValueKey('jobs-search'),
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search barber, client, cut or address',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () => setState(_search.clear),
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
              const SizedBox(height: Gap.md),
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                children: [
                  for (final f in JobFilter.values)
                    FilterChip(
                      key: ValueKey('filter-${f.name}'),
                      label: Text(
                        '${f.label} · ${all.where(f.matches).length}',
                      ),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                ],
              ),
              const SizedBox(height: Gap.md),
              if (shown.isEmpty)
                MessageView(
                  icon: _filter == JobFilter.needsReview
                      ? Icons.task_alt_rounded
                      : Icons.search_off_rounded,
                  title:
                      _filter == JobFilter.needsReview && _search.text.isEmpty
                      ? 'All clear'
                      : 'No matching jobs',
                  message:
                      _filter == JobFilter.needsReview && _search.text.isEmpty
                      ? 'No job is waiting for a decision.'
                      : 'Try another filter or search.',
                )
              else
                for (final j in shown) ...[
                  JobListCard(
                    job: j,
                    counterpart: '${j.barber.name} → ${j.client.name}',
                    onTap: () => context.go(Routes.opsJob(j.id)),
                  ),
                  const SizedBox(height: Gap.sm + 4),
                ],
            ],
          );
        },
      ),
    );
  }
}

/// One job for the operator: header, decision (when it needs review),
/// evidence with the compare slider, and timeline.
class OpsJobScreen extends ConsumerWidget {
  const OpsJobScreen({required this.jobId, super.key});

  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(jobProvider(jobId));
    return Scaffold(
      appBar: const FadeAppBar(title: 'Job'),
      body: AsyncView(
        value: job,
        onRetry: () => ref.invalidate(jobProvider(jobId)),
        builder: (j) => PageList(
          maxWidth: opsMaxWidth,
          onRefresh: () => ref.refresh(jobProvider(jobId).future),
          children: [
            ReviewJobCard(job: j),
            const SectionHeader(title: 'Progress'),
            Panel(child: JobTimeline(job: j)),
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
    final api = ref.read(apiProvider);
    setState(() {
      _demo = value;
      _savingDemo = true;
    });
    try {
      final job = await api.setConsentedDemo(widget.job.id, value: value);
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
    // Capture before awaiting: the screen may close while the call runs.
    final container = ProviderScope.containerOf(context, listen: false);
    final api = container.read(apiProvider);
    setState(() => _busy = true);
    try {
      await api.opsVerdict(widget.job.id, pass: pass, reason: reason);
      refreshOpsIn(container);
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
    final canDecide = j.status == JobStatus.needsReview;
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        JobHeaderCard(
          job: j,
          counterpart: '${j.barber.name} → ${j.client.name}',
        ),
        const SizedBox(height: Gap.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('view-barber'),
            onPressed: () => context.go(Routes.opsBarber(j.barber.id)),
            icon: const Icon(Icons.badge_outlined),
            label: Text('View ${j.barber.name}'),
          ),
        ),
        if (canDecide) ...[
          const SizedBox(height: Gap.sm),
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
        ],
        if (j.evidence != null) ...[
          const SizedBox(height: Gap.md),
          Panel(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.md,
              vertical: 4,
            ),
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
      ],
    );
    final evidence = switch (j.evidence) {
      final e? => EvidenceView(
        evidence: e,
        compareByDefault: true,
        onExpired: () => ref.invalidate(jobProvider(j.id)),
      ),
      null => Callout(
        text: j.status == JobStatus.cancelled
            ? 'Cancelled before any proof photos.'
            : 'No proof photos yet. Slot ${formatSlot(j.slotStart)}.',
      ),
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

/// A compact job row for lists that already show the barber (detail page).
class OpsJobRow extends StatelessWidget {
  const OpsJobRow({required this.job, super.key});

  final Job job;

  @override
  Widget build(BuildContext context) => JobListCard(
    job: job,
    counterpart: job.client.name,
    onTap: () => context.go(Routes.opsJob(job.id)),
  );
}
