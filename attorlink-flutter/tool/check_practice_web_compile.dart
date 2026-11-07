// Compile only; not executed against a browser or live backend.
import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_client.dart';
import 'package:attorlink_flutter/features/auth/domain/auth_models.dart';
import 'package:attorlink_flutter/features/lawyer/data/lawyer_repository.dart';
import 'package:attorlink_flutter/features/lawyer/practice/data/practice_repository.dart';
import 'package:attorlink_flutter/features/lawyer/practice/domain/practice_schema.dart';
import 'package:attorlink_flutter/features/lawyer/practice/domain/weekly_availability.dart';

Future<void> main() async {
  final api = ApiClient(
    config: ApiConfig.fromEnvironment(),
    accessTokenProvider: () => 'compile-only',
  );
  final lawyer = LawyerRepository(
    api,
    ownerId: 7,
    currentUser: () => const AuthUser(
      id: 7,
      email: 'compile-only@example.test',
      role: UserRole.lawyer,
      status: UserStatus.active,
    ),
  );
  final repository = PracticeRepository(lawyer);
  try {
    for (final resource in PracticeResource.values) {
      await repository.list(resource);
      await repository.references(resource);
    }
    final saved = await repository.availability();
    await repository.saveAvailability([
      for (final slot in saved)
        if (slot.available)
          AvailabilityRange(
            day: slot.range.day,
            start: WorkingTime.parse(slot.range.start.wire),
            end: WorkingTime.parse(slot.range.end.wire),
          ),
    ]);
  } finally {
    api.close();
  }
}
