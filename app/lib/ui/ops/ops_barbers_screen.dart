import 'package:fade_call/core/format.dart';
import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/api_exception.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/router.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/ops/ops_common.dart';
import 'package:fade_call/ui/widgets/badges.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:fade_call/ui/widgets/fade_app_bar.dart';
import 'package:fade_call/ui/widgets/portfolio_scores.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _BarberTab { pending, all }

class OpsBarbersScreen extends ConsumerStatefulWidget {
  const OpsBarbersScreen({super.key});

  @override
  ConsumerState<OpsBarbersScreen> createState() => _OpsBarbersScreenState();
}

class _OpsBarbersScreenState extends ConsumerState<OpsBarbersScreen> {
  _BarberTab _tab = _BarberTab.pending;

  @override
  Widget build(BuildContext context) {
    final pending = _tab == _BarberTab.pending;
    final provider = pending ? pendingBarbersProvider : allBarbersProvider;
    final barbers = ref.watch(provider);
    final toggle = Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<_BarberTab>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: _BarberTab.pending,
              label: Text('Awaiting approval'),
            ),
            ButtonSegment(value: _BarberTab.all, label: Text('All barbers')),
          ],
          selected: {_tab},
          onSelectionChanged: (s) => setState(() => _tab = s.first),
        ),
      ),
    );
    return Scaffold(
      appBar: const FadeAppBar(title: 'Barbers'),
      body: AsyncView(
        value: barbers,
        onRetry: () => ref.invalidate(provider),
        builder: (list) => PageList(
          maxWidth: opsMaxWidth,
          onRefresh: () => ref.refresh(provider.future),
          children: [
            toggle,
            if (list.isEmpty)
              MessageView(
                icon: Icons.how_to_reg_outlined,
                title: pending ? 'No one waiting' : 'No barbers yet',
                message: pending
                    ? 'Graded barbers show up here for approval.'
                    : null,
              )
            else if (pending)
              for (final b in list) ...[
                _PendingBarberCard(barber: b),
                const SizedBox(height: Gap.lg),
              ]
            else
              for (final b in list) ...[
                _BarberRow(barber: b),
                const SizedBox(height: Gap.sm),
              ],
          ],
        ),
      ),
    );
  }
}

class _BarberRow extends StatelessWidget {
  const _BarberRow({required this.barber});

  final Barber barber;

  @override
  Widget build(BuildContext context) {
    final b = barber;
    return Panel(
      onTap: () => context.go(Routes.opsBarber(b.id)),
      child: Row(
        children: [
          Monogram(name: b.name),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: Gap.sm,
                  runSpacing: Gap.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(b.name, style: context.text.titleMedium),
                    TierBadge(tier: b.tier),
                  ],
                ),
                Text(
                  [
                    b.areaName ?? 'No area',
                    '${b.verifiedJobs} verified',
                    '★ ${formatRating(b.rating)}',
                  ].join(' · '),
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
          StatusPill.barber(b.status),
          Icon(Icons.chevron_right_rounded, color: context.colors.outline),
        ],
      ),
    );
  }
}

class _PendingBarberCard extends ConsumerStatefulWidget {
  const _PendingBarberCard({required this.barber});

  final Barber barber;

  @override
  ConsumerState<_PendingBarberCard> createState() => _PendingBarberCardState();
}

class _PendingBarberCardState extends ConsumerState<_PendingBarberCard> {
  bool _busy = false;

  Future<void> _decide({required bool approve}) async {
    final reason = await askReason(
      context,
      title: approve
          ? 'Approve ${widget.barber.name}?'
          : 'Reject ${widget.barber.name}?',
      confirmLabel: approve ? 'Approve' : 'Reject',
      hint: approve
          ? 'e.g. Portfolio consistent, verified in person'
          : 'What should they fix?',
      destructive: !approve,
    );
    if (reason == null || !mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final api = container.read(apiProvider);
    setState(() => _busy = true);
    try {
      approve
          ? await api.approveBarber(widget.barber.id, reason: reason)
          : await api.rejectBarber(widget.barber.id, reason: reason);
      refreshOpsIn(container);
      if (mounted) {
        showSnack(
          context,
          '${widget.barber.name} ${approve ? 'approved' : 'rejected'}.',
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
    final b = widget.barber;
    final avg = b.portfolio.isEmpty
        ? null
        : b.portfolio.map((p) => p.overall).reduce((a, c) => a + c) /
              b.portfolio.length;
    return Panel(
      padding: const EdgeInsets.all(Gap.lg - 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: Gap.md,
            runSpacing: Gap.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Monogram(name: b.name, size: 52),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(b.name, style: context.text.titleLarge),
                      const SizedBox(width: Gap.sm),
                      TierBadge(tier: b.tier),
                    ],
                  ),
                  Text(
                    [
                      b.areaName ?? 'No area',
                      if (b.yearsCutting != null) '${b.yearsCutting} yrs',
                      if (b.languages.isNotEmpty) b.languages.join(', '),
                    ].join(' · '),
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          Wrap(
            spacing: Gap.lg,
            runSpacing: Gap.sm,
            children: [
              Stat(
                label: 'Portfolio average',
                value: avg == null ? '—' : avg.toStringAsFixed(1),
              ),
              Stat(
                label: 'Price band',
                value: switch (b.priceBand) {
                  final p? => randRange(p.minZar, p.maxZar),
                  null => '—',
                },
              ),
              Stat(label: 'Pairs', value: '${b.portfolio.length}'),
            ],
          ),
          if (b.styles.isNotEmpty) ...[
            const SizedBox(height: Gap.md),
            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.sm,
              children: [for (final s in b.styles) Chip(label: Text(s))],
            ),
          ],
          const SizedBox(height: Gap.md),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              TextButton.icon(
                onPressed: () => context.go(Routes.opsBarber(widget.barber.id)),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Details'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.status.fail,
                  side: BorderSide(color: context.status.fail),
                ),
                onPressed: _busy ? null : () => _decide(approve: false),
                icon: const Icon(Icons.close_rounded),
                label: const Text('Reject'),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : () => _decide(approve: true),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Approve'),
              ),
            ],
          ),
          const SectionHeader(title: 'Portfolio scores'),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 1000
                  ? 3
                  : c.maxWidth >= 640
                  ? 2
                  : 1;
              final w = (c.maxWidth - Gap.md * (cols - 1)) / cols;
              return Wrap(
                spacing: Gap.md,
                runSpacing: Gap.md,
                children: [
                  for (final (i, item) in b.portfolio.indexed)
                    SizedBox(
                      width: w,
                      child: PortfolioCard(
                        item: item,
                        index: i,
                        onExpired: () => ref.invalidate(pendingBarbersProvider),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
