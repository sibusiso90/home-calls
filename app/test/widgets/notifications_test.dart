import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/router.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/widgets/notification_bell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../fixtures.dart';
import '../helpers.dart';

AppNotification note(String id, {bool read = false, String? job = 'j-1'}) =>
    AppNotification.fromJson(
      decode(
        '{"id": "$id", "job_id": ${job == null ? 'null' : '"$job"'}, '
        '"kind": "reminder", "title": "Your cut is tomorrow $id", '
        '"body": "Thabo M arrives at 16:00", '
        '"created_at": "2026-10-27T16:00:00+02:00", '
        '"read_at": ${read ? '"2026-10-27T17:00:00+02:00"' : 'null'}}',
      ),
    );

void main() {
  final signedIn = sessionProvider.overrideWithBuild(
    (ref, _) => Session.fromJson(decode(loginJson)),
  );

  testWidgets('bell shows the unread count from the inbox', (tester) async {
    final api = mockApi();
    when(api.notifications).thenAnswer(
      (_) async => NotificationInbox(
        items: [note('a'), note('b'), note('c', read: true)],
        unreadCount: 2,
      ),
    );
    await pumpScreen(
      tester,
      const NotificationBell(),
      api: api,
      overrides: [signedIn],
    );
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
    expect(find.byTooltip('Notifications, 2 unread'), findsOneWidget);
    final badge = tester.widget<Badge>(
      find.byKey(const ValueKey('notification-badge')),
    );
    expect(badge.isLabelVisible, isTrue);
  });

  testWidgets('no badge when everything is read', (tester) async {
    final api = mockApi();
    when(api.notifications).thenAnswer(
      (_) async =>
          NotificationInbox(items: [note('a', read: true)], unreadCount: 0),
    );
    await pumpScreen(
      tester,
      const NotificationBell(),
      api: api,
      overrides: [signedIn],
    );
    await tester.pumpAndSettle();
    final badge = tester.widget<Badge>(
      find.byKey(const ValueKey('notification-badge')),
    );
    expect(badge.isLabelVisible, isFalse);
    expect(find.byTooltip('Notifications'), findsOneWidget);
  });

  testWidgets('sheet lists notifications, marks read and opens the job', (
    tester,
  ) async {
    final api = mockApi();
    when(api.notifications).thenAnswer(
      (_) async => NotificationInbox(items: [note('a')], unreadCount: 1),
    );
    when(() => api.markNotificationRead(any())).thenAnswer((_) async {});
    String? opened;
    await pumpScreen(
      tester,
      NotificationsSheet(onOpen: (l) => opened = l),
      api: api,
      overrides: [signedIn],
    );
    await tester.pumpAndSettle();

    expect(find.text('Your cut is tomorrow a'), findsOneWidget);
    expect(find.text('Mark all read'), findsOneWidget);
    await tester.tap(find.text('Your cut is tomorrow a'));
    await tester.pumpAndSettle();

    verify(() => api.markNotificationRead('a')).called(1);
    expect(opened, Routes.barberJob('j-1')); // loginJson is a barber
    expect(find.text('Mark all read'), findsNothing);
  });

  test('operators are sent to the matching queue', () {
    final dispute = AppNotification.fromJson(
      decode(
        '{"id": "x", "job_id": "j", "kind": "dispute_opened", "title": "t", '
        '"body": "", "created_at": null, "read_at": null}',
      ),
    );
    expect(notificationTarget(Role.operator, dispute), Routes.opsDisputes);
    expect(notificationTarget(Role.client, dispute), Routes.clientJob('j'));
    expect(notificationTarget(Role.client, note('n', job: null)), isNull);
  });
}
