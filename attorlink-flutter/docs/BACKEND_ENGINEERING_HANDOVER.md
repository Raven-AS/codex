# Attorlink backend engineering handover

Prepared 2026-11-07 (Asia/Dhaka). Backend: `/home/frost/coding/codex/attorlink-backend`. Reference frontend and evidence: `/home/frost/coding/codex/attorlink-flutter`. This document records source comparison, current offline validation and separately labeled historical integration evidence. It is not production approval.

## 1. Executive summary

The latest **SMTP YAML correction is present and binds correctly**: `spring.mail` supplies Gmail `smtp.gmail.com:587`, SMTP authentication, STARTTLS enablement and mandatory STARTTLS. The independent `app.mail` section remains. Three new handover-only checks loaded the actual copied YAML and Spring's actual `MailProperties`/`MailConfig`, without opening an SMTP connection. Current credentials are environment references; no historical Gmail App Password was retrieved or used in this request. **Authenticated Gmail delivery and inbox receipt remain unverified.**

Security fallback removal is also present, with an important nuance: `DB_PASSWORD`, `JWT_SECRET`, and `ADMIN_PASSWORD` use **empty defaults**, not strictly required placeholders. Missing `JWT_SECRET` fails `JwtService` initialization because the existing signing-key minimum is 32 UTF-8 bytes. Missing database credentials may prevent authentication; absence alone is not a universal startup validation. Blank admin password makes the existing validated nonblank admin login unusable; there is no dedicated startup validator. Supply protected runtime values; do not restore committed secret defaults.

The current source builds offline into an executable Spring Boot JAR. The broad regression invocation and its two initial failures are documented in section 8. One failure exposed a **current WebSocket origin configuration regression**: the plain YAML default contains literal `http\://` strings, causing an allowed-origin handshake to fail with HTTP 403. A focused recheck uses an explicit unescaped local-origin override to isolate the cause; the source is not silently fixed. The other failure was a validation-runner environment collision, not a LiveKit implementation regression.

There is no reliable Git commit marking “the original developer's final backend.” Only two commits exist; the latest (`e900028`) is the most defensible tracked comparison baseline. Numerous functioning modules are untracked, already existed when the Flutter work audited them, and cannot honestly all be labeled Codex creations. The report separates **Git differences**, **confirmed later corrective work**, **pre-existing functionality**, and **uncertain provenance**. A normal `git diff` omits entire untracked modules, so blindly applying it would produce an incomplete backend.

No original backend source/configuration/project file, Flutter implementation, admin-panel file, or database was modified during this request. Validation uses a fresh source copy under `build/backend-handover/snapshot`; the only added Java harness is in that ignored copy. No external mail/storage/media/payment action, Docker operation, installation, service deployment, schema migration or commit occurred. Spring test contexts use disposable in-memory H2; one integration test starts an ephemeral loopback-only HTTP/WebSocket server. **bKash remains deferred.**

## 2. Original baseline and comparison methodology

### 2.1 What can be established

| Evidence | Interpretation |
| --- | --- |
| `884c5db` — 2026-10-04, “Initial commit” | Earliest available commit; not assumed to be the original developer's final version. |
| `e90002853f87ab49f7165112158b7352e990c2af` — 2026-10-05, “fixed” | Current HEAD and latest available committed state; chosen tracked baseline. 273 tracked paths. |
| Working tree versus HEAD | 50 tracked files modified; 324 untracked files individually enumerated, including source/tests and a few logs/PID/helpers. No tracked deletions. These are uncommitted, not a series of reviewable feature commits. |
| Saved copy `build/integration/backend-test` | Supplemental, unversioned earlier implementation evidence. 55 current main Java paths differ or are absent from that copy. Its creation date/source provenance is not strong enough to call it the original developer baseline. |
| `PROGRESS.md`, `COMPLETION_ROADMAP.md`, existing audits and historical build/integration results | Corroborate the specifically authorized corrective batches and their tests. Historical assertions are not substituted for current validation. |

The two committed versions already contain authentication, profiles, qualifications, storage and original admin functionality. Many chat/community/boost/video/support/settings/notification classes are absent from HEAD but were already described as existing backend contracts before their later stabilization. Their presence today is **not evidence that Codex invented those features**. Similarly, changes between the two existing commits are not automatically attributed to Codex.

### 2.2 Reproducibility and confidence

Read-only Git commands used: `git log --format=...`, `git rev-parse HEAD`, `git ls-tree -r --name-only HEAD`, `git status --porcelain=v1 --untracked-files=all`, `git diff --name-status HEAD`, `git diff --stat HEAD`, and targeted Java/POM diffs. Existing commit YAML credentials were not fetched. Do not print raw configuration-history diffs when reviewing this report.

`build/backend-handover/inventory.json` contains file status, controller mappings, method navigation and entity inventories. `snapshot-comparison.txt` lists Java differences against the earlier unversioned copy. `original_fingerprints.json` captures SHA-256 fingerprints of original project files excluding `.git`, target/log/IDE artifacts. A final source-integrity comparison is recorded with validation results.

Confidence labels throughout: **current check** = executed in this request; **historical integration** = actual earlier isolated MySQL/Redis/Mailpit/Android evidence; **mock/source** = implemented and tested without a provider; **unresolved** = remains a real limitation. Earlier test totals are not added together because coverage overlaps.

## 3. Subsystem-by-subsystem change history

Backend Java paths below are relative to `src/main/java/com/attorlink/` unless a full path is shown. The inventory gives every changed/untracked file; this section explains substantial behavior rather than implying every existing feature was newly written.

### 3.1 Authentication, refresh rotation and sessions

**Before:** HEAD user access JWTs were stateless with respect to refresh rows. The filter accepted any nonsuspended user rather than requiring ACTIVE status and a currently valid owned session. Refresh reuse revocations could be rolled back with the same exception intended to reject the reused credential. Refresh/credential mutations lacked coordinated current-read locking. Logout revoked a supplied refresh token without checking its owner against the authenticated caller.

**Corrections:**

- `JwtService.generateAccessToken(User, Long)` adds numeric `sid`, referring to the existing refresh-session row, not a token/hash. `isUserTokenActive` checks token expiration, ACTIVE account, subject/owner match and unrevoked/unexpired row. `JwtAuthenticationFilter` calls that gate and requires both admin subject and ADMIN claim for the separate admin path. Rejected JWT diagnostics are sanitized.
- `AuthServiceImpl.issueTokens` binds issued JWTs to the newly created refresh row. `refresh` looks up owner, locks the account first, validates the token with a pessimistic current read, rotates and issues a successor. Both the outer refresh transaction and `RefreshTokenService.validate` use `noRollbackFor=InvalidCredentialsException` so detected reuse revocations persist.
- `RefreshTokenRepository` adds scalar owner/session lookups and pessimistic token/active-token queries. `UserRepository` adds locking ID/email lookups. Shared account-first ordering serializes credential/refresh/security mutations; this is row-level coordination, not a new schema/idempotency system.
- `RefreshTokenService.revokeOwned` prevents cross-account logout token revocation. Existing current/all-session actions in `SessionService` check ownership and use a single locked list for revoke-all. REST and STOMP now consult the same session validity, so logout/password reset/session revocation/deletion invalidate access as well as refresh use.

**Contract/deployment impact:** Existing auth JSON DTOs/routes remain unchanged, but user JWT semantics change. Legacy access JWTs without `sid` fail closed; a still-valid refresh can upgrade or the user signs in again. Refresh rotation also invalidates the old bound access token. All nodes must deploy the auth/filter/STOMP changes together. Hardcoded-admin JWT compatibility is retained; that mechanism is distinct from user sessions, so do not assume user-session revocation also revokes admin tokens. Per-request DB checks add query/load/availability cost.

**Evidence:** `SessionJwtSecurityTest`, `SecurityTransactionRegressionTest`, `AuthSecurityRegressionTest`, session controller/service and existing auth fixtures. Historical 11F-1 tested rotation/reuse including concurrency, committed revocation, cross-account denial, logout and single/all-session revocation against actual disposable MySQL/Redis. Current complete-suite results are in section 8. No current production session was touched.

### 3.2 Account state, restoration, password and 2FA

**Before:** Scheduled-deletion login restored the account before successful optional 2FA; refresh could issue credentials without an ACTIVE-only gate. Challenges encoded only user/remember state and could survive credential/configuration changes. Redis get-then-delete and OTP delete-after-verify were not atomic. Purge used a previously scanned deletion row without a locked status/deadline recheck.

**Corrections:**

- New `auth/service/AccountSecurity` requires ACTIVE state and fingerprints user ID, credential/status/update stamp and 2FA settings. `AuthServiceImpl` locks accounts, validates suspended/inactive/deletion eligibility, validates actual restoration deadline, binds challenges to security/deletion state, consumes challenge once and restores only in `completeLogin` after all required factors succeed. Restoration revokes prior sessions. Refresh no longer updates the login stamp that would invalidate pending work accidentally.
- `PasswordServiceImpl` sends forgot-password OTP only to active accounts while retaining the generic init response, binds reset/pending-password work to current account security state, locks before applying, rejects stale work and revokes sessions on successful changes. Later verify/reset errors must not be interpreted as guaranteed email-enumeration resistance for every step.
- `TwoFactorServiceImpl.findUser` and account-deletion actions use active-account/locking checks. Existing EMAIL_OTP/TOTP enrollment/disable contracts remain; this does not add recovery codes or claim all 2FA changes revoke every existing session.
- `RedisService.getAndDelete` uses Redis GETDEL. `consumeIfMatches` uses Lua compare-and-delete so concurrent OTP replacement/replay cannot consume a different code. Redis 7 in the disposable environment supports these operations; older deployments must check command compatibility.
- `UserCleanupService.purgeScheduledUser` locks/rechecks status and deadline before existing destructive cleanup. `AccountServiceImpl.purgeDueAccounts` uses that result and does not recreate a deletion record after cleanup removed it. Actual destructive purge was not executed by this request or claimed from mocks.

**Contracts/storage:** No new auth entity/column or schema migration was needed for these fixes. Redis challenge/reset payload encodings changed internally: deployment invalidates in-flight older challenges/resets, which must restart. Existing API validation/DTOs remain. Fingerprinting uses an existing update stamp; unrelated account updates can conservatively invalidate pending security work. No promise of a DB/Redis/SMTP distributed transaction.

**Evidence:** Current focused auth/OTP/2FA tests; historical 48-check security batch included nine H2 transaction/concurrency cases. Historical live testing covered email 2FA replay, OTP concurrency and both password-reset paths. Suspension/deletion/restoration/purge, timed expiry and live TOTP remain explicitly unverified end-to-end.

### 3.3 REST/WebSocket authorization and configuration

**Before:** Existing working-tree STOMP support did not uniformly enforce session revocation after connection. Configurable SockJS registration and hardcoded HTTP matchers could disagree. Broad static JWT acceptance was insufficient for already-connected users.

**Corrections:** `config/WebSocketConfig` authenticates STOMP CONNECT from its Authorization header, stores session claims, rechecks current account/session on inbound work and outbound MESSAGE delivery, checks accepted-conversation participation for private conversation subscriptions, limits SEND destinations and removes tracking on disconnect. `SocketEndpointPath.normalize` is shared by endpoint registration and `SecurityConfig` HTTP matchers. Anonymous HTTP access is limited to handshake transport paths; it does not grant authenticated STOMP access. User JWTs never need to be put in URL query parameters.

Broker/application/user prefixes remain `/topic`/`/queue`, `/app`, `/user`. Existing supported private subscriptions are `/user/queue/chat/conversation/{conversationId}` and `/user/queue/notifications`. Existing SEND mapping includes `/app/chat.send` and `/app/chat/conversation/{conversationId}/send`; no new event protocol or push notification was invented. Payloads remain actual message/notification DTOs.

**Current regression:** YAML `app.websocket.allowed-origins` default contains literal backslashes in `http\://localhost:3000,http\://localhost:8080`. Plain YAML does not remove them. The current real socket test receives HTTP 403 at upgrade. Use the affected recheck and recommendations below; do not globally wildcard origins or weaken authentication. User-supplied `WEBSOCKET_ALLOWED_ORIGINS` can override the incorrect default. Admin-panel browser/socket compatibility still needs its deployed origins tested.

**Limitations:** Session gates prevent further authenticated broker work, not instantaneous provider media disconnection or guaranteed socket close when idle. Simple-broker subscriptions/events are not a durable multi-node message queue. The Flutter transport implements SockJS WebSocket framing, not the complete fallback negotiation/transports. Proxy origins/upgrade/idle-timeouts require runtime acceptance.

### 3.4 Messaging requests, pagination and transactional events

**Before (confirmed against saved earlier Java copy):** Outgoing pending requests were filtered after pagination, making content/totals/boundaries inconsistent. Normalized participant A/B IDs could invert the actual request recipient. Conversation/request mutations could race to create duplicate initial content or conflicting decisions. Sync separately queried original creation/deletion times, omitting edits and receipt changes; sender history read the sender's delivery row. REST and STOMP broadcasting were inconsistent and could duplicate or publish before a rollback.

**Corrections:**

- `chat/repository/ChatConversationRepository.findOutgoingRequests/findIncomingRequests` apply initiator, participant and status visibility before query pagination/counting. `ChatConversationServiceImpl` uses `initiatedByUser`/other participant for decisions/notifications, locks participant accounts in ID order during creation and the conversation during accept/reject. Existing CLIENT_LAWYER/LAWYER_LAWYER/privacy/verification decisions remain authoritative.
- `ChatMessageRepository.findChangesAfterCursor` orders by durable `updatedAt,id`; `ChatMessageServiceImpl.syncConversation` bounds live updates and tombstones together before splitting response lists. Existing cursor JSON names remain, but represent a **latest-change watermark**, not merely creation time. A cursor ID must belong to the requested conversation.
- Send/edit/delete/receipt/read-marker changes use conversation/message locks and a microsecond monotonic change clock. `ChatConversation`/`ChatMessage` callbacks do not regress assigned timestamps. History reports the recipient's actual status; repeated delivered/seen/read actions do not regress state.
- `ChatMessageResponse.from` redacts deleted text. New `ChatRealtimeService.deliverAfterCommit` broadcasts the existing snapshot to both existing private queues only after commit; rollback broadcasts nothing. `ChatWebSocketController` no longer broadcasts a second copy after service delivery. Broker exceptions are logged without changing a committed DB operation into an apparent rollback.

**Compatibility:** No new routes/statuses/DTO fields or migration were introduced by the 11C-2 corrections. Cursor *meaning* and receipt semantics did change, so alternate clients must consume the returned watermark and reconcile updates by stable ID. DTO-preserving is not behavior-preserving. Flutter's recipient rule was updated compatibly; reference timeline code consumes tombstones and guards session generations.

**Verification/limits:** H2 query/locking/rollback fixtures and current unit/controller suites; historical 11F-2 exercised actual MySQL cursor edits/deletions, requests, receipts and host SockJS/STOMP events. The final Android run observed send/SEEN/incoming/edit/delete reconciliation. These are not exhaustive multi-device/concurrent coverage. Sync coalesces state rather than preserving all events; offset pages move during writes; uncertain sends can duplicate without a client idempotency key; no durable outbox, exactly-once delivery or distributed transaction was added.

### 3.5 Community, follows, reports and discovery

The post/comment/follow/report/feed/analytics modules are absent from Git HEAD but already existed as backend functionality during the reference app audit. Their entire product scope is not attributed to Codex here.

**Confirmed later corrections:** `community/repository/CommentRepository`, `CommentServiceImpl` and `CommentController` exclude replies/deleted rows in root queries before pagination and consistently order roots/replies by created time plus ID. Existing author/moderation/privacy/deletion checks remain. `LawyerFollowServiceImpl.unfollow` still requires the active owning CLIENT but no longer requires a previously followed target to remain discoverable; new follow continues to require active/verified lawyer eligibility. Same-client follow creation is serialized using the existing account lock. Tests cover mixed root/reply pages, inactive targets and ownership/eligibility.

`PostServiceImpl`/`PostRepository` additionally changed for provider cleanup, shared media references and deletion errors (section 3.7). No claim is made that all like/bookmark/report/analytics code was rewritten. Existing controllers support TEXT/IMAGE creation; unsupported VIDEO/POLL/QUESTION are not frontend-created or represented as completed server features.

**Verifiable Git delta for discovery:** `LawyerDiscoveryController`, `LawyerDiscoverResponse`, `LawyerDiscoveryService/Impl` are untracked; `LawyerProfileRepository.searchDiscoverable` and batched `LawyerSpecializationRepository` query are tracked modifications. Search selects ACTIVE LAWYER users with VERIFIED profiles, applies name/practice-area criteria before pagination, escapes LIKE wildcards, orders by updated time/ID and batches specialization labels. `SecurityConfig` permits GET `/api/v1/lawyers/discover`. The DTO exposes only `id,userId,fullName,profilePhoto,professionalTitle,bio,yearsOfExperience,practiceAreas,updatedAt`. It is not a general public full-profile endpoint and does not supply invented ratings/availability/credentials.

**Status:** Current relevant fixtures and historical focused API discovery/community/authorization checks exist. Public search, reporting and analytics behavior require deployment rate/abuse/privacy review; test success does not prove every moderation or pagination race. Sponsored-visit linkage remains incomplete in the Flutter flow; no new tracking behavior was invented.

### 3.6 Client preferences and lawyer profile/qualification contracts

**Confirmed tracked deltas:** `ClientProfileController` adds GET/PUT `/api/v1/client/preferences`, backed by untracked request/response/entity/repository/service. Requests use lists `practiceAreaIds,jurisdictionIds,courtIds,lawyerLanguages`; normalization removes null/duplicate/blank entries. Constructor normalization means null list inputs become empty before `@NotNull` validation; consumers should not assume raw null is rejected merely because the component has an annotation. Reference/role checks remain in the service.

Existing lawyer award, Bar Council, credential, education, High/Supreme Court, membership and training controllers/services gain **additional multipart save/upload handler overloads**, preserving JSON handlers and existing dedicated attachment routes. Multipart paths/encodings are in section 5. Existing record DTOs are not globally replaced. `LawyerProfileService` and document-bearing services stop swallowing Cloudinary deletion failures, retain provider IDs for unchanged attachment URLs, clear stale IDs on intentional URL changes and clean managed documents on delete. The education pattern applies to the analogous award/credential/membership/training services; High/Supreme/Council/profile paths retain their own ownership checks.

These are concrete Git differences, but their authorship/date beyond the explicitly documented storage corrections is uncertain. Fields/entities added between `884c5db..e900028` for photos/documents belong to the committed historical range, not automatically later Codex work. Existing onboarding requires first name, bar registration number and saved Council record before submission; admin verification remains server-authoritative. There was no schema migration in the later corrective batches. Historical API tests covered representative profiles, education/office CRUD, availability and verification decisions; actual uploads remain unverified.

### 3.7 Cloudinary storage, private documents and invoices

**Before:** Generic authenticated deletion accepted arbitrary provider IDs without a proven owner/reference check. Deletion used default provider resource types and ignored response semantics; several owning-resource services swallowed failures then removed DB references. Upload validation trusted declared MIME/length. Documents/invoices used publicly delivered raw files, provider IDs could collide/lose type information, and failed DB/upload operations could leave orphaned assets.

**Corrections:**

- `storage/controller/FileUploadController` namespaces generic uploads under the authenticated user, validates IMAGE/DOCUMENT/folders and calls new `storage/FileReferenceGuard` before deletion. The guard checks authenticated owner namespace or owned post-upload metadata, rejects unsafe identifiers, refuses deletion of linked assets and fails closed for unprovable legacy IDs. Metadata is forgotten only after provider-confirmed deletion.
- `StorageServiceImpl` retains the existing image 5 MiB/document 10 MiB limits; validates actual byte length and JPEG/PNG/WebP/PDF signatures; assigns unique prechosen IDs under typed image/document prefixes; uses `overwrite=false`; validates returned metadata and HTTPS URLs. No claim of malware scanning, exhaustive content decoding or verified provider delivery.
- New documents/invoices use `raw/authenticated` delivery and signed HTTPS URLs; ordinary profile/post images stay public `image/upload`. Destroy selects explicit resource/delivery and invalidation, checks `ok`/`not found`, handles legacy raw/image lookup, and reports errors rather than treating DB unlinking as deletion proof.
- New uploads register rollback cleanup and clean their unique ID on uncertain responses; failed cleanup records only an opaque provider ID for operator reconciliation. Document-bearing service delete/replacement propagates failures. Shared post media is kept until the last live post reference is deleted; final deletion removes stale upload metadata.
- `boost/service/BoostInvoicePdfStorageServiceImpl` reuses typed private storage/unique IDs. `BoostInvoiceServiceImpl` verifies owned invoice lookup and adds bounded connect/request timeouts plus successful HTTP status requirements for fetches. No payment activation behavior was added.

**Compatibility/security limits:** UploadedFileResponse/owning-resource DTO fields/routes remain; provider ID formats and URL delivery types change behaviorally. Long-lived signed URLs are bearer capabilities, not per-download owner checks, and lack short expiry. Existing public legal documents/invoices were not migrated. URL-only legacy attachments and account purge do not guarantee provider cleanup. Provider deletes before a later DB rollback can lose the old asset; concurrent link/delete, partial cleanup and process death lack a durable inventory/outbox/atomic DB-provider transaction. **Do not approve private-document production security solely from these mocked tests.**

**Evidence:** Three new storage regression classes plus affected lawyer/community/invoice fixtures; earlier 53 backend checks/71 Flutter checks are historical overlapping batches. No actual Cloudinary credentials, upload, signed/unsigned retrieval, PDF policy or deletion was exercised here or in the provider-unavailable reference completion.

### 3.8 LiveKit, immediate calls and scheduling

Existing call/scheduled-call modules are untracked baseline features, not newly invented workflows. Confirmed 11B corrections in `video/service/LiveKitVideoMediaService` use the **original signing secret** with the SDK rather than a transformed key and pass `RoomServiceClient.create(url, apiKey, apiSecret)` in correct order. SDK grants use identity `user-<id>`, exact persisted room, publish/subscribe/data/update-own-metadata permissions; no room-admin grant.

11E-3 corrected root `video.*`/`video-scheduling.*` to `app.*` binding bridges, introduced optional server-only `LIVEKIT_API_URL`, normalizes public credentials to WS(S) and admin provisioning to HTTP(S), rejects userinfo/query/fragment/unsupported endpoints and nonpositive expiry, closes provider error bodies and sanitizes failures. Room creation handles success/existing-room 409. `VideoCallServiceImpl` and `ScheduledVideoCallServiceImpl` apply configured prefixes only to new rooms and recheck active users, verified-lawyer eligibility and linked accepted conversation at join. READY does not bypass the 15-minute scheduled join window.

**Contract:** Same immediate/scheduled call DTOs/statuses/routes; credentials include transient token/identity/room/public endpoint, never API secret/private provisioning URL. Separate REST call status is not proof of media connection. Flutter has an approved installed LiveKit SDK and actual media adapter; this report does not mislabel it absent. Current mock/signature/config tests and historical Android compilation are not actual two-party media.

**Outstanding:** logout/end/cancel does not force-remove existing provider participants or revoke issued media credentials; admission expiry does not terminate active media. Scheduled STARTED lacks a complete duration/end/webhook lifecycle and can remain joinable; unstarted join can race MISSED processing. The custom webhook signature helper is not evidence of an actual standard LiveKit webhook controller. Date-times are offset-free LocalDateTime/JVM-zone values. Real two-party capture/playback, ICE/TURN/reconnect, private/public reachability and hostile-client teardown remain unverified/incomplete requirements.

### 3.9 SMTP, OTP delivery and notifications

**Before:** HEAD `EmailServiceImpl` treated blank username as development mode and logged stripped HTML/OTP content while recording SKIPPED. The earlier saved `MailConfig` hardcoded localhost:25 with no auth/TLS, so Spring mail settings were ineffective. Provider errors could leak through raw logs/error storage. Some lifecycle/verification email calls bypassed centralized notifications.

**Corrections:** `MailConfig.javaMailSender(MailProperties)` now copies endpoint, credentials, protocol, encoding and JavaMail options from **`spring.mail`**, forcing mail/body/auth debug off. `EmailServiceImpl` uses `app.mail.from` independently of authentication, never prints OTP/body, fails required disabled/misconfigured/failed delivery through the existing sanitized EmailDeliveryException, and permits SKIPPED only for optional disabled templates. Raw provider errors/causes are not returned/stored in ordinary email errors. `OtpServiceImpl.sendOtp` removes only its own failed-delivery hash atomically; cleanup failure retains expiry and the original delivery error.

Current YAML has the user's latest nesting/required-STARTTLS change and preserves `app.mail.enabled/from/notification-enabled`. `MAIL_FROM` falls back to `spring.mail.username`; Gmail requires a permitted sender/account. SMTP authentication/TLS options are now literal true in YAML. Previously documented `MAIL_SMTP_AUTH`, `MAIL_SMTP_STARTTLS_ENABLE`, `MAIL_SMTP_STARTTLS_REQUIRED` and `MAIL_SMTP_SSL_ENABLE` are **no longer referenced by current YAML**: setting those names alone does not override the current policy. Direct Spring property overrides would be needed for a deliberately different SMTP test mode. Do not assume old Mailpit launcher variables still work with this source.

**Notification subsystem delta:** new/untracked notification controllers/DTOs/service/delivery/email components, preference categories and entities were already exposed to Flutter; exact provenance is uncertain. Tracked changes to `AdminUserServiceImpl`, `VerificationServiceImpl`, `AuthServiceImpl` and `AccountServiceImpl` route status/verification/restoration/deletion messages through `NotificationService`. Rejection notes are whitespace-normalized and heuristically suppress internal/admin/private/secret-like text; this is not a formal PII/DLP guarantee. `EmailLog` now has unique nullable `notification_id` and `event_id`, and its repository/service suppress duplicate event sends. `SchedulingConfig` enables async with a bounded notification-email executor (2 core/4 max/100 queue, caller-runs fallback, bounded shutdown wait). Delivery is best-effort; there is no durable mail queue/outbox and DB/SMTP commits are not atomic.

**Current/historical proof:** Three current actual-YAML checks plus seven SMTP mock tests and auth/OTP/notification-email fixtures passed. Historical 11F-1 verified actual delivery into Mailpit followed by signup/recovery/2FA; it did not test Gmail. Earlier Gmail TCP/587 and certificate-verified STARTTLS succeeded without authentication; this request performed no provider action. No explicitly authorized live recipient/current protected credential source was supplied for delivery. Historical exposed credentials were not retrieved or reused.

### 3.10 Boosts, payment sandbox, analytics and support

Boost, invoice, checkout, monitoring and support-ticket modules/controllers are absent from Git HEAD but existed when audited. Their entire lifecycle is not a claimed Codex addition. Existing purchase requires a verified lawyer; pending-same-plan conflict and backend-derived status remain. Checkout is a **sandbox demonstration**, not proof of real payment or boost activation. No bKash/payment-provider implementation or production settlement verification was added in this request or claimed in the source-stabilization corrections.

Confirmed security fix: `boost/service/BoostAnalyticsServiceImpl.getBoostDailyMetrics` now resolves the boost and applies `ensureCurrentUserOwnsBoost` before metric queries, matching summary authorization. Prior arbitrary boost existence-only checks permitted cross-owner daily analytics. Existing lawyer/admin DTO/routes stay; cross-account denial is intentional. Invoice/storage changes are in section 3.7; no payment status is inferred from URL opening.

Support's actual authenticated create/list/detail and admin status/list/detail APIs, categories/statuses and ownership checks are inventoried below. No later broad support rewrite is proven. Untracked reporting/boost/support admin controllers are backend code; **the separate admin-panel repository was never touched**. UI consumption/admin browser compatibility still needs targeted deployed acceptance, not an assumption from preserving a Java signature.

### 3.11 Other verifiable differences

- `UserController` gains own message/comment privacy and notification-preference GET/PUT routes with untracked DTO/settings entities/repositories/services. Their absence from HEAD is proven; authorship predating these corrective batches is uncertain.
- `GlobalExceptionHandler` maps new `ConflictException` to HTTP 409 in the existing ApiResponse envelope, important for duplicate pending purchases and other conflicts.
- `OpenApiConfig` documents added API groups; it does not authorize routes.
- README, three launch/stop helpers, and the boost implementation blueprint are present as modified/untracked files. Scripts are operational helpers, not proof of production configuration; review before using, particularly stop behavior. PID/log files are artifacts, not mergeable application improvements.
- The POM additions are detailed below. No new dependency was installed/resolved online during this request.

## 4. Security fixes and behavior review

| Area | Confirmed correction | Residual requirement |
| --- | --- | --- |
| User JWT | Owned active refresh row required for REST/STOMP; old unbound tokens fail closed | Coordinated deployment; query/load tests; admin tokens have separate semantics |
| Refresh reuse | Revocations survive intended rejection; serialized current reads | MySQL contention/deadlock/expiry tests on actual deployment; no universal exactly-once HTTP semantics |
| In-flight security work | Atomic consume and account-state fingerprint; restore after 2FA | Restart old challenges; live inactive/deletion/TOTP/time-limit acceptance |
| Ownership | Boost daily metrics, refresh logout and generic file deletion gated | Alternate clients/admin routes and provider delivery must still be reviewed |
| Private documents | Authenticated raw delivery and signed URL issuance | Long-lived bearer URLs and legacy public assets remain security limitations |
| Realtime | Participant/session revalidation; after-commit message events | Fix origin default; no durable outbox, push guarantee or exactly-once text sends |
| Media | Exact-room original-secret tokens and current join eligibility | Provider-enforced teardown/revocation absent; no genuine two-party acceptance |
| Mail | No development OTP logs; mandatory STARTTLS config; sanitized failures | Protected current credentials, authorized recipient, actual Gmail delivery/inbox confirmation |
| Secrets | Three sensitive YAML fallbacks removed | Rotate exposed historical credentials/keys through owner-approved operations; do not copy history values |

## 5. API and database compatibility impact

**Not safe to merge blindly.** Selective integration is feasible only after reconstructing the engineer's true branch and reviewing working-tree modules absent from HEAD. There is no versioned patch series that proves every change's authorship. Preserve the separate admin JWT/login interface and existing envelopes; do not assume all deployments accept new user-token semantics.

- No tracked REST handler removal was found. Added mappings in tracked controllers are preferences/privacy/notification settings and multipart qualification overloads; untracked controllers supply the additional families in the appendix. HTTP 409 is now an explicit envelope mapping. Existing common ApiResponse/PageResponse and tracked auth DTOs have no current modifications.
- Behavioral changes intentionally include ACTIVE-only access, session-bound JWTs, rejected legacy challenges, owner-bound logout, stricter storage validation/error propagation, new typed/signed provider URLs, correctly filtered page totals, request-recipient identity, receipt semantics and updatedAt-based sync cursors. Alternate clients/admin workflows must not mistake unchanged JSON shapes for unchanged semantics.
- HEAD-to-current entity delta includes two EmailLog unique nullable columns and numerous untracked feature/settings/chat/video/boost entities. The later targeted security/messaging/storage corrections explicitly reused existing entities/columns; that does **not** mean the whole HEAD-to-working-tree comparison has no schema impact.
- Current JPA configuration uses `ddl-auto: update`; startup can change the connected database. No Flyway/Liquibase migration files/framework were found in the inspected source/POM. Do not start this version against an unknown/prod database to “see whether it works.” Compare actual MySQL schema, constraints/indexes, defaults/enums, FK deletion order and existing duplicate data first, then design owner-reviewed migration/rollback.
- `NotificationPreferenceSchemaCompatibility.ensureLegacySystemColumnCompatibility` attempts startup DDL renaming legacy `user_notification_preferences.system` to `system_enabled` when metadata detects the old column; exceptions are swallowed as optional compatibility. This is a schema mutation despite there being no migration file. It is absent from HEAD with uncertain authorship. Review MySQL metadata casing, permissions/transaction behavior and whether Hibernate runs before/after it. Do not rely on this initializer as a general migration strategy.
- Chat timestamps are truncated to microseconds by callbacks; schema stores existing timestamps, but production column precision/ordering must be confirmed. This request did not change any schema or legacy data.
- Email event uniqueness and conversation participant/type uniqueness need inspection on existing data; nullable unique-column semantics and real MySQL locking differ from H2. See entity inventory for actual class/table/field navigation.



### 5.1 Controller mapping inventory for changed/untracked controllers

Extracted from actual Java annotations. This is a review index rather than a runtime OpenAPI comparison; `multipart` distinguishes alternate handlers with the same HTTP route. Routes of unchanged controllers are retained, but shared authentication behavior changed as described above. Untracked handlers are absent from the chosen Git baseline; that does not establish when or by whom they were created.

| HTTP | Route | Controller method | Comparison with HEAD |
| --- | --- | --- | --- |
| GET | `/api/admin/v1/boosts/analytics` | `AdminBoostAnalyticsController.summary` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/admin/v1/boosts` | `AdminBoostMonitoringController.listBoosts` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/admin/v1/boosts/{boostId}` | `AdminBoostMonitoringController.getBoost` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/admin/v1/boosts/{boostId}/payment` | `AdminBoostMonitoringController.getBoostPayment` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/admin/v1/boosts/{boostId}/invoice` | `AdminBoostMonitoringController.getBoostInvoice` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/admin/v1/boosts/{boostId}/activities` | `AdminBoostMonitoringController.getBoostActivities` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/admin/v1/boosts/summary` | `AdminBoostMonitoringController.summary` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/admin/v1/boost-plans` | `AdminBoostPlanController.create` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/admin/v1/boost-plans` | `AdminBoostPlanController.list` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/admin/v1/boost-plans/{id}` | `AdminBoostPlanController.getById` | mapping absent from HEAD (authorship unproven for untracked source) |
| PUT | `/api/admin/v1/boost-plans/{id}` | `AdminBoostPlanController.update` | mapping absent from HEAD (authorship unproven for untracked source) |
| PATCH | `/api/admin/v1/boost-plans/{id}/activate` | `AdminBoostPlanController.activate` | mapping absent from HEAD (authorship unproven for untracked source) |
| PATCH | `/api/admin/v1/boost-plans/{id}/deactivate` | `AdminBoostPlanController.deactivate` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/admin/v1/community/reports` | `AdminContentReportController.list` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/admin/v1/community/reports/{reportId}` | `AdminContentReportController.detail` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/admin/v1/community/reports/{reportId}/decision` | `AdminContentReportController.decide` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/admin/v1/support/tickets` | `AdminSupportTicketController.list` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/admin/v1/support/tickets/{ticketId}` | `AdminSupportTicketController.detail` | mapping absent from HEAD (authorship unproven for untracked source) |
| PATCH | `/api/admin/v1/support/tickets/{ticketId}/status` | `AdminSupportTicketController.updateStatus` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/auth/sessions` | `SessionController.listSessions` | mapping absent from HEAD (authorship unproven for untracked source) |
| DELETE | `/api/v1/auth/sessions/{sessionId}` | `SessionController.revokeSession` | mapping absent from HEAD (authorship unproven for untracked source) |
| DELETE | `/api/v1/auth/sessions` | `SessionController.revokeAllSessions` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/boosts/{boostId}/profile-visit` | `BoostAnalyticsTrackingController.recordProfileVisit` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/lawyer/boosts/analytics/summary` | `LawyerBoostAnalyticsController.summary` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/lawyer/boosts/{boostId}/analytics` | `LawyerBoostAnalyticsController.getBoostAnalytics` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/lawyer/boosts/{boostId}/analytics/daily` | `LawyerBoostAnalyticsController.getDailyMetrics` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/lawyer/boosts/analytics/daily` | `LawyerBoostAnalyticsController.getLawyerDailyMetrics` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/lawyer/boost-plans` | `LawyerBoostController.listAvailablePlans` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/lawyer/boosts/purchase` | `LawyerBoostController.purchaseBoost` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/lawyer/boosts/invoices` | `LawyerBoostInvoiceController.listInvoices` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/lawyer/boosts/invoices/{invoiceId}` | `LawyerBoostInvoiceController.getInvoice` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/lawyer/boosts/invoices/{invoiceId}/download` | `LawyerBoostInvoiceController.downloadInvoice` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/lawyer/boosts` | `LawyerBoostMonitoringController.listMyBoosts` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/lawyer/boosts/{boostId}` | `LawyerBoostMonitoringController.getMyBoost` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/lawyer/boosts/{boostId}/activities` | `LawyerBoostMonitoringController.getMyBoostActivities` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/lawyer/boosts/{boostId}/sandbox-checkout` | `LawyerBoostSandboxCheckoutController.sandboxCheckout` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/chat/conversations` | `ChatConversationController.create` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/chat/conversations` | `ChatConversationController.list` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/chat/conversations/{conversationId}` | `ChatConversationController.getOne` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/chat/requests/incoming` | `ChatConversationController.incomingRequests` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/chat/requests/outgoing` | `ChatConversationController.outgoingRequests` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/chat/conversations/{conversationId}/accept` | `ChatConversationController.accept` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/chat/conversations/{conversationId}/reject` | `ChatConversationController.reject` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/chat/conversations/{conversationId}/messages` | `ChatMessageController.sendMessage` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/chat/conversations/{conversationId}/messages` | `ChatMessageController.getHistory` | mapping absent from HEAD (authorship unproven for untracked source) |
| PATCH | `/api/v1/chat/conversations/{conversationId}/messages/{messageId}` | `ChatMessageController.editMessage` | mapping absent from HEAD (authorship unproven for untracked source) |
| DELETE | `/api/v1/chat/conversations/{conversationId}/messages/{messageId}` | `ChatMessageController.deleteMessage` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/chat/conversations/{conversationId}/messages/{messageId}/delivered` | `ChatMessageController.markDelivered` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/chat/conversations/{conversationId}/messages/{messageId}/seen` | `ChatMessageController.markSeen` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/chat/conversations/{conversationId}/read` | `ChatMessageController.markConversationRead` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/chat/conversations/{conversationId}/sync` | `ChatMessageController.syncConversation` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/client/profile` | `ClientProfileController.getProfile` | existing mapping; implementation/dependency changed |
| PUT | `/api/v1/client/profile` | `ClientProfileController.updateProfile` | existing mapping; implementation/dependency changed |
| POST | `/api/v1/client/profile/photo` (multipart) | `ClientProfileController.uploadProfilePhoto` | existing mapping; implementation/dependency changed |
| DELETE | `/api/v1/client/profile/photo` | `ClientProfileController.deleteProfilePhoto` | existing mapping; implementation/dependency changed |
| GET | `/api/v1/client/address` | `ClientProfileController.getAddress` | existing mapping; implementation/dependency changed |
| PUT | `/api/v1/client/address` | `ClientProfileController.updateAddress` | existing mapping; implementation/dependency changed |
| GET | `/api/v1/client/preferences` | `ClientProfileController.getPreferences` | mapping absent from HEAD (authorship unproven for untracked source) |
| PUT | `/api/v1/client/preferences` | `ClientProfileController.updatePreferences` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/community/posts/{postId}/comments` | `CommentController.createComment` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/community/posts/{postId}/comments` | `CommentController.listComments` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/community/posts/{postId}/comments/{commentId}/replies` | `CommentController.createReply` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/community/posts/{postId}/comments/{commentId}/replies` | `CommentController.listReplies` | mapping absent from HEAD (authorship unproven for untracked source) |
| PATCH | `/api/v1/community/comments/{commentId}` | `CommentController.updateComment` | mapping absent from HEAD (authorship unproven for untracked source) |
| DELETE | `/api/v1/community/comments/{commentId}` | `CommentController.deleteComment` | mapping absent from HEAD (authorship unproven for untracked source) |
| PUT | `/api/v1/community/comments/{commentId}/vote` | `CommentController.vote` | mapping absent from HEAD (authorship unproven for untracked source) |
| DELETE | `/api/v1/community/comments/{commentId}/vote` | `CommentController.removeVote` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/community/reports` | `ContentReportController.create` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/community/feed-events` | `FeedAnalyticsController.reportEvent` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/community/feed-analytics` | `FeedAnalyticsController.summarizePost` | mapping absent from HEAD (authorship unproven for untracked source) |
| PUT | `/api/v1/community/lawyers/{lawyerId}/follow` | `LawyerFollowController.follow` | mapping absent from HEAD (authorship unproven for untracked source) |
| DELETE | `/api/v1/community/lawyers/{lawyerId}/follow` | `LawyerFollowController.unfollow` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/community/following` | `LawyerFollowController.listFollowing` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/community/lawyers/{lawyerId}/followers` | `LawyerFollowController.listFollowers` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/community/feed` | `PostController.feed` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/community/posts` | `PostController.create` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/community/posts/media` (multipart) | `PostController.uploadMedia` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/community/posts/{postId}` | `PostController.getOne` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/community/posts` | `PostController.list` | mapping absent from HEAD (authorship unproven for untracked source) |
| PATCH | `/api/v1/community/posts/{postId}` | `PostController.update` | mapping absent from HEAD (authorship unproven for untracked source) |
| DELETE | `/api/v1/community/posts/{postId}` | `PostController.delete` | mapping absent from HEAD (authorship unproven for untracked source) |
| PUT | `/api/v1/community/posts/{postId}/like` | `PostController.like` | mapping absent from HEAD (authorship unproven for untracked source) |
| DELETE | `/api/v1/community/posts/{postId}/like` | `PostController.unlike` | mapping absent from HEAD (authorship unproven for untracked source) |
| PUT | `/api/v1/community/posts/{postId}/bookmark` | `PostController.bookmark` | mapping absent from HEAD (authorship unproven for untracked source) |
| DELETE | `/api/v1/community/posts/{postId}/bookmark` | `PostController.removeBookmark` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/community/bookmarks` | `PostController.listBookmarks` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/community/posts/{postId}/share` | `PostController.share` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/lawyer/awards` | `LawyerAwardController.getAll` | existing mapping; implementation/dependency changed |
| POST | `/api/v1/lawyer/awards` | `LawyerAwardController.create` | existing mapping; implementation/dependency changed |
| POST | `/api/v1/lawyer/awards/multipart` (multipart) | `LawyerAwardController.createMultipart` | mapping absent from HEAD (authorship unproven for untracked source) |
| PUT | `/api/v1/lawyer/awards/{id}` | `LawyerAwardController.update` | existing mapping; implementation/dependency changed |
| PUT | `/api/v1/lawyer/awards/{id}/multipart` (multipart) | `LawyerAwardController.updateMultipart` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/lawyer/awards/{id}/document` (multipart) | `LawyerAwardController.uploadDocument` | existing mapping; implementation/dependency changed |
| DELETE | `/api/v1/lawyer/awards/{id}/document` | `LawyerAwardController.deleteDocument` | existing mapping; implementation/dependency changed |
| DELETE | `/api/v1/lawyer/awards/{id}` | `LawyerAwardController.delete` | existing mapping; implementation/dependency changed |
| GET | `/api/v1/lawyer/bar-council` | `LawyerBarCouncilController.get` | existing mapping; implementation/dependency changed |
| PUT | `/api/v1/lawyer/bar-council` | `LawyerBarCouncilController.save` | existing mapping; implementation/dependency changed |
| PUT | `/api/v1/lawyer/bar-council` (multipart) | `LawyerBarCouncilController.saveMultipart` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/lawyer/bar-council/identity-card` (multipart) | `LawyerBarCouncilController.uploadIdentityCard` | existing mapping; implementation/dependency changed |
| DELETE | `/api/v1/lawyer/bar-council/identity-card` | `LawyerBarCouncilController.deleteIdentityCard` | existing mapping; implementation/dependency changed |
| POST | `/api/v1/lawyer/bar-council/sanad` (multipart) | `LawyerBarCouncilController.uploadSanad` | existing mapping; implementation/dependency changed |
| DELETE | `/api/v1/lawyer/bar-council/sanad` | `LawyerBarCouncilController.deleteSanad` | existing mapping; implementation/dependency changed |
| POST | `/api/v1/lawyer/bar-council/green-book` (multipart) | `LawyerBarCouncilController.uploadGreenBook` | existing mapping; implementation/dependency changed |
| DELETE | `/api/v1/lawyer/bar-council/green-book` | `LawyerBarCouncilController.deleteGreenBook` | existing mapping; implementation/dependency changed |
| GET | `/api/v1/lawyer/credentials` | `LawyerCredentialController.getAll` | existing mapping; implementation/dependency changed |
| POST | `/api/v1/lawyer/credentials` | `LawyerCredentialController.create` | existing mapping; implementation/dependency changed |
| POST | `/api/v1/lawyer/credentials/multipart` (multipart) | `LawyerCredentialController.createMultipart` | mapping absent from HEAD (authorship unproven for untracked source) |
| PUT | `/api/v1/lawyer/credentials/{id}` | `LawyerCredentialController.update` | existing mapping; implementation/dependency changed |
| PUT | `/api/v1/lawyer/credentials/{id}/multipart` (multipart) | `LawyerCredentialController.updateMultipart` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/lawyer/credentials/{id}/document` (multipart) | `LawyerCredentialController.uploadDocument` | existing mapping; implementation/dependency changed |
| DELETE | `/api/v1/lawyer/credentials/{id}/document` | `LawyerCredentialController.deleteDocument` | existing mapping; implementation/dependency changed |
| DELETE | `/api/v1/lawyer/credentials/{id}` | `LawyerCredentialController.delete` | existing mapping; implementation/dependency changed |
| GET | `/api/v1/lawyers/discover` | `LawyerDiscoveryController.discover` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/lawyer/educations` | `LawyerEducationController.getAll` | existing mapping; implementation/dependency changed |
| POST | `/api/v1/lawyer/educations` | `LawyerEducationController.create` | existing mapping; implementation/dependency changed |
| POST | `/api/v1/lawyer/educations/multipart` (multipart) | `LawyerEducationController.createMultipart` | mapping absent from HEAD (authorship unproven for untracked source) |
| PUT | `/api/v1/lawyer/educations/{id}` | `LawyerEducationController.update` | existing mapping; implementation/dependency changed |
| PUT | `/api/v1/lawyer/educations/{id}/multipart` (multipart) | `LawyerEducationController.updateMultipart` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/lawyer/educations/{id}/certificate` (multipart) | `LawyerEducationController.uploadCertificate` | existing mapping; implementation/dependency changed |
| DELETE | `/api/v1/lawyer/educations/{id}/certificate` | `LawyerEducationController.deleteCertificate` | existing mapping; implementation/dependency changed |
| DELETE | `/api/v1/lawyer/educations/{id}` | `LawyerEducationController.delete` | existing mapping; implementation/dependency changed |
| GET | `/api/v1/lawyer/high-court` | `LawyerHighCourtController.get` | existing mapping; implementation/dependency changed |
| PUT | `/api/v1/lawyer/high-court` | `LawyerHighCourtController.save` | existing mapping; implementation/dependency changed |
| PUT | `/api/v1/lawyer/high-court` (multipart) | `LawyerHighCourtController.saveMultipart` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/lawyer/high-court/permission-document` (multipart) | `LawyerHighCourtController.uploadPermissionDocument` | existing mapping; implementation/dependency changed |
| DELETE | `/api/v1/lawyer/high-court/permission-document` | `LawyerHighCourtController.deletePermissionDocument` | existing mapping; implementation/dependency changed |
| POST | `/api/v1/lawyer/high-court/sanad-document` (multipart) | `LawyerHighCourtController.uploadSanadDocument` | existing mapping; implementation/dependency changed |
| DELETE | `/api/v1/lawyer/high-court/sanad-document` | `LawyerHighCourtController.deleteSanadDocument` | existing mapping; implementation/dependency changed |
| GET | `/api/v1/lawyer/memberships` | `LawyerMembershipController.getAll` | existing mapping; implementation/dependency changed |
| POST | `/api/v1/lawyer/memberships` | `LawyerMembershipController.create` | existing mapping; implementation/dependency changed |
| POST | `/api/v1/lawyer/memberships/multipart` (multipart) | `LawyerMembershipController.createMultipart` | mapping absent from HEAD (authorship unproven for untracked source) |
| PUT | `/api/v1/lawyer/memberships/{id}` | `LawyerMembershipController.update` | existing mapping; implementation/dependency changed |
| PUT | `/api/v1/lawyer/memberships/{id}/multipart` (multipart) | `LawyerMembershipController.updateMultipart` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/lawyer/memberships/{id}/document` (multipart) | `LawyerMembershipController.uploadDocument` | existing mapping; implementation/dependency changed |
| DELETE | `/api/v1/lawyer/memberships/{id}/document` | `LawyerMembershipController.deleteDocument` | existing mapping; implementation/dependency changed |
| DELETE | `/api/v1/lawyer/memberships/{id}` | `LawyerMembershipController.delete` | existing mapping; implementation/dependency changed |
| GET | `/api/v1/lawyer/supreme-court` | `LawyerSupremeCourtController.get` | existing mapping; implementation/dependency changed |
| PUT | `/api/v1/lawyer/supreme-court` | `LawyerSupremeCourtController.save` | existing mapping; implementation/dependency changed |
| PUT | `/api/v1/lawyer/supreme-court` (multipart) | `LawyerSupremeCourtController.saveMultipart` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/lawyer/supreme-court/scba-certificate` (multipart) | `LawyerSupremeCourtController.uploadScbaCertificate` | existing mapping; implementation/dependency changed |
| DELETE | `/api/v1/lawyer/supreme-court/scba-certificate` | `LawyerSupremeCourtController.deleteScbaCertificate` | existing mapping; implementation/dependency changed |
| POST | `/api/v1/lawyer/supreme-court/scba-id-document` (multipart) | `LawyerSupremeCourtController.uploadScbaIdDocument` | existing mapping; implementation/dependency changed |
| DELETE | `/api/v1/lawyer/supreme-court/scba-id-document` | `LawyerSupremeCourtController.deleteScbaIdDocument` | existing mapping; implementation/dependency changed |
| POST | `/api/v1/lawyer/supreme-court/appellate-division-document` (multipart) | `LawyerSupremeCourtController.uploadAppellateDivisionDocument` | existing mapping; implementation/dependency changed |
| DELETE | `/api/v1/lawyer/supreme-court/appellate-division-document` | `LawyerSupremeCourtController.deleteAppellateDivisionDocument` | existing mapping; implementation/dependency changed |
| POST | `/api/v1/lawyer/supreme-court/senior-advocate-document` (multipart) | `LawyerSupremeCourtController.uploadSeniorAdvocateDocument` | existing mapping; implementation/dependency changed |
| DELETE | `/api/v1/lawyer/supreme-court/senior-advocate-document` | `LawyerSupremeCourtController.deleteSeniorAdvocateDocument` | existing mapping; implementation/dependency changed |
| GET | `/api/v1/lawyer/trainings` | `LawyerTrainingController.getAll` | existing mapping; implementation/dependency changed |
| POST | `/api/v1/lawyer/trainings` | `LawyerTrainingController.create` | existing mapping; implementation/dependency changed |
| POST | `/api/v1/lawyer/trainings/multipart` (multipart) | `LawyerTrainingController.createMultipart` | mapping absent from HEAD (authorship unproven for untracked source) |
| PUT | `/api/v1/lawyer/trainings/{id}` | `LawyerTrainingController.update` | existing mapping; implementation/dependency changed |
| PUT | `/api/v1/lawyer/trainings/{id}/multipart` (multipart) | `LawyerTrainingController.updateMultipart` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/lawyer/trainings/{id}/certificate` (multipart) | `LawyerTrainingController.uploadCertificate` | existing mapping; implementation/dependency changed |
| DELETE | `/api/v1/lawyer/trainings/{id}/certificate` | `LawyerTrainingController.deleteCertificate` | existing mapping; implementation/dependency changed |
| DELETE | `/api/v1/lawyer/trainings/{id}` | `LawyerTrainingController.delete` | existing mapping; implementation/dependency changed |
| GET | `/api/v1/notifications` | `NotificationController.getNotifications` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/notifications/unread-count` | `NotificationController.getUnreadCount` | mapping absent from HEAD (authorship unproven for untracked source) |
| PATCH | `/api/v1/notifications/{id}/read` | `NotificationController.markNotificationAsRead` | mapping absent from HEAD (authorship unproven for untracked source) |
| PATCH | `/api/v1/notifications/read-all` | `NotificationController.markAllNotificationsAsRead` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/files/upload` | `FileUploadController.upload` | existing mapping; implementation/dependency changed |
| DELETE | `/api/v1/files` | `FileUploadController.delete` | existing mapping; implementation/dependency changed |
| POST | `/api/v1/support/tickets` | `SupportTicketController.createTicket` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/support/tickets` | `SupportTicketController.listTickets` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/support/tickets/{ticketId}` | `SupportTicketController.getTicket` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/users/profile/role` | `UserController.selectRole` | existing mapping; implementation/dependency changed |
| GET | `/api/v1/users/me` | `UserController.me` | existing mapping; implementation/dependency changed |
| GET | `/api/v1/users/me/message-privacy` | `UserController.getMessagePrivacy` | mapping absent from HEAD (authorship unproven for untracked source) |
| PUT | `/api/v1/users/me/message-privacy` | `UserController.updateMessagePrivacy` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/users/me/comment-privacy` | `UserController.getCommentPrivacy` | mapping absent from HEAD (authorship unproven for untracked source) |
| PUT | `/api/v1/users/me/comment-privacy` | `UserController.updateCommentPrivacy` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/users/me/notification-preferences` | `UserController.getNotificationPreferences` | mapping absent from HEAD (authorship unproven for untracked source) |
| PUT | `/api/v1/users/me/notification-preferences` | `UserController.updateNotificationPreferences` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/video-calls/scheduled` | `ScheduledVideoCallController.scheduleCall` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/video-calls/scheduled` | `ScheduledVideoCallController.listScheduledCalls` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/video-calls/scheduled/{scheduledCallId}` | `ScheduledVideoCallController.getScheduledCall` | mapping absent from HEAD (authorship unproven for untracked source) |
| PATCH | `/api/v1/video-calls/scheduled/{scheduledCallId}/reschedule` | `ScheduledVideoCallController.rescheduleCall` | mapping absent from HEAD (authorship unproven for untracked source) |
| PATCH | `/api/v1/video-calls/scheduled/{scheduledCallId}/cancel` | `ScheduledVideoCallController.cancelCall` | mapping absent from HEAD (authorship unproven for untracked source) |
| PATCH | `/api/v1/video-calls/scheduled/{scheduledCallId}/start` | `ScheduledVideoCallController.startCall` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/video-calls/scheduled/{scheduledCallId}/join` | `ScheduledVideoCallController.joinScheduledCall` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/video-calls` | `VideoCallController.initiateCall` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/video-calls/{callId}` | `VideoCallController.getCall` | mapping absent from HEAD (authorship unproven for untracked source) |
| PATCH | `/api/v1/video-calls/{callId}/ring` | `VideoCallController.markRinging` | mapping absent from HEAD (authorship unproven for untracked source) |
| PATCH | `/api/v1/video-calls/{callId}/accept` | `VideoCallController.acceptCall` | mapping absent from HEAD (authorship unproven for untracked source) |
| PATCH | `/api/v1/video-calls/{callId}/reject` | `VideoCallController.rejectCall` | mapping absent from HEAD (authorship unproven for untracked source) |
| PATCH | `/api/v1/video-calls/{callId}/cancel` | `VideoCallController.cancelCall` | mapping absent from HEAD (authorship unproven for untracked source) |
| PATCH | `/api/v1/video-calls/{callId}/end` | `VideoCallController.endCall` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/video-calls/{callId}/signal` | `VideoCallController.signalCall` | mapping absent from HEAD (authorship unproven for untracked source) |
| POST | `/api/v1/video-calls/{callId}/join` | `VideoCallController.joinCall` | mapping absent from HEAD (authorship unproven for untracked source) |
| GET | `/api/v1/video-calls` | `VideoCallController.listCalls` | mapping absent from HEAD (authorship unproven for untracked source) |

### 5.2 Entity/table inventory absent from HEAD, plus changed tracked entities

These entities may require tables/constraints when merging onto HEAD. No database or migration was run in this request. Field names are navigation evidence, not SQL migration definitions; inspect each class for types, nullability, indexes and relationships.

| Entity path | Table | Persistent-field navigation |
| --- | --- | --- |
| `src/main/java/com/attorlink/boost/entity/BoostActivity.java` | `boost_activities` | `id`, `profileBoost`, `boostPayment`, `actor`, `activityType`, `description`, `metadataJson`, `createdAt` |
| `src/main/java/com/attorlink/boost/entity/BoostAnalyticsEvent.java` | `boost_analytics_events` | `id`, `boost`, `post`, `viewer`, `eventType`, `eventDay`, `createdAt` |
| `src/main/java/com/attorlink/boost/entity/BoostInvoice.java` | `boost_invoices` | `id`, `version`, `boostPayment`, `profileBoost`, `invoiceNumber`, `merchantInvoiceNumber`, `amount`, `currency`, `status`, `issuedAt`, `paidAt`, `pdfUrl`, `pdfPublicId`, `createdAt`, `updatedAt` |
| `src/main/java/com/attorlink/boost/entity/BoostPayment.java` | `boost_payments` | `id`, `version`, `profileBoost`, `payer`, `provider`, `paymentReference`, `providerPaymentId`, `merchantInvoiceNumber`, `transactionId`, `amount`, `currency`, `status`, `callbackPayload`, `rawResponse`, `createdAt`, `updatedAt`, `verifiedAt` |
| `src/main/java/com/attorlink/boost/entity/BoostPlan.java` | `boost_plans` | `id`, `version`, `code`, `name`, `description`, `durationDays`, `priceAmount`, `currency`, `status`, `displayOrder`, `createdAt`, `updatedAt` |
| `src/main/java/com/attorlink/boost/entity/ProfileBoost.java` | `profile_boosts` | `id`, `version`, `lawyerProfile`, `boostPlan`, `planName`, `planDurationDays`, `planPriceAmount`, `planCurrency`, `startsAt`, `scheduledAt`, `endsAt`, `activatedAt`, `expiredAt`, `status`, `createdAt`, `updatedAt` |
| `src/main/java/com/attorlink/chat/entity/ChatConversation.java` | `chat_conversations` | `id`, `participantA`, `participantB`, `conversationType`, `initiatedByUser`, `requestStatus`, `lastMessageAt`, `createdAt`, `updatedAt` |
| `src/main/java/com/attorlink/chat/entity/ChatMessage.java` | `chat_messages` | `id`, `conversation`, `sender`, `messageType`, `textContent`, `createdAt`, `updatedAt`, `editedAt`, `deletedAt` |
| `src/main/java/com/attorlink/chat/entity/ChatMessageDelivery.java` | `chat_message_deliveries` | `id`, `message`, `user`, `deliveryStatus`, `createdAt`, `updatedAt`, `deliveredAt`, `seenAt` |
| `src/main/java/com/attorlink/client/entity/ClientLegalPreference.java` | `client_legal_preferences` | `id`, `user`, `practiceAreaIds`, `jurisdictionIds`, `courtIds`, `lawyerLanguages`, `createdAt`, `updatedAt` |
| `src/main/java/com/attorlink/community/entity/Comment.java` | `community_comments` | `id`, `post`, `author`, `parent`, `text`, `deleted`, `deletedAt`, `createdAt`, `updatedAt` |
| `src/main/java/com/attorlink/community/entity/CommentVote.java` | `community_comment_votes` | `id`, `comment`, `user`, `voteType`, `createdAt`, `updatedAt` |
| `src/main/java/com/attorlink/community/entity/ContentReport.java` | `content_reports` | `id`, `version`, `reporter`, `targetType`, `targetId`, `reason`, `explanation`, `status`, `moderator`, `moderatorDecision`, `moderatorReason`, `createdAt`, `reviewedAt`, `updatedAt` |
| `src/main/java/com/attorlink/community/entity/ContentReportAudit.java` | `content_report_audits` | `id`, `contentReport`, `moderator`, `decision`, `decisionReason`, `createdAt` |
| `src/main/java/com/attorlink/community/entity/FeedAnalyticsEvent.java` | `feed_analytics_events` | `id`, `actorId`, `postId`, `eventType`, `feedMode`, `createdAt` |
| `src/main/java/com/attorlink/community/entity/LawyerFollow.java` | `community_lawyer_follows` | `id`, `follower`, `lawyer`, `createdAt` |
| `src/main/java/com/attorlink/community/entity/Post.java` | `community_posts` | `id`, `author`, `type`, `textContent`, `mediaUrl`, `mediaPublicId`, `deleted`, `deletedAt`, `createdAt`, `updatedAt` |
| `src/main/java/com/attorlink/community/entity/PostBookmark.java` | `community_post_bookmarks` | `id`, `user`, `post`, `createdAt` |
| `src/main/java/com/attorlink/community/entity/PostLike.java` | `community_post_likes` | `id`, `post`, `user`, `createdAt` |
| `src/main/java/com/attorlink/community/entity/PostMedia.java` | `community_post_media` | `id`, `owner`, `publicId`, `url`, `resourceType`, `mimeType`, `createdAt` |
| `src/main/java/com/attorlink/community/entity/PostShare.java` | `community_post_shares` | `id`, `post`, `user`, `createdAt` |
| `src/main/java/com/attorlink/notification/entity/EmailLog.java` | `email_logs` | `id`, `toEmail`, `notificationId`, `eventId`, `subject`, `template`, `status`, `error`, `createdAt` |
| `src/main/java/com/attorlink/notification/entity/Notification.java` | `notifications` | `id`, `recipient`, `actor`, `type`, `title`, `message`, `relatedEntityType`, `relatedEntityId`, `eventId`, `read`, `createdAt`, `readAt` |
| `src/main/java/com/attorlink/support/entity/SupportTicket.java` | `support_tickets` | `id`, `user`, `referenceNumber`, `subject`, `message`, `category`, `status`, `createdAt`, `updatedAt` |
| `src/main/java/com/attorlink/user/entity/UserCommentPrivacySetting.java` | `user_comment_privacy_settings` | `id`, `user`, `whoCanCommentOnMyPosts`, `createdAt`, `updatedAt` |
| `src/main/java/com/attorlink/user/entity/UserMessagePrivacySetting.java` | `user_message_privacy_settings` | `id`, `user`, `whoCanMessageMe`, `createdAt`, `updatedAt` |
| `src/main/java/com/attorlink/user/entity/UserNotificationPreference.java` | `user_notification_preferences` | `id`, `user`, `social`, `messaging`, `lawyerActivity`, `system`, `createdAt`, `updatedAt` |
| `src/main/java/com/attorlink/video/entity/ScheduledVideoCall.java` | `scheduled_video_calls` | `id`, `caller`, `recipient`, `conversation`, `scheduledAt`, `roomId`, `status`, `notes`, `cancelReason`, `lastReminderSentAt`, `reminderCount`, `startedAt`, `cancelledAt`, `missedAt`, `createdAt`, `updatedAt` |
| `src/main/java/com/attorlink/video/entity/VideoCall.java` | `video_calls` | `id`, `caller`, `recipient`, `conversation`, `status`, `roomId`, `initiatedAt`, `acceptedAt`, `rejectedAt`, `cancelledAt`, `endedAt`, `failedAt`, `failureReason`, `lastSignalAt`, `createdAt`, `updatedAt` |

### 5.3 DTOs absent from HEAD

Existing tracked authentication DTOs and common response envelope classes have no current working-tree changes. The following DTO paths are absent from HEAD and require explicit contract review if these modules are not already in the engineer’s branch. Full validation is in their source; this index does not assert that all were Codex additions.

```text
src/main/java/com/attorlink/admin/dto/AdminContentReportDecisionRequest.java
src/main/java/com/attorlink/admin/dto/AdminContentReportDetailResponse.java
src/main/java/com/attorlink/admin/dto/AdminContentReportListResponse.java
src/main/java/com/attorlink/admin/dto/BoostPlanRequest.java
src/main/java/com/attorlink/admin/dto/BoostPlanResponse.java
src/main/java/com/attorlink/auth/dto/SessionResponse.java
src/main/java/com/attorlink/boost/dto/BoostActivityResponse.java
src/main/java/com/attorlink/boost/dto/BoostAdminSummaryResponse.java
src/main/java/com/attorlink/boost/dto/BoostAnalyticsAdminSummaryResponse.java
src/main/java/com/attorlink/boost/dto/BoostAnalyticsDailyResponse.java
src/main/java/com/attorlink/boost/dto/BoostAnalyticsSummaryResponse.java
src/main/java/com/attorlink/boost/dto/BoostInvoiceMonitoringResponse.java
src/main/java/com/attorlink/boost/dto/BoostInvoiceResponse.java
src/main/java/com/attorlink/boost/dto/BoostMonitoringResponse.java
src/main/java/com/attorlink/boost/dto/BoostPaymentMonitoringResponse.java
src/main/java/com/attorlink/boost/dto/BoostPlanListingResponse.java
src/main/java/com/attorlink/boost/dto/BoostPurchaseRequest.java
src/main/java/com/attorlink/boost/dto/BoostPurchaseResponse.java
src/main/java/com/attorlink/boost/dto/BoostSandboxCheckoutHandoffResponse.java
src/main/java/com/attorlink/chat/dto/ChatConversationResponse.java
src/main/java/com/attorlink/chat/dto/ChatMessageDeletionResponse.java
src/main/java/com/attorlink/chat/dto/ChatMessageResponse.java
src/main/java/com/attorlink/chat/dto/ChatSocketAckRequest.java
src/main/java/com/attorlink/chat/dto/ChatSocketSendRequest.java
src/main/java/com/attorlink/chat/dto/ConversationReadSummaryResponse.java
src/main/java/com/attorlink/chat/dto/CreateChatConversationRequest.java
src/main/java/com/attorlink/chat/dto/CreateChatMessageRequest.java
src/main/java/com/attorlink/chat/dto/IncrementalChatSyncRequest.java
src/main/java/com/attorlink/chat/dto/IncrementalChatSyncResponse.java
src/main/java/com/attorlink/chat/dto/MarkConversationReadRequest.java
src/main/java/com/attorlink/client/dto/ClientLegalPreferencesRequest.java
src/main/java/com/attorlink/client/dto/ClientLegalPreferencesResponse.java
src/main/java/com/attorlink/community/dto/CommentCreateRequest.java
src/main/java/com/attorlink/community/dto/CommentResponse.java
src/main/java/com/attorlink/community/dto/CommentUpdateRequest.java
src/main/java/com/attorlink/community/dto/CommentVoteRequest.java
src/main/java/com/attorlink/community/dto/ContentReportCreateRequest.java
src/main/java/com/attorlink/community/dto/ContentReportResponse.java
src/main/java/com/attorlink/community/dto/FeedAnalyticsEventRequest.java
src/main/java/com/attorlink/community/dto/FeedAnalyticsSummaryResponse.java
src/main/java/com/attorlink/community/dto/LawyerFollowResponse.java
src/main/java/com/attorlink/community/dto/PostCreateRequest.java
src/main/java/com/attorlink/community/dto/PostResponse.java
src/main/java/com/attorlink/community/dto/PostShareResponse.java
src/main/java/com/attorlink/community/dto/PostUpdateRequest.java
src/main/java/com/attorlink/lawyer/dto/LawyerDiscoverResponse.java
src/main/java/com/attorlink/notification/dto/NotificationListResponse.java
src/main/java/com/attorlink/notification/dto/NotificationReadAllResponse.java
src/main/java/com/attorlink/notification/dto/NotificationResponse.java
src/main/java/com/attorlink/notification/dto/NotificationUnreadCountResponse.java
src/main/java/com/attorlink/support/dto/AdminSupportTicketDetailResponse.java
src/main/java/com/attorlink/support/dto/AdminSupportTicketListResponse.java
src/main/java/com/attorlink/support/dto/AdminSupportTicketStatusUpdateRequest.java
src/main/java/com/attorlink/support/dto/SupportTicketCreateRequest.java
src/main/java/com/attorlink/support/dto/SupportTicketResponse.java
src/main/java/com/attorlink/user/dto/NotificationPreferenceRequest.java
src/main/java/com/attorlink/user/dto/NotificationPreferenceResponse.java
src/main/java/com/attorlink/user/dto/WhoCanCommentOnMyPostsRequest.java
src/main/java/com/attorlink/user/dto/WhoCanCommentOnMyPostsResponse.java
src/main/java/com/attorlink/user/dto/WhoCanMessageMeRequest.java
src/main/java/com/attorlink/user/dto/WhoCanMessageMeResponse.java
src/main/java/com/attorlink/video/dto/RescheduleScheduledVideoCallRequest.java
src/main/java/com/attorlink/video/dto/ScheduledVideoCallRequest.java
src/main/java/com/attorlink/video/dto/ScheduledVideoCallResponse.java
src/main/java/com/attorlink/video/dto/VideoCallInitiateRequest.java
src/main/java/com/attorlink/video/dto/VideoCallJoinResponse.java
src/main/java/com/attorlink/video/dto/VideoCallResponse.java
src/main/java/com/attorlink/video/dto/VideoCallSignalRequest.java
```


## 6. Configuration and infrastructure changes

### 6.1 Current SMTP/startup settings

| Configuration | Current behavior / required input |
| --- | --- |
| `spring.mail.host`, `spring.mail.port` | `${MAIL_HOST:smtp.gmail.com}`, `${MAIL_PORT:587}`. |
| `spring.mail.username`, `.password` | `${MAIL_USERNAME:}`, `${MAIL_PASSWORD:}`. Empty by default; no committed replacement credential supplied by this task. |
| `spring.mail.properties.mail.smtp.auth` | Literal `true`; authentication is enabled. |
| `.starttls.enable`, `.starttls.required` | Both literal `true`; Gmail port 587 requires STARTTLS, with no plaintext fallback. |
| SMTP connection/read/write timeouts | Each 5000 ms in the current YAML. |
| `app.mail.enabled` | `${MAIL_ENABLED:true}`; disabled required OTP delivery fails rather than pretending success. |
| `app.mail.from` | `MAIL_FROM` with SMTP username fallback; supply an account-authorized From address. |
| `app.mail.notification-enabled` | `${MAIL_NOTIFICATION_ENABLED:true}` for optional centralized mail. |
| `DB_PASSWORD`, `JWT_SECRET`, `ADMIN_PASSWORD` | Nonempty secret fallbacks removed, **empty defaults retained**. Inject real protected values. JWT key must meet existing byte-length requirement. No old exposed value was restored. |
| Legacy `MAIL_SMTP_*` variables | Previously supported in YAML but currently no bindings. Do not assume the old Mailpit launcher can disable literal auth/TLS by exporting these variables. |

The three actual-YAML tests distinguish YAML syntax/nesting, real sender binding with fixture credentials, and empty-secret startup semantics. They are not an authenticated Gmail delivery test. Current shell or source placeholders alone cannot prove what a deployed Java process received. No Gmail password, OTP, reset token or JWT appears in this report.

### 6.2 Other runtime configuration and compatibility

- Java **21**, Spring Boot parent **3.5.16**, Maven project **0.0.1-SNAPSHOT**. Executed tooling: installed OpenJDK 21.0.13.0.3 / Maven 3.10.0. No installations or online resolution.
- Existing database/cache inputs: `DB_URL`, `DB_USERNAME`, `DB_PASSWORD`, `REDIS_HOST`, `REDIS_PORT`, `REDIS_TIMEOUT`. Existing auth inputs: `JWT_SECRET`, `JWT_ACCESS_EXPIRATION_MINUTES`, `JWT_REFRESH_EXPIRATION_DAYS`, `JWT_REFRESH_EXPIRATION_HOURS`, `ADMIN_USERNAME`, `ADMIN_PASSWORD`, OTP expiration/attempt/resend settings and account-deletion grace days. These should remain server-side; Flutter uses only Spring APIs.
- WebSocket environment: `WEBSOCKET_ENDPOINT_PATH`, `WEBSOCKET_ALLOWED_ORIGINS`. The normalized endpoint defaults to `/ws` in YAML; the AppProperties fallback differs but normal Spring YAML supplies it. Preserve frontend `ATTORLINK_SOCKET_PATH` compatibility. Correct the default origin escaping before relying on its localhost defaults.
- Server-only Cloudinary inputs: `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET`. No cloud credential belongs in Flutter. Existing dedicated cloud/account feature policies and authenticated-raw delivery need actual provider acceptance.
- LiveKit: `VIDEO_PROVIDER`, `VIDEO_LIVEKIT_ENABLED`, `LIVEKIT_URL`, optional **new `LIVEKIT_API_URL`**, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `VIDEO_LIVEKIT_TOKEN_TTL_SECONDS`, `VIDEO_LIVEKIT_ROOM_PREFIX`, `VIDEO_LIVEKIT_AUTO_CREATE_ROOM`. Public URL must reach devices; API URL is backend-only. Root `video.*` and `video-scheduling.*` bridge into `app.*` and remain available for existing deployments.
- Scheduling inputs: `VIDEO_SCHEDULING_MIN_NOTICE_MINUTES`, `VIDEO_SCHEDULING_MAX_HORIZON_DAYS`, `VIDEO_SCHEDULING_REMINDER_MINUTES_BEFORE`, `VIDEO_SCHEDULING_CANCELLATION_CUTOFF_MINUTES`, `VIDEO_SCHEDULING_RESCHEDULE_CUTOFF_MINUTES`. Explicit business/JVM timezone acceptance is still needed.
- Production devices require trusted HTTPS/WSS, supported reverse-proxy WebSocket upgrades and actual RTC address/ICE/TURN/NAT configuration for media. No firewall/network settings were changed; no guessed media port ranges are prescribed as proven.

### 6.3 POM dependency delta versus HEAD

| Added dependency | Version/source | Purpose / review |
| --- | --- | --- |
| `spring-boot-starter-websocket` | Spring Boot managed | Existing SockJS/STOMP transport and broker. |
| `spring-security-messaging` | Spring Boot managed | Inbound security context/destination authorization. |
| `com.itextpdf:kernel`, `com.itextpdf:layout` | **8.0.5** | Existing invoice PDF generation; review deployment/license obligations. |
| `io.livekit:livekit-server` | **0.10.0** | Server-side media credentials and room client. |
| `com.h2database:h2` | Managed, test scope | Disposable repository/transaction tests. |

These are verifiable working-tree additions to the POM, not evidence all were introduced during the latest corrective batch. Original JWT/googleauth/Cloudinary/springdoc properties remain at their existing versions in the compared POM. No dependency upgrade/install was performed here. Cached artifacts absent from the local project cache were copied from the already-installed user Maven cache; nothing was downloaded.

### 6.4 Mailpit remains in the isolated infrastructure

**Mailpit has not been removed.** The original backend `docker-compose.yml` provides MySQL/Redis rather than Mailpit, while the existing Flutter-owned disposable setup still contains:

- `build/integration/compose.yaml`: `mailpit` service, `axllent/mailpit:latest`, loopback SMTP/web publications.
- `build/integration/phase11f1/compose.override.yaml`: Mailpit SMTP `127.0.0.1:11025` and UI/API `127.0.0.1:18025` override.
- `build/integration/phase11f1/start_backend.py`: Mailpit service/health/publication guards and explicit loopback SMTP/no-auth/no-TLS/blank-credential environment, using an isolated JAR snapshot rather than automatically the latest source.
- Existing auth integration scripts fetch OTPs through Mailpit; previous result documentation describes historical delivery. The existing mocked `SmtpEmailIntegrationTest.mailpitConfigurationDoesNotRequireUsernameOrTls` uses only an in-memory configuration context; it neither provisions nor contacts Mailpit.

Do not reuse the old launcher as evidence that the latest original YAML is deployed. Its old `MAIL_SMTP_*` variables no longer control the literal YAML policy, and its built JAR may have older resources. This is a cutover task, not merely a Gmail host change. Container running state was not queried or changed in this request. No MySQL/Redis data, container, volume, network or image was removed. Gmail migration/removal remains pending a separately reviewed minimal cutover with current protected credentials and authorized recipient; do not replace routine mock tests with real Gmail sends.



## 7. Verifiable Git and file inventory

Current HEAD: `e90002853f87ab49f7165112158b7352e990c2af`. Earliest available commit: `884c5db626a1f909afa3b1d0ffb220cc78b928f2`. There are **50 tracked modifications**, **324 individually listed untracked files**, and **no tracked deletions**. `git diff HEAD` does not include the untracked files; a normal diff/patch alone would omit entire functioning subsystems. No new commit was created. Status was captured before testing in `build/backend-handover/git_status_before.txt`.

### 7.1 Existing committed range (not automatically Codex-authored)

The only available commit range is `884c5db..e900028`. The following paths changed in that range. This is historical developer work with uncertain authorship, kept separate from current uncommitted changes.

```text
M	README.md
M	src/main/java/com/attorlink/admin/controller/UserManagementController.java
M	src/main/java/com/attorlink/admin/dto/AdminUserListResponse.java
M	src/main/java/com/attorlink/admin/entity/AdminAction.java
M	src/main/java/com/attorlink/admin/service/AdminUserServiceImpl.java
M	src/main/java/com/attorlink/auth/controller/TwoFactorController.java
M	src/main/java/com/attorlink/auth/service/OtpServiceImpl.java
M	src/main/java/com/attorlink/auth/service/TwoFactorService.java
M	src/main/java/com/attorlink/auth/service/TwoFactorServiceImpl.java
M	src/main/java/com/attorlink/client/controller/ClientProfileController.java
A	src/main/java/com/attorlink/client/dto/ClientProfilePhotoResponse.java
A	src/main/java/com/attorlink/client/dto/ClientProfilePhotoUploadRequest.java
M	src/main/java/com/attorlink/client/dto/ClientProfileRequest.java
M	src/main/java/com/attorlink/client/entity/ClientProfile.java
M	src/main/java/com/attorlink/client/service/ClientProfileService.java
M	src/main/java/com/attorlink/common/enums/OtpPurpose.java
M	src/main/java/com/attorlink/common/exception/GlobalExceptionHandler.java
M	src/main/java/com/attorlink/config/JwtConfig.java
M	src/main/java/com/attorlink/lawyer/controller/LawyerAwardController.java
M	src/main/java/com/attorlink/lawyer/controller/LawyerBarCouncilController.java
M	src/main/java/com/attorlink/lawyer/controller/LawyerCredentialController.java
M	src/main/java/com/attorlink/lawyer/controller/LawyerEducationController.java
M	src/main/java/com/attorlink/lawyer/controller/LawyerHighCourtController.java
M	src/main/java/com/attorlink/lawyer/controller/LawyerMembershipController.java
M	src/main/java/com/attorlink/lawyer/controller/LawyerProfileController.java
M	src/main/java/com/attorlink/lawyer/controller/LawyerSupremeCourtController.java
M	src/main/java/com/attorlink/lawyer/controller/LawyerTrainingController.java
M	src/main/java/com/attorlink/lawyer/dto/LawyerEducationRequest.java
A	src/main/java/com/attorlink/lawyer/dto/LawyerFileUploadRequest.java
A	src/main/java/com/attorlink/lawyer/dto/LawyerFileUploadResponse.java
M	src/main/java/com/attorlink/lawyer/entity/LawyerAward.java
M	src/main/java/com/attorlink/lawyer/entity/LawyerBarCouncil.java
M	src/main/java/com/attorlink/lawyer/entity/LawyerCredential.java
M	src/main/java/com/attorlink/lawyer/entity/LawyerEducation.java
M	src/main/java/com/attorlink/lawyer/entity/LawyerHighCourt.java
M	src/main/java/com/attorlink/lawyer/entity/LawyerMembership.java
M	src/main/java/com/attorlink/lawyer/entity/LawyerProfile.java
M	src/main/java/com/attorlink/lawyer/entity/LawyerSupremeCourt.java
M	src/main/java/com/attorlink/lawyer/entity/LawyerTraining.java
M	src/main/java/com/attorlink/lawyer/service/LawyerAwardService.java
M	src/main/java/com/attorlink/lawyer/service/LawyerBarCouncilService.java
M	src/main/java/com/attorlink/lawyer/service/LawyerCredentialService.java
M	src/main/java/com/attorlink/lawyer/service/LawyerEducationService.java
M	src/main/java/com/attorlink/lawyer/service/LawyerHighCourtService.java
M	src/main/java/com/attorlink/lawyer/service/LawyerMembershipService.java
M	src/main/java/com/attorlink/lawyer/service/LawyerProfileService.java
M	src/main/java/com/attorlink/lawyer/service/LawyerSupremeCourtService.java
M	src/main/java/com/attorlink/lawyer/service/LawyerTrainingService.java
M	src/main/resources/application.yml
A	src/test/java/com/attorlink/auth/service/TwoFactorServiceImplTest.java
```

### 7.2 Every current tracked modification

Paths below are relative to the backend. Methods are a navigation index of declarations in the changed class, **not a claim that every method changed**. Use `git diff HEAD -- <path>` locally for exact hunks; avoid printing configuration diffs containing historical secrets.

| Backend path | Major method navigation |
| --- | --- |
| `README.md` |  |
| `pom.xml` |  |
| `src/main/java/com/attorlink/admin/service/AdminUserServiceImpl.java` | `buildSpecification`, `changeStatus`, `detail`, `findUser`, `list`, `notifyAccountStatusChange`, `toListResponse` |
| `src/main/java/com/attorlink/admin/service/VerificationServiceImpl.java` | `act`, `detail`, `findProfile`, `markAllDocumentsVerified`, `notifyProfileVerificationDecision`, `queue`, `sanitizeRejectionReason`, `verifyDocument` |
| `src/main/java/com/attorlink/auth/repository/RefreshTokenRepository.java` |  |
| `src/main/java/com/attorlink/auth/service/AccountServiceImpl.java` | `cleanupStaleTempUsers`, `confirmDelete`, `findUser`, `notifyAccountLifecycle`, `purgeDueAccounts`, `requestDelete` |
| `src/main/java/com/attorlink/auth/service/AuthServiceImpl.java` | `completeLogin`, `issueTokens`, `login`, `loginFingerprint`, `loginTwoFactor`, `logout`, `pendingDeletion`, `refresh`, `requireLoginEligible`, `resendSignupOtp`, `restoreAccount`, `signup`, `verifySignupOtp` |
| `src/main/java/com/attorlink/auth/service/OtpServiceImpl.java` | `purposeLabel`, `sendOtp`, `verifyOtp` |
| `src/main/java/com/attorlink/auth/service/PasswordServiceImpl.java` | `buildSecurityHistory`, `findUserByEmail`, `forgotConfirm`, `forgotInit`, `forgotVerifyOtp`, `logActivity`, `resetConfirm`, `resetInit`, `validatePasswordMatch` |
| `src/main/java/com/attorlink/auth/service/RefreshTokenService.java` | `create`, `ownerOf`, `revoke`, `revokeAllForUser`, `revokeOwned`, `rotate`, `sessionId`, `validate` |
| `src/main/java/com/attorlink/auth/service/TwoFactorServiceImpl.java` | `disable`, `enableAuthenticator`, `enableEmailOtp`, `findUser`, `logActivity`, `setupAuthenticator`, `urlEncode`, `verifyAuthenticatorCode`, `verifyEmailOtpEnable` |
| `src/main/java/com/attorlink/client/controller/ClientProfileController.java` | `deleteProfilePhoto`, `getAddress`, `getPreferences`, `getProfile`, `updateAddress`, `updatePreferences`, `updateProfile`, `uploadProfilePhoto` |
| `src/main/java/com/attorlink/common/exception/GlobalExceptionHandler.java` | `handleAccessDenied`, `handleAuthentication`, `handleBadRequest`, `handleConflict`, `handleConstraintViolation`, `handleDataIntegrity`, `handleEmailDelivery`, `handleGeneric`, `handleHandlerValidation`, `handleInvalidCredentials`, `handleMaxUpload`, `handleNoHandler`, `handleNoResource`, `handleNotFound`, `handleRateLimit`, `handleSuspended`, `handleTypeMismatch`, `handleUnreadable`, `handleValidation` |
| `src/main/java/com/attorlink/common/redis/RedisService.java` | `consumeIfMatches`, `delete`, `deleteByPattern`, `exists`, `get`, `getAndDelete`, `increment`, `set` |
| `src/main/java/com/attorlink/config/AppProperties.java` |  |
| `src/main/java/com/attorlink/config/OpenApiConfig.java` | `adminApi`, `attorLinkOpenApi`, `authApi`, `catalogApi`, `communityApi`, `lawyerApi`, `userClientApi` |
| `src/main/java/com/attorlink/config/SchedulingConfig.java` | `notificationEmailExecutor` |
| `src/main/java/com/attorlink/config/SecurityConfig.java` | `passwordEncoder`, `restAccessDeniedHandler`, `restAuthenticationEntryPoint`, `securityFilterChain`, `writeJson` |
| `src/main/java/com/attorlink/lawyer/controller/LawyerAwardController.java` | `create`, `createMultipart`, `delete`, `deleteDocument`, `getAll`, `update`, `updateMultipart`, `uploadDocument` |
| `src/main/java/com/attorlink/lawyer/controller/LawyerBarCouncilController.java` | `deleteGreenBook`, `deleteIdentityCard`, `deleteSanad`, `get`, `save`, `saveMultipart`, `uploadGreenBook`, `uploadIdentityCard`, `uploadSanad` |
| `src/main/java/com/attorlink/lawyer/controller/LawyerCredentialController.java` | `create`, `createMultipart`, `delete`, `deleteDocument`, `getAll`, `update`, `updateMultipart`, `uploadDocument` |
| `src/main/java/com/attorlink/lawyer/controller/LawyerEducationController.java` | `create`, `createMultipart`, `delete`, `deleteCertificate`, `getAll`, `update`, `updateMultipart`, `uploadCertificate` |
| `src/main/java/com/attorlink/lawyer/controller/LawyerHighCourtController.java` | `deletePermissionDocument`, `deleteSanadDocument`, `get`, `save`, `saveMultipart`, `uploadPermissionDocument`, `uploadSanadDocument` |
| `src/main/java/com/attorlink/lawyer/controller/LawyerMembershipController.java` | `create`, `createMultipart`, `delete`, `deleteDocument`, `getAll`, `update`, `updateMultipart`, `uploadDocument` |
| `src/main/java/com/attorlink/lawyer/controller/LawyerSupremeCourtController.java` | `deleteAppellateDivisionDocument`, `deleteScbaCertificate`, `deleteScbaIdDocument`, `deleteSeniorAdvocateDocument`, `get`, `save`, `saveMultipart`, `uploadAppellateDivisionDocument`, `uploadScbaCertificate`, `uploadScbaIdDocument`, `uploadSeniorAdvocateDocument` |
| `src/main/java/com/attorlink/lawyer/controller/LawyerTrainingController.java` | `create`, `createMultipart`, `delete`, `deleteCertificate`, `getAll`, `update`, `updateMultipart`, `uploadCertificate` |
| `src/main/java/com/attorlink/lawyer/repository/LawyerProfileRepository.java` |  |
| `src/main/java/com/attorlink/lawyer/repository/LawyerSpecializationRepository.java` |  |
| `src/main/java/com/attorlink/lawyer/service/LawyerAwardService.java` | `create`, `delete`, `deleteCloudinaryIfPresent`, `deleteDocument`, `findOwned`, `getAll`, `replaceCloudinaryAsset`, `update`, `uploadDocument` |
| `src/main/java/com/attorlink/lawyer/service/LawyerBarCouncilService.java` | `deleteCloudinaryIfPresent`, `deleteGreenBook`, `deleteIdentityCard`, `deleteSanad`, `get`, `getOwned`, `replaceCloudinaryAsset`, `save`, `uploadGreenBook`, `uploadIdentityCard`, `uploadSanad` |
| `src/main/java/com/attorlink/lawyer/service/LawyerCredentialService.java` | `create`, `delete`, `deleteCloudinaryIfPresent`, `deleteDocument`, `findOwned`, `getAll`, `replaceCloudinaryAsset`, `update`, `uploadDocument` |
| `src/main/java/com/attorlink/lawyer/service/LawyerEducationService.java` | `create`, `delete`, `deleteCertificate`, `deleteCloudinaryIfPresent`, `findOwned`, `getAll`, `replaceCloudinaryAsset`, `update`, `uploadCertificate` |
| `src/main/java/com/attorlink/lawyer/service/LawyerHighCourtService.java` | `deleteCloudinaryIfPresent`, `deletePermissionDocument`, `deleteSanadDocument`, `get`, `getOwned`, `replaceCloudinaryAsset`, `save`, `uploadPermissionDocument`, `uploadSanadDocument` |
| `src/main/java/com/attorlink/lawyer/service/LawyerMembershipService.java` | `create`, `delete`, `deleteCloudinaryIfPresent`, `deleteDocument`, `findOwned`, `getAll`, `replaceCloudinaryAsset`, `update`, `uploadDocument` |
| `src/main/java/com/attorlink/lawyer/service/LawyerProfileService.java` | `applyRequest`, `createDraftProfile`, `deleteCoverPhoto`, `deleteProfilePhoto`, `getProfile`, `isBlank`, `replaceCloudinaryAsset`, `submit`, `updateProfile`, `uploadCoverPhoto`, `uploadProfilePhoto` |
| `src/main/java/com/attorlink/lawyer/service/LawyerSupremeCourtService.java` | `deleteAppellateDivisionDocument`, `deleteCloudinaryIfPresent`, `deleteScbaCertificate`, `deleteScbaIdDocument`, `deleteSeniorAdvocateDocument`, `get`, `getOwned`, `replaceCloudinaryAsset`, `save`, `uploadAppellateDivisionDocument`, `uploadScbaCertificate`, `uploadScbaIdDocument`, `uploadSeniorAdvocateDocument` |
| `src/main/java/com/attorlink/lawyer/service/LawyerTrainingService.java` | `create`, `delete`, `deleteCertificate`, `deleteCloudinaryIfPresent`, `findOwned`, `getAll`, `replaceCloudinaryAsset`, `update`, `uploadCertificate` |
| `src/main/java/com/attorlink/notification/entity/EmailLog.java` |  |
| `src/main/java/com/attorlink/notification/repository/EmailLogRepository.java` |  |
| `src/main/java/com/attorlink/notification/service/EmailService.java` |  |
| `src/main/java/com/attorlink/notification/service/EmailServiceImpl.java` | `send`, `sendOtpEmail`, `sendTemplateEmail` |
| `src/main/java/com/attorlink/security/JwtAuthenticationFilter.java` | `doFilterInternal` |
| `src/main/java/com/attorlink/security/JwtService.java` | `generateAccessToken`, `generateAdminToken`, `isUserTokenActive`, `isValid`, `parse` |
| `src/main/java/com/attorlink/storage/StorageServiceImpl.java` | `cleanup`, `destroy`, `ensureConfigured`, `starts`, `upload`, `validate` |
| `src/main/java/com/attorlink/storage/controller/FileUploadController.java` | `delete`, `upload` |
| `src/main/java/com/attorlink/user/controller/UserController.java` | `getCommentPrivacy`, `getMessagePrivacy`, `getNotificationPreferences`, `me`, `selectRole`, `updateCommentPrivacy`, `updateMessagePrivacy`, `updateNotificationPreferences` |
| `src/main/java/com/attorlink/user/repository/UserRepository.java` |  |
| `src/main/java/com/attorlink/user/service/UserCleanupService.java` | `deleteUserCompletely`, `purgeScheduledUser` |
| `src/main/resources/application.yml` |  |
| `src/test/java/com/attorlink/auth/service/TwoFactorServiceImplTest.java` |  |

### 7.3 Every untracked file, grouped for selective review

`??` means absent from Git HEAD, not proven newly written by Codex. Some complete feature modules were already present during the first Flutter audit. Do not automatically stage PID/log files or claim original functionality as newly invented.

#### admin

```text
src/main/java/com/attorlink/admin/controller/AdminBoostAnalyticsController.java
src/main/java/com/attorlink/admin/controller/AdminBoostMonitoringController.java
src/main/java/com/attorlink/admin/controller/AdminBoostPlanController.java
src/main/java/com/attorlink/admin/controller/AdminContentReportController.java
src/main/java/com/attorlink/admin/controller/AdminSupportTicketController.java
src/main/java/com/attorlink/admin/dto/AdminContentReportDecisionRequest.java
src/main/java/com/attorlink/admin/dto/AdminContentReportDetailResponse.java
src/main/java/com/attorlink/admin/dto/AdminContentReportListResponse.java
src/main/java/com/attorlink/admin/dto/BoostPlanRequest.java
src/main/java/com/attorlink/admin/dto/BoostPlanResponse.java
src/main/java/com/attorlink/admin/service/AdminContentReportService.java
src/main/java/com/attorlink/admin/service/AdminContentReportServiceImpl.java
src/main/java/com/attorlink/admin/service/AdminSupportTicketService.java
src/main/java/com/attorlink/admin/service/AdminSupportTicketServiceImpl.java
src/main/java/com/attorlink/admin/service/BoostPlanAdminService.java
src/main/java/com/attorlink/admin/service/BoostPlanAdminServiceImpl.java
```

#### auth

```text
src/main/java/com/attorlink/auth/controller/SessionController.java
src/main/java/com/attorlink/auth/dto/SessionResponse.java
src/main/java/com/attorlink/auth/service/AccountSecurity.java
src/main/java/com/attorlink/auth/service/SessionService.java
```

#### boost

```text
src/main/java/com/attorlink/boost/controller/BoostAnalyticsTrackingController.java
src/main/java/com/attorlink/boost/controller/LawyerBoostAnalyticsController.java
src/main/java/com/attorlink/boost/controller/LawyerBoostController.java
src/main/java/com/attorlink/boost/controller/LawyerBoostInvoiceController.java
src/main/java/com/attorlink/boost/controller/LawyerBoostMonitoringController.java
src/main/java/com/attorlink/boost/controller/LawyerBoostSandboxCheckoutController.java
src/main/java/com/attorlink/boost/dto/BoostActivityResponse.java
src/main/java/com/attorlink/boost/dto/BoostAdminSummaryResponse.java
src/main/java/com/attorlink/boost/dto/BoostAnalyticsAdminSummaryResponse.java
src/main/java/com/attorlink/boost/dto/BoostAnalyticsDailyResponse.java
src/main/java/com/attorlink/boost/dto/BoostAnalyticsSummaryResponse.java
src/main/java/com/attorlink/boost/dto/BoostInvoiceMonitoringResponse.java
src/main/java/com/attorlink/boost/dto/BoostInvoiceResponse.java
src/main/java/com/attorlink/boost/dto/BoostMonitoringResponse.java
src/main/java/com/attorlink/boost/dto/BoostPaymentMonitoringResponse.java
src/main/java/com/attorlink/boost/dto/BoostPlanListingResponse.java
src/main/java/com/attorlink/boost/dto/BoostPurchaseRequest.java
src/main/java/com/attorlink/boost/dto/BoostPurchaseResponse.java
src/main/java/com/attorlink/boost/dto/BoostSandboxCheckoutHandoffResponse.java
src/main/java/com/attorlink/boost/entity/BoostActivity.java
src/main/java/com/attorlink/boost/entity/BoostAnalyticsEvent.java
src/main/java/com/attorlink/boost/entity/BoostInvoice.java
src/main/java/com/attorlink/boost/entity/BoostPayment.java
src/main/java/com/attorlink/boost/entity/BoostPlan.java
src/main/java/com/attorlink/boost/entity/ProfileBoost.java
src/main/java/com/attorlink/boost/enums/BoostAnalyticsEventType.java
src/main/java/com/attorlink/boost/repository/BoostActivityRepository.java
src/main/java/com/attorlink/boost/repository/BoostAnalyticsEventRepository.java
src/main/java/com/attorlink/boost/repository/BoostInvoiceRepository.java
src/main/java/com/attorlink/boost/repository/BoostPaymentRepository.java
src/main/java/com/attorlink/boost/repository/BoostPlanRepository.java
src/main/java/com/attorlink/boost/repository/ProfileBoostRepository.java
src/main/java/com/attorlink/boost/service/BoostAnalyticsService.java
src/main/java/com/attorlink/boost/service/BoostAnalyticsServiceImpl.java
src/main/java/com/attorlink/boost/service/BoostInvoicePdfStorage.java
src/main/java/com/attorlink/boost/service/BoostInvoicePdfStorageServiceImpl.java
src/main/java/com/attorlink/boost/service/BoostInvoiceService.java
src/main/java/com/attorlink/boost/service/BoostInvoiceServiceImpl.java
src/main/java/com/attorlink/boost/service/BoostLifecycleScheduler.java
src/main/java/com/attorlink/boost/service/BoostLifecycleService.java
src/main/java/com/attorlink/boost/service/BoostLifecycleServiceImpl.java
src/main/java/com/attorlink/boost/service/BoostMonitoringService.java
src/main/java/com/attorlink/boost/service/BoostMonitoringServiceImpl.java
src/main/java/com/attorlink/boost/service/BoostSandboxCheckoutService.java
src/main/java/com/attorlink/boost/service/BoostSandboxCheckoutServiceImpl.java
src/main/java/com/attorlink/boost/service/LawyerBoostService.java
src/main/java/com/attorlink/boost/service/LawyerBoostServiceImpl.java
```

#### chat

```text
src/main/java/com/attorlink/chat/controller/ChatConversationController.java
src/main/java/com/attorlink/chat/controller/ChatMessageController.java
src/main/java/com/attorlink/chat/controller/ChatWebSocketController.java
src/main/java/com/attorlink/chat/dto/ChatConversationResponse.java
src/main/java/com/attorlink/chat/dto/ChatMessageDeletionResponse.java
src/main/java/com/attorlink/chat/dto/ChatMessageResponse.java
src/main/java/com/attorlink/chat/dto/ChatSocketAckRequest.java
src/main/java/com/attorlink/chat/dto/ChatSocketSendRequest.java
src/main/java/com/attorlink/chat/dto/ConversationReadSummaryResponse.java
src/main/java/com/attorlink/chat/dto/CreateChatConversationRequest.java
src/main/java/com/attorlink/chat/dto/CreateChatMessageRequest.java
src/main/java/com/attorlink/chat/dto/IncrementalChatSyncRequest.java
src/main/java/com/attorlink/chat/dto/IncrementalChatSyncResponse.java
src/main/java/com/attorlink/chat/dto/MarkConversationReadRequest.java
src/main/java/com/attorlink/chat/entity/ChatConversation.java
src/main/java/com/attorlink/chat/entity/ChatMessage.java
src/main/java/com/attorlink/chat/entity/ChatMessageDelivery.java
src/main/java/com/attorlink/chat/repository/ChatConversationRepository.java
src/main/java/com/attorlink/chat/repository/ChatMessageDeliveryRepository.java
src/main/java/com/attorlink/chat/repository/ChatMessageRepository.java
src/main/java/com/attorlink/chat/service/ChatConversationService.java
src/main/java/com/attorlink/chat/service/ChatConversationServiceImpl.java
src/main/java/com/attorlink/chat/service/ChatMessageService.java
src/main/java/com/attorlink/chat/service/ChatMessageServiceImpl.java
src/main/java/com/attorlink/chat/service/ChatRealtimeService.java
```

#### client

```text
src/main/java/com/attorlink/client/dto/ClientLegalPreferencesRequest.java
src/main/java/com/attorlink/client/dto/ClientLegalPreferencesResponse.java
src/main/java/com/attorlink/client/entity/ClientLegalPreference.java
src/main/java/com/attorlink/client/repository/ClientLegalPreferenceRepository.java
src/main/java/com/attorlink/client/service/ClientLegalPreferenceService.java
```

#### common

```text
src/main/java/com/attorlink/common/enums/BoostActivityType.java
src/main/java/com/attorlink/common/enums/BoostInvoiceStatus.java
src/main/java/com/attorlink/common/enums/BoostPaymentStatus.java
src/main/java/com/attorlink/common/enums/BoostPlanStatus.java
src/main/java/com/attorlink/common/enums/BoostProvider.java
src/main/java/com/attorlink/common/enums/ChatConversationRequestStatus.java
src/main/java/com/attorlink/common/enums/ChatConversationType.java
src/main/java/com/attorlink/common/enums/ChatMessageDeliveryStatus.java
src/main/java/com/attorlink/common/enums/ChatMessageType.java
src/main/java/com/attorlink/common/enums/ContentReportDecision.java
src/main/java/com/attorlink/common/enums/ContentReportReason.java
src/main/java/com/attorlink/common/enums/ContentReportStatus.java
src/main/java/com/attorlink/common/enums/ContentReportTargetType.java
src/main/java/com/attorlink/common/enums/NotificationPreferenceCategory.java
src/main/java/com/attorlink/common/enums/NotificationType.java
src/main/java/com/attorlink/common/enums/ProfileBoostStatus.java
src/main/java/com/attorlink/common/enums/ScheduledVideoCallStatus.java
src/main/java/com/attorlink/common/enums/VideoCallStatus.java
src/main/java/com/attorlink/common/enums/WhoCanCommentOnMyPosts.java
src/main/java/com/attorlink/common/enums/WhoCanMessageMe.java
src/main/java/com/attorlink/common/exception/ConflictException.java
```

#### community

```text
src/main/java/com/attorlink/community/controller/CommentController.java
src/main/java/com/attorlink/community/controller/ContentReportController.java
src/main/java/com/attorlink/community/controller/FeedAnalyticsController.java
src/main/java/com/attorlink/community/controller/LawyerFollowController.java
src/main/java/com/attorlink/community/controller/PostController.java
src/main/java/com/attorlink/community/dto/CommentCreateRequest.java
src/main/java/com/attorlink/community/dto/CommentResponse.java
src/main/java/com/attorlink/community/dto/CommentUpdateRequest.java
src/main/java/com/attorlink/community/dto/CommentVoteRequest.java
src/main/java/com/attorlink/community/dto/ContentReportCreateRequest.java
src/main/java/com/attorlink/community/dto/ContentReportResponse.java
src/main/java/com/attorlink/community/dto/FeedAnalyticsEventRequest.java
src/main/java/com/attorlink/community/dto/FeedAnalyticsSummaryResponse.java
src/main/java/com/attorlink/community/dto/LawyerFollowResponse.java
src/main/java/com/attorlink/community/dto/PostCreateRequest.java
src/main/java/com/attorlink/community/dto/PostResponse.java
src/main/java/com/attorlink/community/dto/PostShareResponse.java
src/main/java/com/attorlink/community/dto/PostUpdateRequest.java
src/main/java/com/attorlink/community/entity/Comment.java
src/main/java/com/attorlink/community/entity/CommentVote.java
src/main/java/com/attorlink/community/entity/CommentVoteType.java
src/main/java/com/attorlink/community/entity/ContentReport.java
src/main/java/com/attorlink/community/entity/ContentReportAudit.java
src/main/java/com/attorlink/community/entity/FeedAnalyticsEvent.java
src/main/java/com/attorlink/community/entity/LawyerFollow.java
src/main/java/com/attorlink/community/entity/Post.java
src/main/java/com/attorlink/community/entity/PostBookmark.java
src/main/java/com/attorlink/community/entity/PostLike.java
src/main/java/com/attorlink/community/entity/PostMedia.java
src/main/java/com/attorlink/community/entity/PostShare.java
src/main/java/com/attorlink/community/entity/PostType.java
src/main/java/com/attorlink/community/enums/FeedEventType.java
src/main/java/com/attorlink/community/enums/FeedMode.java
src/main/java/com/attorlink/community/repository/CommentRepository.java
src/main/java/com/attorlink/community/repository/CommentVoteRepository.java
src/main/java/com/attorlink/community/repository/ContentReportAuditRepository.java
src/main/java/com/attorlink/community/repository/ContentReportRepository.java
src/main/java/com/attorlink/community/repository/FeedAnalyticsEventRepository.java
src/main/java/com/attorlink/community/repository/LawyerFollowRepository.java
src/main/java/com/attorlink/community/repository/PostBookmarkRepository.java
src/main/java/com/attorlink/community/repository/PostLikeRepository.java
src/main/java/com/attorlink/community/repository/PostMediaRepository.java
src/main/java/com/attorlink/community/repository/PostRepository.java
src/main/java/com/attorlink/community/repository/PostShareRepository.java
src/main/java/com/attorlink/community/service/CommentService.java
src/main/java/com/attorlink/community/service/CommentServiceImpl.java
src/main/java/com/attorlink/community/service/ContentReportService.java
src/main/java/com/attorlink/community/service/ContentReportServiceImpl.java
src/main/java/com/attorlink/community/service/FeedAnalyticsService.java
src/main/java/com/attorlink/community/service/FeedAnalyticsServiceImpl.java
src/main/java/com/attorlink/community/service/FeedCacheService.java
src/main/java/com/attorlink/community/service/FeedService.java
src/main/java/com/attorlink/community/service/FeedServiceImpl.java
src/main/java/com/attorlink/community/service/LawyerFollowService.java
src/main/java/com/attorlink/community/service/LawyerFollowServiceImpl.java
src/main/java/com/attorlink/community/service/PostService.java
src/main/java/com/attorlink/community/service/PostServiceImpl.java
```

#### config

```text
src/main/java/com/attorlink/config/MailConfig.java
src/main/java/com/attorlink/config/NotificationPreferenceSchemaCompatibility.java
src/main/java/com/attorlink/config/SocketEndpointPath.java
src/main/java/com/attorlink/config/WebSocketConfig.java
```

#### documentation / launch helpers / runtime artifacts

```text
.backend 2.pid
.backend.pid
docs/lawyer-profile-boost-implementation-blueprint.md
logs/attorlink-backend.log
logs/attorlink-jar.log
scripts/start-backend.sh
scripts/start-clean.sh
scripts/stop-backend.sh
```

#### lawyer

```text
src/main/java/com/attorlink/lawyer/controller/LawyerDiscoveryController.java
src/main/java/com/attorlink/lawyer/dto/LawyerDiscoverResponse.java
src/main/java/com/attorlink/lawyer/service/LawyerDiscoveryService.java
src/main/java/com/attorlink/lawyer/service/LawyerDiscoveryServiceImpl.java
```

#### notification

```text
src/main/java/com/attorlink/notification/controller/NotificationController.java
src/main/java/com/attorlink/notification/dto/NotificationListResponse.java
src/main/java/com/attorlink/notification/dto/NotificationReadAllResponse.java
src/main/java/com/attorlink/notification/dto/NotificationResponse.java
src/main/java/com/attorlink/notification/dto/NotificationUnreadCountResponse.java
src/main/java/com/attorlink/notification/entity/Notification.java
src/main/java/com/attorlink/notification/repository/NotificationRepository.java
src/main/java/com/attorlink/notification/service/NotificationDeliveryService.java
src/main/java/com/attorlink/notification/service/NotificationDeliveryServiceImpl.java
src/main/java/com/attorlink/notification/service/NotificationEmailService.java
src/main/java/com/attorlink/notification/service/NotificationEmailServiceImpl.java
src/main/java/com/attorlink/notification/service/NotificationService.java
src/main/java/com/attorlink/notification/service/NotificationServiceImpl.java
```

#### storage

```text
src/main/java/com/attorlink/storage/FileReferenceGuard.java
```

#### support

```text
src/main/java/com/attorlink/support/controller/SupportTicketController.java
src/main/java/com/attorlink/support/dto/AdminSupportTicketDetailResponse.java
src/main/java/com/attorlink/support/dto/AdminSupportTicketListResponse.java
src/main/java/com/attorlink/support/dto/AdminSupportTicketStatusUpdateRequest.java
src/main/java/com/attorlink/support/dto/SupportTicketCreateRequest.java
src/main/java/com/attorlink/support/dto/SupportTicketResponse.java
src/main/java/com/attorlink/support/entity/SupportTicket.java
src/main/java/com/attorlink/support/enums/SupportTicketCategory.java
src/main/java/com/attorlink/support/enums/SupportTicketStatus.java
src/main/java/com/attorlink/support/repository/SupportTicketRepository.java
src/main/java/com/attorlink/support/service/SupportTicketService.java
src/main/java/com/attorlink/support/service/SupportTicketServiceImpl.java
```

#### tests

```text
src/test/java/com/attorlink/admin/controller/AdminBoostPlanControllerSecurityTest.java
src/test/java/com/attorlink/admin/controller/AdminContentReportControllerSecurityTest.java
src/test/java/com/attorlink/admin/controller/AdminSupportTicketControllerSecurityTest.java
src/test/java/com/attorlink/admin/controller/VerificationControllerSecurityTest.java
src/test/java/com/attorlink/admin/service/AdminContentReportServiceImplTest.java
src/test/java/com/attorlink/admin/service/AdminSupportTicketServiceImplTest.java
src/test/java/com/attorlink/admin/service/AdminUserServiceImplTest.java
src/test/java/com/attorlink/admin/service/BoostPlanAdminServiceImplTest.java
src/test/java/com/attorlink/admin/service/VerificationServiceImplTest.java
src/test/java/com/attorlink/auth/controller/AuthSettingsSecurityTest.java
src/test/java/com/attorlink/auth/controller/SessionControllerSecurityTest.java
src/test/java/com/attorlink/auth/service/AuthSecurityRegressionTest.java
src/test/java/com/attorlink/auth/service/AuthServiceImplTest.java
src/test/java/com/attorlink/auth/service/OtpConsumptionSecurityTest.java
src/test/java/com/attorlink/auth/service/SecurityTransactionRegressionTest.java
src/test/java/com/attorlink/auth/service/SessionServiceImplTest.java
src/test/java/com/attorlink/boost/controller/LawyerBoostControllerSecurityTest.java
src/test/java/com/attorlink/boost/controller/LawyerBoostInvoiceControllerSecurityTest.java
src/test/java/com/attorlink/boost/repository/BoostRepositoryTest.java
src/test/java/com/attorlink/boost/service/BoostAnalyticsServiceImplTest.java
src/test/java/com/attorlink/boost/service/BoostInvoiceServiceImplTest.java
src/test/java/com/attorlink/boost/service/BoostLifecycleServiceImplTest.java
src/test/java/com/attorlink/boost/service/BoostMonitoringServiceImplTest.java
src/test/java/com/attorlink/boost/service/BoostSandboxCheckoutServiceImplTest.java
src/test/java/com/attorlink/boost/service/LawyerBoostServiceImplTest.java
src/test/java/com/attorlink/chat/controller/ChatWebSocketIntegrationTest.java
src/test/java/com/attorlink/chat/controller/ChatWebSocketSecurityTest.java
src/test/java/com/attorlink/chat/entity/ChatConversationEntityTest.java
src/test/java/com/attorlink/chat/service/ChatConversationServiceTest.java
src/test/java/com/attorlink/chat/service/ChatMessageServiceTest.java
src/test/java/com/attorlink/chat/service/MessagingCommunityRegressionTest.java
src/test/java/com/attorlink/client/controller/ClientLegalPreferenceControllerSecurityTest.java
src/test/java/com/attorlink/client/service/ClientLegalPreferenceServiceTest.java
src/test/java/com/attorlink/community/controller/FeedAnalyticsControllerSecurityTest.java
src/test/java/com/attorlink/community/controller/PostControllerSecurityTest.java
src/test/java/com/attorlink/community/service/CommentServiceImplTest.java
src/test/java/com/attorlink/community/service/ContentReportServiceImplTest.java
src/test/java/com/attorlink/community/service/FeedAnalyticsServiceImplTest.java
src/test/java/com/attorlink/community/service/FeedServiceImplTest.java
src/test/java/com/attorlink/community/service/LawyerFollowServiceImplTest.java
src/test/java/com/attorlink/community/service/PostServiceImplTest.java
src/test/java/com/attorlink/config/SocketEndpointSecurityTest.java
src/test/java/com/attorlink/lawyer/controller/LawyerAvailabilityControllerSecurityTest.java
src/test/java/com/attorlink/lawyer/controller/LawyerCredentialControllerSecurityTest.java
src/test/java/com/attorlink/lawyer/controller/LawyerProfileControllerSecurityTest.java
src/test/java/com/attorlink/lawyer/controller/LawyerServiceControllerSecurityTest.java
src/test/java/com/attorlink/lawyer/service/LawyerAvailabilityServiceTest.java
src/test/java/com/attorlink/lawyer/service/LawyerCredentialServiceOwnershipTest.java
src/test/java/com/attorlink/lawyer/service/LawyerDiscoveryServiceImplTest.java
src/test/java/com/attorlink/lawyer/service/LawyerEducationServiceOwnershipTest.java
src/test/java/com/attorlink/lawyer/service/LawyerProfileServiceTest.java
src/test/java/com/attorlink/notification/controller/NotificationControllerTest.java
src/test/java/com/attorlink/notification/repository/NotificationRepositoryTest.java
src/test/java/com/attorlink/notification/service/NotificationDeliveryServiceImplTest.java
src/test/java/com/attorlink/notification/service/NotificationEmailServiceImplTest.java
src/test/java/com/attorlink/notification/service/NotificationServiceImplTest.java
src/test/java/com/attorlink/notification/service/SmtpEmailIntegrationTest.java
src/test/java/com/attorlink/security/SessionJwtSecurityTest.java
src/test/java/com/attorlink/storage/FileOwnershipTest.java
src/test/java/com/attorlink/storage/StorageIntegrationTest.java
src/test/java/com/attorlink/storage/StorageLifecycleTest.java
src/test/java/com/attorlink/support/controller/SupportTicketControllerSecurityTest.java
src/test/java/com/attorlink/support/service/SupportTicketServiceImplTest.java
src/test/java/com/attorlink/user/controller/UserControllerSecurityTest.java
src/test/java/com/attorlink/video/service/LiveKitConfigurationTest.java
src/test/java/com/attorlink/video/service/LiveKitVideoMediaServiceTest.java
src/test/java/com/attorlink/video/service/ScheduledVideoCallServiceTest.java
src/test/java/com/attorlink/video/service/VideoCallServiceTest.java
src/test/resources/application-test-duplicate-disabled.properties
src/test/resources/application-test.properties
```

#### user

```text
src/main/java/com/attorlink/user/dto/NotificationPreferenceRequest.java
src/main/java/com/attorlink/user/dto/NotificationPreferenceResponse.java
src/main/java/com/attorlink/user/dto/WhoCanCommentOnMyPostsRequest.java
src/main/java/com/attorlink/user/dto/WhoCanCommentOnMyPostsResponse.java
src/main/java/com/attorlink/user/dto/WhoCanMessageMeRequest.java
src/main/java/com/attorlink/user/dto/WhoCanMessageMeResponse.java
src/main/java/com/attorlink/user/entity/UserCommentPrivacySetting.java
src/main/java/com/attorlink/user/entity/UserMessagePrivacySetting.java
src/main/java/com/attorlink/user/entity/UserNotificationPreference.java
src/main/java/com/attorlink/user/repository/UserCommentPrivacySettingRepository.java
src/main/java/com/attorlink/user/repository/UserMessagePrivacySettingRepository.java
src/main/java/com/attorlink/user/repository/UserNotificationPreferenceRepository.java
src/main/java/com/attorlink/user/service/UserCommentPrivacySettingService.java
src/main/java/com/attorlink/user/service/UserCommentPrivacySettingServiceImpl.java
src/main/java/com/attorlink/user/service/UserMessagePrivacySettingService.java
src/main/java/com/attorlink/user/service/UserMessagePrivacySettingServiceImpl.java
src/main/java/com/attorlink/user/service/UserNotificationPreferenceService.java
src/main/java/com/attorlink/user/service/UserNotificationPreferenceServiceImpl.java
```

#### video

```text
src/main/java/com/attorlink/video/controller/ScheduledVideoCallController.java
src/main/java/com/attorlink/video/controller/VideoCallController.java
src/main/java/com/attorlink/video/dto/RescheduleScheduledVideoCallRequest.java
src/main/java/com/attorlink/video/dto/ScheduledVideoCallRequest.java
src/main/java/com/attorlink/video/dto/ScheduledVideoCallResponse.java
src/main/java/com/attorlink/video/dto/VideoCallInitiateRequest.java
src/main/java/com/attorlink/video/dto/VideoCallJoinResponse.java
src/main/java/com/attorlink/video/dto/VideoCallResponse.java
src/main/java/com/attorlink/video/dto/VideoCallSignalRequest.java
src/main/java/com/attorlink/video/entity/ScheduledVideoCall.java
src/main/java/com/attorlink/video/entity/VideoCall.java
src/main/java/com/attorlink/video/repository/ScheduledVideoCallRepository.java
src/main/java/com/attorlink/video/repository/VideoCallRepository.java
src/main/java/com/attorlink/video/service/LiveKitVideoMediaService.java
src/main/java/com/attorlink/video/service/ScheduledVideoCallService.java
src/main/java/com/attorlink/video/service/ScheduledVideoCallServiceImpl.java
src/main/java/com/attorlink/video/service/VideoCallService.java
src/main/java/com/attorlink/video/service/VideoCallServiceImpl.java
src/main/java/com/attorlink/video/service/VideoMediaService.java
```


## 8. Test execution and verification evidence

### 8.1 Current request: exact scope and results

Tests/build ran on a fresh copy of **511 main Java source files and 71 original test source files**, plus **one handover-only test class with three checks**, under `build/backend-handover/snapshot`. No original test file was edited. Maven ran offline using existing cached artifacts. Fixtures disable optional real mail/providers; repository contexts use in-memory H2, not existing MySQL/Redis. The real socket integration test binds its embedded HTTP server to `127.0.0.1` on a random port.

| Check | Result | Evidence |
| --- | --- | --- |
| Actual copied YAML structure, Spring sender binding, empty-secret semantics | **3 passed** | `CurrentYamlMailBindingTest` in the copy; `focused-tests-final.log`. |
| Focused SMTP/auth/OTP/2FA/notification-email checks | **31 passed**, including those 3 checks | Seven classes, zero failures/errors/skips; `focused-tests-final.log`. The other 28 checks are existing backend tests. |
| Full available regression suite, executed once | **358 tests across 72 classes: 356 passed, 1 failure, 1 error, 0 skipped** | `regression.log`, preserved `regression-summary.json`. Do not report this as a clean default-configuration full-suite pass. |
| Focused failure diagnosis/recheck | **3 passed** | `LiveKitConfigurationTest` (2) and real `ChatWebSocketIntegrationTest` (1), `affected.log`, using corrected test environment and explicit unescaped loopback origins. This includes one test already passing in the broad run; do not add it to the distinct total. |
| Compile/package | **Passed**, executable Spring Boot JAR produced offline | `package.log`; `snapshot/target/attorlink-backend-0.0.1-SNAPSHOT.jar`. `-DskipTests` packaging does not turn the earlier default-config regression into a pass. |
| Original backend integrity | **595 original files fingerprinted: zero changes; Git status unchanged** | `integrity-summary.json`, `original_fingerprints.json`, `git_status_before.txt`. No backend commit created. |
| Gmail login/send/inbox receipt | **Not executed / unverified** | No historical password retrieved, no authorized recipient/provider action. Earlier unauthenticated TCP/STARTTLS success is not delivery. |
| Real MySQL/Redis/services/devices/providers | **Not executed in this request** | No Docker/backend deployment or Android launch. H2/local test server evidence is distinct. |

Build artifact: **96,827,273 bytes**, SHA-256 `1739e5c908f7182c1f16011a84b7dc749563fd0efdde0023d2554b9123e97cf1`. This is a handover validation artifact, not a deployed or installed backend. Its source copy has the current YAML and the harness described above.

### 8.2 Failures, cause and bounded rechecks

1. **Initial default Maven-cache attempt:** offline Maven could not create a named lock under the read-only user cache. No source test ran. The existing project-local Maven cache was selected instead.
2. **Project-cache provider gap:** offline Surefire could not resolve its provider from that partial cache. Reused 25 already-cached files (276,122 bytes) from the user cache; no network resolution/install.
3. **First runnable focused attempt:** Mockito inline self-attach was blocked, producing 26 initialization errors; a newly written harness assertion also expected a required placeholder where the actual file deliberately has an empty default. Fixed only the copied harness expectation and used the existing cached Byte Buddy Java agent explicitly. Final focused result: 31 passed. These are validation-environment/harness issues, not application changes hidden from the report.
4. **Broad LiveKit assertion failure:** the runner exported `VIDEO_LIVEKIT_ENABLED=false`; relaxed binding overrode the context's intended fixture setting. Removed that runner-only environment collision. Default source keeps providers disabled; the test uses mocked provision/signature/configuration fixtures. Recheck passed without editing LiveKit implementation.
5. **Broad socket upgrade error:** actual current YAML default origins contain literal backslashes before `://`; valid `http://localhost:3000` was rejected with 403. Rechecking the same test with explicit normal loopback origin values passed actual CONNECT/SEND/private delivery against embedded H2. **The source/default remains defective and is not marked fixed.** Correcting this single YAML default is a recommended follow-up; never broaden all origins merely to force a green result.

No complete second regression was run. Current source correctness is conditional on fixing/overriding the confirmed origin default. The copied harness gives a reproducible regression check for the SMTP correction, but it is not committed into the original backend; the engineer may selectively adopt it.

### 8.3 Reproducible commands

Run from the Flutter reference root. The prepared runner supplies ephemeral nonproduction fixture secrets in memory, strips inherited mail/provider credentials, disables real optional email, pins the local agent, and logs only into this copied validation area. Do not substitute production environment values or use this as a deployment launcher.

```sh
# Focused run already performed (the final run also supplied in-memory fixture env):
mvn -o -B \
  -Dmaven.repo.local=/home/frost/coding/codex/attorlink-flutter/build/integration/maven-repository \
  -f build/backend-handover/snapshot/pom.xml \
  -DargLine=-javaagent:/home/frost/coding/codex/attorlink-flutter/build/integration/maven-repository/net/bytebuddy/byte-buddy-agent/1.17.8/byte-buddy-agent-1.17.8.jar \
  -Dtest=CurrentYamlMailBindingTest,SmtpEmailIntegrationTest,AuthSecurityRegressionTest,AuthServiceImplTest,OtpConsumptionSecurityTest,TwoFactorServiceImplTest,NotificationEmailServiceImplTest \
  test

# Broad suite was executed once; it exposed the source-origin defect above:
python3 build/backend-handover/run_validation.py regression

# Only affected tests, with explicit unescaped local origin override:
python3 build/backend-handover/run_validation.py affected

# Offline executable packaging, without repeating tests:
python3 build/backend-handover/run_validation.py package
```

The runner expands to offline `mvn` on the copied POM, cached agent, `-Dserver.address=127.0.0.1`, warning-level root logging and the selected `test`/`-DskipTests package` goal. The affected invocation adds `-DWEBSOCKET_ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080` and `-Dtest=LiveKitConfigurationTest,ChatWebSocketIntegrationTest`. Loopback server permission was granted through the normal tool approval mechanism; no sandbox bypass or system configuration was used.

### 8.4 Historical evidence — not current retesting

| Prior evidence | Actual scope and limits |
| --- | --- |
| 11B / 11C-1 | Three original media signature/provisioning checks, then 48 focused security checks including nine H2 transaction/concurrency cases. Individual overlapping batches, not additive coverage. |
| 11C-2 | 72 focused backend checks including H2 paging/transaction/concurrency and socket configuration fixtures; 30 Flutter fixtures. Real deployed MySQL/STOMP was not exercised in that batch. |
| 11E-1 | 26 mocked mail/auth checks. No genuine SMTP connection in that batch. |
| 11E-2 | 53 mocked storage/ownership/lifecycle/affected checks and 71 Flutter checks. No real Cloudinary. |
| 11E-3 | 20 backend media/config/authorization checks and 12 Flutter media checks, plus bounded room-prefix rechecks. No actual media server/device. |
| 11F-1 | `build/integration/phase11f1/RESULTS.md`: **42 actual isolated checks passed** against disposable MySQL/Redis/Mailpit, covering signup/resend/single-use OTP, login/me, rotation/reuse and committed revocation/concurrency, session ownership/revocation/logout, both password-reset paths and email2FA replay. Includes actual Flutter AuthRepository transport. No production/Gmail/TOTP/inactive/deletion/device/provider acceptance. |
| 11F-2 | `build/integration/phase11f2/RESULTS.md`: **51 API/host-transport checks**, **21 final physical Android checks**; profiles/preferences/verification/representative qualifications/discovery/community/chat/notifications and actual host SockJS events. Phone validated recovery/SMTP/login/session restoration/logout/account switching. These are different evidence categories, not a combined API completeness count. |
| Final reference APK follow-through | 78 targeted Flutter checks, offline Android compilation, 10 fresh API checks and bounded native post CRUD/message/receipt/event/badge/offline recovery/session-invalidation observations. Native send included one manual user tap independently confirmed by recipient history. Cloudinary and two-party LiveKit remained unavailable; not exhaustive native CRUD/concurrency. |

Original logs under `build/phase11*` and integration JSON results corroborate these statements. Results predate the latest YAML correction and do not prove this exact configuration can deploy unchanged. Test data and OTPs were not imported into the original database or included here. Old roadmap statements such as “all integrations unverified” or “media adapter unavailable” are dated snapshots; later evidence supersedes only the specific checks actually executed.

## 9. Outstanding issues and production limitations

1. **Confirmed current YAML defect:** remove unintended literal backslashes from default WebSocket allowed-origin URLs, preserving the explicit allowlist. Current source is not unconditionally regression-clean until corrected or overridden. This request reports rather than silently editing original configuration.
2. **Gmail cutover incomplete:** real authentication/delivery/inbox receipt unverified, protected active credentials/recipient not established, Mailpit service/launcher/OTP helpers still present. The old launcher is not a Gmail launcher and may use an older snapshot. Do not retrieve the exposed historical app password or claim delivery from EHLO/STARTTLS.
3. **Credential/deployment readiness:** inject DB/JWT/admin secrets; empty defaults are not complete fail-fast validation. Rotate historical exposed values through approved owner controls. No production account/key rotation happened here. Admin session/token invalidation differs from user-session rows and needs explicit policy review.
4. **Provider media security incomplete:** no backend-enforced teardown/participant removal or issued-token revocation, incomplete scheduled end/duration lifecycle, no demonstrated standard webhook, no real two-party media/ICE/TURN or hostile-client acceptance.
5. **Document privacy/cleanup incomplete:** long-lived signed bearer links, pre-existing public documents/PDFs, legacy URL-only attachments and account purge cleanup, races/process-death/failed rollback reconciliation. No approved legacy migration was performed.
6. **Delivery/concurrency limits:** no durable outbox/idempotent sends/event log; latest-state sync and moving offset pages require reconciliation. No assertion of exactly-once send/notification/email or multi-node simple-broker correctness. GETDEL needs a compatible Redis; MySQL production locking/precision/load acceptance remains broader than focused historical tests.
7. **Schema/merge uncertainty:** 324 untracked paths and only two commits prevent confident reconstruction of the original final developer branch. Automatic JPA update and notification compatibility DDL need review against actual schema/data. Passing H2 is not a migration, MySQL transaction or full admin compatibility proof.
8. **External/deployment acceptance:** no current real Cloudinary, Gmail, LiveKit or payment verification; no current services/devices started. Existing physical Android evidence is bounded, not all workflows/two devices/background delivery. Browser origins/proxy/runtime configuration must match the actual deployment.
9. **Payments:** sandbox checkout only; bKash remains deferred. No real payment status/settlement claim or payment work was performed here.

## 10. Recommendations and engineer review checklist

1. Establish the engineer's actual original/final branch or recover its clean source snapshot. Compare it to `e900028` and the untracked-module inventory before selectively staging anything. Keep logs, PID files, `target`, ignored snapshots, credentials and test artifacts out of commits. Do not rewrite history or silently treat all untracked features as Codex additions.
2. Adopt the security fixes as a coherent unit: JWT `sid`, user/account/session lookups, refresh transaction rollback policy/lock order, password/deletion/2FA fingerprint gates and STOMP checks. Review compatibility/re-login/in-flight challenge behavior and admin JWT policy before mixed-node deployment. Retain the corresponding regression tests.
3. Correct the confirmed YAML origin escape with the narrow literal change only, then rerun the actual socket test with defaults and the relevant configuration/security suites. Keep the current mandatory Gmail STARTTLS settings. Consider explicit deployment secret validation separately; do not reintroduce exposed fallbacks.
4. Diff the real MySQL schema against the complete working feature model, including EmailLog uniqueness and notification preference compatibility initializer. Approve explicit migrations/backups/rollback before any real data deployment; do not use Hibernate update as proof of safe migration.
5. Review the complete controller/DTO/table inventory, especially changed cursor semantics, normalized request recipients, owner checks, 409 conflicts, signed-file URLs and multipart overloads. Run the existing admin API/browser smoke tests in its real origin without changing the admin-panel source.
6. For SMTP cutover, use a protected current credential source and explicitly authorized recipient; confirm authenticated send and separately inbox receipt. Retire only the isolated Mailpit service/ports/launcher/polling dependencies, preserving MySQL/Redis and historical evidence. Keep routine tests mocked. Do not remove shared images or containers without ownership checks.
7. Before confidential documents or hostile media clients are accepted, resolve/document the provider teardown, bearer URL/legacy-asset and cleanup limitations. Provision only approved dedicated test providers; verify actual signed/unsigned and cross-owner access, delete failures and two-device calls.
8. Retain current source-level tests, rerun bounded tests after fixes and do final authorized MySQL/Redis/SMTP/STOMP/Android acceptance. Preserve the distinction between compilation, local H2/mock tests, historical isolated integration and production readiness. No provider success or payment completion should be inferred from a fixture or opened URL.

**Handover conclusion:** The current backend has significant, evidence-backed corrective work and an offline-buildable implementation, but it is not a production-certified or provenance-clean patch series. SMTP binding is corrected; authenticated Gmail delivery is unverified; Mailpit remains; default socket-origin configuration has a reproduced defect. No original backend/admin/Flutter implementation file was modified to prepare this handover.
