import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

// 236 TC-236-01/01R: pure Forward-offer policy for discussion received media
// plus the dispatch-time source gate. The gate never trusts viewer/picker
// state: it reloads the exact (group, message, attachment) identity under the
// group owner lane and verifies the CURRENT file's SHA-256 against the stored
// content hash immediately before any target lookup, upload, or delivery.

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
}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: mime,
    size: 2048,
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
        'announcement group': _canForward(groupType: GroupType.announcement),
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
    // Private per-test media root: the shared FakeMediaFileManager.testRootPath
    // is deleted by OTHER suites' teardowns when the gate runs files in
    // parallel. Absolute stored paths pass through resolveStoredPath as-is.
    late Directory mediaRoot;

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
    }) {
      return GroupMessage(
        id: id,
        groupId: group,
        senderPeerId: isIncoming ? 'peer-alice' : 'peer-self',
        text: text,
        timestamp: DateTime.utc(2026, 7, 10, 12),
        isIncoming: isIncoming,
        createdAt: DateTime.utc(2026, 7, 10, 12),
      );
    }

    /// Writes real bytes under the fake documents root and returns
    /// (relative stored path, sha256 hex of those exact bytes).
    (String, String) writeMediaFile(
      String name,
      List<int> bytes,
    ) {
      final file = File(p.join(mediaRoot.path, '$name.jpg'));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes);
      return (file.path, sha256.convert(bytes).toString());
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
      mediaRoot = Directory.systemTemp.createTempSync('gmf01r_src_');
      gate = GroupMediaForwardSourceGate(
        groupRepository: groupRepo,
        messageRepository: messageRepo,
        mediaAttachmentRepository: mediaRepo,
        mediaFileManager: fileManager,
      );
    });

    tearDown(() {
      if (mediaRoot.existsSync()) mediaRoot.deleteSync(recursive: true);
    });

    test(
      'GMF-01R dispatch reloads exact group source and verifies current file hash',
      () async {
        // --- Eligible current source: exact current bytes proceed.
        final bytes = List<int>.generate(96, (i) => i);
        final (storedPath, actualHash) = writeMediaFile('att-1', bytes);
        await groupRepo.saveGroup(makeGroup());
        await messageRepo.saveMessage(makeMessage());
        await mediaRepo.saveAttachment(
          _attachment(localPath: storedPath, contentHash: actualHash),
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

        // --- Changed bytes after the picker delay: existence alone is NOT
        // enough; the stored hash no longer matches the current file.
        File(storedPath).writeAsBytesSync(List<int>.filled(96, 9));
        final tampered = await gate.verify(request());
        expect(tampered.isVerified, isFalse);
        expect(tampered.denialReason, 'content_hash_mismatch');

        // Restore the original bytes for the remaining rows.
        File(storedPath).writeAsBytesSync(bytes);
        expect((await gate.verify(request())).isVerified, isTrue);

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
            contentHash: actualHash,
            ownerLane: MediaOwnerLane.direct,
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
            contentHash: actualHash,
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

        // --- Source group is not a discussion group.
        await groupRepo.saveGroup(
          makeGroup(id: 'ann-1', type: GroupType.announcement),
        );
        await messageRepo.saveMessage(
          makeMessage(id: 'msg-ann', group: 'ann-1'),
        );
        await mediaRepo.saveAttachment(
          _attachment(
            id: 'att-ann',
            messageId: 'msg-ann',
            localPath: storedPath,
            contentHash: actualHash,
          ),
          owner: MediaOwnerLane.group,
        );
        final announcementSource = await gate.verify(
          request(group: 'ann-1', message: 'msg-ann', attachment: 'att-ann'),
        );
        expect(announcementSource.isVerified, isFalse);
        expect(announcementSource.denialReason, 'source_group_not_discussion');

        // --- Ineligible current state: pending / quarantined rows.
        await messageRepo.saveMessage(makeMessage(id: 'msg-pending'));
        await mediaRepo.saveAttachment(
          _attachment(
            id: 'att-pending',
            messageId: 'msg-pending',
            localPath: storedPath,
            contentHash: actualHash,
            downloadStatus: 'pending',
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
        expect(missingFile.denialReason, 'missing_file');
      },
    );

    test(
      'GMF-01R denied dispatch makes zero uploads and zero deliveries through the coordinator',
      () async {
        // Eligible-looking viewer state whose CURRENT bytes changed after the
        // picker was open: the coordinator-level forward dispatch must fail
        // every target without reading/processing source media or calling any
        // send lane.
        final bytes = List<int>.generate(64, (i) => 64 - i);
        final (storedPath, actualHash) = writeMediaFile('att-live', bytes);
        await groupRepo.saveGroup(makeGroup());
        await messageRepo.saveMessage(makeMessage());
        await mediaRepo.saveAttachment(
          _attachment(localPath: storedPath, contentHash: actualHash),
          owner: MediaOwnerLane.group,
        );
        // The bytes change AFTER the request was built (picker delay).
        File(storedPath).writeAsBytesSync(List<int>.filled(64, 1));

        var processCalls = 0;
        var contactCalls = 0;
        var groupCalls = 0;
        final coordinator = DefaultShareBatchDeliveryCoordinator(
          identityRepository: FakeIdentityRepository()..seed(_makeIdentity()),
          contactRepository: InMemoryContactRepository(),
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

        final contact = _makeContact('peer-bob', 'Bob');
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
      },
    );
  });
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
