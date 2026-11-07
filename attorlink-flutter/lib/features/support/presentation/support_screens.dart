import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../messaging/data/chat_repository.dart' show uncertainChatOutcome;
import '../data/support_repository.dart';
import '../domain/support_ticket.dart';

class SupportAccess extends StatelessWidget {
  const SupportAccess({
    super.key,
    required this.repository,
    required this.child,
  });
  final SupportRepository repository;
  final Widget child;
  @override
  Widget build(BuildContext context) => StreamBuilder<Object?>(
    stream: repository.accessChanges,
    builder: (context, _) {
      try {
        repository.checkAccess();
      } on ApiException catch (error) {
        return Scaffold(
          appBar: AppBar(title: const Text('Support tickets')),
          body: ErrorView(error: error),
        );
      }
      return child;
    },
  );
}

class SupportTickets extends StatefulWidget {
  const SupportTickets({super.key, required this.repository});
  final SupportRepository repository;
  @override
  State<SupportTickets> createState() => _SupportTicketsState();
}

class _SupportTicketsState extends State<SupportTickets> {
  final _tickets = <int, SupportTicket>{};
  ApiPage<SupportTicket>? _page;
  bool _busy = false;
  ApiException? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool more = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.repository.list(
        page: more ? (_page?.page ?? -1) + 1 : 0,
      );
      if (mounted) {
        setState(() {
          if (!more) _tickets.clear();
          for (final ticket in page.content) {
            _tickets[ticket.id] = ticket;
          }
          _page = page;
        });
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          if ([
            ApiErrorKind.unauthorized,
            ApiErrorKind.forbidden,
          ].contains(error.kind)) {
            _tickets.clear();
            _page = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _detail(int id) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SupportTicketDetail(repository: widget.repository, id: id),
      ),
    );
    if (mounted) unawaited(_load());
  }

  Future<void> _create() async {
    final saved = await Navigator.push<SupportTicket>(
      context,
      MaterialPageRoute(
        builder: (_) => SupportTicketForm(repository: widget.repository),
      ),
    );
    if (!mounted) return;
    if (saved != null) {
      await _detail(saved.id);
    } else {
      unawaited(_load());
    }
  }

  @override
  Widget build(BuildContext context) => SupportAccess(
    repository: widget.repository,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('My support tickets'),
        actions: [
          IconButton(
            tooltip: 'Refresh tickets',
            onPressed: _busy ? null : () => _load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _create,
                  icon: const Icon(Icons.add),
                  label: const Text('Create support ticket'),
                ),
              ),
              const Text(
                'Statuses are updated by support. Ticket replies, edits, priority selection, and status changes are not exposed by the user API.',
              ),
              if (_tickets.isEmpty && !_busy && _error == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No support tickets yet.'),
                ),
              for (final ticket in _tickets.values)
                Card(
                  child: ListTile(
                    onTap: () => _detail(ticket.id),
                    title: Text('${ticket.reference} · ${ticket.subject}'),
                    subtitle: Text(
                      '${ticket.category} · ${ticket.status}\n${ticket.createdAt}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
              if (_error != null)
                ErrorView(error: _error!, onRetry: () => _load()),
              if (_busy) const LoadingView(),
              if (_page?.hasNext == true && !_busy)
                TextButton(
                  onPressed: () => _load(more: true),
                  child: const Text('Load more tickets'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class SupportTicketDetail extends StatefulWidget {
  const SupportTicketDetail({
    super.key,
    required this.repository,
    required this.id,
  });
  final SupportRepository repository;
  final int id;
  @override
  State<SupportTicketDetail> createState() => _SupportTicketDetailState();
}

class _SupportTicketDetailState extends State<SupportTicketDetail> {
  bool _busy = false;
  SupportTicket? _ticket;
  ApiException? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ticket = await widget.repository.get(widget.id);
      if (mounted) setState(() => _ticket = ticket);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          if ([
            ApiErrorKind.unauthorized,
            ApiErrorKind.forbidden,
            ApiErrorKind.notFound,
          ].contains(error.kind)) {
            _ticket = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SupportAccess(
    repository: widget.repository,
    child: Scaffold(
      appBar: AppBar(
        title: Text('Support ticket #${widget.id}'),
        actions: [
          IconButton(
            tooltip: 'Refresh ticket status',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_ticket case final ticket?) ...[
                SelectableText(
                  ticket.reference,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text('Category: ${ticket.category}'),
                Text('Backend status: ${ticket.status}'),
                const SizedBox(height: 12),
                SelectableText(
                  ticket.subject,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                SelectableText(ticket.message),
                const SizedBox(height: 12),
                Text('Created: ${ticket.createdAt}'),
                if (ticket.updatedAt != null)
                  Text('Updated: ${ticket.updatedAt}'),
                const Text(
                  'Timestamps are shown as returned by the backend, without timezone conversion.',
                ),
              ],
              if (_error != null) ErrorView(error: _error!, onRetry: _load),
              if (_busy) const LoadingView(),
            ],
          ),
        ),
      ),
    ),
  );
}

class SupportTicketForm extends StatefulWidget {
  const SupportTicketForm({super.key, required this.repository});
  final SupportRepository repository;
  @override
  State<SupportTicketForm> createState() => _SupportTicketFormState();
}

class _SupportTicketFormState extends State<SupportTicketForm> {
  final _form = GlobalKey<FormState>();
  final _subject = TextEditingController(), _message = TextEditingController();
  String _category = 'GENERAL';
  bool _busy = false, _uncertain = false;
  ApiException? _error;
  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _uncertain || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await widget.repository.create(
        subject: _subject.text,
        message: _message.text,
        category: _category,
      );
      if (mounted) Navigator.pop(context, saved);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _uncertain = uncertainChatOutcome(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SupportAccess(
    repository: widget.repository,
    child: Scaffold(
      appBar: AppBar(title: const Text('Create support ticket')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Describe the problem without passwords, OTPs, tokens, or authenticator secrets.',
                ),
                TextFormField(
                  controller: _subject,
                  enabled: !_busy,
                  maxLength: 160,
                  decoration: const InputDecoration(labelText: 'Subject'),
                  validator: ticketSubjectError,
                ),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    for (final category in ticketCategories)
                      DropdownMenuItem(value: category, child: Text(category)),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value != null) setState(() => _category = value);
                        },
                ),
                TextFormField(
                  controller: _message,
                  enabled: !_busy,
                  maxLines: 8,
                  maxLength: 4000,
                  decoration: const InputDecoration(labelText: 'Message'),
                  validator: ticketMessageError,
                ),
                if (_error != null) ErrorView(error: _error!),
                if (_uncertain)
                  const Text(
                    'Submission could not be confirmed. Return to your tickets and refresh before trying again. This form will not repeat the request.',
                  ),
                FilledButton(
                  onPressed: _busy || _uncertain ? null : _submit,
                  child: const Text('Submit ticket'),
                ),
                if (_busy) const LoadingView(),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
