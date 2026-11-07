import 'dart:typed_data';

import '../domain/boost_models.dart';
import 'boost_platform_stub.dart'
    if (dart.library.io) 'boost_platform_io.dart'
    if (dart.library.js_interop) 'boost_platform_web.dart'
    as platform;

Future<void> openCheckout(String value) =>
    platform.openCheckout(checkoutUri(value));
Future<String> saveInvoice(
  Uint8List bytes,
  String filename, {
  String? path,
  void Function()? accessGuard,
}) =>
    platform.saveInvoice(bytes, filename, path: path, accessGuard: accessGuard);
bool get invoiceNeedsPath => platform.invoiceNeedsPath;
