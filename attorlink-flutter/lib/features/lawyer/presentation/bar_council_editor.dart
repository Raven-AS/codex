import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../client/presentation/client_widgets.dart';
import '../data/lawyer_repository.dart';
import '../domain/lawyer_models.dart';
import '../domain/lawyer_validation.dart';

class BarCouncilEditor extends StatelessWidget {
  const BarCouncilEditor({
    super.key,
    required this.repository,
    required this.onSaved,
    this.onboarding = false,
  });
  final LawyerRepository repository;
  final ValueChanged<BarCouncilRecord> onSaved;
  final bool onboarding;
  @override
  Widget build(BuildContext context) => ClientLoader<BarCouncilRecord?>(
    load: repository.barCouncil,
    builder: (record) => _CouncilForm(
      repository: repository,
      record: record,
      onSaved: onSaved,
      onboarding: onboarding,
    ),
  );
}

class _CouncilForm extends StatefulWidget {
  const _CouncilForm({
    required this.repository,
    required this.record,
    required this.onSaved,
    required this.onboarding,
  });
  final LawyerRepository repository;
  final BarCouncilRecord? record;
  final ValueChanged<BarCouncilRecord> onSaved;
  final bool onboarding;
  @override
  State<_CouncilForm> createState() => _CouncilFormState();
}

class _CouncilFormState extends State<_CouncilForm> {
  final _form = GlobalKey<FormState>();
  late final _fields = {
    for (final key in BarCouncilRecord.informationKeys)
      key: TextEditingController(text: widget.record?.text(key) ?? ''),
  };
  bool _busy = false;
  ApiException? _error;
  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final information = {
      for (final entry in _fields.entries)
        entry.key: entry.value.text.trim().isEmpty
            ? null
            : entry.value.text.trim(),
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Registration PUT replaces all fields. Preserve the latest document URLs.
      final current = await widget.repository.barCouncil();
      if (!mounted) return;
      final saved = await widget.repository.saveBarCouncil({
        ...information,
        for (final key in BarCouncilRecord.documentKeys)
          key: current?.text(key),
      });
      if (mounted) widget.onSaved(saved);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: ClientFormLayout(
      title: 'Bar Council registration',
      children: [
        Text(
          widget.record == null
              ? 'No Bar Council record is saved. Save this section before submitting your profile.'
              : 'Record verification status: ${widget.record!.status}',
        ),
        const SizedBox(height: 12),
        const Text(
          'Saving these details resets the Bar Council record status to PENDING. Profile verification status is tracked separately. The fields below are optional; a saved record is required for submission.',
        ),
        const SizedBox(height: 16),
        ClientErrorNotice(error: _error),
        for (final field in _fields.entries) ...[
          TextFormField(
            key: ValueKey('council-${field.key}'),
            controller: field.value,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: LawyerValidation.labels[field.key],
              errorText: _error?.fieldErrors[field.key],
              errorMaxLines: 3,
            ),
            keyboardType: field.key.endsWith('Date')
                ? TextInputType.datetime
                : TextInputType.text,
            validator: (v) =>
                LawyerValidation.councilField(field.key, v?.trim()),
          ),
          const SizedBox(height: 16),
        ],
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(
            _busy
                ? 'Saving…'
                : widget.onboarding
                ? 'Save record and continue'
                : 'Save Bar Council record',
          ),
        ),
      ],
    ),
  );
}
