import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_policy.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_private_media_availability.dart';
import 'package:flutter_app/features/groups/application/group_received_media_action_policy.dart';
import 'package:flutter_app/features/groups/application/group_received_media_actions.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_notification_service.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';

const _hash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test(
    'GPL-04A availability off suppresses private derivatives before every ordinary seam',
    () async {
      const ordinary = GroupPrivateMediaPolicy.ordinary();
      const private = GroupPrivateMediaPolicy.viewOnce();
      const unsupported = GroupPrivateMediaPolicy.unsupported(sourceVersion: 9);
      final attachment = _attachment();

      const disabled = GroupPrivateMediaAvailability.disabled();
      expect(disabled.isEnabled, isFalse);
      expect(disabled.canAuthorPrivateMedia(GroupType.chat), isFalse);
      expect(disabled.allowsMediaDerivatives(ordinary), isTrue);
      expect(disabled.allowsMediaDerivatives(private), isFalse);
      expect(disabled.allowsMediaDerivatives(unsupported), isFalse);
      const enabled = productionGroupPrivateMediaAvailability;
      expect(enabled.isEnabled, isTrue);
      expect(enabled.canAuthorPrivateMedia(GroupType.chat), isTrue);
      expect(enabled.canAuthorPrivateMedia(GroupType.announcement), isTrue);
      expect(enabled.allowsMediaDerivatives(private), isTrue);
      expect(enabled.allowsMediaDerivatives(unsupported), isFalse);

      for (final policy in <GroupPrivateMediaPolicy>[private, unsupported]) {
        expect(
          GroupReceivedMediaActionPolicy.capabilitiesFor(
            groupType: GroupType.chat,
            isIncoming: true,
            attachment: attachment,
            canWrite: true,
            mediaPolicy: policy,
          ),
          isEmpty,
          reason: '$policy must enter no ordinary action surface',
        );
        expect(
          GroupMediaForwardPolicy.canOfferForward(
            groupType: GroupType.chat,
            isIncoming: true,
            attachment: attachment,
            mediaPolicy: policy,
          ),
          isFalse,
          reason: '$policy must not offer Forward',
        );
      }
      expect(
        GroupReceivedMediaActionPolicy.capabilitiesFor(
          groupType: GroupType.chat,
          isIncoming: true,
          attachment: attachment,
          canWrite: true,
          mediaPolicy: ordinary,
        ),
        containsAll(<GroupReceivedMediaAction>{
          GroupReceivedMediaAction.save,
          GroupReceivedMediaAction.share,
          GroupReceivedMediaAction.info,
          GroupReceivedMediaAction.deleteForMe,
          GroupReceivedMediaAction.reply,
        }),
      );
      expect(
        GroupMediaForwardPolicy.canOfferForward(
          groupType: GroupType.chat,
          isIncoming: true,
          attachment: attachment,
          mediaPolicy: ordinary,
        ),
        isTrue,
      );

      final messages = InMemoryGroupMessageRepository();
      final media = _CountingMediaRepository();
      await messages.saveMessage(_message(private));
      var restrictionCalls = 0;
      var fileCalls = 0;
      final egressDecision = await qualifyCurrentGroupMediaRow(
        groupId: 'group-a',
        messageId: 'message-a',
        attachmentId: 'attachment-a',
        messageRepository: messages,
        mediaAttachmentRepository: media,
        mediaFileManager: FakeMediaFileManager(),
        isEgressRestricted: (_) {
          restrictionCalls++;
          return false;
        },
        fileExists: (_) async {
          fileCalls++;
          return true;
        },
      );
      expect(egressDecision.isQualified, isFalse);
      expect(egressDecision.refusalReason, 'lifecycle_restricted');
      expect(media.messageLoads, 0);
      expect(restrictionCalls, 0);
      expect(fileCalls, 0);

      var tokenCalls = 0;
      final request =
          await GroupMediaForwardRequestBuilder(
            messageRepository: messages,
            mediaAttachmentRepository: media,
            operationTokenFactory: () {
              tokenCalls++;
              return 'must-not-be-created';
            },
          ).build(
            group: _group(),
            messageId: 'message-a',
            attachmentId: 'attachment-a',
          );
      expect(request, isNull);
      expect(media.messageLoads, 0);
      expect(tokenCalls, 0);

      final forwardFileManager = FakeMediaFileManager();
      final source =
          await GroupMediaForwardSourceGate(
            groupRepository: InMemoryGroupRepository(),
            messageRepository: messages,
            mediaAttachmentRepository: media,
            mediaFileManager: forwardFileManager,
          ).verify(
            const GroupMediaForwardRequest(
              groupId: 'group-a',
              messageId: 'message-a',
              attachmentId: 'attachment-a',
              initialCaption: '',
              provenance: ForwardProvenance(operationDedupKey: 'op-a'),
            ),
          );
      expect(source.isVerified, isFalse);
      expect(source.denialReason, 'lifecycle_restricted');
      expect(media.messageLoads, 0);
      expect(fileCalls, 0);
      expect(forwardFileManager.trustedMediaRootPathCount, 0);

      final receiveGroups = InMemoryGroupRepository();
      final receiveMessages = InMemoryGroupMessageRepository();
      final receiveMedia = InMemoryMediaAttachmentRepository();
      final receiveBridge = FakeBridge();
      final notifications = FakeNotificationService();
      await receiveGroups.saveGroup(_group());
      for (final peerId in const ['peer-self', 'peer-a']) {
        await receiveGroups.saveMember(
          GroupMember(
            groupId: 'group-a',
            peerId: peerId,
            role: MemberRole.writer,
            publicKey: 'pk-$peerId',
            joinedAt: DateTime.utc(2026, 7, 1),
          ),
        );
      }
      final listener = GroupMessageListener(
        groupRepo: receiveGroups,
        msgRepo: receiveMessages,
        bridge: receiveBridge,
        getSelfPeerId: () async => 'peer-self',
        mediaAttachmentRepo: receiveMedia,
        mediaFileManager: FakeMediaFileManager(),
        notificationService: notifications,
        groupConversationTracker: ActiveConversationTracker(),
        getAppLifecycleState: () => AppLifecycleState.paused,
        privateMediaAvailability: disabled,
      );
      final events = StreamController<Map<String, dynamic>>.broadcast();
      listener.start(events.stream);
      addTearDown(() async {
        listener.dispose();
        await events.close();
      });

      Future<GroupMessage> receive(
        String messageId,
        Map<String, Object?> policy,
      ) {
        final persisted = listener.groupMessageStream
            .firstWhere((message) => message.id == messageId)
            .timeout(const Duration(seconds: 2));
        events.add({
          'groupId': 'group-a',
          'senderId': 'peer-a',
          'senderUsername': 'Sender',
          'keyEpoch': 0,
          'messageId': messageId,
          'text': '',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          ...policy,
          'media': [_wireMedia('attachment-$messageId')],
        });
        return persisted;
      }

      final privateMessage = await receive(
        'private-received',
        const GroupPrivateMediaPolicy.viewOnce().toWireExtras()!,
      );
      expect(privateMessage.privateMediaPolicy, private);
      final unsupportedMessage = await receive('unsupported-received', const {
        'mediaPolicyVersion': 9,
        'mediaLifecycle': 'future',
        'mediaDurationSeconds': null,
        'mediaProtected': true,
      });
      expect(unsupportedMessage.privateMediaPolicy.isUnsupported, isTrue);
      final explicitEmptyFuture = listener.groupMessageStream
          .firstWhere((message) => message.id == 'explicit-empty-policy')
          .timeout(const Duration(seconds: 2));
      events.add({
        'groupId': 'group-a',
        'senderId': 'peer-a',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'messageId': 'explicit-empty-policy',
        'text': '',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'mediaPolicyVersion': 7,
      });
      final explicitEmpty = await explicitEmptyFuture;
      expect(explicitEmpty.privateMediaPolicy.isUnsupported, isTrue);
      expect(explicitEmpty.privateMediaPolicy.version, 7);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(notifications.shown, isEmpty);
      expect(receiveBridge.commandLog, isNot(contains('media:download')));

      final ordinaryMessage = await receive('ordinary-received', const {});
      expect(ordinaryMessage.privateMediaPolicy, ordinary);
      await _waitUntil(
        () =>
            notifications.shown.length == 1 &&
            receiveBridge.commandLog.contains('media:download'),
      );
      expect(notifications.shown, hasLength(1));
      expect(receiveBridge.commandLog, contains('media:download'));
    },
  );

  test(
    'GPL-04F request builder requalifies drift after attachment await before token work',
    () async {
      const ordinary = GroupPrivateMediaPolicy.ordinary();
      const private = GroupPrivateMediaPolicy.viewOnce();
      final messages = InMemoryGroupMessageRepository();
      final media = _DriftOnPreviewMediaRepository(messages);
      await messages.saveMessage(_message(ordinary));
      await media.saveAttachment(_attachment(), owner: MediaOwnerLane.group);
      media.driftOnNextLoad = _message(private);
      var tokenCalls = 0;

      final request =
          await GroupMediaForwardRequestBuilder(
            messageRepository: messages,
            mediaAttachmentRepository: media,
            operationTokenFactory: () {
              tokenCalls++;
              return 'must-not-be-created';
            },
          ).build(
            group: _group(),
            messageId: 'message-a',
            attachmentId: 'attachment-a',
          );

      expect(request, isNull);
      expect(tokenCalls, 0);
      expect(media.messageLoads, 1);
      expect(
        (await messages.getMessage('message-a'))!.privateMediaPolicy,
        private,
      );
    },
  );

  test(
    'GPL-04F Forward preview reloads drifted parent before file or picker work',
    () async {
      const ordinary = GroupPrivateMediaPolicy.ordinary();
      const private = GroupPrivateMediaPolicy.viewOnce();
      final messages = InMemoryGroupMessageRepository();
      final media = _DriftOnPreviewMediaRepository(messages);
      await messages.saveMessage(_message(ordinary));
      await media.saveAttachment(_attachment(), owner: MediaOwnerLane.group);

      final request =
          await GroupMediaForwardRequestBuilder(
            messageRepository: messages,
            mediaAttachmentRepository: media,
            operationTokenFactory: () => 'preview-drift-token',
          ).build(
            group: _group(),
            messageId: 'message-a',
            attachmentId: 'attachment-a',
          );
      expect(request, isNotNull);

      media.driftOnNextLoad = _message(private);
      final fileManager = FakeMediaFileManager();
      final groups = InMemoryGroupRepository();
      await groups.saveGroup(_group());
      final preview = await GroupMediaForwardPreviewGate(
        groupRepository: groups,
        messageRepository: messages,
        mediaAttachmentRepository: media,
        mediaFileManager: fileManager,
      ).verify(groupType: GroupType.chat, request: request!);

      expect(preview.isVerified, isFalse);
      expect(preview.denialReason, 'lifecycle_restricted');
      expect(fileManager.resolveStoredPathCount, 0);
      expect(fileManager.trustedMediaRootPathCount, 0);
      expect(media.messageLoads, 1);
      expect(media.exactLoads, 1);
    },
  );
}

class _CountingMediaRepository extends InMemoryMediaAttachmentRepository {
  int messageLoads = 0;

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) {
    messageLoads++;
    return super.getAttachmentsForMessage(messageId, owner: owner);
  }
}

class _DriftOnPreviewMediaRepository extends _CountingMediaRepository {
  _DriftOnPreviewMediaRepository(this.messages);

  final InMemoryGroupMessageRepository messages;
  GroupMessage? driftOnNextLoad;
  int exactLoads = 0;

  Future<void> _applyPendingDrift() async {
    final drift = driftOnNextLoad;
    driftOnNextLoad = null;
    if (drift != null) await messages.saveMessage(drift);
  }

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    final rows = await super.getAttachmentsForMessage(messageId, owner: owner);
    await _applyPendingDrift();
    return rows;
  }

  @override
  Future<MediaAttachment?> getAttachmentById(String id) async {
    exactLoads++;
    final row = await super.getAttachmentById(id);
    await _applyPendingDrift();
    return row;
  }
}

GroupMessage _message(GroupPrivateMediaPolicy policy) => GroupMessage(
  id: 'message-a',
  groupId: 'group-a',
  senderPeerId: 'peer-a',
  text: '',
  timestamp: DateTime.utc(2026, 7, 12),
  privateMediaPolicy: policy,
  createdAt: DateTime.utc(2026, 7, 12),
);

GroupModel _group() => GroupModel(
  id: 'group-a',
  name: 'Discussion',
  type: GroupType.chat,
  topicName: 'topic-a',
  createdAt: DateTime.utc(2026, 7, 1),
  createdBy: 'peer-a',
  myRole: GroupRole.member,
);

MediaAttachment _attachment() => const MediaAttachment(
  id: 'attachment-a',
  messageId: 'message-a',
  mime: 'image/jpeg',
  size: 128,
  mediaType: 'image',
  localPath: 'media/group-a/attachment-a.jpg',
  downloadStatus: 'done',
  createdAt: '2026-07-12T00:00:00.000Z',
  contentHash: _hash,
  encryptionKeyBase64: 'a2V5',
  encryptionNonce: 'bm9uY2U=',
  encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
  ownerLane: MediaOwnerLane.group,
);

Map<String, dynamic> _wireMedia(String id) => <String, dynamic>{
  'id': id,
  'mime': 'image/jpeg',
  'size': 128,
  'mediaType': 'image',
  'downloadStatus': 'pending',
  'createdAt': '2026-07-12T00:00:00.000Z',
  'contentHash': _hash,
  'encryptionKeyBase64': 'a2V5',
  'encryptionNonce': 'bm9uY2U=',
  'encryptionScheme': kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
};
