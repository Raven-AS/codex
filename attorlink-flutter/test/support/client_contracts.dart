import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_client.dart';
import 'package:attorlink_flutter/core/network/api_exception.dart';
import 'package:attorlink_flutter/core/network/http_transport.dart';
import 'package:attorlink_flutter/features/auth/domain/auth_models.dart';
import 'package:attorlink_flutter/features/client/data/client_repository.dart';
import 'package:attorlink_flutter/features/client/domain/client_models.dart';
import 'package:attorlink_flutter/features/client/domain/client_photo.dart';
import 'package:attorlink_flutter/features/client/domain/client_validation.dart';

Map<String, Object?> clientProfileJson({
  String status = 'DRAFT',
  int userId = 7,
}) => {
  'id': 11,
  'userId': userId,
  'firstName': null,
  'lastName': null,
  'profilePhoto': null,
  'dateOfBirth': null,
  'gender': null,
  'phone': null,
  'email': 'client@example.test',
  'occupation': null,
  'profileStatus': status,
  'createdAt': '2026-11-04T12:00:00',
  'updatedAt': '2026-11-04T12:00:00',
};
Map<String, Object?> get emptyPreferencesJson => {
  'practiceAreas': [],
  'jurisdictions': [],
  'courts': [],
  'lawyerLanguages': [],
};
TransportResponse clientOk(Object? data) => TransportResponse(
  statusCode: 200,
  body: jsonEncode({'success': true, 'message': 'Success', 'data': data}),
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
  throw StateError('Expected API error');
}

Map<String, dynamic> _body(TransportRequest r) =>
    jsonDecode(r.body!) as Map<String, dynamic>;
final _png = Uint8List.fromList([
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
  13,
  10,
]);

class ClientTestTransport implements HttpTransport {
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

class ClientTestFixture {
  ClientTestFixture() {
    transport.respond = (_) => clientOk(clientProfileJson());
    api = ApiClient(
      config: ApiConfig(baseUrl: Uri.parse('https://api.example.test/api/v1/')),
      transport: transport,
      accessTokenProvider: () => 'test-access-token',
    );
    repository = ClientRepository(api, currentUser: () => user, ownerId: 7);
  }
  AuthUser? user = const AuthUser(
    id: 7,
    email: 'client@example.test',
    role: UserRole.client,
    status: UserStatus.active,
  );
  final transport = ClientTestTransport();
  late final ApiClient api;
  late final ClientRepository repository;
  void dispose() => api.close();
}

final clientContractCases = <String, Future<void> Function()>{
  'profile GET preserves nullable fields and backend draft status': () async {
    final f = ClientTestFixture();
    try {
      final profile = await f.repository.profile();
      _check(
        profile.status == 'DRAFT' &&
            profile.photo == null &&
            profile.displayName.isEmpty,
        'Invented profile data',
      );
      final r = f.transport.requests.single;
      _check(
        r.method == 'GET' &&
            r.uri.path == '/api/v1/client/profile' &&
            r.headers['Authorization'] == 'Bearer test-access-token',
        'Wrong profile GET contract',
      );
    } finally {
      f.dispose();
    }
  },
  'profile PUT sends complete replacement DTO without user identity or photo fields':
      () async {
        final f = ClientTestFixture();
        try {
          f.transport.respond = (_) => clientOk({
            ...clientProfileJson(status: 'COMPLETE'),
            'firstName': 'Asha',
          });
          final result = await f.repository.saveProfile({
            'firstName': 'Asha',
            'profilePhoto': 'must-not-send',
            'userId': 99,
          });
          final r = f.transport.requests.single;
          final body = _body(r);
          _check(
            r.method == 'PUT' &&
                r.uri.path == '/api/v1/client/profile' &&
                result.status == 'COMPLETE',
            'Wrong profile update',
          );
          _check(
            body.keys
                    .toSet()
                    .difference(ClientProfile.editableKeys.toSet())
                    .isEmpty &&
                body.length == 7,
            'Unexpected profile fields',
          );
          _check(
            body['firstName'] == 'Asha' &&
                body.containsKey('dateOfBirth') &&
                body['dateOfBirth'] == null,
            'Replacement fields lost',
          );
        } finally {
          f.dispose();
        }
      },
  'profile identity mismatch and malformed nullable fields are rejected':
      () async {
        final f = ClientTestFixture();
        try {
          f.transport.respond = (_) => clientOk(clientProfileJson(userId: 99));
          _check(
            (await _fails(f.repository.profile())).kind ==
                ApiErrorKind.invalidResponse,
            'Wrong owner accepted',
          );
          f.transport.respond = (_) =>
              clientOk({...clientProfileJson(), 'firstName': 123});
          _check(
            (await _fails(f.repository.profile())).kind ==
                ApiErrorKind.invalidResponse,
            'Malformed profile accepted',
          );
        } finally {
          f.dispose();
        }
      },
  'missing address is null and address PUT uses exact fields and numeric coordinates':
      () async {
        final f = ClientTestFixture();
        try {
          f.transport.respond = (_) => clientOk(null);
          _check(
            await f.repository.address() == null,
            'Missing address invented',
          );
          f.transport.respond = (r) => clientOk({'id': 21, ..._body(r)});
          final address = await f.repository.saveAddress({
            'city': 'Dhaka',
            'latitude': 23.8103312,
            'longitude': 90.4125211,
          });
          final r = f.transport.requests.last;
          final body = _body(r);
          _check(
            r.method == 'PUT' && r.uri.path == '/api/v1/client/address',
            'Wrong address route',
          );
          _check(
            body.length == 9 &&
                body['latitude'] is num &&
                body['addressLine'] == null &&
                address.text('city') == 'Dhaka',
            'Incorrect address replacement',
          );
        } finally {
          f.dispose();
        }
      },
  'preferences decode reference items and clear with four non-null empty lists':
      () async {
        final f = ClientTestFixture();
        try {
          f.transport.respond = (_) => clientOk({
            ...emptyPreferencesJson,
            'practiceAreas': [
              {'id': 1, 'name': 'Family'},
            ],
            'lawyerLanguages': ['Bangla'],
          });
          final prefs = await f.repository.preferences();
          _check(
            prefs.practiceAreas.single.name == 'Family' &&
                prefs.lawyerLanguages.single == 'Bangla',
            'Wrong preference decoding',
          );
          f.transport.respond = (_) => clientOk(emptyPreferencesJson);
          await f.repository.savePreferences(
            practiceAreaIds: [],
            jurisdictionIds: [],
            courtIds: [],
            lawyerLanguages: [],
          );
          final r = f.transport.requests.last;
          _check(
            r.method == 'PUT' && r.uri.path == '/api/v1/client/preferences',
            'Wrong preference PUT',
          );
          final body = _body(r);
          _check(
            body.length == 4 &&
                body.values.every((v) => v is List && v.isEmpty),
            'Empty selections were omitted',
          );
        } finally {
          f.dispose();
        }
      },
  'preference payload uses IDs and language strings without invented fields':
      () async {
        final f = ClientTestFixture();
        try {
          f.transport.respond = (_) => clientOk(emptyPreferencesJson);
          await f.repository.savePreferences(
            practiceAreaIds: [1, 1],
            jurisdictionIds: [2],
            courtIds: [3],
            lawyerLanguages: ['Bangla', 'English'],
          );
          final body = _body(f.transport.requests.single);
          _check(
            (body['practiceAreaIds'] as List).join() == '1' &&
                (body['jurisdictionIds'] as List).single == 2 &&
                (body['courtIds'] as List).single == 3 &&
                (body['lawyerLanguages'] as List).length == 2,
            'Wrong preference DTO',
          );
        } finally {
          f.dispose();
        }
      },
  'three reference endpoints return lists and omit bearer on public requests':
      () async {
        final f = ClientTestFixture();
        try {
          f.transport.respond = (r) => clientOk([
            {
              'id': 1,
              'name': r.uri.path.split('/').last,
              'active': true,
              'district': 'Dhaka',
            },
          ]);
          final catalogs = await f.repository.catalogs();
          _check(
            catalogs.practiceAreas.single.name == 'practice-areas' &&
                catalogs.jurisdictions.single.name == 'jurisdictions' &&
                catalogs.courts.single.name == 'courts',
            'Wrong reference contracts',
          );
          _check(
            f.transport.requests.length == 3 &&
                f.transport.requests.every(
                  (r) =>
                      r.method == 'GET' &&
                      !r.headers.containsKey('Authorization'),
                ),
            'Unexpected reference authentication',
          );
        } finally {
          f.dispose();
        }
      },
  'reference failure propagates instead of silently returning empty catalogs':
      () async {
        final f = ClientTestFixture();
        try {
          f.transport.respond = (_) =>
              const TransportResponse(statusCode: 503, body: '');
          _check(
            (await _fails(f.repository.catalogs())).kind == ApiErrorKind.server,
            'Catalog failure hidden',
          );
        } finally {
          f.dispose();
        }
      },
  'client-only repository blocks other roles inactive accounts and wrong owners':
      () async {
        for (final user in [
          null,
          const AuthUser(
            id: 7,
            email: 'x',
            role: UserRole.lawyer,
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
            role: UserRole.admin,
            status: UserStatus.active,
          ),
          const AuthUser(
            id: 7,
            email: 'x',
            role: UserRole.client,
            status: UserStatus.suspended,
          ),
          const AuthUser(
            id: 8,
            email: 'x',
            role: UserRole.client,
            status: UserStatus.active,
          ),
        ]) {
          final f = ClientTestFixture();
          try {
            f.user = user;
            final photo = ClientPhoto.fromBytes('photo.png', _png);
            for (final operation in <Future<Object?> Function()>[
              f.repository.profile,
              () => f.repository.saveProfile({}),
              f.repository.address,
              () => f.repository.saveAddress({}),
              f.repository.preferences,
              f.repository.catalogs,
              () => f.repository.uploadPhoto(photo),
              f.repository.removePhoto,
              () => f.repository.savePreferences(
                practiceAreaIds: [],
                jurisdictionIds: [],
                courtIds: [],
                lawyerLanguages: [],
              ),
            ]) {
              _check(
                (await _fails(operation())).kind == ApiErrorKind.forbidden,
                'Non-client access allowed',
              );
            }
            _check(
              f.transport.requests.isEmpty,
              'Forbidden operation sent HTTP request',
            );
          } finally {
            f.dispose();
          }
        }
      },
  'role changes while a request is pending cannot disclose the old profile':
      () async {
        final f = ClientTestFixture();
        try {
          f.transport.respond = (_) {
            f.user = null;
            return clientOk(clientProfileJson());
          };
          _check(
            (await _fails(f.repository.profile())).kind ==
                ApiErrorKind.forbidden,
            'Stale client response accepted',
          );
        } finally {
          f.dispose();
        }
      },
  'photo upload sends real multipart bytes under the exact file field':
      () async {
        final f = ClientTestFixture();
        try {
          f.transport.respond = (_) => clientOk({
            'profilePhoto': 'https://images.example.test/photo.png',
          });
          final photo = ClientPhoto.fromBytes('unsafe"\r\nname.png', _png);
          final url = await f.repository.uploadPhoto(photo);
          final r = f.transport.requests.single;
          _check(
            r.method == 'POST' &&
                r.uri.path == '/api/v1/client/profile/photo' &&
                r.body == null &&
                r.bodyBytes != null,
            'Photo was not uploaded as binary multipart',
          );
          final contentType = r.headers['Content-Type']!;
          final boundary = contentType.split('boundary=').last;
          final bytes = r.bodyBytes!;
          final text = latin1.decode(bytes);
          _check(
            text.startsWith('--$boundary\r\n') &&
                text.endsWith('\r\n--$boundary--\r\n'),
            'Invalid multipart framing',
          );
          _check(
            text.contains('name="file"; filename="unsafe___name.png"') &&
                text.contains('Content-Type: image/png\r\n'),
            'Unsafe multipart headers',
          );
          final offset = text.indexOf('\r\n\r\n') + 4;
          _check(
            List.generate(
              _png.length,
              (i) => bytes[offset + i] == _png[i],
            ).every((v) => v),
            'Binary photo bytes changed',
          );
          _check(
            url == 'https://images.example.test/photo.png',
            'Upload success was not decoded',
          );
        } finally {
          f.dispose();
        }
      },
  'photo removal decodes null and malformed photo responses are rejected':
      () async {
        final f = ClientTestFixture();
        try {
          f.transport.respond = (_) => clientOk({'profilePhoto': null});
          _check(
            await f.repository.removePhoto() == null,
            'Photo was not cleared',
          );
          _check(
            f.transport.requests.single.method == 'DELETE' &&
                f.transport.requests.single.uri.path.endsWith(
                  '/client/profile/photo',
                ),
            'Wrong removal route',
          );
          f.transport.respond = (_) => clientOk({});
          _check(
            (await _fails(f.repository.removePhoto())).kind ==
                ApiErrorKind.invalidResponse,
            'Missing photo field accepted',
          );
          f.transport.respond = (_) => clientOk({'profilePhoto': null});
          _check(
            (await _fails(
                  f.repository.uploadPhoto(
                    ClientPhoto.fromBytes('p.png', _png),
                  ),
                )).kind ==
                ApiErrorKind.invalidResponse,
            'Upload falsely accepted null URL',
          );
        } finally {
          f.dispose();
        }
      },
  'photo MIME checks reject empty oversized and unsupported bytes': () async {
    for (final bytes in [
      Uint8List(0),
      Uint8List(ClientPhoto.maxBytes + 1),
      Uint8List.fromList([71, 73, 70]),
    ]) {
      var rejected = false;
      try {
        ClientPhoto.fromBytes('wrong.jpg', bytes);
      } on ApiException {
        rejected = true;
      }
      _check(rejected, 'Invalid photo accepted');
    }
    _check(
      ClientPhoto.fromBytes('unknown', _png).mimeType == 'image/png',
      'PNG not detected',
    );
    _check(
      ClientPhoto.fromBytes(
            'unknown',
            Uint8List.fromList([255, 216, 255, 0]),
          ).mimeType ==
          'image/jpeg',
      'JPEG not detected',
    );
    _check(
      ClientPhoto.fromBytes(
            'unknown',
            Uint8List.fromList([82, 73, 70, 70, 0, 0, 0, 0, 87, 69, 66, 80]),
          ).mimeType ==
          'image/webp',
      'WebP not detected',
    );
  },
  'multipart retry preserves bytes boundary and uses the renewed bearer':
      () async {
        final transport = ClientTestTransport();
        var token = 'old';
        final api = ApiClient(
          config: ApiConfig(
            baseUrl: Uri.parse('https://api.example.test/api/v1/'),
          ),
          transport: transport,
          accessTokenProvider: () => token,
          recoverAuthentication: (_) async {
            token = 'new';
            return true;
          },
        );
        try {
          transport.respond = (r) => r.headers['Authorization'] == 'Bearer old'
              ? const TransportResponse(statusCode: 401, body: '')
              : clientOk({'profilePhoto': 'https://images.example.test/p.png'});
          final body = ClientPhoto.fromBytes(
            'p.png',
            _png,
          ).multipart(testBoundary: 'test-boundary');
          await api.request(
            'POST',
            'client/profile/photo',
            authenticated: true,
            encodedBody: body,
            decode: (v) => v,
          );
          _check(
            transport.requests.length == 2 &&
                identical(
                  transport.requests[0].bodyBytes,
                  transport.requests[1].bodyBytes,
                ) &&
                transport.requests.last.headers['Content-Type'] ==
                    'multipart/form-data; boundary=test-boundary',
            'Multipart request was not replayable',
          );
        } finally {
          api.close();
        }
      },
  'forbidden and failed mutations never return fabricated success': () async {
    final f = ClientTestFixture();
    try {
      f.transport.respond = (_) =>
          const TransportResponse(statusCode: 403, body: '');
      _check(
        (await _fails(f.repository.saveProfile({}))).kind ==
            ApiErrorKind.forbidden,
        'Forbidden update succeeded',
      );
      f.transport.respond = (_) => throw const ApiException(
        kind: ApiErrorKind.network,
        message: 'Offline',
      );
      final count = f.transport.requests.length;
      await _fails(
        f.repository.uploadPhoto(ClientPhoto.fromBytes('p.png', _png)),
      );
      _check(
        f.transport.requests.length == count + 1,
        'Ambiguous upload was retried',
      );
    } finally {
      f.dispose();
    }
  },
  'optional fields and backend length date phone and decimal rules validate':
      () async {
        _check(
          ClientValidation.phone('') == null &&
              ClientValidation.email(null) == null &&
              ClientValidation.birthDate('') == null,
          'Optional field made mandatory',
        );
        _check(
          ClientValidation.length('a' * 101, 100) != null &&
              ClientValidation.phone('abc') != null &&
              ClientValidation.email('wrong') != null,
          'Invalid profile fields accepted',
        );
        final now = DateTime(2026, 11, 4);
        _check(
          ClientValidation.birthDate('2026-11-04', now: now) != null &&
              ClientValidation.birthDate('2025-02-29', now: now) != null &&
              ClientValidation.birthDate('2000-02-29', now: now) == null,
          'Invalid birth dates accepted',
        );
        _check(
          ClientValidation.coordinate('23.1234567') == null &&
              ClientValidation.coordinate('1.12345678') != null &&
              ClientValidation.coordinate('NaN') != null,
          'Invalid decimal format accepted',
        );
        _check(
          ClientValidation.normalizeLanguage('  Bangla   language  ') ==
              'Bangla language',
          'Language whitespace not normalized',
        );
      },
};
