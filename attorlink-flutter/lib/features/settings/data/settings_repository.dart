import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/domain/auth_models.dart';
import '../../auth/domain/session_controller.dart';
import '../domain/security_models.dart';

class SettingsRepository {
  SettingsRepository(
    this.api, {
    required this.ownerId,
    required this.currentUser,
    this.accessChanges,
    this.sessionGeneration,
    required this.invalidateSession,
    required this.recheckSession,
  }) : _initialGeneration = sessionGeneration?.call();
  factory SettingsRepository.forSession(SessionController session) =>
      SettingsRepository(
        session.api,
        ownerId: session.state.user!.id,
        currentUser: () => session.state.status == SessionStatus.authenticated
            ? session.state.user
            : null,
        accessChanges: session.changes,
        sessionGeneration: () => session.generation,
        invalidateSession: session.invalidateLocally,
        recheckSession: session.recheckRefreshSession,
      );
  final ApiClient api;
  final int ownerId;
  final AuthUser? Function() currentUser;
  final Stream<Object?>? accessChanges;
  final int Function()? sessionGeneration;
  final int? _initialGeneration;
  final Future<void> Function(String) invalidateSession;
  final Future<void> Function() recheckSession;
  void checkAccess() {
    final user = currentUser();
    if ((_initialGeneration != null &&
            sessionGeneration!() != _initialGeneration) ||
        user == null ||
        user.id != ownerId ||
        user.status != UserStatus.active ||
        ![UserRole.client, UserRole.lawyer].contains(user.role)) {
      throw const ApiException(
        kind: ApiErrorKind.forbidden,
        message: 'Sign in with the same active client or lawyer account to manage settings.',
      );
    }
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    checkAccess();
    final result = await action();
    checkAccess();
    return result;
  }

  Future<Map<String, dynamic>> privacy(bool message, {String? value}) =>
      _guard(() async {
        final key = message ? 'whoCanMessageMe' : 'whoCanCommentOnMyPosts';
        if (value != null && !privacyValues.contains(value)) {
          throw const ApiException(
            kind: ApiErrorKind.validation,
            message: 'Choose a supported privacy value.',
          );
        }
        return (await api.request(
          value == null ? 'GET' : 'PUT',
          'users/me/${message ? 'message' : 'comment'}-privacy',
          authenticated: true,
          accessGuard: checkAccess,
          body: value == null ? null : {key: value},
          decode: (v) => privacyResponse(v, key),
        )).data;
      });
  Future<Map<String, bool>> notifications({Map<String, bool>? values}) =>
      _guard(() async {
        if (values != null &&
            (values.length != notificationKeys.length ||
                notificationKeys.any((k) => !values.containsKey(k)))) {
          throw const FormatException(
            'All four notification preferences are required',
          );
        }
        return (await api.request(
          values == null ? 'GET' : 'PUT',
          'users/me/notification-preferences',
          authenticated: true,
          accessGuard: checkAccess,
          body: values,
          decode: notificationPreferences,
        )).data;
      });
  Future<SecurityState> security() => _guard(
    () async => (await api.request(
      'GET',
      'users/me',
      authenticated: true,
      accessGuard: checkAccess,
      decode: (v) {
        final result = SecurityState.fromJson(v);
        if (result.id != ownerId) {
          throw const FormatException('Wrong security owner');
        }
        return result;
      },
    )).data,
  );
  Future<SecurityHistory> history() => _guard(
    () async => (await api.request(
      'GET',
      'auth/account/security-history',
      authenticated: true,
      accessGuard: checkAccess,
      decode: SecurityHistory.fromJson,
    )).data,
  );
  Future<List<SecuritySession>> sessions() => _guard(
    () async => (await api.request(
      'GET',
      'auth/sessions',
      authenticated: true,
      accessGuard: checkAccess,
      decode: (v) {
        if (v is! List) throw const FormatException('Invalid sessions');
        return v.map(SecuritySession.fromJson).toList();
      },
    )).data,
  );
  Future<String> _post(
    String path, {
    Map<String, Object?>? body,
    bool text = false,
    bool passwordConfirmation = false,
  }) => _guard(() async {
    try {
      return (await api.request(
        'POST',
        path,
        authenticated: true,
        accessGuard: checkAccess,
        recoverUnauthorized: !passwordConfirmation,
        body: body,
        decode: (value) {
          if (text) {
            if (value is! String) {
              throw const FormatException('Expected text result');
            }
            return value;
          }
          if (value != null) {
            throw const FormatException('Expected void result');
          }
          return null;
        },
      )).message;
    } on ApiException catch (error) {
      if (!passwordConfirmation || error.kind != ApiErrorKind.unauthorized) {
        rethrow;
      }
      // The backend also uses 401 for a wrong current password. Validate the
      // bearer with a safe GET; never replay a password-confirmed mutation.
      final user = (await api.request(
        'GET',
        'auth/me',
        authenticated: true,
        accessGuard: checkAccess,
        decode: AuthUser.fromJson,
      )).data;
      checkAccess();
      if (user.id != ownerId) {
        await invalidateSession(
          'Account identity could not be verified. Please sign in again.',
        );
        throw const ApiException(
          kind: ApiErrorKind.invalidResponse,
          message: 'Unexpected account identity. Sign in again.',
        );
      }
      rethrow;
    }
  });
  void _password(String value) {
    if (value.trim().isEmpty) {
      throw const ApiException(
        kind: ApiErrorKind.validation,
        message: 'Password is required.',
      );
    }
  }

  void _otp(String value) {
    if (!RegExp(r'^\d{6}$').hasMatch(value)) {
      throw const ApiException(
        kind: ApiErrorKind.validation,
        message: 'Enter a six-digit code.',
      );
    }
  }

  Future<String> resetInit(String current, String next, String confirm) {
    _password(current);
    if (!RegExp(r'^(?=.*[A-Za-z])(?=.*\d).{8,64}$').hasMatch(next) ||
        confirm != next) {
      throw const ApiException(
        kind: ApiErrorKind.validation,
        message: 'Use matching new passwords of 8–64 characters with a letter and a number.',
      );
    }
    return _post(
      'auth/password/reset/init',
      body: {
        'currentPassword': current,
        'newPassword': next,
        'confirmPassword': confirm,
      },
      text: true,
      passwordConfirmation: true,
    );
  }

  Future<SecurityHistory> resetConfirm(String otp) async {
    _otp(otp);
    final result = await _guard(
      () async => (await api.request(
        'POST',
        'auth/password/reset/confirm',
        authenticated: true,
        accessGuard: checkAccess,
        body: {'otp': otp},
        decode: SecurityHistory.fromJson,
      )).data,
    );
    checkAccess();
    await invalidateSession(
      'Password reset confirmed by the backend. All refresh sessions were revoked. Please sign in again.',
    );
    return result;
  }

  Future<String> emailStart(String password) {
    _password(password);
    return _post(
      'auth/2fa/email/enable',
      body: {'password': password},
      text: true,
      passwordConfirmation: true,
    );
  }

  Future<String> emailVerify(String otp) {
    _otp(otp);
    return _post('auth/2fa/email/enable/verify', body: {'otp': otp});
  }

  Future<TotpSetup> totpSetup() => _guard(
    () async => (await api.request(
      'POST',
      'auth/2fa/authenticator/setup',
      authenticated: true,
      accessGuard: checkAccess,
      decode: TotpSetup.fromJson,
    )).data,
  );
  Future<String> totpEnable(String otp) {
    _otp(otp);
    return _post('auth/2fa/authenticator/enable', body: {'otp': otp});
  }

  Future<String> disable(String password) {
    _password(password);
    return _post(
      'auth/2fa/disable',
      body: {'password': password},
      passwordConfirmation: true,
    );
  }

  Future<String> deleteRequest(String password) {
    _password(password);
    return _post(
      'auth/account/delete/request',
      body: {'password': password},
      text: true,
      passwordConfirmation: true,
    );
  }

  Future<String> deleteConfirm(String otp) async {
    _otp(otp);
    final message = await _post(
      'auth/account/delete/confirm',
      body: {'otp': otp},
      text: true,
    );
    checkAccess();
    await invalidateSession(message);
    return message;
  }

  Future<String> revoke({int? id}) async {
    final message = await _guard(
      () async => (await api.request(
        'DELETE',
        id == null ? 'auth/sessions' : 'auth/sessions/$id',
        authenticated: true,
        accessGuard: checkAccess,
        decode: (v) {
          if (v != null) throw const FormatException('Expected void result');
          return null;
        },
      )).message,
    );
    checkAccess();
    if (id == null) {
      await invalidateSession(
        'All refresh sessions revoked. Please sign in again.',
      );
    } else {
      await recheckSession();
    }
    return message;
  }
}
