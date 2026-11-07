import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../../core/utils/merge_records.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../auth/domain/auth_models.dart';
import '../data/community_repository.dart';
import '../data/community_features.dart';
import '../domain/community_models.dart';
import 'post_detail.dart';
import 'post_editor.dart';
import 'community_access.dart';
import 'connections_screen.dart';
import 'analytics_screen.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key, required this.repository});
  final CommunityRepository repository;
  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  CommunityCategory _category = CommunityCategory.forYou;
  ApiPage<CommunityPost>? _page;
  List<CommunityPost> _posts = [];
  ApiException? _error;
  bool _busy = true, _more = false;
  int _generation = 0;
  final _scroll = ScrollController();
  final _viewportKey = GlobalKey();
  final _postKeys = <int, GlobalKey>{};
  final _impressions = <int>{};
  bool _impressionScheduled = false;
  String? _trackingError;
  bool _dirty = false, _refreshScheduled = false;

  bool get _visible =>
      TickerMode.valuesOf(context).enabled &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  void _onMutation() {
    _dirty = true;
    ++_generation; // Ignore reads begun before a successful/uncertain mutation.
    _scheduleRefresh();
  }

  void _scheduleRefresh() {
    if (!_dirty || _refreshScheduled) return;
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (mounted && _dirty && _visible) _load();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleRefresh();
  }

  @override
  void didUpdateWidget(covariant CommunityScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      oldWidget.repository.mutations.removeListener(_onMutation);
      widget.repository.mutations.addListener(_onMutation);
      // Never render another repository/session's personalized rows for a frame.
      _category = CommunityCategory.forYou;
      _posts = [];
      _page = null;
      _busy = true;
      _error = null;
      _trackingError = null;
      _onMutation();
    }
  }

  void _scheduleImpressions() {
    if (_impressionScheduled) return;
    _impressionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _impressionScheduled = false;
      if (!mounted || !_visible) return;
      final viewport = _viewportKey.currentContext?.findRenderObject();
      if (viewport is! RenderBox || !viewport.hasSize) return;
      final bounds = viewport.localToGlobal(Offset.zero) & viewport.size;
      for (final post in _posts) {
        final box = _postKeys[post.id]?.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.hasSize || !box.attached) continue;
        if (bounds.overlaps(box.localToGlobal(Offset.zero) & box.size) &&
            _impressions.add(post.id)) {
          _impression(post.id, _category.mode);
        }
      }
    });
  }

  Future<void> _impression(int postId, String? mode) async {
    final generation = _generation;
    final error = await widget.repository.trackEvent(
      postId,
      'FEED_IMPRESSION',
      mode: mode,
    );
    if (mounted && generation == _generation && error != null) {
      setState(() => _trackingError = error);
    }
  }

  Future<void> _connections() async {
    final category = await Navigator.push<CommunityCategory>(
      context,
      MaterialPageRoute(
        builder: (_) => CommunityConnections(repository: widget.repository),
      ),
    );
    if (!mounted) return;
    if (category == CommunityCategory.following) {
      setState(() => _category = CommunityCategory.following);
      await _load();
    } else {
      _scheduleRefresh();
    }
  }

  @override
  void initState() {
    super.initState();
    widget.repository.mutations.addListener(_onMutation);
    _load();
  }

  @override
  void dispose() {
    _generation++;
    widget.repository.mutations.removeListener(_onMutation);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (more && (_busy || _more || _page?.hasNext != true)) return;
    if (_dirty && more) more = false;
    _dirty = false;
    final generation = more ? _generation : ++_generation;
    final category = _category;
    final next = more ? _page!.page + 1 : 0;
    setState(() {
      _error = null;
      if (more) {
        _more = true;
      } else {
        _busy = true;
        _more = false;
        _posts = [];
        _page = null;
        _postKeys.clear();
        _impressions.clear();
        _trackingError = null;
      }
    });
    if (!more && _scroll.hasClients) _scroll.jumpTo(0);
    try {
      final page = await widget.repository.list(category, page: next);
      if (mounted && generation == _generation) {
        setState(() {
          _posts = mergeRecords(
            _posts,
            page.content,
            identity: (post) => post.id,
            retain: (post) =>
                !post.deleted &&
                (category != CommunityCategory.own ||
                    post.authorId == widget.repository.ownerId),
          );
          _page = page;
        });
      }
    } on ApiException catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _more = false;
        });
      }
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push<Object?>(
      context,
      MaterialPageRoute<Object?>(builder: (_) => screen),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_visible) {
      _scheduleRefresh();
      _scheduleImpressions();
    }
    return CommunityAccess(
      repository: widget.repository,
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          _scheduleImpressions();
          return false;
        },
        child: ListView(
          key: _viewportKey,
          controller: _scroll,
          padding: const EdgeInsets.all(16),
          children: [
            Text('Community', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in CommunityCategory.values)
                  if (category != CommunityCategory.following ||
                      widget.repository.currentUser()?.role == UserRole.client)
                    ChoiceChip(
                      label: Text(category.label),
                      selected: _category == category,
                      onSelected: (_) {
                        if (_category == category) return;
                        setState(() => _category = category);
                        _load();
                      },
                    ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () =>
                      _open(CommunityPostEditor(repository: widget.repository)),
                  icon: const Icon(Icons.add),
                  label: const Text('Create post'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _load(),
                  child: const Text('Refresh'),
                ),
                TextButton(
                  onPressed: _connections,
                  child: const Text('Lawyer connections'),
                ),
                TextButton(
                  onPressed: () => _open(
                    CommunityAnalyticsScreen(repository: widget.repository),
                  ),
                  child: const Text('Community analytics'),
                ),
              ],
            ),
            if (_category == CommunityCategory.own)
              const Text(
                'Your posts are selected from the visible-post list. Load more to check further pages.',
              ),
            if (_category == CommunityCategory.bookmarks)
              const Text('Open a saved post to remove it from this list.'),
            if (_trackingError != null) Text(_trackingError!),
            const SizedBox(height: 12),
            if (_busy)
              const LoadingView(message: 'Loading community…')
            else ...[
              if (_posts.isEmpty && _error == null)
                EmptyState(
                  title: 'No posts in this page selection',
                  message: _page?.hasNext == true
                      ? 'Load more to check the next page.'
                      : 'There are no matching posts to show.',
                ),
              for (final post in _posts)
                Card(
                  key: _postKeys.putIfAbsent(post.id, () => GlobalKey()),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PostContent(post: post, preview: true),
                        TextButton(
                          onPressed: () => _open(
                            CommunityPostDetail(
                              repository: widget.repository,
                              postId: post.id,
                              feedMode: _category.mode,
                            ),
                          ),
                          child: const Text('Open post'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_error != null)
                ErrorView(
                  error: _error!,
                  onRetry: () => _load(more: _page != null),
                ),
              if (_more) const LoadingView(message: 'Loading more posts…'),
              if (_page?.hasNext == true && !_more && _error == null)
                Center(
                  child: FilledButton.tonal(
                    onPressed: () => _load(more: true),
                    child: const Text('Load more'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
