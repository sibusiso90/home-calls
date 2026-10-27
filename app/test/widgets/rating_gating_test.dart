import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/ui/client/rating_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../fixtures.dart';
import '../helpers.dart';

void main() {
  testWidgets('form is hidden and explained when can_rate is false', (
    tester,
  ) async {
    final job = Job.fromJson(decode(jobJson()));
    await pumpScreen(tester, RatingSection(job: job), api: mockApi());

    expect(find.byKey(const ValueKey('rating-locked')), findsOneWidget);
    expect(find.text('Ratings unlock after a verified job'), findsOneWidget);
    expect(find.byKey(const ValueKey('rating-form')), findsNothing);
    expect(find.text('Submit rating'), findsNothing);
  });

  testWidgets('form shows and submits when can_rate is true', (tester) async {
    final api = mockApi();
    when(
      () => api.rate(
        any(),
        stars: any(named: 'stars'),
        comment: any(named: 'comment'),
      ),
    ).thenAnswer((_) async {});
    when(() => api.job(any())).thenAnswer(
      (_) async =>
          Job.fromJson(decode(jobJson(status: 'verified', canRate: true))),
    );
    final job = Job.fromJson(
      decode(
        jobJson(
          status: 'verified',
          evidence: evidencePassJson(),
          canRate: true,
        ),
      ),
    );
    await pumpScreen(tester, RatingSection(job: job), api: api);

    expect(find.byKey(const ValueKey('rating-form')), findsOneWidget);
    expect(find.byKey(const ValueKey('rating-locked')), findsNothing);

    final submit = find.widgetWithText(FilledButton, 'Submit rating');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    await tester.tap(find.byTooltip('4 stars'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Sharp fade');
    await tester.tap(submit);
    await tester.pump();

    verify(() => api.rate('j-1', stars: 4, comment: 'Sharp fade')).called(1);
  });

  testWidgets('an existing rating is shown instead of the form', (
    tester,
  ) async {
    final job = Job.fromJson(
      decode(
        jobJson(
          status: 'verified',
          canRate: true,
          rating: '{"stars": 5, "comment": "Best fade in Midrand"}',
        ),
      ),
    );
    await pumpScreen(tester, RatingSection(job: job), api: mockApi());

    expect(find.byKey(const ValueKey('rating-done')), findsOneWidget);
    expect(find.text('Best fade in Midrand'), findsOneWidget);
    expect(find.text('Submit rating'), findsNothing);
  });
}
