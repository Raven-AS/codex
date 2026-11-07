import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'http_transport.dart';

/// Shared encoder for endpoints accepting a single binary `file` part.
BinaryRequestBody multipartFileBody({
  required String name,
  required String mimeType,
  required Uint8List bytes,
  String? testBoundary,
}) {
  final random = Random.secure();
  final boundary =
      testBoundary ??
      'attorlink-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  if (!RegExp(r'^[a-zA-Z0-9-]{1,70}$').hasMatch(boundary) ||
      !RegExp(r'^[a-z]+/[a-z0-9.+-]+$').hasMatch(mimeType)) {
    throw ArgumentError('Invalid multipart headers');
  }
  final safeName = name
      .split(RegExp(r'[/\\]'))
      .last
      .replaceAll(RegExp('[^a-zA-Z0-9._-]'), '_');
  final filename = safeName.isEmpty
      ? 'photo'
      : safeName.substring(0, min(100, safeName.length));
  final body = BytesBuilder(copy: false)
    ..add(
      utf8.encode(
        '--$boundary\r\nContent-Disposition: form-data; name="file"; filename="$filename"\r\nContent-Type: $mimeType\r\n\r\n',
      ),
    )
    ..add(bytes)
    ..add(utf8.encode('\r\n--$boundary--\r\n'));
  return BinaryRequestBody(
    bytes: body.takeBytes(),
    contentType: 'multipart/form-data; boundary=$boundary',
  );
}
