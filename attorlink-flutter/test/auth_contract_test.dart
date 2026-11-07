import 'package:flutter_test/flutter_test.dart';

import 'support/auth_contracts.dart';

void main() {
  for (final entry in authContractCases.entries) {
    test(entry.key, entry.value);
  }
}
