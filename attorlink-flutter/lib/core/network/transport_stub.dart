import 'api_exception.dart';
import 'http_transport.dart';

HttpTransport createTransport() => _UnsupportedTransport();

class _UnsupportedTransport implements HttpTransport {
  @override
  Future<TransportResponse> send(TransportRequest request) async =>
      throw const ApiException(
        kind: ApiErrorKind.unsupported,
        message: 'Networking is unavailable on this platform.',
      );
  @override
  void close() {}
}
