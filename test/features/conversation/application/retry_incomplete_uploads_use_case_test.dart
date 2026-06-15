import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/retry_incomplete_uploads_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../domain/repositories/fake_media_attachment_repository.dart';
import '../domain/repositories/fake_message_repository.dart';
import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';
import 'helpers/fake_upload_media_fn.dart';

Future<List<Map<String, dynamic>>> captureFlowEvents(
  Future<void> Function() action,
) async {
  final printed = <String>[];
  final previousLogging = flowEventLoggingEnabled;
  final originalDebugPrint = debugPrint;
  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      printed.add(message);
    }
  };
  try {
    await action();
  } finally {
    debugPrint = originalDebugPrint;
    flowEventLoggingEnabled = previousLogging;
  }

  return printed
      .where((line) => line.startsWith('[FLOW] '))
      .map(
        (line) =>
            jsonDecode(line.substring('[FLOW] '.length))
                as Map<String, dynamic>,
      )
      .toList();
}

const _testContentHash =
    'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef';

MediaAttachment _pendingAtt({
  String id = 'att-00001',
  String messageId = 'msg-00001',
  String localPath = '/tmp/recording.m4a',
  String mime = 'audio/mpeg',
  int? durationMs = 3000,
  String mediaType = 'audio',
}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: mime,
    size: 4096,
    mediaType: mediaType,
    localPath: localPath,
    durationMs: durationMs,
    downloadStatus: 'upload_pending',
    createdAt: DateTime.now().toUtc().toIso8601String(),
  );
}

ConversationMessage _makeMsg(
  String id, {
  required String status,
  String contactPeerId = 'peer-bob-001',
}) {
  final now = DateTime.now().toUtc().toIso8601String();
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'peer-alice-001',
    text: 'test-text',
    timestamp: now,
    status: status,
    isIncoming: false,
    createdAt: now,
  );
}

MediaAttachment _doneAttachment(
  String id,
  String messageId, {
  String mime = 'audio/mpeg',
}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: mime,
    size: 4096,
    mediaType: MediaAttachment.mediaTypeFromMime(mime),
    localPath: '/tmp/recording.m4a',
    downloadStatus: 'done',
    createdAt: DateTime.now().toUtc().toIso8601String(),
    contentHash: _testContentHash,
    encryptionKeyBase64: 'test-blob-key-base64',
    encryptionNonce: 'test-blob-nonce',
    encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
  );
}

ContactModel _contactWithMlKem(String peerId) {
  final now = DateTime.now().toUtc().toIso8601String();
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/relay/tcp/443/p2p/relay',
    username: 'Contact-$peerId',
    signature: 'sig-$peerId',
    scannedAt: now,
    mlKemPublicKey: 'mlkem-$peerId',
  );
}

void main() {
  late FakeMediaAttachmentRepository mediaRepo;
  late FakeMessageRepository messageRepo;
  late FakeBridge bridge;
  late FakeP2PService p2pService;
  late FakeIdentityRepository identityRepo;
  late FakeContactRepository contactRepo;
  late FakeUploadMediaFn fakeUploadFn;

  setUp(() {
    mediaRepo = FakeMediaAttachmentRepository();
    messageRepo = FakeMessageRepository();
    bridge = FakeBridge();
    p2pService = FakeP2PService(
      initialState: const NodeState(
        isStarted: true,
        peerId: 'peer-alice',
        circuitAddresses: ['/p2p-circuit/addr1'],
      ),
      storeInInboxResult: true,
    );
    identityRepo = FakeIdentityRepository();
    contactRepo = FakeContactRepository();
    contactRepo.seed([
      _contactWithMlKem('peer-bob'),
      _contactWithMlKem('peer-bob-001'),
    ]);
    fakeUploadFn = FakeUploadMediaFn();
  });

  group('retryIncompleteUploads', () {
    test('returns 0 when no upload_pending attachments exist', () async {
      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
      );
      expect(count, 0);
    });

    test('returns 0 when identity cannot be loaded', () async {
      mediaRepo.seed([_pendingAtt()]);
      // identityRepo has no seeded identity

      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
      );
      expect(count, 0);
    });

    test('skips message whose parent message row does not exist', () async {
      mediaRepo.seed([_pendingAtt(messageId: 'nonexistent-msg')]);
      identityRepo.seed(FakeIdentityRepository.makeIdentity());

      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
      );
      expect(count, 0);
    });

    test('skips message when parent message is already delivered', () async {
      final msg = _makeMsg('msg-00001', status: 'delivered');
      messageRepo.seed([msg]);
      mediaRepo.seed([_pendingAtt(messageId: 'msg-00001')]);
      identityRepo.seed(FakeIdentityRepository.makeIdentity());

      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
      );
      expect(count, 0);
    });

    test(
      'skips message when any attachment has null localPath — marks ALL as upload_failed',
      () async {
        final noPathAtt = MediaAttachment(
          id: 'att-no-path',
          messageId: 'msg-00001',
          mime: 'image/jpeg',
          size: 1024,
          mediaType: 'image',
          localPath: null,
          downloadStatus: 'upload_pending',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        );
        final msg = _makeMsg('msg-00001', status: 'failed');
        messageRepo.seed([msg]);
        mediaRepo.seed([noPathAtt]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
        );
        expect(count, 0);
        // Attachment should be marked upload_failed
        expect(mediaRepo.lastSavedAttachment?.downloadStatus, 'upload_failed');
      },
    );

    test(
      'first transient upload failure keeps ALL attachments as upload_pending with retryCount=1',
      () async {
        final msg = _makeMsg(
          'msg-00001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        mediaRepo.seed([
          _pendingAtt(
            id: 'att-00001',
            messageId: 'msg-00001',
            localPath: '/tmp/img1.jpg',
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
          _pendingAtt(
            id: 'att-00002',
            messageId: 'msg-00001',
            localPath: '/tmp/img2.jpg',
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
        ]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        fakeUploadFn.willReturn(null); // transient failure

        await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        // Both attachments stay upload_pending (transient, retryable)
        final pending = await mediaRepo.getUploadPendingAttachments();
        expect(pending.length, 2);
        expect(
          pending.every((a) => a.uploadRetryCount == 1),
          isTrue,
          reason: 'retryCount must be incremented to 1',
        );
        expect(
          p2pService.storeInInboxCallCount,
          0,
          reason: 'sendChatMessage must not be called on failed upload',
        );
      },
    );

    test(
      'transient upload failure does not downgrade an attachment completed concurrently',
      () async {
        final msg = _makeMsg(
          'msg-00001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        final pending = _pendingAtt(
          id: 'att-00001',
          messageId: 'msg-00001',
          localPath: '/tmp/img1.jpg',
          mime: 'image/jpeg',
          mediaType: 'image',
        ).copyWith(uploadRetryCount: kMaxUploadRetries - 1);
        messageRepo.seed([msg]);
        mediaRepo.seed([pending]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                mediaFileManager,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
                blobId,
                deleteSourceWhenDone = false,
                preparedArtifact,
              }) async {
                await mediaRepo.saveAttachment(
                  pending.copyWith(downloadStatus: 'done'),
                );
                return null;
              },
        );

        final attachments = await mediaRepo.getAttachmentsForMessage(
          'msg-00001',
        );
        expect(count, 0);
        expect(attachments.single.downloadStatus, 'done');
        expect(
          mediaRepo.allSavedAttachments
              .where(
                (attachment) =>
                    attachment.id == 'att-00001' &&
                    attachment.downloadStatus == 'upload_failed',
              )
              .isEmpty,
          isTrue,
        );
      },
    );

    test(
      'completed upload result does not overwrite a concurrently cancelled attachment',
      () async {
        final msg = _makeMsg(
          'msg-00001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        final pending = _pendingAtt(
          id: 'att-00001',
          messageId: 'msg-00001',
          localPath: '/tmp/img1.jpg',
          mime: 'image/jpeg',
          mediaType: 'image',
        );
        messageRepo.seed([msg]);
        mediaRepo.seed([pending]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                mediaFileManager,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
                blobId,
                deleteSourceWhenDone = false,
                preparedArtifact,
              }) async {
                await mediaRepo.saveAttachment(
                  pending.copyWith(downloadStatus: 'upload_cancelled'),
                );
                return _doneAttachment('att-00001', 'msg-00001');
              },
        );

        final attachments = await mediaRepo.getAttachmentsForMessage(
          'msg-00001',
        );
        expect(count, 0);
        expect(attachments.single.downloadStatus, 'upload_cancelled');
        expect(p2pService.storeInInboxCallCount, 0);
      },
    );

    test(
      'transient failure: attachment IS retried on second call (still upload_pending)',
      () async {
        final msg = _makeMsg(
          'msg-00001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        mediaRepo.seed([_pendingAtt(messageId: 'msg-00001')]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        fakeUploadFn.willReturn(null); // transient failure

        // First attempt: retryCount 0 -> 1, stays upload_pending
        await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        // Second attempt: still upload_pending, so it IS retried
        final pending = await mediaRepo.getUploadPendingAttachments();
        expect(
          pending.length,
          1,
          reason: 'Row must still be upload_pending after first failure',
        );

        // Now succeed on second attempt
        fakeUploadFn.willReturn(_doneAttachment('blob-uploaded', 'msg-00001'));

        final count2 = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );
        expect(count2, 1, reason: 'Second attempt should succeed');
      },
    );

    test(
      'upload_failed attachment is not picked up after kMaxUploadRetries exhaustion',
      () async {
        final msg = _makeMsg(
          'msg-00001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        // Seed with retryCount already at kMaxUploadRetries - 1
        mediaRepo.seed([
          _pendingAtt(
            messageId: 'msg-00001',
          ).copyWith(uploadRetryCount: kMaxUploadRetries - 1),
        ]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        fakeUploadFn.willReturn(null);

        await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        // Now upload_failed -- not picked up on next call
        final pending = await mediaRepo.getUploadPendingAttachments();
        expect(
          pending,
          isEmpty,
          reason: 'Row must be upload_failed after max retries',
        );

        final count2 = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );
        expect(count2, 0);
      },
    );

    test(
      'returns 1 after successful re-upload and send (single attachment)',
      () async {
        final msg = _makeMsg(
          'msg-00001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        mediaRepo.seed([_pendingAtt(messageId: 'msg-00001')]);
        fakeUploadFn.willReturn(_doneAttachment('blob-uploaded', 'msg-00001'));

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );
        expect(count, 1);
      },
    );

    test(
      'emits RETRY_INCOMPLETE_UPLOADS_TIMING with attachment and message counts',
      () async {
        final msg = _makeMsg(
          'msg-00001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        mediaRepo.seed([_pendingAtt(messageId: 'msg-00001')]);
        fakeUploadFn.willReturn(_doneAttachment('blob-uploaded', 'msg-00001'));

        final events = await captureFlowEvents(() async {
          await retryIncompleteUploads(
            mediaAttachmentRepo: mediaRepo,
            messageRepo: messageRepo,
            bridge: bridge,
            p2pService: p2pService,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            uploadMediaFn: fakeUploadFn.call,
          );
        });

        final timing = events.lastWhere(
          (event) => event['event'] == 'RETRY_INCOMPLETE_UPLOADS_TIMING',
        );
        expect(timing['details']['outcome'], 'complete');
        expect(timing['details']['attachmentCount'], 1);
        expect(timing['details']['messageCount'], 1);
        expect(timing['details']['succeeded'], 1);
        expect(timing['details']['elapsedMs'], isA<int>());
      },
    );

    test('also retries when message is still in sending status', () async {
      final msg = _makeMsg(
        'msg-00001',
        status: 'sending',
        contactPeerId: 'peer-bob',
      );
      messageRepo.seed([msg]);
      identityRepo.seed(FakeIdentityRepository.makeIdentity());
      mediaRepo.seed([_pendingAtt(messageId: 'msg-00001')]);
      fakeUploadFn.willReturn(_doneAttachment('blob-id', 'msg-00001'));

      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        uploadMediaFn: fakeUploadFn.call,
      );
      expect(count, 1);
    });

    test(
      'skips the final send when the message is deleted after upload work completes',
      () async {
        final msg = _makeMsg(
          'msg-late-delete',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        var deleted = false;
        messageRepo.seed([msg]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        mediaRepo.seed([_pendingAtt(messageId: msg.id)]);
        mediaRepo.onSaveAttachment = (attachment) {
          if (!deleted &&
              attachment.messageId == msg.id &&
              attachment.downloadStatus == 'done') {
            deleted = true;
            messageRepo.deleteMessage(msg.id);
          }
        };
        fakeUploadFn.willReturn(_doneAttachment('blob-uploaded', msg.id));

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        expect(count, 0);
        expect(await messageRepo.getMessage(msg.id), isNull);
        expect(
          p2pService.storeInInboxCallCount,
          0,
          reason: 'late-send guard must suppress sendChatMessage',
        );
      },
    );

    // ---- Multi-attachment per-message tests ----

    test(
      'multi-attachment message: uploads ALL then sends ONCE with full list',
      () async {
        final msg = _makeMsg(
          'msg-multi-001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        mediaRepo.seed([
          _pendingAtt(
            id: 'att-0000a',
            messageId: 'msg-multi-001',
            localPath: '/tmp/img1.jpg',
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
          _pendingAtt(
            id: 'att-0000b',
            messageId: 'msg-multi-001',
            localPath: '/tmp/img2.jpg',
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
          _pendingAtt(
            id: 'att-0000c',
            messageId: 'msg-multi-001',
            localPath: '/tmp/img3.jpg',
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
        ]);
        fakeUploadFn.willReturnForPath(
          '/tmp/img1.jpg',
          _doneAttachment('blob-a', 'msg-multi-001', mime: 'image/jpeg'),
        );
        fakeUploadFn.willReturnForPath(
          '/tmp/img2.jpg',
          _doneAttachment('blob-b', 'msg-multi-001', mime: 'image/jpeg'),
        );
        fakeUploadFn.willReturnForPath(
          '/tmp/img3.jpg',
          _doneAttachment('blob-c', 'msg-multi-001', mime: 'image/jpeg'),
        );

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        // ONE message successfully sent
        expect(count, 1);
        // uploadMedia called 3 times (once per attachment)
        expect(fakeUploadFn.callCount, 3);
        // sendChatMessage called ONCE (inbox path)
        expect(p2pService.storeInInboxCallCount, 1);
        // The wire payload should contain ALL 3 blob IDs
        final payload = p2pService.lastStoreInInboxMessage!;
        expect(payload, contains('blob-a'));
        expect(payload, contains('blob-b'));
        expect(payload, contains('blob-c'));
      },
    );

    test(
      'multi-attachment: second upload fails -> ALL stay upload_pending (transient), sendChatMessage NOT called',
      () async {
        final msg = _makeMsg(
          'msg-multi-001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        mediaRepo.seed([
          _pendingAtt(
            id: 'att-0000a',
            messageId: 'msg-multi-001',
            localPath: '/tmp/img1.jpg',
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
          _pendingAtt(
            id: 'att-0000b',
            messageId: 'msg-multi-001',
            localPath: '/tmp/img2.jpg',
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
        ]);
        // First upload succeeds, second returns null (transient)
        fakeUploadFn.willReturnForPath(
          '/tmp/img1.jpg',
          _doneAttachment('blob-a', 'msg-multi-001', mime: 'image/jpeg'),
        );
        fakeUploadFn.willReturnForPath('/tmp/img2.jpg', null);

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        expect(count, 0);
        expect(
          p2pService.storeInInboxCallCount,
          0,
          reason: 'must NOT send partial attachment list',
        );
        // Both original attachments for the message should stay upload_pending
        final pending = await mediaRepo.getUploadPendingAttachments();
        expect(pending.length, 2, reason: 'Both rows must stay upload_pending');
        expect(pending.every((a) => a.uploadRetryCount == 1), isTrue);
      },
    );

    test(
      'non-fatal: transient error on first message does not prevent processing second message',
      () async {
        final msg1 = _makeMsg(
          'msg-00001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        final msg2 = _makeMsg(
          'msg-00002',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg1, msg2]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        mediaRepo.seed([
          _pendingAtt(
            id: 'att-00001',
            messageId: 'msg-00001',
            localPath: '/tmp/file1.m4a',
          ),
          _pendingAtt(
            id: 'att-00002',
            messageId: 'msg-00002',
            localPath: '/tmp/file2.m4a',
          ),
        ]);
        fakeUploadFn.willReturnForPath('/tmp/file1.m4a', null); // transient
        fakeUploadFn.willReturnForPath(
          '/tmp/file2.m4a',
          _doneAttachment('blob-2', 'msg-00002'),
        );

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );
        // msg-1 deferred (transient), msg-2 succeeded
        expect(count, 1);
        // sendChatMessage called once (for msg-2 only)
        expect(p2pService.storeInInboxCallCount, 1);
        // att-1 stays upload_pending (retryable on next cycle)
        final pending = await mediaRepo.getUploadPendingAttachments();
        expect(pending.any((a) => a.id == 'att-00001'), isTrue);
      },
    );

    test(
      'two messages each with multiple attachments: independent recovery',
      () async {
        final msg1 = _makeMsg(
          'msg-00001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        final msg2 = _makeMsg(
          'msg-00002',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg1, msg2]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        mediaRepo.seed([
          _pendingAtt(
            id: 'att-001-a',
            messageId: 'msg-00001',
            localPath: '/tmp/1a.jpg',
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
          _pendingAtt(
            id: 'att-001-b',
            messageId: 'msg-00001',
            localPath: '/tmp/1b.jpg',
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
          _pendingAtt(
            id: 'att-002-a',
            messageId: 'msg-00002',
            localPath: '/tmp/2a.jpg',
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
        ]);
        fakeUploadFn.willReturnForPath(
          '/tmp/1a.jpg',
          _doneAttachment('blob-1a', 'msg-00001', mime: 'image/jpeg'),
        );
        fakeUploadFn.willReturnForPath(
          '/tmp/1b.jpg',
          _doneAttachment('blob-1b', 'msg-00001', mime: 'image/jpeg'),
        );
        fakeUploadFn.willReturnForPath(
          '/tmp/2a.jpg',
          _doneAttachment('blob-2a', 'msg-00002', mime: 'image/jpeg'),
        );

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        expect(count, 2); // both messages recovered
        expect(fakeUploadFn.callCount, 3); // 3 uploads total
        expect(
          p2pService.storeInInboxCallCount,
          2,
        ); // 2 sends (one per message)
      },
    );

    // G.8.2.1
    test(
      'first upload failure keeps row as upload_pending (retryable)',
      () async {
        final msg = _makeMsg(
          'msg-test-t1',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        mediaRepo.seed([
          _pendingAtt(
            id: 'att-test-t1',
            messageId: 'msg-test-t1',
            localPath: '/durable/photo.jpg',
          ),
        ]);
        fakeUploadFn.willReturn(null); // transient failure

        await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        final pending = await mediaRepo.getUploadPendingAttachments();
        expect(pending.length, 1);
        expect(pending.first.uploadRetryCount, 1);
        expect(pending.first.downloadStatus, 'upload_pending');
      },
    );

    // G.8.2.2
    test(
      'after kMaxUploadRetries failures, row transitions to upload_failed',
      () async {
        final msg = _makeMsg(
          'msg-test-t2',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        mediaRepo.seed([
          _pendingAtt(
            id: 'att-test-t2',
            messageId: 'msg-test-t2',
            localPath: '/durable/photo.jpg',
          ).copyWith(uploadRetryCount: kMaxUploadRetries - 1),
        ]);
        fakeUploadFn.willReturn(null);

        await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        final pending = await mediaRepo.getUploadPendingAttachments();
        expect(pending, isEmpty);
        final lastSaved = mediaRepo.lastSavedAttachment;
        expect(lastSaved?.downloadStatus, 'upload_failed');
        expect(lastSaved?.uploadRetryCount, kMaxUploadRetries);
      },
    );

    // G.8.2.3
    test(
      'missing local file is immediately terminal regardless of retryCount',
      () async {
        final msg = _makeMsg(
          'msg-test-t3',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        mediaRepo.seed([
          MediaAttachment(
            id: 'att-test-t3',
            messageId: 'msg-test-t3',
            mime: 'image/jpeg',
            size: 0,
            mediaType: 'image',
            localPath: null,
            downloadStatus: 'upload_pending',
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        ]);

        await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        final lastSaved = mediaRepo.lastSavedAttachment;
        expect(lastSaved?.downloadStatus, 'upload_failed');
      },
    );

    // G.8.3.1
    test(
      'partial upload crash: re-uploads only pending, combines with done',
      () async {
        final msg = _makeMsg(
          'msg-partial-001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());

        mediaRepo.seed([
          _doneAttachment('att-done-1', 'msg-partial-001', mime: 'image/jpeg'),
          _doneAttachment('att-done-2', 'msg-partial-001', mime: 'image/jpeg'),
          _pendingAtt(
            id: 'att-pending-3',
            messageId: 'msg-partial-001',
            localPath: '/durable/img3.jpg',
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
        ]);

        fakeUploadFn.willReturn(
          _doneAttachment(
            'att-pending-3',
            'msg-partial-001',
            mime: 'image/jpeg',
          ),
        );

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        expect(count, 1);
        expect(fakeUploadFn.callCount, 1);
        expect(p2pService.storeInInboxCallCount, 1);
        final payload = p2pService.lastStoreInInboxMessage!;
        expect(payload, contains('att-done-1'));
        expect(payload, contains('att-done-2'));
        expect(payload, contains('att-pending-3'));
      },
    );

    test(
      'partial upload crash re-uploads only pending GIF and keeps done JPEG sibling',
      () async {
        final msg = _makeMsg(
          'msg-gif-partial-001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());

        mediaRepo.seed([
          _doneAttachment(
            'att-jpeg-done',
            'msg-gif-partial-001',
            mime: 'image/jpeg',
          ),
          _pendingAtt(
            id: 'att-gif-pending',
            messageId: 'msg-gif-partial-001',
            localPath: '/durable/funny.gif',
            mime: 'image/gif',
            mediaType: 'image',
            durationMs: null,
          ),
        ]);

        fakeUploadFn.willReturn(
          _doneAttachment(
            'att-gif-pending',
            'msg-gif-partial-001',
            mime: 'image/gif',
          ),
        );

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        expect(count, 1);
        expect(fakeUploadFn.callCount, 1);
        expect(fakeUploadFn.lastMime, 'image/gif');
        expect(fakeUploadFn.lastBlobId, 'att-gif-pending');
        final payload = p2pService.lastStoreInInboxMessage!;
        expect(payload, contains('att-jpeg-done'));
        expect(payload, contains('att-gif-pending'));
        final envelope = jsonDecode(payload) as Map<String, dynamic>;
        final encrypted = envelope['encrypted'] as Map<String, dynamic>;
        final ciphertext = encrypted['ciphertext'] as String;
        expect(ciphertext, contains('"mime":"image/gif"'));
      },
    );

    // G.10.1.1
    test(
      'retry after interrupted sendLocalMedia uses relay, not local WiFi',
      () async {
        final msg = _makeMsg(
          'msg-voice-local-001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        mediaRepo.seed([
          _pendingAtt(
            id: 'voice-local-att',
            messageId: 'msg-voice-local-001',
            localPath: '/tmp/voice.m4a',
            mime: 'audio/mp4',
            mediaType: 'audio',
            durationMs: 3000,
          ),
        ]);
        fakeUploadFn.willReturn(
          _doneAttachment(
            'voice-local-att',
            'msg-voice-local-001',
            mime: 'audio/mp4',
          ),
        );

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        expect(count, 1);
        expect(fakeUploadFn.callCount, 1);
        expect(
          p2pService.sendLocalMediaCallCount,
          0,
          reason: 'Retry must use relay, not local WiFi',
        );
      },
    );
  });

  // --- 112 Phase 3: retry/replay key coherence (KC-2) ---
  // These wire the REAL uploadMedia (not the typedef stub): R6 — the
  // stubbed suite above stays green while crypto behavior changes
  // underneath and cannot observe key minting or envelope coherence.
  group('KC-2 key coherence', () {
    late Directory tempDir;
    late File sourceFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('kc2_retry_');
      sourceFile = File('${tempDir.path}/recording.m4a');
      await sourceFile.writeAsBytes(List<int>.filled(4096, 0x42), flush: true);
      identityRepo.seed(
        FakeIdentityRepository.makeIdentity(peerId: 'peer-alice-001'),
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    MediaAttachment seedOldKeyPending() =>
        _pendingAtt(localPath: sourceFile.path).copyWith(
          contentHash: _testContentHash,
          encryptionKeyBase64: 'old-key',
          encryptionNonce: 'old-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );

    test(
      'retry re-encrypts with a fresh key and persists updated metadata to '
      'the attachment row',
      () async {
        // Green-on-arrival pin in plan order (1→2→3): after Phase 2 the
        // real uploadMedia mints a fresh key per call and retry persists
        // the re-uploaded attachment row.
        await messageRepo.saveMessage(_makeMsg('msg-00001', status: 'failed'));
        await mediaRepo.saveAttachment(seedOldKeyPending());

        final realBridge = PassthroughCryptoBridge();
        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: realBridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
        );

        expect(count, 1);
        expect(
          realBridge.commandLog,
          containsAllInOrder(['blob:keygen', 'blob:encrypt', 'media:upload']),
        );
        final row = (await mediaRepo.getAttachmentsForMessage(
          'msg-00001',
        )).single;
        expect(row.downloadStatus, 'done');
        expect(row.encryptionKeyBase64, isNotNull);
        expect(row.encryptionKeyBase64, isNot('old-key'));
        expect(row.encryptionNonce, isNot('old-nonce'));
      },
    );

    test('retry never reuses a prior key for a new blob:encrypt call', () async {
      // Green-on-arrival pin (KC-2 defense-in-depth): distinct blobs get
      // distinct keys even within one retry pass.
      final secondFile = File('${tempDir.path}/second.m4a');
      await secondFile.writeAsBytes(List<int>.filled(2048, 0x17), flush: true);
      await messageRepo.saveMessage(_makeMsg('msg-00001', status: 'failed'));
      await mediaRepo.saveAttachment(seedOldKeyPending());
      await mediaRepo.saveAttachment(
        _pendingAtt(
          id: 'att-00002',
          messageId: 'msg-00001',
          localPath: secondFile.path,
        ),
      );

      final realBridge = PassthroughCryptoBridge();
      await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: realBridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
      );

      final rows = await mediaRepo.getAttachmentsForMessage('msg-00001');
      final keys = rows
          .map((row) => row.encryptionKeyBase64)
          .whereType<String>()
          .toSet();
      expect(rows, hasLength(2));
      expect(keys, hasLength(2), reason: 'each blob must get a fresh key');
    });

    test(
      'successful re-upload with changed key invalidates the persisted wire '
      'envelope of the parent message',
      () async {
        // THE genuine RED of this phase: the Section-4 replay contract
        // persists the envelope verbatim while retry re-encrypts the blob
        // under a new key — a replayed stale envelope would reference a
        // dead key (undecryptable media). Node is STOPPED so the rebuild
        // inside this use case cannot mask the invalidation.
        await messageRepo.saveMessage(
          _makeMsg(
            'msg-00001',
            status: 'failed',
          ).copyWith(wireEnvelope: '{"stale":"envelope-with-old-key"}'),
        );
        await mediaRepo.saveAttachment(seedOldKeyPending());
        p2pService.emitState(NodeState.stopped);

        final realBridge = PassthroughCryptoBridge();
        await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: realBridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
        );

        final row = (await mediaRepo.getAttachmentsForMessage(
          'msg-00001',
        )).single;
        expect(row.encryptionKeyBase64, isNot('old-key'));
        final message = await messageRepo.getMessage('msg-00001');
        expect(
          message!.wireEnvelope,
          isNull,
          reason:
              'the stale envelope referencing the dead key must be '
              'invalidated so no replay path can ship it',
        );
      },
    );

    test(
      're-sent message after media re-upload carries the attachment row\'s '
      'current key in its envelope',
      () async {
        // End-to-end KC-2 contract: the envelope persisted after the
        // retry's rebuild references the row's CURRENT key.
        await messageRepo.saveMessage(
          _makeMsg(
            'msg-00001',
            status: 'failed',
          ).copyWith(wireEnvelope: '{"stale":"envelope-with-old-key"}'),
        );
        await mediaRepo.saveAttachment(seedOldKeyPending());

        final realBridge = PassthroughCryptoBridge();
        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: realBridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
        );

        expect(count, 1);
        final row = (await mediaRepo.getAttachmentsForMessage(
          'msg-00001',
        )).single;
        final rebuiltEnvelope = messageRepo.lastWireEnvelopeValue;
        expect(rebuiltEnvelope, isNotNull);
        final envelope = jsonDecode(rebuiltEnvelope!) as Map<String, dynamic>;
        final inner =
            jsonDecode(
                  (envelope['encrypted'] as Map<String, dynamic>)['ciphertext']
                      as String,
                )
                as Map<String, dynamic>;
        final media = inner['media'] as List<dynamic>;
        final wireAttachment = media.single as Map<String, dynamic>;
        expect(wireAttachment['encryptionKeyBase64'], row.encryptionKeyBase64);
        expect(wireAttachment['encryptionNonce'], row.encryptionNonce);
      },
    );
  });
}
