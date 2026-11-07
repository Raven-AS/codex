import 'package:flutter/services.dart';

import '../../../core/network/api_exception.dart';
import '../domain/boost_models.dart';

const _channel = MethodChannel('attorlink/boost-platform');

Future<void> openAndroidCheckout(Uri uri) async {
  checkoutUri(uri.toString());
  try {
    await _channel.invokeMethod<void>('openCheckout', {'url': uri.toString()});
  } on MissingPluginException {
    throw const ApiException(
      kind: ApiErrorKind.unsupported,
      message: 'Android checkout opening is unavailable. Copy the sandbox URL.',
    );
  } on PlatformException {
    throw const ApiException(
      kind: ApiErrorKind.unsupported,
      message: 'The sandbox URL could not be opened. Copy the link and open it manually.',
    );
  }
}

Future<String> saveAndroidInvoice(
  Uint8List bytes,
  String filename, {
  void Function()? accessGuard,
}) async {
  accessGuard?.call();
  try {
    final destination = await _channel.invokeMethod<String>('chooseInvoice', {
      'filename': filename,
    });
    accessGuard?.call();
    if (destination == null) return 'Invoice save cancelled.';
    final saved = await _channel.invokeMethod<bool>('writeInvoice', {
      'destination': destination,
      'bytes': bytes,
    });
    accessGuard?.call();
    if (saved != true) throw const FormatException('Unconfirmed invoice write');
    return 'Invoice saved to the selected document.';
  } on MissingPluginException {
    throw const ApiException(
      kind: ApiErrorKind.unsupported,
      message: 'Android invoice saving is unavailable.',
    );
  } on PlatformException {
    throw const ApiException(
      kind: ApiErrorKind.validation,
      message: 'The PDF could not be saved. A partial document may remain at the selected destination.',
    );
  } on FormatException {
    throw const ApiException(
      kind: ApiErrorKind.invalidResponse,
      message: 'The invoice save could not be confirmed. Check the selected destination before retrying.',
    );
  }
}
