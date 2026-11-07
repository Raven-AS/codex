// Compile-only entry point to validate SDK interop and conditional web imports.
import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_client.dart';

Future<void> main() async {
  final api = ApiClient(config: ApiConfig.fromEnvironment());
  try {
    await api.request('GET', 'practice-areas', decode: (value) => value);
  } finally {
    api.close();
  }
}
