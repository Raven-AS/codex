import '../../client/domain/client_validation.dart';

abstract final class LawyerValidation {
  static const profileLimits = {
    'firstName': 100,
    'middleName': 100,
    'lastName': 100,
    'professionalTitle': 150,
    'bio': 5000,
    'barCouncil': 150,
    'barRegistrationNumber': 80,
    'website': 255,
    'consultationCurrency': 10,
  };
  static const labels = {
    'firstName': 'First name',
    'middleName': 'Middle name',
    'lastName': 'Last name',
    'dateOfBirth': 'Date of birth (YYYY-MM-DD)',
    'gender': 'Gender',
    'professionalTitle': 'Professional title',
    'bio': 'Bio',
    'barCouncil': 'Bar Council',
    'barRegistrationNumber': 'Bar registration number',
    'yearsOfExperience': 'Years of experience',
    'professionalEmail': 'Professional email',
    'professionalPhone': 'Professional phone',
    'website': 'Website',
    'consultationCurrency': 'Consultation currency',
    'enrollmentNumber': 'Enrollment number',
    'sanadNumber': 'Sanad number',
    'enrollmentDate': 'Enrollment date (YYYY-MM-DD)',
    'sanadIssueDate': 'Sanad issue date (YYYY-MM-DD)',
    'greenBookNumber': 'Green book number',
    'barCouncilIdNumber': 'Bar Council ID number',
  };

  static String? date(String? value) {
    if (value == null || value.isEmpty) return null;
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return 'Use YYYY-MM-DD.';
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null ||
        parsed.year < 1 ||
        parsed.toIso8601String().substring(0, 10) != value) {
      return 'Enter a valid date.';
    }
    return null;
  }

  static String? profileField(String key, String? value) {
    if (key == 'dateOfBirth') return ClientValidation.birthDate(value);
    if (key == 'professionalPhone') return ClientValidation.phone(value);
    if (key == 'professionalEmail') return ClientValidation.email(value);
    if (key == 'yearsOfExperience') {
      if (value == null || value.isEmpty) return null;
      final number = int.tryParse(value);
      return number != null && number >= 0 && number <= 70
          ? null
          : 'Enter a whole number from 0 to 70.';
    }
    return ClientValidation.length(value, profileLimits[key]!);
  }

  static String? councilField(String key, String? value) =>
      key.endsWith('Date') ? date(value) : ClientValidation.length(value, 100);
}
