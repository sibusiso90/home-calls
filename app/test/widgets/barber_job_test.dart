import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/ui/barber/barber_job_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../fixtures.dart';
import '../helpers.dart';

void main() {
  Future<void> pumpJob(WidgetTester tester, String paymentStatus) async {
    final api = mockApi();
    when(() => api.job(any())).thenAnswer(
      (_) async => Job.fromJson(
        decode(
          jobJson(
            status: 'confirmed',
            evidence: null,
            paymentStatus: paymentStatus,
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
}
