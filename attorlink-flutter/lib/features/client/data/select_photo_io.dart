import 'dart:io';
import 'dart:typed_data';

import '../../../core/network/api_exception.dart';
import '../domain/client_photo.dart';

Future<ClientPhoto?> selectPhoto({String? path}) async {
  if (path == null || path.trim().isEmpty) return null;
  try {
    final file = File(path.trim());
    if (await file.length() > ClientPhoto.maxBytes) {
      throw const ApiException(
        kind: ApiErrorKind.validation,
        message: 'Choose a photo of at most 5 MB.',
      );
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      bytes.add(chunk);
      if (bytes.length > ClientPhoto.maxBytes) {
        throw const ApiException(
          kind: ApiErrorKind.validation,
          message: 'Choose a photo of at most 5 MB.',
        );
      }
    }
    return ClientPhoto.fromBytes(file.uri.pathSegments.last, bytes.takeBytes());
  } on FileSystemException {
    throw const ApiException(
      kind: ApiErrorKind.validation,
      message: 'This photo could not be read. Choose a readable local file.',
    );
  }
}
