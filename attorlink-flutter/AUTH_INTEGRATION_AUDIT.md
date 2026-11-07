# Phase 10A — authentication integration audit

Read-only backend contract comparison; Flutter-side corrections only. No service/emulator launch, installation, APK build, schema change or backend/admin-panel modification was performed. Fixture results are not live integration proof.

## Endpoints examined

All paths are under `/api/v1`. Responses use `{success,message,data,timestamp}`; text endpoints duplicate their message in `data`, and void endpoints return null data.

| Endpoints | Actual request and response |
| --- | --- |
| POST `/auth/signup` | `email`, optional `phone`, `password`, `confirmPassword` → text; account not created until OTP verifies. |
| POST `/auth/signup/verify-otp`, `/auth/signup/resend-otp` | `email` + six-digit `otp`, or `email` → text; no login tokens. |
| POST `/auth/login`, `/auth/login/2fa` | `email,password,rememberMe`; then `challengeToken,code` when required → challenge or complete token pair + UserResponse. The challenge is consumed before code verification. |
| POST `/auth/token/refresh` | Opaque `refreshToken` → complete replacement pair/user. Server revokes the old token; reuse can revoke all sessions. |
| POST `/auth/logout`; GET `/auth/me` | Bearer-protected logout with `refreshToken` → null data; current-user GET → UserResponse. |
| POST `/users/profile/role`; GET `/users/me` | Bearer + `role: CLIENT/LAWYER` → UserResponse; role can only be selected from UNASSIGNED. Both current-user endpoints expose the same DTO. |
| POST `/auth/password/forgot`, `/forgot/verify-otp`, `/forgot/confirm` | `email` → enumeration-safe text; `email,otp` → `resetToken`; `email,resetToken,password,confirmPassword` → SecurityHistoryResponse. Reset token is consumed, and successful change revokes refresh sessions. |
| POST `/auth/password/reset/init`, `/reset/confirm` | Bearer + `currentPassword,newPassword,confirmPassword` → text; then `otp` → SecurityHistoryResponse and refresh-session revocation. |
| POST `/auth/2fa/email/enable`, `/email/enable/verify` | Bearer + `password` → text; then `otp` → null data. Only verification enables email 2FA. |
| POST `/auth/2fa/authenticator/setup`, `/authenticator/enable`, `/auth/2fa/disable` | Bearer → `secret,otpauthUri`; `otp` → null data; disable requires `password` → null data. |
| GET/DELETE `/auth/sessions`; DELETE `/auth/sessions/{id}` | Bearer → own active refresh-session list or null-data revocation response. No current-device marker. |
| POST `/auth/account/delete/request`, `/delete/confirm`; GET `/security-history` | Under `/auth/account`: password → text, OTP → scheduled-deletion text and refresh revocation; history → SecurityHistoryResponse. No immediate-deletion or separate restore endpoint. |

Inspected DTO validation, AuthServiceImpl, PasswordServiceImpl, OTP/2FA/refresh/session/account services, UserService role selection, SecurityConfig, JWT authentication and common exception/envelope handling. Passwords retain backend 8–64-character letter/number validation; phone is optional with the existing numeric/plus/hyphen pattern; OTP purposes and rate limits remain server-authoritative. Public auth/recovery requests do not attach bearer tokens; protected requests do. No new endpoint or body field was needed.

## Confirmed Flutter defects corrected

1. **Wrong-password HTTP 401 invalidated a valid login and replayed security mutations.** The backend uses 401 for both bearer failures and incorrect current passwords. Password-confirmed reset/email-2FA/disable/deletion-request operations now disable automatic 401 mutation retry. A safe GET `/auth/me` checks/renews a genuinely expired bearer; the user explicitly retries the action. Incorrect passwords preserve valid sessions. Unexpected account identity fails closed.
2. **Old async work crossed authentication generations.** Startup restore, `/auth/me` and refresh coalescing now belong to their generation. A delayed old account request cannot block new login validation; disposing an old refresh cannot erase a newer persisted pair. Repeated startup restoration is coalesced and does not reread a deliberately cleared vault during an active in-memory refresh.
3. **New login/2FA retained earlier credentials.** A fresh login invalidates prior in-memory/persisted credentials and old issued-token membership before sending the new login. A pending 2FA challenge has no previous-session fallback. Secure-storage failures stop login rather than continuing without protection.
4. **Identity/role responses were trusted without session binding.** Refresh and `/auth/me` must keep the established user ID; role confirmation must match the signed-in user and requested CLIENT/LAWYER role. Unexpected responses cannot authorize another account. The existing role-status refresh action remains available after an uncertain one-time selection.

Android encryption/backup/network-policy source was reviewed; its native implementation was not changed or device-validated in this phase. Existing serialized persistence, old-pair removal before rotation, unavailable-storage UI, JWT-expiry hinting and backend-authoritative role/status guards are preserved.

## Validation and remaining work

- **60 focused tests passed**: existing auth, configuration/API, Android-store/controller and account-security tests plus five new regression groups. The password/identity case was extended and rerun alone after the final identity-clear correction.
- Scoped static analysis is clean after style corrections. Changed Dart files were formatted. No full regression suite, emulator launch, new APK build or live auth mutation was run.
- Evidence: `build/phase10a/tests.log`, `analysis.log`, `analysis-recheck.log`, `password-identity-recheck.log`.
- Real SMTP signup/OTP/recovery, correct/incorrect 2FA against Redis, rotation/reuse detection, logout/revocation, role selection, TLS/connectivity and Android cold-start/Keystore behavior still need live backend/device testing. This phase did not recheck backend availability.
- The previously missing NDK `source.properties` now exists, observed read-only. NDK/toolchain completeness and APK compilation were not retested; no repair or installation was performed here. Real release signing is still required for distribution.

**Exact next step:** at the next approved Android runtime checkpoint, build the separate-namespace Keystore probe offline with the existing SDK, then install/run/restart it on an already connected test device (do not launch a new emulator automatically):

```sh
cd /home/frost/coding/codex/attorlink-flutter/android
./gradlew --offline --no-daemon -Pandroid.builder.sdkDownload=false \
  -Ptarget-platform=android-x64 -Ptarget=tool/android_auth_probe.dart :app:assembleDebug
```

This command targets the previously used x86_64 emulator; a physical device needs its actual ABI. Stop for approval if required components are missing. After the native persistence probe passes, restore/build `lib/main.dart` and perform real SMTP-backed signup → OTP → login → role → forced refresh → process restart → logout against a confirmed disposable Spring Boot test environment. Do not use production credentials/databases or treat the probe as backend authentication.
