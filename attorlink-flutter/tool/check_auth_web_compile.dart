// Compile-only check: this program is not executed or sent to a browser.
import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/features/auth/data/session_store.dart';
import 'package:attorlink_flutter/features/auth/domain/session_controller.dart';

Future<void> main() async {
  final session = SessionController(
    config: ApiConfig.fromEnvironment(),
    store: MemorySessionStore(),
  );
  try {
    await session.restore();
    await session.revalidate();
  } finally {
    session.dispose();
  }
}
