import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'api_exception.dart';
import 'http_transport.dart';

HttpTransport createTransport() => _IoTransport();

class _IoTransport implements HttpTransport {
  final HttpClient _client = HttpClient();
  bool _closed = false;

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    if (_closed) throw StateError('Transport is closed');
    HttpClientRequest? outgoing;
    var expired = false;
    Future<TransportResponse> perform() async {
      outgoing = await _client.openUrl(request.method, request.uri);
      if (expired) {
        outgoing!.abort();
        throw TimeoutException('Request timed out');
      }
      // Never forward bearer tokens through HTTP redirects.
      outgoing!.followRedirects = false;
      request.headers.forEach(
        (key, value) => outgoing!.headers.set(key, value),
      );
      if (request.bodyBytes != null) {
        outgoing!.add(request.bodyBytes!);
      } else if (request.body != null) {
        outgoing!.add(utf8.encode(request.body!));
      }
      final response = await outgoing!.close();
      if (request.receiveBytes &&
          response.statusCode >= 200 &&
          response.statusCode < 300) {
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          bytes.add(chunk);
        }
        return TransportResponse(
          statusCode: response.statusCode,
          body: '',
          bodyBytes: bytes.takeBytes(),
        );
      }
      final body = await response.transform(utf8.decoder).join();
      return TransportResponse(statusCode: response.statusCode, body: body);
    }

    try {
      return await perform().timeout(
        request.timeout,
        onTimeout: () {
          expired = true;
          outgoing?.abort();
          throw TimeoutException('Request timed out');
        },
      );
    } on TimeoutException {
      throw const ApiException(
        kind: ApiErrorKind.timeout,
        message: 'The request timed out. Please try again.',
      );
    } on IOException {
      throw const ApiException(
        kind: ApiErrorKind.network,
        message: 'Unable to connect. Please check your connection.',
      );
    } on FormatException {
      throw const ApiException(
        kind: ApiErrorKind.invalidResponse,
        message: 'The service returned unreadable information.',
      );
    }
  }

  @override
  void close() {
    _closed = true;
    _client.close(force: true);
  }
}
