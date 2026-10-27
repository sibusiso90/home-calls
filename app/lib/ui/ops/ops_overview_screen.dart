import 'package:fade_call/core/format.dart';
import 'package:fade_call/core/theme.dart';
import 'package:fade_call/router.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/ops/ops_common.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:fade_call/ui/widgets/fade_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class OpsOverviewScreen extends ConsumerWidget {
  const OpsOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(opsSummaryProvider);
    return Scaffold(
      appBar: FadeAppBar(
        title: 'Operator',
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => refreshOps(ref),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: AsyncView(
        value: summary,
        onRetry: () => ref.invalidate(opsSummaryProvider),
        builder: (s) => PageList(
          maxWidth: opsMaxWidth,
          onRefresh: () => ref.refresh(opsSummaryProvider.future),
          children: [
            Text('Today at a glance', style: context.text.headlineMedium),
            const SizedBox(height: Gap.xs),
            Text(
              'Every payout and rating waits on a verified job. These need you.',
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Gap.lg),
            LayoutBuilder(
              builder: (context, c) {
                final columns = c.maxWidth >= 900
                    ? 4
                    : c.maxWidth >= 520
                    ? 2
                    : 1;
                final width = (c.maxWidth - Gap.md * (columns - 1)) / columns;
                final tiles = [
                  _Tile(
                    label: 'Barbers awaiting approval',
                    value: '${s.barbersPending}',
                    icon: Icons.how_to_reg_rounded,
                    attention: s.barbersPending > 0,
                    onTap: () => context.go(Routes.opsBarbers),
                  ),
                  _Tile(
                    label: 'Jobs needing review',
                    value: '${s.jobsNeedsReview}',
                    icon: Icons.fact_check_rounded,
                    attention: s.jobsNeedsReview > 0,
                    onTap: () => context.go(Routes.opsReviews),
                  ),
                  _Tile(
                    label: 'Open disputes',
                    value: '${s.openDisputes}',
                    icon: Icons.record_voice_over_rounded,
                    attention: s.openDisputes > 0,
                    onTap: () => context.go(Routes.opsDisputes),
                  ),
                  _Tile(
                    label: 'Payouts released',
                    value: rand(s.payoutsReleasedZar),
                    icon: Icons.payments_rounded,
                    onTap: () => context.go(Routes.opsPayouts),
                  ),
                ];
                return Wrap(
                  spacing: Gap.md,
                  runSpacing: Gap.md,
                  children: [
                    for (final t in tiles) SizedBox(width: width, child: t),
                  ],
                );
              },
            ),
            const SectionHeader(title: 'The rule'),
            const Callout(
              icon: Icons.gavel_rounded,
              text:
                  'A job passes only when every check passes. Anything uncertain '
                  'comes to you. Your verdict, with its reason, is final and is '
                  'the only other way to release a payout or unlock a rating.',
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.attention = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final bool attention;

  @override
  Widget build(BuildContext context) {
    final dark = attention;
    return Semantics(
      button: true,
      label: '$label: $value',
      child: Material(
        color: dark ? Palette.forest : Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(Gap.lg - 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: dark ? Palette.forest : Palette.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: Palette.brass),
                    const Spacer(),
                    Icon(
                      Icons.arrow_outward_rounded,
                      size: 18,
                      color: dark ? Palette.cream : Palette.ink,
                    ),
                  ],
                ),
                const SizedBox(height: Gap.lg),
                Text(
                  value,
                  style: context.text.displaySmall?.copyWith(
                    color: dark ? Palette.cream : Palette.charcoal,
                  ),
                ),
                Text(
                  label,
                  style: context.text.bodyMedium?.copyWith(
                    color: dark
                        ? Palette.cream.withValues(alpha: 0.8)
                        : Palette.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
