import 'package:flutter_test/flutter_test.dart';

import 'support/client_contracts.dart';

void main() {
  for (final entry in clientContractCases.entries) {
    test(entry.key, entry.value);
  }
}
