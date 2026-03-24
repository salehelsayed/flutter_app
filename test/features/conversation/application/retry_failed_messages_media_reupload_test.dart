import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
import 'helpers/fake_upload_media_fn.dart';

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

MediaAttachment _makeAttachment({
  String id = 'att-001',
  required String messageId,
  String? localPath = '/tmp/img.jpg',
  String downloadStatus = 'failed',
  String mime = 'image/jpeg',
  String mediaType = 'image',
  int? durationMs,
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

  group('retryFailedMessages -- re-upload incomplete media', () {
    // F.5.1 Happy path: file present on disk -> re-uploads then sends
    test('re-uploads local image file and sends when CDN upload succeeds',
        () async {
      final msg = _makeFailedMsg(wireEnvelope: null);
      messageRepo.seed([msg]);

      final attachment = _makeAttachment(
        messageId: msg.id,
        localPath: '/tmp/img.jpg',
        downloadStatus: 'failed',
      );
      mediaAttachmentRepo.seed([attachment]);

      // Create a temp file so existsSync() returns true
      final tmpFile = File('/tmp/img.jpg');
      if (!tmpFile.existsSync()) tmpFile.writeAsBytesSync([0xFF]);

      fakeUploadFn.willReturn(
        attachment.copyWith(id: 'new-blob-id', downloadStatus: 'done'),
      );

      final count = await retryFailedMessages(
        messageRepo: messageRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
        uploadMediaFn: fakeUploadFn.call,
      );

      expect(fakeUploadFn.callCount, 1);
      expect(fakeUploadFn.lastLocalPath, '/tmp/img.jpg');
      expect(count, 1);
    });

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

    // F.5.3 CDN upload returns null -> message stays failed, no crash
    test('skips message when re-upload returns null (CDN error)', () async {
      final msg = _makeFailedMsg(wireEnvelope: null);
      messageRepo.seed([msg]);
      mediaAttachmentRepo.seed([
        _makeAttachment(
          messageId: msg.id,
          localPath: '/tmp/img.jpg',
          downloadStatus: 'failed',
        ),
      ]);

      // Ensure file exists for the upload attempt
      final tmpFile = File('/tmp/img.jpg');
      if (!tmpFile.existsSync()) tmpFile.writeAsBytesSync([0xFF]);

      fakeUploadFn.willReturn(null);

      final count = await retryFailedMessages(
        messageRepo: messageRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
        uploadMediaFn: fakeUploadFn.call,
      );

      expect(count, 0);
    });

    // F.5.4 Voice message: audio attachment re-uploaded with correct mime + durationMs
    test('re-uploads audio attachment and sends voice message', () async {
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

      final count = await retryFailedMessages(
        messageRepo: messageRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
        uploadMediaFn: fakeUploadFn.call,
      );

      expect(fakeUploadFn.lastMime, 'audio/mp4');
      expect(fakeUploadFn.lastDurationMs, 3000);
      expect(count, 1);
    });

    // F.5.5 Mixed batch: one recoverable, one file missing -> partial success
    test('retries recoverable messages and skips unrecoverable ones', () async {
      final msgOk =
          _makeFailedMsg(id: 'msg-ok-recoverable-001', wireEnvelope: null);
      final msgMissing =
          _makeFailedMsg(id: 'msg-missing-gone-002', wireEnvelope: null);
      messageRepo.seed([msgOk, msgMissing]);

      mediaAttachmentRepo.seed([
        _makeAttachment(
          id: 'att-ok-001',
          messageId: 'msg-ok-recoverable-001',
          localPath: '/tmp/ok.jpg',
          downloadStatus: 'failed',
        ),
        _makeAttachment(
          id: 'att-gone-002',
          messageId: 'msg-missing-gone-002',
          localPath: '/data/gone.jpg',
          downloadStatus: 'failed',
        ),
      ]);
      // /data/gone.jpg intentionally absent from disk

      // Ensure /tmp/ok.jpg exists
      final tmpFile = File('/tmp/ok.jpg');
      if (!tmpFile.existsSync()) tmpFile.writeAsBytesSync([0xFF]);

      fakeUploadFn.willReturnForPath(
        '/tmp/ok.jpg',
        _makeAttachment(
          messageId: 'msg-ok-recoverable-001',
          localPath: '/tmp/ok.jpg',
          downloadStatus: 'done',
          id: 'ok-blob-id-001',
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
      );

      expect(count, 1);
      expect(fakeUploadFn.callCount, 1);
    });

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
    test('does NOT re-upload when attachment is already done (Part C path)',
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
    });

    // F.5.8 Relative localPath (written by MediaFileManager) -- not resolvable
    test('skips message when localPath is relative (not resolvable)', () async {
      final msg = _makeFailedMsg(wireEnvelope: null);
      messageRepo.seed([msg]);
      mediaAttachmentRepo.seed([
        _makeAttachment(
          messageId: msg.id,
          localPath: 'media/attachments/img.jpg', // relative -- not resolvable
          downloadStatus: 'upload_pending',
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
    });
  });
}
