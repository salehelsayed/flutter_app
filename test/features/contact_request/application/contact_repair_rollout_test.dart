import 'package:flutter_app/features/contact_request/application/contact_repair_rollout.dart';
import 'package:flutter_app/features/contact_request/data/repositories/sql_contact_repair_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/contact_repair_harness.dart';

// Task 12b: the signed marker is on by default; rolloutEnabled: false is the
// off switch, where only a peer that sent us a marker is eligible.

void main() {
  test('the marker is on by default (BL-21)', () async {
    expect(contactRepairRolloutEnabled, isTrue);
    expect(await contactRepairRolloutEligible('any-peer-id-0000'), isTrue);
  });

  test('without the flag, only a peer that sent us a valid signed marker is '
      'eligible', () async {
    final db = await openRepairTestDatabase();
    addTearDown(db.close);
    final repo = SqlContactRepairRepository(db);
    final eligible = contactRepairEligibility(
      repository: repo,
      rolloutEnabled: false,
    );
    expect(await eligible('updated-peer-0000'), isFalse);
    await repo.recordPeerSupportsMarked('updated-peer-0000');
    expect(await eligible('updated-peer-0000'), isTrue);
    expect(await eligible('older-peer-00000'), isFalse);
    expect(
      await contactRepairEligibility(repository: null, rolloutEnabled: false)(
        'updated-peer-0000',
      ),
      isFalse,
    );
  });

  test('the coordinated rollout flag makes every peer eligible', () async {
    final eligible = contactRepairEligibility(
      repository: null,
      rolloutEnabled: true,
    );
    expect(await eligible('any-peer-id-0000'), isTrue);
  });
}
