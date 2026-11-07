import '../../../auth/domain/auth_models.dart' show jsonObject;
import '../../domain/lawyer_models.dart';
import 'qualification_schema.dart';

class QualificationRecord {
  QualificationRecord.fromJson(this.resource, Object? value)
    : fields = Map.unmodifiable(jsonObject(value)) {
    if (fields['id'] is! int || (fields['id'] as int) <= 0) {
      throw const FormatException('Invalid record identity');
    }
    for (final field in resource.schema.fields) {
      final value = fields[field.key];
      if (value == null) continue;
      final valid = switch (field.kind) {
        QualificationKind.integer => value is int,
        QualificationKind.boolean => value is bool,
        QualificationKind.choice =>
          value is String && field.options.contains(value),
        _ => value is String,
      };
      if (!valid) throw FormatException('Invalid ${field.key}');
    }
    for (final key in resource.schema.metadata) {
      if (key == 'verificationStatus') {
        LawyerStatuses.decode(fields[key], LawyerStatuses.record);
      } else if (fields[key] != null && fields[key] is! String) {
        throw FormatException('Invalid $key');
      }
    }
  }
  final QualificationResource resource;
  final Map<String, dynamic> fields;
  int get id => fields['id'] as int;
  String? text(String key) => fields[key]?.toString();
  String get title =>
      text(resource.schema.titleField)?.trim().isNotEmpty == true
      ? text(resource.schema.titleField)!
      : resource.schema.label;
  Map<String, Object?> get requestValues => {
    for (final field in resource.schema.fields) field.key: fields[field.key],
  };
}

Map<String, String> validateQualification(
  QualificationResource resource,
  Map<String, Object?> values,
) {
  final errors = <String, String>{};
  for (final field in resource.schema.informationFields) {
    if (resource == QualificationResource.experience &&
        field.key == 'endDate' &&
        values['current'] == true) {
      continue;
    }
    final value = values[field.key];
    if (value != null &&
        (field.kind == QualificationKind.boolean
            ? value is! bool
            : field.kind == QualificationKind.integer
            ? value is! int
            : value is! String)) {
      errors[field.key] = 'Enter a valid ${field.label.toLowerCase()}.';
      continue;
    }
    final error = field.validate(values[field.key]?.toString());
    if (error != null) errors[field.key] = error;
  }
  if (resource == QualificationResource.experience &&
      values['current'] != true &&
      values['startDate'] != null &&
      values['endDate'] != null &&
      !errors.containsKey('startDate') &&
      !errors.containsKey('endDate')) {
    final start = DateTime.tryParse(values['startDate'].toString());
    final end = DateTime.tryParse(values['endDate'].toString());
    if (start != null && end != null && end.isBefore(start)) {
      errors['endDate'] = 'End date cannot be before start date.';
    }
  }
  if (resource == QualificationResource.education &&
      values['startYear'] is int &&
      values['endYear'] is int &&
      !errors.containsKey('startYear') &&
      !errors.containsKey('endYear') &&
      (values['startYear'] as int) > (values['endYear'] as int)) {
    errors['endYear'] = 'End year must be on or after start year.';
  }
  return errors;
}
