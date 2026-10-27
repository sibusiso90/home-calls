import 'package:fade_call/data/api_exception.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../fixtures.dart';
import '../helpers.dart';

void main() {
  setUpAll(() => registerFallbackValue(Role.client));

  testWidgets('shows roles, mock badge and validates input', (tester) async {
    await pumpScreen(tester, const LoginScreen(), api: mockApi());
    await tester.pump();

    for (final role in Role.values) {
      expect(find.byKey(ValueKey('role-${role.name}')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('mock-badge')), findsOneWidget);
    expect(find.byKey(const ValueKey('login-passcode')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('login-submit')));
    await tester.pump();
    expect(find.text('Enter your name'), findsOneWidget);
    expect(
      find.text('Enter a South African number, like 082 123 4567'),
      findsOneWidget,
    );
  });

  testWidgets('passcode field appears only for operator', (tester) async {
    await pumpScreen(tester, const LoginScreen(), api: mockApi());
    await tester.tap(find.byKey(const ValueKey('role-operator')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-passcode')), findsOneWidget);
    expect(find.text('Continue as operator'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('role-barber')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-passcode')), findsNothing);
  });

  testWidgets('submits demo login with a normalised phone number', (
    tester,
  ) async {
    final api = mockApi();
    when(
      () => api.demoLogin(
        role: any(named: 'role'),
        name: any(named: 'name'),
        phone: any(named: 'phone'),
        passcode: any(named: 'passcode'),
      ),
    ).thenAnswer((_) async => Session.fromJson(decode(loginJson)));

    await pumpScreen(tester, const LoginScreen(), api: api);
    await tester.tap(find.byKey(const ValueKey('role-barber')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('login-name')), 'Thabo');
    await tester.enterText(
      find.byKey(const ValueKey('login-phone')),
      '082 123 4567',
    );
    await tester.tap(find.byKey(const ValueKey('login-submit')));
    await tester.pumpAndSettle();

    verify(
      () => api.demoLogin(
        role: Role.barber,
        name: 'Thabo',
        phone: '+27821234567',
      ),
    ).called(1);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LoginScreen)),
    );
    expect(container.read(sessionProvider)?.token, 'tok-123');
  });

  testWidgets('shows a friendly error for a wrong operator passcode', (
    tester,
  ) async {
    final api = mockApi();
    when(
      () => api.demoLogin(
        role: any(named: 'role'),
        name: any(named: 'name'),
        phone: any(named: 'phone'),
        passcode: any(named: 'passcode'),
      ),
    ).thenThrow(
      const ApiException('forbidden', 'Bad passcode', statusCode: 403),
    );

    await pumpScreen(tester, const LoginScreen(), api: api);
    await tester.tap(find.byKey(const ValueKey('role-operator')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('login-name')), 'Ops');
    await tester.enterText(
      find.byKey(const ValueKey('login-phone')),
      '+27 82 000 0000',
    );
    await tester.enterText(find.byKey(const ValueKey('login-passcode')), 'x');
    await tester.tap(find.byKey(const ValueKey('login-submit')));
    await tester.pumpAndSettle();

    expect(find.text('That operator passcode is not right.'), findsOneWidget);
  });
}
