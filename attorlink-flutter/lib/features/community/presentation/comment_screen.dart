import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../data/community_repository.dart';
import '../data/community_features.dart';
import '../domain/community_extras.dart';
import '../domain/community_models.dart';
import 'community_access.dart';
import 'community_page_list.dart';
import 'report_screen.dart';

class CommunityComments extends StatefulWidget {
  const CommunityComments({
    super.key,
    required this.repository,
    required this.postId,
    this.parentId,
    this.feedMode,
  });
  final CommunityRepository repository;
  final int postId;
  final int? parentId;
  final String? feedMode;
  @override
  State<CommunityComments> createState() => _CommunityCommentsState();
}

class _CommunityCommentsState extends State<CommunityComments> {
  int _revision = 0;
  bool _acting = false, _uncertain = false;
  String? _error;
  void _reload() {
    setState(() {
      _revision++;
      _uncertain = false;
      _error = null;
    });
  }

  Future<void> _edit({CommunityComment? editing}) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CommentEditor(
          repository: widget.repository,
          postId: widget.postId,
          parentId: widget.parentId,
          editing: editing,
          feedMode: widget.feedMode,
        ),
      ),
    );
    if (mounted) {
      _reload();
    }
  }

  Future<void> _act(
    Future<void> Function() action, {
    Future<bool> Function()? confirm,
  }) async {
    if (_acting || _uncertain) return;
    final repository = widget.repository;
    setState(() {
      _acting = true;
      _error = null;
    });
    try {
      repository.checkAccess();
      if (confirm != null && !await confirm()) return;
      if (!mounted) return;
      repository.checkAccess();
      await action();
      if (mounted) {
        _reload();
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = communityErrorMessage(error);
          _uncertain = uncertainCommunityOperation(error);
          if (error.kind == ApiErrorKind.notFound ||
              error.kind == ApiErrorKind.forbidden) {
            _revision++;
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() => _acting = false);
      }
    }
  }

  Future<void> _delete(CommunityComment comment) async {
    final repository = widget.repository;
    await _act(
      () => repository.deleteComment(comment),
      confirm: () async =>
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete comment?'),
              content: const Text('This removes your comment or reply.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ) ==
          true,
    );
  }

  Future<void> _replies(CommunityComment comment) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CommunityComments(
          repository: widget.repository,
          postId: widget.postId,
          parentId: comment.id,
          feedMode: widget.feedMode,
        ),
      ),
    );
    if (mounted) {
      _reload();
    }
  }

  Widget _comment(CommunityComment comment) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Comment #${comment.id}${comment.authorId == null ? '' : ' · Author ID ${comment.authorId}'}',
          ),
          if (comment.parentId != null)
            Text('Reply to comment #${comment.parentId}'),
          if (comment.createdAt != null) Text('Posted: ${comment.createdAt}'),
          if (comment.updatedAt != null) Text('Updated: ${comment.updatedAt}'),
          if (comment.deleted)
            const Text('Comment unavailable.')
          else ...[
            if (comment.text != null) SelectableText(comment.text!),
            Text('${comment.upvotes} upvotes · ${comment.downvotes} downvotes'),
            if (comment.vote != null) Text('Your vote: ${comment.vote}'),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => _replies(comment),
                  child: const Text('Replies'),
                ),
                TextButton(
                  onPressed: _acting || _uncertain
                      ? null
                      : () async {
                          await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CommentEditor(
                                repository: widget.repository,
                                postId: widget.postId,
                                parentId: comment.id,
                                feedMode: widget.feedMode,
                              ),
                            ),
                          );
                          if (mounted) {
                            _reload();
                          }
                        },
                  child: const Text('Reply'),
                ),
                for (final vote in ['UPVOTE', 'DOWNVOTE'])
                  TextButton(
                    onPressed: _acting || _uncertain
                        ? null
                        : () => _act(() async {
                            await widget.repository.voteComment(comment, vote);
                          }),
                    child: Text(vote == 'UPVOTE' ? 'Upvote' : 'Downvote'),
                  ),
                TextButton(
                  onPressed: _acting || _uncertain || comment.vote == null
                      ? null
                      : () => _act(() async {
                          await widget.repository.voteComment(comment, null);
                        }),
                  child: const Text('Remove vote'),
                ),
                if (comment.authorId == widget.repository.ownerId) ...[
                  TextButton(
                    onPressed: _acting || _uncertain
                        ? null
                        : () => _edit(editing: comment),
                    child: const Text('Edit'),
                  ),
                  TextButton(
                    onPressed: _acting || _uncertain
                        ? null
                        : () => _delete(comment),
                    child: const Text('Delete'),
                  ),
                ] else
                  TextButton(
                    onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ContentReportScreen(
                          repository: widget.repository,
                          targetType: 'COMMENT',
                          targetId: comment.id,
                          authorId: comment.authorId,
                        ),
                      ),
                    ),
                    child: const Text('Report'),
                  ),
              ],
            ),
          ],
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => CommunityAccess(
    repository: widget.repository,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.parentId == null
              ? 'Comments and replies'
              : 'Replies to #${widget.parentId}',
        ),
      ),
      body: CommunityPageList<CommunityComment>(
        key: ValueKey(_revision),
        load: (page) => widget.repository.comments(
          widget.postId,
          parentId: widget.parentId,
          page: page,
        ),
        identity: (comment) => comment.id,
        retain: (comment) => !comment.deleted,
        item: _comment,
        header: [
          Text(
            'Post #${widget.postId}. Comment permissions are determined by the post author’s privacy rules.',
          ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: _acting || _uncertain ? null : () => _edit(),
                child: Text(
                  widget.parentId == null ? 'Add comment' : 'Add reply',
                ),
              ),
              TextButton(
                onPressed: _acting ? null : _reload,
                child: const Text('Refresh comments'),
              ),
            ],
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_uncertain)
            const Text(
              'Result not confirmed. Refresh comments before another action.',
            ),
        ],
      ),
    ),
  );
}

class CommentEditor extends StatefulWidget {
  const CommentEditor({
    super.key,
    required this.repository,
    required this.postId,
    this.parentId,
    this.editing,
    this.feedMode,
  });
  final CommunityRepository repository;
  final int postId;
  final int? parentId;
  final CommunityComment? editing;
  final String? feedMode;
  @override
  State<CommentEditor> createState() => _CommentEditorState();
}

class _CommentEditorState extends State<CommentEditor> {
  late final _text = TextEditingController(text: widget.editing?.text ?? '');
  bool _busy = false, _uncertain = false;
  String? _error, _tracking;
  bool _saved = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || _uncertain || _saved) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.writeComment(
        widget.postId,
        _text.text,
        editing: widget.editing,
        parentId: widget.parentId,
      );
      if (!mounted) return;
      setState(() => _saved = true);
      if (widget.editing == null) {
        final tracking = await widget.repository.trackEvent(
          widget.postId,
          'COMMENT_CREATED',
          mode: widget.feedMode,
        );
        if (mounted) {
          setState(() => _tracking = tracking);
        }
      }
      if (mounted && _tracking == null) {
        Navigator.pop(context, true);
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

  @override
  Widget build(BuildContext context) => CommunityAccess(
    repository: widget.repository,
    child: PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.editing != null
                ? 'Edit comment'
                : widget.parentId == null
                ? 'Add comment'
                : 'Reply to #${widget.parentId}',
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _text,
              maxLength: 5000,
              maxLines: 8,
              enabled: !_busy && !_uncertain && !_saved,
              decoration: const InputDecoration(labelText: 'Comment text'),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_uncertain)
              const Text(
                'The save result is unknown. Return to the thread and refresh before trying again.',
              ),
            if (_saved) const Text('Comment saved.'),
            if (_tracking != null) Text(_tracking!),
            if (_saved)
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Return to comments'),
              )
            else
              FilledButton(
                onPressed: _busy || _uncertain ? null : _save,
                child: Text(_busy ? 'Saving…' : 'Save comment'),
              ),
          ],
        ),
      ),
    ),
  );
}
