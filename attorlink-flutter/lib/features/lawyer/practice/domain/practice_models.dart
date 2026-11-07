import '../../../auth/domain/auth_models.dart' show jsonObject;
import '../../../client/domain/client_models.dart' show ReferenceItem;
import '../../domain/lawyer_models.dart';
import '../../qualifications/domain/qualification_schema.dart';
import 'practice_schema.dart';

class PracticeRecord {
  PracticeRecord.fromJson(this.resource, Object? value)
    : fields = Map.unmodifiable(jsonObject(value)) {
    if (fields['id'] is! int || (fields['id'] as int) <= 0) {
      throw const FormatException('Invalid practice record ID');
    }
    for (final field in resource.schema.fields) {
      final value = fields[field.key];
      if (value == null && field.kind != QualificationKind.boolean) continue;
      final valid = field.decimals != null
          ? value is num && value.isFinite
          : switch (field.kind) {
              QualificationKind.integer => value is int,
              QualificationKind.boolean => value is bool,
              QualificationKind.choice =>
                value is String && field.options.contains(value),
              _ => value is String,
            };
      if (!valid) throw FormatException('Invalid ${field.key}');
    }
    for (final key in resource.schema.metadata.keys) {
      if (key == 'verificationStatus') {
        LawyerStatuses.decode(fields[key], LawyerStatuses.record);
      } else if (fields[key] != null && fields[key] is! String) {
        throw FormatException('Invalid $key');
      }
    }
  }
  final PracticeResource resource;
  final Map<String, dynamic> fields;
  int get id => fields['id'] as int;
  String? text(String key) => fields[key]?.toString();
  String get title => text(resource.schema.titleField)?.isNotEmpty == true
      ? text(resource.schema.titleField)!
      : resource.schema.label;
}

class PracticeReference {
  const PracticeReference(
    this.id,
    this.name, {
    this.context = '',
    this.savedOnly = false,
  });
  factory PracticeReference.fromJson(Object? value) {
    final json = jsonObject(value);
    final item = ReferenceItem.fromJson(json);
    final details = <String>[];
    for (final key in ['courtType', 'district', 'division']) {
      final value = json[key];
      if (value != null && value is! String) {
        throw FormatException('Invalid reference $key');
      }
      if (value is String && value.isNotEmpty) details.add(value);
    }
    return PracticeReference(item.id, item.name, context: details.join(' · '));
  }
  final int id;
  final String name;
  final String context;
  final bool savedOnly;
  String get label =>
      '$name${context.isEmpty ? '' : ' · $context'}${savedOnly ? ' (saved reference; not in active catalog)' : ''}';
}

Map<String, String> validatePractice(
  PracticeResource resource,
  Map<String, Object?> values,
) {
  final errors = <String, String>{};
  for (final field in resource.schema.fields) {
    final value = values[field.key];
    final validType =
        value == null ||
        (field.decimals != null
            ? value is num && value.isFinite
            : switch (field.kind) {
                QualificationKind.integer => value is int,
                QualificationKind.boolean => value is bool,
                _ => value is String,
              });
    if (!validType) {
      errors[field.key] = 'Enter a valid ${field.label.toLowerCase()}.';
      continue;
    }
    final error = field.validate(
      value == null ? null : practiceInputText(value),
    );
    if (error != null) errors[field.key] = error;
  }
  return errors;
}

List<PracticeReference> decodePracticeReferences(Object? value) {
  if (value is! List) throw const FormatException('Expected reference list');
  return value.map(PracticeReference.fromJson).toList();
}
