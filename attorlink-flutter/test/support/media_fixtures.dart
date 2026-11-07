import 'dart:async';

import 'package:attorlink_flutter/features/calls/domain/call_models.dart';
import 'package:attorlink_flutter/features/calls/media/media_session.dart';

/// A unit-test double; never used by the production connection path.
class FakeMediaSession extends MediaSession {
  MediaStatus current = MediaStatus.idle;
  bool mic = false,
      video = false,
      closed = false,
      denyCamera = false,
      failConnect = false;
  int microphoneCalls = 0, cameraCalls = 0, switches = 0;
  CallCredentials? received;
  Completer<void>? connecting;
  @override
  MediaStatus get status => current;
  @override
  bool get microphoneEnabled => mic;
  @override
  bool get cameraEnabled => video;
  @override
  List<MediaVideo> get videos => [];
  @override
  int get remoteParticipants => 0;
  void emit(MediaStatus value) {
    current = value;
    if (!closed) notifyListeners();
  }

  @override
  Future<void> connect(CallCredentials credentials) async {
    received = credentials;
    // SDK properties may notify before the first connection-state transition.
    emit(MediaStatus.disconnected);
    if (failConnect) throw StateError('fixture connection failure');
    await connecting?.future;
    if (!closed) emit(MediaStatus.connected);
  }

  @override
  Future<void> microphone(bool enabled) async {
    microphoneCalls++;
    mic = enabled;
  }

  @override
  Future<void> camera(bool enabled) async {
    cameraCalls++;
    if (denyCamera) throw StateError('fixture permission denial');
    video = enabled;
  }

  @override
  Future<void> switchCamera() async {
    switches++;
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    mic = video = false;
    super.dispose();
  }
}
