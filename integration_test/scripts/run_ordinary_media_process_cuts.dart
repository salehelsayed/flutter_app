import 'dart:convert';
import 'dart:io';

import 'evaluate_production_journey_gap_receipt.dart' as recorded;

const _journey = 'MEDIA-018';
const _scenario = 'production.media.ordinary-media-process-cuts';
const _knownGap =
    "KNOWN GAP [MEDIA-018]: Existing cut helper and exact validator cover held durable upload/download process cuts, but no joined owner produces all native full-content recovery and exactly-once observations. The saved evaluator does not stop a process or render media.";

/// Reuses the existing exact criterion AND its full-file/raw-evidence checks.
/// No receipt declaration is a producer. A supplied valid recorded assertion
/// leaves this missing native journey blocked, never native PASS.
Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--list-scenarios') {
    stdout.writeln(_scenario);
    return;
  }
  bool? controlPassed;
  if (arguments.isNotEmpty) {
    if (arguments.length != 6 ||
        arguments[0] != '--source' ||
        arguments[2] != '--receipt' ||
        arguments[4] != '--output') {
      stderr.writeln(
        'Usage: --list-scenarios | --source <full-candidate-revision> --receipt <saved-case.json> --output <recorded-verdict.json>',
      );
      exitCode = 64;
      return;
    }
    try {
      final decoded = jsonDecode(await File(arguments[3]).readAsString());
      if (decoded is! Map ||
          decoded['journeyId'] != _journey ||
          decoded['executionStatus'] != 'complete') {
        throw const FormatException('exact complete journey receipt required');
      }
      // The evaluator binds candidate source and hashes actual MCP artifacts.
      // MEDIA-018 also reads each real cutProofFile before applying its exact
      // actor/device/package/held-partial-transfer and reopen assertions.
      await recorded.main(arguments);
      controlPassed = exitCode == 0;
    } on Object {
      controlPassed = false;
    }
  }
  final failed = controlPassed == false;
  stdout.writeln(
    'SIMS_RESULT_JSON=${jsonEncode(<String, Object?>{
      'status': failed ? 'FAIL' : 'BLOCKED',
      'blocker': failed ? 'test' : 'missingDriver',
      'assertionsAttempted': failed ? 1 : 0,
      'artifactPresent': false,
      'printOnly': false,
      'exitCode': failed ? 1 : 78,
      'journeyId': _journey,
      'scenario': _scenario,
      'detail': _knownGap,
      'recordedControlEvaluated': controlPassed != null,
      'recordedControlPassed': controlPassed,
      'nativeExecutedByThisCommand': false,
      'qualifyingNativeJourneyWritten': false,
      'scope': 'existing host evaluator of supplied complete MCP/native observations and actual files',
      'prerequisites': <String>['Future execution owner pins only available authorized targets and exact candidate artifacts.', 'Actual Appium MCP/native campaign owner supplies complete observations, raw evidence and owned-state restoration.', 'Native-open fields are supplied observations; the evaluator does not collect them.', 'The processed-send comparison is NOT RUN without a genuine blob:encrypt sender receipt; do not equate a raw camera file with processed input.', 'No AWS binding; future external services use authorized Hetzner only.'],
      'missingAssertions': <String>[_knownGap],
    })}',
  );
  exitCode = failed ? 1 : 78;
}
