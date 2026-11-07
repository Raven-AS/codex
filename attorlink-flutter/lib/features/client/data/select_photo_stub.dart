import '../../../core/network/api_exception.dart';
import '../domain/client_photo.dart';

Future<ClientPhoto?> selectPhoto({String? path}) async =>
    throw const ApiException(
      kind: ApiErrorKind.unsupported,
      message: 'Photo selection is unavailable on this platform.',
    );
