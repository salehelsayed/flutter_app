import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

import 'fake_media_attachment_repository.dart';

MediaAttachment _makeAttachment({
  required String id,
  required String messageId,
  required String downloadStatus,
  String localPath = '/tmp/test.jpg',
  String mime = 'image/jpeg',
}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: mime,
    size: 1024,
    mediaType: 'image',
    localPath: localPath,
    downloadStatus: downloadStatus,
    createdAt: DateTime.now().toUtc().toIso8601String(),
  );
}

void main() {
  group('FakeMediaAttachmentRepository.getUploadPendingAttachments', () {
    late FakeMediaAttachmentRepository repo;

    setUp(() {
      repo = FakeMediaAttachmentRepository();
    });

    test('returns empty list when no attachments seeded', () async {
      final result = await repo.getUploadPendingAttachments();
      expect(result, isEmpty);
    });

    test('returns only upload_pending attachments', () async {
      repo.seed([
        _makeAttachment(
            id: 'att-1',
            messageId: 'msg-1',
            downloadStatus: 'upload_pending'),
        _makeAttachment(
            id: 'att-done',
            messageId: 'msg-2',
            downloadStatus: 'done'),
        _makeAttachment(
            id: 'att-pending',
            messageId: 'msg-3',
            downloadStatus: 'pending'),
      ]);

      final result = await repo.getUploadPendingAttachments();
      expect(result.length, 1);
      expect(result.first.id, 'att-1');
    });

    test('returns all upload_pending across multiple messages', () async {
      repo.seed([
        _makeAttachment(
            id: 'att-a',
            messageId: 'msg-1',
            downloadStatus: 'upload_pending'),
        _makeAttachment(
            id: 'att-b',
            messageId: 'msg-2',
            downloadStatus: 'upload_pending'),
      ]);

      final result = await repo.getUploadPendingAttachments();
      expect(result.length, 2);
    });

    test('returns attachment with localPath populated', () async {
      repo.seed([
        _makeAttachment(
          id: 'att-1',
          messageId: 'msg-1',
          downloadStatus: 'upload_pending',
          localPath: '/var/mobile/recordings/voice.m4a',
        ),
      ]);

      final result = await repo.getUploadPendingAttachments();
      expect(result.first.localPath, '/var/mobile/recordings/voice.m4a');
    });

    test('excludes upload_failed attachments', () async {
      repo.seed([
        _makeAttachment(
            id: 'att-1',
            messageId: 'msg-1',
            downloadStatus: 'upload_failed'),
      ]);

      final result = await repo.getUploadPendingAttachments();
      expect(result, isEmpty);
    });
  });
}
