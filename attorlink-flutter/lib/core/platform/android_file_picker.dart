import 'package:flutter/services.dart';

import '../network/api_exception.dart';

/// Validates the SDK document-provider bridge before feature code uses its data.
Future<({String name, Uint8List bytes})?> pickAndroidFile({
  bool document = false,
}) async {
  try {
    final result = await const MethodChannel(
      'attorlink/client-photo',
    ).invokeMethod<Object?>('pickPhoto', document ? {'document': true} : null);
    if (result == null) return null;
    if (result is! Map ||
        result['bytes'] is! Uint8List ||
        (result['name'] != null && result['name'] is! String)) {
      throw const ApiException(
        kind: ApiErrorKind.invalidResponse,
        message: 'The selected file could not be read.',
      );
    }
    final bytes = result['bytes'] as Uint8List;
    final maxMb = document ? 10 : 5;
    if (bytes.isEmpty || bytes.length > maxMb * 1024 * 1024) {
      throw ApiException(
        kind: ApiErrorKind.validation,
        message: 'Choose a nonempty file of at most $maxMb MB.',
      );
    }
    return (
      name: result['name'] as String? ?? (document ? 'document' : 'photo'),
      bytes: bytes,
    );
  } on MissingPluginException {
    throw const ApiException(
      kind: ApiErrorKind.unsupported,
      message: 'This build does not provide the Android document picker.',
    );
  } on PlatformException {
    throw const ApiException(
      kind: ApiErrorKind.unsupported,
      message: 'File selection failed. Choose a readable file and try again.',
    );
  }
}
