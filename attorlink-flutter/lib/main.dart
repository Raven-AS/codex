import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/attorlink_app.dart';
import 'core/config/api_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final config = ApiConfig.fromEnvironment(
      android: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
      productionBuild: !kDebugMode,
    );
    runApp(AttorlinkApp(config: config));
  } on ArgumentError {
    runApp(const _ConfigurationError());
  } on FormatException {
    runApp(const _ConfigurationError());
  }
}

class _ConfigurationError extends StatelessWidget {
  const _ConfigurationError();
  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'API configuration is invalid. Set ATTORLINK_API_URL to the complete HTTPS API root for production. Debug builds may use an explicit local emulator, USB, or LAN HTTP address.',
            ),
          ),
        ),
      ),
    ),
  );
}
