// SDK-only runner; no dependency resolution or Flutter runner invocation.
// ignore_for_file: avoid_print
import '../test/support/qualification_contracts.dart';

Future<void> main() async {
  for (final entry in qualificationContractCases.entries) {
    await entry.value().timeout(const Duration(seconds: 5));
    print('PASS ${entry.key}');
  }
  print(
    '${qualificationContractCases.length} qualification contract checks passed.',
  );
}
