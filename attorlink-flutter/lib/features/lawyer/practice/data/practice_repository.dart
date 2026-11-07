import '../../../../core/network/api_exception.dart';
import '../../data/lawyer_repository.dart';
import '../../qualifications/domain/qualification_schema.dart';
import '../domain/practice_schema.dart';
import '../domain/practice_models.dart';
import '../domain/weekly_availability.dart';

class PracticeRepository {
  PracticeRepository(this.lawyer);
  final LawyerRepository lawyer;
  Future<T> _guard<T>(Future<T> Function() action) async {
    lawyer.checkAccess();
    final result = await action();
    lawyer.checkAccess();
    return result;
  }

  void _id(int id) {
    if (id <= 0) {
      throw ArgumentError.value(id, 'id', 'Expected a positive record ID');
    }
  }

  Future<List<PracticeRecord>> list(PracticeResource resource) => _guard(
    () async => (await lawyer.api.request(
      'GET',
      resource.schema.endpoint,
      authenticated: true,
      accessGuard: lawyer.checkAccess,
      decode: (value) {
        if (value is! List) {
          throw const FormatException('Expected practice record list');
        }
        return value.map((v) => PracticeRecord.fromJson(resource, v)).toList();
      },
    )).data,
  );
  // No practice collection controller exposes a separate detail GET.
  Future<PracticeRecord> detail(PracticeResource resource, int id) async {
    _id(id);
    final records = await list(resource);
    for (final record in records) {
      if (record.id == id) return record;
    }
    throw const ApiException(
      kind: ApiErrorKind.notFound,
      message: 'This record is no longer available. Refresh the list.',
    );
  }

  Future<PracticeRecord> save(
    PracticeResource resource,
    Map<String, Object?> values, {
    int? id,
  }) => _guard(() async {
    if (id != null) _id(id);
    final errors = validatePractice(resource, values);
    if (errors.isNotEmpty) {
      throw ApiException(
        kind: ApiErrorKind.validation,
        message: 'Please check the practice fields.',
        fieldErrors: errors,
      );
    }
    final body = <String, Object?>{
      for (final field in resource.schema.fields)
        field.key:
            field.kind == QualificationKind.boolean && field.key != 'active'
            ? values[field.key] == true
            : values[field.key],
    };
    return (await lawyer.api.request(
      id == null ? 'POST' : 'PUT',
      '${resource.schema.endpoint}${id == null ? '' : '/$id'}',
      authenticated: true,
      body: body,
      accessGuard: lawyer.checkAccess,
      decode: (value) {
        final record = PracticeRecord.fromJson(resource, value);
        if (id != null && record.id != id) {
          throw const FormatException('Wrong saved practice record');
        }
        return record;
      },
    )).data;
  });
  Future<void> delete(PracticeResource resource, int id) => _guard(() async {
    _id(id);
    await lawyer.api.request<void>(
      'DELETE',
      '${resource.schema.endpoint}/$id',
      authenticated: true,
      accessGuard: lawyer.checkAccess,
      decode: (_) {},
    );
  });
  Future<List<PracticeReference>> references(PracticeResource resource) =>
      _guard(() async {
        final path = resource.schema.referenceField?.reference;
        if (path == null) return const [];
        return (await lawyer.api.request(
          'GET',
          path,
          accessGuard: lawyer.checkAccess,
          decode: decodePracticeReferences,
        )).data;
      });
  Future<List<SavedAvailability>> availability() => _guard(
    () async => (await lawyer.api.request(
      'GET',
      'lawyer/availability',
      authenticated: true,
      accessGuard: lawyer.checkAccess,
      decode: decodeAvailability,
    )).data,
  );
  Future<List<SavedAvailability>> saveAvailability(
    List<AvailabilityRange> ranges,
  ) => _guard(() async {
    validateAvailability(ranges);
    return (await lawyer.api.request(
      'PUT',
      'lawyer/availability',
      authenticated: true,
      body: {'slots': ranges.map((r) => r.toJson()).toList()},
      accessGuard: lawyer.checkAccess,
      decode: decodeAvailability,
    )).data;
  });
}
