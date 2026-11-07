# Attorlink completion roadmap

Initial audit prepared 2026-11-06 (Asia/Dhaka); Phase11A–11B implementation and validation updates below. Companion evidence: [BACKEND_FRONTEND_COVERAGE.md](BACKEND_FRONTEND_COVERAGE.md), whose matrix remains the historical audit snapshot.

## Current position

The original audit matrix examines **242 operations: 201 source-complete, 25 partial, 16 unconsumed**. Eleven carry backend-limit flags, two carry external/media-block flags (13 distinct blocked rows); all 242 remain unverified against a live deployment. Block flags overlap source classifications. Fourteen unconsumed handlers are optional multipart/STOMP alternatives, not fourteen missing product features. No numerical completion percentage is meaningful here.

Most supported workflows already have actual repositories, forms, navigation, guards and contract tests. Preserve them. Phase11A corrected the three identified frontend defects. Phase11B added real LiveKit media source, passed focused Flutter/backend tests and built the new Android debug APK. Genuine two-party media/provider/device testing remains pending; payment remains a sandbox demo. The historical 191-test full regression and Linux/web results predate these changes.

## 1. Notification and lifecycle corrections — completed in Phase 11A

Implemented without dependencies or backend changes:

- **F1:** ACCOUNT/unknown USER notifications omit the unsupported shortcut. FOLLOW routes to connections only for the notified lawyer's own user ID. Existing post/comment/message/call routes remain, with access rechecked before opening.
- **F2:** Qualification delete, comment delete and unfollow acquire their operation guard before confirmation. Cancellation/failure releases it; captured repository/resource/record identities and existing session-generation guards reject stale confirmations.
- **F3:** Qualification saves accept an originating-operation guard. Editors check mounted state and captured repository/resource/record identity before mutation and after asynchronous token work. Current server attachments remain preserved; failed preflights cannot dispatch a mutation.

**Validation:** 90 affected tests passed, including 19 new regressions in `test/confirmed_flutter_defects_test.dart`. Affected suites: qualification contracts/widgets, community features, notifications/realtime, profile integration and discovery/community integration. Scoped analysis of the six changed source files and new test found one test-only braces lint; corrected, with that file rechecked clean. Evidence: `build/phase11a_tests.log`, `phase11a_analysis.log`, `phase11a_analysis_recheck.log`. These are fixture/widget checks; no live/backend/device/media verification or APK build occurred. Backend/admin metadata fingerprints match their pre-change baselines.

The original task details are retained below for traceability; F1–F3 are closed for source stabilization, with real runtime acceptance still pending.

| Task | Exact locations and required work | Acceptance criteria | Dependencies / Flutter-only? |
| --- | --- | --- | --- |
| **Completed: F1 notification target dispatch** | `lib/features/notifications/presentation/notification_inbox.dart` `_canOpen`/`_open`; backend `auth/service/AuthServiceImpl.restoreAccount`, `AccountServiceImpl` and `community/service/LawyerFollowServiceImpl` notification creation. Dispatch using notification type plus resource type/identity. ACCOUNT + USER must not be treated as a lawyer-followers link; use an existing own-account destination or omit the unrelated shortcut. FOLLOW + USER retains the verified lawyer connection workflow. | Focused widget/contract fixtures for CLIENT and LAWYER ACCOUNT notifications, FOLLOW notification, unsupported targets and revoked access. No client ID is sent to lawyer-followers merely because the resource type is USER. Existing POST/chat/call fallback navigation remains intact. | No package/backend change. Yes, Flutter-only; live navigation still needs later testing. |
| **Completed: F2 confirmation serialization** | `lawyer/qualifications/presentation/qualifications_hub.dart` `_delete`; `community/presentation/comment_screen.dart` `_delete`; `connections_screen.dart` `_unfollow`. Acquire busy/operation guard before awaiting dialog; capture immutable resource/record; release on cancellation/error; recheck session before mutation. | Rapid reentrant action invokes one dialog/action; cancel dispatches nothing; account change cannot submit old-account action. Existing backend failure remains visible. Avoid repeating already-fixed practice/chat/call/settings work. | Source guard deficiency, not a claimed reproduced double deletion. Yes, Flutter-only. |
| **Completed: F3 qualification save liveness** | `lawyer/qualifications/data/qualifications_repository.dart` `saveInformation`; `presentation/qualification_editor.dart` `_save`; hub navigation. A preflight detail/list GET currently continues to PUT after editor disposal. Check originating-operation liveness between GET and PUT, or deliberately block abandoning the pending operation. Keep attachment preservation and session checks. | Deferred preflight fixture: navigate away/change resource before completion → no new PUT from the abandoned editor; retained editor saves once with preserved attachments; account switch is rejected. Do not pretend an already-dispatched mutation can be rolled back. | Yes, Flutter-only; no repository-wide architectural rewrite needed. |

Validation for this batch is complete as recorded above. No full regression, web/Linux compilation or APK rebuild was performed. Keep later runtime acceptance separate from these source corrections.

## 2. Media consumption — Phase 11B implemented and Android-compiled

Approved `livekit_client 2.13.2` and transitive packages are installed/locked. `features/calls/media/media_session.dart` is the actual SDK adapter; `call_media_controller.dart` manages authenticated media state/control/reconnect/cleanup; `call_media_screen.dart` renders local/remote tracks and device controls. Existing immediate/scheduled endpoints and authoritative lifecycle actions remain intact. Capture permissions are declared/requested through Android WebRTC. Backgrounding releases media; resume fetches fresh backend authorization. No background service/push guarantee is added.

The two explicitly approved backend corrections are applied in `video/service/LiveKitVideoMediaService.java`: SDK token construction using the original secret and correct `RoomServiceClient.create(url, apiKey, apiSecret)` argument order. Its existing test file now verifies original-key signatures/claims and mocked provisioning success/conflict/failure. No other backend source/configuration or admin file was changed by this work.

**Completed validation:** 56 focused Flutter fixtures passed; 11 affected media/call rechecks passed after race corrections; scoped analysis clean. **3 backend media tests passed** after approved Maven resolution (final run offline). Approved Android API35 and CMake3.22.1 are installed, and the final debug APK built successfully. APK: `build/app/outputs/flutter-apk/app-debug.apk` (217,883,976 bytes, ARM32/ARM64/x86_64), including WebRTC/noise/JNI native libraries. Earlier platform/CMake blockers are resolved. Evidence is in `PROGRESS.md` and `build/phase11b_*` logs.

**Remaining acceptance:** genuine two-party media with an authorized backend and configured reachable LiveKit server. Verify actual microphone/camera tracks and remote playback, permission denial/permanent denial, mute/switch controls, device interruption, SDK reconnect/fresh-credential retry, background/foreground, logout/account switch and backend lifecycle authorization. The current APK defaults to emulator API addressing; physical-device builds need the reachable API URL, and backend-issued media URLs must be reachable by both devices. Keep connection credentials out of logs/persistence. No infrastructure, emulator/device or genuine room connection has been started in this phase. Obtain separate runtime authorization; do not begin later phases automatically.

## Phase11C-1 security follow-up — source corrected and focused checks passed

Per-boost daily ownership, persistent refresh-reuse revocations, active-account/2FA/restoration checks, session-bound user JWTs and access invalidation are implemented. Existing account rows are locked for security mutations; no schema migration or dependency was added. REST and STOMP use current session/account validity; OTP/challenge/reset state is single-use and security-state-bound. Purge rechecks status/deadline under lock. Hardcoded admin JWT compatibility remains supported; Flutter API request/response contracts are unchanged.

**48 focused checks passed**, including9 actual H2 transaction/concurrency cases and applicable MockMvc/admin/channel checks. No live MySQL/Redis/SMTP or device testing occurred. Old unbound user JWTs need a valid refresh/login, and pre-deployment pending2FA/reset flows must restart. Deploy these changes consistently across auth, REST and socket nodes. Final full-stack acceptance must exercise MySQL isolation/concurrency, actual Redis atomic operations, SMTP, cross-account analytics denial, all revocation paths and authenticated reconnect/restoration. Exact file groups and log evidence are in `PROGRESS.md`.

## Phase11C-2 — messaging/community corrections source-validated

- Request visibility is applied in database queries before pagination/counting. Incoming decisions and notifications use the initiator/other participant, independent of normalized participant IDs. Flutter uses the same recipient rule. Conversation creation and request decisions serialize existing rows to avoid duplicate requests/initial messages and conflicting decisions.
- Existing sync fields now carry an `updatedAt,id` watermark covering sends, edits, delivery/seen receipts, read markers and tombstones. Conversation-locked writes advance a microsecond-precision clock; latest-state deltas are bounded together before splitting messages/tombstones. Sender history reports the recipient's actual receipt status. No DTO field, route, event type, schema or migration was added.
- REST and STOMP share committed `ChatMessageResponse` delivery to the existing participant-private queues. Rollbacks emit nothing; the controller no longer broadcasts a second copy. Deleted payloads redact text. Phase11C-1 session/account checks remain intact.
- Root-comment queries exclude replies/deleted rows before paging and use created-time/ID tie ordering. Unfollow removes the client's owned relation even when the target becomes ineligible; new follows still enforce active/verified-lawyer rules. Same-client follow creation is serialized.
- SockJS registration and HTTP matchers normalize the same configured endpoint. Custom paths work without retaining an unintended public `/ws` path; STOMP authorization is unchanged.

**Validation:** 72 distinct focused backend tests passed across eight classes, including six disposable H2 query/transaction/concurrency cases and two MockMvc/configuration checks. All backend source and 66 test source files compile offline. Flutter: 30 focused tests passed, changed Dart files formatted, scoped analysis clean. Initial strict-Mockito fixtures and isolated entity-scan harness errors were corrected; affected checks passed on recheck. Logs: `build/phase11c2_{existing_tests,regressions,h2_recheck,compile,flutter_tests,flutter_analysis}.log`. No services, MySQL/Redis, devices, real sockets, schema migration or installation ran; admin unchanged.

**Remaining acceptance:** actual MySQL locking/isolation/time precision and contention, session-bound SockJS delivery/reconnect with Redis-backed authentication, concurrent page movement, and two Android clients. Sync is a latest-state reconciliation stream, not a durable all-events log/outbox. Offset pages are not snapshots; network-uncertain text-send retries can still duplicate messages without a client idempotency key. Broker delivery can fail or arrive out of order; REST reconciliation remains required. No push/background delivery guarantee is introduced. Stop after11C-2; no automatic11D/payment/infrastructure work.

## Phase11E-1 — SMTP source correction completed

Environment SMTP settings now configure the actual sender; unauthenticated SMTP uses independent `MAIL_FROM`. Console OTP/body fallback is removed. Disabled/failed OTP delivery returns the existing email-delivery error; failed sends invalidate only their own OTP hash. SMTP/body/auth secrets and raw provider errors are excluded from normal mail logs/error records. Optional disabled templates retain SKIPPED behavior. Existing auth/admin API contracts are unchanged.

**26 focused mocked tests passed**, including seven new SMTP binding, Mailpit, safe-logging and failure regressions. Offline compilation succeeded for source and 67 test files. No real SMTP, backend, database or device was launched/contacted; Flutter/admin unchanged. Exact variables and local Mailpit example are in the latest `PROGRESS.md` section; use protected deployment credentials. Production STARTTLS requires `MAIL_SMTP_STARTTLS_REQUIRED=true`; implicit TLS uses SSL=true and STARTTLS=false. Mailpit requires auth/TLS disabled and an explicit From address.

**Next acceptance:** separately authorized disposable backend/MySQL/Redis plus the existing Mailpit listener; verify real signup/resend, email2FA, password recovery/reset and verification messages. Repository Compose does not provision Mailpit, and its external availability/port mapping is unverified. Later production SMTP requires authorized credentials/sender and valid TLS; no production connection is permitted by this phase. SMTP and DB commits are not atomic; optional notification mail remains best-effort. Stop after11E-1; no automatic Cloudinary/LiveKit infrastructure work.

## Phase11E-2 — storage corrections source-validated; legacy/runtime gaps remain

- Generic upload/delete now checks authenticated ownership and existing links; unowned legacy IDs fail closed. Provider deletion is resource-aware, checks its response and propagates failures. New photos/post images remain public; new documents/invoices use authenticated raw delivery and signed URLs, with unique IDs and no overwrite. Existing limits now include byte/header checks.
- Dedicated removal/replacement no longer hides provider failures. Document-bearing record deletes clean stored IDs, URL edits keep IDs consistent, failed/rolled-back uploads attempt cleanup, shared post images remain until their last live post is deleted, and owned invoice fetches have timeouts/status checks. No API DTO/route, admin, schema or dependency changes; Flutter compatibility needed no source edit.
- **53 backend checks passed**, including18 new mocked regressions. Offline source/all-test compilation passed. **71 Flutter checks passed; scoped analysis clean.** Exact16 backend source paths, three new test files and logs are recorded in `PROGRESS.md`. No actual Cloudinary request or service/device was launched.

**Configuration:** existing server-only `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET`; use an approved dedicated test cloud, never mobile credentials. Actual account support for raw/authenticated delivery and PDF policies remains unverified.

**Explicit gaps:** signed document URLs are long-lived bearer links, not per-download owner checks. Existing public assets require an approved private-storage migration; they were not changed here. URL-only legacy attachment/account-purge cleanup, cross-system commit/process-death recovery and concurrent upload/link/delete still need reconciliation; there is no durable inventory/outbox or atomic Cloudinary/DB transaction. These are remaining acceptance/implementation requirements, not passing mock evidence.

Next: separately approved live-storage checks of upload/private delivery, unsigned denial, cross-account access, replacement/removal failures, shared files, invoices and CDN invalidation. No automatic LiveKit infrastructure/bKash work. Stop after11E-2.

## Phase11E-3 — LiveKit infrastructure source checkpoint

Fixed actual configuration prefix binding, public WS(S)/private HTTP(S) endpoint separation (`LIVEKIT_API_URL`), endpoint/positive-expiry validation, sanitized provisioning errors/error-body cleanup and effective new-room prefixes. Join credentials recheck current active/verified participants and linked conversation eligibility; READY cannot bypass the scheduled join window. Flutter now rejects delayed permission errors from an abandoned media session. Phase11B signing/room handling and Phase11C-1 session gates are preserved.

**20 distinct backend tests passed**, including six new regressions, plus two affected room-prefix assertion rechecks. Offline source/all-test compilation passed. **12 Flutter call/media tests passed**, changed files formatted, scoped analysis clean. Exact file list, configuration table and evidence logs are in the latest `PROGRESS.md` section. No actual provider/media/device connection, installation, migration or service launch occurred; admin unchanged.

**Controlled runtime readiness:** source is ready for a separately authorized two-party acceptance test using an approved reachable LiveKit server, matching protected backend credentials, disposable backend/MySQL/Redis and two Android endpoints. Configure `LIVEKIT_URL` for devices, optional internal `LIVEKIT_API_URL` for provisioning, HTTPS/WSS with valid certificates, actual advertised RTC media addresses/ports and ICE/TURN/NAT rules. These infrastructure values and network reachability remain unverified; no firewall/service changes are authorized here.

**Production blockers remain:** Spring logout/end does not force-remove provider participants or revoke already issued media credentials; token expiry is not active-media termination. Scheduled STARTED has no end/duration/webhook contract; an unstarted scheduled join can race MISSED processing. No standard LiveKit webhook endpoint is configured. Offset-free scheduling needs explicit business-timezone acceptance. Concurrent join/cancel and cross-system teardown still require source/runtime work; passing mocks do not close these gaps. Stop after11E-3; no automatic live testing or bKash.

## 3. Prepare approved disposable integration prerequisites

Do not repeat environment setup speculatively or start services as part of this roadmap. Obtain explicit execution/package permissions in the later testing task.

| Requirement | Existing source and action | Acceptance / boundary |
| --- | --- | --- |
| Disposable backend/MySQL/Redis | Backend `pom.xml`, existing Compose and `application.yml`; Java21/Spring Boot3.5.16, MySQL8, Redis7 configuration. Use only owner-approved isolated runtime configuration/credentials and disposable data. | Preserve the approved Phase11B media and Phase11C-1 security corrections; admin remains untouched. Never use production data. Startup JPA update and schema compatibility initialization can write DB schema, so the destination must be explicitly disposable. No Flutter direct database/cache connection. |
| SMTP and role/verification data | Auth/mail configuration and real signup/OTP flows; active CLIENT/LAWYER and verified lawyer test accounts, active reference records. | Real email/OTP completion, not fabricated login success. Use existing authorized administrative provisioning outside Flutter scope where needed; do not add verification bypasses. |
| Cloudinary and invoice fixtures | Storage config; dedicated profile/document/media routes; invoice service/download. | Real upload/retrieve/removal observations and an owned backend invoice/PDF created through a supported authorized path. Do not claim a demo checkout produced an invoice or mutate DB to fabricate payment evidence. |
| API/network/origins | `lib/core/config/api_config.dart`, Android network-security XML, backend HTTP/STOMP security. | Emulator uses reachable host mapping; device uses reachable LAN/HTTPS build configuration; production mode requires HTTPS. Socket origins/path work without bypassing auth/CORS/TLS. Do not expose provider credentials. |

Use the exact environment-variable names in the coverage report. Keep credentials out of reports, logs, source and committed files. Installation, firewall, system-service or privileged changes require separate approval.

## 4. Execute focused Android and live workflow acceptance

Run this only in an explicitly authorized runtime phase. Reuse the existing compiled app if its source/configuration matches the target; rebuild only as needed with available/approved artifacts. Install on an API24+ device/emulator only with approval. Use actual responses and independently observed provider effects; fixtures remain labeled fixtures.

| Area | Required checks | Completion evidence |
| --- | --- | --- |
| Auth/native persistence | Real signup/resend/OTP, login/2FA/recovery, rotation/reuse/expiry, cold start/process death, logout, role choice; wrong password vs expired bearer; API-origin switch; Keystore failure. | Actual SMTP and backend outcomes, persistent encrypted session restored safely, old credentials not reused after rotation, private data cleared on account changes. No tokens/OTP secrets in logs. |
| Client/lawyer records | Onboarding, nullable fields, references/decimals, CRUD, verification eligibility/status, council/qualification uploads and preservation, practice replacement/schedule, failure/retry. | Own records round-trip through server; second user denied; no abandoned editor mutations; provider retrieval/removal checked separately from cleared DB URL. |
| Discovery/community | Search/filter races, load-more/refresh, visibility, text/image create/edit/delete, likes/votes/bookmarks/share, comments/replies, following/privacy/report/analytics. | Actual permitted operations and denials; no fabricated totals/author data. Verify the Phase11C-2 root-only pages and ineligible-target unfollow corrections under real concurrent updates. |
| Messaging/realtime | Two users, request acceptance/privacy, send/edit/delete, history/cursor, tombstones/receipts, connect/disconnect/reconnect/refresh/account switch, duplicate/out-of-order deliveries, suspend/resume. | Real SockJS CONNECT and private events; REST reconciliation preserves changes. Verify edit/receipt/deletion cursor recovery; no guaranteed exactly-once send, XHR fallback or push/background delivery. |
| Notifications | Actual account/follow/post/message/call notifications, unread/read-all race, pagination, unavailable targets and corrected target routing. | Server counts and private event results reconcile, logout unsubscribes, notifications route only to supported destinations. |
| Calls/media | Actual participant restrictions, lifecycle conflicts, schedules/timezone assumptions and configured cutoff behavior; two-party media tests from batch 2. | API state and media success separately proven. No claim that ACCEPTED means connected. |
| Boosts/invoices | Verified eligibility, duplicate pending conflicts, uncertain purchase outcome, real history/analytics, sandbox handoff/return/status refresh, owned PDF retrieval/Android save. | Status remains backend-authoritative; browser opening never means paid. Production completion explicitly remains unsupported. Ownership gap is not “fixed” by Flutter precheck. |
| Security/support | Real password/2FA/session revocation/history/deletion grace/restoration; support create/list/detail/ownership and validation. | Backend effects observed, current-session behavior rechecked, no unsupported ticket mutation/recovery/status APIs. |
| Native providers/lifecycle | Photo/document picker cancellation, malformed metadata, size/MIME bounds, process/activity interruption, checkout browser, PDF destination/cancel/partial write, narrow layout/back navigation. | Real external providers and on-device execution, not just Dart channel doubles. Avoid broad storage permissions. |

Run the current full regression suite once at the final integration checkpoint, plus analysis and affected Android build checks. Historical 191 tests are not the current full-suite result. Rerun only checks affected by confirmed fixes. Preserve failure evidence and distinguish backend limitations from Flutter regressions.

## 5. Distribution readiness after functional acceptance

`android/app/build.gradle.kts` currently uses template identity/debug signing assumptions. Before distributing a release, obtain owner-selected application identity and signing policy, produce an approved release build, and verify HTTPS configuration, backups/session privacy, permissions and artifact identity. Keep signing material outside source/logs. This is owner-dependent release work, not a reason to redo the successfully compiled debug bridge implementation.

## Explicit non-goals and limits of completion

Do **not** add 13 unused multipart wrappers or a second STOMP send path merely to improve the count: JSON plus file routes and REST send already implement those user capabilities. Do not create an asset manager without inventory/ownership context, guess sponsored boost IDs, or invent full lawyer profiles, case management, consultation booking, user reports, unsupported post types, ticket replies, recovery codes, push services or payment activation APIs.

The following remain limitations or runtime acceptance requirements after the targeted backend corrections:

- No reliable sponsored-visit linkage in feed/discovery. Phase11E-2 guards generic owned/unlinked deletion, but legacy asset ownership and durable cleanup reconciliation remain incomplete.
- No production payment completion/callback through sandbox checkout; internal activation code is not a frontend API.
- Daily boost analytics authorization is corrected in Phase11C-1. Request/root-comment pagination and ineligible-target unfollow are source-corrected and regression-tested in Phase11C-2; live acceptance remains pending.
- Phase11C-2 covers message edits/receipts/deletions through existing cursor/private-message payloads. There is no durable event log/outbox, general send idempotency key or stable offset snapshot.
- Signaling does not relay media negotiation; scheduled end/webhook lifecycle is not exposed.
- Refresh-reuse commit and inactive-account/session defects are source-corrected and regression-tested in Phase11C-1; real MySQL/Redis semantics still require runtime acceptance. LiveKit signing/provisioning also needs real provider acceptance despite passing unit tests.

Flutter has closed F1–F3 and implemented/Android-compiled the approved media integration. Backend media tests pass; genuine provider/device acceptance remains pending. It cannot truthfully promise production payments, arbitrary safe storage deletion or complete server change-stream/security semantics under the fixed backend contract. If those are mandatory production acceptance conditions, record the project as blocked on owner decisions rather than declaring completion.

**Next planned work:** separately authorize the relevant runtime/source checkpoint. Phase11E-3 stops here; do not begin live testing, bKash/payment work or devices automatically. All Phase11B compilation blockers are resolved; live security/media acceptance remains pending.
