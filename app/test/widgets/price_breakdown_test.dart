import 'package:fade_call/core/format.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/ui/widgets/price_breakdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures.dart';
import '../helpers.dart';

void main() {
  testWidgets('shows tier rate + time + travel = total', (tester) async {
    final match = BarberMatch.fromJson(decodeList(matchesJson).single);
    await pumpScreen(
      tester,
      PriceBreakdown(
        price: match.price,
        tier: match.barber.tier,
        minutes: 50,
        travelBand: match.travelBand,
        distanceKm: match.distanceKm,
      ),
      api: mockApi(),
    );

    expect(find.text('Pro rate'), findsOneWidget);
    expect(find.text('R320'), findsOneWidget);
    expect(find.text('Time (50 min)'), findsOneWidget);
    expect(find.text('R25'), findsOneWidget);
    expect(find.text('Travel (band B, 4.2 km)'), findsOneWidget);
    expect(find.text('R40'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('price-total'))).data,
      'R385',
    );
  });

  test('rand formats with a space as thousands separator', () {
    expect(rand(385), 'R385');
    expect(rand(1540), 'R1 540');
    expect(rand(0), 'R0');
    expect(randRange(320, 420), 'R320–R420');
  });
}
