import 'dart:async';
import 'dart:convert';

import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_client.dart';
import 'package:attorlink_flutter/core/network/api_exception.dart';
import 'package:attorlink_flutter/features/auth/domain/auth_models.dart';
import 'package:attorlink_flutter/features/client/data/client_repository.dart';
import 'package:attorlink_flutter/features/client/domain/client_models.dart';
import 'package:attorlink_flutter/features/client/domain/client_validation.dart';
import 'package:attorlink_flutter/features/client/presentation/address_editor.dart';
import 'package:attorlink_flutter/features/client/presentation/client_widgets.dart';
import 'package:attorlink_flutter/features/client/presentation/photo_editor.dart';
import 'package:attorlink_flutter/features/lawyer/data/lawyer_repository.dart';
import 'package:attorlink_flutter/features/lawyer/practice/data/practice_repository.dart';
import 'package:attorlink_flutter/features/lawyer/practice/domain/practice_schema.dart';
import 'package:attorlink_flutter/features/lawyer/presentation/bar_council_editor.dart';
import 'package:attorlink_flutter/features/lawyer/presentation/council_documents.dart';
import 'package:attorlink_flutter/features/lawyer/qualifications/data/qualifications_repository.dart';
import 'package:attorlink_flutter/features/lawyer/qualifications/domain/qualification_schema.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/client_contracts.dart';
import 'support/lawyer_contracts.dart';

final _forbidden = throwsA(
  isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.forbidden),
);

void main() {
  for (final resource in ['client', 'lawyer', 'qualifications', 'practice']) {
    test(
      '$resource cannot send under a replacement session after token work',
      () async {
        var generation = 1;
        final wire = LawyerTestTransport();
        final api = ApiClient(
          config: ApiConfig(
            baseUrl: Uri.parse('https://api.example.test/api/v1/'),
          ),
          transport: wire,
          accessTokenProvider: () => 'fixture-access',
          beforeAuthenticatedRequest: () async {
            generation++;
          },
        );
        addTearDown(api.close);
        final role = resource == 'client' ? UserRole.client : UserRole.lawyer;
        final user = AuthUser(
          id: 7,
          email: 'fixture@example.test',
          role: role,
          status: UserStatus.active,
        );
        final lawyer = LawyerRepository(
          api,
          ownerId: 7,
          currentUser: () => user,
          sessionGeneration: () => generation,
        );
        final client = ClientRepository(
          api,
          ownerId: 7,
          currentUser: () => user,
          sessionGeneration: () => generation,
        );
        final Future<Object?> operation = switch (resource) {
          'client' => client.saveAddress({'city': 'Dhaka'}),
          'lawyer' => lawyer.saveProfile({'firstName': 'Updated'}),
          'qualifications' => QualificationsRepository(lawyer).save(
            QualificationResource.experience,
            {'organization': 'Firm', 'position': 'Advocate'},
          ),
          _ => PracticeRepository(
            lawyer,
          ).save(PracticeResource.languages, {'language': 'Bangla'}),
        };
        await expectLater(operation, _forbidden);
        expect(wire.requests, isEmpty);
      },
    );
  }

  test(
    '401 recovery cannot replay a profile mutation across sessions',
    () async {
      var generation = 1;
      var rejected = false;
      final wire = LawyerTestTransport()..respond = (_) => lawyerFailure(401);
      final api = ApiClient(
        config: ApiConfig(
          baseUrl: Uri.parse('https://api.example.test/api/v1/'),
        ),
        transport: wire,
        accessTokenProvider: () => 'fixture-access',
        recoverAuthentication: (_) async {
          generation++;
          return true;
        },
        onSessionRejected: (_) async {
          rejected = true;
        },
      );
      addTearDown(api.close);
      final fixture = LawyerTestFixture();
      addTearDown(fixture.dispose);
      final repo = LawyerRepository(
        api,
        ownerId: 7,
        currentUser: () => fixture.user,
        sessionGeneration: () => generation,
      );
      await expectLater(repo.saveProfile({'firstName': 'Updated'}), _forbidden);
      expect(wire.requests, hasLength(1));
      expect(rejected, false);
    },
  );

  test(
    'stale responses are rejected before their fields are decoded',
    () async {
      final fixture = ClientTestFixture();
      addTearDown(fixture.dispose);
      final response = Completer<void>();
      fixture.transport.respond = (_) async {
        await response.future;
        return clientOk({'invalid': 'must not decode for a different account'});
      };
      final pending = fixture.repository.profile();
      final assertion = expectLater(pending, _forbidden);
      fixture.user = null;
      response.complete();
      await assertion;
    },
  );

  testWidgets(
    'small saved coordinates remain editable and round-trip unchanged',
    (tester) async {
      final fixture = ClientTestFixture();
      addTearDown(fixture.dispose);
      final address = {
        'id': 31,
        'latitude': 0.0000001,
        'longitude': -0.0000001,
      };
      fixture.transport.respond = (_) => clientOk(address);
      final model = ClientAddress.fromJson(address);
      expect(model.text('latitude'), '0.0000001');
      expect(ClientValidation.coordinate(model.text('longitude')), isNull);
      var saved = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddressEditor(
              repository: fixture.repository,
              onSaved: () {
                saved = true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.widgetWithText(FilledButton, 'Save address');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(saved, true);
      final put = fixture.transport.requests.singleWhere(
        (r) => r.method == 'PUT',
      );
      expect(jsonDecode(put.body!)['latitude'], 0.0000001);
      expect(jsonDecode(put.body!)['longitude'], -0.0000001);
    },
  );

  test('invalid education year range is rejected before sending', () async {
    final fixture = LawyerTestFixture();
    addTearDown(fixture.dispose);
    await expectLater(
      QualificationsRepository(fixture.repository).save(
        QualificationResource.education,
        {'degree': 'LL.B', 'startYear': 2025, 'endYear': 2020},
      ),
      throwsA(
        isA<ApiException>().having(
          (e) => e.fieldErrors['endYear'],
          'endYear',
          isNotNull,
        ),
      ),
    );
    expect(fixture.transport.requests, isEmpty);
  });

  testWidgets('closing council editor during preservation GET prevents PUT', (
    tester,
  ) async {
    final fixture = LawyerTestFixture();
    addTearDown(fixture.dispose);
    final barrier = Completer<void>();
    var gets = 0;
    fixture.transport.respond = (_) async {
      if (++gets > 1) await barrier.future;
      return lawyerOk(councilRecordJson());
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BarCouncilEditor(
            repository: fixture.repository,
            onSaved: (_) => fail('Detached save callback'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, 'Save Bar Council record');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(gets, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    barrier.complete();
    await tester.pumpAndSettle();
    expect(fixture.transport.requests.where((r) => r.method == 'PUT'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'uncertain photo deletion requires refresh and adopts refreshed URL',
    (tester) async {
      var deletes = 0;
      var photo = 'https://images.example.test/photo.jpg';
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return PhotoEditor.forUpload(
                  photo: photo.isEmpty ? null : photo,
                  upload: (_) async => throw StateError('No upload expected'),
                  remove: () async {
                    deletes++;
                    throw const ApiException(
                      kind: ApiErrorKind.timeout,
                      message: 'Fixture timeout',
                    );
                  },
                  onChanged: () async {
                    rebuild(() => photo = '');
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove current photo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(deletes, 1);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Remove current photo'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Refresh profile'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ProfilePhoto>(find.byType(ProfilePhoto)).url,
        isNull,
      );
      expect(find.text('Remove current photo'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Choose photo'),
            )
            .onPressed,
        isNotNull,
      );
      expect(deletes, 1);
    },
  );

  testWidgets('uncertain council deletion requires authoritative refresh', (
    tester,
  ) async {
    final fixture = LawyerTestFixture();
    addTearDown(fixture.dispose);
    fixture.transport.respond = (r) {
      if (r.method == 'DELETE') {
        throw const ApiException(
          kind: ApiErrorKind.network,
          message: 'Fixture connection loss',
        );
      }
      return lawyerOk(councilRecordJson());
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CouncilDocuments(
            repository: fixture.repository,
            onChanged: (_) {},
            onEditRecord: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final remove = find.text('Remove document');
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Refresh record'), findsOneWidget);
    expect(find.text('Remove document'), findsNothing);
    await tester.tap(find.text('Refresh record'));
    await tester.pumpAndSettle();
    expect(find.text('Remove document'), findsOneWidget);
    expect(
      fixture.transport.requests.where((r) => r.method == 'DELETE'),
      hasLength(1),
    );
  });

  testWidgets('server validation on non-form properties is visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ClientErrorNotice(
            error: ApiException(
              kind: ApiErrorKind.validation,
              message: 'Validation failed',
              fieldErrors: {
                'yearRangeValid':
                    'Start year must be before or equal to end year',
              },
            ),
          ),
        ),
      ),
    );
    expect(
      find.textContaining('Start year must be before or equal to end year'),
      findsOneWidget,
    );
  });
}
