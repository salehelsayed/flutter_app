import '../../tool/sims/production_group_gm007_criteria.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_runner.dart';
import '../support/production_catalog_session.dart';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.gm007',
  validatorId: 'validateProductionGroupGm007',
  texts: productionGm007Texts,
  validate: validateProductionGroupGm007,
  steps: (s) async {
    final texts = productionGm007Texts(s.journey.runId);
    final name = s.catalogName('gm007');
    await s.createAndAcceptAll(name);
    await s.sendAndReceive(
      'alice',
      'alice-before-removal',
      'aliceBeforeCharlieRemoval',
      texts['aliceBeforeCharlieRemoval']!.text,
      ['bob', 'charlie'],
    );
    await s.removeCharlie();
    await s.rotatedForRemainingPair();
    await s.flow('alice', 'production_back_to_chat', 'alice-back-to-chat');
    for (var i = 1; i <= 3; i++) {
      await s.sendAndReceive(
        'alice',
        'alice-during-$i',
        'aliceDuringCharlieRemoval$i',
        texts['aliceDuringCharlieRemoval$i']!.text,
        ['bob'],
      );
    }
    // The original's five-second window before counting Charlie's rows.
    await Future<void>.delayed(const Duration(seconds: 5));
    s.proof['charlieRemovedWindow'] = await s.snap('charlie');
    await s.readdCharlie(name);
    await s.verbatimSend(
      'alice',
      'alice-after-readd',
      texts['aliceAfterCharlieReadd']!.text,
    );
    // Charlie's count before any explicit catch-up, then the original's one
    // explicit production drain before waiting for the post-re-add message.
    s.proof['charlieBeforeDrain'] = await s.snap('charlie');
    s.proof['charlieDrain'] = await s.actors['charlie']!.command(
      'catalog_drain_once',
    );
    for (final receiver in ['bob', 'charlie']) {
      await s.waitWatch(
        receiver,
        '$receiver receives aliceAfterCharlieReadd',
        (x) => ProductionCatalogSession.rows(x, 'aliceAfterCharlieReadd') == 1,
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      s.proof['got:aliceAfterCharlieReadd:$receiver'] = await s.snap(receiver);
    }
  },
);
