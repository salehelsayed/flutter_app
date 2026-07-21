import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/retry_incomplete_group_uploads_use_case.dart';
import 'package:flutter_app/features/groups/application/group_private_media_availability.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../conversation/application/helpers/fake_upload_media_fn.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

const _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Future<void> _seedGroup(
  InMemoryGroupRepository repo, {
  MemberRole selfRole = MemberRole.writer,
}) async {
  await repo.saveGroup(
    GroupModel(
      id: 'group-1',
      name: 'Group',
      type: GroupType.chat,
      topicName: 'topic-1',
      createdAt: DateTime.utc(2026, 7, 12),
      createdBy: 'peer-self',
      myRole: GroupRole.admin,
    ),
  );
  await repo.saveMember(
    GroupMember(
      groupId: 'group-1',
      peerId: 'peer-self',
      role: selfRole,
      publicKey: 'pk-peer-self',
      joinedAt: DateTime.utc(2026, 7, 12),
    ),
  );
  await repo.saveKey(
    GroupKeyInfo(
      groupId: 'group-1',
      keyGeneration: 1,
      encryptedKey: 'group-key',
      createdAt: DateTime.utc(2026, 7, 12),
    ),
  );
}

GroupMessage _parent(String messageId) => GroupMessage(
  id: messageId,
  groupId: 'group-1',
  senderPeerId: 'peer-self',
  senderUsername: 'Self',
  text: '',
  timestamp: DateTime.utc(2026, 7, 12, 10),
  keyGeneration: 1,
  status: 'failed',
  isIncoming: false,
  createdAt: DateTime.utc(2026, 7, 12, 10),
  privateMediaPolicy: const GroupPrivateMediaPolicy.viewOnce(),
  wireEnvelope: jsonEncode({'groupId': 'group-1'}),
);

MediaAttachment _pending(String messageId, String path) => MediaAttachment(
  id: 'private-attachment',
  messageId: messageId,
  mime: 'image/jpeg',
  size: 6,
  mediaType: 'image',
  localPath: path,
  downloadStatus: 'upload_pending',
  createdAt: '2026-07-12T10:00:00.000Z',
);

MediaAttachment _uploaded(String messageId, String path) => MediaAttachment(
  id: 'private-attachment',
  messageId: messageId,
  mime: 'image/jpeg',
  size: 6,
  mediaType: 'image',
  localPath: path,
  downloadStatus: 'done',
  contentHash: _hash,
  encryptionKeyBase64: 'key',
  encryptionNonce: 'nonce',
  encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
  createdAt: '2026-07-12T10:00:00.000Z',
);

class _RevokingAttachmentReadRepository
    extends InMemoryMediaAttachmentRepository {
  _RevokingAttachmentReadRepository(this.groupRepo);

  final InMemoryGroupRepository groupRepo;
  var armed = false;
  var _revoked = false;

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    final attachments = await super.getAttachmentsForMessage(
      messageId,
      owner: owner,
    );
    if (armed && !_revoked) {
      _revoked = true;
      await groupRepo.updateMemberRole(
        'group-1',
        'peer-self',
        MemberRole.reader,
      );
    }
    return attachments;
  }
}

void main() {
  test(
    'foreground durable prep is file-only and claims pending rows inside the B3 leaf',
    () async {
      final source = await File(
        'lib/features/groups/presentation/screens/group_conversation_wired.dart',
      ).readAsString();
      final prepareStart = source.indexOf('_prepareDurableGroupMediaUploads({');
      final leafStart = source.indexOf(
        '_runForegroundGroupUploadLeaf({',
        prepareStart,
      );
      final uploadStart = source.indexOf(
        '_uploadPreparedGroupMediaUploads({',
        leafStart,
      );
      expect(prepareStart, isNonNegative);
      expect(leafStart, greaterThan(prepareStart));
      expect(uploadStart, greaterThan(leafStart));

      final prepareBody = source.substring(prepareStart, leafStart);
      expect(
        prepareBody,
        isNot(contains('saveAttachment(')),
        reason: 'filesystem prep must not create parentless upload rows',
      );

      final leafBody = source.substring(leafStart, uploadStart);
      final phase = leafBody.indexOf('runSelfRemovedGroupLifecycleLeaf');
      final parentReload = leafBody.indexOf('widget.msgRepo.getMessage');
      final pendingSave = leafBody.indexOf(
        'mediaAttachmentRepo.saveAttachment',
      );
      final upload = leafBody.indexOf('final outcome = await upload');
      expect(phase, isNonNegative);
      expect(parentReload, greaterThan(phase));
      expect(pendingSave, greaterThan(parentReload));
      expect(upload, greaterThan(pendingSave));
      expect(
        leafBody,
        contains('completion.completeUploadRetry'),
        reason: 'success completion must remain in the same bounded leaf',
      );

      final voicePending = source.indexOf(
        'pendingAttachment = MediaAttachment(',
        uploadStart,
      );
      final voiceLeaf = source.indexOf(
        'voiceUpload = await _runForegroundGroupUploadLeaf(',
        voicePending,
      );
      final voicePrepBody = source.substring(voicePending, voiceLeaf);
      expect(voicePrepBody, contains('widget.msgRepo.saveMessage'));
      expect(
        voicePrepBody,
        isNot(contains('mediaAttachmentRepo.saveAttachment')),
        reason: 'voice pending-row replacement belongs to the B3 leaf',
      );
    },
  );

  test(
    'restored media replacement cleanup is B3-gated and claimed by the first leaf',
    () async {
      final source = await File(
        'lib/features/groups/presentation/screens/group_conversation_wired.dart',
      ).readAsString();
      final leafStart = source.indexOf('_runForegroundGroupUploadLeaf({');
      final uploadStart = source.indexOf(
        '_uploadPreparedGroupMediaUploads({',
        leafStart,
      );
      final buildStart = source.indexOf(
        '_buildStableUploadedAttachmentFromPlan({',
        uploadStart,
      );
      final onSendStart = source.indexOf('Future<void> _onSend(String text)');
      final onSendEnd = source.indexOf(
        'Future<void> _onRetryUnavailableMedia(',
        onSendStart,
      );
      expect(leafStart, isNonNegative);
      expect(uploadStart, greaterThan(leafStart));
      expect(buildStart, greaterThan(uploadStart));
      expect(onSendStart, isNonNegative);
      expect(onSendEnd, greaterThan(onSendStart));

      final leafBody = source.substring(leafStart, uploadStart);
      final phase = leafBody.indexOf('runSelfRemovedGroupLifecycleLeaf');
      final replacementDelete = leafBody.indexOf(
        'mediaAttachmentRepo.deleteAttachmentsForMessage',
      );
      expect(phase, isNonNegative);
      expect(
        replacementDelete,
        greaterThan(phase),
        reason: 'B3 must win before restored attachment rows can be deleted',
      );

      final uploadBody = source.substring(uploadStart, buildStart);
      expect(
        uploadBody,
        contains('replaceExistingAttachments && index == 0'),
        reason: 'only the first serialized leaf may replace restored rows',
      );
      expect(
        uploadBody,
        contains('if (result == null) return null;'),
        reason: 'a B3-blocked first leaf must prevent every later upload leaf',
      );

      final onSendBody = source.substring(onSendStart, onSendEnd);
      expect(
        onSendBody,
        isNot(contains('_clearPersistedMediaForRestoredContinuation(')),
        reason: 'restored rows must never be cleared before the B3 leaf',
      );
      expect(
        onSendBody,
        contains('replaceExistingAttachments: restoredContinuation != null'),
      );
    },
  );

  test(
    'GPL-03A private parent is durable and requalified immediately before initial and retry upload',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('gpl03a_');
      addTearDown(() => tempDir.delete(recursive: true));
      final path = '${tempDir.path}/private.jpg';
      File(path).writeAsBytesSync(const [0xff, 0xd8, 0xff, 0xe0, 0, 0x10]);

      Future<({int? result, int uploads})> runInitial(
        MemberRole role, {
        bool replaceDurablePolicy = false,
        GroupPrivateMediaAvailability availability =
            const GroupPrivateMediaAvailability.enabledForTesting(),
      }) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final parent = _parent('private-initial');
        await _seedGroup(groupRepo, selfRole: role);
        await msgRepo.saveMessage(
          replaceDurablePolicy
              ? parent.copyWith(
                  privateMediaPolicy: const GroupPrivateMediaPolicy.ordinary(),
                )
              : parent,
        );
        var uploads = 0;
        final result = await runQualifiedPrivateGroupMediaInitialUpload<int>(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          expectedParent: parent,
          senderPeerId: 'peer-self',
          privateMediaAvailability: availability,
          upload: () async {
            uploads++;
            return 1;
          },
        );
        return (result: result, uploads: uploads);
      }

      final initialAllowed = await runInitial(MemberRole.writer);
      expect(initialAllowed.result, 1);
      expect(initialAllowed.uploads, 1);
      final initialReader = await runInitial(MemberRole.reader);
      expect(initialReader.result, isNull);
      expect(initialReader.uploads, 0);
      final initialMismatched = await runInitial(
        MemberRole.writer,
        replaceDurablePolicy: true,
      );
      expect(initialMismatched.result, isNull);
      expect(initialMismatched.uploads, 0);
      final initialDisabled = await runInitial(
        MemberRole.writer,
        availability: const GroupPrivateMediaAvailability.disabled(),
      );
      expect(initialDisabled.result, isNull);
      expect(initialDisabled.uploads, 0);

      Future<({int count, int uploads, FakeBridge bridge})> run(
        MemberRole role, {
        bool revokeDuringAttachmentRead = false,
      }) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final mediaRepo = _RevokingAttachmentReadRepository(groupRepo);
        final bridge = FakeBridge();
        final upload = FakeUploadMediaFn()
          ..willReturn(_uploaded('private-parent', path));
        final identityRepo = FakeIdentityRepository()
          ..seed(
            FakeIdentityRepository.makeIdentity(
              peerId: 'peer-self',
              publicKey: 'pk-peer-self',
              privateKey: 'sk-peer-self',
            ),
          );
        await _seedGroup(groupRepo, selfRole: role);
        await msgRepo.saveMessage(_parent('private-parent'));
        await mediaRepo.saveAttachment(
          _pending('private-parent', path),
          owner: MediaOwnerLane.group,
        );
        mediaRepo.armed = revokeDuringAttachmentRead;

        final count = await retryIncompleteGroupUploads(
          groupRepo: groupRepo,
          groupMsgRepo: msgRepo,
          mediaAttachmentRepo: mediaRepo,
          bridge: bridge,
          p2pService: FakeP2PService(
            initialState: const NodeState(
              isStarted: true,
              peerId: 'peer-self',
              circuitAddresses: [],
            ),
          ),
          identityRepo: identityRepo,
          uploadMediaFn: upload.call,
          messageId: 'private-parent',
          privateMediaAvailability:
              const GroupPrivateMediaAvailability.enabledForTesting(),
        );
        return (count: count, uploads: upload.callCount, bridge: bridge);
      }

      final denied = await run(MemberRole.reader);
      expect(denied.count, 0);
      expect(denied.uploads, 0);
      expect(denied.bridge.commandLog, isEmpty);

      final allowed = await run(MemberRole.writer);
      expect(allowed.count, 1);
      expect(allowed.uploads, 1);
      expect(allowed.bridge.commandLog, contains('group:sendReliable'));

      final revokedDuringPreparation = await run(
        MemberRole.writer,
        revokeDuringAttachmentRead: true,
      );
      expect(revokedDuringPreparation.count, 0);
      expect(revokedDuringPreparation.uploads, 0);
      expect(revokedDuringPreparation.bridge.commandLog, isEmpty);
    },
  );
}
