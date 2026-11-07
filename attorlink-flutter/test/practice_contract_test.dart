import 'package:flutter_test/flutter_test.dart';

import 'support/practice_contracts.dart';

void main() {
  for (final entry in practiceContractCases.entries) {
    test(entry.key, entry.value);
  }
}
