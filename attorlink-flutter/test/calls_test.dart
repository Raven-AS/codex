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
import 'package:attorlink_flutter/features/calls/data/call_repository.dart';
import 'package:attorlink_flutter/features/calls/domain/call_models.dart';
import 'package:attorlink_flutter/features/calls/presentation/call_forms.dart';
import 'package:attorlink_flutter/features/calls/presentation/call_screens.dart';

import 'support/media_fixtures.dart';

// Contract fixtures only: no production success or media connection is simulated.
const user = AuthUser(
  id: 7,
  email: 'fixture@example.invalid',
  role: UserRole.client,
  status: UserStatus.active,
);
Map<String, Object?> record({
  bool scheduled = false,
  String? status,
  int caller = 7,
  int recipient = 42,
}) => {
  'id': 9,
  'callerId': caller,
  'recipientId': recipient,
  'conversationId': 3,
  'roomId': 'room-9',
  'status': status ?? (scheduled ? 'SCHEDULED' : 'INITIATED'),
  if (scheduled) ...{
    'scheduledAt': '2030-06-20T12:15:00.123456789',
    'notes': 'Saved note',
    'reminderCount': 0,
  } else
    'initiatedAt': '2026-11-04T12:00:00',
};
Map<String, Object?> credentials({
  bool scheduled = false,
  String room = 'room-9',
}) => {
  'callId': scheduled ? null : 9,
  'roomId': room,
  'provider': 'livekit',
  'serverUrl': 'wss://media.example.invalid',
  'identity': 'user-7',
  'token': 'private-media-fixture',
  'expiresAt': '2030-06-20T13:00:00',
  'canPublishAudio': true,
  'canPublishVideo': true,
  'canSubscribe': true,
  'canPublishData': true,
};
Map<String, Object?> page(Object row) => {
  'content': [row],
  'page': 0,
  'size': 20,
  'totalElements': 1,
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
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    return handler(request);
  }

  @override
  void close() {}
}

CallRepository repository(Wire wire, {AuthUser? Function()? currentUser}) =>
    CallRepository(
      ChatRepository(
        ApiClient(
          config: ApiConfig(baseUrl: Uri.parse('https://example.test/api/v1/')),
          transport: wire,
          accessTokenProvider: () => 'fixture-access',
        ),
        ownerId: 7,
        currentUser: currentUser ?? () => user,
      ),
    );
Map<String, dynamic> body(TransportRequest r) =>
    jsonDecode(r.body!) as Map<String, dynamic>;

void main() {
  test('7A immediate contracts, direction, lifecycle, signaling and failure non-replay', () async {
    final wire = Wire((r) {
      if (r.method == 'GET' && r.uri.path.endsWith('/video-calls')) {
        return ok(page(record()));
      }
      if (r.uri.path.endsWith('/accept')) {
        return ok(record(status: 'ACCEPTED', caller: 42, recipient: 7));
      }
      if (r.uri.path.endsWith('/reject')) {
        return TransportResponse(statusCode: 503, body: 'unavailable');
      }
      if (r.uri.path.endsWith('/ring')) return ok(record(status: 'RINGING'));
      if (r.uri.path.endsWith('/cancel')) {
        return ok(record(status: 'CANCELLED'));
      }
      if (r.uri.path.endsWith('/end')) return ok(record(status: 'ENDED'));
      return ok(
        record(status: r.uri.path.endsWith('/signal') ? 'ACCEPTED' : null),
      );
    });
    final repo = repository(wire);
    await repo.list(scheduled: false, incoming: false);
    expect(wire.requests.last.uri.queryParameters, {
      'incoming': 'false',
      'page': '0',
      'size': '20',
    });
    final initial = await repo.create(
      recipient: 42,
      conversationId: 3,
      note: 'Optional',
    );
    expect(body(wire.requests.last), {
      'recipientUserId': 42,
      'conversationId': 3,
      'note': 'Optional',
    });
    final ringing = await repo.action(initial, 'ring');
    expect(wire.requests.last.method, 'PATCH');
    await repo.action(ringing, 'cancel', reason: 'Changed plans & time');
    expect(wire.requests.last.uri.queryParameters, {
      'reason': 'Changed plans & time',
    });
    expect(
      body(
        wire.requests.firstWhere((r) => r.method == 'POST'),
      )['recipientUserId'],
      42,
    );
    final incoming = CallRecord.fromJson(
      record(caller: 42, recipient: 7),
      scheduled: false,
    );
    final accepted = await repo.action(incoming, 'accept');
    await repo.action(
      accepted,
      'signal',
      signalType: 'offer',
      payload: 'actual-fixture-sdp',
    );
    expect(wire.requests.last.method, 'POST');
    expect(body(wire.requests.last), {
      'signalType': 'offer',
      'payload': 'actual-fixture-sdp',
    });
    await repo.action(accepted, 'end', reason: 'Done');
    expect(wire.requests.last.uri.path, '/api/v1/video-calls/9/end');
    final before = wire.requests.length;
    await expectLater(
      repo.action(incoming, 'reject'),
      throwsA(isA<ApiException>()),
    );
    expect(wire.requests.length, before + 1);
    expect(
      wire.requests.every(
        (r) => r.headers['Authorization'] == 'Bearer fixture-access',
      ),
      isTrue,
    );
  });

  test('7A scheduled contract preserves nanoseconds, optional inputs and exact action methods', () async {
    final wire = Wire((r) {
      if (r.uri.path.endsWith('/join')) return ok(credentials(scheduled: true));
      if (r.method == 'GET' && r.uri.path.endsWith('/scheduled')) {
        return ok(page(record(scheduled: true, caller: 42, recipient: 7)));
      }
      final status = r.uri.path.endsWith('/reschedule')
          ? 'RESCHEDULED'
          : r.uri.path.endsWith('/cancel')
          ? 'CANCELLED'
          : r.uri.path.endsWith('/start')
          ? 'STARTED'
          : 'SCHEDULED';
      return ok(record(scheduled: true, status: status));
    });
    final repo = repository(wire);
    await repo.list(scheduled: true, incoming: true);
    expect(wire.requests.last.uri.path, '/api/v1/video-calls/scheduled');
    expect(wire.requests.last.uri.queryParameters['incoming'], 'true');
    final created = await repo.create(
      recipient: 42,
      scheduledAt: '2030-06-20T12:15:00.123456789',
    );
    expect(body(wire.requests.last), {
      'recipientUserId': 42,
      'scheduledAt': '2030-06-20T12:15:00.123456789',
    });
    await repo.get(9, scheduled: true);
    expect(wire.requests.last.uri.path, '/api/v1/video-calls/scheduled/9');
    final changed = await repo.action(
      created,
      'reschedule',
      scheduledAt: '2030-06-22T14:00',
      reason: 'New time',
    );
    expect(wire.requests.last.method, 'PATCH');
    expect(body(wire.requests.last), {
      'scheduledAt': '2030-06-22T14:00:00',
      'reason': 'New time',
    });
    await repo.action(changed, 'cancel', reason: 'Unavailable');
    expect(wire.requests.last.uri.queryParameters, {'reason': 'Unavailable'});
    final started = await repo.action(changed, 'start');
    expect(wire.requests.last.method, 'PATCH');
    final result = await repo.credentials(started);
    expect(result.callId, isNull);
    expect(result.canPublishVideo, isTrue);
    expect(wire.requests.last.uri.path, '/api/v1/video-calls/scheduled/9/join');
    expect(wire.requests.last.method, 'POST');
  });

  test(
    '7A state permissions and timezone-free calendar validation match backend',
    () {
      final initiated = CallRecord.fromJson(record(), scheduled: false);
      expect(initiated.actions(7), ['ring', 'cancel', 'signal', 'join']);
      expect(initiated.actions(42), ['ring', 'accept', 'reject', 'signal']);
      expect(initiated.actions(99), isEmpty);
      final ringing = CallRecord.fromJson(
        record(status: 'RINGING'),
        scheduled: false,
      );
      expect(ringing.canJoin(7), isFalse);
      expect(ringing.canJoin(42), isTrue);
      final ended = CallRecord.fromJson(
        record(status: 'ENDED'),
        scheduled: false,
      );
      expect(ended.actions(7), isEmpty);
      final started = CallRecord.fromJson(
        record(scheduled: true, status: 'STARTED'),
        scheduled: true,
      );
      expect(started.actions(7), ['join']);
      for (final stamp in [
        '2030-02-30T12:00',
        '2030-06-01T24:00',
        '2030-06-01T12:00Z',
        '2030-06-01T12:00+06:00',
      ]) {
        expect(() => callLocalTime(stamp), throwsFormatException);
      }
      expect(callLocalTime('2032-02-29T12:15'), '2032-02-29T12:15:00');
      expect(
        callLocalTime('2030-06-20T12:15:00.123456789'),
        '2030-06-20T12:15:00.123456789',
      );
      expect(
        () =>
            CallRecord.fromJson(record(status: 'CONNECTED'), scheduled: false),
        throwsFormatException,
      );
    },
  );

  test('7A guards reject stale accounts, nonparticipants and mismatched credential rooms', () async {
    AuthUser? current = user;
    final pending = Completer<TransportResponse>();
    final wire = Wire((_) => pending.future);
    final repo = repository(wire, currentUser: () => current);
    final request = repo.get(9, scheduled: false);
    await Future<void>.delayed(Duration.zero);
    current = null;
    pending.complete(ok(record()));
    await expectLater(request, throwsA(isA<ApiException>()));
    await expectLater(repo.create(recipient: 42), throwsA(isA<ApiException>()));
    expect(wire.requests.length, 1);
    final invalid = repository(
      Wire((_) => ok(record(caller: 99, recipient: 100))),
    );
    await expectLater(
      invalid.get(9, scheduled: false),
      throwsA(isA<ApiException>()),
    );
    final wrongRoom = repository(
      Wire((_) => ok(credentials(room: 'wrong-room'))),
    );
    await expectLater(
      wrongRoom.credentials(CallRecord.fromJson(record(), scheduled: false)),
      throwsA(isA<ApiException>()),
    );
    await expectLater(
      wrongRoom.action(
        CallRecord.fromJson(record(), scheduled: false),
        'accept',
      ),
      throwsA(isA<ApiException>()),
    );
  });

  testWidgets(
    '7A form validation and accepted lifecycle never claim media connection or expose token',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var status = 'INITIATED';
      final wire = Wire((r) {
        if (r.uri.path.endsWith('/join')) return ok(credentials());
        if (r.uri.path.endsWith('/accept')) status = 'ACCEPTED';
        return ok(record(caller: 42, recipient: 7, status: status));
      });
      final repo = repository(wire);
      await tester.pumpWidget(
        MaterialApp(home: CallForm(repository: repo, scheduled: true)),
      );
      expect(find.textContaining('no installed LiveKit'), findsNothing);
      expect(find.textContaining('choose Join audio/video'), findsOneWidget);
      await tester.tap(find.text('Schedule'));
      await tester.pumpAndSettle();
      expect(find.text('Enter another positive user ID.'), findsOneWidget);
      expect(wire.requests, isEmpty);
      await tester.pumpWidget(
        MaterialApp(
          home: CallDetail(
            repository: repo,
            id: 9,
            scheduled: false,
            createMediaSession: () => FakeMediaSession()..failConnect = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Incoming · INITIATED'), findsOneWidget);
      await tester.tap(find.text('Accept call'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(find.text('Incoming · ACCEPTED'), findsOneWidget);
      await tester.tap(find.text('Join audio/video'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not connect media'), findsOneWidget);
      expect(find.textContaining('private-media-fixture'), findsNothing);
      expect(find.textContaining('CONNECTED'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
