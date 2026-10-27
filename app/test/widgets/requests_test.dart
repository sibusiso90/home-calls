import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/ui/client/booking_sheet.dart';
import 'package:fade_call/ui/widgets/request_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../fixtures.dart';
import '../helpers.dart';

HomeCallRequest _offer() => HomeCallRequest.fromJson(
  decode('''
{
  "id": "r-1", "status": "open", "day": "2026-10-28",
  "windows": [{"id": "afternoon", "label": "Afternoon"}],
  "summary": "tomorrow, afternoon", "cut": "Low taper with line-up", "minutes": 40,
  "area_name": "Midrand Central", "quote_id": "q-1", "chosen_barber": null,
  "offered_until": "2026-10-27T16:30:00+00:00", "broadcast": false, "job_id": null,
  "created_at": "2026-10-27T16:20:00+00:00",
  "offered_to_you": true, "client_name": "Lerato", "distance_km": 0.4,
  "travel_band": "A",
  "price": {"tier_rate_zar": 320, "time_zar": 10, "travel_zar": 0, "total_zar": 330},
  "slots": ["2026-10-28T12:00:00+02:00", "2026-10-28T14:30:00+02:00"]
}'''),
);

void main() {
  test(
    'windows close an hour before their last start; Sunday ends at 17:00',
    () {
      final tue = DateTime(2026, 10, 27);
      expect(
        TimeWindow.morning.open(tue, DateTime(2026, 10, 27, 10, 30)),
        isTrue,
      );
      expect(
        TimeWindow.morning.open(tue, DateTime(2026, 10, 27, 10, 31)),
        isFalse,
      );
      expect(TimeWindow.evening.open(tue, DateTime(2026, 10, 27, 19)), isTrue);
      expect(
        TimeWindow.evening.open(tue, DateTime(2026, 10, 27, 19, 1)),
        isFalse,
      );
      final sun = DateTime(2026, 11); // Sunday 1 Nov
      expect(TimeWindow.evening.open(sun, DateTime(2026, 10, 31, 12)), isTrue);
      expect(
        TimeWindow.evening.open(sun, DateTime(2026, 11, 1, 16, 1)),
        isFalse,
      );
    },
  );

  testWidgets('client asks everyone for a window; no exact time is picked', (
    tester,
  ) async {
    final api = mockApi();
    when(
      () => api.createRequest(
        quoteId: any(named: 'quoteId'),
        day: any(named: 'day'),
        windows: any(named: 'windows'),
        address: any(named: 'address'),
        lat: any(named: 'lat'),
        lng: any(named: 'lng'),
        barberId: any(named: 'barberId'),
      ),
    ).thenAnswer((_) async => _offer());
    when(api.requests).thenAnswer((_) async => const []);
    registerFallbackValue(DateTime(2026));

    await pumpScreen(
      tester,
      const BookingSheet(
        quoteId: 'q-1',
        match: null,
        areaId: 'midrand-central',
      ),
      api: api,
    );
    await tester.pumpAndSettle();
    expect(find.text('Ask barbers near you'), findsOneWidget);

    await tester.tap(find.text('Tomorrow'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('window-afternoon')));
    await tester.tap(find.byKey(const ValueKey('window-evening')));
    await tester.enterText(find.byType(TextField), '12 Example Rd, Midrand');
    await tester.tap(find.text('Send to barbers nearby'));
    await tester.pumpAndSettle();

    final call = verify(
      () => api.createRequest(
        quoteId: 'q-1',
        day: captureAny(named: 'day'),
        windows: [TimeWindow.afternoon, TimeWindow.evening],
        address: '12 Example Rd, Midrand',
        lat: any(named: 'lat'),
        lng: any(named: 'lng'),
      ),
    )..called(1);
    final day = call.captured.single as DateTime;
    final now = DateTime.now();
    expect(day, DateTime(now.year, now.month, now.day + 1));
  });

  testWidgets('barber picks a start time inside the window to accept', (
    tester,
  ) async {
    final api = mockApi();
    when(
      () => api.acceptRequest(any(), slotStart: any(named: 'slotStart')),
    ).thenAnswer((_) async => throw Exception('stop here'));
    when(api.requests).thenAnswer((_) async => const []);
    when(api.jobs).thenAnswer((_) async => const []);
    registerFallbackValue(DateTime(2026));

    await pumpScreen(
      tester,
      SingleChildScrollView(child: BarberRequestCard(request: _offer())),
      api: api,
    );
    expect(find.text('Lerato asked for you'), findsOneWidget);
    expect(find.text('You earn R330'), findsOneWidget);
    final accept = find.widgetWithText(FilledButton, 'Pick a time');
    expect(tester.widget<FilledButton>(accept).onPressed, isNull);

    await tester.tap(find.text('14:30'));
    await tester.pump();
    await tester.tap(find.text('Accept for 14:30'));
    await tester.pump();
    verify(
      () => api.acceptRequest(
        'r-1',
        slotStart: DateTime.parse('2026-10-28T14:30:00+02:00'),
      ),
    ).called(1);
  });
}
