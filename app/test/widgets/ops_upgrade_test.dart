import 'package:fade_call/data/device/location_service.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/data/session_store.dart';
import 'package:fade_call/state/barber_state.dart';
import 'package:fade_call/state/notifications_state.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/ops/ops_barber_screen.dart';
import 'package:fade_call/ui/ops/ops_jobs_screen.dart';
import 'package:fade_call/ui/ops/ops_overview_screen.dart';
import 'package:fade_call/ui/widgets/ai_attribution.dart';
import 'package:fade_call/ui/widgets/check_row.dart';
import 'package:fade_call/ui/widgets/compare_slider.dart';
import 'package:fade_call/ui/widgets/evidence_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../fixtures.dart';
import '../helpers.dart';

Job job(String id, String status, {String barber = 'Thabo M'}) => Job.fromJson(
  decode(
    jobJson(status: status, evidence: null)
        .replaceFirst('"id": "j-1"', '"id": "$id"')
        .replaceFirst('"name": "Thabo M", "tier"', '"name": "$barber", "tier"'),
  ),
);

void main() {
  group('AI attribution', () {
    testWidgets('names each model and the latency', (tester) async {
      await pumpScreen(
        tester,
        AiAttribution.fromVersions(const {
          'spark': 'muse-spark-1.3',
          'sam': 'sam-3.1',
        }, elapsedMs: 8240),
        api: mockApi(),
      );
      expect(find.text('Muse Spark'), findsOneWidget);
      expect(find.text('SAM 3.1'), findsOneWidget);
      expect(find.text('Voice Transcribe'), findsNothing);
      expect(find.text('8.2 s'), findsOneWidget);
      expect(find.byTooltip('muse-spark-1.3'), findsOneWidget);
    });

    testWidgets('falls back when no versions are given', (tester) async {
      await pumpScreen(
        tester,
        AiAttribution.fromVersions(
          const {},
          fallback: const [MetaModel.transcribe, MetaModel.spark],
        ),
        api: mockApi(),
      );
      expect(find.text('Voice Transcribe'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-latency')), findsNothing);
      expect(AiAttribution.formatLatency(420), '420 ms');
    });
  });

  group('Evidence viewer', () {
    Evidence evidence() => Evidence.fromJson(
      decode(
        evidenceNeedsReviewJson.replaceFirst(
          '"decided_by": "model"',
          '"decided_by": "model", "elapsed_ms": 6100',
        ),
      ),
    );

    testWidgets('checks carry the model that judged them', (tester) async {
      await pumpScreen(
        tester,
        SingleChildScrollView(child: EvidenceView(evidence: evidence())),
        api: mockApi(),
      );
      CheckRow row(CheckKind k) =>
          tester.widget<CheckRow>(find.widgetWithText(CheckRow, k.label));
      expect(row(CheckKind.samePerson).model, MetaModel.spark);
      expect(row(CheckKind.hairChanged).model, MetaModel.sam);
      expect(row(CheckKind.beforeGps).model, isNull);
      expect(
        find.byKey(const ValueKey('evidence-attribution')),
        findsOneWidget,
      );
      expect(find.text('6.1 s'), findsOneWidget);
    });

    testWidgets('operator layout starts on the compare slider and toggles', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        SingleChildScrollView(
          child: EvidenceView(evidence: evidence(), compareByDefault: true),
        ),
        api: mockApi(),
      );
      expect(find.byType(CompareSlider), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('evidence-layout')));
      await tester.pump();
      expect(find.byType(CompareSlider), findsNothing);
    });
  });

  group('Compare slider', () {
    testWidgets('dragging moves the divider; tapping opens', (tester) async {
      var opened = false;
      final key = GlobalKey<CompareSliderState>();
      await pumpScreen(
        tester,
        SizedBox(
          width: 300,
          child: CompareSlider(
            key: key,
            beforeUrl: '/media/b',
            afterUrl: '/media/a',
            onOpen: () => opened = true,
          ),
        ),
        api: mockApi(),
      );
      expect(key.currentState!.split, 0.5);
      final slider = find.byKey(const ValueKey('compare-slider'));
      await tester.drag(slider, const Offset(-120, 0));
      await tester.pump();
      expect(key.currentState!.split, lessThan(0.2));
      await tester.drag(slider, const Offset(1000, 0));
      await tester.pump();
      expect(key.currentState!.split, 1.0);
      await tester.tap(slider);
      expect(opened, isTrue);
    });

    testWidgets('fullscreen viewer pages between images', (tester) async {
      await pumpScreen(
        tester,
        const FullscreenImages(
          images: [
            (label: 'Before', url: '/media/b'),
            (label: 'After', url: '/media/a'),
          ],
        ),
        api: mockApi(),
      );
      expect(find.text('BEFORE'), findsOneWidget);
      expect(find.textContaining('1 / 2'), findsOneWidget);
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('AFTER'), findsOneWidget);
    });
  });

  group('Operator jobs', () {
    final jobs = [
      job('a', 'needs_review'),
      job('b', 'verified', barber: 'Sipho D'),
      job('c', 'cancelled'),
      job('d', 'verifying'),
    ];

    test('filterJobs by status chip and search', () {
      expect(filterJobs(jobs, JobFilter.all, '').length, 4);
      expect(filterJobs(jobs, JobFilter.needsReview, '').map((j) => j.id), [
        'a',
      ]);
      expect(filterJobs(jobs, JobFilter.inProgress, '').map((j) => j.id), [
        'd',
      ]);
      // The fixture client is "Sipho"; the barber of job b is "Sipho D".
      expect(filterJobs(jobs, JobFilter.all, 'sipho').length, 4);
      expect(filterJobs(jobs, JobFilter.all, 'SIPHO D').map((j) => j.id), [
        'b',
      ]);
      expect(filterJobs(jobs, JobFilter.verified, 'thabo'), isEmpty);
    });

    testWidgets('jobs page shows counts and filters by chip and search', (
      tester,
    ) async {
      final api = mockApi();
      when(() => api.opsJobs(status: null)).thenAnswer((_) async => jobs);
      await pumpScreen(tester, const OpsJobsScreen(), api: api);
      await tester.pumpAndSettle();
      expect(find.text('Needs review · 1'), findsOneWidget);
      expect(find.text('All · 4'), findsOneWidget);
      expect(find.textContaining('Thabo M → Sipho'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('filter-all')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('jobs-search')),
        'sipho d',
      );
      await tester.pump();
      expect(find.textContaining('Sipho D → Sipho'), findsOneWidget);
      expect(find.textContaining('Thabo M → Sipho'), findsNothing);
    });
  });

  testWidgets('barber detail lists ratings, jobs and scored portfolio', (
    tester,
  ) async {
    final detail = BarberDetail.fromJson(
      decode(
        '{"barber": $barberJson, "jobs": [${jobJson(status: 'verified', evidence: null)}], '
        '"ratings": [{"job_id": "j-1", "stars": 5, "comment": "Sharp", '
        '"client_name": "Sipho", "created_at": "2026-10-28T18:00:00+02:00"}]}',
      ),
    );
    await pumpScreen(
      tester,
      BarberDetailView(detail: detail),
      api: mockApi(),
      size: const Size(1200, 3000),
    );
    expect(find.text('Thabo M'), findsWidgets);
    expect(find.text('Sharp'), findsOneWidget);
    expect(find.text('Rating · 1 review'), findsOneWidget);
    expect(find.text('Pair 1'), findsOneWidget);
    expect(find.text('Muse Spark'), findsWidgets);
  });

  testWidgets('overview shows KPI tiles', (tester) async {
    final api = mockApi();
    when(api.opsSummary).thenAnswer(
      (_) async => OpsSummary.fromJson(
        decode(
          '{"barbers_pending": 1, "jobs_needs_review": 2, "open_disputes": 0, '
          '"payouts_released_zar": 1540, "jobs_total": 9, "verified_jobs": 5, '
          '"decided_jobs": 7, "pass_rate": 0.714, "avg_verdict_ms": 8200}',
        ),
      ),
    );
    await pumpScreen(tester, const OpsOverviewScreen(), api: api);
    await tester.pumpAndSettle();
    expect(find.text('71%'), findsOneWidget);
    expect(find.text('8.2 s'), findsOneWidget);
    expect(find.text('Verified jobs (of 9)'), findsOneWidget);
    expect(find.text('R1 540'), findsOneWidget);
  });

  test('stale or missing GPS fixes are not sent', () {
    final now = DateTime(2026, 11, 2, 9);
    GpsFix fix(int secondsOld) => (
      lat: -25.99,
      lng: 28.12,
      accuracyM: 8,
      at: now.subtract(Duration(seconds: secondsOld)),
    );
    expect(freshFix(fix(3), now), isNotNull);
    expect(freshFix(fix(15), now), isNotNull);
    expect(freshFix(fix(16), now), isNull);
    expect(freshFix(null, now), isNull);
  });

  test('grade result is cleared when another user signs in', () async {
    final store = MemorySessionStore(Session.fromJson(decode(loginJson)));
    final container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(store),
        apiProvider.overrideWithValue(mockApi()),
        notificationPollIntervalProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);
    container.listen(gradeResultProvider, (_, _) {});
    container
        .read(gradeResultProvider.notifier)
        .set(GradeResult.fromJson(decode(gradeJson)));
    expect(container.read(gradeResultProvider), isNotNull);

    await store.write(
      Session.fromJson(
        decode(loginJson.replaceFirst('"id": "u-1"', '"id": "u-2"')),
      ),
    );
    container.invalidate(sessionProvider);
    expect(container.read(gradeResultProvider), isNull);
  });
}
