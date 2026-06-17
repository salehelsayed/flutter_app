/// Real-SQLCipher device proof for Finding 05 Phase 3 (bounded per-group rejoin
/// retry), migration 088 + the rejoin-state helpers, which host suites exercise
/// only against the in-memory fake.
@Tags(['device'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:flutter_app/core/database/helpers/group_rejoin_state_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/088_group_rejoin_state.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('real-SQLCipher group rejoin state proof (Finding 05 Phase 3)', () {
    late Database db;
    late String path;

    setUp(() async {
      final dir = await getDatabasesPath();
      path =
          '$dir/rejoin_state_proof_${DateTime.now().microsecondsSinceEpoch}.db';
      await databaseFactory.deleteDatabase(path);
      db = await openDatabase(path, password: 'proof-key');
      await runGroupRejoinStateMigration(db);
    });

    tearDown(() async {
      await db.close();
      await databaseFactory.deleteDatabase(path);
    });

    testWidgets('088 creates the table; helpers upsert / load / clear', (
      t,
    ) async {
      // Empty to start.
      expect(await dbLoadGroupRejoinStates(db), isEmpty);

      // First failure creates the row at attempt 1.
      await dbRecordGroupRejoinFailure(db, 'g1', nextEligibleAtMs: 1000);
      var rows = await dbLoadGroupRejoinStates(db);
      expect(rows, hasLength(1));
      expect(rows.single['group_id'], 'g1');
      expect(rows.single['rejoin_attempt_count'], 1);
      expect(rows.single['next_eligible_at'], 1000);

      // Second failure increments (ON CONFLICT upsert) + reschedules.
      await dbRecordGroupRejoinFailure(db, 'g1', nextEligibleAtMs: 2000);
      rows = await dbLoadGroupRejoinStates(db);
      expect(rows.single['rejoin_attempt_count'], 2);
      expect(rows.single['next_eligible_at'], 2000);

      // A second group is independent.
      await dbRecordGroupRejoinFailure(db, 'g2', nextEligibleAtMs: 500);
      expect(await dbLoadGroupRejoinStates(db), hasLength(2));

      // Clearing one leaves the other.
      await dbClearGroupRejoinState(db, 'g1');
      final remaining = await dbLoadGroupRejoinStates(db);
      expect(remaining, hasLength(1));
      expect(remaining.single['group_id'], 'g2');
    });
  });
}
