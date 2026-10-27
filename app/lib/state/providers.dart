import 'package:fade_call/core/config.dart';
import 'package:fade_call/data/device/location_service.dart';
import 'package:fade_call/data/device/media_picker.dart';
import 'package:fade_call/data/fade_call_api.dart';
import 'package:fade_call/data/http_fade_call_api.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/data/session_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// Infrastructure
// ---------------------------------------------------------------------------

/// Overridden in `main()` with the persisted store.
final sessionStoreProvider = Provider<SessionStore>(
  (ref) => MemorySessionStore(),
);

final apiProvider = Provider<FadeCallApi>(
  (ref) => HttpFadeCallApi(
    baseUrl: AppConfig.apiBaseUrl,
    token: () => ref.read(sessionProvider)?.token,
    onUnauthorized: () => ref.read(sessionProvider.notifier).expire(),
  ),
);

final locationServiceProvider = Provider<LocationService>(
  (ref) => const LocationService(),
);

final mediaPickerProvider = Provider<MediaPicker>((ref) => const MediaPicker());

// ---------------------------------------------------------------------------
// Session
// ---------------------------------------------------------------------------

final sessionProvider = NotifierProvider<SessionNotifier, Session?>(
  SessionNotifier.new,
);

class SessionNotifier extends Notifier<Session?> {
  @override
  Session? build() => ref.read(sessionStoreProvider).read();

  Future<void> login({
    required Role role,
    required String name,
    required String phone,
    String? passcode,
  }) async {
    final session = await ref
        .read(apiProvider)
        .demoLogin(role: role, name: name, phone: phone, passcode: passcode);
    await ref.read(sessionStoreProvider).write(session);
    state = session;
  }

  Future<void> logout() async {
    await ref.read(sessionStoreProvider).write(null);
    state = null;
  }

  /// Called when the API rejects the token.
  void expire() {
    if (state == null) return;
    // Fire and forget: storage cleanup must not block the redirect.
    logout().ignore();
  }
}

/// Rebuilds user-scoped data when the signed-in user changes.
final currentUserIdProvider = Provider<String?>(
  (ref) => ref.watch(sessionProvider.select((s) => s?.user.id)),
);

final currentRoleProvider = Provider<Role?>(
  (ref) => ref.watch(sessionProvider.select((s) => s?.user.role)),
);

// ---------------------------------------------------------------------------
// Shared data
// ---------------------------------------------------------------------------

final healthProvider = FutureProvider<Health>(
  (ref) => ref.watch(apiProvider).health(),
);

final areasProvider = FutureProvider<List<Area>>(
  (ref) => ref.watch(apiProvider).areas(),
);

final cutsProvider = FutureProvider<List<Cut>>(
  (ref) => ref.watch(apiProvider).cuts(),
);

final consentProvider = NotifierProvider.family<ConsentNotifier, bool, String>(
  ConsentNotifier.new,
);

/// Whether the current user has accepted a consent notice (e.g. `capture`).
class ConsentNotifier extends Notifier<bool> {
  ConsentNotifier(this.topic);

  final String topic;

  String get _key => '${ref.read(currentUserIdProvider) ?? 'anon'}.$topic';

  @override
  bool build() {
    ref.watch(currentUserIdProvider);
    return ref.read(sessionStoreProvider).hasConsent(_key);
  }

  Future<void> accept() async {
    await ref.read(sessionStoreProvider).setConsent(_key);
    state = true;
  }
}

// ---------------------------------------------------------------------------
// Barber and client
// ---------------------------------------------------------------------------

final myBarberProvider = FutureProvider<Barber>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(apiProvider).myBarber();
});

final jobsProvider = FutureProvider<List<Job>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(apiProvider).jobs();
});

final jobProvider = FutureProvider.family<Job, String>((ref, id) {
  ref.watch(currentUserIdProvider);
  return ref.watch(apiProvider).job(id);
});

/// A barber's free slots for the next two weeks (reschedule picker).
final barberSlotsProvider = FutureProvider.family<List<DateTime>, String>(
  (ref, barberId) => ref.watch(apiProvider).barberSlots(barberId, days: 14),
);

final matchesProvider = FutureProvider.family<List<BarberMatch>, String>(
  (ref, quoteId) => ref.watch(apiProvider).matches(quoteId),
);

/// Refreshes a job through a container captured before an `await`, so it
/// still works if the widget that started the request has been disposed.
void refreshJobIn(ProviderContainer container, String id) {
  container
    ..invalidate(jobProvider(id))
    ..invalidate(jobsProvider);
}

extension RefreshX on WidgetRef {
  /// Refreshes a job everywhere it is shown.
  void refreshJob(String id) {
    invalidate(jobProvider(id));
    invalidate(jobsProvider);
  }
}

// ---------------------------------------------------------------------------
// Operator
// ---------------------------------------------------------------------------

final opsSummaryProvider = FutureProvider<OpsSummary>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(apiProvider).opsSummary();
});

final pendingBarbersProvider = FutureProvider<List<Barber>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(apiProvider).opsBarbers();
});

/// Every job, newest first; the operator jobs page filters client-side.
final opsJobsProvider = FutureProvider<List<Job>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(apiProvider).opsJobs(status: null);
});

final allBarbersProvider = FutureProvider<List<Barber>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(apiProvider).opsBarbers(status: null);
});

final opsBarberProvider = FutureProvider.family<BarberDetail, String>((
  ref,
  id,
) {
  ref.watch(currentUserIdProvider);
  return ref.watch(apiProvider).opsBarber(id);
});

final disputesProvider = FutureProvider<List<Dispute>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(apiProvider).opsDisputes();
});

final payoutsProvider = FutureProvider<List<Payout>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(apiProvider).payouts();
});
