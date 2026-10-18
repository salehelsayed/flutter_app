import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/debug/production_journeys/sims_runtime_protocol.dart';
import 'package:flutter_app/features/update_check/domain/version_file_verifier.dart';
import 'package:flutter_app/features/update_check/infrastructure/update_check_fixture_contract.dart';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_update_check_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_ios_simulator_journey.dart';
import '../support/production_journey.dart';
import '../support/production_journey_peer.dart';
import '../support/production_sims_result.dart';
import '../support/production_update_check_notification.dart';
import '../support/update_check_test_keys.dart';

Uint8List signedUpdateFixture({
  required int installedBuild,
  required int sequence,
  required bool hard,
  int? issuedAt,
}) {
  final policy = {
    'latestBuild': installedBuild + 20,
    'minBuild': hard ? installedBuild + 1 : installedBuild,
    'reasonCode': 'general',
  };
  final payload = Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'schemaVersion': 1,
        'sequence': sequence,
        'issuedAt': issuedAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'ios': policy,
        'android': policy,
      }),
    ),
  );
  return encodeVersionEnvelope(
    keyId: updateCheckFixtureKeyId,
    payloadBytes: payload,
    signature: testOnlyK1.sign(payload).signature,
  );
}

Uint8List tamperUpdateFixtureSignature(List<int> bytes) {
  final envelope = Map<String, Object?>.from(
    jsonDecode(utf8.decode(bytes)) as Map,
  );
  final signature = base64Decode(envelope['sig'] as String);
  signature[0] ^= 1;
  envelope['sig'] = base64Encode(signature);
  return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
}

/// Adds case order and observations to the existing production journey and
/// Maestro driver. It never builds an app or controls an unpinned target.
Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--list-scenarios') {
    stdout.write('${productionUpdateCheckJourneys.join('\n')}\n');
    return;
  }
  Directory? output;
  SimsArtifactEvidence? evidence;
  var attempted = 0;
  var stage = 'arguments';
  try {
    if (arguments.length != 2 ||
        arguments.first != '--scenario' ||
        !productionUpdateCheckJourneys.contains(arguments.last)) {
      throw const FormatException(
        'An exact registered SE41 scenario is required.',
      );
    }
    final scenario = arguments.last;
    final directory = Platform.environment['SIMS_PROOF_DIRECTORY'];
    if (directory == null || directory.isEmpty) {
      throw StateError('missing proof directory');
    }
    output = await Directory(directory).absolute.create(recursive: true);
    output = await output.createTemp('attempt-');
    final ProductionJourney journey = scenario == 'kx0028'
        ? ProductionIosSimulatorJourney.fromEnvironment(scenario, output)
        : ProductionAndroidJourney.fromEnvironment(scenario, output);
    final phases = <Map<String, Object?>>[];
    final proof = <String, Object?>{
      'caseId': scenario,
      'runId': journey.runId,
      'attemptDirectory': output.path,
      'phases': phases,
      'scope':
          'signed TEST fixtures, controlled production runner and native posting; OS scheduling, real hours and store install are separate proofs',
    };
    Future<void> saveObservations() => File(
      '${output!.path}/observations.json',
    ).writeAsString(jsonEncode(proof));
    var primaryFailed = false;
    try {
      stage = 'prepare';
      await journey.prepare();
      attempted = 1;
      final peer = journey.alice;
      final baseline = await waitForProductionObservation<Map<String, Object?>>(
        'initial first-frame update check',
        const Duration(seconds: 60),
        () async {
          final value = await peer.command('se41.snapshot');
          return value['lastCheckAtMs'] is int ? value : null;
        },
      );
      proof['baselineSnapshot'] = baseline;
      final build = int.tryParse('${baseline['installedBuild']}');
      if (build == null || build < 0) {
        throw StateError('a numeric installed build is required');
      }
      if (!peer.isIosSimulator) {
        await peer.adb([
          'shell',
          'run-as',
          peer.packageName,
          'mkdir',
          '-p',
          'app_flutter/$updateCheckFixtureDirectory',
        ]);
      }
      var serial = 0;
      Future<String> flow(String name, String label) =>
          journey.flow(peer, name, '${serial++}-$label');
      Future<Map<String, Object?>> phase(
        String label,
        List<int> envelope,
        String kind,
        int sequence,
      ) async {
        stage = label;
        await peer.writeAppFile(
          '$updateCheckFixtureDirectory/$updateCheckFixtureEnvelope',
          Map<String, Object?>.from(jsonDecode(utf8.decode(envelope)) as Map),
        );
        final advanced = await peer.command('se41.advance_clock', {
          'seconds': 21601,
        });
        final checkAfter = advanced['clockMs'] as int;
        await flow('production_background', '$label-home');
        await flow('production_resume', '$label-resume');
        final snapshot =
            await waitForProductionObservation<Map<String, Object?>>(
              '$label completed update check',
              const Duration(seconds: 60),
              () async {
                final value = await peer.command('se41.snapshot');
                final checkedAt = value['lastCheckAtMs'];
                return value['kind'] == kind &&
                        value['sequence'] == sequence &&
                        checkedAt is int &&
                        checkedAt >= checkAfter
                    ? value
                    : null;
              },
            );
        final receipt = await flow(
          kind == 'hard' ? 'production_update_hard' : 'production_update_soft',
          '$label-ui',
        );
        phases.add({
          'label': label,
          'envelope': base64Encode(envelope),
          'snapshot': snapshot,
          'checkAfterMs': checkAfter,
          'flowReceipt': receipt,
        });
        await saveObservations();
        return snapshot;
      }

      Uint8List manifest(int sequence, bool hard, {int? issuedAt}) =>
          signedUpdateFixture(
            installedBuild: build,
            sequence: sequence,
            hard: hard,
            issuedAt: issuedAt,
          );
      int? nativeUid, nativeSdk;
      Future<List<Map<String, Object?>>> nativeCards(String label) async {
        nativeUid ??= int.parse(
          '${(await peer.adb(['shell', 'run-as', peer.packageName, 'id', '-u'])).stdout}'
              .trim(),
        );
        nativeSdk ??= int.parse(
          '${(await peer.adb(['shell', 'getprop', 'ro.build.version.sdk'])).stdout}'
              .trim(),
        );
        proof['androidSdk'] = nativeSdk;
        final notifications =
            '${(await peer.adb(['shell', 'dumpsys', 'notification', '--noredact'])).stdout}';
        final intents =
            '${(await peer.adb(['shell', 'dumpsys', 'activity', 'intents'])).stdout}';
        try {
          return parseProductionUpdateCheckNotifications(
            notificationDump: notifications,
            pendingIntentDump: intents,
            packageName: peer.packageName,
            uid: nativeUid!,
            sdk: nativeSdk!,
          );
        } on Object catch (error) {
          // Full system dumps contain unrelated private notifications. Retain
          // bounded structural diagnostics and hashes, not their raw content.
          await File('${output!.path}/native-parse-$label.json').writeAsString(
            jsonEncode({
              'stage': label,
              'sdk': nativeSdk,
              'errorType': '${error.runtimeType}',
              'notificationChars': notifications.length,
              'pendingIntentChars': intents.length,
              'notificationSha256': sha256
                  .convert(utf8.encode(notifications))
                  .toString(),
              'pendingIntentSha256': sha256
                  .convert(utf8.encode(intents))
                  .toString(),
              'managerHeader': notifications.contains(
                'Current Notification Manager state:',
              ),
              'rankingFooter': notifications.contains('Ranking Config:'),
              'pendingIntentRecord': notifications.contains(
                'PendingIntentRecord{',
              ),
              'binderProxy': notifications.contains('BinderProxy'),
            }),
          );
          rethrow;
        }
      }

      Future<void> nativeCase() async {
        stage = 'native-baseline';
        if (baseline['inCall'] != false) {
          throw StateError(
            'The canonical call source must observe no active call.',
          );
        }
        proof['baselineCards'] = await nativeCards('baseline');
        if ((proof['baselineCards'] as List).isNotEmpty) {
          throw StateError('The disposable fixture already has update cards.');
        }
        final soft = manifest(1, false);
        await peer.writeAppFile(
          '$updateCheckFixtureDirectory/$updateCheckFixtureEnvelope',
          Map<String, Object?>.from(jsonDecode(utf8.decode(soft)) as Map),
        );
        await peer.command('se41.advance_clock', {'seconds': 21601});
        proof['backgroundReceipt'] = await flow(
          'production_background',
          'native-home',
        );
        final checks = <Map<String, Object?>>[];
        proof['nativeChecks'] = checks;
        Future<Map<String, Object?>> runBackground(
          String label,
          int budget,
        ) async {
          stage = label;
          return peer.command('se41.background', {
            'reason': 'android_push',
            'budgetMs': budget,
          });
        }

        if (scenario == 'kx0025') {
          const statePath = 'files/se41_update_check_state.json';
          final mode =
              '${(await peer.adb(['shell', 'run-as', peer.packageName, 'stat', '-c', '%a', statePath])).stdout}'
                  .trim();
          if (!RegExp(r'^[0-7]{3,4}$').hasMatch(mode)) {
            throw StateError('Cannot preserve the exact fixture state mode.');
          }
          try {
            await peer.adb([
              'shell',
              'run-as',
              peer.packageName,
              'chmod',
              '000',
              statePath,
            ]);
            final unavailable = await runBackground('unreadable_state', 18000);
            checks.add({
              'label': 'unreadable_state',
              'result': unavailable,
              'cards': await nativeCards('unreadable_state'),
            });
            await saveObservations();
          } finally {
            await peer.adb([
              'shell',
              'run-as',
              peer.packageName,
              'chmod',
              mode,
              statePath,
            ]);
            final restored =
                '${(await peer.adb(['shell', 'run-as', peer.packageName, 'stat', '-c', '%a', statePath])).stdout}'
                    .trim();
            proof['stateModeRestored'] = restored == mode;
            await saveObservations();
            if (restored != mode) {
              throw StateError('Fixture state mode restoration failed.');
            }
          }
          final expired = await runBackground('expired_budget', 0);
          checks.add({
            'label': 'expired_budget',
            'result': expired,
            'cards': await nativeCards('expired_budget'),
          });
          await saveObservations();
        }
        Future<void> posted(String label, List<int> envelope, int id) async {
          await peer.writeAppFile(
            '$updateCheckFixtureDirectory/$updateCheckFixtureEnvelope',
            Map<String, Object?>.from(jsonDecode(utf8.decode(envelope)) as Map),
          );
          final after = (await peer.command('se41.snapshot'))['clockMs'];
          final result = await runBackground(label, 18000);
          final observed = <String, Object?>{
            'label': label,
            'envelope': base64Encode(envelope),
            'result': result,
            'checkAfterMs': after,
          };
          checks.add(observed);
          await saveObservations();
          final cards =
              await waitForProductionObservation<List<Map<String, Object?>>>(
                '$label single native card',
                const Duration(seconds: 20),
                () async {
                  final cards = await nativeCards(label);
                  return cards.length == 1 && cards.single['id'] == id
                      ? cards
                      : null;
                },
              );
          observed.addAll({
            'cards': cards,
            'snapshot': await peer.command('se41.snapshot'),
          });
          await saveObservations();
        }

        await posted(
          'eligible_soft',
          soft,
          updateCheckFixtureSoftNotificationId,
        );
        if (scenario == 'kx0027') {
          await posted(
            'hard_replaces_soft',
            manifest(2, true),
            updateCheckFixtureHardNotificationId,
          );
        }
        await saveObservations();
      }

      switch (scenario) {
        case 'kx0020':
          await phase('soft', manifest(1, false), 'soft', 1);
          proof['navigationReceipt'] = await flow(
            'production_update_soft_navigation',
            'soft-navigation',
          );
        case 'kx0021':
          await phase('hard', manifest(1, true), 'hard', 1);
        case 'kx0022':
          await phase('baseline_soft', manifest(1, false), 'soft', 1);
          final hard = manifest(2, true);
          await phase(
            'tampered_hard',
            tamperUpdateFixtureSignature(hard),
            'soft',
            1,
          );
          await phase('valid_hard', hard, 'hard', 2);
        case 'kx0023':
          await phase('newer_hard', manifest(2, true), 'hard', 2);
          await phase('stale_soft', manifest(1, false), 'hard', 2);
          await phase('latest_soft', manifest(3, false), 'soft', 3);
        case 'kx0024':
          await phase('old_issued', manifest(2, false, issuedAt: 1), 'soft', 2);
          await phase('older_sequence', manifest(1, true), 'soft', 2);
          await phase(
            'newer_sequence',
            manifest(3, true, issuedAt: 1),
            'hard',
            3,
          );
        case 'kx0026':
          await phase('soft', manifest(1, false), 'soft', 1);
          await phase('hard', manifest(2, true), 'hard', 2);
        case 'kx0028':
          await phase('testflight_hard', manifest(1, true), 'hard', 1);
          final file = File(
            '${await peer.dataContainer()}/Documents/'
            '$updateCheckFixtureDirectory/$updateCheckFixtureStoreOpen',
          );
          if (file.existsSync()) await file.delete();
          proof['storeTapReceipt'] = await flow(
            'production_update_open_store',
            'testflight-tap',
          );
          proof['storeTarget'] =
              await waitForProductionObservation<Map<String, Object?>>(
                'actual update action URL',
                const Duration(seconds: 20),
                () async {
                  if (!file.existsSync()) return null;
                  try {
                    return Map<String, Object?>.from(
                      jsonDecode(await file.readAsString()) as Map,
                    );
                  } on FormatException {
                    return null;
                  }
                },
              );
        case 'kx0025':
        case 'kx0027':
          await nativeCase();
        default:
          throw StateError('Registered case lacks a driver.');
      }
      proof.addAll(journey.provenance());
      stage = 'validate';
      final failures = validateProductionUpdateCheck(proof);
      await File(
        '${output.path}/oracle.json',
      ).writeAsString(jsonEncode({'failures': failures}));
      if (failures.isNotEmpty) throw StateError(failures.join('; '));
    } catch (error, stack) {
      primaryFailed = true;
      await File(
        '${output.path}/first-failure.txt',
      ).writeAsString('$stage\n$error\n$stack');
      rethrow;
    } finally {
      try {
        if (!primaryFailed) stage = 'restore';
        await journey.restore();
      } catch (error, stack) {
        await File(
          '${output.path}/cleanup-failure.txt',
        ).writeAsString('$error\n$stack');
        if (!primaryFailed) rethrow;
      }
    }
    stage = 'artifact';
    evidence = writeSimsArtifactEvidenceSync(
      directory: output,
      capabilityId: scenario,
      validatorIds: ['validateProductionUpdateCheck'],
      payload: {...proof, 'status': 'PASS'},
    );
  } catch (error, stack) {
    if (output != null) {
      final first = File('${output.path}/first-failure.txt');
      if (!first.existsSync()) {
        await first.writeAsString('$stage\n$error\n$stack');
      }
    }
  }
  stdout.writeln(
    'SIMS_RESULT_JSON=${jsonEncode(withProductionFailureBlocker({'status': evidence == null ? 'FAIL' : 'PASS', 'assertionsAttempted': attempted, 'artifactPresent': evidence != null, 'printOnly': false, 'exitCode': evidence == null ? 1 : 0, 'detail': evidence == null ? 'SE41 scenario failed; private evidence retained' : 'SE41 signed TEST fixture and UI observations', if (evidence != null) 'artifactEvidence': evidence.toJson()}))}',
  );
  exitCode = evidence == null ? 1 : 0;
}
