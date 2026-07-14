import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_private_media_availability.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/push/application/private_media_notification_body.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/fake_notification_service.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';

const _contentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _thumbnailHash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

class _NotificationMediaRepository extends InMemoryMediaAttachmentRepository {
  bool _hasSaved = false;
  int readsBeforeSave = 0;
  int readsAfterSave = 0;

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) async {
    await super.saveAttachment(attachment, owner: owner);
    _hasSaved = true;
  }

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    if (_hasSaved) {
      readsAfterSave++;
    } else {
      readsBeforeSave++;
    }
    return super.getAttachmentsForMessage(messageId, owner: owner);
  }
}

Future<
  ({
    FakeBridge bridge,
    FakeMediaFileManager files,
    GroupMessageListener listener,
    _NotificationMediaRepository media,
    GroupMessageRepository messages,
    FakeNotificationService notifications,
  })
>
_fixture({
  GroupPrivateMediaAvailability availability =
      const GroupPrivateMediaAvailability.enabledForTesting(),
  GroupType groupType = GroupType.chat,
}) async {
  final groups = InMemoryGroupRepository();
  final messages = InMemoryGroupMessageRepository();
  final bridge = FakeBridge();
  final media = _NotificationMediaRepository();
  final files = FakeMediaFileManager();
  final notifications = FakeNotificationService();
  final createdAt = DateTime.utc(2026, 7, 12, 9);
  await groups.saveGroup(
    GroupModel(
      id: 'group-private',
      name: 'SECRET group title',
      type: groupType,
      topicName: 'SECRET topic',
      createdAt: createdAt,
      createdBy: 'peer-admin',
      myRole: GroupRole.admin,
    ),
  );
  for (final member in <GroupMember>[
    GroupMember(
      groupId: 'group-private',
      peerId: 'peer-admin',
      username: 'Admin',
      role: MemberRole.admin,
      publicKey: 'admin-key',
      joinedAt: createdAt,
    ),
    GroupMember(
      groupId: 'group-private',
      peerId: 'peer-sender',
      username: 'SECRET sender name',
      role: groupType == GroupType.announcement
          ? MemberRole.admin
          : MemberRole.writer,
      publicKey: 'sender-key',
      joinedAt: createdAt,
    ),
    GroupMember(
      groupId: 'group-private',
      peerId: 'peer-self',
      username: 'Self',
      role: MemberRole.writer,
      publicKey: 'self-key',
      joinedAt: createdAt,
    ),
  ]) {
    await groups.saveMember(member);
  }
  final listener = GroupMessageListener(
    groupRepo: groups,
    msgRepo: messages,
    bridge: bridge,
    getSelfPeerId: () async => 'peer-self',
    mediaAttachmentRepo: media,
    mediaFileManager: files,
    notificationService: notifications,
    groupConversationTracker: ActiveConversationTracker(),
    getAppLifecycleState: () => AppLifecycleState.paused,
    privateMediaAvailability: availability,
  );
  return (
    bridge: bridge,
    files: files,
    listener: listener,
    media: media,
    messages: messages,
    notifications: notifications,
  );
}

Map<String, dynamic> _privateEvent(String messageId) => <String, dynamic>{
  'groupId': 'group-private',
  'senderId': 'peer-sender',
  'senderUsername': 'SECRET sender name',
  'keyEpoch': 0,
  'messageId': messageId,
  'text': '',
  'timestamp': '2026-07-12T10:00:00.000Z',
  'mediaPolicyVersion': 1,
  'mediaLifecycle': 'viewOnce',
  'mediaDurationSeconds': null,
  'mediaProtected': true,
  'media': <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'SECRET-private-attachment-$messageId',
      'mime': 'image/jpeg',
      'size': 42,
      'mediaType': 'image',
      'downloadStatus': 'pending',
      'contentHash': _contentHash,
      'thumbnailHash': _thumbnailHash,
      'encryptionKeyBase64': 'SECRET-key',
      'encryptionNonce': 'SECRET-nonce',
      'encryptionScheme': 'blob_aes_256_gcm_v1',
      'createdAt': '2026-07-12T10:00:00.000Z',
    },
  ],
};

void main() {
  test(
    'GPL-10 generic notification copy is localized without private metadata',
    () {
      expect(
        localizedGroupPrivateMediaNotificationBody(locale: const Locale('en')),
        'New private media',
      );
      for (final locale in const <Locale>[
        Locale('en'),
        Locale('de'),
        Locale('ar'),
      ]) {
        final body = localizedGroupPrivateMediaNotificationBody(locale: locale);
        expect(body, isNotEmpty);
        expect(body, isNot(contains('SECRET')));
        expect(body, isNot(contains('image')));
        expect(body, isNot(contains('viewOnce')));
        expect(body, isNot(contains('1h')));
      }
    },
  );

  test(
    'GPL-10 enabled listener emits only app title and generic body without plaintext fetch',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.listener.dispose);

      await fixture.listener.handleReplayEnvelope(
        _privateEvent('private-notification-enabled'),
        rethrowOnError: true,
      );

      expect(fixture.notifications.shown, hasLength(1));
      final shown = fixture.notifications.shown.single;
      expect(shown.contactPeerId, 'group:group-private');
      expect(shown.senderUsername, 'Mknoon');
      expect(shown.messageText, localizedGroupPrivateMediaNotificationBody());
      expect(shown.messageText, isNot(contains('SECRET')));
      expect(shown.messageText, isNot(contains('image')));
      expect(shown.messageText, isNot(contains('viewOnce')));
      expect(shown.messageText, isNot(contains('3600')));

      expect(fixture.media.count, 1, reason: 'ingress still persists metadata');
      expect(fixture.media.readsBeforeSave, 1);
      expect(
        fixture.media.readsAfterSave,
        0,
        reason: 'notification preview must not reload attachment metadata',
      );
      expect(fixture.files.resolveStoredPathCount, 0);
      expect(
        fixture.bridge.commandLog.where(
          (command) => command == 'media:download',
        ),
        isEmpty,
      );
      final parent = await fixture.messages.getMessage(
        'private-notification-enabled',
      );
      expect(parent, isNotNull);
      expect(parent!.privateMediaPolicy.isPrivate, isTrue);
    },
  );

  test(
    'GPL-10 disabled availability suppresses the notification and all byte derivatives',
    () async {
      final fixture = await _fixture(
        availability: const GroupPrivateMediaAvailability.disabled(),
      );
      addTearDown(fixture.listener.dispose);

      await fixture.listener.handleReplayEnvelope(
        _privateEvent('private-notification-disabled'),
        rethrowOnError: true,
      );

      expect(fixture.notifications.shown, isEmpty);
      expect(fixture.media.count, 1);
      expect(fixture.media.readsAfterSave, 0);
      expect(fixture.files.resolveStoredPathCount, 0);
      expect(
        fixture.bridge.commandLog.where(
          (command) => command == 'media:download',
        ),
        isEmpty,
      );
      expect(
        await fixture.messages.getMessage('private-notification-disabled'),
        isNotNull,
        reason: 'rollout suppression must not discard the durable parent',
      );
    },
  );

  test(
    'APL-07 enabled announcement listener emits app title and generic body without plaintext fetch',
    () async {
      final fixture = await _fixture(groupType: GroupType.announcement);
      addTearDown(fixture.listener.dispose);

      await fixture.listener.handleReplayEnvelope(
        _privateEvent('announcement-private-notification'),
        rethrowOnError: true,
      );

      expect(fixture.notifications.shown, hasLength(1));
      final shown = fixture.notifications.shown.single;
      expect(shown.senderUsername, 'Mknoon');
      expect(shown.messageText, localizedGroupPrivateMediaNotificationBody());
      expect(shown.messageText, isNot(contains('SECRET')));
      expect(fixture.media.readsAfterSave, 0);
      expect(fixture.files.resolveStoredPathCount, 0);
      expect(
        fixture.bridge.commandLog.where(
          (command) => command == 'media:download',
        ),
        isEmpty,
      );
    },
  );
}
