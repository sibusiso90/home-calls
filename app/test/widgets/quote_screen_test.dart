import 'dart:convert';

import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/data/session_store.dart';
import 'package:fade_call/data/upload_file.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/state/quote_state.dart';
import 'package:fade_call/ui/client/quote_screen.dart';
import 'package:fade_call/ui/widgets/consent_gate.dart';
import 'package:fade_call/ui/widgets/cut_picture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../fixtures.dart';
import '../helpers.dart';

// 1x1 transparent PNG, so the selfie tile can decode it.
final _selfie = UploadFile(
  bytes: base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  ),
  filename: 'selfie.png',
  mimeType: 'image/png',
);

final _quote = Quote.fromJson(decode(quoteJson));

Future<ProviderContainer> _pumpQuote(WidgetTester tester, MockApi api) async {
  final store = MemorySessionStore();
  await store.setConsent('anon.${ConsentTopic.quotePhotos.key}');
  await pumpScreen(
    tester,
    const QuoteScreen(),
    api: api,
    overrides: [sessionStoreProvider.overrideWithValue(store)],
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(QuoteScreen)),
  );
  container.read(quoteControllerProvider.notifier)
    ..setArea('midrand-central')
    ..setSelfie(_selfie);
  await tester.pump();
  return container;
}

Finder _picture(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(CutPicture),
);

FilledButton _submit(WidgetTester tester) =>
    tester.widget(find.byKey(const ValueKey('quote-submit')));

void main() {
  setUpAll(() => registerFallbackValue(_selfie));

  MockApi quoteApi() {
    final api = mockApi();
    when(
      api.cuts,
    ).thenAnswer((_) async => decodeList(cutsJson).map(Cut.fromJson).toList());
    when(
      () => api.createQuote(
        selfie: any(named: 'selfie'),
        areaId: any(named: 'areaId'),
        reference: any(named: 'reference'),
        cutId: any(named: 'cutId'),
      ),
    ).thenAnswer((_) async => _quote);
    when(() => api.requote(any(), any())).thenAnswer((_) async => _quote);
    return api;
  }

  testWidgets('pick a cut from the list, then quote a suggestion instead', (
    tester,
  ) async {
    final api = quoteApi();
    await _pumpQuote(tester, api);

    expect(find.text('Buzz cut'), findsOneWidget);
    expect(_picture('cut-buzz-cut'), findsOneWidget);
    expect(
      _picture('cut-mid-skin-fade-textured'),
      findsNothing,
    ); // no image_url
    expect(_submit(tester).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('cut-buzz-cut')));
    await tester.pump();
    expect(_submit(tester).onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('quote-submit')));
    await tester.pumpAndSettle();
    verify(
      () => api.createQuote(
        selfie: _selfie,
        areaId: 'midrand-central',
        cutId: 'buzz-cut',
      ),
    ).called(1);

    expect(find.byKey(const ValueKey('quote-cut-picture')), findsOneWidget);
    expect(_picture('suggestion-low-taper-lineup'), findsOneWidget);
    expect(find.byKey(const ValueKey('quote-face-advice')), findsOneWidget);
    expect(find.text('Your quote'), findsOneWidget);
    final other = find.descendant(
      of: find.byKey(const ValueKey('suggestion-low-taper-lineup')),
      matching: find.text('Quote this cut'),
    );
    await tester.ensureVisible(other);
    await tester.tap(other);
    await tester.pumpAndSettle();
    verify(() => api.requote('q-1', 'low-taper-lineup')).called(1);
  });

  testWidgets('suggest mode sends neither a cut nor a reference', (
    tester,
  ) async {
    final api = quoteApi();
    await _pumpQuote(tester, api);

    await tester.tap(find.text('Suggest'));
    await tester.pump();
    expect(find.byKey(const ValueKey('quote-suggest-note')), findsOneWidget);
    expect(find.text('Suggest my cut'), findsOneWidget);
    expect(_submit(tester).onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('quote-submit')));
    await tester.pumpAndSettle();
    verify(
      () => api.createQuote(selfie: _selfie, areaId: 'midrand-central'),
    ).called(1);
  });

  testWidgets('photo mode needs a reference before it can submit', (
    tester,
  ) async {
    final container = await _pumpQuote(tester, quoteApi());

    await tester.tap(find.text('My photo'));
    await tester.pump();
    expect(find.text('A photo of the exact cut you want'), findsOneWidget);
    expect(_submit(tester).onPressed, isNull);

    container.read(quoteControllerProvider.notifier).setReference(_selfie);
    await tester.pump();
    expect(_submit(tester).onPressed, isNotNull);
  });
}
