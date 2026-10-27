# Submission checklist

Target: submit by **Wed 4 Nov 2026, 15:00 SAST**. Hard close: Thu 5 Nov, 04:00 SAST (4 Nov, 21:00 ET).

## Already done

- [x] Code public at https://github.com/sibusiso90/home-calls
- [x] README: what was built, Meta models, measured live results, limits, consent note, run steps
- [x] Live models verified: smoke test, 12/12 prompt evals, full end-to-end script (13/13 steps on 27 Oct, including a time-window request)
- [x] Demo video script with shot list and click-by-click: [demo-script.md](demo-script.md)
- [x] Consent form to print: [consent-form.md](consent-form.md)

## Scripts

| Script | When | What it does |
| --- | --- | --- |
| `scripts/go_live.sh` | Once, after creating the Supabase project | Writes secrets, migrates, seeds, logs in to Modal, deploys, runs the live end-to-end check |
| `cd backend && uv run python ../scripts/live_e2e.py --base <url> --passcode <op>` | After any deploy | Every flow over HTTP on live models, PASS/FAIL per step |
| `scripts/test_isizulu.sh <recording>` | With a real isiZulu voice note | Decides whether the video uses isiZulu or English |
| `scripts/film_day.sh <lat> <lng> [HH:MM]` | On site, just before filming | Wipes the deployed data and loads the film-day set at your GPS spot |
| `scripts/check_submission.sh --video <url> --app <url>` | Before you press submit | Video opens logged out, repo public, app live, no secrets, `make check` |

## Your steps, in order

1. [ ] Create the Supabase project, then run `scripts/go_live.sh`.
2. [ ] Phone test on the deployed URL: [deploy.md](deploy.md) section 5 (Android Chrome and iPhone Safari).
3. [ ] Record a 20-second isiZulu voice note and run `scripts/test_isizulu.sh`. Decide on the video language.
4. [ ] Onboard the real barber; send me whatever breaks.
5. [ ] Feature freeze after Mon 2 Nov, 18:00 SAST; only bug fixes after that.
6. [ ] Film day (Tue 3 Nov): signed consent forms, `scripts/film_day.sh`, keep one container warm (`FADECALL_MIN_CONTAINERS=1 make deploy MODAL_URL=...`), film with [demo-script.md](demo-script.md).
7. [ ] Edit to 3:00 or less, captions on, no "Mock models" badge in any frame.
8. [ ] Upload (YouTube unlisted or public). Not Google Drive: it often asks judges to sign in.
9. [ ] `scripts/check_submission.sh --video <url> --app <url>` until it says "Ready to submit".
10. [ ] Fill in the submission form: title, the one-liner below, video link, repo link, app link, track (Indie Developer), Meta models used.
11. [ ] Open the video link in a private window one last time, then submit.

## Submission text (copy and edit)

**Title:** Fade Call: verified home-call barbers

**One-liner:** Meta's models grade a barber's work, quote each cut and check every home call before payment is released or a rating unlocks.

**Description:** Some of the best barbers in South Africa cut on the roadside for about R20, while plenty of clients would pay around R400 for a home visit. The gap is trust. Fade Call turns a barber's skill into a verified track record. A voice note becomes a profile (Muse Voice Transcribe and Muse Spark). Five before/after pairs are graded with a reason for every score and set the barber's tier and price. A client's selfie becomes a named cut, a time, face-shape advice and an all-in price including travel (SAM 3.1 hair masks and Muse Spark). The client asks for a time window, even this afternoon; the chosen barber has 10 minutes, then every verified barber nearby is asked, and whoever takes it sets the time. At the job, live-camera before and after photos are checked for time, GPS, same person, a changed hair region and a match with the ordered cut. Only a pass releases payment and unlocks a rating; anything else goes to a human. No verified job, no rating.

**Meta models:** Muse Spark, Muse Voice Transcribe, SAM 3.1.

**Built with:** Flutter web, FastAPI on Modal, Postgres and private storage on Supabase.
