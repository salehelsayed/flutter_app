import 'dart:io';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/send_voice_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/outgoing_ordinary_mutation_result.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

import 'send_chat_message_use_case_test.dart'
    show FakeP2PService, FakeMessageRepository;
import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';

class _FakeMediaAttachmentRepository
    implements
        MediaAttachmentRepository,
        OutgoingOrdinaryAttemptStagingRepository {
  final List<MediaAttachment> saved = [];
  final List<OutgoingOrdinaryAttemptKind> stagedKinds = [];

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) async {
    saved.add(attachment.copyWith(ownerLane: owner));
  }

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async => 0;

  @override
  Future<int> deleteAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => 0;

  @override
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => 0;

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    return saved
        .where(
          (attachment) =>
              attachment.messageId == messageId &&
              attachment.ownerLane == owner,
        )
        .toList();
  }

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) async {
    final result = <String, List<MediaAttachment>>{};
    for (final messageId in messageIds) {
      final attachments = await getAttachmentsForMessage(
        messageId,
        owner: MediaOwnerLane.direct,
      );
      if (attachments.isNotEmpty) {
        result[messageId] = attachments;
      }
    }
    return result;
  }

  @override
  Future<List<MediaAttachment>> getPendingDownloads() async => const [];

  @override
  Future<List<MediaAttachment>> getUploadPendingAttachments({
    required MediaOwnerLane owner,
  }) async => [];

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {}

  @override
  Future<void> updateLocalPath(String id, String localPath) async {}

  @override
  Future<OutgoingOrdinaryMutationResult> stageOutgoingOrdinaryAttemptWithMedia({
    required OutgoingTransportMutationRepository messageMutationRepository,
    required ConversationMessage? expected,
    required ConversationMessage staged,
    required List<MediaAttachment> attachments,
    required OutgoingOrdinaryAttemptKind kind,
  }) async {
    stagedKinds.add(kind);
    if (attachments.isEmpty ||
        kind == OutgoingOrdinaryAttemptKind.tombstoneInitial ||
        kind == OutgoingOrdinaryAttemptKind.tombstoneRetry ||
        attachments.any(
          (attachment) =>
              attachment.id.isEmpty || attachment.messageId != staged.id,
        )) {
      return const OutgoingOrdinaryMutationResult(
        outcome: OutgoingOrdinaryMutationOutcome.refused,
        message: null,
      );
    }
    final parent = await messageMutationRepository.stageOutgoingOrdinaryAttempt(
      expected: expected,
      staged: staged,
      kind: kind,
    );
    if (!parent.authorizesTransport) return parent;
    if (parent.outcome == OutgoingOrdinaryMutationOutcome.idempotent &&
        attachments.any((attachment) {
          final index = saved.indexWhere(
            (candidate) => candidate.id == attachment.id,
          );
          return index < 0 ||
              !_sameOrdinaryOutgoingAttachmentAttempt(
                saved[index],
                attachment.copyWith(ownerLane: MediaOwnerLane.direct),
              );
        })) {
      return const OutgoingOrdinaryMutationResult(
        outcome: OutgoingOrdinaryMutationOutcome.refused,
        message: null,
      );
    }
    for (final attachment in attachments) {
      final direct = attachment.copyWith(ownerLane: MediaOwnerLane.direct);
      final index = saved.indexWhere((candidate) => candidate.id == direct.id);
      if (index < 0) {
        saved.add(direct);
      } else {
        final current = saved[index];
        saved[index] = direct.copyWith(
          isBookmarked: current.isBookmarked,
          lastPlaybackPositionMs: current.lastPlaybackPositionMs,
        );
      }
    }
    final committed = saved
        .where(
          (attachment) =>
              attachment.messageId == staged.id &&
              attachment.ownerLane == MediaOwnerLane.direct,
        )
        .toList(growable: false);
    return OutgoingOrdinaryMutationResult(
      outcome: parent.outcome,
      message: parent.message?.copyWith(media: committed),
    );
  }
}

bool _sameOrdinaryOutgoingAttachmentAttempt(
  MediaAttachment current,
  MediaAttachment candidate,
) {
  final currentMap = current.toMap()
    ..remove('is_bookmarked')
    ..remove('last_playback_position_ms')
    ..['upload_retry_count'] = current.uploadRetryCount ?? 0
    ..['download_retry_count'] = current.downloadRetryCount ?? 0;
  final candidateMap = candidate.toMap()
    ..remove('is_bookmarked')
    ..remove('last_playback_position_ms')
    ..['upload_retry_count'] = candidate.uploadRetryCount ?? 0
    ..['download_retry_count'] = candidate.downloadRetryCount ?? 0;
  return currentMap.length == candidateMap.length &&
      currentMap.entries.every(
        (entry) => candidateMap[entry.key] == entry.value,
      );
}

class _RecordingVoiceUploadProjection
    implements DirectUploadRetryProjectionRepository {
  int callCount = 0;
  String? messageId;
  String? attachmentId;
  UploadMediaFailed? failure;

  @override
  Future<UploadRetryProjectionResult> projectUploadFailure({
    required String messageId,
    required String attachmentId,
    required UploadMediaFailed failure,
  }) async {
    callCount++;
    this.messageId = messageId;
    this.attachmentId = attachmentId;
    this.failure = failure;
    return const UploadRetryProjectionResult(
      state: UploadRetryProjectionState.retryPending,
    );
  }
}

void main() {
  late FakeP2PService p2pService;
  late FakeMessageRepository messageRepo;
  late FakeBridge bridge;
  late _FakeMediaAttachmentRepository mediaAttachmentRepo;
  const mlKemKey = 'test-recipient-mlkem-pub-key';

  final tempDir = Directory.systemTemp.createTempSync('voice_test_');

  setUp(() {
    p2pService = FakeP2PService();
    messageRepo = FakeMessageRepository();
    mediaAttachmentRepo = _FakeMediaAttachmentRepository();
    bridge = FakeBridge(
      initialResponses: {
        'message.encrypt': {
          'ok': true,
          'kem': 'fake-kem',
          'ciphertext': 'fake-ct',
          'nonce': 'fake-nonce',
        },
        'media:upload': {'ok': true},
      },
    );
  });

  tearDownAll(() {
    tempDir.deleteSync(recursive: true);
  });

  AudioRecording createRecording({
    String? filePath,
    int durationMs = 3000,
    int sizeBytes = 48000,
  }) {
    // Create a real temp file for validation tests
    final path =
        filePath ??
        '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    if (!File(path).existsSync()) {
      File(path).writeAsBytesSync(List.filled(sizeBytes, 0));
    }
    return AudioRecording(
      filePath: path,
      durationMs: durationMs,
      sizeBytes: sizeBytes,
    );
  }

  group('sendVoiceMessage', () {
    group('validation', () {
      test('returns invalidMessage if file does not exist', () async {
        final recording = AudioRecording(
          filePath: '/nonexistent/voice.m4a',
          durationMs: 3000,
          sizeBytes: 48000,
        );

        final (result, _) = await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
        );

        expect(result, SendVoiceMessageResult.invalidRecording);
      });

      test('returns invalidMessage if file is 0 bytes', () async {
        final path = '${tempDir.path}/empty.m4a';
        File(path).writeAsBytesSync([]);

        final recording = AudioRecording(
          filePath: path,
          durationMs: 3000,
          sizeBytes: 0,
        );

        final (result, _) = await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
        );

        expect(result, SendVoiceMessageResult.invalidRecording);
      });

      test(
        'returns invalidMessage if file exceeds 100 MB by one byte',
        () async {
          // Keep the file tiny; the use case validates the dedicated voice size
          // field before upload.
          final path = '${tempDir.path}/big.m4a';
          File(path).writeAsBytesSync([
            1,
            2,
            3,
          ]); // tiny file but model says 100MB + 1 byte

          final recording = AudioRecording(
            filePath: path,
            durationMs: 3000,
            sizeBytes: (100 * 1024 * 1024) + 1,
          );

          final (result, _) = await sendVoiceMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            recording: recording,
            bridge: bridge,
            recipientMlKemPublicKey: mlKemKey,
            mediaAttachmentRepo: mediaAttachmentRepo,
          );

          expect(result, SendVoiceMessageResult.invalidRecording);
        },
      );

      test(
        'returns sendFailed before upload when recipient ML-KEM key is missing',
        () async {
          final recording = createRecording();

          final (result, message) = await sendVoiceMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            recording: recording,
            bridge: bridge,
          );

          expect(result, SendVoiceMessageResult.sendFailed);
          expect(message, isNull);
          expect(bridge.commandLog, isNot(contains('media:upload')));
          expect(p2pService.sendCallCount, 0);
          expect(p2pService.localSendCallCount, 0);
          expect(p2pService.storeInInboxCallCount, 0);
          expect(messageRepo.saved, isEmpty);
        },
      );
    });

    group('upload and send', () {
      test(
        'caller-owned fresh voice ID is insert-only before transport',
        () async {
          const messageId = 'caller-owned-fresh-voice';
          const blobId = 'caller-owned-fresh-voice-blob';
          final recording = createRecording();
          var observedCommittedPair = false;
          p2pService
            ..isConnectedToPeerResult = true
            ..sendMessageAcked = true
            ..sendMessageTransport = 'direct'
            ..onSendMessage = () {
              final parent = messageRepo.existingMessages[messageId];
              observedCommittedPair =
                  parent != null &&
                  parent.status == 'sending' &&
                  parent.wireEnvelope != null &&
                  mediaAttachmentRepo.saved.length == 1 &&
                  mediaAttachmentRepo.saved.single.messageId == messageId &&
                  mediaAttachmentRepo.saved.single.id == blobId;
            };

          final (result, message) = await sendVoiceMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            recording: recording,
            bridge: bridge,
            recipientMlKemPublicKey: mlKemKey,
            mediaAttachmentRepo: mediaAttachmentRepo,
            messageId: messageId,
            preassignedMessageIdIsFresh: true,
            timestamp: '2026-08-05T12:00:00.000Z',
            blobId: blobId,
          );

          expect(result, SendVoiceMessageResult.success);
          expect(observedCommittedPair, isTrue);
          expect(mediaAttachmentRepo.stagedKinds, <OutgoingOrdinaryAttemptKind>[
            OutgoingOrdinaryAttemptKind.fresh,
          ]);
          expect(message!.id, messageId);
          expect(message.media.single.id, blobId);
          expect(messageRepo.ordinaryStageCalls.single.expected, isNull);
          expect(messageRepo.wireEnvelopeUpdates, isEmpty);

          final transportCallsBeforeCollision = p2pService.sendCallCount;
          final inboxCallsBeforeCollision = p2pService.storeInInboxCallCount;
          final collisionRecording = createRecording();
          final (collisionResult, collisionMessage) = await sendVoiceMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            recording: collisionRecording,
            bridge: bridge,
            recipientMlKemPublicKey: mlKemKey,
            mediaAttachmentRepo: mediaAttachmentRepo,
            messageId: messageId,
            preassignedMessageIdIsFresh: true,
            timestamp: '2026-08-05T12:01:00.000Z',
            blobId: blobId,
          );
          expect(collisionResult, SendVoiceMessageResult.sendFailed);
          expect(collisionMessage, isNull);
          expect(p2pService.sendCallCount, transportCallsBeforeCollision);
          expect(p2pService.storeInInboxCallCount, inboxCallsBeforeCollision);
          expect(messageRepo.existingMessages[messageId]!.status, 'delivered');
        },
      );

      test('calls sendChatMessage with audio MediaAttachment', () async {
        final recording = createRecording();

        final (result, _) = await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        expect(result, SendVoiceMessageResult.success);
        // sendChatMessage should have been called (the message was sent via P2P)
        expect(p2pService.sendCallCount, greaterThan(0));
      });

      test('message persisted with correct status after send', () async {
        final recording = createRecording();

        await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        // sendChatMessage persists the message
        expect(messageRepo.saved, isNotEmpty);
      });

      test(
        'forwards blobId to uploadMedia and persists stable attachment id',
        () async {
          final recording = createRecording();
          const stableBlobId = 'voice-stable-blob-001';

          final (result, _) = await sendVoiceMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            recording: recording,
            bridge: bridge,
            recipientMlKemPublicKey: mlKemKey,
            mediaAttachmentRepo: mediaAttachmentRepo,
            blobId: stableBlobId,
          );

          expect(result, SendVoiceMessageResult.success);
          expect(mediaAttachmentRepo.saved, isNotEmpty);
          expect(mediaAttachmentRepo.saved.first.id, stableBlobId);
        },
      );

      test('allows empty text (voice-only message)', () async {
        final recording = createRecording();

        final (result, _) = await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        expect(result, SendVoiceMessageResult.success);
      });

      test('allows text caption alongside voice', () async {
        final recording = createRecording();

        final (result, _) = await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
          mediaAttachmentRepo: mediaAttachmentRepo,
          text: 'Listen to this!',
        );

        expect(result, SendVoiceMessageResult.success);
      });

      test('preserves quotedMessageId on the sent voice message', () async {
        final recording = createRecording();

        final (result, message) = await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
          mediaAttachmentRepo: mediaAttachmentRepo,
          quotedMessageId: 'parent-voice-1',
        );

        expect(result, SendVoiceMessageResult.success);
        expect(message!.quotedMessageId, 'parent-voice-1');
        expect(messageRepo.saved.last.quotedMessageId, 'parent-voice-1');
      });

      test('returns uploadFailed when bridge upload fails', () async {
        bridge.responses['media:upload'] = {
          'ok': false,
          'errorMessage': 'fail',
        };
        final recording = createRecording();

        final (result, _) = await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        expect(result, SendVoiceMessageResult.uploadFailed);
      });

      test(
        'connectivity failure stages pending media and projects exactly once into queued result',
        () async {
          final recording = createRecording();
          final projection = _RecordingVoiceUploadProjection();
          Future<UploadMediaOutcome> connectivityFailure({
            required Bridge bridge,
            required String localFilePath,
            required String mime,
            required String recipientPeerId,
            MediaFileManager? mediaFileManager,
            int? width,
            int? height,
            int? durationMs,
            List<double>? waveform,
            List<String>? allowedPeers,
            String? blobId,
            bool deleteSourceWhenDone = false,
            EncryptedMediaArtifact? preparedArtifact,
          }) async => const UploadMediaFailed(
            stage: UploadMediaStage.transport,
            disposition: UploadMediaDisposition.connectivityRetryable,
            errorCode: 'NOT_INITIALIZED',
          );

          final (result, _) = await sendVoiceMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            recording: recording,
            bridge: bridge,
            recipientMlKemPublicKey: mlKemKey,
            messageId: 'voice-message-1',
            blobId: 'voice-attachment-1',
            mediaAttachmentRepo: mediaAttachmentRepo,
            mediaFileManager: FakeMediaFileManager(),
            uploadMediaFn: connectivityFailure,
            uploadRetryProjectionRepo: projection,
          );

          expect(result, SendVoiceMessageResult.uploadQueued);
          expect(projection.callCount, 1);
          expect(projection.messageId, 'voice-message-1');
          expect(projection.attachmentId, 'voice-attachment-1');
          expect(
            projection.failure?.disposition,
            UploadMediaDisposition.connectivityRetryable,
          );
          expect(mediaAttachmentRepo.saved, hasLength(1));
          expect(
            mediaAttachmentRepo.saved.single.downloadStatus,
            'upload_pending',
          );
        },
      );

      test(
        'returns sendFailed when upload succeeds but message send fails',
        () async {
          p2pService.sendMessageResult = false;
          final recording = createRecording();

          final (result, message) = await sendVoiceMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            recording: recording,
            bridge: bridge,
            recipientMlKemPublicKey: mlKemKey,
            mediaAttachmentRepo: mediaAttachmentRepo,
          );

          expect(result, SendVoiceMessageResult.sendFailed);
          expect(message, isNull);
        },
      );

      test(
        'creates MediaAttachment with audio mediaType and correct durationMs',
        () async {
          final recording = createRecording(durationMs: 5500);

          await sendVoiceMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            recording: recording,
            bridge: bridge,
            recipientMlKemPublicKey: mlKemKey,
            mediaAttachmentRepo: mediaAttachmentRepo,
          );

          // The media attachment should have been saved
          expect(mediaAttachmentRepo.saved, isNotEmpty);
          final attachment = mediaAttachmentRepo.saved.first;
          expect(attachment.mediaType, 'audio');
          expect(attachment.mime, 'audio/mp4');
          expect(attachment.durationMs, 5500);
        },
      );
    });

    // --- 112 Phase 2.3: voice inherits the 1:1 blob-encryption flip ---
    group('blob encryption', () {
      test('voice upload produces encrypted attachment metadata and passes the '
          'send gate', () async {
        final recording = createRecording();

        final (result, message) = await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        expect(result, SendVoiceMessageResult.success);
        expect(message, isNotNull);
        expect(
          bridge.commandLog,
          containsAllInOrder(['blob:keygen', 'blob:encrypt', 'media:upload']),
        );
        final attachment = mediaAttachmentRepo.saved.first;
        expect(attachment.encryptionKeyBase64, isNotNull);
        expect(attachment.encryptionNonce, isNotNull);
        expect(
          attachment.encryptionScheme,
          kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );
        expect(attachment.contentHash, isNotNull);
      });

      test('voice temp recording deleted after durable copy and successful '
          'upload', () async {
        final recording = createRecording(
          filePath:
              '${tempDir.path}/voice_temp_cleanup_'
              '${DateTime.now().microsecondsSinceEpoch}.m4a',
        );
        final recordingFile = File(recording.filePath);
        expect(recordingFile.existsSync(), isTrue);

        final (result, _) = await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: FakeMediaFileManager(),
        );

        expect(result, SendVoiceMessageResult.success);
        // The recorder temp (`voice_<ts>.m4a`) is plaintext residue once
        // the durable copy is the render source — it must be unlinked.
        expect(recordingFile.existsSync(), isFalse);
      });
    });
  });
}
