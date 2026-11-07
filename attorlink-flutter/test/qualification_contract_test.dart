import 'package:flutter_test/flutter_test.dart';

import 'support/qualification_contracts.dart';

void main() {
  for (final entry in qualificationContractCases.entries) {
    test(entry.key, entry.value);
  }
}
