# API contract

The Flutter app and the FastAPI backend both build against this document. JSON keys are `snake_case`. Times are ISO 8601 with offset. Money is integer rand (`*_zar`).

## Conventions

- Auth: `Authorization: Bearer <token>` on everything except `/health`, `/auth/demo-login` and `/media/*`.
- Errors: `{"error": {"code": "string", "message": "human readable"}}` with a 4xx/5xx status. Codes used: `unauthorized`, `forbidden`, `not_found`, `validation`, `verdict_required` (409), `conflict` (409), `model_error` (502).
- Media URLs in responses are short-lived signed URLs (`/media/{key}?exp=...&sig=...`, 15-minute expiry). Never store them client-side.
- Every model-produced field carries the reason the model gave. `model_versions` records which models (or `mock`) produced a result.

## Health and auth

`GET /health`

```json
{"status": "ok", "mode": "mock", "models": {"spark": "muse-spark-1.3", "transcribe": "muse-voice-transcribe-1.0", "sam": "sam-3.1"}}
```

`mode` is `live` when `MODEL_API_KEY` is set and `mock` otherwise. The app shows a "Mock models" badge in mock mode.

`POST /auth/demo-login`

```json
{"role": "barber", "name": "Thabo", "phone": "+27821234567", "passcode": null}
```

- `role` is `barber`, `client` or `operator`. Operator requires `passcode` equal to the `OPERATOR_PASSCODE` setting.
- The same phone and role returns the same user.
- Response: `{"token": "...", "user": {"id": "uuid", "role": "barber", "name": "Thabo", "phone": "+27..."}}`

`GET /me` returns the same `user` object.

## Reference data

`GET /areas` returns the launch suburbs:

```json
[{"id": "midrand-central", "name": "Midrand Central", "lat": -25.9992, "lng": 28.1263}]
```

Suburbs cover Midrand and Centurion (about 12 entries).

## Barber onboarding (role: barber)

`GET /barbers/me` returns a Barber:

```json
{
  "id": "uuid", "name": "Thabo M", "area_id": "midrand-central", "area_name": "Midrand Central",
  "languages": ["isiZulu", "English"], "years_cutting": 6, "styles": ["skin fade", "taper"],
  "availability": "Weekdays after 16:00, Saturdays",
  "tier": "pro", "price_band": {"min_zar": 300, "max_zar": 400},
  "verified_jobs": 3, "rating": 4.7, "status": "approved",
  "portfolio": [PortfolioItem], "profile_confirmed": true
}
```

- `tier` is `starter`, `pro`, `elite` or `null` before grading.
- `status` is `onboarding` (profile or portfolio incomplete), `pending_approval`, `approved` or `rejected`. Only `approved` barbers appear in matches.

`POST /barbers/me/voice-note` (multipart: `audio`, any browser format; the backend converts it to WAV)

```json
{
  "transcript": "Igama lami ngu Thabo...", "language_detected": "isiZulu + English",
  "profile": {"name": "Thabo M", "area_id": "midrand-central", "years_cutting": 6,
              "styles": ["skin fade"], "languages": ["isiZulu", "English"], "availability": "..."},
  "read_back": "You are Thabo, cutting for 6 years in Midrand Central...",
  "model_versions": {"transcribe": "...", "spark": "..."}
}
```

The profile is not saved until it is confirmed.

`PUT /barbers/me/profile` takes the `profile` object (edited or as returned) and returns a Barber with `profile_confirmed: true`.

`POST /barbers/me/portfolio` (multipart: `before`, `after`, both images) returns a PortfolioItem:

```json
{
  "id": "uuid", "before_url": "signed", "after_url": "signed",
  "scores": {"fade_blend": 8, "line_up": 7, "symmetry": 8, "finish": 9},
  "reasons": {"fade_blend": "...", "line_up": "...", "symmetry": "...", "finish": "..."},
  "overall": 8.0, "model_versions": {"spark": "..."}
}
```

`DELETE /barbers/me/portfolio/{id}` removes an item.

`POST /barbers/me/grade` needs 5 portfolio items (409 `conflict` otherwise). It sets `tier` and `price_band` and moves the barber to `pending_approval`. Response:

```json
{"barber": Barber, "tier": "pro", "average": 7.6, "summary": "Clean blends; line-ups slightly soft..."}
```

Tier rule: average below 6.5 is `starter` (R250–R320), 6.5 to below 8.0 is `pro` (R320–R420), and 8.0 or higher is `elite` (R420–R550).

## Client quote, match and book (role: client)

`GET /cuts` lists the cut catalog: `[{"id": "buzz-cut", "name": "Buzz cut", "description": "...", "minutes": 20, "styles": ["buzz cut"]}]`.

`POST /quotes` (multipart: `selfie` image and `area_id` text field, plus how the client chose the cut)

- a `reference` image: the cut in the photo (`cut_source: "reference"`)
- a catalog `cut_id` text field: that cut (`"catalog"`)
- neither: Muse Spark picks the catalog cut that suits the client's face (`"suggested"`)

Sending both is a 422. Every quote carries face advice and up to three suggested catalog cuts.

```json
{
  "id": "uuid", "cut_name": "Mid skin fade with textured top", "minutes": 50,
  "cut_source": "reference", "cut_id": "mid-skin-fade-textured",
  "fit_issues": ["Top is short for the textured style; expect a shorter result"],
  "reasons": "Reference shows a mid fade starting at the temple...",
  "face_advice": "An oval face carries most cuts; a clean line-up keeps it sharp.",
  "suggestions": [{"cut_id": "low-taper-lineup", "name": "Low taper with line-up",
                   "minutes": 40, "why": "A softer taper suits your hairline."}],
  "selfie_url": "signed", "reference_url": "signed|null",
  "selfie_overlay_url": "signed", "reference_overlay_url": "signed|null",
  "area_id": "midrand-central", "elapsed_ms": 8200,
  "model_versions": {"spark": "...", "sam": "..."}
}
```

`POST /quotes/{id}/requote` `{"cut_id": "low-taper-lineup"}` returns a new quote for that catalog cut, reusing the first quote's selfie (no new upload).

The overlay URLs are PNGs of the photo with the SAM 3.1 hair mask tinted on top.

`GET /quotes/{id}/matches` returns approved barbers ranked best first:

```json
[{
  "barber": {"id": "uuid", "name": "Thabo M", "tier": "pro", "verified_jobs": 3, "rating": 4.7,
             "area_name": "Midrand Central", "styles": ["skin fade"], "thumbnail_url": "signed|null"},
  "distance_km": 4.2, "travel_band": "B",
  "price": {"tier_rate_zar": 320, "time_zar": 25, "travel_zar": 40, "total_zar": 385},
  "next_slot": "2026-10-28T16:00:00+02:00", "score": 0.82
}]
```

- Travel bands: A is under 5 km (R0), B is 5–12 km (R40), C is 12–20 km (R80). Over 20 km is out of range and not listed.
- Time charge is R5 per started 10 minutes over 30 minutes.
- Ranking score = 0.35 tier + 0.25 verified jobs (capped at 20) + 0.25 rating + 0.15 proximity, each normalised to 0–1. A rating of `null` counts as 0.6.

`POST /jobs`

```json
{"quote_id": "uuid", "barber_id": "uuid", "slot_start": "2026-10-28T16:00:00+02:00",
 "address": "12 Example Rd, Midrand", "lat": -25.99, "lng": 28.12}
```

It returns a Job with status `booked` and a `deposit_url` (mocked) set.

`GET /barbers/{id}/slots?days=7` (any signed-in user; `days` is 1–28) lists the barber's free slots, soonest first, for booking or rescheduling:

```json
{"barber_id": "uuid", "slots": ["2026-10-28T16:00:00+02:00", "2026-10-29T16:00:00+02:00"]}
```

Slots are weekdays at 16:00 and Saturdays at 09:00 (SAST), at least one hour ahead, excluding slots held by live (non-cancelled) jobs.

## Jobs (barber and client see their own; operator sees all)

`GET /jobs` lists Jobs, newest first. `GET /jobs/{id}` returns one Job:

```json
{
  "id": "uuid", "status": "booked",
  "barber": {"id": "...", "name": "...", "tier": "pro"}, "client": {"id": "...", "name": "..."},
  "cut": "Mid skin fade", "minutes": 50, "quote_zar": 385, "travel_band": "B",
  "slot_start": "...", "slot_end": "...", "address": "...", "lat": -25.99, "lng": 28.12,
  "deposit_url": "https://pay.example/mock/...", "payment_status": "deposit_pending",
  "evidence": Evidence | null, "rating": {"stars": 5, "comment": "..."} | null,
  "dispute": Dispute | null, "can_rate": false, "consented_demo": false,
  "cancelled_at": null, "cancelled_by": null, "cancel_reason": null,
  "rescheduled_at": null, "reminder_sent_at": null
}
```

- `cancelled_by` is `client` or `barber`; `cancelled_at`, `cancel_reason` are set with it.
- `rescheduled_at` is the time of the latest reschedule; `reminder_sent_at` is when the day-before reminder went out for the current slot.

- Job `status`: `booked` → `confirmed` (barber accepts) → `in_progress` (before photo in) → `verifying` → `verified` | `needs_review` | `failed`; also `cancelled`.
- `payment_status`: `deposit_pending` → `deposit_paid` (mock) → `released` (verdict pass only) | `held`; after a dispute `refunded` | `partially_refunded`; after a cancellation `refunded` | `forfeited`.

`POST /jobs/{id}/confirm` (barber) moves the job to `confirmed`.
`POST /jobs/{id}/pay-deposit` (client, mock) sets `deposit_paid`. 409 `conflict` on a cancelled job.

### Cancel and reschedule

`POST /jobs/{id}/cancel` (client or barber of the job) with `{"reason": "..."}` (required, 1–500 chars) returns the Job with status `cancelled`.

- Allowed only while the job is `booked` or `confirmed`, i.e. before the before-photo; otherwise 409 `conflict`. Operators get 403.
- A paid deposit becomes `refunded` (mock). If the **client** cancels less than 2 hours before `slot_start` (`LATE_CANCEL_HOURS`), a paid deposit becomes `forfeited`. A barber cancelling never costs the client. An unpaid deposit stays `deposit_pending`.
- The slot is freed for other bookings.

`POST /jobs/{id}/reschedule` (client only) with `{"slot_start": "2026-10-30T16:00:00+02:00"}` returns the Job.

- Allowed only while `booked` or `confirmed` (409 otherwise). The slot must be one of the barber's bookable slots in the next 28 days (422 `validation` if not, or if it is the current slot) and free (409 `conflict` if taken).
- The job goes back to `booked` (the barber re-confirms), `slot_end` moves with it, `rescheduled_at` is set and `reminder_sent_at` is cleared so the new time gets its own reminder.

## Proof of job (role: barber)

`POST /jobs/{id}/proof/before` and `POST /jobs/{id}/proof/after`, multipart:

- `photo` (JPEG)
- `captured_at` (ISO time from the device clock at capture)
- `lat`, `lng`, `accuracy_m` (omitted if GPS was denied)
- `capture_mode`: `live` or `upload_fallback`

`before` returns Evidence with only the capture checks filled. `after` runs the full pipeline and returns the complete Evidence:

```json
{
  "job_id": "uuid",
  "before_url": "signed", "after_url": "signed",
  "before_overlay_url": "signed", "after_overlay_url": "signed",
  "checks": {
    "before_timestamp": {"result": "pass", "reason": "Captured 16:02, slot 16:00–16:50"},
    "before_gps":       {"result": "pass", "reason": "38 m from booking address"},
    "after_timestamp":  {"result": "pass", "reason": "..."},
    "after_gps":        {"result": "pass", "reason": "..."},
    "same_person":      {"result": "pass", "reason": "...", "confidence": 0.93},
    "hair_changed":     {"result": "pass", "reason": "Hair area down 31% around the sides", "change_ratio": 0.31},
    "cut_match":        {"result": "uncertain", "reason": "...", "confidence": 0.55}
  },
  "verdict": "needs_review",
  "verdict_reasons": ["cut_match uncertain"],
  "decided_by": "model",
  "model_versions": {"spark": "...", "sam": "..."}
}
```

- Each check `result` is `pass`, `fail` or `uncertain`.
- Verdict rule: `pass` only if every check passes. Anything else is `needs_review`, never an automatic fail. Upload-fallback capture always goes to `needs_review`.
- Timestamp passes from 30 minutes before slot start to 3 hours after it. GPS passes within 300 m of the booking address; a missing fix is `uncertain`.
- A `pass` verdict (from the model or the operator) is the only thing that sets `payment_status: released`, adds a payout ledger row, increments `verified_jobs` and unlocks rating.

## Rating and disputes (role: client)

`POST /jobs/{id}/rating` with `{"stars": 1-5, "comment": "..."}` returns 409 `verdict_required` unless the verdict is `pass`. One rating per job.

`POST /jobs/{id}/dispute` (multipart: `audio`, optional `text`) returns a Dispute:

```json
{"id": "uuid", "job_id": "uuid", "transcript": "...", "summary": "Client says the fade is uneven...",
 "client_claim": "...", "evidence_notes": "...", "suggested_outcome": "partial_refund",
 "outcome": null, "created_at": "..."}
```

A dispute holds the payout (`payment_status: held`) until the operator resolves it.

## Operator (role: operator)

- `GET /ops/summary` returns:

  ```json
  {"barbers_pending": 2, "jobs_needs_review": 1, "open_disputes": 1, "payouts_released_zar": 1540,
   "jobs_total": 9, "verified_jobs": 5, "decided_jobs": 7, "pass_rate": 0.714, "avg_verdict_ms": 8200}
  ```

  `decided_jobs` counts jobs with any verdict; `pass_rate` is the share of those whose current verdict is `pass` (`null` with none); `avg_verdict_ms` is the mean model time from the after photo arriving to the verdict (`null` with none).
- `GET /ops/barbers/{id}` returns `{"barber": Barber, "jobs": [Job, ...], "ratings": [{"job_id", "stars", "comment", "client_name", "created_at"}]}` (jobs newest slot first).
- `GET /ops/barbers?status=pending_approval` lists Barbers.
- `POST /ops/barbers/{id}/approve` and `POST /ops/barbers/{id}/reject` take `{"reason": "..."}`.
- `GET /ops/jobs?status=needs_review` lists Jobs, each with Evidence. Without `status` it lists every job, newest first.
- `POST /ops/jobs/{id}/verdict` takes `{"verdict": "pass" | "fail", "reason": "..."}`, stores it with `decided_by: "operator"` and the reason, then applies the pass effects.
- `GET /ops/disputes` lists Disputes with their Job.
- `POST /ops/disputes/{id}/resolve` takes `{"outcome": "release" | "refund" | "partial_refund", "reason": "..."}`.
- `GET /ops/payouts` returns the mock ledger: `[{"job_id", "barber_id", "barber_name", "amount_zar", "status", "created_at"}]`.

## Notifications (any role)

Every user has an in-app inbox. Events create notifications: booking created (client and barber), barber confirmed (client), deposit paid (barber), verdict `pass` (both), `needs_review` (both, plus every operator), operator verdict (both), dispute opened (barber, client, operators) and resolved (both), cancellation (both), reschedule (barber), and the day-before reminder (both).

`GET /notifications?limit=50` (newest first, `limit` 1–200):

```json
{"items": [{"id": "uuid", "job_id": "uuid|null", "kind": "reminder",
            "title": "Your cut is tomorrow", "body": "Thabo M arrives Tue 28 Oct, 16:00 at 12 Example Rd.",
            "created_at": "...", "read_at": null}],
 "unread_count": 3}
```

`kind` is one of `booking_created`, `job_confirmed`, `deposit_paid`, `verdict_pass`, `verdict_needs_review`, `verdict_operator`, `dispute_opened`, `dispute_resolved`, `job_cancelled`, `job_rescheduled`, `reminder`.

- `POST /notifications/{id}/read` marks one as read and returns it (404 if it is not yours).
- `POST /notifications/read-all` returns `{"marked": 2, "unread_count": 0}`.

Reminders: `python -m fadecall.reminders` (hourly Modal cron) notifies both sides of every `booked`/`confirmed` job starting in the next 24 hours that has no `reminder_sent_at`, then sets it (idempotent).

WhatsApp copies (stretch goal) go out through the Meta WhatsApp Cloud API only when `WHATSAPP_TOKEN` and `WHATSAPP_PHONE_ID` are both set; otherwise notifications are in-app only.

## Model latency

AI output carries `elapsed_ms` (integer, model time for that step; `null` on older rows): PortfolioItem (Muse Spark grading), Evidence (after photo → model verdict), Dispute (transcribe + summary), the voice-note response (transcribe + profile) and Quote (already listed). Disputes also carry `model_versions`.

## Media

`GET /media/{key}?exp=<unix>&sig=<hmac>` serves a stored object only while the signature is valid and unexpired.
