import 'dart:async';
import 'dart:convert';

import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_client.dart';
import 'package:attorlink_flutter/core/network/api_exception.dart';
import 'package:attorlink_flutter/core/network/http_transport.dart';
import 'package:attorlink_flutter/features/auth/domain/auth_models.dart';
import 'package:attorlink_flutter/features/lawyer/data/lawyer_repository.dart';
import 'package:attorlink_flutter/features/lawyer/practice/data/practice_repository.dart';
import 'package:attorlink_flutter/features/lawyer/practice/domain/practice_schema.dart';
import 'package:attorlink_flutter/features/lawyer/practice/domain/weekly_availability.dart';

const practiceInventory = <PracticeResource, (String, List<String>)>{
  PracticeResource.specializations: (
    'specializations',
    ['practiceAreaId', 'experienceYears', 'isPrimary'],
  ),
  PracticeResource.jurisdictions: (
    'jurisdictions',
    ['jurisdictionId', 'registrationNumber'],
  ),
  PracticeResource.courts: ('courts', ['courtId']),
  PracticeResource.languages: ('languages', ['language', 'proficiency']),
  PracticeResource.offices: (
    'offices',
    [
      'officeName',
      'addressLine',
      'country',
      'division',
      'district',
      'city',
      'area',
      'postalCode',
      'latitude',
      'longitude',
      'phone',
      'email',
      'primaryOffice',
    ],
  ),
  PracticeResource.services: (
    'services',
    [
      'name',
      'description',
      'consultationType',
      'durationMinutes',
      'fee',
      'currency',
      'active',
    ],
  ),
};
Map<String, Object?> practiceValues(PracticeResource resource) =>
    switch (resource) {
      PracticeResource.specializations => {
        'practiceAreaId': 101,
        'experienceYears': 5,
        'isPrimary': false,
      },
      PracticeResource.jurisdictions => {
        'jurisdictionId': 102,
        'registrationNumber': 'REG-1',
      },
      PracticeResource.courts => {'courtId': 103},
      PracticeResource.languages => {
        'language': 'Bangla',
        'proficiency': 'NATIVE',
      },
      PracticeResource.offices => {
        'officeName': 'Chamber',
        'country': 'Bangladesh',
        'latitude': 23.8103312,
        'longitude': 90.4125211,
        'primaryOffice': false,
      },
      PracticeResource.services => {
        'name': 'Consultation',
        'consultationType': 'VIDEO',
        'durationMinutes': 30,
        'fee': 500.25,
        'currency': 'BDT',
        'active': true,
      },
    };
Map<String, Object?> practiceJson(PracticeResource resource, {int id = 1}) => {
  'id': id,
  ...practiceValues(resource),
  if (resource == PracticeResource.specializations)
    'practiceAreaName': 'Family law',
  if (resource == PracticeResource.jurisdictions) ...{
    'jurisdictionName': 'Dhaka',
    'district': 'Dhaka',
    'division': 'Dhaka',
    'verificationStatus': 'PENDING',
  },
  if (resource == PracticeResource.courts) ...{
    'courtName': 'District Court',
    'courtType': 'District',
    'district': 'Dhaka',
  },
  'createdAt': '2026-11-04T12:00:00',
};
Map<String, Object?> availabilityJson({
  int id = 1,
  String day = 'MONDAY',
  String start = '09:00:00',
  String end = '10:00:00',
  bool available = true,
}) => {
  'id': id,
  'dayOfWeek': day,
  'startTime': start,
  'endTime': end,
  'available': available,
};
TransportResponse practiceOk(Object? data) => TransportResponse(
  statusCode: 200,
  body: jsonEncode({'success': true, 'message': 'Success', 'data': data}),
);
TransportResponse practiceFailure(
  int status, [
  String message = 'Backend rejected operation',
]) => TransportResponse(
  statusCode: status,
  body: jsonEncode({'success': false, 'message': message, 'data': null}),
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

class PracticeTestTransport implements HttpTransport {
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

class PracticeTestFixture {
  PracticeTestFixture(this.resource) {
    records = [practiceJson(resource)];
    transport.respond = server;
    api = ApiClient(
      config: ApiConfig(baseUrl: Uri.parse('https://api.example.test/api/v1/')),
      transport: transport,
      accessTokenProvider: () => 'test-lawyer-access',
    );
    lawyer = LawyerRepository(api, ownerId: 7, currentUser: () => user);
    repository = PracticeRepository(lawyer);
  }
  final PracticeResource resource;
  AuthUser? user = const AuthUser(
    id: 7,
    email: 'lawyer@example.test',
    role: UserRole.lawyer,
    status: UserStatus.active,
  );
  late List<Map<String, Object?>> records;
  List<Map<String, Object?>> slots = [availabilityJson()];
  final transport = PracticeTestTransport();
  late final ApiClient api;
  late final LawyerRepository lawyer;
  late final PracticeRepository repository;
  TransportResponse server(TransportRequest r) {
    if (r.uri.path == '/api/v1/practice-areas') {
      return practiceOk([
        {'id': 101, 'name': 'Family law', 'active': true, 'parentId': null},
      ]);
    }
    if (r.uri.path == '/api/v1/jurisdictions') {
      return practiceOk([
        {
          'id': 102,
          'name': 'Dhaka',
          'district': 'Dhaka',
          'division': 'Dhaka',
          'active': true,
        },
      ]);
    }
    if (r.uri.path == '/api/v1/courts') {
      return practiceOk([
        {
          'id': 103,
          'name': 'District Court',
          'courtType': 'District',
          'district': 'Dhaka',
          'active': true,
        },
      ]);
    }
    if (r.uri.path == '/api/v1/lawyer/availability') {
      if (r.method == 'GET') return practiceOk(slots);
      if (r.method == 'PUT') {
        slots = [
          for (final (index, value) in (_body(r)['slots'] as List).indexed)
            {
              'id': 100 + index,
              ...value as Map<String, dynamic>,
              'available': true,
            },
        ];
        return practiceOk(slots);
      }
    }
    final base = '/api/v1/lawyer/${practiceInventory[resource]!.$1}';
    if (r.method == 'GET' && r.uri.path == base) return practiceOk(records);
    if ((r.method == 'POST' && r.uri.path == base) ||
        (r.method == 'PUT' && r.uri.path.startsWith('$base/'))) {
      final id = r.method == 'POST'
          ? (records.isEmpty ? 1 : (records.last['id'] as int) + 1)
          : int.parse(r.uri.path.split('/').last);
      final old = records.where((v) => v['id'] == id).firstOrNull;
      final body = _body(r);
      if (body['isPrimary'] == true) {
        for (final row in records) {
          row['isPrimary'] = false;
        }
      }
      if (body['primaryOffice'] == true && old?['primaryOffice'] != true) {
        for (final row in records) {
          row['primaryOffice'] = false;
        }
      }
      final saved = {...practiceJson(resource, id: id), ...body};
      if (resource == PracticeResource.offices && body['country'] == null) {
        saved['country'] = old?['country'] ?? 'Bangladesh';
      }
      if (resource == PracticeResource.services) {
        if (body['currency'] == null) {
          saved['currency'] = old?['currency'] ?? 'BDT';
        }
        if (body['active'] == null) saved['active'] = old?['active'] ?? true;
      }
      records.removeWhere((v) => v['id'] == id);
      records.add(saved);
      return practiceOk(saved);
    }
    if (r.method == 'DELETE' && r.uri.path.startsWith('$base/')) {
      records.removeWhere(
        (v) => v['id'] == int.parse(r.uri.path.split('/').last),
      );
      return practiceOk(null);
    }
    throw StateError('Unexpected practice endpoint ${r.method} ${r.uri.path}');
  }

  void dispose() => api.close();
}

final practiceContractCases = <String, Future<void> Function()>{
  for (final resource in PracticeResource.values)
    '${practiceInventory[resource]!.$1}: exact list detail create edit delete contracts':
        () async {
          final f = PracticeTestFixture(resource);
          try {
            final base = '/api/v1/lawyer/${practiceInventory[resource]!.$1}';
            _check(
              (await f.repository.list(resource)).single.id == 1,
              'List decoding failed',
            );
            await f.repository.detail(resource, 1);
            _check(
              f.transport.requests.every(
                (r) => r.method == 'GET' && r.uri.path == base,
              ),
              'Invented detail GET',
            );
            await f.repository.save(resource, {
              ...practiceValues(resource),
              'id': 999,
              'verificationStatus': 'VERIFIED',
            });
            final create = f.transport.requests.last;
            final body = _body(create);
            _check(
              create.method == 'POST' &&
                  create.uri.path == base &&
                  body.length == practiceInventory[resource]!.$2.length &&
                  body.keys.toSet().containsAll(
                    practiceInventory[resource]!.$2,
                  ) &&
                  !body.containsKey('id') &&
                  !body.containsKey('verificationStatus'),
              'Incorrect create DTO or route',
            );
            await f.repository.save(resource, practiceValues(resource), id: 1);
            _check(
              f.transport.requests.last.method == 'PUT' &&
                  f.transport.requests.last.uri.path == '$base/1',
              'Wrong edit route',
            );
            await f.repository.delete(resource, 1);
            _check(
              f.transport.requests.last.method == 'DELETE' &&
                  f.transport.requests.last.uri.path == '$base/1',
              'Wrong delete route',
            );
            _check(
              f.transport.requests.every(
                (r) =>
                    r.headers['Authorization'] == 'Bearer test-lawyer-access',
              ),
              'Missing authenticated bearer',
            );
          } finally {
            f.dispose();
          }
        },
  'reference catalogs use existing public GET endpoints and preserve district labels':
      () async {
        const paths = {
          PracticeResource.specializations: 'practice-areas',
          PracticeResource.jurisdictions: 'jurisdictions',
          PracticeResource.courts: 'courts',
        };
        for (final entry in paths.entries) {
          final f = PracticeTestFixture(entry.key);
          try {
            final options = await f.repository.references(entry.key);
            final r = f.transport.requests.single;
            _check(
              r.method == 'GET' &&
                  r.uri.path == '/api/v1/${entry.value}' &&
                  !r.headers.containsKey('Authorization'),
              'Wrong public reference contract',
            );
            _check(
              options.single.id > 0 && options.single.name.isNotEmpty,
              'Reference identity lost',
            );
            if (entry.key == PracticeResource.courts) {
              _check(
                options.single.label.contains('Dhaka'),
                'Court context lost',
              );
            }
          } finally {
            f.dispose();
          }
        }
      },
  'empty lists missing details and forbidden catalog errors stay distinct':
      () async {
        final f = PracticeTestFixture(PracticeResource.specializations);
        try {
          f.records.clear();
          _check(
            (await f.repository.list(f.resource)).isEmpty,
            'Empty practice data invented',
          );
          _check(
            (await _fails(f.repository.detail(f.resource, 1))).kind ==
                ApiErrorKind.notFound,
            'Missing detail invented',
          );
          f.transport.respond = (_) => practiceFailure(403);
          _check(
            (await _fails(f.repository.references(f.resource))).kind ==
                ApiErrorKind.forbidden,
            'Catalog failure hidden',
          );
        } finally {
          f.dispose();
        }
      },
  'required fields enum values lengths and experience limits match DTOs':
      () async {
        const required = {
          PracticeResource.specializations: 'practiceAreaId',
          PracticeResource.jurisdictions: 'jurisdictionId',
          PracticeResource.courts: 'courtId',
          PracticeResource.languages: 'language',
          PracticeResource.offices: 'officeName',
          PracticeResource.services: 'consultationType',
        };
        for (final entry in required.entries) {
          final f = PracticeTestFixture(entry.key);
          try {
            final values = practiceValues(entry.key)..[entry.value] = null;
            _check(
              (await _fails(f.repository.save(entry.key, values))).fieldErrors
                  .containsKey(entry.value),
              'Required field not checked',
            );
            _check(f.transport.requests.isEmpty, 'Invalid record sent');
          } finally {
            f.dispose();
          }
        }
        for (final resource in PracticeResource.values) {
          for (final field in resource.schema.fields) {
            if (field.maxLength != null) {
              _check(
                field.validate('x' * (field.maxLength! + 1)) != null,
                'Length cap missing',
              );
            }
          }
        }
        final experience = PracticeResource.specializations.schema.fields
            .firstWhere((f) => f.key == 'experienceYears');
        _check(
          experience.validate('0') == null &&
              experience.validate('70') == null &&
              experience.validate('71') != null,
          'Experience range mismatch',
        );
        final proficiency = PracticeResource.languages.schema.fields.last;
        _check(
          proficiency.options.join(',') ==
                  'NATIVE,FLUENT,CONVERSATIONAL,BASIC' &&
              proficiency.validate('') == null &&
              proficiency.validate('EXPERT') != null,
          'Invented language proficiency',
        );
        final mode = PracticeResource.services.schema.fields.firstWhere(
          (f) => f.key == 'consultationType',
        );
        _check(
          mode.options.join(',') == 'CHAT,PHONE,VIDEO,IN_PERSON' &&
              mode.validate('ZOOM') != null,
          'Consultation enum mismatch',
        );
      },
  'numeric fees coordinates and durations remain numeric without precision loss or silent rounding':
      () async {
        final f = PracticeTestFixture(PracticeResource.offices);
        try {
          await f.repository.save(f.resource, {
            ...practiceValues(f.resource),
            'latitude': 0.0000001,
            'longitude': -0.0000001,
          });
          final body = _body(f.transport.requests.last);
          _check(
            body['latitude'] is num &&
                body['latitude'] == 0.0000001 &&
                body['longitude'] == -0.0000001,
            'Coordinates changed',
          );
          _check(
            practiceInputText(0.0000001) == '0.0000001',
            'Scientific notation not expanded',
          );
        } finally {
          f.dispose();
        }
        final service = PracticeTestFixture(PracticeResource.services);
        try {
          for (final values in [
            {...practiceValues(service.resource), 'fee': -1},
            {...practiceValues(service.resource), 'fee': 1.234},
            {...practiceValues(service.resource), 'durationMinutes': -1},
            {...practiceValues(service.resource), 'durationMinutes': 1.5},
          ]) {
            await _fails(service.repository.save(service.resource, values));
          }
          _check(
            service.transport.requests.isEmpty,
            'Invalid fee/duration sent',
          );
          await service.repository.save(service.resource, {
            ...practiceValues(service.resource),
            'fee': 0,
            'durationMinutes': 0,
          });
          _check(
            _body(service.transport.requests.last)['fee'] is num,
            'Fee serialized as string',
          );
        } finally {
          service.dispose();
        }
      },
  'primary flags are decided by server and re-read from the own list':
      () async {
        for (final resource in [
          PracticeResource.specializations,
          PracticeResource.offices,
        ]) {
          final f = PracticeTestFixture(resource);
          try {
            final key = resource == PracticeResource.specializations
                ? 'isPrimary'
                : 'primaryOffice';
            f.records.single[key] = true;
            await f.repository.save(resource, {
              ...practiceValues(resource),
              key: true,
            });
            final records = await f.repository.list(resource);
            _check(
              records.where((r) => r.fields[key] == true).length == 1 &&
                  records.firstWhere((r) => r.id == 1).fields[key] == false,
              'Server primary result not reflected',
            );
            _check(
              f.transport.requests.where((r) => r.method != 'GET').length == 1,
              'Invented primary-clear endpoint used',
            );
          } finally {
            f.dispose();
          }
        }
      },
  'nullable defaults and existing-reference edits remain server authoritative':
      () async {
        final office = PracticeTestFixture(PracticeResource.offices);
        try {
          final saved = await office.repository.save(office.resource, {
            ...practiceValues(office.resource),
            'country': null,
          });
          _check(
            _body(office.transport.requests.last)['country'] == null &&
                saved.text('country') == 'Bangladesh',
            'Country default fabricated',
          );
          office.records.first['country'] = 'Other country';
          final updated = await office.repository.save(office.resource, {
            ...practiceValues(office.resource),
            'country': null,
          }, id: 1);
          _check(
            updated.text('country') == 'Other country',
            'Null country did not preserve saved value',
          );
        } finally {
          office.dispose();
        }
        final service = PracticeTestFixture(PracticeResource.services);
        try {
          final saved = await service.repository.save(service.resource, {
            ...practiceValues(service.resource),
            'active': null,
            'currency': null,
          });
          _check(
            saved.text('currency') == 'BDT' &&
                saved.fields['active'] == true &&
                _body(service.transport.requests.last)['active'] == null,
            'Service defaults fabricated',
          );
        } finally {
          service.dispose();
        }
        final reference = PracticeTestFixture(PracticeResource.specializations);
        try {
          await reference.repository.save(reference.resource, {
            ...practiceValues(reference.resource),
            'practiceAreaId': 999,
          }, id: 1);
          _check(
            _body(reference.transport.requests.last)['practiceAreaId'] == 999,
            'Existing reference IDs restricted to active catalog',
          );
        } finally {
          reference.dispose();
        }
      },
  'duplicate relationship and language errors are exposed without simulated success':
      () async {
        for (final resource in [
          PracticeResource.specializations,
          PracticeResource.jurisdictions,
          PracticeResource.courts,
          PracticeResource.languages,
        ]) {
          final f = PracticeTestFixture(resource);
          try {
            f.transport.respond = (_) => practiceFailure(400, 'Already added');
            _check(
              (await _fails(
                    f.repository.save(resource, practiceValues(resource)),
                  )).message ==
                  'Already added',
              'Duplicate error hidden',
            );
            _check(
              f.transport.requests.length == 1,
              'Duplicate creation retried',
            );
          } finally {
            f.dispose();
          }
        }
      },
  'availability GET decodes exact day time available and identity fields':
      () async {
        final f = PracticeTestFixture(PracticeResource.languages);
        try {
          f.slots = [
            availabilityJson(start: '09:00:01.123456789', available: false),
          ];
          final slots = await f.repository.availability();
          _check(
            slots.single.range.day == WorkingDay.monday &&
                slots.single.range.start.wire == '09:00:01.123456789' &&
                !slots.single.available,
            'Unavailable response promoted or precision lost',
          );
          _check(
            f.transport.requests.single.method == 'GET' &&
                f.transport.requests.single.uri.path ==
                    '/api/v1/lawyer/availability',
            'Wrong availability GET',
          );
        } finally {
          f.dispose();
        }
      },
  'whole-week PUT retains multiple ranges uses canonical LocalTime and exact slots DTO':
      () async {
        final f = PracticeTestFixture(PracticeResource.languages);
        try {
          final ranges = [
            AvailabilityRange(
              day: WorkingDay.monday,
              start: WorkingTime.parse('09:00'),
              end: WorkingTime.parse('12:00'),
            ),
            AvailabilityRange(
              day: WorkingDay.monday,
              start: WorkingTime.parse('13:00:00.123456789'),
              end: WorkingTime.parse('17:00:00'),
            ),
            AvailabilityRange(
              day: WorkingDay.friday,
              start: WorkingTime.parse('10:00'),
              end: WorkingTime.parse('11:00'),
            ),
          ];
          final saved = await f.repository.saveAvailability(ranges);
          final r = f.transport.requests.single;
          final body = _body(r);
          final rows = body['slots'] as List;
          _check(
            r.method == 'PUT' &&
                r.uri.path == '/api/v1/lawyer/availability' &&
                body.length == 1 &&
                rows.length == 3,
            'Availability not a bulk replacement',
          );
          _check(
            rows.every(
                  (s) =>
                      (s as Map).length == 4 &&
                      s['available'] == true &&
                      !s.containsKey('id'),
                ) &&
                rows[0]['startTime'] == '09:00:00' &&
                rows[1]['startTime'] == '13:00:00.123456789',
            'Incorrect slot wire format',
          );
          _check(
            saved.first.id == 100 && saved.length == 3,
            'Invented or retained old slot IDs',
          );
        } finally {
          f.dispose();
        }
      },
  'empty slot list clears the week through PUT not DELETE': () async {
    final f = PracticeTestFixture(PracticeResource.languages);
    try {
      _check(
        (await f.repository.saveAvailability([])).isEmpty,
        'Empty week fabricated ranges',
      );
      final r = f.transport.requests.single;
      _check(
        r.method == 'PUT' && (_body(r)['slots'] as List).isEmpty,
        'Unsupported availability clear endpoint',
      );
    } finally {
      f.dispose();
    }
  },
  'all seven days round-trip and overlaps are not prohibited by invented constraints':
      () async {
        final f = PracticeTestFixture(PracticeResource.languages);
        try {
          final ranges = [
            for (final day in WorkingDay.values)
              AvailabilityRange(
                day: day,
                start: WorkingTime.parse('09:00'),
                end: WorkingTime.parse('11:00'),
              ),
            AvailabilityRange(
              day: WorkingDay.monday,
              start: WorkingTime.parse('10:00'),
              end: WorkingTime.parse('12:00'),
            ),
          ];
          await f.repository.saveAvailability(ranges);
          _check(
            (_body(f.transport.requests.single)['slots'] as List)
                    .map((s) => s['dayOfWeek'])
                    .toSet()
                    .join(',') ==
                'MONDAY,TUESDAY,WEDNESDAY,THURSDAY,FRIDAY,SATURDAY,SUNDAY',
            'Day representation changed',
          );
        } finally {
          f.dispose();
        }
      },
  'invalid times equal endpoints and overnight ranges are rejected before network':
      () async {
        for (final input in [
          '24:00:00',
          '09:60:00',
          '09:00:60',
          '9:00',
          '09:00:00Z',
          '09:00:00.1234567890',
        ]) {
          var rejected = false;
          try {
            WorkingTime.parse(input);
          } on FormatException {
            rejected = true;
          }
          _check(rejected, 'Invalid LocalTime accepted: $input');
        }
        final f = PracticeTestFixture(PracticeResource.languages);
        try {
          for (final times in [('10:00', '10:00'), ('23:00', '01:00')]) {
            await _fails(
              f.repository.saveAvailability([
                AvailabilityRange(
                  day: WorkingDay.sunday,
                  start: WorkingTime.parse(times.$1),
                  end: WorkingTime.parse(times.$2),
                ),
              ]),
            );
          }
          _check(f.transport.requests.isEmpty, 'Invalid range sent');
        } finally {
          f.dispose();
        }
      },
  'lawyer-only role owner status and stale response guards cover practice and schedules':
      () async {
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
          for (final resource in PracticeResource.values) {
            final f = PracticeTestFixture(resource);
            try {
              f.user = user;
              for (final action in <Future<Object?> Function()>[
                () => f.repository.list(resource),
                () => f.repository.detail(resource, 1),
                () => f.repository.save(resource, practiceValues(resource)),
                () => f.repository.delete(resource, 1),
                () => f.repository.references(resource),
                f.repository.availability,
                () => f.repository.saveAvailability([]),
              ]) {
                _check(
                  (await _fails(action())).kind == ApiErrorKind.forbidden,
                  'Guard bypassed',
                );
              }
              _check(
                f.transport.requests.isEmpty,
                'Forbidden practice request sent',
              );
            } finally {
              f.dispose();
            }
          }
        }
        final f = PracticeTestFixture(PracticeResource.offices);
        try {
          f.transport.respond = (r) {
            f.user = null;
            return f.server(r);
          };
          _check(
            (await _fails(f.repository.list(f.resource))).kind ==
                ApiErrorKind.forbidden,
            'Stale practice data accepted',
          );
        } finally {
          f.dispose();
        }
      },
  'malformed practice schedules and ambiguous mutations do not become success':
      () async {
        final f = PracticeTestFixture(PracticeResource.services);
        try {
          f.transport.respond = (_) => practiceOk(null);
          _check(
            (await _fails(f.repository.list(f.resource))).kind ==
                ApiErrorKind.invalidResponse,
            'Malformed list accepted',
          );
          f.transport.respond = (_) =>
              practiceOk([availabilityJson(day: 'FUNDAY')]);
          _check(
            (await _fails(f.repository.availability())).kind ==
                ApiErrorKind.invalidResponse,
            'Invented day accepted',
          );
          f.transport.respond = (_) => throw const ApiException(
            kind: ApiErrorKind.timeout,
            message: 'Reply lost',
          );
          final before = f.transport.requests.length;
          await _fails(
            f.repository.save(f.resource, practiceValues(f.resource)),
          );
          await _fails(f.repository.saveAvailability([]));
          _check(
            f.transport.requests.length == before + 2,
            'Ambiguous mutation automatically retried',
          );
        } finally {
          f.dispose();
        }
      },
};
