// SDK-only contract runner; no pub or Flutter runner operations.
// ignore_for_file: avoid_print
import '../test/support/practice_contracts.dart';

Future<void> main() async {
  for (final entry in practiceContractCases.entries) {
    await entry.value().timeout(const Duration(seconds: 5));
    print('PASS ${entry.key}');
  }
  print('${practiceContractCases.length} practice contract checks passed.');
}
