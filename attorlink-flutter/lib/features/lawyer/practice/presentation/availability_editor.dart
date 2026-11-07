import 'package:flutter/material.dart';

import '../../../../core/network/api_exception.dart';
import '../../../client/presentation/client_widgets.dart';
import '../data/practice_repository.dart';
import '../domain/weekly_availability.dart';

class AvailabilityEditor extends StatelessWidget {
  const AvailabilityEditor({super.key, required this.repository});
  final PracticeRepository repository;
  @override
  Widget build(BuildContext context) => ClientLoader<List<SavedAvailability>>(
    load: repository.availability,
    builder: (saved) => _WeekForm(repository: repository, saved: saved),
  );
}

class _RangeFields {
  _RangeFields({String start = '', String end = ''})
    : start = TextEditingController(text: start),
      end = TextEditingController(text: end);
  final TextEditingController start;
  final TextEditingController end;
  void dispose() {
    start.dispose();
    end.dispose();
  }
}

class _WeekForm extends StatefulWidget {
  const _WeekForm({required this.repository, required this.saved});
  final PracticeRepository repository;
  final List<SavedAvailability> saved;
  @override
  State<_WeekForm> createState() => _WeekFormState();
}

class _WeekFormState extends State<_WeekForm> {
  final _form = GlobalKey<FormState>();
  late Map<WorkingDay, List<_RangeFields>> _ranges;
  late Map<WorkingDay, bool> _enabled;
  late List<SavedAvailability> _saved;
  ApiException? _error;
  bool _busy = false;
  bool _needsReload = false;
  String? _message;
  final List<_RangeFields> _retired = [];
  @override
  void initState() {
    super.initState();
    _setSaved(widget.saved);
  }

  void _setSaved(List<SavedAvailability> saved) {
    _saved = List.unmodifiable(saved);
    _ranges = {
      for (final day in WorkingDay.values)
        day: [
          for (final item in saved.where(
            (s) => s.available && s.range.day == day,
          ))
            _RangeFields(
              start: item.range.start.wire,
              end: item.range.end.wire,
            ),
        ],
    };
    _enabled = {
      for (final day in WorkingDay.values) day: _ranges[day]!.isNotEmpty,
    };
  }

  @override
  void dispose() {
    for (final fields in [..._ranges.values.expand((v) => v), ..._retired]) {
      fields.dispose();
    }
    super.dispose();
  }

  String? _timeError(String? value) {
    try {
      WorkingTime.parse(value ?? '');
      return null;
    } on FormatException {
      return 'Use HH:mm or HH:mm:ss (optional fractional seconds).';
    }
  }

  Future<void> _reload() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await widget.repository.availability();
      if (!mounted) return;
      setState(() {
        _retired.addAll(_ranges.values.expand((v) => v));
        _setSaved(saved);
        _needsReload = false;
        _message = 'Saved availability reloaded.';
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _needsReload || !_form.currentState!.validate()) return;
    final slots = <AvailabilityRange>[];
    final errors = <String, String>{};
    for (final day in WorkingDay.values.where((d) => _enabled[d]!)) {
      if (_ranges[day]!.isEmpty) {
        errors[day.wire] =
            'Add a range for ${day.label} or mark it unavailable.';
      }
      for (final range in _ranges[day]!) {
        slots.add(
          AvailabilityRange(
            day: day,
            start: WorkingTime.parse(range.start.text),
            end: WorkingTime.parse(range.end.text),
          ),
        );
      }
    }
    try {
      if (errors.isNotEmpty) {
        throw ApiException(
          kind: ApiErrorKind.validation,
          message: errors.values.join('\n'),
          fieldErrors: errors,
        );
      }
      validateAvailability(slots);
    } on ApiException catch (error) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      if (slots.isEmpty) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Save a week with no availability?'),
            content: const Text('This clears all saved working-hour slots.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Clear saved week'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      final saved = await widget.repository.saveAvailability(slots);
      if (!mounted) return;
      setState(() {
        _retired.addAll(_ranges.values.expand((v) => v));
        _setSaved(saved);
        _message = 'Weekly availability saved.';
      });
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
      title: 'Weekly availability',
      children: [
        const Text(
          'Saving replaces the whole week. Enable days and add one or more working-hour ranges. Unavailable days send no slots. Times are local wall-clock values, without a timezone conversion.',
        ),
        const SizedBox(height: 12),
        if (_saved.isEmpty && _message == null)
          const Text('No weekly availability has been saved.'),
        if (_saved.any((s) => !s.available))
          const Text(
            'Unavailable entries returned by the server are omitted when saving. The API saves submitted ranges as available.',
          ),
        ClientErrorNotice(error: _error),
        if (_error?.fieldErrors.isNotEmpty == true)
          Text(_error!.fieldErrors.values.join('\n')),
        if (_message != null)
          Semantics(liveRegion: true, child: Text(_message!)),
        for (final day in WorkingDay.values)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(day.label),
                    subtitle: Text(
                      _enabled[day]! ? 'Available' : 'Unavailable',
                    ),
                    value: _enabled[day]!,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                            _enabled[day] = value;
                            if (value && _ranges[day]!.isEmpty) {
                              _ranges[day]!.add(_RangeFields());
                            }
                          }),
                  ),
                  if (_enabled[day]!) ...[
                    for (final range in _ranges[day]!)
                      Padding(
                        key: ObjectKey(range),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          children: [
                            TextFormField(
                              controller: range.start,
                              enabled: !_busy,
                              decoration: const InputDecoration(
                                labelText: 'Start time',
                                hintText: 'HH:mm:ss',
                              ),
                              keyboardType: TextInputType.datetime,
                              validator: _timeError,
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: range.end,
                              enabled: !_busy,
                              decoration: const InputDecoration(
                                labelText: 'End time',
                                hintText: 'HH:mm:ss',
                              ),
                              keyboardType: TextInputType.datetime,
                              validator: _timeError,
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                      _ranges[day]!.remove(range);
                                      _retired.add(range);
                                    }),
                              child: const Text('Remove range'),
                            ),
                          ],
                        ),
                      ),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => setState(
                              () => _ranges[day]!.add(_RangeFields()),
                            ),
                      child: const Text('Add time range'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (_needsReload)
          const Text(
            'The save result could not be confirmed. Reload saved availability before another attempt.',
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy || _needsReload ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Save whole week'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : _reload,
          child: const Text('Reload saved availability'),
        ),
      ],
    ),
  );
}
