import '../../auth/domain/auth_models.dart';

const privacyValues = ['EVERYONE', 'FOLLOWERS_ONLY'];
const notificationKeys = ['social', 'messaging', 'lawyerActivity', 'system'];
const securityActivities = [
  'ACCOUNT_CREATED',
  'PASSWORD_CHANGED_FORGOT',
  'PASSWORD_CHANGED_RESET',
  'ACCOUNT_RESTORED',
  'TWO_FACTOR_ENABLED',
  'TWO_FACTOR_DISABLED',
  'ACCOUNT_DELETE_SCHEDULED',
  'PROFILE_SUBMITTED',
];

Map<String, dynamic> privacyResponse(Object? value, String key) {
  final json = jsonObject(value);
  if (!privacyValues.contains(json[key])) throw FormatException('Invalid $key');
  return {key: json[key]};
}

Map<String, bool> notificationPreferences(Object? value) {
  final json = jsonObject(value);
  for (final key in notificationKeys) {
    if (json[key] is! bool) throw FormatException('Invalid $key');
  }
  return {for (final key in notificationKeys) key: json[key] as bool};
}

class SecurityState {
  SecurityState.fromJson(Object? value) {
    final json = jsonObject(value);
    if (json['id'] is! int || (json['id'] as int) <= 0) {
      throw const FormatException('Invalid user');
    }
    id = json['id'] as int;
    email = requiredString(json, 'email');
    if (json['twoFactorEnabled'] != null && json['twoFactorEnabled'] is! bool) {
      throw const FormatException('Invalid 2FA flag');
    }
    if (json['twoFactorMethod'] != null &&
        !['EMAIL_OTP', 'AUTHENTICATOR'].contains(json['twoFactorMethod'])) {
      throw const FormatException('Invalid 2FA method');
    }
    enabled = json['twoFactorEnabled'] as bool?;
    method = json['twoFactorMethod'] as String?;
  }
  late final int id;
  late final String email;
  late final bool? enabled;
  late final String? method;
}

class TotpSetup {
  TotpSetup.fromJson(Object? value) {
    final json = jsonObject(value);
    secret = requiredString(json, 'secret');
    uri = requiredString(json, 'otpauthUri');
    final parsed = Uri.tryParse(uri);
    if (parsed == null ||
        parsed.scheme != 'otpauth' ||
        parsed.host != 'totp' ||
        parsed.queryParameters['secret'] != secret) {
      throw const FormatException('Invalid enrollment URI');
    }
  }
  late final String secret, uri;
  @override
  String toString() => 'TotpSetup(redacted)';
}

class SecuritySession {
  SecuritySession.fromJson(Object? value) {
    final json = jsonObject(value);
    if (json['sessionId'] is! int ||
        (json['sessionId'] as int) <= 0 ||
        json['rememberMe'] is! bool) {
      throw const FormatException('Invalid session');
    }
    id = json['sessionId'] as int;
    rememberMe = json['rememberMe'] as bool;
    createdAt = requiredString(json, 'createdAt');
    expiresAt = requiredString(json, 'expiresAt');
  }
  late final int id;
  late final bool rememberMe;
  late final String createdAt, expiresAt;
}

class SecurityHistory {
  SecurityHistory.fromJson(Object? value) {
    final json = jsonObject(value);
    email = requiredString(json, 'email');
    if (json['accountCreatedAt'] != null &&
        json['accountCreatedAt'] is! String) {
      throw const FormatException('Invalid creation time');
    }
    accountCreatedAt = json['accountCreatedAt'] as String?;
    if (json['events'] is! List) throw const FormatException('Invalid history');
    events = (json['events'] as List)
        .map((value) {
          final event = jsonObject(value);
          if (!securityActivities.contains(event['type']) ||
              (event['description'] != null &&
                  event['description'] is! String)) {
            throw const FormatException('Invalid security event');
          }
          requiredString(event, 'time');
          return Map<String, dynamic>.unmodifiable({
            'type': event['type'],
            'description': event['description'],
            'time': event['time'],
          });
        })
        .toList(growable: false);
  }
  late final String email;
  late final String? accountCreatedAt;
  late final List<Map<String, dynamic>> events;
}
