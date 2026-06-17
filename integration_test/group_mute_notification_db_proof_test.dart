/// Real-SQLCipher device proof for 04-P0 / SI-1 (G-NM-1 Tier B).
///
/// The background group-message mute suppression depends on `dbLoadGroup`
/// projecting the `is_muted` column out of the REAL encrypted engine and into
/// the `groupMemberMessageDisplayEligibility` helper — the resolver's
/// `_resolveGroupMessageNotificationDisplayEligibilityFromEncryptedDb` hop
/// (dbLoadGroup :313 -> dbLoadGroupMember :315 -> helper :320).
///
/// Host unit tests can only hand-build the `groups` row map: sqflite_ffi / plain
/// SQLite cannot run sqflite_sqlcipher, and the host VM cannot open the encrypted
/// identity.db. The helper -> suppress DECISION is locked host-side
/// (background_message_handler_test.dart, incl. the Tier A end-to-end fallback
/// test). This proof closes the remaining gap: that the encrypted-engine SQL hop
/// feeding the helper behaves correctly — a muted group, read through the same
/// dbLoadGroup/dbLoadGroupMember the resolver uses, suppresses with reason
/// 'muted'; an un-muted group allows.
@Tags(['device'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:flutter_app/core/database/helpers/group_members_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/017_groups_tables.dart';
import 'package:flutter_app/features/push/application/background_message_handler.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('real-SQLCipher background group-mute display eligibility (04-P0 SI-1)', () {
    late Database db;
    late String path;
    const groupId = 'group-mute-proof';
    const localPeerId = 'peer-local-proof';

    Map<String, Object?> groupRow({required int isMuted}) => {
          'id': groupId,
          'name': 'Mute Proof Group',
          'type': 'chat',
          'topic_name': '/mknoon/group/$groupId',
          'created_at': '2026-06-17T00:00:00.000Z',
          'created_by': 'peer-admin',
          'my_role': 'member',
          'is_muted': isMuted,
        };

    Map<String, Object?> memberRow() => {
          'group_id': groupId,
          'peer_id': localPeerId,
          'username': 'Local User',
          'role': 'writer',
          'joined_at': '2026-06-17T00:00:00.000Z',
        };

    setUp(() async {
      final dir = await getDatabasesPath();
      // Unique-per-run name so a crashed prior run cannot collide.
      path = '$dir/group_mute_notification_proof_'
          '${DateTime.now().microsecondsSinceEpoch}.db';
      await databaseFactory.deleteDatabase(path);
      // Real SQLCipher: a non-empty password forces the encrypted engine.
      db = await openDatabase(path, password: 'proof-key');
      await runGroupsTablesMigration(db);
    });

    tearDown(() async {
      await db.close();
      await databaseFactory.deleteDatabase(path);
    });

    testWidgets(
      'muted group + present member -> dbLoadGroup surfaces is_muted -> '
      'helper suppresses with reason "muted"',
      (tester) async {
        await dbInsertGroup(db, groupRow(isMuted: 1));
        await dbInsertGroupMember(db, memberRow());

        // The exact reads the resolver performs at :313 / :315, then the :320
        // helper call, on the real encrypted engine.
        final loadedGroup = await dbLoadGroup(db, groupId);
        final loadedMember = await dbLoadGroupMember(db, groupId, localPeerId);
        expect(loadedGroup, isNotNull);
        expect(
          loadedMember,
          isNotNull,
          reason: 'a present member is required to reach the mute branch',
        );
        expect(
          loadedGroup!['is_muted'],
          1,
          reason: 'dbLoadGroup must project is_muted out of SQLCipher',
        );

        final eligibility = groupMemberMessageDisplayEligibility(loadedGroup);
        expect(eligibility.shouldDisplay, isFalse);
        expect(eligibility.reason, 'muted');
      },
    );

    testWidgets(
      'un-muted group + present member -> helper allows the current member',
      (tester) async {
        await dbInsertGroup(db, groupRow(isMuted: 0));
        await dbInsertGroupMember(db, memberRow());

        final loadedGroup = await dbLoadGroup(db, groupId);
        expect(loadedGroup, isNotNull);
        expect(loadedGroup!['is_muted'], 0);

        final eligibility = groupMemberMessageDisplayEligibility(loadedGroup);
        expect(eligibility.shouldDisplay, isTrue);
      },
    );
  });
}
