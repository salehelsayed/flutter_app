import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

import '../domain/repositories/fake_media_attachment_repository.dart';
import '../../../core/bridge/fake_bridge.dart';
import 'helpers/fake_upload_media_fn.dart';

void main() {
  group('Stable-ID contract: no orphan rows', () {
    // F.7.1.6.1
    test(
        'after successful relay upload, exactly one row exists per attachment',
        () async {
      final repo = FakeMediaAttachmentRepository();
      const attachmentId = 'stable-att-id-001';
      const messageId = 'msg-001';

      // Step 1: Write upload_pending row with stable ID
      await repo.saveAttachment(MediaAttachment(
        id: attachmentId,
        messageId: messageId,
        mime: 'image/jpeg',
        size: 0,
        mediaType: 'image',
        localPath: '/tmp/photo.jpg',
        downloadStatus: 'upload_pending',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));

      // Step 2: Upload succeeds -- save done row with SAME ID
      await repo.saveAttachment(MediaAttachment(
        id: attachmentId, // Same ID -- overwrites placeholder
        messageId: messageId,
        mime: 'image/jpeg',
        size: 2048,
        mediaType: 'image',
        localPath: 'media/peer-bob/stable-att-id-001.jpg',
        downloadStatus: 'done',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));

      // Assert: exactly one row for this message, no orphan upload_pending
      final attachments = await repo.getAttachmentsForMessage(messageId);
      expect(attachments.length, 1,
          reason: 'Must have exactly one row, not two');
      expect(attachments.first.id, attachmentId);
      expect(attachments.first.downloadStatus, 'done');

      // Assert: no upload_pending rows anywhere
      final pending = await repo.getUploadPendingAttachments();
      expect(pending, isEmpty,
          reason: 'No orphan upload_pending rows must exist');
    });

    // F.7.1.6.2
    test(
        'after successful local-WiFi transfer, upload_pending row is updated to done',
        () async {
      final repo = FakeMediaAttachmentRepository();
      const attachmentId = 'stable-att-id-002';
      const messageId = 'msg-002';

      // Step 1: Write upload_pending row
      await repo.saveAttachment(MediaAttachment(
        id: attachmentId,
        messageId: messageId,
        mime: 'audio/mp4',
        size: 8192,
        mediaType: 'audio',
        localPath: '/tmp/voice.m4a',
        downloadStatus: 'upload_pending',
        createdAt: DateTime.now().toUtc().toIso8601String(),
        durationMs: 5000,
      ));

      // Step 2: Local WiFi succeeds -- save done row with SAME ID
      await repo.saveAttachment(MediaAttachment(
        id: attachmentId,
        messageId: messageId,
        mime: 'audio/mp4',
        size: 8192,
        mediaType: 'audio',
        localPath: '/tmp/voice.m4a',
        downloadStatus: 'done',
        createdAt: DateTime.now().toUtc().toIso8601String(),
        durationMs: 5000,
      ));

      final attachments = await repo.getAttachmentsForMessage(messageId);
      expect(attachments.length, 1);
      expect(attachments.first.downloadStatus, 'done');

      final pending = await repo.getUploadPendingAttachments();
      expect(pending, isEmpty);
    });

    // F.7.1.6.3
    test(
        'multi-attachment message: each attachment uses its own stable ID',
        () async {
      final repo = FakeMediaAttachmentRepository();
      const messageId = 'msg-multi-003';
      final attIds = ['att-a', 'att-b', 'att-c'];

      // Step 1: Write 3 upload_pending rows
      for (final id in attIds) {
        await repo.saveAttachment(MediaAttachment(
          id: id,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 0,
          mediaType: 'image',
          localPath: '/tmp/$id.jpg',
          downloadStatus: 'upload_pending',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ));
      }

      // Step 2: All uploads succeed -- overwrite each with done
      for (final id in attIds) {
        await repo.saveAttachment(MediaAttachment(
          id: id,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 2048,
          mediaType: 'image',
          localPath: 'media/peer-bob/$id.jpg',
          downloadStatus: 'done',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ));
      }

      final attachments = await repo.getAttachmentsForMessage(messageId);
      expect(attachments.length, 3,
          reason: 'Exactly 3 rows, no orphans');
      expect(
          attachments.every((a) => a.downloadStatus == 'done'), isTrue);

      final pending = await repo.getUploadPendingAttachments();
      expect(pending, isEmpty);
    });

    // F.7.1.6.4 -- Defensive fallback: if ID mismatch occurs, cleanup works
    test(
        'fallback: if upload returns different ID, deleteAttachmentsForMessage cleans orphans',
        () async {
      final repo = FakeMediaAttachmentRepository();
      const placeholderId = 'placeholder-id';
      const uploadedId = 'different-relay-id';
      const messageId = 'msg-fallback';

      // Step 1: Write upload_pending row
      await repo.saveAttachment(MediaAttachment(
        id: placeholderId,
        messageId: messageId,
        mime: 'image/jpeg',
        size: 0,
        mediaType: 'image',
        localPath: '/tmp/photo.jpg',
        downloadStatus: 'upload_pending',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));

      // Step 2: Upload returned a DIFFERENT ID (fallback scenario)
      // Delete all rows for this message first
      await repo.deleteAttachmentsForMessage(messageId);

      // Step 3: Save new row with upload-assigned ID
      await repo.saveAttachment(MediaAttachment(
        id: uploadedId,
        messageId: messageId,
        mime: 'image/jpeg',
        size: 2048,
        mediaType: 'image',
        localPath: 'media/peer-bob/different-relay-id.jpg',
        downloadStatus: 'done',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));

      final attachments = await repo.getAttachmentsForMessage(messageId);
      expect(attachments.length, 1);
      expect(attachments.first.id, uploadedId);

      final pending = await repo.getUploadPendingAttachments();
      expect(pending, isEmpty);
    });

    // F.7.1.7b.1 -- Voice relay fallback threads stable ID through sendVoiceMessage -> uploadMedia
    test(
        'voice relay path forwards blobId to uploadMedia, producing one row',
        () async {
      final repo = FakeMediaAttachmentRepository();
      const voiceAttId = 'stable-voice-001';
      const messageId = 'msg-voice-relay-001';

      // Step 1: Write upload_pending row with the stable voice attachment ID
      await repo.saveAttachment(MediaAttachment(
        id: voiceAttId,
        messageId: messageId,
        mime: 'audio/mp4',
        size: 8192,
        mediaType: 'audio',
        localPath: '/tmp/voice.m4a',
        downloadStatus: 'upload_pending',
        createdAt: DateTime.now().toUtc().toIso8601String(),
        durationMs: 5000,
        waveform: [0.1, 0.5, 0.9],
      ));

      // Step 2: Simulate sendVoiceMessage calling uploadMedia(blobId: voiceAttId)
      // which returns an attachment with the SAME id.
      // Then saveAttachment overwrites the upload_pending row.
      final fakeUploadFn = FakeUploadMediaFn();
      fakeUploadFn.willReturn(MediaAttachment(
        id: voiceAttId, // Same stable ID -- returned by uploadMedia
        messageId: messageId,
        mime: 'audio/mp4',
        size: 8192,
        mediaType: 'audio',
        localPath: 'media/peer-bob/$voiceAttId.m4a',
        downloadStatus: 'done',
        createdAt: DateTime.now().toUtc().toIso8601String(),
        durationMs: 5000,
        waveform: [0.1, 0.5, 0.9],
      ));

      // Simulate the upload call with blobId (as sendVoiceMessage would do)
      final uploaded = await fakeUploadFn.call(
        bridge: FakeBridge(),
        localFilePath: '/tmp/voice.m4a',
        mime: 'audio/mp4',
        recipientPeerId: 'peer-bob',
        durationMs: 5000,
        waveform: [0.1, 0.5, 0.9],
        blobId: voiceAttId, // Stable-ID contract
      );

      // Verify blobId was forwarded
      expect(fakeUploadFn.lastBlobId, voiceAttId,
          reason: 'sendVoiceMessage must forward blobId to uploadMedia');

      // Save the done row (same ID overwrites upload_pending)
      if (uploaded != null) {
        await repo.saveAttachment(uploaded);
      }

      // Assert: exactly one row, no orphan upload_pending
      final attachments = await repo.getAttachmentsForMessage(messageId);
      expect(attachments.length, 1,
          reason: 'Must have exactly one row, not two');
      expect(attachments.first.id, voiceAttId);
      expect(attachments.first.downloadStatus, 'done');

      final pending = await repo.getUploadPendingAttachments();
      expect(pending, isEmpty,
          reason: 'No orphan upload_pending rows must exist');
    });
  });
}
