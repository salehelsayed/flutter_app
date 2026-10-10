import 'dart:io';

import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_test/flutter_test.dart';

const _jpegBytes = <int>[0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10];
const _pngBytes = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

void main() {
  group('GroupMediaMimePolicy', () {
    test('allows exact group media MIME values and maps mediaType', () {
      const expected = {
        'image/jpeg': 'image',
        'image/png': 'image',
        'image/gif': 'image',
        'image/webp': 'image',
        'image/heic': 'image',
        'video/mp4': 'video',
        'video/quicktime': 'video',
        'audio/mp4': 'audio',
        'audio/aac': 'audio',
        'audio/mpeg': 'audio',
        'audio/ogg': 'audio',
        'application/pdf': 'file',
      };

      for (final entry in expected.entries) {
        expect(
          GroupMediaMimePolicy.mediaTypeForMime(' ${entry.key.toUpperCase()} '),
          entry.value,
          reason: entry.key,
        );
        expect(
          GroupMediaMimePolicy.validateDescriptor(
            mime: entry.key,
            mediaType: entry.value,
          ).isValid,
          isTrue,
          reason: entry.key,
        );
      }
    });

    test('rejects missing, wildcard, dangerous, and unsupported MIME', () {
      const rejected = <String?>[
        null,
        '',
        'not-a-mime',
        'image/*',
        '*/jpeg',
        'image/jpeg; charset=utf-8',
        'application/pdf; x=1',
        'text/html',
        'image/svg+xml',
        'application/zip',
        'application/x-msdownload',
        'application/octet-stream',
        'video/x-matroska',
        'video/x-msvideo',
        'audio/x-m4a',
      ];

      for (final mime in rejected) {
        expect(
          GroupMediaMimePolicy.validateDescriptor(mime: mime).isValid,
          isFalse,
          reason: '$mime should be rejected',
        );
      }
    });

    test('rejects mediaType mismatches', () {
      expect(
        GroupMediaMimePolicy.validateDescriptor(
          mime: 'image/jpeg',
          mediaType: 'video',
        ).reason,
        'media_type_mismatch',
      );
      expect(
        GroupMediaMimePolicy.validateDescriptor(
          mime: 'audio/mp4',
          mediaType: 'file',
        ).reason,
        'media_type_mismatch',
      );
    });

    test('rejects spoofed local bytes with dangerous signatures', () async {
      final dir = await Directory.systemTemp.createTemp('group_mime_policy_');
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final jpeg = File('${dir.path}/photo.jpg')..writeAsBytesSync(_jpegBytes);
      final script = File('${dir.path}/script.jpg')
        ..writeAsStringSync('<script>alert(1)</script>');
      final exe = File('${dir.path}/binary.png')
        ..writeAsBytesSync(const <int>[0x4d, 0x5a, 0x90, 0x00]);

      expect(
        await GroupMediaMimePolicy.fileMatchesDeclaredMime(
          path: jpeg.path,
          mime: 'image/jpeg',
          mediaType: 'image',
        ),
        isTrue,
      );
      expect(
        (await GroupMediaMimePolicy.validateFile(
          path: script.path,
          mime: 'image/jpeg',
          mediaType: 'image',
        )).reason,
        'dangerous_signature',
      );
      expect(
        (await GroupMediaMimePolicy.validateFile(
          path: exe.path,
          mime: 'image/png',
          mediaType: 'image',
        )).reason,
        'dangerous_signature',
      );
    });

    test(
      'rejects unknown visual signatures while preserving allowed audio fallback',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'group_mime_unknown_',
        );
        addTearDown(() async {
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        });

        final unknownJpeg = File('${dir.path}/unknown.jpg')
          ..writeAsStringSync('plain bytes with no known media signature');
        final unknownOctet = File('${dir.path}/unknown.bin')
          ..writeAsStringSync('plain bytes with no known media signature');
        final unknownAudio = File('${dir.path}/unknown.m4a')
          ..writeAsStringSync('plain bytes with no known audio signature');

        expect(
          (await GroupMediaMimePolicy.validateFile(
            path: unknownJpeg.path,
            mime: 'image/jpeg',
            mediaType: 'image',
          )).reason,
          'unknown_signature',
        );
        expect(
          (await GroupMediaMimePolicy.validateFile(
            path: unknownOctet.path,
            mime: 'application/octet-stream',
            mediaType: 'file',
          )).reason,
          'disallowed_mime',
        );
        expect(
          (await GroupMediaMimePolicy.validateFile(
            path: unknownAudio.path,
            mime: 'audio/mp4',
            mediaType: 'audio',
          )).isValid,
          isTrue,
        );
      },
    );

    group('PDF (414)', () {
      late Directory dir;
      setUp(() async {
        dir = await Directory.systemTemp.createTemp('group_mime_pdf_');
      });
      tearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      test('application/pdf with %PDF- bytes is a valid file', () async {
        final pdf = File('${dir.path}/doc.pdf')
          ..writeAsStringSync('%PDF-1.7\n%\n1 0 obj');
        final result = await GroupMediaMimePolicy.validateFile(
          path: pdf.path,
          mime: 'application/pdf',
          mediaType: 'file',
        );
        expect(result.isValid, isTrue);
        expect(
          GroupMediaMimePolicy.mediaTypeForMime('application/pdf'),
          'file',
        );
      });

      test('PDF bytes under an image MIME stay dangerous_signature', () async {
        final pdf = File('${dir.path}/spoof.jpg')
          ..writeAsStringSync('%PDF-1.7\n');
        expect(
          (await GroupMediaMimePolicy.validateFile(
            path: pdf.path,
            mime: 'image/jpeg',
            mediaType: 'image',
          )).reason,
          'dangerous_signature',
        );
      });

      test('application/pdf without PDF bytes is refused', () async {
        final plain = File('${dir.path}/plain.pdf')
          ..writeAsStringSync('not a pdf at all');
        final zip = File('${dir.path}/zip.pdf')
          ..writeAsBytesSync(const <int>[0x50, 0x4b, 0x03, 0x04, 0x00]);
        final html = File('${dir.path}/page.pdf')
          ..writeAsStringSync('<html><script>');
        expect(
          (await GroupMediaMimePolicy.validateFile(
            path: plain.path,
            mime: 'application/pdf',
            mediaType: 'file',
          )).reason,
          'unknown_signature',
        );
        for (final file in [zip, html]) {
          expect(
            (await GroupMediaMimePolicy.validateFile(
              path: file.path,
              mime: 'application/pdf',
              mediaType: 'file',
            )).reason,
            'dangerous_signature',
            reason: file.path,
          );
        }
      });

      test('a PDF declared as another media type is a mismatch', () {
        expect(
          GroupMediaMimePolicy.validateDescriptor(
            mime: 'application/pdf',
            mediaType: 'image',
          ).reason,
          'media_type_mismatch',
        );
      });
    });

    test(
      'rejects known content signatures that disagree with declared MIME',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'group_mime_mismatch_',
        );
        addTearDown(() async {
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        });

        final pngAsJpeg = File('${dir.path}/spoof.jpg')
          ..writeAsBytesSync(_pngBytes);

        expect(
          (await GroupMediaMimePolicy.validateFile(
            path: pngAsJpeg.path,
            mime: 'image/jpeg',
            mediaType: 'image',
          )).reason,
          'mime_signature_mismatch',
        );
      },
    );
  });
}
