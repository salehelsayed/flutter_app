import 'package:flutter_app/core/database/helpers/group_invite_delivery_attempts_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/067_group_invite_delivery_attempts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runGroupInviteDeliveryAttemptsMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('upserts and loads invite delivery attempts by group/member', () async {
    await dbUpsertGroupInviteDeliveryAttempt(db, {
      'group_id': 'group-1',
      'peer_id': 'peer-a',
      'username': 'Alice',
      'status': 'sent',
      'attempted_at': '2026-05-07T12:00:00.000Z',
      'updated_at': '2026-05-07T12:00:00.000Z',
    });

    final row = await dbLoadGroupInviteDeliveryAttempt(
      db,
      groupId: 'group-1',
      peerId: 'peer-a',
    );

    expect(row, isNotNull);
    expect(row!['status'], 'sent');
    expect(row['username'], 'Alice');
  });

  test('loads all attempts for a group in stable member order', () async {
    await dbUpsertGroupInviteDeliveryAttempt(db, {
      'group_id': 'group-1',
      'peer_id': 'peer-b',
      'username': 'Bob',
      'status': 'queued',
      'attempted_at': '2026-05-07T12:00:00.000Z',
      'updated_at': '2026-05-07T12:00:00.000Z',
    });
    await dbUpsertGroupInviteDeliveryAttempt(db, {
      'group_id': 'group-1',
      'peer_id': 'peer-a',
      'username': 'Alice',
      'status': 'needs_resend',
      'attempted_at': '2026-05-07T12:01:00.000Z',
      'updated_at': '2026-05-07T12:01:00.000Z',
    });

    final rows = await dbLoadGroupInviteDeliveryAttemptsForGroup(db, 'group-1');

    expect(rows.map((row) => row['peer_id']), ['peer-a', 'peer-b']);
  });

  test('updates status without losing original attempt timestamp', () async {
    await dbUpsertGroupInviteDeliveryAttempt(db, {
      'group_id': 'group-1',
      'peer_id': 'peer-a',
      'username': 'Alice',
      'status': 'needs_resend',
      'attempted_at': '2026-05-07T12:00:00.000Z',
      'updated_at': '2026-05-07T12:00:00.000Z',
      'last_error': 'send_failed',
    });

    await dbUpdateGroupInviteDeliveryAttemptStatus(
      db,
      groupId: 'group-1',
      peerId: 'peer-a',
      status: 'joined',
      updatedAt: '2026-05-07T12:05:00.000Z',
    );

    final row = await dbLoadGroupInviteDeliveryAttempt(
      db,
      groupId: 'group-1',
      peerId: 'peer-a',
    );

    expect(row!['status'], 'joined');
    expect(row['attempted_at'], '2026-05-07T12:00:00.000Z');
    expect(row['updated_at'], '2026-05-07T12:05:00.000Z');
    expect(row['last_error'], isNull);
  });

  test('deletes rows by group/member and by group', () async {
    await dbUpsertGroupInviteDeliveryAttempt(db, {
      'group_id': 'group-1',
      'peer_id': 'peer-a',
      'username': 'Alice',
      'status': 'sent',
      'attempted_at': '2026-05-07T12:00:00.000Z',
      'updated_at': '2026-05-07T12:00:00.000Z',
    });
    await dbUpsertGroupInviteDeliveryAttempt(db, {
      'group_id': 'group-1',
      'peer_id': 'peer-b',
      'username': 'Bob',
      'status': 'sent',
      'attempted_at': '2026-05-07T12:00:00.000Z',
      'updated_at': '2026-05-07T12:00:00.000Z',
    });

    expect(
      await dbDeleteGroupInviteDeliveryAttempt(
        db,
        groupId: 'group-1',
        peerId: 'peer-a',
      ),
      1,
    );
    expect(
      await dbLoadGroupInviteDeliveryAttemptsForGroup(db, 'group-1'),
      hasLength(1),
    );
    expect(await dbDeleteGroupInviteDeliveryAttemptsForGroup(db, 'group-1'), 1);
    expect(
      await dbLoadGroupInviteDeliveryAttemptsForGroup(db, 'group-1'),
      isEmpty,
    );
  });
}
