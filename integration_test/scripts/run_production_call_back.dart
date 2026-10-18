import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/debug/production_journeys/sims_runtime_protocol.dart';

import 'android_production_audio_call_campaign.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--list-scenarios') {
    stdout.writeln(productionCallBackJourneys.join('\n'));
    return;
  }
  if (arguments.length != 2 ||
      arguments.first != '--scenario' ||
      !productionCallBackJourneys.contains(arguments.last)) {
    stderr.writeln('An exact registered callback scenario is required.');
    exitCode = 64;
    return;
  }
  final devices = (Platform.environment['RELIABILITY_MULTI_DEVICE_IDS'] ?? '')
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final result = await runAndroidProductionAudioCallCampaign(
    devices: devices,
    artifactPath:
        Platform.environment['SIMS_ARTIFACT_ANDROID_E2E_PRODUCTION_CALL_LOCAL'],
    regressionScenario: arguments.last,
  );
  stdout.writeln('SIMS_RESULT_JSON=${jsonEncode(result.json)}');
  exitCode = result.processExitCode;
}
