import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/ui/barber/barber_job_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../fixtures.dart';
import '../helpers.dart';

void main() {
  Future<void> pumpJob(
    WidgetTester tester,
    String paymentStatus, {
    String pictures = '',
  }) async {
    final api = mockApi();
    when(() => api.job(any())).thenAnswer(
      (_) async => Job.fromJson(
        decode(
          jobJson(
            status: 'confirmed',
            evidence: null,
            paymentStatus: paymentStatus,
            pictures: pictures,
          ),
        ),
      ),
    );
    await pumpScreen(tester, const BarberJobScreen(jobId: 'j-1'), api: api);
    await tester.pumpAndSettle();
  }

  testWidgets('proof is disabled until the client pays the deposit', (
    tester,
  ) async {
    await pumpJob(tester, 'deposit_pending');
    expect(find.byKey(const ValueKey('waiting-deposit')), findsOneWidget);
    final button = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Capture before photo'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('proof is enabled once the deposit is paid', (tester) async {
    await pumpJob(tester, 'deposit_paid');
    expect(find.byKey(const ValueKey('waiting-deposit')), findsNothing);
    final button = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Capture before photo'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('barber sees the ordered cut and the client reference photo', (
    tester,
  ) async {
    await pumpJob(tester, 'deposit_paid', pictures: jobPicturesJson);
    final pictures = find.byKey(const ValueKey('job-cut-pictures'));
    expect(pictures, findsOneWidget);
    expect(
      find.descendant(of: pictures, matching: find.text('THE CUT')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: pictures, matching: find.text('THEIR PHOTO')),
      findsOneWidget,
    );
  });

  testWidgets('no picture section for a job without a cut picture', (
    tester,
  ) async {
    await pumpJob(tester, 'deposit_paid');
    expect(find.byKey(const ValueKey('job-cut-pictures')), findsNothing);
  });
}
