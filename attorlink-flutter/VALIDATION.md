# Phase 9 validation — 2026-11-05

Phase11C-1: **48 distinct focused backend checks passed** (23 new), including9 real transaction/concurrency checks in disposable H2, owned analytics, user JWT/session invalidation and serverless STOMP gates. Java source/test compilation passed. Initial test-context proxy errors were fixed with affected-only rechecks. No running MySQL/Redis/SMTP/backend/device or Android test was performed; no dependencies/schema/config changes. Legacy user JWTs must refresh/login, and old pending2FA/reset state must restart. Admin JWT compatibility retained. See `PROGRESS.md` for changed files and evidence logs.

Phase 11B: approved LiveKit SDK2.13.2 media integration is implemented and **Android debug compilation passed** after approved API35/CMake3.22.1 installations. New APK: `build/app/outputs/flutter-apk/app-debug.apk` (217,883,976 bytes; ARM32/ARM64/x86_64; WebRTC/noise/JNI packaged). **3 backend media tests passed** for approved signing/room-factory corrections; **56 focused Flutter fixtures and 11 affected media/call rechecks passed**, scoped analysis clean. Earlier package/build blockers below are superseded. No actual backend/media server, Android device or two-party media test ran; runtime success remains unverified. See [PROGRESS.md](PROGRESS.md) and [COMPLETION_ROADMAP.md](COMPLETION_ROADMAP.md).

Phase 10F current Android checkpoint: **75 relevant tests passed**, full-project analysis clean and normal `lib/main.dart` debug APK built successfully with cached dependencies/offline Gradle. Android Keystore/picker/checkout/PDF bridges are compiled and packaged (minimum API24; ARM32/ARM64/x86_64). No native execution, live API/provider test, emulator/device/service launch or installation occurred. [ANDROID_READINESS.md](ANDROID_READINESS.md) is the current gap inventory and integration handoff; historical build blockers below are superseded by this APK result. Media transport and production payments remain incomplete.

Phase 10E calls/boosts/security/support corrections and **69 distinct focused passing tests** (26 new) are recorded in [REMAINING_FEATURES_AUDIT.md](REMAINING_FEATURES_AUDIT.md). Scoped analysis is clean after affected-file corrections. New Android checkout/document-export bridge code has only Dart channel-fixture validation; Kotlin compilation, actual browser/picker/export, media and live payment/security operations remain unverified. No backend/device/service launch or APK build occurred. A backend per-boost daily-analytics ownership gap remains despite the Flutter owned-detail safeguard. Historical runtime/build results below do not validate these later changes.

Phase 10D messaging/notification/realtime corrections and **28 distinct focused passing tests** are documented in [MESSAGING_REALTIME_AUDIT.md](MESSAGING_REALTIME_AUDIT.md). Scoped analysis is clean after targeted corrections. No actual backend, SockJS or Android runtime test/build was performed; earlier runtime results do not validate these source changes.

Phase 10C discovery/community source corrections and **41 distinct focused passing tests** are documented in [DISCOVERY_COMMUNITY_AUDIT.md](DISCOVERY_COMMUNITY_AUDIT.md). Scoped analysis is clean after targeted corrections. No live/backend/device/build checks were performed; historical Phase 9 runtime/build evidence below does not validate these later changes.

Phase 10B client/lawyer source stabilization and **127 focused passing tests** are documented in [PROFILE_INTEGRATION_AUDIT.md](PROFILE_INTEGRATION_AUDIT.md). Scoped analysis is clean after targeted fixes. This later phase did not repeat runtime, full-suite or build checks; the Phase 9 results below remain historical.

Subsequent Android networking/authentication source changes and their separate targeted checks/blockers are documented in [ANDROID_AUTH.md](ANDROID_AUTH.md). The 191-test and Linux/web build results below precede those changes.

**Reference frontend validated locally; live backend integration remains unverified.** Spring Boot was not started. No dependencies/tools were installed or downloaded, and backend/admin-panel/system configuration/permissions/installed SDK source were untouched.

## Results

| Check | Result and scope |
| --- | --- |
| Local dependencies | All 28 package-config roots present. |
| Full Flutter regression | **191 tests passed**, full suite run once. Contract/widget fixtures are not live API evidence. |
| Static analysis | Full `flutter analyze --no-pub`: no issues. New platform probe separately analyzed clean after style corrections. |
| Linux compilation | Debug build of normal `lib/main.dart` passed. |
| Web compilation | JavaScript build passed with `--no-pub --no-web-resources-cdn --no-wasm-dry-run`. An interrupted attempt was completed; no successful check was repeated. Browser runtime/Wasm were not tested. |
| Linux desktop | Normal production entrypoint launched in the existing X11/XWayland desktop session and rendered. No mock login/session/backend was injected. |
| Native file adapters | Local fixture probe passed PDF save/readback, refusal of an existing destination, PDF document read, PDF rejection as a photo, and empty-path cancellation. This does not validate a real invoice or Cloudinary operation. |
| Android | Bridge/channel/MIME/size/cancellation code and INTERNET declaration reviewed. Not compiled or run: Android platform 36 exists, but no cached Gradle wrapper distribution was found; Gradle 9.3.1 would need external preparation. No Android build/download was attempted. |

## Genuine desktop interactions

- Sign-in rendering and empty email/password validation.
- Navigation to signup and its empty-input validation.
- Recovery navigation, typed fictitious `example.invalid` email, real request to configured unavailable localhost backend, visible connection error, and working return to sign-in. No OTP delivery or authentication succeeded or was simulated.
- Existing-signup OTP navigation and blank-code validation.
- Signed-out forms/error text inspected at 390×650, normal desktop width, and the OTP screen at 1120×800. No overflow indicator or unhandled Dart exception observed.
- The log contains a nonfatal GTK/ATK `atk_socket_embed` assertion and normal Impeller initialization. This is an unresolved desktop accessibility limitation; it did not prevent the observed rendering/input. Window-manager Alt+F4 ended the process with status 143 (SIGTERM); graceful application-disposal behavior was therefore not established. This deliberate close was not a startup crash.

Client/lawyer shells, role restrictions, profile/practice/qualification flows, and later domain screens were exercised by fixture-based tests and inspected statically. They were **not** reached through genuine authenticated desktop/backend sessions.

## Integration audit and remaining gaps

[ENDPOINT_COVERAGE.md](ENDPOINT_COVERAGE.md) maps client/lawyer controller families to UI. Reviewed mappings and DTOs include auth/session/OTP, privacy/preferences, multipart uploads, notification envelopes, chat cursor/tombstones and private STOMP destinations, call credentials, boosts/invoices, and support. No new endpoint/method/envelope mismatch was confirmed in the reviewed contracts; this is not live authorization or field-by-field server conformance proof.

No production application defect was confirmed by this checkpoint, so no speculative app refactor was made. Stale README feature/build claims were corrected, and a local platform I/O probe was added.

Still blocked/unverified: all successful live APIs; MySQL/Redis-backed server operation; SMTP/OTP and real TOTP enrollment; server refresh/revocation/privacy; real uploads; browser CORS/origins, picker/download/WebSocket interactions; native checkout opening; actual invoice storage/download; and Android/iOS/Windows behavior. At Phase 9, LiveKit media was unavailable and tokens persisted only in process memory. Android now has compiled Keystore persistence awaiting device tests; media, sponsored-visit linkage and safe standalone asset management remain missing, and SockJS remains WebSocket-only. Sandbox checkout is a demo rather than proof of payment.

Evidence: `build/phase9-*.log`, `build/phase9-controller-inventory.json`, `build/runtime-smoke/phase9-*.png`, and `build/phase9-platform-*`. These generated artifacts remain local. The controller inventory includes alternate encodings/admin-only reference mutations and is not a percentage-coverage claim.

## Launch with already installed tools/dependencies

```sh
cd /home/frost/coding/codex/attorlink-flutter
flutter --no-version-check --suppress-analytics run -d linux --no-pub
```

Or launch the compiled bundle directly:

```sh
./build/linux/x64/debug/bundle/attorlink_flutter
```

The default API root is `http://localhost:8081/api/v1/`. To use an already-running service, add `--dart-define=ATTORLINK_API_URL=https://your-api.example/api/v1/` to `flutter run`/build; changes require recompilation. `ATTORLINK_SOCKET_PATH` defaults to `/ws`. Android emulator host access uses `10.0.2.2`, physical devices need a reachable host, and Android deployment should use HTTPS. Web requires backend HTTP CORS and separately permitted SockJS origins. Do not start the backend as part of this guide. Without a backend, expect sign-in/restoration connection errors. Desktop sessions remain process-local; Android uses API-origin-scoped encrypted persistence. For the latest Android APK/configuration and device checklist, use [ANDROID_READINESS.md](ANDROID_READINESS.md).

## Files to study

| Files/modules | Purpose |
| --- | --- |
| `lib/main.dart`, `lib/app/attorlink_app.dart`, `app_services.dart`, `app_shell.dart` | Startup, service ownership, guarded responsive navigation. |
| `lib/core/config`, `lib/core/network`, `lib/core/realtime`, `lib/app/live_updates.dart` | API configuration, envelope/PDF transport, errors, SockJS/STOMP lifecycle and REST reconciliation. |
| `lib/features/auth/domain/session_controller.dart`, `auth/data/session_store.dart` | JWT rotation, generation guards, sign-out/revocation; Android Keystore persistence, process-local storage on other platforms. |
| `lib/features/client`, `lib/features/lawyer` | Role onboarding/profiles; qualification/practice schemas, editors, documents and verification. |
| `lib/features/discovery`, `community`, `messaging`, `notifications` | Discovery, social workflows, REST cursor history and realtime consumers. |
| `lib/features/calls`, `boosts`, `settings`, `support` | Call lifecycle/media limitation, purchases/PDFs, security and support tickets. |
| `test/`, `tool/phase9_platform_probe.dart` | Contract/widget regression fixtures and real local file-adapter probe. |

Work stops after Phase 9. A running backend and provider configuration are required before any live integration sign-off.
