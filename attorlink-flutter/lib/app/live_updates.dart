import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../core/config/api_config.dart';
import '../core/network/create_transport.dart';
import '../core/network/http_transport.dart';
import '../core/realtime/socket_link.dart';
import '../core/realtime/stomp_codec.dart';
import '../features/messaging/domain/chat_models.dart';
import '../features/notifications/domain/notification_models.dart';

enum LiveKind { state, reconcile, notification, message, unread }

class LiveEvent {
  const LiveEvent(
    this.ownerId,
    this.kind, {
    this.message,
    this.notification,
    this.conversationId,
    this.sessionGeneration,
  });
  final int ownerId;
  final LiveKind kind;
  final ChatMessage? message;
  final NotificationItem? notification;
  final int? conversationId;
  final int? sessionGeneration;
}

/// SockJS WebSocket + STOMP 1.2 only. REST reconciliation covers absent events.
class LiveUpdates {
  LiveUpdates({
    required this.config,
    required this.accessToken,
    required this.currentUserId,
    required Stream<Object?> sessionChanges,
    required this.readUnread,
    this.sessionGeneration,
    bool initiallyPaused = false,
    SocketConnector? connector,
    HttpTransport? transport,
    Uri? endpoint,
    this.interval = const Duration(seconds: 30),
  }) : _paused = initiallyPaused,
       connector = connector ?? connectSocket,
       transport = transport ?? createTransport(),
       endpoint = endpoint ?? _endpoint(config) {
    _auth = sessionChanges.listen((_) => _sessionChanged(), onDone: dispose);
  }
  final ApiConfig config;
  final Future<String> Function() accessToken;
  final int? Function() currentUserId;
  final Future<int> Function() readUnread;
  final int Function()? sessionGeneration;
  final SocketConnector connector;
  final HttpTransport transport;
  final Uri endpoint;
  final Duration interval;
  final _events = StreamController<LiveEvent>.broadcast();
  final _decoder = StompDecoder();
  final _watches = <int, int>{};
  StreamSubscription<Object?>? _auth;
  StreamSubscription<String>? _input;
  SocketLink? _socket;
  Timer? _retry, _periodic, _deadline;
  int? _owner;
  int _generation = 0, _attempt = 0, _identity = 0;
  bool _active = false,
      _disposed = false,
      _connecting = false,
      _online = false,
      _countDirty = false,
      _transportUnavailable = false;
  bool _paused;
  int? _authGeneration;
  int _lifecycle = 0;
  Object? _credentialsFlight, _countFlight;
  String? _token;
  DateTime? _lastFrame;
  int? unreadCount;
  String status = 'Realtime inactive';
  Stream<LiveEvent> get events => _events.stream;
  bool get paused => _paused;

  static Uri _endpoint(ApiConfig config) {
    const path = String.fromEnvironment(
      'ATTORLINK_SOCKET_PATH',
      defaultValue: '/ws',
    );
    final uri = Uri.parse(path);
    if (!path.startsWith('/') ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.any((s) => s == '..' || s == '.' || s.contains('/'))) {
      throw ArgumentError('Invalid socket endpoint path');
    }
    return config.baseUrl.replace(
      path: uri.path.replaceFirst(RegExp(r'/$'), ''),
      query: null,
      fragment: null,
    );
  }

  void _emit(
    LiveKind kind, {
    ChatMessage? message,
    NotificationItem? notification,
    int? conversationId,
  }) {
    final owner = _owner;
    if (!_disposed &&
        owner != null &&
        currentUserId() == owner &&
        sessionGeneration?.call() == _authGeneration) {
      _events.add(
        LiveEvent(
          owner,
          kind,
          message: message,
          notification: notification,
          conversationId: conversationId,
          sessionGeneration: _authGeneration,
        ),
      );
    }
  }

  void activate() {
    if (_disposed) return;
    if (_active) {
      _sessionChanged();
      return;
    }
    _active = true;
    _sessionChanged();
    if (_active && !_paused) {
      _periodic ??= Timer.periodic(interval, (_) => _tick());
    }
  }

  void _sessionChanged() {
    final owner = currentUserId();
    final authGeneration = sessionGeneration?.call();
    if (owner != _owner || authGeneration != _authGeneration) {
      _identity++;
      _authGeneration = authGeneration;
      _credentialsFlight = _countFlight = null;
      _countDirty = false;
      _transportUnavailable = false;
      _disconnect();
      _watches.clear();
      unreadCount = null;
      _token = null;
      _owner = owner;
    }
    if (owner == null) {
      _active = false;
      _periodic?.cancel();
      _periodic = null;
      status = 'Signed out';
      return;
    }
    if (_active && !_paused) {
      unawaited(_credentials());
      unawaited(_count());
    }
  }

  bool _current(int identity, int lifecycle, int? owner) =>
      !_disposed &&
      _active &&
      !_paused &&
      identity == _identity &&
      lifecycle == _lifecycle &&
      owner == _owner &&
      owner == currentUserId() &&
      sessionGeneration?.call() == _authGeneration;

  Future<void> _credentials() async {
    if (_credentialsFlight != null ||
        _disposed ||
        !_active ||
        _paused ||
        _owner == null) {
      return;
    }
    final flight = Object();
    _credentialsFlight = flight;
    final owner = _owner, identity = _identity, lifecycle = _lifecycle;
    try {
      final token = await accessToken();
      if (!_current(identity, lifecycle, owner)) return;
      if (_token != null && _token != token) _disconnect();
      _token = token;
      if (_socket == null &&
          !_connecting &&
          _retry == null &&
          !_transportUnavailable) {
        unawaited(_connect());
      }
    } catch (_) {
      if (_current(identity, lifecycle, owner)) {
        _fail('Session unavailable; REST remains available.');
      }
    } finally {
      if (identical(_credentialsFlight, flight)) _credentialsFlight = null;
    }
  }

  Future<void> _count() async {
    if (_disposed || !_active || _paused || _owner == null) return;
    if (_countFlight != null) {
      _countDirty = true;
      return;
    }
    final flight = Object();
    _countFlight = flight;
    _countDirty = false;
    final owner = _owner, identity = _identity, lifecycle = _lifecycle;
    try {
      final count = await readUnread();
      if (_current(identity, lifecycle, owner) && !_countDirty && count >= 0) {
        unreadCount = count;
        _emit(LiveKind.unread);
      }
    } catch (_) {
      /* Keep the last authoritative count; never invent zero. */
    } finally {
      if (identical(_countFlight, flight)) {
        _countFlight = null;
        if (_countDirty && _current(identity, lifecycle, owner)) {
          unawaited(_count());
        }
      }
    }
  }

  void _tick() {
    if (_disposed || !_active || _paused || _owner == null) return;
    if (_online &&
        _lastFrame != null &&
        DateTime.now().difference(_lastFrame!) > const Duration(seconds: 75)) {
      _fail('Realtime connection timed out; retrying.');
    }
    unawaited(_credentials());
    unawaited(_count());
    _emit(LiveKind.reconcile);
  }

  Future<void> _connect() async {
    if (_disposed || !_active || _paused || _owner == null || _token == null) {
      return;
    }
    final generation = _generation, owner = _owner, token = _token!;
    _connecting = true;
    status = 'Connecting realtime…';
    _emit(LiveKind.state);
    try {
      final info = await transport.send(
        TransportRequest(
          method: 'GET',
          uri: endpoint.replace(path: '${endpoint.path}/info'),
          headers: const {'Accept': 'application/json'},
          timeout: const Duration(seconds: 20),
        ),
      );
      if (generation != _generation || _disposed) return;
      if (info.statusCode != 200 ||
          (jsonDecode(info.body) as Map)['websocket'] != true) {
        throw UnsupportedError('SockJS WebSocket transport unavailable');
      }
      final random = Random.secure();
      final session = List.generate(
        16,
        (_) => random.nextInt(16).toRadixString(16),
      ).join();
      final uri = endpoint.replace(
        scheme: endpoint.scheme == 'https' ? 'wss' : 'ws',
        path:
            '${endpoint.path}/${random.nextInt(1000).toString().padLeft(3, '0')}/$session/websocket',
        query: null,
        fragment: null,
      );
      final socket = await connector(uri);
      if (_disposed || generation != _generation || owner != currentUserId()) {
        await socket.close();
        return;
      }
      _socket = socket;
      _input = socket.messages.listen(
        (data) {
          if (_disposed ||
              generation != _generation ||
              sessionGeneration?.call() != _authGeneration) {
            return;
          }
          try {
            _frame(data, token);
          } catch (_) {
            _fail('Realtime protocol error; REST remains available.');
          }
        },
        onError: (Object _) {
          if (generation == _generation) {
            _fail('Realtime disconnected; retrying.');
          }
        },
        onDone: () {
          if (generation == _generation && !_disposed) {
            _fail('Realtime disconnected; retrying.');
          }
        },
      );
      _deadline = Timer(const Duration(seconds: 20), () {
        if (generation == _generation && !_online) {
          _fail('Realtime handshake timed out; retrying.');
        }
      });
    } on UnsupportedError {
      if (generation == _generation && !_disposed) {
        _transportUnavailable = true;
        _fail(
          'SockJS WebSocket unavailable; REST updates remain active.',
          retry: false,
        );
      }
    } catch (_) {
      if (generation == _generation && !_disposed) {
        _fail('Realtime connection failed; retrying with REST available.');
      }
    } finally {
      if (generation == _generation) {
        _connecting = false;
      }
    }
  }

  void _send(String command, Map<String, String> headers) {
    try {
      _socket?.send(jsonEncode([encodeStomp(command, headers)]));
    } catch (_) {
      _fail('Realtime send failed; REST remains available.');
    }
  }

  void _frame(String data, String token) {
    _lastFrame = DateTime.now();
    if (data == 'o') {
      _send('CONNECT', {
        'accept-version': '1.2',
        'host': endpoint.host,
        'heart-beat': '0,0',
        'Authorization': 'Bearer $token',
      });
      return;
    }
    if (data == 'h') return;
    if (data.startsWith('c')) {
      _fail('SockJS session closed; reconnecting.');
      return;
    }
    for (final text in sockJsMessages(data)) {
      for (final frame in _decoder.add(text)) {
        if (frame.command == 'CONNECTED') {
          if (_online) continue;
          if (frame.headers['version'] != '1.2') {
            throw const FormatException('Unsupported STOMP version');
          }
          _deadline?.cancel();
          _online = true;
          _connecting = false;
          _attempt = 0;
          status = 'Realtime connected (SockJS WebSocket)';
          _send('SUBSCRIBE', {
            'id': 'notifications',
            'destination': '/user/queue/notifications',
            'ack': 'auto',
          });
          for (final id in _watches.keys) {
            _subscribe(id);
          }
          _emit(LiveKind.state);
          _emit(LiveKind.reconcile);
          unawaited(_count());
        } else if (frame.command == 'ERROR') {
          _fail(
            'Realtime authorization/protocol rejected; REST remains available.',
          );
          return;
        } else if (frame.command == 'MESSAGE' && _online) {
          final subscription = frame.headers['subscription'];
          if (subscription == 'notifications') {
            final notification = NotificationItem.fromJson(
              jsonDecode(frame.body),
            );
            if (notification.recipientId != _owner) {
              throw const FormatException('Wrong notification recipient');
            }
            _emit(LiveKind.notification, notification: notification);
            unawaited(_count());
          } else if (subscription != null && subscription.startsWith('chat-')) {
            final id = int.tryParse(subscription.substring(5));
            if (id == null || !_watches.containsKey(id)) continue;
            final message = ChatMessage.fromJson(jsonDecode(frame.body));
            if (message.conversationId != id) {
              throw const FormatException('Wrong conversation event');
            }
            _emit(LiveKind.message, message: message, conversationId: id);
          }
        }
      }
    }
  }

  void _subscribe(int id) => _send('SUBSCRIBE', {
    'id': 'chat-$id',
    'destination': '/user/queue/chat/conversation/$id',
    'ack': 'auto',
  });
  void Function() watchConversation(int owner, int id) {
    if (id <= 0 || currentUserId() != owner) return () {};
    activate();
    if (id <= 0 || currentUserId() != owner || _owner != owner) return () {};
    final first = !_watches.containsKey(id);
    _watches[id] = (_watches[id] ?? 0) + 1;
    final identity = _identity;
    if (first && _online) {
      _subscribe(id);
    }
    var released = false;
    return () {
      if (released || _owner != owner || identity != _identity) return;
      released = true;
      final count = _watches[id];
      if (count == null) return;
      if (count > 1) {
        _watches[id] = count - 1;
      } else {
        _watches.remove(id);
        if (_online) {
          _send('UNSUBSCRIBE', {'id': 'chat-$id'});
        }
      }
    };
  }

  void chatChanged(int owner, int? id) {
    if (_owner == owner) {
      _emit(LiveKind.reconcile, conversationId: id);
    }
  }

  void notificationsChanged(int owner) {
    if (_owner == owner) {
      unawaited(_count());
      _emit(LiveKind.reconcile);
    }
  }

  void reconnect() {
    if (!_disposed) {
      _transportUnavailable = false;
      _disconnect();
      _active = true;
      _sessionChanged();
      if (_active && !_paused) {
        _periodic ??= Timer.periodic(interval, (_) => _tick());
      }
    }
  }

  void pause() {
    if (_disposed || _paused) return;
    _paused = true;
    _lifecycle++;
    _credentialsFlight = _countFlight = null;
    _countDirty = false;
    _periodic?.cancel();
    _periodic = null;
    _disconnect();
    status = 'Realtime paused';
    _emit(LiveKind.state);
  }

  void resume() {
    if (_disposed || !_paused) return;
    _paused = false;
    _lifecycle++;
    if (_active) {
      _sessionChanged();
      _periodic ??= Timer.periodic(interval, (_) => _tick());
      _emit(LiveKind.reconcile);
    }
  }

  void _fail(String reason, {bool retry = true}) {
    _disconnect();
    status = reason;
    _emit(LiveKind.state);
    if (retry && _active && !_paused && !_disposed && _owner != null) {
      final seconds = min(30, 1 << min(_attempt++, 5));
      _retry = Timer(Duration(seconds: seconds), () {
        _retry = null;
        unawaited(_credentials());
      });
    }
  }

  void _disconnect() {
    _generation++;
    _retry?.cancel();
    _retry = null;
    _deadline?.cancel();
    _deadline = null;
    _online = false;
    _connecting = false;
    unawaited(_input?.cancel() ?? Future<void>.value());
    _input = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      unawaited(socket.close().catchError((Object _) {}));
    }
    _decoder.clear();
    _lastFrame = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _active = false;
    _disconnect();
    _periodic?.cancel();
    unawaited(_auth?.cancel() ?? Future<void>.value());
    _watches.clear();
    _token = null;
    unreadCount = null;
    transport.close();
    unawaited(_events.close());
  }
}
