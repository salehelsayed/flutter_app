#!/usr/bin/env dart

import 'dart:io';

import 'android_group_media_reliability_controller.dart';
import 'group_media_ios_background_recovery.dart';
import 'group_media_reliability_criteria.dart';
import 'group_media_reliability_runner_contract.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--list-scenarios') {
    // `dart run` can print build-hook progress without a trailing newline.
    // Keep every machine-readable scenario on its own exact line.
    stdout.writeln();
    for (final scenario in groupMediaReliabilityScenarioIds) {
      stdout.writeln(scenario);
    }
    return;
  }

  final result = await runGroupMediaReliabilityRunner(
    arguments: arguments,
    environment: Platform.environment,
    executeScenario: _executeScenario,
  );
  // Keep the sole structured sentinel separate from build-hook progress.
  stdout.writeln();
  stdout.writeln(result.sentinel);
  exitCode = result.exitCode;
}

Future<Map<String, Object?>> _executeScenario(
  GroupMediaReliabilityRunContext context,
) async {
  if (context.scenario == groupMediaForegroundRetryAclRoundtripScenario) {
    return executeAndroidGroupMediaReliabilityScenario(context);
  }

  final fixtureDriverPath = Platform
      .environment[groupMediaIosFixtureDriverEnvironment]
      ?.trim();
  if (fixtureDriverPath == null || fixtureDriverPath.isEmpty) {
    throw const GroupMediaReliabilityBlocked(
      'missingDriver',
      'SIMS_GROUP_MEDIA_IOS_FIXTURE_DRIVER must name the independent physical '
          'relay/SQLCipher fixture observer.',
    );
  }
  final sender = context.roles['sender'];
  final receiver = context.roles['receiver'];
  final androidCompanion = context.androidCompanionArtifact;
  if (sender == null || receiver == null) {
    throw const GroupMediaReliabilityBlocked(
      'harness',
      'The iOS group-media scenario requires both explicit role bindings.',
    );
  }
  if (androidCompanion == null ||
      androidCompanion.profile != groupMediaReliabilityAndroidBuildProfile) {
    throw const GroupMediaReliabilityBlocked(
      'missingArtifact',
      'The iOS row requires the dedicated Android companion artifact.',
    );
  }
  try {
    return await GroupMediaIosBackgroundRecoveryController(
      options: GroupMediaIosBackgroundRecoveryOptions(
        runId: context.runId,
        preparedBundle: Directory(context.preparedArtifact.path),
        proofDirectory: context.proofDirectory,
        fixtureDriver: File(fixtureDriverPath),
        senderDeviceId: sender.deviceId,
        receiverDeviceId: receiver.deviceId,
        inheritedEnvironment: Platform.environment,
        androidCompanionArtifact: File(androidCompanion.path),
        androidCompanionArtifactSha256: androidCompanion.sha256Digest,
        buildGuardLog: context.buildGuardLog,
      ),
    ).run();
  } on GroupMediaIosBackgroundRecoveryBlocked catch (error) {
    throw GroupMediaReliabilityBlocked(error.blocker, error.detail);
  } on GroupMediaIosBackgroundRecoveryFailure catch (error) {
    throw StateError(error.detail);
  }
}
