import 'dart:async';
import 'dart:io';

import '../support/media_content_oracle.dart';

/// Runs only the two host decoders used by the recorded-media controls.
/// Output is drained, not retained or printed. No shell, SDK or device command
/// is accepted, and cleanup signals only this invocation's owned child.
Future<int> runRecordedMediaDecoder(
  String executable,
  List<String> arguments, {
  required Duration timeout,
}) async {
  if (!{'sips', 'ffmpeg'}.contains(executable) || timeout <= Duration.zero) {
    throw ArgumentError(
      'A supported recorded-media decoder and deadline are required.',
    );
  }
  final elapsed = Stopwatch()..start();
  final process = await Process.start(executable, arguments, runInShell: false);
  var exitObserved = false;
  final exited = process.exitCode.then((code) {
    exitObserved = true;
    return code;
  });
  // Async closures capture even synchronous stdin/drain setup errors. All
  // futures immediately enter the join below, so a failed stream cannot leave
  // an unobserved error while cleanup waits for the child.
  final stdoutDrained = () async {
    await process.stdout.drain<void>();
  }();
  final stderrDrained = () async {
    await process.stderr.drain<void>();
  }();
  final stdinClosed = () async {
    await process.stdin.close();
  }();
  final io = <Future<void>>[stdoutDrained, stderrDrained, stdinClosed];
  final completed = Future.wait<void>([
    ...io,
    exited.then<void>((_) {}),
  ], eagerError: true);

  try {
    final remaining = timeout - elapsed.elapsed;
    await completed.timeout(
      remaining > Duration.zero ? remaining : Duration.zero,
    );
    return await exited;
  } on TimeoutException {
    throw const MediaOracleFailure('HOST_DECODER_DEADLINE_EXCEEDED');
  } finally {
    try {
      if (!exitObserved) {
        // This grace matches the existing owned-child supervisor convention;
        // it is cleanup time, not an extension of either decoder's budget.
        try {
          process.kill(ProcessSignal.sigterm);
        } on Object {
          // Still await exit and escalate only this owned child below.
        }
        try {
          await exited.timeout(const Duration(seconds: 5));
        } on TimeoutException {
          try {
            process.kill(ProcessSignal.sigkill);
          } on Object {
            // Never return and allow another case before this child exits.
          }
          await exited;
        }
      }
    } finally {
      // Join both drains even when setup, I/O or termination fails. The wait
      // observes every future before forwarding an error to the caller.
      await Future.wait<void>(io);
    }
  }
}
