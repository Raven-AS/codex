import '../../auth/domain/auth_models.dart' show jsonObject, requiredString;

String? lawyerString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value != null && value is! String) throw FormatException('Invalid $key');
  return value as String?;
}

abstract final class LawyerStatuses {
  static const profile = {
    'DRAFT',
    'SUBMITTED',
    'IN_REVIEW',
    'VERIFIED',
    'REJECTED',
    'EXPIRED',
    'SUSPENDED',
    'COMPLETE',
  };
  static const record = {'PENDING', 'VERIFIED', 'REJECTED', 'EXPIRED'};
  static String decode(Object? value, Set<String> allowed) {
    if (value is! String || !allowed.contains(value)) {
      throw const FormatException('Unknown verification status');
    }
    return value;
  }
}

class LawyerProfile {
  LawyerProfile.fromJson(Object? value)
    : fields = Map.unmodifiable(jsonObject(value)) {
    for (final key in ['id', 'userId']) {
      if (fields[key] is! int || (fields[key] as int) <= 0) {
        throw FormatException('Invalid $key');
      }
    }
    LawyerStatuses.decode(fields['profileStatus'], LawyerStatuses.profile);
    for (final key in [
      ...requestKeys.where((k) => k != 'yearsOfExperience'),
      'fullName',
      'rejectionReason',
      'createdAt',
      'updatedAt',
    ]) {
      lawyerString(fields, key);
    }
    if (fields['yearsOfExperience'] != null &&
        fields['yearsOfExperience'] is! int) {
      throw const FormatException('Invalid experience');
    }
  }
  static const personalKeys = [
    'firstName',
    'middleName',
    'lastName',
    'dateOfBirth',
    'gender',
  ];
  static const professionalKeys = [
    'professionalTitle',
    'bio',
    'barCouncil',
    'barRegistrationNumber',
    'yearsOfExperience',
    'professionalEmail',
    'professionalPhone',
    'website',
    'consultationCurrency',
  ];
  static const requestKeys = [
    ...personalKeys,
    ...professionalKeys,
    'profilePhoto',
    'coverPhoto',
  ];
  final Map<String, dynamic> fields;
  int get id => fields['id'] as int;
  int get userId => fields['userId'] as int;
  String get status => fields['profileStatus'] as String;
  String? text(String key) => fields[key]?.toString();
  String get displayName => text('fullName')?.trim().isNotEmpty == true
      ? text('fullName')!
      : [
          text('firstName'),
          text('middleName'),
          text('lastName'),
        ].whereType<String>().where((v) => v.isNotEmpty).join(' ');
}

class BarCouncilRecord {
  BarCouncilRecord.fromJson(Object? value)
    : fields = Map.unmodifiable(jsonObject(value)) {
    if (fields['id'] is! int || (fields['id'] as int) <= 0) {
      throw const FormatException('Invalid Bar Council identity');
    }
    LawyerStatuses.decode(fields['verificationStatus'], LawyerStatuses.record);
    for (final key in [
      ...requestKeys,
      'verifiedAt',
      'verifiedBy',
      'rejectionReason',
    ]) {
      lawyerString(fields, key);
    }
  }
  static const informationKeys = [
    'enrollmentNumber',
    'sanadNumber',
    'enrollmentDate',
    'sanadIssueDate',
    'greenBookNumber',
    'barCouncilIdNumber',
  ];
  static const documentKeys = [
    'identityCardDocument',
    'sanadDocument',
    'greenBookDocument',
  ];
  static const requestKeys = [...informationKeys, ...documentKeys];
  final Map<String, dynamic> fields;
  String get status => fields['verificationStatus'] as String;
  String? text(String key) => fields[key] as String?;
}

enum CouncilDocument {
  identityCard('identity-card', 'identityCardDocument', 'Identity card'),
  sanad('sanad', 'sanadDocument', 'Sanad'),
  greenBook('green-book', 'greenBookDocument', 'Green book');

  const CouncilDocument(this.path, this.field, this.label);
  final String path;
  final String field;
  final String label;
}

class LawyerUploadResult {
  LawyerUploadResult.fromJson(Object? value) {
    final json = jsonObject(value);
    if (!json.containsKey('url') || !json.containsKey('publicId')) {
      throw const FormatException('Incomplete upload result');
    }
    url = lawyerString(json, 'url');
    publicId = lawyerString(json, 'publicId');
  }
  late final String? url;
  late final String? publicId;
}

class LawyerSubmission {
  LawyerSubmission.fromJson(Object? value) {
    final json = jsonObject(value);
    final id = json['lawyerProfileId'];
    if (id is! int || id <= 0) {
      throw const FormatException('Invalid submitted profile id');
    }
    profileId = id;
    status = LawyerStatuses.decode(
      json['profileStatus'],
      LawyerStatuses.profile,
    );
    message = requiredString(json, 'message');
  }
  late final int profileId;
  late final String status;
  late final String message;
}

class LawyerSnapshot {
  const LawyerSnapshot(this.profile, this.barCouncil);
  final LawyerProfile profile;
  final BarCouncilRecord? barCouncil;
  bool get hasFirstName => profile.text('firstName')?.trim().isNotEmpty == true;
  bool get hasBarRegistration =>
      profile.text('barRegistrationNumber')?.trim().isNotEmpty == true;
  bool get hasBarCouncilRecord => barCouncil != null;
  // Mirrors the actual submit service, not its narrower DRAFT/REJECTED comment.
  bool get alreadySubmitted =>
      {'SUBMITTED', 'IN_REVIEW', 'VERIFIED'}.contains(profile.status);
  bool get canSubmit =>
      hasFirstName &&
      hasBarRegistration &&
      hasBarCouncilRecord &&
      !alreadySubmitted;
}
