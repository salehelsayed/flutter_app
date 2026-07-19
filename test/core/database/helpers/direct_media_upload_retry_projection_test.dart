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
      'CREATE TABLE messages ('
      'id TEXT PRIMARY KEY, status TEXT NOT NULL, is_incoming INTEGER NOT NULL, '
      'wire_envelope TEXT)',
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
    String parentStatus = 'failed',
    int retryCount = 0,
    String owner = 'direct',
    bool incoming = false,
    String downloadStatus = 'upload_pending',
    String localPath = 'pending_uploads/m1/a1.jpg',
    String? wireEnvelope,
  }) async {
    await db.insert('messages', {
      'id': 'm1',
      'status': parentStatus,
      'is_incoming': incoming ? 1 : 0,
      'wire_envelope': wireEnvelope,
    });
    await db.insert('media_attachments', {
      'id': 'a1',
      'message_id': 'm1',
      'owner_lane': owner,
      'local_path': localPath,
      'download_status': downloadStatus,
      'upload_retry_count': retryCount,
    });
  }

  Future<Map<String, Object?>> attachment() async => (await db.query(
    'media_attachments',
    where: 'id = ?',
    whereArgs: ['a1'],
  )).single;

  test(
    'connectivity retry normalizes legacy parent without burning budget',
    () async {
      await seed(retryCount: 2);

      final result = await dbProjectDirectUploadFailure(
        db,
        messageId: 'm1',
        attachmentId: 'a1',
        disposition: UploadMediaDisposition.connectivityRetryable,
      );

      expect(result.state, UploadRetryProjectionState.retryPending);
      expect((await attachment())['download_status'], 'upload_pending');
      expect((await attachment())['upload_retry_count'], 2);
      expect((await db.query('messages')).single['status'], 'sending');
    },
  );

  test(
    'third bounded failure atomically terminalizes child and parent',
    () async {
      await seed(parentStatus: 'sending', retryCount: 2);

      final result = await dbProjectDirectUploadFailure(
        db,
        messageId: 'm1',
        attachmentId: 'a1',
        disposition: UploadMediaDisposition.boundedRetryable,
      );

      expect(result.isTerminal, isTrue);
      expect((await attachment())['download_status'], 'upload_failed');
      expect((await attachment())['upload_retry_count'], 3);
      expect((await db.query('messages')).single['status'], 'failed');
    },
  );

  test(
    'legacy pending count above the ceiling is clamped at terminal',
    () async {
      await seed(parentStatus: 'sending', retryCount: 9);

      final result = await dbProjectDirectUploadFailure(
        db,
        messageId: 'm1',
        attachmentId: 'a1',
        disposition: UploadMediaDisposition.boundedRetryable,
      );

      expect(result.isTerminal, isTrue);
      expect((await attachment())['download_status'], 'upload_failed');
      expect((await attachment())['upload_retry_count'], kMaxUploadRetries);
      expect((await db.query('messages')).single['status'], 'failed');
    },
  );

  test('typed terminal failure does not forge a ceiling count', () async {
    await seed(retryCount: 1);

    await dbProjectDirectUploadFailure(
      db,
      messageId: 'm1',
      attachmentId: 'a1',
      disposition: UploadMediaDisposition.terminal,
    );

    expect((await attachment())['download_status'], 'upload_failed');
    expect((await attachment())['upload_retry_count'], 1);
  });

  test(
    'opposite owner and settled parent are no-ops before attachment mutation',
    () async {
      await seed(parentStatus: 'delivered', owner: 'group');

      final result = await dbProjectDirectUploadFailure(
        db,
        messageId: 'm1',
        attachmentId: 'a1',
        disposition: UploadMediaDisposition.terminal,
      );

      expect(result.applied, isFalse);
      expect((await attachment())['download_status'], 'upload_pending');
      expect((await db.query('messages')).single['status'], 'delivered');
    },
  );

  test('parent update abort rolls attachment update back', () async {
    await seed(retryCount: 0);
    await db.execute(
      "CREATE TRIGGER abort_direct_projection BEFORE UPDATE OF status ON messages "
      "WHEN NEW.id = 'm1' BEGIN SELECT RAISE(ABORT, 'parent abort'); END",
    );

    await expectLater(
      dbProjectDirectUploadFailure(
        db,
        messageId: 'm1',
        attachmentId: 'a1',
        disposition: UploadMediaDisposition.boundedRetryable,
      ),
      throwsA(anything),
    );
    expect((await attachment())['download_status'], 'upload_pending');
    expect((await attachment())['upload_retry_count'], 0);
    expect((await db.query('messages')).single['status'], 'failed');
  });

  group('manual retry rearm', () {
    test(
      'atomically normalizes parent and rearms the complete unfinished set',
      () async {
        await seed(
          parentStatus: 'failed',
          retryCount: kMaxUploadRetries,
          downloadStatus: 'upload_failed',
          wireEnvelope: 'stale-envelope',
        );
        await db.insert('media_attachments', {
          'id': 'a2',
          'message_id': 'm1',
          'owner_lane': 'direct',
          'local_path': 'pending_uploads/m1/a2.jpg',
          'download_status': 'upload_pending',
          'upload_retry_count': 1,
        });

        final applied = await dbRearmDirectUploadRetryForManualRetry(
          db,
          messageId: 'm1',
          attachments: const [
            ManualUploadRetryAttachmentExpectation(
              attachmentId: 'a1',
              storedLocalPath: 'pending_uploads/m1/a1.jpg',
              downloadStatus: 'upload_failed',
              uploadRetryCount: kMaxUploadRetries,
            ),
            ManualUploadRetryAttachmentExpectation(
              attachmentId: 'a2',
              storedLocalPath: 'pending_uploads/m1/a2.jpg',
              downloadStatus: 'upload_pending',
              uploadRetryCount: 1,
            ),
          ],
        );

        expect(applied, isTrue);
        final parent = (await db.query('messages')).single;
        expect(parent['status'], 'sending');
        expect(parent['wire_envelope'], isNull);
        final rows = await db.query('media_attachments', orderBy: 'id ASC');
        expect(rows[0]['download_status'], 'upload_pending');
        expect(rows[0]['upload_retry_count'], 0);
        expect(rows[1]['download_status'], 'upload_pending');
        expect(rows[1]['upload_retry_count'], 1);
      },
    );

    test(
      'below-ceiling terminal row is refused without any mutation',
      () async {
        await seed(
          parentStatus: 'failed',
          retryCount: kMaxUploadRetries - 1,
          downloadStatus: 'upload_failed',
          wireEnvelope: 'stale-envelope',
        );
        final parentBefore = (await db.query('messages')).single;
        final attachmentBefore = await attachment();

        final applied = await dbRearmDirectUploadRetryForManualRetry(
          db,
          messageId: 'm1',
          attachments: const [
            ManualUploadRetryAttachmentExpectation(
              attachmentId: 'a1',
              storedLocalPath: 'pending_uploads/m1/a1.jpg',
              downloadStatus: 'upload_failed',
              uploadRetryCount: kMaxUploadRetries - 1,
            ),
          ],
        );

        expect(applied, isFalse);
        expect((await db.query('messages')).single, parentBefore);
        expect(await attachment(), attachmentBefore);
      },
    );

    test('omitting one unfinished sibling refuses the whole rearm', () async {
      await seed(
        parentStatus: 'failed',
        retryCount: kMaxUploadRetries,
        downloadStatus: 'upload_failed',
      );
      await db.insert('media_attachments', {
        'id': 'a2',
        'message_id': 'm1',
        'owner_lane': 'direct',
        'local_path': 'pending_uploads/m1/a2.jpg',
        'download_status': 'upload_pending',
        'upload_retry_count': 0,
      });
      final before = await db.query('media_attachments', orderBy: 'id ASC');

      final applied = await dbRearmDirectUploadRetryForManualRetry(
        db,
        messageId: 'm1',
        attachments: const [
          ManualUploadRetryAttachmentExpectation(
            attachmentId: 'a1',
            storedLocalPath: 'pending_uploads/m1/a1.jpg',
            downloadStatus: 'upload_failed',
            uploadRetryCount: kMaxUploadRetries,
          ),
        ],
      );

      expect(applied, isFalse);
      expect(await db.query('media_attachments', orderBy: 'id ASC'), before);
      expect((await db.query('messages')).single['status'], 'failed');
    });

    test('attachment abort rolls the earlier parent rearm back', () async {
      await seed(
        parentStatus: 'failed',
        retryCount: kMaxUploadRetries,
        downloadStatus: 'upload_failed',
        wireEnvelope: 'stale-envelope',
      );
      await db.execute(
        "CREATE TRIGGER abort_direct_rearm BEFORE UPDATE OF download_status "
        "ON media_attachments WHEN NEW.id = 'a1' "
        "BEGIN SELECT RAISE(ABORT, 'attachment abort'); END",
      );

      await expectLater(
        dbRearmDirectUploadRetryForManualRetry(
          db,
          messageId: 'm1',
          attachments: const [
            ManualUploadRetryAttachmentExpectation(
              attachmentId: 'a1',
              storedLocalPath: 'pending_uploads/m1/a1.jpg',
              downloadStatus: 'upload_failed',
              uploadRetryCount: kMaxUploadRetries,
            ),
          ],
        ),
        throwsA(anything),
      );
      final parent = (await db.query('messages')).single;
      expect(parent['status'], 'failed');
      expect(parent['wire_envelope'], 'stale-envelope');
      expect((await attachment())['download_status'], 'upload_failed');
      expect((await attachment())['upload_retry_count'], kMaxUploadRetries);
    });
  });
}
