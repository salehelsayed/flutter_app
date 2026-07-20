import 'dart:io';

import 'package:flutter_app/core/database/helpers/group_media_deletion_journal_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_message_local_deletions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_storage_manager.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/groups/application/group_media_deletion_journal_reconciler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

/// Key store whose delete can be forced to fail per key.
class _FailableSecureKeyStore extends FakeSecureKeyStore {
  final Set<String> failDeletesFor = {};

  @override
  Future<void> delete(String key) async {
    if (failDeletesFor.contains(key)) {
      throw StateError('injected key-delete failure for $key');
    }
    await super.delete(key);
  }
}

/// Real-file gateway whose delete can be forced to fail per absolute path.
class _FailableFileGateway implements MediaStorageFileGateway {
  _FailableFileGateway();

  final Set<String> failDeletesFor = {};
  final List<String> deleted = [];

  @override
  Future<bool> exists(String absolutePath) => File(absolutePath).exists();

  @override
  Future<int?> lengthOrNull(String absolutePath) async {
    try {
      return await File(absolutePath).length();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> resolveRealPathOrNull(String absolutePath) async {
    try {
      return await File(absolutePath).resolveSymbolicLinks();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> delete(String absolutePath, {required String reason}) async {
    if (failDeletesFor.contains(absolutePath)) {
      throw StateError('injected file-delete failure for $absolutePath');
    }
    final file = File(absolutePath);
    if (await file.exists()) {
      await file.delete();
      deleted.add(absolutePath);
    }
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late Directory root;
  late _FailableSecureKeyStore keyStore;
  late _FailableFileGateway fileGateway;

  String absoluteOf(String relative) => p.join(root.path, relative);

  /// A fresh reconciler instance — constructing a new one per pass simulates
  /// a fresh process over the same durable DB + file tree.
  GroupMediaDeletionJournalReconciler freshReconciler() {
    return GroupMediaDeletionJournalReconciler(
      loadJournalPage:
          ({
            required int limit,
            String? afterCreatedAt,
            String? afterAttachmentId,
          }) => dbLoadGroupMediaDeletionJournalPage(
            db,
            limit: limit,
            afterCreatedAt: afterCreatedAt,
            afterAttachmentId: afterAttachmentId,
          ),
      loadAttachmentRow: (attachmentId) => dbLoadMediaById(db, attachmentId),
      loadLocalDeletionGroupId: (messageId) async {
        final row = await dbLoadGroupMessageLocalDeletion(db, messageId);
        return row?['group_id'] as String?;
      },
      parentExists:
          ({required String messageId, required String groupId}) async {
            final rows = await db.query(
              'group_messages',
              columns: ['id'],
              where: 'id = ? AND group_id = ?',
              whereArgs: [messageId, groupId],
              limit: 1,
            );
            return rows.isNotEmpty;
          },
      finalizeEntry:
          ({required String attachmentId, required String messageId}) =>
              dbFinalizeGroupMediaDeletionJournalEntry(
                db,
                attachmentId: attachmentId,
                messageId: messageId,
              ),
      resolveStoredPath: (relativePath) async => absoluteOf(relativePath),
      secureKeyStore: keyStore,
      fileGateway: fileGateway,
      lifecycleLock: MediaAttachmentLifecycleLock(),
    );
  }

  Future<void> seedParent(String messageId, {String groupId = 'group-1'}) {
    return db.insert('group_messages', {
      'id': messageId,
      'group_id': groupId,
      'sender_peer_id': 'peer-alice',
      'sender_username': 'Alice',
      'text': 'media',
      'timestamp': '2026-07-10T00:00:00.000Z',
      'key_generation': 0,
      'status': 'delivered',
      'is_incoming': 1,
      'created_at': '2026-07-10T00:00:00.000Z',
    }).then((_) {});
  }

  /// Seeds one done group attachment; optionally a real canonical file and a
  /// secure key.
  Future<String> seedAttachment({
    required String id,
    required String messageId,
    bool withFile = true,
    bool withKey = true,
    bool canonicalPath = true,
    String groupId = 'group-1',
  }) async {
    final relative = 'media/$groupId/$id.jpg';
    if (withFile) {
      final file = File(absoluteOf(relative));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(List<int>.filled(16, 3));
    }
    if (withKey) {
      await keyStore.write(
        mediaAttachmentEncryptionKeyStoreName(id),
        'key-material-$id',
      );
    }
    await db.insert('media_attachments', {
      'id': id,
      'message_id': messageId,
      'mime': 'image/jpeg',
      'size': 16,
      'media_type': 'image',
      'local_path': canonicalPath ? relative : '/noncanonical/$id.jpg',
      'download_status': 'done',
      'created_at': '2026-07-10T00:00:01.000Z',
      'owner_lane': 'group',
      'is_bookmarked': 0,
      'last_playback_position_ms': 0,
    });
    return relative;
  }

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await runProductionOnCreate(db, currentIdentityDatabaseVersion);
    root = Directory.systemTemp.createTempSync('gma08_media_root');
    keyStore = _FailableSecureKeyStore();
    fileGateway = _FailableFileGateway();
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test(
    'GMA-08 self contained journal saga converges per item across every restart boundary',
    () async {
      await seedParent('msg-m');
      final relA = await seedAttachment(id: 'att-a', messageId: 'msg-m');
      await seedAttachment(
        id: 'att-b',
        messageId: 'msg-m',
        canonicalPath: false,
        withFile: false,
      );
      final relC = await seedAttachment(id: 'att-c', messageId: 'msg-m');

      final prepared = await dbPrepareGroupMediaDeleteForMe(
        db,
        groupId: 'group-1',
        messageId: 'msg-m',
        operationId: 'op-1',
      );
      expect(prepared.outcome, GroupMediaDeletePrepareOutcome.prepared);
      expect(prepared.journaledAttachments, 3);
      // No file/key I/O happened during prepare.
      expect(File(absoluteOf(relA)).existsSync(), isTrue);
      expect(
        await keyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName('att-a'),
        ),
        isTrue,
      );

      // A wrong-group orphan WITHOUT a journal row: cleanup must never
      // touch it (orphan shape is not deletion authority).
      await seedAttachment(
        id: 'att-orphan',
        messageId: 'msg-unrelated',
        groupId: 'group-1',
      );

      // ---- Pass 1 with injected failures:
      //  - att-a: file delete throws (stage 1) -> journal retained.
      //  - att-b: null canonical path -> no file stage; key+finalize succeed.
      //  - att-c: key delete throws (stage 2) -> file already gone, journal
      //    retained.
      fileGateway.failDeletesFor.add(absoluteOf(relA));
      keyStore.failDeletesFor.add(mediaAttachmentEncryptionKeyStoreName('att-c'));
      final pass1 = await freshReconciler().runBounded();
      expect(pass1.completed, 1, reason: 'att-b completes despite siblings');
      expect(pass1.retained, 2);
      expect(pass1.quarantined, 0);

      var journal = await db.query(
        'group_media_deletion_journal',
        orderBy: 'attachment_id',
      );
      expect(journal.map((row) => row['attachment_id']), ['att-a', 'att-c']);
      expect(File(absoluteOf(relA)).existsSync(), isTrue);
      expect(
        File(absoluteOf(relC)).existsSync(),
        isFalse,
        reason: 'att-c file stage ran before its key stage failed',
      );
      expect(
        await keyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName('att-b'),
        ),
        isFalse,
      );
      expect(
        (await db.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: ['att-b'],
        )),
        isEmpty,
        reason: 'att-b finalize removed the row with the journal atomically',
      );

      // ---- Pass 2: fresh process, no failures -> full convergence.
      fileGateway.failDeletesFor.clear();
      keyStore.failDeletesFor.clear();
      final pass2 = await freshReconciler().runBounded();
      expect(pass2.completed, 2);
      expect(pass2.retained, 0);
      expect(await db.query('group_media_deletion_journal'), isEmpty);
      expect(File(absoluteOf(relA)).existsSync(), isFalse);
      expect(
        await keyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName('att-a'),
        ),
        isFalse,
      );
      expect(
        await keyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName('att-c'),
        ),
        isFalse,
        reason: 'a missing file on retry is success; the key stage completes',
      );
      expect(
        (await db.query(
          'media_attachments',
          where: "owner_lane = 'group' AND message_id = 'msg-m'",
        )),
        isEmpty,
      );

      // The unjournaled wrong-group orphan survived every pass.
      final orphanRelative = 'media/group-1/att-orphan.jpg';
      expect(File(absoluteOf(orphanRelative)).existsSync(), isTrue);
      expect(
        (await db.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: ['att-orphan'],
        )),
        hasLength(1),
      );
      expect(
        await keyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName('att-orphan'),
        ),
        isTrue,
      );

      // ---- Row-disappears-before-restart: the journal's own snapshotted
      // MIME/path identity drives cleanup when the attachment row is gone.
      await seedParent('msg-rowless');
      final relRowless = await seedAttachment(
        id: 'att-rowless',
        messageId: 'msg-rowless',
      );
      await dbPrepareGroupMediaDeleteForMe(
        db,
        groupId: 'group-1',
        messageId: 'msg-rowless',
        operationId: 'op-rowless',
      );
      // Crash-era bypass removes the row while file+key+journal survive.
      await db.delete(
        'media_attachments',
        where: 'id = ?',
        whereArgs: ['att-rowless'],
      );
      final rowlessPass = await freshReconciler().runBounded();
      expect(rowlessPass.completed, 1);
      expect(File(absoluteOf(relRowless)).existsSync(), isFalse);
      expect(
        await keyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName('att-rowless'),
        ),
        isFalse,
      );
      expect(await db.query('group_media_deletion_journal'), isEmpty);

      // ---- Quarantine: mismatches perform NO destructive work.
      // (a) journal row without its exact-group tombstone;
      await db.insert('group_media_deletion_journal', {
        'attachment_id': 'att-quarantine-tombstone',
        'operation_id': 'op-q1',
        'message_id': 'msg-no-tombstone',
        'group_id': 'group-1',
        'operation_intent': 'delete_for_me',
        'normalized_mime': 'image/jpeg',
        'canonical_relative_path': 'media/group-1/att-quarantine-tombstone.jpg',
        'created_at': '2026-07-10T00:00:09.000Z',
      });
      // (b) journal row whose surviving attachment row mismatches the exact
      // tuple (owner lane direct).
      await seedParent('msg-q2');
      await seedAttachment(id: 'att-q2', messageId: 'msg-q2');
      await dbPrepareGroupMediaDeleteForMe(
        db,
        groupId: 'group-1',
        messageId: 'msg-q2',
        operationId: 'op-q2',
      );
      await db.update(
        'media_attachments',
        {'owner_lane': 'direct'},
        where: 'id = ?',
        whereArgs: ['att-q2'],
      );
      final quarantinePass = await freshReconciler().runBounded();
      expect(quarantinePass.quarantined, 2);
      expect(quarantinePass.completed, 0);
      expect(
        File(absoluteOf('media/group-1/att-q2.jpg')).existsSync(),
        isTrue,
        reason: 'quarantine performs no destructive work',
      );
      expect(
        await keyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName('att-q2'),
        ),
        isTrue,
      );
      expect(
        await db.query('group_media_deletion_journal'),
        hasLength(2),
        reason: 'quarantined journal rows remain as evidence',
      );
    },
  );

  test('GMA-09D journal aware download commit cannot outlive cleanup', () async {
    await seedParent('msg-dl');
    final relative = await seedAttachment(
      id: 'att-dl',
      messageId: 'msg-dl',
      withFile: false,
    );
    // The download claims first (pending -> downloading is not claimable from
    // done; reset the row to pending first).
    await db.update(
      'media_attachments',
      {'download_status': 'pending', 'local_path': null},
      where: 'id = ?',
      whereArgs: ['att-dl'],
    );
    final claimed = await dbBeginMediaDownload(db, 'att-dl', ownerLane: 'group');
    expect(claimed, 1);

    // Delete-for-me commits while the transfer is in flight: the row (status
    // downloading) is journaled and the parent is gone.
    final prepared = await dbPrepareGroupMediaDeleteForMe(
      db,
      groupId: 'group-1',
      messageId: 'msg-dl',
      operationId: 'op-dl',
    );
    expect(prepared.outcome, GroupMediaDeletePrepareOutcome.prepared);
    expect(prepared.journaledAttachments, 1);

    // The late commit anti-joins the active journal: zero rows affected, no
    // restored path, no done promotion.
    final committed = await dbCommitMediaDownloadLocalPath(
      db,
      'att-dl',
      ownerLane: 'group',
      localPath: relative,
    );
    expect(committed, 0, reason: 'deletion won — the commit must lose');
    final row = (await db.query(
      'media_attachments',
      where: 'id = ?',
      whereArgs: ['att-dl'],
    )).single;
    expect(row['download_status'], 'downloading');
    expect(row['local_path'], isNull);

    // A DIRECT-lane commit is byte-identical pre-235 behavior (no anti-join):
    // same-shape direct row with a downloading claim still commits.
    await db.insert('media_attachments', {
      'id': 'att-direct-dl',
      'message_id': 'msg-direct-dl',
      'mime': 'image/jpeg',
      'size': 16,
      'media_type': 'image',
      'local_path': null,
      'download_status': 'downloading',
      'created_at': '2026-07-10T00:00:01.000Z',
      'owner_lane': 'direct',
      'is_bookmarked': 0,
      'last_playback_position_ms': 0,
    });
    expect(
      await dbCommitMediaDownloadLocalPath(
        db,
        'att-direct-dl',
        ownerLane: 'direct',
        localPath: 'media/contact-1/att-direct-dl.jpg',
      ),
      1,
    );

    // Cleanup converges: the journaled row is finalized away; the blocked
    // download can never resurrect it.
    final pass = await freshReconciler().runBounded();
    expect(pass.completed, 1);
    expect(
      (await db.query(
        'media_attachments',
        where: 'id = ?',
        whereArgs: ['att-dl'],
      )),
      isEmpty,
    );
    expect(await db.query('group_media_deletion_journal'), isEmpty);
    expect(
      await keyStore.containsKey(
        mediaAttachmentEncryptionKeyStoreName('att-dl'),
      ),
      isFalse,
    );
  });
}
