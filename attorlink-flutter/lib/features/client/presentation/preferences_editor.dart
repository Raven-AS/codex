import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../data/client_repository.dart';
import '../domain/client_models.dart';
import '../domain/client_validation.dart';
import 'client_widgets.dart';

class PreferencesEditor extends StatelessWidget {
  const PreferencesEditor({
    super.key,
    required this.repository,
    required this.onSaved,
    this.onSkip,
  });
  final ClientRepository repository;
  final VoidCallback onSaved;
  final VoidCallback? onSkip;
  @override
  Widget build(BuildContext context) =>
      ClientLoader<(LegalPreferences, PreferenceCatalogs)>(
        onSkipOnError: onSkip,
        load: () async {
          final results = await Future.wait<Object>([
            repository.preferences(),
            repository.catalogs(),
          ]);
          return (
            results[0] as LegalPreferences,
            results[1] as PreferenceCatalogs,
          );
        },
        builder: (data) => _PreferencesForm(
          repository: repository,
          initial: data.$1,
          catalogs: data.$2,
          onSaved: onSaved,
          onSkip: onSkip,
        ),
      );
}

class _PreferencesForm extends StatefulWidget {
  const _PreferencesForm({
    required this.repository,
    required this.initial,
    required this.catalogs,
    required this.onSaved,
    this.onSkip,
  });
  final ClientRepository repository;
  final LegalPreferences initial;
  final PreferenceCatalogs catalogs;
  final VoidCallback onSaved;
  final VoidCallback? onSkip;
  @override
  State<_PreferencesForm> createState() => _PreferencesFormState();
}

class _PreferencesFormState extends State<_PreferencesForm> {
  late final _areas = widget.initial.practiceAreas.map((e) => e.id).toSet();
  late final _jurisdictions = widget.initial.jurisdictions
      .map((e) => e.id)
      .toSet();
  late final _courts = widget.initial.courts.map((e) => e.id).toSet();
  late final _languages = [...widget.initial.lawyerLanguages];
  final _language = TextEditingController();
  String? _languageError;
  ApiException? _error;
  bool _busy = false;
  @override
  void dispose() {
    _language.dispose();
    super.dispose();
  }

  bool _addLanguage() {
    final raw = _language.text.trim();
    if (raw.length > 60) {
      setState(() => _languageError = 'Use at most 60 characters.');
      return false;
    }
    final value = ClientValidation.normalizeLanguage(raw);
    if (value.isNotEmpty &&
        !_languages.any((v) => v.toLowerCase() == value.toLowerCase())) {
      _languages.add(value);
    }
    _language.clear();
    setState(() => _languageError = null);
    return true;
  }

  Future<void> _save() async {
    if (_busy || !_addLanguage()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.savePreferences(
        practiceAreaIds: _areas,
        jurisdictionIds: _jurisdictions,
        courtIds: _courts,
        lawyerLanguages: _languages,
      );
      if (mounted) widget.onSaved();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ClientFormLayout(
    title: 'Legal preferences',
    children: [
      const Text(
        'Choose the legal areas, locations, courts, and lawyer languages you prefer. All selections are optional. Saving empty selections clears your preferences.',
      ),
      const SizedBox(height: 16),
      ClientErrorNotice(error: _error),
      for (final entry in [
        (
          'Practice areas',
          widget.catalogs.practiceAreas,
          _areas,
          widget.initial.practiceAreas,
        ),
        (
          'Jurisdictions',
          widget.catalogs.jurisdictions,
          _jurisdictions,
          widget.initial.jurisdictions,
        ),
        ('Courts', widget.catalogs.courts, _courts, widget.initial.courts),
      ])
        _ReferenceChoices(
          title: entry.$1,
          items: entry.$2,
          selected: entry.$3,
          previous: entry.$4,
          enabled: !_busy,
          onChanged: () => setState(() {}),
        ),
      const SizedBox(height: 16),
      Text('Lawyer languages', style: Theme.of(context).textTheme.titleMedium),
      if (_languages.isEmpty) const Text('No preferred languages selected.'),
      Wrap(
        spacing: 8,
        children: [
          for (final value in _languages)
            InputChip(
              label: Text(value),
              onDeleted: _busy
                  ? null
                  : () => setState(() => _languages.remove(value)),
            ),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _language,
        enabled: !_busy,
        decoration: InputDecoration(
          labelText: 'Add a language',
          errorText: _languageError,
          helperText: 'Enter a language name, then tap Add.',
        ),
        onSubmitted: _busy ? null : (_) => _addLanguage(),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: _busy ? null : _addLanguage,
          child: const Text('Add language'),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(_busy ? 'Saving…' : 'Save preferences'),
      ),
      if (widget.onSkip != null)
        TextButton(
          onPressed: _busy ? null : widget.onSkip,
          child: const Text('Skip for now'),
        ),
    ],
  );
}

class _ReferenceChoices extends StatefulWidget {
  const _ReferenceChoices({
    required this.title,
    required this.items,
    required this.selected,
    required this.previous,
    required this.enabled,
    required this.onChanged,
  });
  final String title;
  final List<ReferenceItem> items;
  final List<ReferenceItem> previous;
  final Set<int> selected;
  final bool enabled;
  final VoidCallback onChanged;
  @override
  State<_ReferenceChoices> createState() => _ReferenceChoicesState();
}

class _ReferenceChoicesState extends State<_ReferenceChoices> {
  String _search = '';
  @override
  Widget build(BuildContext context) {
    final items = widget.items
        .where(
          (item) => item.name.toLowerCase().contains(_search.toLowerCase()),
        )
        .toList();
    final unavailable = widget.previous.where(
      (item) =>
          widget.selected.contains(item.id) &&
          !widget.items.any((v) => v.id == item.id),
    );
    return ExpansionTile(
      title: Text('${widget.title} (${widget.selected.length})'),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            enabled: widget.enabled,
            decoration: InputDecoration(
              labelText: 'Search ${widget.title.toLowerCase()}',
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        for (final item in unavailable)
          CheckboxListTile(
            value: true,
            title: Text('${item.name} (no longer available; remove to save)'),
            onChanged: !widget.enabled
                ? null
                : (_) {
                    widget.selected.remove(item.id);
                    widget.onChanged();
                  },
          ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              widget.items.isEmpty
                  ? 'No active options are available.'
                  : 'No matching options.',
            ),
          )
        else
          SizedBox(
            height: 220,
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return CheckboxListTile(
                  value: widget.selected.contains(item.id),
                  title: Text(item.name),
                  onChanged: !widget.enabled
                      ? null
                      : (selected) {
                          if (selected == true) {
                            widget.selected.add(item.id);
                          } else {
                            widget.selected.remove(item.id);
                          }
                          widget.onChanged();
                        },
                );
              },
            ),
          ),
      ],
    );
  }
}
