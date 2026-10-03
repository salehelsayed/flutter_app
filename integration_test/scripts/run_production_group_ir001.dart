import '../../tool/sims/production_group_ir001_criteria.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_runner.dart';
import '../support/production_catalog_session.dart';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.ir001',
  validatorId: 'validateProductionGroupIr001',
  texts: productionIr001Texts,
  validate: validateProductionGroupIr001,
  steps: (s) async {
    final t = productionIr001Texts(s.journey.runId);
    await s.createAndAcceptAll(s.catalogName('ir001'));
    s.proof['bobBeforeOffline'] = await s.snap('bob');
    await s.takeOffline('bob', 'bobOffline');
    for (var i = 1; i <= 3; i++) {
      await s.sendAndReceive(
        'alice',
        'alice-missed-$i',
        'aliceMissedWhileBobOffline$i',
        t['aliceMissedWhileBobOffline$i']!.text,
        ['charlie'],
      );
    }
    await s.bringOnline('bob');
    s.proof['bobRelaunched'] = await s.snap('bob');
    // The original's one explicit catch-up drain on reconnect.
    s.proof['bobDrain'] = await s.actors['bob']!.command('catalog_drain_once');
    for (var i = 1; i <= 3; i++) {
      final key = 'aliceMissedWhileBobOffline$i';
      await s.waitWatch(
        'bob',
        'bob receives $key',
        (x) => ProductionCatalogSession.rows(x, key) == 1,
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      s.proof['got:$key:bob'] = await s.snap('bob');
    }
    await s.sendAndReceive(
      'alice',
      'alice-live',
      'aliceLiveAfterBobDrain',
      t['aliceLiveAfterBobDrain']!.text,
      ['bob', 'charlie'],
    );
  },
);
