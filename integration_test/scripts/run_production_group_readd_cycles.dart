import '../../tool/sims/production_group_readd_cycles_criteria.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_runner.dart';
import '../support/production_catalog_session.dart';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.private_readd_cycles',
  validatorId: 'validateProductionGroupReaddCycles',
  texts: productionMl008Texts,
  validate: validateProductionGroupReaddCycles,
  steps: (s) async {
    final t = productionMl008Texts(s.journey.runId);
    final name = s.catalogName('private_readd_cycles');
    Future<void> receive(String role, String key) => s.waitWatch(
      role,
      '$role receives $key',
      (x) => ProductionCatalogSession.rows(x, key) == 1,
    );
    await s.createAndAcceptAll(name);
    // Alice's key epoch and her new rotation/removal events after each
    // removal, so a removal that did not rotate names its cause.
    final seenRotationEvents = <String>{};
    for (var c = 1; c <= productionMl008Cycles; c++) {
      await s.removeCharlie();
      s.proof['charlieSelfRemoved:$c'] =
          (s.proof['charlieRemoved'] as Map)['selfMember'] == false;
      await s.rotatedForRemainingPair();
      final alice = await s.snap('alice');
      s.proof['rotation:$c'] = {
        'keyEpoch': alice['keyEpoch'],
        'events': [
          for (final e in (alice['flowEvents'] as List? ?? const []).cast<Map>())
            if ('${e['event']}'.startsWith('GROUP_ROTATE_KEY_') ||
                '${e['event']}'.startsWith('GROUP_INFO_FL_REMOVE_'))
              if (seenRotationEvents.add('${e['ts']}${e['event']}')) e,
        ],
      };
      await s.flow('alice', 'production_back_to_chat', 'alice-back-to-chat');
      final removed = productionMl008RemovedKey(c);
      await s.verbatimSend('alice', 'alice-removed-$c', t[removed]!.text);
      await receive('bob', removed);
      // The original's two-second window before Charlie's count; his rows
      // persist, so the final snapshot carries any leak.
      await Future<void>.delayed(const Duration(seconds: 2));
      await s.readdCharlie(name);
      final bob = await s.snap('bob');
      s.proof['bobCharlieRows:$c'] = ProductionCatalogSession.members(
        bob,
      ).where((p) => p == s.peers['charlie']).length;
      final alicePost = productionMl008AlicePostKey(c);
      await s.verbatimSend('alice', 'alice-post-$c', t[alicePost]!.text);
      await receive('bob', alicePost);
      await receive('charlie', alicePost);
      final charliePost = productionMl008CharliePostKey(c);
      await s.verbatimSend('charlie', 'charlie-post-$c', t[charliePost]!.text);
      await receive('alice', charliePost);
      await receive('bob', charliePost);
      if (productionMl008RestartRole(c) case final role?) {
        await s.takeOffline(role, 'restart:$c');
        await s.bringOnline(role);
        await s.settled(role, 3);
      }
      s.proof['completedCycles'] = c;
      await s.persist();
    }
  },
);
