import 'dart:convert';
import 'dart:io';

const _journey = 'VC-018';
const _scenario = 'production.call.call-audio-interruption';
const _knownGap =
    "KNOWN GAP [VC-018]: No actual OS audio-focus interruption/mute-preservation and ready-media recovery producer; scripted events are narrower.";

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

/// Exact ownership from existing call.snapshot only. Its schema has no OS
/// focus event or mute state; this body never invents either observation.
List<String> validateRecordedControls(Map<String, Object?> input) {
  final failures = <String>[];
  Map<String, Object?> read(String phase) => input[phase] is Map
      ? Map<String, Object?>.from(input[phase]! as Map)
      : {};
  final before = read('before');
  final recovered = read('recovered');
  final replacement = read('replacement');
  final afterLate = read('afterLateEvent');
  bool hash(Object? value) =>
      value is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
  if (!hash(before['callSha256']) || !hash(before['contactSha256'])) {
    failures.add('bound original call required');
  }
  for (final value in [before, recovered, replacement, afterLate]) {
    if (value['sourceBound'] != true ||
        value['connectionReadSucceeded'] != true ||
        value['inCall'] != true ||
        value['state'] != 'connected' ||
        value['connectionPresent'] != true) {
      failures.add(
        'each supplied control needs a real current connected source',
      );
    }
  }
  if (recovered['callSha256'] != before['callSha256'] ||
      recovered['contactSha256'] != before['contactSha256']) {
    failures.add('recovery control changed the original owner');
  }
  if (!hash(replacement['callSha256']) ||
      replacement['callSha256'] == before['callSha256'] ||
      afterLate['callSha256'] != replacement['callSha256'] ||
      afterLate['contactSha256'] != replacement['contactSha256']) {
    failures.add(
      'late work must leave the distinct replacement call unchanged',
    );
  }
  return failures;
}

const _prerequisites = <String>[
  "Future execution owner resolves and pins only available authorized targets.",
  "Exact candidate source/configuration/artifact and owned fixture state/cleanup evidence.",
  "No AWS binding; future external test services use authorized Hetzner only.",
  "Actual Appium MCP/native campaign ownership is required for new OS/UI actions.",
  "Supplied phase maps are unmodified outputs of existing ProductionCallControls.call.snapshot; this command cannot collect or authenticate their occurrence.",
];
const _missingAssertions = <String>[
  "No actual OS audio-focus interruption/mute-preservation and ready-media recovery producer; scripted events are narrower.",
  "A supplied control verdict must never count as execution or PASS of VC-018.",
];
