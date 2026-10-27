# Demo video script

Three minutes, recorded Tue 3 Nov. One real barber and one real client, both with signed consent (see [consent-and-data.md](consent-and-data.md)). Everything on screen runs on the live Meta models; if a shot needs the mock, it doesn't go in the video.

## Shot list

| Time | Shot | On screen | Voice-over |
| --- | --- | --- | --- |
| 0:00–0:15 | Roadside barber, then a client at home | No app yet | "Some of the best barbers in South Africa cut on the roadside for R20. Clients would pay R400 for a home visit. The gap is trust." |
| 0:15–0:45 | Barber onboarding | Voice note recorded, then the profile card; 5 portfolio pairs, then scores with reasons, tier and price band | "A voice note becomes a profile. Muse Spark grades five cuts, with a reason for every score, and sets the tier and price." |
| 0:45–1:10 | Client quote | Selfie and reference photo, then SAM 3.1 hair masks, named cut, minutes, face-shape advice and suggested cuts; tap "Quote this cut instead" | "SAM 3.1 finds the hair. Muse Spark names the cut, says what suits your face, and quotes it, travel included." |
| 1:10–1:25 | Match and book | Ranked barbers; ask Thabo for this afternoon; Thabo's phone gets the request with a countdown, picks a time, accepts; client pays the deposit (mocked) | "Only verified barbers show up. Ask for this afternoon: your barber has ten minutes, then every verified barber nearby gets it, and whoever takes it sets the time." |
| 1:25–2:20 | Proof of job (the core) | Live-camera before photo at the door (timestamp and GPS), the cut, the after photo, then each check with its reason, then PASS | "No gallery uploads. Same person, hair changed, cut matches. Only a pass releases payment." |
| 2:20–2:35 | Rating unlocks | Client rates; the job joins the barber's verified record | "No verified job, no rating." |
| 2:35–2:50 | Dispute and operator | Voice complaint, then the case summary; the operator view with evidence | "If something goes wrong, a voice note becomes a case the operator can rule on." |
| 2:50–3:00 | Close | Logo and repo link | "Fade Call. Verified home calls, starting with barbers." |

## Before recording

- [ ] Live models on (no "Mock models" badge in any shot)
- [ ] Barber onboarded on the deployed app, approved by the operator
- [ ] Booking slot and GPS match the filming location
- [ ] The window asked for in the booking shot still has at least an hour left (afternoon closes for new requests at 15:30, evening at 19:00)
- [ ] Voice note language decided after the isiZulu test: isiZulu if it holds, English with code-switching if not
- [ ] Signed consent from everyone whose face or voice appears
- [ ] Captions on; the video link opens in a logged-out browser

## Film-day data

Run right before recording, where you film (the GPS check passes within 300 m of the booking):

```bash
cd backend
uv run python -m fadecall.seed --demo --lat <your lat> --lng <your lng>   # optional: --slot 14:30
```

It wipes the database, runs the normal seed, then adds the film-day set and prints the logins:

| Shot | Role | Login | State |
| --- | --- | --- | --- |
| Voice onboarding | barber | Ayanda K, 082 555 0101 | Brand new, nothing recorded |
| Portfolio and grade | barber | Bongani S, 082 555 0102 | Profile confirmed, 4 of 5 pairs scored |
| Quote | client | Naledi, 084 555 0103 | No quote on screen yet (a seeded quote's matches URL is printed as a backup) |
| Proof of job | barber | Thabo M, 082 123 4567 | Today's job with Naledi, confirmed, deposit paid; slot about 10 minutes before the seed ran |
| Rating | client | Naledi | Same job; rating unlocks after the pass |
| Dispute and history | client | Lerato, 083 123 4567 | One verified and rated job, one in review, one disputed |
| Operator | operator | any name + `OPERATOR_PASSCODE` | 1 job in review, 1 open dispute, KPIs filled |

Live photos pass the time check from 30 minutes before the slot to 3 hours after it; the seed prints the exact window.

## Click-by-click

Timings match the shot list above. Phone shots at phone width; operator shots on a laptop.

| Time | Screen | Tap | On screen (model) |
| --- | --- | --- | --- |
| 0:15 | Barber Ayanda → Profile | I understand and agree → hold the mic, speak, release | Transcript and read-back with **Voice Transcribe** + **Muse Spark** chips and latency |
| 0:28 | Same | Confirm my profile | Profile saved |
| 0:32 | Barber Bongani → Profile | Add Before / Add After → Score this pair | Four scores with reasons, **Muse Spark** chip and latency |
| 0:40 | Same | Grade my portfolio | Tier badge, price band, "What the grader said" (**Muse Spark**) |
| 0:45 | Client Naledi → Get a quote | Agree → suburb → selfie → reference → Get my quote | Progress; then the cut name, minutes, fit check, **Muse Spark** + **SAM 3.1** chips with latency |
| 1:00 | Same, scroll | Show hair mask / photos | **SAM 3.1** hair masks on both photos |
| 1:04 | Same, scroll | Face advice → a suggested cut → Quote this cut instead | New quote for the suggested cut, no new selfie (**Muse Spark**) |
| 1:10 | See barbers near you | Scroll the ranked list | Tier, verified jobs, rating, distance, price breakdown |
| 1:15 | Same | Ask Thabo → Today → Afternoon (or Evening) → Send request | "Waiting for Thabo M" with a 10-minute countdown in My bookings |
| 1:19 | Barber Thabo → Jobs | New requests → a start time → Accept | Confirmed job; client gets "Thabo M is coming" |
| 1:22 | Client Naledi → My bookings → job | Pay deposit | Deposit paid (mocked) |
| 1:25 | Barber Thabo | Bell → New booking / Deposit paid → the job | Today's job, deposit paid |
| 1:30 | Capture before photo | Client agrees → shutter → Use photo | Live camera with time + GPS overlay; before checks pass |
| 1:50 | Capture after photo | Client agrees → shutter → Use photo | "Verifying…" steps |
| 2:00 | Result | Scroll the checks | **Verified**; **SAM 3.1** masks; same person and cut match (**Muse Spark**), hair changed (**SAM 3.1**); "Checked by" with latency |
| 2:20 | Client Naledi → My bookings → job | 5 stars → Submit rating | Rating unlocked only now |
| 2:35 | Client Lerato → disputed job | Scroll to "Your report" | Case summary with **Voice Transcribe** + **Muse Spark** chips |
| 2:42 | Operator → Overview | — | KPIs: verified jobs, pass rate, avg verdict time, payouts |
| 2:45 | Jobs → Needs review → the job | Drag the compare divider; tap for fullscreen; Pass with a reason | Before/after compare with **SAM 3.1** masks; checks with model chips |
| 2:50 | View barber | — | Barber page: tier, ratings, jobs, scored portfolio |

## AI on screen checklist

- [ ] Voice note: transcript, read-back, **Voice Transcribe** + **Muse Spark** chips, latency
- [ ] Portfolio: four scores, a reason for each, **Muse Spark** chip, latency
- [ ] Grade: tier, price band, summary attributed to **Muse Spark** scores
- [ ] Quote: named cut, minutes, fit issues, **Muse Spark** + **SAM 3.1** chips, "quoted in" latency
- [ ] Quote: **SAM 3.1** hair masks on selfie and reference
- [ ] Quote: face-shape advice and suggested cuts; re-quote of a suggestion
- [ ] Proof: **SAM 3.1** masks before and after; hair-change check tagged **SAM 3.1**
- [ ] Proof: same-person and cut-match checks tagged **Muse Spark** with confidence
- [ ] Proof: verdict banner and "Checked by" latency
- [ ] Dispute: case summary tagged **Voice Transcribe** + **Muse Spark**
- [ ] Operator: compare slider over the masks; avg verdict time KPI
- [ ] No "Mock models" badge in any frame (live keys set)
