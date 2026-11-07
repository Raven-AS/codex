import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/network/api_exception.dart';
import '../domain/auth_models.dart';
import 'session_store.dart';

SessionStore sessionStoreFor(Uri apiRoot) =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? AndroidSessionStore(apiRoot.toString())
    : runtimeSessionStore;

/// Native bridge encrypts the complete pair with Android Keystore AES-GCM and
/// commits it atomically in noBackupFilesDir. No plaintext storage fallback.
class AndroidSessionStore implements PersistentSessionStore {
  AndroidSessionStore(this.origin, {MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('attorlink/secure-session');
  final String origin;
  final MethodChannel _channel;
  Future<T?> _call<T>(String method, {String? value}) async {
    try {
      return await _channel.invokeMethod<T>(method, {
        'origin': origin,
        'value': ?value,
      });
    } on PlatformException catch (error) {
      throw ApiException(
        kind: error.code == 'INVALID_SESSION'
            ? ApiErrorKind.unauthorized
            : ApiErrorKind.unsupported,
        message: error.code == 'INVALID_SESSION'
            ? 'The saved Android session is no longer readable. Please sign in again.'
            : 'Android secure session storage is unavailable. Unlock the device and try again.',
      );
    } on MissingPluginException {
      throw const ApiException(
        kind: ApiErrorKind.unsupported,
        message: 'Android secure session storage is unavailable in this build.',
      );
    }
  }

  @override
  Future<SessionTokens?> read() async {
    final value = await _call<String>('read');
    if (value == null) return null;
    try {
      final json = jsonObject(jsonDecode(value));
      if (json['version'] != 1) {
        throw const FormatException('Unknown session version');
      }
      return SessionTokens(
        accessToken: requiredString(json, 'accessToken'),
        refreshToken: requiredString(json, 'refreshToken'),
      );
    } on FormatException {
      await clear();
      throw const ApiException(
        kind: ApiErrorKind.unauthorized,
        message: 'The saved Android session is invalid. Please sign in again.',
      );
    }
  }

  @override
  Future<void> write(SessionTokens tokens) async {
    await _call<void>(
      'write',
      value: jsonEncode({
        'version': 1,
        'accessToken': tokens.accessToken,
        'refreshToken': tokens.refreshToken,
      }),
    );
  }

  @override
  Future<void> clear() async {
    await _call<void>('clear');
  }
}
