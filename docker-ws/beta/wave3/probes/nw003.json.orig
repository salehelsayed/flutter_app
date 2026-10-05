import '../../tool/sims/production_group_nw003_criteria.dart';
import '../support/production_catalog_fallback_steps.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_runner.dart';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.private_partition_readd_heal',
  validatorId: 'validateProductionGroupNw003',
  texts: productionNw003Texts,
  validate: validateProductionGroupNw003,
  steps: (s) async {
    final texts = productionNw003Texts(s.journey.runId);
    String text(String key) => texts[key]!.text;
    final name = s.catalogName('private_partition_readd_heal');
    await s.createAndAcceptAll(name);
    await s.sendAndReceive(
      'alice',
      'alice-baseline',
      'aliceNw003Baseline',
      text('aliceNw003Baseline'),
      ['bob', 'charlie'],
    );
    final groupId = (await s.snap('alice'))['groupId'] as String;

    // Partition: Bob's and Charlie's app processes die (verified); the
    // original stops their nodes.
    await s.takeOffline('bob', 'bob-offline');
    await s.takeOffline('charlie', 'charlie-offline');
    await Future<void>.delayed(productionCatalogMeshSettle);

    // Alice removes Charlie while both are away; her removal rotates the key.
    await s.removeCharlie(waitApplied: false);
    await s.waitWatch(
      'alice',
      'Alice rotated the key',
      (x) => ((x['keyEpoch'] as int?) ?? 0) >= 2,
    );
    await s.flow('alice', 'production_back_to_chat', 'alice-back-to-chat');
    await s.verbatimSend(
      'alice',
      'alice-removed-window',
      text('aliceRemovedWindow'),
    );
    await s.ownRowSent('alice', 'aliceRemovedWindow');

    // Alice re-adds Charlie, still away; his invitation waits on the relay.
    await s.readdCharlie(name, accept: false);

    // Heal: both relaunch the same installs. Bob recovers the removed-window
    // post from the inbox; Charlie applies his removal, then accepts the
    // waiting re-add invitation.
    await s.relaunchAndRecover('bob', 'aliceRemovedWindow');
    await s.flow('bob', 'production_group_open', 'bob-open-group', {
      'GROUP_ID': groupId,
    });
    await s.bringOnline('charlie');
    await s.acceptReadd(name);
    await Future<void>.delayed(productionCatalogMeshSettle);

    for (final (role, label, key, receivers) in const [
      ('alice', 'alice-post-heal', 'alicePostHeal', ['bob', 'charlie']),
      ('bob', 'bob-post-heal', 'bobPostHeal', ['alice', 'charlie']),
      ('charlie', 'charlie-post-heal', 'charliePostHeal', ['alice', 'bob']),
    ]) {
      await s.sendAndReceive(role, label, key, text(key), receivers);
    }
  },
);
