import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/domain/auth_models.dart';
import '../../client/domain/client_photo.dart';
import '../domain/lawyer_document.dart';
import '../domain/lawyer_models.dart';

class LawyerRepository {
  LawyerRepository(
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
        user.role != UserRole.lawyer ||
        user.status != UserStatus.active) {
      throw const ApiException(
        kind: ApiErrorKind.forbidden,
        message: 'Only the signed-in lawyer can manage this profile.',
      );
    }
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    checkAccess();
    final result = await action();
    checkAccess();
    return result;
  }

  LawyerProfile _profile(Object? value) {
    final profile = LawyerProfile.fromJson(value);
    if (profile.userId != ownerId) {
      throw const FormatException('Wrong profile owner');
    }
    return profile;
  }

  Future<LawyerProfile> profile() => _guard(
    () async => (await api.request(
      'GET',
      'lawyer/profile',
      authenticated: true,
      accessGuard: checkAccess,
      decode: _profile,
    )).data,
  );
  Future<LawyerProfile> saveProfile(Map<String, Object?> changes) => _guard(
    () async => (await api.request(
      'PUT',
      'lawyer/profile',
      authenticated: true,
      accessGuard: checkAccess,
      body: {
        for (final entry in changes.entries)
          if (LawyerProfile.requestKeys.contains(entry.key))
            entry.key: entry.value,
      },
      decode: _profile,
    )).data,
  );
  Future<BarCouncilRecord?> barCouncil() => _guard(
    () async => (await api.request(
      'GET',
      'lawyer/bar-council',
      authenticated: true,
      accessGuard: checkAccess,
      decode: (value) =>
          value == null ? null : BarCouncilRecord.fromJson(value),
    )).data,
  );
  Future<BarCouncilRecord> saveBarCouncil(Map<String, Object?> values) =>
      _guard(
        () async => (await api.request(
          'PUT',
          'lawyer/bar-council',
          authenticated: true,
          accessGuard: checkAccess,
          body: {
            for (final key in BarCouncilRecord.requestKeys) key: values[key],
          },
          decode: BarCouncilRecord.fromJson,
        )).data,
      );
  Future<LawyerSnapshot> snapshot() async {
    final values = await Future.wait<Object?>([profile(), barCouncil()]);
    return LawyerSnapshot(
      values[0] as LawyerProfile,
      values[1] as BarCouncilRecord?,
    );
  }

  Future<LawyerSubmission> submit(int expectedProfileId) => _guard(
    () async => (await api.request(
      'POST',
      'lawyer/profile/submit',
      authenticated: true,
      accessGuard: checkAccess,
      decode: (value) {
        final result = LawyerSubmission.fromJson(value);
        if (result.profileId != expectedProfileId) {
          throw const FormatException('Wrong submitted profile');
        }
        return result;
      },
    )).data,
  );

  Future<LawyerUploadResult> uploadPhoto(
    ClientPhoto photo, {
    bool cover = false,
  }) => _guard(
    () async => (await api.request(
      'POST',
      'lawyer/profile/${cover ? 'cover-photo' : 'photo'}',
      authenticated: true,
      accessGuard: checkAccess,
      encodedBody: photo.multipart(),
      decode: _uploaded,
    )).data,
  );
  Future<LawyerUploadResult> removePhoto({bool cover = false}) => _guard(
    () async => (await api.request(
      'DELETE',
      'lawyer/profile/${cover ? 'cover-photo' : 'photo'}',
      authenticated: true,
      accessGuard: checkAccess,
      decode: LawyerUploadResult.fromJson,
    )).data,
  );
  Future<LawyerUploadResult> uploadDocument(
    CouncilDocument target,
    LawyerDocument document,
  ) => _guard(
    () async => (await api.request(
      'POST',
      'lawyer/bar-council/${target.path}',
      authenticated: true,
      accessGuard: checkAccess,
      encodedBody: document.multipart(),
      decode: _uploaded,
    )).data,
  );
  Future<LawyerUploadResult> removeDocument(CouncilDocument target) => _guard(
    () async => (await api.request(
      'DELETE',
      'lawyer/bar-council/${target.path}',
      authenticated: true,
      accessGuard: checkAccess,
      decode: LawyerUploadResult.fromJson,
    )).data,
  );
  LawyerUploadResult _uploaded(Object? value) {
    final result = LawyerUploadResult.fromJson(value);
    if (result.url == null ||
        result.url!.isEmpty ||
        result.publicId == null ||
        result.publicId!.isEmpty) {
      throw const FormatException('Incomplete uploaded file');
    }
    return result;
  }
}
