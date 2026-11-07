import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attorlink_flutter/app/attorlink_app.dart';
import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/http_transport.dart';
import 'package:attorlink_flutter/features/auth/data/session_store.dart';
import 'package:attorlink_flutter/features/auth/domain/session_controller.dart';

class _AuthTransport implements HttpTransport {
  final requests = <TransportRequest>[];
  _AuthTransport({this.profileStatus = 'COMPLETE'});
  var profileStatus = 'COMPLETE';
  var role = 'UNASSIGNED';

  Map<String, Object> get user => {
    'id': 1,
    'email': 'person@example.test',
    'role': role,
    'status': 'ACTIVE',
    'emailVerified': true,
  };

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    Object? data;
    switch (request.uri.path) {
      case '/api/v1/auth/login':
        final payload = base64Url.encode(
          utf8.encode(
            jsonEncode({
              'exp':
                  DateTime.now()
                      .add(const Duration(hours: 1))
                      .millisecondsSinceEpoch ~/
                  1000,
            }),
          ),
        );
        data = {
          'twoFactorRequired': false,
          'accessToken': 'header.$payload.signature',
          'refreshToken': 'test-refresh',
          'user': user,
        };
      case '/api/v1/auth/me':
        data = user;
      case '/api/v1/users/profile/role':
        role = (jsonDecode(request.body!) as Map)['role'] as String;
        data = user;
      case '/api/v1/client/profile':
        if (request.method == 'PUT') profileStatus = 'COMPLETE';
        data = {
          'id': 1,
          'userId': 1,
          'profileStatus': profileStatus,
          'email': 'person@example.test',
        };
      case '/api/v1/client/address':
        data = null;
      case '/api/v1/client/preferences':
        data = {
          'practiceAreas': [],
          'jurisdictions': [],
          'courts': [],
          'lawyerLanguages': [],
        };
      case '/api/v1/practice-areas':
      case '/api/v1/jurisdictions':
      case '/api/v1/courts':
        data = [];
      case '/api/v1/auth/logout':
        data = null;
      default:
        throw StateError('Unexpected auth endpoint ${request.uri.path}');
    }
    return TransportResponse(
      statusCode: 200,
      body: jsonEncode({'success': true, 'message': 'Success', 'data': data}),
    );
  }

  @override
  void close() {}
}

void main() {
  testWidgets(
    'signed-out navigation is guarded and validation sends no requests',
    (tester) async {
      final transport = _AuthTransport();
      final session = SessionController(
        config: ApiConfig.fromEnvironment(),
        store: MemorySessionStore(),
        transport: transport,
      );
      addTearDown(session.dispose);
      await tester.pumpWidget(AttorlinkApp(session: session));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to Attorlink'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(transport.requests, isEmpty);
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pushNamed('/private/deep-link');
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.text('Sign in to Attorlink'), findsOneWidget);
    },
  );

  testWidgets('login requires role selection then logout closes the shell', (
    tester,
  ) async {
    final transport = _AuthTransport();
    final session = SessionController(
      config: ApiConfig.fromEnvironment(),
      store: MemorySessionStore(),
      transport: transport,
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(AttorlinkApp(session: session));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('email')),
      'person@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('password-login')),
      'password1',
    );
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Choose your role'), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    await tester.tap(find.text('Continue as a client'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Attorlink'), findsOneWidget);
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    expect(find.text('Client profile'), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to Attorlink'), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(transport.requests.last.uri.path, '/api/v1/auth/logout');
  });
  testWidgets(
    'draft client completes optional onboarding before entering shell',
    (tester) async {
      final transport = _AuthTransport(profileStatus: 'DRAFT');
      final session = SessionController(
        config: ApiConfig.fromEnvironment(),
        store: MemorySessionStore(),
        transport: transport,
      );
      addTearDown(session.dispose);
      await tester.pumpWidget(AttorlinkApp(session: session));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('email')),
        'person@example.test',
      );
      await tester.enterText(
        find.byKey(const ValueKey('password-login')),
        'password1',
      );
      await tester.ensureVisible(find.text('Sign in'));
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue as a client'));
      await tester.pumpAndSettle();
      expect(find.text('Client setup · 1 of 4'), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      await tester.ensureVisible(find.text('Save and continue'));
      await tester.tap(find.text('Save and continue'));
      await tester.pumpAndSettle();
      expect(find.text('Client setup · 2 of 4'), findsOneWidget);
      await tester.ensureVisible(find.text('Skip for now'));
      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();
      expect(find.text('Client setup · 3 of 4'), findsOneWidget);
      await tester.ensureVisible(find.text('Skip for now'));
      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();
      expect(find.text('Client setup · 4 of 4'), findsOneWidget);
      await tester.ensureVisible(find.text('Finish onboarding'));
      await tester.tap(find.text('Finish onboarding'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Attorlink'), findsOneWidget);
      expect(
        transport.requests.any(
          (r) => r.uri.path.endsWith('/client/profile') && r.method == 'PUT',
        ),
        true,
      );
    },
  );
}
