import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/live_updates.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../../core/utils/merge_records.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../data/chat_repository.dart';
import '../domain/chat_models.dart';
import 'chat_access.dart';
import 'chat_thread.dart';
import 'start_conversation.dart';

class ChatInboxScreen extends StatefulWidget {
  const ChatInboxScreen({super.key, required this.repository});
  final ChatRepository repository;
  @override
  State<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends State<ChatInboxScreen> {
  ChatInbox _tab = ChatInbox.all;
  String? _status;
  final _scroll = ScrollController();
  List<ChatConversation> _rows = [];
  ApiPage<ChatConversation>? _page;
  ApiException? _error;
  int _generation = 0;
  bool _busy = true, _more = false;
  bool _liveDirty = false, _liveBusy = false;
  Timer? _liveTimer;
  StreamSubscription<LiveEvent>? _liveEvents;
  final _watched = <int, void Function()>{};
  @override
  void initState() {
    super.initState();
    widget.repository.live?.activate();
    _liveEvents = widget.repository.live?.events.listen((event) {
      if (!mounted || !widget.repository.acceptsEvent(event)) return;
      if (event.kind == LiveKind.state) {
        setState(() {});
      }
      if ([
        LiveKind.reconcile,
        LiveKind.message,
        LiveKind.notification,
      ].contains(event.kind)) {
        _queueLive();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _liveTimer?.cancel();
    unawaited(_liveEvents?.cancel() ?? Future<void>.value());
    for (final release in _watched.values) {
      release();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _watches() {
    final live = widget.repository.live;
    if (live == null) return;
    final ids = _rows
        .where((row) => row.status == 'ACCEPTED')
        .map((row) => row.id)
        .toSet();
    for (final id in _watched.keys.toList()) {
      if (!ids.contains(id)) {
        _watched.remove(id)!();
      }
    }
    for (final id in ids) {
      _watched.putIfAbsent(
        id,
        () => live.watchConversation(widget.repository.ownerId, id),
      );
    }
  }

  void _queueLive() {
    _liveDirty = true;
    if (_liveTimer?.isActive == true) return;
    _liveTimer = Timer(const Duration(milliseconds: 250), () {
      _liveTimer = null;
      if (!mounted ||
          widget.repository.live?.paused == true ||
          _busy ||
          _more ||
          _liveBusy ||
          !TickerMode.valuesOf(context).enabled ||
          !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return;
      }
      unawaited(_refreshLive());
    });
  }

  Future<void> _refreshLive() async {
    if (_liveBusy || _busy || _more) {
      _liveDirty = true;
      return;
    }
    _liveDirty = false;
    setState(() => _liveBusy = true);
    final generation = _generation;
    final tab = _tab;
    final pages = _page?.page ?? 0;
    try {
      final rows = <ChatConversation>[];
      ApiPage<ChatConversation>? last;
      for (var i = 0; i <= pages; i++) {
        last = await widget.repository.inbox(tab, page: i);
        if (!mounted || generation != _generation) return;
        if (widget.repository.live?.paused == true) {
          _liveDirty = true;
          return;
        }
        rows.addAll(last.content);
        if (!last.hasNext) break;
      }
      if (mounted && generation == _generation) {
        setState(() {
          _rows = mergeRecords<ChatConversation>(
            [],
            rows,
            identity: (row) => row.id,
          );
          _page = last;
          _error = null;
        });
        _watches();
      }
    } on ApiException catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = error;
          if ([
            ApiErrorKind.forbidden,
            ApiErrorKind.unauthorized,
            ApiErrorKind.validation,
          ].contains(error.kind)) {
            _rows = [];
            _page = null;
          }
        });
        _watches();
      }
    } finally {
      if (mounted) setState(() => _liveBusy = false);
      if (mounted && _liveDirty) {
        _queueLive();
      }
    }
  }

  Future<void> _load({bool more = false}) async {
    if (more && (_busy || _more || _liveBusy || _page?.hasNext != true)) return;
    final generation = more ? _generation : ++_generation;
    final next = more ? _page!.page + 1 : 0;
    final tab = _tab;
    setState(() {
      _error = null;
      if (more) {
        _more = true;
      } else {
        _busy = true;
        _more = false;
        _rows = [];
        _page = null;
      }
    });
    if (!more && _scroll.hasClients) {
      _scroll.jumpTo(0);
    }
    try {
      final page = await widget.repository.inbox(tab, page: next);
      if (mounted && generation == _generation) {
        setState(() {
          _rows = mergeRecords(_rows, page.content, identity: (row) => row.id);
          _page = page;
        });
        _watches();
      }
    } on ApiException catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = error;
          if ([
            ApiErrorKind.forbidden,
            ApiErrorKind.unauthorized,
            ApiErrorKind.validation,
          ].contains(error.kind)) {
            _rows = [];
            _page = null;
          }
        });
        _watches();
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _more = false;
        });
        if (_liveDirty) {
          _queueLive();
        }
      }
    }
  }

  Future<void> _open(ChatConversation conversation) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ChatThreadScreen(
          repository: widget.repository,
          conversationId: conversation.id,
        ),
      ),
    );
    if (mounted) {
      await _load();
    }
  }

  Future<void> _start() async {
    final conversation = await Navigator.push<ChatConversation>(
      context,
      MaterialPageRoute(
        builder: (_) => StartConversation(repository: widget.repository),
      ),
    );
    if (!mounted) return;
    if (conversation != null) {
      await _open(conversation);
    } else {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_liveDirty &&
        !_busy &&
        !_more &&
        !_liveBusy &&
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _queueLive();
        }
      });
    }
    final rows = _rows
        .where(
          (row) =>
              (_tab != ChatInbox.sent ||
                  row.initiator == widget.repository.ownerId) &&
              (_status == null || row.status == _status),
        )
        .toList();
    return ChatAccess(
      repository: widget.repository,
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.all(16),
        children: [
          Text('Messages', style: Theme.of(context).textTheme.headlineSmall),
          const Text(
            'Private realtime events are reconciled with REST. Participants are identified by user ID.',
          ),
          if (widget.repository.live != null) ...[
            Text(widget.repository.live!.status),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: widget.repository.live!.reconnect,
                child: const Text('Reconnect realtime'),
              ),
            ),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tab in ChatInbox.values)
                ChoiceChip(
                  label: Text(tab.label),
                  selected: _tab == tab,
                  onSelected: (_) {
                    if (_tab == tab) return;
                    setState(() {
                      _tab = tab;
                      _status = null;
                    });
                    _load();
                  },
                ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('Start conversation'),
              ),
              TextButton(
                onPressed: _busy ? null : () => _load(),
                child: const Text('Refresh inbox'),
              ),
            ],
          ),
          if (_tab == ChatInbox.all || _tab == ChatInbox.sent)
            DropdownButtonFormField<String>(
              key: ValueKey((_tab, _status)),
              initialValue: _status,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Status on loaded pages',
              ),
              items: const [
                DropdownMenuItem<String>(
                  value: null,
                  child: Text('All statuses'),
                ),
                DropdownMenuItem(value: 'PENDING', child: Text('PENDING')),
                DropdownMenuItem(value: 'ACCEPTED', child: Text('ACCEPTED')),
                DropdownMenuItem(value: 'REJECTED', child: Text('REJECTED')),
              ],
              onChanged: (value) => setState(() => _status = value),
            ),
          if (_tab == ChatInbox.outgoing)
            const Text(
              'This endpoint lists pending requests only and may have incomplete pagination totals. Use Sent conversations to review all outgoing statuses across inbox pages.',
            ),
          if (_tab == ChatInbox.sent)
            const Text(
              'Sent conversations are selected from loaded inbox pages. Load more to review additional statuses.',
            ),
          if (_busy)
            const LoadingView()
          else ...[
            Text('${rows.length} matches on loaded pages'),
            if (rows.isEmpty && _error == null)
              const EmptyState(
                title: 'No conversations in this selection',
                message: 'Refresh or load more pages when available.',
              ),
            for (final row in rows)
              Card(
                child: ListTile(
                  title: Text(
                    'Conversation #${row.id} · User ID ${row.other(widget.repository.ownerId) ?? 'unavailable'}',
                  ),
                  subtitle: Text(
                    '${row.type}\n${row.status} · ${row.unreadCount} unread${row.lastMessageAt == null ? '' : '\nLast message: ${row.lastMessageAt}'}',
                  ),
                  isThreeLine: true,
                  onTap: () => _open(row),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
            if (_error != null)
              ErrorView(
                error: _error!,
                onRetry: () => _load(more: _page != null),
              ),
            if (_more) const LoadingView(),
            if (_page?.hasNext == true && !_more && _error == null)
              Center(
                child: FilledButton.tonal(
                  onPressed: _liveBusy ? null : () => _load(more: true),
                  child: const Text('Load more conversations'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
