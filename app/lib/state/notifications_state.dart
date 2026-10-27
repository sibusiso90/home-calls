import 'dart:async';

import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/state/providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How often the inbox is polled while the app is visible. Null disables
/// polling (tests).
final notificationPollIntervalProvider = Provider<Duration?>(
  (ref) => const Duration(seconds: 30),
);

final notificationsProvider =
    AsyncNotifierProvider<NotificationsNotifier, NotificationInbox>(
      NotificationsNotifier.new,
    );

/// The signed-in user's inbox. Polls while the app is visible, refreshes when
/// it comes back to the foreground, and refreshes affected jobs when new
/// notifications arrive.
class NotificationsNotifier extends AsyncNotifier<NotificationInbox> {
  Timer? _timer;
  AppLifecycleListener? _lifecycle;

  @override
  Future<NotificationInbox> build() async {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return NotificationInbox.empty;

    final interval = ref.watch(notificationPollIntervalProvider);
    if (interval != null) {
      _timer = Timer.periodic(interval, (_) => unawaited(poll()));
      _lifecycle = AppLifecycleListener(onShow: () => unawaited(poll()));
      ref.onDispose(() {
        _timer?.cancel();
        _lifecycle?.dispose();
      });
    }
    return ref.read(apiProvider).notifications();
  }

  static bool get _visible => switch (WidgetsBinding.instance.lifecycleState) {
    AppLifecycleState.hidden ||
    AppLifecycleState.paused ||
    AppLifecycleState.detached => false,
    _ => true,
  };

  /// Fetches the inbox in the background, keeping the last good copy on error.
  Future<void> poll() async {
    if (!_visible) return;
    final NotificationInbox fresh;
    try {
      fresh = await ref.read(apiProvider).notifications();
    } on Object {
      return;
    }
    if (!ref.mounted) return;
    final previous = state.value;
    state = AsyncData(fresh);
    _refreshJobsFor(previous, fresh);
  }

  /// New notifications usually mean a job changed: refresh those jobs.
  void _refreshJobsFor(NotificationInbox? before, NotificationInbox after) {
    if (before == null) return;
    final seen = {for (final n in before.items) n.id};
    final changed = {
      for (final n in after.items)
        if (!seen.contains(n.id) && n.jobId != null) n.jobId!,
    };
    if (changed.isEmpty) return;
    ref.invalidate(jobsProvider);
    for (final id in changed) {
      ref.invalidate(jobProvider(id));
    }
  }

  Future<void> markRead(AppNotification n) async {
    if (!n.isUnread) return;
    _update(
      (inbox) => NotificationInbox(
        items: [
          for (final i in inbox.items)
            i.id == n.id ? i.markedRead(DateTime.now()) : i,
        ],
        unreadCount: (inbox.unreadCount - 1).clamp(0, 1 << 30),
      ),
    );
    try {
      await ref.read(apiProvider).markNotificationRead(n.id);
    } on Object {
      await poll();
    }
  }

  Future<void> markAllRead() async {
    final now = DateTime.now();
    _update(
      (inbox) => NotificationInbox(
        items: [for (final i in inbox.items) i.markedRead(now)],
        unreadCount: 0,
      ),
    );
    try {
      await ref.read(apiProvider).markAllNotificationsRead();
    } on Object {
      await poll();
    }
  }

  void _update(NotificationInbox Function(NotificationInbox) change) {
    final current = state.value;
    if (current != null) state = AsyncData(change(current));
  }
}
