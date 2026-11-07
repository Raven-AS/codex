import 'package:flutter/material.dart';

import '../../../../core/network/api_exception.dart';
import '../../../client/presentation/client_widgets.dart';
import '../data/practice_repository.dart';
import '../domain/practice_models.dart';
import '../domain/practice_schema.dart';
import '../../qualifications/domain/qualification_schema.dart';
import 'availability_editor.dart';
import 'practice_editor.dart';

enum _Mode { records, detail, edit }

class PracticeHub extends StatefulWidget {
  const PracticeHub({super.key, required this.repository});
  final PracticeRepository repository;
  @override
  State<PracticeHub> createState() => _PracticeHubState();
}

class _PracticeHubState extends State<PracticeHub> {
  PracticeResource? _resource = PracticeResource.specializations;
  _Mode _mode = _Mode.records;
  PracticeRecord? _record;
  int _revision = 0;
  bool _busy = false;
  ApiException? _error;
  String? _message;
  void _reload() => setState(() {
    _mode = _Mode.records;
    _record = null;
    _error = null;
    _revision++;
  });
  void _open(PracticeRecord record) => setState(() {
    _record = record;
    _mode = _Mode.detail;
    _message = null;
    _error = null;
  });
  Future<void> _delete(PracticeRecord record) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete this practice record?'),
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
      await widget.repository.delete(record.resource, record.id);
      if (mounted) {
        _reload();
        setState(() => _message = 'Practice record deleted.');
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _records(PracticeResource resource) =>
      ClientLoader<List<PracticeRecord>>(
        key: ValueKey('list-$resource-$_revision'),
        load: () => widget.repository.list(resource),
        builder: (records) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => setState(() {
                      _record = null;
                      _mode = _Mode.edit;
                      _message = null;
                    }),
                    icon: const Icon(Icons.add),
                    label: const Text('Add practice record'),
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
                  ? const Center(child: Text('No practice records saved yet.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: records.length,
                      itemBuilder: (context, index) {
                        final record = records[index];
                        final badges = <String>[
                          if (record.fields['isPrimary'] == true ||
                              record.fields['primaryOffice'] == true)
                            'Primary',
                          if (record.fields['active'] != null)
                            record.fields['active'] == true
                                ? 'Active'
                                : 'Inactive',
                          if (record.text('verificationStatus') != null)
                            record.text('verificationStatus')!,
                          if (record.text('proficiency') != null)
                            record.text('proficiency')!,
                        ];
                        return Card(
                          child: ListTile(
                            title: Text(record.title),
                            subtitle: badges.isEmpty
                                ? null
                                : Text(badges.join(' · ')),
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
  Widget _detail(PracticeRecord record) => ClientFormLayout(
    title: record.title,
    children: [
      for (final field in record.resource.schema.fields)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(field.label),
          subtitle: Text(
            field.reference != null
                ? record.text(field.referenceName!) ??
                      'Saved ID ${record.fields[field.key]}'
                : field.kind == QualificationKind.boolean
                ? record.fields[field.key] == true
                      ? 'Yes'
                      : 'No'
                : record.text(field.key)?.isNotEmpty == true
                ? practiceInputText(record.fields[field.key])
                : 'Not provided',
          ),
        ),
      for (final meta in record.resource.schema.metadata.entries)
        if (record.text(meta.key) != null &&
            meta.key != record.resource.schema.referenceField?.referenceName)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(meta.value),
            subtitle: Text(record.text(meta.key)!),
          ),
      FilledButton(
        onPressed: _busy
            ? null
            : () => setState(() {
                _record = record;
                _mode = _Mode.edit;
              }),
        child: const Text('Edit practice record'),
      ),
      TextButton(
        onPressed: _busy ? null : () => _delete(record),
        child: Text(_busy ? 'Deleting…' : 'Delete practice record'),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: DropdownButtonFormField<int>(
          initialValue: _resource?.index ?? PracticeResource.values.length,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Practice management'),
          items: [
            for (final resource in PracticeResource.values)
              DropdownMenuItem(
                value: resource.index,
                child: Text(resource.schema.label),
              ),
            DropdownMenuItem(
              value: PracticeResource.values.length,
              child: const Text('Weekly availability'),
            ),
          ],
          onChanged: _busy
              ? null
              : (index) => setState(() {
                  _resource = index == PracticeResource.values.length
                      ? null
                      : PracticeResource.values[index!];
                  _mode = _Mode.records;
                  _record = null;
                  _revision++;
                  _error = null;
                  _message = null;
                }),
        ),
      ),
      if (_mode != _Mode.records)
        TextButton.icon(
          onPressed: _busy ? null : _reload,
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back to practice records'),
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
        child: _resource == null
            ? AvailabilityEditor(repository: widget.repository)
            : switch (_mode) {
                _Mode.records => _records(_resource!),
                _Mode.detail => ClientLoader<PracticeRecord>(
                  key: ValueKey('detail-$_resource-${_record!.id}-$_revision'),
                  load: () => widget.repository.detail(_resource!, _record!.id),
                  builder: _detail,
                ),
                _Mode.edit => PracticeEditor(
                  key: ValueKey('edit-$_resource-${_record?.id}-$_revision'),
                  repository: widget.repository,
                  resource: _resource!,
                  initial: _record,
                  onReload: _reload,
                  onSaved: (record) => setState(() {
                    _record = record;
                    _mode = _Mode.detail;
                    _revision++;
                    _message = 'Practice record saved.';
                  }),
                ),
              },
      ),
    ],
  );
}
