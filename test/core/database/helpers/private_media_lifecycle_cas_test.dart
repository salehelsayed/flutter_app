import 'dart:io';

import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';

void main() {
  late MediaRepositoryRealDbFixture fixture;

  setUp(() async {
    fixture = await MediaRepositoryRealDbFixture.create();
  });

  tearDown(() => fixture.dispose());

  Future<void> seedTarget({
    required String id,
    required PrivateMediaDirection direction,
    required String mode,
    String state = 'available',
    String? attachmentId,
    String? localPath,
  }) async {
    await fixture.seedDirectParent(id);
    await fixture.db.update(
      'messages',
      <String, Object?>{
        'is_incoming': direction == PrivateMediaDirection.incoming ? 1 : 0,
        'private_media_policy_version': 1,
        'private_media_mode': mode,
        'private_media_state': state,
        'private_media_received_at_ms': 1000,
        'private_media_clock_high_water_ms': 1000,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    if (attachmentId != null) {
      await dbInsertMediaAttachment(
        fixture.db,
        MediaAttachment(
          id: attachmentId,
          messageId: id,
          mime: 'image/jpeg',
          size: 3,
          mediaType: 'image',
          localPath: localPath,
          downloadStatus: 'done',
          createdAt: '2026-07-19T00:00:00.000Z',
          ownerLane: MediaOwnerLane.direct,
        ).toMap(),
      );
    }
  }

  Future<String> stateOf(String id) async {
    final rows = await fixture.db.query(
      'messages',
      columns: const <String>['private_media_state'],
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    return rows.single['private_media_state']! as String;
  }

  test(
    'direction-aware CAS gives sender protected and view-once one lease while incoming protected repeats without one',
    () async {
      await seedTarget(
        id: 'incoming-protected',
        direction: PrivateMediaDirection.incoming,
        mode: 'protected',
      );
      expect(
        await dbClaimDirectPrivateMediaOpening(
          fixture.db,
          'incoming-protected',
          nowMs: 1100,
        ),
        0,
      );
      expect(await stateOf('incoming-protected'), 'available');

      for (final candidate in <({String id, String mode})>[
        (id: 'incoming-view-once', mode: 'view_once'),
        (id: 'outgoing-protected', mode: 'protected'),
        (id: 'outgoing-view-once', mode: 'view_once'),
      ]) {
        final direction = candidate.id.startsWith('incoming')
            ? PrivateMediaDirection.incoming
            : PrivateMediaDirection.outgoing;
        await seedTarget(
          id: candidate.id,
          direction: direction,
          mode: candidate.mode,
        );
        expect(
          await dbClaimDirectPrivateMediaOpening(
            fixture.db,
            candidate.id,
            nowMs: 1100,
          ),
          1,
          reason: candidate.id,
        );
        expect(
          await dbClaimDirectPrivateMediaOpening(
            fixture.db,
            candidate.id,
            nowMs: 1101,
          ),
          0,
          reason: '${candidate.id} cannot mint a concurrent lease',
        );
        expect(
          await dbMarkDirectPrivateMediaViewing(
            fixture.db,
            candidate.id,
            nowMs: 1200,
          ),
          1,
          reason: candidate.id,
        );
        expect(
          await dbRollbackDirectPrivateMediaOpening(fixture.db, candidate.id),
          0,
          reason: '${candidate.id} cannot roll back after reveal',
        );
        expect(
          await dbConsumeDirectPrivateMedia(
            fixture.db,
            candidate.id,
            nowMs: 1300,
          ),
          1,
          reason: candidate.id,
        );
        expect(await stateOf(candidate.id), 'consumed');
        expect(
          await dbClaimDirectPrivateMediaOpening(
            fixture.db,
            candidate.id,
            nowMs: 1400,
          ),
          0,
          reason: '${candidate.id} is one-shot after consumption',
        );
      }

      await seedTarget(
        id: 'outgoing-disappearing',
        direction: PrivateMediaDirection.outgoing,
        mode: 'disappearing',
      );
      expect(
        await dbClaimDirectPrivateMediaOpening(
          fixture.db,
          'outgoing-disappearing',
          nowMs: 1100,
        ),
        0,
      );
    },
  );

  test(
    'indeterminate quarantine CAS qualifies direction mode identity and path',
    () async {
      const messageId = 'quarantine-outgoing';
      const attachmentId = 'quarantine-outgoing-attachment';
      const localPath = 'media/contact-1/quarantine-outgoing-attachment.jpg';
      await seedTarget(
        id: messageId,
        direction: PrivateMediaDirection.outgoing,
        mode: 'protected',
        attachmentId: attachmentId,
        localPath: localPath,
      );

      Future<int> quarantine({
        PrivateMediaDirection direction = PrivateMediaDirection.outgoing,
        String mode = 'protected',
        String attachment = attachmentId,
        String path = localPath,
      }) => dbQuarantineIndeterminateDirectPrivateMediaAvailable(
        fixture.db,
        messageId,
        isIncoming: direction == PrivateMediaDirection.incoming,
        mode: mode,
        attachmentId: attachment,
        storedLocalPath: path,
        nowMs: 1200,
      );

      expect(await quarantine(direction: PrivateMediaDirection.incoming), 0);
      expect(await quarantine(mode: 'view_once'), 0);
      expect(await quarantine(attachment: 'other-attachment'), 0);
      expect(await quarantine(path: '$localPath.replaced'), 0);
      expect(await stateOf(messageId), 'available');
      expect(await quarantine(), 1);
      expect(await stateOf(messageId), 'opening');
    },
  );

  test(
    'active lease CAS writes match direction mode attachment and stored path',
    () async {
      const messageId = 'exact-active-lease';
      const attachmentId = 'exact-active-lease-attachment';
      const storedPath = 'media/contact-1/exact-active-lease.jpg';
      await seedTarget(
        id: messageId,
        direction: PrivateMediaDirection.outgoing,
        mode: 'protected',
        attachmentId: attachmentId,
        localPath: storedPath,
      );

      Future<int> claim({
        bool? isIncoming = false,
        String? mode = 'protected',
        String? attachment = attachmentId,
        String? path = storedPath,
      }) => dbClaimDirectPrivateMediaOpening(
        fixture.db,
        messageId,
        nowMs: 1100,
        isIncoming: isIncoming,
        mode: mode,
        attachmentId: attachment,
        storedLocalPath: path,
      );

      expect(await claim(isIncoming: true), 0);
      expect(await claim(mode: 'view_once'), 0);
      expect(await claim(attachment: 'replacement'), 0);
      expect(await claim(path: '$storedPath.replaced'), 0);
      expect(
        await dbClaimDirectPrivateMediaOpening(
          fixture.db,
          messageId,
          nowMs: 1100,
          isIncoming: false,
        ),
        0,
        reason: 'a partial exact identity must fail closed',
      );
      expect(await claim(), 1);

      await fixture.db.update(
        'media_attachments',
        <String, Object?>{'local_path': '$storedPath.replaced'},
        where: 'id = ?',
        whereArgs: const <Object?>[attachmentId],
      );
      expect(
        await dbMarkDirectPrivateMediaViewing(
          fixture.db,
          messageId,
          nowMs: 1200,
          isIncoming: false,
          mode: 'protected',
          attachmentId: attachmentId,
          storedLocalPath: storedPath,
        ),
        0,
        reason: 'a replaced attachment path cannot inherit the lease',
      );
      await fixture.db.update(
        'media_attachments',
        const <String, Object?>{'local_path': storedPath},
        where: 'id = ?',
        whereArgs: const <Object?>[attachmentId],
      );
      expect(
        await dbMarkDirectPrivateMediaViewing(
          fixture.db,
          messageId,
          nowMs: 1200,
          isIncoming: false,
          mode: 'protected',
          attachmentId: attachmentId,
          storedLocalPath: storedPath,
        ),
        1,
      );
      expect(
        await dbConsumeDirectPrivateMedia(
          fixture.db,
          messageId,
          nowMs: 1300,
          isIncoming: true,
          mode: 'view_once',
          attachmentId: attachmentId,
          storedLocalPath: storedPath,
        ),
        0,
      );
      expect(
        await dbConsumeDirectPrivateMedia(
          fixture.db,
          messageId,
          nowMs: 1300,
          isIncoming: false,
          mode: 'protected',
          attachmentId: attachmentId,
          storedLocalPath: storedPath,
        ),
        1,
      );

      const rollbackId = 'exact-active-rollback';
      const rollbackAttachmentId = 'exact-active-rollback-attachment';
      const rollbackPath = 'media/contact-1/exact-active-rollback.jpg';
      await seedTarget(
        id: rollbackId,
        direction: PrivateMediaDirection.incoming,
        mode: 'view_once',
        attachmentId: rollbackAttachmentId,
        localPath: rollbackPath,
      );
      expect(
        await dbClaimDirectPrivateMediaOpening(
          fixture.db,
          rollbackId,
          nowMs: 1400,
          isIncoming: true,
          mode: 'view_once',
          attachmentId: rollbackAttachmentId,
          storedLocalPath: rollbackPath,
        ),
        1,
      );
      expect(
        await dbRollbackDirectPrivateMediaOpening(
          fixture.db,
          rollbackId,
          isIncoming: false,
          mode: 'view_once',
          attachmentId: rollbackAttachmentId,
          storedLocalPath: rollbackPath,
        ),
        0,
      );
      expect(
        await dbRollbackDirectPrivateMediaOpening(
          fixture.db,
          rollbackId,
          isIncoming: true,
          mode: 'view_once',
          attachmentId: rollbackAttachmentId,
          storedLocalPath: rollbackPath,
        ),
        1,
      );
    },
  );

  test(
    'recovery candidates include stale sender leases without widening sender modes',
    () async {
      await seedTarget(
        id: 'stale-outgoing-protected',
        direction: PrivateMediaDirection.outgoing,
        mode: 'protected',
        state: 'opening',
      );
      await seedTarget(
        id: 'stale-outgoing-view-once',
        direction: PrivateMediaDirection.outgoing,
        mode: 'view_once',
        state: 'viewing',
      );
      await seedTarget(
        id: 'stale-outgoing-disappearing',
        direction: PrivateMediaDirection.outgoing,
        mode: 'disappearing',
        state: 'opening',
      );

      final rows = await dbLoadDirectPrivateMediaRecoveryCandidates(fixture.db);
      final ids = rows.map((row) => row['id']).toSet();
      expect(
        ids,
        containsAll(<String>{
          'stale-outgoing-protected',
          'stale-outgoing-view-once',
        }),
      );
      expect(ids, isNot(contains('stale-outgoing-disappearing')));
    },
  );

  test(
    'file-backed restart consumes sender lease and reopens with no attachment or key',
    () async {
      await fixture.dispose();
      final temp = Directory.systemTemp.createTempSync(
        'private-sender-restart-',
      );
      addTearDown(() {
        try {
          if (temp.existsSync()) temp.deleteSync(recursive: true);
        } catch (_) {}
      });
      fixture = await MediaRepositoryRealDbFixture.create(
        databasePath: p.join(temp.path, 'identity.db'),
      );
      const messageId = 'restart-outgoing-protected';
      const attachmentId = 'restart-outgoing-protected-attachment';
      const storedPath =
          'media/contact-1/restart-outgoing-protected-attachment.jpg';
      await seedTarget(
        id: messageId,
        direction: PrivateMediaDirection.outgoing,
        mode: 'protected',
        state: 'opening',
      );
      await fixture.repo.saveAttachment(
        const MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 3,
          mediaType: 'image',
          localPath: storedPath,
          downloadStatus: 'done',
          createdAt: '2026-07-19T00:00:00.000Z',
          encryptionKeyBase64: 'c2VuZGVyLWtleQ==',
          encryptionNonce: 'bm9uY2U=',
          ownerLane: MediaOwnerLane.direct,
        ),
        owner: MediaOwnerLane.direct,
      );
      final canonical = File(
        p.join(FakeMediaFileManager.testRootPath, storedPath),
      );
      canonical.parent.createSync(recursive: true);
      canonical.writeAsBytesSync(const <int>[1, 2, 3]);

      fixture = await fixture.reopen();
      final restarted = PrivateMediaLifecycleEngine(
        adapter: DirectPrivateMediaLifecycle(
          messageRepository: fixture.messageRepo,
          mediaAttachmentRepository: fixture.repo,
          mediaFileManager: FakeMediaFileManager(),
        ),
        lifecycleLock: fixture.repo.lifecycleLock,
        nowMs: () => 1500,
      );
      final result = await restarted.reconcileLocalLifecycle();

      expect(result.terminalClaims, 1);
      expect(result.cleanupCompleted, 1);
      expect(canonical.existsSync(), isFalse);
      expect(await fixture.rawAttachmentRow(attachmentId), isNull);
      expect(
        await fixture.secureKeyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName(attachmentId),
        ),
        isFalse,
      );

      fixture = await fixture.reopen();
      final parent = await fixture.messageRepo.getMessage(messageId);
      expect(parent!.privateMediaState, PrivateMediaLifecycleState.consumed);
      expect(
        await fixture.repo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.direct,
        ),
        isEmpty,
      );
      expect(
        await fixture.messageRepo.claimPrivateMediaOpening(
          messageId,
          nowMs: 1600,
        ),
        isFalse,
      );
    },
  );
}
