# Decision log

Newest first.

| Date | Decision | Why |
| --- | --- | --- |
| 27 Oct 2026 | Either side may cancel before the before-photo; a paid deposit is refunded, except that a client cancelling under 2 hours before the slot forfeits it (`forfeited`). A barber cancelling never costs the client. Only the client reschedules, to a free slot; the barber then re-confirms | A late cancel leaves the barber with a dead slot they can't refill; the barber's own cancel is their cost, not the client's. Re-confirming keeps the barber in control of their calendar |
| 27 Oct 2026 | Notifications are an in-app inbox for every role, with a day-before reminder from an hourly cron; WhatsApp is wired behind a `Notifier` interface but off unless configured | The app is where people already are; WhatsApp needs a Meta business number and template approval, so it stays a stretch goal |
| 26 Oct 2026 | Proof photos and overlays are purged 7 days after a final verdict, unless a dispute is open or the job is in the consented demo set | Disputes arrive after a pass and need the evidence; the consent rule still deletes faces promptly |
| 26 Oct 2026 | Build starts 26 Oct evening; the window opened 26 Oct 12:00 ET (18:00 SAST) | The official window opens before our planned 27 Oct start |
| 26 Oct 2026 | Every model call sits behind one interface with a mock mode | Build and test end to end before API keys arrive |
| 26 Oct 2026 | English-first voice notes; isiZulu best-effort | Muse Voice Transcribe's 25 languages include no South African language |
| 26 Oct 2026 | Planning docs go in on 26 Oct; application code starts 27 Oct | Indie track: all code is new and built inside the window |
| 26 Oct 2026 | Repo stays `sibusiso90/home-calls` for now | A rename can come later; GitHub redirects old links |
| 26 Oct 2026 | Name: Fade Call (formerly Home Call) | An umbrella name for nails and makeup comes later |
| 26 Oct 2026 | App-first; WhatsApp only for reminders, as a stretch goal | Everything lives in one place; live camera and GPS need an app |
| 26 Oct 2026 | Flutter web, installable, instead of app-store builds | Judges open a link; no store review inside nine days |
| 26 Oct 2026 | FastAPI on Modal, Postgres on Supabase | Meta's cookbook is in Python; quick to stand up |
| 26 Oct 2026 | Proof of job is the only path to payout and rating | Trust is the product: no verified job, no rating |
| 26 Oct 2026 | Launch with men's barbering in Midrand / Centurion | One real barber for the demo; nails next |
