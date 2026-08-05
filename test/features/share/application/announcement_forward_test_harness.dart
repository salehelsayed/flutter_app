import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/outgoing_ordinary_mutation_result.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/groups/application/announcement_media_forward_request.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

const announcementSourceGroupId = 'announcement-source-A';
const announcementSourceMessageId = 'announcement-source-message-A';
const announcementSourceAttachmentId = 'announcement-source-attachment-A';
const announcementSourceSenderId = 'announcement-source-sender-A';
const announcementSourceKey = 'announcement-source-key-A';
const announcementSourceNonce = 'announcement-source-nonce-A';
const announcementOwnPeerId = 'announcement-local-peer';

class RecordingOwnerMediaRepository extends InMemoryMediaAttachmentRepository {
  final List<({String messageId, MediaOwnerLane owner})> reads = [];
  final List<({String attachmentId, String messageId, MediaOwnerLane owner})>
  saves = [];
  final List<({String attachmentId, String messageId, MediaOwnerLane owner})>
  atomicStages = [];

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    reads.add((messageId: messageId, owner: owner));
    return super.getAttachmentsForMessage(messageId, owner: owner);
  }

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) async {
    saves.add((
      attachmentId: attachment.id,
      messageId: attachment.messageId,
      owner: owner,
    ));
    return super.saveAttachment(attachment, owner: owner);
  }

  @override
  Future<OutgoingOrdinaryMutationResult> stageOutgoingOrdinaryAttemptWithMedia({
    required OutgoingTransportMutationRepository messageMutationRepository,
    required ConversationMessage? expected,
    required ConversationMessage staged,
    required List<MediaAttachment> attachments,
    required OutgoingOrdinaryAttemptKind kind,
  }) async {
    final result = await super.stageOutgoingOrdinaryAttemptWithMedia(
      messageMutationRepository: messageMutationRepository,
      expected: expected,
      staged: staged,
      attachments: attachments,
      kind: kind,
    );
    if (result.authorizesTransport) {
      atomicStages.addAll(
        attachments.map(
          (attachment) => (
            attachmentId: attachment.id,
            messageId: attachment.messageId,
            owner: MediaOwnerLane.direct,
          ),
        ),
      );
    }
    return result;
  }
}

class RecordingCryptoBridge extends PassthroughCryptoBridge {
  final List<String> generatedBlobKeys = [];
  final List<String> generatedBlobNonces = [];

  @override
  Future<String> send(String message) async {
    final command = jsonDecode(message) as Map<String, dynamic>;
    final response = await super.send(message);
    final decoded = jsonDecode(response) as Map<String, dynamic>;
    if (command['cmd'] == 'blob:keygen' && decoded['keyBase64'] is String) {
      generatedBlobKeys.add(decoded['keyBase64'] as String);
    }
    if (command['cmd'] == 'blob:encrypt' && decoded['nonce'] is String) {
      generatedBlobNonces.add(decoded['nonce'] as String);
    }
    return response;
  }

  List<Map<String, dynamic>> commandPayloads(String command) => sentMessages
      .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
      .where((map) => map['cmd'] == command)
      .map(
        (map) => Map<String, dynamic>.from(
          (map['payload'] as Map?) ?? const <String, dynamic>{},
        ),
      )
      .toList(growable: false);
}

class AnnouncementForwardHarness {
  final identities = FakeIdentityRepository();
  final contacts = InMemoryContactRepository();
  final groups = InMemoryGroupRepository();
  final groupMessages = InMemoryGroupMessageRepository();
  final directMessages = InMemoryMessageRepository();
  final media = RecordingOwnerMediaRepository();
  final fileManager = FakeMediaFileManager();
  final bridge = RecordingCryptoBridge();
  final p2p = FakeP2PService(
    initialState: const NodeState(
      isStarted: true,
      peerId: announcementOwnPeerId,
    ),
  );
  late final Directory sourceDirectory;
  late final File sourceFile;
  int preprocessCount = 0;

  ContactModel contact(String peerId) => ContactModel(
    peerId: peerId,
    publicKey: 'public-$peerId',
    rendezvous: '/dns4/relay/tcp/443',
    username: peerId,
    signature: 'signature-$peerId',
    scannedAt: '2026-07-10T00:00:00.000Z',
    mlKemPublicKey: 'mlkem-$peerId',
  );

  GroupModel group(
    String id, {
    GroupType type = GroupType.chat,
    GroupRole role = GroupRole.member,
  }) => GroupModel(
    id: id,
    name: id,
    type: type,
    topicName: 'topic-$id',
    createdAt: DateTime.utc(2026, 7, 10),
    createdBy: announcementOwnPeerId,
    myRole: role,
  );

  Future<void> setUp() async {
    identities.seed(
      IdentityModel(
        peerId: announcementOwnPeerId,
        publicKey: 'own-public-key',
        privateKey: 'own-private-key',
        mnemonic12:
            'one two three four five six seven eight nine ten eleven twelve',
        mlKemPublicKey: 'own-mlkem-public',
        mlKemSecretKey: 'own-mlkem-secret',
        username: 'Owner',
        createdAt: '2026-07-10T00:00:00.000Z',
        updatedAt: '2026-07-10T00:00:00.000Z',
      ),
    );
    final sourceBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    sourceFile = File(
      await fileManager.localPathForAttachment(
        contactPeerId: announcementSourceGroupId,
        blobId: announcementSourceAttachmentId,
        mime: 'image/png',
      ),
    )..writeAsBytesSync(sourceBytes);
    sourceDirectory = sourceFile.parent;

    final sourceGroup = group(
      announcementSourceGroupId,
      type: GroupType.announcement,
      role: GroupRole.member,
    );
    await groups.saveGroup(sourceGroup);
    await seedWritableGroup(sourceGroup);
    await groups.saveMember(
      GroupMember(
        groupId: sourceGroup.id,
        peerId: announcementSourceSenderId,
        username: 'Announcement sender',
        role: MemberRole.admin,
        publicKey: 'announcement-source-public-key',
        mlKemPublicKey: 'announcement-source-mlkem-key',
        joinedAt: DateTime.utc(2026, 7, 10, 0, 2),
      ),
    );
    await groupMessages.saveMessage(
      GroupMessage(
        id: announcementSourceMessageId,
        groupId: announcementSourceGroupId,
        senderPeerId: announcementSourceSenderId,
        text: 'source caption',
        timestamp: DateTime.utc(2026, 7, 10, 12),
        isIncoming: true,
        createdAt: DateTime.utc(2026, 7, 10, 12),
      ),
    );
    await media.saveAttachment(
      MediaAttachment(
        id: announcementSourceAttachmentId,
        messageId: announcementSourceMessageId,
        mime: 'image/png',
        size: sourceFile.lengthSync(),
        mediaType: 'image',
        localPath: sourceFile.path,
        downloadStatus: 'done',
        createdAt: '2026-07-10T12:00:00.000Z',
        // Relay integrity covers ciphertext, not this canonical plaintext.
        contentHash: sha256.convert(<int>[...sourceBytes, 0xa5]).toString(),
        encryptionKeyBase64: announcementSourceKey,
        encryptionNonce: announcementSourceNonce,
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        ownerLane: MediaOwnerLane.group,
      ),
      owner: MediaOwnerLane.group,
    );
    media.reads.clear();
    media.saves.clear();
    media.atomicStages.clear();
    bridge.responses['group:publish'] = {
      'ok': true,
      'messageId': 'announcement-forward-live',
      'topicPeers': 1,
    };
    bridge.responses['group:inboxStore'] = {'ok': false};
  }

  void dispose() {
    if (sourceDirectory.existsSync()) {
      sourceDirectory.deleteSync(recursive: true);
    }
  }

  Future<void> seedWritableGroup(GroupModel value) async {
    await groups.saveGroup(value);
    await groups.saveKey(
      GroupKeyInfo(
        groupId: value.id,
        keyGeneration: 1,
        encryptedKey: 'group-key-${value.id}',
        createdAt: DateTime.utc(2026, 7, 10),
      ),
    );
    await groups.saveMember(
      GroupMember(
        groupId: value.id,
        peerId: announcementOwnPeerId,
        username: 'Owner',
        role: value.myRole == GroupRole.admin
            ? MemberRole.admin
            : MemberRole.writer,
        publicKey: 'own-public-key',
        mlKemPublicKey: 'own-mlkem-public',
        joinedAt: DateTime.utc(2026, 7, 10),
      ),
    );
    await groups.saveMember(
      GroupMember(
        groupId: value.id,
        peerId: 'destination-member-${value.id}',
        username: 'Destination member',
        role: MemberRole.writer,
        publicKey: 'destination-public-${value.id}',
        mlKemPublicKey: 'destination-mlkem-${value.id}',
        joinedAt: DateTime.utc(2026, 7, 10, 0, 1),
      ),
    );
  }

  AnnouncementMediaForwardRequest request({
    AnnouncementForwardCaptionMode captionMode =
        AnnouncementForwardCaptionMode.keep,
    String? editedCaption,
  }) => AnnouncementMediaForwardRequest(
    groupId: announcementSourceGroupId,
    messageId: announcementSourceMessageId,
    attachmentId: announcementSourceAttachmentId,
    initialCaption: 'source caption',
    provenance: const ForwardProvenance(
      operationDedupKey: 'opaque-announcement-action-token',
    ),
    captionMode: captionMode,
    editedCaption: editedCaption,
  );

  DefaultShareBatchDeliveryCoordinator coordinator({
    SendToContactFn? sendToContactFn,
    SendToGroupFn? sendToGroupFn,
    DateTime Function()? forwardNow,
  }) => DefaultShareBatchDeliveryCoordinator(
    identityRepository: identities,
    contactRepository: contacts,
    messageRepository: directMessages,
    mediaAttachmentRepository: media,
    groupRepository: groups,
    groupMessageRepository: groupMessages,
    bridge: bridge,
    p2pService: p2p,
    mediaFileManager: fileManager,
    imageProcessor: imageProcessor(),
    sendToContactFn: sendToContactFn,
    sendToGroupFn: sendToGroupFn,
    forwardNow: forwardNow,
    processSharedMediaFn: (intent) async {
      preprocessCount++;
      return ProcessedShareMediaBatch(
        processedMedia: [
          PendingComposerMedia(
            file: File(intent.filePaths.single),
            budgetBytes: sourceFile.lengthSync(),
          ),
        ],
      );
    },
  );

  static ImageProcessor imageProcessor() => ImageProcessor(
    compressFile:
        ({
          required path,
          required quality,
          required keepExif,
          minWidth = 1920,
          minHeight = 1080,
        }) async => null,
    compressVideo: ({required path, required compress, onProgress}) async =>
        VideoProcessResult(path: path),
  );

  Iterable<String> allDestinationSerializedSurfaces() sync* {
    for (final raw in bridge.sentMessages) {
      yield raw;
    }
    for (final raw in p2p.sentMessageLog) {
      yield raw.content;
    }
    for (final raw in p2p.storeInInboxLog) {
      yield raw.message;
    }
    yield jsonEncode(request().privacySafeDiagnostic);
  }
}

const announcementSourceSentinels = <String>[
  announcementSourceGroupId,
  announcementSourceMessageId,
  announcementSourceAttachmentId,
  announcementSourceSenderId,
  announcementSourceKey,
  announcementSourceNonce,
  'group',
  'direct',
];
