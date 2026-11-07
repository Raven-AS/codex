import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/api_exception.dart';
import '../domain/session_controller.dart';

enum AuthStep {
  login,
  signup,
  signupOtp,
  challenge,
  forgot,
  recoveryOtp,
  newPassword,
}

class AuthForm extends StatefulWidget {
  const AuthForm({
    super.key,
    required this.session,
    this.challenge = false,
    this.message,
  });
  final SessionController session;
  final bool challenge;
  final String? message;

  @override
  State<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<AuthForm> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _code = TextEditingController();
  late AuthStep _step = widget.challenge ? AuthStep.challenge : AuthStep.login;
  late String? _message = widget.message;
  ApiException? _error;
  String? _resetToken;
  bool _busy = false;
  bool _obscure = true;
  bool _remember = false;

  @override
  void dispose() {
    for (final controller in [_email, _phone, _password, _confirm, _code]) {
      controller.dispose();
    }
    _resetToken = null;
    super.dispose();
  }

  void _move(AuthStep next, {String? message}) {
    setState(() {
      _step = next;
      _password.clear();
      _confirm.clear();
      _code.clear();
      _error = null;
      _message = message;
      if (next != AuthStep.newPassword) _resetToken = null;
    });
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool validate = true,
  }) async {
    if (_busy || (validate && !_form.currentState!.validate())) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await action();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() => _run(() async {
    final repository = widget.session.repository;
    switch (_step) {
      case AuthStep.login:
        await widget.session.login(
          _email.text.trim(),
          _password.text,
          rememberMe: _remember,
        );
        if (mounted) _password.clear();
      case AuthStep.signup:
        final message = await repository.signup(
          _email.text,
          _password.text,
          _confirm.text,
          phone: _phone.text.trim(),
        );
        if (mounted) _move(AuthStep.signupOtp, message: message);
      case AuthStep.signupOtp:
        final message = await repository.verifySignup(_email.text, _code.text);
        if (mounted) _move(AuthStep.login, message: message);
      case AuthStep.challenge:
        await widget.session.verifyTwoFactor(_code.text);
      case AuthStep.forgot:
        final message = await repository.forgotPassword(_email.text);
        if (mounted) _move(AuthStep.recoveryOtp, message: message);
      case AuthStep.recoveryOtp:
        final token = await repository.verifyRecovery(_email.text, _code.text);
        if (mounted) {
          _move(AuthStep.newPassword);
          _resetToken = token;
        }
      case AuthStep.newPassword:
        final token = _resetToken;
        if (token == null) {
          _move(AuthStep.forgot);
          return;
        }
        try {
          final message = await repository.completeRecovery(
            _email.text,
            token,
            _password.text,
            _confirm.text,
          );
          if (mounted) _move(AuthStep.login, message: message);
        } on ApiException {
          // Reset tokens are consumed server-side; request a fresh one on failure.
          if (mounted) {
            _move(
              AuthStep.forgot,
              message: 'Request a new recovery code to try again.',
            );
          }
          rethrow;
        }
    }
  });

  Future<void> _resend() => _run(() async {
    final repository = widget.session.repository;
    final message = _step == AuthStep.signupOtp
        ? await repository.resendSignup(_email.text)
        : await repository.forgotPassword(_email.text);
    if (mounted) {
      setState(() {
        _message = message;
        _code.clear();
      });
    }
  }, validate: false);

  String? _emailValidator(String? value) =>
      value == null ||
          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())
      ? 'Enter a valid email address.'
      : null;

  String? _passwordValidator(String? value) {
    if (value == null || value.isEmpty) return 'Enter your password.';
    if (_step == AuthStep.login) return null;
    if (value.length < 8 ||
        value.length > 64 ||
        !RegExp('[A-Za-z]').hasMatch(value) ||
        !RegExp('[0-9]').hasMatch(value)) {
      return 'Use 8–64 characters with a letter and a number.';
    }
    return null;
  }

  InputDecoration _decoration(String label, String field) => InputDecoration(
    labelText: label,
    errorText: _error?.fieldErrors[field],
    errorMaxLines: 3,
  );

  @override
  Widget build(BuildContext context) {
    final title = switch (_step) {
      AuthStep.login => 'Sign in to Attorlink',
      AuthStep.signup => 'Create your account',
      AuthStep.signupOtp => 'Verify your email',
      AuthStep.challenge => 'Two-factor verification',
      AuthStep.forgot => 'Recover your password',
      AuthStep.recoveryOtp => 'Verify recovery code',
      AuthStep.newPassword => 'Choose a new password',
    };
    final hasPassword = [
      AuthStep.login,
      AuthStep.signup,
      AuthStep.newPassword,
    ].contains(_step);
    final hasEmail = [
      AuthStep.login,
      AuthStep.signup,
      AuthStep.forgot,
      AuthStep.signupOtp,
    ].contains(_step);
    final hasOtp = [
      AuthStep.signupOtp,
      AuthStep.challenge,
      AuthStep.recoveryOtp,
    ].contains(_step);
    return Scaffold(
      appBar: AppBar(title: const Text('Attorlink')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: AutofillGroup(
              child: Form(
                key: _form,
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    if (_message != null) ...[
                      Semantics(liveRegion: true, child: Text(_message!)),
                      const SizedBox(height: 16),
                    ],
                    if (_error != null) ...[
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!.message,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (hasEmail) ...[
                      TextFormField(
                        key: const ValueKey('email'),
                        controller: _email,
                        enabled: !_busy,
                        decoration: _decoration('Email', 'email'),
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        validator: _emailValidator,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_step == AuthStep.signup) ...[
                      TextFormField(
                        controller: _phone,
                        enabled: !_busy,
                        decoration: _decoration('Phone (optional)', 'phone'),
                        keyboardType: TextInputType.phone,
                        validator: (v) =>
                            v == null ||
                                v.trim().isEmpty ||
                                RegExp(r'^[0-9+\-]{6,20}$').hasMatch(v.trim())
                            ? null
                            : 'Enter a valid phone number.',
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (hasPassword) ...[
                      TextFormField(
                        key: ValueKey('password-${_step.name}'),
                        controller: _password,
                        enabled: !_busy,
                        obscureText: _obscure,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: [
                          _step == AuthStep.login
                              ? AutofillHints.password
                              : AutofillHints.newPassword,
                        ],
                        decoration: _decoration('Password', 'password')
                            .copyWith(
                              suffixIcon: IconButton(
                                tooltip: _obscure
                                    ? 'Show password'
                                    : 'Hide password',
                                onPressed: _busy
                                    ? null
                                    : () =>
                                          setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                        validator: _passwordValidator,
                      ),
                      const SizedBox(height: 16),
                      if (_step != AuthStep.login) ...[
                        TextFormField(
                          controller: _confirm,
                          enabled: !_busy,
                          obscureText: _obscure,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: _decoration(
                            'Confirm password',
                            'confirmPassword',
                          ),
                          validator: (v) => v == _password.text
                              ? null
                              : 'Passwords must match.',
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                    if (hasOtp) ...[
                      Text(
                        _step == AuthStep.challenge
                            ? 'Enter the code from your email or authenticator. If verification fails, sign in again to request a new challenge.'
                            : 'Enter the six-digit code sent to ${_email.text.trim()}.',
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const ValueKey('otp'),
                        controller: _code,
                        enabled: !_busy,
                        decoration: _decoration(
                          'Verification code',
                          _step == AuthStep.challenge ? 'code' : 'otp',
                        ),
                        keyboardType: TextInputType.number,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        validator: (v) =>
                            v != null && RegExp(r'^\d{6}$').hasMatch(v)
                            ? null
                            : 'Enter the six-digit code.',
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_step == AuthStep.login) ...[
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _remember,
                        title: const Text('Use a longer server session'),
                        subtitle: Text(
                          widget.session.hasSecurePersistence
                              ? 'Uses Android-protected storage between app launches.'
                              : 'Applies only while this app stays open.',
                        ),
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _remember = v ?? false),
                      ),
                      Text(
                        widget.session.hasSecurePersistence
                            ? 'Sign-in is encrypted using Android Keystore. Sign out to remove it from this device.'
                            : 'Sign-in is kept in memory only. Reopening the app requires sign-in.',
                      ),
                      const SizedBox(height: 16),
                    ],
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                semanticsLabel: 'Please wait',
                              ),
                            )
                          : Text(switch (_step) {
                              AuthStep.login => 'Sign in',
                              AuthStep.signup => 'Create account',
                              AuthStep.forgot => 'Send recovery code',
                              AuthStep.newPassword => 'Save new password',
                              _ => 'Verify code',
                            }),
                    ),
                    if (_step == AuthStep.login) ...[
                      TextButton(
                        onPressed: _busy ? null : () => _move(AuthStep.signup),
                        child: const Text('Create an account'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : () => _move(AuthStep.forgot),
                        child: const Text('Forgot password?'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _move(AuthStep.signupOtp),
                        child: const Text('Verify an existing signup'),
                      ),
                    ] else ...[
                      if (_step == AuthStep.signupOtp ||
                          _step == AuthStep.recoveryOtp)
                        TextButton(
                          onPressed: _busy ? null : _resend,
                          child: const Text('Resend code'),
                        ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                if (_step == AuthStep.challenge) {
                                  await widget.session.cancelChallenge();
                                } else {
                                  _move(AuthStep.login);
                                }
                              },
                        child: const Text('Back to sign in'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
