// Compile-only entry point; never executed in a browser or against the backend.
import 'dart:typed_data';

import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_client.dart';
import 'package:attorlink_flutter/features/auth/domain/auth_models.dart';
import 'package:attorlink_flutter/features/client/domain/client_photo.dart';
import 'package:attorlink_flutter/features/lawyer/data/lawyer_repository.dart';
import 'package:attorlink_flutter/features/lawyer/data/select_document.dart';
import 'package:attorlink_flutter/features/lawyer/domain/lawyer_document.dart';
import 'package:attorlink_flutter/features/lawyer/domain/lawyer_models.dart';

Future<void> main() async {
  final api = ApiClient(
    config: ApiConfig.fromEnvironment(),
    accessTokenProvider: () => 'compile-only',
  );
  final repository = LawyerRepository(
    api,
    ownerId: 1,
    currentUser: () => const AuthUser(
      id: 1,
      email: 'compile-only@example.test',
      role: UserRole.lawyer,
      status: UserStatus.active,
    ),
  );
  try {
    final snapshot = await repository.snapshot();
    final document =
        await selectDocument() ??
        LawyerDocument.fromBytes(
          'compile.pdf',
          Uint8List.fromList([37, 80, 68, 70, 45]),
        );
    await repository.uploadDocument(CouncilDocument.sanad, document);
    await repository.uploadPhoto(
      ClientPhoto.fromBytes(
        'compile.png',
        Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      ),
      cover: true,
    );
    await repository.submit(snapshot.profile.id);
  } finally {
    api.close();
  }
}
