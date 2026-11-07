import 'dart:io';
import 'dart:typed_data';

import '../../../core/network/api_exception.dart';
import '../domain/lawyer_document.dart';

Future<LawyerDocument?> selectDocument({String? path}) async {
  if (path == null || path.trim().isEmpty) return null;
  try {
    final file = File(path.trim());
    if (await file.length() > LawyerDocument.maxBytes) {
      throw const ApiException(
        kind: ApiErrorKind.validation,
        message: 'Choose a document of at most 10 MB.',
      );
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      bytes.add(chunk);
      if (bytes.length > LawyerDocument.maxBytes) {
        throw const ApiException(
          kind: ApiErrorKind.validation,
          message: 'Choose a document of at most 10 MB.',
        );
      }
    }
    return LawyerDocument.fromBytes(
      file.uri.pathSegments.last,
      bytes.takeBytes(),
    );
  } on FileSystemException {
    throw const ApiException(
      kind: ApiErrorKind.validation,
      message: 'This document could not be read. Choose a readable local file.',
    );
  }
}
