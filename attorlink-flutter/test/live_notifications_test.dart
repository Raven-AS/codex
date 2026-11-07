import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attorlink_flutter/app/live_updates.dart';
import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_client.dart';
import 'package:attorlink_flutter/core/network/api_exception.dart';
import 'package:attorlink_flutter/core/network/http_transport.dart';
import 'package:attorlink_flutter/core/realtime/socket_link.dart';
import 'package:attorlink_flutter/core/realtime/stomp_codec.dart';
import 'package:attorlink_flutter/features/auth/domain/auth_models.dart';
import 'package:attorlink_flutter/features/community/data/community_repository.dart';
import 'package:attorlink_flutter/features/messaging/data/chat_repository.dart';
import 'package:attorlink_flutter/features/messaging/domain/chat_models.dart';
import 'package:attorlink_flutter/features/messaging/domain/chat_timeline.dart';
import 'package:attorlink_flutter/features/messaging/presentation/chat_inbox.dart';
import 'package:attorlink_flutter/features/notifications/data/notification_repository.dart';
import 'package:attorlink_flutter/features/notifications/domain/notification_models.dart';
import 'package:attorlink_flutter/features/notifications/presentation/notification_inbox.dart';

// Fixtures only; production connects to the actual configured service.
const user = AuthUser(
  id: 7,
  email: 'fixture@example.invalid',
  role: UserRole.client,
  status: UserStatus.active,
);
Map<String, Object?> notification({int id = 1, bool read = false}) => {
  'id': id,
  'recipientId': 7,
  'actorId': 42,
  'type': 'MESSAGE',
  'title': 'Message notice $id',
  'message': 'A message is available',
  'relatedEntityType': 'chat_message',
  'relatedEntityId': 22,
  'eventId': 'chat-message:22-$id',
  'read': read,
  'createdAt': '2026-11-04T12:00:00',
  'readAt': read ? '2026-11-04T12:01:00' : null,
};
Map<String, Object?> message({
  String status = 'SENT',
  String text = 'Original',
  String? edited,
  bool deleted = false,
}) => {
  'id': 5,
  'conversationId': 9,
  'senderId': 42,
  'messageType': 'TEXT',
  'text': text,
  'createdAt': '2026-11-04T12:00:00.000000001',
  'updatedAt': edited ?? '2026-11-04T12:00:00.000000001',
  'editedAt': edited,
  'deletedAt': deleted ? '2026-11-04T12:00:01' : null,
  'deliveryStatus': status,
  'isEdited': edited != null,
  'isDeleted': deleted,
};
Map<String, Object?> page(List<Object?> rows, {int number = 0}) => {
  'content': rows,
  'page': number,
  'size': 20,
  'totalElements': rows.length,
  'totalPages': 1,
};
TransportResponse ok(Object? data) => TransportResponse(
  statusCode: 200,
  body: jsonEncode({'success': true, 'message': 'Success', 'data': data}),
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

class Link implements SocketLink {
  final incoming = StreamController<String>();
  final sent = <String>[];
  bool closed = false;
  @override
  Stream<String> get messages => incoming.stream;
  @override
  void send(String value) => sent.add(value);
  void receive(String value) {
    if (!closed) {
      incoming.add(value);
    }
  }

  @override
  Future<void> close() async {
    closed = true;
    unawaited(incoming.close());
  }

  List<StompFrame> get frames => sent
      .expand((value) => (jsonDecode(value) as List).cast<String>())
      .expand((value) => StompDecoder().add(value))
      .toList();
}

ApiClient api(Wire wire) => ApiClient(
  config: ApiConfig(baseUrl: Uri.parse('https://example.test/api/v1/')),
  transport: wire,
  accessTokenProvider: () => 'fixture-token',
);
Future<void> until(bool Function() ready) async {
  for (var i = 0; i < 40 && !ready(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(ready(), isTrue);
}

void server(
  Link link,
  String command,
  Map<String, String> headers, {
  String body = '',
}) =>
    link.receive('a${jsonEncode([encodeStomp(command, headers, body: body)])}');

void main() {
  test(
    '6B notification REST contracts, ownership and authoritative read counts',
    () async {
      AuthUser? current = user;
      final wire = Wire((r) {
        if (r.uri.path.endsWith('/unread-count')) return ok({'unreadCount': 8});
        if (r.uri.path.endsWith('/read-all')) return ok({'updatedCount': 3});
        if (r.method == 'PATCH') return ok(notification(read: true));
        return ok(page([notification()], number: 2));
      });
      final repo = NotificationRepository(
        api(wire),
        ownerId: 7,
        currentUser: () => current,
      );
      expect((await repo.list(page: 2)).content.single.type, 'MESSAGE');
      expect(wire.requests.last.uri.queryParameters, {
        'page': '2',
        'size': '20',
      });
      expect(await repo.unread(), 8);
      final read = await repo.read(1);
      expect(read.read, isTrue);
      expect(read.text('readAt'), '2026-11-04T12:01:00');
      expect(wire.requests.last.method, 'PATCH');
      expect(wire.requests.last.uri.path, '/api/v1/notifications/1/read');
      expect(await repo.readAll(), 3);
      expect(wire.requests.last.uri.path, '/api/v1/notifications/read-all');
      expect(
        wire.requests.every(
          (r) => r.headers['Authorization'] == 'Bearer fixture-token',
        ),
        isTrue,
      );
      final before = wire.requests.length;
      current = null;
      await expectLater(repo.unread(), throwsA(isA<ApiException>()));
      expect(wire.requests, hasLength(before));
      final wrong = NotificationRepository(
        api(Wire((_) => ok(page([notification()..['recipientId'] = 99])))),
        ownerId: 7,
        currentUser: () => user,
      );
      await expectLater(
        wrong.list(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.invalidResponse,
          ),
        ),
      );
    },
  );

  test('6B SockJS/STOMP framing handles Unicode byte lengths, fragmentation and header escapes', () {
    final encoded = encodeStomp('MESSAGE', {
      'subscription': 'chat-9',
      'x-value': 'a:b\nc\\d',
    }, body: 'héllo 🙂\u0000body');
    final decoder = StompDecoder();
    expect(decoder.add(encoded.substring(0, 12)), isEmpty);
    final result = decoder.add(
      '${encoded.substring(12)}\n${encodeStomp('RECEIPT', {'receipt-id': 'next'})}',
    );
    expect(result, hasLength(2));
    expect(result.first.body, 'héllo 🙂\u0000body');
    expect(result.first.headers['x-value'], 'a:b\nc\\d');
    expect(sockJsMessages('a${jsonEncode([encoded])}'), [encoded]);
    expect(() => sockJsMessages('a[12]'), throwsFormatException);
    expect(
      () => encodeStomp('CONNECT', {'Authorization': 'Bearer bad\nheader'}),
      throwsFormatException,
    );
  });

  test('6B lifecycle uses real SockJS paths, CONNECT-only JWT, private subscriptions, refresh and logout cleanup', () async {
    int? owner = 7;
    var token = 'first-token';
    final auth = StreamController<Object?>.broadcast();
    final links = <Link>[], uris = <Uri>[];
    final transport = Wire(
      (_) => const TransportResponse(
        statusCode: 200,
        body: '{"websocket":true,"cookie_needed":true,"origins":["*:*"],"entropy":1}',
      ),
    );
    final live = LiveUpdates(
      config: ApiConfig(baseUrl: Uri.parse('https://example.test/api/v1/')),
      currentUserId: () => owner,
      accessToken: () async => token,
      sessionChanges: auth.stream,
      readUnread: () async => 4,
      transport: transport,
      interval: const Duration(hours: 1),
      connector: (uri) async {
        uris.add(uri);
        final link = Link();
        links.add(link);
        return link;
      },
    );
    addTearDown(() async {
      live.dispose();
      await auth.close();
    });
    final events = <LiveEvent>[];
    final sub = live.events.listen(events.add);
    addTearDown(sub.cancel);
    final release = live.watchConversation(7, 9);
    await until(() => links.length == 1);
    expect(uris.single.scheme, 'wss');
    expect(uris.single.path, startsWith('/ws/'));
    expect(uris.single.path, endsWith('/websocket'));
    expect(uris.single.hasQuery, isFalse);
    expect(uris.single.toString(), isNot(contains(token)));
    expect(transport.requests.single.uri.path, '/ws/info');
    expect(
      transport.requests.single.headers.containsKey('Authorization'),
      isFalse,
    );
    links[0].receive('o');
    await until(() => links[0].frames.any((f) => f.command == 'CONNECT'));
    expect(
      links[0].frames.first.headers['Authorization'],
      'Bearer first-token',
    );
    server(links[0], 'CONNECTED', {'version': '1.2', 'heart-beat': '0,0'});
    await until(
      () => links[0].frames.where((f) => f.command == 'SUBSCRIBE').length == 2,
    );
    expect(
      links[0].frames
          .where((f) => f.command == 'SUBSCRIBE')
          .map((f) => f.headers['destination'])
          .toSet(),
      {'/user/queue/notifications', '/user/queue/chat/conversation/9'},
    );
    server(links[0], 'MESSAGE', {
      'subscription': 'notifications',
    }, body: jsonEncode(notification()));
    server(links[0], 'MESSAGE', {
      'subscription': 'chat-9',
    }, body: jsonEncode(message()));
    await until(
      () =>
          events.any((e) => e.message?.id == 5) &&
          events.any((e) => e.notification?.id == 1),
    );
    expect(live.unreadCount, 4);
    token = 'rotated-token';
    auth.add(null);
    await until(() => links.length == 2);
    expect(links[0].closed, isTrue);
    links[1].receive('o');
    await until(() => links[1].frames.isNotEmpty);
    expect(
      links[1].frames.first.headers['Authorization'],
      'Bearer rotated-token',
    );
    server(links[1], 'CONNECTED', {'version': '1.2'});
    await until(
      () => links[1].frames.where((f) => f.command == 'SUBSCRIBE').length == 2,
    );
    owner = null;
    auth.add(null);
    await until(() => links[1].closed);
    expect(live.unreadCount, isNull);
    owner = 7;
    live.activate();
    await until(() => links.length == 3);
    final newRelease = live.watchConversation(7, 9);
    links[2].receive('o');
    await until(() => links[2].frames.isNotEmpty);
    server(links[2], 'CONNECTED', {'version': '1.2'});
    await until(
      () => links[2].frames.where((f) => f.command == 'SUBSCRIBE').length == 2,
    );
    release();
    expect(
      links[2].frames.where((f) => f.command == 'UNSUBSCRIBE'),
      isEmpty,
    ); // Old login must not release new watches.
    newRelease();
    expect(links[2].frames.last.command, 'UNSUBSCRIBE');
    live.dispose();
    expect(links[2].closed, isTrue);
  });

  test('6B duplicate reconciliation cannot undo read receipts or resurrect deleted text', () {
    final cache = NotificationCache();
    cache.merge(NotificationItem.fromJson(notification(read: true)));
    cache.merge(NotificationItem.fromJson(notification()));
    expect(cache.items, hasLength(1));
    expect(cache.items.single.read, isTrue);
    final timeline = ChatTimeline(9);
    timeline.history([ChatMessage.fromJson(message())], seed: true);
    final cursor = timeline.cursor;
    timeline.merge(ChatMessage.fromJson(message(status: 'SEEN')));
    timeline.merge(ChatMessage.fromJson(message(status: 'SENT')));
    expect(timeline.messages.single.status, 'SEEN');
    expect(identical(timeline.cursor, cursor), isTrue);
    timeline.merge(
      ChatMessage.fromJson(
        message(
          status: 'SEEN',
          text: 'Edited',
          edited: '2026-11-04T12:00:00.000000009',
        ),
      ),
    );
    timeline.merge(ChatMessage.fromJson(message()));
    expect(timeline.messages.single.text, 'Edited');
    timeline.apply(
      ChatSync.fromJson({
        'conversationId': 9,
        'nextCursorMessageId': 5,
        'nextCursorCreatedAt': '2026-11-04T12:00:01',
        'hasMore': false,
        'messages': [],
        'tombstones': [
          {'id': 5, 'conversationId': 9, 'deletedAt': '2026-11-04T12:00:01'},
        ],
      }),
    );
    timeline.merge(ChatMessage.fromJson(message()));
    expect(timeline.messages, isEmpty);
    expect(timeline.tombstones.single.id, 5);
  });

  testWidgets(
    '6B notification UI confirms reads/counts and never treats a message ID as a conversation ID',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1100);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var oneRead = false, allRead = false;
      final wire = Wire((r) {
        if (r.uri.path.endsWith('/unread-count')) {
          return ok({
            'unreadCount': allRead
                ? 0
                : oneRead
                ? 2
                : 3,
          });
        }
        if (r.uri.path.endsWith('/read-all')) {
          allRead = true;
          return ok({'updatedCount': 2});
        }
        if (r.uri.path.endsWith('/1/read')) {
          oneRead = true;
          return ok(notification(read: true));
        }
        if (r.uri.path.endsWith('/notifications')) {
          return ok(
            page([
              notification(read: oneRead || allRead),
              notification(id: 2, read: allRead),
            ]),
          );
        }
        if (r.uri.path.endsWith('/chat/conversations')) return ok(page([]));
        throw StateError('Unexpected route ${r.uri.path}');
      });
      final client = api(wire);
      final notifications = NotificationRepository(
        client,
        ownerId: 7,
        currentUser: () => user,
      );
      final chat = ChatRepository(client, ownerId: 7, currentUser: () => user);
      final community = CommunityRepository(
        client,
        ownerId: 7,
        currentUser: () => user,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationInbox(
            repository: notifications,
            chat: chat,
            community: community,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('3 unread'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey(1)),
          matching: find.text('Mark read'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 unread'), findsOneWidget);
      await tester.tap(find.text('Mark all read'));
      await tester.pumpAndSettle();
      expect(find.text('0 unread'), findsOneWidget);
      expect(find.text('Mark read'), findsNothing);
      await tester.tap(find.text('Details').first);
      await tester.pumpAndSettle();
      expect(find.text('Related: chat_message #22'), findsOneWidget);
      await tester.tap(find.text('Open related area'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatInboxScreen), findsOneWidget);
      expect(
        wire.requests.any((r) => r.uri.path == '/api/v1/chat/conversations/22'),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
