import 'dart:io';

import 'package:flutter_app/core/media/document_file_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('document_check_');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('documentFileRejection (414)', () {
    test('a real PDF passes', () async {
      final f = File('${dir.path}/a.pdf')..writeAsStringSync('%PDF-1.4\n');
      expect(
        await documentFileRejection(path: f.path, mime: 'application/pdf'),
        isNull,
      );
    });

    test('non-PDF bytes under application/pdf are refused', () async {
      final f = File('${dir.path}/a.pdf')..writeAsStringSync('<html>');
      expect(
        await documentFileRejection(path: f.path, mime: 'application/pdf'),
        'unknown_signature',
      );
      final tiny = File('${dir.path}/b.pdf')..writeAsStringSync('%PD');
      expect(
        await documentFileRejection(path: tiny.path, mime: 'application/pdf'),
        'unknown_signature',
      );
    });

    test('other MIMEs are unsupported even with PDF bytes', () async {
      final f = File('${dir.path}/a.bin')..writeAsStringSync('%PDF-1.4\n');
      for (final mime in [
        'application/octet-stream',
        'application/zip',
        null,
      ]) {
        expect(
          await documentFileRejection(path: f.path, mime: mime),
          'unsupported_document',
          reason: '$mime',
        );
      }
    });

    test('a missing file is reported', () async {
      expect(
        await documentFileRejection(
          path: '${dir.path}/gone.pdf',
          mime: 'application/pdf',
        ),
        'missing_file',
      );
    });
  });
}
