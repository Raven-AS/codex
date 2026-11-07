# Phase 10F — Android readiness handoff

2026-11-05. **The main Android debug application compiles; the application is not yet fully functional or production-ready.** No device/emulator, backend or Docker was launched. No backend/admin contents, database, system configuration or installed SDK source was changed. Nothing was installed/downloaded; no dependency was added. Prior Phase 10A–10E corrections remain intact.

## Prioritized consolidated gap inventory

A = Flutter/project work using supported APIs (dependency additions still need approval); B = external infrastructure; C = backend limitation; D = runtime verification. Closed A items and open D checks are separate: compilation does not prove execution.

| Priority | Category | Gap and current disposition |
| --- | --- | --- |
| P0 | A — closed this phase | Native file-provider metadata and malformed picker results: shared validated Android adapter now serves client/lawyer photos, qualification documents and community images. Missing display-name metadata no longer blocks a readable stream. Cancellation, missing channel/provider failure, malformed results and 5/10 MB limits have focused tests. |
| P0 | A — closed this phase | Main Android compilation/native bridge wiring: debug APK successfully built with the existing toolchain. Keystore, picker, checkout and invoice-export classes are present in DEX. Opt-in offline Gradle resolution and SDK/JDK auto-download prevention support dependency-frozen validation. |
| P0 | A — approval required | **Actual Flutter audio/video transport is absent.** No compatible media dependency is installed. Candidate: pinned `livekit_client: 2.13.2`, plus its resolved transitive Dart/native dependencies, subject to explicit approval. Call lifecycle screens/credentials are not a media implementation. See the integration plan below. |
| P0 | B — open | Genuine full-stack tests need a disposable Spring Boot test instance with MySQL/Redis, reference data and real active CLIENT/LAWYER accounts, including verified lawyers. Flutter reaches these services only through Spring Boot. Nothing was started or probed here. |
| P0 | B — open | SMTP/OTP, Cloudinary storage and LiveKit server/provisioning/network access require valid backend-side configuration. No provider operation, email delivery or media connection has been verified. |
| P0 | C — open | Production boost payment processing is not implemented by the public sandbox handoff. No reviewed user completion/cancel/activation API exists. A real provider/callback/payment-verification contract requires backend-owner work; a Flutter success screen cannot close this gap. |
| P0 | C — open | Existing per-boost daily-analytics endpoint omits ownership enforcement. Flutter's owned-detail precheck protects its workflow, not the exposed API. Backend-owner remediation is required before production. |
| P0 | D — open | Keystore read/write, encrypted cold-start restore, refresh rotation, logout/relogin/account-switch races and unavailable/invalidated Keystore behavior require real Android execution. The SDK-only implementation is now compiled, not runtime-proven. |
| P1 | D — open | Actual Android rendering, back navigation, external document providers, browser handoff, invoice export/cancellation/interruption, upload/retrieve/delete, networking and app/activity/process lifecycle need device testing. |
| P1 | B/D — open | REST TLS, backend HTTP CORS where applicable, SockJS path/origin authorization, reconnect/refresh and real messaging/notification delivery remain unverified. WebSocket-only SockJS is implemented; no XHR fallback or native push is claimed. |
| P1 | C — open | Messaging lacks idempotency keys, a complete edit/receipt event stream and reliable outgoing-request pagination totals. Receipt data is viewer-specific; conversation detail defaults unreadCount to zero. REST reconciliation/UI safeguards mitigate but cannot repair these server semantics. |
| P1 | C — open | Community feed/general-post visibility differs; own-post lists are client-filtered. There is no bookmark-state field, user-report/full-other-lawyer-profile API, media-removal PATCH or complete offline change stream. Sponsored profile visits lack the required boostId linkage. |
| P1 | C — open | No ownership/linkage-safe asset inventory or abandoned-upload lookup exists. Generic `/files` deletion has no owner/link assertion in its reviewed controller/storage service and uses default destroy options despite DOCUMENT uploads using `resource_type=raw`. Do not expose arbitrary-publicId asset deletion as safe management. Unknown uploads and non-atomic upload/link failures cannot be fully reconciled in Flutter. |
| P1 | C — open | Server LocalDateTime values lack a timezone discovery contract. Scheduling windows/cutoffs remain authoritative; signals only record receipt, and scheduled calls have no end endpoint. Lawyer availability writes force available=true; nullable profile fields have backend merge limits. |
| P1 | C/D — open | No security recovery-code/deletion-status API or current-session/device metadata. Refresh revocation does not prove immediate JWT invalidation. OTP/TOTP, revocation/deletion grace and role/privacy/verification decisions require live tests. Support exposes create/list/owned detail only, without replies, priorities or user status changes. |
| P2 | A — outside debug checkpoint | Distribution identity/signing still use the template application ID and release debug-key configuration. Supply the intended application ID and private release-signing setup before distribution; no secrets/signing configuration were invented. |
| P2 | D — open | Offset pages can shift; ambiguous writes cannot guarantee exactly-once execution across app restarts/devices. Already dispatched HTTP/provider writes cannot be canceled on logout. Interrupted export may leave a partial document. Other-platform adapters and atomic desktop no-clobber behavior remain outside Android proof. |

## Flutter/project fixes and preservation

- Added `lib/core/platform/android_file_picker.dart`: validate the complete native result before casting, bound received bytes, preserve nullable filenames/cancellation and translate provider/channel errors into safe API exceptions. Feature factories still validate real MIME signatures; multipart authentication and ownership guards are unchanged.
- Reused that adapter in profile photos, lawyer document selection and community image creation, eliminating the uncaught malformed-filename TypeError path. Added six focused regression groups, including the actual photo widget and lawyer adapter.
- Native picker display-name query failures now fall back to a safe name and continue with the bounded authoritative stream read. No filesystem path assumption, broad storage permission or SDK/package dependency was added.
- Added opt-in `ATTORLINK_OFFLINE_BUILD=true` resolution in project Gradle settings; disabled automatic Android SDK/JDK component installation and removed duplicate compatibility flags. Existing heap/worker limits remain. No SDK source or system service was modified.
- Existing Android networking remains debug-only local HTTP with emulator default `http://10.0.2.2:18081/api/v1/`; explicit private-LAN/loopback overrides support physical devices. Production/profile/release require explicit HTTPS. INTERNET permission, system-CA trust and backup exclusion remain; camera/microphone permissions are not requested for missing media functionality.

## Tests, analysis and APK

- **75 relevant automated tests passed**, including six new tests in `test/android_readiness_test.dart`. Included existing Android auth/configuration, profile/community/session isolation, Phase 10E/export and app-navigation tests. These use fixtures/channel doubles; they are not live integrations. No full regression rerun was necessary.
- **Full-project `flutter analyze --no-pub`: no issues found.** Only changed Dart files were formatted. Android XML parses. No failed test or analysis finding remains from this phase.
- Built the normal `lib/main.dart` debug APK successfully in 82.6 seconds, using Java21, cached Gradle9.3.1, AGP9.1.0/Kotlin2.4.0 configuration, API36/Build Tools36.0.0 and NDK28.2.13676358. Gradle heap2 GiB, metaspace768 MiB, workers2, parallel=false, Kotlin in-process. SDK XML v4/v3 compatibility warning was nonfatal; no tool update was attempted.
- APK: `build/app/outputs/flutter-apk/app-debug.apk` — 166,732,147 bytes, minimum Android API24, target/compile API36; ARM32 (`armeabi-v7a`), ARM64 and x86_64 native libraries. ZIP integrity passed; debug kernel and MainActivity/SecureSessionBridge/BoostPlatformBridge DEX descriptors are present. This is not a release/distribution build.
- SHA-256: `b21a28fae4be24f72b8416b1e72ad28aa6166a1bfc4549a09028eeb1f315e0b6`.
- Evidence: `build/phase10f_android_build.log`, `phase10f_tests.log`, `phase10f_analysis.log`, `phase10f_apk_report.json`. No runtime launch or backend request occurred.

Reproduce using only already-cached components:

```sh
cd /home/frost/coding/codex/attorlink-flutter
ATTORLINK_OFFLINE_BUILD=true flutter --no-version-check --suppress-analytics build apk --debug --no-pub --target lib/main.dart
```

For physical-device LAN testing, rebuild with `--dart-define=ATTORLINK_API_URL=http://192.168.1.10:18081/api/v1/` using the actual disposable backend's private address; the shown address is an example, not a verified service. The default APK targets emulator-host networking. For HTTPS staging, also set `--dart-define=ATTORLINK_ENV=production --dart-define=ATTORLINK_API_URL=https://your-test-api.example/api/v1/`. Missing cached components must stop the build for approval, not trigger installation.

## Exact media dependency and integration plan — not implemented

The verified LiveKit publisher lists [livekit_client 2.13.2](https://pub.dev/packages/livekit_client); its [Flutter setup guide](https://docs.livekit.io/transport/sdk-platforms/flutter/) describes camera/microphone permissions and room connection. No media SDK exists in this project's dependency manifest. Proposed command **only after explicit approval**: `flutter pub add livekit_client:2.13.2`. Approval must cover transitive Dart/native artifacts; compatibility must then be built/tested rather than assumed. No components/UI package is needed for this app's functional scope.

Use the existing authenticated immediate/scheduled `/join` APIs, consume serverUrl/token/identity/room/grants transiently, and connect a real LiveKit Room. Use Android SDK runtime permission requests, connect listeners, permitted local camera/microphone publication and actual remote-track rendering. Show transport connection only after SDK confirmation, and show track/permission failures separately. Disconnect/dispose on logout, generation change, route exit and explicit hangup; reconcile backend status after reconnect/lost mutations. Avoid inventing background call/push support. Backend ACCEPTED/STARTED still does not prove media connected. Backend media configuration, generated-token compatibility, TURN/TLS reachability and two-party media must be verified independently.

## External-service setup requirements

Keep all provider credentials on the disposable backend. Required variable names from existing configuration: `MAIL_ENABLED`, `MAIL_NOTIFICATION_ENABLED`, `MAIL_HOST`, `MAIL_PORT`, `MAIL_USERNAME`, `MAIL_PASSWORD`; `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET`; `VIDEO_PROVIDER`, `VIDEO_LIVEKIT_ENABLED`, `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` and optional `VIDEO_LIVEKIT_*`; `WEBSOCKET_ENDPOINT_PATH`, `WEBSOCKET_ALLOWED_ORIGINS`. No values were printed or configured. MySQL/Redis and server JWT/encryption settings remain backend-owner responsibilities; Flutter must not store these secrets or connect directly to database/cache/SMTP.

Payment handoff uses the backend-provided demo URL and always refreshes backend status after return. Cloudinary upload compatibility uses real multipart fields/MIME/limits and displays actual errors; invoice PDF retrieval stays authenticated through Spring Boot. Native export uses user-selected content URIs and rechecks session before sending bytes after the picker. These code paths are compiled and fixture-tested, not provider-tested.

## Later runtime checklist — execute only in the approved testing phase

1. Confirm disposable backend/database ownership and reachability, reference records, test roles/verification and required providers. Obtain separate authorization for infrastructure startup or missing-package installations. Resolve backend authorization gaps before production use.
2. Select a test Android API24+ ARM/ARM64 device and x86_64 emulator as applicable. With runtime approval, install the main debug APK, e.g. `adb -s SERIAL install -r build/app/outputs/flutter-apk/app-debug.apk`; launch manually. Do not use the standalone auth probe as application integration proof. Rebuild for the correct API address before physical-device tests.
3. Verify first-launch rendering, signup → genuine SMTP OTP → login/optional2FA → role/onboarding. Force access expiry/rotation, process restart, device lock, invalidated Keystore, logout and same/different-account login. Confirm old requests/events/picker results cannot populate a replacement session. Inspect app-private encrypted persistence without printing tokens.
4. Exercise client/lawyer profile/reference/qualification/practice CRUD, address precision, unavailable days and verification transitions. Pick JPEG/PNG/WebP/PDF from local/cloud providers; include cancellation, metadata absence, unreadable/empty/oversized files and provider interruption. Verify real upload, retrieval and dedicated removal with storage enabled and unavailable.
5. Exercise discovery/feed/comments/follow/report/analytics with two authorized accounts, empty/error/forbidden/deleted targets, rapid actions and shifting pages. Check server visibility discrepancies explicitly; do not count missing fields as successful UI features.
6. Test chat requests/privacy/acceptance, history/cursors/tombstones, edits/receipts, notification badges/read-all/targets, genuine STOMP CONNECT/subscriptions and REST convergence. Include network loss, refresh during reconnect, logout/account switch, background/resume and process death. Confirm no query-string user JWT or fabricated mobile push.
7. Test immediate/scheduled call lifecycle and server windows separately from media. Until the approved SDK/provider integration exists, actual audio/video is blocked. Later verify both parties' tracks/permissions, camera/mic toggles, speaker routing, reconnect/disposal and hangup without claiming status-only calls are connected.
8. Test verified-lawyer purchases, duplicate-pending conflicts, lost responses, history/analytics/activity and genuine backend invoice states. Open/cancel demo checkout and confirm it never implies payment. Retrieve a real authenticated PDF; export, cancel, interrupt and resume with account changes. Review partial files after interrupted writes.
9. Test privacy/preferences, wrong-password401, OTP expiry/rate limits, email/TOTP enrollment/disable, individual/all session revocation and deletion scheduling/restoration on disposable accounts. Verify support create/list/owned detail and SMTP failure without resubmitting a possibly saved ticket.

Next checkpoint: explicitly approved Android device/full-stack integration, with a separately approved media dependency implementation if desired. This phase stops at source/build readiness; no claim of production readiness or full live functionality is made.
