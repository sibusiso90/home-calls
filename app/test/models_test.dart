import 'package:fade_call/data/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  test('Health and Session parse', () {
    final h = Health.fromJson(decode(healthJson));
    expect(h.isMock, isTrue);
    expect(h.models['sam'], 'sam-3.1');

    final s = Session.fromJson(decode(loginJson));
    expect(s.token, 'tok-123');
    expect(s.user.role, Role.barber);
    expect(Session.fromJson(s.toJson()).user.phone, '+27821234567');
  });

  test('Area parses', () {
    final a = Area.fromJson(decodeList(areasJson).single);
    expect(a.name, 'Midrand Central');
    expect(a.lat, closeTo(-25.9992, 1e-6));
  });

  test('Barber parses with tier, band and portfolio', () {
    final b = Barber.fromJson(decode(barberJson));
    expect(b.tier, Tier.pro);
    expect(b.status, BarberStatus.approved);
    expect(b.priceBand!.minZar, 300);
    expect(b.rating, 4.7);
    expect(b.isOnboarded, isTrue);
    final item = b.portfolio.single;
    expect(item.score(ScoreCriterion.finish), 9);
    expect(item.reason(ScoreCriterion.lineUp), 'Slightly soft');
    expect(item.overall, 8.0);
  });

  test('Ungraded barber has null tier and is not onboarded', () {
    final b = Barber.fromJson(decode(onboardingBarberJson));
    expect(b.tier, isNull);
    expect(b.priceBand, isNull);
    expect(b.isOnboarded, isFalse);
    expect(b.status, BarberStatus.onboarding);
  });

  test('BarberStatus parses pending_approval', () {
    expect(
      BarberStatus.parse('pending_approval'),
      BarberStatus.pendingApproval,
    );
  });

  test('Voice note result and profile round-trip', () {
    final v = VoiceNoteResult.fromJson(decode(voiceNoteJson));
    expect(v.languageDetected, 'isiZulu + English');
    expect(v.profile.areaId, 'midrand-central');
    expect(v.profile.toJson()['years_cutting'], 6);
  });

  test('Grade result parses', () {
    final g = GradeResult.fromJson(decode(gradeJson));
    expect(g.tier, Tier.pro);
    expect(g.average, 7.6);
    expect(g.barber.name, 'Thabo M');
  });

  test('Quote and matches parse', () {
    final q = Quote.fromJson(decode(quoteJson));
    expect(q.cutName, 'Mid skin fade with textured top');
    expect(q.fitIssues, hasLength(1));
    expect(q.elapsedMs, 8200);

    final m = BarberMatch.fromJson(decodeList(matchesJson).single);
    expect(m.barber.thumbnailUrl, isNull);
    expect(m.price.totalZar, 385);
    expect(m.travelBand, 'B');
    expect(m.nextSlot!.toUtc(), DateTime.utc(2026, 10, 28, 14));
  });

  test('Evidence parses all checks and verdict', () {
    final e = Evidence.fromJson(decode(evidenceNeedsReviewJson));
    expect(e.verdict, Verdict.needsReview);
    expect(e.checks, hasLength(7));
    expect(e.checks[CheckKind.cutMatch]!.result, CheckResult.uncertain);
    expect(e.checks[CheckKind.hairChanged]!.changeRatio, 0.31);
    expect(e.checks[CheckKind.samePerson]!.confidence, 0.93);
    expect(e.verdictReasons, ['cut_match uncertain']);
  });

  test('Partial evidence (before only) has no verdict', () {
    final e = Evidence.fromJson(
      decode(
        '{"job_id": "j", "before_url": "/m", "checks": {"before_timestamp": {"result": "pass", "reason": "ok"}}, "verdict": null}',
      ),
    );
    expect(e.verdict, isNull);
    expect(e.checks.keys, [CheckKind.beforeTimestamp]);
  });

  test('Job parses status, payment, evidence and rating', () {
    final j = Job.fromJson(
      decode(
        jobJson(
          status: 'in_progress',
          rating: '{"stars": 5, "comment": "Sharp"}',
          paymentStatus: 'released',
        ),
      ),
    );
    expect(j.status, JobStatus.inProgress);
    expect(j.paymentStatus, PaymentStatus.released);
    expect(j.barber.tier, Tier.pro);
    expect(j.evidence!.verdict, Verdict.needsReview);
    expect(j.rating!.stars, 5);
    expect(j.canRate, isFalse);
  });

  test('Dispute parses', () {
    final d = Dispute.fromJson(decode(disputeJson));
    expect(d.suggestedOutcome, DisputeOutcome.partialRefund);
    expect(d.isOpen, isTrue);
    expect(DisputeOutcome.partialRefund.wire, 'partial_refund');
  });

  test('Ops summary and payouts parse', () {
    final s = OpsSummary.fromJson(decode(opsSummaryJson));
    expect(s.payoutsReleasedZar, 1540);
    final p = Payout.fromJson(decodeList(payoutsJson).single);
    expect(p.amountZar, 385);
    expect(p.barberName, 'Thabo M');
  });

  test('isoWithOffset includes the UTC offset', () {
    final iso = isoWithOffset(DateTime(2026, 10, 28, 16, 2, 11));
    expect(iso, matches(RegExp(r'^2026-10-28T16:02:11[+-]\d\d:\d\d$')));
  });

  test('backend extras: purge, operator reason, distance, consent, refunds', () {
    final e = Evidence.fromJson(
      decode(
        '{"job_id": "j", "before_url": null, "after_url": null, "checks": '
        '{"before_gps": {"result": "pass", "reason": "38 m", "distance_m": 38}}, '
        '"verdict": "pass", "decided_by": "operator", "operator_reason": "Same client", '
        '"purged_at": "2026-11-04T10:00:00+02:00"}',
      ),
    );
    expect(e.isPurged, isTrue);
    expect(e.operatorReason, 'Same client');
    expect(e.checks[CheckKind.beforeGps]!.distanceM, 38);

    final j = Job.fromJson(
      decode(
        jobJson(paymentStatus: 'partially_refunded').replaceFirst(
          '"can_rate": false',
          '"can_rate": false, "consented_demo": true',
        ),
      ),
    );
    expect(j.consentedDemo, isTrue);
    expect(j.paymentStatus, PaymentStatus.partiallyRefunded);
    expect(PaymentStatus.parse('refunded'), PaymentStatus.refunded);

    final d = Dispute.fromJson(
      decode(
        disputeJson.replaceFirst(
          '"outcome": null',
          '"outcome": "refund", "resolution_reason": "Uneven", "resolved_at": "2026-10-29T09:00:00+02:00"',
        ),
      ),
    );
    expect(d.isOpen, isFalse);
    expect(d.resolutionReason, 'Uneven');
    expect(d.resolvedAt, isNotNull);

    final v = VoiceNoteResult.fromJson(
      decode(
        voiceNoteJson.replaceFirst(
          '"language_detected": "isiZulu + English"',
          '"language_detected": "", "clean_transcript": "My name is Thabo."',
        ),
      ),
    );
    expect(v.cleanTranscript, 'My name is Thabo.');
    expect(v.languageDetected, isNull);
  });

  test('describeReason labels check keys and passes free text through', () {
    expect(
      CheckKind.describeReason('cut_match uncertain'),
      'Matches the ordered cut: uncertain',
    );
    expect(CheckKind.describeReason('same_person'), 'Same person');
    expect(CheckKind.describeReason('Upload fallback'), 'Upload fallback');
  });
}
