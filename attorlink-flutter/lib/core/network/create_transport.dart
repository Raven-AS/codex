import 'http_transport.dart';
import 'transport_stub.dart'
    if (dart.library.io) 'transport_io.dart'
    if (dart.library.js_interop) 'transport_web.dart'
    as platform;

HttpTransport createTransport() => platform.createTransport();
