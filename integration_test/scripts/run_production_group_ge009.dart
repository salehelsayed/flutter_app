import '../../tool/sims/production_group_ge009_criteria.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_runner.dart';
import '../support/production_catalog_session.dart';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.ge009',
  validatorId: 'validateProductionGroupGe009',
  texts: productionGe009Texts,
  validate: validateProductionGroupGe009,
  steps: (s) async {
    final t = productionGe009Texts(s.journey.runId);
    final name = s.catalogName('ge009');
    await s.createAndAcceptAll(name);
    for (final (role, key, to) in const [
      ('alice', 'aliceGe009BeforePartition', ['bob', 'charlie']),
      ('bob', 'bobGe009BeforePartition', ['alice', 'charlie']),
      ('charlie', 'charlieGe009BeforePartition', ['alice', 'bob']),
    ]) {
      await s.sendAndReceive(role, '$role-before', key, t[key]!.text, to);
    }
    await s.removeCharlie();
    await s.flow('alice', 'production_back_to_chat', 'alice-back-to-chat');
    // Charlie stays "partitioned": the re-add invitation is not accepted
    // until Alice and Bob have exchanged their post-re-add messages.
    await s.readdCharlie(name, accept: false);
    await s.waitWatch(
      'bob',
      'Bob includes Charlie',
      (x) => ProductionCatalogSession.members(x).contains(s.peers['charlie']),
    );
    await s.sendAndReceive(
      'alice',
      'alice-post-readd',
      'aliceGe009PostReadd',
      t['aliceGe009PostReadd']!.text,
      ['bob'],
    );
    await s.sendAndReceive(
      'bob',
      'bob-post-readd',
      'bobGe009PostReadd',
      t['bobGe009PostReadd']!.text,
      ['alice'],
    );
    s.proof['charliePartitioned'] = await s.snap('charlie');
    // Heal: Charlie accepts and catches up through the app's own replay.
    await s.acceptReadd(name);
    for (final key in ['aliceGe009PostReadd', 'bobGe009PostReadd']) {
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
      'charlie-after-heal',
      'charlieGe009AfterHeal',
      t['charlieGe009AfterHeal']!.text,
      ['alice', 'bob'],
    );
  },
);
