# Fade Call

Verified home-call grooming, starting with barbers.

Some of the best barbers in South Africa cut on the roadside for about R20. Plenty of clients would pay around R400 for a home visit: no driving, no queue, at a time that suits them. Demand isn't the problem. Trust is: who's good, who's safe, who shows up.

Fade Call turns a barber's skill into a verified track record. Meta's models grade their work, quote each job and check every cut before payment is released or a rating is unlocked.

**No verified job, no rating.**

> Entry for the Meta Global AI Developer Hackathon: *Build for Your World*, Indie Developer track.
> All code in this repository is written during the hackathon window, which opened 26 Oct 2026 at 18:00 SAST and closes 5 Nov 2026 at 04:00 SAST.

## Status

| Date | State |
| --- | --- |
| 26 Oct 2026 | Planning docs. The window opens at 18:00 SAST; the build starts that evening: app shell, backend, schema, model layer (mock until API keys arrive). |
| 27 Oct 2026 | All four flows, the operator view, disputes and in-app reminders work end to end. Postgres migrations and a local Docker stack are done. Live Meta models: the smoke test, all 12 prompt evals and the full end-to-end script pass. Clients can now pick a cut from a catalog or take a suggested one, with face-shape advice. Next: Modal deploy, real phones, a real barber. |
| 2 Nov 2026 | Feature freeze. |
| 4 Nov 2026 | Submission. |

## What ships

Four flows ship, each with one AI job you can see on screen. See [docs/product-spec.md](docs/product-spec.md).

1. **Barber onboarding.** A voice note in any South African language becomes a profile. Five before/after photo pairs are graded and set the barber's tier and price band.
2. **Client quote.** A selfie plus a reference photo, a cut picked from the catalog, or no choice at all (Muse Spark suggests one) becomes a named cut, a time estimate and an all-in price that includes travel. Every quote adds face-shape advice and up to three other cuts that would suit, each one tap away from its own quote.
3. **Match and book.** A ranked list of verified barbers in range, then a booking.
4. **Proof of job.** Live-camera before and after photos, checked for timestamp, GPS, same person, a changed hair region and a match with the ordered cut. Only a pass releases payment and unlocks a rating.

## Meta models

| Model | What it does in Fade Call |
| --- | --- |
| Muse Spark | Profile extraction, skill grading with reasons, cut identification, suggestion and quote with face-shape advice, same-person and cut-match checks, dispute summaries |
| Muse Voice Transcribe | Barber onboarding voice notes and client dispute voice notes |
| SAM 3.1 | Hair-region segmentation on quote photos and proof-of-job before/after photos |

## Stack

| Layer | Choice |
| --- | --- |
| App | Flutter web, installable on phones (barber, client and operator views) |
| Backend | Python FastAPI on Modal |
| Models | Meta Model API |
| Database | Postgres (Supabase) |
| Photos | Private bucket, signed URLs only |

Architecture, data model and the proof-of-job verdict rule: [docs/architecture.md](docs/architecture.md).

## Measured on the live models

Run on 27 Oct 2026 against the Meta Model API (`muse-spark-1.3`, `muse-voice-transcribe-1.0`, `sam-3.1`), using synthetic illustrated faces:

| Step | Time | Result |
| --- | --- | --- |
| Voice note to profile | 15 s | Name, years cutting and area extracted |
| Grade five portfolio pairs | 57 s | Tier and average score with reasons |
| Quote from selfie and reference | 12 s | Named catalog cut, minutes, face advice, suggestions |
| Proof of job, same person | 10 s | All capture checks, same person and hair change pass; cut match `uncertain`, so the job goes to review |
| Proof of job, different person | 8 s | Same person `fail`, job goes to review, no payout |
| Dispute voice note to case | 17 s | Summary and a suggested outcome |

Reproduce with `scripts/live_e2e.py` (below). Cut match on cartoon faces is expected to be uncertain; real photos are the next test.

## Limits

- isiZulu and other South African languages: Muse Voice Transcribe does not list them. Spoken English transcribes well; a real isiZulu voice note is still to be tested. See [docs/meta-api-notes.md](docs/meta-api-notes.md).
- Proof-of-job checks never auto-fail. Anything short of a pass goes to a human operator.
- Synthetic faces are used everywhere except the consented demo set.

## Out of scope for the hackathon

- Real payments. The deposit link and the payout ledger are mocked.
- Nails, makeup and women's hair.
- App-store builds. The app ships as installable Flutter web instead.
- Identity documents and police clearance. These are on the roadmap.

## Consent and data

Real faces appear only with signed consent. The repository holds code and synthetic samples only, never real photos or voice notes. Face-shape advice talks only about hair, face shape and hairline; the model is told never to identify anyone or comment on age, race or looks. See [docs/consent-and-data.md](docs/consent-and-data.md).

## Docs

- [Product spec](docs/product-spec.md)
- [Architecture](docs/architecture.md)
- [Build plan](docs/build-plan.md)
- [Consent and data](docs/consent-and-data.md)
- [Decision log](docs/decisions.md)
- [API contract](docs/api-contract.md)
- [Meta Model API notes](docs/meta-api-notes.md)
- [Demo video script](docs/demo-script.md)
- [Consent form](docs/consent-form.md)
- [Submission checklist](docs/submission-checklist.md)
- [Deploy runbook](docs/deploy.md)
- [Local Docker stack](docs/local-docker.md)

## Run it

Needs `uv`, Flutter 3.44+ and ffmpeg.

```sh
make seed     # synthetic demo data (no real faces)
make dev      # API on :8000 and the web app in Chrome
make check    # what CI runs: lint, format, tests, web build
```

Without `MODEL_API_KEY` the backend runs every model in mock mode, and the app shows a "Mock models" badge. See [backend/README.md](backend/README.md) and [app/README.md](app/README.md).

Other ways to run it:

```sh
make local-up                                   # Supabase + API in Docker: docs/local-docker.md
scripts/go_live.sh                              # guided deploy to Supabase + Modal: docs/deploy.md
cd backend && uv run python ../scripts/live_e2e.py --base <url>   # every flow over HTTP
```
