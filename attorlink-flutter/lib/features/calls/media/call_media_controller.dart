import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../data/call_repository.dart';
import '../domain/call_models.dart';
import 'media_session.dart';

/// One foreground media session, bound to the existing authenticated repository.
class CallMediaController extends ChangeNotifier {
  CallMediaController(
    this.repository,
    this.initial, {
    MediaSession Function()? createSession,
  }) : _create = createSession ?? LiveKitMediaSession.new {
    _access = repository.chat.accessChanges?.listen((_) => checkAccess());
    _poll = Timer.periodic(
      const Duration(seconds: 8),
      (_) => unawaited(reconcile()),
    );
  }
  final CallRepository repository;
  final CallRecord initial;
  final MediaSession Function() _create;
  MediaSession? _session;
  MediaSession? get session => _session;
  MediaStatus status = MediaStatus.idle;
  String? error;
  CallRecord? record;
  bool busy = false, _disposed = false, _foreground = true, _reading = false;
  bool _wanted = false, _mic = true, _camera = true;
  bool _canMic = false, _canCamera = false;
  bool get canMicrophone => _canMic;
  bool get canCamera => _canCamera;
  int _generation = 0;
  StreamSubscription<Object?>? _access;
  Timer? _poll;
  Future<void> _closing = Future<void>.value();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void checkAccess() {
    if (_disposed) return;
    try {
      repository.chat.checkAccess();
    } on ApiException {
      _wanted = false;
      error = 'Your session changed. Leave this call and sign in again.';
      unawaited(leave());
    }
  }

  bool _valid(int generation) {
    if (_disposed || !_foreground || generation != _generation) return false;
    repository.chat.checkAccess();
    return true;
  }

  Future<void> join() async {
    if (_disposed || busy || !_foreground || _session != null) return;
    final generation = ++_generation;
    busy = true;
    _wanted = true;
    error = null;
    status = MediaStatus.connecting;
    _notify();
    try {
      await _closing;
      if (!_valid(generation)) return;
      final current = await repository.get(
        initial.id,
        scheduled: initial.scheduled,
      );
      if (!_valid(generation)) return;
      record = current;
      final credentials = await repository.credentials(current);
      if (!_valid(generation)) return;
      final url = Uri.tryParse(credentials.serverUrl);
      final production =
          kReleaseMode ||
          const String.fromEnvironment('ATTORLINK_ENV') == 'production';
      if (url == null ||
          url.host.isEmpty ||
          url.userInfo.isNotEmpty ||
          url.hasQuery ||
          url.hasFragment ||
          !['ws', 'wss', 'http', 'https'].contains(url.scheme) ||
          (production && !['wss', 'https'].contains(url.scheme))) {
        throw const FormatException('Invalid media server address');
      }
      _canMic = credentials.canPublishAudio;
      _canCamera = credentials.canPublishVideo;
      final media = _create();
      _session = media;
      media.addListener(_mediaChanged);
      await media.connect(credentials);
      if (!_valid(generation)) return;
      // Android WebRTC requests capture permissions when these tracks are enabled.
      // One denied device must not prevent receiving the other participant.
      if (_canMic && _mic) await _capture(media, microphone: true);
      if (!_valid(generation)) return;
      if (_canCamera && _camera) await _capture(media, microphone: false);
      if (!_valid(generation)) return;
      status = media.status;
    } on ApiException catch (e) {
      if (!_disposed && generation == _generation) {
        error = e.message;
        status = MediaStatus.failed;
        await _dropSession();
      }
    } catch (_) {
      if (!_disposed && generation == _generation) {
        error = 'Could not connect media. Check the media service, network and device permissions, then retry.';
        status = MediaStatus.failed;
        await _dropSession();
      }
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> _capture(MediaSession media, {required bool microphone}) async {
    try {
      if (microphone) {
        await media.microphone(true);
      } else {
        await media.camera(true);
      }
    } catch (_) {
      if (!_disposed && _foreground && identical(_session, media)) {
        error =
            '${microphone ? 'Microphone' : 'Camera'} unavailable or permission denied. Allow access in Android app settings and retry the control.';
      }
    }
  }

  void _mediaChanged() {
    if (_disposed || _session == null) return;
    checkAccess();
    if (_session == null) return;
    final next = _session!.status;
    // Room property notifications can precede the SDK's first connecting event.
    // Initial connection failures are handled by the awaited connect operation.
    if (busy &&
        status == MediaStatus.connecting &&
        next == MediaStatus.disconnected) {
      return;
    }
    status = next;
    // LiveKit owns transient reconnection; a final disconnect needs fresh credentials.
    if (status == MediaStatus.disconnected) {
      error = 'Media disconnected. Retry to request fresh backend credentials.';
      unawaited(_dropSession());
    }
    _notify();
  }

  Future<void> controls(String action) async {
    final media = _session;
    if (_disposed || busy || media == null || status != MediaStatus.connected) {
      return;
    }
    busy = true;
    error = null;
    _notify();
    final generation = _generation;
    try {
      if (!_valid(generation)) return;
      switch (action) {
        case 'microphone':
          if (!_canMic) return;
          final enabled = !media.microphoneEnabled;
          await media.microphone(enabled);
          if (!_valid(generation)) return;
          _mic = enabled;
        case 'camera':
          if (!_canCamera) return;
          final enabled = !media.cameraEnabled;
          await media.camera(enabled);
          if (!_valid(generation)) return;
          _camera = enabled;
        case 'switch':
          if (_canCamera && media.cameraEnabled) await media.switchCamera();
      }
    } catch (_) {
      if (!_disposed && generation == _generation) error = 'Device control failed. Check camera/microphone permissions and device availability.';
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> reconcile() async {
    if (_disposed || !_foreground || _reading || _session == null) return;
    _reading = true;
    final generation = _generation;
    try {
      final current = await repository.get(
        initial.id,
        scheduled: initial.scheduled,
      );
      if (!_valid(generation)) return;
      record = current;
      if (!current.canJoin(repository.chat.ownerId)) {
        _wanted = false;
        await leave();
        error =
            'Backend call status is ${current.status}. Media has been disconnected.';
      }
    } on ApiException catch (e) {
      if (!_disposed &&
          generation == _generation &&
          [
            ApiErrorKind.unauthorized,
            ApiErrorKind.forbidden,
            ApiErrorKind.notFound,
            ApiErrorKind.validation,
          ].contains(e.kind)) {
        _wanted = false;
        await leave();
        error = 'This call is no longer authorized or available.';
      }
    } finally {
      _reading = false;
      _notify();
    }
  }

  Future<void> foreground(bool active) async {
    if (_disposed || _foreground == active) return;
    _foreground = active;
    if (!active) {
      ++_generation;
      busy = false;
      status = MediaStatus.paused;
      await _dropSession();
      _notify();
    } else if (_wanted) {
      await join();
    }
  }

  Future<void> _dropSession() {
    final media = _session;
    _session = null;
    if (media != null) {
      media.removeListener(_mediaChanged);
      _closing = _closing.then((_) async {
        try {
          await media.close();
        } catch (_) {
          /* Best-effort SDK cleanup, never log credentials. */
        }
      });
    }
    return _closing;
  }

  Future<void> leave() async {
    ++_generation;
    busy = false;
    _wanted = false;
    status = MediaStatus.disconnected;
    await _dropSession();
    _notify();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    _poll?.cancel();
    unawaited(_access?.cancel() ?? Future<void>.value());
    unawaited(_dropSession());
    super.dispose();
  }
}
