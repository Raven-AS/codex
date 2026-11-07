import 'socket_stub.dart'
    if (dart.library.io) 'socket_io.dart'
    if (dart.library.js_interop) 'socket_web.dart'
    as platform;

abstract interface class SocketLink {
  Stream<String> get messages;
  void send(String data);
  Future<void> close();
}

typedef SocketConnector = Future<SocketLink> Function(Uri uri);
Future<SocketLink> connectSocket(Uri uri) => platform.connectSocket(uri);
