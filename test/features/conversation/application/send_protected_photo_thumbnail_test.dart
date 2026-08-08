import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/outgoing_direct_private_mutation_coordinator.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../domain/repositories/fake_media_attachment_repository.dart';
import '../domain/repositories/fake_message_repository.dart';

const _thumbnailKey = 'thumbnailInlineBase64';
const _thumbnailRawCap = 49152;
const _targetPeerId = '12D3KooWThumbSendTarget';

/// Minimal P2P service: the target peer is already directly connected, so the
/// send takes the reuse path and succeeds with an acknowledged direct write.
class _ReuseP2PService extends Fake implements P2PService {
  String? lastSentMessage;

  @override
  NodeState get currentState => NodeState(
    isStarted: true,
    connections: const [
      p2p.ConnectionState(
        peerId: _targetPeerId,
        multiaddrs: ['/ip4/10.0.0.2/tcp/4001'],
        direction: 'outbound',
        status: 'connected',
      ),
    ],
  );

  @override
  bool isLocalPeer(String peerId) => false;

  @override
  bool isConnectedToPeer(String peerId) => peerId == _targetPeerId;

  @override
  void recordSuccessfulTransport(String peerId, String transport) {}

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async {
    lastSentMessage = message;
    return const SendMessageResult(
      sent: true,
      acked: true,
      transport: 'direct',
    );
  }
}

class _PrivateCustodyMessageRepository extends FakeMessageRepository
    implements OutgoingDirectPrivateEnvelopeCustodyRepository {
  _PrivateCustodyMessageRepository(this.current);

  ConversationMessage current;

  @override
  Future<ConversationMessage?> getMessage(String id) async =>
      id == current.id ? current : null;

  @override
  Future<bool> invalidateWireEnvelopeBeforePrivateUpload({
    required String messageId,
    required String attachmentId,
    required String expectedPendingLocalPath,
  }) async => false;

  @override
  Future<bool> markOutgoingDirectPrivateUploadHandoffFailed({
    required String messageId,
    required String attachmentId,
    required String expectedPendingLocalPath,
  }) async => false;

  @override
  Future<OutgoingDirectPrivateEnvelopeHandoffOutcome>
  commitOutgoingDirectPrivateWireEnvelope({
    required String messageId,
    required MediaAttachment completedAttachment,
    required String expectedPendingLocalPath,
    required String envelope,
    required bool hasOwnedPendingCompletion,
  }) async {
    if (messageId != current.id) {
      return OutgoingDirectPrivateEnvelopeHandoffOutcome.refused;
    }
    current = current.copyWith(wireEnvelope: envelope);
    return OutgoingDirectPrivateEnvelopeHandoffOutcome.committed;
  }

  @override
  Future<OutgoingDirectPrivateTransportSettlementOutcome>
  settleOutgoingDirectPrivateTransport({
    required String messageId,
    required String? attachmentId,
    required String expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
  }) async {
    current = current.copyWith(status: status, transport: transport);
    return OutgoingDirectPrivateTransportSettlementOutcome.committed;
  }
}

class _PrivateMutationMediaRepository extends FakeMediaAttachmentRepository
    implements OutgoingDirectPrivateMutationRepository {
  final MediaAttachmentLifecycleLock _lifecycleLock =
      MediaAttachmentLifecycleLock();

  late final OutgoingDirectPrivateMutationCoordinator _coordinator =
      OutgoingDirectPrivateMutationCoordinator(
        lifecycleLock: _lifecycleLock,
        classifyCompletion: (_, _) async =>
            OutgoingDirectPrivateCompletionQualification.refused,
        commitAvailable: (_, _) async => false,
        commitRollback: (_, _, {required mode}) async => false,
      );

  @override
  OutgoingDirectPrivateMutationCoordinator
  get outgoingDirectPrivateMutationCoordinator => _coordinator;

  @override
  Future<OutgoingDirectPrivateNonCompletionMutationOutcome>
  applyOutgoingDirectPrivateNonCompletionMutation(
    MediaAttachment attachment,
  ) async => OutgoingDirectPrivateNonCompletionMutationOutcome.refused;

  @override
  Future<OutgoingDirectPrivatePendingPreparationOutcome>
  prepareOutgoingDirectPrivatePendingAttachments(
    List<MediaAttachment> attachments,
  ) async => OutgoingDirectPrivatePendingPreparationOutcome.refused;

  @override
  Future<OutgoingDirectPrivateNonCompletionMutationOutcome>
  deleteOutgoingDirectPrivatePendingAttachmentsForMessage(
    String messageId, {
    required MediaFileManager mediaFileManager,
  }) async => OutgoingDirectPrivateNonCompletionMutationOutcome.refused;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('protected_thumb_send_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  String writePhotoFixture(String name, {int width = 640, int height = 480}) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(40, 90, 160));
    final file = File(p.join(tempDir.path, name));
    file.writeAsBytesSync(img.encodeJpg(image, quality: 90));
    return file.path;
  }

  String writeNoisePhotoFixture(String name, {int side = 320}) {
    // Seeded max-entropy noise: resists JPEG compression so the generated
    // 320px/q60 thumbnail deterministically exceeds the 49,152-byte raw cap.
    final random = _Lcg(0xC0FFEE);
    final image = img.Image(width: side, height: side);
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        image.setPixelRgb(
          x,
          y,
          random.next() & 0xFF,
          random.next() & 0xFF,
          random.next() & 0xFF,
        );
      }
    }
    final file = File(p.join(tempDir.path, name));
    file.writeAsBytesSync(img.encodeJpg(image, quality: 100));
    return file.path;
  }

  String writeGifFixture(String name) {
    final image = img.Image(width: 24, height: 24);
    img.fill(image, color: img.ColorRgb8(200, 30, 30));
    final file = File(p.join(tempDir.path, name));
    file.writeAsBytesSync(img.encodeGif(image));
    return file.path;
  }

  String writeCorruptFixture(String name) {
    final file = File(p.join(tempDir.path, name));
    file.writeAsBytesSync(utf8.encode('not an image at all'));
    return file.path;
  }

  MediaAttachment attachment({
    required String id,
    required String messageId,
    required String localPath,
    String mime = 'image/jpeg',
    String mediaType = 'image',
  }) {
    return MediaAttachment(
      id: id,
      messageId: messageId,
      mime: mime,
      size: 1024,
      mediaType: mediaType,
      localPath: localPath,
      downloadStatus: 'done',
      createdAt: '2026-07-29T09:00:00.000Z',
      contentHash:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      encryptionKeyBase64: 'thumb-send-key',
      encryptionNonce: 'thumb-send-nonce',
      encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      ownerLane: MediaOwnerLane.direct,
    );
  }

  ConversationMessage outgoingRow({
    required String id,
    required PrivateMediaPolicy policy,
  }) {
    return ConversationMessage(
      id: id,
      contactPeerId: _targetPeerId,
      senderPeerId: 'my-peer',
      text: '',
      timestamp: '2026-07-29T09:00:00.000Z',
      status: 'sending',
      isIncoming: false,
      createdAt: '2026-07-29T09:00:00.000Z',
      privateMediaPolicy: policy,
      privateMediaState: policy.initialState,
    );
  }

  FakeBridge encryptOkBridge() => FakeBridge(
    initialResponses: {
      'message.encrypt': {
        'ok': true,
        'kem': 'opaque-kem',
        'ciphertext': 'opaque-ciphertext',
        'nonce': 'opaque-nonce',
      },
    },
  );

  Map<String, dynamic> capturedInnerJson(FakeBridge bridge) {
    final encryptCommand = bridge.sentMessages
        .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
        .singleWhere((command) => command['cmd'] == 'message.encrypt');
    final plaintext =
        (encryptCommand['payload'] as Map<String, dynamic>)['plaintext']
            as String;
    return jsonDecode(plaintext) as Map<String, dynamic>;
  }

  /// Sends one private (protected/view-once) message through the REAL use case
  /// over the custody fakes and returns the exact serialized inner JSON the
  /// transport encrypted — no re-serialization in any fake.
  Future<({SendChatMessageResult result, Map<String, dynamic> inner})>
  sendPrivate({
    required String messageId,
    required PrivateMediaPolicy policy,
    required MediaAttachment media,
  }) async {
    final bridge = encryptOkBridge();
    final messageRepo = _PrivateCustodyMessageRepository(
      outgoingRow(id: messageId, policy: policy),
    );
    final mediaRepo = _PrivateMutationMediaRepository()..seed([media]);
    final (result, _) = await sendChatMessage(
      p2pService: _ReuseP2PService(),
      messageRepo: messageRepo,
      targetPeerId: _targetPeerId,
      text: '',
      senderPeerId: 'my-peer',
      senderUsername: 'Me',
      messageId: messageId,
      timestamp: '2026-07-29T09:00:00.000Z',
      createdAt: '2026-07-29T09:00:00.000Z',
      bridge: bridge,
      recipientMlKemPublicKey: 'recipient-key',
      mediaAttachments: [media],
      privateMediaPolicy: policy,
      mediaAttachmentRepo: mediaRepo,
    );
    return (result: result, inner: capturedInnerJson(bridge));
  }

  test('protected photo send embeds one bounded inline thumbnail', () async {
    const messageId = 'protected-thumb-send-1';
    const attachmentId = '$messageId-att';
    final localPath = writePhotoFixture('protected-source.jpg');

    final send = await sendPrivate(
      messageId: messageId,
      policy: const PrivateMediaPolicy.protected(),
      media: attachment(
        id: attachmentId,
        messageId: messageId,
        localPath: localPath,
      ),
    );

    expect(send.result, SendChatMessageResult.success);
    final media = (send.inner['media'] as List).cast<Map<String, dynamic>>();
    expect(media, hasLength(1));
    final inline = media.single[_thumbnailKey];
    expect(
      inline,
      isA<String>(),
      reason: 'the inline thumbnail must ride the attachment JSON',
    );
    final rawBytes = base64Decode(inline as String);
    expect(rawBytes, isNotEmpty);
    expect(rawBytes.length, lessThanOrEqualTo(_thumbnailRawCap));
    final decoded = img.decodeJpg(rawBytes);
    expect(
      decoded,
      isNotNull,
      reason: 'the inline payload must be a decodable JPEG',
    );
    expect(
      decoded!.width <= 320 && decoded.height <= 320,
      isTrue,
      reason:
          'longest side must be bounded to 320px '
          '(${decoded.width}x${decoded.height})',
    );
    // Exactly one embed in the whole serialized payload.
    expect(_thumbnailKey.allMatches(jsonEncode(send.inner)).length, 1);
  });

  test(
    'ordinary view-once disappearing video gif and oversized sends carry no inline thumbnail',
    () async {
      // Ordinary photo (fresh send path with strict combined custody).
      {
        final bridge = encryptOkBridge();
        final messages = InMemoryMessageRepository();
        final attachments = InMemoryMediaAttachmentRepository()
          ..enableDirectMediaInboxCustodyForTest(messages);
        final (result, _) = await sendChatMessage(
          p2pService: _ReuseP2PService(),
          messageRepo: messages,
          targetPeerId: _targetPeerId,
          text: '',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: bridge,
          recipientMlKemPublicKey: 'recipient-key',
          mediaAttachments: [
            attachment(
              id: 'ordinary-att',
              messageId: '',
              localPath: writePhotoFixture('ordinary.jpg'),
            ),
          ],
          mediaAttachmentRepo: attachments,
          storeInAckCustodyInboxDetailed:
              (peerId, envelope, {required custodyKind, timeoutMs}) async {
                expect(custodyKind, AckCustodyKind.directTextV108);
                return const InboxStoreOutcome(
                  status: InboxStoreStatus.stored,
                  storeStatus: 'stored',
                  expiresAtMs: 1770000000000,
                  custodyContract: ackOrExpiryInboxCustodyContract,
                );
              },
        );
        expect(result, SendChatMessageResult.success);
        expect(
          messages.directCustodyRows,
          hasLength(1),
          reason:
              'the direct live ACK does not settle local ACK-or-expiry custody',
        );
        final inner = capturedInnerJson(bridge);
        final media = (inner['media'] as List).cast<Map<String, dynamic>>();
        expect(
          media.single.containsKey(_thumbnailKey),
          isFalse,
          reason: 'ordinary',
        );
      }

      // View-once photo (private custody path, still no thumbnail).
      {
        const messageId = 'view-once-thumbless';
        final send = await sendPrivate(
          messageId: messageId,
          policy: const PrivateMediaPolicy.viewOnce(),
          media: attachment(
            id: '$messageId-att',
            messageId: messageId,
            localPath: writePhotoFixture('view-once.jpg'),
          ),
        );
        expect(send.result, SendChatMessageResult.success);
        final media = (send.inner['media'] as List)
            .cast<Map<String, dynamic>>();
        expect(
          media.single.containsKey(_thumbnailKey),
          isFalse,
          reason: 'view-once',
        );
      }

      // Disappearing photo (fresh private send, not one-more-look).
      {
        final bridge = encryptOkBridge();
        final (result, _) = await sendChatMessage(
          p2pService: _ReuseP2PService(),
          messageRepo: FakeMessageRepository(),
          targetPeerId: _targetPeerId,
          text: '',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: bridge,
          recipientMlKemPublicKey: 'recipient-key',
          mediaAttachments: [
            attachment(
              id: 'disappearing-att',
              messageId: '',
              localPath: writePhotoFixture('disappearing.jpg'),
            ),
          ],
          privateMediaPolicy: PrivateMediaPolicy.disappearing(3600),
          mediaAttachmentRepo: FakeMediaAttachmentRepository(),
        );
        expect(result, SendChatMessageResult.success);
        final inner = capturedInnerJson(bridge);
        final media = (inner['media'] as List).cast<Map<String, dynamic>>();
        expect(
          media.single.containsKey(_thumbnailKey),
          isFalse,
          reason: 'disappearing',
        );
      }

      // Protected VIDEO — representable, but never thumbnailed by this plan.
      {
        const messageId = 'protected-video-thumbless';
        final send = await sendPrivate(
          messageId: messageId,
          policy: const PrivateMediaPolicy.protected(),
          media: attachment(
            id: '$messageId-att',
            messageId: messageId,
            localPath: writePhotoFixture('video-stand-in.jpg'),
            mime: 'video/mp4',
            mediaType: 'video',
          ),
        );
        expect(send.result, SendChatMessageResult.success);
        final media = (send.inner['media'] as List)
            .cast<Map<String, dynamic>>();
        expect(
          media.single.containsKey(_thumbnailKey),
          isFalse,
          reason: 'protected video',
        );
      }

      // Protected GIF — the dual check (mime OR mediaType) must exclude it. A
      // bare mime.startsWith('image/') predicate would wrongly embed here: the
      // fixture is a real decodable GIF with an image/gif mime.
      {
        const messageId = 'protected-gif-thumbless';
        final send = await sendPrivate(
          messageId: messageId,
          policy: const PrivateMediaPolicy.protected(),
          media: attachment(
            id: '$messageId-att',
            messageId: messageId,
            localPath: writeGifFixture('protected.gif'),
            mime: 'image/gif',
            mediaType: 'gif',
          ),
        );
        expect(send.result, SendChatMessageResult.success);
        final media = (send.inner['media'] as List)
            .cast<Map<String, dynamic>>();
        expect(
          media.single.containsKey(_thumbnailKey),
          isFalse,
          reason: 'protected gif',
        );
      }

      // Oversized: max-entropy source whose 320px/q60 thumbnail exceeds the
      // raw cap — the field must be omitted, and the send still succeeds.
      {
        const messageId = 'protected-oversized-thumbless';
        final send = await sendPrivate(
          messageId: messageId,
          policy: const PrivateMediaPolicy.protected(),
          media: attachment(
            id: '$messageId-att',
            messageId: messageId,
            localPath: writeNoisePhotoFixture('oversized-noise.jpg'),
          ),
        );
        expect(send.result, SendChatMessageResult.success);
        final media = (send.inner['media'] as List)
            .cast<Map<String, dynamic>>();
        expect(
          media.single.containsKey(_thumbnailKey),
          isFalse,
          reason: 'oversized',
        );
      }

      // Generation failure (undecodable source): field absent AND the send
      // still succeeds — thumbnailing is strictly best-effort.
      {
        const messageId = 'protected-corrupt-source';
        final send = await sendPrivate(
          messageId: messageId,
          policy: const PrivateMediaPolicy.protected(),
          media: attachment(
            id: '$messageId-att',
            messageId: messageId,
            localPath: writeCorruptFixture('corrupt.jpg'),
          ),
        );
        expect(
          send.result,
          SendChatMessageResult.success,
          reason: 'generation failure must never fail the send',
        );
        final media = (send.inner['media'] as List)
            .cast<Map<String, dynamic>>();
        expect(
          media.single.containsKey(_thumbnailKey),
          isFalse,
          reason: 'corrupt source',
        );
      }
    },
  );
}

/// Deterministic LCG so the noise fixture is identical on every run.
class _Lcg {
  _Lcg(this._state);

  int _state;

  int next() {
    _state = (_state * 1103515245 + 12345) & 0x7FFFFFFF;
    return _state >> 16;
  }
}
