import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/media/upload_media_outcome.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';

void main() {
  sqfliteFfiInit();

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE group_messages ('
      'id TEXT PRIMARY KEY, status TEXT NOT NULL, is_incoming INTEGER NOT NULL, '
      'wire_envelope TEXT, inbox_retry_payload TEXT, '
      'inbox_stored INTEGER NOT NULL DEFAULT 0, '
      'retry_attempt_count INTEGER NOT NULL DEFAULT 0, next_eligible_at INTEGER)',
    );
    await db.execute(
      'CREATE TABLE media_attachments ('
      'id TEXT PRIMARY KEY, message_id TEXT NOT NULL, owner_lane TEXT NOT NULL, '
      'local_path TEXT, download_status TEXT NOT NULL, '
      'upload_retry_count INTEGER NOT NULL DEFAULT 0)',
    );
  });

  tearDown(() => db.close());

  Future<void> seed({
    String parentStatus = 'sending',
    int retryCount = 0,
    String owner = 'group',
    bool incoming = false,
    String downloadStatus = 'upload_pending',
    String localPath = 'pending_uploads/g1/a1.jpg',
    String? wireEnvelope,
    String? inboxRetryPayload,
    int inboxStored = 0,
    int retryAttemptCount = 0,
    int? nextEligibleAt,
  }) async {
    await db.insert('group_messages', {
      'id': 'g1',
      'status': parentStatus,
      'is_incoming': incoming ? 1 : 0,
      'wire_envelope': wireEnvelope,
      'inbox_retry_payload': inboxRetryPayload,
      'inbox_stored': inboxStored,
      'retry_attempt_count': retryAttemptCount,
      'next_eligible_at': nextEligibleAt,
    });
    await db.insert('media_attachments', {
      'id': 'a1',
      'message_id': 'g1',
      'owner_lane': owner,
      'local_path': localPath,
      'download_status': downloadStatus,
      'upload_retry_count': retryCount,
    });
  }

  Future<Map<String, Object?>> attachment() async =>
      (await db.query('media_attachments')).single;

  test(
    'retryable group projection uses existing queued_offline lane',
    () async {
      await seed(parentStatus: 'failed');

      final result = await dbProjectGroupUploadFailure(
        db,
        messageId: 'g1',
        attachmentId: 'a1',
        disposition: UploadMediaDisposition.boundedRetryable,
      );

      expect(result.state, UploadRetryProjectionState.retryPending);
      expect((await attachment())['upload_retry_count'], 1);
      expect(
        (await db.query('group_messages')).single['status'],
        'queued_offline',
      );
    },
  );

  test(
    'queued_offline is an allowed parent and connectivity costs zero',
    () async {
      await seed(parentStatus: 'queued_offline', retryCount: 2);

      await dbProjectGroupUploadFailure(
        db,
        messageId: 'g1',
        attachmentId: 'a1',
        disposition: UploadMediaDisposition.connectivityRetryable,
      );

      expect((await attachment())['download_status'], 'upload_pending');
      expect((await attachment())['upload_retry_count'], 2);
      expect(
        (await db.query('group_messages')).single['status'],
        'queued_offline',
      );
    },
  );

  test(
    'terminal failure preserves count and ignores direct-owned collision',
    () async {
      await seed(parentStatus: 'failed', retryCount: 1, owner: 'direct');

      final result = await dbProjectGroupUploadFailure(
        db,
        messageId: 'g1',
        attachmentId: 'a1',
        disposition: UploadMediaDisposition.terminal,
      );

      expect(result.applied, isFalse);
      expect((await attachment())['download_status'], 'upload_pending');
      expect((await attachment())['upload_retry_count'], 1);
      expect((await db.query('group_messages')).single['status'], 'failed');
    },
  );

  test('incoming parent is a no-op before attachment mutation', () async {
    await seed(incoming: true);

    final result = await dbProjectGroupUploadFailure(
      db,
      messageId: 'g1',
      attachmentId: 'a1',
      disposition: UploadMediaDisposition.boundedRetryable,
    );

    expect(result.applied, isFalse);
    expect((await attachment())['upload_retry_count'], 0);
  });

  test('parent trigger abort rolls back group attachment mutation', () async {
    await seed(parentStatus: 'queued_offline');
    await db.execute(
      "CREATE TRIGGER abort_group_projection BEFORE UPDATE OF status ON group_messages "
      "WHEN NEW.id = 'g1' BEGIN SELECT RAISE(ABORT, 'parent abort'); END",
    );

    await expectLater(
      dbProjectGroupUploadFailure(
        db,
        messageId: 'g1',
        attachmentId: 'a1',
        disposition: UploadMediaDisposition.boundedRetryable,
      ),
      throwsA(anything),
    );
    expect((await attachment())['download_status'], 'upload_pending');
    expect((await attachment())['upload_retry_count'], 0);
    expect(
      (await db.query('group_messages')).single['status'],
      'queued_offline',
    );
  });

  group('manual retry rearm', () {
    test('atomically resets terminal rows and group retry metadata', () async {
      await seed(
        parentStatus: 'failed',
        retryCount: kMaxUploadRetries,
        downloadStatus: 'upload_failed',
        wireEnvelope: 'stale-envelope',
        inboxRetryPayload: 'stale-payload',
        inboxStored: 1,
        retryAttemptCount: 7,
        nextEligibleAt: 999,
      );
      await db.insert('media_attachments', {
        'id': 'a2',
        'message_id': 'g1',
        'owner_lane': 'group',
        'local_path': 'pending_uploads/g1/a2.jpg',
        'download_status': 'upload_pending',
        'upload_retry_count': 2,
      });

      final applied = await dbRearmGroupUploadRetryForManualRetry(
        db,
        messageId: 'g1',
        attachments: const [
          ManualUploadRetryAttachmentExpectation(
            attachmentId: 'a1',
            storedLocalPath: 'pending_uploads/g1/a1.jpg',
            downloadStatus: 'upload_failed',
            uploadRetryCount: kMaxUploadRetries,
          ),
          ManualUploadRetryAttachmentExpectation(
            attachmentId: 'a2',
            storedLocalPath: 'pending_uploads/g1/a2.jpg',
            downloadStatus: 'upload_pending',
            uploadRetryCount: 2,
          ),
        ],
      );

      expect(applied, isTrue);
      final parent = (await db.query('group_messages')).single;
      expect(parent['status'], 'queued_offline');
      expect(parent['wire_envelope'], isNull);
      expect(parent['inbox_retry_payload'], isNull);
      expect(parent['inbox_stored'], 0);
      expect(parent['retry_attempt_count'], 0);
      expect(parent['next_eligible_at'], isNull);
      final rows = await db.query('media_attachments', orderBy: 'id ASC');
      expect(rows[0]['download_status'], 'upload_pending');
      expect(rows[0]['upload_retry_count'], 0);
      expect(rows[1]['download_status'], 'upload_pending');
      expect(rows[1]['upload_retry_count'], 2);
    });

    test(
      'typed terminal row below the ceiling is byte-for-byte refused',
      () async {
        await seed(
          parentStatus: 'failed',
          retryCount: 1,
          downloadStatus: 'upload_failed',
          wireEnvelope: 'stale-envelope',
          inboxRetryPayload: 'stale-payload',
          inboxStored: 1,
          retryAttemptCount: 4,
          nextEligibleAt: 555,
        );
        final parentBefore = (await db.query('group_messages')).single;
        final attachmentBefore = await attachment();

        final applied = await dbRearmGroupUploadRetryForManualRetry(
          db,
          messageId: 'g1',
          attachments: const [
            ManualUploadRetryAttachmentExpectation(
              attachmentId: 'a1',
              storedLocalPath: 'pending_uploads/g1/a1.jpg',
              downloadStatus: 'upload_failed',
              uploadRetryCount: 1,
            ),
          ],
        );

        expect(applied, isFalse);
        expect((await db.query('group_messages')).single, parentBefore);
        expect(await attachment(), attachmentBefore);
      },
    );

    test('attachment abort rolls all group parent fields back', () async {
      await seed(
        parentStatus: 'failed',
        retryCount: kMaxUploadRetries,
        downloadStatus: 'upload_failed',
        wireEnvelope: 'stale-envelope',
        inboxRetryPayload: 'stale-payload',
        inboxStored: 1,
        retryAttemptCount: 4,
        nextEligibleAt: 555,
      );
      await db.execute(
        "CREATE TRIGGER abort_group_rearm BEFORE UPDATE OF download_status "
        "ON media_attachments WHEN NEW.id = 'a1' "
        "BEGIN SELECT RAISE(ABORT, 'attachment abort'); END",
      );

      await expectLater(
        dbRearmGroupUploadRetryForManualRetry(
          db,
          messageId: 'g1',
          attachments: const [
            ManualUploadRetryAttachmentExpectation(
              attachmentId: 'a1',
              storedLocalPath: 'pending_uploads/g1/a1.jpg',
              downloadStatus: 'upload_failed',
              uploadRetryCount: kMaxUploadRetries,
            ),
          ],
        ),
        throwsA(anything),
      );

      final parent = (await db.query('group_messages')).single;
      expect(parent['status'], 'failed');
      expect(parent['wire_envelope'], 'stale-envelope');
      expect(parent['inbox_retry_payload'], 'stale-payload');
      expect(parent['inbox_stored'], 1);
      expect(parent['retry_attempt_count'], 4);
      expect(parent['next_eligible_at'], 555);
      expect((await attachment())['download_status'], 'upload_failed');
      expect((await attachment())['upload_retry_count'], kMaxUploadRetries);
    });
  });
}
