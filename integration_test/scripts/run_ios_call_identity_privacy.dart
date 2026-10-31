import 'dart:convert';
import 'dart:io';
import '../support/production_shared_xctest.dart';

const _journey = 'VC-010';
const _scenario = 'production.call.ios-call-identity';
const _knownGap =
    "KNOWN GAP [VC-010]: No existing iPhone system caller-name/fallback and raw-identifier/handle-disclosure observation producer.";
const _selectors = <String, String>{
  'answer':
      'RunnerUITests/VC205CallLifecycleUITests/testAnswerAlreadyPresentedSystemCall',
};

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

/// Checks only existing named native XCTest result output. It neither runs an
/// iPhone nor supplies the missing lifecycle/identity/system-control oracle.
List<String> validateRecordedControls(Map<String, Object?> input) {
  final failures = <String>[];
  for (final entry in _selectors.entries) {
    final raw = input[entry.key];
    if (raw is! Map) {
      failures.add('missing recorded ${entry.key} XCTest output');
      continue;
    }
    failures.addAll(
      validateSharedXCTestReceipt(
        entry.value,
        raw['summary'],
        raw['tests'],
      ).map((failure) => '${entry.key}: $failure'),
    );
  }
  return failures;
}

const _prerequisites = <String>[
  "Future execution owner resolves and pins only available authorized targets.",
  "Exact candidate source/configuration/artifact and owned fixture state/cleanup evidence.",
  "No AWS binding; future external test services use authorized Hetzner only.",
  "Actual Appium MCP/native campaign ownership is required for new OS/UI actions.",
  "Already compiled compatible physical-iOS XCTest product and certified data-preserving prepare/restore; never use the simulator adapter as a physical iOS driver.",
];
const _missingAssertions = <String>[
  "No existing iPhone system caller-name/fallback and raw-identifier/handle-disclosure observation producer.",
  "A supplied control verdict must never count as execution or PASS of VC-010.",
];
