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
| 27 Oct 2026 | All four flows, the operator view, disputes and in-app reminders work end to end against mock models. Next: Postgres, Modal deploy, live Meta models, real phones. |
| 2 Nov 2026 | Feature freeze. |
| 4 Nov 2026 | Submission. |

## What ships

Four flows ship, each with one AI job you can see on screen. See [docs/product-spec.md](docs/product-spec.md).

1. **Barber onboarding.** A voice note in any South African language becomes a profile. Five before/after photo pairs are graded and set the barber's tier and price band.
2. **Client quote.** A selfie and a reference photo become a named cut, a time estimate and an all-in price that includes travel.
3. **Match and book.** A ranked list of verified barbers in range, then a booking.
4. **Proof of job.** Live-camera before and after photos, checked for timestamp, GPS, same person, a changed hair region and a match with the ordered cut. Only a pass releases payment and unlocks a rating.

## Meta models

| Model | What it does in Fade Call |
| --- | --- |
| Muse Spark | Profile extraction, skill grading with reasons, cut identification and quote, same-person and cut-match checks, dispute summaries |
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

## Out of scope for the hackathon

- Real payments. The deposit link and the payout ledger are mocked.
- Nails, makeup and women's hair.
- App-store builds. The app ships as installable Flutter web instead.
- Identity documents and police clearance. These are on the roadmap.

## Consent and data

Real faces appear only with signed consent. The repository holds code and synthetic samples only, never real photos or voice notes. See [docs/consent-and-data.md](docs/consent-and-data.md).

## Docs

- [Product spec](docs/product-spec.md)
- [Architecture](docs/architecture.md)
- [Build plan](docs/build-plan.md)
- [Consent and data](docs/consent-and-data.md)
- [Decision log](docs/decisions.md)
- [API contract](docs/api-contract.md)
- [Meta Model API notes](docs/meta-api-notes.md)
- [Demo video script](docs/demo-script.md)

## Run it

Needs `uv`, Flutter 3.44+ and ffmpeg.

```sh
make seed     # synthetic demo data (no real faces)
make dev      # API on :8000 and the web app in Chrome
make check    # what CI runs: lint, format, tests, web build
```

Without `MODEL_API_KEY` the backend runs every model in mock mode, and the app shows a "Mock models" badge. See [backend/README.md](backend/README.md) and [app/README.md](app/README.md).
