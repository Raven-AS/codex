import 'dart:async';

import '../../../core/config/api_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/http_transport.dart';
import '../data/auth_repository.dart';
import '../data/session_store.dart';
import 'auth_models.dart';

/// Process-local session owner. Generation checks reject late login/refresh
/// results after sign-out; a single refresh flight prevents refresh-token reuse.
class SessionController {
  SessionController({
    required ApiConfig config,
    required this.store,
    HttpTransport? transport,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    api = ApiClient(
      config: config,
      transport: transport,
      accessTokenProvider: () => _tokens?.accessToken,
      beforeAuthenticatedRequest: ensureFreshTokens,
      recoverAuthentication: _recover,
      onSessionRejected: _reject,
    );
    repository = AuthRepository(api);
  }

  late final ApiClient api;
  late final AuthRepository repository;
  final SessionStore store;
  final DateTime Function() _clock;
  final _changes = StreamController<AuthState>.broadcast(sync: true);
  AuthState _state = const AuthState(SessionStatus.restoring);
  SessionTokens? _tokens;
  String? _challenge;
  final Set<String> _issuedAccessTokens = {};
  Future<void> _storeQueue = Future<void>.value();
  bool _mustClearStore = false;
  int? _sessionUserId;
  Future<void>? _restoring;
  int? _restoreGeneration, _refreshGeneration, _validationGeneration;
  Future<void>? _refreshing;
  Future<void>? _revalidating;
  int _generation = 0;
  bool _disposed = false;
  bool _ending = false;

  /// Changes when the authentication session is replaced or invalidated.
  int get generation => _generation;

  bool get hasSecurePersistence => store is PersistentSessionStore;
  Future<T> _withStore<T>(Future<T> Function() action) {
    final operation = _storeQueue.then((_) => action());
    _storeQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  AuthState get state => _state;
  Stream<AuthState> get changes => _changes.stream;

  /// For authenticated STOMP CONNECT only; never use this token in a URL.
  Future<String> realtimeAccessToken() async {
    await ensureFreshTokens();
    if (_tokens == null || _ending || _disposed) throw _signedOut;
    return _tokens!.accessToken;
  }

  void _emit(AuthState state) {
    if (_disposed) return;
    _state = state;
    _changes.add(state);
  }

  void _showUser(AuthUser user) {
    final status =
        user.status != UserStatus.active || user.role == UserRole.admin
        ? SessionStatus.restricted
        : user.role == UserRole.unassigned
        ? SessionStatus.roleRequired
        : SessionStatus.authenticated;
    _emit(AuthState(status, user: user));
  }

  Future<void> restore() async {
    if (_disposed || _ending) return;
    final current = _restoring;
    if (current != null && _restoreGeneration == _generation) return current;
    _restoreGeneration = _generation;
    final future = _restore();
    _restoring = future;
    try {
      await future;
    } finally {
      if (identical(_restoring, future)) {
        _restoring = null;
        _restoreGeneration = null;
      }
    }
  }

  Future<void> _restore() async {
    if (_disposed || _ending) return;
    if (_tokens != null) {
      await revalidate();
      return;
    }
    final generation = _generation;
    if (_mustClearStore) {
      try {
        await _clear('Please sign in again.');
      } on ApiException {
        /* State explains secure-removal failure. */
      }
      return;
    }
    SessionTokens? saved;
    try {
      saved = await _withStore(store.read);
    } on ApiException catch (error) {
      if (_disposed || generation != _generation) return;
      if (error.kind == ApiErrorKind.unauthorized) {
        try {
          await _clear(error.message);
        } on ApiException {
          /* State explains secure-removal failure. */
        }
      } else {
        _emit(AuthState(SessionStatus.unavailable, message: error.message));
      }
      return;
    }
    if (_disposed || generation != _generation) return;
    _tokens = saved;
    if (saved != null) _issuedAccessTokens.add(saved.accessToken);
    if (saved == null) {
      _emit(const AuthState(SessionStatus.signedOut));
      return;
    }
    await revalidate();
  }

  Future<void> login(
    String email,
    String password, {
    bool rememberMe = false,
  }) async {
    if (_ending || _disposed) throw _signedOut;
    final generation = ++_generation;
    _tokens = null;
    _sessionUserId = null;
    _challenge = null;
    _issuedAccessTokens.clear();
    _mustClearStore = true;
    _emit(const AuthState(SessionStatus.signedOut));
    try {
      await _withStore(() async {
        if (!_disposed && generation == _generation) await store.clear();
      });
    } on ApiException catch (error) {
      if (!_disposed && generation == _generation) {
        _emit(AuthState(SessionStatus.unavailable, message: error.message));
      }
      rethrow;
    }
    if (_disposed || _ending || generation != _generation) return;
    _mustClearStore = false;
    final result = await repository.login(
      email,
      password,
      rememberMe: rememberMe,
    );
    if (_disposed || generation != _generation) return;
    if (result.challengeToken != null) {
      _challenge = result.challengeToken;
      _emit(const AuthState(SessionStatus.challenge));
    } else {
      await _accept(result, generation);
      await revalidate();
    }
  }

  Future<void> verifyTwoFactor(String code) async {
    final challenge = _challenge;
    if (challenge == null) {
      throw const ApiException(
        kind: ApiErrorKind.unauthorized,
        message:
            'Please sign in again to request a new verification challenge.',
      );
    }
    // Spring consumes the challenge before checking the code, even on failure.
    _challenge = null;
    final generation = _generation;
    try {
      final result = await repository.verifyTwoFactor(challenge, code);
      await _accept(result, generation);
      if (generation == _generation) await revalidate();
    } on ApiException catch (error) {
      if (generation == _generation) {
        _emit(
          AuthState(
            SessionStatus.signedOut,
            message: '${error.message} Sign in again to request a new code.',
          ),
        );
      }
      rethrow;
    }
  }

  Future<void> _accept(AuthResult result, int generation) async {
    if (result.tokens == null || result.user == null) {
      throw const ApiException(
        kind: ApiErrorKind.invalidResponse,
        message:
            'The service returned an incomplete session. Please sign in again.',
      );
    }
    if (_disposed || generation != _generation) return;
    try {
      await _withStore(() async {
        if (!_disposed && generation == _generation) {
          await store.write(result.tokens!);
        }
      });
    } on ApiException {
      if (!_disposed && generation == _generation) {
        await _clear('Secure session saving failed. Please sign in again.');
      }
      rethrow;
    }
    if (_disposed || generation != _generation) return;
    _tokens = result.tokens;
    _sessionUserId = result.user!.id;
    _mustClearStore = false;
    _issuedAccessTokens.add(result.tokens!.accessToken);
    _challenge = null;
    // Keep protected navigation closed until /auth/me validates the session.
  }

  Future<void> ensureFreshTokens() async {
    if (_ending || _disposed || _tokens == null) throw _signedOut;
    final generation = _generation;
    if (_tokens!.expiresSoon(_clock())) await _refresh();
    if (_tokens == null || generation != _generation) throw _signedOut;
  }

  Future<bool> _recover(String rejectedToken) async {
    if (_ending || _disposed || _tokens == null) return false;
    if (!_issuedAccessTokens.contains(rejectedToken)) return false;
    if (_tokens!.accessToken != rejectedToken) return true;
    final generation = _generation;
    await _refresh();
    return !_ending && generation == _generation && _tokens != null;
  }

  Future<void> _refresh() async {
    final current = _refreshing;
    if (current != null && _refreshGeneration == _generation) return current;
    _refreshGeneration = _generation;
    final future = _rotate();
    _refreshing = future;
    try {
      await future;
    } finally {
      if (identical(_refreshing, future)) {
        _refreshing = null;
        _refreshGeneration = null;
      }
    }
  }

  Future<void> _rotate() async {
    final tokens = _tokens;
    if (tokens == null) throw _signedOut;
    final generation = _generation;
    final expectedUser = _sessionUserId;
    try {
      // A consumed opaque token must never be restored after a process death.
      // Invalidate the saved pair before sending rotation; commit only its reply.
      await _withStore(store.clear);
      if (_disposed || generation != _generation) return;
      final result = await repository.refresh(tokens.refreshToken);
      if (expectedUser != null && result.user?.id != expectedUser) {
        throw const ApiException(
          kind: ApiErrorKind.invalidResponse,
          message: 'Unexpected refreshed account identity.',
        );
      }
      await _accept(result, generation);
    } on ApiException catch (error) {
      // The server may have consumed this token even if its reply was lost.
      // Never retry an ambiguous rotation with the old refresh token.
      if (generation == _generation) {
        await _clear(
          'Session renewal could not be confirmed. Please sign in again.',
        );
      }
      throw ApiException(
        kind: error.kind,
        statusCode: error.statusCode,
        message:
            'Session renewal could not be confirmed. Please sign in again.',
      );
    }
  }

  Future<void> revalidate({bool background = false}) async {
    if (_ending || _disposed) return;
    if (_tokens == null) {
      if (_state.status == SessionStatus.unavailable) await restore();
      return;
    }
    final current = _revalidating;
    if (current != null && _validationGeneration == _generation) return current;
    _validationGeneration = _generation;
    final future = _loadUser(background: background);
    _revalidating = future;
    try {
      await future;
    } finally {
      if (identical(_revalidating, future)) {
        _revalidating = null;
        _validationGeneration = null;
      }
    }
  }

  Future<void> _loadUser({required bool background}) async {
    final generation = _generation;
    // Picker dialogs can resume the app while an editor is awaiting a result.
    // Preserve an already validated screen during the background /me request.
    if (!background || _state.status != SessionStatus.authenticated) {
      _emit(const AuthState(SessionStatus.restoring));
    }
    try {
      final user = await repository.me();
      if (!_disposed && !_ending && generation == _generation) {
        if (_sessionUserId != null && user.id != _sessionUserId) {
          await _clear(
            'Account identity could not be verified. Please sign in again.',
          );
          return;
        }
        _sessionUserId = user.id;
        _showUser(user);
      }
    } on ApiException catch (error) {
      if (_disposed || generation != _generation) return;
      if (_tokens != null) {
        _emit(AuthState(SessionStatus.unavailable, message: error.message));
      }
    }
  }

  Future<void> selectRole(UserRole role) async {
    if (_state.status != SessionStatus.roleRequired) {
      throw const ApiException(
        kind: ApiErrorKind.forbidden,
        message: 'A role has already been selected.',
      );
    }
    final generation = _generation;
    final user = await repository.selectRole(role);
    if (!_disposed && generation == _generation) {
      if (user.id != _sessionUserId || user.role != role) {
        throw const ApiException(
          kind: ApiErrorKind.invalidResponse,
          message: 'Role confirmation returned an unexpected account or role. Check current account status.',
        );
      }
      _showUser(user);
    }
  }

  Future<void> cancelChallenge() => _clear();

  /// Server-confirmed password/deletion/all-session changes invalidate this device.
  Future<void> invalidateLocally(String message) => _clear(message);

  /// Session DTOs have no current-device marker; validate with real rotation.
  Future<void> recheckRefreshSession() async {
    if (_ending || _disposed || _tokens == null) throw _signedOut;
    await _refresh();
  }

  Future<void> logout() async {
    if (_ending) return;
    _ending = true;
    _emit(const AuthState(SessionStatus.restoring, message: 'Signing out…'));
    ApiException? failure;
    try {
      if (_refreshing != null && _refreshGeneration == _generation) {
        await _refreshing;
      }
      if (_tokens != null && _tokens!.expiresSoon(_clock())) await _refresh();
      if (_tokens != null) await repository.logout(_tokens!.refreshToken);
    } on ApiException catch (error) {
      failure = error;
    } finally {
      try {
        await _clear(
          failure == null ? 'You have signed out.' : 'Signed out on this device. Server revocation could not be confirmed.',
        );
      } on ApiException {
        // _clear exposes the failed secure removal through unavailable state.
      } finally {
        _ending = false;
      }
    }
  }

  Future<void> _reject(String token) async {
    if (!_disposed && !_ending && _issuedAccessTokens.contains(token)) {
      await _clear('Your session expired. Please sign in again.');
    }
  }

  Future<void> _clear([String? message]) async {
    if (_disposed) return;
    final generation = ++_generation;
    _tokens = null;
    _sessionUserId = null;
    _issuedAccessTokens.clear();
    _challenge = null;
    _mustClearStore = true;
    try {
      await _withStore(store.clear);
      if (generation == _generation) _mustClearStore = false;
    } on ApiException {
      if (!_disposed && generation == _generation) {
        _emit(
          const AuthState(
            SessionStatus.unavailable,
            message: 'Secure sign-out could not be completed. Retry to remove saved credentials.',
          ),
        );
      }
      rethrow;
    }
    if (!_disposed && generation == _generation) {
      _emit(AuthState(SessionStatus.signedOut, message: message));
    }
  }

  static const _signedOut = ApiException(
    kind: ApiErrorKind.unauthorized,
    message: 'Please sign in to continue.',
  );

  void dispose() {
    if ((_refreshing != null && _refreshGeneration == _generation) || _ending) {
      unawaited(_withStore(store.clear).catchError((Object _) {}));
    }
    _disposed = true;
    _issuedAccessTokens.clear();
    ++_generation;
    _challenge = null;
    _tokens = null;
    api.close();
    unawaited(_changes.close());
  }
}
