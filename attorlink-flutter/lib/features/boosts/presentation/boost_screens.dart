import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../../core/utils/merge_records.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../messaging/data/chat_repository.dart' show uncertainChatOutcome;
import '../data/boost_repository.dart';
import '../data/boost_platform.dart';
import '../domain/boost_models.dart';

class BoostAccess extends StatelessWidget {
  const BoostAccess({super.key, required this.repository, required this.child});
  final BoostRepository repository;
  final Widget child;
  @override
  Widget build(BuildContext context) => StreamBuilder<Object?>(
    stream: repository.accessChanges,
    builder: (context, _) {
      try {
        repository.checkAccess();
      } on ApiException catch (error) {
        return Scaffold(
          appBar: AppBar(title: const Text('Profile boosts')),
          body: ErrorView(error: error),
        );
      }
      return child;
    },
  );
}

class BoostFields extends StatelessWidget {
  const BoostFields(this.data, {super.key});
  final BoostData data;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final entry in data.fields.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SelectableText('${entry.key}: ${entry.value}'),
        ),
    ],
  );
}

enum BoostView { plans, history, invoices, activities }

class BoostHub extends StatelessWidget {
  const BoostHub({super.key, required this.repository});
  final BoostRepository repository;
  @override
  Widget build(BuildContext context) => BoostAccess(
    repository: repository,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Profile boosts',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const Text(
          'Purchasing requires a verified lawyer profile. Sandbox checkout is a demonstration and does not prove payment or activate a boost. Status always comes from the backend.',
        ),
        for (final view in [
          BoostView.plans,
          BoostView.history,
          BoostView.invoices,
        ])
          ListTile(
            title: Text(switch (view) {
              BoostView.plans => 'Available plans',
              BoostView.history => 'Purchase history',
              _ => 'Invoices',
            }),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    BoostListScreen(repository: repository, view: view),
              ),
            ),
          ),
        ListTile(
          title: const Text('Boost analytics'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => BoostAnalyticsScreen(repository: repository),
            ),
          ),
        ),
      ],
    ),
  );
}

class BoostListScreen extends StatefulWidget {
  const BoostListScreen({
    super.key,
    required this.repository,
    required this.view,
    this.boostId,
  });
  final BoostRepository repository;
  final BoostView view;
  final int? boostId;
  @override
  State<BoostListScreen> createState() => _BoostListScreenState();
}

class _BoostListScreenState extends State<BoostListScreen> {
  final _rows = <BoostData>[];
  ApiPage<BoostData>? _page;
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
      ApiPage<BoostData>? page;
      final number = more ? (_page?.page ?? -1) + 1 : 0;
      final rows = switch (widget.view) {
        BoostView.plans => await widget.repository.plans(),
        BoostView.invoices => await widget.repository.invoices(),
        BoostView.history => (page = await widget.repository.history(
          page: number,
        )).content,
        BoostView.activities => (page = await widget.repository.activities(
          widget.boostId!,
          page: number,
        )).content,
      };
      if (mounted) {
        setState(() {
          if (!more) _rows.clear();
          final merged = mergeRecords(_rows, rows, identity: (row) => row.id);
          _rows
            ..clear()
            ..addAll(merged);
          _page = page;
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(BoostData row) async {
    if (widget.view == BoostView.activities) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => widget.view == BoostView.plans
            ? BoostPlanReview(repository: widget.repository, plan: row)
            : BoostDetail(
                repository: widget.repository,
                id: row.id,
                invoice: widget.view == BoostView.invoices,
              ),
      ),
    );
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) => BoostAccess(
    repository: widget.repository,
    child: Scaffold(
      appBar: AppBar(
        title: Text(switch (widget.view) {
          BoostView.plans => 'Available plans',
          BoostView.history => 'Purchase history',
          BoostView.invoices => 'Invoices',
          BoostView.activities => 'Boost activity',
        }),
        actions: [
          IconButton(
            tooltip: 'Refresh',
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
              if (_error != null)
                ErrorView(error: _error!, onRetry: () => _load()),
              if (_rows.isEmpty && !_busy && _error == null)
                const Text('No records available.'),
              for (final row in _rows)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(switch (widget.view) {
                          BoostView.plans => row.text('name'),
                          BoostView.history =>
                            'Boost #${row.id} · ${row.text('planName')}',
                          BoostView.invoices => row.text('invoiceNumber'),
                          BoostView.activities => row.text('activityType'),
                        }, style: Theme.of(context).textTheme.titleMedium),
                        if (widget.view == BoostView.plans)
                          Text(
                            '${row.text('price')} ${row.text('currency')} · ${row.text('durationDays')} days',
                          ),
                        if (widget.view == BoostView.history)
                          Text(
                            '${row.text('boostStatus')} · Payment: ${row.text('paymentStatus')}',
                          ),
                        if (widget.view == BoostView.invoices)
                          Text(
                            '${row.text('amount')} ${row.text('currency')} · ${row.text('status')}',
                          ),
                        if (widget.view == BoostView.activities)
                          BoostFields(row)
                        else
                          TextButton(
                            onPressed: () => _open(row),
                            child: Text(
                              widget.view == BoostView.plans
                                  ? 'Review plan'
                                  : 'Details',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (_busy) const LoadingView(),
              if (_page?.hasNext == true && !_busy)
                TextButton(
                  onPressed: () => _load(more: true),
                  child: const Text('Load more'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class BoostPlanReview extends StatefulWidget {
  const BoostPlanReview({
    super.key,
    required this.repository,
    required this.plan,
  });
  final BoostRepository repository;
  final BoostData plan;
  @override
  State<BoostPlanReview> createState() => _BoostPlanReviewState();
}

class _BoostPlanReviewState extends State<BoostPlanReview> {
  bool _busy = false, _verified = false, _checked = false, _blocked = false;
  ApiException? _error;
  BoostData? _purchase;
  @override
  void initState() {
    super.initState();
    unawaited(_verify());
  }

  Future<void> _verify() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final verified = await widget.repository.verified();
      if (mounted) {
        setState(() {
          _verified = verified;
          _checked = true;
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buy() async {
    if (_busy || !_verified || _blocked || _purchase != null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await widget.repository.purchase(widget.plan.id);
      if (mounted) setState(() => _purchase = saved);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _blocked =
              error.kind == ApiErrorKind.conflict ||
              uncertainChatOutcome(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => BoostAccess(
    repository: widget.repository,
    child: Scaffold(
      appBar: AppBar(title: const Text('Review boost purchase')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              BoostFields(widget.plan),
              const Text(
                'Review the plan before initiating a purchase. The backend confirms the current price, eligibility, and purchase state. Sandbox checkout does not mark a purchase paid or activate a boost.',
              ),
              if (_checked && !_verified)
                const Text(
                  'Only verified lawyers can purchase. You may still browse plans and history.',
                ),
              if (_error != null)
                ErrorView(error: _error!, onRetry: _blocked ? null : _verify),
              if (_blocked)
                const Text(
                  'A pending purchase may already exist, or the result is unknown. Review purchase history before trying again. This form will not repeat the purchase.',
                ),
              if (_purchase case final purchase?) ...[
                const Text('Backend purchase response'),
                BoostFields(purchase),
                FilledButton(
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BoostDetail(
                        repository: widget.repository,
                        id: purchase.id,
                      ),
                    ),
                  ),
                  child: const Text('View purchase / sandbox checkout'),
                ),
              ] else
                FilledButton(
                  onPressed: _busy || !_verified || _blocked ? null : _buy,
                  child: const Text('Initiate purchase'),
                ),
              TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BoostListScreen(
                      repository: widget.repository,
                      view: BoostView.history,
                    ),
                  ),
                ),
                child: const Text('Purchase history'),
              ),
              if (_busy) const LoadingView(),
            ],
          ),
        ),
      ),
    ),
  );
}

class BoostDetail extends StatefulWidget {
  const BoostDetail({
    super.key,
    required this.repository,
    required this.id,
    this.invoice = false,
    this.checkoutOpener,
  });
  final BoostRepository repository;
  final int id;
  final bool invoice;
  final Future<void> Function(String)? checkoutOpener;
  @override
  State<BoostDetail> createState() => _BoostDetailState();
}

class _BoostDetailState extends State<BoostDetail> with WidgetsBindingObserver {
  BoostData? _data, _handoff;
  bool _busy = false, _choosingPath = false;
  ApiException? _error;
  String? _notice;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        mounted &&
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        !_busy) {
      unawaited(_load());
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      widget.repository.checkAccess();
      await action();
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _handoff = null;
          if ([
            ApiErrorKind.unauthorized,
            ApiErrorKind.forbidden,
            ApiErrorKind.notFound,
          ].contains(error.kind)) {
            _data = null;
          }
        });
      }
    } on FormatException catch (error) {
      if (mounted) {
        setState(
          () => _error = ApiException(
            kind: ApiErrorKind.invalidResponse,
            message: error.message,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run(() async {
    final data = widget.invoice
        ? await widget.repository.invoice(widget.id)
        : await widget.repository.detail(widget.id);
    if (mounted) {
      setState(() {
        _data = data;
        _handoff = null;
      });
    }
  });
  Future<void> _checkout() => _run(() async {
    final handoff = await widget.repository.checkout(widget.id);
    if (mounted) setState(() => _handoff = handoff);
  });
  Future<void> _open() => _run(() async {
    final handoff = _handoff;
    if (handoff == null) return;
    await (widget.checkoutOpener ?? openCheckout)(
      handoff.text('sandboxDemoUrl'),
    );
    widget.repository.checkAccess();
    if (mounted) {
      setState(
        () => _notice = 'Sandbox URL handed to the platform. This is not proof of payment. Refresh backend status after returning. If no browser opened, copy the link.',
      );
    }
  });
  Future<void> _download() async {
    if (_busy || _choosingPath) return;
    String? path;
    if (invoiceNeedsPath) {
      _choosingPath = true;
      try {
        path = await showDialog<String>(
          context: context,
          builder: (_) => _InvoicePathDialog(repository: widget.repository),
        );
      } finally {
        _choosingPath = false;
      }
      if (!mounted || path == null || path.trim().isEmpty) return;
    }
    await _run(() async {
      final bytes = await widget.repository.invoicePdf(widget.id);
      widget.repository.checkAccess();
      final result = await saveInvoice(
        bytes,
        'boost-invoice-${widget.id}.pdf',
        path: path,
        accessGuard: widget.repository.checkAccess,
      );
      widget.repository.checkAccess();
      if (mounted) setState(() => _notice = result);
    });
  }

  @override
  Widget build(BuildContext context) => BoostAccess(
    repository: widget.repository,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.invoice ? 'Invoice' : 'Boost purchase'} #${widget.id}',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh backend status',
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
              if (_data case final data?) ...[
                BoostFields(data),
                if (!widget.invoice) ...[
                  const Text(
                    'Only backend status confirms payment or boost activity. No local checkout result changes these statuses.',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (data.pending)
                        OutlinedButton(
                          onPressed: _busy ? null : _checkout,
                          child: const Text('Get sandbox checkout'),
                        ),
                      OutlinedButton(
                        onPressed: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BoostListScreen(
                              repository: widget.repository,
                              view: BoostView.activities,
                              boostId: widget.id,
                            ),
                          ),
                        ),
                        child: const Text('Activity history'),
                      ),
                      OutlinedButton(
                        onPressed: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BoostAnalyticsScreen(
                              repository: widget.repository,
                              boostId: widget.id,
                            ),
                          ),
                        ),
                        child: const Text('Analytics'),
                      ),
                      if (data.fields['invoiceId'] case final int id)
                        OutlinedButton(
                          onPressed: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BoostDetail(
                                repository: widget.repository,
                                id: id,
                                invoice: true,
                              ),
                            ),
                          ),
                          child: const Text('View invoice'),
                        ),
                    ],
                  ),
                ] else if (data.fields['pdfUrl'] case final String url) ...[
                  if (url.trim().isNotEmpty)
                    OutlinedButton(
                      onPressed: _busy ? null : _download,
                      child: const Text('Download invoice PDF'),
                    ),
                ] else
                  const Text(
                    'Invoice PDF is not available yet. Refresh to check again.',
                  ),
              ],
              if (_handoff case final handoff?) ...[
                const Divider(),
                const Text('Sandbox demonstration only'),
                BoostFields(handoff),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: _busy ? null : _open,
                      child: const Text('Open sandbox demo'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              widget.repository.checkAccess();
                              await Clipboard.setData(
                                ClipboardData(
                                  text: handoff.text('sandboxDemoUrl'),
                                ),
                              );
                              if (mounted) {
                                setState(() => _notice = 'Sandbox URL copied.');
                              }
                            }),
                      child: const Text('Copy sandbox URL'),
                    ),
                  ],
                ),
              ],
              if (_notice != null) Text(_notice!),
              if (_error != null)
                ErrorView(error: _error!, onRetry: _busy ? null : _load),
              if (_busy) const LoadingView(),
            ],
          ),
        ),
      ),
    ),
  );
}

class BoostAnalyticsScreen extends StatefulWidget {
  const BoostAnalyticsScreen({
    super.key,
    required this.repository,
    this.boostId,
  });
  final BoostRepository repository;
  final int? boostId;
  @override
  State<BoostAnalyticsScreen> createState() => _BoostAnalyticsScreenState();
}

class _BoostAnalyticsScreenState extends State<BoostAnalyticsScreen> {
  final _from = TextEditingController(), _to = TextEditingController();
  BoostData? _summary;
  final _rows = <BoostData>[];
  ApiPage<BoostData>? _page;
  ApiException? _error;
  bool _busy = false;
  String _loadedFrom = '', _loadedTo = '';
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final from = more ? _loadedFrom : _from.text,
          to = more ? _loadedTo : _to.text;
      final summary = more
          ? _summary
          : await widget.repository.summary(
              boostId: widget.boostId,
              from: from,
              to: to,
            );
      ApiPage<BoostData>? page;
      final rows = widget.boostId == null
          ? (page = await widget.repository.daily(
              page: more ? (_page?.page ?? -1) + 1 : 0,
              from: from,
              to: to,
            )).content
          : await widget.repository.boostDaily(
              widget.boostId!,
              from: from,
              to: to,
            );
      if (mounted) {
        setState(() {
          _summary = summary;
          if (!more) _rows.clear();
          _rows.addAll(rows);
          _page = page;
          _loadedFrom = from;
          _loadedTo = to;
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
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
  Widget build(BuildContext context) => BoostAccess(
    repository: widget.repository,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.boostId == null
              ? 'All boost analytics'
              : 'Boost #${widget.boostId} analytics',
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Backend wall times, without timezone conversion. Leave a bound blank for the server default. Metrics are returned by the server: some summary counts are lifetime totals, while daily results use the requested window. Account daily rows may contain separate records for the same date; they are not merged.',
              ),
              TextField(
                controller: _from,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'From (optional)',
                  hintText: 'YYYY-MM-DDTHH:mm:ss',
                ),
              ),
              TextField(
                controller: _to,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'To (optional)',
                  hintText: 'YYYY-MM-DDTHH:mm:ss',
                ),
              ),
              FilledButton(
                onPressed: _busy ? null : () => _load(),
                child: const Text('Load analytics'),
              ),
              if (_summary case final summary?) ...[
                const Text('Summary'),
                BoostFields(summary),
              ],
              const Text('Daily metrics'),
              for (final row in _rows)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: BoostFields(row),
                  ),
                ),
              if (_rows.isEmpty && !_busy && _error == null)
                const Text('No daily analytics returned.'),
              if (_error != null)
                ErrorView(error: _error!, onRetry: () => _load()),
              if (_busy) const LoadingView(),
              if (_page?.hasNext == true && !_busy)
                TextButton(
                  onPressed: () => _load(more: true),
                  child: const Text('Load more daily metrics'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _InvoicePathDialog extends StatefulWidget {
  const _InvoicePathDialog({required this.repository});
  final BoostRepository repository;
  @override
  State<_InvoicePathDialog> createState() => _InvoicePathDialogState();
}

class _InvoicePathDialogState extends State<_InvoicePathDialog> {
  final _path = TextEditingController();
  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BoostAccess(
    repository: widget.repository,
    child: AlertDialog(
      title: const Text('Save invoice PDF'),
      content: TextField(
        controller: _path,
        decoration: const InputDecoration(
          labelText: 'New absolute file path',
          hintText: '/absolute/path/invoice.pdf',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _path.text),
          child: const Text('Download and save'),
        ),
      ],
    ),
  );
}
