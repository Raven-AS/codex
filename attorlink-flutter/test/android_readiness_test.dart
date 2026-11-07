import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attorlink_flutter/core/network/api_exception.dart';
import 'package:attorlink_flutter/core/platform/android_file_picker.dart';
import 'package:attorlink_flutter/features/client/domain/client_photo.dart';
import 'package:attorlink_flutter/features/client/presentation/photo_editor.dart';
import 'package:attorlink_flutter/features/lawyer/domain/lawyer_document.dart';
import 'package:attorlink_flutter/features/lawyer/presentation/document_selection.dart';

// Channel fixtures only. Real content providers, permissions and activity
// recreation require the later Android device checkpoint.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('attorlink/client-photo');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
  void respond(Future<Object?> Function(MethodCall)? handler) {
    messenger.setMockMethodCallHandler(channel, handler);
  }

  tearDown(() => respond(null));

  test('Android picker retains bytes, defaults missing names and sends the document flag', () async {
    final calls = <MethodCall>[];
    respond((call) async {
      calls.add(call);
      return {'bytes': png};
    });
    final photo = (await pickAndroidFile())!;
    expect(photo.name, 'photo');
    expect(
      ClientPhoto.fromBytes(photo.name, photo.bytes).mimeType,
      'image/png',
    );
    final document = (await pickAndroidFile(document: true))!;
    expect(document.name, 'document');
    expect(calls.last.arguments, {'document': true});
    expect(calls.first.method, 'pickPhoto');
  });
  test('Malformed Android picker envelopes fail safely instead of throwing type errors', () async {
    for (final value in [
      42,
      ['unexpected'],
      {'name': 42, 'bytes': png},
      {
        'name': 'photo.png',
        'bytes': [137, 80],
      },
      {'name': 'photo.png'},
    ]) {
      respond((_) async => value);
      await expectLater(
        pickAndroidFile(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            ApiErrorKind.invalidResponse,
          ),
        ),
      );
    }
  });
  test('Android size checks preserve distinct photo/document limits and content validation', () async {
    respond((_) async => {'name': 'empty', 'bytes': Uint8List(0)});
    await expectLater(pickAndroidFile(), throwsA(isA<ApiException>()));
    final large = Uint8List(5 * 1024 * 1024 + 1)..setRange(0, 8, png);
    respond((_) async => {'name': 'large.png', 'bytes': large});
    await expectLater(
      pickAndroidFile(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiErrorKind.validation,
        ),
      ),
    );
    final document = (await pickAndroidFile(document: true))!;
    expect(
      LawyerDocument.fromBytes(document.name, document.bytes).mimeType,
      'image/png',
    );
    respond((_) async => {'bytes': Uint8List(10 * 1024 * 1024 + 1)});
    await expectLater(
      pickAndroidFile(document: true),
      throwsA(isA<ApiException>()),
    );
    expect(
      () =>
          LawyerDocument.fromBytes('wrong.pdf', Uint8List.fromList([1, 2, 3])),
      throwsA(isA<ApiException>()),
    );
  });
  test('Android picker cancellation and provider/channel failures are honest and sanitized', () async {
    respond((_) async => null);
    expect(await pickAndroidFile(), isNull);
    respond(
      (_) async => throw PlatformException(
        code: 'READ',
        message: 'private-provider-details',
      ),
    );
    await expectLater(
      pickAndroidFile(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          isNot(contains('private-provider-details')),
        ),
      ),
    );
    respond(null);
    await expectLater(
      pickAndroidFile(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiErrorKind.unsupported,
        ),
      ),
    );
  });
  testWidgets(
    'Profile photo UI surfaces malformed native metadata without a runtime exception',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        respond((_) async => {'name': 17, 'bytes': png});
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PhotoEditor.forUpload(
                upload: (_) async => null,
                remove: () async => null,
                photo: null,
                onChanged: () async {},
              ),
            ),
          ),
        );
        await tester.tap(find.text('Choose photo'));
        await tester.pumpAndSettle();
        expect(
          find.text('The selected file could not be read.'),
          findsOneWidget,
        );
        expect(find.text('Upload selected photo'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
  testWidgets(
    'Lawyer document adapter uses the shared native validation and real MIME limits',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        respond((call) async {
          expect(call.arguments, {'document': true});
          return {
            'name': 'credential.pdf',
            'bytes': Uint8List.fromList('%PDF-fixture'.codeUnits),
          };
        });
        expect((await chooseLawyerDocument())!.mimeType, 'application/pdf');
        respond((_) async => {'name': false, 'bytes': png});
        await expectLater(chooseLawyerDocument(), throwsA(isA<ApiException>()));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
