import '../domain/auth_models.dart';

/// No disk/browser storage fallback: replace only with vetted OS-backed storage.
abstract interface class SessionStore {
  Future<SessionTokens?> read();
  Future<void> write(SessionTokens tokens);
  Future<void> clear();
}

/// Marker for a platform implementation that protects tokens at rest.
abstract interface class PersistentSessionStore implements SessionStore {}

class MemorySessionStore implements SessionStore {
  SessionTokens? _tokens;
  @override
  Future<SessionTokens?> read() async => _tokens;
  @override
  Future<void> write(SessionTokens tokens) async {
    _tokens = tokens;
  }

  @override
  Future<void> clear() async {
    _tokens = null;
  }
}

// Survives widget-tree recreation during this process, never a process restart.
final runtimeSessionStore = MemorySessionStore();
