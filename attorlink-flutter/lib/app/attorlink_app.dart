import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../core/config/api_config.dart';
import '../core/network/api_exception.dart';
import '../features/auth/data/android_session_store.dart';
import '../features/auth/domain/session_controller.dart';
import '../features/auth/presentation/auth_gate.dart';
import 'app_services.dart';
import 'app_theme.dart';
import 'live_updates.dart';
import '../features/auth/domain/auth_models.dart';
import '../features/notifications/domain/notification_models.dart';

class AttorlinkApp extends StatefulWidget {
  const AttorlinkApp({super.key, this.session, this.config});
  final ApiConfig? config;

  /// Injected controllers are owned by the caller (for tests/embedding).
  final SessionController? session;

  @override
  State<AttorlinkApp> createState() => _AttorlinkAppState();
}

class _AttorlinkAppState extends State<AttorlinkApp>
    with WidgetsBindingObserver {
  late final _config =
      widget.config ??
      ApiConfig.fromEnvironment(
        android: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
        productionBuild: !kDebugMode,
      );
  late final SessionController _session =
      widget.session ??
      SessionController(
        config: _config,
        store: sessionStoreFor(_config.baseUrl),
      );
  late final _live = LiveUpdates(
    config: _session.api.config,
    accessToken: _session.realtimeAccessToken,
    sessionGeneration: () => _session.generation,
    initiallyPaused:
        WidgetsBinding.instance.lifecycleState != null &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed,
    currentUserId: () => _session.state.status == SessionStatus.authenticated
        ? _session.state.user?.id
        : null,
    sessionChanges: _session.changes,
    readUnread: () async {
      final generation = _session.generation, owner = _session.state.user?.id;
      return (await _session.api.request(
        'GET',
        'notifications/unread-count',
        authenticated: true,
        accessGuard: () {
          if (_session.generation != generation ||
              owner == null ||
              _session.state.status != SessionStatus.authenticated ||
              _session.state.user?.id != owner) {
            throw const ApiException(
              kind: ApiErrorKind.unauthorized,
              message: 'The notification session has changed.',
            );
          }
        },
        decode: (value) => notificationCount(value, 'unreadCount'),
      )).data;
    },
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_session.restore());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_session.revalidate(background: true));
      _live.resume();
    } else {
      _live.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _live.dispose();
    if (widget.session == null) _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppServices(
    session: _session,
    live: _live,
    child: MaterialApp(
      title: 'Attorlink',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // Unknown/deep-link locations cannot bypass the session and role guard.
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => AuthGate(session: _session),
      ),
    ),
  );
}
