import 'dart:convert';
import 'dart:io';

import '../../tool/sims/production_private_media_criteria.dart';
import 'run_production_private_media_local.dart' as local;

const _journey = 'MEDIA-030';
const _scenario = 'production.media.private-remote-delivery';
const _knownGap =
    'KNOWN GAP [MEDIA-030]: No paired encrypted remote send/download producer joins protected/view-once/disappearing modes to authorized first frame, refused save/share/forward, close/expiry and cold reopen. The existing fixture-local native viewer journey cannot establish remote receipt.';

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--list-scenarios') {
    stdout.writeln(_scenario);
    return;
  }
  if (arguments.length == 1 && arguments.single == '--existing-device-local') {
    // Retain the actual existing native protected-window/view-once lifecycle
    // campaign and its own local-only result. It seeds device-local fixtures;
    // never treat that seed as encrypted wire receive or export private bytes.
    stderr.writeln(_knownGap);
    stderr.writeln(
      'Dispatch scope: existing device-local private campaign only.',
    );
    await local.main(const <String>[]);
    return;
  }
  List<String>? failures;
  if (arguments.isNotEmpty) {
    if (arguments.length != 2 ||
        arguments.first != '--assert-existing-control') {
      stderr.writeln(
        'Usage: --list-scenarios | --assert-existing-control <local-observations.json> | --existing-device-local',
      );
      exitCode = 64;
      return;
    }
    try {
      final decoded = jsonDecode(await File(arguments.last).readAsString());
      failures = decoded is Map
          ? validateProductionPrivateMedia(Map<String, Object?>.from(decoded))
          : ['saved device-local control must be an object'];
    } on Object {
      failures = ['saved device-local control unreadable or malformed'];
    }
  }
  final failed = failures != null && failures.isNotEmpty;
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
      'nativeExecutedByThisCommand': false,
      'recordedControlEvaluated': failures != null,
      'recordedControlFailures': failures ?? const <String>[],
      'qualifyingNativeJourneyWritten': false,
      'scope': 'existing local private SQL/viewer/native-window control; no remote delivery or independent private export',
      'prerequisites': <String>['Existing exact prepared production journey APK, available pinned Android pair and owned-state guard/restoration.', 'Actual paired encrypted send/download with current SQL parent/attachment authority inside the protected viewer is still required.', 'Any future byte/native-open assertion must run inside the actual viewer grant before first frame, without exporting private/view-once files.', 'No account-wide consumption or remote revocation claim; retain the existing local validator limits.', 'No AWS binding; future external services use authorized Hetzner only.'],
      'missingAssertions': <String>[_knownGap],
    })}',
  );
  exitCode = failed ? 1 : 78;
}
