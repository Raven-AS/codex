import 'package:flutter/material.dart';

import '../../../../core/network/api_exception.dart';
import '../../../client/presentation/client_widgets.dart';
import '../../domain/lawyer_document.dart';
import '../../presentation/document_selection.dart';
import '../data/qualifications_repository.dart';
import '../domain/qualification_record.dart';
import '../domain/qualification_schema.dart';

class QualificationDocuments extends StatelessWidget {
  const QualificationDocuments({
    super.key,
    required this.repository,
    required this.resource,
    required this.id,
  });
  final QualificationsRepository repository;
  final QualificationResource resource;
  final int id;
  @override
  Widget build(BuildContext context) => ClientLoader<QualificationRecord>(
    load: () => repository.detail(resource, id),
    builder: (record) => _Documents(repository: repository, initial: record),
  );
}

class _Documents extends StatefulWidget {
  const _Documents({required this.repository, required this.initial});
  final QualificationsRepository repository;
  final QualificationRecord initial;
  @override
  State<_Documents> createState() => _DocumentsState();
}

class _DocumentsState extends State<_Documents> {
  late QualificationRecord _record = widget.initial;
  late QualificationAttachment _target =
      _record.resource.schema.attachments.first;
  final _path = TextEditingController();
  late final _url = TextEditingController(
    text: _record.text(_target.field) ?? '',
  );
  LawyerDocument? _selected;
  UnlinkedQualificationUpload? _unlinked;
  QualificationAttachment? _pendingTarget;
  bool _busy = false;
  bool _needsRefresh = false;
  ApiException? _error;
  String? _message;
  @override
  void dispose() {
    _path.dispose();
    _url.dispose();
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
    } on UnlinkedQualificationUpload catch (error) {
      if (mounted) {
        setState(() {
          _unlinked = error;
          _pendingTarget = _target;
          _needsRefresh = true;
          _error = error;
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    final record = await widget.repository.detail(_record.resource, _record.id);
    if (!mounted) return;
    setState(() {
      _record = record;
      _needsRefresh = false;
      _url.text = record.text(_target.field) ?? '';
      if (_unlinked != null &&
          record.text(_pendingTarget!.field) == _unlinked!.uploaded.url) {
        _unlinked = null;
        _pendingTarget = null;
        _selected = null;
      }
    });
  }

  Future<void> _pick() => _run(() async {
    final file = await chooseLawyerDocument(
      path: documentSelectionUsesPath ? _path.text : null,
    );
    if (mounted && file != null) setState(() => _selected = file);
  });
  Future<void> _upload() => _run(() async {
    if (_selected == null) return;
    setState(() => _needsRefresh = true);
    await widget.repository.upload(
      _record.resource,
      _record.id,
      _target.field,
      _selected!,
    );
    if (!mounted) return;
    setState(() {
      _selected = null;
      _message = 'Document uploaded and attached.';
    });
    await _refresh();
  });
  Future<void> _remove(QualificationAttachment attachment) => _run(() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          attachment.endpoint == null
              ? 'Clear this document link?'
              : 'Remove this document?',
        ),
        content: attachment.endpoint == null
            ? const Text(
                'This removes the record link. The stored file is not deleted.',
              )
            : null,
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
    if (confirmed != true || !mounted) return;
    setState(() => _needsRefresh = true);
    await widget.repository.removeDocument(
      _record.resource,
      _record.id,
      attachment.field,
    );
    if (!mounted) return;
    setState(() => _message = 'Document operation completed.');
    await _refresh();
  });
  Future<void> _link(String? url, QualificationAttachment target) =>
      _run(() async {
        setState(() => _needsRefresh = true);
        await widget.repository.linkDocument(
          _record.resource,
          _record.id,
          target.field,
          url,
        );
        if (!mounted) return;
        setState(() {
          _unlinked = null;
          _pendingTarget = null;
          _selected = null;
          _message = 'Document link saved.';
        });
        await _refresh();
      });
  @override
  Widget build(BuildContext context) => ClientFormLayout(
    title: '${_record.resource.schema.label}: documents',
    children: [
      const Text(
        'Choose PDF, JPEG, or PNG files up to 10 MB. Upload only after reviewing the selected filename.',
      ),
      const SizedBox(height: 16),
      ClientErrorNotice(error: _error),
      if (_message != null) Text(_message!),
      if (_unlinked != null) ...[
        SelectableText('Uploaded file URL: ${_unlinked!.uploaded.url}'),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _link(_unlinked!.uploaded.url, _pendingTarget!),
          child: const Text('Retry linking uploaded file'),
        ),
      ],
      OutlinedButton(
        onPressed: _busy ? null : () => _run(_refresh),
        child: const Text('Refresh record'),
      ),
      if (_needsRefresh || _unlinked != null)
        const Text(
          'Refresh the record or resolve the uploaded file link before another file operation.',
        )
      else ...[
        for (final attachment in _record.resource.schema.attachments)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    attachment.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SelectableText(
                    _record.text(attachment.field)?.isNotEmpty == true
                        ? _record.text(attachment.field)!
                        : 'No document saved.',
                  ),
                  if (_record.text(attachment.field)?.isNotEmpty == true)
                    TextButton(
                      onPressed: _busy ? null : () => _remove(attachment),
                      child: Text(
                        attachment.endpoint == null
                            ? 'Clear document link'
                            : 'Remove document',
                      ),
                    ),
                ],
              ),
            ),
          ),
        DropdownButtonFormField<String>(
          initialValue: _target.field,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Document field'),
          items: [
            for (final item in _record.resource.schema.attachments)
              DropdownMenuItem(value: item.field, child: Text(item.label)),
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() {
                  _target = _record.resource.schema.attachments.firstWhere(
                    (a) => a.field == value,
                  );
                  _selected = null;
                  _url.text = _record.text(_target.field) ?? '';
                }),
        ),
        if (documentSelectionUsesPath) ...[
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
        if (_target.endpoint == null) ...[
          const SizedBox(height: 16),
          const Text(
            'This record stores a document URL. Uploads are attached in a separate save. Clearing or replacing a link does not delete the stored file.',
          ),
          TextField(
            controller: _url,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Existing document URL',
            ),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => _link(
                    _url.text.trim().isEmpty ? null : _url.text.trim(),
                    _target,
                  ),
            child: const Text('Save document URL'),
          ),
        ],
      ],
      if (_busy)
        const LinearProgressIndicator(
          semanticsLabel: 'Updating record documents',
        ),
    ],
  );
}
