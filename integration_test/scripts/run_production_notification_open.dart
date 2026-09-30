import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_notification_open_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_journey_peer.dart';
import '../support/production_provider_delivery.dart';

const _scenario = 'production.notification_open';
Map<String, Object?> _object(Object? value) =>
    Map<String, Object?>.from(value as Map);

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--list-scenarios')) {
    stdout.writeln(_scenario);
    return;
  }
  var attempts = 0;
  SimsArtifactEvidence? evidence;
  Directory? output;
  try {
    final path = Platform.environment['SIMS_PROOF_DIRECTORY'];
    if (path == null || path.isEmpty) {
      throw StateError('missing SIMS_PROOF_DIRECTORY');
    }
    final root = await Directory(path).absolute.create(recursive: true);
    output = await root.createTemp('attempt-');
    final journey = ProductionAndroidJourney.fromEnvironment(_scenario, output);
    final cases = <Map<String, Object?>>[];
    Map<String, Object?>? provider;
    final elapsed = Stopwatch()..start();
    try {
      await journey.prepare();
      final a = await journey.alice.command('identity');
      final b = await journey.bob.command('identity');
      final other = await journey.bob.command('prepare_other_chat');
      final aliceId = a['peerId']! as String;
      final aliceUsername = a['username']! as String;
      final bobId = b['peerId']! as String;
      final otherId = other['peerId']! as String;
      journey.alice = await journey.reopen(journey.alice);
      journey.bob = await journey.reopen(journey.bob);
      // Reopening starts a new bootstrap that may rotate its cached FCM token.
      var providerToken = await journey.bob.claimProviderToken();
      await journey.flow(
        journey.bob,
        'production_direct_open',
        'bob-other-chat',
        {'PEER_ID': otherId},
      );
      await journey.flow(
        journey.alice,
        'production_direct_open',
        'alice-sender-chat',
        {'PEER_ID': bobId},
      );

      Future<Map<String, Object?>> snapshot(ProductionJourneyPeer p) =>
          p.command('direct_snapshot', {
            'peerIds': p.invocation.role == 'bob'
                ? [aliceId, otherId]
                : [bobId],
          });
      for (final id in ['warm-other-chat', 'cold-start', 'same-peer']) {
        attempts++;
        final baseline = (await snapshot(journey.bob))['notifications'] as List;
        await journey.flow(
          journey.bob,
          'production_background',
          '$id-background',
        );
        await waitForProductionObservation(
          'real paused lifecycle',
          const Duration(seconds: 5),
          () async {
            final value = await snapshot(journey.bob);
            return value['lifecycle'] == 'paused' ? value : null;
          },
        );
        // SwiftKey capitalizes the first character of a newly opened chat.
        // The fixture keeps exact case-sensitive UI and persisted-text checks.
        final text =
            '${id[0].toUpperCase()}${id.substring(1)} notification ${journey.runId}';
        await journey.flow(
          journey.alice,
          'production_direct_send',
          '$id-send',
          {'MESSAGE': text, 'MESSAGE_PATTERN': RegExp.escape(text)},
        );
        final sent = await waitForProductionObservation(
          'exact outgoing message',
          const Duration(seconds: 30),
          () async {
            final rows = ((await snapshot(journey.alice))['messages'] as List)
                .cast<Map>()
                .where((row) => row['text'] == text && row['incoming'] == false)
                .toList();
            return rows.length == 1 ? _object(rows.single) : null;
          },
        );
        final messageId = sent['id']! as String;
        final delivery = await proveProductionProviderDelivery(
          journey: journey,
          receiver: journey.bob,
          token: providerToken,
          caseId: id,
          data: {
            'type': 'new_message',
            'sender_id': aliceId,
            'message_id': messageId,
            'title': 'Mknoon',
            'body': text,
          },
        );
        String? nativeDump;
        final received = await waitForProductionObservation(
          'exact received message and native notification card',
          const Duration(seconds: 30),
          () async {
            final value = await snapshot(journey.bob);
            final rows = (value['messages'] as List).cast<Map>();
            if (!rows.any(
              (row) => row['id'] == messageId && row['incoming'] == true,
            )) {
              return null;
            }
            final dump = await journey.bob.adb([
              'shell',
              'dumpsys',
              'notification',
              '--noredact',
            ]);
            nativeDump = '${dump.stdout}';
            final card = productionNotificationOpenNativeCard(
              nativeDump!,
              package: journey.bob.packageName,
              body: text,
            );
            return card == null
                ? null
                : {'snapshot': value, 'nativeCard': card};
          },
        );
        final before = _object(received['snapshot']);
        final nativeCard = _object(received['nativeCard']);
        final nativeFile = File('${output.path}/$id-native.txt');
        await nativeFile.writeAsString(nativeDump!);
        await journey.runner.run('chmod', ['600', nativeFile.path]);
        final previousNonce = journey.bob.invocation.nonce;
        if (id == 'cold-start') {
          final previous = journey.bob;
          journey.bob = await journey.stageFreshInvocation(previous);
          await journey.killOwnedProcess(previous);
        }
        await journey.flow(
          journey.bob,
          'production_notification_tap',
          '$id-tap',
          {'MESSAGE_PATTERN': RegExp.escape(text)},
        );
        if (id == 'cold-start') {
          await journey.bob.awaitReady();
          // The cold notification tap starts another bootstrap generation.
          providerToken = await journey.bob.claimProviderToken();
        }
        final after = await waitForProductionObservation(
          'production conversation route and read state',
          const Duration(seconds: 5),
          () async {
            final value = await snapshot(journey.bob);
            final routes = (value['conversations'] as List).cast<Map>();
            final rows = (value['messages'] as List).cast<Map>();
            return routes.any(
                      (route) =>
                          route['peerId'] == aliceId &&
                          route['onstage'] == true,
                    ) &&
                    rows.any(
                      (row) => row['id'] == messageId && row['readAt'] != null,
                    )
                ? value
                : null;
          },
        );
        cases.add({
          'id': id,
          'senderPeerId': aliceId,
          'otherPeerId': otherId,
          'messageId': messageId,
          'sentText': text,
          'senderUsername': aliceUsername,
          'provider': delivery,
          'nativeCard': nativeCard,
          'notificationBaseline': baseline.length,
          'before': before,
          'after': after,
          if (id == 'cold-start') ...{
            'coldProcessDeathVerified': true,
            'beforeNonce': previousNonce,
            'afterNonce': journey.bob.invocation.nonce,
          },
        });
        await File(
          '${output.path}/scenario-observations.json',
        ).writeAsString(jsonEncode({'cases': cases}));
      }
      final failures = validateProductionNotificationOpen({'cases': cases});
      await File(
        '${output.path}/oracle.json',
      ).writeAsString(jsonEncode({'failures': failures}));
      if (failures.isNotEmpty) throw StateError(failures.join('; '));
      provider = {'caseReceipts': cases.map((row) => row['provider']).toList()};
    } catch (error, stack) {
      await File(
        '${output.path}/scenario-failure.txt',
      ).writeAsString('$error\n$stack');
      rethrow;
    } finally {
      await journey.restore();
    }
    evidence = writeSimsArtifactEvidenceSync(
      directory: output,
      capabilityId: _scenario,
      validatorIds: ['validateProductionNotificationOpen'],
      payload: {
        ...journey.provenance(),
        'cases': cases,
        'provider': provider,
        'elapsedMs': elapsed.elapsedMilliseconds,
        'status': 'PASS',
      },
    );
  } catch (error, stack) {
    if (output != null) {
      await File(
        '${output.path}/first-failure.txt',
      ).writeAsString('$error\n$stack');
    }
  }
  final passed = evidence != null;
  stdout.writeln(
    'SIMS_RESULT_JSON=${jsonEncode({'status': passed ? 'PASS' : 'FAIL', 'assertionsAttempted': attempts, 'artifactPresent': passed, 'printOnly': false, 'exitCode': passed ? 0 : 1, 'detail': passed ? 'production warm/cold/same-peer notification routing passed' : 'production notification-open journey failed', if (evidence != null) 'artifactEvidence': evidence.toJson()})}',
  );
  exitCode = passed ? 0 : 1;
}
