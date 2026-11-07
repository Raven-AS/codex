import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../data/client_repository.dart';
import '../domain/client_models.dart';
import '../domain/client_validation.dart';
import 'client_widgets.dart';

class AddressEditor extends StatelessWidget {
  const AddressEditor({
    super.key,
    required this.repository,
    required this.onSaved,
    this.onboarding = false,
    this.onSkip,
  });
  final ClientRepository repository;
  final VoidCallback onSaved;
  final bool onboarding;
  final VoidCallback? onSkip;
  @override
  Widget build(BuildContext context) => ClientLoader<ClientAddress?>(
    load: repository.address,
    onSkipOnError: onSkip,
    builder: (address) => _AddressForm(
      repository: repository,
      address: address,
      onSaved: onSaved,
      onboarding: onboarding,
      onSkip: onSkip,
    ),
  );
}

class _AddressForm extends StatefulWidget {
  const _AddressForm({
    required this.repository,
    required this.address,
    required this.onSaved,
    required this.onboarding,
    this.onSkip,
  });
  final ClientRepository repository;
  final ClientAddress? address;
  final VoidCallback onSaved;
  final bool onboarding;
  final VoidCallback? onSkip;
  @override
  State<_AddressForm> createState() => _AddressFormState();
}

class _AddressFormState extends State<_AddressForm> {
  final _form = GlobalKey<FormState>();
  late final _fields = {
    for (final key in [...ClientAddress.textKeys, 'latitude', 'longitude'])
      key: TextEditingController(text: widget.address?.text(key) ?? ''),
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.saveAddress({
        for (final entry in _fields.entries)
          entry.key: entry.value.text.trim().isEmpty
              ? null
              : ['latitude', 'longitude'].contains(entry.key)
              ? num.parse(entry.value.text.trim())
              : entry.value.text.trim(),
      });
      if (mounted) widget.onSaved();
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
      title: 'Your address',
      children: [
        if (widget.address == null)
          const Text(
            'No address has been saved. Add one now or leave these optional fields empty.',
          ),
        const SizedBox(height: 16),
        ClientErrorNotice(error: _error),
        for (final entry in _fields.entries) ...[
          TextFormField(
            controller: entry.value,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: switch (entry.key) {
                'addressLine' => 'Address line',
                'postalCode' => 'Postal code',
                _ => '${entry.key[0].toUpperCase()}${entry.key.substring(1)}',
              },
              errorText: _error?.fieldErrors[entry.key],
              errorMaxLines: 3,
            ),
            keyboardType: ['latitude', 'longitude'].contains(entry.key)
                ? const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  )
                : TextInputType.text,
            validator: (v) => ['latitude', 'longitude'].contains(entry.key)
                ? ClientValidation.coordinate(v?.trim())
                : ClientValidation.length(
                    v?.trim(),
                    ClientValidation.addressLimits[entry.key]!,
                  ),
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
                : 'Save address',
          ),
        ),
        if (widget.onSkip != null)
          TextButton(
            onPressed: _busy ? null : widget.onSkip,
            child: const Text('Skip for now'),
          ),
      ],
    ),
  );
}
