# Product spec

Four flows ship. Everything else is mocked or cut. Each flow has one AI job that judges can see.

## Users

| User | Wants | Channel |
| --- | --- | --- |
| Barber (supply) | More money per cut, steady bookings, a reputation that travels | App, with in-app voice notes in any South African language |
| Client (demand) | A good, safe barber at home without guesswork | App; WhatsApp reminders as a stretch goal |
| Operator | Oversight of verified barbers, jobs, disputes and payouts | Web dashboard (operator view of the same app) |

## Launch scope

- Service: men's barbering only. Nails come next; women's hair is out of scope.
- Area: Midrand / Centurion, with one real barber for the demo.

## Flow 1: Barber onboarding (voice and portfolio)

1. The barber records a voice note in the app covering name, area, years cutting, styles and availability.
2. Muse Voice Transcribe transcribes it, and Muse Spark extracts a structured profile. The profile is read back to the barber to confirm.
3. The barber uploads 5 before/after photo pairs. Muse Spark scores each on fade blend, line-up sharpness, symmetry and finish (0–10), with a written reason per score.
4. The output is a tier (Starter / Pro / Elite), a suggested home-call price band and a profile card.
5. The operator approves the barber before they appear in search.

## Flow 2: Client quote (selfie and reference)

1. The client sends a selfie and a reference photo of the cut they want.
2. SAM 3.1 segments the hair region in both photos.
3. Muse Spark names the cut, estimates the minutes and flags fit issues, such as hair too short for the style.
4. Price = barber tier rate + time + travel band (by suburb distance).
5. The quote comes back in under 30 seconds.

## Flow 3: Match and book

1. A ranked list of verified barbers in travel range shows tier, verified jobs, rating, price and the first free time.
2. The client asks for a day (today included) and one or more time windows: morning 08–12, afternoon 12–17, evening 17–20 (Sunday 09–17). Windows with less than an hour left can't be picked.
3. The request goes to the barber the client chose, who has 10 minutes to accept. If they decline or don't answer, every verified barber in range is notified. "Ask all nearby barbers" skips straight to that.
4. The barber who takes it picks the exact start from their free times inside the windows, with travel time between jobs kept clear. The job is confirmed and the client pays the deposit (mocked). A request nobody takes expires when its windows pass.
5. A reminder goes out the day before. WhatsApp delivery is a stretch goal.

## Flow 4: Proof of job (the core)

1. **At the door:** the barber captures a before photo with the in-app live camera. Gallery uploads are not allowed. The timestamp and GPS are checked against the booking.
2. **After the cut:** an after photo is captured under the same rules.
3. **Checks:**
   - Same person in both photos (Muse Spark compares face crops within this one job).
   - The hair region changed (SAM 3.1 masks).
   - The result matches the ordered cut (Muse Spark).
4. **Pass:** payment is released, a rating is unlocked and the job is added to the barber's verified record.
5. **Fail or dispute:** the client records a voice note. Muse Voice Transcribe and Muse Spark turn it into a case summary, and the operator reviews it with the evidence.

The verdict rule is set out in [architecture.md](architecture.md#proof-of-job-verdict-rule).

## AI jobs visible in the demo

| Job | Model | Visible in demo |
| --- | --- | --- |
| Voice onboarding | Muse Voice Transcribe + Muse Spark | isiZulu voice note becomes a profile card |
| Skill grading | Muse Spark (vision) | Scores with a reason for each photo |
| Hair segmentation | SAM 3.1 | Mask overlay on the before and after photos |
| Cut identification and quote | Muse Spark | Reference photo becomes a named cut and a price |
| Proof of job | SAM 3.1 + Muse Spark | Pass or fail, with the evidence frames |
| Dispute summary | Muse Voice Transcribe + Muse Spark | Voice complaint becomes a case summary |

## Out of scope

- Real payments (a mocked deposit link and payout ledger stand in)
- Nails, makeup and women's hair
- App-store builds (installable Flutter web instead)
- Identity documents and police clearance (roadmap)
