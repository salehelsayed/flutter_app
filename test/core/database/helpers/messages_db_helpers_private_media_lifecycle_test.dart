import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fixtures/media_repository_real_db_fixture.dart';

void main() {
  late MediaRepositoryRealDbFixture fixture;

  setUp(() async {
    fixture = await MediaRepositoryRealDbFixture.create();
  });

  tearDown(() => fixture.dispose());

  Future<void> seedPrivateParent({
    required String id,
    required String mode,
    String state = 'available',
    int receivedAtMs = 1000,
    int? expiresAtMs,
    int highWaterMs = 1000,
  }) async {
    await fixture.seedDirectParent(id);
    await fixture.db.update(
      'messages',
      {
        'private_media_policy_version': 1,
        'private_media_mode': mode,
        'private_media_duration_seconds': mode == 'disappearing' ? 3600 : null,
        'private_media_state': state,
        'private_media_received_at_ms': receivedAtMs,
        'private_media_expires_at_ms': expiresAtMs,
        'private_media_clock_high_water_ms': highWaterMs,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, Object?>> parent(String id) async =>
      (await fixture.db.query(
        'messages',
        where: 'id = ?',
        whereArgs: [id],
      )).single;

  test(
    'stale full save preserves private CAS authority and emits committed snapshot',
    () async {
      const messageId = 'stale-private-save';
      const attachmentId = 'stale-private-save-att';
      await seedPrivateParent(id: messageId, mode: 'view_once');
      final stale = (await fixture.messageRepo.getMessage(messageId))!;
      await fixture.repo.saveAttachment(
        const MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 1,
          mediaType: 'image',
          downloadStatus: 'done',
          localPath: 'media/contact-1/stale-private-save-att.jpg',
          createdAt: '2026-07-11T00:00:00.000Z',
          encryptionKeyBase64: 'a2V5',
          encryptionNonce: 'bm9uY2U=',
        ),
        owner: MediaOwnerLane.direct,
      );
      expect(
        await dbClaimDirectPrivateMediaOpening(
          fixture.db,
          messageId,
          nowMs: 1500,
        ),
        1,
      );
      expect(
        await dbConsumeDirectPrivateMedia(fixture.db, messageId, nowMs: 2000),
        1,
      );
      expect(
        await dbHideDirectPrivateMediaForMe(
          fixture.db,
          messageId,
          hiddenAt: '2026-07-11T00:00:02.000Z',
          nowMs: 2000,
        ),
        1,
      );

      final emittedFuture = fixture.messageRepo.messageChanges.first;
      await fixture.messageRepo.saveMessage(stale);
      final emitted = await emittedFuture;
      final committed = await fixture.messageRepo.getMessage(messageId);
      expect(committed!.hiddenAt, isNotNull);
      expect(committed.privateMediaState.name, 'consumed');
      expect(committed.privateMediaTerminalAtMs, 2000);
      expect(committed.privateMediaClockHighWaterMs, 2000);
      expect(emitted.hiddenAt, committed.hiddenAt);
      expect(emitted.privateMediaState, committed.privateMediaState);
      expect(
        await fixture.rawAttachmentRow(attachmentId),
        isNotNull,
        reason: 'existing-row UPDATE must preserve attachment relations',
      );

      final remoteDeleted = committed.copyWith(
        deletedAt: '2026-07-11T00:00:03.000Z',
        deletedByPeerId: 'contact-1',
      );
      await fixture.messageRepo.saveMessage(remoteDeleted);
      await fixture.messageRepo.saveMessage(stale);
      final afterStaleReplay = await fixture.messageRepo.getMessage(messageId);
      expect(afterStaleReplay!.deletedAt, remoteDeleted.deletedAt);
      expect(afterStaleReplay.deletedByPeerId, 'contact-1');
      expect(afterStaleReplay.hiddenAt, isNotNull);
      expect(afterStaleReplay.privateMediaState.name, 'consumed');

      expect(
        await fixture.repo.deleteDirectPrivateMediaEncryptionKeyWithinLock(
          messageId: messageId,
          attachmentId: attachmentId,
        ),
        isTrue,
      );
      expect(
        await fixture.repo.deleteDirectPrivateMediaAttachmentWithinLock(
          messageId: messageId,
          attachmentId: attachmentId,
        ),
        1,
        reason: 'remote delete remains private cleanup authority',
      );
    },
  );

  test(
    'view-once opening/viewing/rollback are conditional CAS writes',
    () async {
      await seedPrivateParent(id: 'view-once', mode: 'view_once');

      final results = await Future.wait([
        dbClaimDirectPrivateMediaOpening(fixture.db, 'view-once', nowMs: 1100),
        dbClaimDirectPrivateMediaOpening(fixture.db, 'view-once', nowMs: 1100),
      ]);

      expect(results.where((count) => count == 1), hasLength(1));
      expect((await parent('view-once'))['private_media_state'], 'opening');
      expect(
        await dbMarkDirectPrivateMediaViewing(
          fixture.db,
          'view-once',
          nowMs: 1200,
        ),
        1,
      );
      expect(
        await dbRollbackDirectPrivateMediaOpening(fixture.db, 'view-once'),
        0,
        reason: 'viewing cannot be rolled back to available',
      );
      expect(
        await dbConsumeDirectPrivateMedia(fixture.db, 'view-once', nowMs: 1300),
        1,
      );
      expect(
        await dbMarkDirectPrivateMediaViewing(
          fixture.db,
          'view-once',
          nowMs: 1400,
        ),
        0,
        reason: 'a stale first-frame callback cannot reopen a terminal row',
      );
    },
  );

  test('only view-once may enter opening/viewing', () async {
    await seedPrivateParent(id: 'protected', mode: 'protected');
    await seedPrivateParent(
      id: 'disappearing',
      mode: 'disappearing',
      expiresAtMs: 5000,
    );

    expect(
      await dbClaimDirectPrivateMediaOpening(
        fixture.db,
        'protected',
        nowMs: 1100,
      ),
      0,
    );
    expect(
      await dbClaimDirectPrivateMediaOpening(
        fixture.db,
        'disappearing',
        nowMs: 1100,
      ),
      0,
    );
  });

  test(
    'clock rollback preserves high-water until exact expiry and never reopens',
    () async {
      await seedPrivateParent(
        id: 'expiring',
        mode: 'disappearing',
        expiresAtMs: 2000,
      );

      expect(
        await dbAdvanceDirectPrivateMediaClock(
          fixture.db,
          'expiring',
          nowMs: 1500,
        ),
        1,
      );
      expect(
        (await parent('expiring'))['private_media_clock_high_water_ms'],
        1500,
      );
      await dbAdvanceDirectPrivateMediaClock(
        fixture.db,
        'expiring',
        nowMs: 1200,
      );
      expect(
        (await parent('expiring'))['private_media_clock_high_water_ms'],
        1500,
        reason: 'backward wall time cannot lower the persisted high-water',
      );
      final afterRollback = await parent('expiring');
      expect(afterRollback['private_media_state'], 'available');
      expect(afterRollback['private_media_terminal_at_ms'], isNull);
      await dbAdvanceDirectPrivateMediaClock(
        fixture.db,
        'expiring',
        nowMs: 2000,
      );
      final expired = await parent('expiring');
      expect(expired['private_media_state'], 'expired');
      expect(expired['private_media_terminal_at_ms'], 2000);

      await dbAdvanceDirectPrivateMediaClock(
        fixture.db,
        'expiring',
        nowMs: 1100,
      );
      expect((await parent('expiring'))['private_media_state'], 'expired');
    },
  );

  test('download final commit atomically loses to parent expiry', () async {
    await seedPrivateParent(
      id: 'download-race',
      mode: 'disappearing',
      expiresAtMs: 1500,
    );
    await fixture.repo.saveAttachment(
      const MediaAttachment(
        id: 'download-race-att',
        messageId: 'download-race',
        mime: 'image/jpeg',
        size: 3,
        mediaType: 'image',
        downloadStatus: 'downloading',
        createdAt: '2026-07-11T00:00:00.000Z',
      ),
      owner: MediaOwnerLane.direct,
    );

    expect(
      await dbCommitDirectPrivateMediaDownloadIfEligible(
        fixture.db,
        messageId: 'download-race',
        attachmentId: 'download-race-att',
        localPath: 'media/contact-1/download-race-att.jpg',
        nowMs: 1500,
      ),
      0,
    );
    expect((await parent('download-race'))['private_media_state'], 'expired');
    final attachment = await fixture.rawAttachmentRow('download-race-att');
    expect(attachment!['download_status'], 'downloading');
    expect(attachment['local_path'], isNull);
  });

  test(
    'atomic commit leaves ordinary outgoing wrong-owner and wrong-parent rows unchanged',
    () async {
      Future<void> seedAttachment({
        required String id,
        required String messageId,
        MediaOwnerLane owner = MediaOwnerLane.direct,
      }) {
        return fixture.repo.saveAttachment(
          MediaAttachment(
            id: id,
            messageId: messageId,
            mime: 'image/jpeg',
            size: 3,
            mediaType: 'image',
            downloadStatus: 'downloading',
            createdAt: '2026-07-11T00:00:00.000Z',
          ),
          owner: owner,
        );
      }

      await fixture.seedDirectParent('ordinary');
      await seedAttachment(id: 'ordinary-att', messageId: 'ordinary');

      await seedPrivateParent(
        id: 'outgoing',
        mode: 'disappearing',
        expiresAtMs: 1200,
      );
      await fixture.db.update(
        'messages',
        {'is_incoming': 0},
        where: 'id = ?',
        whereArgs: ['outgoing'],
      );
      await seedAttachment(id: 'outgoing-att', messageId: 'outgoing');

      await seedPrivateParent(id: 'wrong-owner', mode: 'protected');
      await fixture.seedGroupParent('wrong-owner');
      await seedAttachment(
        id: 'wrong-owner-att',
        messageId: 'wrong-owner',
        owner: MediaOwnerLane.group,
      );

      await seedPrivateParent(id: 'expected-parent', mode: 'protected');
      await fixture.seedDirectParent('actual-parent');
      await seedAttachment(id: 'wrong-parent-att', messageId: 'actual-parent');

      for (final candidate in <({String messageId, String attachmentId})>[
        (messageId: 'ordinary', attachmentId: 'ordinary-att'),
        (messageId: 'outgoing', attachmentId: 'outgoing-att'),
        (messageId: 'wrong-owner', attachmentId: 'wrong-owner-att'),
        (messageId: 'expected-parent', attachmentId: 'wrong-parent-att'),
      ]) {
        expect(
          await dbCommitDirectPrivateMediaDownloadIfEligible(
            fixture.db,
            messageId: candidate.messageId,
            attachmentId: candidate.attachmentId,
            localPath: 'media/contact-1/${candidate.attachmentId}.jpg',
            nowMs: 1500,
          ),
          0,
        );
        final row = await fixture.rawAttachmentRow(candidate.attachmentId);
        expect(row!['download_status'], 'downloading');
        expect(row['local_path'], isNull);
      }

      final outgoing = await parent('outgoing');
      expect(outgoing['private_media_state'], 'available');
      expect(outgoing['private_media_clock_high_water_ms'], 1000);
      expect(outgoing['private_media_terminal_at_ms'], isNull);
    },
  );

  test('private delete keeps truthful hidden tombstone state', () async {
    await seedPrivateParent(id: 'delete-protected', mode: 'protected');

    expect(
      await dbHideDirectPrivateMediaForMe(
        fixture.db,
        'delete-protected',
        hiddenAt: '2026-07-11T13:00:00.000Z',
        nowMs: 2000,
      ),
      1,
    );
    final hidden = await parent('delete-protected');
    expect(hidden['hidden_at'], '2026-07-11T13:00:00.000Z');
    expect(hidden['private_media_state'], 'available');
    expect(
      await dbClaimDirectPrivateMediaOpening(
        fixture.db,
        'delete-protected',
        nowMs: 2100,
      ),
      0,
    );
  });

  test('clean tombstones cannot starve bounded residual cleanup', () async {
    for (var index = 0; index < 101; index++) {
      await seedPrivateParent(
        id: 'clean-terminal-$index',
        mode: 'view_once',
        state: 'consumed',
      );
    }
    await seedPrivateParent(
      id: 'residual-terminal',
      mode: 'view_once',
      state: 'consumed',
    );
    await fixture.repo.saveAttachment(
      const MediaAttachment(
        id: 'residual-terminal-att',
        messageId: 'residual-terminal',
        mime: 'image/jpeg',
        size: 1,
        mediaType: 'image',
        downloadStatus: 'done',
        localPath: 'media/contact-1/residual-terminal-att.jpg',
        createdAt: '2026-07-11T00:00:00.000Z',
      ),
      owner: MediaOwnerLane.direct,
    );

    final candidates = await dbLoadDirectPrivateMediaRecoveryCandidates(
      fixture.db,
      limit: 100,
    );

    expect(candidates.map((row) => row['id']), ['residual-terminal']);
  });

  test(
    'every guarded attachment mutation keeps unexpired rollback eligible',
    () async {
      Future<void> seedRollbackParent(String id) => seedPrivateParent(
        id: id,
        mode: 'disappearing',
        expiresAtMs: 5000,
        highWaterMs: 1500,
      );

      for (final id in const ['save', 'begin', 'ready', 'failure', 'commit']) {
        await seedRollbackParent('rollback-$id');
      }
      Future<void> seedRow(String id, String status, {String? localPath}) =>
          fixture.repo.saveAttachment(
            MediaAttachment(
              id: 'rollback-$id-att',
              messageId: 'rollback-$id',
              mime: 'image/jpeg',
              size: 3,
              mediaType: 'image',
              downloadStatus: status,
              localPath: localPath,
              createdAt: '2026-07-11T00:00:00.000Z',
            ),
            owner: MediaOwnerLane.direct,
          );
      await seedRow('begin', 'pending');
      await seedRow(
        'ready',
        'done',
        localPath: 'media/contact-1/rollback-ready-att.jpg',
      );
      await seedRow('failure', 'downloading');
      await seedRow('commit', 'downloading');

      final guardedRow = const MediaAttachment(
        id: 'rollback-save-att',
        messageId: 'rollback-save',
        mime: 'image/jpeg',
        size: 3,
        mediaType: 'image',
        downloadStatus: 'pending',
        createdAt: '2026-07-11T00:00:00.000Z',
      ).copyWith(ownerLane: MediaOwnerLane.direct).toMap();
      expect(
        await dbSaveDirectPrivateMediaAttachmentGuarded(
          fixture.db,
          guardedRow,
          messageId: 'rollback-save',
          nowMs: 1200,
        ),
        isTrue,
      );
      expect(
        await dbBeginDirectPrivateMediaDownloadIfEligible(
          fixture.db,
          messageId: 'rollback-begin',
          attachmentId: 'rollback-begin-att',
          nowMs: 1200,
        ),
        1,
      );
      expect(
        await dbQualifyDirectPrivateMediaLocalReadyIfEligible(
          fixture.db,
          messageId: 'rollback-ready',
          attachmentId: 'rollback-ready-att',
          expectedLocalPath: 'media/contact-1/rollback-ready-att.jpg',
          nowMs: 1200,
        ),
        1,
      );
      expect(
        await dbRecordDirectPrivateMediaDownloadFailureIfEligible(
          fixture.db,
          messageId: 'rollback-failure',
          attachmentId: 'rollback-failure-att',
          nowMs: 1200,
          incrementRetryCount: true,
          failureStatus: 'failed',
          expectedDownloadStatus: 'downloading',
        ),
        1,
      );
      expect(
        await dbCommitDirectPrivateMediaDownloadIfEligible(
          fixture.db,
          messageId: 'rollback-commit',
          attachmentId: 'rollback-commit-att',
          localPath: 'media/contact-1/rollback-commit-att.jpg',
          nowMs: 1200,
        ),
        1,
      );

      for (final id in const ['save', 'begin', 'ready', 'failure', 'commit']) {
        final current = await parent('rollback-$id');
        expect(current['private_media_state'], 'available');
        expect(current['private_media_clock_high_water_ms'], 1500);
        expect(current['private_media_terminal_at_ms'], isNull);
      }
      expect(
        (await fixture.rawAttachmentRow(
          'rollback-save-att',
        ))!['download_status'],
        'pending',
      );
      expect(
        (await fixture.rawAttachmentRow(
          'rollback-begin-att',
        ))!['download_status'],
        'downloading',
      );
      expect(
        (await fixture.rawAttachmentRow(
          'rollback-ready-att',
        ))!['download_status'],
        'done',
      );
      expect(
        (await fixture.rawAttachmentRow(
          'rollback-failure-att',
        ))!['download_status'],
        'failed',
      );
      final committed = await fixture.rawAttachmentRow('rollback-commit-att');
      expect(committed!['download_status'], 'done');
      expect(
        committed['local_path'],
        'media/contact-1/rollback-commit-att.jpg',
      );
    },
  );

  test('private begin has one owner and never reclaims downloading', () async {
    await seedPrivateParent(id: 'single-owner', mode: 'protected');
    await fixture.repo.saveAttachment(
      const MediaAttachment(
        id: 'single-owner-att',
        messageId: 'single-owner',
        mime: 'image/jpeg',
        size: 3,
        mediaType: 'image',
        downloadStatus: 'pending',
        createdAt: '2026-07-11T00:00:00.000Z',
      ),
      owner: MediaOwnerLane.direct,
    );
    final claims = await Future.wait([
      dbBeginDirectPrivateMediaDownloadIfEligible(
        fixture.db,
        messageId: 'single-owner',
        attachmentId: 'single-owner-att',
        nowMs: 1100,
      ),
      dbBeginDirectPrivateMediaDownloadIfEligible(
        fixture.db,
        messageId: 'single-owner',
        attachmentId: 'single-owner-att',
        nowMs: 1100,
      ),
    ]);
    expect(claims.reduce((a, b) => a + b), 1);
    expect(
      await dbBeginDirectPrivateMediaDownloadIfEligible(
        fixture.db,
        messageId: 'single-owner',
        attachmentId: 'single-owner-att',
        nowMs: 1100,
      ),
      0,
    );
  });

  test(
    'private failure CAS requires exact status and committed path',
    () async {
      await seedPrivateParent(id: 'failure-cas', mode: 'protected');
      await fixture.repo.saveAttachment(
        const MediaAttachment(
          id: 'failure-cas-att',
          messageId: 'failure-cas',
          mime: 'image/jpeg',
          size: 3,
          mediaType: 'image',
          downloadStatus: 'done',
          localPath: 'media/contact-1/failure-cas-att.jpg',
          createdAt: '2026-07-11T00:00:00.000Z',
        ),
        owner: MediaOwnerLane.direct,
      );
      Future<int> record(String status, String? path) =>
          dbRecordDirectPrivateMediaDownloadFailureIfEligible(
            fixture.db,
            messageId: 'failure-cas',
            attachmentId: 'failure-cas-att',
            nowMs: 1100,
            incrementRetryCount: false,
            failureStatus: 'failed',
            expectedDownloadStatus: status,
            expectedLocalPath: path,
            clearLocalPath: true,
          );
      expect(await record('downloading', null), 0);
      expect(await record('done', 'media/contact-1/wrong.jpg'), 0);
      expect(
        (await fixture.rawAttachmentRow('failure-cas-att'))!['local_path'],
        isNotNull,
      );
      expect(await record('done', 'media/contact-1/failure-cas-att.jpg'), 1);
      final row = await fixture.rawAttachmentRow('failure-cas-att');
      expect(row!['download_status'], 'failed');
      expect(row['local_path'], isNull);
    },
  );

  test('private commit rejects a noncanonical path before mutation', () async {
    await seedPrivateParent(id: 'canonical-commit', mode: 'protected');
    await fixture.repo.saveAttachment(
      const MediaAttachment(
        id: 'canonical-commit-att',
        messageId: 'canonical-commit',
        mime: 'image/jpeg',
        size: 3,
        mediaType: 'image',
        downloadStatus: 'downloading',
        createdAt: '2026-07-11T00:00:00.000Z',
      ),
      owner: MediaOwnerLane.direct,
    );
    expect(
      await dbCommitDirectPrivateMediaDownloadIfEligible(
        fixture.db,
        messageId: 'canonical-commit',
        attachmentId: 'canonical-commit-att',
        localPath: '../external.jpg',
        nowMs: 1100,
      ),
      0,
    );
    expect(
      await dbCommitDirectPrivateMediaDownloadIfEligible(
        fixture.db,
        messageId: 'canonical-commit',
        attachmentId: 'canonical-commit-att',
        localPath: 'media/contact-1/canonical-commit-att.jpg',
        nowMs: 1100,
      ),
      1,
    );
  });

  test('v0 terminal corrupt rows cannot enter or starve recovery', () async {
    await seedPrivateParent(
      id: 'v0-terminal',
      mode: 'protected',
      state: 'consumed',
    );
    await fixture.db.update(
      'messages',
      {'private_media_policy_version': 0},
      where: 'id = ?',
      whereArgs: ['v0-terminal'],
    );
    await fixture.repo.saveAttachment(
      const MediaAttachment(
        id: 'v0-terminal-att',
        messageId: 'v0-terminal',
        mime: 'image/jpeg',
        size: 1,
        mediaType: 'image',
        downloadStatus: 'done',
        createdAt: '2026-07-11T00:00:00.000Z',
      ),
      owner: MediaOwnerLane.direct,
    );
    expect(
      await dbLoadDirectPrivateMediaRecoveryCandidates(fixture.db, limit: 1),
      isEmpty,
    );
    expect(
      await dbRotateDirectPrivateMediaRecoveryCandidate(
        fixture.db,
        'v0-terminal',
        nowMs: 9999,
      ),
      0,
    );
  });

  test('external qualifier terminalization emits exactly once', () async {
    await seedPrivateParent(
      id: 'external-emission',
      mode: 'disappearing',
      expiresAtMs: 5000,
      highWaterMs: 5000,
    );
    await fixture.repo.saveAttachment(
      const MediaAttachment(
        id: 'external-emission-att',
        messageId: 'external-emission',
        mime: 'image/jpeg',
        size: 1,
        mediaType: 'image',
        downloadStatus: 'pending',
        createdAt: '2026-07-11T00:00:00.000Z',
      ),
      owner: MediaOwnerLane.direct,
    );
    await fixture.messageRepo.getMessage('external-emission');
    final emitted = <String>[];
    final subscription = fixture.messageRepo.messageChanges.listen(
      (message) => emitted.add(message.privateMediaState.name),
    );
    addTearDown(subscription.cancel);
    expect(
      await fixture.repo.beginDirectPrivateMediaDownload(
        'external-emission-att',
        messageId: 'external-emission',
        nowMs: 1200,
      ),
      isFalse,
    );
    expect(
      await fixture.repo.qualifyDirectPrivateMediaLocalReady(
        'external-emission-att',
        messageId: 'external-emission',
        expectedLocalPath: 'media/contact-1/external-emission-att.jpg',
        nowMs: 1200,
      ),
      isFalse,
    );
    await Future<void>.delayed(Duration.zero);
    expect(emitted, ['expired']);
  });
}
