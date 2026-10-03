import '../../tool/sims/production_group_ge005_criteria.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_runner.dart';
import '../support/production_catalog_session.dart';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.ge005',
  validatorId: 'validateProductionGroupGe005',
  texts: productionGe005Texts,
  validate: validateProductionGroupGe005,
  steps: (s) async {
    final t = productionGe005Texts(s.journey.runId);
    final name = s.catalogName('ge005');
    Future<void> receive(String role, String key) => s.waitWatch(
      role,
      '$role receives $key',
      (x) => ProductionCatalogSession.rows(x, key) == 1,
    );
    await s.createAndAcceptAll(name);
    for (var c = 1; c <= productionGe005Cycles; c++) {
      final tag = c.toString().padLeft(2, '0');
      await s.removeCharlie();
      await s.flow('alice', 'production_back_to_chat', 'alice-back-to-chat');
      final removed = productionGe005RemovedKey(c);
      await s.verbatimSend('alice', 'alice-removed-$tag', t[removed]!.text);
      await receive('bob', removed);
      await s.rotatedForRemainingPair();
      await s.readdCharlie(name);
      final readd = productionGe005ReaddKey(c);
      await s.verbatimSend('bob', 'bob-readd-$tag', t[readd]!.text);
      await receive('alice', readd);
      await receive('charlie', readd);
      s.proof['completedCycles'] = c;
      await s.persist();
    }
    // The original receivers' two-second duplicate-settlement window.
    await Future<void>.delayed(const Duration(seconds: 2));
  },
);
