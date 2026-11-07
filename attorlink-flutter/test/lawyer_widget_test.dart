import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attorlink_flutter/app/attorlink_app.dart';
import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/features/auth/data/session_store.dart';
import 'package:attorlink_flutter/features/auth/domain/session_controller.dart';
import 'package:attorlink_flutter/features/lawyer/domain/lawyer_models.dart';
import 'package:attorlink_flutter/features/lawyer/presentation/lawyer_profile_editor.dart';
import 'package:attorlink_flutter/features/lawyer/presentation/verification_panel.dart';

import 'support/lawyer_contracts.dart';

void main() {
  testWidgets('missing saved requirements disable submission', (tester) async {
    final fixture = LawyerTestFixture();
    addTearDown(fixture.dispose);
    fixture.transport.respond = (r) => r.uri.path.endsWith('/bar-council')
        ? lawyerOk(null)
        : lawyerOk({
            ...lawyerProfileJson(),
            'firstName': null,
            'barRegistrationNumber': null,
          });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VerificationPanel(
            repository: fixture.repository,
            onSnapshot: (_) {},
            onEditPersonal: () {},
            onEditProfessional: () {},
            onEditCouncil: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Required before submission'), findsNWidgets(3));
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Submit for verification'),
    );
    expect(button.onPressed, isNull);
    expect(fixture.transport.requests.any((r) => r.method == 'POST'), false);
  });

  testWidgets(
    'submission displays SUBMITTED and never claims administrator approval',
    (tester) async {
      final fixture = LawyerTestFixture();
      addTearDown(fixture.dispose);
      var status = 'DRAFT';
      fixture.transport.respond = (r) {
        if (r.uri.path.endsWith('/submit')) {
          status = 'SUBMITTED';
          return lawyerOk({
            'lawyerProfileId': 11,
            'profileStatus': status,
            'message': 'Submitted for administrator review.',
          });
        }
        return r.uri.path.endsWith('/bar-council')
            ? lawyerOk(councilRecordJson())
            : lawyerOk(lawyerProfileJson(status: status));
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VerificationPanel(
              repository: fixture.repository,
              onSnapshot: (_) {},
              onEditPersonal: () {},
              onEditProfessional: () {},
              onEditCouncil: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Submit for verification'));
      await tester.tap(find.text('Submit for verification'));
      await tester.pumpAndSettle();
      expect(find.text('Profile status: SUBMITTED'), findsOneWidget);
      expect(find.text('Submitted for administrator review.'), findsOneWidget);
      expect(find.text('Profile status: VERIFIED'), findsNothing);
      final posts = fixture.transport.requests
          .where((r) => r.method == 'POST')
          .toList();
      expect(posts.length, 1);
      expect(posts.single.body, isNull);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Submit for verification'),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'invalid professional experience is rejected before sending PUT',
    (tester) async {
      final fixture = LawyerTestFixture();
      addTearDown(fixture.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LawyerProfileEditor(
              repository: fixture.repository,
              profile: LawyerProfile.fromJson(lawyerProfileJson()),
              personal: false,
              onSaved: (_) {},
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('lawyer-yearsOfExperience')),
        '71',
      );
      await tester.ensureVisible(find.text('Save information'));
      await tester.tap(find.text('Save information'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a whole number from 0 to 70.'), findsOneWidget);
      expect(fixture.transport.requests, isEmpty);
    },
  );

  testWidgets(
    'authenticated lawyer enters onboarding and can open unverified account',
    (tester) async {
      final fixture = LawyerTestFixture();
      fixture.transport.respond = (r) {
        final user = {
          'id': 7,
          'email': 'lawyer@example.test',
          'role': 'LAWYER',
          'status': 'ACTIVE',
        };
        if (r.uri.path.endsWith('/auth/login')) {
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
          return lawyerOk({
            'twoFactorRequired': false,
            'accessToken': 'h.$payload.s',
            'refreshToken': 'test-refresh',
            'user': user,
          });
        }
        if (r.uri.path.endsWith('/auth/me')) return lawyerOk(user);
        return r.uri.path.endsWith('/bar-council')
            ? lawyerOk(councilRecordJson())
            : lawyerOk(lawyerProfileJson());
      };
      final session = SessionController(
        config: ApiConfig.fromEnvironment(),
        store: MemorySessionStore(),
        transport: fixture.transport,
      );
      addTearDown(session.dispose);
      addTearDown(fixture.dispose);
      await tester.pumpWidget(AttorlinkApp(session: session));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('email')),
        'lawyer@example.test',
      );
      await tester.enterText(
        find.byKey(const ValueKey('password-login')),
        'password1',
      );
      await tester.ensureVisible(find.text('Sign in'));
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Lawyer setup · 1 of 4'), findsOneWidget);
      expect(find.text('Personal information'), findsOneWidget);
      await tester.tap(find.text('Continue to lawyer account'));
      await tester.pumpAndSettle();
      expect(find.text('Lawyer profile'), findsOneWidget);
      expect(find.text('Profile verification: DRAFT'), findsOneWidget);
      expect(
        fixture.transport.requests.any((r) => r.uri.path.endsWith('/submit')),
        false,
      );
    },
  );
}
