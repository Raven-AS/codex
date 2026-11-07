import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../client/presentation/client_widgets.dart';
import '../data/lawyer_repository.dart';
import '../domain/lawyer_models.dart';
import '../domain/lawyer_validation.dart';

class LawyerProfileEditor extends StatefulWidget {
  const LawyerProfileEditor({
    super.key,
    required this.repository,
    required this.profile,
    required this.personal,
    required this.onSaved,
    this.onboarding = false,
  });
  final LawyerRepository repository;
  final LawyerProfile profile;
  final bool personal;
  final ValueChanged<LawyerProfile> onSaved;
  final bool onboarding;
  @override
  State<LawyerProfileEditor> createState() => _LawyerProfileEditorState();
}

class _LawyerProfileEditorState extends State<LawyerProfileEditor> {
  final _form = GlobalKey<FormState>();
  late final _fields = {
    for (final key
        in (widget.personal
                ? LawyerProfile.personalKeys
                : LawyerProfile.professionalKeys)
            .where((k) => k != 'gender'))
      key: TextEditingController(text: widget.profile.text(key) ?? ''),
  };
  late String? _gender = widget.profile.text('gender');
  ApiException? _error;
  bool _busy = false;
  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final changes = <String, Object?>{};
      for (final field in _fields.entries) {
        final value = field.value.text.trim();
        changes[field.key] = field.key == 'yearsOfExperience'
            ? (value.isEmpty ? null : int.parse(value))
            : (value.isEmpty &&
                      ['dateOfBirth', 'professionalPhone'].contains(field.key)
                  ? null
                  : value);
      }
      if (widget.personal) changes['gender'] = _gender;
      final result = await widget.repository.saveProfile(changes);
      if (mounted) widget.onSaved(result);
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
      title: widget.personal
          ? 'Personal information'
          : 'Professional information',
      children: [
        const Text(
          'First name and bar registration number are required for verification submission. Other fields are optional.',
        ),
        const SizedBox(height: 12),
        const Text(
          'Leaving date, gender, experience, or phone blank keeps the saved value. Professional contact details are separate from sign-in credentials.',
        ),
        const SizedBox(height: 16),
        ClientErrorNotice(error: _error),
        for (final field in _fields.entries) ...[
          TextFormField(
            key: ValueKey('lawyer-${field.key}'),
            controller: field.value,
            enabled: !_busy,
            minLines: field.key == 'bio' ? 3 : 1,
            maxLines: field.key == 'bio' ? 8 : 1,
            decoration: InputDecoration(
              labelText: LawyerValidation.labels[field.key],
              errorText: _error?.fieldErrors[field.key],
              errorMaxLines: 3,
            ),
            keyboardType: switch (field.key) {
              'professionalEmail' => TextInputType.emailAddress,
              'professionalPhone' => TextInputType.phone,
              'yearsOfExperience' => TextInputType.number,
              'dateOfBirth' => TextInputType.datetime,
              'bio' => TextInputType.multiline,
              _ => TextInputType.text,
            },
            validator: (value) =>
                LawyerValidation.profileField(field.key, value?.trim()),
          ),
          const SizedBox(height: 16),
        ],
        if (widget.personal) ...[
          DropdownButtonFormField<String>(
            initialValue: _gender,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Gender',
              errorText: _error?.fieldErrors['gender'],
            ),
            items: [
              if (_gender == null)
                const DropdownMenuItem(
                  value: null,
                  child: Text('Not specified'),
                ),
              for (final value in ['MALE', 'FEMALE', 'OTHER'])
                DropdownMenuItem(
                  value: value,
                  child: Text(value.toLowerCase()),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _gender = value),
          ),
          const SizedBox(height: 16),
        ],
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(
            _busy
                ? 'Saving…'
                : widget.onboarding
                ? 'Save and continue'
                : 'Save information',
          ),
        ),
      ],
    ),
  );
}
