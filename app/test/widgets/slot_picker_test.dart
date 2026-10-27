import 'package:fade_call/ui/widgets/slot_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  testWidgets('groups slots by day and offers today first', (tester) async {
    final now = DateTime(2026, 10, 27, 13);
    final slots = [
      DateTime(2026, 10, 27, 14),
      DateTime(2026, 10, 27, 14, 30),
      DateTime(2026, 10, 28, 8),
      DateTime(2026, 10, 30, 9),
    ];
    DateTime? picked;
    await pumpScreen(
      tester,
      StatefulBuilder(
        builder: (context, setState) => SlotPicker(
          slots: slots,
          selected: picked,
          now: now,
          onSelected: (s) => setState(() => picked = s),
        ),
      ),
      api: mockApi(),
    );

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);
    expect(find.text('Fri 30 Oct'), findsOneWidget);
    expect(find.text('14:00'), findsOneWidget);
    expect(find.text('14:30'), findsOneWidget);
    expect(find.text('08:00'), findsNothing);

    await tester.tap(find.text('14:30'));
    await tester.pump();
    expect(picked, DateTime(2026, 10, 27, 14, 30));

    await tester.tap(find.text('Tomorrow'));
    await tester.pump();
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('14:00'), findsNothing);
  });
}
