import 'dart:io';

import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/group_private_media_lifecycle_test_fixture.dart';

void main() {
  test(
    'GPL-07O outgoing disappearing clock anchors once at custody success',
    () async {
      final fixture = await GroupPrivateMediaLifecycleTestFixture.create(
        nowMs: 5000,
      );
      addTearDown(fixture.dispose);
      const messageId = 'gpl07-outgoing-custody';
      await fixture.seedParent(
        messageId: messageId,
        policy: GroupPrivateMediaPolicy.disappearing(3600),
        isIncoming: false,
      );

      expect(
        await fixture.messageRepository.anchorOutgoingGroupPrivateMediaCustody(
          messageId,
          nowMs: 5000,
        ),
        isTrue,
      );
      var parent = await fixture.messageRepository.loadGroupPrivateMediaMessage(
        messageId,
      );
      expect(parent!.mediaReceivedAt, 5000);
      expect(parent.mediaExpiresAt, 3605000);
      expect(parent.mediaLastCheckedAt, 5000);

      expect(
        await fixture.messageRepository.anchorOutgoingGroupPrivateMediaCustody(
          messageId,
          nowMs: 9000,
        ),
        isFalse,
        reason: 'later retries cannot reset the accepted custody anchor',
      );
      parent = await fixture.messageRepository.loadGroupPrivateMediaMessage(
        messageId,
      );
      expect(parent!.mediaReceivedAt, 5000);
      expect(parent.mediaExpiresAt, 3605000);

      fixture.nowMs = 3605000;
      final expired = await fixture.engine.sweepExpiries();
      expect(expired.terminalClaims, 1);
      parent = await fixture.messageRepository.loadGroupPrivateMediaMessage(
        messageId,
      );
      expect(parent!.mediaExpiredAt, 3605000);
    },
  );

  test(
    'GPL-07 expiry state machine follows approved clock authority across lifecycle',
    () async {
      final temp = Directory.systemTemp.createTempSync('gpl07-expiry-');
      final databasePath = p.join(temp.path, 'identity.db');
      var fixture = await GroupPrivateMediaLifecycleTestFixture.create(
        databasePath: databasePath,
        nowMs: 2000,
      );
      try {
        const durationMs = 3600 * 1000;
        const rollbackMessageId = 'gpl07-rollback';
        const rollbackAnchor = 1000;
        const rollbackDeadline = rollbackAnchor + durationMs;
        await fixture.seedParent(
          messageId: rollbackMessageId,
          policy: GroupPrivateMediaPolicy.disappearing(3600),
          receivedAt: rollbackAnchor,
          expiresAt: rollbackDeadline,
          lastCheckedAt: 5000,
        );

        const lateMessageId = 'gpl07-offline-late-arrival';
        const lateReceiverCommit = 10000;
        const lateDeadline = lateReceiverCommit + durationMs;
        await fixture.seedParent(
          messageId: lateMessageId,
          policy: GroupPrivateMediaPolicy.disappearing(3600),
          receivedAt: lateReceiverCommit,
          expiresAt: lateDeadline,
          lastCheckedAt: lateReceiverCommit,
          timestamp: '2020-01-01T00:00:00.000Z',
        );

        expect(await fixture.engine.loadNextExpiryAtMs(), rollbackDeadline);
        final foreground = await fixture.engine.sweepExpiries(
          evaluationFloorMs: 3000,
        );
        expect(foreground.terminalClaims, 0);
        var rollback = await fixture.messageRepository
            .loadGroupPrivateMediaMessage(rollbackMessageId);
        var late = await fixture.messageRepository.loadGroupPrivateMediaMessage(
          lateMessageId,
        );
        expect(
          rollback!.mediaLastCheckedAt,
          5000,
          reason: 'a backward clock sample cannot lower persisted high-water',
        );
        expect(rollback.mediaExpiredAt, isNull);
        expect(late!.mediaReceivedAt, lateReceiverCommit);
        expect(late.mediaExpiresAt, lateDeadline);
        expect(
          late.mediaExpiredAt,
          isNull,
          reason:
              'offline replay anchors at local receiver commit, not old sender time',
        );

        fixture.nowMs = 100;
        fixture = await fixture.reopen();
        final afterRestartRollback = await fixture.engine.sweepExpiries();
        expect(afterRestartRollback.terminalClaims, 0);
        rollback = await fixture.messageRepository.loadGroupPrivateMediaMessage(
          rollbackMessageId,
        );
        late = await fixture.messageRepository.loadGroupPrivateMediaMessage(
          lateMessageId,
        );
        expect(rollback!.mediaLastCheckedAt, 5000);
        expect(late!.mediaLastCheckedAt, lateReceiverCommit);

        fixture.nowMs = rollbackDeadline;
        final exactBoundary = await fixture.engine.sweepExpiries();
        expect(exactBoundary.terminalClaims, 1);
        expect(exactBoundary.cleanupCompleted, 1);
        rollback = await fixture.messageRepository.loadGroupPrivateMediaMessage(
          rollbackMessageId,
        );
        late = await fixture.messageRepository.loadGroupPrivateMediaMessage(
          lateMessageId,
        );
        expect(rollback!.mediaExpiredAt, rollbackDeadline);
        expect(rollback.mediaLastCheckedAt, rollbackDeadline);
        expect(rollback.mediaCleanupPending, isFalse);
        expect(late!.mediaExpiredAt, isNull);
        expect(late.mediaLastCheckedAt, rollbackDeadline);
        expect(await fixture.engine.loadNextExpiryAtMs(), lateDeadline);

        fixture.nowMs = rollbackDeadline - 100000;
        final backgroundRollback = await fixture.engine.sweepExpiries();
        expect(backgroundRollback.terminalClaims, 0);
        late = await fixture.messageRepository.loadGroupPrivateMediaMessage(
          lateMessageId,
        );
        expect(
          late!.mediaLastCheckedAt,
          rollbackDeadline,
          reason: 'background/resume rollback must preserve the prior sample',
        );
        expect(late.mediaExpiredAt, isNull);

        fixture.nowMs = lateDeadline + 500000;
        final forwardJump = await fixture.engine.sweepExpiries();
        expect(forwardJump.terminalClaims, 1);
        expect(forwardJump.cleanupCompleted, 1);
        late = await fixture.messageRepository.loadGroupPrivateMediaMessage(
          lateMessageId,
        );
        expect(
          late!.mediaExpiredAt,
          lateDeadline + 500000,
          reason:
              'a forward jump terminalizes immediately at the effective sample',
        );
        expect(late.mediaLastCheckedAt, lateDeadline + 500000);
        expect(late.mediaCleanupPending, isFalse);
        expect(await fixture.engine.loadNextExpiryAtMs(), isNull);
      } finally {
        await fixture.dispose();
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      }
    },
  );
}
