import 'package:flutter/material.dart';

import '../../../../core/network/api_exception.dart';
import '../../../client/presentation/client_widgets.dart';
import '../data/qualifications_repository.dart';
import '../domain/qualification_record.dart';
import '../domain/qualification_schema.dart';

class QualificationEditor extends StatefulWidget {
  const QualificationEditor({
    super.key,
    required this.repository,
    required this.resource,
    required this.onSaved,
    required this.onReload,
    this.initial,
  });
  final QualificationsRepository repository;
  final QualificationResource resource;
  final QualificationRecord? initial;
  final ValueChanged<QualificationRecord> onSaved;
  final VoidCallback onReload;
  @override
  State<QualificationEditor> createState() => _QualificationEditorState();
}

class _QualificationEditorState extends State<QualificationEditor> {
  final _form = GlobalKey<FormState>();
  late final _text = {
    for (final field in widget.resource.schema.informationFields.where(
      (f) =>
          f.kind != QualificationKind.boolean &&
          f.kind != QualificationKind.choice,
    ))
      field.key: TextEditingController(
        text: widget.initial?.text(field.key) ?? '',
      ),
  };
  late final _booleans = {
    for (final field in widget.resource.schema.informationFields.where(
      (f) => f.kind == QualificationKind.boolean,
    ))
      field.key: widget.initial?.fields[field.key] == true,
  };
  late final _choices = {
    for (final field in widget.resource.schema.informationFields.where(
      (f) => f.kind == QualificationKind.choice,
    ))
      field.key: widget.initial?.text(field.key),
  };
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
    for (final field in widget.resource.schema.informationFields) {
      if (!_text.containsKey(field.key)) continue;
      final text = _text[field.key]!.text.trim();
      values[field.key] = text.isEmpty
          ? null
          : field.kind == QualificationKind.integer
          ? int.parse(text)
          : text;
    }
    final errors = validateQualification(widget.resource, values);
    if (errors.isNotEmpty) {
      setState(
        () => _error = ApiException(
          kind: ApiErrorKind.validation,
          message: 'Please check the record fields.',
          fieldErrors: errors,
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repository = widget.repository;
    final resource = widget.resource;
    final id = widget.initial?.id;
    try {
      final record = await repository.saveInformation(
        resource,
        values,
        id: id,
        checkOperation: () {
          if (!mounted ||
              widget.repository != repository ||
              widget.resource != resource ||
              widget.initial?.id != id) {
            throw const ApiException(
              kind: ApiErrorKind.forbidden,
              message: 'This editor is no longer active. Reopen the record.',
            );
          }
        },
      );
      if (mounted) widget.onSaved(record);
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

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: ClientFormLayout(
      title:
          '${widget.initial == null ? 'Add' : 'Edit'} ${widget.resource.schema.label.toLowerCase()}',
      children: [
        const Text('Fields marked * are required. Dates use YYYY-MM-DD.'),
        if (widget.resource.schema.verified)
          const Text(
            'Saving information returns this record to PENDING review. Overall profile verification is tracked separately.',
          ),
        if (widget.resource.schema.attachments.isNotEmpty)
          const Text(
            'Existing document links are preserved. Manage files after saving the record.',
          ),
        const SizedBox(height: 16),
        ClientErrorNotice(error: _error),
        for (final field in widget.resource.schema.informationFields) ...[
          if (field.kind == QualificationKind.boolean)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(field.label),
              value: _booleans[field.key],
              onChanged: _busy
                  ? null
                  : (value) =>
                        setState(() => _booleans[field.key] = value ?? false),
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
                for (final choice in field.options)
                  DropdownMenuItem(value: choice, child: Text(choice)),
              ],
              validator: field.validate,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _choices[field.key] = value),
            )
          else
            TextFormField(
              key: ValueKey('qualification-${field.key}'),
              controller: _text[field.key],
              enabled:
                  !_busy &&
                  !(widget.resource == QualificationResource.experience &&
                      field.key == 'endDate' &&
                      _booleans['current'] == true),
              minLines: field.key == 'description' ? 3 : 1,
              maxLines: field.key == 'description' ? 7 : 1,
              decoration: InputDecoration(
                labelText: '${field.label}${field.required ? ' *' : ''}',
                errorText: _error?.fieldErrors[field.key],
                errorMaxLines: 3,
              ),
              keyboardType: field.kind == QualificationKind.integer
                  ? const TextInputType.numberWithOptions(signed: true)
                  : field.kind == QualificationKind.date
                  ? TextInputType.datetime
                  : field.key == 'description'
                  ? TextInputType.multiline
                  : TextInputType.text,
              validator: (v) =>
                  widget.resource == QualificationResource.experience &&
                      field.key == 'endDate' &&
                      _booleans['current'] == true
                  ? null
                  : field.validate(v),
            ),
          const SizedBox(height: 16),
        ],
        if (_needsReload) ...[
          const Text(
            'The save result could not be confirmed. Reload records before retrying to avoid creating duplicates.',
          ),
          OutlinedButton(
            onPressed: _busy ? null : widget.onReload,
            child: const Text('Reload records'),
          ),
        ],
        FilledButton(
          onPressed: _busy || _needsReload ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Save record'),
        ),
      ],
    ),
  );
}
