import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

MediaAttachment _attachment({
  required String id,
  String downloadStatus = 'upload_pending',
  int? uploadRetryCount,
  String? localPath,
}) {
  return MediaAttachment(
    id: id,
    messageId: 'message-1',
    mime: 'application/pdf',
    size: 42,
    mediaType: 'file',
    localPath: localPath,
    downloadStatus: downloadStatus,
    uploadRetryCount: uploadRetryCount,
    createdAt: '2026-07-19T00:00:00.000Z',
  );
}

void main() {
  group('isManualUploadRetryAttachmentSetEligible', () {
    bool qualify(List<MediaAttachment> attachments) =>
        isManualUploadRetryAttachmentSetEligible(
          attachments,
          sourceExists: (path) => path.startsWith('/exists/'),
        );

    test('accepts completed envelopes and complete retryable source sets', () {
      expect(
        qualify([_attachment(id: 'done', downloadStatus: 'done')]),
        isTrue,
      );
      expect(
        qualify([
          _attachment(id: 'pending', localPath: '/exists/pending.pdf'),
          _attachment(
            id: 'terminal',
            downloadStatus: 'upload_failed',
            uploadRetryCount: kMaxUploadRetries,
            localPath: '/exists/terminal.pdf',
          ),
        ]),
        isTrue,
      );
    });

    test('fails closed for empty, partial, missing, and over-limit sets', () {
      expect(qualify(const []), isFalse);
      expect(
        qualify([
          _attachment(
            id: 'below-ceiling',
            downloadStatus: 'upload_failed',
            uploadRetryCount: kMaxUploadRetries - 1,
            localPath: '/exists/below.pdf',
          ),
        ]),
        isFalse,
      );
      expect(
        qualify([
          _attachment(
            id: 'missing',
            downloadStatus: 'upload_failed',
            uploadRetryCount: kMaxUploadRetries,
            localPath: '/missing/source.pdf',
          ),
        ]),
        isFalse,
      );
      expect(
        qualify([
          _attachment(id: 'pending', localPath: '/exists/pending.pdf'),
          _attachment(
            id: 'cancelled',
            downloadStatus: 'upload_cancelled',
            localPath: '/exists/cancelled.pdf',
          ),
        ]),
        isFalse,
      );
      expect(
        qualify([
          for (var i = 0; i < kReuploadMaxAttachmentsPerMessage + 1; i++)
            _attachment(id: 'over-$i', localPath: '/exists/$i.pdf'),
        ]),
        isFalse,
      );
    });
  });
}
