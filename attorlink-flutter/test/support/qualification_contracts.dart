import 'dart:async';
import 'dart:convert';

import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_client.dart';
import 'package:attorlink_flutter/core/network/api_exception.dart';
import 'package:attorlink_flutter/core/network/http_transport.dart';
import 'package:attorlink_flutter/features/auth/domain/auth_models.dart';
import 'package:attorlink_flutter/features/lawyer/data/lawyer_repository.dart';
import 'package:attorlink_flutter/features/lawyer/domain/lawyer_document.dart';
import 'package:attorlink_flutter/features/lawyer/qualifications/data/qualifications_repository.dart';
import 'package:attorlink_flutter/features/lawyer/qualifications/domain/qualification_record.dart';
import 'package:attorlink_flutter/features/lawyer/qualifications/domain/qualification_schema.dart';

import 'lawyer_contracts.dart' show lawyerPdfBytes;

// Independent endpoint/DTO inventory taken from the inspected Java contracts.
const qualificationInventory = <QualificationResource, (String, List<String>)>{
  QualificationResource.highCourt: (
    'high-court',
    [
      'permissionNumber',
      'permissionDate',
      'sanadNumber',
      'permissionDocument',
      'sanadDocument',
    ],
  ),
  QualificationResource.supremeCourt: (
    'supreme-court',
    [
      'scbaMembershipNumber',
      'scbaIdNumber',
      'scbaMembershipDate',
      'scbaCertificateDocument',
      'scbaIdDocument',
      'appellateDivisionEnrolled',
      'appellateDivisionEnrollmentNumber',
      'appellateDivisionEnrollmentDate',
      'appellateDivisionDocument',
      'advocateOnRecord',
      'advocateOnRecordNumber',
      'seniorAdvocate',
      'seniorAdvocateDocument',
    ],
  ),
  QualificationResource.barAssociations: (
    'bar-associations',
    [
      'associationName',
      'membershipNumber',
      'membershipDate',
      'membershipType',
      'membershipStatus',
      'currentCertificateDocument',
      'membershipCardDocument',
    ],
  ),
  QualificationResource.credentials: (
    'credentials',
    [
      'credentialType',
      'credentialName',
      'credentialNumber',
      'issuingOrganization',
      'issueDate',
      'expiryDate',
      'documentUrl',
    ],
  ),
  QualificationResource.education: (
    'educations',
    [
      'degree',
      'fieldOfStudy',
      'institution',
      'location',
      'startYear',
      'endYear',
      'description',
      'certificateDocument',
    ],
  ),
  QualificationResource.experience: (
    'experiences',
    [
      'organization',
      'position',
      'location',
      'startDate',
      'endDate',
      'current',
      'description',
    ],
  ),
  QualificationResource.training: (
    'trainings',
    [
      'trainingName',
      'organization',
      'trainingType',
      'startDate',
      'endDate',
      'certificateNumber',
      'certificateDocument',
      'description',
    ],
  ),
  QualificationResource.memberships: (
    'memberships',
    [
      'organization',
      'membershipType',
      'membershipNumber',
      'startDate',
      'endDate',
      'documentUrl',
    ],
  ),
  QualificationResource.awards: (
    'awards',
    ['title', 'organization', 'awardYear', 'description', 'documentUrl'],
  ),
  QualificationResource.publications: (
    'publications',
    [
      'title',
      'publication',
      'publicationDate',
      'url',
      'description',
      'documentUrl',
    ],
  ),
};
const _single = {
  QualificationResource.highCourt,
  QualificationResource.supremeCourt,
};
const _reviewed = {
  QualificationResource.highCourt,
  QualificationResource.supremeCourt,
  QualificationResource.barAssociations,
  QualificationResource.credentials,
  QualificationResource.education,
  QualificationResource.training,
  QualificationResource.memberships,
};
const attachmentInventory = <QualificationResource, Map<String, String?>>{
  QualificationResource.highCourt: {
    'permissionDocument': 'permission-document',
    'sanadDocument': 'sanad-document',
  },
  QualificationResource.supremeCourt: {
    'scbaCertificateDocument': 'scba-certificate',
    'scbaIdDocument': 'scba-id-document',
    'appellateDivisionDocument': 'appellate-division-document',
    'seniorAdvocateDocument': 'senior-advocate-document',
  },
  QualificationResource.barAssociations: {
    'currentCertificateDocument': null,
    'membershipCardDocument': null,
  },
  QualificationResource.credentials: {'documentUrl': 'document'},
  QualificationResource.education: {'certificateDocument': 'certificate'},
  QualificationResource.training: {'certificateDocument': 'certificate'},
  QualificationResource.memberships: {'documentUrl': 'document'},
  QualificationResource.awards: {'documentUrl': 'document'},
  QualificationResource.publications: {'documentUrl': null},
};
Map<String, Object?> qualificationValues(
  QualificationResource resource,
) => switch (resource) {
  QualificationResource.highCourt => {'permissionNumber': 'HC-1'},
  QualificationResource.supremeCourt => {
    'scbaMembershipNumber': 'SC-1',
    'appellateDivisionEnrolled': true,
    'advocateOnRecord': false,
    'seniorAdvocate': false,
  },
  QualificationResource.barAssociations => {'associationName': 'District Bar'},
  QualificationResource.credentials => {
    'credentialType': 'NID',
    'credentialName': 'National identity',
  },
  QualificationResource.education => {
    'degree': 'LL.B',
    'startYear': 1950,
    'endYear': 2100,
  },
  QualificationResource.experience => {
    'organization': 'Chambers',
    'position': 'Advocate',
    'current': false,
  },
  QualificationResource.training => {'trainingName': 'Professional training'},
  QualificationResource.memberships => {
    'organization': 'Professional association',
  },
  QualificationResource.awards => {'title': 'Recognition', 'awardYear': -1},
  QualificationResource.publications => {
    'title': 'Legal article',
    'url': 'https://example.test/article',
  },
};
Map<String, Object?> qualificationJson(
  QualificationResource resource, {
  int id = 1,
}) => {
  'id': id,
  ...qualificationValues(resource),
  if (_reviewed.contains(resource)) 'verificationStatus': 'PENDING',
  if (resource == QualificationResource.credentials)
    'documentUrl': 'https://images.example.test/old.pdf',
};
TransportResponse qualificationOk(Object? data) => TransportResponse(
  statusCode: 200,
  body: jsonEncode({'success': true, 'message': 'Success', 'data': data}),
);
TransportResponse _failure(int status) => TransportResponse(
  statusCode: status,
  body: jsonEncode({
    'success': false,
    'message': 'Backend rejected operation',
    'data': null,
  }),
);
void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<ApiException> _fails(Future<Object?> future) async {
  try {
    await future;
  } on ApiException catch (error) {
    return error;
  }
  throw StateError('Expected API failure');
}

Map<String, dynamic> _body(TransportRequest r) =>
    jsonDecode(r.body!) as Map<String, dynamic>;

class QualificationTestTransport implements HttpTransport {
  final requests = <TransportRequest>[];
  late FutureOr<TransportResponse> Function(TransportRequest) respond;
  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    return await respond(request);
  }

  @override
  void close() {}
}

class QualificationTestFixture {
  QualificationTestFixture(this.resource) {
    record = qualificationJson(resource);
    transport.respond = server;
    api = ApiClient(
      config: ApiConfig(baseUrl: Uri.parse('https://api.example.test/api/v1/')),
      transport: transport,
      accessTokenProvider: () => 'test-access',
    );
    lawyer = LawyerRepository(api, ownerId: 7, currentUser: () => user);
    repository = QualificationsRepository(lawyer);
  }
  final QualificationResource resource;
  AuthUser? user = const AuthUser(
    id: 7,
    email: 'lawyer@example.test',
    role: UserRole.lawyer,
    status: UserStatus.active,
  );
  Map<String, Object?>? record;
  final transport = QualificationTestTransport();
  late final ApiClient api;
  late final LawyerRepository lawyer;
  late final QualificationsRepository repository;
  TransportResponse server(TransportRequest r) {
    if (r.uri.path == '/api/v1/files/upload') {
      return qualificationOk({
        'url': 'https://images.example.test/new.pdf',
        'publicId': 'new-file',
        'resourceType': 'raw',
      });
    }
    final base = '/api/v1/lawyer/${qualificationInventory[resource]!.$1}';
    if (r.method == 'GET' && r.uri.path == base) {
      return qualificationOk(
        _single.contains(resource) ? record : [if (record != null) record],
      );
    }
    if ((r.method == 'PUT' &&
            (r.uri.path == '$base/1' || r.uri.path == base)) ||
        (r.method == 'POST' && r.uri.path == base)) {
      record = {
        'id': 1,
        ..._body(r),
        if (_reviewed.contains(resource)) 'verificationStatus': 'PENDING',
      };
      return qualificationOk(record);
    }
    if (r.method == 'DELETE' && r.uri.path == '$base/1') {
      record = null;
      return qualificationOk(null);
    }
    for (final entry
        in attachmentInventory[resource]?.entries ??
            <MapEntry<String, String?>>[]) {
      if (entry.value == null) continue;
      final path =
          '$base${_single.contains(resource) ? '' : '/1'}/${entry.value}';
      if (r.uri.path != path) continue;
      if (r.method == 'POST') {
        record![entry.key] = 'https://images.example.test/new.pdf';
        return qualificationOk({
          'url': record![entry.key],
          'publicId': 'new-file',
        });
      }
      if (r.method == 'DELETE') {
        record![entry.key] = null;
        return qualificationOk({'url': null, 'publicId': null});
      }
    }
    throw StateError('Unexpected endpoint ${r.method} ${r.uri.path}');
  }

  void dispose() => api.close();
}

final qualificationContractCases = <String, Future<void> Function()>{
  for (final resource in QualificationResource.values)
    '${qualificationInventory[resource]!.$1}: exact read detail create update and supported delete contracts':
        () async {
          final f = QualificationTestFixture(resource);
          try {
            final base =
                '/api/v1/lawyer/${qualificationInventory[resource]!.$1}';
            final records = await f.repository.list(resource);
            _check(records.single.id == 1, 'Record decoding failed');
            await f.repository.detail(resource, 1);
            _check(
              f.transport.requests.every(
                (r) => r.method == 'GET' && r.uri.path == base,
              ),
              'Invented detail GET endpoint',
            );
            await f.repository.save(resource, {
              ...qualificationValues(resource),
              'verificationStatus': 'VERIFIED',
              'id': 99,
            });
            final create = f.transport.requests.last;
            _check(
              create.method == (_single.contains(resource) ? 'PUT' : 'POST') &&
                  create.uri.path == base,
              'Wrong create/upsert route',
            );
            final body = _body(create);
            final expected = qualificationInventory[resource]!.$2.toSet();
            _check(
              body.length == expected.length &&
                  body.keys.toSet().containsAll(expected) &&
                  !body.containsKey('id') &&
                  !body.containsKey('verificationStatus'),
              'Incorrect DTO fields or forged metadata',
            );
            await f.repository.save(
              resource,
              qualificationValues(resource),
              id: 1,
            );
            _check(
              f.transport.requests.last.method == 'PUT' &&
                  f.transport.requests.last.uri.path ==
                      (_single.contains(resource) ? base : '$base/1'),
              'Wrong update route',
            );
            if (_single.contains(resource)) {
              final count = f.transport.requests.length;
              _check(
                (await _fails(f.repository.delete(resource, 1))).kind ==
                        ApiErrorKind.unsupported &&
                    count == f.transport.requests.length,
                'Invented singleton deletion',
              );
            } else {
              await f.repository.delete(resource, 1);
              _check(
                f.transport.requests.last.method == 'DELETE' &&
                    f.transport.requests.last.uri.path == '$base/1',
                'Wrong delete route',
              );
            }
            _check(
              f.transport.requests.every(
                (r) => r.headers['Authorization'] == 'Bearer test-access',
              ),
              'Unauthenticated qualification request',
            );
          } finally {
            f.dispose();
          }
        },
  for (final resource in attachmentInventory.keys)
    '${qualificationInventory[resource]!.$1}: exact document upload removal and link contracts': () async {
      final f = QualificationTestFixture(resource);
      try {
        final base = '/api/v1/lawyer/${qualificationInventory[resource]!.$1}';
        final file = LawyerDocument.fromBytes('record.pdf', lawyerPdfBytes);
        for (final attachment in attachmentInventory[resource]!.entries) {
          final start = f.transport.requests.length;
          await f.repository.upload(resource, 1, attachment.key, file);
          final requests = f.transport.requests.skip(start).toList();
          final upload = requests.singleWhere((r) => r.method == 'POST');
          final expected = attachment.value == null
              ? '/api/v1/files/upload'
              : '$base${_single.contains(resource) ? '' : '/1'}/${attachment.value}';
          _check(
            upload.uri.path == expected &&
                upload.body == null &&
                upload.bodyBytes != null &&
                latin1
                    .decode(upload.bodyBytes!)
                    .contains('Content-Type: application/pdf\r\n'),
            'Wrong binary upload contract',
          );
          if (attachment.value == null) {
            _check(
              upload.uri.queryParameters['type'] == 'DOCUMENT',
              'Generic upload used image mode',
            );
            final link = requests.last;
            _check(
              link.method == 'PUT' &&
                  _body(link)[attachment.key] ==
                      'https://images.example.test/new.pdf',
              'Uploaded URL not saved to DTO',
            );
          }
          await f.repository.removeDocument(resource, 1, attachment.key);
          final removal = f.transport.requests.last;
          _check(
            removal.method == (attachment.value == null ? 'PUT' : 'DELETE'),
            'Incorrect document removal method',
          );
          if (attachment.value == null) {
            _check(_body(removal)[attachment.key] == null, 'Link not cleared');
          }
          _check(
            f.record![attachment.key] == null,
            'Backend fixture link remained',
          );
        }
        _check(
          !f.transport.requests.any(
            (r) => r.method == 'DELETE' && r.uri.path == '/api/v1/files',
          ),
          'Unowned generic asset deletion attempted',
        );
      } finally {
        f.dispose();
      }
    },
  'null singleton empty collection and missing detail are distinct from failures':
      () async {
        for (final resource in QualificationResource.values) {
          final f = QualificationTestFixture(resource);
          try {
            f.record = null;
            _check(
              (await f.repository.list(resource)).isEmpty,
              'Empty records invented',
            );
            _check(
              (await _fails(f.repository.detail(resource, 1))).kind ==
                  ApiErrorKind.notFound,
              'Missing detail invented',
            );
            f.transport.respond = (_) => _failure(403);
            _check(
              (await _fails(f.repository.list(resource))).kind ==
                  ApiErrorKind.forbidden,
              'Forbidden hidden as empty',
            );
          } finally {
            f.dispose();
          }
        }
      },
  'required fields and credential types match DTOs before mutations': () async {
    const required = {
      QualificationResource.barAssociations: ['associationName'],
      QualificationResource.credentials: ['credentialType'],
      QualificationResource.education: ['degree'],
      QualificationResource.experience: ['organization', 'position'],
      QualificationResource.training: ['trainingName'],
      QualificationResource.memberships: ['organization'],
      QualificationResource.awards: ['title'],
      QualificationResource.publications: ['title'],
    };
    for (final entry in required.entries) {
      final f = QualificationTestFixture(entry.key);
      try {
        for (final key in entry.value) {
          final values = qualificationValues(entry.key)..[key] = null;
          _check(
            (await _fails(f.repository.save(entry.key, values))).fieldErrors
                .containsKey(key),
            'Missing required $key accepted',
          );
        }
        _check(f.transport.requests.isEmpty, 'Invalid record sent to server');
      } finally {
        f.dispose();
      }
    }
    final field = QualificationResource.credentials.schema.fields.first;
    _check(
      field.options.join(',') == 'BAR_COUNCIL_SANAD,BAR_COUNCIL_ID,BAR_COUNCIL_ENROLLMENT,GREEN_BOOK,NID,PASSPORT,OTHER',
      'Credential enum mismatch',
    );
    _check(field.validate('CERTIFIED') != null, 'Invented credential accepted');
  },
  'education years award integers dates and free membership status follow actual constraints':
      () async {
        final education = QualificationResource.education.schema.fields;
        _check(
          education.firstWhere((f) => f.key == 'startYear').validate('1949') !=
                  null &&
              education
                      .firstWhere((f) => f.key == 'endYear')
                      .validate('2101') !=
                  null,
          'Education limits missing',
        );
        _check(
          education.firstWhere((f) => f.key == 'startYear').validate('1950') ==
              null,
          '1950 rejected',
        );
        final awardYear = QualificationResource.awards.schema.fields.firstWhere(
          (f) => f.key == 'awardYear',
        );
        _check(
          awardYear.validate('-1') == null &&
              awardYear.validate('3000') == null &&
              awardYear.validate('2147483648') != null,
          'Invented award year range',
        );
        for (final resource in QualificationResource.values) {
          for (final field in resource.schema.informationFields) {
            if (field.maxLength != null) {
              _check(
                field.validate('x' * (field.maxLength! + 1)) != null,
                'Length limit missing',
              );
            }
            if (field.kind == QualificationKind.date) {
              _check(
                field.validate('2999-01-01') == null &&
                    field.validate('2025-02-29') != null,
                'Incorrect date rule',
              );
            }
          }
        }
        final membershipStatus = QualificationResource
            .barAssociations
            .schema
            .fields
            .firstWhere((f) => f.key == 'membershipStatus');
        _check(
          membershipStatus.validate('Custom association status') == null,
          'Invented membership status enum',
        );
      },
  'experience current flag clears end date and only experience enforces date ordering':
      () async {
        final f = QualificationTestFixture(QualificationResource.experience);
        try {
          final values = {
            ...qualificationValues(f.resource),
            'startDate': '2026-01-01',
            'endDate': '2025-01-01',
          };
          _check(
            (await _fails(f.repository.save(f.resource, values))).fieldErrors
                .containsKey('endDate'),
            'Invalid experience order allowed',
          );
          await f.repository.save(f.resource, {...values, 'current': true});
          _check(
            _body(f.transport.requests.last)['endDate'] == null &&
                _body(f.transport.requests.last)['current'] == true,
            'Current experience end date retained',
          );
          _check(
            validateQualification(QualificationResource.training, {
              'trainingName': 'Training',
              'startDate': '2026-01-01',
              'endDate': '2025-01-01',
            }).isEmpty,
            'Invented training order restriction',
          );
        } finally {
          f.dispose();
        }
      },
  'information edits preserve latest document URLs and do not submit verification metadata':
      () async {
        for (final resource in attachmentInventory.keys) {
          final f = QualificationTestFixture(resource);
          try {
            for (final field in attachmentInventory[resource]!.keys) {
              f.record![field] =
                  'https://images.example.test/latest-$field.pdf';
            }
            await f.repository.saveInformation(resource, {
              ...qualificationValues(resource),
              'verificationStatus': 'VERIFIED',
            }, id: 1);
            final body = _body(f.transport.requests.last);
            for (final field in attachmentInventory[resource]!.keys) {
              _check(
                body[field] == 'https://images.example.test/latest-$field.pdf',
                'Existing document overwritten',
              );
            }
            _check(
              !body.containsKey('verificationStatus'),
              'Record status forged',
            );
          } finally {
            f.dispose();
          }
        }
      },
  'generic upload partial failure keeps uploaded URL for link-only retry':
      () async {
        final f = QualificationTestFixture(QualificationResource.publications);
        try {
          var rejectSave = true;
          f.transport.respond = (r) =>
              r.method == 'PUT' && rejectSave ? _failure(403) : f.server(r);
          final error = await _fails(
            f.repository.upload(
              f.resource,
              1,
              'documentUrl',
              LawyerDocument.fromBytes('p.pdf', lawyerPdfBytes),
            ),
          );
          _check(
            error is UnlinkedQualificationUpload &&
                error.kind == ApiErrorKind.forbidden,
            'Partial upload or forbidden classification lost',
          );
          final partial = error as UnlinkedQualificationUpload;
          _check(
            partial.uploaded.url == 'https://images.example.test/new.pdf' &&
                partial.uploaded.publicId == 'new-file',
            'Uploaded asset lost',
          );
          rejectSave = false;
          await f.repository.linkDocument(
            f.resource,
            1,
            'documentUrl',
            partial.uploaded.url,
          );
          _check(
            f.transport.requests
                        .where((r) => r.uri.path == '/api/v1/files/upload')
                        .length ==
                    1 &&
                f.record!['documentUrl'] == partial.uploaded.url,
            'Link retry uploaded twice',
          );
        } finally {
          f.dispose();
        }
      },
  'lawyer role status owner and stale-response guards cover all resources':
      () async {
        for (final resource in QualificationResource.values) {
          for (final user in <AuthUser?>[
            null,
            const AuthUser(
              id: 7,
              email: 'x',
              role: UserRole.client,
              status: UserStatus.active,
            ),
            const AuthUser(
              id: 7,
              email: 'x',
              role: UserRole.admin,
              status: UserStatus.active,
            ),
            const AuthUser(
              id: 7,
              email: 'x',
              role: UserRole.lawyer,
              status: UserStatus.suspended,
            ),
            const AuthUser(
              id: 8,
              email: 'x',
              role: UserRole.lawyer,
              status: UserStatus.active,
            ),
          ]) {
            final f = QualificationTestFixture(resource);
            try {
              f.user = user;
              for (final action in <Future<Object?> Function()>[
                () => f.repository.list(resource),
                () => f.repository.detail(resource, 1),
                () =>
                    f.repository.save(resource, qualificationValues(resource)),
                () => f.repository.delete(resource, 1),
              ]) {
                _check(
                  (await _fails(action())).kind == ApiErrorKind.forbidden,
                  'Qualification role/owner guard bypassed',
                );
              }
              _check(
                f.transport.requests.isEmpty,
                'Forbidden operation sent request',
              );
            } finally {
              f.dispose();
            }
          }
          final f = QualificationTestFixture(resource);
          try {
            f.transport.respond = (r) {
              f.user = null;
              return f.server(r);
            };
            _check(
              (await _fails(f.repository.list(resource))).kind ==
                  ApiErrorKind.forbidden,
              'Stale records disclosed',
            );
          } finally {
            f.dispose();
          }
        }
      },
  'malformed responses and mutation failures never become successful records':
      () async {
        final f = QualificationTestFixture(QualificationResource.education);
        try {
          f.transport.respond = (_) => qualificationOk(null);
          _check(
            (await _fails(f.repository.list(f.resource))).kind ==
                ApiErrorKind.invalidResponse,
            'Null collection accepted',
          );
          f.transport.respond = (_) => qualificationOk([
            {
              ...qualificationJson(f.resource),
              'verificationStatus': 'APPROVED',
            },
          ]);
          _check(
            (await _fails(f.repository.list(f.resource))).kind ==
                ApiErrorKind.invalidResponse,
            'Invented status accepted',
          );
          f.transport.respond = (_) => throw const ApiException(
            kind: ApiErrorKind.timeout,
            message: 'Reply lost',
          );
          final count = f.transport.requests.length;
          await _fails(
            f.repository.save(f.resource, qualificationValues(f.resource)),
          );
          _check(
            f.transport.requests.length == count + 1,
            'Ambiguous record creation retried',
          );
        } finally {
          f.dispose();
        }
      },
};
