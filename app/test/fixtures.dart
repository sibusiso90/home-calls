// JSON copied from docs/api-contract.md (with placeholders filled in).
import 'dart:convert';

import 'package:fade_call/data/models/models.dart';

Json decode(String s) => (jsonDecode(s) as Map).cast<String, dynamic>();

List<Json> decodeList(String s) => (jsonDecode(s) as List)
    .map((e) => (e as Map).cast<String, dynamic>())
    .toList();

const healthJson =
    '{"status": "ok", "mode": "mock", "models": {"spark": "muse-spark-1.3", "transcribe": "muse-voice-transcribe-1.0", "sam": "sam-3.1"}}';

const loginJson =
    '{"token": "tok-123", "user": {"id": "u-1", "role": "barber", "name": "Thabo", "phone": "+27821234567"}}';

const areasJson =
    '[{"id": "midrand-central", "name": "Midrand Central", "lat": -25.9992, "lng": 28.1263}]';

const portfolioItemJson = '''
{
  "id": "p-1", "before_url": "/media/b1?exp=1&sig=x", "after_url": "/media/a1?exp=1&sig=x",
  "scores": {"fade_blend": 8, "line_up": 7, "symmetry": 8, "finish": 9},
  "reasons": {"fade_blend": "Smooth", "line_up": "Slightly soft", "symmetry": "Even", "finish": "Clean"},
  "overall": 8.0, "model_versions": {"spark": "muse-spark-1.3"}
}''';

const barberJson =
    '''
{
  "id": "b-1", "name": "Thabo M", "area_id": "midrand-central", "area_name": "Midrand Central",
  "languages": ["isiZulu", "English"], "years_cutting": 6, "styles": ["skin fade", "taper"],
  "availability": "Weekdays after 16:00, Saturdays",
  "tier": "pro", "price_band": {"min_zar": 300, "max_zar": 400},
  "verified_jobs": 3, "rating": 4.7, "status": "approved",
  "portfolio": [$portfolioItemJson], "profile_confirmed": true
}''';

const onboardingBarberJson = '''
{
  "id": "b-2", "name": "", "area_id": null, "area_name": null,
  "languages": [], "years_cutting": null, "styles": [], "availability": null,
  "tier": null, "price_band": null, "verified_jobs": 0, "rating": null,
  "status": "onboarding", "portfolio": [], "profile_confirmed": false
}''';

const voiceNoteJson = '''
{
  "transcript": "Igama lami ngu Thabo...", "language_detected": "isiZulu + English",
  "profile": {"name": "Thabo M", "area_id": "midrand-central", "years_cutting": 6,
              "styles": ["skin fade"], "languages": ["isiZulu", "English"], "availability": "..."},
  "read_back": "You are Thabo, cutting for 6 years in Midrand Central...",
  "model_versions": {"transcribe": "muse-voice-transcribe-1.0", "spark": "muse-spark-1.3"}
}''';

const gradeJson =
    '{"barber": $barberJson, "tier": "pro", "average": 7.6, "summary": "Clean blends; line-ups slightly soft..."}';

const quoteJson = '''
{
  "id": "q-1", "cut_name": "Mid skin fade with textured top", "minutes": 50,
  "fit_issues": ["Top is short for the textured style; expect a shorter result"],
  "reasons": "Reference shows a mid fade starting at the temple...",
  "selfie_url": "/media/s", "reference_url": "/media/r",
  "selfie_overlay_url": "/media/so", "reference_overlay_url": "/media/ro",
  "area_id": "midrand-central", "elapsed_ms": 8200,
  "model_versions": {"spark": "muse-spark-1.3", "sam": "sam-3.1"}
}''';

const matchesJson = '''
[{
  "barber": {"id": "b-1", "name": "Thabo M", "tier": "pro", "verified_jobs": 3, "rating": 4.7,
             "area_name": "Midrand Central", "styles": ["skin fade"], "thumbnail_url": null},
  "distance_km": 4.2, "travel_band": "B",
  "price": {"tier_rate_zar": 320, "time_zar": 25, "travel_zar": 40, "total_zar": 385},
  "next_slot": "2026-10-28T16:00:00+02:00", "score": 0.82
}]''';

const evidenceNeedsReviewJson = '''
{
  "job_id": "j-1",
  "before_url": "/media/b", "after_url": "/media/a",
  "before_overlay_url": "/media/bo", "after_overlay_url": "/media/ao",
  "checks": {
    "before_timestamp": {"result": "pass", "reason": "Captured 16:02, slot 16:00–16:50"},
    "before_gps":       {"result": "pass", "reason": "38 m from booking address"},
    "after_timestamp":  {"result": "pass", "reason": "Captured 16:48"},
    "after_gps":        {"result": "pass", "reason": "41 m from booking address"},
    "same_person":      {"result": "pass", "reason": "Same face shape and ears", "confidence": 0.93},
    "hair_changed":     {"result": "pass", "reason": "Hair area down 31% around the sides", "change_ratio": 0.31},
    "cut_match":        {"result": "uncertain", "reason": "Top looks longer than ordered", "confidence": 0.55}
  },
  "verdict": "needs_review",
  "verdict_reasons": ["cut_match uncertain"],
  "decided_by": "model",
  "model_versions": {"spark": "muse-spark-1.3", "sam": "sam-3.1"}
}''';

String evidencePassJson() => evidenceNeedsReviewJson
    .replaceFirst(
      '"cut_match":        {"result": "uncertain", "reason": "Top looks longer than ordered", "confidence": 0.55}',
      '"cut_match":        {"result": "pass", "reason": "Mid fade as ordered", "confidence": 0.88}',
    )
    .replaceFirst('"verdict": "needs_review"', '"verdict": "pass"')
    .replaceFirst('["cut_match uncertain"]', '[]');

String jobJson({
  String status = 'needs_review',
  String? evidence = evidenceNeedsReviewJson,
  bool canRate = false,
  String rating = 'null',
  String paymentStatus = 'deposit_paid',
}) =>
    '''
{
  "id": "j-1", "status": "$status",
  "barber": {"id": "b-1", "name": "Thabo M", "tier": "pro"}, "client": {"id": "c-1", "name": "Sipho"},
  "cut": "Mid skin fade", "minutes": 50, "quote_zar": 385, "travel_band": "B",
  "slot_start": "2026-10-28T16:00:00+02:00", "slot_end": "2026-10-28T16:50:00+02:00",
  "address": "12 Example Rd, Midrand", "lat": -25.99, "lng": 28.12,
  "deposit_url": "https://pay.example/mock/j-1", "payment_status": "$paymentStatus",
  "evidence": ${evidence ?? 'null'}, "rating": $rating,
  "dispute": null, "can_rate": $canRate
}''';

const disputeJson = '''
{"id": "d-1", "job_id": "j-1", "transcript": "The fade is not even...", "summary": "Client says the fade is uneven...",
 "client_claim": "Left side higher", "evidence_notes": "After photo shows slight asymmetry", "suggested_outcome": "partial_refund",
 "outcome": null, "created_at": "2026-10-28T18:00:00+02:00"}''';

const opsSummaryJson =
    '{"barbers_pending": 2, "jobs_needs_review": 1, "open_disputes": 1, "payouts_released_zar": 1540}';

const payoutsJson =
    '[{"job_id": "j-1", "barber_id": "b-1", "barber_name": "Thabo M", "amount_zar": 385, "status": "released", "created_at": "2026-10-28T17:00:00+02:00"}]';
