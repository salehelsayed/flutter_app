import 'dart:io';

import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../helpers/group_private_media_lifecycle_test_fixture.dart';

void main() {
  test(
    'GPL-06 consumed media stays unavailable across injected restart seams',
    () async {
      for (final crashPoint in const <String>[
        'after-consume',
        'file-delete',
        'key-delete',
        'row-delete',
      ]) {
        final temp = Directory.systemTemp.createTempSync('gpl06-$crashPoint-');
        final databasePath = p.join(temp.path, 'identity.db');
        final firstManager = crashPoint == 'file-delete'
            ? FailOnceGroupPrivateMediaFileManager()
            : FakeMediaFileManager();
        final cleanupFailure = switch (crashPoint) {
          'key-delete' => GroupPrivateCleanupFailurePoint.keyDelete,
          'row-delete' => GroupPrivateCleanupFailurePoint.rowDelete,
          _ => GroupPrivateCleanupFailurePoint.none,
        };
        var fixture = await GroupPrivateMediaLifecycleTestFixture.create(
          databasePath: databasePath,
          nowMs: 2000,
          mediaFileManager: firstManager,
          cleanupFailure: cleanupFailure,
        );
        try {
          final messageId = 'gpl06-$crashPoint';
          final attachmentId = '$messageId-att';
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
          final grant = await fixture.engine.qualifyOpen(
            groupId: 'group-1',
            messageId: messageId,
            attachmentId: attachmentId,
          );
          expect(grant, isNotNull, reason: crashPoint);
          expect(
            await fixture.engine.consumeAtFirstFrame(grant!),
            isTrue,
            reason: crashPoint,
          );

          final consumed = await fixture.messageRepository
              .loadGroupPrivateMediaMessage(messageId);
          expect(consumed!.mediaConsumedAt, 2000, reason: crashPoint);
          expect(consumed.mediaCleanupPending, isTrue, reason: crashPoint);

          if (crashPoint != 'after-consume') {
            final interrupted = await fixture.engine.reconcileLocalLifecycle();
            expect(interrupted.retainedAfterError, 1, reason: crashPoint);
            expect(interrupted.cleanupCompleted, 0, reason: crashPoint);
            expect(
              await fixture.mediaFixture.rawAttachmentRow(attachmentId),
              isNotNull,
              reason:
                  'a partial cleanup remains durably replayable: $crashPoint',
            );
          } else {
            expect(File(seeded.absolutePath).existsSync(), isTrue);
          }

          fixture = await fixture.reopen(
            mediaFileManager: FakeMediaFileManager(),
          );

          expect(
            await fixture.engine.qualifyOpen(
              groupId: 'group-1',
              messageId: messageId,
              attachmentId: attachmentId,
            ),
            isNull,
            reason: 'fresh repositories must deny before decode: $crashPoint',
          );
          expect(
            fixture.mediaFileManager.resolveStoredPathCount,
            0,
            reason:
                'terminal parent state is checked before bytes: $crashPoint',
          );

          final recovered = await fixture.engine.reconcileLocalLifecycle();
          expect(recovered.retainedAfterError, 0, reason: crashPoint);
          expect(recovered.cleanupCompleted, 1, reason: crashPoint);
          final placeholder = await fixture.messageRepository
              .loadGroupPrivateMediaMessage(messageId);
          expect(placeholder, isNotNull, reason: crashPoint);
          expect(placeholder!.mediaConsumedAt, 2000, reason: crashPoint);
          expect(placeholder.mediaCleanupPending, isFalse, reason: crashPoint);
          expect(
            await fixture.mediaFixture.rawAttachmentRow(attachmentId),
            isNull,
            reason: crashPoint,
          );
          expect(File(seeded.absolutePath).existsSync(), isFalse);

          final replay = await fixture.engine.reconcileLocalLifecycle();
          expect(replay.cleanupCompleted, 0, reason: crashPoint);
          expect(replay.retainedAfterError, 0, reason: crashPoint);
        } finally {
          await fixture.dispose();
          if (temp.existsSync()) temp.deleteSync(recursive: true);
        }
      }
    },
  );

  test(
    'GPL-06 recovery clears pending parent after last attachment row was deleted',
    () async {
      final temp = Directory.systemTemp.createTempSync(
        'gpl06-after-row-delete-',
      );
      final databasePath = p.join(temp.path, 'identity.db');
      var fixture = await GroupPrivateMediaLifecycleTestFixture.create(
        databasePath: databasePath,
        nowMs: 2000,
      );
      try {
        const messageId = 'gpl06-after-last-row-delete';
        const attachmentId = '$messageId-att';
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
        final grant = await fixture.engine.qualifyOpen(
          groupId: 'group-1',
          messageId: messageId,
          attachmentId: attachmentId,
        );
        expect(grant, isNotNull);
        expect(await fixture.engine.consumeAtFirstFrame(grant!), isTrue);

        // Reproduce a process death after cleanup has removed the exact file,
        // key, and final attachment row but before it clears the parent marker.
        File(seeded.absolutePath).deleteSync();
        expect(
          await dbDeleteGroupPrivateMediaAttachmentExact(
            fixture.db,
            messageId: messageId,
            attachmentId: attachmentId,
          ),
          1,
        );
        final interrupted = await fixture.messageRepository
            .loadGroupPrivateMediaMessage(messageId);
        expect(interrupted, isNotNull);
        expect(interrupted!.mediaConsumedAt, 2000);
        expect(interrupted.mediaCleanupPending, isTrue);
        expect(
          await fixture.mediaFixture.rawAttachmentRow(attachmentId),
          isNull,
        );

        fixture = await fixture.reopen();
        final recovered = await fixture.engine.reconcileLocalLifecycle();
        expect(recovered.retainedAfterError, 0);
        expect(recovered.cleanupCompleted, 1);
        final placeholder = await fixture.messageRepository
            .loadGroupPrivateMediaMessage(messageId);
        expect(placeholder, isNotNull);
        expect(placeholder!.mediaConsumedAt, 2000);
        expect(placeholder.mediaCleanupPending, isFalse);

        final replay = await fixture.engine.reconcileLocalLifecycle();
        expect(replay.cleanupCompleted, 0);
        expect(replay.retainedAfterError, 0);
      } finally {
        await fixture.dispose();
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      }
    },
  );
}
