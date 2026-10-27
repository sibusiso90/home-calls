# Fade Call app

Flutter web app (installable PWA) for all three Fade Call roles: client, barber
and operator. It talks to the FastAPI backend in `../backend` using
[`docs/api-contract.md`](../docs/api-contract.md).

Requires Flutter 3.44+ / Dart 3.12+.

## Run

Start the backend first (see `../backend/README.md`), then:

```bash
cd app
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

`API_BASE_URL` defaults to `http://localhost:8000`. When the backend has no
model API key, the app shows a **Mock models** badge.

Demo sign-in: pick a role, then enter a name and a South African number
(`082 123 4567` or `+27…`). The operator role also needs the passcode
(`OPERATOR_PASSCODE` on the backend; `fadecall-ops` by default).

Camera, microphone and GPS need a secure origin: `localhost` works, and so does
any `https://` host. If the camera can't start, the proof-of-job screen offers
a photo upload instead, and that job is always sent to operator review.

## Build

```bash
flutter build web --release --dart-define=API_BASE_URL=https://<your-api>
```

The output in `build/web` is a static, installable PWA. Routes use the `#/`
hash strategy, so any static host works without rewrite rules.

## Test and check

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

## Layout

```
lib/
  core/        config (API_BASE_URL), theme, formatting (R385, dates)
  data/        models (fromJson per the contract), FadeCallApi interface,
               HttpFadeCallApi (error envelope -> ApiException), device services
  state/       Riverpod providers and notifiers (session, data, quote flow)
  ui/          auth, barber, client, ops screens and shared widgets
  router.dart  go_router with role-based redirects
test/          model, API client and widget tests (fake API via mocktail)
```

Signed media URLs expire after 15 minutes, so they are never cached. When a
photo fails to load, the app refetches the parent resource to get fresh URLs.
