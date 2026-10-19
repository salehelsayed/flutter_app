import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/debug/production_journeys/sims_runtime_protocol.dart';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_contact_delete_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_journey_peer.dart';
import '../support/production_sims_result.dart';

String parseContactFixtureLocales(String output, String package, int user) {
  final match = RegExp(
    '^Locales for ${RegExp.escape(package)} for user $user are '
    r'\[([A-Za-z0-9,-]*)\]$',
  ).firstMatch(output.trim());
  if (match == null) {
    throw const FormatException('Exact per-app locale readback required.');
  }
  return match.group(1)!;
}

Map<String, String> contactDeleteFlowValues(
  Map<String, Object?> translations,
  String scenario,
  String peerId,
) {
  final body = (translations['delete_contact_body'] as String).replaceAll(
    '{username}',
    'FixtureAlpha',
  );
  final title =
      translations[scenario == 'kx0011'
              ? 'orbit_delete_chat'
              : 'conversation_delete_chat']
          as String;
  String exact(String value) => '^${RegExp.escape(value)}\$';
  return {
    'PEER_ID': peerId,
    // Android exposes the title and body as one accessibility label.
    'DIALOG_LABEL': '(?-i)${exact('$title\n$body')}',
    'CANCEL': exact(translations['btn_cancel'] as String),
    'OPTIONS': exact(translations['action_conversation_options'] as String),
    'DELETE_ACTION': exact(
      translations[scenario == 'kx0011'
              ? 'orbit_delete_action'
              : 'conversation_delete_chat_action']
          as String,
    ),
  };
}

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--list-scenarios') {
    stdout.write('${productionContactDeleteJourneys.join('\n')}\n');
    return;
  }
  Directory? output;
  SimsArtifactEvidence? evidence;
  var stage = 'arguments';
  var attempted = 0;
  try {
    if (arguments.length != 2 ||
        arguments.first != '--scenario' ||
        !productionContactDeleteJourneys.contains(arguments.last)) {
      throw const FormatException('An exact registered SE47 case is required.');
    }
    final id = arguments.last;
    final root = Platform.environment['SIMS_PROOF_DIRECTORY'];
    if (root == null || root.isEmpty) {
      throw StateError('Missing proof directory.');
    }
    output = await (await Directory(
      root,
    ).absolute.create(recursive: true)).createTemp('attempt-');
    final journey = ProductionAndroidJourney.fromEnvironment(id, output);
    final proof = <String, Object?>{
      'caseId': id,
      'runId': journey.runId,
      'attemptDirectory': output.path,
      'scope':
          'owned fixture contacts; actual Maestro deletion, SQL abort/rollback and restart; confirmation action retains current English Delete label',
    };
    Future<void> save() async => File(
      '${output!.path}/observations.json',
    ).writeAsString(jsonEncode(proof));
    String? originalLocales;
    int? user;
    var primaryFailed = false;
    Future<String> locales() async => parseContactFixtureLocales(
      '${(await journey.alice.adb(['shell', 'cmd', 'locale', 'get-app-locales', journey.alice.packageName, '--user', '$user'])).stdout}',
      journey.alice.packageName,
      user!,
    );
    Future<void> setLocales(String value) async {
      await journey.alice.adb([
        'shell',
        'cmd',
        'locale',
        'set-app-locales',
        journey.alice.packageName,
        '--user',
        '$user',
        if (value.isNotEmpty) ...['--locales', value],
      ]);
      if (await locales() != value) {
        throw StateError('Per-app locale transition failed.');
      }
    }

    try {
      stage = 'prepare';
      await journey.prepare();
      attempted = 1;
      user = int.parse(
        '${(await journey.alice.adb(['shell', 'am', 'get-current-user'])).stdout}'
            .trim(),
      );
      originalLocales = await locales();
      final language = contactDeleteLanguage(id);
      await setLocales(language);
      await journey.alice.command('se47.seed');
      journey.alice = await journey.reopen(journey.alice);
      final translations = Map<String, Object?>.from(
        jsonDecode(await File('lib/l10n/app_$language.arb').readAsString())
            as Map,
      );
      final body = (translations['delete_contact_body'] as String).replaceAll(
        '{username}',
        'FixtureAlpha',
      );
      proof['expectedBody'] = body;
      final initial = await journey.alice.command('se47.snapshot');
      final peerA = initial['peerA'] as String;
      final values = contactDeleteFlowValues(translations, id, peerA);
      var serial = 0;
      Future<String> flow(String name, String label) =>
          journey.flow(journey.alice, name, '${serial++}-$label', values);
      if (id != 'kx0011') {
        await journey.flow(
          journey.alice,
          'production_direct_open',
          'open-fixture-a',
          {'PEER_ID': peerA},
        );
      }
      final dialogFlow = id == 'kx0011'
          ? 'production_contact_orbit_dialog'
          : 'production_contact_conversation_dialog';
      stage = 'dialog';
      proof['dialogReceipt'] = await flow(dialogFlow, 'dialog');
      proof['before'] =
          await waitForProductionObservation<Map<String, Object?>>(
            'actual localized contact dialog',
            const Duration(seconds: 20),
            () async {
              final snapshot = await journey.alice.command('se47.snapshot');
              return (snapshot['dialog'] as List).length == 1 ? snapshot : null;
            },
          );
      await save();
      if (id == 'kx0010' || id == 'kx0011') {
        stage = 'triggered-deletion';
        proof['abortTriggerInstalled'] =
            (await journey.alice.command('se47.abort_contact_delete', {
              'enabled': true,
            }))['enabled'] ==
            true;
        proof['abortedConfirmReceipt'] = await flow(
          'production_contact_confirm',
          'abort-confirm',
        );
        proof['afterAbort'] =
            await waitForProductionObservation<Map<String, Object?>>(
              'exact fixture SQL abort',
              const Duration(seconds: 30),
              () async {
                final snapshot = await journey.alice.command('se47.snapshot');
                return (snapshot['events'] as List).any(
                      (event) => event is Map && event['fixtureAbort'] == true,
                    )
                    ? snapshot
                    : null;
              },
            );
        await save();
        proof['abortTriggerRemoved'] =
            (await journey.alice.command('se47.abort_contact_delete', {
              'enabled': false,
            }))['enabled'] ==
            false;
        stage = 'successful-deletion';
        proof['retryDialogReceipt'] = await flow(dialogFlow, 'retry-dialog');
        proof['confirmReceipt'] = await flow(
          'production_contact_confirm',
          'confirm',
        );
        proof['afterDelete'] =
            await waitForProductionObservation<Map<String, Object?>>(
              'committed contact deletion',
              const Duration(seconds: 30),
              () async {
                final snapshot = await journey.alice.command('se47.snapshot');
                return snapshot['contactA'] == false ? snapshot : null;
              },
            );
        await save();
        stage = 'restart';
        await journey.killOwnedProcess(journey.alice);
        proof['verifiedProcessDeath'] = true;
        journey.alice = await journey.reopen(journey.alice);
        proof['afterRestart'] = await journey.alice.command('se47.snapshot');
      } else {
        stage = 'cancel';
        proof['cancelReceipt'] = await flow(
          'production_contact_cancel',
          'cancel',
        );
        proof['afterCancel'] = await journey.alice.command('se47.snapshot');
      }
      await save();
    } catch (error, stack) {
      primaryFailed = true;
      await File(
        '${output.path}/first-failure.txt',
      ).writeAsString('$stage\n$error\n$stack');
      rethrow;
    } finally {
      final cleanupFailures = <Object>[];
      if (originalLocales != null) {
        try {
          await setLocales(originalLocales);
          proof['localeRestored'] = true;
          await save();
        } catch (error) {
          cleanupFailures.add(error);
        }
      }
      try {
        await journey.restore();
      } catch (error) {
        cleanupFailures.add(error);
      }
      if (cleanupFailures.isNotEmpty) {
        await File(
          '${output.path}/cleanup-failure.txt',
        ).writeAsString(cleanupFailures.join('\n'));
        if (!primaryFailed) {
          throw StateError('Contact fixture restoration failed.');
        }
      }
    }
    proof.addAll(journey.provenance());
    stage = 'validate';
    final failures = validateProductionContactDelete(proof);
    await File(
      '${output.path}/oracle.json',
    ).writeAsString(jsonEncode({'failures': failures}));
    if (failures.isNotEmpty) throw StateError(failures.join('; '));
    evidence = writeSimsArtifactEvidenceSync(
      directory: output,
      capabilityId: id,
      validatorIds: ['validateProductionContactDelete'],
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
    'SIMS_RESULT_JSON=${jsonEncode(withProductionFailureBlocker({'status': evidence == null ? 'FAIL' : 'PASS', 'assertionsAttempted': attempted, 'artifactPresent': evidence != null, 'printOnly': false, 'exitCode': evidence == null ? 1 : 0, 'detail': evidence == null ? 'SE47 case failed; private evidence retained' : 'SE47 actual contact deletion/dialog observations', if (evidence != null) 'artifactEvidence': evidence.toJson()}))}',
  );
  exitCode = evidence == null ? 1 : 0;
}
