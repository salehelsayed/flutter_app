import 'dart:io';

import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/group_private_media_lifecycle_test_fixture.dart';

void main() {
  test(
    'APL-09 terminal announcement retains minimized safety metadata without media resurrection',
    () async {
      final fixture = await GroupPrivateMediaLifecycleTestFixture.create(
        nowMs: 2000,
      );
      addTearDown(fixture.dispose);
      const messageId = 'announcement-moderation-placeholder';
      const attachmentId = 'announcement-moderation-attachment';
      const policy = GroupPrivateMediaPolicy.viewOnce();
      await fixture.seedParent(
        groupId: 'announcement-1',
        messageId: messageId,
        policy: policy,
        receivedAt: 1000,
        lastCheckedAt: 1000,
      );
      final seeded = await fixture.seedAttachment(
        groupId: 'announcement-1',
        messageId: messageId,
        attachmentId: attachmentId,
        isBookmarked: true,
        lastPlaybackPositionMs: 12345,
      );

      final grant = await fixture.engine.qualifyOpen(
        groupId: 'announcement-1',
        messageId: messageId,
        attachmentId: attachmentId,
      );
      expect(grant, isNotNull);
      expect(await fixture.engine.consumeAtFirstFrame(grant!), isTrue);
      await fixture.engine.settle(grant);

      final placeholder = await fixture.messageRepository
          .loadGroupPrivateMediaMessage(messageId);
      expect(placeholder, isNotNull);
      expect(placeholder!.id, messageId);
      expect(placeholder.groupId, 'announcement-1');
      expect(placeholder.senderPeerId, 'peer-g');
      expect(placeholder.privateMediaPolicy, policy);
      expect(placeholder.mediaReceivedAt, 1000);
      expect(placeholder.mediaConsumedAt, 2000);
      expect(placeholder.mediaCleanupPending, isFalse);
      expect(
        await fixture.mediaFixture.rawAttachmentRow(attachmentId),
        isNull,
        reason: 'terminal moderation metadata is never a byte recovery path',
      );
      expect(File(seeded.absolutePath).existsSync(), isFalse);
      expect(
        await fixture.engine.qualifyOpen(
          groupId: 'announcement-1',
          messageId: messageId,
          attachmentId: attachmentId,
        ),
        isNull,
        reason: 'a later admin has no lifecycle reset or media override path',
      );
    },
  );
}
