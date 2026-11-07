import '../../calls/data/call_repository.dart';
import '../../calls/presentation/call_screens.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/live_updates.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../auth/domain/auth_models.dart';
import '../../community/data/community_repository.dart';
import '../../community/presentation/community_screen.dart';
import '../../community/presentation/connections_screen.dart';
import '../../community/presentation/post_detail.dart';
import '../../messaging/data/chat_repository.dart';
import '../../messaging/presentation/chat_inbox.dart';
import '../../messaging/presentation/chat_thread.dart';
import '../data/notification_repository.dart';
import '../domain/notification_models.dart';

class NotificationEntry extends StatefulWidget {
  const NotificationEntry({
    super.key,
    required this.repository,
    required this.chat,
    required this.community,
  });
  final NotificationRepository repository;
  final ChatRepository chat;
  final CommunityRepository community;
  @override
  State<NotificationEntry> createState() => _NotificationEntryState();
}

class _NotificationEntryState extends State<NotificationEntry> {
  @override
  void initState() {
    super.initState();
    widget.repository.live?.activate();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<LiveEvent>(
    stream: widget.repository.live?.events,
    builder: (context, _) {
      final count = widget.repository.live?.unreadCount;
      return IconButton(
        tooltip: count == null
            ? 'Notifications'
            : 'Notifications ($count unread)',
        icon: Badge(
          label: Text('$count'),
          isLabelVisible: count != null && count > 0,
          child: const Icon(Icons.notifications_outlined),
        ),
        onPressed: () => Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => NotificationInbox(
              repository: widget.repository,
              chat: widget.chat,
              community: widget.community,
            ),
          ),
        ),
      );
    },
  );
}

class NotificationAccess extends StatelessWidget {
  const NotificationAccess({
    super.key,
    required this.repository,
    required this.child,
  });
  final NotificationRepository repository;
  final Widget child;
  @override
  Widget build(BuildContext context) => StreamBuilder<Object?>(
    stream: repository.accessChanges,
    builder: (context, _) {
      try {
        repository.checkAccess();
      } on ApiException catch (error) {
        return Scaffold(
          appBar: AppBar(title: const Text('Notifications')),
          body: ErrorView(error: error),
        );
      }
      return child;
    },
  );
}

class NotificationInbox extends StatefulWidget {
  const NotificationInbox({
    super.key,
    required this.repository,
    required this.chat,
    required this.community,
  });
  final NotificationRepository repository;
  final ChatRepository chat;
  final CommunityRepository community;
  @override
  State<NotificationInbox> createState() => _NotificationInboxState();
}

class _NotificationInboxState extends State<NotificationInbox> {
  final _cache = NotificationCache();
  ApiPage<NotificationItem>? _page;
  int? _unread;
  int _unreadRevision = 0;
  ApiException? _error;
  String? _notice, _countError;
  bool _busy = false, _acting = false, _dirty = false;
  StreamSubscription<LiveEvent>? _events;
  Timer? _refreshTimer;
  @override
  void initState() {
    super.initState();
    widget.repository.live?.activate();
    _events = widget.repository.live?.events.listen((event) {
      if (!mounted || !widget.repository.acceptsEvent(event)) return;
      if (event.kind == LiveKind.unread || event.kind == LiveKind.state) {
        setState(() {
          if (event.kind == LiveKind.unread) {
            ++_unreadRevision;
            _unread = widget.repository.live?.unreadCount;
          }
        });
      }
      if (event.notification != null) {
        setState(() => _cache.merge(event.notification!));
      }
      if ([LiveKind.notification, LiveKind.reconcile].contains(event.kind)) {
        _queueRefresh();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    unawaited(_events?.cancel() ?? Future<void>.value());
    super.dispose();
  }

  void _queueRefresh() {
    _dirty = true;
    if (_refreshTimer?.isActive == true) return;
    _refreshTimer = Timer(const Duration(milliseconds: 250), () {
      _refreshTimer = null;
      if (!mounted ||
          widget.repository.live?.paused == true ||
          _busy ||
          _acting ||
          !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return;
      }
      _dirty = false;
      unawaited(_load());
    });
  }

  Future<void> _load({bool more = false}) async {
    if (more && _page?.hasNext != true) return;
    if (_busy || _acting) {
      _dirty = true;
      return;
    }
    _dirty = false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      try {
        final revision = _unreadRevision;
        final count = await widget.repository.unread();
        if (!mounted) return;
        setState(() {
          if (revision == _unreadRevision) _unread = count;
          _countError = null;
        });
      } on ApiException catch (error) {
        if (mounted) {
          setState(() => _countError = 'Unread count: ${error.message}');
        }
      }
      final first = more ? (_page!.page + 1) : 0;
      final last = more ? first : (_page?.page ?? 0);
      for (var i = first; i <= last; i++) {
        final page = await widget.repository.list(page: i);
        if (!mounted) return;
        setState(() {
          for (final item in page.content) {
            _cache.merge(item);
          }
          _page = page;
        });
        if (!page.hasNext) break;
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          if ([
            ApiErrorKind.forbidden,
            ApiErrorKind.unauthorized,
          ].contains(error.kind)) {
            _cache.clear();
            _unread = null;
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_dirty) {
          _queueRefresh();
        }
      }
    }
  }

  Future<void> _read(NotificationItem? item) async {
    if (_acting || _busy) return;
    var saved = false;
    setState(() {
      _acting = true;
      _error = null;
    });
    try {
      if (item == null) {
        final knownBefore = _cache.items;
        final count = await widget.repository.readAll();
        if (mounted) {
          setState(() {
            for (final known in knownBefore) {
              _cache.merge(known.asRead());
            }
            _notice = '$count notifications marked read by the server.';
          });
        }
      } else {
        final result = await widget.repository.read(item.id);
        if (mounted) {
          setState(() => _cache.merge(result));
        }
      }
      saved = true;
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _dirty = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _acting = false);
        if (saved || _dirty) {
          _dirty = false;
          await _load();
        }
      }
    }
  }

  bool _canOpen(NotificationItem item) {
    if (item.resourceId == null ||
        item.recipientId != widget.repository.ownerId) {
      return false;
    }
    if (item.resourceType?.toLowerCase() == 'user') {
      // FOLLOW targets the notified lawyer; ACCOUNT targets the account itself.
      // There is no generic user-profile destination for other USER notices.
      return item.type.toUpperCase() == 'FOLLOW' &&
          item.resourceId == item.recipientId &&
          widget.repository.currentUser()?.role == UserRole.lawyer;
    }
    return [
      'post',
      'comment',
      'chat_conversation',
      'chat_message',
      'video_call',
    ].contains(item.resourceType?.toLowerCase());
  }

  Future<void> _open(NotificationItem item) async {
    if (!mounted || !_canOpen(item)) return;
    try {
      widget.repository.checkAccess();
    } on ApiException catch (error) {
      setState(() => _error = error);
      return;
    }
    final id = item.resourceId;
    if (id == null) return;
    final Widget? target = switch (item.resourceType?.toLowerCase()) {
      // The backend uses VIDEO_CALL for both immediate and scheduled IDs.
      // Open the inbox rather than guessing which ID namespace applies.
      'video_call' => CallsScreen(repository: CallRepository(widget.chat)),
      'post' => CommunityPostDetail(repository: widget.community, postId: id),
      'chat_conversation' => ChatThreadScreen(
        repository: widget.chat,
        conversationId: id,
      ),
      'chat_message' => Scaffold(
        appBar: AppBar(title: const Text('Messages')),
        body: ChatInboxScreen(repository: widget.chat),
      ), // A message ID is NOT a conversation ID.
      'comment' => Scaffold(
        appBar: AppBar(title: const Text('Community')),
        body: CommunityScreen(repository: widget.community),
      ), // No standalone comment-to-post lookup exists.
      'user' => CommunityConnections(
        repository: widget.community,
        lawyerUserId: id,
        showFollowingFeed: false,
      ),
      _ => null,
    };
    if (target != null) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => target),
      );
    }
    if (mounted && _dirty) {
      _dirty = false;
      await _load();
    }
  }

  Future<void> _detail(NotificationItem item) async {
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => NotificationAccess(
        repository: widget.repository,
        child: AlertDialog(
          title: Text(item.title),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.message),
                  Text('Type: ${item.type}'),
                  Text(
                    'Notification #${item.id} · ${item.read ? 'Read' : 'Unread'}',
                  ),
                  if (item.actorId != null)
                    Text('Actor user ID: ${item.actorId}'),
                  if (item.text('createdAt') != null)
                    Text('Created: ${item.text('createdAt')}'),
                  if (item.text('readAt') != null)
                    Text('Read: ${item.text('readAt')}'),
                  if (item.resourceType != null)
                    Text(
                      'Related: ${item.resourceType} #${item.resourceId ?? 'unavailable'}',
                    ),
                  if (item.resourceType?.toLowerCase() == 'chat_message')
                    const Text(
                      'Open Messages to select the conversation for this message.',
                    ),
                  if (item.resourceType?.toLowerCase() == 'comment')
                    const Text(
                      'Open Community to locate this comment in its post.',
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Close'),
            ),
            if (_canOpen(item))
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Open related area'),
              ),
          ],
        ),
      ),
    );
    if (open == true && mounted) {
      await _open(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dirty &&
        !_busy &&
        !_acting &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _queueRefresh();
        }
      });
    }
    final live = widget.repository.live;
    return NotificationAccess(
      repository: widget.repository,
      child: Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              (_unread ?? live?.unreadCount) == null
                  ? 'Unread count unavailable'
                  : '${_unread ?? live?.unreadCount} unread',
            ),
            if (_countError != null) Text(_countError!),
            if (live != null) Text(live.status),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _busy || _acting ? null : () => _load(),
                  child: const Text('Refresh notifications'),
                ),
                TextButton(
                  onPressed: _busy || _acting ? null : () => _read(null),
                  child: const Text('Mark all read'),
                ),
                if (live != null)
                  TextButton(
                    onPressed: live.reconnect,
                    child: const Text('Reconnect realtime'),
                  ),
              ],
            ),
            if (_notice != null) Text(_notice!),
            if (_error != null)
              ErrorView(error: _error!, onRetry: () => _load()),
            if (_cache.items.isEmpty && !_busy && _error == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No notifications.'),
              ),
            for (final item in _cache.items)
              Card(
                key: ValueKey(item.id),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(item.message),
                      Text('${item.type} · ${item.read ? 'Read' : 'Unread'}'),
                      if (item.text('createdAt') != null)
                        Text(item.text('createdAt')!),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () => _detail(item),
                            child: const Text('Details'),
                          ),
                          if (!item.read)
                            TextButton(
                              onPressed: _busy || _acting
                                  ? null
                                  : () => _read(item),
                              child: const Text('Mark read'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (_busy || _acting) const LoadingView(),
            if (_page?.hasNext == true && !_busy && !_acting)
              Center(
                child: FilledButton.tonal(
                  onPressed: () => _load(more: true),
                  child: const Text('Load more notifications'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
