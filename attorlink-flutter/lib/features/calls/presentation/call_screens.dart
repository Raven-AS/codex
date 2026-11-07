import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/live_updates.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../messaging/data/chat_repository.dart';
import '../../messaging/presentation/chat_access.dart';
import '../data/call_repository.dart';
import '../domain/call_models.dart';
import '../media/media_session.dart';
import 'call_forms.dart';
import 'call_media_screen.dart';

class CallsEntry extends StatelessWidget {
  const CallsEntry({super.key, required this.chat});
  final ChatRepository chat;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Video calls and schedules',
    icon: const Icon(Icons.video_call_outlined),
    onPressed: () => Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CallsScreen(repository: CallRepository(chat)),
      ),
    ),
  );
}

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key, required this.repository});
  final CallRepository repository;
  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  bool _scheduled = false, _incoming = true, _busy = false, _dirty = false;
  int _generation = 0;
  ApiPage<CallRecord>? _page;
  final _rows = <int, CallRecord>{};
  ApiException? _error;
  Timer? _timer;
  StreamSubscription<LiveEvent>? _events;
  bool get _visible => mounted && (ModalRoute.of(context)?.isCurrent ?? true);
  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_visible && !_busy && widget.repository.chat.live?.paused != true) {
        unawaited(_load());
      }
    });
    _events = widget.repository.chat.live?.events.listen((event) {
      if (widget.repository.chat.acceptsEvent(event) &&
          (event.kind == LiveKind.reconcile ||
              event.notification?.type == 'VIDEO_CALL')) {
        if (_visible && !_busy && widget.repository.chat.live?.paused != true) {
          unawaited(_load());
        } else {
          _dirty = true;
        }
      }
    });
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    unawaited(_events?.cancel() ?? Future<void>.value());
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (_busy || widget.repository.chat.live?.paused == true) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final loaded = <CallRecord>[];
      ApiPage<CallRecord>? result;
      final first = more ? (_page?.page ?? -1) + 1 : 0;
      final last = more ? first : (_page?.page ?? 0);
      for (var page = first; page <= last; page++) {
        result = await widget.repository.list(
          scheduled: _scheduled,
          incoming: _incoming,
          page: page,
        );
        if (widget.repository.chat.live?.paused == true) return;
        loaded.addAll(result.content);
        if (!result.hasNext) break;
      }
      if (mounted && generation == _generation) {
        setState(() {
          if (!more) _rows.clear();
          for (final r in loaded) {
            _rows[r.id] = r;
          }
          _page = result;
        });
      }
    } on ApiException catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = error;
          if ([
            ApiErrorKind.unauthorized,
            ApiErrorKind.forbidden,
            ApiErrorKind.notFound,
            ApiErrorKind.validation,
          ].contains(error.kind)) {
            _rows.clear();
            _page = null;
          }
        });
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _open(CallRecord record) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CallDetail(
          repository: widget.repository,
          id: record.id,
          scheduled: record.scheduled,
        ),
      ),
    );
    if (mounted) unawaited(_load());
  }

  Future<void> _create() async {
    final record = await Navigator.push<CallRecord>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CallForm(repository: widget.repository, scheduled: _scheduled),
      ),
    );
    if (!mounted) return;
    if (record != null) await _open(record);
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    if (_dirty &&
        !_busy &&
        _visible &&
        widget.repository.chat.live?.paused != true) {
      _dirty = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_load());
      });
    }
    return ChatAccess(
      repository: widget.repository.chat,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Video calls and schedules'),
          actions: [
            IconButton(
              tooltip: 'Refresh calls',
              onPressed: _busy ? null : () => _load(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Use Join audio/video in an eligible call’s details to connect media. Incoming and outgoing calls refresh every 20 seconds while this page is open.',
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final scheduled in [false, true])
                      ChoiceChip(
                        label: Text(
                          scheduled ? 'Scheduled' : 'Immediate / history',
                        ),
                        selected: _scheduled == scheduled,
                        onSelected: _busy
                            ? null
                            : (_) {
                                setState(() {
                                  _scheduled = scheduled;
                                  _rows.clear();
                                  _page = null;
                                });
                                unawaited(_load());
                              },
                      ),
                    for (final incoming in [true, false])
                      ChoiceChip(
                        label: Text(incoming ? 'Incoming' : 'Outgoing'),
                        selected: _incoming == incoming,
                        onSelected: _busy
                            ? null
                            : (_) {
                                setState(() {
                                  _incoming = incoming;
                                  _rows.clear();
                                  _page = null;
                                });
                                unawaited(_load());
                              },
                      ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _create,
                    icon: const Icon(Icons.add),
                    label: Text(_scheduled ? 'Schedule call' : 'Start call'),
                  ),
                ),
                if (_error != null)
                  ErrorView(error: _error!, onRetry: () => _load()),
                if (_rows.isEmpty && !_busy && _error == null)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No calls found.'),
                  ),
                for (final record in _rows.values)
                  Card(
                    child: ListTile(
                      onTap: () => _open(record),
                      title: Text(
                        '${record.scheduled ? 'Scheduled call' : 'Call'} #${record.id} · ${record.status}',
                      ),
                      subtitle: Text(
                        'Caller #${record.callerId} → Recipient #${record.recipientId}${record.scheduled ? '\n${record.fields['scheduledAt']} (backend wall time)' : '\n${record.fields['initiatedAt'] ?? ''}'}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  ),
                if (_busy) const LoadingView(),
                if (_page?.hasNext == true && !_busy)
                  TextButton(
                    onPressed: () => _load(more: true),
                    child: const Text('Load more calls'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CallDetail extends StatefulWidget {
  const CallDetail({
    super.key,
    required this.repository,
    required this.id,
    required this.scheduled,
    this.createMediaSession,
  });
  final CallRepository repository;
  final int id;
  final bool scheduled;
  final MediaSession Function()? createMediaSession;
  @override
  State<CallDetail> createState() => _CallDetailState();
}

class _CallDetailState extends State<CallDetail> {
  CallRecord? _record;
  bool _busy = false, _uncertain = false, _interacting = false;
  ApiException? _error;
  String? _notice;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted &&
          !_busy &&
          !_interacting &&
          widget.repository.chat.live?.paused != true &&
          !_uncertain &&
          (ModalRoute.of(context)?.isCurrent ?? true) &&
          (_record == null ||
              _record!.pending ||
              _record!.activeSchedule ||
              _record!.status == 'ACCEPTED' ||
              _record!.status == 'STARTED')) {
        unawaited(_refresh());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final record = await widget.repository.get(
        widget.id,
        scheduled: widget.scheduled,
      );
      if (mounted) {
        setState(() {
          _record = record;
          _uncertain = false;
        });
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _uncertain = true;
          if ([
            ApiErrorKind.unauthorized,
            ApiErrorKind.forbidden,
            ApiErrorKind.notFound,
            ApiErrorKind.validation,
          ].contains(error.kind)) {
            _record = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _act(String action) async {
    if (_busy || _uncertain || _interacting || _record == null) return;
    setState(() => _interacting = true);
    try {
      await _performAction(action);
    } finally {
      if (mounted) setState(() => _interacting = false);
    }
  }

  Future<void> _performAction(String action) async {
    final record = _record;
    if (_busy || _uncertain || record == null) return;
    if (action == 'reschedule') {
      final result = await Navigator.push<CallRecord>(
        context,
        MaterialPageRoute(
          builder: (_) => CallForm(
            repository: widget.repository,
            scheduled: true,
            existing: record,
          ),
        ),
      );
      if (mounted && result != null) setState(() => _record = result);
      // A closed form can have an unknown mutation outcome. Fetch authoritative
      // state before enabling another action on the old detail snapshot.
      if (mounted) {
        setState(() => _uncertain = true);
        await _refresh();
      }
      return;
    }
    if (action == 'join') {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => CallMediaScreen(
            repository: widget.repository,
            record: record,
            createSession: widget.createMediaSession,
          ),
        ),
      );
      if (mounted) await _refresh();
      return;
    }
    final input = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) =>
          CallActionDialog(repository: widget.repository, action: action),
    );
    if (!mounted || input == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final result = await widget.repository.action(
        record,
        action,
        reason: input['reason'],
        signalType: input['signalType'],
        payload: input['payload'],
      );
      if (mounted) {
        setState(() {
          _record = result;
          _notice = action == 'signal'
              ? 'Server acknowledged the signal. It does not relay payloads or establish media.'
              : 'Backend status updated. Join media separately to connect audio/video.';
        });
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          // A definite state/permission rejection can also mean this snapshot
          // is obsolete. Read authoritative state before another lifecycle action.
          _uncertain = true;
        });
      }
    } on FormatException catch (error) {
      if (mounted) {
        setState(
          () => _error = ApiException(
            kind: ApiErrorKind.validation,
            message: error.message,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _label(String action) => switch (action) {
    'ring' => 'Mark ringing',
    'accept' => 'Accept call',
    'reject' => 'Reject call',
    'cancel' => 'Cancel call',
    'end' => 'End call',
    'start' => 'Mark scheduled call started',
    'join' => 'Join audio/video',
    'reschedule' => 'Reschedule',
    'signal' => 'Submit signaling data',
    _ => action,
  };
  @override
  Widget build(BuildContext context) {
    final record = _record;
    return ChatAccess(
      repository: widget.repository.chat,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '${widget.scheduled ? 'Scheduled call' : 'Call'} #${widget.id}',
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh call status',
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Backend ACCEPTED/STARTED statuses describe lifecycle only. Join audio/video to establish a separate media connection.',
                ),
                if (widget.scheduled)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(callTimeHelp),
                  ),
                if (record != null) ...[
                  Text(
                    '${record.recipientId == widget.repository.chat.ownerId ? 'Incoming' : 'Outgoing'} · ${record.status}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    'Caller #${record.callerId} · Recipient #${record.recipientId}',
                  ),
                  for (final field in record.fields.entries)
                    if (![
                          'id',
                          'callerId',
                          'recipientId',
                          'status',
                        ].contains(field.key) &&
                        field.value != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text('${field.key}: ${field.value}'),
                      ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final action in record.actions(
                        widget.repository.chat.ownerId,
                      ))
                        OutlinedButton(
                          onPressed: _busy || _uncertain || _interacting
                              ? null
                              : () => _act(action),
                          child: Text(_label(action)),
                        ),
                    ],
                  ),
                ],
                if (_notice != null) Text(_notice!),
                if (_error != null)
                  ErrorView(error: _error!, onRetry: _busy ? null : _refresh),
                if (_uncertain)
                  const Text(
                    'The call state needs verification. Refresh authoritative state before another action.',
                  ),
                if (_busy) const LoadingView(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
