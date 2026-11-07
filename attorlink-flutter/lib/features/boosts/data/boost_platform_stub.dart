import 'dart:typed_data';

import '../../../core/network/api_exception.dart';

bool get invoiceNeedsPath => false;
Future<void> openCheckout(Uri uri) async => throw const ApiException(
  kind: ApiErrorKind.unsupported,
  message:
      'URL opening is unavailable. Copy the sandbox URL and open it manually.',
);
Future<String> saveInvoice(
  Uint8List bytes,
  String filename, {
  String? path,
  void Function()? accessGuard,
}) async => throw const ApiException(
  kind: ApiErrorKind.unsupported,
  message: 'Invoice saving is unavailable on this platform.',
);
