# Attorlink Flutter

Functional reference frontend for the existing Attorlink Spring Boot API: authentication, client/lawyer profiles and records, discovery/community, messaging/notifications, LiveKit calling, scheduling, account security and support. Android uses encrypted Keystore-backed persistent sessions; other platforms retain memory-only sessions. Payments remain the existing sandbox demonstration; bKash is deferred.

Verified against the disposable backend: 51 real API/production realtime checks and 21 physical-Android checks, including SMTP recovery/OTP/login, session restoration, logout persistence, client data screens and lawyer account switching. The final reference build additionally passed 78 targeted Flutter checks, clean analysis and Android compilation. Physical-device post CRUD, real messaging/receipts/edit/deletion synchronization, notification-badge reconciliation, interrupted-startup recovery and password-reset session invalidation were exercised. These are focused results, not exhaustive end-to-end proof. Live Cloudinary uploads and two-party LiveKit media require dedicated authorized test infrastructure. See `build/integration/phase11f2/RESULTS.md` for evidence and limitations.

## Run on Android with the isolated backend

Use existing local dependencies and the existing isolated environment; no new Docker setup is required. For a USB-connected phone, keep Spring Boot bound to host loopback and establish forwarding after every device/ADB reconnect:

```sh
adb -s DEVICE_SERIAL reverse tcp:18081 tcp:18081
flutter build apk --debug --no-pub --dart-define=ATTORLINK_ENV=development --dart-define=ATTORLINK_API_URL=http://127.0.0.1:18081/api/v1/
adb -s DEVICE_SERIAL install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s DEVICE_SERIAL shell am start -n com.example.attorlink_flutter/.MainActivity
```

For local signup and recovery, read the test email in host Mailpit at `http://127.0.0.1:18025`. The isolated MySQL database is disposable: stopping its container discards test accounts and records. Register fresh accounts after a clean restart.

Use `ATTORLINK_OFFLINE_BUILD=true` for builds with this workspace's existing offline Gradle configuration. Emulator builds can instead use `http://10.0.2.2:18081/api/v1/`. Remote/production builds require an explicit HTTPS API URL and valid server certificates. Flutter connects only to Spring Boot, never directly to MySQL/Redis/SMTP. Provider credentials belong only in protected backend configuration.

## Structure

- `lib/app/`: application bootstrap, service scope, Material themes, responsive navigation.
- `lib/core/config/`: validated API configuration.
- `lib/core/network/`: injectable JSON client, response/page models, typed errors, native and browser HTTP adapters.
- `lib/features/discovery/`: public name/practice-area search, paginated cards, and discovery-data-only lawyer summaries, integrated into client and lawyer navigation.
- `lib/features/lawyer/practice/`: practice resource schemas, reference-aware forms, guarded CRUD repository, and whole-week availability editor.
- `lib/features/lawyer/qualifications/`: exact resource schemas, guarded CRUD/document repository, reusable record forms, lists/details, and attachment management for ten qualification/history groups.
- `lib/features/lawyer/`: lawyer-only profile and Bar Council models/repository, personal/professional editors, onboarding, photos/documents, and verification checklist/status.
- `lib/features/client/`: client-only repository, profile/address/preferences models and editors, onboarding, photo selection, multipart uploads, and account overview.
- `lib/features/auth/`: typed authentication contracts, Android encrypted session storage, session controller, forms, and navigation guard.
- `lib/shared/widgets/`: loading, error/retry, and empty-state widgets.
- `test/`: API/config contracts and widget tests using existing Flutter test dependencies.
- `tool/`: SDK-only checks for environments where the Flutter runner cannot execute.

Navigation uses a bottom bar below 720 logical pixels, a rail from 720, and an extended rail from 1100. Selection survives resizing. The shell is available only to authenticated, active CLIENT or LAWYER users. UNASSIGNED users must choose a role; administrator and inactive accounts are restricted. Every generated route passes through the same guard, including unknown/deep-link locations (which currently open the guarded root rather than feature-specific content).

## Configuration

`ATTORLINK_API_URL` is a compile-time Dart define containing the complete API root. Defaults: Android emulator `http://10.0.2.2:18081/api/v1/`; other platforms `http://localhost:8081/api/v1/`. A trailing slash is normalized automatically.

When running with an already prepared SDK, pass `--no-pub` and, when needed, `--dart-define=ATTORLINK_API_URL=https://your-api.example/api/v1/` to Flutter commands. Dependency installation is outside this phase.

Android emulators reach the host using `10.0.2.2`; physical devices need a reachable server address. Android Internet permission is declared. Release/profile builds require HTTPS. Debug builds permit local development HTTP; certificate validation is never bypassed. Browsers require appropriate backend CORS access and HTTPS APIs when the app is served over HTTPS.

## API usage

Obtain the app-owned client with `AppServices.apiOf(context)`, or inject an `ApiClient` into a future repository. Paths are relative, such as `lawyers/discover`, with query parameters supplied separately.

```dart
final response = await api.request<List<Object?>>(
  'GET',
  'practice-areas',
  decode: (data) => data as List<Object?>,
);
```

Authenticated calls opt in with `authenticated: true`; the app-owned session supplies the current bearer token. Access tokens are renewed near expiry, and a rejected bearer can trigger one shared refresh followed by one retry. HTTP 403 permission errors do not trigger refresh. Tokens are never logged by this client. `AppServices.sessionOf(context)` exposes session actions.

The client decodes `{success, message, data, timestamp}`, including null data for message-only responses. `ApiPage.fromJson` supports Spring `number` and notification `page` pagination. Backend timestamps retain their original timezone-free strings. Multipart photo bodies are supported as immutable binary requests. Authenticated PDF downloads and SDK-only SockJS WebSocket/STOMP transport are implemented; see the current validation guide for transport/platform limits.

Requests use `dart:io` HttpClient on native platforms and browser Fetch through `dart:js_interop` on web. Both apply a configurable overall timeout and cancel on disposal. Redirects are rejected; browser cookies are omitted. HTTP errors, validation fields, malformed envelopes, and connectivity failures map to `ApiException`. Only eligible HTTP 401 responses can trigger one automatic retry after session recovery; password-confirmed security mutations instead verify the bearer with a safe GET and require explicit action retry; network/timeout failures and other mutation errors are never retried automatically. Retry UI requires an explicit callback.

## Authentication and restoration

Signup and email OTP verification create an account but do not sign in. Users return to login, complete email/authenticator 2FA when required, and select CLIENT or LAWYER once. Recovery uses the exact three-step forgot-password flow. A recovery resend repeats the existing forgot endpoint; there is no invented recovery-resend endpoint. Failed 2FA submissions return to login because the backend consumes its challenge before code validation. Failed password confirmation restarts recovery because reset tokens are single-use.

Android session token pairs are encrypted using platform Keystore/atomic no-backup files; challenge/recovery secrets remain memory-only. Other platforms retain memory-only sessions. There is no plaintext persistence fallback or new package dependency. **Android compilation, encrypted-session restoration after force-stop/relaunch, logout persistence and password-reset invalidation have been exercised on a physical device.** Other platforms require sign-in after a process restart. The longer-session option extends server validity. Android stores the encrypted token pair for either option and clears it on logout. A shared in-memory store supports widget-tree recreation, and app resume revalidates with `/auth/me` in the background, preserving an open editor while the check is pending. A failed resume check still closes protected navigation. Backend responses, rather than decoded JWT role claims, determine access.

Concurrent renewals share one rotating refresh request. The token pair is replaced together; ambiguous renewal failures clear local credentials so an already-consumed refresh token cannot be reused. Logout waits for a pending rotation and attempts server revocation with the latest token, then clears memory even on failure. Offline logout explicitly reports that server revocation could not be confirmed. Generation checks prevent late login/refresh/401 responses from restoring or clearing a newer session.

## Client profile and onboarding

Active CLIENT users load their own `/client/profile` before entering the shell. DRAFT profiles open a four-step setup flow: optional personal details (saved through the real profile PUT), optional address, legal preferences, and photo. Existing profiles open the client account area. The backend sets COMPLETE when profile details or a photo are saved; it has no separate onboarding completion flag. Later optional steps are not tracked server-side, so a fresh app session follows the returned profile status rather than inventing completion data.

The Account area shows profile details, saved address, and legal preferences, with separate editors and photo management. PUT requests include the full DTO because blank nullable fields replace stored values. Profile contact details do not change sign-in credentials. The backend preserves an existing gender when given null, so the editor offers no clear-gender option once one is set. Missing addresses render as an empty state. Preference requests always include all four lists; empty lists clear selections. Practice areas, jurisdictions, and courts come from the existing public active-reference endpoints. Languages are free text, normalized and limited to the backend's 60 characters.

Photo selection uses browser file input through SDK JS interop, Android ACTION_OPEN_DOCUMENT through a project-local method channel, and a readable-file-path dialog on desktop. The desktop path option does not provide a graphical file browser. No additional storage permissions, plugins, packages, temporary image files, or system configuration are introduced. Selected bytes are checked for JPEG/PNG/WebP signatures and the backend's 5 MB size limit, previewed, then explicitly uploaded using multipart field `file`. Removal uses DELETE `/client/profile/photo`. No photo URL or success is fabricated; server errors, including unavailable Cloudinary configuration, are displayed.

The Android bridge has not been compiled or exercised on-device in this environment. Browser selection/upload and desktop path selection also remain untested in a running application. Phase 9 completed widget tests and Linux/web builds with existing dependencies; Android remains uncompiled.

## Lawyer profile and verification

Active LAWYER users load their own profile and Bar Council record through the existing authenticated endpoints. DRAFT profiles open personal information → professional information → Bar Council registration → verification checklist. Users can continue to their unverified account without submitting; doing so changes no server status. The backend has no separate onboarding-completed flag, so a fresh view of a DRAFT profile can offer setup again.

The lawyer Account area provides profile overview, personal/professional editors, profile and cover photos, Bar Council registration/documents, and verification status. Profile PUT sends only the edited section: omitted/null fields retain their saved values. Blank date, gender, experience, and professional-phone inputs therefore cannot clear an existing value. Bar Council PUT is a replacement; its form reads the latest record before saving and preserves existing document URLs. Saving registration details resets the record's verification status to PENDING according to the server. Profile status and record status remain separate.

The checklist requires saved first name, bar registration number, and a saved Bar Council record. It mirrors the submit service's actual blocked states: SUBMITTED, IN_REVIEW, VERIFIED. Other statuses are still subject to server eligibility. Before POST `/lawyer/profile/submit`, the screen re-reads the saved information. The returned `lawyerProfileId`, `profileStatus`, and `message` are authoritative. Submission never grants verification locally, and ambiguous failures require a fresh status check before another attempt. Pending review, rejection reason, and Bar Council rejection feedback come from the self-service DTOs. Additional admin request-info notes/history are not exposed through those endpoints; no admin APIs are called by this frontend.

Profile/cover photos reuse the client image selection/editor and 5 MB JPEG/PNG/WebP validation through callback-based upload operations. A shared single-file multipart encoder supports both photos and Bar Council identity-card, sanad, and green-book documents. Documents accept PDF/JPEG/PNG up to 10 MB, use the actual upload/removal endpoints, and are optional for submission under current backend rules. Browser document selection uses SDK interop; Android reuses the existing local document-picker channel with an optional document-mode flag; desktop uses a readable local file path. Saved document URLs can be viewed/copied. Qualifications and professional-history resources are implemented in Phase 4C-1; lawyer practice management is implemented in Phase 4C-2.

The Android bridge remains uncompiled. Linux/web builds and fixture widget tests passed in Phase 9; live API, Cloudinary, browser, and graphical picker execution remain untested. The secure-persistence limitation from Phase 3 remains unchanged.

## Qualifications and credentials (Phase 4C-1)

The lawyer Account → Qualifications area supports High Court and Supreme Court registration, bar associations, credentials/certifications, education, work experience, training, professional memberships, awards, and publications. Shared schema-driven forms keep the audited field names, required fields, lengths, primitive/enum values, and validation limits together. All requests reuse the current lawyer/owner/status guards and authentication client.

High Court and Supreme Court use singleton GET/PUT upserts; their APIs do not expose whole-record deletion. The eight collections support GET lists, POST creation, PUT updates, and DELETE records. None exposes a separate detail GET, so the frontend resolves details from the current authenticated list. Education years use 1950–2100; only work experience enforces start/end ordering, and `current=true` clears endDate. Award year has no invented calendar-range restriction. Verification metadata is read-only and always comes from server responses.

Information saves preserve current document URLs. The six High/Supreme Court document slots and credential, education, training, membership, and award attachments use their exact dedicated upload/removal endpoints. Files use the existing PDF/JPEG/PNG 10 MB selector and multipart transport. Bar-association certificate/card fields and publication document URLs have no dedicated file routes: they use authenticated `/files/upload?type=DOCUMENT`, followed by the actual JSON record update. Existing URLs can also be linked manually. If upload succeeds but attaching fails, the UI keeps the returned URL and allows link-only retry without uploading again. Generic link clearing uses record PUT and does not delete the stored asset; those record DTOs do not retain public IDs. Unresolved upload-link information is held in the current view only.

Qualification record creation/editing and file management are separate explicit actions. Ambiguous record-save failures require reloading before retrying. Lists, missing singleton records, required/invalid input, forbidden responses, and retry states are handled without inserting mock records or assigning verification locally. The shared document-selection wrapper reuses the existing platform adapters; no native/platform code or dependencies were added in this phase. Phase 9 passed fixture widget tests and Linux/web builds. Native document read was checked with a local fixture; authenticated runtime, browser interactions, and live API operations remain unverified.

## Lawyer practice management (Phase 4C-2)

Lawyer Account → Practice provides specializations, practice jurisdictions/courts, languages, offices/addresses, offered legal services, and weekly availability. The six record collections use their actual GET-list, POST-create, PUT-update, and DELETE endpoints. They have no individual detail GET, so the frontend resolves current details from the authenticated own list. Reference dropdowns read the existing public active practice-area/jurisdiction/court catalogs. Already added references are disabled for creation; an existing selection missing from the active catalog is retained for editing because the relationship services check existence rather than active status. Duplicate/ownership/eligibility decisions remain server-authoritative.

Forms reuse existing validation/widgets and follow required fields, lengths, 0–70 specialization experience, optional proficiency values, CHAT/PHONE/VIDEO/IN_PERSON consultation modes, and nonnegative duration/fees. Fee input respects DECIMAL(12,2); office coordinates respect DECIMAL(10,7) and remain JSON numbers, including small decimal values. Primary specialization/office changes are sent as one real save and re-read from server lists; the frontend does not invent flag-clear endpoints or optimistically alter other records. Blank country/currency values preserve existing values on update and use the server's Bangladesh/BDT defaults on creation. Jurisdiction verification metadata is read-only.

Availability uses only GET and whole-week PUT `/lawyer/availability` with `{slots: [...]}`. Rows carry MONDAY–SUNDAY, timezone-free LocalTime start/end strings, and `available: true`. The backend forces every submitted slot to available, so disabled days are omitted rather than sent as false. An empty list clears the week after confirmation. Multiple ranges per day are retained. Only start-before-end is enforced; no overlap or appointment-booking rule is invented. HH:mm input is normalized to HH:mm:ss, and existing seconds/fractional seconds (up to nanoseconds) round-trip without timezone conversion. Returned unavailable slots remain unavailable in the editor and are omitted on replacement.

The weekly editor shows loading/empty/error/success states, supports draft range removal and unavailable-day toggles, and requires a reload after ambiguous save failures. Practice record mutations have the same confirmation/reload safeguards. No new Android-specific code, SDKs, packages, permissions, or platform adapters were introduced. Phase 9 passed Linux/web builds and fixture widget tests; office CRUD and weekly availability have now been verified through the real isolated APIs; exhaustive Android practice CRUD remains unverified.

## Checks without package resolution

Use the installed Dart executable directly, avoiding SDK bootstrap scripts:

```sh
/path/to/flutter/bin/cache/dart-sdk/bin/dart format --output=none --set-exit-if-changed lib test tool
/path/to/flutter/bin/cache/dart-sdk/bin/dart analyze lib test tool
/path/to/flutter/bin/cache/dart-sdk/bin/dart tool/check_foundation.dart
/path/to/flutter/bin/cache/dart-sdk/bin/dart tool/check_auth.dart
/path/to/flutter/bin/cache/dart-sdk/bin/dart tool/check_client.dart
/path/to/flutter/bin/cache/dart-sdk/bin/dart tool/check_lawyer.dart
/path/to/flutter/bin/cache/dart-sdk/bin/dart tool/check_qualifications.dart
/path/to/flutter/bin/cache/dart-sdk/bin/dart tool/check_practice.dart
mkdir -p build/foundation_checks
/path/to/flutter/bin/cache/dart-sdk/bin/dart compile js tool/check_web_compile.dart -o build/foundation_checks/transport.js
/path/to/flutter/bin/cache/dart-sdk/bin/dart compile js tool/check_auth_web_compile.dart -o build/foundation_checks/auth.js
/path/to/flutter/bin/cache/dart-sdk/bin/dart compile js tool/check_client_web_compile.dart -o build/foundation_checks/client.js
/path/to/flutter/bin/cache/dart-sdk/bin/dart compile js tool/check_lawyer_web_compile.dart -o build/foundation_checks/lawyer.js
/path/to/flutter/bin/cache/dart-sdk/bin/dart compile js tool/check_qualifications_web_compile.dart -o build/foundation_checks/qualifications.js
/path/to/flutter/bin/cache/dart-sdk/bin/dart compile js tool/check_practice_web_compile.dart -o build/foundation_checks/practice.js
```

The web check compiles the networking adapter without executing a network request. Generated output stays under the ignored `build/` directory. Full Flutter widget tests require a runner able to access its SDK cache; see `PROGRESS.md` for this environment's blocker.
