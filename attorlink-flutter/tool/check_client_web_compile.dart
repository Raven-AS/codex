// Compile-only check; this program is not executed in a browser.
import 'dart:typed_data';

import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_client.dart';
import 'package:attorlink_flutter/features/auth/domain/auth_models.dart';
import 'package:attorlink_flutter/features/client/data/client_repository.dart';
import 'package:attorlink_flutter/features/client/data/select_photo.dart';
import 'package:attorlink_flutter/features/client/domain/client_photo.dart';

Future<void> main() async {
  final api = ApiClient(
    config: ApiConfig.fromEnvironment(),
    accessTokenProvider: () => 'compile-only',
  );
  final client = ClientRepository(
    api,
    ownerId: 1,
    currentUser: () => const AuthUser(
      id: 1,
      email: 'compile-only@example.test',
      role: UserRole.client,
      status: UserStatus.active,
    ),
  );
  try {
    final photo =
        await selectPhoto() ??
        ClientPhoto.fromBytes(
          'compile.png',
          Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
        );
    await client.uploadPhoto(photo);
    await client.profile();
    await client.address();
    await client.preferences();
    await client.catalogs();
  } finally {
    api.close();
  }
}
