import '../../tool/sims/production_group_rapid_readd_criteria.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_runner.dart';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.private_rapid_readd',
  validatorId: 'validateProductionGroupRapidReadd',
  texts: productionRapidReaddTexts,
  validate: validateProductionGroupRapidReadd,
  steps: (s) async {
    final t = productionRapidReaddTexts(s.journey.runId);
    final name = s.catalogName('private_rapid_readd');
    await s.createAndAcceptAll(name);
    // Remove, send and re-add back to back: no wait for Bob or Charlie to
    // apply the removal before the re-add is issued.
    await s.removeCharlie(waitApplied: false);
    await s.flow('alice', 'production_back_to_chat', 'alice-back-to-chat');
    await s.verbatimSend(
      'alice',
      'alice-during-rapid-remove',
      t['aliceDuringRapidRemove']!.text,
    );
    await s.readdCharlie(name, accept: false);
    s.proof['readdWithoutWaitingForRemovalAcks'] = true;
    await s.persist();
    // Bob gets the removed-window message; Charlie applies the removal
    // before accepting the new invitation.
    await s.waitWatch(
      'bob',
      'bob receives aliceDuringRapidRemove',
      (x) => (((x['watched'] as Map?)?['aliceDuringRapidRemove'] as List?) ??
                  const [])
              .length ==
          1,
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    s.proof['got:aliceDuringRapidRemove:bob'] = await s.snap('bob');
    await s.waitWatch(
      'charlie',
      'Charlie self-removed',
      (x) => x['selfMember'] == false,
    );
    // The original's five-second window before counting Charlie's rows.
    await Future<void>.delayed(const Duration(seconds: 5));
    s.proof['charlieRemovedWindow'] = await s.snap('charlie');
    await s.acceptReadd(name);
    await s.sendAndReceive(
      'alice',
      'alice-after-readd',
      'alicePostRapidReadd',
      t['alicePostRapidReadd']!.text,
      ['bob', 'charlie'],
    );
    await s.sendAndReceive(
      'bob',
      'bob-after-readd',
      'bobPostRapidReadd',
      t['bobPostRapidReadd']!.text,
      ['alice', 'charlie'],
    );
  },
);
