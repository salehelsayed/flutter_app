import 'dart:convert';
import 'dart:io';
import '../support/android_production_audio_call_evidence.dart';
import '../support/production_shared_xctest.dart';

const _journey = 'VC-015';
const _scenario = 'production.call.cross-platform-call';
const _knownGap =
    "KNOWN GAP [VC-015]: No phone acoustic-content/audibility producer or supported reciprocal physical iOS/Android campaign.";
const _selectors = <String, String>{
  'start':
      'RunnerUITests/VC205CallLifecycleUITests/testTapStartVoiceCallOnAlreadyRunningApp',
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

/// Independent existing platform controls only. Android RTP and iOS selector
/// success cannot be promoted to reciprocal cross-platform audible content.
List<String> validateRecordedControls(Map<String, Object?> input) {
  final failures = <String>[];
  final android = input['android'];
  if (android is! Map) {
    failures.add('existing Android production-call artifact required');
  } else {
    final artifact = Map<String, Object?>.from(android);
    final proof = artifact['runtimeProof'];
    final topology = proof is Map ? proof['topology'] : null;
    final validation = validateAndroidProductionAudioCallDurableArtifact(
      artifact,
      emulatorPair:
          topology is Map &&
          topology['callerKind'] == 'emulator' &&
          topology['calleeKind'] == 'emulator',
      physicalCaller:
          topology is Map &&
          topology['callerKind'] == 'physical' &&
          topology['calleeKind'] == 'emulator',
    );
    if (!validation.ok) failures.add(validation.detail);
  }
  for (final entry in _selectors.entries) {
    final value = input[entry.key];
    if (value is! Map) {
      failures.add('exact ${entry.key} XCTest output required');
    } else {
      failures.addAll(
        validateSharedXCTestReceipt(
          entry.value,
          value['summary'],
          value['tests'],
        ).map((failure) => '${entry.key}: $failure'),
      );
    }
  }
  return failures;
}

const _prerequisites = <String>[
  "Future execution owner resolves and pins only available authorized targets.",
  "Exact candidate source/configuration/artifact and owned fixture state/cleanup evidence.",
  "No AWS binding; future external test services use authorized Hetzner only.",
  "Actual Appium MCP/native campaign ownership is required for new OS/UI actions.",
  "Already compiled compatible physical-iOS XCTest product and certified data-preserving prepare/restore; never use the simulator adapter as a physical iOS driver.",
  "Existing Android production call artifact can establish only its strict structural/RTP/native-cleanup control.",
];
const _missingAssertions = <String>[
  "No phone acoustic-content/audibility producer or supported reciprocal physical iOS/Android campaign.",
  "A supplied control verdict must never count as execution or PASS of VC-015.",
];
