import 'dart:async';
import 'dart:convert';

import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_exception.dart';
import 'package:attorlink_flutter/core/network/http_transport.dart';
import 'package:attorlink_flutter/features/auth/data/session_store.dart';
import 'package:attorlink_flutter/features/auth/domain/auth_models.dart';
import 'package:attorlink_flutter/features/auth/domain/session_controller.dart';

final _now = DateTime.utc(2026, 11, 4);
String _jwt(String tag, {bool expired = false}) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({
      'exp': _now.add(Duration(hours: expired ? -1 : 1)).millisecondsSinceEpoch ~/ 1000,
      'tag': tag, 'role': 'ADMIN', // Must never control frontend authorization.
    }))).replaceAll('=', '')}.signature';
Map<String, Object?> _user({
  String role = 'CLIENT',
  String status = 'ACTIVE',
  int id = 1,
}) => {
  'id': id,
  'email': 'person@example.test',
  'role': role,
  'status': status,
  'emailVerified': true,
};
Map<String, Object?> _auth(String tag, {String role = 'CLIENT'}) => {
  'twoFactorRequired': false,
  'accessToken': _jwt(tag),
  'refreshToken': 'refresh-$tag',
  'user': _user(role: role),
};
TransportResponse _ok(Object? data) => TransportResponse(
  statusCode: 200,
  body: jsonEncode({'success': true, 'message': 'Success', 'data': data}),
);
TransportResponse _failure(int status) => TransportResponse(
  statusCode: status,
  body: jsonEncode({
    'success': false,
    'message': 'Request rejected',
    'data': null,
  }),
);
void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<ApiException> _fails(Future<Object?> future) async {
  try {
    await future;
  } on ApiException catch (e) {
    return e;
  }
  throw StateError('Expected API failure');
}

Map<String, dynamic> _body(TransportRequest request) =>
    jsonDecode(request.body!) as Map<String, dynamic>;

class _Transport implements HttpTransport {
  final requests = <TransportRequest>[];
  late FutureOr<TransportResponse> Function(TransportRequest) respond;
  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    return await respond(request);
  }

  @override
  void close() {}
}

class _Fixture {
  _Fixture() {
    transport.respond = (r) {
      if (r.uri.path.endsWith('/auth/login')) return _ok(_auth('initial'));
      if (r.uri.path.endsWith('/auth/me')) return _ok(_user());
      throw StateError('Unexpected endpoint ${r.uri.path}');
    };
    session = SessionController(
      config: ApiConfig(baseUrl: Uri.parse('https://api.example.test/api/v1/')),
      store: store,
      transport: transport,
      clock: () => _now,
    );
  }
  final store = MemorySessionStore();
  final transport = _Transport();
  late final SessionController session;
  Future<void> signIn() => session.login('person@example.test', 'password1');
}

final authContractCases = <String, Future<void> Function()>{
  'signup verification and resend use exact contracts without signing in':
      () async {
        final f = _Fixture();
        try {
          f.transport.respond = (_) => _ok('Email verification message');
          await f.session.repository.signup(
            ' person@example.test ',
            'password1',
            'password1',
          );
          await f.session.repository.verifySignup(
            'person@example.test',
            '123456',
          );
          await f.session.repository.resendSignup('person@example.test');
          final requests = f.transport.requests;
          _check(
            requests.map((r) => r.uri.path).join(',') == '/api/v1/auth/signup,/api/v1/auth/signup/verify-otp,/api/v1/auth/signup/resend-otp',
            'Wrong signup endpoints',
          );
          _check(
            _body(requests.first)['email'] == 'person@example.test' &&
                !_body(requests.first).containsKey('phone'),
            'Wrong signup body',
          );
          _check(_body(requests[1])['otp'] == '123456', 'Wrong OTP body');
          _check(
            await f.store.read() == null,
            'Signup must not issue a local session',
          );
        } finally {
          f.session.dispose();
        }
      },
  'forgot password exchanges OTP for reset token and never signs in': () async {
    final f = _Fixture();
    try {
      f.transport.respond = (r) => switch (r.uri.path) {
        '/api/v1/auth/password/forgot' => _ok(
          'If the account exists, a code was sent.',
        ),
        '/api/v1/auth/password/forgot/verify-otp' => _ok({
          'resetToken': 'recovery-secret',
        }),
        '/api/v1/auth/password/forgot/confirm' => _ok({
          'email': 'person@example.test',
          'events': [],
        }),
        _ => throw StateError('Unknown recovery endpoint'),
      };
      await f.session.repository.forgotPassword('person@example.test');
      final token = await f.session.repository.verifyRecovery(
        'person@example.test',
        '123456',
      );
      await f.session.repository.completeRecovery(
        'person@example.test',
        token,
        'newpass1',
        'newpass1',
      );
      final body = _body(f.transport.requests.last);
      _check(
        body['resetToken'] == 'recovery-secret' &&
            body['password'] == 'newpass1' &&
            body['confirmPassword'] == 'newpass1',
        'Wrong recovery fields',
      );
      _check(
        !f.transport.requests.any(
          (r) => r.headers.containsKey('Authorization'),
        ),
        'Public flow leaked bearer token',
      );
      _check(
        await f.store.read() == null,
        'Recovery must not create a session',
      );
    } finally {
      f.session.dispose();
    }
  },
  'login retrieves current user and enforces one-time client/lawyer selection':
      () async {
        final f = _Fixture();
        try {
          f.transport.respond = (r) {
            if (r.uri.path.endsWith('/auth/login')) {
              return _ok(_auth('initial', role: 'UNASSIGNED'));
            }
            if (r.uri.path.endsWith('/auth/me')) {
              return _ok(_user(role: 'UNASSIGNED'));
            }
            if (r.uri.path.endsWith('/users/profile/role')) {
              _check(
                r.method == 'POST' && _body(r)['role'] == 'LAWYER',
                'Wrong role selection payload',
              );
              return _ok(_user(role: 'LAWYER'));
            }
            throw StateError('Unexpected endpoint');
          };
          await f.session.login(
            ' person@example.test ',
            'password1',
            rememberMe: true,
          );
          _check(
            _body(f.transport.requests.first)['rememberMe'] == true,
            'Remember flag lost',
          );
          _check(
            f.session.state.status == SessionStatus.roleRequired,
            'Role selection bypassed',
          );
          await f.session.selectRole(UserRole.lawyer);
          _check(
            f.session.state.user?.role == UserRole.lawyer,
            'Wrong selected role',
          );
          _check(
            f.session.state.status == SessionStatus.authenticated,
            'Lawyer not admitted',
          );
          await _fails(f.session.selectRole(UserRole.client));
          _check(f.transport.requests.length == 3, 'Role mutation repeated');
        } finally {
          f.session.dispose();
        }
      },
  'two-factor challenge carries no tokens and failed challenge cannot be reused':
      () async {
        final f = _Fixture();
        try {
          f.transport.respond = (r) => r.uri.path.endsWith('/login')
              ? _ok({
                  'twoFactorRequired': true,
                  'challengeToken': 'challenge-secret',
                })
              : _failure(400);
          await f.signIn();
          _check(
            f.session.state.status == SessionStatus.challenge &&
                await f.store.read() == null,
            'Challenge opened protected session',
          );
          await _fails(f.session.verifyTwoFactor('123456'));
          _check(
            _body(f.transport.requests.last)['challengeToken'] ==
                'challenge-secret',
            'Wrong challenge request',
          );
          await _fails(f.session.verifyTwoFactor('123456'));
          _check(
            f.transport.requests.length == 2 &&
                f.session.state.status == SessionStatus.signedOut,
            'Challenge was retried',
          );
        } finally {
          f.session.dispose();
        }
      },
  'successful two-factor completion fetches authenticated user': () async {
    final f = _Fixture();
    try {
      f.transport.respond = (r) => switch (r.uri.path) {
        '/api/v1/auth/login' => _ok({
          'twoFactorRequired': true,
          'challengeToken': 'challenge',
        }),
        '/api/v1/auth/login/2fa' => _ok(_auth('2fa')),
        '/api/v1/auth/me' => _ok(_user()),
        _ => throw StateError('Unexpected endpoint'),
      };
      await f.signIn();
      await f.session.verifyTwoFactor('123456');
      _check(
        f.session.state.status == SessionStatus.authenticated,
        '2FA never established a session',
      );
      _check(
        (await f.store.read())?.refreshToken == 'refresh-2fa',
        '2FA tokens missing',
      );
    } finally {
      f.session.dispose();
    }
  },
  'memory restoration validates with backend and ignores JWT role claim':
      () async {
        final f = _Fixture();
        try {
          await f.store.write(
            SessionTokens(
              accessToken: _jwt('saved'),
              refreshToken: 'saved-refresh',
            ),
          );
          await f.session.restore();
          _check(
            f.transport.requests.single.uri.path.endsWith('/auth/me'),
            'Restoration did not validate backend',
          );
          _check(
            f.session.state.user?.role == UserRole.client,
            'Unverified JWT role used',
          );
        } finally {
          f.session.dispose();
        }
      },
  'expired restoration rotates once before fetching user': () async {
    final f = _Fixture();
    try {
      await f.store.write(
        SessionTokens(
          accessToken: _jwt('expired', expired: true),
          refreshToken: 'saved-refresh',
        ),
      );
      f.transport.respond = (r) {
        if (r.uri.path.endsWith('/token/refresh')) {
          _check(
            _body(r)['refreshToken'] == 'saved-refresh' &&
                !r.headers.containsKey('Authorization'),
            'Wrong refresh contract',
          );
          return _ok(_auth('rotated'));
        }
        _check(
          r.headers['Authorization'] == 'Bearer ${_jwt('rotated')}',
          'Restored request used old bearer',
        );
        return _ok(_user());
      };
      await f.session.restore();
      _check(
        f.transport.requests.length == 2 &&
            (await f.store.read())?.refreshToken == 'refresh-rotated',
        'Rotation was not committed',
      );
    } finally {
      f.session.dispose();
    }
  },
  'concurrent 401 responses share one rotation and retry once with fresh bearer':
      () async {
        final f = _Fixture();
        try {
          await f.signIn();
          final refresh = Completer<TransportResponse>();
          final entered = Completer<void>();
          var rotations = 0;
          var retries = 0;
          f.transport.respond = (r) {
            if (r.uri.path.endsWith('/token/refresh')) {
              rotations++;
              if (!entered.isCompleted) entered.complete();
              return refresh.future;
            }
            if (r.headers['Authorization'] == 'Bearer ${_jwt('initial')}') {
              return _failure(401);
            }
            retries++;
            return _ok('retried');
          };
          final first = f.session.api.request(
            'GET',
            'private/one',
            authenticated: true,
            decode: (v) => v,
          );
          final second = f.session.api.request(
            'GET',
            'private/two',
            authenticated: true,
            decode: (v) => v,
          );
          await entered.future;
          refresh.complete(_ok(_auth('fresh')));
          await Future.wait([first, second]);
          _check(
            rotations == 1 && retries == 2,
            'Concurrent refresh reused a rotating token',
          );
        } finally {
          f.session.dispose();
        }
      },
  'ambiguous refresh failure clears memory and never reuses old refresh':
      () async {
        final f = _Fixture();
        try {
          await f.signIn();
          var rotations = 0;
          f.transport.respond = (r) {
            if (r.uri.path.endsWith('/token/refresh')) {
              rotations++;
              throw const ApiException(
                kind: ApiErrorKind.network,
                message: 'Connection lost',
              );
            }
            return _failure(401);
          };
          await _fails(
            f.session.api.request(
              'GET',
              'private',
              authenticated: true,
              decode: (v) => v,
            ),
          );
          await _fails(
            f.session.api.request(
              'GET',
              'private',
              authenticated: true,
              decode: (v) => v,
            ),
          );
          _check(
            rotations == 1 &&
                await f.store.read() == null &&
                f.session.state.status == SessionStatus.signedOut,
            'Ambiguous rotation reused old token',
          );
        } finally {
          f.session.dispose();
        }
      },
  'second 401 after rotation expires session without a refresh loop': () async {
    final f = _Fixture();
    try {
      await f.signIn();
      var rotations = 0;
      f.transport.respond = (r) {
        if (r.uri.path.endsWith('/token/refresh')) {
          rotations++;
          return _ok(_auth('fresh'));
        }
        return _failure(401);
      };
      await _fails(
        f.session.api.request(
          'GET',
          'private',
          authenticated: true,
          decode: (v) => v,
        ),
      );
      _check(
        rotations == 1 &&
            await f.store.read() == null &&
            f.session.state.status == SessionStatus.signedOut,
        'Unauthorized retry loop',
      );
    } finally {
      f.session.dispose();
    }
  },
  'temporary current-user failure keeps protected routes closed until retry':
      () async {
        final f = _Fixture();
        try {
          await f.signIn();
          f.transport.respond = (_) => _failure(503);
          await f.session.revalidate();
          _check(
            f.session.state.status == SessionStatus.unavailable &&
                await f.store.read() != null,
            'Network outage bypassed guard or lost valid credentials',
          );
          f.transport.respond = (_) => _ok(_user());
          await f.session.revalidate();
          _check(
            f.session.state.status == SessionStatus.authenticated,
            'Retry failed to restore verified user',
          );
        } finally {
          f.session.dispose();
        }
      },
  'logout revokes refresh token and clears local session even if offline':
      () async {
        for (final offline in [false, true]) {
          final f = _Fixture();
          try {
            await f.signIn();
            f.transport.respond = (r) {
              _check(
                r.uri.path.endsWith('/auth/logout') && r.method == 'POST',
                'Wrong logout endpoint',
              );
              _check(
                _body(r)['refreshToken'] == 'refresh-initial' &&
                    r.headers.containsKey('Authorization'),
                'Wrong logout contract',
              );
              if (offline) {
                throw const ApiException(
                  kind: ApiErrorKind.network,
                  message: 'Offline',
                );
              }
              return _ok(null);
            };
            await f.session.logout();
            _check(
              await f.store.read() == null &&
                  f.session.state.status == SessionStatus.signedOut,
              'Logout retained local credentials',
            );
            _check(
              !offline ||
                  f.session.state.message!.contains('could not be confirmed'),
              'Offline logout falsely claimed revocation',
            );
          } finally {
            f.session.dispose();
          }
        }
      },
  'logout waits for in-flight rotation then revokes newest refresh token':
      () async {
        final f = _Fixture();
        try {
          await f.signIn();
          final refresh = Completer<TransportResponse>();
          final entered = Completer<void>();
          f.transport.respond = (r) {
            if (r.uri.path.endsWith('/token/refresh')) {
              entered.complete();
              return refresh.future;
            }
            if (r.uri.path.endsWith('/auth/logout')) {
              _check(
                _body(r)['refreshToken'] == 'refresh-fresh',
                'Logout revoked stale refresh token',
              );
              return _ok(null);
            }
            return _failure(401);
          };
          final pending = _fails(
            f.session.api.request(
              'GET',
              'private',
              authenticated: true,
              decode: (v) => v,
            ),
          );
          await entered.future;
          final logout = f.session.logout();
          refresh.complete(_ok(_auth('fresh')));
          await Future.wait([pending, logout]);
          _check(
            await f.store.read() == null &&
                f.session.state.status == SessionStatus.signedOut,
            'Refresh resurrected signed-out session',
          );
        } finally {
          f.session.dispose();
        }
      },
  'late login response cannot restore a signed-out session': () async {
    final f = _Fixture();
    try {
      final login = Completer<TransportResponse>();
      f.transport.respond = (_) => login.future;
      final pending = f.signIn();
      await f.session.logout();
      login.complete(_ok(_auth('late')));
      await pending;
      _check(
        await f.store.read() == null &&
            f.session.state.status == SessionStatus.signedOut,
        'Late login resurrected session',
      );
    } finally {
      f.session.dispose();
    }
  },
  'stale 401 from a previous login cannot clear the newer session': () async {
    final f = _Fixture();
    try {
      await f.signIn();
      final old = Completer<TransportResponse>();
      final entered = Completer<void>();
      f.transport.respond = (r) {
        if (r.uri.path.endsWith('/old-request')) {
          entered.complete();
          return old.future;
        }
        if (r.uri.path.endsWith('/auth/logout')) return _ok(null);
        if (r.uri.path.endsWith('/auth/login')) return _ok(_auth('second'));
        return _ok(_user());
      };
      final pending = _fails(
        f.session.api.request(
          'GET',
          'old-request',
          authenticated: true,
          decode: (v) => v,
        ),
      );
      await entered.future;
      await f.session.logout();
      await f.signIn();
      old.complete(_failure(401));
      await pending;
      _check(
        (await f.store.read())?.refreshToken == 'refresh-second' &&
            f.session.state.status == SessionStatus.authenticated,
        'Old response cleared new account',
      );
    } finally {
      f.session.dispose();
    }
  },
  'admin and inactive accounts never enter client/lawyer navigation': () async {
    for (final user in [
      _user(role: 'ADMIN'),
      _user(status: 'SUSPENDED'),
      _user(status: 'SCHEDULED_DELETION'),
    ]) {
      final f = _Fixture();
      try {
        f.transport.respond = (r) => r.uri.path.endsWith('/auth/login')
            ? _ok(_auth('initial'))
            : _ok(user);
        await f.signIn();
        _check(
          f.session.state.status == SessionStatus.restricted,
          'Restricted account admitted',
        );
      } finally {
        f.session.dispose();
      }
    }
  },
  'fresh process memory store is empty and rejected credentials never refresh':
      () async {
        final f = _Fixture();
        try {
          await f.session.restore();
          _check(
            f.session.state.status == SessionStatus.signedOut &&
                f.transport.requests.isEmpty,
            'Cold start fabricated authentication',
          );
          f.transport.respond = (_) => _failure(401);
          await _fails(f.signIn());
          _check(
            f.transport.requests.length == 1 && await f.store.read() == null,
            'Failed login attempted token refresh',
          );
        } finally {
          f.session.dispose();
        }
      },
  'forbidden actions preserve the session and never refresh': () async {
    final f = _Fixture();
    try {
      await f.signIn();
      final before = f.transport.requests.length;
      f.transport.respond = (_) => _failure(403);
      final error = await _fails(
        f.session.api.request(
          'GET',
          'private',
          authenticated: true,
          decode: (v) => v,
        ),
      );
      _check(
        error.kind == ApiErrorKind.forbidden &&
            f.transport.requests.length == before + 1,
        'Permission failure triggered refresh',
      );
      _check(
        f.session.state.status == SessionStatus.authenticated &&
            await f.store.read() != null,
        'Permission error cleared session',
      );
    } finally {
      f.session.dispose();
    }
  },
  'malformed rotation response cannot partially replace credentials': () async {
    final f = _Fixture();
    try {
      await f.signIn();
      f.transport.respond = (r) => r.uri.path.endsWith('/token/refresh')
          ? _ok({'twoFactorRequired': false, 'accessToken': 'incomplete'})
          : _failure(401);
      await _fails(
        f.session.api.request(
          'GET',
          'private',
          authenticated: true,
          decode: (v) => v,
        ),
      );
      _check(
        await f.store.read() == null &&
            f.session.state.status == SessionStatus.signedOut,
        'Partial rotation retained unsafe credentials',
      );
    } finally {
      f.session.dispose();
    }
  },
  'background resume validation preserves editors but still closes them on failure':
      () async {
        final f = _Fixture();
        try {
          await f.signIn();
          final response = Completer<TransportResponse>();
          f.transport.respond = (_) => response.future;
          final pending = f.session.revalidate(background: true);
          _check(
            f.session.state.status == SessionStatus.authenticated,
            'Resume verification discarded the active editor',
          );
          response.complete(_ok(_user()));
          await pending;
          _check(
            f.session.state.status == SessionStatus.authenticated,
            'Verified resume lost authentication',
          );
          f.transport.respond = (_) => _failure(503);
          await f.session.revalidate(background: true);
          _check(
            f.session.state.status == SessionStatus.unavailable,
            'Resume failure did not close protected navigation',
          );
        } finally {
          f.session.dispose();
        }
      },
};
