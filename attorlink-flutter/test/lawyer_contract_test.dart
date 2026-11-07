import 'package:flutter_test/flutter_test.dart';

import 'support/lawyer_contracts.dart';

void main() {
  for (final entry in lawyerContractCases.entries) {
    test(entry.key, entry.value);
  }
}
