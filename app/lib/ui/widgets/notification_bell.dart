import 'dart:async';

import 'package:fade_call/core/format.dart';
import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/router.dart';
import 'package:fade_call/state/notifications_state.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Bell with an unread badge; opens the notifications sheet.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(notificationsProvider).value?.unreadCount ?? 0;
    return IconButton(
      key: const ValueKey('notification-bell'),
      tooltip: unread == 0 ? 'Notifications' : 'Notifications, $unread unread',
      onPressed: () => showNotificationsSheet(context),
      icon: Badge(
        key: const ValueKey('notification-badge'),
        isLabelVisible: unread > 0,
        backgroundColor: Palette.fail,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: Icon(
          unread > 0
              ? Icons.notifications_active_rounded
              : Icons.notifications_none_rounded,
        ),
      ),
    );
  }
}

Future<void> showNotificationsSheet(BuildContext context) {
  final router = GoRouter.of(context);
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (sheetContext) => NotificationsSheet(
      onOpen: (location) {
        Navigator.of(sheetContext).pop();
        router.go(location);
      },
    ),
  );
}

/// Where tapping a notification goes, by role.
String? notificationTarget(Role role, AppNotification n) => switch (role) {
  Role.client when n.jobId != null => Routes.clientJob(n.jobId!),
  Role.barber when n.jobId != null => Routes.barberJob(n.jobId!),
  Role.client when n.requestId != null => Routes.clientBookings,
  Role.barber when n.requestId != null => Routes.barberJobs,
  Role.operator => switch (n.kind) {
    NotificationKind.disputeOpened ||
    NotificationKind.disputeResolved => Routes.opsDisputes,
    _ when n.jobId != null => Routes.opsJob(n.jobId!),
    _ => Routes.opsOverview,
  },
  _ => null,
};

class NotificationsSheet extends ConsumerWidget {
  const NotificationsSheet({required this.onOpen, super.key});

  final void Function(String location) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(notificationsProvider);
    final role = ref.watch(currentRoleProvider);
    final notifier = ref.read(notificationsProvider.notifier);
    final unread = inbox.value?.unreadCount ?? 0;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.md, Gap.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Notifications',
                    style: context.text.headlineSmall,
                  ),
                ),
                if (unread > 0)
                  TextButton(
                    onPressed: () => unawaited(notifier.markAllRead()),
                    child: const Text('Mark all read'),
                  ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: AsyncView(
              value: inbox,
              onRetry: () => ref.invalidate(notificationsProvider),
              isEmpty: (i) => i.items.isEmpty,
              empty: const MessageView(
                icon: Icons.notifications_none_rounded,
                title: "You're all caught up",
                message:
                    'Bookings, reminders and verdicts show up here as they happen.',
              ),
              builder: (i) => ListView.separated(
                padding: const EdgeInsets.only(bottom: Gap.lg),
                itemCount: i.items.length,
                separatorBuilder: (_, _) => const Divider(indent: Gap.lg + 40),
                itemBuilder: (context, index) {
                  final n = i.items[index];
                  final target = role == null
                      ? null
                      : notificationTarget(role, n);
                  return NotificationTile(
                    notification: n,
                    onTap: () {
                      unawaited(notifier.markRead(n));
                      if (target != null) onOpen(target);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NotificationTile extends StatelessWidget {
  const NotificationTile({
    required this.notification,
    required this.onTap,
    super.key,
  });

  final AppNotification notification;
  final VoidCallback onTap;

  static (IconData, Color) _look(BuildContext context, NotificationKind k) =>
      switch (k) {
        NotificationKind.verdictPass => (
          Icons.verified_rounded,
          context.status.pass,
        ),
        NotificationKind.verdictNeedsReview || NotificationKind.disputeOpened =>
          (Icons.manage_search_rounded, context.status.review),
        NotificationKind.jobCancelled => (
          Icons.event_busy_rounded,
          context.status.fail,
        ),
        NotificationKind.reminder => (Icons.alarm_rounded, Palette.brass),
        NotificationKind.requestNew => (Icons.campaign_outlined, Palette.brass),
        NotificationKind.requestAccepted => (
          Icons.check_circle_rounded,
          context.status.pass,
        ),
        NotificationKind.jobRescheduled => (
          Icons.update_rounded,
          Palette.brass,
        ),
        NotificationKind.depositPaid => (
          Icons.payments_rounded,
          context.colors.primary,
        ),
        NotificationKind.verdictOperator || NotificationKind.disputeResolved =>
          (Icons.gavel_rounded, context.colors.primary),
        _ => (Icons.event_available_rounded, context.colors.primary),
      };

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final (icon, color) = _look(context, n.kind);
    return Semantics(
      button: true,
      label: '${n.isUnread ? 'Unread: ' : ''}${n.title}',
      child: InkWell(
        onTap: onTap,
        child: Container(
          color: n.isUnread
              ? Palette.brassSoft.withValues(alpha: 0.35)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.lg,
            vertical: Gap.sm + 4,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(icon, size: 20, color: color),
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.title,
                      style: context.text.titleSmall?.copyWith(
                        fontWeight: n.isUnread
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                    if (n.body.isNotEmpty)
                      Text(n.body, style: context.text.bodySmall),
                    const SizedBox(height: 2),
                    Text(
                      formatSlot(n.createdAt),
                      style: context.text.labelSmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (n.isUnread)
                const Padding(
                  padding: EdgeInsets.only(top: 6, left: Gap.sm),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Palette.fail,
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox.square(dimension: 8),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
