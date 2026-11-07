import '../../../../core/utils/decimal_text.dart';
import '../../../client/domain/client_validation.dart';
import '../../qualifications/domain/qualification_schema.dart';

class PracticeField extends QualificationField {
  const PracticeField(
    super.key,
    super.label, {
    super.kind,
    super.required,
    super.maxLength,
    super.min,
    super.max,
    super.options,
    this.reference,
    this.referenceName,
    this.decimals,
    this.wholeDigits,
  });
  final String? reference;
  final String? referenceName;
  final int? decimals;
  final int? wholeDigits;
  @override
  String? validate(String? input) {
    final value = input?.trim() ?? '';
    if (value.isEmpty) return required ? '$label is required.' : null;
    if (reference != null) {
      return int.tryParse(value) != null && int.parse(value) > 0
          ? null
          : 'Choose a valid $label.';
    }
    if (decimals != null) {
      final signed = key == 'fee' ? '' : '-?';
      return RegExp('^$signed[0-9]{1,$wholeDigits}(\\.[0-9]{1,$decimals})?\$')
              .hasMatch(value)
          ? null
          : 'Use up to $wholeDigits integer and $decimals decimal digits${key == 'fee' ? ', with no negative fee' : ''}.';
    }
    if (key == 'phone') return ClientValidation.phone(value);
    if (key == 'email') return ClientValidation.email(value);
    return super.validate(value);
  }
}

class PracticeSchema {
  const PracticeSchema(
    this.path,
    this.label,
    this.titleField,
    this.fields, {
    this.metadata = const {'createdAt': 'Created at'},
  });
  final String path;
  final String label;
  final String titleField;
  final List<PracticeField> fields;
  final Map<String, String> metadata;
  String get endpoint => 'lawyer/$path';
  PracticeField? get referenceField {
    for (final field in fields) {
      if (field.reference != null) return field;
    }
    return null;
  }
}

enum PracticeResource {
  specializations(
    PracticeSchema(
      'specializations',
      'Specializations',
      'practiceAreaName',
      [
        PracticeField(
          'practiceAreaId',
          'Practice area',
          kind: QualificationKind.integer,
          required: true,
          reference: 'practice-areas',
          referenceName: 'practiceAreaName',
        ),
        PracticeField(
          'experienceYears',
          'Experience years',
          kind: QualificationKind.integer,
          min: 0,
          max: 70,
        ),
        PracticeField(
          'isPrimary',
          'Primary specialization',
          kind: QualificationKind.boolean,
        ),
      ],
      metadata: {
        'practiceAreaName': 'Practice area',
        'createdAt': 'Created at',
      },
    ),
  ),
  jurisdictions(
    PracticeSchema(
      'jurisdictions',
      'Jurisdictions',
      'jurisdictionName',
      [
        PracticeField(
          'jurisdictionId',
          'Jurisdiction',
          kind: QualificationKind.integer,
          required: true,
          reference: 'jurisdictions',
          referenceName: 'jurisdictionName',
        ),
        PracticeField(
          'registrationNumber',
          'Registration number',
          maxLength: 100,
        ),
      ],
      metadata: {
        'jurisdictionName': 'Jurisdiction',
        'district': 'District',
        'division': 'Division',
        'verificationStatus': 'Verification status',
        'createdAt': 'Created at',
      },
    ),
  ),
  courts(
    PracticeSchema(
      'courts',
      'Courts',
      'courtName',
      [
        PracticeField(
          'courtId',
          'Court',
          kind: QualificationKind.integer,
          required: true,
          reference: 'courts',
          referenceName: 'courtName',
        ),
      ],
      metadata: {
        'courtName': 'Court',
        'courtType': 'Court type',
        'district': 'District',
        'createdAt': 'Created at',
      },
    ),
  ),
  languages(
    PracticeSchema('languages', 'Languages', 'language', [
      PracticeField('language', 'Language', required: true, maxLength: 60),
      PracticeField(
        'proficiency',
        'Proficiency',
        kind: QualificationKind.choice,
        options: ['NATIVE', 'FLUENT', 'CONVERSATIONAL', 'BASIC'],
      ),
    ]),
  ),
  offices(
    PracticeSchema('offices', 'Law offices', 'officeName', [
      PracticeField(
        'officeName',
        'Office name',
        required: true,
        maxLength: 191,
      ),
      PracticeField('addressLine', 'Address line', maxLength: 255),
      PracticeField('country', 'Country', maxLength: 80),
      PracticeField('division', 'Division', maxLength: 80),
      PracticeField('district', 'District', maxLength: 80),
      PracticeField('city', 'City', maxLength: 80),
      PracticeField('area', 'Area', maxLength: 80),
      PracticeField('postalCode', 'Postal code', maxLength: 20),
      PracticeField('latitude', 'Latitude', decimals: 7, wholeDigits: 3),
      PracticeField('longitude', 'Longitude', decimals: 7, wholeDigits: 3),
      PracticeField('phone', 'Office phone'),
      PracticeField('email', 'Office email'),
      PracticeField(
        'primaryOffice',
        'Primary office',
        kind: QualificationKind.boolean,
      ),
    ]),
  ),
  services(
    PracticeSchema('services', 'Legal services', 'name', [
      PracticeField('name', 'Service name', required: true, maxLength: 191),
      PracticeField('description', 'Description', maxLength: 2000),
      PracticeField(
        'consultationType',
        'Consultation type',
        kind: QualificationKind.choice,
        required: true,
        options: ['CHAT', 'PHONE', 'VIDEO', 'IN_PERSON'],
      ),
      PracticeField(
        'durationMinutes',
        'Duration (minutes)',
        kind: QualificationKind.integer,
        min: 0,
        max: 2147483647,
      ),
      PracticeField('fee', 'Fee', decimals: 2, wholeDigits: 10),
      PracticeField('currency', 'Currency', maxLength: 10),
      PracticeField(
        'active',
        'Active service',
        kind: QualificationKind.boolean,
      ),
    ]),
  );

  const PracticeResource(this.schema);
  final PracticeSchema schema;
}

/// Preserve the backend decimal precision when displaying form values.
String practiceInputText(Object? value) => decimalText(value);
