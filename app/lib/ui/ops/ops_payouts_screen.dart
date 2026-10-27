import 'package:fade_call/core/format.dart';
import 'package:fade_call/core/theme.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/ops/ops_common.dart';
import 'package:fade_call/ui/widgets/badges.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:fade_call/ui/widgets/fade_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OpsPayoutsScreen extends ConsumerWidget {
  const OpsPayoutsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payouts = ref.watch(payoutsProvider);
    return Scaffold(
      appBar: const FadeAppBar(title: 'Payouts'),
      body: AsyncView(
        value: payouts,
        onRetry: () => ref.invalidate(payoutsProvider),
        isEmpty: (l) => l.isEmpty,
        empty: const MessageView(
          icon: Icons.account_balance_wallet_outlined,
          title: 'No payouts yet',
          message: 'A payout is added only when a job is verified.',
        ),
        builder: (list) {
          final total = list
              .where((p) => p.status == 'released')
              .fold<int>(0, (sum, p) => sum + p.amountZar);
          return PageList(
            maxWidth: opsMaxWidth,
            onRefresh: () => ref.refresh(payoutsProvider.future),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Mock ledger', style: context.text.headlineSmall),
                        Text(
                          'One row per verified job. No real money moves.',
                          style: context.text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Stat(label: 'Released', value: rand(total)),
                ],
              ),
              const SizedBox(height: Gap.md),
              Panel(
                padding: EdgeInsets.zero,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingTextStyle: context.text.labelLarge,
                    columns: const [
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Barber')),
                      DataColumn(label: Text('Job')),
                      DataColumn(label: Text('Amount'), numeric: true),
                      DataColumn(label: Text('Status')),
                    ],
                    rows: [
                      for (final p in list)
                        DataRow(
                          cells: [
                            DataCell(Text(formatSlot(p.createdAt))),
                            DataCell(Text(p.barberName)),
                            DataCell(
                              Text(
                                p.jobId.length > 8
                                    ? p.jobId.substring(0, 8)
                                    : p.jobId,
                                style: context.text.bodySmall?.copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                            DataCell(Text(rand(p.amountZar))),
                            DataCell(
                              StatusPill(
                                label: p.status.isEmpty
                                    ? '—'
                                    : '${p.status[0].toUpperCase()}${p.status.substring(1)}',
                                tone: switch (p.status) {
                                  'released' => Tone.pass,
                                  'reversed' => Tone.fail,
                                  _ => Tone.review,
                                },
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
