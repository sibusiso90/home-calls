# Build plan

Nine days, 27 Oct – 4 Nov 2026 (SAST). Proof of job is built first because it is the core claim. Feature freeze is Mon 2 Nov; Tue and Wed are for the video, the README and buffer.

## Mon 26 Oct: setup (no code)

- [x] Planning docs in the public repo

## Tue 27 Oct: skeleton

- [ ] Flutter web app shell: login, barber and client roles
- [ ] Live-camera capture screen with timestamp and GPS
- [ ] FastAPI backend on Modal with a health endpoint
- [ ] Meta Model API hello-world: one vision call, one transcription call, one SAM 3.1 call
- [ ] Postgres schema: barbers, portfolio_items, clients, jobs, evidence, ratings, disputes

## Wed 28 Oct: proof of job

- [ ] Before/after pipeline: SAM 3.1 hair masks, same-person check, cut-match check
- [ ] Evidence record per job: images, masks, model reasons, verdict
- [ ] Verdict gates payment release and rating insert
- [ ] Camera and GPS tested on Android Chrome and iPhone Safari

## Thu 29 Oct: onboarding

- [ ] Voice note to profile: transcribe, extract fields, confirm back to the barber
- [ ] Portfolio grading: 5 photo pairs to scores, reasons, tier and price band

## Fri 30 Oct: quote and match

- [ ] Selfie and reference photo to named cut, minutes and price with travel band
- [ ] Ranking by tier, verified jobs, rating and distance
- [ ] Booking confirmation and reminders

## Sat 31 Oct – Sun 1 Nov: real world

- [ ] Onboard the real barber end to end and fix what breaks
- [ ] Film a real home call with proof of job (with consent)
- [ ] Operator dashboard: barbers, jobs, evidence viewer, disputes

## Mon 2 Nov: freeze

- [ ] Dispute flow: voice complaint to case summary
- [ ] Stretch: WhatsApp booking reminders, only if ahead of plan
- [ ] Bug fixes only after 18:00; feature freeze

## Tue 3 Nov: package

- [ ] Record and edit the 3-minute video
- [ ] README: what was built in the window, architecture, run steps, limits, consent note
- [ ] Test the video link in a logged-out browser

## Wed 4 Nov: submit

- [ ] Submit by 15:00 SAST (hard deadline Thu 5 Nov, 04:00 SAST)
