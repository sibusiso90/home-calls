import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/app_shell.dart';
import 'package:fade_call/ui/auth/login_screen.dart';
import 'package:fade_call/ui/barber/barber_job_screen.dart';
import 'package:fade_call/ui/barber/barber_jobs_screen.dart';
import 'package:fade_call/ui/barber/barber_profile_screen.dart';
import 'package:fade_call/ui/barber/proof_capture_screen.dart';
import 'package:fade_call/ui/client/bookings_screen.dart';
import 'package:fade_call/ui/client/client_job_screen.dart';
import 'package:fade_call/ui/client/matches_screen.dart';
import 'package:fade_call/ui/client/quote_screen.dart';
import 'package:fade_call/ui/ops/ops_barbers_screen.dart';
import 'package:fade_call/ui/ops/ops_disputes_screen.dart';
import 'package:fade_call/ui/ops/ops_overview_screen.dart';
import 'package:fade_call/ui/ops/ops_payouts_screen.dart';
import 'package:fade_call/ui/ops/ops_reviews_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

abstract final class Routes {
  static const login = '/login';
  static const barberJobs = '/barber/jobs';
  static const barberProfile = '/barber/profile';
  static const clientQuote = '/client/quote';
  static const clientBookings = '/client/bookings';
  static const opsOverview = '/ops/overview';
  static const opsBarbers = '/ops/barbers';
  static const opsReviews = '/ops/reviews';
  static const opsDisputes = '/ops/disputes';
  static const opsPayouts = '/ops/payouts';

  static String barberJob(String id) => '$barberJobs/$id';
  static String proof(String id, {required bool after}) =>
      '$barberJobs/$id/proof/${after ? 'after' : 'before'}';
  static String matches(String quoteId) => '$clientQuote/matches/$quoteId';
  static String clientJob(String id, {bool confirmed = false}) =>
      '$clientBookings/$id${confirmed ? '?confirmed=1' : ''}';

  static String homeFor(Role role) => switch (role) {
    Role.barber => barberJobs,
    Role.client => clientQuote,
    Role.operator => opsOverview,
  };

  static String _prefix(Role role) => switch (role) {
    Role.barber => '/barber',
    Role.client => '/client',
    Role.operator => '/ops',
  };

  /// Role-based redirect: signed-out users go to login, and each role is
  /// kept inside its own section.
  static String? redirect({required Role? role, required String location}) {
    if (role == null) return location == login ? null : login;
    final prefix = _prefix(role);
    if (location == prefix || !location.startsWith('$prefix/')) {
      return homeFor(role);
    }
    return null;
  }
}

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

const _barberTabs = <ShellDestination>[
  (
    icon: Icons.event_note_outlined,
    selected: Icons.event_note_rounded,
    label: 'Jobs',
  ),
  (icon: Icons.badge_outlined, selected: Icons.badge_rounded, label: 'Profile'),
];

const _clientTabs = <ShellDestination>[
  (
    icon: Icons.content_cut_outlined,
    selected: Icons.content_cut_rounded,
    label: 'Get a quote',
  ),
  (
    icon: Icons.calendar_month_outlined,
    selected: Icons.calendar_month_rounded,
    label: 'My bookings',
  ),
];

const _opsTabs = <ShellDestination>[
  (
    icon: Icons.space_dashboard_outlined,
    selected: Icons.space_dashboard_rounded,
    label: 'Overview',
  ),
  (
    icon: Icons.how_to_reg_outlined,
    selected: Icons.how_to_reg_rounded,
    label: 'Barbers',
  ),
  (
    icon: Icons.fact_check_outlined,
    selected: Icons.fact_check_rounded,
    label: 'Reviews',
  ),
  (
    icon: Icons.record_voice_over_outlined,
    selected: Icons.record_voice_over_rounded,
    label: 'Disputes',
  ),
  (
    icon: Icons.payments_outlined,
    selected: Icons.payments_rounded,
    label: 'Payouts',
  ),
];

StatefulShellBranch _branch(
  String path,
  Widget screen, [
  List<RouteBase> routes = const [],
]) => StatefulShellBranch(
  routes: [
    GoRoute(
      path: path,
      pageBuilder: (context, state) => NoTransitionPage(child: screen),
      routes: routes,
    ),
  ],
);

/// Builds the app router. Exposed for tests.
GoRouter buildRouter({
  required ValueListenable<Role?> role,
  String? initialLocation,
}) => GoRouter(
  navigatorKey: _rootKey,
  initialLocation: initialLocation ?? Routes.login,
  refreshListenable: role,
  redirect: (context, state) =>
      Routes.redirect(role: role.value, location: state.matchedLocation),
  routes: [
    GoRoute(path: '/', redirect: (_, _) => Routes.login),
    GoRoute(
      path: Routes.login,
      builder: (context, state) => const LoginScreen(),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) =>
          AppShell(shell: shell, destinations: _barberTabs),
      branches: [
        _branch(Routes.barberJobs, const BarberJobsScreen(), [
          GoRoute(
            path: ':id',
            builder: (context, state) =>
                BarberJobScreen(jobId: state.pathParameters['id']!),
            routes: [
              GoRoute(
                path: 'proof/:phase',
                parentNavigatorKey: _rootKey,
                builder: (context, state) => ProofCaptureScreen(
                  jobId: state.pathParameters['id']!,
                  after: state.pathParameters['phase'] == 'after',
                ),
              ),
            ],
          ),
        ]),
        _branch(Routes.barberProfile, const BarberProfileScreen()),
      ],
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) =>
          AppShell(shell: shell, destinations: _clientTabs),
      branches: [
        _branch(Routes.clientQuote, const QuoteScreen(), [
          GoRoute(
            path: 'matches/:quoteId',
            builder: (context, state) =>
                MatchesScreen(quoteId: state.pathParameters['quoteId']!),
          ),
        ]),
        _branch(Routes.clientBookings, const BookingsScreen(), [
          GoRoute(
            path: ':id',
            builder: (context, state) => ClientJobScreen(
              jobId: state.pathParameters['id']!,
              justBooked: state.uri.queryParameters['confirmed'] == '1',
            ),
          ),
        ]),
      ],
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) =>
          AppShell(shell: shell, destinations: _opsTabs, railBreakpoint: 720),
      branches: [
        _branch(Routes.opsOverview, const OpsOverviewScreen()),
        _branch(Routes.opsBarbers, const OpsBarbersScreen()),
        _branch(Routes.opsReviews, const OpsReviewsScreen()),
        _branch(Routes.opsDisputes, const OpsDisputesScreen()),
        _branch(Routes.opsPayouts, const OpsPayoutsScreen()),
      ],
    ),
  ],
);

final routerProvider = Provider<GoRouter>((ref) {
  final role = ValueNotifier<Role?>(ref.read(currentRoleProvider));
  ref
    ..listen(currentRoleProvider, (_, next) => role.value = next)
    ..onDispose(role.dispose);
  final router = buildRouter(role: role);
  ref.onDispose(router.dispose);
  return router;
});
