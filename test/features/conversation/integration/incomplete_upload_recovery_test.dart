import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/conversation/application/recover_stuck_sending_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_incomplete_uploads_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../../core/services/fake_p2p_service.dart';
import '../../../core/bridge/fake_bridge.dart';
import '../domain/repositories/fake_media_attachment_repository.dart';
import '../domain/repositories/fake_message_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';

void main() {
  group('Incomplete-upload recovery — smoke test', () {
    test(
      'voice message upload interrupted by lock is re-uploaded and delivered on resume',
      () async {
        final msgTs = DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 3))
            .toIso8601String();

        final stuckMsg = ConversationMessage(
          id: 'msg-voice-001',
          contactPeerId: 'peer-bob',
          senderPeerId: 'peer-alice',
          text: '',
          timestamp: msgTs,
          status: 'sending', // upload had not completed when app was killed
          isIncoming: false,
          createdAt: msgTs,
          wireEnvelope: null,
        );

        final pendingAtt = MediaAttachment(
          id: 'att-placeholder-uuid',
          messageId: 'msg-voice-001',
          mime: 'audio/mpeg',
          size: 8192,
          mediaType: 'audio',
          localPath: '/var/mobile/recordings/voice.m4a',
          durationMs: 5200,
          downloadStatus: 'upload_pending',
          createdAt: msgTs,
          waveform: [0.1, 0.5, 0.9, 0.3],
        );

        final messageRepo = FakeMessageRepository()..seed([stuckMsg]);
        final mediaRepo = FakeMediaAttachmentRepository()
          ..seed([pendingAtt]);

        final identityRepo = FakeIdentityRepository()
          ..seed(IdentityModel(
            peerId: 'peer-alice',
            publicKey: 'pk-alice',
            privateKey: 'sk-alice',
            mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
            createdAt: msgTs,
            updatedAt: msgTs,
          ));

        final contactRepo = FakeContactRepository()
          ..seed([
            ContactModel(
              peerId: 'peer-bob',
              publicKey: 'pk-bob',
              rendezvous: '/ip4/127.0.0.1/tcp/4001',
              username: 'Bob',
              signature: 'sig',
              scannedAt: msgTs,
              mlKemPublicKey: null,
            ),
          ]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'peer-alice',
            circuitAddresses: ['/p2p-circuit/addr1'],
          ),
          storeInInboxResult: true,
        );

        final bridge = FakeBridge();
        bridge.uploadMediaResult = MediaAttachment(
          id: 'relay-blob-id-abc',
          messageId: 'msg-voice-001',
          mime: 'audio/mpeg',
          size: 8192,
          mediaType: 'audio',
          localPath: '/var/mobile/recordings/voice.m4a',
          durationMs: 5200,
          downloadStatus: 'done',
          createdAt: msgTs,
          waveform: [0.1, 0.5, 0.9, 0.3],
        );

        // ---- Act: resume recovery sequence ----

        // Step 1: transition 'sending' -> 'failed'
        await recoverStuckSendingMessages(
          messageRepo: messageRepo,
          threshold: const Duration(seconds: 30),
        );
        messageRepo.seed([stuckMsg.copyWith(status: 'failed')]);

        // Step 2: re-upload and re-send
        final outerBridge = bridge;
        final reuploadCount = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: ({
            required Bridge bridge,
            required String localFilePath,
            required String mime,
            required String recipientPeerId,
            mediaFileManager,
            int? width,
            int? height,
            int? durationMs,
            waveform,
            allowedPeers,
            String? blobId,
          }) async => outerBridge.consumeUploadMediaResult(),
        );

        // ---- Assert ----
        expect(reuploadCount, 1);
        final saved = messageRepo.lastSavedMessage;
        expect(saved, isNotNull);
        expect(saved!.status, isNot('sending'));
        expect(saved.status, isNot('failed'));
        expect(saved.status, 'delivered');
      },
    );

    test(
      'image upload interrupted — attachment marked upload_failed when re-upload fails',
      () async {
        final msgTs = DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 2))
            .toIso8601String();

        final stuckMsg = ConversationMessage(
          id: 'msg-img-001',
          contactPeerId: 'peer-carol',
          senderPeerId: 'peer-alice',
          text: 'Check this out',
          timestamp: msgTs,
          status: 'failed',
          isIncoming: false,
          createdAt: msgTs,
          wireEnvelope: null,
        );

        final pendingAtt = MediaAttachment(
          id: 'att-placeholder-img',
          messageId: 'msg-img-001',
          mime: 'image/jpeg',
          size: 0,
          mediaType: 'image',
          localPath: '/tmp/photo.jpg',
          downloadStatus: 'upload_pending',
          createdAt: msgTs,
        );

        final messageRepo = FakeMessageRepository()..seed([stuckMsg]);
        final mediaRepo = FakeMediaAttachmentRepository()
          ..seed([pendingAtt]);
        final identityRepo = FakeIdentityRepository()
          ..seed(IdentityModel(
            peerId: 'peer-alice',
            publicKey: 'pk-alice',
            privateKey: 'sk-alice',
            mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
            createdAt: msgTs,
            updatedAt: msgTs,
          ));
        final contactRepo = FakeContactRepository();
        final p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'peer-alice',
            circuitAddresses: ['/p2p-circuit/addr1'],
          ),
        );
        final bridge = FakeBridge();
        bridge.uploadMediaResult = null;

        // Seed with retryCount at max-1 so this failure transitions to terminal
        mediaRepo.seed([
          pendingAtt.copyWith(uploadRetryCount: 2),
        ]);

        final outerBridge2 = bridge;
        await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: ({
            required Bridge bridge,
            required String localFilePath,
            required String mime,
            required String recipientPeerId,
            mediaFileManager,
            int? width,
            int? height,
            int? durationMs,
            waveform,
            allowedPeers,
            String? blobId,
          }) async => outerBridge2.consumeUploadMediaResult(),
        );

        final lastSaved = mediaRepo.lastSavedAttachment;
        expect(lastSaved, isNotNull);
        expect(lastSaved!.downloadStatus, 'upload_failed');
      },
    );

    test(
      'no upload_pending attachments — all recovery steps are no-ops',
      () async {
        final messageRepo = FakeMessageRepository();
        final mediaRepo = FakeMediaAttachmentRepository();
        final identityRepo = FakeIdentityRepository();
        final p2pService = FakeP2PService(
          initialState: const NodeState(
              isStarted: true, peerId: 'peer-alice'),
        );
        final bridge = FakeBridge();
        final contactRepo = FakeContactRepository();

        final recovered =
            await recoverStuckSendingMessages(messageRepo: messageRepo);
        expect(recovered, 0);

        final reuploaded = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
        );
        expect(reuploaded, 0);

        final retried = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );
        expect(retried, 0);
      },
    );
  });
}
