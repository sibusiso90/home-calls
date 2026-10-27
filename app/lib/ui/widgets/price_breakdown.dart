import 'package:fade_call/core/format.dart';
import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:flutter/material.dart';

/// Tier rate + time + travel = total.
class PriceBreakdown extends StatelessWidget {
  const PriceBreakdown({
    required this.price,
    super.key,
    this.tier,
    this.minutes,
    this.travelBand,
    this.distanceKm,
  });

  final PriceQuote price;
  final Tier? tier;
  final int? minutes;
  final String? travelBand;
  final double? distanceKm;

  @override
  Widget build(BuildContext context) {
    final travelDetail = [
      if (travelBand != null && travelBand!.isNotEmpty) 'band $travelBand',
      if (distanceKm != null) formatKm(distanceKm!),
    ].join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Line(
          label: '${tier?.label ?? 'Tier'} rate',
          amount: price.tierRateZar,
        ),
        _Line(
          label: minutes == null ? 'Time' : 'Time ($minutes min)',
          amount: price.timeZar,
        ),
        _Line(
          label: travelDetail.isEmpty ? 'Travel' : 'Travel ($travelDetail)',
          amount: price.travelZar,
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: Gap.xs + 2),
          child: Divider(),
        ),
        Row(
          children: [
            Expanded(child: Text('Total', style: context.text.titleMedium)),
            Text(
              rand(price.totalZar),
              key: const ValueKey('price-total'),
              style: context.text.titleLarge?.copyWith(
                color: context.colors.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.amount});

  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: context.text.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          rand(amount),
          style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}
