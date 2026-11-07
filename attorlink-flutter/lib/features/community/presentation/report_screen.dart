import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../data/community_repository.dart';
import '../data/community_features.dart';
import '../domain/community_extras.dart';
import '../domain/community_models.dart';
import 'community_access.dart';

class ContentReportScreen extends StatefulWidget {
  const ContentReportScreen({
    super.key,
    required this.repository,
    required this.targetType,
    required this.targetId,
    this.authorId,
  });
  final CommunityRepository repository;
  final String targetType;
  final int targetId;
  final int? authorId;
  @override
  State<ContentReportScreen> createState() => _ContentReportScreenState();
}

class _ContentReportScreenState extends State<ContentReportScreen> {
  final _explanation = TextEditingController();
  String _reason = reportReasons.first;
  ReportReceipt? _receipt;
  bool _busy = false, _uncertain = false;
  String? _error;
  @override
  void dispose() {
    _explanation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _uncertain || _receipt != null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final receipt = await widget.repository.report(
        targetType: widget.targetType,
        targetId: widget.targetId,
        reason: _reason,
        explanation: _explanation.text,
        authorId: widget.authorId,
      );
      if (mounted) {
        setState(() => _receipt = receipt);
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
        appBar: AppBar(title: const Text('Report content')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('${widget.targetType} #${widget.targetId}'),
            if (_receipt != null) ...[
              Text(
                'Report #${_receipt!.id} submitted. Status: ${_receipt!.status}',
              ),
              Text('Reason: ${_receipt!.reason}'),
              if (_receipt!.createdAt != null)
                Text('Created: ${_receipt!.createdAt}'),
            ] else ...[
              DropdownButtonFormField<String>(
                initialValue: _reason,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Reason'),
                items: [
                  for (final reason in reportReasons)
                    DropdownMenuItem(
                      value: reason,
                      child: Text(reason.replaceAll('_', ' ')),
                    ),
                ],
                onChanged: _busy || _uncertain
                    ? null
                    : (value) => setState(() => _reason = value!),
              ),
              TextField(
                controller: _explanation,
                maxLength: 1000,
                maxLines: 5,
                enabled: !_busy && !_uncertain,
                decoration: const InputDecoration(
                  labelText: 'Explanation (optional)',
                ),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_uncertain)
                const Text(
                  'Submission could not be confirmed. A duplicate report is not sent automatically.',
                ),
              FilledButton(
                onPressed: _busy || _uncertain ? null : _submit,
                child: Text(_busy ? 'Submitting…' : 'Submit report'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
