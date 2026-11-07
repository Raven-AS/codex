import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import '../../../core/network/api_exception.dart';

@JS('window.open')
external JSAny? _open(String url, String target, String features);
@JS('document.createElement')
external _Anchor _create(String tag);

extension type _Anchor._(JSObject _) implements JSObject {
  external set href(String value);
  external set download(String value);
  external void click();
}

bool get invoiceNeedsPath => false;
Future<void> openCheckout(Uri uri) async {
  // Invoked by a separate user click after the handoff response has loaded.
  _open(uri.toString(), '_blank', 'noopener,noreferrer');
}

Future<String> saveInvoice(
  Uint8List bytes,
  String filename, {
  String? path,
  void Function()? accessGuard,
}) async {
  accessGuard?.call();
  try {
    final anchor = _create('a')
      ..href = 'data:application/pdf;base64,${base64Encode(bytes)}'
      ..download = filename;
    anchor.click();
    return 'PDF download requested. Check browser downloads.';
  } catch (_) {
    throw const ApiException(
      kind: ApiErrorKind.unsupported,
      message: 'The browser could not request this PDF download.',
    );
  }
}
