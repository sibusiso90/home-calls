import 'package:fade_call/app.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/data/session_store.dart';
import 'package:fade_call/router.dart';
import 'package:fade_call/state/notifications_state.dart';
import 'package:fade_call/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../fixtures.dart';
import '../helpers.dart';

void main() {
  group('Routes.redirect', () {
    test('signed-out users go to login', () {
      expect(
        Routes.redirect(role: null, location: '/ops/overview'),
        '/login?from=%2Fops%2Foverview',
      );
      expect(Routes.redirect(role: null, location: '/login'), isNull);
    });

    test('signed-in users leave login for their home', () {
      expect(
        Routes.redirect(role: Role.client, location: '/login'),
        Routes.clientQuote,
      );
      expect(
        Routes.redirect(role: Role.barber, location: '/login'),
        Routes.barberJobs,
      );
      expect(
        Routes.redirect(role: Role.operator, location: '/login'),
        Routes.opsOverview,
      );
    });

    test('a deep link survives sign-in when it fits the role', () {
      final job = Uri.parse('/client/bookings/j-1');
      final toLogin = Routes.redirect(
        role: null,
        location: job.path,
        uri: job,
      )!;
      expect(toLogin, '/login?from=%2Fclient%2Fbookings%2Fj-1');
      final back = Uri.parse(toLogin);
      expect(
        Routes.redirect(role: Role.client, location: back.path, uri: back),
        '/client/bookings/j-1',
      );
      // Another role's link is not honoured.
      expect(
        Routes.redirect(role: Role.barber, location: back.path, uri: back),
        Routes.barberJobs,
      );
    });

    test('roles are kept inside their own section', () {
      expect(
        Routes.redirect(role: Role.client, location: '/ops/payouts'),
        Routes.clientQuote,
      );
      expect(
        Routes.redirect(role: Role.barber, location: '/client/bookings'),
        Routes.barberJobs,
      );
      expect(
        Routes.redirect(role: Role.barber, location: '/barberx/jobs'),
        Routes.barberJobs,
      );
      expect(
        Routes.redirect(role: Role.operator, location: '/ops/disputes'),
        isNull,
      );
      expect(
        Routes.redirect(role: Role.barber, location: '/barber/jobs/j-1'),
        isNull,
      );
    });
  });

  testWidgets('app router follows the session role', (tester) async {
    tester.view
      ..physicalSize = const Size(430, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = mockApi();
    when(api.jobs).thenAnswer((_) async => const []);
    when(
      api.myBarber,
    ).thenAnswer((_) async => Barber.fromJson(decode(barberJson)));
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        apiProvider.overrideWithValue(api),
        sessionStoreProvider.overrideWithValue(MemorySessionStore()),
        notificationPollIntervalProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const FadeCallApp(googleFonts: false),
      ),
    );
    await tester.pumpAndSettle();

    final router = container.read(routerProvider);
    String path() => router.routerDelegate.currentConfiguration.uri.path;
    expect(path(), Routes.login);

    // Signing in as a barber lands on the barber's jobs.
    await container
        .read(sessionStoreProvider)
        .write(Session.fromJson(decode(loginJson)));
    container.invalidate(sessionProvider);
    await tester.pumpAndSettle();
    expect(path(), Routes.barberJobs);
    expect(find.text('No jobs yet'), findsOneWidget);

    // A barber can't open operator screens.
    router.go(Routes.opsPayouts);
    await tester.pumpAndSettle();
    expect(path(), Routes.barberJobs);

    // Signing out returns to login.
    await container.read(sessionProvider.notifier).logout();
    await tester.pumpAndSettle();
    expect(path(), Routes.login);
  });
}
