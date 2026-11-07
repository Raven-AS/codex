import '../../../core/utils/decimal_text.dart';

import '../../auth/domain/auth_models.dart' show jsonObject, requiredString;

String? optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value != null && value is! String) throw FormatException('Invalid $key');
  return value as String?;
}

class ClientProfile {
  ClientProfile.fromJson(Object? value)
    : fields = Map.unmodifiable(jsonObject(value)) {
    if (fields['id'] is! int || fields['userId'] is! int) {
      throw const FormatException('Invalid profile identity');
    }
    requiredString(fields, 'profileStatus');
    for (final key in [
      ...editableKeys,
      'profilePhoto',
      'createdAt',
      'updatedAt',
    ]) {
      optionalString(fields, key);
    }
  }
  static const editableKeys = [
    'firstName',
    'lastName',
    'dateOfBirth',
    'gender',
    'phone',
    'email',
    'occupation',
  ];
  final Map<String, dynamic> fields;
  int get userId => fields['userId'] as int;
  String? text(String key) => fields[key] as String?;
  String get status => fields['profileStatus'] as String;
  String? get photo => text('profilePhoto');
  String get displayName => [
    text('firstName'),
    text('lastName'),
  ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
}

class ClientAddress {
  ClientAddress.fromJson(Object? value)
    : fields = Map.unmodifiable(jsonObject(value)) {
    if (fields['id'] is! int) {
      throw const FormatException('Invalid address identity');
    }
    for (final key in textKeys) {
      optionalString(fields, key);
    }
    for (final key in ['latitude', 'longitude']) {
      if (fields[key] != null && fields[key] is! num) {
        throw FormatException('Invalid $key');
      }
    }
  }
  static const textKeys = [
    'addressLine',
    'country',
    'division',
    'district',
    'city',
    'area',
    'postalCode',
  ];
  final Map<String, dynamic> fields;
  String? text(String key) =>
      fields[key] == null ? null : decimalText(fields[key]);
}

class ReferenceItem {
  const ReferenceItem(this.id, this.name);
  factory ReferenceItem.fromJson(Object? value) {
    final json = jsonObject(value);
    if (json['id'] is! int || (json['id'] as int) <= 0) {
      throw const FormatException('Invalid reference id');
    }
    return ReferenceItem(json['id'] as int, requiredString(json, 'name'));
  }
  final int id;
  final String name;
}

List<ReferenceItem> referenceList(Object? value) {
  if (value is! List) throw const FormatException('Expected reference list');
  return List.unmodifiable(value.map(ReferenceItem.fromJson));
}

class LegalPreferences {
  LegalPreferences({
    required this.practiceAreas,
    required this.jurisdictions,
    required this.courts,
    required this.lawyerLanguages,
  });
  factory LegalPreferences.fromJson(Object? value) {
    final json = jsonObject(value);
    final languages = json['lawyerLanguages'];
    if (languages is! List || languages.any((v) => v is! String)) {
      throw const FormatException('Invalid languages');
    }
    return LegalPreferences(
      practiceAreas: referenceList(json['practiceAreas']),
      jurisdictions: referenceList(json['jurisdictions']),
      courts: referenceList(json['courts']),
      lawyerLanguages: List<String>.unmodifiable(languages),
    );
  }
  final List<ReferenceItem> practiceAreas;
  final List<ReferenceItem> jurisdictions;
  final List<ReferenceItem> courts;
  final List<String> lawyerLanguages;
}

class PreferenceCatalogs {
  const PreferenceCatalogs(this.practiceAreas, this.jurisdictions, this.courts);
  final List<ReferenceItem> practiceAreas;
  final List<ReferenceItem> jurisdictions;
  final List<ReferenceItem> courts;
}
