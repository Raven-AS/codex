abstract final class ClientValidation {
  static const profileLimits = {
    'firstName': 100,
    'lastName': 100,
    'occupation': 150,
  };
  static const addressLimits = {
    'addressLine': 255,
    'country': 80,
    'division': 80,
    'district': 80,
    'city': 80,
    'area': 80,
    'postalCode': 20,
  };

  static String? length(String? value, int limit) =>
      (value?.length ?? 0) > limit ? 'Use at most $limit characters.' : null;
  static String? phone(String? value) =>
      value == null ||
          value.isEmpty ||
          RegExp(r'^[0-9+\-]{6,20}$').hasMatch(value)
      ? null
      : 'Use 6–20 digits, + or -.';
  static String? email(String? value) =>
      value == null ||
          value.isEmpty ||
          RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)
      ? null
      : 'Enter a valid email address.';
  static String? birthDate(String? value, {DateTime? now}) {
    if (value == null || value.isEmpty) return null;
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return 'Use YYYY-MM-DD.';
    }
    final date = DateTime.tryParse(value);
    if (date == null ||
        date.year < 1 ||
        date.toIso8601String().substring(0, 10) != value) {
      return 'Enter a valid date.';
    }
    final today = now ?? DateTime.now();
    return date.isBefore(DateTime(today.year, today.month, today.day))
        ? null
        : 'Date of birth must be in the past.';
  }

  static String? coordinate(String? value) {
    if (value == null || value.isEmpty) return null;
    // Matches the entity's DECIMAL(10,7) storage; no geographic range is imposed by its DTO.
    if (!RegExp(r'^-?\d{1,3}(\.\d{1,7})?$').hasMatch(value)) {
      return 'Use up to 3 integer and 7 decimal digits.';
    }
    return null;
  }

  static String normalizeLanguage(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');
}
