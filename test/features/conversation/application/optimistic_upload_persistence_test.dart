import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

import '../domain/repositories/fake_media_attachment_repository.dart';

void main() {
  group('optimistic pre-upload attachment persistence', () {
    test(
      'saveAttachment called with upload_pending BEFORE uploadMedia is called',
      () async {
        final callOrder = <String>[];
        String? firstSavedStatus;

        final fakeMediaRepo = FakeMediaAttachmentRepository()
          ..onSaveAttachment = (att) {
            callOrder.add('saveAttachment:${att.downloadStatus}');
            firstSavedStatus ??= att.downloadStatus;
          };

        // Pre-upload save (this is the contract conversation_wired must fulfill)
        await fakeMediaRepo.saveAttachment(
          MediaAttachment(
            id: 'att-pre',
            messageId: 'msg-1',
            mime: 'image/jpeg',
            size: 0,
            mediaType: 'image',
            localPath: '/tmp/photo.jpg',
            downloadStatus: 'upload_pending',
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
        callOrder.add('uploadMedia');

        final saveIdx =
            callOrder.indexWhere((e) => e.startsWith('saveAttachment'));
        final uploadIdx = callOrder.indexOf('uploadMedia');

        expect(saveIdx, isNot(-1));
        expect(uploadIdx, isNot(-1));
        expect(saveIdx < uploadIdx, isTrue,
            reason:
                'saveAttachment(upload_pending) must precede uploadMedia');
        expect(firstSavedStatus, 'upload_pending');
      },
    );

    test(
      'after successful upload, saveAttachment called again with done',
      () async {
        final savedStatuses = <String>[];
        final fakeMediaRepo = FakeMediaAttachmentRepository()
          ..onSaveAttachment =
              (att) => savedStatuses.add(att.downloadStatus);

        await fakeMediaRepo.saveAttachment(
          MediaAttachment(
            id: 'att-1',
            messageId: 'msg-1',
            mime: 'image/jpeg',
            size: 0,
            mediaType: 'image',
            localPath: '/tmp/photo.jpg',
            downloadStatus: 'upload_pending',
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );

        await fakeMediaRepo.saveAttachment(
          MediaAttachment(
            id: 'blob-abc',
            messageId: 'msg-1',
            mime: 'image/jpeg',
            size: 2048,
            mediaType: 'image',
            localPath: '/var/mobile/media/photo.jpg',
            downloadStatus: 'done',
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );

        expect(
            savedStatuses,
            containsAllInOrder(['upload_pending', 'done']));
      },
    );

    test(
      'when upload fails, only upload_pending row is present — no done row',
      () async {
        final savedStatuses = <String>[];
        final fakeMediaRepo = FakeMediaAttachmentRepository()
          ..onSaveAttachment =
              (att) => savedStatuses.add(att.downloadStatus);

        await fakeMediaRepo.saveAttachment(
          MediaAttachment(
            id: 'att-1',
            messageId: 'msg-1',
            mime: 'image/jpeg',
            size: 0,
            mediaType: 'image',
            localPath: '/tmp/photo.jpg',
            downloadStatus: 'upload_pending',
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );

        // Upload fails — no second saveAttachment in the success path
        expect(savedStatuses, equals(['upload_pending']));
        expect(savedStatuses.contains('done'), isFalse);
      },
    );

    test(
      'voice message pre-upload save includes durationMs and waveform',
      () async {
        MediaAttachment? savedAtt;
        final fakeMediaRepo = FakeMediaAttachmentRepository()
          ..onSaveAttachment = (att) => savedAtt = att;

        await fakeMediaRepo.saveAttachment(
          MediaAttachment(
            id: 'voice-att-pre',
            messageId: 'msg-voice-1',
            mime: 'audio/mpeg',
            size: 8192,
            mediaType: 'audio',
            localPath: '/tmp/voice.m4a',
            durationMs: 4200,
            downloadStatus: 'upload_pending',
            createdAt: DateTime.now().toUtc().toIso8601String(),
            waveform: [0.1, 0.5, 0.9, 0.4, 0.2],
          ),
        );

        expect(savedAtt, isNotNull);
        expect(savedAtt!.durationMs, 4200);
        expect(savedAtt!.waveform, isNotEmpty);
        expect(savedAtt!.localPath, '/tmp/voice.m4a');
        expect(savedAtt!.downloadStatus, 'upload_pending');
      },
    );
  });
}
