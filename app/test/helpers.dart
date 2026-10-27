import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/fade_call_api.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/state/notifications_state.dart';
import 'package:fade_call/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockApi extends Mock implements FadeCallApi {}

/// A mock API with the always-needed calls stubbed.
MockApi mockApi() {
  final api = MockApi();
  when(
    () => api.mediaUrl(any()),
  ).thenAnswer((i) => 'http://test${i.positionalArguments.first as String}');
  when(api.health).thenAnswer((_) async => Health.fromJson(decode(healthJson)));
  when(
    api.areas,
  ).thenAnswer((_) async => decodeList(areasJson).map(Area.fromJson).toList());
  return api;
}

/// Pumps [child] inside a themed MaterialApp and a ProviderScope.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget child, {
  required FadeCallApi api,
  List<Override> overrides = const [],
  Size size = const Size(430, 1400),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        apiProvider.overrideWithValue(api),
        notificationPollIntervalProvider.overrideWithValue(null),
        ...overrides,
      ],
      child: MaterialApp(
        theme: buildTheme(googleFonts: false),
        home: Scaffold(body: child),
      ),
    ),
  );
}
