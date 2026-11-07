import 'package:flutter/material.dart';

import '../../../../core/network/api_exception.dart';
import '../../../client/presentation/client_widgets.dart';
import '../data/qualifications_repository.dart';
import '../domain/qualification_record.dart';
import '../domain/qualification_schema.dart';
import 'qualification_documents.dart';
import 'qualification_editor.dart';

enum _Mode { records, detail, edit, documents }

class QualificationsHub extends StatefulWidget {
  const QualificationsHub({super.key, required this.repository});
  final QualificationsRepository repository;
  @override
  State<QualificationsHub> createState() => _QualificationsHubState();
}

class _QualificationsHubState extends State<QualificationsHub> {
  QualificationResource _resource = QualificationResource.highCourt;
  _Mode _mode = _Mode.records;
  QualificationRecord? _selected;
  int _revision = 0;
  bool _deleting = false;
  ApiException? _error;
  String? _message;

  void _reload() => setState(() {
    _mode = _Mode.records;
    _selected = null;
    _revision++;
    _error = null;
  });
  void _open(QualificationRecord record) => setState(() {
    _selected = record;
    _mode = _Mode.detail;
    _error = null;
    _message = null;
  });
  Future<void> _delete(QualificationRecord record) async {
    if (_deleting) return;
    final repository = widget.repository;
    final resource = record.resource;
    final id = record.id;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      repository.lawyer.checkAccess();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete this record?'),
          content: Text(record.title),
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
      );
      if (confirmed != true || !mounted) return;
      repository.lawyer.checkAccess();
      await repository.delete(resource, id);
      if (mounted) {
        _reload();
        setState(() => _message = 'Record deleted.');
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Widget _records() => ClientLoader<List<QualificationRecord>>(
    key: ValueKey('$_resource-$_revision'),
    load: () => widget.repository.list(_resource),
    builder: (records) => Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (!_resource.schema.singleton || records.isEmpty)
                FilledButton.icon(
                  onPressed: () => setState(() {
                    _selected = null;
                    _mode = _Mode.edit;
                    _message = null;
                  }),
                  icon: const Icon(Icons.add),
                  label: Text(
                    _resource.schema.singleton
                        ? 'Set up registration'
                        : 'Add record',
                  ),
                ),
              OutlinedButton(
                onPressed: _reload,
                child: const Text('Refresh records'),
              ),
            ],
          ),
        ),
        Expanded(
          child: records.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No records saved yet.'),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: records.length,
                  itemBuilder: (context, index) {
                    final record = records[index];
                    return Card(
                      child: ListTile(
                        title: Text(record.title),
                        subtitle: record.text('verificationStatus') == null
                            ? null
                            : Text(
                                'Verification: ${record.text('verificationStatus')}',
                              ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _open(record),
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );

  Widget _detail(QualificationRecord record) => ClientFormLayout(
    title: record.title,
    children: [
      for (final field in record.resource.schema.fields)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(field.label),
          subtitle: field.kind == QualificationKind.document
              ? SelectableText(
                  record.text(field.key)?.isNotEmpty == true
                      ? record.text(field.key)!
                      : 'Not provided',
                )
              : Text(
                  record.fields[field.key] is bool
                      ? (record.fields[field.key] == true ? 'Yes' : 'No')
                      : record.text(field.key)?.isNotEmpty == true
                      ? record.text(field.key)!
                      : 'Not provided',
                ),
        ),
      for (final field in record.resource.schema.metadata)
        if (record.text(field) != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(switch (field) {
              'verificationStatus' => 'Verification status',
              'verifiedAt' => 'Verified at',
              'verifiedBy' => 'Verified by',
              'rejectionReason' => 'Review feedback',
              _ => 'Created at',
            }),
            subtitle: Text(record.text(field)!),
          ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _deleting
            ? null
            : () => setState(() {
                _selected = record;
                _mode = _Mode.edit;
              }),
        child: const Text('Edit record'),
      ),
      if (record.resource.schema.attachments.isNotEmpty)
        OutlinedButton(
          onPressed: _deleting
              ? null
              : () => setState(() {
                  _selected = record;
                  _mode = _Mode.documents;
                }),
          child: const Text('Manage documents'),
        ),
      if (!record.resource.schema.singleton)
        TextButton(
          onPressed: _deleting ? null : () => _delete(record),
          child: Text(_deleting ? 'Deleting…' : 'Delete record'),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: DropdownButtonFormField<QualificationResource>(
          initialValue: _resource,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Qualifications and credentials',
          ),
          items: [
            for (final resource in QualificationResource.values)
              DropdownMenuItem(
                value: resource,
                child: Text(resource.schema.label),
              ),
          ],
          onChanged: _deleting
              ? null
              : (value) => setState(() {
                  _resource = value!;
                  _mode = _Mode.records;
                  _selected = null;
                  _error = null;
                  _message = null;
                  _revision++;
                }),
        ),
      ),
      if (_mode != _Mode.records)
        TextButton.icon(
          onPressed: _deleting ? null : _reload,
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back to records'),
        ),
      if (_message != null)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Semantics(liveRegion: true, child: Text(_message!)),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: ClientErrorNotice(error: _error),
      ),
      Expanded(
        child: switch (_mode) {
          _Mode.records => _records(),
          _Mode.detail => ClientLoader<QualificationRecord>(
            key: ValueKey('detail-$_resource-${_selected!.id}-$_revision'),
            load: () => widget.repository.detail(_resource, _selected!.id),
            builder: _detail,
          ),
          _Mode.edit => QualificationEditor(
            key: ValueKey('edit-$_resource-${_selected?.id}-$_revision'),
            repository: widget.repository,
            resource: _resource,
            initial: _selected,
            onReload: _reload,
            onSaved: (record) => setState(() {
              _selected = record;
              _mode = _Mode.detail;
              _revision++;
              _message = 'Record saved.';
            }),
          ),
          _Mode.documents => QualificationDocuments(
            key: ValueKey('files-$_resource-${_selected!.id}'),
            repository: widget.repository,
            resource: _resource,
            id: _selected!.id,
          ),
        },
      ),
    ],
  );
}
