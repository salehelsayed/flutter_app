import '../../tool/sims/production_group_gm015_criteria.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_runner.dart';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.gm015',
  validatorId: 'validateProductionGroupGm015',
  texts: productionGm015Texts,
  validate: validateProductionGroupGm015,
  steps: (s) async {
    final t = productionGm015Texts(s.journey.runId);
    await s.createAndAcceptAll(s.catalogName('gm015'));
    for (final r in ['alice', 'bob', 'charlie']) {
      s.proof['${r}Before'] = await s.snap(r);
    }
    final groupId = (s.proof['aliceBefore']! as Map)['groupId'] as String;
    await s.flow('alice', 'production_group_info_leave_blocked', 'alice-leave-blocked');
    s.proof['aliceAfterAttempt'] = await s.snap('alice');
    s.proof['aliceExitAfter'] = await s.actors['alice']!.command(
      'catalog_exit_snapshot',
      {'groupId': groupId},
    );
    await s.sendAndReceive(
      'bob',
      'bob-post-attempt',
      'bobAfterBlockedAdminSelfRemoval',
      t['bobAfterBlockedAdminSelfRemoval']!.text,
      ['alice', 'charlie'],
    );
    await s.sendAndReceive(
      'charlie',
      'charlie-post-attempt',
      'charlieAfterBlockedAdminLeave',
      t['charlieAfterBlockedAdminLeave']!.text,
      ['alice', 'bob'],
    );
  },
);
