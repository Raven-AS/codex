// SDK-only runner: direct execution does not invoke pub or the Flutter runner.
// ignore_for_file: avoid_print
import '../test/support/auth_contracts.dart';

Future<void> main() async {
  for (final entry in authContractCases.entries) {
    await entry.value().timeout(const Duration(seconds: 5));
    print('PASS ${entry.key}');
  }
  print('${authContractCases.length} authentication contract checks passed.');
}
