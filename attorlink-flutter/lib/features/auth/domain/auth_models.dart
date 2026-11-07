import 'dart:convert';

enum UserRole { unassigned, client, lawyer, admin }

enum UserStatus { active, suspended, scheduledDeletion }

Map<String, dynamic> jsonObject(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected object');
  }
  return value;
}

String requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) throw FormatException('Invalid $key');
  return value;
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.role,
    required this.status,
    this.emailVerified = false,
  });

  factory AuthUser.fromJson(Object? value) {
    final json = jsonObject(value);
    final id = json['id'];
    if (id is! int || id <= 0) throw const FormatException('Invalid user id');
    return AuthUser(
      id: id,
      email: requiredString(json, 'email'),
      role: switch (json['role']) {
        'UNASSIGNED' => UserRole.unassigned,
        'CLIENT' => UserRole.client,
        'LAWYER' => UserRole.lawyer,
        'ADMIN' => UserRole.admin,
        _ => throw const FormatException('Unknown role'),
      },
      status: switch (json['status']) {
        'ACTIVE' => UserStatus.active,
        'SUSPENDED' => UserStatus.suspended,
        'SCHEDULED_DELETION' => UserStatus.scheduledDeletion,
        _ => throw const FormatException('Unknown user status'),
      },
      emailVerified: json['emailVerified'] == true,
    );
  }

  final int id;
  final String email;
  final UserRole role;
  final UserStatus status;
  final bool emailVerified;
}

class SessionTokens {
  const SessionTokens({required this.accessToken, required this.refreshToken});
  final String accessToken;
  final String refreshToken;

  // This unverified claim is a scheduling hint only. Authorization always comes
  // from the backend's /auth/me response, never from decoded JWT role claims.
  bool expiresSoon(DateTime now) {
    try {
      final parts = accessToken.split('.');
      if (parts.length != 3) return true;
      final json = jsonObject(
        jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        ),
      );
      final exp = json['exp'];
      if (exp is! int) return true;
      return exp <=
          now.toUtc().add(const Duration(seconds: 30)).millisecondsSinceEpoch ~/
              1000;
    } on FormatException {
      return true;
    }
  }

  @override
  String toString() => 'SessionTokens(redacted)';
}

class AuthResult {
  const AuthResult._({this.challengeToken, this.tokens, this.user});
  factory AuthResult.fromJson(Object? value) {
    final json = jsonObject(value);
    if (json['twoFactorRequired'] == true) {
      return AuthResult._(
        challengeToken: requiredString(json, 'challengeToken'),
      );
    }
    if (json['twoFactorRequired'] != false) {
      throw const FormatException('Invalid auth result');
    }
    return AuthResult._(
      tokens: SessionTokens(
        accessToken: requiredString(json, 'accessToken'),
        refreshToken: requiredString(json, 'refreshToken'),
      ),
      user: AuthUser.fromJson(json['user']),
    );
  }
  final String? challengeToken;
  final SessionTokens? tokens;
  final AuthUser? user;
}

enum SessionStatus {
  restoring,
  signedOut,
  challenge,
  roleRequired,
  authenticated,
  restricted,
  unavailable,
}

class AuthState {
  const AuthState(this.status, {this.user, this.message});
  final SessionStatus status;
  final AuthUser? user;
  final String? message;
}
