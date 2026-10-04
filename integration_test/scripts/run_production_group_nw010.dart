import '../../tool/sims/production_group_nw010_criteria.dart';
import '../support/production_catalog_fallback_steps.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_runner.dart';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability:
      'production.group_catalog.private_background_resume_group_delivery',
  validatorId: 'validateProductionGroupNw010',
  texts: productionNw010Texts,
  validate: validateProductionGroupNw010,
  steps: (s) async {
    final texts = productionNw010Texts(s.journey.runId);
    String text(String key) => texts[key]!.text;
    final order = <String>[];
    s.proof['order'] = order;
    Future<void> mark(String milestone) async {
      order.add(milestone);
      await s.persist();
    }

    await s.createAndAcceptAll(
      s.catalogName('private_background_resume_group_delivery'),
    );
    final groupId = (await s.snap('alice'))['groupId'] as String;

    // Bob goes away: verified death of his app process (the original stops
    // his node while "backgrounded").
    await s.takeOffline('bob', 'bob-offline');
    await mark('bob-offline');
    await Future<void>.delayed(productionCatalogMeshSettle);
    await s.sendAndReceive(
      'alice',
      'alice-before-edit',
      'aliceDuringBackgroundBeforeEdit',
      text('aliceDuringBackgroundBeforeEdit'),
      ['charlie'],
    );
    await s.ownRowSent('alice', 'aliceDuringBackgroundBeforeEdit');

    // Alice removes online Charlie while Bob is away.
    await s.removeCharlie(waitApplied: false);
    s.proof['charlieRemoved'] = await s.waitWatch(
      'charlie',
      'Charlie self-removed',
      (x) => x['selfMember'] == false,
    );
    await mark('remove-charlie');
    await s.flow('alice', 'production_back_to_chat', 'alice-back-to-chat');
    await s.verbatimSend(
      'alice',
      'alice-after-edit',
      text('aliceDuringBackgroundAfterEdit'),
    );
    await s.ownRowSent('alice', 'aliceDuringBackgroundAfterEdit');
    await mark('alice-after-edit');

    // Bob comes back: an ordinary relaunch; his catch-up applies the first
    // post, Charlie's removal and the second post.
    await s.relaunchAndRecover('bob', 'aliceDuringBackgroundBeforeEdit');
    await mark('bob-online');
    await s.receivedOnce('bob', 'aliceDuringBackgroundAfterEdit');
    s.proof['bobRecovered'] = await s.wait(
      'bob',
      'catalog_group_snapshot',
      'Bob group recovery finished',
      (x) => x['groupRecoveryActive'] == false,
    );
    await s.flow('bob', 'production_group_open', 'bob-open-group', {
      'GROUP_ID': groupId,
    });
    await Future<void>.delayed(productionCatalogMeshSettle);
    await s.sendAndReceive(
      'alice',
      'alice-post-foreground',
      'alicePostForegroundLive',
      text('alicePostForegroundLive'),
      ['bob'],
    );
    await s.sendAndReceive(
      'bob',
      'bob-publish-back',
      'bobPostForegroundPublishBack',
      text('bobPostForegroundPublishBack'),
      ['alice'],
    );
  },
);
