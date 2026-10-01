import '../../tool/sims/production_group_gm019_criteria.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_runner.dart';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.gm019',
  validatorId: 'validateProductionGroupGm019',
  texts: productionGm019Texts,
  validate: validateProductionGroupGm019,
  steps: (s) async {
    final texts = productionGm019Texts(s.journey.runId);
    final name = s.catalogName('gm019');
    await s.createAndAcceptAll(name);
    await s.removeCharlie();
    await s.flow('alice', 'production_back_to_chat', 'alice-back-to-chat');
    await s.sendAndReceive(
      'alice',
      'alice-removed-window',
      'aliceGm019RemovedWindow',
      texts['aliceGm019RemovedWindow']!.text,
      ['bob'],
    );
    // The original's five-second window before counting Charlie's rows.
    await Future<void>.delayed(const Duration(seconds: 5));
    s.proof['charlieRemovedWindow'] = await s.snap('charlie');
    await s.readdCharlie(name);
    await s.sendAndReceive(
      'alice',
      'alice-after-readd',
      'aliceGm019AfterReadd',
      texts['aliceGm019AfterReadd']!.text,
      ['bob', 'charlie'],
    );
    await s.sendAndReceive(
      'bob',
      'bob-after-readd',
      'bobGm019AfterReadd',
      texts['bobGm019AfterReadd']!.text,
      ['alice', 'charlie'],
    );
  },
);
