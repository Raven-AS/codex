import '../domain/lawyer_document.dart';
import 'select_document_stub.dart'
    if (dart.library.io) 'select_document_io.dart'
    if (dart.library.js_interop) 'select_document_web.dart'
    as platform;

Future<LawyerDocument?> selectDocument({String? path}) =>
    platform.selectDocument(path: path);
