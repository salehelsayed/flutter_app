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
      // No explicit override -> the per-type (image) cap rejects first, with a
      // type-aware reason, before the running total can overflow.
      expect(result.reason, 'image_size_exceeded');
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

    test('groupMediaPerTypeLimitBytes resolves the cap for each media type', () {
      expect(groupMediaPerTypeLimitBytes('image/jpeg'), kGroupMediaImageLimitBytes);
      expect(groupMediaPerTypeLimitBytes('image/png'), kGroupMediaImageLimitBytes);
      expect(groupMediaPerTypeLimitBytes('IMAGE/JPEG '), kGroupMediaImageLimitBytes);
      expect(groupMediaPerTypeLimitBytes('video/mp4'), kGroupMediaVideoLimitBytes);
      expect(groupMediaPerTypeLimitBytes('audio/mp4'), kGroupMediaAudioLimitBytes);
      expect(groupMediaPerTypeLimitBytes('image/gif'), kMaxGifFileSize);
      expect(
        groupMediaPerTypeLimitBytes('application/octet-stream'),
        kGroupMediaFileLimitBytes,
      );
      expect(groupMediaPerTypeLimitBytes(null), kGroupMediaFileLimitBytes);
      expect(groupMediaPerTypeLimitBytes(''), kGroupMediaFileLimitBytes);
    });

    test('validateSize derives per-type caps with type-aware reasons', () {
      // image @ 25 MB
      expect(
        GroupMediaSizePolicy.validateSize(
          sizeBytes: kGroupMediaImageLimitBytes,
          mime: 'image/jpeg',
        ).isValid,
        isTrue,
      );
      final image = GroupMediaSizePolicy.validateSize(
        sizeBytes: kGroupMediaImageLimitBytes + 1,
        mime: 'image/jpeg',
      );
      expect(image.isValid, isFalse);
      expect(image.reason, 'image_size_exceeded');

      // video @ 250 MB
      expect(
        GroupMediaSizePolicy.validateSize(
          sizeBytes: kGroupMediaVideoLimitBytes,
          mime: 'video/mp4',
        ).isValid,
        isTrue,
      );
      final video = GroupMediaSizePolicy.validateSize(
        sizeBytes: kGroupMediaVideoLimitBytes + 1,
        mime: 'video/mp4',
      );
      expect(video.isValid, isFalse);
      expect(video.reason, 'video_size_exceeded');

      // audio/voice @ 16 MB
      expect(
        GroupMediaSizePolicy.validateSize(
          sizeBytes: kGroupMediaAudioLimitBytes,
          mime: 'audio/mp4',
        ).isValid,
        isTrue,
      );
      final audio = GroupMediaSizePolicy.validateSize(
        sizeBytes: kGroupMediaAudioLimitBytes + 1,
        mime: 'audio/mp4',
      );
      expect(audio.isValid, isFalse);
      expect(audio.reason, 'voice_size_exceeded');

      // generic file / unknown mime @ 100 MB
      expect(
        GroupMediaSizePolicy.validateSize(
          sizeBytes: kGroupMediaFileLimitBytes,
          mime: 'application/pdf',
        ).isValid,
        isTrue,
      );
      final file = GroupMediaSizePolicy.validateSize(
        sizeBytes: kGroupMediaFileLimitBytes + 1,
        mime: 'application/pdf',
      );
      expect(file.isValid, isFalse);
      expect(file.reason, 'file_size_exceeded');

      // gif keeps its dedicated cap
      final gif = GroupMediaSizePolicy.validateSize(
        sizeBytes: kMaxGifFileSize + 1,
        mime: 'image/gif',
      );
      expect(gif.isValid, isFalse);
      expect(gif.reason, 'gif_size_exceeded');
    });

    test('enforces the total-message cap on per-type-valid attachments', () {
      // Each video is within the 250 MB per-type cap, but together they exceed
      // the 500 MB total-message cap.
      final result = GroupMediaSizePolicy.validateAttachments([
        _attachment(id: 'v1', mime: 'video/mp4', size: kGroupMediaVideoLimitBytes),
        _attachment(id: 'v2', mime: 'video/mp4', size: kGroupMediaVideoLimitBytes),
        _attachment(id: 'v3', mime: 'video/mp4', size: 1),
      ]);

      expect(result.isValid, isFalse);
      expect(result.reason, 'total_media_size_exceeded');
    });

    test('explicit perMediaLimitBytes override wins over the per-type table', () {
      // INV-SZ-4: an explicit cap (test overrides + receive-side backstop) is
      // honored verbatim and reports the generic reason; the table is ignored.
      final result = GroupMediaSizePolicy.validateSize(
        sizeBytes: 1024,
        mime: 'image/jpeg',
        perMediaLimitBytes: 512,
      );

      expect(result.isValid, isFalse);
      expect(result.reason, 'media_size_exceeded');
    });
  });
}
