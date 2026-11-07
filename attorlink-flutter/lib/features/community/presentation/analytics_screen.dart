import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../data/community_repository.dart';
import '../data/community_features.dart';
import '../domain/community_extras.dart';
import '../domain/community_models.dart';
import 'community_access.dart';

class CommunityAnalyticsScreen extends StatefulWidget {
  const CommunityAnalyticsScreen({
    super.key,
    required this.repository,
    this.postId,
  });
  final CommunityRepository repository;
  final int? postId;
  @override
  State<CommunityAnalyticsScreen> createState() =>
      _CommunityAnalyticsScreenState();
}

class _CommunityAnalyticsScreenState extends State<CommunityAnalyticsScreen> {
  late final _id = TextEditingController(text: widget.postId?.toString() ?? '');
  final _from = TextEditingController(
    text: DateTime.now().subtract(const Duration(days: 7)).toIso8601String(),
  );
  final _to = TextEditingController(text: DateTime.now().toIso8601String());
  CommunityAnalytics? _summary;
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _id.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _summary = null;
    });
    try {
      final id = int.tryParse(_id.text.trim());
      if (id == null || id <= 0) {
        throw const ApiException(
          kind: ApiErrorKind.validation,
          message: 'Enter a positive post ID.',
        );
      }
      final summary = await widget.repository.analytics(
        id,
        _from.text.trim(),
        _to.text.trim(),
      );
      if (mounted) {
        setState(() => _summary = summary);
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = communityErrorMessage(error));
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
    child: Scaffold(
      appBar: AppBar(title: const Text('Community event analytics')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'These metrics cover community-wide events within the selected window. The service requires a visible post ID, but its totals are not filtered to that post.',
          ),
          TextField(
            controller: _id,
            keyboardType: TextInputType.number,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Post ID'),
          ),
          TextField(
            controller: _from,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'From · YYYY-MM-DDTHH:MM:SS',
            ),
          ),
          TextField(
            controller: _to,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'To · YYYY-MM-DDTHH:MM:SS',
            ),
          ),
          const Text(
            'Use local date/time without a timezone. Fractional seconds are supported.',
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _load,
            child: Text(_busy ? 'Loading…' : 'Load analytics'),
          ),
          if (_error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_summary != null) ...[
            Text('Requested post ID: ${_summary!.postId}'),
            Text('Window: ${_summary!.from} to ${_summary!.to}'),
            for (final entry in _summary!.counts.entries)
              ListTile(
                title: Text(entry.key),
                trailing: Text('${entry.value}'),
              ),
            ListTile(
              title: const Text('Engagement rate'),
              trailing: Text('${_summary!.engagementRate}%'),
            ),
          ],
        ],
      ),
    ),
  );
}
