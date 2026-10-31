import 'dart:convert';
import 'dart:io';

const _journey = 'VC-019';
const _scenario = 'production.call.call-received-content-privacy';
const _knownGap =
    "KNOWN GAP [VC-019]: No remote phone PCM/content producer before answer, during either-endpoint mute and after hangup; RTP and local track flags are insufficient.";

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

/// Local enabled-track controls from call.snapshot. These assertions cannot
/// prove absence or intelligibility of microphone content at the receiver.
List<String> validateRecordedControls(Map<String, Object?> input) {
  final failures = <String>[];
  Map<String, Object?> endpoint(String phase, String role) {
    final pair = input[phase];
    final value = pair is Map ? pair[role] : null;
    return value is Map ? Map<String, Object?>.from(value) : {};
  }

  final original = endpoint('unmuted', 'a');
  final call = original['callSha256'];
  if (call is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(call)) {
    failures.add('bound positive call identity required');
  }
  if (original['contactSha256'] == endpoint('unmuted', 'b')['contactSha256']) {
    failures.add('distinct endpoint contact bindings required');
  }
  for (final role in ['a', 'b']) {
    final positive = endpoint('unmuted', role);
    final peer = positive['contactSha256'];
    if (peer is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(peer)) {
      failures.add('$role: bound contact required');
    }
    for (final phase in [
      'beforeAnswer',
      'unmuted',
      'aMuted',
      'bMuted',
      'afterUnmute',
      'afterHangup',
    ]) {
      final value = endpoint(phase, role);
      if (value['sourceBound'] != true ||
          value['connectionReadSucceeded'] != true ||
          value['callSha256'] != call ||
          value['contactSha256'] != peer) {
        failures.add(
          '$phase/$role: exact source/call/contact binding required',
        );
      }
      if (['unmuted', 'afterUnmute'].contains(phase) &&
          (value['localAudioEnabled'] != true ||
              value['connectionPresent'] != true ||
              value['inboundAudioRtpObserved'] != true ||
              value['outboundAudioRtpObserved'] != true)) {
        failures.add(
          '$phase/$role: positive local track and RTP control required',
        );
      }
      if (phase == 'beforeAnswer' &&
          (value['inCall'] != true ||
              value['connectionPresent'] != false &&
                  value['localAudioEnabled'] != false)) {
        failures.add('$phase/$role: no local capture before Answer required');
      }
      if (phase == '${role}Muted' &&
          (value['connectionPresent'] != true ||
              value['localAudioEnabled'] != false)) {
        failures.add(
          '$phase/$role: exact disabled local track control required',
        );
      }
      if (phase == 'afterHangup' &&
          (value['inCall'] != false || value['connectionPresent'] != false)) {
        failures.add('afterHangup/$role: retained connection forbidden');
      }
    }
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
  "No remote phone PCM/content producer before answer, during either-endpoint mute and after hangup; RTP and local track flags are insufficient.",
  "A supplied control verdict must never count as execution or PASS of VC-019.",
];
