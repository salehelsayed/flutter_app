import 'dart:io';

import '../../tool/sims/production_group_media_reaction_criteria.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_runner.dart';
import '../support/production_catalog_session.dart';
import '../support/production_journey_peer.dart';

const _key = 'aliceMediaReactionTarget';
const _fixture = 'integration_test/fixtures/received_media_egress_fixture.jpg';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.private_media_reaction_roundtrip',
  validatorId: 'validateProductionGroupMediaReaction',
  texts: productionMediaReactionTexts,
  validate: validateProductionGroupMediaReaction,
  steps: (s) async {
    final text = productionMediaReactionTexts(s.journey.runId)[_key]!.text;
    final pattern = RegExp.escape(text);
    await s.createAndAcceptAll(
      s.catalogName('private_media_reaction_roundtrip'),
    );
    // A real image in Alice's gallery, picked in the composer like a user.
    final alice = s.actors['alice']!;
    final file =
        'mknoon_l01_${s.journey.runId.replaceAll(RegExp('[^A-Za-z0-9]'), '')}.jpg';
    final remote = '/sdcard/Pictures/$file';
    await alice.adb(['push', File(_fixture).absolute.path, remote]);
    // adb push keeps the source file's date; give the image the current one
    // so it is the newest entry of the picker's Recent list.
    await alice.adb(['shell', 'touch', remote]);
    await alice.adb([
      'shell',
      'am',
      'broadcast',
      '-a',
      'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
      '-d',
      'file://$remote',
    ]);
    try {
      await s.verbatimFlow(
        'alice',
        'production_catalog_group_send_media',
        'production_catalog_group_send_media',
        'send-media',
        {'FILE': file, 'MESSAGE': text, 'MESSAGE_PATTERN': pattern},
      );
    } finally {
      await alice.adb(['shell', 'rm', '-f', remote], allowFailure: true);
    }
    for (final receiver in ['bob', 'charlie']) {
      await s.waitWatch(receiver, '$receiver receives the image message', (x) {
        final rows = (x['watched'] as Map?)?[_key] as List? ?? const [];
        return rows.length == 1 &&
            ((rows.single as Map)['mediaAttachmentCount'] as int? ?? 0) >= 1;
      });
      // The original receiver's two-second duplicate-settlement window.
      await Future<void>.delayed(const Duration(seconds: 2));
      s.proof['got:$_key:$receiver'] = await s.snap(receiver);
    }
    final sent = await s.waitWatch(
      'alice',
      'Alice holds her image message',
      (x) => ProductionCatalogSession.rows(x, _key) == 1,
    );
    final target =
        (((sent['watched'] as Map)[_key] as List).single as Map)['messageId']
            as String;
    final arms = <String, Object?>{};
    final finals = <String, Object?>{};
    s.proof['reactionArmed'] = arms;
    s.proof['reactionFinal'] = finals;
    for (final role in ['alice', 'bob', 'charlie']) {
      arms[role] = await s.actors[role]!.command('catalog_arm_reaction', {
        'messageId': target,
        'reactorPeerId': s.peers['bob'],
      });
    }
    await s.persist();
    await s.flow('bob', 'production_catalog_react', 'react-bob', {
      'MESSAGE_PATTERN': pattern,
    });
    for (final role in ['alice', 'bob', 'charlie']) {
      await waitForProductionObservation(
        '$role actual reaction delivery',
        const Duration(seconds: 120),
        () async {
          final r = await s.actors[role]!.command('catalog_reaction_snapshot');
          return (r['reactions'] as List).length == 1 &&
                  (role == 'bob'
                      ? (r['outcomes'] as List).isNotEmpty
                      : (r['changes'] as List).isNotEmpty)
              ? r
              : null;
        },
      );
    }
    // The original receiver's duplicate-settlement window.
    await Future<void>.delayed(const Duration(seconds: 2));
    for (final role in ['alice', 'bob', 'charlie']) {
      finals[role] = await s.actors[role]!.command('catalog_reaction_snapshot');
    }
    await s.persist();
  },
);
