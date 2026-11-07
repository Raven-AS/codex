import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_client.dart';
import 'package:attorlink_flutter/core/network/api_exception.dart';
import 'package:attorlink_flutter/core/network/http_transport.dart';
import 'package:attorlink_flutter/features/auth/domain/auth_models.dart';
import 'package:attorlink_flutter/features/client/domain/client_photo.dart';
import 'package:attorlink_flutter/features/lawyer/data/lawyer_repository.dart';
import 'package:attorlink_flutter/features/lawyer/domain/lawyer_document.dart';
import 'package:attorlink_flutter/features/lawyer/domain/lawyer_models.dart';
import 'package:attorlink_flutter/features/lawyer/domain/lawyer_validation.dart';

Map<String, Object?> lawyerProfileJson({
  String status = 'DRAFT',
  int userId = 7,
  String? reason,
}) => {
  'id': 11,
  'userId': userId,
  'firstName': 'Asha',
  'middleName': null,
  'lastName': null,
  'fullName': 'Asha',
  'profileStatus': status,
  'barRegistrationNumber': 'BAR-123',
  'yearsOfExperience': null,
  'profilePhoto': null,
  'coverPhoto': null,
  'rejectionReason': reason,
};
Map<String, Object?> councilRecordJson({
  String status = 'PENDING',
  String? reason,
}) => {
  'id': 21,
  'verificationStatus': status,
  'enrollmentNumber': null,
  'sanadNumber': null,
  'enrollmentDate': null,
  'sanadIssueDate': null,
  'greenBookNumber': null,
  'barCouncilIdNumber': null,
  'identityCardDocument': null,
  'sanadDocument': 'https://images.example.test/sanad.pdf',
  'greenBookDocument': null,
  'verifiedAt': null,
  'verifiedBy': null,
  'rejectionReason': reason,
};
TransportResponse lawyerOk(Object? data) => TransportResponse(
  statusCode: 200,
  body: jsonEncode({'success': true, 'message': 'Success', 'data': data}),
);
TransportResponse lawyerFailure(int status) => TransportResponse(
  statusCode: status,
  body: jsonEncode({
    'success': false,
    'message': 'Backend rejected this operation',
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
  throw StateError('Expected backend/API failure');
}

Map<String, dynamic> _body(TransportRequest r) =>
    jsonDecode(r.body!) as Map<String, dynamic>;
final lawyerPngBytes = Uint8List.fromList([
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  255,
]);
final lawyerPdfBytes = Uint8List.fromList(
  utf8.encode('%PDF-1.4\nexample document bytes'),
);

class LawyerTestTransport implements HttpTransport {
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

class LawyerTestFixture {
  LawyerTestFixture() {
    transport.respond = (r) => r.uri.path.endsWith('/bar-council')
        ? lawyerOk(councilRecordJson())
        : lawyerOk(lawyerProfileJson());
    api = ApiClient(
      config: ApiConfig(baseUrl: Uri.parse('https://api.example.test/api/v1/')),
      transport: transport,
      accessTokenProvider: () => 'test-lawyer-access',
    );
    repository = LawyerRepository(api, currentUser: () => user, ownerId: 7);
  }
  AuthUser? user = const AuthUser(
    id: 7,
    email: 'lawyer@example.test',
    role: UserRole.lawyer,
    status: UserStatus.active,
  );
  final transport = LawyerTestTransport();
  late final ApiClient api;
  late final LawyerRepository repository;
  void dispose() => api.close();
}

final lawyerContractCases = <String, Future<void> Function()>{
  'lawyer snapshot uses authenticated own profile and Bar Council endpoints':
      () async {
        final f = LawyerTestFixture();
        try {
          final snapshot = await f.repository.snapshot();
          _check(
            snapshot.profile.userId == 7 &&
                snapshot.profile.status == 'DRAFT' &&
                snapshot.barCouncil!.status == 'PENDING',
            'Wrong snapshot',
          );
          _check(
            f.transport.requests.map((r) => r.uri.path).toSet().containsAll([
              '/api/v1/lawyer/profile',
              '/api/v1/lawyer/bar-council',
            ]),
            'Wrong GET routes',
          );
          _check(
            f.transport.requests.every(
              (r) =>
                  r.method == 'GET' &&
                  r.headers['Authorization'] == 'Bearer test-lawyer-access',
            ),
            'Missing lawyer authentication',
          );
        } finally {
          f.dispose();
        }
      },
  'profile partial PUT preserves omitted fields and uses exact DTO names':
      () async {
        final f = LawyerTestFixture();
        try {
          final profile = await f.repository.saveProfile({
            'professionalTitle': 'Advocate',
            'yearsOfExperience': 12,
            'dateOfBirth': null,
            'profileStatus': 'VERIFIED',
            'userId': 99,
          });
          final r = f.transport.requests.single;
          final body = _body(r);
          _check(
            r.method == 'PUT' &&
                r.uri.path == '/api/v1/lawyer/profile' &&
                body.length == 3 &&
                body['professionalTitle'] == 'Advocate' &&
                body['yearsOfExperience'] == 12 &&
                body.containsKey('dateOfBirth'),
            'Wrong partial profile contract',
          );
          _check(
            !body.containsKey('firstName') &&
                !body.containsKey('profileStatus') &&
                profile.status == 'DRAFT',
            'Profile edit erased fields or invented verification',
          );
        } finally {
          f.dispose();
        }
      },
  'wrong profile owner and malformed fields fail response decoding': () async {
    final f = LawyerTestFixture();
    try {
      f.transport.respond = (_) => lawyerOk(lawyerProfileJson(userId: 99));
      _check(
        (await _fails(f.repository.profile())).kind ==
            ApiErrorKind.invalidResponse,
        'Wrong owner accepted',
      );
      f.transport.respond = (_) =>
          lawyerOk({...lawyerProfileJson(), 'yearsOfExperience': '12'});
      _check(
        (await _fails(f.repository.profile())).kind ==
            ApiErrorKind.invalidResponse,
        'Malformed experience accepted',
      );
    } finally {
      f.dispose();
    }
  },
  'missing Bar Council record is null but HTTP errors are never treated as missing':
      () async {
        final f = LawyerTestFixture();
        try {
          f.transport.respond = (_) => lawyerOk(null);
          _check(
            await f.repository.barCouncil() == null,
            'Missing record fabricated',
          );
          f.transport.respond = (_) => lawyerFailure(404);
          _check(
            (await _fails(f.repository.barCouncil())).kind ==
                ApiErrorKind.notFound,
            '404 hidden as empty record',
          );
        } finally {
          f.dispose();
        }
      },
  'Bar Council upsert sends all nine replacement fields and preserves supplied documents':
      () async {
        final f = LawyerTestFixture();
        try {
          f.transport.respond = (r) =>
              lawyerOk({...councilRecordJson(), ..._body(r)});
          final saved = await f.repository.saveBarCouncil({
            'enrollmentNumber': 'EN-1',
            'enrollmentDate': '2030-01-01',
            'sanadDocument': 'https://images.example.test/saved.pdf',
            'verificationStatus': 'VERIFIED',
          });
          final r = f.transport.requests.single;
          final body = _body(r);
          _check(
            r.method == 'PUT' &&
                r.uri.path == '/api/v1/lawyer/bar-council' &&
                body.length == 9 &&
                body['identityCardDocument'] == null &&
                body['sanadDocument'] ==
                    'https://images.example.test/saved.pdf',
            'Wrong Bar Council replacement',
          );
          _check(
            !body.containsKey('verificationStatus') &&
                saved.status == 'PENDING',
            'Forged record verification',
          );
        } finally {
          f.dispose();
        }
      },
  'checklist requires saved nonblank first name registration and record only':
      () async {
        final profile = LawyerProfile.fromJson(lawyerProfileJson());
        final record = BarCouncilRecord.fromJson(councilRecordJson());
        _check(
          LawyerSnapshot(profile, record).canSubmit,
          'Optional documents incorrectly required',
        );
        _check(
          !LawyerSnapshot(profile, null).canSubmit,
          'Unsaved Bar Council accepted',
        );
        for (final key in ['firstName', 'barRegistrationNumber']) {
          final missing = LawyerProfile.fromJson({
            ...lawyerProfileJson(),
            key: '   ',
          });
          _check(
            !LawyerSnapshot(missing, record).canSubmit,
            'Blank $key accepted',
          );
        }
      },
  'checklist mirrors exact backend status restrictions without invented statuses':
      () async {
        final record = BarCouncilRecord.fromJson(councilRecordJson());
        for (final status in LawyerStatuses.profile) {
          final snapshot = LawyerSnapshot(
            LawyerProfile.fromJson(lawyerProfileJson(status: status)),
            record,
          );
          _check(
            snapshot.canSubmit ==
                !{'SUBMITTED', 'IN_REVIEW', 'VERIFIED'}.contains(status),
            'Incorrect local restriction for $status',
          );
        }
        final f = LawyerTestFixture();
        try {
          f.transport.respond = (_) =>
              lawyerOk(lawyerProfileJson(status: 'APPROVED'));
          _check(
            (await _fails(f.repository.profile())).kind ==
                ApiErrorKind.invalidResponse,
            'Invented verification status accepted',
          );
        } finally {
          f.dispose();
        }
      },
  'submission calls actual POST without body and trusts returned status and message':
      () async {
        final f = LawyerTestFixture();
        try {
          f.transport.respond = (_) => lawyerOk({
            'lawyerProfileId': 11,
            'profileStatus': 'SUBMITTED',
            'message': 'Profile submitted for admin verification.',
          });
          final result = await f.repository.submit(11);
          final r = f.transport.requests.single;
          _check(
            r.method == 'POST' &&
                r.uri.path == '/api/v1/lawyer/profile/submit' &&
                r.body == null &&
                r.bodyBytes == null,
            'Wrong submission contract',
          );
          _check(
            result.profileId == 11 &&
                result.status == 'SUBMITTED' &&
                result.message.contains('admin verification'),
            'Submission was treated as approval',
          );
        } finally {
          f.dispose();
        }
      },
  'submission server rejection and mismatched response never simulate verification':
      () async {
        final f = LawyerTestFixture();
        try {
          f.transport.respond = (_) => lawyerFailure(400);
          _check(
            (await _fails(f.repository.submit(11))).message ==
                'Backend rejected this operation',
            'Backend rejection hidden',
          );
          f.transport.respond = (_) => lawyerOk({
            'lawyerProfileId': 999,
            'profileStatus': 'SUBMITTED',
            'message': 'Submitted',
          });
          _check(
            (await _fails(f.repository.submit(11))).kind ==
                ApiErrorKind.invalidResponse,
            'Wrong submitted profile accepted',
          );
        } finally {
          f.dispose();
        }
      },
  'submission network failure is not automatically retried': () async {
    final f = LawyerTestFixture();
    try {
      f.transport.respond = (_) => throw const ApiException(
        kind: ApiErrorKind.timeout,
        message: 'Reply lost',
      );
      await _fails(f.repository.submit(11));
      _check(f.transport.requests.length == 1, 'Ambiguous submission retried');
    } finally {
      f.dispose();
    }
  },
  'profile and Bar Council rejection feedback and all real statuses survive decoding':
      () async {
        for (final status in LawyerStatuses.profile) {
          final profile = LawyerProfile.fromJson(
            lawyerProfileJson(
              status: status,
              reason: 'Update enrollment details.',
            ),
          );
          _check(
            profile.status == status &&
                profile.text('rejectionReason') == 'Update enrollment details.',
            'Profile feedback lost',
          );
        }
        for (final status in LawyerStatuses.record) {
          final record = BarCouncilRecord.fromJson(
            councilRecordJson(status: status, reason: 'Document unreadable.'),
          );
          _check(
            record.status == status &&
                record.text('rejectionReason') == 'Document unreadable.',
            'Record feedback lost',
          );
        }
      },
  'profile and cover photo upload/removal use distinct real endpoints':
      () async {
        final f = LawyerTestFixture();
        try {
          f.transport.respond = (r) => lawyerOk({
            'url': r.method == 'DELETE'
                ? null
                : 'https://images.example.test/photo.png',
            'publicId': r.method == 'DELETE' ? null : 'lawyer/photo',
          });
          final photo = ClientPhoto.fromBytes('photo.png', lawyerPngBytes);
          for (final cover in [false, true]) {
            final uploaded = await f.repository.uploadPhoto(
              photo,
              cover: cover,
            );
            final upload = f.transport.requests.last;
            final removed = await f.repository.removePhoto(cover: cover);
            final remove = f.transport.requests.last;
            final path =
                '/api/v1/lawyer/profile/${cover ? 'cover-photo' : 'photo'}';
            _check(
              upload.uri.path == path &&
                  upload.method == 'POST' &&
                  upload.bodyBytes != null &&
                  upload.body == null &&
                  uploaded.url != null,
              'Wrong image upload',
            );
            _check(
              remove.uri.path == path &&
                  remove.method == 'DELETE' &&
                  removed.url == null &&
                  removed.publicId == null,
              'Wrong image removal',
            );
          }
        } finally {
          f.dispose();
        }
      },
  'all three Bar Council documents upload as binary file parts and remove separately':
      () async {
        final f = LawyerTestFixture();
        try {
          f.transport.respond = (r) => lawyerOk({
            'url': r.method == 'DELETE'
                ? null
                : 'https://images.example.test/document.pdf',
            'publicId': r.method == 'DELETE' ? null : 'council/doc',
          });
          final document = LawyerDocument.fromBytes(
            'unsafe"\r\nfile.pdf',
            lawyerPdfBytes,
          );
          for (final target in CouncilDocument.values) {
            await f.repository.uploadDocument(target, document);
            final upload = f.transport.requests.last;
            final text = latin1.decode(upload.bodyBytes!);
            _check(
              upload.uri.path == '/api/v1/lawyer/bar-council/${target.path}' &&
                  upload.method == 'POST' &&
                  text.contains('name="file"; filename="unsafe___file.pdf"') &&
                  text.contains('Content-Type: application/pdf\r\n'),
              'Wrong document multipart contract',
            );
            _check(
              text.contains('%PDF-1.4\nexample document bytes'),
              'Document bytes changed',
            );
            await f.repository.removeDocument(target);
            _check(
              f.transport.requests.last.method == 'DELETE' &&
                  f.transport.requests.last.uri.path == upload.uri.path,
              'Wrong document deletion',
            );
          }
        } finally {
          f.dispose();
        }
      },
  'document selection matches PDF JPEG PNG and 10 MB storage rules': () async {
    _check(
      LawyerDocument.fromBytes('x', lawyerPdfBytes).mimeType ==
          'application/pdf',
      'PDF not accepted',
    );
    _check(
      LawyerDocument.fromBytes('x', lawyerPngBytes).mimeType == 'image/png',
      'PNG not accepted',
    );
    _check(
      LawyerDocument.fromBytes(
            'x',
            Uint8List.fromList([255, 216, 255]),
          ).mimeType ==
          'image/jpeg',
      'JPEG not accepted',
    );
    for (final bytes in [
      Uint8List(0),
      Uint8List(LawyerDocument.maxBytes + 1),
      Uint8List.fromList([82, 73, 70, 70, 0, 0, 0, 0, 87, 69, 66, 80]),
    ]) {
      var rejected = false;
      try {
        LawyerDocument.fromBytes('x', bytes);
      } on ApiException {
        rejected = true;
      }
      _check(rejected, 'Invalid/oversize/WebP document accepted');
    }
  },
  'malformed upload results never report saved images or documents': () async {
    final f = LawyerTestFixture();
    try {
      f.transport.respond = (_) => lawyerOk({'url': null, 'publicId': null});
      _check(
        (await _fails(
              f.repository.uploadPhoto(
                ClientPhoto.fromBytes('p.png', lawyerPngBytes),
              ),
            )).kind ==
            ApiErrorKind.invalidResponse,
        'Null uploaded image accepted',
      );
      f.transport.respond = (_) =>
          lawyerOk({'url': 'https://images.example.test/p.pdf'});
      _check(
        (await _fails(
              f.repository.uploadDocument(
                CouncilDocument.sanad,
                LawyerDocument.fromBytes('p.pdf', lawyerPdfBytes),
              ),
            )).kind ==
            ApiErrorKind.invalidResponse,
        'Incomplete upload accepted',
      );
    } finally {
      f.dispose();
    }
  },
  'lawyer-only guards block every operation for clients inactive accounts and wrong owners':
      () async {
        for (final user in [
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
            role: UserRole.unassigned,
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
          final f = LawyerTestFixture();
          try {
            f.user = user;
            for (final action in <Future<Object?> Function()>[
              f.repository.profile,
              f.repository.barCouncil,
              f.repository.snapshot,
              () => f.repository.saveProfile({}),
              () => f.repository.saveBarCouncil({}),
              () => f.repository.submit(11),
              () => f.repository.uploadPhoto(
                ClientPhoto.fromBytes('p.png', lawyerPngBytes),
              ),
              f.repository.removePhoto,
              () => f.repository.uploadDocument(
                CouncilDocument.sanad,
                LawyerDocument.fromBytes('d.pdf', lawyerPdfBytes),
              ),
              () => f.repository.removeDocument(CouncilDocument.sanad),
            ]) {
              _check(
                (await _fails(action())).kind == ApiErrorKind.forbidden,
                'Forbidden lawyer access admitted',
              );
            }
            _check(
              f.transport.requests.isEmpty,
              'Forbidden action sent network request',
            );
          } finally {
            f.dispose();
          }
        }
      },
  'stale lawyer data is rejected after sign-out or role changes': () async {
    final f = LawyerTestFixture();
    try {
      f.transport.respond = (_) {
        f.user = null;
        return lawyerOk(lawyerProfileJson());
      };
      _check(
        (await _fails(f.repository.profile())).kind == ApiErrorKind.forbidden,
        'Stale profile leaked',
      );
    } finally {
      f.dispose();
    }
  },
  'backend validation limits distinguish past DOB from unrestricted Council dates':
      () async {
        for (final key in LawyerValidation.profileLimits.keys) {
          _check(
            LawyerValidation.profileField(key, '') == null,
            'Optional field made required',
          );
          _check(
            LawyerValidation.profileField(
                  key,
                  'x' * (LawyerValidation.profileLimits[key]! + 1),
                ) !=
                null,
            'Length limit missing for $key',
          );
        }
        _check(
          LawyerValidation.profileField('yearsOfExperience', '0') == null &&
              LawyerValidation.profileField('yearsOfExperience', '70') ==
                  null &&
              LawyerValidation.profileField('yearsOfExperience', '71') !=
                  null &&
              LawyerValidation.profileField('yearsOfExperience', '1.5') != null,
          'Wrong experience limits',
        );
        _check(
          LawyerValidation.profileField('dateOfBirth', '2999-01-01') != null &&
              LawyerValidation.councilField('enrollmentDate', '2999-01-01') ==
                  null,
          'Invented Council date restriction',
        );
        _check(
          LawyerValidation.councilField('sanadIssueDate', '2025-02-29') !=
                  null &&
              LawyerValidation.councilField('sanadNumber', 'x' * 101) != null,
          'Council validation missing',
        );
      },
};
