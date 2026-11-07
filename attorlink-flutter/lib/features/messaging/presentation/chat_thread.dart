import '../../calls/data/call_repository.dart';
import '../../calls/presentation/call_forms.dart';
import '../../calls/presentation/call_screens.dart';
import '../../calls/domain/call_models.dart';

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../app/live_updates.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../data/chat_repository.dart';
import '../domain/chat_models.dart';
import '../domain/chat_timeline.dart';
import 'chat_access.dart';

class ChatThreadScreen extends StatefulWidget {
  const ChatThreadScreen({
    super.key,
    required this.repository,
    required this.conversationId,
  });
  final ChatRepository repository;
  final int conversationId;
  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  late final _timeline = ChatTimeline(widget.conversationId);
  final _draft = TextEditingController();
  ChatConversation? _conversation;
  ApiPage<ChatMessage>? _history;
  ApiException? _error;
  String? _notice;
  bool _loading = true,
      _working = false,
      _uncertain = false,
      _sendUncertain = false;
  StreamSubscription<LiveEvent>? _liveEvents;
  void Function()? _releaseWatch;
  Timer? _liveTimer;
  bool _liveDirty = false;
  int _liveHistoryPage = 0;
  bool _refreshing = false, _dialogOpen = false;
  int _metadataRevision = 0;
  @override
  void initState() {
    super.initState();
    widget.repository.live?.activate();
    _liveEvents = widget.repository.live?.events.listen((event) {
      if (!mounted || !widget.repository.acceptsEvent(event)) return;
      if (event.kind == LiveKind.state) {
        setState(() {});
      }
      if (event.message?.conversationId == widget.conversationId) {
        if (_conversation?.status == 'ACCEPTED') {
          setState(() => _timeline.merge(event.message!));
        }
        // An inbox subscription may deliver before this thread's first GET.
        _queueLive();
      } else if ((event.kind == LiveKind.reconcile &&
              (event.conversationId == null ||
                  event.conversationId == widget.conversationId)) ||
          (event.kind == LiveKind.notification &&
              event.notification?.type == 'MESSAGE')) {
        _queueLive();
      }
    });
    _refresh();
  }

  @override
  void dispose() {
    _draft.dispose();
    _liveTimer?.cancel();
    _releaseWatch?.call();
    unawaited(_liveEvents?.cancel() ?? Future<void>.value());
    super.dispose();
  }

  void _watch() {
    if (_conversation?.status == 'ACCEPTED') {
      _releaseWatch ??= widget.repository.live?.watchConversation(
        widget.repository.ownerId,
        widget.conversationId,
      );
    } else {
      _releaseWatch?.call();
      _releaseWatch = null;
    }
  }

  void _queueLive() {
    _liveDirty = true;
    if (_liveTimer?.isActive == true) return;
    _liveTimer = Timer(const Duration(milliseconds: 250), () {
      _liveTimer = null;
      if (!mounted ||
          widget.repository.live?.paused == true ||
          _loading ||
          _working ||
          !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return;
      }
      unawaited(_reconcileLive());
    });
  }

  Future<void> _reconcileLive() async {
    if (_loading || _working) {
      _liveDirty = true;
      return;
    }
    final revision = ++_metadataRevision;
    _liveDirty = false;
    setState(() => _working = true);
    try {
      final conversation = await widget.repository.get(widget.conversationId);
      if (!mounted || widget.repository.live?.paused == true) {
        _liveDirty = true;
        return;
      }
      if (revision != _metadataRevision) {
        _liveDirty = true;
        return;
      }
      setState(() => _conversation = conversation);
      _watch();
      if (conversation.status == 'ACCEPTED' && _timeline.cursor != null) {
        for (var batch = 0; batch < 3; batch++) {
          final sync = await widget.repository.sync(
            conversation,
            _timeline.cursor!,
            limit: 200,
          );
          if (!mounted || widget.repository.live?.paused == true) {
            _liveDirty = true;
            return;
          }
          setState(() => _timeline.apply(sync));
          if (!sync.hasMore) break;
          if (batch == 2) {
            _liveDirty = true;
          }
        }
      }
      // The server does not broadcast REST edits/receipts. Rotate through loaded
      // history pages, bounded per pass; never advance the event cursor here.
      final pages = max(
        (_history?.page ?? 0) + 1,
        max(1, (_timeline.messages.length / 20).ceil()),
      );
      for (var i = 0; i < min(2, pages); i++) {
        final next = _liveHistoryPage % pages;
        final history = await widget.repository.history(
          widget.conversationId,
          page: next,
        );
        if (!mounted || widget.repository.live?.paused == true) {
          _liveDirty = true;
          return;
        }
        setState(() {
          _timeline.history(
            history.content,
            seed: _timeline.cursor == null && next == 0,
          );
          _history ??= history;
        });
        _liveHistoryPage = history.hasNext ? (next + 1) % pages : 0;
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _failed(error, accessCheck: true));
        _watch();
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
        if (_liveDirty) {
          _queueLive();
        }
      }
    }
  }

  void _failed(ApiException error, {bool accessCheck = false}) {
    _error = error;
    if ((accessCheck && error.kind == ApiErrorKind.validation) ||
        [
          ApiErrorKind.forbidden,
          ApiErrorKind.unauthorized,
          ApiErrorKind.notFound,
        ].contains(error.kind)) {
      _conversation = null;
      _timeline.clear();
      _watch();
    }
  }

  Future<void> _refresh() async {
    if (_working || _refreshing) return;
    _refreshing = true;
    final revision = ++_metadataRevision;
    final hadCursor = _timeline.cursor != null;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final conversation = await widget.repository.get(widget.conversationId);
      final history = await widget.repository.history(widget.conversationId);
      if (mounted && revision == _metadataRevision) {
        setState(() {
          _conversation = conversation;
          _history = history;
          // Reconcile by version; a delayed GET must not erase newer live data.
          _timeline.history(history.content, seed: _timeline.cursor == null);
          if (hadCursor && conversation.status == 'ACCEPTED') _liveDirty = true;
          _uncertain = false;
        });
        _watch();
      }
    } on ApiException catch (error) {
      if (mounted && revision == _metadataRevision) {
        setState(() => _failed(error, accessCheck: true));
      }
    } finally {
      _refreshing = false;
      if (mounted) {
        setState(() => _loading = false);
        if (_liveDirty) {
          _queueLive();
        }
      }
    }
  }

  Future<void> _metadata() async {
    final revision = ++_metadataRevision;
    try {
      final conversation = await widget.repository.get(widget.conversationId);
      if (mounted && revision == _metadataRevision) {
        setState(() => _conversation = conversation);
        _watch();
      }
    } on ApiException catch (error) {
      if (mounted && revision == _metadataRevision) {
        setState(() => _failed(error, accessCheck: true));
      }
    }
  }

  Future<void> _historyMore() async {
    if (_working || _loading || (_history != null && !_history!.hasNext)) {
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final history = await widget.repository.history(
        widget.conversationId,
        page: _history == null ? 0 : _history!.page + 1,
      );
      if (mounted) {
        setState(() {
          _history = history;
          _timeline.history(history.content, seed: _timeline.cursor == null);
        });
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _failed(error, accessCheck: true));
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
        if (_liveDirty) {
          _queueLive();
        }
      }
    }
  }

  Future<void> _sync() async {
    final cursor = _timeline.cursor, conversation = _conversation;
    if (cursor == null || conversation == null || _working || _loading) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final sync = await widget.repository.sync(conversation, cursor);
      if (mounted) {
        setState(() {
          _timeline.apply(sync);
          _notice = sync.hasMore
              ? 'More changes are available.'
              : 'Sync completed.';
        });
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _failed(error, accessCheck: true));
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<bool> _mutate(
    Future<void> Function() action,
    String notice, {
    bool sending = false,
  }) async {
    if (_working || _loading || _uncertain) return false;
    setState(() {
      _working = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
      widget.repository.live?.chatChanged(
        widget.repository.ownerId,
        widget.conversationId,
      );
      if (mounted) {
        setState(() => _notice = notice);
      }
      return true;
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _failed(error);
          _uncertain = uncertainChatOutcome(error);
          if (sending && _uncertain) {
            _sendUncertain = true;
          }
        });
      }
      if (mounted && error.statusCode == 400) await _metadata();
      return false;
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _send() async {
    final conversation = _conversation;
    if (conversation == null || _sendUncertain) return;
    final sent = await _mutate(
      () async {
        final message = await widget.repository.send(conversation, _draft.text);
        if (mounted) {
          setState(() {
            _timeline.merge(message);
            _draft.clear();
          });
        }
      },
      'Message saved by the server.',
      sending: true,
    );
    if (sent && mounted) {
      // Do not seed from our send: another message could have arrived first.
      if (_timeline.cursor == null) {
        _history = null;
        await _historyMore();
      }
      if (mounted) {
        await _metadata();
      }
    }
  }

  Future<bool> _confirm(String title, String text) async {
    if (_dialogOpen) return false;
    _dialogOpen = true;
    try {
      return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(title),
              content: Text(text),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Confirm'),
                ),
              ],
            ),
          ) ==
          true;
    } finally {
      _dialogOpen = false;
    }
  }

  Future<void> _decision(bool accept) async {
    if (_working ||
        _loading ||
        _uncertain ||
        _dialogOpen ||
        _conversation?.canDecide(widget.repository.ownerId) != true) {
      return;
    }
    final target = _conversation!;
    if (!await _confirm(
      accept ? 'Accept request?' : 'Reject request?',
      accept
          ? 'Allow ordinary messaging in this conversation?'
          : 'Reject this conversation request?',
    )) {
      return;
    }
    if (!mounted ||
        _conversation?.id != target.id ||
        _conversation?.canDecide(widget.repository.ownerId) != true) {
      return;
    }
    final done = await _mutate(
      () async {
        final conversation = await widget.repository.decide(
          target,
          accept: accept,
        );
        if (mounted) {
          setState(() => _conversation = conversation);
        }
      },
      accept
          ? 'Request accepted by the server.'
          : 'Request rejected by the server.',
    );
    if (done && mounted) {
      await _refresh();
    }
  }

  Future<void> _change(ChatMessage message, {required bool deleting}) async {
    if (_dialogOpen || _working || _loading || _uncertain) return;
    String? text;
    if (deleting) {
      if (!await _confirm(
        'Delete message?',
        'The message will be replaced with a deletion marker.',
      )) {
        return;
      }
    } else {
      _dialogOpen = true;
      try {
        text = await showDialog<String>(
          context: context,
          builder: (_) => ChatTextDialog(
            repository: widget.repository,
            text: message.text ?? '',
          ),
        );
      } finally {
        _dialogOpen = false;
      }
      if (text == null) return;
    }
    if (!mounted || _conversation == null) return;
    await _mutate(
      () async {
        final result = await widget.repository.change(
          _conversation!,
          message,
          text: text,
        );
        if (mounted) {
          setState(() => _timeline.merge(result));
        }
      },
      deleting
          ? 'Message deleted by the server.'
          : 'Message edited by the server.',
    );
  }

  Future<void> _ack(ChatMessage message, bool seen) async {
    final done = await _mutate(
      () async {
        final result = await widget.repository.acknowledge(
          widget.conversationId,
          message,
          seen: seen,
        );
        if (mounted) {
          setState(() => _timeline.merge(result));
        }
      },
      seen ? 'Seen acknowledgement saved.' : 'Delivery acknowledgement saved.',
    );
    if (done && mounted) {
      await _metadata();
    }
  }

  Future<void> _read(ChatMessage through) async {
    ChatReadResult? result;
    final done = await _mutate(() async {
      result = await widget.repository.markRead(widget.conversationId, through);
    }, 'Read marker saved.');
    if (done && mounted) {
      setState(
        () => _notice =
            'Server marked ${result!.markedSeenCount} messages seen through #${result!.messageId}. Refresh history for receipt updates.',
      );
      await _metadata();
    }
  }

  Future<void> _unlockSend() async {
    if (_working || _loading || _uncertain || _dialogOpen) return;
    if (await _confirm(
      'Allow a new send?',
      'The previous send may have succeeded. Review the history and sync results first. This only unlocks the composer; it does not retry a message.',
    )) {
      if (mounted) {
        setState(() => _sendUncertain = false);
      }
    }
  }

  Widget _message(ChatMessage message) {
    final own = message.senderId == widget.repository.ownerId;
    final mutate =
        !_working && !_uncertain && _conversation?.status == 'ACCEPTED';
    return Card(
      key: ValueKey(message.id),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Message #${message.id} · ${own
                  ? 'You'
                  : message.senderId == null
                  ? 'Sender unavailable'
                  : 'User ID ${message.senderId}'} · ${message.type}',
            ),
            if (message.text != null) SelectableText(message.text!),
            Text('Created: ${message.createdAt}'),
            if (message.editedAt != null) Text('Edited: ${message.editedAt}'),
            Text('Server receipt status: ${message.status}'),
            Wrap(
              spacing: 8,
              children: [
                if (own && message.type == 'TEXT')
                  TextButton(
                    onPressed: mutate
                        ? () => _change(message, deleting: false)
                        : null,
                    child: const Text('Edit message'),
                  ),
                if (own)
                  TextButton(
                    onPressed: mutate
                        ? () => _change(message, deleting: true)
                        : null,
                    child: const Text('Delete message'),
                  ),
                if (!own && message.senderId != null) ...[
                  TextButton(
                    onPressed:
                        _working || _uncertain || message.status != 'SENT'
                        ? null
                        : () => _ack(message, false),
                    child: const Text('Acknowledge delivered'),
                  ),
                  TextButton(
                    onPressed:
                        _working || _uncertain || message.status == 'SEEN'
                        ? null
                        : () => _ack(message, true),
                    child: const Text('Acknowledge seen'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_liveDirty &&
        !_loading &&
        !_working &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _queueLive();
        }
      });
    }
    final conversation = _conversation;
    final messages = _timeline.messages;
    final incoming =
        messages
            .where(
              (message) =>
                  message.senderId != null &&
                  message.senderId != widget.repository.ownerId,
            )
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    final canSend =
        conversation?.status == 'ACCEPTED' &&
        !_working &&
        !_uncertain &&
        !_sendUncertain;
    return ChatAccess(
      repository: widget.repository,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Conversation #${widget.conversationId}'),
          actions: [
            if (conversation?.status == 'ACCEPTED')
              PopupMenuButton<bool>(
                tooltip: 'Video calls',
                icon: const Icon(Icons.video_call_outlined),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: false, child: Text('Start call')),
                  PopupMenuItem(value: true, child: Text('Schedule call')),
                ],
                onSelected: (scheduled) async {
                  final repository = CallRepository(widget.repository);
                  final saved = await Navigator.push<CallRecord>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CallForm(
                        repository: repository,
                        scheduled: scheduled,
                        recipient: conversation!.other(
                          widget.repository.ownerId,
                        ),
                        conversationId: conversation.id,
                      ),
                    ),
                  );
                  if (!context.mounted || saved == null) return;
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CallDetail(
                        repository: repository,
                        id: saved.id,
                        scheduled: saved.scheduled,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        body: _loading
            ? const LoadingView()
            : conversation == null
            ? ErrorView(
                error:
                    _error ??
                    const ApiException(
                      kind: ApiErrorKind.notFound,
                      message: 'Conversation unavailable.',
                    ),
                onRetry: _refresh,
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            Text(
                              'User ID ${conversation.other(widget.repository.ownerId) ?? 'unavailable'} · ${conversation.type}',
                            ),
                            Text('Conversation status: ${conversation.status}'),
                            if (widget.repository.live != null)
                              Text(widget.repository.live!.status),
                            if (conversation.status == 'PENDING')
                              const Text(
                                'Request pending. You may review the initial history; ordinary messaging requires acceptance.',
                              ),
                            if (conversation.status == 'REJECTED')
                              const Text(
                                'Request rejected. There is no reopen action for this request.',
                              ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                TextButton(
                                  onPressed: _working ? null : _refresh,
                                  child: const Text('Refresh history'),
                                ),
                                if (conversation.status == 'ACCEPTED')
                                  TextButton(
                                    onPressed:
                                        _working || _timeline.cursor == null
                                        ? null
                                        : _sync,
                                    child: Text(
                                      _timeline.hasMoreSync
                                          ? 'Sync more changes'
                                          : 'Sync latest',
                                    ),
                                  ),
                                if (conversation.canDecide(
                                  widget.repository.ownerId,
                                )) ...[
                                  FilledButton(
                                    onPressed: _working || _uncertain
                                        ? null
                                        : () => _decision(true),
                                    child: const Text('Accept request'),
                                  ),
                                  TextButton(
                                    onPressed: _working || _uncertain
                                        ? null
                                        : () => _decision(false),
                                    child: const Text('Reject request'),
                                  ),
                                ],
                                if (incoming.isNotEmpty)
                                  TextButton(
                                    onPressed: _working || _uncertain
                                        ? null
                                        : () => _read(incoming.last),
                                    child: Text(
                                      'Mark incoming through #${incoming.last.id} read',
                                    ),
                                  ),
                              ],
                            ),
                            if (_timeline.cursor == null)
                              const Text(
                                'No sync cursor yet. Refresh history to discover the first message.',
                              ),
                            if (_error != null)
                              ErrorView(
                                error: _error!,
                                onRetry: _working ? null : _refresh,
                              ),
                            if (_uncertain)
                              const Text(
                                'The last operation could not be confirmed. Refresh before another mutation.',
                              ),
                            const Text(
                              'History is oldest-first. Load later pages or sync for newer messages. Refresh history for edits and receipt changes.',
                            ),
                            if (messages.isEmpty && _error == null)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('No live messages loaded.'),
                              ),
                            for (final message in messages) _message(message),
                            if (_history?.hasNext == true)
                              FilledButton.tonal(
                                onPressed: _working ? null : _historyMore,
                                child: const Text('Load later history'),
                              ),
                            for (final tombstone in _timeline.tombstones)
                              Card(
                                child: ListTile(
                                  title: Text(
                                    'Message #${tombstone.id} deleted',
                                  ),
                                  subtitle: Text(
                                    'Deleted: ${tombstone.deletedAt}',
                                  ),
                                ),
                              ),
                            if (_working) const LinearProgressIndicator(),
                          ],
                        ),
                      ),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_notice != null)
                                Text(
                                  _notice!,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (_sendUncertain) ...[
                                const Text(
                                  'The send result is unknown. Your draft is retained; it has not been retried.',
                                ),
                                TextButton(
                                  onPressed: _working || _uncertain
                                      ? null
                                      : _unlockSend,
                                  child: const Text(
                                    'Allow a new send after review',
                                  ),
                                ),
                              ],
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: TextField(
                                      key: const ValueKey('chat-composer'),
                                      controller: _draft,
                                      enabled: canSend,
                                      maxLines: 3,
                                      minLines: 1,
                                      maxLength: 4000,
                                      decoration: const InputDecoration(
                                        labelText: 'Text message',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    onPressed: canSend ? _send : null,
                                    child: Text(
                                      _working ? 'Please wait…' : 'Send',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
