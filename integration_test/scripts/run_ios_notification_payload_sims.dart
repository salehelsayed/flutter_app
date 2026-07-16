#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

import '../support/ios_notification_payload_campaign.dart';
import 'notification_ios_payload_campaign.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--list-scenarios')) {
    stdout.writeln(iosNotificationPayloadScenario);
    return;
  }
  if (args.contains('--artifact-schema')) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'scenario': iosNotificationPayloadScenario,
        'validator': iosNotificationPayloadValidator,
        'requiredChecks': const <String>[
          'iosReceiver',
          'apnsDelivered',
          'nseStagingOn',
          'nse04P0WithStagingOn',
          'airplaneModeBeforeTap',
          'messageVisibleFromStagedEnvelope',
          'noRelayDrainBeforeVisibility',
          'networkRestored',
          'appTerminatedAfterCapture',
        ],
      }),
    );
    return;
  }

  final environment = Platform.environment;
  final result = await runIosNotificationPayloadCampaign(
    IosNotificationPayloadCampaignOptions(
      receiverDeviceId:
          _valueFor(args, '--receiver') ??
          _valueFor(args, '--device') ??
          environment['SIMS_IOS_PHYSICAL_DEVICE_ID'],
      prebuiltApplicationPath:
          _valueFor(args, '--application-binary') ??
          _valueFor(args, '--prebuilt-app') ??
          _valueFor(args, '--prebuilt-ipa') ??
          environment['SIMS_ARTIFACT_IOS_DEVICE_PRODUCTION'],
      stagingManifestPath:
          _valueFor(args, '--staging-manifest') ??
          environment['SIMS_IOS_NOTIFICATION_STAGING_MANIFEST'],
      xctestrunPath:
          _valueFor(args, '--xctestrun') ??
          environment['SIMS_IOS_NOTIFICATION_XCTESTRUN'],
      providerDriverPath:
          _valueFor(args, '--provider-driver') ??
          environment['SIMS_IOS_NOTIFICATION_PROVIDER_DRIVER'],
      providerRequestPath:
          _valueFor(args, '--provider-request') ??
          environment['SIMS_IOS_NOTIFICATION_PROVIDER_REQUEST'],
      relayTarget:
          _valueFor(args, '--relay-target') ??
          environment['SIMS_NOTIFICATION_RELAY_TARGET'],
      relayKeyPath:
          _valueFor(args, '--relay-key') ??
          environment['SIMS_NOTIFICATION_RELAY_KEY'],
      proofDirectory:
          _valueFor(args, '--artifact-dir') ??
          environment['SIMS_PROOF_DIRECTORY'] ??
          'build/sims/proofs/$iosNotificationPayloadCapabilityId',
      verbose: args.contains('--verbose'),
    ),
  );
  stdout.writeln('SIMS_RESULT_JSON=${jsonEncode(result.json)}');
  exitCode = result.processExitCode;
}

String? _valueFor(List<String> args, String name) {
  for (var index = 0; index < args.length; index += 1) {
    final argument = args[index];
    if (argument == name && index + 1 < args.length) {
      return args[index + 1];
    }
    if (argument.startsWith('$name=')) {
      return argument.substring(name.length + 1);
    }
  }
  return null;
}
