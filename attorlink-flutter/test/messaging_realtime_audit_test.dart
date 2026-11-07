import 'dart:async';

import 'package:attorlink_flutter/app/live_updates.dart';
import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_client.dart';
import 'package:attorlink_flutter/core/network/api_exception.dart';
import 'package:attorlink_flutter/core/network/http_transport.dart';
import 'package:attorlink_flutter/features/auth/domain/auth_models.dart';
import 'package:attorlink_flutter/features/community/data/community_repository.dart';
import 'package:attorlink_flutter/features/messaging/data/chat_repository.dart';
import 'package:attorlink_flutter/features/messaging/domain/chat_models.dart';
import 'package:attorlink_flutter/features/messaging/domain/chat_timeline.dart';
import 'package:attorlink_flutter/features/messaging/presentation/chat_thread.dart';
import 'package:attorlink_flutter/features/notifications/data/notification_repository.dart';
import 'package:attorlink_flutter/features/notifications/domain/notification_models.dart';
import 'package:attorlink_flutter/features/notifications/presentation/notification_inbox.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'messaging_test.dart' as chat;
import 'live_notifications_test.dart' as fixture;

final config = ApiConfig(baseUrl: Uri.parse('https://example.test/api/v1/'));
const info = TransportResponse(statusCode: 200, body: '{"websocket":true}');
final forbidden = throwsA(
  isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.forbidden),
);

// Widget event fixtures only; transport/lifecycle behavior is tested separately
// below using the actual LiveUpdates class and backend-shaped SockJS frames.
class WidgetEvents extends LiveUpdates {
  WidgetEvents(Stream<Object?> auth)
    : super(
        config: config,
        accessToken: () async => 'fixture',
        currentUserId: () => 7,
        readUnread: () async => 1,
        sessionChanges: auth,
        transport: fixture.Wire((_) => info),
      );
  final incoming = StreamController<LiveEvent>.broadcast();
  @override
  Stream<LiveEvent> get events => incoming.stream;
  @override
  void activate() {}
  @override
  void notificationsChanged(int owner) {}
  @override
  void dispose() {
    unawaited(incoming.close());
    super.dispose();
  }
}

void main() {
  testWidgets(
    'message events during initial thread loading trigger REST reconciliation',
    (tester) async {
      final auth = StreamController<Object?>.broadcast();
      final live = WidgetEvents(auth.stream);
      final first = Completer<TransportResponse>();
      var metadata = 0;
      final newer = chat.message(
        id: 2,
        text: 'New arrival',
        created: '2026-11-04T12:00:01',
      );
      final wire = fixture.Wire((r) {
        if (r.uri.path.endsWith('/messages')) {
          return chat.response(chat.page([chat.message()]));
        }
        if (r.uri.path.endsWith('/sync')) {
          return chat.response({
            'conversationId': 9,
            'nextCursorMessageId': 2,
            'nextCursorCreatedAt': '2026-11-04T12:00:01',
            'hasMore': false,
            'messages': [newer],
            'tombstones': [],
          });
        }
        return ++metadata == 1
            ? first.future
            : chat.response(chat.conversation());
      });
      final api = fixture.api(wire);
      addTearDown(api.close);
      final repo = ChatRepository(
        api,
        ownerId: 7,
        currentUser: () => fixture.user,
        live: live,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ChatThreadScreen(repository: repo, conversationId: 9),
        ),
      );
      await tester.pump();
      live.incoming.add(
        LiveEvent(
          7,
          LiveKind.message,
          message: ChatMessage.fromJson(newer),
          conversationId: 9,
        ),
      );
      await tester.pump();
      first.complete(chat.response(chat.conversation()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('New arrival'), findsOneWidget);
      expect(wire.requests.any((r) => r.uri.path.endsWith('/sync')), true);
      await tester.pumpWidget(const SizedBox.shrink());
      live.dispose();
      await auth.close();
      await tester.pump();
    },
  );

  testWidgets(
    'backend HTTP 400 access denial clears private history and can recover',
    (tester) async {
      var denied = false;
      final wire = fixture.Wire((r) {
        if (r.uri.path.endsWith('/messages')) {
          return chat.response(chat.page([chat.message()]));
        }
        if (denied) {
          return chat.response(
            null,
            status: 400,
            error: 'You do not have access to this conversation',
          );
        }
        return chat.response({...chat.conversation(), 'unreadCount': 0});
      });
      final api = fixture.api(wire);
      addTearDown(api.close);
      final repo = ChatRepository(
        api,
        ownerId: 7,
        currentUser: () => fixture.user,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ChatThreadScreen(repository: repo, conversationId: 9),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hello'), findsOneWidget);
      expect(find.textContaining('0 unread'), findsNothing);
      denied = true;
      await tester.tap(find.text('Refresh history'));
      await tester.pumpAndSettle();
      expect(find.text('Hello'), findsNothing);
      expect(find.byKey(const ValueKey('chat-composer')), findsNothing);
      expect(
        find.text('You do not have access to this conversation'),
        findsOneWidget,
      );
      denied = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Hello'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    '401 recovery cannot replay a message send under a replacement login',
    () async {
      var generation = 1;
      final wire = fixture.Wire(
        (_) => const TransportResponse(
          statusCode: 401,
          body: '{"success":false,"message":"Expired","data":null}',
        ),
      );
      final api = ApiClient(
        config: config,
        transport: wire,
        accessTokenProvider: () => 'fixture',
        recoverAuthentication: (_) async {
          generation++;
          return true;
        },
      );
      addTearDown(api.close);
      final repo = ChatRepository(
        api,
        ownerId: 7,
        currentUser: () => fixture.user,
        sessionGeneration: () => generation,
      );
      await expectLater(
        repo.send(ChatConversation.fromJson(chat.conversation()), 'Draft'),
        forbidden,
      );
      expect(wire.requests, hasLength(1));
    },
  );

  testWidgets('request decision dialogs cannot stack before a frame rebuild', (
    tester,
  ) async {
    final wire = fixture.Wire(
      (r) => fixture.ok(
        r.uri.path.endsWith('/messages')
            ? chat.page([])
            : chat.conversation(status: 'PENDING', incoming: true),
      ),
    );
    final api = fixture.api(wire);
    addTearDown(api.close);
    final repo = ChatRepository(
      api,
      ownerId: 7,
      currentUser: () => fixture.user,
    );
    await tester.pumpWidget(
      MaterialApp(home: ChatThreadScreen(repository: repo, conversationId: 9)),
    );
    await tester.pumpAndSettle();
    final accept = tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Accept request'),
        )
        .onPressed!;
    accept();
    accept();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(wire.requests.where((r) => r.method == 'POST'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'a later unread event wins over an earlier in-flight inbox count',
    (tester) async {
      final auth = StreamController<Object?>.broadcast();
      final live = WidgetEvents(auth.stream);
      final pending = Completer<TransportResponse>();
      final wire = fixture.Wire(
        (r) => r.uri.path.endsWith('/unread-count')
            ? pending.future
            : fixture.ok(fixture.page([])),
      );
      final api = fixture.api(wire);
      final notices = NotificationRepository(
        api,
        ownerId: 7,
        currentUser: () => fixture.user,
        live: live,
      );
      final messages = ChatRepository(
        api,
        ownerId: 7,
        currentUser: () => fixture.user,
      );
      final community = CommunityRepository(
        api,
        ownerId: 7,
        currentUser: () => fixture.user,
      );
      addTearDown(api.close);
      addTearDown(community.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationInbox(
            repository: notices,
            chat: messages,
            community: community,
          ),
        ),
      );
      await tester.pump();
      live.unreadCount = 2; // Fixture for a newer confirmed REST count event.
      live.incoming.add(const LiveEvent(7, LiveKind.unread));
      await tester.pump();
      pending.complete(fixture.ok({'unreadCount': 99}));
      await tester.pumpAndSettle();
      expect(find.text('2 unread'), findsOneWidget);
      expect(find.text('99 unread'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      live.dispose();
      await auth.close();
      await tester.pump();
    },
  );

  for (final operation in ['send', 'decision', 'read', 'read-all']) {
    test(
      '$operation cannot dispatch across an authentication generation',
      () async {
        var generation = 1;
        final wire = fixture.Wire((_) => throw StateError('Must not send'));
        final api = ApiClient(
          config: config,
          transport: wire,
          accessTokenProvider: () => 'fixture-access',
          beforeAuthenticatedRequest: () async {
            generation++;
          },
        );
        addTearDown(api.close);
        final messages = ChatRepository(
          api,
          ownerId: 7,
          currentUser: () => fixture.user,
          sessionGeneration: () => generation,
        );
        final notices = NotificationRepository(
          api,
          ownerId: 7,
          currentUser: () => fixture.user,
          sessionGeneration: () => generation,
        );
        final accepted = ChatConversation.fromJson(chat.conversation());
        final Future<Object?> pending = switch (operation) {
          'send' => messages.send(accepted, 'Fixture text'),
          'decision' => messages.decide(
            ChatConversation.fromJson(
              chat.conversation(status: 'PENDING', incoming: true),
            ),
            accept: true,
          ),
          'read' => messages.markRead(9, ChatMessage.fromJson(chat.message())),
          _ => notices.readAll(),
        };
        // Notification access errors are unauthorized; chat access errors forbidden.
        await expectLater(pending, throwsA(isA<ApiException>()));
        expect(wire.requests, isEmpty);
      },
    );
  }

  test('old queued realtime events cannot authorize a new login to the same account', () {
    var generation = 1;
    final api = fixture.api(fixture.Wire((_) => fixture.ok(null)));
    addTearDown(api.close);
    final oldRepo = ChatRepository(
      api,
      ownerId: 7,
      currentUser: () => fixture.user,
      sessionGeneration: () => generation,
    );
    generation = 2;
    final newRepo = NotificationRepository(
      api,
      ownerId: 7,
      currentUser: () => fixture.user,
      sessionGeneration: () => generation,
    );
    const stale = LiveEvent(7, LiveKind.reconcile, sessionGeneration: 1);
    expect(oldRepo.acceptsEvent(stale), false);
    expect(newRepo.acceptsEvent(stale), false);
    expect(
      newRepo.acceptsEvent(
        const LiveEvent(7, LiveKind.reconcile, sessionGeneration: 2),
      ),
      true,
    );
  });

  test(
    'late message responses are rejected before decoding after logout',
    () async {
      AuthUser? current = fixture.user;
      final pending = Completer<TransportResponse>();
      final api = fixture.api(fixture.Wire((_) => pending.future));
      addTearDown(api.close);
      final repo = ChatRepository(api, ownerId: 7, currentUser: () => current);
      final request = repo.get(9);
      final assertion = expectLater(request, forbidden);
      current = null;
      pending.complete(fixture.ok({'not': 'a conversation'}));
      await assertion;
    },
  );

  test('content versions, receipts, tombstones and established cursors merge independently', () {
    final timeline = ChatTimeline(9);
    timeline.history([ChatMessage.fromJson(fixture.message())], seed: true);
    timeline.merge(
      ChatMessage.fromJson(
        fixture.message(
          text: 'Edited',
          edited: '2026-11-04T12:00:02',
          status: 'SENT',
        ),
      ),
    );
    timeline.merge(ChatMessage.fromJson(fixture.message(status: 'SEEN')));
    expect(timeline.messages.single.text, 'Edited');
    expect(timeline.messages.single.status, 'SEEN');
    timeline.merge(
      ChatMessage.fromJson(
        fixture.message(
          text: 'Edited again',
          edited: '2026-11-04T12:00:03',
          status: 'DELIVERED',
        ),
      ),
    );
    expect(timeline.messages.single.text, 'Edited again');
    expect(timeline.messages.single.status, 'SEEN');
    timeline.apply(
      ChatSync.fromJson({
        'conversationId': 9,
        'nextCursorMessageId': 5,
        'nextCursorCreatedAt': '2026-11-04T12:00:04',
        'hasMore': false,
        'messages': [],
        'tombstones': [],
      }),
    );
    timeline.history([ChatMessage.fromJson(fixture.message())], seed: true);
    expect(timeline.cursor!.timestamp, '2026-11-04T12:00:04');
    timeline.remove(ChatTombstone(5, 9, '2026-11-04T12:00:06'));
    timeline.remove(ChatTombstone(5, 9, '2026-11-04T12:00:05'));
    expect(timeline.tombstones.single.deletedAt, '2026-11-04T12:00:06');
    expect(timeline.messages, isEmpty);
  });

  test('pending credentials/counts from an old login cannot block a replacement session', () async {
    var generation = 1;
    var credentials = 0, counts = 0;
    final oldToken = Completer<String>(), oldCount = Completer<int>();
    final auth = StreamController<Object?>.broadcast();
    addTearDown(auth.close);
    final links = <fixture.Link>[];
    final live = LiveUpdates(
      config: config,
      sessionChanges: auth.stream,
      currentUserId: () => 7,
      sessionGeneration: () => generation,
      accessToken: () => ++credentials == 1
          ? oldToken.future
          : Future.value('new-fixture-token'),
      readUnread: () => ++counts == 1 ? oldCount.future : Future.value(3),
      transport: fixture.Wire((_) => info),
      interval: const Duration(hours: 1),
      connector: (_) async {
        final link = fixture.Link();
        links.add(link);
        return link;
      },
    );
    addTearDown(live.dispose);
    live.activate();
    await fixture.until(() => credentials == 1 && counts == 1);
    generation++;
    auth.add(null);
    await fixture.until(() => links.length == 1 && live.unreadCount == 3);
    links.single.receive('o');
    await fixture.until(() => links.single.frames.isNotEmpty);
    expect(
      links.single.frames.first.headers['Authorization'],
      'Bearer new-fixture-token',
    );
    oldToken.completeError(StateError('Old login failed late'));
    oldCount.complete(99);
    await Future<void>.delayed(Duration.zero);
    expect(live.unreadCount, 3);
    expect(links.single.closed, false);
  });

  test(
    'dirty unread counts do not publish an earlier response after a read/event',
    () async {
      final auth = StreamController<Object?>.broadcast();
      addTearDown(auth.close);
      final first = Completer<int>(), latest = Completer<int>();
      var calls = 0;
      final live = LiveUpdates(
        config: config,
        sessionChanges: auth.stream,
        currentUserId: () => 7,
        accessToken: () async => 'fixture',
        readUnread: () => ++calls == 1 ? first.future : latest.future,
        interval: const Duration(hours: 1),
        transport: fixture.Wire((_) => info),
        connector: (_) async => fixture.Link(),
      );
      addTearDown(live.dispose);
      live.activate();
      await fixture.until(() => calls == 1);
      live.notificationsChanged(7);
      first.complete(99);
      await fixture.until(() => calls == 2);
      expect(live.unreadCount, isNull);
      latest.complete(2);
      await fixture.until(() => live.unreadCount == 2);
    },
  );

  test(
    'pause/resume rejects old count responses and releases pending token work',
    () async {
      final auth = StreamController<Object?>.broadcast();
      addTearDown(auth.close);
      final oldToken = Completer<String>(), oldCount = Completer<int>();
      var tokens = 0, counts = 0;
      final links = <fixture.Link>[];
      final live = LiveUpdates(
        config: config,
        sessionChanges: auth.stream,
        currentUserId: () => 7,
        accessToken: () =>
            ++tokens == 1 ? oldToken.future : Future.value('resumed-token'),
        readUnread: () => ++counts == 1 ? oldCount.future : Future.value(4),
        interval: const Duration(hours: 1),
        transport: fixture.Wire((_) => info),
        connector: (_) async {
          final link = fixture.Link();
          links.add(link);
          return link;
        },
      );
      addTearDown(live.dispose);
      live.activate();
      await fixture.until(() => tokens == 1 && counts == 1);
      live.pause();
      live.resume();
      await fixture.until(() => links.length == 1 && live.unreadCount == 4);
      oldToken.complete('old-token');
      oldCount.complete(90);
      await Future<void>.delayed(Duration.zero);
      expect(live.unreadCount, 4);
      expect(links, hasLength(1));
    },
  );

  test('unsupported SockJS WebSocket capability stays on REST until explicit reconnect', () async {
    final auth = StreamController<Object?>.broadcast();
    addTearDown(auth.close);
    final wire = fixture.Wire(
      (_) =>
          const TransportResponse(statusCode: 200, body: '{"websocket":false}'),
    );
    final live = LiveUpdates(
      config: config,
      sessionChanges: auth.stream,
      currentUserId: () => 7,
      accessToken: () async => 'fixture',
      readUnread: () async => 2,
      transport: wire,
      interval: const Duration(hours: 1),
      connector: (_) async =>
          throw StateError('Unsupported socket must not open'),
    );
    addTearDown(live.dispose);
    live.activate();
    await fixture.until(() => live.status.contains('unavailable'));
    live.activate();
    auth.add(null);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(wire.requests, hasLength(1));
    expect(live.unreadCount, 2);
    live.reconnect();
    await fixture.until(() => wire.requests.length == 2);
  });

  test(
    'initial suspension defers socket/REST activity until resumed',
    () async {
      final auth = StreamController<Object?>.broadcast();
      addTearDown(auth.close);
      var count = 0;
      final links = <fixture.Link>[];
      final wire = fixture.Wire((_) => info);
      final live = LiveUpdates(
        config: config,
        sessionChanges: auth.stream,
        currentUserId: () => 7,
        initiallyPaused: true,
        accessToken: () async => 'fixture',
        readUnread: () async {
          count++;
          return 1;
        },
        transport: wire,
        interval: const Duration(hours: 1),
        connector: (_) async {
          final link = fixture.Link();
          links.add(link);
          return link;
        },
      );
      addTearDown(live.dispose);
      live.activate();
      await Future<void>.delayed(Duration.zero);
      expect(wire.requests, isEmpty);
      expect(count, 0);
      live.resume();
      await fixture.until(() => links.isNotEmpty && count > 0);
    },
  );

  testWidgets(
    'read-all confirms only captured notifications; later arrivals stay unread',
    (tester) async {
      final auth = StreamController<Object?>.broadcast();
      final live = WidgetEvents(auth.stream);
      final readResponse = Completer<TransportResponse>();
      var allRead = false, arrived = false;
      final wire = fixture.Wire((r) {
        if (r.uri.path.endsWith('/unread-count')) {
          return fixture.ok({'unreadCount': allRead ? 1 : 2});
        }
        if (r.uri.path.endsWith('/read-all')) {
          allRead = true;
          return readResponse.future;
        }
        return fixture.ok(
          fixture.page([
            if (arrived) fixture.notification(id: 3),
            fixture.notification(read: allRead),
            fixture.notification(id: 2, read: allRead),
          ]),
        );
      });
      final api = fixture.api(wire);
      final notices = NotificationRepository(
        api,
        ownerId: 7,
        currentUser: () => fixture.user,
        live: live,
      );
      final messages = ChatRepository(
        api,
        ownerId: 7,
        currentUser: () => fixture.user,
      );
      final community = CommunityRepository(
        api,
        ownerId: 7,
        currentUser: () => fixture.user,
      );
      addTearDown(api.close);
      addTearDown(community.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationInbox(
            repository: notices,
            chat: messages,
            community: community,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark all read'));
      await tester.pump();
      arrived = true;
      live.incoming.add(
        LiveEvent(
          7,
          LiveKind.notification,
          notification: NotificationItem.fromJson(fixture.notification(id: 3)),
        ),
      );
      await tester.pump();
      readResponse.complete(fixture.ok({'updatedCount': 2}));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      final latest = find.byKey(const ValueKey(3));
      expect(
        find.descendant(of: latest, matching: find.text('Mark read')),
        findsOneWidget,
      );
      expect(find.text('1 unread'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      live.dispose();
      await auth.close();
      await tester.pump();
    },
  );
}
