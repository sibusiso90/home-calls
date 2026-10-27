import 'package:fade_call/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const opsMaxWidth = 1160.0;

/// Refreshes every operator view after an action.
void refreshOps(WidgetRef ref) =>
    refreshOpsIn(ProviderScope.containerOf(ref.context));

/// Same as [refreshOps], through a container captured before an `await`.
void refreshOpsIn(ProviderContainer ref) {
  ref
    ..invalidate(opsSummaryProvider)
    ..invalidate(pendingBarbersProvider)
    ..invalidate(opsJobsProvider)
    ..invalidate(allBarbersProvider)
    ..invalidate(opsBarberProvider)
    ..invalidate(jobProvider)
    ..invalidate(disputesProvider)
    ..invalidate(payoutsProvider);
}
