import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../data/client_repository.dart';
import '../domain/client_models.dart';
import '../domain/client_validation.dart';
import 'client_widgets.dart';

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({
    super.key,
    required this.repository,
    required this.profile,
    required this.onSaved,
    this.onboarding = false,
  });
  final ClientRepository repository;
  final ClientProfile profile;
  final ValueChanged<ClientProfile> onSaved;
  final bool onboarding;
  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  final _form = GlobalKey<FormState>();
  late final _fields = {
    for (final key in ClientProfile.editableKeys.where((k) => k != 'gender'))
      key: TextEditingController(text: widget.profile.text(key) ?? ''),
  };
  late String? _gender = widget.profile.text('gender');
  ApiException? _error;
  bool _busy = false;
  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
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
      final result = await widget.repository.saveProfile({
        for (final entry in _fields.entries)
          entry.key: entry.value.text.trim().isEmpty
              ? null
              : entry.value.text.trim(),
        'gender': _gender,
      });
      if (mounted) widget.onSaved(result);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: ClientFormLayout(
      title: widget.onboarding ? 'Tell us about yourself' : 'Edit profile',
      children: [
        const Text(
          'All fields are optional. Your profile contact details are separate from your sign-in email.',
        ),
        const SizedBox(height: 16),
        ClientErrorNotice(error: _error),
        for (final entry in _fields.entries) ...[
          TextFormField(
            key: ValueKey('client-${entry.key}'),
            controller: entry.value,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: switch (entry.key) {
                'firstName' => 'First name',
                'lastName' => 'Last name',
                'dateOfBirth' => 'Date of birth (YYYY-MM-DD)',
                'phone' => 'Profile phone',
                'email' => 'Profile contact email',
                _ => 'Occupation',
              },
              errorText: _error?.fieldErrors[entry.key],
              errorMaxLines: 3,
            ),
            keyboardType: switch (entry.key) {
              'email' => TextInputType.emailAddress,
              'phone' => TextInputType.phone,
              'dateOfBirth' => TextInputType.datetime,
              _ => TextInputType.text,
            },
            validator: (v) {
              final value = v?.trim();
              if (entry.key == 'phone') return ClientValidation.phone(value);
              if (entry.key == 'email') return ClientValidation.email(value);
              if (entry.key == 'dateOfBirth') {
                return ClientValidation.birthDate(value);
              }
              return ClientValidation.length(
                value,
                ClientValidation.profileLimits[entry.key]!,
              );
            },
          ),
          const SizedBox(height: 16),
        ],
        DropdownButtonFormField<String>(
          initialValue: _gender,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Gender',
            errorText: _error?.fieldErrors['gender'],
          ),
          items: [
            if (widget.profile.text('gender') == null)
              const DropdownMenuItem(value: null, child: Text('Not specified')),
            for (final value in ['MALE', 'FEMALE', 'OTHER'])
              DropdownMenuItem(value: value, child: Text(value.toLowerCase())),
          ],
          onChanged: _busy ? null : (value) => setState(() => _gender = value),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(
            _busy
                ? 'Saving…'
                : widget.onboarding
                ? 'Save and continue'
                : 'Save profile',
          ),
        ),
      ],
    ),
  );
}
