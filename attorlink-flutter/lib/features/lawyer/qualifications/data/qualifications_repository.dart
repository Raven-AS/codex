import '../../../../core/network/api_exception.dart';
import '../../../auth/domain/auth_models.dart' show jsonObject, requiredString;
import '../../data/lawyer_repository.dart';
import '../../domain/lawyer_document.dart';
import '../../domain/lawyer_models.dart';
import '../domain/qualification_record.dart';
import '../domain/qualification_schema.dart';

class UnlinkedQualificationUpload extends ApiException {
  UnlinkedQualificationUpload(this.uploaded, ApiException cause)
    : super(
        kind: cause.kind,
        statusCode: cause.statusCode,
        fieldErrors: cause.fieldErrors,
        message:
            '${cause.message} The file was uploaded, but attaching it to the record could not be confirmed. Refresh or retry linking this uploaded file.',
      );
  final LawyerUploadResult uploaded;
}

class QualificationsRepository {
  QualificationsRepository(this.lawyer);
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

  Future<List<QualificationRecord>> list(QualificationResource resource) =>
      _guard(
        () async => (await lawyer.api.request(
          'GET',
          resource.schema.endpoint,
          authenticated: true,
          accessGuard: lawyer.checkAccess,
          decode: (value) {
            if (resource.schema.singleton) {
              return value == null
                  ? <QualificationRecord>[]
                  : [QualificationRecord.fromJson(resource, value)];
            }
            if (value is! List) {
              throw const FormatException('Expected a record list');
            }
            return value
                .map((item) => QualificationRecord.fromJson(resource, item))
                .toList();
          },
        )).data,
      );

  /// Collection controllers have no GET /{id}; resolve from the current own list.
  Future<QualificationRecord> detail(
    QualificationResource resource,
    int id,
  ) async {
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

  Future<QualificationRecord> save(
    QualificationResource resource,
    Map<String, Object?> values, {
    int? id,
    void Function()? checkOperation,
  }) => _guard(() async {
    void checkAccess() {
      lawyer.checkAccess();
      checkOperation?.call();
    }

    checkAccess();
    if (id != null) _id(id);
    final errors = validateQualification(resource, values);
    if (errors.isNotEmpty) {
      throw ApiException(
        kind: ApiErrorKind.validation,
        message: 'Please check the record fields.',
        fieldErrors: errors,
      );
    }
    final body = <String, Object?>{
      for (final field in resource.schema.fields)
        field.key: field.kind == QualificationKind.boolean
            ? values[field.key] == true
            : values[field.key],
    };
    if (resource == QualificationResource.experience &&
        body['current'] == true) {
      body['endDate'] = null;
    }
    final path = resource.schema.singleton || id == null
        ? resource.schema.endpoint
        : '${resource.schema.endpoint}/$id';
    return (await lawyer.api.request(
      resource.schema.singleton || id != null ? 'PUT' : 'POST',
      path,
      authenticated: true,
      body: body,
      accessGuard: checkAccess,
      decode: (value) {
        final record = QualificationRecord.fromJson(resource, value);
        if (id != null && record.id != id) {
          throw const FormatException('Wrong saved record');
        }
        return record;
      },
    )).data;
  });

  Future<QualificationRecord> saveInformation(
    QualificationResource resource,
    Map<String, Object?> values, {
    int? id,
    void Function()? checkOperation,
  }) async {
    lawyer.checkAccess();
    checkOperation?.call();
    QualificationRecord? current;
    if (id != null) {
      current = await detail(resource, id);
    } else if (resource.schema.singleton) {
      final records = await list(resource);
      if (records.isNotEmpty) current = records.single;
    }
    return save(
      resource,
      {
        ...values,
        for (final attachment in resource.schema.attachments)
          attachment.field: current?.fields[attachment.field],
      },
      id: current?.id ?? id,
      checkOperation: checkOperation,
    );
  }

  Future<void> delete(QualificationResource resource, int id) =>
      _guard(() async {
        _id(id);
        if (resource.schema.singleton) {
          throw const ApiException(
            kind: ApiErrorKind.unsupported,
            message:
                'This API does not support deleting the registration record.',
          );
        }
        await lawyer.api.request<void>(
          'DELETE',
          '${resource.schema.endpoint}/$id',
          authenticated: true,
          accessGuard: lawyer.checkAccess,
          decode: (_) {},
        );
      });

  QualificationAttachment _attachment(
    QualificationResource resource,
    String field,
  ) {
    for (final attachment in resource.schema.attachments) {
      if (attachment.field == field) return attachment;
    }
    throw ArgumentError.value(field, 'field', 'Unsupported attachment');
  }

  String _filePath(
    QualificationResource resource,
    int id,
    QualificationAttachment attachment,
  ) =>
      '${resource.schema.endpoint}${resource.schema.singleton ? '' : '/$id'}/${attachment.endpoint}';
  LawyerUploadResult _uploaded(Object? value) {
    final result = LawyerUploadResult.fromJson(value);
    if (result.url?.isNotEmpty != true || result.publicId?.isNotEmpty != true) {
      throw const FormatException('Incomplete uploaded file');
    }
    return result;
  }

  Future<LawyerUploadResult> upload(
    QualificationResource resource,
    int id,
    String field,
    LawyerDocument file,
  ) => _guard(() async {
    _id(id);
    final attachment = _attachment(resource, field);
    // Refresh ownership/existence before transferring bytes.
    await detail(resource, id);
    lawyer.checkAccess();
    if (attachment.endpoint != null) {
      return (await lawyer.api.request(
        'POST',
        _filePath(resource, id, attachment),
        authenticated: true,
        encodedBody: file.multipart(),
        accessGuard: lawyer.checkAccess,
        decode: _uploaded,
      )).data;
    }
    final uploaded = (await lawyer.api.request(
      'POST',
      'files/upload',
      authenticated: true,
      query: {'type': 'DOCUMENT', 'folder': 'lawyer/qualifications'},
      encodedBody: file.multipart(),
      accessGuard: lawyer.checkAccess,
      decode: (value) {
        requiredString(jsonObject(value), 'resourceType');
        return _uploaded(value);
      },
    )).data;
    try {
      await linkDocument(resource, id, field, uploaded.url);
    } on ApiException catch (error) {
      throw UnlinkedQualificationUpload(uploaded, error);
    }
    return uploaded;
  });
  Future<QualificationRecord> linkDocument(
    QualificationResource resource,
    int id,
    String field,
    String? url,
  ) async {
    final attachment = _attachment(resource, field);
    if (attachment.endpoint != null) {
      throw ArgumentError('Use this resource\'s dedicated file endpoint.');
    }
    final current = await detail(resource, id);
    return save(resource, {...current.requestValues, field: url}, id: id);
  }

  Future<void> removeDocument(
    QualificationResource resource,
    int id,
    String field,
  ) => _guard(() async {
    _id(id);
    final attachment = _attachment(resource, field);
    await detail(resource, id);
    if (attachment.endpoint == null) {
      await linkDocument(resource, id, field, null);
      return;
    }
    await lawyer.api.request(
      'DELETE',
      _filePath(resource, id, attachment),
      authenticated: true,
      accessGuard: lawyer.checkAccess,
      decode: LawyerUploadResult.fromJson,
    );
  });
}
