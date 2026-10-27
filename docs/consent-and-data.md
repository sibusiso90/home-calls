# Consent and data

Fade Call handles faces and voices, so these rules apply from the first commit.

## Consent

- Real faces appear only with signed consent from the barber and from each demo client.
- Seed data comes from the builder's own photos and from consenting friends. No scraped or third-party images.
- A consent screen is shown before any capture.

## Storage

- Photos and voice notes live in a private bucket and are served only through short-lived signed URLs.
- This repository holds code and synthetic samples only. Real photos and voice notes are never committed.
- Raw proof-of-job photos are deleted after the verdict, except for the consented demo set.

## Face comparison

- The same-person check compares the before and after photos within one job only.
- No face database, no search across jobs, no identification.

## Cut pictures

- Each catalog cut shows a drawn illustration with no real face.
- An operator can replace it with a real photo. Cut pictures are public, so a photo is used only with the person's signed consent to appear in the catalog.

## Face-shape advice

- A quote may describe the client's face shape and hairline to recommend cuts. This is covered by the consent shown before the selfie.
- The prompt limits the advice to hair, face shape and hairline. It never identifies the person or comments on age, race or attractiveness.
