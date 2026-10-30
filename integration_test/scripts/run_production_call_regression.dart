import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/debug/production_journeys/sims_runtime_protocol.dart';

import 'android_production_audio_call_campaign.dart';
import 'evaluate_production_journey_gap_receipt.dart' as recorded;

const _alwaysRelayNegative = 'production.call.always-relay-negative';

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--list-scenarios') {
    stdout.writeln(
      [...productionCallRegressionJourneys, _alwaysRelayNegative].join('\n'),
    );
    return;
  }
  if (arguments.length >= 2 &&
      arguments.first == '--scenario' &&
      arguments[1] == _alwaysRelayNegative) {
    await _assertRecordedAlwaysRelay(arguments.skip(2).toList());
    return;
  }
  if (arguments.length != 2 ||
      arguments.first != '--scenario' ||
      !productionCallRegressionJourneys.contains(arguments.last)) {
    stderr.writeln('An exact registered call regression scenario is required.');
    exitCode = 64;
    return;
  }
  final result = await runAndroidProductionAudioCallCampaign(
    devices: (Platform.environment['RELIABILITY_MULTI_DEVICE_IDS'] ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(),
    artifactPath:
        Platform.environment['SIMS_ARTIFACT_ANDROID_E2E_PRODUCTION_CALL_LOCAL'],
    regressionScenario: arguments.last,
  );
  stdout.writeln('SIMS_RESULT_JSON=${jsonEncode(result.json)}');
  exitCode = result.processExitCode;
}

/// The existing exact VC-023 evaluator checks saved toggle, native relay pair,
/// effective/restored owned TURN fault, no direct fallback, original terminal
/// deadline and a fresh restored call. It does not gather any observation.
/// kx0030 above keeps its original executable campaign and narrower assertion
/// scope. A supplied receipt is never promoted to a new native producer.
Future<void> _assertRecordedAlwaysRelay(List<String> arguments) async {
  const gap =
      'KNOWN GAP [VC-023]: existing kx0030 proves saved preference/copy on a forced-relay build; full saved-preference selected-media, unavailable TURN/no direct fallback and restored-call producer is absent.';
  bool? recordedPassed;
  if (arguments.isNotEmpty) {
    if (arguments.length != 6 ||
        arguments[0] != '--source' ||
        arguments[2] != '--receipt' ||
        arguments[4] != '--output') {
      stderr.writeln(
        'Use --scenario $_alwaysRelayNegative [--source <full-candidate-revision> --receipt <VC-023.json> --output <recorded-verdict.json>]',
      );
      exitCode = 64;
      return;
    }
    try {
      final receipt = jsonDecode(await File(arguments[3]).readAsString());
      if (receipt is! Map || receipt['journeyId'] != 'VC-023') {
        throw const FormatException('exact VC-023 saved receipt required');
      }
      await recorded.main(arguments);
      recordedPassed = exitCode == 0;
    } on Object {
      recordedPassed = false;
    }
  }
  final failed = recordedPassed == false;
  stdout.writeln(
    'SIMS_RESULT_JSON=${jsonEncode(<String, Object?>{
      'status': failed ? 'FAIL' : 'BLOCKED',
      'blocker': failed ? 'test' : 'missingDriver',
      'assertionsAttempted': failed ? 1 : 0,
      'artifactPresent': false,
      'printOnly': false,
      'exitCode': failed ? 1 : 78,
      'scenario': _alwaysRelayNegative,
      'journeyId': 'VC-023',
      'detail': gap,
      'recordedControlEvaluated': recordedPassed != null,
      'recordedControlPassed': recordedPassed,
      'nativeExecutedByThisCommand': false,
      'qualifyingNativeJourneyWritten': false,
      'prerequisites': <String>['Exact default-policy candidate and installed artifact; no forced-relay build substituted for the saved preference.', 'Existing actual Appium MCP/native evidence with effective owned TURN fault, unchanged signaling and exact restoration.', 'No AWS binding; future external service use is Hetzner-only.', 'Available pinned targets and the existing full VC-023 saved-observation criteria; no new app observer hook.'],
    })}',
  );
  exitCode = failed ? 1 : 78;
}
