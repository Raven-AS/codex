// Local platform I/O fixture probe; does not contact any backend or provider.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:attorlink_flutter/core/network/api_exception.dart';
import 'package:attorlink_flutter/features/boosts/data/boost_platform_io.dart'
    as native;
import 'package:attorlink_flutter/features/client/data/select_photo_io.dart'
    as photos;
import 'package:attorlink_flutter/features/lawyer/data/select_document_io.dart'
    as documents;

Future<void> main() async {
  final directory = await Directory(
    'build/phase9-platform-${DateTime.now().microsecondsSinceEpoch}',
  ).create(recursive: true);
  final pdf = Uint8List.fromList(
    ascii.encode('%PDF-1.4\n% Fixture bytes for I/O validation only.\n%%EOF\n'),
  );
  final path = '${directory.absolute.path}/fixture-invoice.pdf';
  await native.saveInvoice(pdf, 'fixture-invoice.pdf', path: path);
  if (base64Encode(await File(path).readAsBytes()) != base64Encode(pdf)) {
    throw StateError('Saved bytes differ');
  }
  var overwriteDenied = false;
  try {
    await native.saveInvoice(pdf, 'fixture-invoice.pdf', path: path);
  } on ApiException catch (error) {
    overwriteDenied = error.kind == ApiErrorKind.conflict;
  }
  if (!overwriteDenied) throw StateError('Existing-file protection failed');
  final document = await documents.selectDocument(path: path);
  if (document == null || document.mimeType != 'application/pdf') {
    throw StateError('Native document selection failed');
  }
  var photoRejected = false;
  try {
    await photos.selectPhoto(path: path);
  } on ApiException catch (error) {
    photoRejected = error.kind == ApiErrorKind.validation;
  }
  if (!photoRejected) throw StateError('Non-image photo input was accepted');
  if (await documents.selectDocument(path: '') != null) {
    throw StateError('Cancelled path was accepted');
  }
  stdout.writeln(
    'PASS: native PDF byte save/readback, existing-file refusal, PDF document read, non-image rejection, empty selection.',
  );
  stdout.writeln('Evidence directory: ${directory.path}');
}
