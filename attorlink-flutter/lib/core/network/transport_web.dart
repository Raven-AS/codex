import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'api_exception.dart';
import 'http_transport.dart';

@JS('fetch')
external JSPromise<_FetchResponse> _fetch(String url, _FetchOptions options);

@JS('AbortController')
extension type _AbortController._(JSObject _) implements JSObject {
  external factory _AbortController();
  external JSObject get signal;
  external void abort();
}

extension type _FetchOptions._(JSObject _) implements JSObject {
  external factory _FetchOptions({
    required String method,
    required JSObject headers,
    JSAny? body,
    required String redirect,
    required String credentials,
    required JSObject signal,
  });
}

extension type _FetchResponse._(JSObject _) implements JSObject {
  external int get status;
  external JSPromise<JSString> text();
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

HttpTransport createTransport() => _WebTransport();

/// Uses browser Fetch through SDK interop, with no third-party web package.
class _WebTransport implements HttpTransport {
  final Set<_AbortController> _active = {};
  bool _closed = false;

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    if (_closed) throw StateError('Transport is closed');
    final controller = _AbortController();
    _active.add(controller);
    Future<TransportResponse> perform() async {
      final response = await _fetch(
        request.uri.toString(),
        _FetchOptions(
          method: request.method,
          headers: request.headers.jsify() as JSObject,
          body: request.bodyBytes?.toJS ?? request.body?.toJS,
          redirect: 'error',
          credentials: 'omit',
          signal: controller.signal,
        ),
      ).toDart;
      if (request.receiveBytes &&
          response.status >= 200 &&
          response.status < 300) {
        final buffer = await response.arrayBuffer().toDart;
        return TransportResponse(
          statusCode: response.status,
          body: '',
          bodyBytes: Uint8List.view(buffer.toDart),
        );
      }
      final body = await response.text().toDart;
      return TransportResponse(statusCode: response.status, body: body.toDart);
    }

    try {
      return await perform().timeout(
        request.timeout,
        onTimeout: () {
          controller.abort();
          throw const ApiException(
            kind: ApiErrorKind.timeout,
            message: 'The request timed out. Please try again.',
          );
        },
      );
    } on ApiException {
      rethrow;
    } catch (_) {
      // Browsers do not distinguish CORS, offline, and Fetch rejection errors.
      throw const ApiException(
        kind: ApiErrorKind.network,
        message: 'Unable to connect. Please check your connection.',
      );
    } finally {
      _active.remove(controller);
    }
  }

  @override
  void close() {
    _closed = true;
    for (final controller in _active.toList()) {
      controller.abort();
    }
  }
}
