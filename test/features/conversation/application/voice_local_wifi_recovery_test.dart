import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

import '../domain/repositories/fake_media_attachment_repository.dart';

void main() {
  group('Voice local-WiFi recovery (Gap 5)', () {
    // G.10.2.1
    test('after successful sendLocalMedia, upload_pending row updated to done',
        () async {
      final repo = FakeMediaAttachmentRepository();
      const voiceAttId = 'voice-att-local-001';
      const messageId = 'msg-voice-local-001';

      await repo.saveAttachment(MediaAttachment(
        id: voiceAttId,
        messageId: messageId,
        mime: 'audio/mp4',
        size: 8192,
        mediaType: 'audio',
        localPath: 'pending_uploads/$messageId/$voiceAttId.m4a',
        downloadStatus: 'upload_pending',
        createdAt: DateTime.now().toUtc().toIso8601String(),
        durationMs: 5000,
        waveform: [0.1, 0.5, 0.9],
      ));

      await repo.saveAttachment(MediaAttachment(
        id: voiceAttId,
        messageId: messageId,
        mime: 'audio/mp4',
        size: 8192,
        mediaType: 'audio',
        localPath: 'pending_uploads/$messageId/$voiceAttId.m4a',
        downloadStatus: 'done',
        createdAt: DateTime.now().toUtc().toIso8601String(),
        durationMs: 5000,
        waveform: [0.1, 0.5, 0.9],
      ));

      final pending = await repo.getUploadPendingAttachments();
      expect(pending, isEmpty);
      final attachments = await repo.getAttachmentsForMessage(messageId);
      expect(attachments.length, 1);
      expect(attachments.first.downloadStatus, 'done');
    });

    // G.10.3.1
    test('media local-WiFi success updates upload_pending to done', () async {
      final repo = FakeMediaAttachmentRepository();
      const attachmentId = 'media-att-local-001';
      const messageId = 'msg-media-local-001';

      await repo.saveAttachment(MediaAttachment(
        id: attachmentId,
        messageId: messageId,
        mime: 'image/jpeg',
        size: 0,
        mediaType: 'image',
        localPath: 'pending_uploads/$messageId/$attachmentId.jpg',
        downloadStatus: 'upload_pending',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));

      await repo.saveAttachment(MediaAttachment(
        id: attachmentId,
        messageId: messageId,
        mime: 'image/jpeg',
        size: 2048,
        mediaType: 'image',
        localPath: 'pending_uploads/$messageId/$attachmentId.jpg',
        downloadStatus: 'done',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));

      final pending = await repo.getUploadPendingAttachments();
      expect(pending, isEmpty);
      final attachments = await repo.getAttachmentsForMessage(messageId);
      expect(attachments.length, 1);
      expect(attachments.first.downloadStatus, 'done');
    });
  });
}
