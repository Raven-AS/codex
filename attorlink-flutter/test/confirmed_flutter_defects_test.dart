import 'dart:async';
import 'dart:convert';

import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_client.dart';
import 'package:attorlink_flutter/core/network/api_exception.dart';
import 'package:attorlink_flutter/core/network/http_transport.dart';
import 'package:attorlink_flutter/features/auth/domain/auth_models.dart';
import 'package:attorlink_flutter/features/community/data/community_repository.dart';
import 'package:attorlink_flutter/features/community/presentation/comment_screen.dart';
import 'package:attorlink_flutter/features/community/presentation/connections_screen.dart';
import 'package:attorlink_flutter/features/community/presentation/post_detail.dart';
import 'package:attorlink_flutter/features/lawyer/data/lawyer_repository.dart';
import 'package:attorlink_flutter/features/lawyer/qualifications/data/qualifications_repository.dart';
import 'package:attorlink_flutter/features/lawyer/qualifications/domain/qualification_record.dart';
import 'package:attorlink_flutter/features/lawyer/qualifications/domain/qualification_schema.dart';
import 'package:attorlink_flutter/features/lawyer/qualifications/presentation/qualification_editor.dart';
import 'package:attorlink_flutter/features/lawyer/qualifications/presentation/qualifications_hub.dart';
import 'package:attorlink_flutter/features/messaging/data/chat_repository.dart';
import 'package:attorlink_flutter/features/notifications/data/notification_repository.dart';
import 'package:attorlink_flutter/features/notifications/presentation/notification_inbox.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'community_features_test.dart' as community;
import 'live_notifications_test.dart' as notices;
import 'support/qualification_contracts.dart';

Future<void> mount(WidgetTester tester, Widget child) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 1600);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

const lawyer = AuthUser(
  id: 7,
  email: 'fixture@example.invalid',
  role: UserRole.lawyer,
  status: UserStatus.active,
);

void main() {
  for (final entry in [
    (UserRole.client, 'ACCOUNT', 'USER', 7, false),
    (UserRole.lawyer, 'ACCOUNT', 'USER', 7, false),
    (UserRole.lawyer, 'FOLLOW', 'USER', 7, true),
    (UserRole.lawyer, 'FOLLOW', 'USER', 99, false),
    (UserRole.client, 'FOLLOW', 'USER', 7, false),
    (UserRole.lawyer, 'OTHER', 'USER', 7, false),
    (UserRole.client, 'OTHER', 'UNKNOWN', 1, false),
    (UserRole.client, 'POST', 'POST', 22, true),
    (UserRole.client, 'MESSAGE', 'CHAT_MESSAGE', 22, true),
    (UserRole.client, 'MESSAGE', 'CHAT_CONVERSATION', 22, true),
    (UserRole.client, 'VIDEO_CALL', 'VIDEO_CALL', 22, true),
    (UserRole.client, 'COMMENT', 'COMMENT', 22, true),
  ]) {
    testWidgets('notification dispatch $entry', (tester) async {
      AuthUser? user = entry.$1 == UserRole.lawyer ? lawyer : community.client;
      final wire = notices.Wire((r) {
        if (r.uri.path.endsWith('/unread-count')) {
          return notices.ok({'unreadCount': 0});
        }
        if (r.uri.path.endsWith('/notifications')) {
          return notices.ok(
            notices.page([
              {
                ...notices.notification(read: true),
                'type': entry.$2,
                'relatedEntityType': entry.$3,
                'relatedEntityId': entry.$4,
              },
            ]),
          );
        }
        if (r.uri.path.endsWith('/followers')) {
          return notices.ok(community.page([]));
        }
        // Unavailable resource must stay an honest error, not a successful detail.
        return const TransportResponse(
          statusCode: 404,
          body:
              '{"success":false,"message":"Resource unavailable","data":null}',
        );
      });
      final api = ApiClient(
        config: ApiConfig(baseUrl: Uri.parse('https://example.test/api/v1/')),
        transport: wire,
        accessTokenProvider: () => 'fixture',
      );
      final repo = NotificationRepository(
        api,
        ownerId: 7,
        currentUser: () => user,
      );
      final social = CommunityRepository(
        api,
        ownerId: 7,
        currentUser: () => user,
      );
      addTearDown(api.close);
      addTearDown(social.dispose);
      await mount(
        tester,
        NotificationInbox(
          repository: repo,
          chat: ChatRepository(api, ownerId: 7, currentUser: () => user),
          community: social,
        ),
      );
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(
        find.text('Open related area'),
        entry.$5 ? findsOneWidget : findsNothing,
      );
      if (entry.$2 == 'FOLLOW' && entry.$5) {
        await tester.tap(find.text('Open related area'));
        await tester.pumpAndSettle();
        expect(find.byType(CommunityConnections), findsOneWidget);
        expect(
          wire.requests.last.uri.path,
          '/api/v1/community/lawyers/7/followers',
        );
      } else if (entry.$3 == 'POST') {
        await tester.tap(find.text('Open related area'));
        await tester.pumpAndSettle();
        expect(find.byType(CommunityPostDetail), findsOneWidget);
        expect(find.text('Resource unavailable'), findsOneWidget);
      } else if (entry.$5) {
        // A logout while the detail dialog is open must reject its stale shortcut.
        user = null;
        await tester.tap(find.text('Open related area'));
        await tester.pumpAndSettle();
        expect(
          wire.requests.where((r) => !r.uri.path.contains('/notifications')),
          isEmpty,
        );
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final screen in ['qualification', 'comment', 'unfollow']) {
    testWidgets(
      '$screen confirmation is serialized, cancellable and session-bound',
      (tester) async {
        var generation = 0;
        final fixture = QualificationTestFixture(
          QualificationResource.education,
        );
        addTearDown(fixture.dispose);
        final wire = community.Wire((r) {
          if (r.method == 'DELETE') {
            return community.response(
              null,
              status: 400,
              message: 'Action rejected',
            );
          }
          return community.response(
            community.page(
              screen == 'comment'
                  ? [community.comment()]
                  : [
                      {'id': 1, 'followerId': 7, 'lawyerId': 42},
                    ],
            ),
          );
        });
        final api = ApiClient(
          config: ApiConfig(baseUrl: Uri.parse('https://example.test/api/v1/')),
          transport: wire,
          accessTokenProvider: () => 'fixture',
        );
        final social = CommunityRepository(
          api,
          ownerId: 7,
          currentUser: () => community.client,
          sessionGeneration: () => generation,
        );
        addTearDown(api.close);
        addTearDown(social.dispose);
        final originalServer = fixture.server;
        fixture.transport.respond = (r) => r.method == 'DELETE'
            ? community.response(null, status: 400, message: 'Action rejected')
            : originalServer(r);
        final qualifications = QualificationsRepository(
          LawyerRepository(
            fixture.api,
            ownerId: 7,
            currentUser: () => lawyer,
            sessionGeneration: () => generation,
          ),
        );
        final child = screen == 'qualification'
            ? QualificationsHub(repository: qualifications)
            : screen == 'comment'
            ? CommunityComments(repository: social, postId: 1)
            : CommunityConnections(repository: social);
        if (screen == 'qualification') {
          // Hub defaults to High Court. The fixture only supports education.
          fixture.transport.respond = (r) => r.uri.path.endsWith('/high-court')
              ? qualificationOk(null)
              : r.method == 'DELETE'
              ? community.response(
                  null,
                  status: 400,
                  message: 'Action rejected',
                )
              : originalServer(r);
        }
        await mount(tester, child);
        if (screen == 'qualification') {
          tester
              .widget<DropdownButtonFormField<QualificationResource>>(
                find.byType(DropdownButtonFormField<QualificationResource>),
              )
              .onChanged!(QualificationResource.education);
          await tester.pumpAndSettle();
          await tester.tap(find.text('LL.B'));
          await tester.pumpAndSettle();
        }
        final actionLabel = screen == 'qualification'
            ? 'Delete record'
            : screen == 'comment'
            ? 'Delete'
            : 'Unfollow';
        Future<void> openTwice() async {
          final finder = find.widgetWithText(TextButton, actionLabel);
          await tester.ensureVisible(finder);
          final action = tester.widget<TextButton>(finder).onPressed!;
          action();
          action();
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
        }

        await openTwice();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(
          [
            ...wire.requests,
            ...fixture.transport.requests,
          ].where((r) => r.method == 'DELETE'),
          isEmpty,
        );
        await openTwice();
        final confirmLabel = screen == 'unfollow' ? 'Unfollow' : 'Delete';
        await tester.tap(find.widgetWithText(FilledButton, confirmLabel));
        await tester.pumpAndSettle();
        expect(find.text('Action rejected'), findsOneWidget);
        final requests = screen == 'qualification'
            ? fixture.transport.requests
            : wire.requests;
        expect(requests.where((r) => r.method == 'DELETE'), hasLength(1));
        await openTwice();
        generation++; // Includes logging back into the same account.
        await tester.tap(find.widgetWithText(FilledButton, confirmLabel));
        await tester.pumpAndSettle();
        expect(requests.where((r) => r.method == 'DELETE'), hasLength(1));
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final resource in [
    QualificationResource.credentials,
    QualificationResource.highCourt,
  ]) {
    testWidgets('disposed $resource editor cannot mutate after preflight', (
      tester,
    ) async {
      final fixture = QualificationTestFixture(resource);
      addTearDown(fixture.dispose);
      final delayed = Completer<TransportResponse>();
      fixture.transport.respond = (_) => delayed.future;
      await mount(
        tester,
        QualificationEditor(
          repository: fixture.repository,
          resource: resource,
          initial: QualificationRecord.fromJson(resource, fixture.record),
          onSaved: (_) => fail('Disposed editor reported a save'),
          onReload: () {},
        ),
      );
      final save = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save record'),
          )
          .onPressed!;
      save();
      save();
      await tester.pump();
      expect(fixture.transport.requests, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      delayed.complete(
        qualificationOk(
          resource.schema.singleton ? fixture.record : [fixture.record],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        fixture.transport.requests.every((r) => r.method == 'GET'),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  }

  test('preflight preserves current attachments and rejects failure/session changes', () async {
    final fixture = QualificationTestFixture(QualificationResource.credentials);
    addTearDown(fixture.dispose);
    await fixture.repository.saveInformation(fixture.resource, {
      ...qualificationValues(fixture.resource),
      'documentUrl': 'https://example.test/stale.pdf',
    }, id: 1);
    final saved = jsonDecode(fixture.transport.requests.last.body!) as Map;
    expect(saved['documentUrl'], 'https://images.example.test/old.pdf');
    fixture.transport.requests.clear();
    fixture.transport.respond = (_) =>
        community.response(null, status: 500, message: 'Preflight failed');
    await expectLater(
      fixture.repository.saveInformation(
        fixture.resource,
        qualificationValues(fixture.resource),
        id: 1,
      ),
      throwsA(isA<ApiException>()),
    );
    expect(fixture.transport.requests.map((r) => r.method), ['GET']);
    fixture.transport.requests.clear();
    fixture.transport.respond = (r) {
      fixture.user = null;
      return fixture.server(r);
    };
    await expectLater(
      fixture.repository.saveInformation(
        fixture.resource,
        qualificationValues(fixture.resource),
        id: 1,
      ),
      throwsA(isA<ApiException>()),
    );
    expect(fixture.transport.requests.map((r) => r.method), ['GET']);
  });

  test(
    'save operation liveness is rechecked after asynchronous token work',
    () async {
      var active = true;
      final waiting = Completer<void>();
      final entered = Completer<void>();
      final wire = notices.Wire(
        (_) => fail('Abandoned save reached transport'),
      );
      final api = ApiClient(
        config: ApiConfig(baseUrl: Uri.parse('https://example.test/api/v1/')),
        transport: wire,
        accessTokenProvider: () => 'fixture',
        beforeAuthenticatedRequest: () {
          entered.complete();
          return waiting.future;
        },
      );
      addTearDown(api.close);
      final repository = QualificationsRepository(
        LawyerRepository(api, ownerId: 7, currentUser: () => lawyer),
      );
      final pending = repository.saveInformation(
        QualificationResource.education,
        qualificationValues(QualificationResource.education),
        checkOperation: () {
          if (!active) {
            throw const ApiException(
              kind: ApiErrorKind.forbidden,
              message: 'Editor closed',
            );
          }
        },
      );
      final rejected = expectLater(pending, throwsA(isA<ApiException>()));
      await entered.future;
      active = false;
      waiting.complete();
      await rejected;
      expect(wire.requests, isEmpty);
    },
  );
}
