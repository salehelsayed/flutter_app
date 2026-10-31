import 'dart:convert';
import 'dart:io';
import '../../tool/sims/production_call_back_criteria.dart';

const _journey = 'VC-027';
const _scenario = 'production.call.call-terminal-cleanup';
const _knownGap =
    "KNOWN GAP [VC-027]: No existing causal per-terminal native producer joins decline/cancel/timeout/busy/media failure to exact capture, card, call/history cleanup and successor isolation.";
const _terminalCases = {
  'decline',
  'cancel',
  'no_answer',
  'busy',
  'media_failure',
  'local_hangup',
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

/// Parameterized cleanup controls use actual call.snapshot fields and the
/// existing strict native audio-policy parser. No receipt boolean substitutes
/// for raw owned-UID capture inventory, and every case preserves its successor.
/// The cause, OS card/history owners and deadline remain missing producers.
List<String> validateRecordedControls(Map<String, Object?> input) {
  final failures = <String>[];
  final rows = input['cases'];
  if (rows is! List || rows.length != _terminalCases.length) {
    return ['all exact terminal cases required'];
  }
  final seen = <String>{};
  for (final raw in rows) {
    if (raw is! Map ||
        raw['case'] is! String ||
        !_terminalCases.contains(raw['case']) ||
        !seen.add(raw['case'] as String)) {
      failures.add('unknown or duplicate terminal case');
      continue;
    }
    final name = raw['case'];
    Map<String, Object?> value(String key) =>
        raw[key] is Map ? Map<String, Object?>.from(raw[key] as Map) : {};
    final before = value('before');
    final after = value('after');
    final successor = value('successor');
    final late = value('afterLateEvent');
    final id = before['callSha256'];
    if (id is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(id) ||
        before['contactSha256'] is! String ||
        !RegExp(
          r'^[a-f0-9]{64}$',
        ).hasMatch(before['contactSha256'] as String) ||
        before['sourceBound'] != true ||
        before['connectionReadSucceeded'] != true ||
        before['inCall'] != true) {
      failures.add('$name: real positive owned call required');
    }
    if (after['sourceBound'] != true ||
        after['connectionReadSucceeded'] != true ||
        after['callSha256'] != id ||
        after['contactSha256'] != before['contactSha256']) {
      failures.add('$name: exact owned call/contact required after action');
    }
    if (name == 'busy') {
      if (after['inCall'] != true ||
          after['state'] != before['state'] ||
          after['connectionPresent'] != before['connectionPresent'] ||
          after['localAudioEnabled'] != before['localAudioEnabled']) {
        failures.add(
          'busy: the already active call and its media must be preserved',
        );
      }
    } else if (after['inCall'] != false ||
        after['connectionPresent'] != false) {
      failures.add('$name: terminal owner must have no connection');
    }
    try {
      final dump = raw['audioPolicyDump'];
      final uid = raw['packageUid'];
      if (dump is! String || uid is! int) {
        throw const FormatException('native capture input missing');
      }
      final capture = productionCallbackAudioCaptureSnapshot(dump, uid: uid);
      if (name == 'busy') {
        final beforeDump = raw['beforeAudioPolicyDump'];
        if (beforeDump is! String) {
          throw const FormatException('positive active-call inventory missing');
        }
        final baseline = productionCallbackAudioCaptureSnapshot(
          beforeDump,
          uid: uid,
        );
        if (baseline['activeOwnedRecordClients'] is! int ||
            (baseline['activeOwnedRecordClients'] as int) <= 0 ||
            capture['activeOwnedRecordClients'] !=
                baseline['activeOwnedRecordClients']) {
          failures.add(
            'busy: exact existing native capture owner was not preserved',
          );
        }
      } else if (capture['captureReadSucceeded'] != true ||
          capture['activeOwnedRecordClients'] != 0) {
        failures.add('$name: native microphone capture still owned');
      }
    } on Object {
      failures.add('$name: complete raw native capture inventory required');
    }
    if (successor['sourceBound'] != true ||
        successor['connectionReadSucceeded'] != true ||
        successor['callSha256'] is! String ||
        !RegExp(
          r'^[a-f0-9]{64}$',
        ).hasMatch(successor['callSha256'] as String) ||
        successor['callSha256'] == id ||
        successor['state'] != 'connected' ||
        successor['connectionPresent'] != true ||
        successor['inCall'] != true ||
        late['sourceBound'] != true ||
        late['connectionReadSucceeded'] != true ||
        late['callSha256'] != successor['callSha256'] ||
        late['contactSha256'] != successor['contactSha256'] ||
        late['state'] != 'connected' ||
        late['connectionPresent'] != true ||
        late['inCall'] != true) {
      failures.add(
        '$name: stale terminal work changed or lost the current successor',
      );
    }
  }
  if (seen.length != _terminalCases.length) {
    failures.add('missing terminal case');
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
  "No existing causal per-terminal native producer joins decline/cancel/timeout/busy/media failure to exact capture, card, call/history cleanup and successor isolation.",
  "A supplied control verdict must never count as execution or PASS of VC-027.",
];
