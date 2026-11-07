import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../../core/utils/merge_records.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../client/domain/client_models.dart';
import '../../community/data/community_repository.dart';
import '../../community/presentation/connections_screen.dart';
import '../data/discovery_repository.dart';
import '../domain/discovery_models.dart';
import 'lawyer_summary.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({
    super.key,
    required this.repository,
    this.community,
    this.refreshRevision = 0,
  });
  final DiscoveryRepository repository;
  final CommunityRepository? community;
  final int refreshRevision;

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  List<ReferenceItem> _areas = [];
  ReferenceItem? _selected;
  bool _areasBusy = true;
  ApiException? _areasError;
  List<DiscoveredLawyer> _lawyers = [];
  ApiPage<DiscoveredLawyer>? _page;
  ApiException? _error;
  ApiException? _moreError;
  bool _busy = true;
  bool _moreBusy = false;
  int _generation = 0;
  String _activeSearch = '';
  int? _activeArea;
  bool _needsRefresh = false, _refreshScheduled = false;

  void _scheduleRefresh() {
    if (!_needsRefresh || _refreshScheduled) return;
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (mounted && _needsRefresh && TickerMode.valuesOf(context).enabled) {
        _runSearch(repeat: true);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleRefresh();
  }

  @override
  void didUpdateWidget(covariant DiscoveryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshRevision != widget.refreshRevision ||
        oldWidget.repository != widget.repository) {
      ++_generation;
      _needsRefresh = true;
      _scheduleRefresh();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadAreas();
    _runSearch();
  }

  @override
  void dispose() {
    _generation++;
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadAreas() async {
    setState(() {
      _areasBusy = true;
      _areasError = null;
    });
    try {
      final areas = await widget.repository.practiceAreas();
      if (mounted) setState(() => _areas = areas);
    } on ApiException catch (error) {
      if (mounted) setState(() => _areasError = error);
    } finally {
      if (mounted) setState(() => _areasBusy = false);
    }
  }

  Future<void> _runSearch({bool repeat = false}) async {
    _needsRefresh = false;
    final generation = ++_generation;
    if (!repeat) {
      _activeSearch = _search.text.trim();
      _activeArea = _selected?.id;
    }
    setState(() {
      _busy = true;
      _moreBusy = false;
      _error = _moreError = null;
      _lawyers = [];
      _page = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    try {
      final page = await widget.repository.search(
        search: _activeSearch,
        practiceAreaId: _activeArea,
      );
      if (mounted && generation == _generation) {
        setState(() {
          _page = page;
          _lawyers = mergeRecords<DiscoveredLawyer>(
            [],
            page.content,
            identity: (lawyer) => lawyer.id,
          );
        });
      }
    } on ApiException catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _loadMore() async {
    if (_busy || _moreBusy || _page?.hasNext != true) return;
    final generation = _generation;
    final next = _page!.page + 1;
    setState(() {
      _moreBusy = true;
      _moreError = null;
    });
    try {
      final page = await widget.repository.search(
        search: _activeSearch,
        practiceAreaId: _activeArea,
        page: next,
      );
      if (mounted && generation == _generation) {
        setState(() {
          _page = page;
          _lawyers = mergeRecords(
            _lawyers,
            page.content,
            identity: (lawyer) => lawyer.id,
          );
        });
      }
    } on ApiException catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _moreError = error);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _moreBusy = false);
      }
    }
  }

  void _clear() {
    _search.clear();
    setState(() => _selected = null);
    _runSearch();
  }

  @override
  Widget build(BuildContext context) {
    // Retain a chosen reference if it disappears from a refreshed active catalog.
    final areas = [
      ..._areas,
      if (_selected != null && !_areas.any((item) => item.id == _selected!.id))
        _selected!,
    ];
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      children: [
        Text('Find a lawyer', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text(
          'Search verified, active lawyers by name. Listings are selected by the service.',
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('discovery-search'),
          controller: _search,
          decoration: const InputDecoration(
            labelText: 'Lawyer name',
            prefixIcon: Icon(Icons.search),
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _runSearch(),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          key: ValueKey(('discovery-area', _selected?.id, _areasBusy)),
          initialValue: _selected?.id,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: _areasBusy ? 'Loading practice areas…' : 'Practice area',
          ),
          items: [
            const DropdownMenuItem<int>(
              value: null,
              child: Text('All practice areas'),
            ),
            for (final area in areas)
              DropdownMenuItem(
                value: area.id,
                child: Text(area.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _areasBusy || _areasError != null
              ? null
              : (id) {
                  setState(
                    () => _selected = id == null
                        ? null
                        : areas.firstWhere((item) => item.id == id),
                  );
                },
        ),
        if (_areasError != null) ...[
          Text(
            'Practice areas: ${_areasError!.message}',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _loadAreas,
              child: const Text('Retry practice areas'),
            ),
          ),
        ] else if (!_areasBusy && areas.isEmpty)
          const Text(
            'No practice areas are currently available. You can still search by name.',
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => _runSearch(),
              icon: const Icon(Icons.search),
              label: const Text('Search lawyers'),
            ),
            TextButton(onPressed: _clear, child: const Text('Clear filters')),
            TextButton(
              onPressed: _busy ? null : () => _runSearch(repeat: true),
              child: const Text('Refresh results'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_busy)
          const LoadingView(message: 'Finding lawyers…')
        else if (_error != null)
          ErrorView(error: _error!, onRetry: () => _runSearch(repeat: true))
        else if (_lawyers.isEmpty)
          const EmptyState(
            title: 'No lawyers found',
            message: 'Try another name or clear the practice-area filter.',
            icon: Icons.person_search_outlined,
          )
        else ...[
          Text('Showing ${_lawyers.length} of ${_page!.totalElements} results'),
          const SizedBox(height: 8),
          for (final lawyer in _lawyers)
            DiscoveryCard(
              key: ValueKey(lawyer.id),
              lawyer: lawyer,
              onConnections: widget.community == null
                  ? null
                  : () {
                      Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CommunityConnections(
                            repository: widget.community!,
                            lawyerUserId: lawyer.userId,
                            showFollowingFeed: false,
                          ),
                        ),
                      );
                    },
            ),
          if (_moreBusy) const LoadingView(message: 'Loading more lawyers…'),
          if (_moreError != null)
            ErrorView(error: _moreError!, onRetry: _loadMore),
          if (_page!.hasNext && !_moreBusy && _moreError == null)
            Center(
              child: FilledButton.tonal(
                onPressed: _loadMore,
                child: const Text('Load more'),
              ),
            ),
        ],
      ],
    );
  }
}
