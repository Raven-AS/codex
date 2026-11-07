# Android networking and authentication

Phase 10F update: the normal main Android debug APK now **builds successfully** with cached SDK/NDK/Gradle components and offline resolution. Keystore/picker/checkout/export classes are packaged; no native device behavior or real authentication has been tested. Earlier NDK/APK blockers below are historical. See [ANDROID_READINESS.md](ANDROID_READINESS.md) for current artifact, evidence, configuration and required runtime checks.

Latest static/fixture corrections and endpoint comparison: [Phase 10A audit](AUTH_INTEGRATION_AUDIT.md), with 60 focused tests passed. Native device behavior remains unverified.

Android is now configured separately for local development and production. These changes use existing Flutter/Android SDK APIs; no package dependency was added.

## API configuration

Debug Android defaults to `http://10.0.2.2:18081/api/v1/` (Android emulator host alias). Desktop debug retains localhost:8081. Set `ATTORLINK_API_URL` explicitly when the backend listens elsewhere:

```sh
flutter run -d emulator-5554 --no-pub \
  --dart-define=ATTORLINK_ENV=development \
  --dart-define=ATTORLINK_API_URL=http://10.0.2.2:18081/api/v1/
```

Physical Android devices can use an explicit reachable private IPv4 LAN address, e.g. `http://192.168.1.20:18081/api/v1/`, with backend binding/network access prepared by its owner. Loopback on a phone means the phone, not the computer. A USB-connected device can instead use `adb reverse tcp:18081 tcp:18081` and `http://127.0.0.1:18081/api/v1/`; port forwarding needs to be reapplied after reconnection. This task has not changed host firewall rules or backend binding.

Release/profile builds require an explicit HTTPS API root, even if `ATTORLINK_ENV=development` is supplied. Production mode in debug also requires HTTPS. HTTP is limited by Dart configuration to localhost/loopback and RFC1918 IPv4 development addresses. Main/profile/release Android network-security resources reject cleartext; only the debug resource enables it. TLS certificates remain normally validated, with no insecure-certificate callback or user-CA trust override. The application already declares INTERNET permission.

```sh
flutter build apk --release --no-pub \
  --dart-define=ATTORLINK_ENV=production \
  --dart-define=ATTORLINK_API_URL=https://your-api.example/api/v1/
```

Configure a real release signing key before distribution; the existing template signing setup has not been promoted to production readiness. Invalid/missing production API configuration displays a configuration error rather than silently using a development server.

## Protected session persistence

`AndroidSessionStore` communicates over `attorlink/secure-session` with `SecureSessionBridge.kt`. The complete access/refresh pair is AES-256-GCM encrypted using a non-exportable Android Keystore key, and atomically stored in `noBackupFilesDir`. Keys/files are scoped by a SHA-256 digest of the full normalized API root; the root is also authenticated encryption AAD. Different environments cannot accidentally reuse a saved pair. See the platform [Keystore](https://developer.android.com/privacy-and-security/keystore) and [AtomicFile](https://developer.android.com/reference/android/util/AtomicFile) contracts. Android backups are disabled. Hardware-backed protection depends on the device; StrongBox/biometric protection is not claimed.

JWT/refresh tokens are encrypted at rest; passwords, OTPs and TOTP secrets are not persisted by the session store. Secrets are not written to logs or error text. Keystore failures do not fall back to plaintext or memory-only authentication on Android. Unreadable sessions require sign-in; transient storage failure keeps protected navigation closed and offers retry. Other platforms retain their existing memory-only store.

Storage operations are serialized with generation checks, preventing a late secure write from restoring credentials after logout/account changes. Before sending a rotating refresh token, the saved old pair is removed. Only a confirmed complete replacement is persisted; process death or an ambiguous response requires sign-in instead of reusing a possibly consumed token. Startup still calls `/auth/me` and trusts backend role/status, not JWT role claims. Logout revokes the latest server refresh token when possible and removes local ciphertext/key; failed local secure removal is surfaced rather than reported as success.

Signup/OTP, login/2FA, forgotten-password recovery, logout, and role selection retain the actual backend request/response contracts. Signup and password recovery do not create a session. Backend-consumed 2FA challenges/recovery tokens are not blindly retried. Flutter connects only to Spring Boot, never directly to MySQL/Redis/SMTP.

## Current verification

- 50 targeted configuration, API-client, authentication contract/widget, and new Android-storage/controller tests passed. These use fixture responses/platform-channel mocks and are not live backend integration.
- Offline APK build attempted using cached Gradle 9.3.1 with SDK auto-download disabled. It is blocked by incomplete `/home/frost/Android/Sdk/ndk/28.2.13676358` (missing `source.properties`); no other NDK is installed. The previous build failure is historical: Phase 10A observed that source.properties now exists. Toolchain completeness/APK compilation was not rechecked, and no installation was performed by this task.
- An existing API36 emulator (`emulator-5554`) is connected. The new Android Keystore bridge is not yet APK-compiled or exercised on that emulator while the NDK blocker remains.
- The test backend at `127.0.0.1:18081` returned connection refusal, including a check outside the filesystem sandbox. Real signup, SMTP-backed OTP/recovery, login, JWT rotation/revocation and role selection are unverified. The backend was not started or modified.
- `tool/android_auth_probe.dart` is a clearly labelled platform-only fixture harness, ready to test encrypted read/write, process-restart persistence and secure clearing on Android. It uses a separate `.invalid` storage namespace, never a synthetic login or production backend response. It has not yet run on a device.

Evidence: `build/android-auth-check/`. Do not start unrelated feature work or treat this as live authentication sign-off.
