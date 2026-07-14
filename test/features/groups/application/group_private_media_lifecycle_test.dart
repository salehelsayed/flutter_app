import 'dart:io';

import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/group_private_media_lifecycle_test_fixture.dart';

void main() {
  test(
    'GPL-05 view once transition is atomic idempotent granular and boundary exact',
    () async {
      final fixture = await GroupPrivateMediaLifecycleTestFixture.create(
        nowMs: 2000,
      );
      addTearDown(fixture.dispose);

      const messageId = 'gpl05-view-once';
      const attachmentId = 'gpl05-view-once-att';
      await fixture.seedParent(
        messageId: messageId,
        policy: const GroupPrivateMediaPolicy.viewOnce(),
        receivedAt: 1000,
        lastCheckedAt: 1000,
      );
      final seeded = await fixture.seedAttachment(
        messageId: messageId,
        attachmentId: attachmentId,
      );

      final cancelledBeforeDecode = await fixture.engine.qualifyOpen(
        groupId: 'group-1',
        messageId: messageId,
        attachmentId: attachmentId,
      );
      expect(cancelledBeforeDecode, isNotNull);
      var parent = await fixture.messageRepository.loadGroupPrivateMediaMessage(
        messageId,
      );
      expect(parent!.mediaConsumedAt, isNull);
      expect(parent.mediaCleanupPending, isFalse);
      expect(
        await fixture.mediaFixture.rawAttachmentRow(attachmentId),
        isNotNull,
        reason:
            'cancelling or failing decode before first frame is non-consuming',
      );
      expect(File(seeded.absolutePath).existsSync(), isTrue);

      final grants = await Future.wait([
        fixture.engine.qualifyOpen(
          groupId: 'group-1',
          messageId: messageId,
          attachmentId: attachmentId,
        ),
        fixture.engine.qualifyOpen(
          groupId: 'group-1',
          messageId: messageId,
          attachmentId: attachmentId,
        ),
      ]);
      expect(grants, everyElement(isNotNull));

      final consumeResults = await Future.wait([
        fixture.engine.consumeAtFirstFrame(grants[0]!),
        fixture.engine.consumeAtFirstFrame(grants[1]!),
      ]);
      expect(consumeResults.where((consumed) => consumed), hasLength(1));
      final winningGrant = grants[consumeResults.indexOf(true)]!;

      parent = await fixture.messageRepository.loadGroupPrivateMediaMessage(
        messageId,
      );
      expect(parent!.mediaConsumedAt, 2000);
      expect(parent.mediaCleanupPending, isTrue);
      expect(
        await fixture.mediaFixture.rawAttachmentRow(attachmentId),
        isNotNull,
        reason:
            'the durable consumed CAS must precede every cleanup side effect',
      );
      expect(File(seeded.absolutePath).existsSync(), isTrue);
      expect(
        await fixture.mediaFixture.secureKeyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName(attachmentId),
        ),
        isTrue,
      );
      expect(
        await fixture.engine.consumeAtFirstFrame(winningGrant),
        isFalse,
        reason: 'the same first-frame callback is idempotent',
      );
      expect(
        await fixture.engine.qualifyOpen(
          groupId: 'group-1',
          messageId: messageId,
          attachmentId: attachmentId,
        ),
        isNull,
        reason: 'no second open can be minted after the durable consume',
      );

      await fixture.engine.settle(winningGrant);
      parent = await fixture.messageRepository.loadGroupPrivateMediaMessage(
        messageId,
      );
      expect(parent, isNotNull, reason: 'the truthful placeholder is durable');
      expect(parent!.mediaConsumedAt, 2000);
      expect(parent.mediaCleanupPending, isFalse);
      expect(await fixture.mediaFixture.rawAttachmentRow(attachmentId), isNull);
      expect(File(seeded.absolutePath).existsSync(), isFalse);

      const malformedMessageId = 'gpl05-multiple-attachments';
      await fixture.seedParent(
        messageId: malformedMessageId,
        policy: const GroupPrivateMediaPolicy.viewOnce(),
        receivedAt: 3000,
        lastCheckedAt: 3000,
      );
      final firstSibling = await fixture.seedAttachment(
        messageId: malformedMessageId,
        attachmentId: 'gpl05-multiple-a',
      );
      final secondSibling = await fixture.seedAttachment(
        messageId: malformedMessageId,
        attachmentId: 'gpl05-multiple-b',
      );
      expect(
        await fixture.engine.qualifyOpen(
          groupId: 'group-1',
          messageId: malformedMessageId,
          attachmentId: firstSibling.attachment.id,
        ),
        isNull,
        reason:
            'the accepted one-item scope fails closed instead of consuming siblings',
      );
      final malformedParent = await fixture.messageRepository
          .loadGroupPrivateMediaMessage(malformedMessageId);
      expect(malformedParent!.mediaConsumedAt, isNull);
      expect(
        await fixture.mediaFixture.rawAttachmentRow(firstSibling.attachment.id),
        isNotNull,
      );
      expect(
        await fixture.mediaFixture.rawAttachmentRow(
          secondSibling.attachment.id,
        ),
        isNotNull,
      );
    },
  );
}
