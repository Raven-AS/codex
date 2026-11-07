import 'dart:async';
import 'dart:js_interop';

import 'socket_link.dart';

@JS('WebSocket')
extension type _WebSocket._(JSObject _) implements JSObject {
  external factory _WebSocket(String url);
  external set onopen(JSFunction? value);
  external set onmessage(JSFunction? value);
  external set onerror(JSFunction? value);
  external set onclose(JSFunction? value);
  external void send(String data);
  external void close();
}

extension type _MessageEvent._(JSObject _) implements JSObject {
  external JSAny? get data;
}

Future<SocketLink> connectSocket(Uri uri) async {
  final socket = _WebSocket(uri.toString());
  final result = _BrowserLink(socket);
  try {
    await result.open.future.timeout(const Duration(seconds: 20));
    return result;
  } catch (_) {
    await result.close();
    rethrow;
  }
}

class _BrowserLink implements SocketLink {
  _BrowserLink(this.socket) {
    socket.onopen = ((JSAny? _) {
      if (!open.isCompleted) {
        open.complete();
      }
    }).toJS;
    socket.onmessage = ((_MessageEvent event) {
      if (_closed) return;
      final value = event.data.dartify();
      if (value is String) {
        _messages.add(value);
      } else {
        _messages.addError(
          const FormatException('Expected text WebSocket frame'),
        );
      }
    }).toJS;
    socket.onerror = ((JSAny? _) {
      if (!open.isCompleted) {
        open.completeError(StateError('WebSocket connection failed'));
      } else if (!_closed) {
        _messages.addError(StateError('WebSocket connection failed'));
      }
    }).toJS;
    socket.onclose = ((JSAny? _) {
      if (!open.isCompleted) {
        open.completeError(StateError('WebSocket closed before opening'));
      }
      if (!_closed) {
        _closed = true;
        unawaited(_messages.close());
      }
    }).toJS;
  }
  final _WebSocket socket;
  final open = Completer<void>();
  final _messages = StreamController<String>();
  bool _closed = false;
  @override
  Stream<String> get messages => _messages.stream;
  @override
  void send(String data) {
    if (_closed) {
      throw StateError('WebSocket closed');
    }
    socket.send(data);
  }

  @override
  Future<void> close() async {
    if (!_closed) {
      _closed = true;
      socket.close();
      unawaited(_messages.close());
    }
    socket.onopen = null;
    socket.onmessage = null;
    socket.onerror = null;
    socket.onclose = null;
  }
}
