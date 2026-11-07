import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_exception.dart';
import 'package:attorlink_flutter/core/network/http_transport.dart';
import 'package:attorlink_flutter/features/auth/data/android_session_store.dart';
import 'package:attorlink_flutter/features/auth/data/session_store.dart';
import 'package:attorlink_flutter/features/auth/domain/auth_models.dart';
import 'package:attorlink_flutter/features/auth/domain/session_controller.dart';

final now = DateTime.utc(2030, 1, 1);
String token({bool expired = false}) =>
    'h.${base64Url.encode(utf8.encode(jsonEncode({'exp': now.add(Duration(hours: expired ? -1 : 1)).millisecondsSinceEpoch ~/ 1000})))}.s';
Map<String, Object?> user() => {
  'id': 7,
  'email': 'fixture@example.invalid',
  'role': 'CLIENT',
  'status': 'ACTIVE',
  'emailVerified': true,
};
TransportResponse ok(Object? data) => TransportResponse(
  statusCode: 200,
  body: jsonEncode({'success': true, 'message': 'Success', 'data': data}),
);
Map<String, Object?> auth() => {
  'twoFactorRequired': false,
  'accessToken': token(),
  'refreshToken': 'fixture-refresh',
  'user': user(),
};

class Wire implements HttpTransport {
  Wire(this.handler);
  final FutureOr<TransportResponse> Function(TransportRequest) handler;
  final requests = <TransportRequest>[];
  @override
  Future<TransportResponse> send(TransportRequest r) async {
    requests.add(r);
    return handler(r);
  }

  @override
  void close() {}
}

class SlowStore extends MemorySessionStore implements PersistentSessionStore {
  final started = Completer<void>(), release = Completer<void>();
  @override
  Future<void> write(SessionTokens tokens) async {
    started.complete();
    await release.future;
    await super.write(tokens);
  }
}

class FailingStore extends MemorySessionStore
    implements PersistentSessionStore {
  bool failRead = true;
  @override
  Future<SessionTokens?> read() async {
    if (failRead) {
      throw const ApiException(
        kind: ApiErrorKind.unsupported,
        message: 'Storage locked',
      );
    }
    return super.read();
  }
}

SessionController session(SessionStore store, Wire wire) => SessionController(
  config: ApiConfig(baseUrl: Uri.parse('https://api.example.invalid/api/v1/')),
  store: store,
  transport: wire,
  clock: () => now,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Android emulator/LAN configuration is explicit and production cannot allow HTTP', () {
    expect(
      ApiConfig.forRuntime(android: true).baseUrl.toString(),
      'http://10.0.2.2:18081/api/v1/',
    );
    expect(
      ApiConfig.forRuntime(
        apiUrl: 'http://192.168.1.20:18081/api/v1',
        android: true,
      ).baseUrl.path,
      '/api/v1/',
    );
    expect(
      ApiConfig.forRuntime(apiUrl: 'http://127.0.0.1:18081/api/v1/')
          .baseUrl
          .host,
      '127.0.0.1',
    );
    for (final url in [
      'http://api.example.com/api/v1/',
      'http://8.8.8.8/',
      'http://172.32.0.1/',
    ]) {
      expect(() => ApiConfig.forRuntime(apiUrl: url), throwsArgumentError);
    }
    expect(
      () => ApiConfig.forRuntime(productionBuild: true),
      throwsArgumentError,
    );
    expect(
      () => ApiConfig.forRuntime(
        productionBuild: true,
        environment: 'development',
        apiUrl: 'http://10.0.2.2/',
      ),
      throwsArgumentError,
    );
    expect(
      ApiConfig.forRuntime(
        productionBuild: true,
        apiUrl: 'https://api.example.com/api/v1/',
      ).baseUrl.scheme,
      'https',
    );
  });
  test('Android secure channel scopes complete token pairs and never falls back to plaintext', () async {
    const channel = MethodChannel('attorlink/secure-session');
    String? saved;
    final origins = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = call.arguments as Map;
          origins.add(args['origin'] as String);
          switch (call.method) {
            case 'write':
              saved = args['value'] as String;
              return null;
            case 'read':
              return saved;
            case 'clear':
              saved = null;
              return null;
          }
          throw PlatformException(code: 'INVALID_ARGUMENT');
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final store = AndroidSessionStore('https://api.example.invalid/api/v1/');
    await store.write(
      SessionTokens(accessToken: token(), refreshToken: 'fixture-refresh'),
    );
    expect((await store.read())!.refreshToken, 'fixture-refresh');
    expect(origins.toSet(), {'https://api.example.invalid/api/v1/'});
    saved = 'not-json';
    await expectLater(store.read(), throwsA(isA<ApiException>()));
    expect(saved, isNull);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(
            code: 'STORE_UNAVAILABLE',
            message: 'Private detail must not surface',
          );
        });
    await expectLater(
      store.read(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'safe error',
          isNot(contains('Private detail')),
        ),
      ),
    );
  });
  test(
    'Delayed secure write cannot resurrect credentials after logout',
    () async {
      final store = SlowStore();
      final wire = Wire(
        (r) => r.uri.path.endsWith('/login') ? ok(auth()) : ok(user()),
      );
      final controller = session(store, wire);
      addTearDown(controller.dispose);
      final login = controller.login('fixture@example.invalid', 'FixturePass9');
      await store.started.future;
      final logout = controller.logout();
      store.release.complete();
      await Future.wait([login, logout]);
      expect(controller.state.status, SessionStatus.signedOut);
      expect(await store.read(), isNull);
    },
  );
  test('Saved tokens survive controller recreation but identity still requires auth/me', () async {
    final store = MemorySessionStore();
    final wire = Wire(
      (r) => r.uri.path.endsWith('/login') ? ok(auth()) : ok(user()),
    );
    final first = session(store, wire);
    await first.login('fixture@example.invalid', 'FixturePass9');
    first.dispose();
    final requests = Wire((_) => ok(user()));
    final second = session(store, requests);
    addTearDown(second.dispose);
    await second.restore();
    expect(second.state.status, SessionStatus.authenticated);
    expect(second.state.user!.id, 7);
    expect(requests.requests.single.uri.path, '/api/v1/auth/me');
  });
  test('Rotation removes the persisted old pair before sending and never retries ambiguous refresh', () async {
    final store = MemorySessionStore();
    await store.write(
      SessionTokens(
        accessToken: token(expired: true),
        refreshToken: 'fixture-old',
      ),
    );
    var refreshCalls = 0;
    final wire = Wire((r) async {
      if (r.uri.path.endsWith('/token/refresh')) {
        refreshCalls++;
        expect(await store.read(), isNull);
        return const TransportResponse(statusCode: 503, body: 'Unavailable');
      }
      return ok(user());
    });
    final controller = session(store, wire);
    addTearDown(controller.dispose);
    await controller.restore();
    expect(refreshCalls, 1);
    expect(controller.state.status, SessionStatus.signedOut);
    expect(await store.read(), isNull);
  });
  test(
    'Unavailable secure storage closes navigation and can retry startup safely',
    () async {
      final store = FailingStore();
      final controller = session(store, Wire((_) => ok(user())));
      addTearDown(controller.dispose);
      await controller.restore();
      expect(controller.state.status, SessionStatus.unavailable);
      store.failRead = false;
      await controller.revalidate();
      expect(controller.state.status, SessionStatus.signedOut);
    },
  );
}
