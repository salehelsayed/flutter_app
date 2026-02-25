import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/shared/widgets/media/media_preview_text.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

MediaAttachment _makeAttachment({
  required String mediaType,
  String mime = 'application/octet-stream',
  int? durationMs,
}) {
  return MediaAttachment(
    id: 'id-${DateTime.now().microsecondsSinceEpoch}',
    messageId: 'msg-1',
    mime: mime,
    size: 1024,
    mediaType: mediaType,
    durationMs: durationMs,
    downloadStatus: 'done',
    createdAt: DateTime.now().toIso8601String(),
  );
}

void main() {
  group('mediaPreviewText', () {
    test('returns "Photo" for single image', () {
      final result = mediaPreviewText([_makeAttachment(mediaType: 'image', mime: 'image/jpeg')]);
      expect(result, 'Photo');
    });

    test('returns "3 photos" for multiple images', () {
      final result = mediaPreviewText([
        _makeAttachment(mediaType: 'image', mime: 'image/jpeg'),
        _makeAttachment(mediaType: 'image', mime: 'image/png'),
        _makeAttachment(mediaType: 'image', mime: 'image/jpeg'),
      ]);
      expect(result, '3 photos');
    });

    test('returns "Video" for single video', () {
      final result = mediaPreviewText([_makeAttachment(mediaType: 'video', mime: 'video/mp4')]);
      expect(result, 'Video');
    });
  });

  group('mediaPreviewIcon', () {
    test('returns camera icon for images', () {
      final result = mediaPreviewIcon([_makeAttachment(mediaType: 'image', mime: 'image/jpeg')]);
      expect(result, Icons.camera_alt_outlined);
    });
  });
}
