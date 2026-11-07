import 'dart:async';

import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_client.dart';
import 'package:attorlink_flutter/core/network/http_transport.dart';
import 'package:attorlink_flutter/features/calls/data/call_repository.dart';
import 'package:attorlink_flutter/features/calls/domain/call_models.dart';
import 'package:attorlink_flutter/features/calls/media/call_media_controller.dart';
import 'package:attorlink_flutter/features/calls/media/media_session.dart';
import 'package:attorlink_flutter/features/messaging/data/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calls_test.dart' as fixtures;
import 'support/media_fixtures.dart';

void main() {
  test(
    'abandoned capture failure cannot overwrite a newly resumed media session',
    () async {
      final wire = fixtures.Wire(
        (r) => fixtures.ok(
          r.method == 'POST'
              ? fixtures.credentials()
              : fixtures.record(status: 'ACCEPTED'),
        ),
      );
      final repo = fixtures.repository(wire);
      final first = DeferredCameraSession();
      final second = FakeMediaSession();
      final sessions = <MediaSession>[first, second];
      final controller = CallMediaController(
        repo,
        CallRecord.fromJson(fixtures.record(), scheduled: false),
        createSession: () => sessions.removeAt(0),
      );
      addTearDown(controller.dispose);
      addTearDown(repo.chat.api.close);
      final joining = controller.join();
      while (first.cameraCalls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      await controller.foreground(false);
      await controller.foreground(true);
      expect(controller.session, same(second));
      expect(controller.status, MediaStatus.connected);
      first.capture.completeError(StateError('old permission failure'));
      await joining;
      expect(controller.session, same(second));
      expect(controller.status, MediaStatus.connected);
      expect(controller.error, isNull);
      expect(first.closed, isTrue);
      expect(second.closed, isFalse);
    },
  );

  test('media uses only authorized join credentials and denial does not fake camera capture', () async {
    final wire = fixtures.Wire(
      (r) => fixtures.ok(
        r.method == 'POST'
            ? fixtures.credentials()
            : fixtures.record(status: 'ACCEPTED'),
      ),
    );
    final repo = fixtures.repository(wire);
    final fake = FakeMediaSession()..denyCamera = true;
    final media = CallMediaController(
      repo,
      CallRecord.fromJson(fixtures.record(), scheduled: false),
      createSession: () => fake,
    );
    addTearDown(media.dispose);
    addTearDown(repo.chat.api.close);
    await media.join();
    expect(media.status, MediaStatus.connected);
    expect(fake.received?.token, 'private-media-fixture');
    expect(fake.microphoneEnabled, isTrue);
    expect(fake.cameraEnabled, isFalse);
    expect(media.error, contains('permission denied'));
    await media.controls('microphone');
    expect(fake.microphoneEnabled, isFalse);
    fake.denyCamera = false;
    await media.controls('camera');
    await media.controls('switch');
    expect(fake.cameraEnabled, isTrue);
    expect(fake.switches, 1);
    expect(wire.requests.map((r) => '${r.method} ${r.uri.path}'), [
      'GET /api/v1/video-calls/9',
      'POST /api/v1/video-calls/9/join',
    ]);
    await media.leave();
    expect(fake.closed, isTrue);
    expect(media.status, MediaStatus.disconnected);
  });

  test('logout during pending connect disposes media and never publishes late tracks', () async {
    var generation = 0;
    final access = StreamController<Object?>();
    final wire = fixtures.Wire(
      (r) => fixtures.ok(
        r.method == 'POST'
            ? fixtures.credentials()
            : fixtures.record(status: 'ACCEPTED'),
      ),
    );
    final api = ApiClient(
      config: ApiConfig(baseUrl: Uri.parse('https://example.test/api/v1/')),
      transport: wire,
      accessTokenProvider: () => 'fixture',
    );
    final chat = ChatRepository(
      api,
      ownerId: 7,
      currentUser: () => fixtures.user,
      sessionGeneration: () => generation,
      accessChanges: access.stream,
    );
    final fake = FakeMediaSession()..connecting = Completer<void>();
    final media = CallMediaController(
      CallRepository(chat),
      CallRecord.fromJson(fixtures.record(), scheduled: false),
      createSession: () => fake,
    );
    addTearDown(media.dispose);
    addTearDown(api.close);
    addTearDown(access.close);
    final joining = media.join();
    while (fake.received == null) {
      await Future<void>.delayed(Duration.zero);
    }
    generation++;
    access.add(null);
    await Future<void>.delayed(Duration.zero);
    fake.connecting!.complete();
    await joining;
    expect(fake.closed, isTrue);
    expect(fake.microphoneCalls, 0);
    expect(fake.cameraCalls, 0);
    expect(media.status, MediaStatus.disconnected);
  });

  test('background cancels pending join; resume obtains new scheduled credentials and retains mute', () async {
    final wire = fixtures.Wire(
      (r) => fixtures.ok(
        r.method == 'POST'
            ? fixtures.credentials(scheduled: true)
            : fixtures.record(scheduled: true, status: 'STARTED'),
      ),
    );
    final repo = fixtures.repository(wire);
    final first = FakeMediaSession()..connecting = Completer<void>();
    final second = FakeMediaSession();
    final third = FakeMediaSession();
    final queue = [first, second, third];
    final media = CallMediaController(
      repo,
      CallRecord.fromJson(fixtures.record(scheduled: true), scheduled: true),
      createSession: () => queue.removeAt(0),
    );
    addTearDown(media.dispose);
    addTearDown(repo.chat.api.close);
    final joining = media.join();
    while (first.received == null) {
      await Future<void>.delayed(Duration.zero);
    }
    await media.foreground(false);
    first.connecting!.complete();
    await joining;
    expect(first.closed, isTrue);
    expect(first.microphoneCalls, 0);
    expect(media.status, MediaStatus.paused);
    await media.foreground(true);
    expect(media.status, MediaStatus.connected);
    await media.controls('microphone');
    expect(second.mic, isFalse);
    await media.foreground(false);
    await media.foreground(true);
    expect(third.mic, isFalse);
    expect(third.video, isTrue);
    expect(wire.requests.where((r) => r.method == 'POST'), hasLength(3));
    expect(
      wire.requests.every((r) => r.uri.path.contains('/scheduled/9')),
      isTrue,
    );
    await media.leave();
  });

  test(
    'backend end or authorization loss disconnects real media state',
    () async {
      var ended = false;
      final wire = fixtures.Wire(
        (r) => fixtures.ok(
          r.method == 'POST'
              ? fixtures.credentials()
              : fixtures.record(status: ended ? 'ENDED' : 'ACCEPTED'),
        ),
      );
      final repo = fixtures.repository(wire);
      final fake = FakeMediaSession();
      final media = CallMediaController(
        repo,
        CallRecord.fromJson(fixtures.record(), scheduled: false),
        createSession: () => fake,
      );
      addTearDown(media.dispose);
      addTearDown(repo.chat.api.close);
      await media.join();
      ended = true;
      await media.reconcile();
      expect(fake.closed, isTrue);
      expect(media.status, MediaStatus.disconnected);
      expect(media.error, contains('ENDED'));
      expect(wire.requests.where((r) => r.uri.path.endsWith('/end')), isEmpty);
    },
  );

  test('connection failure/final disconnect supports explicit fresh-credential retry', () async {
    final wire = fixtures.Wire(
      (r) => fixtures.ok(
        r.method == 'POST'
            ? fixtures.credentials()
            : fixtures.record(status: 'ACCEPTED'),
      ),
    );
    final repo = fixtures.repository(wire);
    final first = FakeMediaSession()..failConnect = true;
    final second = FakeMediaSession();
    final third = FakeMediaSession();
    final queue = [first, second, third];
    final media = CallMediaController(
      repo,
      CallRecord.fromJson(fixtures.record(), scheduled: false),
      createSession: () => queue.removeAt(0),
    );
    addTearDown(media.dispose);
    addTearDown(repo.chat.api.close);
    await media.join();
    expect(media.status, MediaStatus.failed);
    expect(first.closed, isTrue);
    expect(media.error, isNot(contains('private-media-fixture')));
    await media.join();
    second.emit(MediaStatus.reconnecting);
    expect(media.status, MediaStatus.reconnecting);
    second.emit(MediaStatus.connected);
    expect(media.status, MediaStatus.connected);
    second.emit(MediaStatus.disconnected);
    await media.join();
    expect(media.status, MediaStatus.connected);
    expect(second.closed, isTrue);
    expect(wire.requests.where((r) => r.method == 'POST'), hasLength(3));
    await media.leave();
  });

  test(
    'rejected preflight never creates a media session or exposes credentials',
    () async {
      final wire = fixtures.Wire(
        (_) => const TransportResponse(
          statusCode: 403,
          body: '{"success":false,"message":"Call forbidden","data":null}',
        ),
      );
      final repo = fixtures.repository(wire);
      final media = CallMediaController(
        repo,
        CallRecord.fromJson(fixtures.record(), scheduled: false),
        createSession: () => throw StateError('Must not create media'),
      );
      addTearDown(media.dispose);
      addTearDown(repo.chat.api.close);
      await media.join();
      expect(media.status, MediaStatus.failed);
      expect(media.error, 'Call forbidden');
      expect(wire.requests, hasLength(1));
    },
  );
}

class DeferredCameraSession extends FakeMediaSession {
  final capture = Completer<void>();
  @override
  Future<void> camera(bool enabled) async {
    cameraCalls++;
    await capture.future;
    video = enabled;
  }
}
