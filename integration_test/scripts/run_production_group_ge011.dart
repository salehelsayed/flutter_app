import '../../tool/sims/production_group_ge011_criteria.dart';
import '../support/production_catalog_fallback_steps.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_runner.dart';

const _key = 'aliceGe011PartialLiveFallback';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.ge011',
  validatorId: 'validateProductionGroupGe011',
  texts: productionGe011Texts,
  validate: validateProductionGroupGe011,
  steps: (s) async {
    final t = productionGe011Texts(s.journey.runId);
    await s.createAndAcceptAll(s.catalogName('ge011'));
    s.proof['bobBeforeSend'] = await s.snap('bob');
    s.proof['charlieBeforeSend'] = await s.snap('charlie');
    await s.takeOffline('charlie', 'charlieOffline');
    await Future<void>.delayed(productionCatalogMeshSettle);
    await s.verbatimSend('alice', 'alice-partial-live', t[_key]!.text);
    await s.ownRowSent('alice', _key);
    await s.receivedOnce('bob', _key);
    // The original's catch-up drain after Bob's live copy.
    s.proof['bobDrain'] = await s.actors['bob']!.command('catalog_drain_once');
    await s.relaunchAndRecover('charlie', _key);
  },
);
