import '../../tool/sims/production_group_nw006_criteria.dart';
import '../support/production_catalog_fallback_steps.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_runner.dart';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.private_peer_disconnect_not_removal',
  validatorId: 'validateProductionGroupNw006',
  texts: productionNw006Texts,
  validate: validateProductionGroupNw006,
  steps: (s) async {
    final texts = productionNw006Texts(s.journey.runId);
    await s.createAndAcceptAll(
      s.catalogName('private_peer_disconnect_not_removal'),
    );
    s.proof['aliceBeforeDisconnect'] = await s.snap('alice');
    // Bob's disconnect: verified death of his app process (the original
    // stops his node). Charlie stays live on the topic.
    await s.takeOffline('bob', 'bob-offline');
    await Future<void>.delayed(productionCatalogMeshSettle);
    s.proof['aliceDuringDisconnect'] = await s.snap('alice');
    await s.sendAndReceive(
      'alice',
      'alice-missed',
      'aliceMissedDuringDisconnect',
      texts['aliceMissedDuringDisconnect']!.text,
      ['charlie'],
    );
    await s.ownRowSent('alice', 'aliceMissedDuringDisconnect');
    await s.relaunchAndRecover('bob', 'aliceMissedDuringDisconnect');
    final groupId = (await s.snap('alice'))['groupId'] as String;
    await s.flow('bob', 'production_group_open', 'bob-open-group', {
      'GROUP_ID': groupId,
    });
    // Bob's topic mesh forms before the post-reconnect sends, so live
    // receipt is observable rather than an inbox catch-up.
    await Future<void>.delayed(productionCatalogMeshSettle);
    await s.sendAndReceive(
      'alice',
      'alice-post-reconnect',
      'alicePostReconnectLive',
      texts['alicePostReconnectLive']!.text,
      ['bob', 'charlie'],
    );
    await s.sendAndReceive(
      'bob',
      'bob-publish-back',
      'bobPublishBackAfterReconnect',
      texts['bobPublishBackAfterReconnect']!.text,
      ['alice', 'charlie'],
    );
  },
);
