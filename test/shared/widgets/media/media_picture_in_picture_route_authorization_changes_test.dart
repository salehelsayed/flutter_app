import 'dart:async';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ConversationMessage directMessage(String id, String contactPeerId) =>
      ConversationMessage(
        id: id,
        contactPeerId: contactPeerId,
        senderPeerId: contactPeerId,
        text: '',
        timestamp: '2026-07-14T09:00:00.000Z',
        status: 'delivered',
        isIncoming: true,
        createdAt: '2026-07-14T09:00:00.000Z',
        privateMediaPolicy: const PrivateMediaPolicy.ordinary(),
        privateMediaState: PrivateMediaLifecycleState.none,
      );

  GroupMessage groupMessage(String id, String groupId) => GroupMessage(
    id: id,
    groupId: groupId,
    senderPeerId: 'sender',
    text: '',
    timestamp: DateTime.utc(2026, 7, 14, 9),
    createdAt: DateTime.utc(2026, 7, 14, 9),
  );

  const currentDirectItem = MediaViewerItem(
    attachmentId: 'attachment-active',
    messageId: 'message-active',
    kind: MediaViewerKind.video,
    mime: 'video/mp4',
    owner: MediaOwnerLane.direct,
  );
  const currentGroupItem = MediaViewerItem(
    attachmentId: 'group-attachment-active',
    messageId: 'group-message-active',
    kind: MediaViewerKind.video,
    mime: 'video/mp4',
    owner: MediaOwnerLane.group,
  );

  test(
    'direct production PiP authorization signal is exact-conversation scoped',
    () async {
      final repositoryChanges =
          StreamController<ConversationMessage>.broadcast();
      var signals = 0;
      final subscription = directPictureInPictureAuthorizationChanges(
        repositoryChanges.stream,
        contactPeerId: 'contact-active',
      ).listen((_) => signals++);
      addTearDown(() async {
        await subscription.cancel();
        await repositoryChanges.close();
      });

      repositoryChanges.add(directMessage('other', 'contact-other'));
      await Future<void>.delayed(Duration.zero);
      expect(signals, 0);

      repositoryChanges.add(directMessage('active', 'contact-active'));
      await Future<void>.delayed(Duration.zero);
      expect(signals, 1);
    },
  );

  test(
    'direct production PiP authorization ignores noncurrent typed mutations',
    () async {
      final repositoryChanges =
          StreamController<ConversationMessage>.broadcast();
      final removals = StreamController<DirectMessageRemoval>.broadcast();
      final attachments =
          StreamController<MediaAttachmentAuthorizationChange>.broadcast();
      var signals = 0;
      final subscription = directPictureInPictureAuthorizationChanges(
        repositoryChanges.stream,
        contactPeerId: 'contact-active',
        messageRemovals: removals.stream,
        attachmentChanges: attachments.stream,
        currentItem: () => currentDirectItem,
      ).listen((_) => signals++);
      addTearDown(() async {
        await subscription.cancel();
        await repositoryChanges.close();
        await removals.close();
        await attachments.close();
      });

      repositoryChanges.add(directMessage('message-other', 'contact-active'));
      removals.add(
        const DirectMessageRemoval(
          contactPeerId: 'contact-active',
          messageId: 'message-other',
        ),
      );
      attachments.add(
        const MediaAttachmentAuthorizationChange(
          owner: MediaOwnerLane.direct,
          messageId: 'message-active',
          attachmentId: 'attachment-other',
          kind: MediaAttachmentAuthorizationMutation.evicted,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(signals, 0);

      attachments.add(
        const MediaAttachmentAuthorizationChange(
          owner: MediaOwnerLane.direct,
          messageId: 'message-active',
          attachmentId: 'attachment-active',
          kind: MediaAttachmentAuthorizationMutation.evicted,
        ),
      );
      removals.add(
        const DirectMessageRemoval(
          contactPeerId: 'contact-active',
          messageId: 'message-active',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(signals, 2);
    },
  );

  test(
    'group production PiP authorization signal is exact-group scoped',
    () async {
      final listenerChanges = StreamController<GroupMessage>.broadcast();
      var signals = 0;
      final subscription = groupPictureInPictureAuthorizationChanges(
        listenerChanges.stream,
        groupId: 'group-active',
      ).listen((_) => signals++);
      addTearDown(() async {
        await subscription.cancel();
        await listenerChanges.close();
      });

      listenerChanges.add(groupMessage('other', 'group-other'));
      await Future<void>.delayed(Duration.zero);
      expect(signals, 0);

      listenerChanges.add(groupMessage('active', 'group-active'));
      await Future<void>.delayed(Duration.zero);
      expect(signals, 1);
    },
  );

  test(
    'group production PiP authorization ignores noncurrent typed mutations',
    () async {
      final listenerChanges = StreamController<GroupMessage>.broadcast();
      final repositoryChanges =
          StreamController<GroupMessageAuthorizationChange>.broadcast();
      final attachments =
          StreamController<MediaAttachmentAuthorizationChange>.broadcast();
      var signals = 0;
      final subscription = groupPictureInPictureAuthorizationChanges(
        listenerChanges.stream,
        groupId: 'group-active',
        repositoryChanges: repositoryChanges.stream,
        attachmentChanges: attachments.stream,
        currentItem: () => currentGroupItem,
      ).listen((_) => signals++);
      addTearDown(() async {
        await subscription.cancel();
        await listenerChanges.close();
        await repositoryChanges.close();
        await attachments.close();
      });

      repositoryChanges.add(
        const GroupMessageAuthorizationChange(
          groupId: 'group-active',
          messageId: 'group-message-other',
          kind: GroupMessageAuthorizationMutation.removed,
        ),
      );
      attachments.add(
        const MediaAttachmentAuthorizationChange(
          owner: MediaOwnerLane.group,
          messageId: 'group-message-active',
          attachmentId: 'group-attachment-other',
          kind: MediaAttachmentAuthorizationMutation.evicted,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(signals, 0);

      repositoryChanges.add(
        const GroupMessageAuthorizationChange(
          groupId: 'group-active',
          messageId: 'group-message-active',
          kind: GroupMessageAuthorizationMutation.privateLifecycle,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(signals, 1);
    },
  );
}
