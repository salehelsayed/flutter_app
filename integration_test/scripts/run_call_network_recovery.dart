import 'dart:convert';
import 'dart:io';

const _journey = 'VC-017';
const _scenario = 'production.call.call-network-recovery';
const _knownGap =
    "KNOWN GAP [VC-017]: Existing snapshots do not prove causal native network loss, the original reconnect deadline or new usable media after restoration.";

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

/// Reads existing call.snapshot values. RTP booleans are historical presence,
/// so this does not claim packet progress or recovered usable native media.
List<String> validateRecordedControls(Map<String, Object?> input) {
  final failures = <String>[];
  Map<String, Object?> phase(String name) =>
      input[name] is Map ? Map<String, Object?>.from(input[name]! as Map) : {};
  final before = phase('before');
  final loss = phase('loss');
  final restored = phase('restored');
  final terminal = phase('terminal');
  final late = phase('late');
  final successor = phase('successor');
  final call = before['callSha256'];
  final peer = before['contactSha256'];
  bool hash(Object? value) =>
      value is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
  if (!hash(call) || !hash(peer)) {
    failures.add('bound original call/contact required');
  }
  for (final entry in {
    'before': before,
    'loss': loss,
    'restored': restored,
  }.entries) {
    final value = entry.value;
    if (value['sourceBound'] != true ||
        value['connectionReadSucceeded'] != true ||
        value['callSha256'] != call ||
        value['contactSha256'] != peer ||
        value['inCall'] != true) {
      failures.add(
        '${entry.key}: exact retained current-call ownership required',
      );
    }
  }
  if (before['state'] != 'connected' ||
      loss['state'] != 'reconnecting' ||
      restored['state'] != 'connected' ||
      restored['connectionPresent'] != true ||
      restored['localAudioEnabled'] != true ||
      restored['inboundAudioRtpObserved'] != true ||
      restored['outboundAudioRtpObserved'] != true) {
    failures.add(
      'source-observed connected/reconnecting/connected structural control required',
    );
  }
  for (final entry in {'terminal': terminal, 'late': late}.entries) {
    if (entry.value['sourceBound'] != true ||
        entry.value['connectionReadSucceeded'] != true ||
        entry.value['callSha256'] != call ||
        entry.value['inCall'] != false ||
        entry.value['connectionPresent'] != false) {
      failures.add(
        '${entry.key}: original call must remain terminal with no connection',
      );
    }
  }
  if (successor['sourceBound'] != true ||
      successor['connectionReadSucceeded'] != true ||
      !hash(successor['callSha256']) ||
      successor['callSha256'] == call ||
      successor['contactSha256'] != peer ||
      successor['state'] != 'connected' ||
      successor['inCall'] != true ||
      successor['connectionPresent'] != true) {
    failures.add('distinct current successor after terminal cleanup required');
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
  "Existing snapshots do not prove causal native network loss, the original reconnect deadline or new usable media after restoration.",
  "A supplied control verdict must never count as execution or PASS of VC-017.",
];
