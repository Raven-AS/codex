import '../domain/client_photo.dart';
import 'select_photo_stub.dart'
    if (dart.library.io) 'select_photo_io.dart'
    if (dart.library.js_interop) 'select_photo_web.dart'
    as platform;

Future<ClientPhoto?> selectPhoto({String? path}) =>
    platform.selectPhoto(path: path);
