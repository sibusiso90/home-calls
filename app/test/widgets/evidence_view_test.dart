import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/ui/widgets/check_row.dart';
import 'package:fade_call/ui/widgets/evidence_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures.dart';
import '../helpers.dart';

void main() {
  testWidgets('pass verdict shows payment released and every check', (
    tester,
  ) async {
    final evidence = Evidence.fromJson(decode(evidencePassJson()));
    await pumpScreen(
      tester,
      SingleChildScrollView(child: EvidenceView(evidence: evidence)),
      api: mockApi(),
    );

    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('Payment released, rating unlocked.'), findsOneWidget);
    expect(find.byType(CheckRow), findsNWidgets(CheckKind.values.length));
    for (final kind in CheckKind.values) {
      expect(find.text(kind.label), findsOneWidget);
    }
    expect(find.text('Uncertain'), findsNothing);
    expect(find.text('Confidence 93%'), findsOneWidget);
    expect(find.text('Change 31%'), findsOneWidget);
  });

  testWidgets('needs_review verdict shows operator review and reasons', (
    tester,
  ) async {
    final evidence = Evidence.fromJson(decode(evidenceNeedsReviewJson));
    await pumpScreen(
      tester,
      SingleChildScrollView(child: EvidenceView(evidence: evidence)),
      api: mockApi(),
    );

    expect(find.text('Sent to operator review'), findsOneWidget);
    expect(find.text('• Matches the ordered cut: uncertain'), findsOneWidget);
    expect(find.text('Uncertain'), findsOneWidget);
    expect(find.text('Top looks longer than ordered'), findsOneWidget);
    expect(find.textContaining('Payment released'), findsNothing);
  });

  testWidgets('toggles between hair masks and raw photos', (tester) async {
    final api = mockApi();
    final evidence = Evidence.fromJson(decode(evidenceNeedsReviewJson));
    await pumpScreen(
      tester,
      SingleChildScrollView(child: EvidenceView(evidence: evidence)),
      api: api,
    );
    expect(find.textContaining('SAM 3.1'), findsWidgets);
    await tester.tap(find.text('Photo'));
    await tester.pump();
    expect(
      find.text('Tinted area is the hair region found by SAM 3.1.'),
      findsNothing,
    );
  });

  testWidgets('purged evidence explains the deletion and keeps checks', (
    tester,
  ) async {
    final evidence = Evidence.fromJson(
      decode(
        evidencePassJson()
            .replaceAll(RegExp(r'"/media/[a-z]+"'), 'null')
            .replaceFirst(
              '"decided_by": "model"',
              '"decided_by": "model", "purged_at": "2026-11-04T10:00:00+02:00"',
            ),
      ),
    );
    await pumpScreen(
      tester,
      SingleChildScrollView(child: EvidenceView(evidence: evidence)),
      api: mockApi(),
    );
    expect(find.byKey(const ValueKey('evidence-purged')), findsOneWidget);
    expect(
      find.textContaining('Photos deleted under the retention policy on'),
      findsOneWidget,
    );
    expect(find.text('Hair mask'), findsNothing);
    expect(find.byType(CheckRow), findsNWidgets(CheckKind.values.length));
    expect(find.text('Verified'), findsOneWidget);
  });
}
