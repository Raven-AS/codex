import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_client.dart';
import 'package:attorlink_flutter/core/network/api_exception.dart';
import 'package:attorlink_flutter/core/network/http_transport.dart';
import 'package:attorlink_flutter/features/auth/domain/auth_models.dart';
import 'package:attorlink_flutter/features/auth/domain/session_controller.dart';
import 'package:attorlink_flutter/features/auth/data/session_store.dart';
import 'package:attorlink_flutter/features/settings/data/settings_repository.dart';
import 'package:attorlink_flutter/features/settings/domain/security_models.dart';
import 'package:attorlink_flutter/features/settings/presentation/settings_screens.dart';

// Fixture-based contracts only; these do not verify a live security operation.
const user = AuthUser(
  id: 7,
  email: 'fixture@example.invalid',
  role: UserRole.client,
  status: UserStatus.active,
);
Map<String, Object?> history() => {
  'email': user.email,
  'accountCreatedAt': '2026-01-01T00:00:00',
  'events': [
    {
      'type': 'PASSWORD_CHANGED_RESET',
      'description': 'Password changed',
      'time': '2026-11-04T12:00:00',
    },
  ],
};
TransportResponse ok(Object? data, {String message = 'Confirmed'}) =>
    TransportResponse(
      statusCode: 200,
      body: jsonEncode({'success': true, 'message': message, 'data': data}),
    );

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

ApiConfig get config =>
    ApiConfig(baseUrl: Uri.parse('https://example.test/api/v1/'));
SettingsRepository repo(
  Wire wire, {
  Future<void> Function(String)? invalidate,
  Future<void> Function()? recheck,
  AuthUser? Function()? current,
}) => SettingsRepository(
  ApiClient(
    config: config,
    transport: wire,
    accessTokenProvider: () => 'fixture-access',
  ),
  ownerId: 7,
  currentUser: current ?? () => user,
  invalidateSession: invalidate ?? (_) async {},
  recheckSession: recheck ?? () async {},
);
Map<String, dynamic> body(TransportRequest r) =>
    jsonDecode(r.body!) as Map<String, dynamic>;
void main() {
  test('8A privacy and all notification preferences match exact endpoints and DTOs', () async {
    final wire = Wire((r) {
      if (r.uri.path.endsWith('/message-privacy')) {
        return ok({
          'whoCanMessageMe': r.body == null
              ? 'EVERYONE'
              : body(r)['whoCanMessageMe'],
        });
      }
      if (r.uri.path.endsWith('/comment-privacy')) {
        return ok({
          'whoCanCommentOnMyPosts': r.body == null
              ? 'EVERYONE'
              : body(r)['whoCanCommentOnMyPosts'],
        });
      }
      return ok(
        r.body == null
            ? {
                'social': true,
                'messaging': false,
                'lawyerActivity': true,
                'system': true,
              }
            : body(r),
      );
    });
    final repository = repo(wire);
    await repository.privacy(true);
    expect(wire.requests.last.uri.path, '/api/v1/users/me/message-privacy');
    expect(
      (await repository.privacy(
        true,
        value: 'FOLLOWERS_ONLY',
      ))['whoCanMessageMe'],
      'FOLLOWERS_ONLY',
    );
    expect(wire.requests.last.method, 'PUT');
    await repository.privacy(false, value: 'EVERYONE');
    expect(body(wire.requests.last), {'whoCanCommentOnMyPosts': 'EVERYONE'});
    final values = await repository.notifications();
    expect(values['messaging'], isFalse);
    await repository.notifications(values: {...values, 'social': false});
    expect(wire.requests.last.method, 'PUT');
    expect(body(wire.requests.last).keys, unorderedEquals(notificationKeys));
    await expectLater(
      repository.privacy(true, value: 'NOBODY'),
      throwsA(isA<ApiException>()),
    );
    expect(
      wire.requests.every(
        (r) => r.headers['Authorization'] == 'Bearer fixture-access',
      ),
      isTrue,
    );
  });
  test(
    '8A password reset and deletion invalidate only after confirmed responses',
    () async {
      final invalidations = <String>[];
      var fail = false;
      final wire = Wire((r) {
        if (fail) {
          return const TransportResponse(statusCode: 503, body: 'Unavailable');
        }
        if (r.uri.path.endsWith('/reset/confirm')) return ok(history());
        return ok('Server result', message: 'Server result');
      });
      final repository = repo(
        wire,
        invalidate: (message) async {
          invalidations.add(message);
        },
      );
      await repository.resetInit('current-pass', 'Newpass123', 'Newpass123');
      expect(body(wire.requests.last), {
        'currentPassword': 'current-pass',
        'newPassword': 'Newpass123',
        'confirmPassword': 'Newpass123',
      });
      expect(invalidations, isEmpty);
      await repository.resetConfirm('123456');
      expect(body(wire.requests.last), {'otp': '123456'});
      expect(invalidations.length, 1);
      await repository.deleteRequest('current-pass');
      expect(body(wire.requests.last), {'password': 'current-pass'});
      expect(invalidations.length, 1);
      fail = true;
      await expectLater(
        repository.deleteConfirm('123456'),
        throwsA(isA<ApiException>()),
      );
      expect(invalidations.length, 1);
      fail = false;
      expect(await repository.deleteConfirm('123456'), 'Server result');
      expect(invalidations.last, 'Server result');
      expect(
        () => repository.resetInit('old', 'short', 'short'),
        throwsA(isA<ApiException>()),
      );
      expect(() => repository.emailVerify('12'), throwsA(isA<ApiException>()));
    },
  );
  test('8A email and TOTP setup/verification/disable retain secrets only as enrollment data', () async {
    final wire = Wire((r) {
      if (r.uri.path.endsWith('/users/me')) {
        return ok({
          'id': 7,
          'email': user.email,
          'twoFactorEnabled': true,
          'twoFactorMethod': 'EMAIL_OTP',
        });
      }
      if (r.uri.path.endsWith('/authenticator/setup')) {
        return ok({
          'secret': 'PRIVATEFIXTURE',
          'otpauthUri': 'otpauth://totp/AttorLink:test?secret=PRIVATEFIXTURE&issuer=AttorLink',
        });
      }
      return ok(r.uri.path.endsWith('/email/enable') ? 'Code sent' : null);
    });
    final repository = repo(wire);
    final state = await repository.security();
    expect(state.enabled, isTrue);
    expect(state.method, 'EMAIL_OTP');
    await repository.emailStart('password');
    expect(body(wire.requests.last), {'password': 'password'});
    await repository.emailVerify('123456');
    expect(wire.requests.last.uri.path, '/api/v1/auth/2fa/email/enable/verify');
    final setup = await repository.totpSetup();
    expect(setup.toString(), isNot(contains('PRIVATEFIXTURE')));
    await repository.totpEnable('654321');
    expect(body(wire.requests.last), {'otp': '654321'});
    await repository.disable('password');
    expect(wire.requests.last.uri.path, '/api/v1/auth/2fa/disable');
    expect(body(wire.requests.last), {'password': 'password'});
  });
  test('8A session revocation checks real refresh validity and clears revoked local credentials', () async {
    final access =
        'a.${base64Url.encode(utf8.encode(jsonEncode({'exp': 4102444800})))}.c';
    final store = MemorySessionStore();
    await store.write(
      SessionTokens(accessToken: access, refreshToken: 'private-refresh'),
    );
    final wire = Wire((r) {
      if (r.uri.path.endsWith('/auth/me')) {
        return ok({
          'id': 7,
          'email': user.email,
          'role': 'CLIENT',
          'status': 'ACTIVE',
          'emailVerified': true,
        });
      }
      if (r.uri.path.endsWith('/token/refresh')) {
        return const TransportResponse(statusCode: 401, body: 'Revoked');
      }
      if (r.method == 'DELETE') return ok(null);
      if (r.uri.path.endsWith('/security-history')) return ok(history());
      return ok([
        {
          'sessionId': 8,
          'createdAt': '2026-11-04T12:00:00',
          'expiresAt': '2026-11-05T12:00:00',
          'rememberMe': true,
        },
      ]);
    });
    final session = SessionController(
      config: config,
      store: store,
      transport: wire,
    );
    addTearDown(session.dispose);
    await session.restore();
    final repository = SettingsRepository.forSession(session);
    expect((await repository.sessions()).single.id, 8);
    expect(
      (await repository.history()).events.single['type'],
      'PASSWORD_CHANGED_RESET',
    );
    await expectLater(repository.revoke(id: 8), throwsA(isA<ApiException>()));
    expect(
      wire.requests.any(
        (r) => r.method == 'DELETE' && r.uri.path.endsWith('/sessions/8'),
      ),
      isTrue,
    );
    expect(session.state.status, SessionStatus.signedOut);
    expect(await store.read(), isNull);
    var invalidated = false;
    final all = repo(
      Wire((_) => ok(null)),
      invalidate: (_) async {
        invalidated = true;
      },
    );
    await all.revoke();
    expect(invalidated, isTrue);
    final denied = repo(wire, current: () => null);
    await expectLater(denied.sessions(), throwsA(isA<ApiException>()));
  });
  testWidgets(
    '8A TOTP stays unenabled until confirmed and clears enrollment on background; deletion requires deliberate action',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 1300);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final wire = Wire(
        (r) => r.uri.path.endsWith('/setup')
            ? ok({
                'secret': 'PRIVATEFIXTURE',
                'otpauthUri':
                    'otpauth://totp/AttorLink:test?secret=PRIVATEFIXTURE',
              })
            : ok(null),
      );
      final repository = repo(wire);
      await tester.pumpWidget(
        MaterialApp(
          home: SecurityFlow(repository: repository, mode: SecurityMode.totp),
        ),
      );
      expect(wire.requests, isEmpty);
      await tester.tap(find.text('Generate authenticator setup'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('totp-secret')), findsOneWidget);
      expect(
        wire.requests.where((r) => r.uri.path.endsWith('/enable')),
        isEmpty,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('PRIVATEFIXTURE'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: SecurityFlow(
            key: const ValueKey('delete'),
            repository: repository,
            mode: SecurityMode.deletion,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final request = find.widgetWithText(FilledButton, 'Request email code');
      expect(tester.widget<FilledButton>(request).onPressed, isNull);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(request).onPressed, isNotNull);
      await tester.tap(request);
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsOneWidget);
      expect(wire.requests.length, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
