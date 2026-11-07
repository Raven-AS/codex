import '../../../core/network/api_client.dart';
import '../domain/auth_models.dart';

class AuthRepository {
  AuthRepository(this.api);
  final ApiClient api;

  Future<AuthResult> login(
    String email,
    String password, {
    bool rememberMe = false,
  }) async => (await api.request(
    'POST',
    'auth/login',
    body: {
      'email': email.trim(),
      'password': password,
      'rememberMe': rememberMe,
    },
    decode: AuthResult.fromJson,
  )).data;

  Future<String> signup(
    String email,
    String password,
    String confirmPassword, {
    String? phone,
  }) => _message('auth/signup', {
    'email': email.trim(),
    'password': password,
    'confirmPassword': confirmPassword,
    if (phone != null && phone.isNotEmpty) 'phone': phone,
  });

  Future<String> verifySignup(String email, String otp) =>
      _message('auth/signup/verify-otp', {'email': email.trim(), 'otp': otp});
  Future<String> resendSignup(String email) =>
      _message('auth/signup/resend-otp', {'email': email.trim()});

  Future<AuthResult> verifyTwoFactor(String challenge, String code) async =>
      (await api.request(
        'POST',
        'auth/login/2fa',
        body: {'challengeToken': challenge, 'code': code},
        decode: AuthResult.fromJson,
      )).data;

  Future<String> forgotPassword(String email) =>
      _message('auth/password/forgot', {'email': email.trim()});
  Future<String> verifyRecovery(String email, String otp) async =>
      (await api.request(
        'POST',
        'auth/password/forgot/verify-otp',
        body: {'email': email.trim(), 'otp': otp},
        decode: (value) => requiredString(jsonObject(value), 'resetToken'),
      )).data;

  Future<String> completeRecovery(
    String email,
    String resetToken,
    String password,
    String confirmPassword,
  ) async => (await api.request(
    'POST',
    'auth/password/forgot/confirm',
    body: {
      'email': email.trim(),
      'resetToken': resetToken,
      'password': password,
      'confirmPassword': confirmPassword,
    },
    decode: (value) {
      // The endpoint returns SecurityHistoryResponse; do not treat it as login.
      final json = jsonObject(value);
      requiredString(json, 'email');
      if (json['events'] is! List) {
        throw const FormatException('Invalid security history');
      }
      return null;
    },
  )).message;

  Future<AuthResult> refresh(String refreshToken) async => (await api.request(
    'POST',
    'auth/token/refresh',
    body: {'refreshToken': refreshToken},
    decode: AuthResult.fromJson,
  )).data;

  Future<AuthUser> me() async => (await api.request(
    'GET',
    'auth/me',
    authenticated: true,
    decode: AuthUser.fromJson,
  )).data;

  Future<AuthUser> selectRole(UserRole role) async {
    if (role != UserRole.client && role != UserRole.lawyer) {
      throw ArgumentError.value(
        role,
        'role',
        'Only CLIENT or LAWYER can be selected',
      );
    }
    return (await api.request(
      'POST',
      'users/profile/role',
      authenticated: true,
      body: {'role': role.name.toUpperCase()},
      decode: AuthUser.fromJson,
    )).data;
  }

  Future<void> logout(String refreshToken) async {
    await api.request<void>(
      'POST',
      'auth/logout',
      authenticated: true,
      manageSession: false,
      body: {'refreshToken': refreshToken},
      decode: (_) {},
    );
  }

  Future<String> _message(String path, Map<String, Object?> body) async =>
      (await api.request(
        'POST',
        path,
        body: body,
        decode: (value) {
          if (value is! String) throw const FormatException('Expected message');
          return value;
        },
      )).data;
}
