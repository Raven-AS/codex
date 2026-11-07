import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/error_view.dart';
import '../../messaging/data/chat_repository.dart';
import '../../messaging/presentation/chat_access.dart';
import '../data/call_repository.dart';
import '../domain/call_models.dart';

const callTimeHelp =
    'Backend wall time (no timezone or UTC conversion). Confirm the server timezone before scheduling. The server enforces future times, notice, horizon, conflicts, cutoffs, and join windows.';

class CallForm extends StatefulWidget {
  const CallForm({
    super.key,
    required this.repository,
    required this.scheduled,
    this.existing,
    this.recipient,
    this.conversationId,
  });
  final CallRepository repository;
  final bool scheduled;
  final CallRecord? existing;
  final int? recipient, conversationId;
  @override
  State<CallForm> createState() => _CallFormState();
}

class _CallFormState extends State<CallForm> {
  final _form = GlobalKey<FormState>();
  late final _recipient = TextEditingController(
    text: widget.recipient?.toString(),
  );
  late final _conversation = TextEditingController(
    text: widget.conversationId?.toString(),
  );
  late final _time = TextEditingController(
    text: widget.existing?.fields['scheduledAt'] as String?,
  );
  final _note = TextEditingController();
  bool _busy = false, _uncertain = false;
  ApiException? _error;
  @override
  void dispose() {
    for (final controller in [_recipient, _conversation, _time, _note]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || _uncertain || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final existing = widget.existing;
      final saved = existing == null
          ? await widget.repository.create(
              recipient: int.parse(_recipient.text.trim()),
              conversationId: int.tryParse(_conversation.text.trim()),
              note: _note.text,
              scheduledAt: widget.scheduled ? _time.text.trim() : null,
            )
          : await widget.repository.action(
              existing,
              'reschedule',
              scheduledAt: _time.text.trim(),
              reason: _note.text,
            );
      if (mounted) Navigator.pop(context, saved);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _uncertain = uncertainChatOutcome(error);
        });
      }
    } on FormatException catch (error) {
      if (mounted) {
        setState(
          () => _error = ApiException(
            kind: ApiErrorKind.validation,
            message: error.message,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ChatAccess(
    repository: widget.repository.chat,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing != null
              ? 'Reschedule call'
              : widget.scheduled
              ? 'Schedule call'
              : 'Start call',
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Calls use user IDs. Lawyer participants must be verified. Any supplied conversation must include both users and be accepted. Eligibility remains server-authoritative.',
                ),
                const SizedBox(height: 12),
                if (widget.existing == null) ...[
                  TextFormField(
                    controller: _recipient,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Recipient user ID',
                    ),
                    validator: (text) {
                      final id = int.tryParse(text?.trim() ?? '');
                      return id == null ||
                              id <= 0 ||
                              id == widget.repository.chat.ownerId
                          ? 'Enter another positive user ID.'
                          : null;
                    },
                  ),
                  TextFormField(
                    controller: _conversation,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Accepted conversation ID (optional)',
                    ),
                    validator: (text) =>
                        text == null ||
                            text.trim().isEmpty ||
                            (int.tryParse(text.trim()) ?? 0) > 0
                        ? null
                        : 'Enter a positive conversation ID.',
                  ),
                ],
                if (widget.scheduled) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(callTimeHelp),
                  ),
                  TextFormField(
                    controller: _time,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Scheduled time',
                      hintText: 'YYYY-MM-DDTHH:mm:ss',
                    ),
                    validator: (value) {
                      try {
                        callLocalTime(value?.trim() ?? '');
                        return null;
                      } on FormatException catch (error) {
                        return error.message;
                      }
                    },
                  ),
                ],
                if (widget.scheduled)
                  TextFormField(
                    controller: _note,
                    enabled: !_busy,
                    maxLines: 3,
                    maxLength: widget.scheduled ? 500 : null,
                    decoration: InputDecoration(
                      labelText: widget.existing == null
                          ? 'Note (optional)'
                          : 'Reason (optional; replaces saved notes)',
                    ),
                  ),
                if (_error != null) ErrorView(error: _error!),
                if (_uncertain)
                  const Text(
                    'The outcome is unknown. Close this form and review or refresh your calls before trying again.',
                  ),
                const Text(
                  'Audio/video requires the configured LiveKit service. After starting or accepting a call, open its details and choose Join audio/video.',
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy || _uncertain ? null : _save,
                  child: Text(
                    _busy
                        ? 'Saving…'
                        : widget.existing != null
                        ? 'Reschedule'
                        : widget.scheduled
                        ? 'Schedule'
                        : 'Start backend call',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class CallActionDialog extends StatefulWidget {
  const CallActionDialog({
    super.key,
    required this.repository,
    required this.action,
  });
  final CallRepository repository;
  final String action;
  @override
  State<CallActionDialog> createState() => _CallActionDialogState();
}

class _CallActionDialogState extends State<CallActionDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController(),
      _type = TextEditingController(),
      _payload = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    _type.dispose();
    _payload.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final signal = widget.action == 'signal';
    return ChatAccess(
      repository: widget.repository.chat,
      child: AlertDialog(
        title: Text(
          signal ? 'Submit actual signaling data' : 'Confirm ${widget.action}',
        ),
        content: SizedBox(
          width: 480,
          child: Form(
            key: _form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    signal
                        ? 'This backend only records signal receipt; it does not relay the payload or establish media. Supply real data only.'
                        : 'This updates the call status on the server. Audio/video connection status is shown separately.',
                  ),
                  if (signal) ...[
                    TextFormField(
                      controller: _type,
                      decoration: const InputDecoration(
                        labelText: 'Signal type',
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    TextFormField(
                      controller: _payload,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Signal payload',
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                  ] else if ([
                    'reject',
                    'cancel',
                    'end',
                  ].contains(widget.action))
                    TextFormField(
                      controller: _reason,
                      maxLength: 255,
                      decoration: const InputDecoration(
                        labelText: 'Reason (optional)',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () {
              if (_form.currentState!.validate()) {
                Navigator.pop(context, {
                  'reason': _reason.text,
                  'signalType': _type.text,
                  'payload': _payload.text,
                });
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }
}
