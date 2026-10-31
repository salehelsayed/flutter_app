import 'dart:convert';
import 'dart:io';
import '../../tool/sims/production_call_back_criteria.dart';

const _journey = 'VC-020';
const _scenario = 'production.call.call-native-permission';
const _knownGap =
    "KNOWN GAP [VC-020]: Existing Android microphone-denial callback control does not join subsequent OS grant, notification denial/grant/fallback and capture/signaling ownership.";
const _controlCase = 'kx0008';

// This is a saved-control assertion entrypoint, not a native producer. Even a
// valid supplied control cannot satisfy the named missing journey. The default
// path remains blocked; no target availability, execution or app hook is inferred.

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--list-scenarios') {
    stdout.writeln(_scenario);
    return;
  }
  List<String>? failures;
  if (arguments.isNotEmpty) {
    if (arguments.length != 2 ||
        arguments.first != '--assert-existing-control') {
      stderr.writeln(
        'Usage: --list-scenarios | --assert-existing-control <saved-control.json>',
      );
      exitCode = 64;
      return;
    }
    try {
      final decoded = jsonDecode(await File(arguments.last).readAsString());
      failures = decoded is Map
          ? validateRecordedControls(Map<String, Object?>.from(decoded))
          : ['saved control must be an object'];
    } on Object {
      failures = ['saved control unreadable or malformed'];
    }
  }
  final failed = failures != null && failures.isNotEmpty;
  final result = <String, Object?>{
    'status': failed ? 'FAIL' : 'BLOCKED',
    'blocker': failed ? 'test' : 'missingDriver',
    'assertionsAttempted': failed ? 1 : 0,
    'artifactPresent': false,
    'printOnly': false,
    'exitCode': failed ? 1 : 78,
    'detail': _knownGap,
    'journeyId': _journey,
    'scenario': _scenario,
    'nativeExecutedByThisCommand': false,
    'recordedControlEvaluated': failures != null,
    'recordedControlFailures': failures ?? const <String>[],
    'qualifyingNativeJourneyWritten': false,
    'prerequisites': _prerequisites,
    'missingAssertions': _missingAssertions,
  };
  stdout.writeln('SIMS_RESULT_JSON=${jsonEncode(result)}');
  exitCode = failed ? 1 : 78;
}

/// Reuses the real existing callback validator, including its bound baseline
/// artifact and native raw capture/keyguard/process evidence checks. The case
/// discriminator is fixed so a different passing callback cannot substitute.
List<String> validateRecordedControls(Map<String, Object?> input) => [
  if (input['caseId'] != _controlCase) 'exact $_controlCase control required',
  ...validateProductionCallBack(input),
];
const _prerequisites = <String>[
  "Future execution owner resolves and pins only available authorized targets.",
  "Exact candidate source/configuration/artifact and owned fixture state/cleanup evidence.",
  "No AWS binding; future external test services use authorized Hetzner only.",
  "Actual Appium MCP/native campaign ownership is required for new OS/UI actions.",
  "Existing exact kx0008 proof and its actual bound baseline/evidence files, as checked by validateProductionCallBack.",
];
const _missingAssertions = <String>[
  "Existing Android microphone-denial callback control does not join subsequent OS grant, notification denial/grant/fallback and capture/signaling ownership.",
  "A supplied control verdict must never count as execution or PASS of VC-020.",
];
