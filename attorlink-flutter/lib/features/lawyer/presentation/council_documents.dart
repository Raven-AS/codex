import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/api_exception.dart';
import '../../client/presentation/client_widgets.dart';
import '../data/lawyer_repository.dart';
import 'document_selection.dart';
import '../domain/lawyer_document.dart';
import '../domain/lawyer_models.dart';

class CouncilDocuments extends StatelessWidget {
  const CouncilDocuments({
    super.key,
    required this.repository,
    required this.onChanged,
    required this.onEditRecord,
  });
  final LawyerRepository repository;
  final ValueChanged<BarCouncilRecord> onChanged;
  final VoidCallback onEditRecord;
  @override
  Widget build(BuildContext context) => ClientLoader<BarCouncilRecord?>(
    load: repository.barCouncil,
    builder: (record) => record == null
        ? ClientFormLayout(
            title: 'Bar Council documents',
            children: [
              const Text(
                'Save your Bar Council registration record before managing its documents.',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onEditRecord,
                child: const Text('Save registration record'),
              ),
            ],
          )
        : _DocumentManager(
            repository: repository,
            initial: record,
            onChanged: onChanged,
          ),
  );
}

class _DocumentManager extends StatefulWidget {
  const _DocumentManager({
    required this.repository,
    required this.initial,
    required this.onChanged,
  });
  final LawyerRepository repository;
  final BarCouncilRecord initial;
  final ValueChanged<BarCouncilRecord> onChanged;
  @override
  State<_DocumentManager> createState() => _DocumentManagerState();
}

class _DocumentManagerState extends State<_DocumentManager> {
  late BarCouncilRecord _record = widget.initial;
  CouncilDocument _target = CouncilDocument.identityCard;
  LawyerDocument? _selected;
  final _path = TextEditingController();
  bool _busy = false;
  bool _needsRefresh = false;
  ApiException? _error;
  String? _message;
  bool get _desktop =>
      !kIsWeb && defaultTargetPlatform != TargetPlatform.android;
  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _error = ApiException(
            kind: ApiErrorKind.unsupported,
            message: error.message ?? 'Document selection is unavailable.',
          ),
        );
      }
    } on MissingPluginException {
      if (mounted) {
        setState(
          () => _error = const ApiException(
            kind: ApiErrorKind.unsupported,
            message: 'This build does not provide the Android document picker.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() => _run(() async {
    final file = await chooseLawyerDocument(path: _desktop ? _path.text : null);
    if (mounted && file != null) setState(() => _selected = file);
  });
  Future<void> _refresh() async {
    final record = await widget.repository.barCouncil();
    if (record == null) {
      throw const ApiException(
        kind: ApiErrorKind.invalidResponse,
        message: 'The saved Bar Council record could not be retrieved.',
      );
    }
    if (!mounted) return;
    setState(() {
      _record = record;
      _needsRefresh = false;
      _selected = null;
    });
    widget.onChanged(record);
  }

  Future<void> _upload() => _run(() async {
    final file = _selected;
    if (file == null || _needsRefresh) return;
    setState(() => _needsRefresh = true);
    final result = await widget.repository.uploadDocument(_target, file);
    if (!mounted) return;
    setState(() {
      _selected = null;
      _needsRefresh = true;
      _message = '${_target.label} uploaded. Saved URL: ${result.url}';
    });
    await _refresh();
  });
  Future<void> _remove(CouncilDocument target) => _run(() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${target.label.toLowerCase()} document?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _needsRefresh) return;
    setState(() => _needsRefresh = true);
    final result = await widget.repository.removeDocument(target);
    if (!mounted) return;
    setState(() {
      _needsRefresh = true;
      _message = result.url == null
          ? '${target.label} document removed.'
          : 'The server still reports a saved document.';
    });
    await _refresh();
  });
  @override
  Widget build(BuildContext context) => ClientFormLayout(
    title: 'Bar Council documents',
    children: [
      const Text(
        'Documents are optional under the current submission rules. Upload PDF, JPEG, or PNG files up to 10 MB. Document operations do not replace the registration details.',
      ),
      const SizedBox(height: 16),
      ClientErrorNotice(error: _error),
      if (_message != null) SelectableText(_message!),
      if (_needsRefresh) ...[
        const Text('Refresh the record before another file operation.'),
        FilledButton(
          onPressed: _busy ? null : () => _run(_refresh),
          child: const Text('Refresh record'),
        ),
      ] else ...[
        Text('Record verification: ${_record.status}'),
        if (_record.text('rejectionReason')?.isNotEmpty == true)
          Text('Record feedback: ${_record.text('rejectionReason')}'),
        for (final target in CouncilDocument.values)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    target.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SelectableText(
                    _record.text(target.field) ?? 'No document saved.',
                  ),
                  if (_record.text(target.field) != null)
                    TextButton(
                      onPressed: _busy ? null : () => _remove(target),
                      child: const Text('Remove document'),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        DropdownButtonFormField<CouncilDocument>(
          initialValue: _target,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Document to upload'),
          items: [
            for (final target in CouncilDocument.values)
              DropdownMenuItem(value: target, child: Text(target.label)),
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() {
                  _target = value!;
                  _selected = null;
                }),
        ),
        if (_desktop) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _path,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Readable local file path',
            ),
          ),
        ],
        OutlinedButton(
          onPressed: _busy ? null : _pick,
          child: const Text('Choose document'),
        ),
        if (_selected != null) ...[
          Text('Selected: ${_selected!.name} (${_selected!.mimeType})'),
          FilledButton(
            onPressed: _busy ? null : _upload,
            child: const Text('Upload selected document'),
          ),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _selected = null),
            child: const Text('Discard selection'),
          ),
        ],
      ],
      if (_busy)
        const LinearProgressIndicator(semanticsLabel: 'Updating documents'),
    ],
  );
}
