import 'dart:typed_data';

class TransportRequest {
  const TransportRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.timeout,
    this.body,
    this.bodyBytes,
    this.receiveBytes = false,
  });
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final Duration timeout;
  final String? body;
  final Uint8List? bodyBytes;
  final bool receiveBytes;
}

class TransportResponse {
  const TransportResponse({
    required this.statusCode,
    required this.body,
    this.bodyBytes,
  });
  final int statusCode;
  final String body;
  final Uint8List? bodyBytes;
}

abstract interface class HttpTransport {
  Future<TransportResponse> send(TransportRequest request);
  void close();
}

/// Already encoded body, retained unchanged across an authenticated 401 retry.
class BinaryRequestBody {
  BinaryRequestBody({required Uint8List bytes, required this.contentType})
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final Uint8List bytes;
  final String contentType;
}
