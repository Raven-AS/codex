import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_client.dart';
import 'package:attorlink_flutter/core/network/api_exception.dart';
import 'package:attorlink_flutter/core/network/http_transport.dart';
import 'package:attorlink_flutter/features/auth/domain/auth_models.dart';
import 'package:attorlink_flutter/features/messaging/data/chat_repository.dart';
import 'package:attorlink_flutter/features/messaging/domain/chat_models.dart';
import 'package:attorlink_flutter/features/messaging/domain/chat_timeline.dart';
import 'package:attorlink_flutter/features/messaging/presentation/chat_thread.dart';
import 'package:attorlink_flutter/features/messaging/presentation/chat_access.dart';

// Fixtures only: no successful response is substituted in production.
const stamp = '2026-11-04T12:00:00.000000001';
Map<String, Object?> conversation({
  String status = 'ACCEPTED',
  bool incoming = false,
}) => {
  'id': 9,
  'participantAId': incoming ? 42 : 7,
  'participantBId': incoming ? 7 : 42,
  'initiatedByUserId': incoming ? 42 : 7,
  'conversationType': 'CLIENT_LAWYER',
  'requestStatus': status,
  'lastMessageAt': stamp,
  'createdAt': stamp,
  'updatedAt': stamp,
  'unreadCount': 2,
};
Map<String, Object?> message({
  int id = 1,
  int sender = 42,
  String status = 'SENT',
  String created = stamp,
  String? updated,
  String? deleted,
  String text = 'Hello',
}) => {
  'id': id,
  'conversationId': 9,
  'senderId': sender,
  'messageType': 'TEXT',
  'text': text,
  'createdAt': created,
  'updatedAt': updated ?? created,
  'editedAt': updated,
  'deletedAt': deleted,
  'deliveryStatus': status,
  'isEdited': updated != null,
  'isDeleted': deleted != null,
};
Map<String, Object?> page(
  List<Object?> rows, {
  int number = 0,
  int pages = 1,
}) => {
  'content': rows,
  'page': number,
  'size': 20,
  'totalElements': rows.length,
  'totalPages': pages,
};
TransportResponse response(
  Object? data, {
  int status = 200,
  String error = 'Denied',
}) => TransportResponse(
  statusCode: status,
  body: jsonEncode({
    'success': status == 200,
    'message': status == 200 ? 'Success' : error,
    'data': data,
  }),
);

class Wire implements HttpTransport {
  Wire(this.handler);
  final FutureOr<TransportResponse> Function(TransportRequest) handler;
  final requests = <TransportRequest>[];
  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    return handler(request);
  }

  @override
  void close() {}
}

const user = AuthUser(
  id: 7,
  email: 'fixture@example.invalid',
  role: UserRole.client,
  status: UserStatus.active,
);
ChatRepository repository(
  Wire wire, {
  AuthUser? Function()? current,
  Stream<Object?>? changes,
}) => ChatRepository(
  ApiClient(
    config: ApiConfig(baseUrl: Uri.parse('https://example.test/api/v1/')),
    transport: wire,
    accessTokenProvider: () => 'fixture-token',
  ),
  ownerId: 7,
  currentUser: current ?? () => user,
  accessChanges: changes,
);
Matcher apiError(ApiErrorKind kind) =>
    isA<ApiException>().having((e) => e.kind, 'kind', kind);

void main() {
  test('normalized participant order preserves intended request recipient', () {
    final normalized = ChatConversation.fromJson({
      ...conversation(status: 'PENDING'),
      'participantAId': 7,
      'participantBId': 42,
      'initiatedByUserId': 42,
    });
    expect(normalized.canDecide(7), isTrue);
    expect(normalized.canDecide(42), isFalse);
    expect(normalized.canDecide(99), isFalse);
    final unknown = ChatConversation.fromJson({
      ...conversation(status: 'PENDING'),
      'initiatedByUserId': null,
    });
    expect(unknown.canDecide(42), isFalse);
  });

  test('existing sync DTO reconciles older message receipt/edit versions and opaque deletion cursors', () {
    const old = '2026-11-04T11:00:00';
    final timeline = ChatTimeline(9);
    timeline.history([
      ChatMessage.fromJson(message(id: 1, created: old)),
      ChatMessage.fromJson(message(id: 2)),
    ], seed: true);
    timeline.apply(
      ChatSync.fromJson({
        'conversationId': 9,
        'nextCursorMessageId': 1,
        'nextCursorCreatedAt': '2026-11-04T13:00:00',
        'hasMore': false,
        'messages': [
          {
            ...message(
              id: 1,
              created: old,
              updated: '2026-11-04T13:00:00',
              status: 'SEEN',
            ),
            'editedAt': null,
            'isEdited': false,
          },
        ],
        'tombstones': [],
      }),
    );
    expect(timeline.messages.first.status, 'SEEN');
    expect(timeline.messages.first.edited, isFalse);
    timeline.apply(
      ChatSync.fromJson({
        'conversationId': 9,
        'nextCursorMessageId': 1,
        'nextCursorCreatedAt': '2026-11-04T14:00:00',
        'hasMore': false,
        'messages': [
          message(
            id: 1,
            created: old,
            updated: '2026-11-04T14:00:00',
            text: 'Edited',
            status: 'SEEN',
          ),
        ],
        'tombstones': [],
      }),
    );
    expect(timeline.messages.first.text, 'Edited');
    timeline.apply(
      ChatSync.fromJson({
        'conversationId': 9,
        'nextCursorMessageId': 1,
        'nextCursorCreatedAt': '2026-11-04T15:00:00.000001',
        'hasMore': false,
        'messages': [],
        'tombstones': [
          {'id': 1, 'conversationId': 9, 'deletedAt': '2026-11-04T15:00:00'},
        ],
      }),
    );
    expect(timeline.messages.map((m) => m.id), [2]);
    expect(timeline.cursor!.timestamp, '2026-11-04T15:00:00.000001');
  });

  test('6A inbox/request/start contracts, intended recipient and session/privacy guards', () async {
    AuthUser? current = user;
    final wire = Wire((request) {
      if (request.method == 'GET') {
        return response(
          page([conversation(status: 'PENDING')], number: 2, pages: 4),
        );
      }
      if (request.uri.path.endsWith('/accept')) {
        return response(conversation(incoming: true));
      }
      if (request.uri.path.endsWith('/reject')) {
        return response(conversation(status: 'REJECTED', incoming: true));
      }
      return response(conversation(status: 'PENDING'));
    });
    final repo = repository(wire, current: () => current);
    for (final tab in ChatInbox.values) {
      await repo.inbox(tab, page: 2);
      expect(wire.requests.last.uri.path, '/api/v1/chat/${tab.path}');
      expect(wire.requests.last.uri.queryParameters, {
        'page': '2',
        'size': '20',
      });
    }
    final pending = await repo.start(42, 'Request text');
    expect(pending.status, 'PENDING');
    expect(jsonDecode(wire.requests.last.body!), {
      'recipientUserId': 42,
      'firstMessageText': 'Request text',
    });
    final incoming = ChatConversation.fromJson(
      conversation(status: 'PENDING', incoming: true),
    );
    await repo.decide(incoming, accept: true);
    expect(wire.requests.last.uri.path, '/api/v1/chat/conversations/9/accept');
    await repo.decide(incoming, accept: false);
    expect(wire.requests.last.uri.path, '/api/v1/chat/conversations/9/reject');
    final count = wire.requests.length;
    await expectLater(
      repo.decide(pending, accept: true),
      throwsA(apiError(ApiErrorKind.forbidden)),
    );
    await expectLater(
      repo.start(7, ''),
      throwsA(apiError(ApiErrorKind.validation)),
    );
    current = null;
    await expectLater(
      repo.inbox(ChatInbox.all),
      throwsA(apiError(ApiErrorKind.forbidden)),
    );
    expect(wire.requests, hasLength(count));
    expect(
      wire.requests.every(
        (r) => r.headers['Authorization'] == 'Bearer fixture-token',
      ),
      isTrue,
    );
    final privacy = Wire(
      (_) => response(
        null,
        status: 400,
        error: 'Only users who follow this lawyer may request a conversation',
      ),
    );
    await expectLater(
      repository(privacy).start(42, ''),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'privacy',
          contains('follow'),
        ),
      ),
    );
    expect(privacy.requests, hasLength(1));
  });

  test(
    '6A accepted text CRUD and actual recipient/read acknowledgements',
    () async {
      final wire = Wire((r) {
        if (r.uri.path.endsWith('/read')) {
          return response({
            'conversationId': 9,
            'lastReadMessageId': 1,
            'markedSeenCount': 2,
          });
        }
        return response(
          message(
            id: r.uri.path.contains('/messages/1') ? 1 : 2,
            sender:
                r.uri.path.endsWith('/delivered') ||
                    r.uri.path.endsWith('/seen')
                ? 42
                : 7,
            status: r.uri.path.endsWith('/seen')
                ? 'SEEN'
                : r.uri.path.endsWith('/delivered')
                ? 'DELIVERED'
                : 'SENT',
            deleted: r.method == 'DELETE' ? '2026-11-04T12:01:00' : null,
          ),
        );
      });
      final repo = repository(wire),
          accepted = ChatConversation.fromJson(conversation());
      final sent = await repo.send(accepted, 'Draft text');
      expect(jsonDecode(wire.requests.last.body!), {'text': 'Draft text'});
      expect(sent.id, 2);
      expect(sent.status, 'SENT');
      await repo.change(accepted, sent, text: 'Edited');
      expect(wire.requests.last.method, 'PATCH');
      final deleted = await repo.change(accepted, sent);
      expect(wire.requests.last.method, 'DELETE');
      expect(deleted.deleted, isTrue);
      expect(deleted.text, isNull);
      final incoming = ChatMessage.fromJson(message());
      expect(
        (await repo.acknowledge(9, incoming, seen: false)).status,
        'DELIVERED',
      );
      expect(
        wire.requests.last.uri.path,
        '/api/v1/chat/conversations/9/messages/1/delivered',
      );
      expect((await repo.acknowledge(9, incoming, seen: true)).status, 'SEEN');
      expect((await repo.markRead(9, incoming)).markedSeenCount, 2);
      expect(jsonDecode(wire.requests.last.body!), {'lastReadMessageId': 1});
      final count = wire.requests.length;
      await expectLater(
        repo.send(
          ChatConversation.fromJson(conversation(status: 'PENDING')),
          'Blocked',
        ),
        throwsA(apiError(ApiErrorKind.forbidden)),
      );
      await expectLater(
        repo.change(accepted, incoming, text: 'No'),
        throwsA(apiError(ApiErrorKind.forbidden)),
      );
      await expectLater(
        repo.acknowledge(9, sent, seen: true),
        throwsA(apiError(ApiErrorKind.forbidden)),
      );
      await expectLater(
        repo.markRead(9, sent),
        throwsA(apiError(ApiErrorKind.validation)),
      );
      expect(wire.requests, hasLength(count));
    },
  );

  test('6A stable timeline preserves nanosecond cursors and tombstones without resurrection', () {
    final timeline = ChatTimeline(9);
    expect(timeline.cursor, isNull); // No fabricated zero/epoch cursor.
    timeline.history([
      ChatMessage.fromJson(message(id: 5)),
      ChatMessage.fromJson(message(id: 80)),
    ], seed: true);
    expect(timeline.cursor!.id, 80);
    expect(timeline.cursor!.timestamp, stamp);
    timeline.merge(
      ChatMessage.fromJson(
        message(
          id: 5,
          text: 'Edited',
          updated: '2026-11-04T12:00:00.000000008',
        ),
      ),
    );
    timeline.history([ChatMessage.fromJson(message(id: 5, text: 'Stale'))]);
    expect(timeline.messages.first.text, 'Edited');
    final sync = ChatSync.fromJson({
      'conversationId': 9,
      'nextCursorMessageId': 5,
      'nextCursorCreatedAt': '2026-11-04T12:00:00.000000009',
      'hasMore': false,
      'messages': [],
      'tombstones': [
        {
          'id': 5,
          'conversationId': 9,
          'deletedAt': '2026-11-04T12:00:00.000000009',
        },
      ],
    });
    timeline.apply(sync);
    expect(
      timeline.cursor!.id,
      5,
    ); // An older ID can be the latest deletion event.
    expect(timeline.messages.map((m) => m.id), [80]);
    expect(timeline.tombstones.single.id, 5);
    timeline.history([
      ChatMessage.fromJson(message(id: 5, text: 'Must stay deleted')),
    ]);
    expect(timeline.messages.map((m) => m.id), [80]);
    timeline.resetHistory();
    timeline.history([]);
    expect(timeline.cursor!.timestamp, '2026-11-04T12:00:00.000000009');
    expect(timeline.tombstones.single.id, 5);
  });

  test('6A history and sync use independent pages and exact validated server cursors', () async {
    final wire = Wire(
      (r) => response(
        r.uri.path.endsWith('/sync')
            ? {
                'conversationId': 9,
                'nextCursorMessageId': 1,
                'nextCursorCreatedAt': stamp,
                'hasMore': false,
                'messages': [],
                'tombstones': [],
              }
            : page([message()], number: 3, pages: 5),
      ),
    );
    final repo = repository(wire);
    await repo.history(9, page: 3);
    expect(wire.requests.last.uri.queryParameters, {'page': '3', 'size': '20'});
    final conversationModel = ChatConversation.fromJson(conversation());
    final cursor = ChatCursor(1, stamp);
    final sync = await repo.sync(conversationModel, cursor);
    expect(sync.cursor.timestamp, stamp);
    expect(wire.requests.last.uri.path, '/api/v1/chat/conversations/9/sync');
    expect(wire.requests.last.uri.queryParameters, {
      'lastMessageId': '1',
      'lastEventTimestamp': stamp,
      'limit': '50',
    });
    await expectLater(
      repo.sync(conversationModel, cursor, limit: 201),
      throwsA(apiError(ApiErrorKind.validation)),
    );
    final malformed = Wire(
      (_) => response({
        'conversationId': 9,
        'nextCursorMessageId': 1,
        'nextCursorCreatedAt': stamp,
        'hasMore': true,
        'messages': [],
        'tombstones': [],
      }),
    );
    await expectLater(
      repository(malformed).sync(conversationModel, cursor),
      throwsA(apiError(ApiErrorKind.invalidResponse)),
    );
  });

  testWidgets(
    '6A pending composer, uncertain draft and expired-session routes stay guarded',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1100);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AuthUser? actor = user;
      final changes = StreamController<Object?>.broadcast();
      addTearDown(changes.close);
      var accepted = false;
      final wire = Wire((r) {
        if (r.uri.path.endsWith('/accept')) {
          accepted = true;
          return response(conversation(incoming: true));
        }
        if (r.uri.path.endsWith('/messages')) {
          if (r.method == 'POST') {
            throw const ApiException(
              kind: ApiErrorKind.network,
              message: 'Connection unavailable',
            );
          }
          return response(page([message()]));
        }
        return response(
          conversation(
            status: accepted ? 'ACCEPTED' : 'PENDING',
            incoming: true,
          ),
        );
      });
      final chat = repository(
        wire,
        current: () => actor,
        changes: changes.stream,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ChatThreadScreen(repository: chat, conversationId: 9),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('chat-composer')))
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Send'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Accept request'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('chat-composer')))
            .enabled,
        isTrue,
      );
      await tester.enterText(
        find.byKey(const ValueKey('chat-composer')),
        'Preserved draft',
      );
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(find.text('Connection unavailable'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('chat-composer')))
            .controller!
            .text,
        'Preserved draft',
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Send'))
            .onPressed,
        isNull,
      );
      expect(
        wire.requests.where(
          (r) => r.method == 'POST' && r.uri.path.endsWith('/messages'),
        ),
        hasLength(1),
      );
      unawaited(
        showDialog<String>(
          context: tester.element(find.byType(ChatThreadScreen)),
          builder: (_) =>
              ChatTextDialog(repository: chat, text: 'Private edit'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'Private edit',
      );
      actor = null;
      changes.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byKey(const ValueKey('chat-composer')), findsNothing);
      expect(
        find.textContaining('Sign in with an active client or lawyer'),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
