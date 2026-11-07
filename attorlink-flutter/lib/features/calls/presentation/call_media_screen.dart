import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../messaging/presentation/chat_access.dart';
import '../data/call_repository.dart';
import '../domain/call_models.dart';
import '../media/call_media_controller.dart';
import '../media/media_session.dart';

class CallMediaScreen extends StatefulWidget {
  const CallMediaScreen({
    super.key,
    required this.repository,
    required this.record,
    this.createSession,
  });
  final CallRepository repository;
  final CallRecord record;
  final MediaSession Function()? createSession;
  @override
  State<CallMediaScreen> createState() => _CallMediaScreenState();
}

class _CallMediaScreenState extends State<CallMediaScreen>
    with WidgetsBindingObserver {
  late final _media = CallMediaController(
    widget.repository,
    widget.record,
    createSession: widget.createSession,
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_media.join());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_media.foreground(true));
    } else if ([
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.detached,
    ].contains(state)) {
      unawaited(_media.foreground(false));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _media.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChatAccess(
    repository: widget.repository.chat,
    child: Scaffold(
      appBar: AppBar(title: Text('Call media #${widget.record.id}')),
      body: AnimatedBuilder(
        animation: _media,
        builder: (context, _) {
          final session = _media.session;
          final connected = _media.status == MediaStatus.connected;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Backend status: ${_media.record?.status ?? widget.record.status}',
              ),
              Text(
                'Media: ${_media.status.name}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text('Remote participants: ${session?.remoteParticipants ?? 0}'),
              const Text(
                'Leaving media does not end the backend call. Return to call details to use supported lifecycle actions. Backgrounding disconnects media; resume requests fresh authorization.',
              ),
              if (_media.error != null)
                Text(
                  _media.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_media.busy) const LinearProgressIndicator(),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (session == null)
                    FilledButton(
                      onPressed: _media.busy ? null : _media.join,
                      child: const Text('Retry media connection'),
                    ),
                  OutlinedButton(
                    onPressed:
                        _media.busy || !connected || !_media.canMicrophone
                        ? null
                        : () => _media.controls('microphone'),
                    child: Text(
                      session?.microphoneEnabled == true
                          ? 'Mute microphone'
                          : 'Enable microphone',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _media.busy || !connected || !_media.canCamera
                        ? null
                        : () => _media.controls('camera'),
                    child: Text(
                      session?.cameraEnabled == true
                          ? 'Turn camera off'
                          : 'Enable camera',
                    ),
                  ),
                  OutlinedButton(
                    onPressed:
                        _media.busy ||
                            !connected ||
                            session?.cameraEnabled != true
                        ? null
                        : () => _media.controls('switch'),
                    child: const Text('Switch camera'),
                  ),
                  TextButton(
                    onPressed: () async {
                      await _media.leave();
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('Leave media'),
                  ),
                ],
              ),
              for (final video in session?.videos ?? <MediaVideo>[])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      Text(
                        video.local
                            ? 'Your camera'
                            : 'Participant ${video.identity}',
                      ),
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: lk.VideoTrackRenderer(
                          video.track,
                          key: ValueKey(video.track),
                          fit: lk.VideoViewFit.contain,
                        ),
                      ),
                    ],
                  ),
                ),
              if (connected && (session?.remoteParticipants ?? 0) == 0)
                const Text(
                  'Connected to the media server. Waiting for the other participant.',
                ),
            ],
          );
        },
      ),
    ),
  );
}
