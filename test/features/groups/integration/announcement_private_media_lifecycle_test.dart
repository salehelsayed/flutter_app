import 'dart:io';

import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/group_private_media_lifecycle_test_fixture.dart';

void main() {
  test(
    'APL-05 announcement view once commits before cleanup and stays consumed after settle',
    () async {
      final fixture = await GroupPrivateMediaLifecycleTestFixture.create(
        nowMs: 2000,
      );
      addTearDown(fixture.dispose);
      const messageId = 'announcement-view-once';
      const attachmentId = 'announcement-view-once-attachment';
      await fixture.seedParent(
        groupId: 'announcement-1',
        messageId: messageId,
        policy: const GroupPrivateMediaPolicy.viewOnce(),
        receivedAt: 1000,
        lastCheckedAt: 1000,
      );
      final seeded = await fixture.seedAttachment(
        groupId: 'announcement-1',
        messageId: messageId,
        attachmentId: attachmentId,
      );

      final grant = await fixture.engine.qualifyOpen(
        groupId: 'announcement-1',
        messageId: messageId,
        attachmentId: attachmentId,
      );
      expect(grant, isNotNull);
      expect(await fixture.engine.consumeAtFirstFrame(grant!), isTrue);
      var parent = await fixture.messageRepository.loadGroupPrivateMediaMessage(
        messageId,
      );
      expect(parent!.mediaConsumedAt, 2000);
      expect(parent.mediaCleanupPending, isTrue);
      expect(
        await fixture.mediaFixture.rawAttachmentRow(attachmentId),
        isNotNull,
        reason:
            'the durable consume must precede every byte cleanup side effect',
      );
      expect(File(seeded.absolutePath).existsSync(), isTrue);

      await fixture.engine.settle(grant);
      parent = await fixture.messageRepository.loadGroupPrivateMediaMessage(
        messageId,
      );
      expect(parent, isNotNull, reason: 'the truthful placeholder remains');
      expect(parent!.mediaConsumedAt, 2000);
      expect(parent.mediaCleanupPending, isFalse);
      expect(await fixture.mediaFixture.rawAttachmentRow(attachmentId), isNull);
      expect(File(seeded.absolutePath).existsSync(), isFalse);
      expect(
        await fixture.engine.qualifyOpen(
          groupId: 'announcement-1',
          messageId: messageId,
          attachmentId: attachmentId,
        ),
        isNull,
      );
    },
  );

  test(
    'APL-06 announcement disappearing state expires on the shared high water clock and cannot reopen',
    () async {
      final fixture = await GroupPrivateMediaLifecycleTestFixture.create(
        nowMs: 5000,
      );
      addTearDown(fixture.dispose);
      const messageId = 'announcement-disappearing';
      const attachmentId = 'announcement-disappearing-attachment';
      await fixture.seedParent(
        groupId: 'announcement-1',
        messageId: messageId,
        policy: GroupPrivateMediaPolicy.disappearing(3600),
        receivedAt: 1000,
        expiresAt: 4000,
        lastCheckedAt: 1000,
      );
      final seeded = await fixture.seedAttachment(
        groupId: 'announcement-1',
        messageId: messageId,
        attachmentId: attachmentId,
      );

      final result = await fixture.engine.sweepExpiries();
      expect(result.terminalClaims, 1);
      expect(result.cleanupCompleted, 1);
      final parent = await fixture.messageRepository
          .loadGroupPrivateMediaMessage(messageId);
      expect(parent, isNotNull);
      expect(parent!.mediaExpiredAt, 5000);
      expect(parent.mediaLastCheckedAt, 5000);
      expect(parent.mediaCleanupPending, isFalse);
      expect(await fixture.mediaFixture.rawAttachmentRow(attachmentId), isNull);
      expect(File(seeded.absolutePath).existsSync(), isFalse);
      expect(
        await fixture.engine.qualifyOpen(
          groupId: 'announcement-1',
          messageId: messageId,
          attachmentId: attachmentId,
        ),
        isNull,
      );
    },
  );
}
