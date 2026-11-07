import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/domain/auth_models.dart';
import '../domain/client_models.dart';
import '../domain/client_photo.dart';

class ClientRepository {
  ClientRepository(
    this.api, {
    required this.currentUser,
    required this.ownerId,
    this.sessionGeneration,
  }) : _initialGeneration = sessionGeneration?.call();
  final ApiClient api;
  final AuthUser? Function() currentUser;
  final int ownerId;
  final int Function()? sessionGeneration;
  final int? _initialGeneration;

  void checkAccess() {
    final user = currentUser();
    if (sessionGeneration?.call() != _initialGeneration ||
        user == null ||
        user.id != ownerId ||
        user.role != UserRole.client ||
        user.status != UserStatus.active) {
      throw const ApiException(
        kind: ApiErrorKind.forbidden,
        message: 'Only the signed-in client can access this profile.',
      );
    }
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    checkAccess();
    final result = await action();
    checkAccess();
    return result;
  }

  Future<ClientProfile> profile() => _guard(() async {
    final value = (await api.request(
      'GET',
      'client/profile',
      authenticated: true,
      accessGuard: checkAccess,
      decode: ClientProfile.fromJson,
    )).data;
    if (value.userId != ownerId) {
      throw const ApiException(
        kind: ApiErrorKind.invalidResponse,
        message: 'The returned profile does not match this account.',
      );
    }
    return value;
  });

  Future<ClientProfile> saveProfile(Map<String, Object?> values) => _guard(
    () async {
      final result = (await api.request(
        'PUT',
        'client/profile',
        authenticated: true,
        accessGuard: checkAccess,
        body: {for (final key in ClientProfile.editableKeys) key: values[key]},
        decode: ClientProfile.fromJson,
      )).data;
      if (result.userId != ownerId) {
        throw const ApiException(
          kind: ApiErrorKind.invalidResponse,
          message: 'The returned profile does not match this account.',
        );
      }
      return result;
    },
  );

  Future<ClientAddress?> address() => _guard(
    () async => (await api.request(
      'GET',
      'client/address',
      authenticated: true,
      accessGuard: checkAccess,
      decode: (value) => value == null ? null : ClientAddress.fromJson(value),
    )).data,
  );
  Future<ClientAddress> saveAddress(Map<String, Object?> values) => _guard(
    () async => (await api.request(
      'PUT',
      'client/address',
      authenticated: true,
      accessGuard: checkAccess,
      body: {
        for (final key in [...ClientAddress.textKeys, 'latitude', 'longitude'])
          key: values[key],
      },
      decode: ClientAddress.fromJson,
    )).data,
  );

  Future<LegalPreferences> preferences() => _guard(
    () async => (await api.request(
      'GET',
      'client/preferences',
      authenticated: true,
      accessGuard: checkAccess,
      decode: LegalPreferences.fromJson,
    )).data,
  );
  Future<LegalPreferences> savePreferences({
    required Iterable<int> practiceAreaIds,
    required Iterable<int> jurisdictionIds,
    required Iterable<int> courtIds,
    required Iterable<String> lawyerLanguages,
  }) => _guard(
    () async => (await api.request(
      'PUT',
      'client/preferences',
      authenticated: true,
      accessGuard: checkAccess,
      body: {
        'practiceAreaIds': practiceAreaIds.toSet().toList(),
        'jurisdictionIds': jurisdictionIds.toSet().toList(),
        'courtIds': courtIds.toSet().toList(),
        'lawyerLanguages': lawyerLanguages.toList(),
      },
      decode: LegalPreferences.fromJson,
    )).data,
  );

  Future<PreferenceCatalogs> catalogs() => _guard(() async {
    // Each endpoint returns an ordinary list of active items, not a page.
    final results = await Future.wait([
      for (final path in ['practice-areas', 'jurisdictions', 'courts'])
        api.request(
          'GET',
          path,
          accessGuard: checkAccess,
          decode: referenceList,
        ),
    ]);
    return PreferenceCatalogs(
      results[0].data,
      results[1].data,
      results[2].data,
    );
  });

  Future<String?> uploadPhoto(ClientPhoto photo) => _guard(
    () async => (await api.request(
      'POST',
      'client/profile/photo',
      authenticated: true,
      accessGuard: checkAccess,
      encodedBody: photo.multipart(),
      decode: (value) => requiredString(jsonObject(value), 'profilePhoto'),
    )).data,
  );
  Future<String?> removePhoto() => _guard(
    () async => (await api.request(
      'DELETE',
      'client/profile/photo',
      authenticated: true,
      accessGuard: checkAccess,
      decode: _photoResponse,
    )).data,
  );
  String? _photoResponse(Object? value) {
    final json = jsonObject(value);
    if (!json.containsKey('profilePhoto')) {
      throw const FormatException('Missing photo field');
    }
    return optionalString(json, 'profilePhoto');
  }
}
