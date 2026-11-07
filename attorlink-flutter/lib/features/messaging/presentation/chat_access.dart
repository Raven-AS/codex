import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/error_view.dart';
import '../data/chat_repository.dart';

class ChatAccess extends StatelessWidget {
  const ChatAccess({super.key, required this.repository, required this.child});
  final ChatRepository repository;
  final Widget child;
  @override
  Widget build(BuildContext context) => StreamBuilder<Object?>(
    stream: repository.accessChanges,
    builder: (context, _) {
      try {
        repository.checkAccess();
      } on ApiException catch (error) {
        return Scaffold(
          appBar: AppBar(title: const Text('Messages')),
          body: ErrorView(error: error),
        );
      }
      return child;
    },
  );
}

class ChatTextDialog extends StatefulWidget {
  const ChatTextDialog({
    super.key,
    required this.repository,
    required this.text,
  });
  final ChatRepository repository;
  final String text;
  @override
  State<ChatTextDialog> createState() => _ChatTextDialogState();
}

class _ChatTextDialogState extends State<ChatTextDialog> {
  late final _text = TextEditingController(text: widget.text);
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChatAccess(
    repository: widget.repository,
    child: AlertDialog(
      title: const Text('Edit message'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: TextFormField(
            controller: _text,
            maxLines: 6,
            maxLength: 4000,
            decoration: const InputDecoration(labelText: 'Message text'),
            validator: (text) =>
                text == null || text.trim().isEmpty || text.length > 4000
                ? 'Enter text of at most 4000 characters.'
                : null,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_form.currentState!.validate()) {
              Navigator.pop(context, _text.text);
            }
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
