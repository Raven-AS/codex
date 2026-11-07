import 'dart:io';
import 'dart:typed_data';

import '../../../core/network/api_exception.dart';
import 'boost_platform_android.dart';

bool get invoiceNeedsPath => !Platform.isAndroid;
Future<void> openCheckout(Uri uri) async {
  if (Platform.isAndroid) return openAndroidCheckout(uri);
  final command = Platform.isLinux
      ? 'xdg-open'
      : Platform.isMacOS
      ? 'open'
      : null;
  if (command == null) {
    throw const ApiException(
      kind: ApiErrorKind.unsupported,
      message: 'URL opening is unavailable here. Copy the sandbox URL and open it manually.',
    );
  }
  try {
    final result = await Process.run(command, [
      uri.toString(),
    ], runInShell: false).timeout(const Duration(seconds: 15));
    if (result.exitCode != 0) {
      throw const ApiException(
        kind: ApiErrorKind.unsupported,
        message: 'The desktop could not open the sandbox URL. Copy it and open it manually.',
      );
    }
  } on ProcessException {
    throw const ApiException(
      kind: ApiErrorKind.unsupported,
      message: 'No existing URL opener is available. Copy the sandbox URL and open it manually.',
    );
  } on IOException {
    throw const ApiException(
      kind: ApiErrorKind.unsupported,
      message: 'The sandbox URL could not be opened.',
    );
  } on Exception catch (error) {
    if (error is ApiException) rethrow;
    throw const ApiException(
      kind: ApiErrorKind.unsupported,
      message: 'The URL opener did not finish. Copy the sandbox URL and open it manually.',
    );
  }
}

Future<String> saveInvoice(
  Uint8List bytes,
  String filename, {
  String? path,
  void Function()? accessGuard,
}) async {
  accessGuard?.call();
  if (Platform.isAndroid) {
    return saveAndroidInvoice(bytes, filename, accessGuard: accessGuard);
  }
  if (path == null || path.trim().isEmpty || !File(path.trim()).isAbsolute) {
    throw const ApiException(
      kind: ApiErrorKind.validation,
      message: 'Enter an absolute writable PDF file path.',
    );
  }
  final file = File(path.trim());
  try {
    if (await file.exists()) {
      throw const ApiException(
        kind: ApiErrorKind.conflict,
        message: 'That file already exists. Choose a new filename.',
      );
    }
    accessGuard?.call();
    await file.writeAsBytes(bytes, flush: true);
    return 'Invoice saved to ${file.path}';
  } on FileSystemException {
    throw const ApiException(
      kind: ApiErrorKind.validation,
      message: 'Unable to save the PDF. Choose a writable path in an existing directory.',
    );
  }
}
