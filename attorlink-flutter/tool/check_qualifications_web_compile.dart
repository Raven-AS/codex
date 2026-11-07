// Compile only. Never executed against a browser or live backend.
import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_client.dart';
import 'package:attorlink_flutter/features/auth/domain/auth_models.dart';
import 'package:attorlink_flutter/features/lawyer/data/lawyer_repository.dart';
import 'package:attorlink_flutter/features/lawyer/data/select_document.dart';
import 'package:attorlink_flutter/features/lawyer/qualifications/data/qualifications_repository.dart';
import 'package:attorlink_flutter/features/lawyer/qualifications/domain/qualification_schema.dart';

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
  final repository = QualificationsRepository(lawyer);
  try {
    for (final resource in QualificationResource.values) {
      final records = await repository.list(resource);
      if (records.isEmpty) continue;
      await repository.detail(resource, records.first.id);
      await repository.saveInformation(
        resource,
        records.first.requestValues,
        id: records.first.id,
      );
      if (resource.schema.attachments.isNotEmpty) {
        final file = await selectDocument();
        if (file != null) {
          await repository.upload(
            resource,
            records.first.id,
            resource.schema.attachments.first.field,
            file,
          );
        }
      }
    }
  } finally {
    api.close();
  }
}
