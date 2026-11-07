import 'package:flutter/material.dart';

import '../../../../core/network/api_exception.dart';
import '../../../client/presentation/client_widgets.dart';
import '../../qualifications/domain/qualification_schema.dart';
import '../data/practice_repository.dart';
import '../domain/practice_models.dart';
import '../domain/practice_schema.dart';

class PracticeEditor extends StatelessWidget {
  const PracticeEditor({
    super.key,
    required this.repository,
    required this.resource,
    required this.onSaved,
    required this.onReload,
    this.initial,
  });
  final PracticeRepository repository;
  final PracticeResource resource;
  final PracticeRecord? initial;
  final ValueChanged<PracticeRecord> onSaved;
  final VoidCallback onReload;
  @override
  Widget build(BuildContext context) =>
      ClientLoader<(List<PracticeReference>, List<PracticeRecord>)>(
        load: () async {
          if (resource.schema.referenceField == null) {
            return (const <PracticeReference>[], const <PracticeRecord>[]);
          }
          final values = await Future.wait<Object>([
            repository.references(resource),
            repository.list(resource),
          ]);
          return (
            values[0] as List<PracticeReference>,
            values[1] as List<PracticeRecord>,
          );
        },
        builder: (data) => _PracticeForm(
          repository: repository,
          resource: resource,
          initial: initial,
          references: data.$1,
          existing: data.$2,
          onSaved: onSaved,
          onReload: onReload,
        ),
      );
}

class _PracticeForm extends StatefulWidget {
  const _PracticeForm({
    required this.repository,
    required this.resource,
    required this.initial,
    required this.references,
    required this.existing,
    required this.onSaved,
    required this.onReload,
  });
  final PracticeRepository repository;
  final PracticeResource resource;
  final PracticeRecord? initial;
  final List<PracticeReference> references;
  final List<PracticeRecord> existing;
  final ValueChanged<PracticeRecord> onSaved;
  final VoidCallback onReload;
  @override
  State<_PracticeForm> createState() => _PracticeFormState();
}

class _PracticeFormState extends State<_PracticeForm> {
  final _form = GlobalKey<FormState>();
  late final _text = {
    for (final field in widget.resource.schema.fields.where(
      (f) =>
          f.kind != QualificationKind.boolean &&
          f.kind != QualificationKind.choice &&
          f.reference == null,
    ))
      field.key: TextEditingController(
        text: practiceInputText(widget.initial?.fields[field.key]),
      ),
  };
  late final _booleans = {
    for (final field in widget.resource.schema.fields.where(
      (f) => f.kind == QualificationKind.boolean,
    ))
      field.key: widget.initial == null
          ? field.key == 'active'
          : widget.initial!.fields[field.key] == true,
  };
  late final _choices = {
    for (final field in widget.resource.schema.fields.where(
      (f) => f.kind == QualificationKind.choice,
    ))
      field.key: widget.initial?.text(field.key),
  };
  late int? _referenceId = widget.resource.schema.referenceField == null
      ? null
      : widget.initial?.fields[widget.resource.schema.referenceField!.key]
            as int?;
  bool _busy = false;
  bool _needsReload = false;
  ApiException? _error;
  @override
  void dispose() {
    for (final controller in _text.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || _needsReload || !_form.currentState!.validate()) return;
    final values = <String, Object?>{..._booleans, ..._choices};
    for (final field in widget.resource.schema.fields) {
      if (field.reference != null) {
        values[field.key] = _referenceId;
        continue;
      }
      if (!_text.containsKey(field.key)) continue;
      final text = _text[field.key]!.text.trim();
      values[field.key] = text.isEmpty
          ? null
          : field.decimals != null
          ? num.parse(text)
          : field.kind == QualificationKind.integer
          ? int.parse(text)
          : text;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await widget.repository.save(
        widget.resource,
        values,
        id: widget.initial?.id,
      );
      if (mounted) widget.onSaved(saved);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _needsReload = {
            ApiErrorKind.network,
            ApiErrorKind.timeout,
            ApiErrorKind.server,
            ApiErrorKind.invalidResponse,
          }.contains(error.kind);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<PracticeReference> _referenceOptions(PracticeField field) {
    final options = [...widget.references];
    final savedId = widget.initial?.fields[field.key] as int?;
    if (savedId != null && !options.any((r) => r.id == savedId)) {
      options.add(
        PracticeReference(
          savedId,
          widget.initial!.text(field.referenceName!) ?? 'Saved ID $savedId',
          savedOnly: true,
        ),
      );
    }
    return options;
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: ClientFormLayout(
      title:
          '${widget.initial == null ? 'Add' : 'Edit'} ${widget.resource.schema.label.toLowerCase()}',
      children: [
        const Text('Fields marked * are required.'),
        if (widget.resource == PracticeResource.specializations ||
            widget.resource == PracticeResource.offices)
          const Text(
            'Selecting a primary record can clear other primary flags. The saved list reflects the server result.',
          ),
        if (widget.resource == PracticeResource.offices)
          const Text(
            'A blank country uses Bangladesh for a new office and keeps the saved country when editing.',
          ),
        if (widget.resource == PracticeResource.services)
          const Text(
            'A blank currency defaults to BDT for a new service and keeps the saved currency when editing. Fees support two decimal places.',
          ),
        if (widget.resource == PracticeResource.jurisdictions)
          const Text(
            'Saving a jurisdiction returns its record verification to PENDING.',
          ),
        const SizedBox(height: 16),
        ClientErrorNotice(error: _error),
        for (final field in widget.resource.schema.fields) ...[
          if (field.reference != null) ...[
            if (_referenceOptions(field).isEmpty)
              const Text(
                'No active reference options are available. Return to records and retry the catalog.',
              ),
            DropdownButtonFormField<int>(
              initialValue: _referenceId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: '${field.label} *',
                errorText: _error?.fieldErrors[field.key],
                errorMaxLines: 3,
              ),
              items: [
                for (final item in _referenceOptions(field))
                  DropdownMenuItem(
                    value: item.id,
                    enabled:
                        widget.initial != null ||
                        !widget.existing.any(
                          (r) => r.fields[field.key] == item.id,
                        ),
                    child: Text(item.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              validator: (value) => value == null
                  ? 'Choose a ${field.label.toLowerCase()}.'
                  : null,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _referenceId = value),
            ),
            if (widget.initial == null && widget.existing.isNotEmpty)
              const Text(
                'Already added references are disabled for new records.',
              ),
          ] else if (field.kind == QualificationKind.boolean)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(field.label),
              value: _booleans[field.key],
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _booleans[field.key] = v ?? false),
            )
          else if (field.kind == QualificationKind.choice)
            DropdownButtonFormField<String>(
              initialValue: _choices[field.key],
              isExpanded: true,
              decoration: InputDecoration(
                labelText: '${field.label}${field.required ? ' *' : ''}',
                errorText: _error?.fieldErrors[field.key],
              ),
              items: [
                if (!field.required)
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('Not specified'),
                  ),
                for (final option in field.options)
                  DropdownMenuItem(
                    value: option,
                    child: Text(option.replaceAll('_', ' ')),
                  ),
              ],
              validator: field.validate,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _choices[field.key] = v),
            )
          else
            TextFormField(
              key: ValueKey('practice-${field.key}'),
              controller: _text[field.key],
              enabled: !_busy,
              minLines: field.key == 'description' ? 3 : 1,
              maxLines: field.key == 'description' ? 7 : 1,
              decoration: InputDecoration(
                labelText: '${field.label}${field.required ? ' *' : ''}',
                errorText: _error?.fieldErrors[field.key],
                errorMaxLines: 3,
              ),
              keyboardType: field.decimals != null
                  ? const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    )
                  : field.kind == QualificationKind.integer
                  ? TextInputType.number
                  : field.key == 'email'
                  ? TextInputType.emailAddress
                  : field.key == 'phone'
                  ? TextInputType.phone
                  : field.key == 'description'
                  ? TextInputType.multiline
                  : TextInputType.text,
              validator: field.validate,
            ),
          const SizedBox(height: 16),
        ],
        if (_needsReload) ...[
          const Text(
            'The save result could not be confirmed. Reload before another attempt to avoid duplicate records.',
          ),
          OutlinedButton(
            onPressed: _busy ? null : widget.onReload,
            child: const Text('Reload records'),
          ),
        ],
        FilledButton(
          onPressed: _busy || _needsReload ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Save practice record'),
        ),
      ],
    ),
  );
}
