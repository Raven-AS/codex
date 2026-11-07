import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/domain/auth_models.dart';
import '../data/community_repository.dart';
import '../data/community_features.dart';
import '../domain/community_extras.dart';
import '../domain/community_models.dart';
import 'community_access.dart';
import 'community_page_list.dart';

class CommunityConnections extends StatefulWidget {
  const CommunityConnections({
    super.key,
    required this.repository,
    this.lawyerUserId,
    this.showFollowingFeed = true,
  });
  final CommunityRepository repository;
  final int? lawyerUserId;
  final bool showFollowingFeed;
  @override
  State<CommunityConnections> createState() => _CommunityConnectionsState();
}

class _CommunityConnectionsState extends State<CommunityConnections> {
  late final _id = TextEditingController(
    text:
        (widget.lawyerUserId ??
                (widget.repository.currentUser()?.role == UserRole.lawyer
                    ? widget.repository.ownerId
                    : null))
            ?.toString() ??
        '',
  );
  late int? _followersOf =
      widget.lawyerUserId ??
      (widget.repository.currentUser()?.role == UserRole.lawyer
          ? widget.repository.ownerId
          : null);
  int _revision = 0;
  bool _busy = false, _uncertain = false;
  String? _error, _message;
  bool get _client => widget.repository.currentUser()?.role == UserRole.client;
  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  int _target() {
    final id = int.tryParse(_id.text.trim());
    if (id == null || id <= 0) {
      throw const ApiException(
        kind: ApiErrorKind.validation,
        message: 'Enter a positive lawyer user ID.',
      );
    }
    return id;
  }

  void _reload() {
    setState(() {
      _revision++;
      _uncertain = false;
      _error = null;
    });
  }

  Future<void> _follow({int? remove}) async {
    if (_busy || _uncertain) return;
    final repository = widget.repository;
    setState(() {
      _busy = true;
      _error = _message = null;
    });
    try {
      repository.checkAccess();
      if (remove != null) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Unfollow lawyer?'),
            content: Text('Stop following lawyer user ID $remove?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Unfollow'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      repository.checkAccess();
      if (remove == null) {
        await repository.followLawyer(_target());
      } else {
        await repository.unfollowLawyer(remove);
      }
      if (mounted) {
        setState(
          () => _message = remove == null
              ? 'Lawyer followed.'
              : 'Lawyer unfollowed.',
        );
        _reload();
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = communityErrorMessage(error);
          _uncertain = uncertainCommunityOperation(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _unfollow(int id) => _follow(remove: id);

  void _followers() {
    try {
      final id = _target();
      setState(() => _followersOf = id);
      _reload();
    } on ApiException catch (error) {
      setState(() => _error = communityErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) => CommunityAccess(
    repository: widget.repository,
    child: Scaffold(
      appBar: AppBar(title: const Text('Lawyer connections')),
      body: CommunityPageList<LawyerConnection>(
        key: ValueKey((_revision, _followersOf)),
        load: (page) => widget.repository.connections(
          lawyerUserId: _followersOf,
          page: page,
        ),
        identity: (follow) => follow.id ?? (follow.followerId, follow.lawyerId),
        header: [
          const Text(
            'Following is available to active clients for active, verified lawyers. Use a user ID, not a lawyer profile ID.',
          ),
          TextField(
            controller: _id,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Lawyer user ID'),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_client)
                FilledButton(
                  onPressed: _busy || _uncertain ? null : () => _follow(),
                  child: const Text('Follow lawyer'),
                ),
              TextButton(
                onPressed: _busy ? null : _followers,
                child: const Text('Show followers'),
              ),
              if (_client)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() => _followersOf = null);
                          _reload();
                        },
                  child: const Text('My following'),
                ),
              TextButton(
                onPressed: _busy ? null : _reload,
                child: const Text('Refresh connections'),
              ),
              if (_client && widget.showFollowingFeed)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () =>
                            Navigator.pop(context, CommunityCategory.following),
                  child: const Text('View following feed'),
                ),
            ],
          ),
          Text(
            _followersOf == null
                ? 'Lawyers you follow'
                : 'Followers of lawyer user ID $_followersOf',
          ),
          if (_message != null) Text(_message!),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_uncertain)
            const Text(
              'Result not confirmed. Refresh connections before another action.',
            ),
        ],
        item: (follow) => Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Lawyer user ID: ${follow.lawyerId ?? 'unavailable'}'),
                Text('Follower user ID: ${follow.followerId ?? 'unavailable'}'),
                if (follow.createdAt != null)
                  Text('Followed: ${follow.createdAt}'),
                if (_client &&
                    follow.followerId == widget.repository.ownerId &&
                    follow.lawyerId != null)
                  TextButton(
                    onPressed: _busy || _uncertain
                        ? null
                        : () => _unfollow(follow.lawyerId!),
                    child: const Text('Unfollow'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
