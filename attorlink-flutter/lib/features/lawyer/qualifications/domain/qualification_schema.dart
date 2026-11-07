import '../../domain/lawyer_validation.dart';

enum QualificationKind { text, date, integer, boolean, choice, document }

class QualificationField {
  const QualificationField(
    this.key,
    this.label, {
    this.kind = QualificationKind.text,
    this.required = false,
    this.maxLength,
    this.min,
    this.max,
    this.options = const [],
  });
  final String key;
  final String label;
  final QualificationKind kind;
  final bool required;
  final int? maxLength;
  final int? min;
  final int? max;
  final List<String> options;

  String? validate(String? input) {
    final value = input?.trim() ?? '';
    if (value.isEmpty) return required ? '$label is required.' : null;
    if (maxLength != null && value.length > maxLength!) {
      return 'Use at most $maxLength characters.';
    }
    if (kind == QualificationKind.date) return LawyerValidation.date(value);
    if (kind == QualificationKind.integer) {
      final number = int.tryParse(value);
      if (number == null ||
          number < (min ?? -2147483648) ||
          number > (max ?? 2147483647)) {
        return min != null && max != null
            ? 'Enter a whole number from $min to $max.'
            : 'Enter a valid 32-bit whole number.';
      }
    }
    if (kind == QualificationKind.choice && !options.contains(value)) {
      return 'Choose a supported value.';
    }
    return null;
  }
}

class QualificationAttachment {
  const QualificationAttachment(this.field, this.label, {this.endpoint});
  final String field;
  final String label;
  // Null means generic storage upload + JSON record update, never an invented route.
  final String? endpoint;
}

class QualificationSchema {
  const QualificationSchema({
    required this.path,
    required this.label,
    required this.titleField,
    required this.fields,
    this.singleton = false,
    this.verified = false,
    this.metadata = const ['createdAt'],
    this.attachments = const [],
  });
  final String path;
  final String label;
  final String titleField;
  final List<QualificationField> fields;
  final bool singleton;
  final bool verified;
  final List<String> metadata;
  final List<QualificationAttachment> attachments;
  String get endpoint => 'lawyer/$path';
  Iterable<QualificationField> get informationFields =>
      fields.where((f) => f.kind != QualificationKind.document);
}

const _verifiedMetadata = [
  'verificationStatus',
  'verifiedAt',
  'verifiedBy',
  'rejectionReason',
];
const _credentialTypes = [
  'BAR_COUNCIL_SANAD',
  'BAR_COUNCIL_ID',
  'BAR_COUNCIL_ENROLLMENT',
  'GREEN_BOOK',
  'NID',
  'PASSPORT',
  'OTHER',
];
const _description = QualificationField(
  'description',
  'Description',
  maxLength: 2000,
);
const _startDate = QualificationField(
  'startDate',
  'Start date',
  kind: QualificationKind.date,
);
const _endDate = QualificationField(
  'endDate',
  'End date',
  kind: QualificationKind.date,
);

enum QualificationResource {
  highCourt(
    QualificationSchema(
      path: 'high-court',
      label: 'High Court registration',
      titleField: 'permissionNumber',
      singleton: true,
      verified: true,
      metadata: _verifiedMetadata,
      fields: [
        QualificationField(
          'permissionNumber',
          'Permission number',
          maxLength: 100,
        ),
        QualificationField(
          'permissionDate',
          'Permission date',
          kind: QualificationKind.date,
        ),
        QualificationField('sanadNumber', 'Sanad number', maxLength: 100),
        QualificationField(
          'permissionDocument',
          'Permission document',
          kind: QualificationKind.document,
        ),
        QualificationField(
          'sanadDocument',
          'Sanad document',
          kind: QualificationKind.document,
        ),
      ],
      attachments: [
        QualificationAttachment(
          'permissionDocument',
          'Permission document',
          endpoint: 'permission-document',
        ),
        QualificationAttachment(
          'sanadDocument',
          'Sanad document',
          endpoint: 'sanad-document',
        ),
      ],
    ),
  ),
  supremeCourt(
    QualificationSchema(
      path: 'supreme-court',
      label: 'Supreme Court registration',
      titleField: 'scbaMembershipNumber',
      singleton: true,
      verified: true,
      metadata: _verifiedMetadata,
      fields: [
        QualificationField(
          'scbaMembershipNumber',
          'SCBA membership number',
          maxLength: 100,
        ),
        QualificationField('scbaIdNumber', 'SCBA ID number', maxLength: 100),
        QualificationField(
          'scbaMembershipDate',
          'SCBA membership date',
          kind: QualificationKind.date,
        ),
        QualificationField(
          'scbaCertificateDocument',
          'SCBA certificate',
          kind: QualificationKind.document,
        ),
        QualificationField(
          'scbaIdDocument',
          'SCBA ID document',
          kind: QualificationKind.document,
        ),
        QualificationField(
          'appellateDivisionEnrolled',
          'Appellate Division enrolled',
          kind: QualificationKind.boolean,
        ),
        QualificationField(
          'appellateDivisionEnrollmentNumber',
          'Appellate Division enrollment number',
          maxLength: 100,
        ),
        QualificationField(
          'appellateDivisionEnrollmentDate',
          'Appellate Division enrollment date',
          kind: QualificationKind.date,
        ),
        QualificationField(
          'appellateDivisionDocument',
          'Appellate Division document',
          kind: QualificationKind.document,
        ),
        QualificationField(
          'advocateOnRecord',
          'Advocate on record',
          kind: QualificationKind.boolean,
        ),
        QualificationField(
          'advocateOnRecordNumber',
          'Advocate on record number',
          maxLength: 100,
        ),
        QualificationField(
          'seniorAdvocate',
          'Senior advocate',
          kind: QualificationKind.boolean,
        ),
        QualificationField(
          'seniorAdvocateDocument',
          'Senior advocate document',
          kind: QualificationKind.document,
        ),
      ],
      attachments: [
        QualificationAttachment(
          'scbaCertificateDocument',
          'SCBA certificate',
          endpoint: 'scba-certificate',
        ),
        QualificationAttachment(
          'scbaIdDocument',
          'SCBA ID document',
          endpoint: 'scba-id-document',
        ),
        QualificationAttachment(
          'appellateDivisionDocument',
          'Appellate Division document',
          endpoint: 'appellate-division-document',
        ),
        QualificationAttachment(
          'seniorAdvocateDocument',
          'Senior advocate document',
          endpoint: 'senior-advocate-document',
        ),
      ],
    ),
  ),
  barAssociations(
    QualificationSchema(
      path: 'bar-associations',
      label: 'Bar associations',
      titleField: 'associationName',
      verified: true,
      metadata: [..._verifiedMetadata, 'createdAt'],
      fields: [
        QualificationField(
          'associationName',
          'Association name',
          required: true,
          maxLength: 191,
        ),
        QualificationField(
          'membershipNumber',
          'Membership number',
          maxLength: 100,
        ),
        QualificationField(
          'membershipDate',
          'Membership date',
          kind: QualificationKind.date,
        ),
        QualificationField('membershipType', 'Membership type', maxLength: 80),
        QualificationField(
          'membershipStatus',
          'Membership status',
          maxLength: 80,
        ),
        QualificationField(
          'currentCertificateDocument',
          'Current certificate',
          kind: QualificationKind.document,
        ),
        QualificationField(
          'membershipCardDocument',
          'Membership card',
          kind: QualificationKind.document,
        ),
      ],
      attachments: [
        QualificationAttachment(
          'currentCertificateDocument',
          'Current certificate',
        ),
        QualificationAttachment('membershipCardDocument', 'Membership card'),
      ],
    ),
  ),
  credentials(
    QualificationSchema(
      path: 'credentials',
      label: 'Professional credentials',
      titleField: 'credentialName',
      verified: true,
      metadata: [..._verifiedMetadata, 'createdAt'],
      fields: [
        QualificationField(
          'credentialType',
          'Credential type',
          kind: QualificationKind.choice,
          required: true,
          options: _credentialTypes,
        ),
        QualificationField('credentialName', 'Credential name', maxLength: 191),
        QualificationField(
          'credentialNumber',
          'Credential number',
          maxLength: 100,
        ),
        QualificationField(
          'issuingOrganization',
          'Issuing organization',
          maxLength: 191,
        ),
        QualificationField(
          'issueDate',
          'Issue date',
          kind: QualificationKind.date,
        ),
        QualificationField(
          'expiryDate',
          'Expiry date',
          kind: QualificationKind.date,
        ),
        QualificationField(
          'documentUrl',
          'Document',
          kind: QualificationKind.document,
        ),
      ],
      attachments: [
        QualificationAttachment(
          'documentUrl',
          'Credential document',
          endpoint: 'document',
        ),
      ],
    ),
  ),
  education(
    QualificationSchema(
      path: 'educations',
      label: 'Education history',
      titleField: 'degree',
      verified: true,
      metadata: ['verificationStatus', 'rejectionReason', 'createdAt'],
      fields: [
        QualificationField('degree', 'Degree', required: true, maxLength: 150),
        QualificationField('fieldOfStudy', 'Field of study', maxLength: 150),
        QualificationField('institution', 'Institution', maxLength: 191),
        QualificationField('location', 'Location', maxLength: 150),
        QualificationField(
          'startYear',
          'Start year',
          kind: QualificationKind.integer,
          min: 1950,
          max: 2100,
        ),
        QualificationField(
          'endYear',
          'End year',
          kind: QualificationKind.integer,
          min: 1950,
          max: 2100,
        ),
        _description,
        QualificationField(
          'certificateDocument',
          'Certificate',
          kind: QualificationKind.document,
        ),
      ],
      attachments: [
        QualificationAttachment(
          'certificateDocument',
          'Education certificate',
          endpoint: 'certificate',
        ),
      ],
    ),
  ),
  experience(
    QualificationSchema(
      path: 'experiences',
      label: 'Work experience',
      titleField: 'position',
      fields: [
        QualificationField(
          'organization',
          'Organization',
          required: true,
          maxLength: 191,
        ),
        QualificationField(
          'position',
          'Position',
          required: true,
          maxLength: 150,
        ),
        QualificationField('location', 'Location', maxLength: 150),
        _startDate,
        _endDate,
        QualificationField(
          'current',
          'Current position',
          kind: QualificationKind.boolean,
        ),
        _description,
      ],
    ),
  ),
  training(
    QualificationSchema(
      path: 'trainings',
      label: 'Training records',
      titleField: 'trainingName',
      verified: true,
      metadata: ['verificationStatus', 'rejectionReason', 'createdAt'],
      fields: [
        QualificationField(
          'trainingName',
          'Training name',
          required: true,
          maxLength: 191,
        ),
        QualificationField('organization', 'Organization', maxLength: 191),
        QualificationField('trainingType', 'Training type', maxLength: 100),
        _startDate,
        _endDate,
        QualificationField(
          'certificateNumber',
          'Certificate number',
          maxLength: 100,
        ),
        QualificationField(
          'certificateDocument',
          'Certificate',
          kind: QualificationKind.document,
        ),
        _description,
      ],
      attachments: [
        QualificationAttachment(
          'certificateDocument',
          'Training certificate',
          endpoint: 'certificate',
        ),
      ],
    ),
  ),
  memberships(
    QualificationSchema(
      path: 'memberships',
      label: 'Professional memberships',
      titleField: 'organization',
      verified: true,
      metadata: ['verificationStatus', 'createdAt'],
      fields: [
        QualificationField(
          'organization',
          'Organization',
          required: true,
          maxLength: 191,
        ),
        QualificationField('membershipType', 'Membership type', maxLength: 100),
        QualificationField(
          'membershipNumber',
          'Membership number',
          maxLength: 100,
        ),
        _startDate,
        _endDate,
        QualificationField(
          'documentUrl',
          'Document',
          kind: QualificationKind.document,
        ),
      ],
      attachments: [
        QualificationAttachment(
          'documentUrl',
          'Membership document',
          endpoint: 'document',
        ),
      ],
    ),
  ),
  awards(
    QualificationSchema(
      path: 'awards',
      label: 'Awards and recognitions',
      titleField: 'title',
      fields: [
        QualificationField(
          'title',
          'Award title',
          required: true,
          maxLength: 191,
        ),
        QualificationField('organization', 'Organization', maxLength: 191),
        QualificationField(
          'awardYear',
          'Award year',
          kind: QualificationKind.integer,
        ),
        _description,
        QualificationField(
          'documentUrl',
          'Document',
          kind: QualificationKind.document,
        ),
      ],
      attachments: [
        QualificationAttachment(
          'documentUrl',
          'Award document',
          endpoint: 'document',
        ),
      ],
    ),
  ),
  publications(
    QualificationSchema(
      path: 'publications',
      label: 'Publications',
      titleField: 'title',
      fields: [
        QualificationField('title', 'Title', required: true, maxLength: 255),
        QualificationField('publication', 'Publication', maxLength: 191),
        QualificationField(
          'publicationDate',
          'Publication date',
          kind: QualificationKind.date,
        ),
        QualificationField('url', 'Publication URL', maxLength: 500),
        _description,
        QualificationField(
          'documentUrl',
          'Document',
          kind: QualificationKind.document,
        ),
      ],
      attachments: [
        QualificationAttachment('documentUrl', 'Publication document'),
      ],
    ),
  );

  const QualificationResource(this.schema);
  final QualificationSchema schema;
}
