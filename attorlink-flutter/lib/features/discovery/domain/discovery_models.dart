import '../../auth/domain/auth_models.dart' show jsonObject;
import '../../client/domain/client_models.dart' show optionalString;

/// Only the public LawyerDiscoverResponse, never an owner's full profile.
class DiscoveredLawyer {
  DiscoveredLawyer.fromJson(Object? value) {
    final json = jsonObject(value);
    int identity(String key) {
      final id = json[key];
      if (id is! int || id <= 0) throw FormatException('Invalid $key');
      return id;
    }

    id = identity('id');
    userId = identity('userId');
    final name = json['fullName'];
    if (name is! String) throw const FormatException('Invalid fullName');
    fullName = name;
    profilePhoto = optionalString(json, 'profilePhoto');
    professionalTitle = optionalString(json, 'professionalTitle');
    bio = optionalString(json, 'bio');
    updatedAt = optionalString(json, 'updatedAt');
    final experience = json['yearsOfExperience'];
    if (experience != null && experience is! int) {
      throw const FormatException('Invalid yearsOfExperience');
    }
    yearsOfExperience = experience as int?;
    final areas = json['practiceAreas'];
    if (areas is! List || areas.any((item) => item is! String)) {
      throw const FormatException('Invalid practiceAreas');
    }
    practiceAreas = List<String>.unmodifiable(areas);
  }

  late final int id;
  late final int userId;
  late final String fullName;
  late final String? profilePhoto;
  late final String? professionalTitle;
  late final String? bio;
  late final int? yearsOfExperience;
  late final List<String> practiceAreas;
  // Preserve the backend's timezone-free LocalDateTime string.
  late final String? updatedAt;

  String get displayName => fullName.trim().isEmpty ? 'Lawyer' : fullName;
}
