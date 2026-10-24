import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_group_local_media_delete_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_session.dart';
import '../support/production_sims_result.dart';

const _fixture = 'integration_test/fixtures/received_media_egress_fixture.jpg';
const _roles = ['alice', 'bob', 'charlie'];

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--list-scenarios')) {
    stdout.writeln(productionGroupLocalMediaDelete);
    return;
  }
  Directory? output;
  SimsArtifactEvidence? evidence;
  var attempted = 0;
  try {
    if (Platform.environment['SIMS_DISPOSABLE_ANDROID_JOURNEYS'] != '1') {
      throw StateError('requires three disposable emulator roles');
    }
    final path = Platform.environment['SIMS_PROOF_DIRECTORY'];
    if (path == null || path.isEmpty) {
      throw StateError('proof directory missing');
    }
    output = await (await Directory(
      path,
    ).absolute.create(recursive: true)).createTemp('attempt-');
    final journey = ProductionAndroidJourney.fromEnvironment(
      groupLocalMediaDeleteRuntime,
      output,
    );
    final proof = <String, Object?>{
      'runId': journey.runId,
      'runtimeScenario': groupLocalMediaDeleteRuntime,
      'emulatorTriple':
          journey.disposableAndroidJourneys && journey.actors.length == 3,
      'fixtureSha256': sha256
          .convert(await File(_fixture).readAsBytes())
          .toString(),
    };
    final s = ProductionCatalogSession(journey, output, proof);
    final kills = <String, Object?>{};
    proof['ownedKills'] = kills;
    try {
      await s.start();
      final texts = groupLocalMediaDeleteTexts(journey.runId);
      s.watch = {
        for (final entry in texts.entries)
          entry.key: {
            'text': entry.value.text,
            'senderPeerId': s.peers[entry.value.role],
          },
      };
      proof['initialNonces'] = {
        for (final role in _roles) role: s.actors[role]!.invocation.nonce,
      };
      attempted++;
      await s.createAndAcceptAll(s.catalogName('de002'));
      Future<Map<String, Object?>> snapshot(String role) async => {
        ...await s.snap(role),
        'invocationNonce': s.actors[role]!.invocation.nonce,
      };
      Future<void> waitForRows(String key) async {
        for (final role in _roles) {
          await s.waitWatch(role, '$role actual $key row', (x) {
            final rows = (x['watched'] as Map?)?[key] as List? ?? const [];
            return rows.length == 1 &&
                (rows.single as Map)['mediaAttachmentCount'] ==
                    (texts[key]!.media ? 1 : 0);
          });
        }
      }

      Future<void> sendImage(String key) async {
        final peer = s.actors['alice']!;
        final safeRun = journey.runId.replaceAll(RegExp('[^A-Za-z0-9]'), '');
        final file = 'mknoon_gc009_${safeRun}_$key.jpg';
        final remote = '/sdcard/Pictures/$file';
        await peer.adb(['push', File(_fixture).absolute.path, remote]);
        try {
          await peer.adb(['shell', 'touch', remote]);
          await peer.adb([
            'shell',
            'am',
            'broadcast',
            '-a',
            'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
            '-d',
            'file://$remote',
          ]);
          await s.verbatimFlow(
            'alice',
            'production_catalog_group_send_media',
            'production_catalog_group_send_media',
            'send-$key',
            {
              'FILE': file,
              'MESSAGE': texts[key]!.text,
              'MESSAGE_PATTERN': RegExp.escape(texts[key]!.text),
            },
          );
          await waitForRows(key);
        } finally {
          await peer.adb(['shell', 'rm', '-f', remote], allowFailure: true);
        }
      }

      // One author's clock establishes the real top-to-bottom selector anchors;
      // no ordering claim is inferred by comparing different device clocks.
      await sendImage('target');
      await s.verbatimSend('alice', 'send-marker', texts['marker']!.text);
      await waitForRows('marker');
      await sendImage('preserved');
      final values = {
        'TARGET_PATTERN': RegExp.escape(texts['target']!.text),
        'MARKER_PATTERN': RegExp.escape(texts['marker']!.text),
        'PRESERVED_PATTERN': RegExp.escape(texts['preserved']!.text),
      };
      Future<void> openImage(String role, String key, String label) => s.flow(
        role,
        key == 'target'
            ? 'production_catalog_media_open_above_marker'
            : 'production_catalog_media_open_below_marker',
        label,
        {...values, 'CAPTION_PATTERN': RegExp.escape(texts[key]!.text)},
      );
      for (final role in _roles) {
        await openImage(role, 'target', 'before-target-$role');
        await openImage(role, 'preserved', 'before-preserved-$role');
      }
      proof['beforeDelete'] = {
        for (final role in _roles) role: await snapshot(role),
      };
      await s.persist();
      await s.flow(
        'bob',
        'production_catalog_media_delete_above_marker',
        'delete-target-bob',
        values,
      );
      await s.waitWatch(
        'bob',
        'Bob local target row absent',
        (x) =>
            ProductionCatalogSession.rows(x, 'target') == 0 &&
            ProductionCatalogSession.rows(x, 'marker') == 1 &&
            ProductionCatalogSession.rows(x, 'preserved') == 1,
      );
      Future<void> verifyPhase(String phase) async {
        for (final role in _roles) {
          if (role != 'bob') {
            await openImage(role, 'target', '$phase-target-$role');
          }
          await openImage(role, 'preserved', '$phase-preserved-$role');
          if (role == 'bob') {
            await s.flow(
              role,
              'production_catalog_media_assert_local_absent',
              '$phase-absent-bob',
              values,
            );
          }
        }
        proof[phase] = {for (final role in _roles) role: await snapshot(role)};
        await s.persist();
      }

      await verifyPhase('afterDelete');
      for (final role in _roles) {
        final peer = s.actors[role]!;
        await journey.killOwnedProcess(peer);
        kills[role] = jsonDecode(
          await File(
            '${output.path}/${peer.invocation.nonce}-process-death.json',
          ).readAsString(),
        );
        await s.persist();
        await peer.adb(['shell', 'am', 'force-stop', peer.packageName]);
      }
      final groupId =
          ((proof['beforeDelete'] as Map)['alice'] as Map)['groupId'] as String;
      for (final role in _roles) {
        s.replace(role, await journey.reopen(s.actors[role]!));
        await s.settled(role, 3);
        await s.flow(role, 'production_group_open', 'open-afterRestart-$role', {
          'GROUP_ID': groupId,
        });
      }
      proof['finalNonces'] = {
        for (final role in _roles) role: s.actors[role]!.invocation.nonce,
      };
      await verifyPhase('afterRestart');
      final failures = validateProductionGroupLocalMediaDelete(proof);
      await File(
        '${output.path}/oracle.json',
      ).writeAsString(jsonEncode({'failures': failures}));
      if (failures.isNotEmpty) throw StateError(failures.join('; '));
    } finally {
      await journey.restore();
    }
    evidence = writeSimsArtifactEvidenceSync(
      directory: output,
      capabilityId: productionGroupLocalMediaDelete,
      validatorIds: ['validateProductionGroupLocalMediaDelete'],
      payload: {...journey.provenance(), ...proof, 'status': 'PASS'},
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
    'SIMS_RESULT_JSON=${jsonEncode(productionSimsResult(passed: passed, assertionsAttempted: attempted, detail: passed ? 'received group media local deletion leg passed' : 'local deletion leg incomplete or failed', evidence: evidence))}',
  );
  exitCode = passed ? 0 : 1;
}
