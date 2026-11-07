import '../../support/data/support_repository.dart';
import '../../support/presentation/support_screens.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../messaging/data/chat_repository.dart' show uncertainChatOutcome;
import '../data/settings_repository.dart';
import '../domain/security_models.dart';

class SettingsEntry extends StatelessWidget {
  const SettingsEntry({super.key, required this.repository});
  final SettingsRepository repository;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Settings and security',
    icon: const Icon(Icons.settings_outlined),
    onPressed: () => Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => SettingsHome(repository: repository)),
    ),
  );
}

class SettingsAccess extends StatelessWidget {
  const SettingsAccess({
    super.key,
    required this.repository,
    required this.child,
  });
  final SettingsRepository repository;
  final Widget child;
  @override
  Widget build(BuildContext context) => StreamBuilder<Object?>(
    stream: repository.accessChanges,
    builder: (context, _) {
      try {
        repository.checkAccess();
      } on ApiException catch (error) {
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ErrorView(error: error),
        );
      }
      return child;
    },
  );
}

class SettingsHome extends StatelessWidget {
  const SettingsHome({super.key, required this.repository});
  final SettingsRepository repository;
  @override
  Widget build(BuildContext context) => SettingsAccess(
    repository: repository,
    child: Scaffold(
      appBar: AppBar(title: const Text('Settings and security')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Account role: ${repository.currentUser()?.role.name ?? 'Unavailable'}',
          ),
          ListTile(
            title: const Text('Support tickets'),
            trailing: const Icon(Icons.help_outline),
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => SupportTickets(
                  repository: SupportRepository(
                    repository.api,
                    ownerId: repository.ownerId,
                    currentUser: repository.currentUser,
                    accessChanges: repository.accessChanges,
                    sessionGeneration: repository.sessionGeneration,
                    parentAccess: repository.checkAccess,
                  ),
                ),
              ),
            ),
          ),
          for (final section in SettingsSection.values)
            ListTile(
              title: Text(section.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      SettingsPage(repository: repository, section: section),
                ),
              ),
            ),
          ListTile(
            title: const Text('Change password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => SecurityFlow(
                  repository: repository,
                  mode: SecurityMode.password,
                ),
              ),
            ),
          ),
          ListTile(
            title: const Text('Request account deletion'),
            trailing: const Icon(Icons.delete_outline),
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => SecurityFlow(
                  repository: repository,
                  mode: SecurityMode.deletion,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

enum SettingsSection {
  privacy('Message and comment privacy'),
  notifications('Notification preferences'),
  twoFactor('Two-factor authentication'),
  sessions('Active sessions'),
  history('Security history and account activity');

  const SettingsSection(this.label);
  final String label;
}

Future<bool> confirmSecurity(
  BuildContext context,
  SettingsRepository repo,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => SettingsAccess(
        repository: repo,
        child: AlertDialog(
          title: const Text('Confirm account action'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    ) ??
    false;

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.repository,
    required this.section,
  });
  final SettingsRepository repository;
  final SettingsSection section;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false, _uncertain = false, _confirming = false;
  ApiException? _error;
  String? _notice;
  String? _messagePrivacy, _commentPrivacy;
  Map<String, bool>? _notifications;
  SecurityState? _security;
  SecurityHistory? _history;
  List<SecuritySession>? _sessions;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
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
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run(() async {
    final repo = widget.repository;
    switch (widget.section) {
      case SettingsSection.privacy:
        final values = await Future.wait([
          repo.privacy(true),
          repo.privacy(false),
        ]);
        if (mounted) {
          setState(() {
            _messagePrivacy = values[0]['whoCanMessageMe'] as String;
            _commentPrivacy = values[1]['whoCanCommentOnMyPosts'] as String;
          });
        }
      case SettingsSection.notifications:
        final values = await repo.notifications();
        if (mounted) setState(() => _notifications = values);
      case SettingsSection.twoFactor:
        final value = await repo.security();
        if (mounted) setState(() => _security = value);
      case SettingsSection.sessions:
        final values = await repo.sessions();
        if (mounted) setState(() => _sessions = values);
      case SettingsSection.history:
        final value = await repo.history();
        if (mounted) setState(() => _history = value);
    }
    if (mounted) setState(() => _uncertain = false);
  });
  Future<void> _savePrivacy(bool message, String value) => _run(() async {
    try {
      final result = await widget.repository.privacy(message, value: value);
      if (mounted) {
        setState(() {
          if (message) {
            _messagePrivacy = result['whoCanMessageMe'] as String;
          } else {
            _commentPrivacy = result['whoCanCommentOnMyPosts'] as String;
          }
          _notice = 'Privacy saved by the backend.';
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _uncertain = uncertainChatOutcome(error));
      rethrow;
    }
  });
  Future<void> _saveNotifications() => _run(() async {
    try {
      final result = await widget.repository.notifications(
        values: _notifications,
      );
      if (mounted) {
        setState(() {
          _notifications = result;
          _notice = 'Notification preferences saved by the backend.';
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _uncertain = uncertainChatOutcome(error));
      rethrow;
    }
  });
  Future<void> _flow(SecurityMode mode) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SecurityFlow(repository: widget.repository, mode: mode),
      ),
    );
    if (mounted) unawaited(_load());
  }

  Future<void> _revoke(int? id) async {
    if (_busy || _uncertain || _confirming) return;
    _confirming = true;
    bool confirmed;
    try {
      confirmed = await confirmSecurity(
        context,
        widget.repository,
        id == null
            ? 'Revoke all refresh sessions, including this device, and sign out?'
            : 'Revoke session #$id? The server does not identify the current device. This device will renew its refresh session to check whether it may remain signed in.',
      );
    } finally {
      _confirming = false;
    }
    if (!mounted || !confirmed || _busy || _uncertain) return;
    await _run(() async {
      try {
        final message = await widget.repository.revoke(id: id);
        if (!mounted) return;
        if (id == null) {
          Navigator.popUntil(context, (r) => r.isFirst);
          return;
        }
        final sessions = await widget.repository.sessions();
        if (mounted) {
          setState(() {
            _sessions = sessions;
            _notice = message;
          });
        }
      } on ApiException catch (error) {
        if (mounted) setState(() => _uncertain = uncertainChatOutcome(error));
        rethrow;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _busy || _uncertain;
    return SettingsAccess(
      repository: widget.repository,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.section.label),
          actions: [
            IconButton(
              tooltip: 'Refresh settings',
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
                if (widget.section == SettingsSection.privacy) ...[
                  const Text(
                    'The backend enforces who can message you and comment on your posts. FOLLOWERS_ONLY uses the backend follower relationships and role restrictions.',
                  ),
                  for (final message in [true, false])
                    if ((message ? _messagePrivacy : _commentPrivacy)
                        case final value?)
                      DropdownButton<String>(
                        key: ValueKey('${message}_$value'),
                        value: value,
                        hint: Text(
                          message
                              ? 'Who can message me'
                              : 'Who can comment on my posts',
                        ),
                        items: [
                          for (final option in privacyValues)
                            DropdownMenuItem(
                              value: option,
                              child: Text(
                                '${message ? 'Messages' : 'Comments'}: $option',
                              ),
                            ),
                        ],
                        onChanged: disabled
                            ? null
                            : (selected) {
                                if (selected != null) {
                                  unawaited(_savePrivacy(message, selected));
                                }
                              },
                      ),
                ],
                if (widget.section == SettingsSection.notifications &&
                    _notifications != null) ...[
                  const Text(
                    'Draft preferences are applied only after Save succeeds.',
                  ),
                  for (final key in notificationKeys)
                    SwitchListTile(
                      title: Text(key),
                      value: _notifications![key]!,
                      onChanged: disabled
                          ? null
                          : (value) => setState(
                              () => _notifications = {
                                ..._notifications!,
                                key: value,
                              },
                            ),
                    ),
                  FilledButton(
                    onPressed: disabled ? null : _saveNotifications,
                    child: const Text('Save notification preferences'),
                  ),
                ],
                if (widget.section == SettingsSection.twoFactor)
                  if (_security case final security?) ...[
                    Text(
                      'Backend 2FA: ${security.enabled == null
                          ? 'Unknown'
                          : security.enabled!
                          ? 'Enabled'
                          : 'Disabled'}',
                    ),
                    Text('Method: ${security.method ?? 'Not provided'}'),
                    const Text(
                      'Enable only after verifying a six-digit code. Disable the current method before switching. The backend provides no recovery-code or dedicated 2FA recovery API.',
                    ),
                    if (security.enabled != true) ...[
                      OutlinedButton(
                        onPressed: disabled
                            ? null
                            : () => _flow(SecurityMode.email),
                        child: const Text('Set up email 2FA'),
                      ),
                      OutlinedButton(
                        onPressed: disabled
                            ? null
                            : () => _flow(SecurityMode.totp),
                        child: const Text('Set up authenticator app'),
                      ),
                    ],
                    if (security.enabled == true)
                      OutlinedButton(
                        onPressed: disabled
                            ? null
                            : () => _flow(SecurityMode.disable),
                        child: const Text('Disable 2FA with password'),
                      ),
                  ],
                if (widget.section == SettingsSection.sessions &&
                    _sessions != null) ...[
                  const Text(
                    'These are active refresh sessions. Device names, IP addresses, and a current-device marker are not supplied. Revocation prevents renewal; an already issued access token may remain valid until expiry.',
                  ),
                  OutlinedButton(
                    onPressed: disabled ? null : () => _revoke(null),
                    child: const Text('Revoke all sessions and sign out'),
                  ),
                  if (_sessions!.isEmpty)
                    const Text('No active refresh sessions returned.'),
                  for (final session in _sessions!)
                    Card(
                      child: ListTile(
                        title: Text('Session #${session.id}'),
                        subtitle: Text(
                          'Created: ${session.createdAt}\nExpires: ${session.expiresAt}\nRemember me: ${session.rememberMe}',
                        ),
                        trailing: TextButton(
                          onPressed: disabled
                              ? null
                              : () => _revoke(session.id),
                          child: const Text('Revoke'),
                        ),
                      ),
                    ),
                ],
                if (widget.section == SettingsSection.history)
                  if (_history case final history?) ...[
                    Text(history.email),
                    if (history.accountCreatedAt != null)
                      Text('Account created: ${history.accountCreatedAt}'),
                    const Text(
                      'Backend activity timestamps are shown without timezone conversion.',
                    ),
                    if (history.events.isEmpty)
                      const Text('No security events returned.'),
                    for (final event in history.events)
                      Card(
                        child: ListTile(
                          title: Text(event['type'] as String),
                          subtitle: Text(
                            '${event['description'] ?? ''}\n${event['time']}',
                          ),
                        ),
                      ),
                  ],
                if (_notice != null) Text(_notice!),
                if (_error != null) ErrorView(error: _error!, onRetry: _load),
                if (_uncertain)
                  const Text(
                    'The operation outcome is unknown. Refresh authoritative state before another change.',
                  ),
                if (_busy) const LoadingView(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum SecurityMode { password, email, totp, disable, deletion }

class SecurityFlow extends StatefulWidget {
  const SecurityFlow({super.key, required this.repository, required this.mode});
  final SettingsRepository repository;
  final SecurityMode mode;
  @override
  State<SecurityFlow> createState() => _SecurityFlowState();
}

class _SecurityFlowState extends State<SecurityFlow>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController(),
      _next = TextEditingController(),
      _confirm = TextEditingController(),
      _otp = TextEditingController();
  int _exposureEpoch = 0;
  int _step = 0;
  bool _busy = false,
      _uncertain = false,
      _deliberate = false,
      _confirming = false;
  ApiException? _error;
  String? _notice;
  TotpSetup? _setup;
  StreamSubscription<Object?>? _access;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _access = widget.repository.accessChanges?.listen((_) {
      try {
        widget.repository.checkAccess();
      } on ApiException {
        _clear();
        if (mounted) setState(() => _setup = null);
      }
    });
  }

  void _clear() {
    for (final c in [_password, _next, _confirm, _otp]) {
      c.clear();
    }
    _setup = null;
    _exposureEpoch++;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      if (mounted) {
        setState(() {
          _clear();
          if (widget.mode == SecurityMode.totp && _step == 1) {
            _step = 0;
            _notice = 'Enrollment details cleared while backgrounded. Generate a new setup to continue.';
          }
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_access?.cancel() ?? Future<void>.value());
    for (final c in [_password, _next, _confirm, _otp]) {
      c.dispose();
    }
    _setup = null;
    super.dispose();
  }

  String get _title => switch (widget.mode) {
    SecurityMode.password => 'Change password',
    SecurityMode.email => 'Email 2FA enrollment',
    SecurityMode.totp => 'Authenticator enrollment',
    SecurityMode.disable => 'Disable two-factor authentication',
    SecurityMode.deletion => 'Account deletion',
  };
  Future<void> _submit() async {
    if (_busy || _uncertain || _confirming || !_form.currentState!.validate()) {
      return;
    }
    final destructive =
        widget.mode == SecurityMode.disable ||
        (widget.mode == SecurityMode.deletion && _step == 1);
    if (widget.mode == SecurityMode.deletion && !_deliberate) return;
    final exposureBeforeConfirmation = _exposureEpoch;
    if (destructive) {
      _confirming = true;
      bool confirmed;
      try {
        confirmed = await confirmSecurity(
          context,
          widget.repository,
          widget.mode == SecurityMode.deletion
              ? 'Confirm scheduling account deletion with this OTP? All refresh sessions will be revoked. The backend response supplies the actual grace period and restore instructions.'
              : 'Disable two-factor authentication after password verification?',
        );
      } finally {
        _confirming = false;
      }
      if (!confirmed) return;
    }
    if (!mounted ||
        _busy ||
        _uncertain ||
        exposureBeforeConfirmation != _exposureEpoch) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final repo = widget.repository;
      final exposure = _exposureEpoch;
      String? message;
      bool terminal = false;
      switch (widget.mode) {
        case SecurityMode.password:
          if (_step == 0) {
            message = await repo.resetInit(
              _password.text,
              _next.text,
              _confirm.text,
            );
            if (!mounted) return;
            _clear();
            _step = 1;
          } else {
            await repo.resetConfirm(_otp.text);
            if (mounted) Navigator.popUntil(context, (route) => route.isFirst);
            return;
          }
        case SecurityMode.email:
          if (_step == 0) {
            message = await repo.emailStart(_password.text);
            if (!mounted) return;
            _clear();
            _step = 1;
          } else {
            message = await repo.emailVerify(_otp.text);
            terminal = true;
          }
        case SecurityMode.totp:
          if (_step == 0) {
            final setup = await repo.totpSetup();
            if (!mounted) return;
            if (exposure != _exposureEpoch) return;
            _setup = setup;
            _step = 1;
            message = 'Enter the secret manually into your authenticator app, then verify its code. No external QR service is used.';
          } else {
            message = await repo.totpEnable(_otp.text);
            terminal = true;
          }
        case SecurityMode.disable:
          message = await repo.disable(_password.text);
          terminal = true;
        case SecurityMode.deletion:
          if (_step == 0) {
            message = await repo.deleteRequest(_password.text);
            if (!mounted) return;
            _clear();
            _step = 1;
          } else {
            message = await repo.deleteConfirm(_otp.text);
            if (!mounted) return;
            _clear();
            if (mounted) {
              Navigator.pushAndRemoveUntil<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => DeletionResult(message: message!),
                ),
                (route) => route.isFirst,
              );
            }
            return;
          }
      }
      if (!mounted) return;
      if (terminal) {
        _clear();
        _step = 2;
      }
      if (mounted) setState(() => _notice = message);
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

  Widget _field(
    TextEditingController controller,
    String label, {
    bool code = false,
    bool newPassword = false,
    bool confirm = false,
  }) => TextFormField(
    controller: controller,
    enabled: !_busy && !_uncertain,
    obscureText: !code,
    autocorrect: false,
    enableSuggestions: false,
    keyboardType: code ? TextInputType.number : null,
    maxLength: code ? 6 : null,
    decoration: InputDecoration(labelText: label),
    validator: (value) {
      if (code) {
        return RegExp(r'^\d{6}$').hasMatch(value ?? '')
            ? null
            : 'Enter a six-digit code.';
      }
      if (value == null || value.trim().isEmpty) return 'Required';
      if (newPassword &&
          !RegExp(r'^(?=.*[A-Za-z])(?=.*\d).{8,64}$').hasMatch(value)) {
        return 'Use 8–64 characters, including a letter and number.';
      }
      if (confirm && value != _next.text) return 'Passwords must match.';
      return null;
    },
  );
  @override
  Widget build(BuildContext context) => SettingsAccess(
    repository: widget.repository,
    child: Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.mode == SecurityMode.deletion) ...[
                  const Text(
                    'Deletion is scheduled, not immediate permanent erasure. The backend returns the actual grace period and restoration instructions. Confirmation revokes all refresh sessions and signs out this device.',
                  ),
                  CheckboxListTile(
                    title: const Text(
                      'I understand and want to request account deletion',
                    ),
                    value: _deliberate,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _deliberate = v == true),
                  ),
                ],
                if (widget.mode == SecurityMode.password)
                  const Text(
                    'Current and new passwords are verified first; an email OTP completes the change. Confirmation revokes all refresh sessions and signs you out.',
                  ),
                if (widget.mode == SecurityMode.totp)
                  const Text(
                    'Enrollment secrets are displayed only here, held in memory, and cleared on completion, backgrounding, account changes, or leaving. Manual entry is supported; no QR library is installed.',
                  ),
                if (_step == 0 && widget.mode != SecurityMode.totp)
                  _field(_password, 'Current password'),
                if (_step == 0 && widget.mode == SecurityMode.password) ...[
                  _field(_next, 'New password', newPassword: true),
                  _field(_confirm, 'Confirm new password', confirm: true),
                ],
                if (_setup case final setup?) ...[
                  const Text('Authenticator enrollment secret — keep private'),
                  Text(setup.secret, key: const ValueKey('totp-secret')),
                  const Text('Backend enrollment URI'),
                  Text(setup.uri),
                ],
                if (_step == 1) _field(_otp, 'Six-digit code', code: true),
                if (_notice != null) Text(_notice!),
                if (_error != null) ErrorView(error: _error!),
                if (_uncertain)
                  const Text(
                    'The backend outcome is unknown. Return to settings and refresh status before attempting another security change.',
                  ),
                if (_step < 2)
                  FilledButton(
                    onPressed:
                        _busy ||
                            _uncertain ||
                            (widget.mode == SecurityMode.deletion &&
                                !_deliberate)
                        ? null
                        : _submit,
                    child: Text(
                      _step == 1
                          ? 'Verify and confirm'
                          : widget.mode == SecurityMode.totp
                          ? 'Generate authenticator setup'
                          : widget.mode == SecurityMode.disable
                          ? 'Disable 2FA'
                          : 'Request email code',
                    ),
                  ),
                if (_step == 1 && widget.mode == SecurityMode.email)
                  TextButton(
                    onPressed: _busy || _uncertain
                        ? null
                        : () => setState(() {
                            _clear();
                            _step = 0;
                            _notice = 'Enter your password again to request another setup code. Backend rate limits apply.';
                          }),
                    child: const Text('Resend setup code'),
                  ),
                if (_step == 2)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Return and refresh security state'),
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

class DeletionResult extends StatelessWidget {
  const DeletionResult({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Deletion request confirmed')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            const Text(
              'This device is signed out. Follow the backend instructions above for the deletion schedule or restoration.',
            ),
            TextButton(
              onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
              child: const Text('Return to sign in'),
            ),
          ],
        ),
      ),
    ),
  );
}
