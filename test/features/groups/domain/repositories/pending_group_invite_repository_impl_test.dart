import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/helpers/group_invite_consumptions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_invite_revocations_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_group_invites_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/055_group_invite_revocations.dart';
import 'package:flutter_app/core/database/migrations/056_group_invite_consumptions.dart';
import 'package:flutter_app/core/database/migrations/051_pending_group_invites.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_consumption.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_revocation.dart';
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
    await runGroupInviteRevocationsMigration(db);
    await runGroupInviteConsumptionsMigration(db);
    repo = PendingGroupInviteRepositoryImpl(
      dbUpsertPendingGroupInvite: (row) => dbUpsertPendingGroupInvite(db, row),
      dbLoadPendingGroupInvites: () => dbLoadPendingGroupInvites(db),
      dbLoadPendingGroupInvite: (groupId) =>
          dbLoadPendingGroupInvite(db, groupId),
      dbUpsertGroupInviteRevocation: (row) =>
          dbUpsertGroupInviteRevocation(db, row),
      dbLoadGroupInviteRevocation: (inviteId) =>
          dbLoadGroupInviteRevocation(db, inviteId),
      dbUpsertGroupInviteConsumption: (row) =>
          dbUpsertGroupInviteConsumption(db, row),
      dbLoadGroupInviteConsumption: (inviteId) =>
          dbLoadGroupInviteConsumption(db, inviteId),
      dbDeletePendingGroupInvite: (groupId) =>
          dbDeletePendingGroupInvite(db, groupId),
      dbDeleteExpiredPendingGroupInvites: (cutoff) =>
          dbDeleteExpiredPendingGroupInvites(db, cutoff),
      dbDeleteExpiredGroupInviteRevocations: (cutoff) =>
          dbDeleteExpiredGroupInviteRevocations(db, cutoff),
      dbDeleteExpiredGroupInviteConsumptions: (cutoff) =>
          dbDeleteExpiredGroupInviteConsumptions(db, cutoff),
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

    test('saveRevokedInvite and getRevokedInvite round-trip', () async {
      final revokedAt = DateTime.utc(2026, 4, 29, 12);
      await repo.saveRevokedInvite(
        GroupInviteRevocation(
          inviteId: 'invite-1',
          groupId: 'group-1',
          revokedAt: revokedAt,
          expiresAt: revokedAt.add(const Duration(days: 7)),
          revokedBy: 'peer-admin',
        ),
      );

      final stored = await repo.getRevokedInvite('invite-1');
      expect(stored, isNotNull);
      expect(stored!.groupId, 'group-1');
      expect(stored.revokedBy, 'peer-admin');
      expect(stored.isActiveAt(DateTime.utc(2026, 5, 1)), isTrue);
    });

    test(
      'deleteExpiredRevokedInvites removes expired revocations only',
      () async {
        await repo.saveRevokedInvite(
          GroupInviteRevocation(
            inviteId: 'expired-invite',
            groupId: 'group-expired',
            revokedAt: DateTime.utc(2026, 4, 1),
            expiresAt: DateTime.utc(2026, 4, 8),
          ),
        );
        await repo.saveRevokedInvite(
          GroupInviteRevocation(
            inviteId: 'fresh-invite',
            groupId: 'group-fresh',
            revokedAt: DateTime.utc(2026, 4, 5),
            expiresAt: DateTime.utc(2026, 4, 12),
          ),
        );

        final deleted = await repo.deleteExpiredRevokedInvites(
          DateTime.utc(2026, 4, 10),
        );

        expect(deleted, 1);
        expect(await repo.getRevokedInvite('expired-invite'), isNull);
        expect(await repo.getRevokedInvite('fresh-invite'), isNotNull);
      },
    );

    test('saveConsumedInvite and getConsumedInvite round-trip', () async {
      final consumedAt = DateTime.utc(2026, 4, 29, 12);
      await repo.saveConsumedInvite(
        GroupInviteConsumption(
          inviteId: 'invite-1',
          groupId: 'group-1',
          consumedAt: consumedAt,
          expiresAt: consumedAt.add(const Duration(days: 7)),
        ),
      );

      final stored = await repo.getConsumedInvite('invite-1');
      expect(stored, isNotNull);
      expect(stored!.groupId, 'group-1');
      expect(stored.isActiveAt(DateTime.utc(2026, 5, 1)), isTrue);
    });

    test(
      'deleteExpiredConsumedInvites removes expired consumptions only',
      () async {
        await repo.saveConsumedInvite(
          GroupInviteConsumption(
            inviteId: 'expired-invite',
            groupId: 'group-expired',
            consumedAt: DateTime.utc(2026, 4, 1),
            expiresAt: DateTime.utc(2026, 4, 8),
          ),
        );
        await repo.saveConsumedInvite(
          GroupInviteConsumption(
            inviteId: 'fresh-invite',
            groupId: 'group-fresh',
            consumedAt: DateTime.utc(2026, 4, 5),
            expiresAt: DateTime.utc(2026, 4, 12),
          ),
        );

        final deleted = await repo.deleteExpiredConsumedInvites(
          DateTime.utc(2026, 4, 10),
        );

        expect(deleted, 1);
        expect(await repo.getConsumedInvite('expired-invite'), isNull);
        expect(await repo.getConsumedInvite('fresh-invite'), isNotNull);
      },
    );
  });
}
