import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/media_upload_in_flight_tracker.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart'
    as p2p;

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../features/conversation/domain/repositories/fake_media_attachment_repository.dart';
import '../../../features/conversation/domain/repositories/fake_message_repository.dart';
import '../../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import 'helpers/fake_upload_media_fn.dart';

class _FakeDirectManualUploadRetryRearmRepository
    implements DirectManualUploadRetryRearmRepository {
  _FakeDirectManualUploadRetryRearmRepository({
    required this.messageRepo,
    required this.mediaAttachmentRepo,
  });

  final FakeMessageRepository messageRepo;
  final FakeMediaAttachmentRepository mediaAttachmentRepo;
  int callCount = 0;
  bool willApply = true;
  List<ManualUploadRetryAttachmentExpectation>? lastExpectations;

  @override
  Future<bool> rearmUploadRetryForManualRetry({
    required String messageId,
    required List<ManualUploadRetryAttachmentExpectation> attachments,
  }) async {
    callCount++;
    lastExpectations = List.unmodifiable(attachments);
    if (!willApply) return false;
    final parent = await messageRepo.getMessage(messageId);
    if (parent == null || parent.isIncoming || parent.status != 'failed') {
      return false;
    }
    final persisted = await mediaAttachmentRepo.getAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.direct,
    );
    final unfinished = persisted
        .where((attachment) => attachment.downloadStatus != 'done')
        .toList(growable: false);
    if (unfinished.length != attachments.length) return false;
    for (final expected in attachments) {
      final matches = unfinished.where(
        (attachment) =>
            attachment.id == expected.attachmentId &&
            attachment.localPath == expected.storedLocalPath &&
            attachment.downloadStatus == expected.downloadStatus &&
            (attachment.uploadRetryCount ?? 0) == expected.uploadRetryCount,
      );
      if (matches.length != 1) return false;
    }

    await messageRepo.saveMessage(
      parent.copyWith(status: 'sending', wireEnvelope: null),
    );
    for (final expected in attachments) {
      if (expected.downloadStatus != 'upload_failed') continue;
      final current = unfinished.singleWhere(
        (attachment) => attachment.id == expected.attachmentId,
      );
      await mediaAttachmentRepo.saveAttachment(
        current.copyWith(downloadStatus: 'upload_pending', uploadRetryCount: 0),
        owner: MediaOwnerLane.direct,
      );
    }
    return true;
  }
}

IdentityModel _makeIdentity() {
  return IdentityModel(
    peerId: 'my-peer-id',
    publicKey: 'my-pk-base64',
    privateKey: 'my-privkey-base64',
    mnemonic12:
        'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
  );
}

ConversationMessage _makeFailedMsg({
  String id = 'msg-fail-001',
  String contactPeerId = 'peer-target',
  String? wireEnvelope,
  String text = 'Hello',
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'my-peer-id',
    text: text,
    timestamp: '2026-01-01T00:00:00.000Z',
    status: 'failed',
    isIncoming: false,
    createdAt: '2026-01-01T00:00:00.000Z',
    wireEnvelope: wireEnvelope,
  );
}

ContactModel _makeContact({
  String peerId = 'peer-target',
  String? mlKemPublicKey = 'test-mlkem-pk',
}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'test-pk',
    rendezvous: '/ip4/127.0.0.1/tcp/4001',
    username: 'TestUser',
    signature: 'test-sig',
    scannedAt: '2026-01-01T00:00:00.000Z',
    mlKemPublicKey: mlKemPublicKey,
  );
}

const _testContentHash =
    'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef';

MediaAttachment _makeAttachment({
  String id = 'att-001',
  required String messageId,
  String? localPath = '/tmp/img.jpg',
  String downloadStatus = 'failed',
  String mime = 'image/jpeg',
  String mediaType = 'image',
  int? durationMs,
  int? uploadRetryCount,
}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: mime,
    size: 1024,
    mediaType: mediaType,
    localPath: localPath,
    downloadStatus: downloadStatus,
    createdAt: '2026-01-01T00:00:00.000Z',
    durationMs: durationMs,
    uploadRetryCount: uploadRetryCount,
    contentHash: _testContentHash,
    encryptionKeyBase64: 'test-blob-key-base64',
    encryptionNonce: 'test-blob-nonce',
    encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
  );
}

void main() {
  late FakeIdentityRepository identityRepo;
  late FakeMessageRepository messageRepo;
  late FakeContactRepository contactRepo;
  late FakeMediaAttachmentRepository mediaAttachmentRepo;
  late FakeBridge bridge;
  late FakeUploadMediaFn fakeUploadFn;
  late FakeP2PService p2pService;
  late FakeMediaFileManager mediaFileManager;
  late MediaUploadInFlightTracker uploadTracker;
  late _FakeDirectManualUploadRetryRearmRepository manualRearmRepo;

  setUp(() {
    identityRepo = FakeIdentityRepository();
    messageRepo = FakeMessageRepository();
    contactRepo = FakeContactRepository();
    mediaAttachmentRepo = FakeMediaAttachmentRepository();
    bridge = FakeBridge(
      initialResponses: {
        'message.encrypt': {
          'ok': true,
          'kem': 'fake-kem',
          'ciphertext': 'fake-ct',
          'nonce': 'fake-nonce',
        },
      },
    );
    fakeUploadFn = FakeUploadMediaFn();
    mediaFileManager = FakeMediaFileManager();
    uploadTracker = MediaUploadInFlightTracker();
    manualRearmRepo = _FakeDirectManualUploadRetryRearmRepository(
      messageRepo: messageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
    );

    identityRepo.seed(_makeIdentity());
    contactRepo.seed([_makeContact(peerId: 'peer-target')]);

    p2pService = FakeP2PService(
      initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
      discoverPeerResult: const DiscoveredPeer(
        id: 'peer-target',
        addresses: ['/ip4/127.0.0.1/tcp/4001'],
      ),
      dialPeerResult: true,
      sendMessageWithReplyResult: const p2p.SendMessageResult(
        sent: true,
        reply: 'ack',
      ),
      storeInInboxResult: true,
    );
  });

  Future<int> retryManual(
    String messageId, {
    FakeMediaFileManager? manager,
    void Function(Iterable<String> attachmentIds)? onClaim,
  }) {
    return retryFailedMessage(
      messageId: messageId,
      messageRepo: messageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      identityRepo: identityRepo,
      contactRepo: contactRepo,
      p2pService: p2pService,
      bridge: bridge,
      uploadMediaFn: fakeUploadFn.call,
      mediaFileManager: manager,
      uploadRetryRearmRepo: manualRearmRepo,
      tryClaimUploadLease: (attachmentIds) {
        onClaim?.call(attachmentIds);
        return uploadTracker.tryClaimAll(
          attachmentIds,
          source: MediaUploadTriggerSource.manual,
        );
      },
      releaseUploadLease: uploadTracker.release,
    );
  }

  group('retryFailedMessages -- re-upload incomplete media', () {
    test(
      'manual Retry rearms an at-ceiling upload and sends on success',
      () async {
        final msg = _makeFailedMsg(wireEnvelope: null);
        messageRepo.seed([msg]);

        final attachment = _makeAttachment(
          messageId: msg.id,
          localPath: '/tmp/img.jpg',
          downloadStatus: 'upload_failed',
          uploadRetryCount: kMaxUploadRetries,
        );
        mediaAttachmentRepo.seed([attachment]);

        // Create a temp file so existsSync() returns true
        final tmpFile = File('/tmp/img.jpg');
        if (!tmpFile.existsSync()) tmpFile.writeAsBytesSync([0xFF]);

        fakeUploadFn.willReturn(
          attachment.copyWith(id: 'new-blob-id', downloadStatus: 'done'),
        );

        final count = await retryManual(msg.id);

        expect(fakeUploadFn.callCount, 1);
        expect(fakeUploadFn.lastLocalPath, '/tmp/img.jpg');
        expect(fakeUploadFn.lastBlobId, attachment.id);
        expect(manualRearmRepo.callCount, 1);
        expect(
          manualRearmRepo.lastExpectations!.single.uploadRetryCount,
          kMaxUploadRetries,
        );
        expect(uploadTracker.inFlightCount, 0);
        expect(count, 1);
      },
    );

    // F.5.2 File deleted between crash and retry -> left as 'failed'
    test('skips message when local file is missing from disk', () async {
      final msg = _makeFailedMsg(wireEnvelope: null);
      messageRepo.seed([msg]);
      mediaAttachmentRepo.seed([
        _makeAttachment(
          messageId: msg.id,
          localPath: '/data/media/deleted.jpg',
          downloadStatus: 'failed',
        ),
      ]);
      // File intentionally absent

      final count = await retryFailedMessages(
        messageRepo: messageRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
        uploadMediaFn: fakeUploadFn.call,
      );

      expect(fakeUploadFn.callCount, 0);
      expect(count, 0);
    });

    test('manual Retry releases ownership when re-upload fails', () async {
      final msg = _makeFailedMsg(wireEnvelope: null);
      messageRepo.seed([msg]);
      mediaAttachmentRepo.seed([
        _makeAttachment(
          messageId: msg.id,
          localPath: '/tmp/img.jpg',
          downloadStatus: 'upload_pending',
        ),
      ]);

      // Ensure file exists for the upload attempt
      final tmpFile = File('/tmp/img.jpg');
      if (!tmpFile.existsSync()) tmpFile.writeAsBytesSync([0xFF]);

      fakeUploadFn.willReturn(null);

      final count = await retryManual(msg.id);

      expect(fakeUploadFn.callCount, 1);
      expect(manualRearmRepo.callCount, 1);
      expect(uploadTracker.inFlightCount, 0);
      expect(count, 0);
    });

    test('manual Retry uploads audio with its persisted metadata', () async {
      final msg = _makeFailedMsg(wireEnvelope: null);
      messageRepo.seed([msg]);

      final audioAttachment = _makeAttachment(
        messageId: msg.id,
        localPath: '/tmp/voice.m4a',
        downloadStatus: 'upload_pending',
        mime: 'audio/mp4',
        mediaType: 'audio',
        durationMs: 3000,
      );
      mediaAttachmentRepo.seed([audioAttachment]);

      // Ensure file exists
      final tmpFile = File('/tmp/voice.m4a');
      if (!tmpFile.existsSync()) tmpFile.writeAsBytesSync([0xFF]);

      fakeUploadFn.willReturn(
        audioAttachment.copyWith(id: 'audio-blob-id', downloadStatus: 'done'),
      );

      final count = await retryManual(msg.id);

      expect(fakeUploadFn.lastMime, 'audio/mp4');
      expect(fakeUploadFn.lastDurationMs, 3000);
      expect(manualRearmRepo.callCount, 1);
      expect(count, 1);
    });

    test(
      'automatic bulk retries done media but never claims or uploads unfinished rows',
      () async {
        final msgPending = _makeFailedMsg(id: 'msg-pending-001');
        final msgTerminal = _makeFailedMsg(id: 'msg-terminal-002');
        final msgCancelled = _makeFailedMsg(id: 'msg-cancelled-003');
        final msgDone = _makeFailedMsg(id: 'msg-done-004');
        messageRepo.seed([msgPending, msgTerminal, msgCancelled, msgDone]);

        mediaAttachmentRepo.seed([
          _makeAttachment(
            id: 'att-pending-001',
            messageId: msgPending.id,
            localPath: '/tmp/pending.jpg',
            downloadStatus: 'upload_pending',
          ),
          _makeAttachment(
            id: 'att-terminal-002',
            messageId: msgTerminal.id,
            localPath: '/tmp/terminal.jpg',
            downloadStatus: 'upload_failed',
            uploadRetryCount: kMaxUploadRetries,
          ),
          _makeAttachment(
            id: 'att-cancelled-003',
            messageId: msgCancelled.id,
            localPath: '/tmp/cancelled.jpg',
            downloadStatus: 'upload_cancelled',
          ),
          _makeAttachment(
            id: 'att-done-004',
            messageId: msgDone.id,
            localPath: 'media/peer-target/att-done-004.jpg',
            downloadStatus: 'done',
          ),
        ]);

        fakeUploadFn.willReturn(
          _makeAttachment(
            id: 'must-not-upload',
            messageId: msgPending.id,
            downloadStatus: 'done',
          ),
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          uploadMediaFn: fakeUploadFn.call,
          mediaFileManager: mediaFileManager,
        );

        expect(count, 1);
        expect(fakeUploadFn.callCount, 0);
        expect(manualRearmRepo.callCount, 0);
        expect(uploadTracker.inFlightCount, 0);
        expect((await messageRepo.getMessage(msgPending.id))?.status, 'failed');
        expect(
          (await messageRepo.getMessage(msgTerminal.id))?.status,
          'failed',
        );
        expect(
          (await messageRepo.getMessage(msgCancelled.id))?.status,
          'failed',
        );
      },
    );

    // F.5.6 Attachment with null localPath -> treated as missing
    test('skips attachment with null localPath', () async {
      final msg = _makeFailedMsg(wireEnvelope: null);
      messageRepo.seed([msg]);
      mediaAttachmentRepo.seed([
        _makeAttachment(
          messageId: msg.id,
          localPath: null,
          downloadStatus: 'failed',
        ),
      ]);

      final count = await retryFailedMessages(
        messageRepo: messageRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
        uploadMediaFn: fakeUploadFn.call,
      );

      expect(fakeUploadFn.callCount, 0);
      expect(count, 0);
    });

    // F.5.7 Attachment already uploaded (Part C path): uploadMediaFn NOT called
    test(
      'does NOT re-upload when attachment is already done (Part C path)',
      () async {
        final msg = _makeFailedMsg(wireEnvelope: null);
        messageRepo.seed([msg]);
        mediaAttachmentRepo.seed([
          _makeAttachment(
            messageId: msg.id,
            localPath: '/tmp/img.jpg',
            downloadStatus: 'done',
            id: 'existing-blob-id',
          ),
        ]);

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          uploadMediaFn: fakeUploadFn.call,
        );

        expect(fakeUploadFn.callCount, 0); // Part C path -- no new upload
        expect(count, 1);
      },
    );

    test(
      'cached-envelope inbox success cleans settled media staging',
      () async {
        final msg = _makeFailedMsg(
          id: 'msg-envelope-cleanup',
          wireEnvelope: '{"type":"chat","version":"2","payload":{}}',
        );
        messageRepo.seed([msg]);
        mediaAttachmentRepo.seed([
          _makeAttachment(
            id: 'att-envelope-cleanup',
            messageId: msg.id,
            localPath: 'media/peer-target/att-envelope-cleanup.jpg',
            downloadStatus: 'done',
          ),
        ]);
        final deletedDirs = <String>[];
        mediaFileManager.onDeletePendingUploadDir = deletedDirs.add;

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          uploadMediaFn: fakeUploadFn.call,
          mediaFileManager: mediaFileManager,
        );

        expect(count, 1);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(deletedDirs, [msg.id]);
        expect((await messageRepo.getMessage(msg.id))?.status, 'inboxed');
      },
    );

    test(
      'already-inbox cached-envelope success also cleans media staging',
      () async {
        final msg = _makeFailedMsg(
          id: 'msg-already-inbox-cleanup',
          wireEnvelope: '{"type":"chat","version":"2","payload":{}}',
        ).copyWith(transport: 'inbox');
        messageRepo.seed([msg]);
        mediaAttachmentRepo.seed([
          _makeAttachment(
            id: 'att-already-inbox-cleanup',
            messageId: msg.id,
            localPath: 'media/peer-target/att-already-inbox-cleanup.jpg',
            downloadStatus: 'done',
          ),
        ]);
        final deletedDirs = <String>[];
        mediaFileManager.onDeletePendingUploadDir = deletedDirs.add;

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          uploadMediaFn: fakeUploadFn.call,
          mediaFileManager: mediaFileManager,
        );

        expect(count, 1);
        expect(p2pService.storeInInboxCallCount, 0);
        expect(deletedDirs, [msg.id]);
        expect((await messageRepo.getMessage(msg.id))?.status, 'inboxed');
      },
    );

    test('manual Retry resolves and uploads a relative stored path', () async {
      final msg = _makeFailedMsg(wireEnvelope: null);
      messageRepo.seed([msg]);
      final attachment = _makeAttachment(
        messageId: msg.id,
        localPath: 'pending_uploads/${msg.id}/att-001.jpg',
        downloadStatus: 'upload_pending',
      );
      mediaAttachmentRepo.seed([attachment]);
      final resolvedPath = await mediaFileManager.resolveStoredPath(
        attachment.localPath!,
      );
      await File(resolvedPath).create(recursive: true);
      await File(resolvedPath).writeAsBytes([0xFF]);
      fakeUploadFn.willReturn(
        attachment.copyWith(
          localPath: 'media/peer-target/${attachment.id}.jpg',
          downloadStatus: 'done',
        ),
      );

      final count = await retryManual(msg.id, manager: mediaFileManager);

      expect(fakeUploadFn.callCount, 1);
      expect(fakeUploadFn.lastLocalPath, resolvedPath);
      expect(mediaFileManager.resolveStoredPathCount, greaterThanOrEqualTo(1));
      expect(count, 1);
    });

    // F.5.9 Voice-only retry without mediaAttachments returns invalidMessage
    test(
      'voice-only retry without mediaAttachments returns invalidMessage, not success',
      () async {
        final msg = _makeFailedMsg(wireEnvelope: null, text: '');
        messageRepo.seed([msg]);
        // No mediaAttachmentRepo rows seeded -- simulates pre-Part-G state

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          uploadMediaFn: fakeUploadFn.call,
        );

        expect(count, 0); // invalidMessage -- not a success
      },
    );

    test(
      'skips cancelled media rows without re-uploading or re-sending',
      () async {
        final msg = _makeFailedMsg(wireEnvelope: null);
        messageRepo.seed([msg]);
        mediaAttachmentRepo.seed([
          _makeAttachment(
            messageId: msg.id,
            localPath: '/tmp/cancelled.jpg',
            downloadStatus: 'upload_cancelled',
          ),
        ]);

        final tmpFile = File('/tmp/cancelled.jpg');
        if (!tmpFile.existsSync()) tmpFile.writeAsBytesSync([0xFF]);

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          uploadMediaFn: fakeUploadFn.call,
        );

        expect(fakeUploadFn.callCount, 0);
        expect(p2pService.storeInInboxCallCount, 0);
        expect(count, 0);
        expect((await messageRepo.getMessage(msg.id))?.status, 'failed');
      },
    );

    test(
      'manual Retry refuses a typed-terminal row below the ceiling',
      () async {
        final msg = _makeFailedMsg(wireEnvelope: 'still-valid');
        final attachment = _makeAttachment(
          messageId: msg.id,
          localPath: '/tmp/typed-terminal.jpg',
          downloadStatus: 'upload_failed',
          uploadRetryCount: kMaxUploadRetries - 1,
        );
        messageRepo.seed([msg]);
        mediaAttachmentRepo.seed([attachment]);
        await File(attachment.localPath!).writeAsBytes([0xFF]);
        var claimCount = 0;

        final count = await retryManual(msg.id, onClaim: (_) => claimCount++);

        expect(count, 0);
        expect(claimCount, 0);
        expect(manualRearmRepo.callCount, 0);
        expect(fakeUploadFn.callCount, 0);
        expect((await messageRepo.getMessage(msg.id))?.toMap(), msg.toMap());
        expect(
          (await mediaAttachmentRepo.getAttachmentById(attachment.id))?.toMap(),
          attachment.copyWith(ownerLane: MediaOwnerLane.direct).toMap(),
        );
      },
    );

    test(
      'held competing lease leaves parent and terminal attachment byte-identical',
      () async {
        final msg = _makeFailedMsg(wireEnvelope: 'still-valid');
        final attachment = _makeAttachment(
          messageId: msg.id,
          localPath: '/tmp/held-terminal.jpg',
          downloadStatus: 'upload_failed',
          uploadRetryCount: kMaxUploadRetries,
        );
        messageRepo.seed([msg]);
        mediaAttachmentRepo.seed([attachment]);
        await File(attachment.localPath!).writeAsBytes([0xFF]);
        final competitor = uploadTracker.tryClaimAll([
          attachment.id,
        ], source: MediaUploadTriggerSource.foreground);
        expect(competitor, isNotNull);
        final parentBefore = (await messageRepo.getMessage(msg.id))!.toMap();
        final attachmentBefore = (await mediaAttachmentRepo.getAttachmentById(
          attachment.id,
        ))!.toMap();

        final count = await retryManual(msg.id);

        expect(count, 0);
        expect(manualRearmRepo.callCount, 0);
        expect(fakeUploadFn.callCount, 0);
        expect((await messageRepo.getMessage(msg.id))?.toMap(), parentBefore);
        expect(
          (await mediaAttachmentRepo.getAttachmentById(attachment.id))?.toMap(),
          attachmentBefore,
        );
        expect(uploadTracker.release(competitor!), isTrue);
      },
    );

    test(
      'missing source in a multi-attachment set prevents claim and partial rearm',
      () async {
        final msg = _makeFailedMsg(wireEnvelope: 'still-valid');
        final present = _makeAttachment(
          id: 'att-present',
          messageId: msg.id,
          localPath: '/tmp/present-for-all-or-none.jpg',
          downloadStatus: 'upload_failed',
          uploadRetryCount: kMaxUploadRetries,
        );
        final missing = _makeAttachment(
          id: 'att-missing',
          messageId: msg.id,
          localPath: '/tmp/does-not-exist-for-all-or-none.jpg',
          downloadStatus: 'upload_pending',
        );
        messageRepo.seed([msg]);
        mediaAttachmentRepo.seed([present, missing]);
        await File(present.localPath!).writeAsBytes([0xFF]);
        final absent = File(missing.localPath!);
        if (absent.existsSync()) await absent.delete();
        var claimCount = 0;
        final before = (await mediaAttachmentRepo.getAttachmentsForMessage(
          msg.id,
          owner: MediaOwnerLane.direct,
        )).map((attachment) => attachment.toMap()).toList();

        final count = await retryManual(msg.id, onClaim: (_) => claimCount++);

        expect(count, 0);
        expect(claimCount, 0);
        expect(manualRearmRepo.callCount, 0);
        expect(fakeUploadFn.callCount, 0);
        expect((await messageRepo.getMessage(msg.id))?.toMap(), msg.toMap());
        expect(
          (await mediaAttachmentRepo.getAttachmentsForMessage(
            msg.id,
            owner: MediaOwnerLane.direct,
          )).map((attachment) => attachment.toMap()).toList(),
          before,
        );
      },
    );

    test(
      'over-limit manual set is refused before claim or terminal rearm',
      () async {
        final msg = _makeFailedMsg(wireEnvelope: 'still-valid');
        final tempDir = Directory.systemTemp.createTempSync(
          'direct_manual_retry_over_limit_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final attachments = <MediaAttachment>[];
        for (var i = 0; i < kReuploadMaxAttachmentsPerMessage + 1; i++) {
          final path = '${tempDir.path}/$i.jpg';
          await File(path).writeAsBytes([0xFF, i]);
          attachments.add(
            _makeAttachment(
              id: 'att-over-limit-$i',
              messageId: msg.id,
              localPath: path,
              downloadStatus: 'upload_failed',
              uploadRetryCount: kMaxUploadRetries,
            ),
          );
        }
        messageRepo.seed([msg]);
        mediaAttachmentRepo.seed(attachments);
        var claimCount = 0;
        final before = (await mediaAttachmentRepo.getAttachmentsForMessage(
          msg.id,
          owner: MediaOwnerLane.direct,
        )).map((attachment) => attachment.toMap()).toList();

        final count = await retryManual(msg.id, onClaim: (_) => claimCount++);

        expect(count, 0);
        expect(claimCount, 0);
        expect(manualRearmRepo.callCount, 0);
        expect(fakeUploadFn.callCount, 0);
        expect((await messageRepo.getMessage(msg.id))?.toMap(), msg.toMap());
        expect(
          (await mediaAttachmentRepo.getAttachmentsForMessage(
            msg.id,
            owner: MediaOwnerLane.direct,
          )).map((attachment) => attachment.toMap()).toList(),
          before,
        );
      },
    );

    test('failed parent+attachment CAS releases the manual lease', () async {
      final msg = _makeFailedMsg();
      final attachment = _makeAttachment(
        messageId: msg.id,
        localPath: '/tmp/cas-lost.jpg',
        downloadStatus: 'upload_pending',
      );
      messageRepo.seed([msg]);
      mediaAttachmentRepo.seed([attachment]);
      await File(attachment.localPath!).writeAsBytes([0xFF]);
      manualRearmRepo.willApply = false;

      final count = await retryManual(msg.id);

      expect(count, 0);
      expect(manualRearmRepo.callCount, 1);
      expect(fakeUploadFn.callCount, 0);
      expect(uploadTracker.inFlightCount, 0);
      expect((await messageRepo.getMessage(msg.id))?.status, 'failed');
      expect(
        (await mediaAttachmentRepo.getAttachmentById(
          attachment.id,
        ))?.downloadStatus,
        'upload_pending',
      );
    });
  });
}
