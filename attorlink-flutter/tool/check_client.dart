// SDK-only checks; no Flutter runner or dependency resolution.
// ignore_for_file: avoid_print
import '../test/support/client_contracts.dart';

Future<void> main() async {
  for (final entry in clientContractCases.entries) {
    await entry.value().timeout(const Duration(seconds: 5));
    print('PASS ${entry.key}');
  }
  print('${clientContractCases.length} client contract checks passed.');
}
