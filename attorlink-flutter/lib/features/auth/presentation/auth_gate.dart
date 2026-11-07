import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/loading_view.dart';
import '../domain/auth_models.dart';
import '../domain/session_controller.dart';
import 'auth_form.dart';
import '../../client/presentation/client_workspace.dart';
import '../../lawyer/presentation/lawyer_workspace.dart';

/// Every root route is wrapped in this guard, including unknown/deep-link routes.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.session});
  final SessionController session;

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: session.changes,
    initialData: session.state,
    builder: (context, snapshot) {
      final state = snapshot.data ?? session.state;
      return switch (state.status) {
        SessionStatus.restoring => Scaffold(
          body: LoadingView(message: state.message ?? 'Checking your session…'),
        ),
        SessionStatus.signedOut => AuthForm(
          key: const ValueKey('login'),
          session: session,
          message: state.message,
        ),
        SessionStatus.challenge => AuthForm(
          key: const ValueKey('challenge'),
          session: session,
          challenge: true,
        ),
        SessionStatus.roleRequired => _RoleSelection(session: session),
        SessionStatus.authenticated when state.user!.role == UserRole.client =>
          ClientWorkspace(
            key: ValueKey(state.user!.id),
            session: session,
            user: state.user!,
          ),
        SessionStatus.authenticated => LawyerWorkspace(
          key: ValueKey(state.user!.id),
          session: session,
          user: state.user!,
        ),
        SessionStatus.restricted => _Restricted(
          session: session,
          user: state.user!,
        ),
        SessionStatus.unavailable => Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    state.message ?? 'Your session could not be checked.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: session.revalidate,
                    child: const Text('Try again'),
                  ),
                  TextButton(
                    onPressed: session.logout,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      };
    },
  );
}

class _RoleSelection extends StatefulWidget {
  const _RoleSelection({required this.session});
  final SessionController session;
  @override
  State<_RoleSelection> createState() => _RoleSelectionState();
}

class _RoleSelectionState extends State<_RoleSelection> {
  bool _busy = false;
  ApiException? _error;

  Future<void> _select(UserRole role) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.selectRole(role);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Choose your role')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'How will you use Attorlink?',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            const Text(
              'Your role can be selected once. Choose carefully before continuing.',
            ),
            const SizedBox(height: 24),
            if (_error != null) ...[
              Text(
                _error!.message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed: _busy ? null : widget.session.revalidate,
                child: const Text('Check current account status'),
              ),
            ],
            FilledButton.icon(
              onPressed: _busy ? null : () => _select(UserRole.client),
              icon: const Icon(Icons.person_outline),
              label: const Text('Continue as a client'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _select(UserRole.lawyer),
              icon: const Icon(Icons.balance),
              label: const Text('Continue as a lawyer'),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              ),
            TextButton(
              onPressed: _busy ? null : widget.session.logout,
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Restricted extends StatelessWidget {
  const _Restricted({required this.session, required this.user});
  final SessionController session;
  final AuthUser user;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              user.role == UserRole.admin
                  ? 'Administrator accounts use the admin panel.'
                  : 'This account is not active. Please contact support.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: session.logout,
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    ),
  );
}
