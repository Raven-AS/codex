import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_exception.dart';
import 'package:attorlink_flutter/core/network/http_transport.dart';
import 'package:attorlink_flutter/features/auth/data/session_store.dart';
import 'package:attorlink_flutter/features/auth/domain/auth_models.dart';
import 'package:attorlink_flutter/features/auth/domain/session_controller.dart';
import 'package:attorlink_flutter/features/settings/data/settings_repository.dart';

// Backend-shaped fixtures reproduce client defects; never live integration proof.
final now = DateTime.utc(2030, 1, 1);
String jwt(int id) =>
    'h.${base64Url.encode(utf8.encode(jsonEncode({'exp': now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000, 'sub': '$id'})))}.s';
Map<String, Object?> user(int id, {String role = 'CLIENT'}) => {
  'id': id,
  'email': 'fixture$id@example.invalid',
  'role': role,
  'status': 'ACTIVE',
  'emailVerified': true,
};
Map<String, Object?> auth(int id, {String role = 'CLIENT'}) => {
  'twoFactorRequired': false,
  'accessToken': jwt(id),
  'refreshToken': 'fixture-refresh-$id',
  'user': user(id, role: role),
};
TransportResponse ok(Object? data) => TransportResponse(
  statusCode: 200,
  body: jsonEncode({'success': true, 'message': 'Success', 'data': data}),
);
TransportResponse unauthorized([String message = 'Password is incorrect']) =>
    TransportResponse(
      statusCode: 401,
      body: jsonEncode({'success': false, 'message': message, 'data': null}),
    );

class Wire implements HttpTransport {
  Wire(this.handler);
  final FutureOr<TransportResponse> Function(TransportRequest) handler;
  final calls = <TransportRequest>[];
  @override
  Future<TransportResponse> send(TransportRequest r) async {
    calls.add(r);
    return handler(r);
  }

  @override
  void close() {}
}

SessionController controller(SessionStore store, Wire wire) =>
    SessionController(
      config: ApiConfig(
        baseUrl: Uri.parse('https://api.example.invalid/api/v1/'),
      ),
      store: store,
      transport: wire,
      clock: () => now,
    );

class CountingStore extends MemorySessionStore {
  int reads = 0;
  @override
  Future<SessionTokens?> read() {
    reads++;
    return super.read();
  }
}

Future<void> until(bool Function() done) async {
  for (var i = 0; i < 60 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue);
}

void main() {
  test('10A wrong-password 401 never replays a security mutation or destroys a valid session', () async {
    var meId = 1;
    final wire = Wire((r) {
      if (r.uri.path.endsWith('/login')) {
        return ok(auth(1));
      }
      if (r.uri.path.endsWith('/auth/me')) {
        return ok(user(meId));
      }
      if (r.uri.path.endsWith('/token/refresh')) {
        throw StateError('Valid JWT must not rotate for a bad password');
      }
      return unauthorized();
    });
    final session = controller(MemorySessionStore(), wire);
    addTearDown(session.dispose);
    await session.login('fixture1@example.invalid', 'FixturePass9');
    final repo = SettingsRepository.forSession(session);
    final actions = <Future<String> Function()>[
      () => repo.resetInit('wrong', 'NewPass123', 'NewPass123'),
      () => repo.emailStart('wrong'),
      () => repo.disable('wrong'),
      () => repo.deleteRequest('wrong'),
    ];
    for (final action in actions) {
      final before = wire.calls.length;
      await expectLater(
        action(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.unauthorized,
          ),
        ),
      );
      expect(wire.calls.skip(before).map((r) => r.method), ['POST', 'GET']);
      expect(session.state.status, SessionStatus.authenticated);
    }
    meId = 99;
    await expectLater(
      repo.disable('wrong'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.kind,
          'kind',
          ApiErrorKind.invalidResponse,
        ),
      ),
    );
    expect(session.state.status, SessionStatus.signedOut);
  });
  test('10A genuine bearer 401 on a password action renews only the safe account check', () async {
    var rejectMe = false, refreshes = 0, actions = 0;
    final wire = Wire((r) {
      if (r.uri.path.endsWith('/login')) {
        return ok(auth(1));
      }
      if (r.uri.path.endsWith('/auth/me')) {
        return rejectMe
            ? unauthorized(
                'Unauthorized: missing or invalid authentication token',
              )
            : ok(user(1));
      }
      if (r.uri.path.endsWith('/token/refresh')) {
        refreshes++;
        rejectMe = false;
        return ok({...auth(1), 'refreshToken': 'fixture-rotated'});
      }
      actions++;
      return unauthorized(
        'Unauthorized: missing or invalid authentication token',
      );
    });
    final session = controller(MemorySessionStore(), wire);
    addTearDown(session.dispose);
    await session.login('fixture1@example.invalid', 'FixturePass9');
    rejectMe = true;
    await expectLater(
      SettingsRepository.forSession(session).disable('password'),
      throwsA(isA<ApiException>()),
    );
    expect(actions, 1);
    expect(refreshes, 1);
    expect(session.state.status, SessionStatus.authenticated);
  });
  test(
    '10A an old account-validation request cannot block a later login',
    () async {
      final oldMe = Completer<TransportResponse>();
      var identity = 1, delay = false;
      final wire = Wire((r) {
        if (r.uri.path.endsWith('/login')) {
          return ok(auth(identity));
        }
        if (r.uri.path.endsWith('/logout')) {
          return ok(null);
        }
        if (delay && identity == 1) {
          return oldMe.future;
        }
        return ok(user(identity));
      });
      final session = controller(MemorySessionStore(), wire);
      addTearDown(session.dispose);
      await session.login('fixture1@example.invalid', 'FixturePass9');
      delay = true;
      final background = session.revalidate(background: true);
      await until(
        () =>
            wire.calls.where((r) => r.uri.path.endsWith('/auth/me')).length ==
            2,
      );
      await session.logout();
      identity = 2;
      final newLogin = session.login(
        'fixture2@example.invalid',
        'FixturePass9',
      );
      await until(() => session.state.user?.id == 2);
      expect(session.state.status, SessionStatus.authenticated);
      oldMe.complete(ok(user(1)));
      await Future.wait([background, newLogin]);
      expect(session.state.user!.id, 2);
    },
  );
  test('10A old refresh disposal cannot erase a newer saved session and 2FA has no old credential fallback', () async {
    final oldRefresh = Completer<TransportResponse>();
    var identity = 1, challenge = false;
    final store = MemorySessionStore();
    final wire = Wire((r) {
      if (r.uri.path.endsWith('/login')) {
        return ok(
          challenge
              ? {
                  'twoFactorRequired': true,
                  'challengeToken': 'fixture-challenge',
                }
              : auth(identity),
        );
      }
      if (r.uri.path.endsWith('/token/refresh')) {
        return oldRefresh.future;
      }
      return ok(user(identity));
    });
    final session = controller(store, wire);
    await session.login('fixture1@example.invalid', 'FixturePass9');
    final refresh = session.recheckRefreshSession();
    await until(
      () => wire.calls.any((r) => r.uri.path.endsWith('/token/refresh')),
    );
    identity = 2;
    await session.login('fixture2@example.invalid', 'FixturePass9');
    session.dispose();
    await Future<void>.delayed(Duration.zero);
    expect((await store.read())!.refreshToken, 'fixture-refresh-2');
    oldRefresh.complete(ok(auth(1)));
    await refresh;
    expect((await store.read())!.refreshToken, 'fixture-refresh-2');
    final next = controller(store, wire);
    addTearDown(next.dispose);
    await next.restore();
    challenge = true;
    await next.login('fixture2@example.invalid', 'FixturePass9');
    expect(next.state.status, SessionStatus.challenge);
    expect(await store.read(), isNull);
  });
  test('10A startup coalesces and unexpected refresh/me/role identities cannot authorize another account', () async {
    final store = CountingStore();
    await store.write(
      SessionTokens(accessToken: jwt(1), refreshToken: 'fixture-refresh-1'),
    );
    final delayed = Completer<TransportResponse>();
    final wire = Wire((_) => delayed.future);
    final first = controller(store, wire);
    addTearDown(first.dispose);
    final a = first.restore(), b = first.restore();
    await until(() => wire.calls.isNotEmpty);
    delayed.complete(ok(user(1)));
    await Future.wait([a, b]);
    expect(store.reads, 1);
    expect(wire.calls.length, 1);
    var badMe = false, roleWrong = false;
    final otherWire = Wire((r) {
      if (r.uri.path.endsWith('/login')) {
        return ok(auth(1, role: 'UNASSIGNED'));
      }
      if (r.uri.path.endsWith('/token/refresh')) {
        return ok(auth(99));
      }
      if (r.uri.path.endsWith('/profile/role')) {
        return ok(user(roleWrong ? 99 : 1, role: 'LAWYER'));
      }
      return ok(user(badMe ? 99 : 1, role: 'UNASSIGNED'));
    });
    final otherStore = MemorySessionStore();
    final next = controller(otherStore, otherWire);
    addTearDown(next.dispose);
    await next.login('fixture1@example.invalid', 'FixturePass9');
    roleWrong = true;
    await expectLater(
      next.selectRole(UserRole.lawyer),
      throwsA(isA<ApiException>()),
    );
    expect(next.state.status, SessionStatus.roleRequired);
    await expectLater(
      next.recheckRefreshSession(),
      throwsA(isA<ApiException>()),
    );
    expect(next.state.status, SessionStatus.signedOut);
    expect(await otherStore.read(), isNull);
    await next.login('fixture1@example.invalid', 'FixturePass9');
    badMe = true;
    await next.revalidate();
    expect(next.state.status, SessionStatus.signedOut);
    expect(await otherStore.read(), isNull);
  });
}
