# Phase 10B — client and lawyer integration audit

2026-11-05. Backend controllers, request/response DTOs and relevant service/validation rules were inspected read-only. Results below are source, contract-fixture and widget-test evidence, **not live API or Android runtime verification**. Backend and admin-panel contents were not changed. Phase 10A authentication behavior is preserved; the session controller only gains a read-only generation getter.

## Contracts examined

All REST paths below have prefix `/api/v1`. Responses use the existing `success/message/data/timestamp` envelope, including nullable singleton data and ordinary collection arrays.

| Endpoint family | Actual supported operations and constraints |
| --- | --- |
| `POST /users/profile/role` | CLIENT or LAWYER only, once from UNASSIGNED; server creates the corresponding DRAFT profile. Role selection itself remains Phase 10A code. |
| `/client/profile`, `/client/address`, `/client/preferences` | GET/PUT. Personal/contact fields replace nullable values; gender changes only when non-null. Address GET may return null; coordinates are BigDecimal stored as DECIMAL(10,7). Preferences replace practice-area, jurisdiction and court IDs plus language strings; server accepts active references and normalizes/deduplicates languages, maximum 60 characters. |
| `/client/profile/photo` | POST multipart `file`; DELETE. Response `{profilePhoto}`; upload requires a URL, removal may return null. Profile update/photo upload marks client COMPLETE; optional onboarding steps are frontend guidance. |
| `/lawyer/profile` | GET/PUT; nullable request fields generally retain existing values, so blank DOB/gender/experience/phone cannot be treated as clearing them. Personal/professional limits, past DOB, phone/email and 0–70 experience validation match the DTO. POST/DELETE `/photo` and `/cover-photo` return `{url,publicId}`. |
| `/lawyer/bar-council` | GET nullable / PUT full replacement. Preserve saved document URLs when editing registration information. PUT resets record verification to PENDING. POST/DELETE `/identity-card`, `/sanad`, `/green-book` use the dedicated upload contract. |
| `POST /lawyer/profile/submit` | Requires saved first name, bar registration number and a saved Bar Council record. SUBMITTED, IN_REVIEW and VERIFIED profiles cannot resubmit. Documents are not required by this submission service. Actual profile/record status and rejection feedback remain server-authoritative. |
| `/lawyer/high-court`, `/lawyer/supreme-court` | Nullable GET / singleton PUT; no whole-record DELETE. High Court documents: `/permission-document`, `/sanad-document`. Supreme Court documents: `/scba-certificate`, `/scba-id-document`, `/appellate-division-document`, `/senior-advocate-document`; POST/DELETE for each. |
| `/lawyer/{bar-associations,credentials,educations,experiences,trainings,memberships,awards,publications}` | GET list / POST / PUT and DELETE `/{id}`. No separate detail GET or pagination. Exact DTO fields, credential enums, required names, lengths, education years 1950–2100 and start≤end, and experience date/current rules inspected. Credential/award/membership `/{id}/document`, education/training `/{id}/certificate` support POST/DELETE. Alternative multipart saves provide equivalent workflows. |
| `/lawyer/{specializations,jurisdictions,courts,languages,offices,services}` | GET list / POST / PUT and DELETE `/{id}`. No detail GET or pagination. Own-profile relationships are resolved by the backend; duplicate/reference and primary-record rules remain authoritative. Languages use text plus NATIVE/FLUENT/CONVERSATIONAL/BASIC; services use CHAT/PHONE/VIDEO/IN_PERSON, nonnegative duration/fee, currency and active. Office/address decimals and fee precision follow entity storage. |
| `/lawyer/availability` | GET / PUT `{slots:[{dayOfWeek,startTime,endTime,available}]}` replaces the week. MONDAY–SUNDAY and local times, including fractional seconds; start must precede end. Backend saves every submitted slot as available=true; unavailable days omit slots and empty slots clear the week. |
| `/practice-areas`, `/jurisdictions`, `/courts`; `/files/upload` | Public active reference lists; no invented language catalog. Generic authenticated multipart upload with type=DOCUMENT links Bar Association/publication files through their actual JSON update DTOs; no guessed dedicated document routes or public IDs. |

Client/lawyer role and ACTIVE account checks, own-profile resolution, verification resets, collection ownership, replacement/merge behavior, and upload responses were compared with the existing repositories, schemas and editors. No additional endpoint/method mismatch was confirmed in this scope.

## Flutter corrections

1. **Session changes during token work:** repository entry/exit checks could allow an old mutation to be sent with a new account's token after awaited refresh. Profile requests now check access before sending, after token work/recovery, and before decoding responses. Repositories also bind to their originating authentication generation, including logout/relogin to the same account. Qualification/practice requests and public catalog results share these guards. No token logging or mutation retry was added.
2. **Stale snapshots:** client/lawyer workspace fetches have revision checks; a late older fetch cannot replace a newer fetched or saved snapshot.
3. **Decimal address editing:** small JSON coordinates such as ±0.0000001 previously appeared as scientific notation, which the form rejected. A shared decimal formatter expands notation without fixed-precision rounding; existing office/fee handling uses the same helper.
4. **Detached Bar Council save:** registration fields are captured before the preservation GET, and closing the form prevents a later PUT. Existing document URLs remain preserved.
5. **Ambiguous photo/document results:** client/lawyer photo and council-document mutations now require an authoritative refresh before another operation after an uncertain result. This prevents blind replay after a lost response. Photo widgets adopt refreshed parent URLs; recovered drafts are cleared only on successful refresh. Existing qualification upload/link reconciliation remains intact.
6. **Validation visibility:** backend errors on properties without a corresponding input (for example education `yearRangeValid` or indexed slot errors) are included in the shared error notice. Education start/end year ordering is also checked before sending.

## Backend limitations and remaining gaps

- No profile/qualification/practice pagination or individual collection-detail endpoint exists. Details resolve from the authenticated user's current list; no paging or other-lawyer full-profile API was fabricated.
- Lawyer nullable-field merge behavior, verification/ownership decisions, and availability's forced available=true behavior cannot be changed from Flutter.
- Record saves and external storage are not an atomic transaction. Dedicated routes are used where provided; generic uploaded-but-unlinked qualification files retain reconciliation information. Standalone asset inventory/abandoned-file cleanup remains outside this feature, as already recorded in ENDPOINT_COVERAGE.md.
- No further confirmed Flutter defect is left unresolved in the inspected scope. This is not evidence of production readiness: concurrent edits from other devices have no frontend-enforceable backend version contract, and actual authorization/storage behavior still needs integration testing.

## Validation

- Changed Dart files formatted with the installed formatter. Initial sandbox/automatic review blocked generated SDK-cache writes; the user explicitly approved those writes only. No packages/tools were installed or downloaded; no SDK source, permissions or system configuration was changed.
- **127 distinct focused tests passed after targeted corrections:** 12 new regressions plus existing API, client, lawyer, qualification, practice and Phase 10A audit tests. The initial run passed 125 and had two new test-harness timeouts because confirmation dialogs retain animated busy indicators. Those two tests were corrected to wait for the dialog animation rather than global settling, then both passed alone. Successful tests were not repeated.
- Scoped analysis covered core networking/utilities, the session controller, client/lawyer features and the new test file. Eight brace-style findings were corrected; reanalysis of the three affected files found **no issues**. No remaining findings in the original scope.
- Evidence: `build/phase10b_tests.log`, `build/phase10b_recheck.log`, `build/phase10b_analysis.log`, `build/phase10b_analysis_recheck.log`. The first logs preserve the initial failures; the recheck logs record their resolution.
- No full regression suite, APK build, emulator/device launch, backend request, infrastructure startup or runtime integration test was performed.

## Required later verification and next phase

Use a confirmed disposable Spring Boot test environment with MySQL and Redis, authenticated CLIENT/LAWYER accounts and active reference data. SMTP is needed for genuine signup/OTP/recovery; Cloudinary configuration/network access is required for real photo/document transfers. Flutter accesses these through Spring Boot, never directly through database/cache credentials. Android network configuration and encrypted startup restoration still require the Phase 10A native checks documented in ANDROID_AUTH.md.

At the approved device/end-to-end checkpoint, verify onboarding → save/reopen profile/address/preferences → upload/retrieve/remove photos and documents → credential/practice CRUD → weekly replacement → verification submission/status. Include invalid references, forbidden ownership, expired/replaced sessions and interrupted responses. No live behavior is claimed here.

Recommended next **source-stabilization** phase: discovery/community contracts and mutation-state reconciliation, followed by messaging/realtime lifecycle review. Keep the planned Android secure-session and full-stack checkpoints separate; do not advance automatically.
