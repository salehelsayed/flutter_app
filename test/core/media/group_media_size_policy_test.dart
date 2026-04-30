import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/constants/media_constants.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

MediaAttachment _attachment({
  String id = 'blob-1',
  String mime = 'image/jpeg',
  int size = 1024,
}) {
  return MediaAttachment(
    id: id,
    messageId: 'msg-1',
    mime: mime,
    size: size,
    mediaType: MediaAttachment.mediaTypeFromMime(mime),
    downloadStatus: 'done',
    createdAt: '2026-01-01T00:00:00.000Z',
  );
}

void main() {
  group('GroupMediaSizePolicy', () {
    test('accepts per-media and total exact boundary values', () {
      final result = GroupMediaSizePolicy.validateAttachments(
        [_attachment(size: 100), _attachment(id: 'blob-2', size: 100)],
        perMediaLimitBytes: 100,
        totalLimitBytes: 200,
      );

      expect(result.isValid, isTrue);
    });

    test('rejects one byte over the per-media limit', () {
      final result = GroupMediaSizePolicy.validateAttachments(
        [_attachment(size: 101)],
        perMediaLimitBytes: 100,
        totalLimitBytes: 200,
      );

      expect(result.isValid, isFalse);
      expect(result.reason, 'media_size_exceeded');
    });

    test('rejects one byte over the total message media limit', () {
      final result = GroupMediaSizePolicy.validateAttachments(
        [_attachment(size: 100), _attachment(id: 'blob-2', size: 101)],
        perMediaLimitBytes: 200,
        totalLimitBytes: 200,
      );

      expect(result.isValid, isFalse);
      expect(result.reason, 'total_media_size_exceeded');
    });

    test('rejects missing, zero, negative, and non-integer remote sizes', () {
      for (final rawSize in <Object?>[null, 0, -1, '100', 1.5]) {
        final result = GroupMediaSizePolicy.validateRawDescriptors([
          {'id': 'blob', 'mime': 'image/jpeg', 'size': rawSize},
        ]);

        expect(result.isValid, isFalse, reason: 'rawSize=$rawSize');
      }
    });

    test('rejects large totals before accepting unsafe sums', () {
      final result = GroupMediaSizePolicy.validateRawDescriptors([
        {'id': 'blob-1', 'mime': 'image/jpeg', 'size': 9223372036854775807},
        {'id': 'blob-2', 'mime': 'image/jpeg', 'size': 9223372036854775807},
      ]);

      expect(result.isValid, isFalse);
      expect(result.reason, 'media_size_exceeded');
    });

    test('preserves the GIF-specific cap below the general media cap', () {
      final result = GroupMediaSizePolicy.validateAttachments([
        _attachment(mime: 'image/gif', size: kMaxGifFileSize + 1),
      ]);

      expect(result.isValid, isFalse);
      expect(result.reason, 'gif_size_exceeded');
    });

    test('does not replace MIME validation', () {
      final result = GroupMediaSizePolicy.validateRawDescriptors([
        {'id': 'blob-svg', 'mime': 'image/svg+xml', 'size': 1024},
      ]);

      expect(result.isValid, isTrue);
    });
  });
}
