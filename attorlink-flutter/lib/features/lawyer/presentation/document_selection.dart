import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/platform/android_file_picker.dart';
import '../data/select_document.dart';
import '../domain/lawyer_document.dart';

bool get documentSelectionUsesPath =>
    !kIsWeb && defaultTargetPlatform != TargetPlatform.android;

/// Shared SDK/Android document selector, retaining the existing 10 MB contract.
Future<LawyerDocument?> chooseLawyerDocument({String? path}) async {
  try {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final selected = await pickAndroidFile(document: true);
      if (selected == null) return null;
      return LawyerDocument.fromBytes(selected.name, selected.bytes);
    }
    return await selectDocument(path: path);
  } on PlatformException catch (error) {
    throw ApiException(
      kind: ApiErrorKind.unsupported,
      message: error.message ?? 'Document selection is unavailable.',
    );
  } on MissingPluginException {
    throw const ApiException(
      kind: ApiErrorKind.unsupported,
      message: 'This build does not provide the Android document picker.',
    );
  }
}
