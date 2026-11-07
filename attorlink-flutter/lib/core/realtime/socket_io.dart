import 'dart:io';

import 'socket_link.dart';

Future<SocketLink> connectSocket(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    return _Socket(
      await WebSocket.connect(
        uri.toString(),
        customClient: client,
      ).timeout(const Duration(seconds: 20)),
      client,
    );
  } catch (_) {
    client.close(force: true);
    rethrow;
  }
}

class _Socket implements SocketLink {
  _Socket(this.socket, this.client);
  final WebSocket socket;
  final HttpClient client;
  @override
  Stream<String> get messages => socket.map((value) {
    if (value is! String) {
      throw const FormatException('Expected text WebSocket frame');
    }
    return value;
  });
  @override
  void send(String data) => socket.add(data);
  @override
  Future<void> close() async {
    try {
      await socket
          .close(WebSocketStatus.normalClosure)
          .timeout(const Duration(seconds: 3));
    } finally {
      client.close(force: true);
    }
  }
}
