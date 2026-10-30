import 'dart:convert';
import 'dart:io';
import '../support/android_production_audio_call_evidence.dart';

const _journey = 'VC-014';
const _scenario = 'production.call.background-call-os-delivery';
const _knownGap =
    "KNOWN GAP [VC-014]: No joined provider acceptance, suspended/process-terminated/locked OS wake and answer/media producer for each available shipped platform.";

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

/// Existing strict Android artifact assertions retain run/nonces, installed
/// artifact, both endpoint bindings, RTP controls and native cleanup. They do
/// not establish suspended/terminated/locked delivery or provider acceptance.
List<String> validateRecordedControls(Map<String, Object?> input) {
  final proof = input['runtimeProof'];
  if (proof is! Map) return ['existing production call runtime proof required'];
  final topology = proof['topology'];
  final validation = validateAndroidProductionAudioCallDurableArtifact(
    input,
    emulatorPair:
        topology is Map &&
        topology['callerKind'] == 'emulator' &&
        topology['calleeKind'] == 'emulator',
    physicalCaller:
        topology is Map &&
        topology['callerKind'] == 'physical' &&
        topology['calleeKind'] == 'emulator',
  );
  return validation.ok ? [] : [validation.detail];
}

const _prerequisites = <String>[
  "Future execution owner resolves and pins only available authorized targets.",
  "Exact candidate source/configuration/artifact and owned fixture state/cleanup evidence.",
  "No AWS binding; future external test services use authorized Hetzner only.",
  "Actual Appium MCP/native campaign ownership is required for new OS/UI actions.",
  "Existing Android production call artifact can establish only its strict structural/RTP/native-cleanup control.",
];
const _missingAssertions = <String>[
  "No joined provider acceptance, suspended/process-terminated/locked OS wake and answer/media producer for each available shipped platform.",
  "A supplied control verdict must never count as execution or PASS of VC-014.",
];
