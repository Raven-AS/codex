import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../../core/utils/merge_records.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';

/// Paged comments/connections share loading and retry behavior, not DTOs.
class CommunityPageList<T> extends StatefulWidget {
  const CommunityPageList({
    super.key,
    required this.load,
    required this.item,
    required this.identity,
    this.retain,
    this.header = const [],
    this.empty = 'No records to show.',
  });
  final Future<ApiPage<T>> Function(int page) load;
  final Widget Function(T value) item;
  final Object Function(T value) identity;
  final bool Function(T value)? retain;
  final List<Widget> header;
  final String empty;
  @override
  State<CommunityPageList<T>> createState() => _CommunityPageListState<T>();
}

class _CommunityPageListState<T> extends State<CommunityPageList<T>> {
  final _items = <T>[];
  ApiPage<T>? _page;
  bool _busy = false;
  ApiException? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.load(_page == null ? 0 : _page!.page + 1);
      if (mounted) {
        setState(() {
          final merged = mergeRecords(
            _items,
            page.content,
            identity: widget.identity,
            retain: widget.retain,
          );
          _items
            ..clear()
            ..addAll(merged);
          _page = page;
        });
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      ...widget.header,
      if (_page != null)
        Text('Loaded ${_items.length} of ${_page!.totalElements} records'),
      if (_items.isEmpty && !_busy && _error == null)
        Padding(padding: const EdgeInsets.all(24), child: Text(widget.empty)),
      for (final item in _items) widget.item(item),
      if (_error != null) ErrorView(error: _error!, onRetry: _load),
      if (_busy) const LoadingView(),
      if (_page?.hasNext == true && !_busy && _error == null)
        Center(
          child: FilledButton.tonal(
            onPressed: _load,
            child: const Text('Load more'),
          ),
        ),
    ],
  );
}
