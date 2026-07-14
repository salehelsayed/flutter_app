import 'dart:io';

import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';

void main() {
  test(
    'reopen terminalizes opening and preserves monotonic expiry across rollback',
    () async {
      final temp = Directory.systemTemp.createTempSync('private-restart-');
      addTearDown(() {
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final dbPath = p.join(temp.path, 'identity.db');
      var fixture = await MediaRepositoryRealDbFixture.create(
        databasePath: dbPath,
      );
      addTearDown(() async {
        try {
          await fixture.dispose();
        } catch (_) {}
      });

      await fixture.seedDirectParent('restart-view-once');
      await fixture.db.update(
        'messages',
        {
          'private_media_policy_version': 1,
          'private_media_mode': 'view_once',
          'private_media_state': 'opening',
          'private_media_received_at_ms': 1000,
          'private_media_clock_high_water_ms': 1100,
        },
        where: 'id = ?',
        whereArgs: ['restart-view-once'],
      );
      await fixture.repo.saveAttachment(
        const MediaAttachment(
          id: 'restart-view-once-att',
          messageId: 'restart-view-once',
          mime: 'image/jpeg',
          size: 1,
          mediaType: 'image',
          localPath: 'media/contact-1/restart-view-once-att.jpg',
          downloadStatus: 'done',
          createdAt: '2026-07-11T00:00:00.000Z',
          encryptionKeyBase64: 'a2V5',
          encryptionNonce: 'bm9uY2U=',
        ),
        owner: MediaOwnerLane.direct,
      );
      await fixture.seedDirectParent('restart-disappearing');
      await fixture.db.update(
        'messages',
        {
          'private_media_policy_version': 1,
          'private_media_mode': 'disappearing',
          'private_media_duration_seconds': 3600,
          'private_media_state': 'available',
          'private_media_received_at_ms': 1000,
          'private_media_expires_at_ms': 2000,
          'private_media_clock_high_water_ms': 1500,
        },
        where: 'id = ?',
        whereArgs: ['restart-disappearing'],
      );
      await fixture.repo.saveAttachment(
        const MediaAttachment(
          id: 'restart-disappearing-att',
          messageId: 'restart-disappearing',
          mime: 'image/jpeg',
          size: 1,
          mediaType: 'image',
          localPath: 'media/contact-1/restart-disappearing-att.jpg',
          downloadStatus: 'done',
          createdAt: '2026-07-11T00:00:00.000Z',
          encryptionKeyBase64: 'a2V5',
          encryptionNonce: 'bm9uY2U=',
        ),
        owner: MediaOwnerLane.direct,
      );

      fixture = await fixture.reopen();
      final adapter = DirectPrivateMediaLifecycle(
        messageRepository: fixture.messageRepo,
        mediaAttachmentRepository: fixture.repo,
        mediaFileManager: FakeMediaFileManager(),
      );
      var currentTimeMs = 1000;
      final restarted = PrivateMediaLifecycleEngine(
        adapter: adapter,
        lifecycleLock: fixture.repo.lifecycleLock,
        nowMs: () => currentTimeMs,
      );

      final first = await restarted.reconcileLocalLifecycle();
      final parent = await fixture.messageRepo.getMessage('restart-view-once');
      expect(
        first.terminalClaims,
        1,
        reason: 'only interrupted View Once is terminal at rollback time',
      );
      expect(
        first.cleanupCompleted,
        1,
        reason: 'unexpired disappearing residue remains locally available',
      );
      expect(parent!.privateMediaState.name, 'consumed');
      expect(await fixture.rawAttachmentRow('restart-view-once-att'), isNull);
      final rollbackParent = await fixture.messageRepo.getMessage(
        'restart-disappearing',
      );
      expect(rollbackParent!.privateMediaState.name, 'available');
      expect(rollbackParent.privateMediaClockHighWaterMs, 1500);
      expect(rollbackParent.privateMediaTerminalAtMs, isNull);
      expect(
        await fixture.rawAttachmentRow('restart-disappearing-att'),
        isNotNull,
      );
      expect(
        await fixture.messageRepo.claimPrivateMediaOpening(
          'restart-view-once',
          nowMs: 2100,
        ),
        isFalse,
        reason: 'replay cannot reopen a terminal parent or remint a lease',
      );

      final second = await restarted.reconcileLocalLifecycle();
      expect(second.terminalClaims, 0);
      expect(second.cleanupCompleted, 0);
      expect(second.retainedAfterError, 0);

      currentTimeMs = 2000;
      final atDeadline = await restarted.reconcileLocalLifecycle();
      expect(atDeadline.terminalClaims, 1);
      expect(atDeadline.cleanupCompleted, 1);
      final expired = await fixture.messageRepo.getMessage(
        'restart-disappearing',
      );
      expect(expired!.privateMediaState.name, 'expired');
      expect(expired.privateMediaClockHighWaterMs, 2000);
      expect(expired.privateMediaTerminalAtMs, 2000);
      expect(
        await fixture.rawAttachmentRow('restart-disappearing-att'),
        isNull,
      );

      final settled = await restarted.reconcileLocalLifecycle();
      expect(settled.terminalClaims, 0);
      expect(settled.cleanupCompleted, 0);
      expect(settled.retainedAfterError, 0);
    },
  );

  test(
    'restart reclaims an exclusive downloading claim and staged bytes',
    () async {
      final temp = Directory.systemTemp.createTempSync(
        'private-download-restart-',
      );
      addTearDown(() {
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final dbPath = p.join(temp.path, 'identity.db');
      var fixture = await MediaRepositoryRealDbFixture.create(
        databasePath: dbPath,
      );
      addTearDown(() async {
        try {
          await fixture.dispose();
        } catch (_) {}
      });
      const messageId = 'restart-downloading';
      const attachmentId = 'restart-downloading-att';
      await fixture.seedDirectParent(messageId);
      await fixture.db.update(
        'messages',
        {
          'private_media_policy_version': 1,
          'private_media_mode': 'protected',
          'private_media_state': 'available',
          'private_media_received_at_ms': 1000,
          'private_media_clock_high_water_ms': 1000,
        },
        where: 'id = ?',
        whereArgs: [messageId],
      );
      await fixture.repo.saveAttachment(
        const MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 3,
          mediaType: 'image',
          downloadStatus: 'downloading',
          createdAt: '2026-07-11T00:00:00.000Z',
          encryptionKeyBase64: 'cmVzdGFydC1rZXk=',
          encryptionNonce: 'bm9uY2U=',
        ),
        owner: MediaOwnerLane.direct,
      );
      final canonical = File(
        p.join(
          FakeMediaFileManager.testRootPath,
          'media/contact-1/$attachmentId.jpg',
        ),
      )..createSync(recursive: true);
      canonical.writeAsBytesSync(const [9, 9, 9]);
      final staged = File('${canonical.path}.part')
        ..writeAsBytesSync(const [1, 2]);

      fixture = await fixture.reopen();
      final restarted = PrivateMediaLifecycleEngine(
        adapter: DirectPrivateMediaLifecycle(
          messageRepository: fixture.messageRepo,
          mediaAttachmentRepository: fixture.repo,
          mediaFileManager: FakeMediaFileManager(),
        ),
        lifecycleLock: fixture.repo.lifecycleLock,
        nowMs: () => 1100,
      );
      final result = await restarted.reconcileLocalLifecycle(limit: 1);

      expect(result.downloadClaimsRecovered, 1);
      expect(result.retainedAfterError, 0);
      expect(canonical.existsSync(), isFalse);
      expect(staged.existsSync(), isFalse);
      final row = await fixture.rawAttachmentRow(attachmentId);
      expect(row!['download_status'], 'failed');
      expect(row['download_retry_count'], 1);
      expect(
        await fixture.secureKeyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName(attachmentId),
        ),
        isTrue,
        reason: 'active parent retains decryptability for the next retry',
      );
      expect(
        await fixture.repo.beginDirectPrivateMediaDownload(
          attachmentId,
          messageId: messageId,
          nowMs: 1200,
        ),
        isTrue,
      );
    },
  );
}
