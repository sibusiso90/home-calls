import 'package:fade_call/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const opsMaxWidth = 1160.0;

/// Refreshes every operator view after an action.
void refreshOps(WidgetRef ref) {
  ref
    ..invalidate(opsSummaryProvider)
    ..invalidate(pendingBarbersProvider)
    ..invalidate(reviewJobsProvider)
    ..invalidate(disputesProvider)
    ..invalidate(payoutsProvider);
}
