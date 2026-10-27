import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/ui/widgets/booking_changes.dart';
import 'package:fade_call/ui/widgets/job_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures.dart';
import '../helpers.dart';

Job job({String status = 'confirmed', String payment = 'deposit_paid'}) =>
    Job.fromJson(
      decode(jobJson(status: status, evidence: null, paymentStatus: payment)),
    );

/// The fixture slot starts 2026-10-28 16:00 SAST.
final slot = DateTime.parse('2026-10-28T16:00:00+02:00');

void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    required Job j,
    required Role role,
    required DateTime now,
  }) => pumpScreen(
    tester,
    CancelBookingDialog(job: j, role: role, now: now),
    api: mockApi(),
  );

  testWidgets('late client cancel warns that the deposit is kept', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      j: job(),
      role: Role.client,
      now: slot.subtract(const Duration(minutes: 90)),
    );
    expect(find.byKey(const ValueKey('late-cancel-warning')), findsOneWidget);
    expect(find.text('Late cancellation: deposit kept'), findsOneWidget);
  });

  testWidgets('early client cancel promises a refund', (tester) async {
    await pumpDialog(
      tester,
      j: job(),
      role: Role.client,
      now: slot.subtract(const Duration(hours: 5)),
    );
    expect(find.byKey(const ValueKey('late-cancel-warning')), findsNothing);
    expect(
      find.textContaining('Your deposit will be refunded'),
      findsOneWidget,
    );
  });

  testWidgets('barber cancel never warns about a kept deposit', (tester) async {
    await pumpDialog(
      tester,
      j: job(),
      role: Role.barber,
      now: slot.subtract(const Duration(minutes: 30)),
    );
    expect(find.byKey(const ValueKey('late-cancel-warning')), findsNothing);
    expect(find.textContaining('refunded in full'), findsOneWidget);
    expect(find.text('Cancel job'), findsOneWidget);
  });

  testWidgets('a reason is required before confirming', (tester) async {
    await pumpDialog(
      tester,
      j: job(),
      role: Role.client,
      now: slot.subtract(const Duration(days: 1)),
    );
    FilledButton confirm() => tester.widget<FilledButton>(
      find.byKey(const ValueKey('confirm-cancel')),
    );
    expect(confirm().onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('cancel-reason')),
      'Work trip',
    );
    await tester.pump();
    expect(confirm().onPressed, isNotNull);
  });

  testWidgets('timeline explains a cancellation', (tester) async {
    final j = Job.fromJson(
      decode(
        jobJson(
          status: 'cancelled',
          evidence: null,
          paymentStatus: 'forfeited',
        ).replaceFirst(
          '"can_rate": false',
          '"can_rate": false, "cancelled_by": "client", '
              '"cancel_reason": "Work trip", '
              '"cancelled_at": "2026-10-28T15:00:00+02:00"',
        ),
      ),
    );
    await pumpScreen(tester, JobTimeline(job: j), api: mockApi());
    expect(find.text('Cancelled by the client'), findsOneWidget);
    expect(find.text('“Work trip”'), findsOneWidget);
    expect(find.textContaining('deposit is kept'), findsOneWidget);
  });

  testWidgets('timeline notes a reschedule', (tester) async {
    final j = Job.fromJson(
      decode(
        jobJson(status: 'booked', evidence: null).replaceFirst(
          '"can_rate": false',
          '"can_rate": false, "rescheduled_at": "2026-10-27T10:00:00+02:00"',
        ),
      ),
    );
    await pumpScreen(tester, JobTimeline(job: j), api: mockApi());
    expect(find.byKey(const ValueKey('timeline-rescheduled')), findsOneWidget);
  });
}
