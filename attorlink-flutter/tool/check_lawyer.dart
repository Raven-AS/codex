// Direct SDK runner; no pub operation or Flutter cache writes.
// ignore_for_file: avoid_print
import '../test/support/lawyer_contracts.dart';

Future<void> main() async {
  for (final entry in lawyerContractCases.entries) {
    await entry.value().timeout(const Duration(seconds: 5));
    print('PASS ${entry.key}');
  }
  print('${lawyerContractCases.length} lawyer contract checks passed.');
}
