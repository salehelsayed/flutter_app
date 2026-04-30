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

    test(
      'rejects missing, wildcard, generic, dangerous, and unsupported MIME',
      () {
        const rejected = <String?>[
          null,
          '',
          'not-a-mime',
          'image/*',
          '*/jpeg',
          'image/jpeg; charset=utf-8',
          'application/octet-stream',
          'application/pdf',
          'text/html',
          'image/svg+xml',
          'application/zip',
          'application/x-msdownload',
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
      },
    );

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
