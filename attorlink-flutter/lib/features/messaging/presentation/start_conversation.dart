import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../data/chat_repository.dart';
import '../domain/chat_models.dart';
import 'chat_access.dart';

class StartConversation extends StatefulWidget {
  const StartConversation({super.key, required this.repository});
  final ChatRepository repository;
  @override
  State<StartConversation> createState() => _StartConversationState();
}

class _StartConversationState extends State<StartConversation> {
  final _recipient = TextEditingController(), _text = TextEditingController();
  bool _busy = false, _uncertain = false;
  String? _error;
  @override
  void dispose() {
    _recipient.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy || _uncertain) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = int.tryParse(_recipient.text.trim());
      if (id == null) {
        throw const ApiException(
          kind: ApiErrorKind.validation,
          message: 'Enter a positive recipient user ID.',
        );
      }
      final conversation = await widget.repository.start(id, _text.text);
      if (mounted) {
        Navigator.pop<ChatConversation>(context, conversation);
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = [
            error.message,
            ...error.fieldErrors.values.toSet(),
          ].join('\n');
          _uncertain = uncertainChatOutcome(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ChatAccess(
    repository: widget.repository,
    child: PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Start conversation')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Client–lawyer and lawyer–lawyer conversations are supported. Recipient privacy may require following. New requests must be accepted before ordinary messaging.',
                ),
                TextField(
                  controller: _recipient,
                  enabled: !_busy && !_uncertain,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Recipient user ID',
                  ),
                ),
                TextField(
                  controller: _text,
                  enabled: !_busy && !_uncertain,
                  maxLines: 6,
                  maxLength: 4000,
                  decoration: const InputDecoration(
                    labelText: 'First message (optional)',
                  ),
                ),
                const Text(
                  'An existing conversation may be returned instead of a new request. Check its status and history; a first message is added only for a new conversation.',
                ),
                if (_error != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_uncertain)
                  const Text(
                    'The result could not be confirmed. Return to the inbox and check for the request before starting again.',
                  ),
                FilledButton(
                  onPressed: _busy || _uncertain ? null : _start,
                  child: Text(
                    _busy ? 'Please wait…' : 'Start or open conversation',
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
