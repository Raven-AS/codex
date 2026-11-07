import 'dart:typed_data';

import '../../../core/network/api_exception.dart';
import '../../../core/network/http_transport.dart';
import '../../../core/network/multipart_file.dart';

class ClientPhoto {
  ClientPhoto._(this.name, this.bytes, this.mimeType);
  factory ClientPhoto.fromBytes(String name, Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const ApiException(
        kind: ApiErrorKind.validation,
        message: 'Choose a nonempty photo of at most 5 MB.',
      );
    }
    final mime = _mime(bytes);
    if (mime == null) {
      throw const ApiException(
        kind: ApiErrorKind.validation,
        message: 'Choose a JPEG, PNG, or WebP image.',
      );
    }
    return ClientPhoto._(
      name,
      Uint8List.fromList(bytes).asUnmodifiableView(),
      mime,
    );
  }
  static const maxBytes = 5 * 1024 * 1024;
  final String name;
  final Uint8List bytes;
  final String mimeType;

  static String? _mime(Uint8List bytes) {
    bool starts(List<int> signature, [int offset = 0]) =>
        bytes.length >= offset + signature.length &&
        List.generate(
          signature.length,
          (i) => bytes[offset + i] == signature[i],
        ).every((v) => v);
    if (starts([255, 216, 255])) return 'image/jpeg';
    if (starts([137, 80, 78, 71, 13, 10, 26, 10])) return 'image/png';
    if (starts([82, 73, 70, 70]) && starts([87, 69, 66, 80], 8)) {
      return 'image/webp';
    }
    return null;
  }

  BinaryRequestBody multipart({String? testBoundary}) => multipartFileBody(
    name: name.isEmpty ? 'photo' : name,
    mimeType: mimeType,
    bytes: bytes,
    testBoundary: testBoundary,
  );
}
