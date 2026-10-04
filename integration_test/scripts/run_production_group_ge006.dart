import '../../tool/sims/production_group_ge006_criteria.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_runner.dart';
import '../support/production_catalog_session.dart';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.ge006',
  validatorId: 'validateProductionGroupGe006',
  texts: productionGe006Texts,
  validate: validateProductionGroupGe006,
  steps: (s) async {
    final t = productionGe006Texts(s.journey.runId);
    final name = s.catalogName('ge006');
    await s.createAndAcceptAll(name);
    await s.takeOffline('charlie', 'charlieOffline');
    await s.removeCharlie(waitApplied: false);
    await s.flow('alice', 'production_back_to_chat', 'alice-back-to-chat');
    s.proof['bobExcluded'] = await s.waitWatch(
      'bob',
      'Bob excludes Charlie',
      (x) => !ProductionCatalogSession.members(x).contains(s.peers['charlie']),
    );
    await s.rotatedForRemainingPair();
    await s.sendAndReceive(
      'alice',
      'alice-removed-window',
      'aliceGe006RemovedWindow',
      t['aliceGe006RemovedWindow']!.text,
      ['bob'],
    );
    // Charlie is offline, so a re-add that went through despite a slow flow
    // shows on Alice's own roster.
    await s.membershipEdit(
      'alice',
      'readd-charlie',
      'production_group_info_add_member',
      'production_group_info_add_member_retry',
      {'CONTACT_NAME': 'Journeycharlie'},
      () async => ProductionCatalogSession.members(
        await s.snap('alice'),
      ).contains(s.peers['charlie']),
    );
    s.proof['aliceReadded'] = await s.snap('alice');
    await s.sendAndReceive(
      'alice',
      'alice-post-readd',
      'aliceGe006PostReadd',
      t['aliceGe006PostReadd']!.text,
      ['bob'],
    );
    await s.sendAndReceive(
      'bob',
      'bob-post-readd',
      'bobGe006PostReadd',
      t['bobGe006PostReadd']!.text,
      ['alice'],
    );
    await s.bringOnline('charlie');
    s.proof['charlieRelaunched'] = await s.snap('charlie');
    await s.acceptReadd(name);
    for (final key in ['aliceGe006PostReadd', 'bobGe006PostReadd']) {
      await s.waitWatch(
        'charlie',
        'charlie receives $key',
        (x) => ProductionCatalogSession.rows(x, key) == 1,
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      s.proof['got:$key:charlie'] = await s.snap('charlie');
    }
    await s.sendAndReceive(
      'charlie',
      'charlie-post-catch-up',
      'charlieGe006PostCatchUp',
      t['charlieGe006PostCatchUp']!.text,
      ['alice', 'bob'],
    );
  },
);
