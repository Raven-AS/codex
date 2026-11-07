import 'dart:typed_data';

import '../../../core/network/api_exception.dart';
import '../../../core/network/http_transport.dart';
import '../../../core/network/multipart_file.dart';

class LawyerDocument {
  LawyerDocument._(this.name, this.bytes, this.mimeType);
  factory LawyerDocument.fromBytes(String name, Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const ApiException(
        kind: ApiErrorKind.validation,
        message: 'Choose a nonempty document of at most 10 MB.',
      );
    }
    bool starts(List<int> signature) =>
        bytes.length >= signature.length &&
        List.generate(
          signature.length,
          (i) => bytes[i] == signature[i],
        ).every((v) => v);
    final mime = starts([37, 80, 68, 70, 45])
        ? 'application/pdf'
        : starts([255, 216, 255])
        ? 'image/jpeg'
        : starts([137, 80, 78, 71, 13, 10, 26, 10])
        ? 'image/png'
        : null;
    if (mime == null) {
      throw const ApiException(
        kind: ApiErrorKind.validation,
        message: 'Choose a PDF, JPEG, or PNG document.',
      );
    }
    return LawyerDocument._(
      name,
      Uint8List.fromList(bytes).asUnmodifiableView(),
      mime,
    );
  }
  static const maxBytes = 10 * 1024 * 1024;
  final String name;
  final Uint8List bytes;
  final String mimeType;
  BinaryRequestBody multipart({String? testBoundary}) => multipartFileBody(
    name: name,
    mimeType: mimeType,
    bytes: bytes,
    testBoundary: testBoundary,
  );
}
