import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/helpers/pending_group_invites_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/051_pending_group_invites.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_group_invite_repository_impl.dart';

void main() {
  late Database db;
  late PendingGroupInviteRepositoryImpl repo;

  PendingGroupInvite makeInvite({
    String groupId = 'group-1',
    String groupName = 'Book Club',
    DateTime? receivedAt,
  }) {
    final effectiveReceivedAt = (receivedAt ?? DateTime.now().toUtc()).toUtc();
    final createdAt = effectiveReceivedAt.subtract(const Duration(hours: 6));
    final inviteTimestamp = createdAt.add(const Duration(minutes: 5));
    final payload = GroupInvitePayload(
      id: 'invite-$groupId',
      groupId: groupId,
      groupKey: 'base64-key',
      keyEpoch: 1,
      groupConfig: {
        'name': groupName,
        'groupType': 'chat',
        'createdBy': 'peer-admin',
        'createdAt': createdAt.toIso8601String(),
        'members': const [],
      },
      senderPeerId: 'peer-admin',
      senderUsername: 'Admin',
      timestamp: inviteTimestamp.toIso8601String(),
    );
    return PendingGroupInvite.fromPayload(
      payload,
      receivedAt: effectiveReceivedAt,
    );
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runPendingGroupInvitesMigration(db);
    repo = PendingGroupInviteRepositoryImpl(
      dbUpsertPendingGroupInvite: (row) => dbUpsertPendingGroupInvite(db, row),
      dbLoadPendingGroupInvites: () => dbLoadPendingGroupInvites(db),
      dbLoadPendingGroupInvite: (groupId) =>
          dbLoadPendingGroupInvite(db, groupId),
      dbDeletePendingGroupInvite: (groupId) =>
          dbDeletePendingGroupInvite(db, groupId),
      dbDeleteExpiredPendingGroupInvites: (cutoff) =>
          dbDeleteExpiredPendingGroupInvites(db, cutoff),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('PendingGroupInviteRepositoryImpl', () {
    test('savePendingInvite and getPendingInvite round-trip', () async {
      final invite = makeInvite();
      await repo.savePendingInvite(invite);

      final stored = await repo.getPendingInvite('group-1');
      expect(stored, isNotNull);
      expect(stored!.groupName, 'Book Club');
    });

    test('getPendingInvites orders newest first', () async {
      await repo.savePendingInvite(
        makeInvite(
          groupId: 'group-1',
          receivedAt: DateTime.utc(2026, 4, 5, 13, 0),
        ),
      );
      await repo.savePendingInvite(
        makeInvite(
          groupId: 'group-2',
          receivedAt: DateTime.utc(2026, 4, 5, 14, 0),
        ),
      );

      final invites = await repo.getPendingInvites();
      expect(invites.map((invite) => invite.groupId).toList(), [
        'group-2',
        'group-1',
      ]);
    });

    test('deleteExpiredPendingInvites removes expired rows only', () async {
      await repo.savePendingInvite(
        makeInvite(
          groupId: 'group-expired',
          receivedAt: DateTime.utc(2026, 4, 1, 13, 0),
        ),
      );
      await repo.savePendingInvite(
        makeInvite(
          groupId: 'group-fresh',
          receivedAt: DateTime.utc(2026, 4, 5, 13, 0),
        ),
      );

      final deleted = await repo.deleteExpiredPendingInvites(
        DateTime.utc(2026, 4, 12, 12, 59),
      );

      expect(deleted, 1);
      expect(await repo.getPendingInvite('group-expired'), isNull);
      expect(await repo.getPendingInvite('group-fresh'), isNotNull);
    });
  });
}
