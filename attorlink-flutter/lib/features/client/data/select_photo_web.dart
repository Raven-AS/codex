import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import '../../../core/network/api_exception.dart';
import '../domain/client_photo.dart';

@JS('document.createElement')
external _FileInput _createInput(String tag);

extension type _FileInput._(JSObject _) implements JSObject {
  external set type(String value);
  external set accept(String value);
  external set onchange(JSFunction? callback);
  external set oncancel(JSFunction? callback);
  external _FileList? get files;
  external void click();
}

extension type _FileList._(JSObject _) implements JSObject {
  external int get length;
  external _BrowserFile? item(int index);
}

extension type _BrowserFile._(JSObject _) implements JSObject {
  external String get name;
  external int get size;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

Future<ClientPhoto?> selectPhoto({String? path}) {
  final input = _createInput('input')
    ..type = 'file'
    ..accept = 'image/jpeg,image/png,image/webp';
  final result = Completer<ClientPhoto?>();
  Future<void> read() async {
    try {
      final files = input.files;
      if (files == null || files.length == 0) {
        result.complete(null);
        return;
      }
      final file = files.item(0)!;
      if (file.size > ClientPhoto.maxBytes) {
        throw const ApiException(
          kind: ApiErrorKind.validation,
          message: 'Choose a photo of at most 5 MB.',
        );
      }
      final buffer = await file.arrayBuffer().toDart;
      result.complete(
        ClientPhoto.fromBytes(file.name, Uint8List.view(buffer.toDart)),
      );
    } on ApiException catch (e) {
      result.completeError(e);
    } catch (_) {
      result.completeError(
        const ApiException(
          kind: ApiErrorKind.unsupported,
          message: 'The selected photo could not be read.',
        ),
      );
    } finally {
      input.onchange = null;
      input.oncancel = null;
    }
  }

  input.onchange = ((JSAny? _) {
    unawaited(read());
  }).toJS;
  input.oncancel = ((JSAny? _) {
    if (!result.isCompleted) result.complete(null);
    input.onchange = null;
    input.oncancel = null;
  }).toJS;
  input.click();
  return result.future;
}
