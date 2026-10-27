import 'package:fade_call/data/models/json.dart';

/// What a notification is about; drives its icon.
enum NotificationKind {
  bookingCreated('booking_created'),
  jobConfirmed('job_confirmed'),
  depositPaid('deposit_paid'),
  verdictPass('verdict_pass'),
  verdictNeedsReview('verdict_needs_review'),
  verdictOperator('verdict_operator'),
  disputeOpened('dispute_opened'),
  disputeResolved('dispute_resolved'),
  jobCancelled('job_cancelled'),
  jobRescheduled('job_rescheduled'),
  reminder('reminder'),
  other('other');

  const NotificationKind(this.wire);
  final String wire;

  static NotificationKind parse(String? value) =>
      values.firstWhere((k) => k.wire == value, orElse: () => other);
}

final class AppNotification {
  const AppNotification({
    required this.id,
    required this.jobId,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.readAt,
  });

  factory AppNotification.fromJson(Json json) => AppNotification(
    id: json.str('id'),
    jobId: json.strOrNull('job_id'),
    kind: NotificationKind.parse(json.strOrNull('kind')),
    title: json.strOrNull('title') ?? '',
    body: json.strOrNull('body') ?? '',
    createdAt: json.timeOrNull('created_at'),
    readAt: json.timeOrNull('read_at'),
  );

  final String id;
  final String? jobId;
  final NotificationKind kind;
  final String title;
  final String body;
  final DateTime? createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  AppNotification markedRead(DateTime at) => AppNotification(
    id: id,
    jobId: jobId,
    kind: kind,
    title: title,
    body: body,
    createdAt: createdAt,
    readAt: readAt ?? at,
  );
}

final class NotificationInbox {
  const NotificationInbox({required this.items, required this.unreadCount});

  factory NotificationInbox.fromJson(Json json) => NotificationInbox(
    items: json.list('items', AppNotification.fromJson),
    unreadCount: json.intOrNull('unread_count') ?? 0,
  );

  static const empty = NotificationInbox(items: [], unreadCount: 0);

  final List<AppNotification> items;
  final int unreadCount;
}
