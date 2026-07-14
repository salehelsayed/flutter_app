import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../../shared/fakes/nth_exact_media_read_gated_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

// 236 TC-236-01/01R: pure Forward-offer policy for discussion received media
// plus the dispatch-time source gate. The gate never trusts viewer/picker
// state: it reloads the exact (group, message, attachment) identity under the
// group owner lane and verifies the canonical local plaintext immediately
// before any target lookup, upload, or delivery. The stored content hash is a
// relay-ciphertext digest and must never be applied to those plaintext bytes.

const _validContentHash =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

MediaAttachment _attachment({
  String id = 'att-1',
  String messageId = 'msg-1',
  String mime = 'image/jpeg',
  String mediaType = 'image',
  String downloadStatus = 'done',
  String? localPath = 'media/group-1/att-1.jpg',
  String? contentHash = _validContentHash,
  String? encryptionKeyBase64 = 'a2V5',
  String? encryptionNonce = 'bm9uY2U=',
  String? encryptionScheme = kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
  MediaOwnerLane? ownerLane = MediaOwnerLane.group,
  int size = 2048,
}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: mime,
    size: size,
    mediaType: mediaType,
    localPath: localPath,
    downloadStatus: downloadStatus,
    createdAt: '2026-07-10T12:00:00.000Z',
    contentHash: contentHash,
    encryptionKeyBase64: encryptionKeyBase64,
    encryptionNonce: encryptionNonce,
    encryptionScheme: encryptionScheme,
    ownerLane: ownerLane,
  );
}

bool _canForward({
  GroupType groupType = GroupType.chat,
  bool isIncoming = true,
  MediaAttachment? attachment,
  bool Function(MediaAttachment)? isLifecycleRestricted,
}) {
  return GroupMediaForwardPolicy.canOfferForward(
    groupType: groupType,
    isIncoming: isIncoming,
    attachment: attachment ?? _attachment(),
    isLifecycleRestricted: isLifecycleRestricted,
  );
}

void main() {
  group('GroupMediaForwardPolicy', () {
    test('GMF-01 only eligible incoming discussion media can forward', () {
      // The one fully eligible row: incoming verified ordinary image in a
      // discussion (chat) group under the group owner lane.
      expect(_canForward(), isTrue);
      // Video parity.
      expect(
        _canForward(
          attachment: _attachment(
            mime: 'video/mp4',
            mediaType: 'video',
            localPath: 'media/group-1/att-1.mp4',
          ),
        ),
        isTrue,
        reason: 'verified incoming discussion video can forward',
      );

      // Every broken dimension removes Forward. Table-driven: each row breaks
      // exactly one input.
      final denied = <String, bool>{
        'qa group': _canForward(groupType: GroupType.qa),
        'outgoing message': _canForward(isIncoming: false),
        'audio attachment': _canForward(
          attachment: _attachment(mime: 'audio/mp4', mediaType: 'audio'),
        ),
        'direct-lane collision row': _canForward(
          attachment: _attachment(ownerLane: MediaOwnerLane.direct),
        ),
        'unresolved-lane row': _canForward(
          attachment: _attachment(ownerLane: null),
        ),
        'pending download': _canForward(
          attachment: _attachment(downloadStatus: 'pending'),
        ),
        'failed download': _canForward(
          attachment: _attachment(downloadStatus: 'failed'),
        ),
        'quarantined (integrity_failed)': _canForward(
          attachment: _attachment(downloadStatus: 'integrity_failed'),
        ),
        'evicted local copy': _canForward(
          attachment: _attachment(downloadStatus: 'evicted', localPath: null),
        ),
        'missing local path': _canForward(
          attachment: _attachment(localPath: null),
        ),
        'missing content hash': _canForward(
          attachment: _attachment(contentHash: null),
        ),
        'malformed content hash': _canForward(
          attachment: _attachment(contentHash: 'nope'),
        ),
        'missing encryption metadata': _canForward(
          attachment: _attachment(
            encryptionKeyBase64: null,
            encryptionNonce: null,
            encryptionScheme: null,
          ),
        ),
      };
      denied.forEach((label, allowed) {
        expect(allowed, isFalse, reason: '$label must not offer Forward');
      });
      expect(
        _canForward(groupType: GroupType.announcement),
        isTrue,
        reason: 'plan 240 permits verified incoming announcement media',
      );

      // 238 seam: an abstract lifecycle restriction (expiry / protection /
      // view-once) denies Forward without this plan knowing the concrete
      // model. The default (no restriction) allows; a restricting policy
      // fixture denies the SAME row.
      expect(
        _canForward(isLifecycleRestricted: (_) => false),
        isTrue,
        reason: 'an allowing lifecycle policy keeps Forward available',
      );
      expect(
        _canForward(isLifecycleRestricted: (_) => true),
        isFalse,
        reason: 'a restricting lifecycle policy removes Forward',
      );
    });
  });

  group('GroupMediaForwardSourceGate', () {
    const groupId = 'group-1';
    const messageId = 'msg-1';
    const attachmentId = 'att-1';

    late InMemoryGroupRepository groupRepo;
    late InMemoryGroupMessageRepository messageRepo;
    late InMemoryMediaAttachmentRepository mediaRepo;
    late FakeMediaFileManager fileManager;
    late GroupMediaForwardSourceGate gate;
    late Set<String> ownedPaths;

    GroupModel makeGroup({
      String id = groupId,
      GroupType type = GroupType.chat,
    }) {
      return GroupModel(
        id: id,
        name: 'Discussion',
        type: type,
        topicName: 'topic-$id',
        createdAt: DateTime.utc(2026, 7, 1),
        createdBy: 'peer-alice',
        myRole: GroupRole.member,
      );
    }

    GroupMessage makeMessage({
      String id = messageId,
      String group = groupId,
      bool isIncoming = true,
      String text = 'original caption',
      GroupPrivateMediaPolicy privateMediaPolicy =
          const GroupPrivateMediaPolicy.ordinary(),
      int? mediaExpiredAt,
      bool mediaCleanupPending = false,
    }) {
      return GroupMessage(
        id: id,
        groupId: group,
        senderPeerId: isIncoming ? 'peer-alice' : 'peer-self',
        text: text,
        timestamp: DateTime.utc(2026, 7, 10, 12),
        isIncoming: isIncoming,
        createdAt: DateTime.utc(2026, 7, 10, 12),
        privateMediaPolicy: privateMediaPolicy,
        mediaExpiredAt: mediaExpiredAt,
        mediaCleanupPending: mediaCleanupPending,
      );
    }

    /// Writes canonical local plaintext and returns its absolute app-owned
    /// path plus a VALID relay-ciphertext digest from different bytes.
    Future<(String, String)> writeMediaFile(
      String name,
      List<int> bytes, {
      String group = groupId,
      String mime = 'image/jpeg',
    }) async {
      final path = await fileManager.localPathForAttachment(
        contactPeerId: group,
        blobId: name,
        mime: mime,
      );
      final file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes);
      ownedPaths.add(file.path);
      final plaintextHash = sha256.convert(bytes).toString();
      final relayCiphertextHash = sha256.convert(<int>[
        ...bytes,
        0xa5,
      ]).toString();
      expect(relayCiphertextHash, isNot(plaintextHash));
      return (file.path, relayCiphertextHash);
    }

    GroupMediaForwardRequest request({
      String group = groupId,
      String message = messageId,
      String attachment = attachmentId,
    }) {
      return GroupMediaForwardRequest(
        groupId: group,
        messageId: message,
        attachmentId: attachment,
        initialCaption: 'original caption',
        provenance: const ForwardProvenance(operationDedupKey: 'op-1'),
      );
    }

    setUp(() {
      groupRepo = InMemoryGroupRepository();
      messageRepo = InMemoryGroupMessageRepository();
      mediaRepo = InMemoryMediaAttachmentRepository();
      fileManager = FakeMediaFileManager();
      ownedPaths = <String>{};
      gate = GroupMediaForwardSourceGate(
        groupRepository: groupRepo,
        messageRepository: messageRepo,
        mediaAttachmentRepository: mediaRepo,
        mediaFileManager: fileManager,
      );
    });

    tearDown(() {
      for (final path in ownedPaths) {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      }
    });

    test(
      'GMF-01R dispatch accepts canonical plaintext with a distinct relay ciphertext hash',
      () async {
        // --- Eligible current source: canonical plaintext proceeds even though
        // the valid relay-ciphertext hash intentionally differs from it.
        final bytes = List<int>.filled(96, 0x31)
          ..setRange(0, 4, const <int>[0xff, 0xd8, 0xff, 0xe0]);
        final (storedPath, relayCiphertextHash) = await writeMediaFile(
          'att-1',
          bytes,
        );
        await groupRepo.saveGroup(makeGroup());
        await messageRepo.saveMessage(makeMessage());
        await mediaRepo.saveAttachment(
          _attachment(
            localPath: storedPath,
            contentHash: relayCiphertextHash,
            size: bytes.length,
          ),
          owner: MediaOwnerLane.group,
        );

        final verified = await gate.verify(request());
        expect(verified.isVerified, isTrue);
        expect(
          verified.source!.resolvedPath,
          storedPath,
          reason: 'the verified source is the resolved CURRENT stored file',
        );
        expect(verified.source!.attachment.id, attachmentId);

        // --- A size drift after the picker delay fails closed.
        File(storedPath).writeAsBytesSync(<int>[...bytes, 0x42]);
        final sizeDrift = await gate.verify(request());
        expect(sizeDrift.isVerified, isFalse);
        expect(sizeDrift.denialReason, 'plaintext_size_mismatch');

        // --- Same-sized dangerous signature drift fails independently.
        final signatureDrift = List<int>.filled(bytes.length, 0x20)
          ..setRange(0, 4, const <int>[0x25, 0x50, 0x44, 0x46]);
        File(storedPath).writeAsBytesSync(signatureDrift);
        final wrongSignature = await gate.verify(request());
        expect(wrongSignature.isVerified, isFalse);
        expect(wrongSignature.denialReason, 'dangerous_signature');

        // Restore the original bytes for the remaining rows.
        File(storedPath).writeAsBytesSync(bytes);
        expect((await gate.verify(request())).isVerified, isTrue);

        // --- A valid file outside the exact owner/id path is not eligible.
        await mediaRepo.saveAttachment(
          _attachment(
            localPath: 'media/$groupId/not-$attachmentId.jpg',
            contentHash: relayCiphertextHash,
            size: bytes.length,
          ),
          owner: MediaOwnerLane.group,
        );
        final noncanonicalPath = await gate.verify(request());
        expect(noncanonicalPath.isVerified, isFalse);
        expect(noncanonicalPath.denialReason, 'noncanonical_local_path');
        await mediaRepo.saveAttachment(
          _attachment(
            localPath: storedPath,
            contentHash: relayCiphertextHash,
            size: bytes.length,
          ),
          owner: MediaOwnerLane.group,
        );

        // --- Wrong group: same message id under a different caller group.
        final wrongGroup = await gate.verify(request(group: 'group-2'));
        expect(wrongGroup.isVerified, isFalse);
        expect(wrongGroup.denialReason, 'wrong_group');

        // --- Wrong attachment id.
        final wrongAttachment = await gate.verify(
          request(attachment: 'att-unknown'),
        );
        expect(wrongAttachment.isVerified, isFalse);
        expect(wrongAttachment.denialReason, 'attachment_not_group_owned');

        // --- Same-ID DIRECT collision row never satisfies the group lane.
        await mediaRepo.saveAttachment(
          _attachment(
            id: 'att-direct',
            localPath: storedPath,
            contentHash: relayCiphertextHash,
            ownerLane: MediaOwnerLane.direct,
            size: bytes.length,
          ),
          owner: MediaOwnerLane.direct,
        );
        final directCollision = await gate.verify(
          request(attachment: 'att-direct'),
        );
        expect(directCollision.isVerified, isFalse);
        expect(directCollision.denialReason, 'attachment_not_group_owned');

        // --- Outgoing parent: not a RECEIVED-media forward source.
        await messageRepo.saveMessage(
          makeMessage(id: 'msg-out', isIncoming: false),
        );
        await mediaRepo.saveAttachment(
          _attachment(
            id: 'att-out',
            messageId: 'msg-out',
            localPath: storedPath,
            contentHash: relayCiphertextHash,
            size: bytes.length,
          ),
          owner: MediaOwnerLane.group,
        );
        final outgoing = await gate.verify(
          request(message: 'msg-out', attachment: 'att-out'),
        );
        expect(outgoing.isVerified, isFalse);
        expect(outgoing.denialReason, 'not_incoming');

        // --- Missing parent.
        final missingParent = await gate.verify(request(message: 'msg-gone'));
        expect(missingParent.isVerified, isFalse);
        expect(missingParent.denialReason, 'parent_missing');

        // --- Plan 240: an incoming announcement uses the same group owner
        // lane and is a valid source after identical byte verification.
        await groupRepo.saveGroup(
          makeGroup(id: 'ann-1', type: GroupType.announcement),
        );
        await messageRepo.saveMessage(
          makeMessage(id: 'msg-ann', group: 'ann-1'),
        );
        final (announcementPath, announcementRelayHash) = await writeMediaFile(
          'att-ann',
          bytes,
          group: 'ann-1',
        );
        await mediaRepo.saveAttachment(
          _attachment(
            id: 'att-ann',
            messageId: 'msg-ann',
            localPath: announcementPath,
            contentHash: announcementRelayHash,
            size: bytes.length,
          ),
          owner: MediaOwnerLane.group,
        );
        final announcementSource = await gate.verify(
          request(group: 'ann-1', message: 'msg-ann', attachment: 'att-ann'),
        );
        expect(announcementSource.isVerified, isTrue);

        // --- Ineligible current state: pending / quarantined rows.
        await messageRepo.saveMessage(makeMessage(id: 'msg-pending'));
        await mediaRepo.saveAttachment(
          _attachment(
            id: 'att-pending',
            messageId: 'msg-pending',
            localPath: storedPath,
            contentHash: relayCiphertextHash,
            downloadStatus: 'pending',
            size: bytes.length,
          ),
          owner: MediaOwnerLane.group,
        );
        final pending = await gate.verify(
          request(message: 'msg-pending', attachment: 'att-pending'),
        );
        expect(pending.isVerified, isFalse);
        expect(pending.denialReason, 'not_displayable');

        // --- 238 lifecycle seam: a restricting policy denies dispatch too.
        final restrictedGate = GroupMediaForwardSourceGate(
          groupRepository: groupRepo,
          messageRepository: messageRepo,
          mediaAttachmentRepository: mediaRepo,
          mediaFileManager: fileManager,
          isLifecycleRestricted: (_) => true,
        );
        final restricted = await restrictedGate.verify(request());
        expect(restricted.isVerified, isFalse);
        expect(restricted.denialReason, 'lifecycle_restricted');

        // --- Missing file: metadata alone can never pass.
        File(storedPath).deleteSync();
        final missingFile = await gate.verify(request());
        expect(missingFile.isVerified, isFalse);
        expect(missingFile.denialReason, 'unsafe_or_missing_local_file');
      },
    );

    test(
      'GMF-01N private expired and wrong-owner sources deny before canonical file work',
      () async {
        await groupRepo.saveGroup(makeGroup());
        await mediaRepo.saveAttachment(
          _attachment(localPath: '/must-not-be-read/private.jpg'),
          owner: MediaOwnerLane.group,
        );

        await messageRepo.saveMessage(
          makeMessage(
            privateMediaPolicy: const GroupPrivateMediaPolicy.viewOnce(),
          ),
        );
        final privateGate = GroupMediaForwardSourceGate(
          groupRepository: groupRepo,
          messageRepository: messageRepo,
          mediaAttachmentRepository: mediaRepo,
          mediaFileManager: fileManager,
        );
        final privateResult = await privateGate.verify(request());
        expect(privateResult.denialReason, 'lifecycle_restricted');
        expect(fileManager.trustedMediaRootPathCount, 0);

        await messageRepo.saveMessage(makeMessage());
        final expiredGate = GroupMediaForwardSourceGate(
          groupRepository: groupRepo,
          messageRepository: messageRepo,
          mediaAttachmentRepository: mediaRepo,
          mediaFileManager: fileManager,
          // The lifecycle owner reports that this ordinary-looking row has
          // expired between viewer qualification and dispatch.
          isLifecycleRestricted: (_) => true,
        );
        final expiredResult = await expiredGate.verify(request());
        expect(expiredResult.denialReason, 'lifecycle_restricted');
        expect(fileManager.trustedMediaRootPathCount, 0);

        await mediaRepo.saveAttachment(
          _attachment(
            id: 'direct-owner-collision',
            localPath: '/must-not-be-read/direct.jpg',
            ownerLane: MediaOwnerLane.direct,
          ),
          owner: MediaOwnerLane.direct,
        );
        final ownerGate = GroupMediaForwardSourceGate(
          groupRepository: groupRepo,
          messageRepository: messageRepo,
          mediaAttachmentRepository: mediaRepo,
          mediaFileManager: fileManager,
        );
        final ownerResult = await ownerGate.verify(
          request(attachment: 'direct-owner-collision'),
        );
        expect(ownerResult.denialReason, 'attachment_not_group_owned');
        expect(fileManager.trustedMediaRootPathCount, 0);
        expect(fileManager.resolveStoredPathCount, 0);
      },
    );

    test(
      'GMF-01O post-copy final parent authority denies every drift and disposes snapshot before delivery',
      () async {
        for (final drift in const <String>[
          'group',
          'parent',
          'tombstone',
          'private',
          'expired',
          'cleanup',
        ]) {
          await groupRepo.saveGroup(makeGroup());
          final driftMessages = InMemoryGroupMessageRepository();
          final exactRowAwait = NthExactMediaReadGatedRepository(gateAtCall: 3);
          final trackingFiles = _SnapshotTrackingFakeMediaFileManager();
          fileManager = trackingFiles;
          final driftMessageId = 'msg-post-validation-$drift';
          final driftAttachmentId = 'att-post-validation-$drift';
          final bytes = List<int>.filled(80, 0x31)
            ..setRange(0, 4, const <int>[0xff, 0xd8, 0xff, 0xe0]);
          final (storedPath, relayCiphertextHash) = await writeMediaFile(
            driftAttachmentId,
            bytes,
          );
          await driftMessages.saveMessage(makeMessage(id: driftMessageId));
          await exactRowAwait.saveAttachment(
            _attachment(
              id: driftAttachmentId,
              messageId: driftMessageId,
              localPath: storedPath,
              contentHash: relayCiphertextHash,
              size: bytes.length,
            ),
            owner: MediaOwnerLane.group,
          );

          addTearDown(() {
            if (!exactRowAwait.release.isCompleted) {
              exactRowAwait.release.complete();
            }
          });
          final contact = _makeContact('peer-post-$drift', 'Post $drift');
          final contacts = InMemoryContactRepository();
          await contacts.addContact(contact);
          var processCalls = 0;
          var sendCalls = 0;
          final coordinator = DefaultShareBatchDeliveryCoordinator(
            identityRepository: FakeIdentityRepository()..seed(_makeIdentity()),
            contactRepository: contacts,
            messageRepository: InMemoryMessageRepository(),
            mediaAttachmentRepository: exactRowAwait,
            groupRepository: groupRepo,
            groupMessageRepository: driftMessages,
            bridge: FakeBridge(),
            p2pService: FakeP2PService(),
            mediaFileManager: trackingFiles,
            imageProcessor: _imageProcessor(),
            processSharedMediaFn: (_) async {
              processCalls++;
              return const ProcessedShareMediaBatch(processedMedia: []);
            },
            sendToContactFn:
                ({
                  required identity,
                  required shareIntent,
                  required contact,
                  required processedMedia,
                  required uploadHooks,
                }) async {
                  sendCalls++;
                  return ShareBatchTargetResult(
                    target: ShareTargetSelection.contact(contact),
                    status: ShareBatchTargetStatus.sent,
                    detail: 'Sent.',
                  );
                },
          );
          final delivery = coordinator.deliverGroupMediaForward(
            request: request(
              message: driftMessageId,
              attachment: driftAttachmentId,
            ),
            targets: [ShareTargetSelection.contact(contact)],
          );
          await exactRowAwait.captured.future.timeout(
            const Duration(seconds: 2),
          );
          switch (drift) {
            case 'group':
              await groupRepo.saveGroup(makeGroup(type: GroupType.qa));
            case 'parent':
              await driftMessages.deleteMessageForMembershipRepair(
                driftMessageId,
              );
            case 'tombstone':
              driftMessages.seedLocalDeletion(
                messageId: driftMessageId,
                groupId: groupId,
              );
            case 'private':
              await driftMessages.saveMessage(
                makeMessage(
                  id: driftMessageId,
                  privateMediaPolicy: const GroupPrivateMediaPolicy.viewOnce(),
                ),
              );
            case 'expired':
              await driftMessages.saveMessage(
                makeMessage(id: driftMessageId, mediaExpiredAt: 1234),
              );
            case 'cleanup':
              await driftMessages.saveMessage(
                makeMessage(id: driftMessageId, mediaCleanupPending: true),
              );
          }
          exactRowAwait.release.complete();

          final result = await delivery;
          expect(result.failureCount, 1, reason: drift);
          expect(processCalls, 0, reason: '$drift bytes never leave the gate');
          expect(sendCalls, 0, reason: '$drift cannot reach a send lane');
          expect(trackingFiles.lastSnapshotDirectory, isNotNull, reason: drift);
          expect(
            Directory(trackingFiles.lastSnapshotDirectory!).existsSync(),
            isFalse,
            reason: '$drift denial must dispose its immutable snapshot',
          );
          expect(File(storedPath).readAsBytesSync(), bytes);
        }
      },
    );

    test(
      'GMF-01T lifecycle cleanup waits for snapshot and coordinator reads only the immutable copy',
      () async {
        final bytes = List<int>.filled(96, 0x31)
          ..setRange(0, 4, const <int>[0xff, 0xd8, 0xff, 0xe0]);
        final (storedPath, relayCiphertextHash) = await writeMediaFile(
          attachmentId,
          bytes,
        );
        await groupRepo.saveGroup(makeGroup());
        await messageRepo.saveMessage(makeMessage());
        final gatedMedia = NthExactMediaReadGatedRepository(gateAtCall: 3);
        await gatedMedia.saveAttachment(
          _attachment(
            localPath: storedPath,
            contentHash: relayCiphertextHash,
            size: bytes.length,
          ),
          owner: MediaOwnerLane.group,
        );

        final contact = _makeContact('peer-snapshot', 'Snapshot');
        final contacts = InMemoryContactRepository();
        await contacts.addContact(contact);
        final cleanupCompleted = Completer<void>();
        addTearDown(() {
          if (!gatedMedia.release.isCompleted) {
            gatedMedia.release.complete();
          }
        });
        String? snapshotPath;
        var processCalls = 0;
        var sendCalls = 0;
        final coordinator = DefaultShareBatchDeliveryCoordinator(
          identityRepository: FakeIdentityRepository()..seed(_makeIdentity()),
          contactRepository: contacts,
          messageRepository: InMemoryMessageRepository(),
          mediaAttachmentRepository: gatedMedia,
          groupRepository: groupRepo,
          groupMessageRepository: messageRepo,
          bridge: FakeBridge(),
          p2pService: FakeP2PService(),
          mediaFileManager: fileManager,
          imageProcessor: _imageProcessor(),
          processSharedMediaFn: (intent) async {
            processCalls++;
            await cleanupCompleted.future.timeout(const Duration(seconds: 2));
            snapshotPath = intent.filePaths.single;
            expect(snapshotPath, isNot(storedPath));
            final snapshot = File(snapshotPath!);
            expect(snapshot.readAsBytesSync(), bytes);
            return ProcessedShareMediaBatch(
              processedMedia: [
                PendingComposerMedia(file: snapshot, budgetBytes: bytes.length),
              ],
            );
          },
          sendToContactFn:
              ({
                required identity,
                required shareIntent,
                required contact,
                required processedMedia,
                required uploadHooks,
              }) async {
                sendCalls++;
                return ShareBatchTargetResult(
                  target: ShareTargetSelection.contact(contact),
                  status: ShareBatchTargetStatus.sent,
                  detail: 'Sent.',
                );
              },
        );

        final delivery = coordinator.deliverGroupMediaForward(
          request: request(),
          targets: [ShareTargetSelection.contact(contact)],
        );
        await gatedMedia.captured.future.timeout(const Duration(seconds: 2));
        var cleanupRan = false;
        final cleanup = mediaAttachmentLifecycleLock.synchronized(
          attachmentId,
          () async {
            cleanupRan = true;
            File(storedPath).deleteSync();
            cleanupCompleted.complete();
          },
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          cleanupRan,
          isFalse,
          reason: 'cleanup cannot interleave with snapshot capture',
        );
        gatedMedia.release.complete();

        final result = await delivery;
        await cleanup;
        expect(result.failureCount, 0);
        expect(processCalls, 1);
        expect(sendCalls, 1);
        expect(cleanupRan, isTrue);
        expect(File(storedPath).existsSync(), isFalse);
        expect(snapshotPath, isNotNull);
        expect(File(snapshotPath!).existsSync(), isFalse);
      },
    );

    test(
      'GMF-01O post-copy lifecycle-queued row mutation waits for qualifier return',
      () async {
        const currentMessageId = 'msg-post-copy-final-order';
        const currentAttachmentId = 'att-post-copy-final-order';
        final lifecycleLock = MediaAttachmentLifecycleLock();
        final exactRowAwait = NthExactMediaReadGatedRepository(gateAtCall: 3);
        final bytes = List<int>.filled(96, 0x31)
          ..setRange(0, 4, const <int>[0xff, 0xd8, 0xff, 0xe0]);
        final (storedPath, relayCiphertextHash) = await writeMediaFile(
          currentAttachmentId,
          bytes,
        );
        await groupRepo.saveGroup(makeGroup());
        await messageRepo.saveMessage(makeMessage(id: currentMessageId));
        await exactRowAwait.saveAttachment(
          _attachment(
            id: currentAttachmentId,
            messageId: currentMessageId,
            localPath: storedPath,
            contentHash: relayCiphertextHash,
            size: bytes.length,
          ),
          owner: MediaOwnerLane.group,
        );
        addTearDown(() {
          if (!exactRowAwait.release.isCompleted) {
            exactRowAwait.release.complete();
          }
        });

        final verification =
            GroupMediaForwardSourceGate(
              groupRepository: groupRepo,
              messageRepository: messageRepo,
              mediaAttachmentRepository: exactRowAwait,
              mediaFileManager: fileManager,
              lifecycleLock: lifecycleLock,
            ).verify(
              request(
                message: currentMessageId,
                attachment: currentAttachmentId,
              ),
              captureImmutableSnapshot: true,
            );

        await exactRowAwait.captured.future.timeout(const Duration(seconds: 2));
        var mutationRan = false;
        final mutation = lifecycleLock.synchronized(
          currentAttachmentId,
          () async {
            mutationRan = true;
            await exactRowAwait.updateDownloadStatus(
              currentAttachmentId,
              'evicted',
            );
          },
        );
        await Future<void>.delayed(Duration.zero);
        expect(mutationRan, isFalse);
        exactRowAwait.release.complete();

        final result = await verification;
        expect(result.isVerified, isTrue);
        await mutation;
        expect(mutationRan, isTrue);
        expect(
          (await exactRowAwait.getAttachmentById(
            currentAttachmentId,
          ))?.downloadStatus,
          'evicted',
        );
        await result.source!.immutableSnapshot!.dispose();
      },
    );

    test(
      'GMF-01S dispatch final-copy row drift disposes snapshot and performs zero process or send',
      () async {
        final bytes = List<int>.filled(96, 0x31)
          ..setRange(0, 4, const <int>[0xff, 0xd8, 0xff, 0xe0]);
        await groupRepo.saveGroup(makeGroup());
        final contact = _makeContact('peer-final-copy', 'Final copy');
        final contacts = InMemoryContactRepository();
        await contacts.addContact(contact);

        for (final mutation in const <String>[
          'localPath',
          'status',
          'size',
          'signature metadata',
        ]) {
          final suffix = mutation.replaceAll(' ', '-');
          final currentMessageId = 'msg-final-copy-$suffix';
          final currentAttachmentId = 'att-final-copy-$suffix';
          final (storedPath, relayCiphertextHash) = await writeMediaFile(
            currentAttachmentId,
            bytes,
          );
          await messageRepo.saveMessage(makeMessage(id: currentMessageId));
          final gatedMedia = NthExactMediaReadGatedRepository(gateAtCall: 3);
          final attachment = _attachment(
            id: currentAttachmentId,
            messageId: currentMessageId,
            localPath: storedPath,
            contentHash: relayCiphertextHash,
            size: bytes.length,
          );
          await gatedMedia.saveAttachment(
            attachment,
            owner: MediaOwnerLane.group,
          );
          addTearDown(() {
            if (!gatedMedia.release.isCompleted) {
              gatedMedia.release.complete();
            }
          });

          var processCalls = 0;
          var sendCalls = 0;
          final coordinator = DefaultShareBatchDeliveryCoordinator(
            identityRepository: FakeIdentityRepository()..seed(_makeIdentity()),
            contactRepository: contacts,
            messageRepository: InMemoryMessageRepository(),
            mediaAttachmentRepository: gatedMedia,
            groupRepository: groupRepo,
            groupMessageRepository: messageRepo,
            bridge: FakeBridge(),
            p2pService: FakeP2PService(),
            mediaFileManager: fileManager,
            imageProcessor: _imageProcessor(),
            processSharedMediaFn: (_) async {
              processCalls++;
              return const ProcessedShareMediaBatch(processedMedia: []);
            },
            sendToContactFn:
                ({
                  required identity,
                  required shareIntent,
                  required contact,
                  required processedMedia,
                  required uploadHooks,
                }) async {
                  sendCalls++;
                  return ShareBatchTargetResult(
                    target: ShareTargetSelection.contact(contact),
                    status: ShareBatchTargetStatus.sent,
                    detail: 'Sent.',
                  );
                },
          );
          final delivery = coordinator.deliverGroupMediaForward(
            request: request(
              message: currentMessageId,
              attachment: currentAttachmentId,
            ),
            targets: [ShareTargetSelection.contact(contact)],
          );

          await gatedMedia.captured.future.timeout(const Duration(seconds: 2));
          switch (mutation) {
            case 'localPath':
              await gatedMedia.updateLocalPath(
                currentAttachmentId,
                'media/$groupId/$currentAttachmentId-moved.jpg',
              );
            case 'status':
              await gatedMedia.updateDownloadStatus(
                currentAttachmentId,
                'evicted',
              );
            case 'size':
              await gatedMedia.saveAttachment(
                attachment.copyWith(size: attachment.size + 1),
                owner: MediaOwnerLane.group,
              );
            case 'signature metadata':
              await gatedMedia.saveAttachment(
                attachment.copyWith(mime: 'image/png'),
                owner: MediaOwnerLane.group,
              );
          }
          gatedMedia.release.complete();

          final result = await delivery;
          expect(result.failureCount, 1, reason: mutation);
          expect(processCalls, 0, reason: mutation);
          expect(sendCalls, 0, reason: mutation);
        }
      },
    );

    test(
      'GMF-01T snapshot dispose retries after a bounded deletion failure and is idempotent',
      () async {
        final retryingManager = _RetryingSnapshotFakeMediaFileManager();
        fileManager = retryingManager;
        final bytes = List<int>.filled(72, 0x31)
          ..setRange(0, 4, const <int>[0xff, 0xd8, 0xff, 0xe0]);
        final (storedPath, relayCiphertextHash) = await writeMediaFile(
          attachmentId,
          bytes,
        );
        await groupRepo.saveGroup(makeGroup());
        await messageRepo.saveMessage(makeMessage());
        await mediaRepo.saveAttachment(
          _attachment(
            localPath: storedPath,
            contentHash: relayCiphertextHash,
            size: bytes.length,
          ),
          owner: MediaOwnerLane.group,
        );
        final result = await GroupMediaForwardSourceGate(
          groupRepository: groupRepo,
          messageRepository: messageRepo,
          mediaAttachmentRepository: mediaRepo,
          mediaFileManager: retryingManager,
        ).verify(request(), captureImmutableSnapshot: true);
        final snapshot = result.source?.immutableSnapshot;
        expect(snapshot, isNotNull);
        expect(File(snapshot!.path).existsSync(), isTrue);

        retryingManager.remainingDeleteFailures = 3;
        await snapshot.dispose();
        expect(retryingManager.physicalDeleteAttempts, 3);
        expect(File(snapshot.path).existsSync(), isTrue);

        retryingManager.remainingDeleteFailures = 0;
        await snapshot.dispose();
        expect(retryingManager.physicalDeleteAttempts, 4);
        expect(File(snapshot.path).existsSync(), isFalse);

        await snapshot.dispose();
        expect(retryingManager.physicalDeleteAttempts, 4);
      },
    );

    test(
      'GMF-01R denied dispatch makes zero uploads and zero deliveries through the coordinator',
      () async {
        // Eligible-looking viewer state whose CURRENT bytes changed after the
        // picker was open: the coordinator-level forward dispatch must fail
        // every target without reading/processing source media or calling any
        // send lane.
        final bytes = List<int>.filled(64, 0x31)
          ..setRange(0, 4, const <int>[0xff, 0xd8, 0xff, 0xe0]);
        final (storedPath, relayCiphertextHash) = await writeMediaFile(
          'att-1',
          bytes,
        );
        await groupRepo.saveGroup(makeGroup());
        await messageRepo.saveMessage(makeMessage());
        await mediaRepo.saveAttachment(
          _attachment(
            localPath: storedPath,
            contentHash: relayCiphertextHash,
            size: bytes.length,
          ),
          owner: MediaOwnerLane.group,
        );
        // The bytes change AFTER the request was built (picker delay).
        File(storedPath).writeAsBytesSync(<int>[...bytes, 1]);

        var processCalls = 0;
        var contactCalls = 0;
        var groupCalls = 0;
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        addTearDown(() => debugSetFlowEventSink(null));
        final contact = _makeContact('peer-bob', 'Bob');
        final contacts = InMemoryContactRepository();
        await contacts.addContact(contact);
        final coordinator = DefaultShareBatchDeliveryCoordinator(
          identityRepository: FakeIdentityRepository()..seed(_makeIdentity()),
          contactRepository: contacts,
          messageRepository: InMemoryMessageRepository(),
          mediaAttachmentRepository: mediaRepo,
          groupRepository: groupRepo,
          groupMessageRepository: messageRepo,
          bridge: FakeBridge(),
          p2pService: FakeP2PService(),
          mediaFileManager: fileManager,
          imageProcessor: _imageProcessor(),
          processSharedMediaFn: (_) async {
            processCalls++;
            return const ProcessedShareMediaBatch(processedMedia: []);
          },
          sendToContactFn:
              ({
                required identity,
                required shareIntent,
                required contact,
                required processedMedia,
                required uploadHooks,
              }) async {
                contactCalls++;
                return ShareBatchTargetResult(
                  target: ShareTargetSelection.contact(contact),
                  status: ShareBatchTargetStatus.sent,
                  detail: 'Sent.',
                );
              },
          sendToGroupFn:
              ({
                required identity,
                required shareIntent,
                required group,
                required processedMedia,
                required uploadHooks,
              }) async {
                groupCalls++;
                return ShareBatchTargetResult(
                  target: ShareTargetSelection.group(group),
                  status: ShareBatchTargetStatus.sent,
                  detail: 'Sent.',
                );
              },
        );

        final targets = [
          ShareTargetSelection.contact(contact),
          ShareTargetSelection.group(makeGroup()),
        ];
        final result = await coordinator.deliverGroupMediaForward(
          request: request(),
          caption: 'edited caption',
          targets: targets,
        );

        expect(result.results, hasLength(2));
        for (final target in result.results) {
          expect(
            target.status,
            ShareBatchTargetStatus.failed,
            reason: 'a failed source verification fails every target',
          );
        }
        expect(processCalls, 0, reason: 'source media is never processed');
        expect(contactCalls, 0, reason: 'no contact delivery is attempted');
        expect(groupCalls, 0, reason: 'no group delivery is attempted');
        final denial = flowEvents.singleWhere(
          (event) => event['event'] == 'GROUP_MEDIA_FORWARD_SOURCE_DENIED',
        );
        expect(
          (denial['details'] as Map<String, dynamic>)['reason'],
          'plaintext_size_mismatch',
        );
        expect((denial['details'] as Map<String, dynamic>)['targetCount'], 2);
      },
    );

    test(
      'GPL-04G dispatch reloads a parent that drifts private during attachment lookup before file work',
      () async {
        final bytes = List<int>.filled(64, 0x31)
          ..setRange(0, 4, const <int>[0xff, 0xd8, 0xff, 0xe0]);
        final (storedPath, relayCiphertextHash) = await writeMediaFile(
          'att-1',
          bytes,
        );
        final gatedMedia = NthExactMediaReadGatedRepository(gateAtCall: 1);
        addTearDown(() {
          if (!gatedMedia.release.isCompleted) {
            gatedMedia.release.complete();
          }
        });
        await groupRepo.saveGroup(makeGroup());
        await messageRepo.saveMessage(makeMessage());
        await gatedMedia.saveAttachment(
          _attachment(
            localPath: storedPath,
            contentHash: relayCiphertextHash,
            size: bytes.length,
          ),
          owner: MediaOwnerLane.group,
        );
        final driftGate = GroupMediaForwardSourceGate(
          groupRepository: groupRepo,
          messageRepository: messageRepo,
          mediaAttachmentRepository: gatedMedia,
          mediaFileManager: fileManager,
        );

        final verification = driftGate.verify(request());
        await gatedMedia.captured.future.timeout(const Duration(seconds: 2));
        await messageRepo.saveMessage(
          makeMessage(
            text: 'PRIVATE CAPTION MUST NOT REACH FILE WORK',
            privateMediaPolicy: const GroupPrivateMediaPolicy.viewOnce(),
          ),
        );
        gatedMedia.release.complete();

        final result = await verification;
        expect(result.isVerified, isFalse);
        expect(result.denialReason, 'lifecycle_restricted');
        expect(fileManager.resolveStoredPathCount, 0);
        expect(fileManager.trustedMediaRootPathCount, 0);
      },
    );
  });
}

class _SnapshotTrackingFakeMediaFileManager extends FakeMediaFileManager {
  String? lastSnapshotDirectory;

  @override
  Future<MediaForwardSnapshotLease> createMediaForwardSnapshotLease() async {
    final lease = await super.createMediaForwardSnapshotLease();
    lastSnapshotDirectory = lease.directory.path;
    return lease;
  }
}

class _RetryingSnapshotFakeMediaFileManager extends FakeMediaFileManager {
  int remainingDeleteFailures = 0;
  int physicalDeleteAttempts = 0;

  @override
  Future<void> deleteGroupForwardSnapshotDirectoryOnce(
    Directory directory,
  ) async {
    physicalDeleteAttempts++;
    if (remainingDeleteFailures > 0) {
      remainingDeleteFailures--;
      throw const FileSystemException('simulated snapshot delete failure');
    }
    await super.deleteGroupForwardSnapshotDirectoryOnce(directory);
  }
}

ContactModel _makeContact(String peerId, String username) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/relay/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-09T08:00:00.000Z',
    mlKemPublicKey: 'mlkem-$peerId',
  );
}

IdentityModel _makeIdentity() {
  return IdentityModel(
    peerId: 'my-peer-id-12345',
    publicKey: 'my-public-key',
    privateKey: 'my-private-key',
    mnemonic12:
        'one two three four five six seven eight nine ten eleven twelve',
    mlKemPublicKey: 'mlkem-public',
    mlKemSecretKey: 'mlkem-secret',
    username: 'Me',
    createdAt: '2026-03-09T08:00:00.000Z',
    updatedAt: '2026-03-09T08:00:00.000Z',
  );
}

ImageProcessor _imageProcessor() {
  return ImageProcessor(
    compressFile:
        ({
          required path,
          required quality,
          required keepExif,
          minWidth = 1920,
          minHeight = 1080,
        }) async => null,
    compressVideo: ({required path, required compress, onProgress}) async =>
        const VideoProcessResult(path: '/tmp/video.mp4'),
  );
}
