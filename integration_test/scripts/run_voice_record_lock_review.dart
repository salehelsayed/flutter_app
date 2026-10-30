import 'dart:convert';
import 'dart:io';

import '../support/android_voice_message_evidence.dart';
import 'run_voice_message_sims.dart' as basic;

const _journey = 'MEDIA-027';
const _scenario = 'production.media.voice-record-lock-review';
const _knownGap =
    "KNOWN GAP [MEDIA-027]: The real basic voice campaign records hold/release and receives/plays exact bytes, but no native lock-review-send/cancel producer joins that branch to received playable audio.";

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--list-scenarios') {
    stdout.writeln(_scenario);
    return;
  }
  if (arguments.isNotEmpty && arguments.first == '--existing-basic-voice') {
    // Preserve the actual existing campaign and its own exact result identity.
    // It prepares neither a new APK nor a new UI harness. Its basic record/send/
    // download/native-player proof does not pass this runner's missing journey.
    stderr.writeln(_knownGap);
    stderr.writeln('Dispatch scope: existing basic voice campaign only.');
    await basic.main(arguments.skip(1).toList());
    return;
  }
  List<String>? failures;
  if (arguments.isNotEmpty) {
    if (arguments.length != 2 ||
        arguments.first != '--assert-existing-control') {
      stderr.writeln(
        'Usage: --list-scenarios | --assert-existing-control <basic-runtime-proof.json> | --existing-basic-voice [existing campaign arguments]',
      );
      exitCode = 64;
      return;
    }
    try {
      final decoded = jsonDecode(await File(arguments.last).readAsString());
      if (decoded is! Map) {
        failures = ['saved basic voice control must be an object'];
      } else {
        final result = validateAndroidVoiceMessageEvidence(
          Map<String, Object?>.from(decoded),
        );
        failures = result.ok ? <String>[] : <String>[result.detail];
      }
    } on Object {
      failures = ['saved basic voice control unreadable or malformed'];
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
      'prerequisites': <String>['Basic campaign: exact centrally prepared main APK, available pinned Android physical/emulator pair and exclusive automation ownership.', 'Real existing relay/provider bindings plus owned app-state restore; no raw recording or secrets in durable evidence.', 'Missing permission/recorder/player/audio-session actions require actual Appium MCP/native observations; supplied basic flags are not that producer.', 'Existing native player progress is not decoded PCM, acoustic content or audible speaker proof.', 'No AWS binding; future external services use authorized Hetzner only.'],
      'missingAssertions': <String>[_knownGap],
    })}',
  );
  exitCode = failed ? 1 : 78;
}
