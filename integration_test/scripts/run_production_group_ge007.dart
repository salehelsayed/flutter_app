import '../../tool/sims/production_group_ge007_criteria.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_runner.dart';
import '../support/production_catalog_session.dart';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.ge007',
  validatorId: 'validateProductionGroupGe007',
  texts: productionGe007Texts,
  validate: validateProductionGroupGe007,
  steps: (s) async {
    final t = productionGe007Texts(s.journey.runId);
    final name = s.catalogName('ge007');
    await s.createAndAcceptAll(name);
    await s.takeOffline('bob', 'bobOffline');
    await s.removeCharlie(waitApplied: false);
    s.proof['charlieRemoved'] = await s.waitWatch(
      'charlie',
      'Charlie self-removed',
      (x) => x['selfMember'] == false,
    );
    await s.flow('alice', 'production_back_to_chat', 'alice-back-to-chat');
    await s.verbatimSend(
      'alice',
      'alice-removed-window',
      t['aliceGe007RemovedWindow']!.text,
    );
    await s.readdCharlie(name, accept: false);
    await s.acceptReadd(name, online: const ['alice', 'charlie']);
    await s.sendAndReceive(
      'alice',
      'alice-post-readd',
      'aliceGe007PostReadd',
      t['aliceGe007PostReadd']!.text,
      ['charlie'],
    );
    await s.sendAndReceive(
      'charlie',
      'charlie-post-readd',
      'charlieGe007PostReadd',
      t['charlieGe007PostReadd']!.text,
      ['alice'],
    );
    // Bob comes back with his own persisted state and catches up.
    await s.bringOnline('bob');
    s.proof['bobDrain'] = await s.actors['bob']!.command('catalog_drain_once');
    for (final key in [
      'aliceGe007RemovedWindow',
      'aliceGe007PostReadd',
      'charlieGe007PostReadd',
    ]) {
      await s.waitWatch(
        'bob',
        'bob receives $key',
        (x) => ProductionCatalogSession.rows(x, key) == 1,
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      s.proof['got:$key:bob'] = await s.snap('bob');
    }
    final groupId = (await s.snap('bob'))['groupId'] as String;
    await s.flow('bob', 'production_group_open', 'bob-open-group', {
      'GROUP_ID': groupId,
    });
    await s.sendAndReceive(
      'bob',
      'bob-catch-up',
      'bobGe007PostCatchUp',
      t['bobGe007PostCatchUp']!.text,
      ['alice', 'charlie'],
    );
  },
);
