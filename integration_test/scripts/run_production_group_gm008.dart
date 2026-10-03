import '../../tool/sims/production_group_gm008_criteria.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_runner.dart';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.gm008',
  validatorId: 'validateProductionGroupGm008',
  texts: productionGm008Texts,
  validate: validateProductionGroupGm008,
  steps: (s) async {
    final t = productionGm008Texts(s.journey.runId);
    final name = s.catalogName('gm008');
    await s.createAndAcceptAll(name);
    await s.removeCharlie();
    // Charlie restarts after applying his removal.
    await s.takeOffline('charlie', 'charlieRestarted');
    await s.bringOnline('charlie');
    s.proof['charlieAfterRestart'] = await s.snap('charlie');
    await s.rotatedForRemainingPair();
    s.proof['charlieRejected'] = await s.actors['charlie']!.command(
      'catalog_attempt_removed_send',
      {
        'key': 'charlieDuringRestartedRemoval',
        'text': t['charlieDuringRestartedRemoval']!.text,
      },
    );
    await s.flow('alice', 'production_back_to_chat', 'alice-back-to-chat');
    await s.sendAndReceive(
      'alice',
      'alice-during-removal',
      'aliceDuringCharlieRestartedRemoval',
      t['aliceDuringCharlieRestartedRemoval']!.text,
      ['bob'],
    );
    // The original's five-second window before counting Charlie's rows.
    await Future<void>.delayed(const Duration(seconds: 5));
    s.proof['charlieRemovedWindow'] = await s.snap('charlie');
    await s.readdCharlie(name);
    await s.sendAndReceive(
      'charlie',
      'charlie-after-readd',
      'charlieAfterRestartReadd',
      t['charlieAfterRestartReadd']!.text,
      ['alice', 'bob'],
    );
    await s.sendAndReceive(
      'alice',
      'alice-after-readd',
      'aliceAfterRestartReadd',
      t['aliceAfterRestartReadd']!.text,
      ['bob', 'charlie'],
    );
  },
);
