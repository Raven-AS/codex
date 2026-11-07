import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../domain/call_models.dart';

enum MediaStatus {
  idle,
  connecting,
  connected,
  reconnecting,
  disconnected,
  paused,
  failed,
}

class MediaVideo {
  const MediaVideo(this.identity, this.track, {required this.local});
  final String identity;
  final lk.VideoTrack track;
  final bool local;
}

/// Injectable media boundary. Production uses the LiveKit SDK, never REST status.
abstract class MediaSession extends ChangeNotifier {
  MediaStatus get status;
  bool get microphoneEnabled;
  bool get cameraEnabled;
  List<MediaVideo> get videos;
  int get remoteParticipants;
  Future<void> connect(CallCredentials credentials);
  Future<void> microphone(bool enabled);
  Future<void> camera(bool enabled);
  Future<void> switchCamera();
  Future<void> close();
}

class LiveKitMediaSession extends MediaSession {
  LiveKitMediaSession() {
    // SDK debug messages can contain signaling URLs/credentials. App errors are sanitized.
    lk.disableLogging();
    _room.addListener(_changed);
  }
  final _room = lk.Room(
    roomOptions: const lk.RoomOptions(adaptiveStream: true, dynacast: true),
  );
  bool _closed = false;
  bool _front = true;
  @override
  MediaStatus get status => switch (_room.connectionState) {
    lk.ConnectionState.connecting => MediaStatus.connecting,
    lk.ConnectionState.connected => MediaStatus.connected,
    lk.ConnectionState.reconnecting => MediaStatus.reconnecting,
    lk.ConnectionState.disconnected => MediaStatus.disconnected,
  };
  void _changed() {
    if (!_closed) notifyListeners();
  }

  @override
  bool get microphoneEnabled =>
      _room.localParticipant?.isMicrophoneEnabled() ?? false;
  @override
  bool get cameraEnabled => _room.localParticipant?.isCameraEnabled() ?? false;
  @override
  int get remoteParticipants => _room.remoteParticipants.length;
  @override
  List<MediaVideo> get videos => [
    if (_room.localParticipant case final local?)
      for (final pub in local.videoTrackPublications)
        if (pub.track case final lk.VideoTrack track when !pub.muted)
          MediaVideo(local.identity, track, local: true),
    for (final remote in _room.remoteParticipants.values)
      for (final pub in remote.videoTrackPublications)
        if (pub.track case final lk.VideoTrack track when !pub.muted)
          MediaVideo(remote.identity, track, local: false),
  ];
  @override
  Future<void> connect(CallCredentials credentials) =>
      _room.connect(credentials.serverUrl, credentials.token);
  @override
  Future<void> microphone(bool enabled) async {
    if (_closed) return;
    final publication = await _room.localParticipant?.setMicrophoneEnabled(
      enabled,
    );
    if (_closed) await publication?.track?.stop();
    _changed();
  }

  @override
  Future<void> camera(bool enabled) async {
    if (_closed) return;
    final publication = await _room.localParticipant?.setCameraEnabled(enabled);
    if (_closed) await publication?.track?.stop();
    _changed();
  }

  @override
  Future<void> switchCamera() async {
    if (_closed) return;
    for (final pub
        in _room.localParticipant?.videoTrackPublications ??
            <lk.LocalTrackPublication>[]) {
      if (pub.track case final lk.LocalVideoTrack track) {
        await track.setCameraPosition(
          _front ? lk.CameraPosition.back : lk.CameraPosition.front,
        );
        _front = !_front;
        _changed();
        return;
      }
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _room.removeListener(_changed);
    try {
      await _room.disconnect();
    } finally {
      await _room.dispose();
      super.dispose();
    }
  }
}
