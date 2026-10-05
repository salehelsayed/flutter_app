import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_shared_xctest_criteria.dart';
import '../support/ios_xctestrun_relocator.dart';
import '../support/production_shared_xctest.dart';

const _scenario = 'production.shared_xctest';
const _profile = 'ios.device.production';

/// The one RunnerUITests selector that launches no app and changes no device
/// state (`NotificationTapUITests.swift:156`).
const _selector =
    'RunnerUITests/NotificationTapUITests/testAirplaneToggleStateDecoderContract';

/// Wave 4 shared-XCTest caller: one centrally built and attested physical-iOS
/// app/XCTest bundle serves two selector runs through `test-without-building`
/// with independent fixtures and results. A changed bundle and a wrong input
/// digest are rejected before any xcodebuild launch. Original fresh-build
/// routes are untouched.
Future<void> main(List<String> arguments) async {
  if (arguments.contains('--list-scenarios')) {
    stdout.writeln(_scenario);
    return;
  }
  Directory? output;
  SimsArtifactEvidence? evidence;
  var attempts = 0;
  try {
    final env = Platform.environment;
    String required(String name) {
      final value = env[name];
      if (value == null || value.isEmpty) throw StateError('missing $name');
      return value;
    }

    output = await (await Directory(
      required('SIMS_PROOF_DIRECTORY'),
    ).absolute.create(recursive: true)).createTemp('attempt-');
    final bundle = Directory(
      required('SIMS_ARTIFACT_IOS_DEVICE_PRODUCTION'),
    ).absolute;
    final attestation = File('${bundle.parent.path}/attestation.json');
    final inputDigest = required('SIMS_ARTIFACT_INPUT_DIGEST');
    final artifactDigest = required('SIMS_ARTIFACT_SHA256');
    final device = required('SIMS_IOS_PHYSICAL_DEVICE_ID');
    final calls = <String>[];
    Future<ProcessResult> counted(String executable, List<String> args) {
      calls.add(
        executable == 'xcodebuild'
            ? 'xcodebuild ${args.isEmpty ? '' : args.first}'
            : executable,
      );
      // Like the other attested-bundle callers, declare that this xcodebuild
      // only runs tests; the SIMS build guard then allows exactly
      // test-without-building and still rejects any build.
      return Process.run(
        executable,
        args,
        environment: executable == 'xcodebuild'
            ? const {'SIMS_CHILD_BUILDS_FORBIDDEN': '1'}
            : null,
      );
    }

    int xcodebuildCalls() =>
        calls.where((c) => c.startsWith('xcodebuild')).length;
    final manifest = Map<String, Object?>.from(
      jsonDecode(
            await File('${bundle.path}/bundle_manifest.json').readAsString(),
          )
          as Map,
    );
    final proof = <String, Object?>{
      'profileId': _profile,
      'selector': validatedIosUiTestSelector(_selector),
      'deviceId': device,
      'inputDigest': inputDigest,
      'artifactDigest': artifactDigest,
      'sharedBuild': {
        'logicalBuildCount': manifest['logicalBuildCount'],
        'centralCompileCommands': manifest['centralCompileCommands'],
        'childBuildCount': manifest['childBuildCount'],
      },
      // scripts/full_suite_adapters.py:224-260: every original full.xctest
      // check runs its own build-for-testing before one test-without-building.
      'originalRoute': {
        'buildsPerSelectorRun': 1,
        'source': 'scripts/full_suite_adapters.py build-for-testing per check',
      },
    };
    final rejections = <Map<String, Object?>>[];
    proof['rejections'] = rejections;
    Future<void> persist() => File(
      '${output!.path}/observations.json',
    ).writeAsString(jsonEncode({...proof, 'processCalls': calls}));

    // 1. Provenance rejection, before any xcodebuild launch.
    Future<void> expectRejected(
      String name,
      Future<Object?> Function() open,
    ) async {
      attempts++;
      final before = xcodebuildCalls();
      String? error;
      try {
        await open();
      } on StateError catch (e) {
        error = e.message;
      }
      rejections.add({
        'case': name,
        'rejected': error != null,
        'error': error,
        'xcodebuildCalls': xcodebuildCalls() - before,
      });
      await persist();
    }

    final tampered = Directory('${output.path}/tampered.bundle');
    final copy = await Process.run('cp', ['-Rp', bundle.path, tampered.path]);
    if (copy.exitCode != 0) {
      throw StateError('cannot copy bundle: ${copy.stderr}');
    }
    await File(
      '${tampered.path}/bundle_manifest.json',
    ).writeAsString(' ', mode: FileMode.append);
    await expectRejected(
      'changed bundle bytes',
      () => ProductionSharedXCTest.open(
        bundle: tampered,
        attestationFile: attestation,
        profileId: _profile,
        expectedInputDigest: inputDigest,
        expectedArtifactDigest: artifactDigest,
        process: counted,
      ),
    );
    await tampered.delete(recursive: true);
    await expectRejected(
      'wrong input digest',
      () => ProductionSharedXCTest.open(
        bundle: bundle,
        attestationFile: attestation,
        profileId: _profile,
        expectedInputDigest: '0' * 64,
        expectedArtifactDigest: artifactDigest,
        process: counted,
      ),
    );

    // 2. One open, two independent selector runs from the same products.
    final openTimer = Stopwatch()..start();
    final shared = await ProductionSharedXCTest.open(
      bundle: bundle,
      attestationFile: attestation,
      profileId: _profile,
      expectedInputDigest: inputDigest,
      expectedArtifactDigest: artifactDigest,
      process: counted,
    );
    proof['openMs'] = openTimer.elapsedMilliseconds;
    final runs = <Map<String, Object?>>[];
    proof['runs'] = runs;
    final exact = validatedIosUiTestSelector(_selector);
    for (final fixtureId in ['shared_a', 'shared_b']) {
      attempts++;
      final timer = Stopwatch()..start();
      File marker(Directory d) => File('${d.path}/fixture-$fixtureId.json');
      final receipt = await shared.runSelector(
        selector: _selector,
        deviceId: device,
        fixtureId: fixtureId,
        output: output,
        prepare: (d) async {
          await marker(d).writeAsString(jsonEncode({'fixtureId': fixtureId}));
          return {'MKNOON_SHARED_XCTEST_FIXTURE': fixtureId};
        },
        verify: (d) async {
          final file = marker(d);
          final bound =
              file.existsSync() &&
              (jsonDecode(await file.readAsString()) as Map)['fixtureId'] ==
                  fixtureId &&
              d.listSync().length == 1;
          return {
            'fixtureId': fixtureId,
            'selector': exact,
            'status': bound ? 'PASS' : 'FAIL',
          };
        },
        restore: (d) async {
          final file = marker(d);
          if (file.existsSync()) await file.delete();
          return {
            'status': 'PASS',
            'fixtureId': fixtureId,
            'exactRestorationVerified': d.listSync().isEmpty,
          };
        },
      );
      final attempt = Directory(
        (receipt['resultBundle']! as String).replaceFirst(
          RegExp(r'/result\.xcresult$'),
          '',
        ),
      );
      runs.add({
        ...receipt,
        'selectorMs': timer.elapsedMilliseconds,
        'cleanup': jsonDecode(
          await File('${attempt.path}/cleanup.json').readAsString(),
        ),
      });
      await persist();
    }
    proof['xcodebuildActions'] = [
      for (final c in calls)
        if (c.startsWith('xcodebuild')) c,
    ];
    await persist();
    final failures = validateProductionSharedXCTest(proof);
    await File(
      '${output.path}/oracle.json',
    ).writeAsString(jsonEncode({'failures': failures}));
    if (failures.isNotEmpty) throw StateError(failures.join('; '));
    evidence = writeSimsArtifactEvidenceSync(
      directory: output,
      capabilityId: _scenario,
      validatorIds: ['validateProductionSharedXCTest'],
      payload: {...proof, 'status': 'PASS'},
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
    'SIMS_RESULT_JSON=${jsonEncode({'status': passed ? 'PASS' : 'FAIL', 'assertionsAttempted': attempts, 'artifactPresent': passed, 'printOnly': false, 'exitCode': passed ? 0 : 1, 'detail': passed ? 'production shared XCTest passed' : 'production shared XCTest failed', if (evidence != null) 'artifactEvidence': evidence.toJson()})}',
  );
  exitCode = passed ? 0 : 1;
}
