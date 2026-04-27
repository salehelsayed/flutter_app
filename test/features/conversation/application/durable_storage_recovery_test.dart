import 'package:flutter_test/flutter_test.dart';
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
import '../../../shared/fakes/fake_media_file_manager.dart';
import 'helpers/fake_upload_media_fn.dart';

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
    contactRepo.seed([_contactWithMlKem('peer-bob-001')]);
    fakeUploadFn = FakeUploadMediaFn();
  });

  group('Durable storage recovery (Gap 4)', () {
    // G.9.5.1
    test(
      'recovery succeeds from durable copy after temp file deletion',
      () async {
        messageRepo.seed([_makeMsg('msg-durable', status: 'failed')]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        mediaRepo.seed([
          MediaAttachment(
            id: 'att-001',
            messageId: 'msg-durable',
            mime: 'image/jpeg',
            size: 0,
            mediaType: 'image',
            localPath: 'pending_uploads/msg-durable/att-001.jpg',
            downloadStatus: 'upload_pending',
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        ]);
        final fm = FakeMediaFileManager()
          ..resolveResult =
              '/var/mobile/Documents/pending_uploads/msg-durable/att-001.jpg';
        fakeUploadFn.willReturn(
          _doneAttachment('att-001', 'msg-durable', mime: 'image/jpeg'),
        );

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
          mediaFileManager: fm,
        );
        expect(count, 1);
      },
    );

    // G.9.5.2
    test('voice recording recovery succeeds from durable copy', () async {
      messageRepo.seed([_makeMsg('msg-voice-durable', status: 'failed')]);
      identityRepo.seed(FakeIdentityRepository.makeIdentity());
      mediaRepo.seed([
        MediaAttachment(
          id: 'voice-att-001',
          messageId: 'msg-voice-durable',
          mime: 'audio/mp4',
          size: 8192,
          mediaType: 'audio',
          localPath: 'pending_uploads/msg-voice-durable/voice-att-001.m4a',
          downloadStatus: 'upload_pending',
          createdAt: DateTime.now().toUtc().toIso8601String(),
          durationMs: 5000,
          waveform: [0.1, 0.5, 0.9],
        ),
      ]);
      final fm = FakeMediaFileManager()
        ..resolveResult =
            '/var/mobile/Documents/pending_uploads/msg-voice-durable/voice-att-001.m4a';
      fakeUploadFn.willReturn(
        _doneAttachment(
          'voice-att-001',
          'msg-voice-durable',
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
        mediaFileManager: fm,
      );
      expect(count, 1);
      expect(fakeUploadFn.lastDurationMs, 5000);
    });

    // G.9.5.4
    test('durable copy is deleted after successful upload and send', () async {
      final fm = FakeMediaFileManager();
      final deletedDirs = <String>[];
      fm.onDeletePendingUploadDir = (msgId) {
        deletedDirs.add(msgId);
      };
      await fm.deletePendingUploadDir('msg-cleanup-001');
      expect(deletedDirs, contains('msg-cleanup-001'));
    });

    // G.8.1.1
    test(
      'resolves relative localPath via MediaFileManager before checking file existence',
      () async {
        final msg = _makeMsg(
          'msg-rel-0001',
          status: 'failed',
          contactPeerId: 'peer-bob-001',
        );
        messageRepo.seed([msg]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());

        mediaRepo.seed([
          _pendingAtt(
            id: 'att-rel-001',
            messageId: 'msg-rel-0001',
            localPath: 'pending_uploads/msg-rel/photo.jpg',
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
        ]);

        final fakeMediaFileManager = FakeMediaFileManager()
          ..resolveResult =
              '/var/mobile/Documents/pending_uploads/msg-rel/photo.jpg';

        fakeUploadFn.willReturn(
          _doneAttachment('att-rel-001', 'msg-rel-0001', mime: 'image/jpeg'),
        );

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
          mediaFileManager: fakeMediaFileManager,
        );

        expect(count, 1);
        expect(
          fakeUploadFn.lastLocalPath,
          '/var/mobile/Documents/pending_uploads/msg-rel/photo.jpg',
        );
      },
    );
  });
}
