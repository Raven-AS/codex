import '../../../core/network/api_exception.dart';
import '../domain/lawyer_document.dart';

Future<LawyerDocument?> selectDocument({String? path}) async =>
    throw const ApiException(
      kind: ApiErrorKind.unsupported,
      message: 'Document selection is unavailable on this platform.',
    );
