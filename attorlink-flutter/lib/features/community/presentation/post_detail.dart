import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../data/community_repository.dart';
import '../data/community_features.dart';
import '../domain/community_models.dart';
import 'post_editor.dart';
import 'community_access.dart';
import 'comment_screen.dart';
import 'report_screen.dart';
import 'analytics_screen.dart';
import 'connections_screen.dart';

class PostContent extends StatelessWidget {
  const PostContent({super.key, required this.post, this.preview = false});
  final CommunityPost post;
  final bool preview;
  @override
  Widget build(BuildContext context) {
    final url = Uri.tryParse(post.mediaUrl ?? '');
    final image =
        post.editable &&
        url != null &&
        ['https', 'http'].contains(url.scheme) &&
        url.host.isNotEmpty &&
        url.userInfo.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          post.authorId == null
              ? 'Author unavailable'
              : 'Author ID ${post.authorId}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Text('Post #${post.id} · ${post.type}'),
        if (post.sponsored) const Chip(label: Text('Sponsored')),
        if (post.createdAt != null) Text('Posted: ${post.createdAt}'),
        if (!preview && post.updatedAt != null)
          Text('Updated: ${post.updatedAt}'),
        const SizedBox(height: 12),
        if (post.deleted)
          const Text('This post is no longer available.')
        else ...[
          if (post.text != null)
            Text(
              post.text!,
              maxLines: preview ? 6 : null,
              overflow: preview ? TextOverflow.ellipsis : null,
            ),
          if (image)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Image.network(
                url.toString(),
                height: preview ? 220 : 320,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Text('Image unavailable.'),
              ),
            ),
          Text('${post.likeCount} likes'),
        ],
      ],
    );
  }
}

class CommunityPostDetail extends StatefulWidget {
  const CommunityPostDetail({
    super.key,
    required this.repository,
    required this.postId,
    this.feedMode,
  });
  final CommunityRepository repository;
  final int postId;
  final String? feedMode;
  @override
  State<CommunityPostDetail> createState() => _CommunityPostDetailState();
}

class _CommunityPostDetailState extends State<CommunityPostDetail> {
  CommunityPost? _post;
  ApiException? _error;
  bool _busy = true, _uncertain = false, _confirming = false, _loading = false;
  String? _message, _tracking;
  @override
  void initState() {
    super.initState();
    _load(trackClick: true);
  }

  Future<void> _track(String event) async {
    final error = await widget.repository.trackEvent(
      widget.postId,
      event,
      mode: widget.feedMode,
    );
    if (mounted && error != null) {
      setState(() => _tracking = error);
    }
  }

  Future<void> _load({bool trackClick = false}) async {
    if (_loading || (_busy && _post != null)) return;
    _loading = true;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final post = await widget.repository.get(widget.postId);
      if (mounted) {
        setState(() {
          _post = post;
          _uncertain = false;
        });
        if (trackClick && !post.deleted) {
          unawaited(_track('POST_CLICK'));
        }
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          if ([
            ApiErrorKind.notFound,
            ApiErrorKind.forbidden,
            ApiErrorKind.unauthorized,
          ].contains(error.kind)) {
            _post = null;
          }
        });
      }
    } finally {
      _loading = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _act(Future<void> Function() action, String message) async {
    if (_busy || _uncertain) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await action();
      if (!mounted) return;
      setState(() => _message = message);
      final post = await widget.repository.get(widget.postId);
      if (mounted) setState(() => _post = post);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _uncertain = uncertainCommunityOperation(error);
          if ([
            ApiErrorKind.notFound,
            ApiErrorKind.forbidden,
            ApiErrorKind.unauthorized,
          ].contains(error.kind)) {
            _post = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String text) async {
    if (_confirming) return false;
    _confirming = true;
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
      _confirming = false;
    }
  }

  Future<void> _delete() async {
    if (_busy || _uncertain || _confirming || _post == null) return;
    final post = _post!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await _confirm(
            'Delete post?',
            'This will remove your post from the community.',
          ) ||
          !mounted) {
        return;
      }
      await widget.repository.delete(post);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _uncertain = uncertainCommunityOperation(error);
          if ([
            ApiErrorKind.notFound,
            ApiErrorKind.forbidden,
            ApiErrorKind.unauthorized,
          ].contains(error.kind)) {
            _post = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    return CommunityAccess(
      repository: widget.repository,
      child: Scaffold(
        appBar: AppBar(title: const Text('Community post')),
        body: _busy
            ? const LoadingView()
            : post == null
            ? ErrorView(error: _error!, onRetry: _load)
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      PostContent(post: post),
                      if (_tracking != null) Text(_tracking!),
                      if (_message != null) Text(_message!),
                      if (_error != null)
                        ErrorView(error: _error!, onRetry: _load),
                      if (_uncertain)
                        const Text(
                          'The last result could not be confirmed. Reload the post before another action.',
                        ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          TextButton(
                            onPressed: _load,
                            child: const Text('Reload post'),
                          ),
                          if (!post.deleted && !_uncertain) ...[
                            TextButton(
                              onPressed: () => Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CommunityComments(
                                    repository: widget.repository,
                                    postId: post.id,
                                    feedMode: widget.feedMode,
                                  ),
                                ),
                              ),
                              child: const Text('Comments and replies'),
                            ),
                            if (post.authorId != widget.repository.ownerId)
                              TextButton(
                                onPressed: () => Navigator.push<void>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ContentReportScreen(
                                      repository: widget.repository,
                                      targetType: 'POST',
                                      targetId: post.id,
                                      authorId: post.authorId,
                                    ),
                                  ),
                                ),
                                child: const Text('Report post'),
                              ),
                            TextButton(
                              onPressed: () => Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CommunityAnalyticsScreen(
                                    repository: widget.repository,
                                    postId: post.id,
                                  ),
                                ),
                              ),
                              child: const Text('Event analytics'),
                            ),
                            if (post.authorId != null)
                              TextButton(
                                onPressed: () =>
                                    Navigator.push<CommunityCategory>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => CommunityConnections(
                                          repository: widget.repository,
                                          lawyerUserId: post.authorId,
                                          showFollowingFeed: false,
                                        ),
                                      ),
                                    ),
                                child: const Text('Author connections'),
                              ),
                            TextButton.icon(
                              onPressed: () => _act(() async {
                                final result = await widget.repository.like(
                                  post,
                                );
                                if (result.liked) {
                                  unawaited(_track('POST_LIKE'));
                                }
                              }, 'Like updated.'),
                              icon: Icon(
                                post.liked
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                              ),
                              label: Text(post.liked ? 'Unlike' : 'Like'),
                            ),
                            TextButton(
                              onPressed: () => _act(() async {
                                await widget.repository.save(
                                  post.id,
                                  saved: true,
                                );
                                unawaited(_track('POST_BOOKMARKED'));
                              }, 'Post saved.'),
                              child: const Text('Save post'),
                            ),
                            TextButton(
                              onPressed: () => _act(() async {
                                await widget.repository.save(
                                  post.id,
                                  saved: false,
                                );
                              }, 'Post removed from saved posts.'),
                              child: const Text('Remove from saved posts'),
                            ),
                            TextButton(
                              onPressed: () async {
                                if (await _confirm(
                                  'Record share?',
                                  'Record that you shared this post.',
                                )) {
                                  if (!mounted) return;
                                  await _act(() async {
                                    await widget.repository.share(post.id);
                                    unawaited(_track('POST_SHARED'));
                                  }, 'Share recorded.');
                                }
                              },
                              child: const Text('Record share'),
                            ),
                            if (post.authorId == widget.repository.ownerId) ...[
                              if (post.editable)
                                TextButton(
                                  onPressed: () async {
                                    await Navigator.push<bool>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => CommunityPostEditor(
                                          repository: widget.repository,
                                          post: post,
                                        ),
                                      ),
                                    );
                                    if (mounted) await _load();
                                  },
                                  child: const Text('Edit post'),
                                ),
                              TextButton(
                                onPressed: _delete,
                                child: const Text('Delete post'),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
