// Android platform probe only. Does not fabricate a login or API response.
import 'package:flutter/material.dart';
import 'package:attorlink_flutter/features/auth/data/android_session_store.dart';
import 'package:attorlink_flutter/features/auth/domain/auth_models.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _Probe());
}

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  String _result =
      'Checking Android secure storage (fixture data, no backend login)…';
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final store = AndroidSessionStore(
      'https://android-storage-probe.invalid/api/v1/',
    );
    try {
      final existing = await store.read();
      if (existing == null) {
        await store.write(
          const SessionTokens(
            accessToken: 'fixture-access-not-a-jwt',
            refreshToken: 'fixture-refresh-not-a-session',
          ),
        );
        final read = await store.read();
        if (read?.accessToken != 'fixture-access-not-a-jwt') {
          throw StateError('Readback failed');
        }
        if (mounted) {
          setState(
            () => _result = 'FIRST_PASS: Keystore encrypted write/read succeeded. Restart this process to verify persistence. This is not backend authentication.',
          );
        }
      } else {
        if (existing.accessToken != 'fixture-access-not-a-jwt' ||
            existing.refreshToken != 'fixture-refresh-not-a-session') {
          throw StateError('Unexpected fixture');
        }
        await store.clear();
        if (await store.read() != null) throw StateError('Clear failed');
        if (mounted) {
          setState(
            () => _result = 'SECOND_PASS: Android process-restart persistence and secure clearing succeeded. No backend login was simulated.',
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _result = 'FAILED: Android secure storage probe. No plaintext fallback was used.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(
        title: const Text('Android authentication platform probe'),
      ),
      body: Padding(padding: const EdgeInsets.all(24), child: Text(_result)),
    ),
  );
}
