import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../support/android_notification_payload_campaign.dart'
    show relayJournalContainsAndroidProviderSend;
import 'reaction_notification_proof_support.dart';

const String groupReactionNotificationArtifactSchema =
    'mknoon.plan257.device-proof.v1';
const int groupReactionNotificationArtifactVersion = 1;
const String groupReactionNotificationVerdictSchema =
    'mknoon.plan257.orchestrator-verdict.v1';
const String groupReactionNotificationStagingSchema =
    'mknoon.plan257.staging-prerequisites.v1';
const String plan398ExistingStateTraceManifestSchema =
    'mknoon.plan398.existing-state-trace-manifest.v1';
const String groupReactionBackgroundConnectedScenarioId =
    'android_group_reaction_recipient_background_connected';
const String iosChatGroupMessageAndReactionScenarioId =
    'ios_chat_group_message_and_reaction_recipient';
const String iosChatGroupMessageAndReactionArtifactSchema =
    'mknoon.plan397.ios-chat-group-notification-proof.v1';
const int iosChatGroupMessageAndReactionArtifactVersion = 1;
const String plan398IosGroupMessageDiagnosticArtifactSchema =
    'mknoon.plan398.ios-group-message-diagnostic.v2';
const int plan398IosGroupMessageDiagnosticArtifactVersion = 2;
const String plan398ExistingStateTraceArtifactSchema =
    'mknoon.plan398.ios-group-message-existing-state-trace.v1';
const String plan398ExistingStateLiveDiagnosticArtifactSchema =
    'mknoon.plan398.ios-group-message-existing-state-live-diagnostic.v1';
const int plan398ExistingStateTraceArtifactVersion = 1;
const String plan398ExistingStateTraceArtifactFileName =
    'plan398_existing_state_trace.json';
const String plan398ExistingStateTraceClaimFileName =
    'plan398_existing_state_trace_claim.json';
const String plan398ExistingStateTraceFailureFileName =
    'plan398_existing_state_trace_failure.json';
const String plan398ExistingStateTraceCommandJournalFileName =
    'plan398_existing_state_trace_command_journal.json';
const String plan398ReviewedFinalTraceAuthorization =
    'plan398-reviewed-final-same-container-manual-trace-v1';
const String plan398ExistingStateTraceAttempt = 'attempt-03';
const String plan398ExistingStateTraceIosStdoutFileName =
    'plan398_existing_state_trace_ios_stdout.bin';
const String plan398ExistingStateTraceIosStderrFileName =
    'plan398_existing_state_trace_ios_stderr.bin';
const String plan398ExistingStateTraceTerminalReceiptFileName =
    'plan398_existing_state_trace_terminal_receipt.json';
const String plan398ExistingStateTraceTerminalReceiptSchema =
    'mknoon.plan398.existing-state-trace-terminal-receipt.v1';
const String plan398ExistingStateLiveDiagnosticTerminalReceiptSchema =
    'mknoon.plan398.existing-state-live-diagnostic-terminal-receipt.v1';
const String plan398LegacyFinalAttemptAuthorityMode = 'legacy_final_attempt';
const String plan398LiveDiagnosticAuthorityMode = 'live_diagnostic';
const int plan398ExistingStateTraceIosStdoutLimitBytes = 64 * 1024 * 1024;
const int plan398ExistingStateTraceIosStderrLimitBytes = 4 * 1024 * 1024;
const int plan398ExistingStateTraceJournalLimitBytes = 4 * 1024 * 1024;
const int plan398ExistingStateTracePixelLogLimitBytes = 64 * 1024 * 1024;
const int plan398ExistingStateTraceArtifactLimitBytes = 1024 * 1024;
const String relayGroupMessageDispatchCounter =
    'relay_group_message_dispatch_total';
const String plan398IosGroupObservationHostReceiptSchema =
    'mknoon.sims.ios-group-notification-observation-host-receipt.v3';
const String plan398IosGroupObservationDiagnosticSchema =
    'mknoon.sims.ios-group-notification-diagnostics.v2';
const String groupStrictNotificationScenarioId =
    'android_strict_group_notification_closure';
const int groupReactionBackgroundConnectedHomeToReactDelayMs = 3000;
// The picker driver is independently bounded to three long-press attempts and
// four UI-hierarchy polls per attempt. This anti-stale ceiling must contain
// that bounded automation; it is not the notification-delivery SLA below.
const int groupReactionBackgroundConnectedHomeToReactAutomationWindowMs = 60000;
const int groupReactionBackgroundConnectedObservationWindowMs = 60000;
const String groupReactionBackgroundConnectedObservationPrefix =
    'MKNOON_315_BACKGROUND_CONNECTED_OBSERVATION ';
const Set<String> _processAliveReactionScenarioIds = <String>{
  groupReactionBackgroundConnectedScenarioId,
};

String plan398PixelLogFileName(String deviceId) =>
    'device_logcat_${deviceId.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_')}.log';

final class Plan398TraceLogOverflow implements Exception {
  const Plan398TraceLogOverflow(this.channel, this.limitBytes);

  final String channel;
  final int limitBytes;

  @override
  String toString() =>
      'Plan398TraceLogOverflow($channel exceeded $limitBytes bytes)';
}

enum Plan398IosLoggerLivenessFailure {
  notStarted,
  notConnected,
  disconnected,
  exited,
}

/// Pure fail-closed classification for the long-lived Plan 398 iOS logger.
///
/// `idevicesyslog` can emit a standalone `[disconnected]` line before its
/// process-exit future is observed. Both signals invalidate every subsequent
/// claim/readiness/send boundary after the initial connection.
Plan398IosLoggerLivenessFailure? classifyPlan398IosLoggerLiveness({
  required bool loggerStarted,
  required bool loggerConnected,
  required int? observedExitCode,
  required String stdoutLog,
  required String stderrLog,
}) {
  if (!loggerStarted) return Plan398IosLoggerLivenessFailure.notStarted;
  if (!loggerConnected) return Plan398IosLoggerLivenessFailure.notConnected;
  if (_plan398ContainsIosLoggerDisconnect(stdoutLog) ||
      _plan398ContainsIosLoggerDisconnect(stderrLog)) {
    return Plan398IosLoggerLivenessFailure.disconnected;
  }
  if (observedExitCode != null) {
    return Plan398IosLoggerLivenessFailure.exited;
  }
  return null;
}

bool _plan398ContainsIosLoggerDisconnect(String log) => const LineSplitter()
    .convert(log)
    .any((line) => line.trim() == '[disconnected]');

/// Incremental, bounded recognition of idevicesyslog's standalone terminal
/// sentinel. It retains at most one short raw line and performs no I/O.
final class Plan398IosLoggerDisconnectObserver {
  static const int _maximumCandidateLineBytes = 256;
  static const String _sentinel = '[disconnected]';

  final List<int> _candidateLine = <int>[];
  bool _candidateOverflowed = false;
  bool _completedSentinelObserved = false;

  bool get observed => _completedSentinelObserved || _pendingLineIsSentinel;

  void addRawChunk(List<int> chunk) {
    if (_completedSentinelObserved) return;
    for (final byte in chunk) {
      if (byte == 0x0a) {
        if (_pendingLineIsSentinel) {
          _completedSentinelObserved = true;
          return;
        }
        _candidateLine.clear();
        _candidateOverflowed = false;
        continue;
      }
      if (_candidateLine.length < _maximumCandidateLineBytes) {
        _candidateLine.add(byte);
      } else {
        _candidateOverflowed = true;
      }
    }
  }

  bool get _pendingLineIsSentinel =>
      !_candidateOverflowed &&
      String.fromCharCodes(_candidateLine).trim() == _sentinel;
}

enum Plan398ManualSendWaitDisposition {
  acknowledged,
  inputClosed,
  timedOut,
  loggerFailed,
}

final class Plan398ManualSendWaitResult {
  const Plan398ManualSendWaitResult({
    required this.disposition,
    this.acknowledgement,
    this.livenessFailure,
  });

  final Plan398ManualSendWaitDisposition disposition;
  final String? acknowledgement;
  final Plan398IosLoggerLivenessFailure? livenessFailure;
}

/// Races one manual-send acknowledgement against bounded logger-liveness
/// polling, then rechecks liveness once more before accepting the input.
Future<Plan398ManualSendWaitResult> waitForPlan398ManualSendAcknowledgement({
  required Stream<String> acknowledgements,
  required Plan398IosLoggerLivenessFailure? Function() readLivenessFailure,
  required Duration timeout,
  required Duration pollInterval,
}) async {
  if (timeout.inMicroseconds <= 0 || pollInterval.inMicroseconds <= 0) {
    throw ArgumentError('Plan 398 manual-send wait durations must be positive');
  }

  Plan398ManualSendWaitResult loggerFailure(
    Plan398IosLoggerLivenessFailure failure,
  ) => Plan398ManualSendWaitResult(
    disposition: Plan398ManualSendWaitDisposition.loggerFailed,
    livenessFailure: failure,
  );

  final initialFailure = readLivenessFailure();
  if (initialFailure != null) return loggerFailure(initialFailure);

  final input = Completer<Plan398ManualSendWaitResult>();
  final liveness = Completer<Plan398ManualSendWaitResult>();
  final subscription = acknowledgements.listen(
    (line) {
      if (!input.isCompleted) {
        input.complete(
          Plan398ManualSendWaitResult(
            disposition: Plan398ManualSendWaitDisposition.acknowledged,
            acknowledgement: line,
          ),
        );
      }
    },
    onError: (Object error, StackTrace stackTrace) {
      if (!input.isCompleted) input.completeError(error, stackTrace);
    },
    onDone: () {
      if (!input.isCompleted) {
        input.complete(
          const Plan398ManualSendWaitResult(
            disposition: Plan398ManualSendWaitDisposition.inputClosed,
          ),
        );
      }
    },
    cancelOnError: true,
  );
  final timer = Timer.periodic(pollInterval, (_) {
    if (liveness.isCompleted) return;
    final failure = readLivenessFailure();
    if (failure != null) liveness.complete(loggerFailure(failure));
  });

  try {
    var result = await Future.any<Plan398ManualSendWaitResult>(
      <Future<Plan398ManualSendWaitResult>>[
        input.future,
        liveness.future,
        Future<Plan398ManualSendWaitResult>.delayed(
          timeout,
          () => const Plan398ManualSendWaitResult(
            disposition: Plan398ManualSendWaitDisposition.timedOut,
          ),
        ),
      ],
    );
    if (result.disposition == Plan398ManualSendWaitDisposition.acknowledged) {
      await Future<void>.delayed(Duration.zero);
      final finalFailure = readLivenessFailure();
      if (finalFailure != null) result = loggerFailure(finalFailure);
    }
    return result;
  } finally {
    timer.cancel();
    await subscription.cancel();
  }
}

final class Plan398TraceLogFileReference {
  const Plan398TraceLogFileReference({
    required this.file,
    required this.lengthBytes,
    required this.sha256,
  });

  final File file;
  final int lengthBytes;
  final String sha256;

  Map<String, Object?> toJson() => <String, Object?>{
    'fileName': file.uri.pathSegments.last,
    'lengthBytes': lengthBytes,
    'sha256': sha256,
    'mode': '0600',
  };
}

final class Plan398TraceLogCommit {
  const Plan398TraceLogCommit({required this.stdout, required this.stderr});

  final Plan398TraceLogFileReference stdout;
  final Plan398TraceLogFileReference stderr;
}

/// Byte-exact, bounded persistence for the one authorized Plan 398 trace.
///
/// Each stream chunk is written and awaited before it reaches the separate
/// chunked UTF-8 decoder. Decoding is deliberately `allowMalformed`: raw bytes
/// are the authority, while the in-memory strings continue feeding the strict
/// existing parsers without making a malformed byte a persistence failure.
final class Plan398TraceRawLogCapture {
  Plan398TraceRawLogCapture({
    required this.outputDirectory,
    this.stdoutLimitBytes = plan398ExistingStateTraceIosStdoutLimitBytes,
    this.stderrLimitBytes = plan398ExistingStateTraceIosStderrLimitBytes,
  }) {
    if (stdoutLimitBytes <= 0 || stderrLimitBytes <= 0) {
      throw ArgumentError('Plan 398 raw-log limits must be positive');
    }
  }

  final Directory outputDirectory;
  final int stdoutLimitBytes;
  final int stderrLimitBytes;

  _Plan398TraceRawLogChannel? _stdout;
  _Plan398TraceRawLogChannel? _stderr;
  bool _finished = false;

  bool get prepared => _stdout != null && _stderr != null && !_finished;

  Future<void> prepare() async {
    if (_stdout != null || _stderr != null || _finished) {
      throw StateError('Plan 398 raw-log capture cannot be prepared twice');
    }
    await outputDirectory.create(recursive: true);
    try {
      _stdout = await _Plan398TraceRawLogChannel.create(
        stableFile: File(
          '${outputDirectory.path}${Platform.pathSeparator}'
          '$plan398ExistingStateTraceIosStdoutFileName',
        ),
        channel: 'stdout',
        limitBytes: stdoutLimitBytes,
      );
      _stderr = await _Plan398TraceRawLogChannel.create(
        stableFile: File(
          '${outputDirectory.path}${Platform.pathSeparator}'
          '$plan398ExistingStateTraceIosStderrFileName',
        ),
        channel: 'stderr',
        limitBytes: stderrLimitBytes,
      );
    } on Object {
      await disposeTemps();
      rethrow;
    }
  }

  Future<void> consumeStdout(
    Stream<List<int>> source,
    StringBuffer decoded, {
    void Function()? onFirstRawChunk,
    void Function(List<int>)? onRawChunk,
  }) => _consume(
    source,
    decoded,
    channel: _stdout,
    onFirstRawChunk: onFirstRawChunk,
    onRawChunk: onRawChunk,
  );

  Future<void> consumeStderr(
    Stream<List<int>> source,
    StringBuffer decoded, {
    void Function()? onFirstRawChunk,
    void Function(List<int>)? onRawChunk,
  }) => _consume(
    source,
    decoded,
    channel: _stderr,
    onFirstRawChunk: onFirstRawChunk,
    onRawChunk: onRawChunk,
  );

  Future<void> _consume(
    Stream<List<int>> source,
    StringBuffer decoded, {
    required _Plan398TraceRawLogChannel? channel,
    required void Function()? onFirstRawChunk,
    required void Function(List<int>)? onRawChunk,
  }) async {
    if (channel == null || _finished) {
      throw StateError('Plan 398 raw-log capture is not prepared');
    }
    final decoder = const Utf8Decoder(
      allowMalformed: true,
    ).startChunkedConversion(StringConversionSink.fromStringSink(decoded));
    var observedRawChunk = false;
    try {
      await for (final chunk in source) {
        if (chunk.isEmpty) continue;
        await channel.write(chunk);
        onRawChunk?.call(chunk);
        if (!observedRawChunk) {
          observedRawChunk = true;
          onFirstRawChunk?.call();
        }
        decoder.add(chunk);
      }
    } finally {
      decoder.close();
    }
  }

  Future<Plan398TraceLogCommit> closeAndCommit() async {
    final stdout = _stdout;
    final stderr = _stderr;
    if (stdout == null || stderr == null || _finished) {
      throw StateError('Plan 398 raw-log capture is not open');
    }
    _finished = true;
    Plan398TraceLogCommit? committed;
    Object? operationError;
    StackTrace? operationStackTrace;
    try {
      await stdout.close();
      await stderr.close();
      final stdoutReference = await stdout.publishNoReplace();
      final stderrReference = await stderr.publishNoReplace();
      committed = Plan398TraceLogCommit(
        stdout: stdoutReference,
        stderr: stderrReference,
      );
    } on Object catch (error, stackTrace) {
      operationError = error;
      operationStackTrace = stackTrace;
    }
    Object? cleanupError;
    StackTrace? cleanupStackTrace;
    try {
      await stdout.disposeTemp();
    } on Object catch (error, stackTrace) {
      cleanupError ??= error;
      cleanupStackTrace ??= stackTrace;
    }
    try {
      await stderr.disposeTemp();
    } on Object catch (error, stackTrace) {
      cleanupError ??= error;
      cleanupStackTrace ??= stackTrace;
    }
    if (operationError != null) {
      Error.throwWithStackTrace(operationError, operationStackTrace!);
    }
    if (cleanupError != null) {
      Error.throwWithStackTrace(cleanupError, cleanupStackTrace!);
    }
    return committed!;
  }

  Future<void> disposeTemps() async {
    _finished = true;
    Object? firstError;
    StackTrace? firstStackTrace;
    for (final channel in <_Plan398TraceRawLogChannel?>[_stdout, _stderr]) {
      if (channel == null) continue;
      try {
        await channel.disposeTemp();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }
}

final class _Plan398TraceRawLogChannel {
  _Plan398TraceRawLogChannel._({
    required this.stableFile,
    required this.temporaryFile,
    required this.channel,
    required this.limitBytes,
    required RandomAccessFile handle,
  }) : _handle = handle;

  final File stableFile;
  final File temporaryFile;
  final String channel;
  final int limitBytes;
  RandomAccessFile? _handle;
  int _lengthBytes = 0;

  static Future<_Plan398TraceRawLogChannel> create({
    required File stableFile,
    required String channel,
    required int limitBytes,
  }) async {
    final temporaryFile = File(
      '${stableFile.path}.$pid.'
      '${DateTime.now().toUtc().microsecondsSinceEpoch}.private-temp',
    );
    await temporaryFile.create(exclusive: true);
    RandomAccessFile? handle;
    try {
      final chmod = await Process.run('chmod', <String>[
        '600',
        temporaryFile.path,
      ]);
      final entityType = await FileSystemEntity.type(
        temporaryFile.path,
        followLinks: false,
      );
      final stat = await temporaryFile.stat();
      if (chmod.exitCode != 0 ||
          entityType != FileSystemEntityType.file ||
          (stat.mode & 0x1ff) != 0x180 ||
          stat.size != 0) {
        throw const FileSystemException(
          'private empty Plan 398 raw-log temp rejected',
        );
      }
      handle = await temporaryFile.open(mode: FileMode.append);
      return _Plan398TraceRawLogChannel._(
        stableFile: stableFile,
        temporaryFile: temporaryFile,
        channel: channel,
        limitBytes: limitBytes,
        handle: handle,
      );
    } on Object {
      try {
        await handle?.close();
      } finally {
        if (await temporaryFile.exists()) await temporaryFile.delete();
      }
      rethrow;
    }
  }

  Future<void> write(List<int> bytes) async {
    final handle = _handle;
    if (handle == null) {
      throw StateError('Plan 398 $channel raw-log handle is closed');
    }
    if (_lengthBytes + bytes.length > limitBytes) {
      throw Plan398TraceLogOverflow(channel, limitBytes);
    }
    await handle.writeFrom(bytes);
    _lengthBytes += bytes.length;
  }

  Future<void> close() async {
    final handle = _handle;
    if (handle == null) return;
    _handle = null;
    try {
      await handle.flush();
    } finally {
      await handle.close();
    }
  }

  Future<Plan398TraceLogFileReference> publishNoReplace() async {
    if (_handle != null) {
      throw StateError('Plan 398 $channel raw log must close before publish');
    }
    final temporaryBytes = await temporaryFile.readAsBytes();
    final expectedSha256 = sha256.convert(temporaryBytes).toString();
    if (temporaryBytes.length != _lengthBytes) {
      throw const FileSystemException(
        'Plan 398 raw-log temp length changed before publish',
      );
    }
    final publish = await Process.run('ln', <String>[
      temporaryFile.path,
      stableFile.path,
    ]);
    if (publish.exitCode != 0) {
      throw FileSystemException(
        'Plan 398 raw-log no-replace publication rejected',
        stableFile.path,
      );
    }
    final reference = Plan398TraceLogFileReference(
      file: stableFile,
      lengthBytes: _lengthBytes,
      sha256: expectedSha256,
    );
    await _verifyPlan398TraceLogReference(reference);
    await fsyncPlan398Directory(stableFile.parent);
    return reference;
  }

  Future<void> disposeTemp() async {
    Object? closeError;
    StackTrace? closeStackTrace;
    try {
      await close();
    } on Object catch (error, stackTrace) {
      closeError = error;
      closeStackTrace = stackTrace;
    }
    if (await temporaryFile.exists()) await temporaryFile.delete();
    if (closeError != null) {
      Error.throwWithStackTrace(closeError, closeStackTrace!);
    }
  }
}

Future<void> _verifyPlan398TraceLogReference(
  Plan398TraceLogFileReference reference,
) async {
  final type = await FileSystemEntity.type(
    reference.file.path,
    followLinks: false,
  );
  final stat = await reference.file.stat();
  if (type != FileSystemEntityType.file ||
      (stat.mode & 0x1ff) != 0x180 ||
      stat.size != reference.lengthBytes ||
      sha256.convert(await reference.file.readAsBytes()).toString() !=
          reference.sha256) {
    throw FileSystemException(
      'Plan 398 raw-log publication verification failed',
      reference.file.path,
    );
  }
}

Future<GroupReactionNotificationArtifactValidation>
validatePlan398ExistingStateTraceOutputPreflight(
  Directory outputDirectory,
) async {
  final failures = <String>[];
  for (final fileName in const <String>[
    plan398ExistingStateTraceArtifactFileName,
    plan398ExistingStateTraceClaimFileName,
    'plan398_existing_state_trace_verdict.json',
    plan398ExistingStateTraceIosStdoutFileName,
    plan398ExistingStateTraceIosStderrFileName,
    plan398ExistingStateTraceTerminalReceiptFileName,
  ]) {
    final path = '${outputDirectory.path}${Platform.pathSeparator}$fileName';
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      failures.add('stale Plan 398 output exists: $fileName');
    }
  }
  if (await outputDirectory.exists()) {
    await for (final entity in outputDirectory.list(followLinks: false)) {
      final name = entity.uri.pathSegments.last;
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        failures.add('stale Plan 398 symlink exists: $name');
      }
      if (name.contains('private-temp')) {
        failures.add('stale Plan 398 private-temp residue exists: $name');
      }
    }
  }
  return GroupReactionNotificationArtifactValidation(failures);
}

int? plan398RunnerProcessIdFromDevicectlLaunchJson(Object? value) {
  final candidates = <int>[];
  void visit(Object? node) {
    if (node is Map) {
      for (final entry in node.entries) {
        if (<String>{'processIdentifier', 'processID'}.contains(entry.key) &&
            entry.value is int &&
            (entry.value! as int) > 0) {
          candidates.add(entry.value! as int);
        }
        visit(entry.value);
      }
    } else if (node is List) {
      for (final child in node) {
        visit(child);
      }
    }
  }

  visit(value);
  final unique = candidates.toSet();
  return unique.length == 1 ? unique.single : null;
}

const Set<String> _plan398TraceTerminalStatuses = <String>{
  'success',
  'typed_failure',
  'unexpected_failure',
  'manual_timeout',
  'logger_forced_kill',
  'decoder_error',
  'cleanup_error',
  'pre_logger_failure',
};

Future<File> writePlan398ExistingStateTraceTerminalReceipt({
  required Directory outputDirectory,
  required String scenario,
  String authorityMode = plan398LegacyFinalAttemptAuthorityMode,
  String? attempt,
  String? authorization,
  String? finalRunnerProductReceiptSha256,
  String? finalRunnerInstallTerminalSha256,
  String? attempt02ReceiptSha256,
  required String terminalStatus,
  required int captureExitCode,
  required String stage,
  required String detailCode,
  required bool traceAttemptClaimed,
  required bool loggerStarted,
  required bool loggerConnected,
  required int? loggerProcessId,
  required int? runnerProcessId,
  required String stopDisposition,
  required int loggerExitCode,
  required bool loggerForcedTimeout,
  Plan398TraceLogCommit? logs,
  required Plan398TraceLogFileReference commandJournal,
  required Plan398TraceLogFileReference? pixelLog,
}) async {
  final legacyAuthority =
      authorityMode == plan398LegacyFinalAttemptAuthorityMode;
  final liveDiagnostic = authorityMode == plan398LiveDiagnosticAuthorityMode;
  final canOmitPixelLog =
      terminalStatus == 'pre_logger_failure' &&
      !loggerStarted &&
      !loggerConnected &&
      loggerProcessId == null &&
      runnerProcessId == null &&
      stopDisposition == 'not_started' &&
      loggerExitCode == -1 &&
      !loggerForcedTimeout &&
      logs == null;
  if ((!legacyAuthority && !liveDiagnostic) ||
      legacyAuthority &&
          (attempt != plan398ExistingStateTraceAttempt ||
              authorization != plan398ReviewedFinalTraceAuthorization ||
              !_isSha256(finalRunnerProductReceiptSha256) ||
              !_isSha256(finalRunnerInstallTerminalSha256) ||
              !_isSha256(attempt02ReceiptSha256)) ||
      liveDiagnostic &&
          <Object?>[
            attempt,
            authorization,
            finalRunnerProductReceiptSha256,
            finalRunnerInstallTerminalSha256,
            attempt02ReceiptSha256,
          ].any((value) => value != null) ||
      !_plan398TraceTerminalStatuses.contains(terminalStatus) ||
      !RegExp(r'^[A-Za-z0-9_.:-]{1,160}$').hasMatch(stage) ||
      !RegExp(r'^[A-Za-z0-9_.:-]{1,200}$').hasMatch(detailCode) ||
      !<String>{
        'graceful',
        'already_exited',
        'forced_kill',
        'not_started',
      }.contains(stopDisposition) ||
      loggerConnected && !loggerStarted ||
      loggerStarted && (loggerProcessId == null || loggerProcessId <= 0) ||
      !loggerStarted && loggerProcessId != null ||
      runnerProcessId != null && runnerProcessId <= 0 ||
      terminalStatus == 'success' && captureExitCode != 0 ||
      terminalStatus != 'success' && captureExitCode == 0 ||
      loggerStarted && logs == null ||
      !loggerStarted &&
          (loggerExitCode != -1 || loggerForcedTimeout || logs != null) ||
      pixelLog == null && !canOmitPixelLog) {
    throw const FormatException('invalid Plan 398 terminal receipt shape');
  }
  if (terminalStatus == 'success' &&
      (!loggerStarted ||
          !loggerConnected ||
          runnerProcessId == null ||
          logs == null ||
          logs.stdout.lengthBytes <= 0 ||
          stopDisposition != 'graceful')) {
    throw const FormatException('invalid successful Plan 398 terminal receipt');
  }
  if (terminalStatus == 'logger_forced_kill' &&
      (stopDisposition != 'forced_kill' || !loggerForcedTimeout)) {
    throw const FormatException('forced-kill receipt lacks forced stop');
  }
  if (terminalStatus == 'pre_logger_failure' &&
      (loggerStarted ||
          loggerConnected ||
          loggerProcessId != null ||
          runnerProcessId != null ||
          stopDisposition != 'not_started' ||
          logs != null ||
          loggerExitCode != -1 ||
          loggerForcedTimeout)) {
    throw const FormatException('invalid pre-logger terminal receipt');
  }
  if (logs != null) {
    if (logs.stdout.file.uri.pathSegments.last !=
            plan398ExistingStateTraceIosStdoutFileName ||
        logs.stderr.file.uri.pathSegments.last !=
            plan398ExistingStateTraceIosStderrFileName) {
      throw const FormatException('Plan 398 log filenames are not canonical');
    }
    await _verifyPlan398TraceLogReference(logs.stdout);
    await _verifyPlan398TraceLogReference(logs.stderr);
  }
  if (commandJournal.file.uri.pathSegments.last !=
          plan398ExistingStateTraceCommandJournalFileName ||
      commandJournal.lengthBytes <= 0 ||
      commandJournal.lengthBytes > plan398ExistingStateTraceJournalLimitBytes ||
      pixelLog != null &&
          (pixelLog.file.uri.pathSegments.last !=
                  plan398PixelLogFileName('21071FDF600CSC') ||
              pixelLog.lengthBytes <= 0 ||
              pixelLog.lengthBytes >
                  plan398ExistingStateTracePixelLogLimitBytes)) {
    throw const FormatException(
      'Plan 398 terminal journal or Pixel log reference is invalid',
    );
  }
  await _verifyPlan398TraceLogReference(commandJournal);
  if (pixelLog != null) {
    await _verifyPlan398TraceLogReference(pixelLog);
  }
  await outputDirectory.create(recursive: true);
  final receipt = File(
    '${outputDirectory.path}${Platform.pathSeparator}'
    '$plan398ExistingStateTraceTerminalReceiptFileName',
  );
  final encoded = utf8.encode(
    jsonEncode(<String, Object?>{
      'schema': legacyAuthority
          ? plan398ExistingStateTraceTerminalReceiptSchema
          : plan398ExistingStateLiveDiagnosticTerminalReceiptSchema,
      'version': 1,
      'scenario': scenario,
      if (legacyAuthority) ...<String, Object?>{
        'attempt': attempt,
        'authorization': authorization,
        'finalRunnerProductReceiptSha256': finalRunnerProductReceiptSha256,
        'finalRunnerInstallTerminalSha256': finalRunnerInstallTerminalSha256,
        'attempt02ReceiptSha256': attempt02ReceiptSha256,
      } else
        'authorityMode': plan398LiveDiagnosticAuthorityMode,
      'terminalStatus': terminalStatus,
      'captureExitCode': captureExitCode,
      'stage': stage,
      'detailCode': detailCode,
      'traceAttemptClaimed': traceAttemptClaimed,
      'loggerExitCode': loggerExitCode,
      'loggerForcedTimeout': loggerForcedTimeout,
      'logger': <String, Object?>{
        'started': loggerStarted,
        'connected': loggerConnected,
        'processId': loggerProcessId,
        'runnerProcessId': runnerProcessId,
        'stopDisposition': stopDisposition,
      },
      'logs': logs == null
          ? null
          : <String, Object?>{
              'stdout': logs.stdout.toJson(),
              'stderr': logs.stderr.toJson(),
            },
      'commandJournal': commandJournal.toJson(),
      'pixelLog': pixelLog?.toJson(),
      'committedAt': DateTime.now().toUtc().toIso8601String(),
    }),
  );
  await writePlan398PrivateNoReplaceEvidence(
    stableFile: receipt,
    bytes: encoded,
    maximumLengthBytes: 16384,
  );
  return receipt;
}

Future<Plan398TraceLogFileReference> writePlan398PrivateNoReplaceEvidence({
  required File stableFile,
  required List<int> bytes,
  required int maximumLengthBytes,
}) async {
  if (maximumLengthBytes <= 0 || bytes.length > maximumLengthBytes) {
    throw const FileSystemException(
      'Plan 398 private evidence exceeds its byte bound',
    );
  }
  await stableFile.parent.create(recursive: true);
  final temporary = File(
    '${stableFile.path}.$pid.'
    '${DateTime.now().toUtc().microsecondsSinceEpoch}.private-temp',
  );
  RandomAccessFile? handle;
  try {
    await temporary.create(exclusive: true);
    final chmod = await Process.run('chmod', <String>['600', temporary.path]);
    final type = await FileSystemEntity.type(
      temporary.path,
      followLinks: false,
    );
    final before = await temporary.stat();
    if (chmod.exitCode != 0 ||
        type != FileSystemEntityType.file ||
        (before.mode & 0x1ff) != 0x180 ||
        before.size != 0) {
      throw const FileSystemException(
        'private empty Plan 398 receipt temp rejected',
      );
    }
    handle = await temporary.open(mode: FileMode.append);
    await handle.writeFrom(bytes);
    await handle.flush();
    await handle.close();
    handle = null;
    final publish = await Process.run('ln', <String>[
      temporary.path,
      stableFile.path,
    ]);
    if (publish.exitCode != 0) {
      throw FileSystemException(
        'Plan 398 private evidence no-replace publication rejected',
        stableFile.path,
      );
    }
    final stableType = await FileSystemEntity.type(
      stableFile.path,
      followLinks: false,
    );
    final stat = await stableFile.stat();
    final digest = sha256.convert(bytes).toString();
    if (stableType != FileSystemEntityType.file ||
        (stat.mode & 0x1ff) != 0x180 ||
        stat.size != bytes.length ||
        sha256.convert(await stableFile.readAsBytes()).toString() != digest) {
      throw FileSystemException(
        'Plan 398 private evidence publication verification failed',
        stableFile.path,
      );
    }
    await fsyncPlan398Directory(stableFile.parent);
    return Plan398TraceLogFileReference(
      file: stableFile,
      lengthBytes: bytes.length,
      sha256: digest,
    );
  } finally {
    try {
      await handle?.close();
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
        await fsyncPlan398Directory(stableFile.parent);
      }
    }
  }
}

Future<void> fsyncPlan398Directory(Directory directory) async {
  final type = await FileSystemEntity.type(directory.path, followLinks: false);
  if (type != FileSystemEntityType.directory) {
    throw FileSystemException(
      'Plan 398 fsync target is not a no-follow directory',
      directory.path,
    );
  }
  const script =
      'import os,sys\n'
      'fd=os.open(sys.argv[1],os.O_RDONLY|getattr(os,"O_DIRECTORY",0))\n'
      'try: os.fsync(fd)\n'
      'finally: os.close(fd)';
  final result = await Process.run('python3', <String>[
    '-c',
    script,
    directory.absolute.path,
  ]);
  if (result.exitCode != 0) {
    throw FileSystemException(
      'Plan 398 directory fsync failed',
      directory.path,
    );
  }
}

Future<GroupReactionNotificationArtifactValidation>
validatePlan398ExistingStateTraceTerminalReceipt({
  required File receiptFile,
  required String expectedScenario,
  String expectedAuthorityMode = plan398LegacyFinalAttemptAuthorityMode,
  String? expectedAuthorization,
  String? expectedFinalRunnerProductReceiptSha256,
  String? expectedFinalRunnerInstallTerminalSha256,
  String? expectedAttempt02ReceiptSha256,
  required String expectedPixelLogFileName,
  required bool requireSuccessfulTrace,
}) async {
  final failures = <String>[];
  final legacyAuthority =
      expectedAuthorityMode == plan398LegacyFinalAttemptAuthorityMode;
  final liveDiagnostic =
      expectedAuthorityMode == plan398LiveDiagnosticAuthorityMode;
  if ((!legacyAuthority && !liveDiagnostic) ||
      legacyAuthority &&
          (expectedAuthorization != plan398ReviewedFinalTraceAuthorization ||
              !_isSha256(expectedFinalRunnerProductReceiptSha256) ||
              !_isSha256(expectedFinalRunnerInstallTerminalSha256) ||
              !_isSha256(expectedAttempt02ReceiptSha256)) ||
      liveDiagnostic &&
          <Object?>[
            expectedAuthorization,
            expectedFinalRunnerProductReceiptSha256,
            expectedFinalRunnerInstallTerminalSha256,
            expectedAttempt02ReceiptSha256,
          ].any((value) => value != null) ||
      expectedPixelLogFileName != plan398PixelLogFileName('21071FDF600CSC')) {
    failures.add(r'$ terminal receipt expected authority is invalid');
  }
  if (receiptFile.uri.pathSegments.last !=
      plan398ExistingStateTraceTerminalReceiptFileName) {
    failures.add(r'$ terminal receipt filename is not canonical');
  }
  try {
    final type = await FileSystemEntity.type(
      receiptFile.path,
      followLinks: false,
    );
    final stat = await receiptFile.stat();
    if (type != FileSystemEntityType.file ||
        (stat.mode & 0x1ff) != 0x180 ||
        stat.size <= 0 ||
        stat.size > 16384) {
      failures.add(r'$ terminal receipt must be bounded private mode 0600');
      return GroupReactionNotificationArtifactValidation(failures);
    }
    final raw = await receiptFile.readAsString();
    final root = _asStringMap(jsonDecode(raw), r'$', failures);
    if (root == null) {
      return GroupReactionNotificationArtifactValidation(failures);
    }
    _expectExactKeys(
      root,
      <String>{
        'schema',
        'version',
        'scenario',
        if (legacyAuthority) ...<String>{
          'attempt',
          'authorization',
          'finalRunnerProductReceiptSha256',
          'finalRunnerInstallTerminalSha256',
          'attempt02ReceiptSha256',
        } else
          'authorityMode',
        'terminalStatus',
        'captureExitCode',
        'stage',
        'detailCode',
        'traceAttemptClaimed',
        'loggerExitCode',
        'loggerForcedTimeout',
        'logger',
        'logs',
        'commandJournal',
        'pixelLog',
        'committedAt',
      },
      r'$',
      failures,
    );
    _expectValue(
      root,
      'schema',
      legacyAuthority
          ? plan398ExistingStateTraceTerminalReceiptSchema
          : plan398ExistingStateLiveDiagnosticTerminalReceiptSchema,
      r'$',
      failures,
    );
    _expectValue(root, 'version', 1, r'$', failures);
    _expectValue(root, 'scenario', expectedScenario, r'$', failures);
    if (legacyAuthority) {
      _expectValue(
        root,
        'attempt',
        plan398ExistingStateTraceAttempt,
        r'$',
        failures,
      );
      _expectValue(
        root,
        'authorization',
        expectedAuthorization,
        r'$',
        failures,
      );
      _expectValue(
        root,
        'finalRunnerProductReceiptSha256',
        expectedFinalRunnerProductReceiptSha256,
        r'$',
        failures,
      );
      _expectValue(
        root,
        'finalRunnerInstallTerminalSha256',
        expectedFinalRunnerInstallTerminalSha256,
        r'$',
        failures,
      );
      _expectValue(
        root,
        'attempt02ReceiptSha256',
        expectedAttempt02ReceiptSha256,
        r'$',
        failures,
      );
      for (final digest in <Object?>[
        root['finalRunnerProductReceiptSha256'],
        root['finalRunnerInstallTerminalSha256'],
        root['attempt02ReceiptSha256'],
      ]) {
        if (!_isSha256(digest)) {
          failures.add(r'$ terminal authority SHA-256 is invalid');
        }
      }
    } else {
      _expectValue(
        root,
        'authorityMode',
        plan398LiveDiagnosticAuthorityMode,
        r'$',
        failures,
      );
    }
    final status = root['terminalStatus'];
    if (status is! String || !_plan398TraceTerminalStatuses.contains(status)) {
      failures.add(r'$.terminalStatus is not closed');
    }
    if (requireSuccessfulTrace && status != 'success') {
      failures.add(r'$.terminalStatus must equal success');
    }
    final captureExitCode = root['captureExitCode'];
    final loggerExitCode = root['loggerExitCode'];
    final loggerForcedTimeout = root['loggerForcedTimeout'];
    if (root['stage'] is! String || root['detailCode'] is! String) {
      failures.add(r'$.stage and $.detailCode must be strings');
    }
    if (root['traceAttemptClaimed'] is! bool ||
        captureExitCode is! int ||
        loggerExitCode is! int ||
        loggerForcedTimeout is! bool ||
        root['committedAt'] is! String ||
        DateTime.tryParse('${root['committedAt']}') == null) {
      failures.add(r'$ terminal receipt scalar fields are invalid');
    }
    final logger = _mapField(root, 'logger', r'$', failures);
    bool loggerStarted = false;
    bool loggerConnected = false;
    int? runnerProcessId;
    String? stopDisposition;
    int? stdoutLengthBytes;
    if (logger != null) {
      _expectExactKeys(
        logger,
        const <String>{
          'started',
          'connected',
          'processId',
          'runnerProcessId',
          'stopDisposition',
        },
        r'$.logger',
        failures,
      );
      loggerStarted = logger['started'] == true;
      loggerConnected = logger['connected'] == true;
      runnerProcessId = logger['runnerProcessId'] as int?;
      stopDisposition = logger['stopDisposition'] as String?;
      if (logger['started'] is! bool ||
          logger['connected'] is! bool ||
          loggerConnected && !loggerStarted ||
          loggerStarted &&
              (logger['processId'] is! int ||
                  (logger['processId']! as int) <= 0) ||
          !loggerStarted && logger['processId'] != null ||
          runnerProcessId != null && runnerProcessId <= 0 ||
          !<String>{
            'graceful',
            'already_exited',
            'forced_kill',
            'not_started',
          }.contains(stopDisposition)) {
        failures.add(r'$.logger state is inconsistent');
      }
    }
    final logsValue = root['logs'];
    if (logsValue != null) {
      final logs = _asStringMap(logsValue, r'$.logs', failures);
      if (logs != null) {
        _expectExactKeys(
          logs,
          const <String>{'stdout', 'stderr'},
          r'$.logs',
          failures,
        );
        await _validatePlan398TerminalLogReference(
          value: logs['stdout'],
          receiptDirectory: receiptFile.parent,
          expectedFileName: plan398ExistingStateTraceIosStdoutFileName,
          maximumLengthBytes: plan398ExistingStateTraceIosStdoutLimitBytes,
          path: r'$.logs.stdout',
          failures: failures,
        );
        await _validatePlan398TerminalLogReference(
          value: logs['stderr'],
          receiptDirectory: receiptFile.parent,
          expectedFileName: plan398ExistingStateTraceIosStderrFileName,
          maximumLengthBytes: plan398ExistingStateTraceIosStderrLimitBytes,
          path: r'$.logs.stderr',
          failures: failures,
        );
        final stdout = _asStringMap(logs['stdout'], r'$.logs.stdout', failures);
        stdoutLengthBytes = stdout?['lengthBytes'] as int?;
      }
    }
    if (status == 'success' &&
        (captureExitCode != 0 ||
            !loggerStarted ||
            !loggerConnected ||
            runnerProcessId == null ||
            logsValue == null ||
            stdoutLengthBytes == null ||
            stdoutLengthBytes <= 0 ||
            stopDisposition != 'graceful')) {
      failures.add(r'$ successful terminal receipt is incomplete');
    }
    if (status != 'success' && captureExitCode == 0) {
      failures.add(r'$ failed terminal receipt has zero capture exit');
    }
    if (loggerStarted && logsValue == null) {
      failures.add(r'$ logger-started terminal receipt omitted raw logs');
    }
    if (status == 'success' && runnerProcessId != null) {
      try {
        final stdoutBytes = await File(
          '${receiptFile.parent.path}${Platform.pathSeparator}'
          '$plan398ExistingStateTraceIosStdoutFileName',
        ).readAsBytes();
        final stdout = utf8.decode(stdoutBytes, allowMalformed: true);
        if (!plan398ExistingStateNotificationAuthorizationReady(
          stdout,
          expectedRunnerProcessId: runnerProcessId,
        )) {
          failures.add(
            r'$ successful terminal receipt lacks its exact public '
            'Runner settings record',
          );
        }
      } on Object {
        failures.add(r'$ successful terminal receipt stdout is unreadable');
      }
    }
    if (status == 'logger_forced_kill' &&
        (stopDisposition != 'forced_kill' || loggerForcedTimeout != true)) {
      failures.add(r'$ forced-kill terminal receipt is inconsistent');
    }
    final pixelLogValue = root['pixelLog'];
    if (status == 'pre_logger_failure' &&
        (loggerStarted ||
            loggerConnected ||
            runnerProcessId != null ||
            stopDisposition != 'not_started' ||
            loggerExitCode != -1 ||
            loggerForcedTimeout != false ||
            logsValue != null)) {
      failures.add(r'$ pre-logger terminal receipt retained logger state');
    }
    if (status != 'pre_logger_failure' && pixelLogValue == null) {
      failures.add(r'$ non-pre-logger terminal receipt omitted Pixel log');
    }
    await _validatePlan398TerminalLogReference(
      value: root['commandJournal'],
      receiptDirectory: receiptFile.parent,
      expectedFileName: plan398ExistingStateTraceCommandJournalFileName,
      maximumLengthBytes: plan398ExistingStateTraceJournalLimitBytes,
      path: r'$.commandJournal',
      failures: failures,
    );
    if (pixelLogValue != null) {
      await _validatePlan398TerminalLogReference(
        value: pixelLogValue,
        receiptDirectory: receiptFile.parent,
        expectedFileName: expectedPixelLogFileName,
        maximumLengthBytes: plan398ExistingStateTracePixelLogLimitBytes,
        path: r'$.pixelLog',
        failures: failures,
      );
    }
    for (final entry in <MapEntry<String, Object?>>[
      MapEntry<String, Object?>('commandJournal', root['commandJournal']),
      if (pixelLogValue != null)
        MapEntry<String, Object?>('pixelLog', pixelLogValue),
    ]) {
      final reference = _asStringMap(entry.value, '\$.${entry.key}', failures);
      if (reference?['lengthBytes'] is! int ||
          (reference!['lengthBytes']! as int) <= 0) {
        failures.add('\$.${entry.key} must bind non-empty bytes');
      }
    }
  } on Object {
    failures.add(r'$ terminal receipt is unreadable or invalid');
  }
  return GroupReactionNotificationArtifactValidation(failures);
}

Future<void> _validatePlan398TerminalLogReference({
  required Object? value,
  required Directory receiptDirectory,
  required String expectedFileName,
  required int maximumLengthBytes,
  required String path,
  required List<String> failures,
}) async {
  final reference = _asStringMap(value, path, failures);
  if (reference == null) return;
  _expectExactKeys(
    reference,
    const <String>{'fileName', 'lengthBytes', 'sha256', 'mode'},
    path,
    failures,
  );
  _expectValue(reference, 'fileName', expectedFileName, path, failures);
  _expectValue(reference, 'mode', '0600', path, failures);
  final length = reference['lengthBytes'];
  final digest = reference['sha256'];
  if (length is! int ||
      length < 0 ||
      length > maximumLengthBytes ||
      !_isSha256(digest)) {
    failures.add('$path length or SHA-256 is invalid');
    return;
  }
  final file = File(
    '${receiptDirectory.path}${Platform.pathSeparator}$expectedFileName',
  );
  try {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    final stat = await file.stat();
    final bytes = await file.readAsBytes();
    if (type != FileSystemEntityType.file ||
        (stat.mode & 0x1ff) != 0x180 ||
        stat.size != length ||
        sha256.convert(bytes).toString() != digest) {
      failures.add('$path is not bound to durable private bytes');
    }
  } on Object {
    failures.add('$path durable bytes are missing or unreadable');
  }
}

enum Plan398NativeObservationDisposition {
  behaviorPass,
  captureEvidence,
  environmentEvidence,
}

Plan398NativeObservationDisposition classifyPlan398NativeObservationReceipt({
  required int subprocessExitCode,
  required Object? receipt,
  required String phase,
  required String captureNonceSha256,
  required String receiverDeviceIdSha256,
  required String expectedGroupIdSha256,
  required String expectedEventIdSha256,
  required String expectedTargetMessageIdSha256,
  required String expectedCollapseIdentifierSha256,
}) {
  if (subprocessExitCode < 0 || receipt is! Map) {
    return Plan398NativeObservationDisposition.environmentEvidence;
  }
  Map<String, Object?> value;
  try {
    value = Map<String, Object?>.from(receipt);
  } on Object {
    return Plan398NativeObservationDisposition.environmentEvidence;
  }
  final status = value['status'];
  if ((status == 'PASS' && subprocessExitCode != 0) ||
      (status == 'FAIL' && subprocessExitCode <= 0)) {
    return Plan398NativeObservationDisposition.environmentEvidence;
  }
  final valid = _isValidPlan398NativeObservationReceipt(
    value,
    phase: phase,
    captureNonceSha256: captureNonceSha256,
    receiverDeviceIdSha256: receiverDeviceIdSha256,
    expectedGroupIdSha256: expectedGroupIdSha256,
    expectedEventIdSha256: expectedEventIdSha256,
    expectedTargetMessageIdSha256: expectedTargetMessageIdSha256,
    expectedCollapseIdentifierSha256: expectedCollapseIdentifierSha256,
  );
  if (!valid) {
    return Plan398NativeObservationDisposition.environmentEvidence;
  }
  return value['status'] == 'FAIL'
      ? Plan398NativeObservationDisposition.captureEvidence
      : Plan398NativeObservationDisposition.behaviorPass;
}

bool _isValidPlan398NativeObservationReceipt(
  Map<String, Object?> value, {
  required String phase,
  required String captureNonceSha256,
  required String receiverDeviceIdSha256,
  required String expectedGroupIdSha256,
  required String expectedEventIdSha256,
  required String expectedTargetMessageIdSha256,
  required String expectedCollapseIdentifierSha256,
}) {
  const exactKeys = <String>{
    'schema',
    'action',
    'phase',
    'status',
    'containsSecrets',
    'bundleId',
    'captureNonceSha256',
    'receiverDeviceIdSha256',
    'expectedGroupIdSha256',
    'expectedEventIdSha256',
    'expectedTargetMessageIdSha256',
    'expectedCollapseIdentifierSha256',
    'matchingRemoteCount',
    'matchingLocalCount',
    'matchingUsefulProviderCount',
    'matchingSanitizedProviderCount',
    'matchingFlutterLocalCount',
    'matchingUnknownCount',
    'matchingTotalCount',
    'stableSampleCount',
    'stableSampleIntervalMilliseconds',
    'observationDeadlineMilliseconds',
    'sampledThroughDeadline',
    'badSourceSeen',
    'duplicateSeen',
    'requestIdentifierSha256',
    'diagnosticSchema',
    'diagnosticRecords',
    'diagnosticRecordCount',
    'diagnosticOverflow',
    'diagnosticConflict',
    'diagnosticComplete',
    'childBuildCount',
    'manualActionCount',
    'runnerTerminated',
    'preTapCleanupLaunchCount',
    'resultCode',
    'completedAt',
  };
  const integerKeys = <String>{
    'matchingRemoteCount',
    'matchingLocalCount',
    'matchingUsefulProviderCount',
    'matchingSanitizedProviderCount',
    'matchingFlutterLocalCount',
    'matchingUnknownCount',
    'matchingTotalCount',
    'stableSampleCount',
    'stableSampleIntervalMilliseconds',
    'observationDeadlineMilliseconds',
    'diagnosticRecordCount',
    'childBuildCount',
    'manualActionCount',
    'preTapCleanupLaunchCount',
  };
  const booleanKeys = <String>{
    'sampledThroughDeadline',
    'badSourceSeen',
    'duplicateSeen',
    'diagnosticOverflow',
    'diagnosticConflict',
    'diagnosticComplete',
    'runnerTerminated',
  };
  final expectedBindings = <String, String>{
    'captureNonceSha256': captureNonceSha256,
    'receiverDeviceIdSha256': receiverDeviceIdSha256,
    'expectedGroupIdSha256': expectedGroupIdSha256,
    'expectedEventIdSha256': expectedEventIdSha256,
    'expectedTargetMessageIdSha256': expectedTargetMessageIdSha256,
    'expectedCollapseIdentifierSha256': expectedCollapseIdentifierSha256,
  };
  if (value.keys.toSet().difference(exactKeys).isNotEmpty ||
      exactKeys.difference(value.keys.toSet()).isNotEmpty ||
      value['schema'] != plan398IosGroupObservationHostReceiptSchema ||
      value['action'] != 'observe-group' ||
      value['phase'] != phase ||
      !const <String>{'message', 'reaction'}.contains(phase) ||
      !const <String>{'PASS', 'FAIL'}.contains(value['status']) ||
      value['containsSecrets'] != false ||
      value['bundleId'] != 'com.mknoon.app' ||
      integerKeys.any(
        (key) => value[key] is! int || (value[key]! as int).isNegative,
      ) ||
      booleanKeys.any((key) => value[key] is! bool) ||
      expectedBindings.entries.any(
        (entry) => !_isSha256(entry.value) || value[entry.key] != entry.value,
      ) ||
      value['diagnosticSchema'] != plan398IosGroupObservationDiagnosticSchema ||
      value['runnerTerminated'] != true ||
      value['preTapCleanupLaunchCount'] != 0 ||
      value['resultCode'] is! String ||
      value['completedAt'] is! String ||
      DateTime.tryParse(value['completedAt']! as String) == null) {
    return false;
  }

  final identifiers = value['requestIdentifierSha256'];
  if (identifiers is! List ||
      identifiers.length > 8 ||
      identifiers.length != value['matchingTotalCount'] ||
      identifiers.any((identifier) => !_isSha256(identifier)) ||
      identifiers.toSet().length != identifiers.length) {
    return false;
  }
  final identifierHashes = identifiers.cast<String>();
  final sortedIdentifiers = identifierHashes.toList()..sort();
  if (!_sameStringList(identifierHashes, sortedIdentifiers)) return false;
  final identifierHashSet = identifierHashes.toSet();

  final rawRecords = value['diagnosticRecords'];
  if (rawRecords is! List || rawRecords.length > 8) return false;
  final records = <Map<String, Object?>>[];
  for (final rawRecord in rawRecords) {
    if (rawRecord is! Map) return false;
    Map<String, Object?> record;
    try {
      record = Map<String, Object?>.from(rawRecord);
    } on Object {
      return false;
    }
    if (!_isValidPlan398DiagnosticRecord(
      record,
      expectedCollapseIdentifierSha256: expectedCollapseIdentifierSha256,
    )) {
      return false;
    }
    records.add(record);
  }
  final recordHashes = records
      .map((record) => record['requestIdentifierSha256']! as String)
      .toList(growable: false);
  final sortedRecordHashes = recordHashes.toList()..sort();
  if (!_sameStringList(recordHashes, sortedRecordHashes) ||
      recordHashes.toSet().length != recordHashes.length ||
      identifierHashSet.difference(recordHashes.toSet()).isNotEmpty ||
      value['diagnosticRecordCount'] != records.length) {
    return false;
  }
  final inventoryRecords = records
      .where(
        (record) => identifierHashSet.contains(
          record['requestIdentifierSha256']! as String,
        ),
      )
      .toList(growable: false);
  final computedComplete =
      value['sampledThroughDeadline'] == true &&
      value['diagnosticOverflow'] == false &&
      value['diagnosticConflict'] == false &&
      records.isNotEmpty;
  if (value['diagnosticComplete'] != computedComplete) return false;

  final remote = value['matchingRemoteCount']! as int;
  final local = value['matchingLocalCount']! as int;
  final useful = value['matchingUsefulProviderCount']! as int;
  final sanitized = value['matchingSanitizedProviderCount']! as int;
  final flutterLocal = value['matchingFlutterLocalCount']! as int;
  final unknown = value['matchingUnknownCount']! as int;
  final total = value['matchingTotalCount']! as int;
  if (remote + local != total ||
      useful + sanitized + flutterLocal + unknown != total ||
      inventoryRecords.length != total) {
    return false;
  }
  if (inventoryRecords
              .where((record) => record['triggerOrigin'] == 'remote')
              .length !=
          remote ||
      inventoryRecords
              .where((record) => record['triggerOrigin'] == 'local')
              .length !=
          local ||
      inventoryRecords
              .where((record) => record['sourceClass'] == 'usefulProviderRich')
              .length !=
          useful ||
      inventoryRecords
              .where(
                (record) => record['sourceClass'] == 'sanitizedProviderRich',
              )
              .length !=
          sanitized ||
      inventoryRecords
              .where((record) => record['sourceClass'] == 'flutterLocal')
              .length !=
          flutterLocal ||
      inventoryRecords
              .where((record) => record['sourceClass'] == 'unknown')
              .length !=
          unknown) {
    return false;
  }

  final exactRecord = records.length == 1 ? records.single : null;
  final exactUsefulSource =
      value['sampledThroughDeadline'] == true &&
      value['diagnosticComplete'] == true &&
      value['stableSampleCount'] == 3 &&
      value['badSourceSeen'] == false &&
      value['duplicateSeen'] == false &&
      value['diagnosticOverflow'] == false &&
      value['diagnosticConflict'] == false &&
      remote == 1 &&
      local == 0 &&
      useful == 1 &&
      sanitized == 0 &&
      flutterLocal == 0 &&
      unknown == 0 &&
      total == 1 &&
      identifierHashes.length == 1 &&
      identifierHashes.single == expectedCollapseIdentifierSha256 &&
      exactRecord != null &&
      exactRecord['requestIdentifierSha256'] ==
          expectedCollapseIdentifierSha256 &&
      exactRecord['expectedCollapseIdentifierMatch'] == true &&
      exactRecord['triggerOrigin'] == 'remote' &&
      exactRecord['sourceClass'] == 'usefulProviderRich' &&
      exactRecord['reason'] == 'exactUseful';
  if (exactUsefulSource) {
    if (value['status'] != 'PASS' || value['resultCode'] != 'ok') return false;
  } else {
    if (value['status'] != 'FAIL') return false;
    final String expectedFailureResultCode;
    if (value['sampledThroughDeadline'] != true ||
        value['stableSampleCount'] != 3) {
      expectedFailureResultCode = 'source_inventory_unstable';
    } else if (value['badSourceSeen'] == true) {
      expectedFailureResultCode = 'bad_source_seen';
    } else if (value['duplicateSeen'] == true) {
      expectedFailureResultCode = 'duplicate_seen';
    } else {
      expectedFailureResultCode = 'source_inventory_mismatch';
    }
    if (value['resultCode'] != expectedFailureResultCode) return false;
  }

  if (value['status'] == 'PASS') {
    if (value['resultCode'] != 'ok' ||
        remote != 1 ||
        local != 0 ||
        useful != 1 ||
        sanitized != 0 ||
        flutterLocal != 0 ||
        unknown != 0 ||
        total != 1 ||
        value['stableSampleCount'] != 3 ||
        value['stableSampleIntervalMilliseconds'] != 500 ||
        value['observationDeadlineMilliseconds'] != 8000 ||
        value['sampledThroughDeadline'] != true ||
        value['badSourceSeen'] != false ||
        value['duplicateSeen'] != false ||
        value['diagnosticComplete'] != true ||
        records.length != 1 ||
        records.single['triggerOrigin'] != 'remote' ||
        records.single['sourceClass'] != 'usefulProviderRich' ||
        records.single['reason'] != 'exactUseful' ||
        records.single['expectedCollapseIdentifierMatch'] != true ||
        value['childBuildCount'] != 0 ||
        value['manualActionCount'] != 0) {
      return false;
    }
  }
  return true;
}

bool _isValidPlan398DiagnosticRecord(
  Map<String, Object?> record, {
  required String expectedCollapseIdentifierSha256,
}) {
  const keys = <String>{
    'requestIdentifierSha256',
    'dispatchCorrelationSha256',
    'claimedCollapseIdentifierSha256',
    'providerMessageIdSha256',
    'triggerOrigin',
    'sourceClass',
    'reason',
    'expectedCollapseIdentifierMatch',
    'dispatchClaim',
  };
  if (record.keys.toSet().difference(keys).isNotEmpty ||
      keys.difference(record.keys.toSet()).isNotEmpty ||
      !_isSha256(record['requestIdentifierSha256']) ||
      !_isNullableSha256(record['dispatchCorrelationSha256']) ||
      !_isNullableSha256(record['claimedCollapseIdentifierSha256']) ||
      !_isNullableSha256(record['providerMessageIdSha256']) ||
      record['expectedCollapseIdentifierMatch'] is! bool ||
      record['expectedCollapseIdentifierMatch'] !=
          (record['requestIdentifierSha256'] ==
              expectedCollapseIdentifierSha256) ||
      !const <String>{
        'groupInbox',
        'groupContent',
        'absent',
        'invalid',
      }.contains(record['dispatchClaim'])) {
    return false;
  }
  final triple = (
    record['triggerOrigin'],
    record['sourceClass'],
    record['reason'],
  );
  return const <(Object?, Object?, Object?)>{
    ('remote', 'usefulProviderRich', 'exactUseful'),
    ('remote', 'sanitizedProviderRich', 'exactSanitized'),
    ('local', 'flutterLocal', 'exactFlutterLocal'),
    ('remote', 'unknown', 'missingOrInvalidType'),
    ('remote', 'unknown', 'groupHashMismatch'),
    ('remote', 'unknown', 'partialContent'),
    ('remote', 'unknown', 'unclassifiedRemote'),
    ('local', 'unknown', 'groupHashMismatch'),
    ('local', 'unknown', 'unclassifiedLocal'),
  }.contains(triple);
}

bool _sameStringList(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

/// Returns whether one complete AppDelegate settings record proves that iOS
/// notifications are authorized and both alert and badge presentation remain
/// enabled.
///
/// Installed builds can render imported UserNotifications enums either as
/// normalized case names or as Swift raw-value descriptions. Values are bound
/// within one exact diagnostic line so unrelated or partial syslog records can
/// never be combined into a readiness claim.
bool plan398ExistingStateNotificationAuthorizationReady(
  String systemLogWindow, {
  int? expectedRunnerProcessId,
}) {
  const marker = '[PUSH_DIAG] native_notification_settings ';
  final normalizedReadyPattern = RegExp(
    r'^context=\S+ '
    r'authorization=(authorized|provisional|ephemeral) '
    r'alert=enabled badge=enabled '
    r'sound=(enabled|disabled|not_supported)$',
  );
  final rawReadyPattern = RegExp(
    r'^context=\S+ '
    r'authorization=UNAuthorizationStatus\(rawValue: [234]\) '
    r'alert=UNNotificationSetting\(rawValue: 2\) '
    r'badge=UNNotificationSetting\(rawValue: 2\) '
    r'sound=UNNotificationSetting\(rawValue: [012]\)$',
  );

  for (final line in const LineSplitter().convert(systemLogWindow)) {
    final markerIndex = line.indexOf(marker);
    if (markerIndex < 0 || markerIndex != line.lastIndexOf(marker)) continue;
    if (expectedRunnerProcessId != null) {
      final runnerPid = RegExp(
        'Runner\\[$expectedRunnerProcessId\\]',
      ).allMatches(line.substring(0, markerIndex));
      if (runnerPid.length != 1) continue;
    }
    final record = line.substring(markerIndex + marker.length).trimRight();
    if (normalizedReadyPattern.hasMatch(record) ||
        rawReadyPattern.hasMatch(record)) {
      return true;
    }
  }
  return false;
}

bool groupReactionNotificationKeepsRecipientProcessAlive(String scenarioId) =>
    _processAliveReactionScenarioIds.contains(scenarioId);

/// Canonical Android text-target reaction copy after Plan 330.
///
/// The emoji remains part of the authenticated reaction transition, but the
/// notification preview deliberately exposes only the trusted actor and the
/// locally derived semantic target kind.
String groupReactionNotificationExpectedAndroidReactionBody(String actorName) =>
    '$actorName reacted to your message';

/// The throwaway group a killed-recipient reaction lane warms its background
/// isolate through.
///
/// DERIVED from the graded group's name rather than measured. `$.measurements`
/// is exact-keyed (`_expectExactKeys` at the bottom of this file), so a new
/// measurement key would reject every artifact this lane has ever written. The
/// capture driver and the validator both call this one function, so the two
/// sides cannot drift.
///
/// The digest is what keeps the two names free of any substring relation. A
/// plain prefix or suffix of the graded name would make the warm-up group's
/// Orbit row — `Open group <warm-up>, 1 unread message` — satisfy a
/// `contains('Open group <graded>')` test, both in this file's raw UI checks
/// and in `findSemanticNodeCenter`, whose fallback arm matches on containment.
String groupReactionNotificationWarmupGroupName(String gradedGroupName) =>
    'Warmup'
    '${sha256.convert(utf8.encode(gradedGroupName)).toString().substring(0, 12)}';

/// Builds a least-disclosure probe for the rollout flag inherited by the
/// running relay process. `systemctl show --property=Environment` omits values
/// loaded through EnvironmentFile, which is how the deployed relay is wired.
List<String> groupReactionRelayProcessFlagProbe(String mainPid) {
  if (!RegExp(r'^[1-9][0-9]*$').hasMatch(mainPid)) {
    throw const FormatException('relay MainPID must be a positive integer');
  }
  return <String>[
    'sudo',
    'grep',
    '-z',
    '-x',
    '-E',
    r'GROUP_REACTION_PUSH_ENABLED=(1|true)',
    '/proc/$mainPid/environ',
  ];
}

class GroupReactionNotificationStagingValidation {
  GroupReactionNotificationStagingValidation(List<String> failures)
    : failures = List<String>.unmodifiable(failures);

  final List<String> failures;

  bool get ok => failures.isEmpty;

  String get detail => ok ? 'accepted' : failures.join('; ');
}

/// Validates the declared, redacted staging configuration.
///
/// This is deliberately not a proof of relay/provider readiness. The capture
/// driver independently checks the live relay process, binary digest, rollout
/// flag, provider credentials/config, target inventory, and the eventual
/// provider delivery record before it can emit a passing artifact.
GroupReactionNotificationStagingValidation
validateGroupReactionNotificationStagingManifest(
  Map<String, Object?> value, {
  required GroupReactionNotificationScenario scenario,
}) {
  final failures = <String>[];
  _expectExactKeys(
    value,
    <String>{
      'schema',
      'version',
      'environment',
      'relayActive',
      'providerConfigured',
      'providerProbeSucceeded',
      'productionDeploymentPerformed',
      'allowAppDataReset',
      'candidateRelayRevision',
      'candidateRelaySha256',
      'provider',
      'relayAddresses',
      if (scenario.recipientPlatform == 'ios') 'iosCapture',
    },
    r'$',
    failures,
  );
  _expectValue(
    value,
    'schema',
    groupReactionNotificationStagingSchema,
    r'$',
    failures,
  );
  _expectValue(value, 'version', 1, r'$', failures);
  _expectValue(value, 'environment', 'staging', r'$', failures);
  _expectValue(value, 'relayActive', true, r'$', failures);
  _expectValue(value, 'providerConfigured', true, r'$', failures);
  _expectValue(value, 'providerProbeSucceeded', true, r'$', failures);
  _expectValue(value, 'productionDeploymentPerformed', false, r'$', failures);
  _expectValue(value, 'allowAppDataReset', true, r'$', failures);
  _expectValue(
    value,
    'provider',
    scenario.recipientPlatform == 'ios' ? 'apns' : 'fcm',
    r'$',
    failures,
  );
  for (final key in const <String>[
    'candidateRelayRevision',
    'candidateRelaySha256',
  ]) {
    _requiredString(value, key, r'$', failures);
  }
  final digest = value['candidateRelaySha256'];
  if (digest is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
    failures.add(r'$.candidateRelaySha256 must be a lowercase SHA-256 digest');
  }
  final relayAddresses = value['relayAddresses'];
  if (relayAddresses is! List || relayAddresses.isEmpty) {
    failures.add(r'$.relayAddresses must be a non-empty list');
  } else {
    for (var index = 0; index < relayAddresses.length; index++) {
      final address = relayAddresses[index];
      if (address is! String ||
          address.trim().isEmpty ||
          address.contains(RegExp(r'[\r\n]'))) {
        failures.add(r'$.relayAddresses must contain safe non-empty strings');
        break;
      }
    }
  }
  if (scenario.recipientPlatform == 'ios') {
    final iosCapture = _mapField(value, 'iosCapture', r'$', failures);
    if (iosCapture != null) {
      _expectExactKeys(
        iosCapture,
        const <String>{
          'bundleId',
          'workspace',
          'scheme',
          'fixtureCreateSelector',
          'fixtureAuthorSelector',
          'notificationPrepareSelector',
          'notificationTapSelector',
          'systemLogExecutable',
        },
        r'$.iosCapture',
        failures,
      );
      _expectValue(
        iosCapture,
        'bundleId',
        'com.mknoon.app',
        r'$.iosCapture',
        failures,
      );
      _expectValue(
        iosCapture,
        'workspace',
        'ios/Runner.xcworkspace',
        r'$.iosCapture',
        failures,
      );
      _expectValue(iosCapture, 'scheme', 'Runner', r'$.iosCapture', failures);
      final requiredSelectors = groupReactionNotificationIosSelectorsFor(
        scenario,
      );
      for (final entry in requiredSelectors.entries) {
        _expectValue(
          iosCapture,
          entry.key,
          entry.value,
          r'$.iosCapture',
          failures,
        );
      }
      _expectValue(
        iosCapture,
        'systemLogExecutable',
        'idevicesyslog',
        r'$.iosCapture',
        failures,
      );
    }
  }
  return GroupReactionNotificationStagingValidation(failures);
}

/// Validates the private, non-mutating authority used by the installed-state
/// trace. Unlike the general Plan-257 manifest, this branch cannot authorize
/// app-data reset and does not pretend that unused XCTest selectors are part
/// of a build-free observation.
GroupReactionNotificationStagingValidation
validatePlan398ExistingStateTraceManifest(Map<String, Object?> value) {
  final failures = <String>[];
  _expectExactKeys(
    value,
    const <String>{
      'schema',
      'version',
      'environment',
      'relayActive',
      'providerConfigured',
      'providerProbeSucceeded',
      'productionDeploymentPerformed',
      'allowAppDataReset',
      'candidateRelayRevision',
      'candidateRelaySha256',
      'provider',
      'relayAddresses',
      'iosCapture',
    },
    r'$',
    failures,
  );
  for (final entry in const <String, Object?>{
    'schema': plan398ExistingStateTraceManifestSchema,
    'version': 1,
    'environment': 'staging',
    'relayActive': true,
    'providerConfigured': true,
    'providerProbeSucceeded': true,
    'productionDeploymentPerformed': false,
    'allowAppDataReset': false,
    'provider': 'apns',
  }.entries) {
    _expectValue(value, entry.key, entry.value, r'$', failures);
  }
  _requiredString(value, 'candidateRelayRevision', r'$', failures);
  if (!_isSha256(value['candidateRelaySha256'])) {
    failures.add(r'$.candidateRelaySha256 must be a lowercase SHA-256 digest');
  }
  final relayAddresses = value['relayAddresses'];
  if (relayAddresses is! List || relayAddresses.isEmpty) {
    failures.add(r'$.relayAddresses must be a non-empty list');
  } else {
    for (final address in relayAddresses) {
      if (address is! String ||
          address.trim().isEmpty ||
          address.contains(RegExp(r'[\r\n]'))) {
        failures.add(r'$.relayAddresses must contain safe non-empty strings');
        break;
      }
    }
  }
  final iosCapture = _mapField(value, 'iosCapture', r'$', failures);
  if (iosCapture != null) {
    _expectExactKeys(
      iosCapture,
      const <String>{'bundleId', 'systemLogExecutable'},
      r'$.iosCapture',
      failures,
    );
    _expectValue(
      iosCapture,
      'bundleId',
      'com.mknoon.app',
      r'$.iosCapture',
      failures,
    );
    _expectValue(
      iosCapture,
      'systemLogExecutable',
      'idevicesyslog',
      r'$.iosCapture',
      failures,
    );
  }
  return GroupReactionNotificationStagingValidation(failures);
}

Map<String, String> groupReactionNotificationIosSelectorsFor(
  GroupReactionNotificationScenario scenario,
) {
  const owner = 'RunnerUITests/NotificationTapUITests/';
  if (scenario.id == iosChatGroupMessageAndReactionScenarioId) {
    return const <String, String>{
      'fixtureCreateSelector': '${owner}testCreateChatGroupNotificationFixture',
      'fixtureAuthorSelector': '${owner}testAuthorChatGroupReactionTarget',
      'notificationPrepareSelector': '${owner}testPrepareWarmNotificationTap',
      'notificationTapSelector': '${owner}testChatGroupNotificationTap',
    };
  }
  return const <String, String>{
    'fixtureCreateSelector': '${owner}testCreateAnnouncementReactionFixture',
    'fixtureAuthorSelector': '${owner}testAuthorAnnouncementReactionTarget',
    'notificationPrepareSelector': '${owner}testPrepareWarmNotificationTap',
    'notificationTapSelector':
        '${owner}testAnnouncementReactionNotificationTap',
  };
}

final class GroupReactionCentralBuildValidation {
  GroupReactionCentralBuildValidation({
    required List<String> failures,
    this.profileId,
    this.inputDigest,
    this.artifactDigest,
    this.attestation,
  }) : failures = List<String>.unmodifiable(failures);

  final List<String> failures;
  final String? profileId;
  final String? inputDigest;
  final String? artifactDigest;
  final File? attestation;

  bool get ok => failures.isEmpty;

  String get detail => ok ? 'accepted' : failures.join('; ');

  Map<String, Object?> get redactedProvenance => <String, Object?>{
    if (profileId != null) 'profileId': profileId,
    if (inputDigest != null) 'inputDigest': inputDigest,
    if (artifactDigest != null) 'artifactDigest': artifactDigest,
    'attestationAdjacent': attestation != null,
  };
}

/// Verifies a Sims build report against the cache-adjacent attestation and the
/// exact artifact bytes. No environment path can substitute for this join.
GroupReactionCentralBuildValidation validateGroupReactionCentralBuildArtifact({
  required String profileId,
  required FileSystemEntity artifact,
  required File buildReport,
  DateTime? now,
}) {
  final failures = <String>[];
  String? reportDigest;
  String? inputDigest;
  String? attestedDigest;
  File? attestationFile;
  final artifactType = FileSystemEntity.typeSync(
    artifact.path,
    followLinks: false,
  );
  if (artifactType != FileSystemEntityType.file &&
      artifactType != FileSystemEntityType.directory) {
    failures.add('central artifact must be a regular file or directory');
  }
  if (FileSystemEntity.typeSync(buildReport.path, followLinks: false) !=
      FileSystemEntityType.file) {
    failures.add('central build report is missing or not a regular file');
  } else {
    try {
      final decoded = jsonDecode(buildReport.readAsStringSync());
      if (decoded is! Map) {
        failures.add('central build report root must be an object');
      } else {
        final report = decoded.map<String, Object?>(
          (key, value) => MapEntry('$key', value),
        );
        final generatedAt = DateTime.tryParse('${report['generatedAt']}');
        final reference = (now ?? DateTime.now()).toUtc();
        if (generatedAt == null ||
            generatedAt.toUtc().isAfter(
              reference.add(const Duration(minutes: 1)),
            ) ||
            reference.difference(generatedAt.toUtc()) >
                const Duration(hours: 1)) {
          failures.add('central build report is stale or has invalid time');
        }
        final builds = report['builds'];
        final digests = builds is Map ? builds['artifactDigests'] : null;
        final candidate = digests is Map ? digests[profileId] : null;
        if (!_isSha256(candidate)) {
          failures.add('central build report lacks the exact profile digest');
        } else {
          reportDigest = candidate! as String;
        }
        final failedProfiles = builds is Map
            ? builds['failedProfileIds']
            : null;
        if (failedProfiles is List && failedProfiles.contains(profileId)) {
          failures.add('central build report marks the profile failed');
        }
      }
    } on Object {
      failures.add('central build report is not valid JSON');
    }
  }

  if (artifactType == FileSystemEntityType.file ||
      artifactType == FileSystemEntityType.directory) {
    final parent = artifact is File
        ? artifact.absolute.parent
        : (artifact as Directory).absolute.parent;
    attestationFile = File(
      '${parent.path}${Platform.pathSeparator}attestation.json',
    );
    if (FileSystemEntity.typeSync(attestationFile.path, followLinks: false) !=
        FileSystemEntityType.file) {
      failures.add('cache-adjacent attestation is missing');
    } else {
      try {
        final decoded = jsonDecode(attestationFile.readAsStringSync());
        if (decoded is! Map) {
          failures.add('cache-adjacent attestation root must be an object');
        } else {
          final attestation = decoded.map<String, Object?>(
            (key, value) => MapEntry('$key', value),
          );
          inputDigest = attestation['inputDigest'] as String?;
          attestedDigest = attestation['artifactDigest'] as String?;
          final attestedPath = attestation['artifactPath'];
          if (attestation['schemaVersion'] != 1 ||
              attestation['profileId'] != profileId ||
              !_isSha256(inputDigest) ||
              !_isSha256(attestedDigest) ||
              attestedPath is! String ||
              File(attestedPath).absolute.path != artifact.absolute.path ||
              parent.uri.pathSegments
                      .where((segment) => segment.isNotEmpty)
                      .last !=
                  inputDigest) {
            failures.add('cache-adjacent attestation is not artifact-bound');
          }
        }
      } on Object {
        failures.add('cache-adjacent attestation is not valid JSON');
      }
    }
    try {
      final actualDigest = groupReactionSimsArtifactDigest(artifact);
      if (reportDigest != null && actualDigest != reportDigest) {
        failures.add('central artifact digest does not match build report');
      }
      if (attestedDigest != null && actualDigest != attestedDigest) {
        failures.add('central artifact digest does not match attestation');
      }
    } on FormatException catch (error) {
      failures.add(error.message);
    }
  }
  if (reportDigest != null &&
      attestedDigest != null &&
      reportDigest != attestedDigest) {
    failures.add('build report and attestation artifact digests differ');
  }

  return GroupReactionCentralBuildValidation(
    failures: failures,
    profileId: profileId,
    inputDigest: inputDigest,
    artifactDigest: attestedDigest ?? reportDigest,
    attestation: attestationFile,
  );
}

/// Matches the content-addressed directory digest used by the Sims cache,
/// including modes and symlink targets.
String groupReactionSimsArtifactDigest(FileSystemEntity entity) {
  final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
  if (type == FileSystemEntityType.file) {
    return sha256.convert(File(entity.path).readAsBytesSync()).toString();
  }
  if (type != FileSystemEntityType.directory) {
    throw const FormatException(
      'central artifact must be a regular file or directory',
    );
  }
  final root = Directory(entity.path).absolute;
  final records = <String>[];
  final entries = root.listSync(recursive: true, followLinks: false)
    ..sort((left, right) => left.path.compareTo(right.path));
  for (final entry in entries) {
    final relative = entry.path.substring(root.path.length + 1);
    final entryType = FileSystemEntity.typeSync(entry.path, followLinks: false);
    switch (entryType) {
      case FileSystemEntityType.file:
        final mode = entry.statSync().mode & 0x1ff;
        records.add(
          'file\t$relative\t${mode.toRadixString(8)}\t'
          '${sha256.convert(File(entry.path).readAsBytesSync())}',
        );
      case FileSystemEntityType.directory:
        final mode = entry.statSync().mode & 0x1ff;
        records.add('directory\t$relative\t${mode.toRadixString(8)}');
      case FileSystemEntityType.link:
        records.add('link\t$relative\t${Link(entry.path).targetSync()}');
      case FileSystemEntityType.notFound:
        records.add('missing\t$relative');
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        throw FormatException(
          'central artifact contains unsupported entry $relative',
        );
    }
  }
  return sha256.convert(utf8.encode(records.join('\n'))).toString();
}

final class GroupReactionIosBundleValidation {
  GroupReactionIosBundleValidation({
    required List<String> failures,
    this.application,
    this.xctestrun,
    this.testProducts,
    this.manifest,
  }) : failures = List<String>.unmodifiable(failures);

  final List<String> failures;
  final Directory? application;
  final File? xctestrun;
  final Directory? testProducts;
  final File? manifest;

  bool get ok => failures.isEmpty;
  String get detail => ok ? 'accepted' : failures.join('; ');
}

GroupReactionCentralBuildValidation
validateGroupReactionAttemptTwoIosBuildFreshness({
  required String attemptOneInputDigest,
  required String attemptOneArtifactDigest,
  required GroupReactionCentralBuildValidation attemptTwo,
}) {
  final failures = <String>[...attemptTwo.failures];
  if (!_isSha256(attemptOneInputDigest) ||
      !_isSha256(attemptOneArtifactDigest)) {
    failures.add('attempt-one iOS digests are invalid');
  }
  if (attemptTwo.inputDigest == attemptOneInputDigest) {
    failures.add('attempt two reused attempt-one iOS input digest');
  }
  if (attemptTwo.artifactDigest == attemptOneArtifactDigest) {
    failures.add('attempt two reused attempt-one iOS artifact digest');
  }
  return GroupReactionCentralBuildValidation(
    failures: failures,
    profileId: attemptTwo.profileId,
    inputDigest: attemptTwo.inputDigest,
    artifactDigest: attemptTwo.artifactDigest,
    attestation: attemptTwo.attestation,
  );
}

GroupReactionIosBundleValidation validateGroupReactionIosProductionBundle(
  Directory bundle,
) {
  final failures = <String>[];
  final manifest = File(
    '${bundle.absolute.path}${Platform.pathSeparator}bundle_manifest.json',
  );
  Directory? application;
  File? xctestrun;
  Directory? testProducts;
  if (FileSystemEntity.typeSync(manifest.path, followLinks: false) !=
      FileSystemEntityType.file) {
    failures.add('central iOS bundle manifest is missing');
  } else {
    try {
      final decoded = jsonDecode(manifest.readAsStringSync());
      if (decoded is! Map) {
        failures.add('central iOS bundle manifest root must be an object');
      } else {
        final value = decoded.map<String, Object?>(
          (key, item) => MapEntry('$key', item),
        );
        String? safeMember(String key) {
          final member = value[key];
          if (member is! String ||
              member.trim().isEmpty ||
              member.startsWith('/') ||
              member.split('/').contains('..')) {
            failures.add('central iOS bundle has unsafe $key member');
            return null;
          }
          return member;
        }

        if (value['schema'] != 'mknoon.sims.ios-device-production-bundle.v1' ||
            value['profileId'] != 'ios.device.production' ||
            value['centralCompileCommands'] != 1 ||
            value['logicalBuildCount'] != 1 ||
            value['childBuildCount'] != 0) {
          failures.add('central iOS bundle manifest contract is invalid');
        }
        final appMember = safeMember('applicationApp');
        final xctestrunMember = safeMember('xctestrun');
        final productsMember = safeMember('testProducts');
        if (appMember != null) {
          application = Directory('${bundle.absolute.path}/$appMember');
          if (!appMember.endsWith('.app') ||
              FileSystemEntity.typeSync(application.path, followLinks: false) !=
                  FileSystemEntityType.directory) {
            failures.add('central iOS application member is missing');
          }
        }
        if (xctestrunMember != null) {
          xctestrun = File('${bundle.absolute.path}/$xctestrunMember');
          if (!xctestrunMember.endsWith('.xctestrun') ||
              FileSystemEntity.typeSync(xctestrun.path, followLinks: false) !=
                  FileSystemEntityType.file ||
              xctestrun.lengthSync() == 0) {
            failures.add('central iOS xctestrun member is missing');
          }
        }
        if (productsMember != null) {
          testProducts = Directory('${bundle.absolute.path}/$productsMember');
          if (FileSystemEntity.typeSync(
                testProducts.path,
                followLinks: false,
              ) !=
              FileSystemEntityType.directory) {
            failures.add('central iOS test-products member is missing');
          }
        }
      }
    } on Object {
      failures.add('central iOS bundle manifest is not valid JSON');
    }
  }
  return GroupReactionIosBundleValidation(
    failures: failures,
    application: application,
    xctestrun: xctestrun,
    testProducts: testProducts,
    manifest: manifest,
  );
}

bool groupReactionIosDeviceIsOnline(String xctraceOutput, String deviceId) {
  if (!RegExp(r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}$').hasMatch(deviceId)) {
    return false;
  }
  final online = <String>[];
  for (final line in const LineSplitter().convert(xctraceOutput)) {
    if (RegExp(
      r'^=*[ ]*Devices Offline\b',
      caseSensitive: false,
    ).hasMatch(line.trim())) {
      break;
    }
    online.add(line);
  }
  final boundary = RegExp(
    '(^|[^0-9A-Fa-f-])${RegExp.escape(deviceId)}([^0-9A-Fa-f-]|\$)',
    caseSensitive: false,
  );
  return online.any(boundary.hasMatch);
}

bool groupReactionIosUsbDeviceIsPresent(String ideviceOutput, String deviceId) {
  if (!RegExp(r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}$').hasMatch(deviceId)) {
    return false;
  }
  return const LineSplitter()
      .convert(ideviceOutput)
      .map((line) => line.trim())
      .any((line) => line.toLowerCase() == deviceId.toLowerCase());
}

bool groupReactionIosRelayRegistrationSucceeded(String recipientLog) =>
    const LineSplitter()
        .convert(recipientLog)
        .any(
          (line) =>
              line.contains('[PUSH_DIAG] relay_push_registration_success') &&
              RegExp(r'\bplatform=ios\b').hasMatch(line),
        );

class GroupReactionNotificationEvidenceRequirement {
  const GroupReactionNotificationEvidenceRequirement({
    required this.kind,
    required this.markers,
  });

  final String kind;
  final List<String> markers;
}

class GroupReactionNotificationScenario {
  const GroupReactionNotificationScenario({
    required this.id,
    required this.testCase,
    required this.summary,
    required this.groupType,
    required this.senderRole,
    required this.senderPlatform,
    required this.senderDeviceKind,
    required this.recipientRole,
    required this.recipientPlatform,
    required this.recipientDeviceKind,
    required this.evidenceRequirements,
  });

  final String id;
  final String testCase;
  final String summary;
  final String groupType;
  final String senderRole;
  final String senderPlatform;
  final String senderDeviceKind;
  final String recipientRole;
  final String recipientPlatform;
  final String recipientDeviceKind;
  final List<GroupReactionNotificationEvidenceRequirement> evidenceRequirements;
}

const List<GroupReactionNotificationScenario>
groupReactionNotificationScenarios = <GroupReactionNotificationScenario>[
  GroupReactionNotificationScenario(
    id: 'android_group_message_unread_lifecycle',
    testCase: 'TC-13',
    summary:
        'discussion message dismissal, replacement, notification route, and '
        'Orbit unread lifecycle',
    groupType: 'chat',
    senderRole: 'message_sender',
    senderPlatform: 'android',
    senderDeviceKind: 'emulator',
    recipientRole: 'message_recipient',
    recipientPlatform: 'android',
    recipientDeviceKind: 'physical',
    evidenceRequirements: <GroupReactionNotificationEvidenceRequirement>[
      GroupReactionNotificationEvidenceRequirement(
        kind: 'relay',
        markers: <String>[
          'remote_type=group_message',
          'group_type=chat',
          'relay_store_matched=true',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'provider_fcm',
        markers: <String>['event=group_message', 'delivery_matched=true'],
      ),
      // Plan 386 / TC-386-02. The relay's own counters, scraped raw before the
      // graded transitions and again after quiescence. This is the only
      // provider evidence relay v1.8.0 can still attribute to this lane.
      GroupReactionNotificationEvidenceRequirement(
        kind: 'relay_metrics',
        markers: <String>[
          'MKNOON_386_RELAY_METRICS_PHASE baseline',
          'MKNOON_386_RELAY_METRICS_PHASE final',
          'relay_group_reaction_wake_total',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'sender_app',
        markers: <String>['role=message_sender', 'two_messages_committed=true'],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'recipient_app',
        markers: <String>[
          'route_target_matched=true',
          'conversation_read_committed=true',
          'both_messages_visible=true',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'sqlcipher_state',
        markers: <String>['unread=0,1,1,2,0', 'read_commit_before_tap=false'],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'android_notification_records',
        markers: <String>[
          'dismissal_observed=true',
          'replacement_observed=true',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'ui_automation',
        markers: <String>[
          'orbit=0,1,1,2,0',
          'orbit_indicators_after_return=0',
          'manual_taps=0',
        ],
      ),
    ],
  ),
  GroupReactionNotificationScenario(
    id: 'android_announcement_message_unread_lifecycle',
    testCase: 'TC-14',
    summary:
        'announcement message dismissal, replacement, notification route, '
        'and Orbit unread lifecycle',
    groupType: 'announcement',
    senderRole: 'announcement_admin_sender',
    senderPlatform: 'android',
    senderDeviceKind: 'emulator',
    recipientRole: 'announcement_member_recipient',
    recipientPlatform: 'android',
    recipientDeviceKind: 'physical',
    evidenceRequirements: <GroupReactionNotificationEvidenceRequirement>[
      GroupReactionNotificationEvidenceRequirement(
        kind: 'relay',
        markers: <String>[
          'remote_type=group_message',
          'group_type=announcement',
          'relay_store_matched=true',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'provider_fcm',
        markers: <String>['event=group_message', 'delivery_matched=true'],
      ),
      // Plan 386 / TC-386-02. The relay's own counters, scraped raw before the
      // graded transitions and again after quiescence. This is the only
      // provider evidence relay v1.8.0 can still attribute to this lane.
      GroupReactionNotificationEvidenceRequirement(
        kind: 'relay_metrics',
        markers: <String>[
          'MKNOON_386_RELAY_METRICS_PHASE baseline',
          'MKNOON_386_RELAY_METRICS_PHASE final',
          'relay_group_reaction_wake_total',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'sender_app',
        markers: <String>[
          'role=announcement_admin_sender',
          'two_messages_committed=true',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'recipient_app',
        markers: <String>[
          'role=announcement_member_recipient',
          'route_target_matched=true',
          'conversation_read_committed=true',
          'both_messages_visible=true',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'sqlcipher_state',
        markers: <String>['unread=0,1,1,2,0', 'read_commit_before_tap=false'],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'android_notification_records',
        markers: <String>[
          'dismissal_observed=true',
          'replacement_observed=true',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'ui_automation',
        markers: <String>[
          'orbit=0,1,1,2,0',
          'orbit_indicators_after_return=0',
          'manual_taps=0',
        ],
      ),
    ],
  ),
  GroupReactionNotificationScenario(
    id: 'android_group_reaction_recipient',
    testCase: 'TC-15',
    summary:
        'killed Android target author receives trusted discussion reaction '
        'copy, replacement, target route, and no unread mutation',
    groupType: 'chat',
    senderRole: 'member_reactor',
    senderPlatform: 'android',
    senderDeviceKind: 'emulator',
    recipientRole: 'target_message_author',
    recipientPlatform: 'android',
    recipientDeviceKind: 'physical',
    evidenceRequirements: <GroupReactionNotificationEvidenceRequirement>[
      GroupReactionNotificationEvidenceRequirement(
        kind: 'relay',
        markers: <String>[
          'remote_type=group_reaction',
          'action=add',
          'remove_provider_send=false',
          'duplicate_provider_send=false',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'provider_fcm',
        markers: <String>['event=group_reaction', 'delivery_matched=true'],
      ),
      // Plan 386 / TC-386-02. The relay's own counters, scraped raw before the
      // graded transitions and again after quiescence. This is the only
      // provider evidence relay v1.8.0 can still attribute to this lane.
      GroupReactionNotificationEvidenceRequirement(
        kind: 'relay_metrics',
        markers: <String>[
          'MKNOON_386_RELAY_METRICS_PHASE baseline',
          'MKNOON_386_RELAY_METRICS_PHASE final',
          'relay_group_reaction_wake_total',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'sender_app',
        markers: <String>[
          'role=member_reactor',
          'group_type=chat',
          'reaction_send_committed=true',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'recipient_app',
        markers: <String>[
          'stored_reaction=true',
          'route_target_matched=true',
          'pid_absent_before_delivery=true',
          'unread_after_tap=0',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'sqlcipher_state',
        markers: <String>[
          'reaction_rows=1',
          'reaction_created_message_rows=0',
          'unread=0,0,0',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'android_logcat',
        markers: <String>[
          'PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK',
          'PUSH_ANDROID_DATA_DECRYPT_OK',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'android_notification_records',
        markers: <String>[
          'title_source=recipient_owned_group',
          'body=Alice reacted to your message',
          'stable_group_card=true',
          'contains_new_message_copy=false',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'ui_automation',
        markers: <String>[
          'target_message_visible=true',
          'orbit_indicators=0',
          'manual_taps=0',
        ],
      ),
    ],
  ),
  GroupReactionNotificationScenario(
    id: 'android_announcement_reaction_recipient',
    testCase: 'TC-15',
    summary:
        'killed Android announcement author receives trusted member reaction '
        'copy, replacement, target route, and no unread mutation',
    groupType: 'announcement',
    senderRole: 'announcement_member_reactor',
    senderPlatform: 'android',
    senderDeviceKind: 'emulator',
    recipientRole: 'announcement_admin_author',
    recipientPlatform: 'android',
    recipientDeviceKind: 'physical',
    evidenceRequirements: <GroupReactionNotificationEvidenceRequirement>[
      GroupReactionNotificationEvidenceRequirement(
        kind: 'relay',
        markers: <String>[
          'remote_type=group_reaction',
          'action=add',
          'remove_provider_send=false',
          'duplicate_provider_send=false',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'provider_fcm',
        markers: <String>['event=group_reaction', 'delivery_matched=true'],
      ),
      // Plan 386 / TC-386-02. The relay's own counters, scraped raw before the
      // graded transitions and again after quiescence. This is the only
      // provider evidence relay v1.8.0 can still attribute to this lane.
      GroupReactionNotificationEvidenceRequirement(
        kind: 'relay_metrics',
        markers: <String>[
          'MKNOON_386_RELAY_METRICS_PHASE baseline',
          'MKNOON_386_RELAY_METRICS_PHASE final',
          'relay_group_reaction_wake_total',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'sender_app',
        markers: <String>[
          'role=announcement_member_reactor',
          'group_type=announcement',
          'reaction_send_committed=true',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'recipient_app',
        markers: <String>[
          'role=announcement_admin_author',
          'stored_reaction=true',
          'route_target_matched=true',
          'pid_absent_before_delivery=true',
          'unread_after_tap=0',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'sqlcipher_state',
        markers: <String>[
          'reaction_rows=1',
          'reaction_created_message_rows=0',
          'unread=0,0,0',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'android_logcat',
        markers: <String>[
          'PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK',
          'PUSH_ANDROID_DATA_DECRYPT_OK',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'android_notification_records',
        markers: <String>[
          'title_source=recipient_owned_group',
          'body=Alice reacted to your message',
          'stable_group_card=true',
          'contains_new_message_copy=false',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'ui_automation',
        markers: <String>[
          'target_message_visible=true',
          'orbit_indicators=0',
          'manual_taps=0',
        ],
      ),
    ],
  ),
  GroupReactionNotificationScenario(
    id: groupReactionBackgroundConnectedScenarioId,
    testCase: 'TC-12',
    summary:
        'backgrounded connected Android target author receives a provably '
        'push-origin discussion reaction while its process stays alive',
    groupType: 'chat',
    senderRole: 'member_reactor',
    senderPlatform: 'android',
    senderDeviceKind: 'emulator',
    recipientRole: 'target_message_author',
    recipientPlatform: 'android',
    recipientDeviceKind: 'physical',
    evidenceRequirements: <GroupReactionNotificationEvidenceRequirement>[
      GroupReactionNotificationEvidenceRequirement(
        kind: 'relay',
        markers: <String>[
          'remote_type=group_reaction',
          'action=add',
          'remove_provider_send=false',
          'duplicate_provider_send=false',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'provider_fcm',
        markers: <String>['event=group_reaction', 'delivery_matched=true'],
      ),
      // Plan 386 / TC-386-02. The relay's own counters, scraped raw before the
      // graded transitions and again after quiescence. This is the only
      // provider evidence relay v1.8.0 can still attribute to this lane.
      GroupReactionNotificationEvidenceRequirement(
        kind: 'relay_metrics',
        markers: <String>[
          'MKNOON_386_RELAY_METRICS_PHASE baseline',
          'MKNOON_386_RELAY_METRICS_PHASE final',
          'relay_group_reaction_wake_total',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'sender_app',
        markers: <String>[
          'role=member_reactor',
          'group_type=chat',
          'reaction_send_committed=true',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'recipient_app',
        markers: <String>[
          'stored_reaction=true',
          'route_target_matched=true',
          'pid_present_before_delivery=true',
          'connectivity_event=P2P_RELAY_PRESENCE_SET_RESPONSE',
          'home_to_react_delay_ms=3000',
          'notification_observation_window_ms=60000',
          'unread_after_tap=0',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'sqlcipher_state',
        markers: <String>[
          'reaction_rows=1',
          'reaction_created_message_rows=0',
          'unread=0,0,0',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'android_logcat',
        markers: <String>[
          'PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK',
          'PUSH_ANDROID_DATA_DECRYPT_OK',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'android_notification_records',
        markers: <String>[
          'title_source=recipient_owned_group',
          'body=Alice reacted to your message',
          'stable_group_card=true',
          'contains_new_message_copy=false',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'ui_automation',
        markers: <String>[
          'target_message_visible=true',
          'orbit_indicators=0',
          'manual_taps=0',
        ],
      ),
    ],
  ),
  GroupReactionNotificationScenario(
    id: 'ios_announcement_reaction_recipient',
    testCase: 'TC-16',
    summary:
        'physical iOS announcement author receives NSE reaction copy, one '
        'audible alert, target route, and no unread mutation',
    groupType: 'announcement',
    senderRole: 'announcement_member_reactor',
    senderPlatform: 'android',
    senderDeviceKind: 'physical',
    recipientRole: 'announcement_admin_author',
    recipientPlatform: 'ios',
    recipientDeviceKind: 'physical',
    evidenceRequirements: <GroupReactionNotificationEvidenceRequirement>[
      GroupReactionNotificationEvidenceRequirement(
        kind: 'relay',
        markers: <String>[
          'remote_type=group_reaction',
          'action=add',
          'remove_provider_send=false',
          'duplicate_provider_send=false',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'provider_apns',
        markers: <String>[
          'event=group_reaction',
          'mutable-content=1',
          'fallback_title=New reaction',
          'fallback_silent=true',
          'provider_private_fields=false',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'sender_app',
        markers: <String>[
          'role=announcement_member_reactor',
          'group_type=announcement',
          'reaction_send_committed=true',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'recipient_app',
        markers: <String>[
          'role=announcement_admin_author',
          'stored_reaction=true',
          'route_target_matched=true',
          'unread_after_tap=0',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'sqlcipher_state',
        markers: <String>[
          'mknoon.plan257.sqlcipher-observation.v1',
          'reactionRows=1',
          'unreadCount=0',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'nse_log',
        markers: <String>['PUSH_NSE_DECRYPT_OK', 'kind=group_reaction'],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'xcuitest',
        markers: <String>[
          'testAnnouncementReactionNotificationTap',
          'target_message_visible=true',
          'manual_taps=0',
        ],
      ),
    ],
  ),
  GroupReactionNotificationScenario(
    id: iosChatGroupMessageAndReactionScenarioId,
    testCase: 'TC-397-07/08',
    summary:
        'physical iOS ordinary chat-group recipient receives one provider '
        'message card and one provider ADD-reaction card with exact cold taps',
    groupType: 'chat',
    senderRole: 'member_message_sender_and_reactor',
    senderPlatform: 'android',
    senderDeviceKind: 'physical',
    recipientRole: 'chat_member_target_author',
    recipientPlatform: 'ios',
    recipientDeviceKind: 'physical',
    evidenceRequirements: <GroupReactionNotificationEvidenceRequirement>[
      GroupReactionNotificationEvidenceRequirement(
        kind: 'relay',
        markers: <String>[
          'message_window=complete',
          'reaction_window=complete',
          'duplicate_provider_send=false',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'provider_apns',
        markers: <String>[
          'message_provider_result=true',
          'reaction_attempted_delta=1',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'sender_app',
        markers: <String>[
          'message_phase_observed=true',
          'reaction_phase_observed=true',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'recipient_app',
        markers: <String>[
          'message_route_matched=true',
          'reaction_route_matched=true',
          'unread_after_tap=0',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'nse_log',
        markers: <String>['kind=group_message', 'kind=group_reaction'],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'native_inventory',
        markers: <String>[
          'message_matchingUsefulProviderCount=1',
          'reaction_matchingUsefulProviderCount=1',
          'matchingFlutterLocalCount=0',
        ],
      ),
      GroupReactionNotificationEvidenceRequirement(
        kind: 'xcuitest',
        markers: <String>[
          'testChatGroupNotificationTap',
          'message_target_visible=true',
          'reaction_target_visible=true',
          'manual_taps=0',
        ],
      ),
    ],
  ),
];

/// Named source extension consumed only by the Plan-330 Android adapter.
///
/// It deliberately stays out of [groupReactionNotificationScenarios]: the
/// Plan-257 rollout runner and validator own their stable legacy matrix, while
/// Plan 330 has a stronger two-group/media evidence schema and its own Sims
/// capability.
const GroupReactionNotificationScenario
groupNotificationProjectionAndroidSourceScenario =
    GroupReactionNotificationScenario(
      id: 'android_group_notification_projection_durability',
      testCase: 'PLAN-330',
      summary:
          'two-group Android read-zero cancellation plus stable localized '
          'photo, video, and voice-message reaction projection',
      groupType: 'chat',
      senderRole: 'member_reactor',
      senderPlatform: 'android',
      senderDeviceKind: 'emulator',
      recipientRole: 'target_media_author',
      recipientPlatform: 'android',
      recipientDeviceKind: 'physical',
      evidenceRequirements: <GroupReactionNotificationEvidenceRequirement>[],
    );

/// Plan 393 strict-authority source extension.
///
/// The shared capture driver supplies device/UI/relay mechanics; this row has
/// a dedicated artifact grammar and never joins the legacy Plan-257 matrix.
const GroupReactionNotificationScenario groupStrictNotificationSourceScenario =
    GroupReactionNotificationScenario(
      id: groupStrictNotificationScenarioId,
      testCase: 'TC-393-08',
      summary:
          'strict group exact-chat suppression plus killed message and '
          'author-targeted ADD wake on the Android pair',
      groupType: 'chat',
      senderRole: 'strict_member_reactor',
      senderPlatform: 'android',
      senderDeviceKind: 'emulator',
      recipientRole: 'strict_target_author',
      recipientPlatform: 'android',
      recipientDeviceKind: 'physical',
      evidenceRequirements: <GroupReactionNotificationEvidenceRequirement>[],
    );

/// Plan 379 muted-group source extensions (G4 closure).
///
/// Like [groupNotificationProjectionAndroidSourceScenario] these deliberately
/// stay out of [groupReactionNotificationScenarios]. The Plan-257 catalog is a
/// *reaction* grammar: its validator hard-requires a non-zero unread count,
/// per-branch notification cards, and relay/provider `[PUSH] … sent to`
/// evidence. A muted group asserts the exact negation of all three, so an
/// in-catalog row could not be expressed without rewriting the six existing
/// scenarios' assertions. The muted lane therefore owns its own validator,
/// runner, and Sims capability and reuses only the shared capture driver.
const GroupReactionNotificationScenario
groupMutedMessageSuppressionSourceScenario = GroupReactionNotificationScenario(
  id: 'android_group_muted_message_suppression',
  testCase: 'PLAN-379',
  summary:
      'muted group suppresses the live-path message card, sound, and badge '
      'while preserving unread and delivery',
  groupType: 'chat',
  senderRole: 'message_sender',
  senderPlatform: 'android',
  senderDeviceKind: 'emulator',
  recipientRole: 'muted_group_member',
  recipientPlatform: 'android',
  recipientDeviceKind: 'physical',
  evidenceRequirements: <GroupReactionNotificationEvidenceRequirement>[],
);

const GroupReactionNotificationScenario
groupMutedReactionBackgroundSourceScenario = GroupReactionNotificationScenario(
  id: 'android_group_muted_reaction_background_suppression',
  testCase: 'PLAN-379',
  summary:
      'muted group suppresses the FCM/background-isolate reaction card '
      'while an unmuted control reaction still posts',
  groupType: 'chat',
  senderRole: 'member_reactor',
  senderPlatform: 'android',
  senderDeviceKind: 'emulator',
  recipientRole: 'muted_group_target_author',
  recipientPlatform: 'android',
  recipientDeviceKind: 'physical',
  evidenceRequirements: <GroupReactionNotificationEvidenceRequirement>[],
);

/// Plan 384 killed-app group-text source extension (G19 closure).
///
/// Rides the muted lane's runner, pinned pair, and prebuilt APK, but asserts
/// the opposite observable: a card that MUST be present. It therefore owns its
/// own validator kind rather than joining the muted grammar, and it uses the
/// shared capture driver's DEFAULT one-group fixture — no mute toggle, no
/// control group, no reaction.
const GroupReactionNotificationScenario groupTextKilledAppCardSourceScenario =
    GroupReactionNotificationScenario(
      id: 'android_group_text_killed_app_card',
      testCase: 'PLAN-384',
      summary:
          'a killed recipient posts an OS card for a default-lane group text '
          'after a warm-up wake absorbs the cold-start storage deferral',
      groupType: 'chat',
      senderRole: 'message_sender',
      senderPlatform: 'android',
      senderDeviceKind: 'emulator',
      recipientRole: 'killed_app_message_recipient',
      recipientPlatform: 'android',
      recipientDeviceKind: 'physical',
      evidenceRequirements: <GroupReactionNotificationEvidenceRequirement>[],
    );

const List<GroupReactionNotificationScenario>
groupMutedNotificationSourceScenarios = <GroupReactionNotificationScenario>[
  groupMutedMessageSuppressionSourceScenario,
  groupMutedReactionBackgroundSourceScenario,
  groupTextKilledAppCardSourceScenario,
];

GroupReactionNotificationScenario? groupReactionNotificationScenario(
  String id,
) {
  if (id == groupNotificationProjectionAndroidSourceScenario.id) {
    return groupNotificationProjectionAndroidSourceScenario;
  }
  if (id == groupStrictNotificationSourceScenario.id) {
    return groupStrictNotificationSourceScenario;
  }
  for (final scenario in groupMutedNotificationSourceScenarios) {
    if (scenario.id == id) return scenario;
  }
  for (final scenario in groupReactionNotificationScenarios) {
    if (scenario.id == id) return scenario;
  }
  return null;
}

/// Which capture lifecycle a scenario id drives.
enum GroupReactionCaptureLifecycleStage {
  messageUnreadLifecycle,
  reactionRecipient,
  notificationProjection,
  mutedMessageSuppression,
  mutedReactionBackgroundSuppression,
  groupTextKilledAppCard,
  strictNotificationClosure,
}

/// Which SQLCipher probe shape a scenario id asks the installed app for.
///
/// [messageMarkers] sends `firstMarker`/`secondMarker`; the other two send a
/// `targetMarker` only. The in-app probe enforces exactly this split
/// (`group_reaction_e2e_probe.dart` marker-shape gate), so this enum is the
/// harness-side mirror of a contract the runtime already fails closed on.
enum GroupReactionCaptureObservationKind {
  messageMarkers,
  reactionTarget,
  mutedTarget,
}

/// Which artifact validator accepts the capture output for a scenario id.
enum GroupReactionCaptureValidatorKind {
  reaction,
  notificationProjection,
  muted,
  killedTextCard,
  strictNotification,
}

final class GroupReactionCaptureDispatch {
  const GroupReactionCaptureDispatch({
    required this.lifecycleStage,
    required this.observationKind,
    required this.validatorKind,
  });

  final GroupReactionCaptureLifecycleStage lifecycleStage;
  final GroupReactionCaptureObservationKind observationKind;
  final GroupReactionCaptureValidatorKind validatorKind;
}

/// Resolves the capture driver's per-scenario behaviour from the scenario id.
///
/// The capture driver historically re-derived this at every branch by testing
/// `id.endsWith('_message_unread_lifecycle')`, which silently routes any new
/// id into the reaction branch. Centralizing the decision here makes the
/// routing a host-testable value instead of a string coincidence, and lets a
/// scenario that is neither "message" nor "reaction" exist at all.
///
/// Returns `null` for an unregistered id so callers fail closed.
GroupReactionCaptureDispatch? groupReactionCaptureDispatchFor(
  String scenarioId,
) {
  if (groupReactionNotificationScenario(scenarioId) == null) return null;
  if (scenarioId == groupMutedMessageSuppressionSourceScenario.id) {
    return const GroupReactionCaptureDispatch(
      lifecycleStage:
          GroupReactionCaptureLifecycleStage.mutedMessageSuppression,
      observationKind: GroupReactionCaptureObservationKind.mutedTarget,
      validatorKind: GroupReactionCaptureValidatorKind.muted,
    );
  }
  if (scenarioId == groupMutedReactionBackgroundSourceScenario.id) {
    return const GroupReactionCaptureDispatch(
      lifecycleStage:
          GroupReactionCaptureLifecycleStage.mutedReactionBackgroundSuppression,
      observationKind: GroupReactionCaptureObservationKind.mutedTarget,
      validatorKind: GroupReactionCaptureValidatorKind.muted,
    );
  }
  if (scenarioId == groupTextKilledAppCardSourceScenario.id) {
    // Reuses `mutedTarget`: the in-app probe's marker-shape gate only cares
    // that a single `targetMarker` is sent, which is exactly this lane's
    // shape. A dedicated enum case would have zero consumers.
    return const GroupReactionCaptureDispatch(
      lifecycleStage: GroupReactionCaptureLifecycleStage.groupTextKilledAppCard,
      observationKind: GroupReactionCaptureObservationKind.mutedTarget,
      validatorKind: GroupReactionCaptureValidatorKind.killedTextCard,
    );
  }
  if (scenarioId == groupNotificationProjectionAndroidSourceScenario.id) {
    return const GroupReactionCaptureDispatch(
      lifecycleStage: GroupReactionCaptureLifecycleStage.notificationProjection,
      observationKind: GroupReactionCaptureObservationKind.reactionTarget,
      validatorKind: GroupReactionCaptureValidatorKind.notificationProjection,
    );
  }
  if (scenarioId == groupStrictNotificationSourceScenario.id) {
    return const GroupReactionCaptureDispatch(
      lifecycleStage:
          GroupReactionCaptureLifecycleStage.strictNotificationClosure,
      observationKind: GroupReactionCaptureObservationKind.reactionTarget,
      validatorKind: GroupReactionCaptureValidatorKind.strictNotification,
    );
  }
  if (scenarioId.endsWith('_message_unread_lifecycle')) {
    return const GroupReactionCaptureDispatch(
      lifecycleStage: GroupReactionCaptureLifecycleStage.messageUnreadLifecycle,
      observationKind: GroupReactionCaptureObservationKind.messageMarkers,
      validatorKind: GroupReactionCaptureValidatorKind.reaction,
    );
  }
  return const GroupReactionCaptureDispatch(
    lifecycleStage: GroupReactionCaptureLifecycleStage.reactionRecipient,
    observationKind: GroupReactionCaptureObservationKind.reactionTarget,
    validatorKind: GroupReactionCaptureValidatorKind.reaction,
  );
}

class GroupReactionNotificationArtifactValidation {
  GroupReactionNotificationArtifactValidation(List<String> failures)
    : failures = List<String>.unmodifiable(failures);

  final List<String> failures;

  bool get ok => failures.isEmpty;

  String get detail => ok ? 'accepted' : failures.join('; ');
}

Future<GroupReactionNotificationArtifactValidation>
validatePlan398ExistingStateTraceArtifact({
  required File artifactFile,
  required File traceAttemptMarker,
  required String expectedSenderDeviceId,
  required String expectedRecipientDeviceId,
}) async {
  final failures = <String>[];
  if (artifactFile.path.split(Platform.pathSeparator).last !=
      plan398ExistingStateTraceArtifactFileName) {
    failures.add(
      r'$ artifact filename must be plan398_existing_state_trace.json',
    );
  }
  if (!await artifactFile.exists()) {
    failures.add('missing artifact file ${artifactFile.path}');
    return GroupReactionNotificationArtifactValidation(failures);
  }

  late final String raw;
  try {
    raw = await artifactFile.readAsString();
  } on Object {
    failures.add(r'$ artifact could not be read');
    return GroupReactionNotificationArtifactValidation(failures);
  }
  _scanForbidden(raw, r'$', failures);
  _scanPlan398ExistingStateTraceForbidden(raw, failures);

  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on Object {
    failures.add(r'$ is not valid JSON');
    return GroupReactionNotificationArtifactValidation(failures);
  }
  final root = _asStringMap(decoded, r'$', failures);
  if (root != null) {
    await _validatePlan398ExistingStateTraceRoot(
      root: root,
      traceAttemptMarker: traceAttemptMarker,
      expectedSenderDeviceId: expectedSenderDeviceId,
      expectedRecipientDeviceId: expectedRecipientDeviceId,
      failures: failures,
    );
  }
  return GroupReactionNotificationArtifactValidation(failures);
}

Future<void> _validatePlan398ExistingStateTraceRoot({
  required Map<String, Object?> root,
  required File traceAttemptMarker,
  required String expectedSenderDeviceId,
  required String expectedRecipientDeviceId,
  required List<String> failures,
}) async {
  final liveDiagnostic =
      root['schema'] == plan398ExistingStateLiveDiagnosticArtifactSchema;
  _expectExactKeys(
    root,
    <String>{
      'schema',
      'version',
      if (liveDiagnostic) 'authorityMode',
      'status',
      'closurePassed',
      'disposition',
      'traceAttemptClaimed',
      'traceAttemptClaimSha256',
      'topology',
      'installedState',
      'window',
      'execution',
      'redaction',
    },
    r'$',
    failures,
  );
  for (final entry in const <String, Object?>{
    'version': plan398ExistingStateTraceArtifactVersion,
    'status': 'trace_complete',
    'closurePassed': false,
    'traceAttemptClaimed': true,
  }.entries) {
    _expectValue(root, entry.key, entry.value, r'$', failures);
  }
  _expectValue(
    root,
    'schema',
    liveDiagnostic
        ? plan398ExistingStateLiveDiagnosticArtifactSchema
        : plan398ExistingStateTraceArtifactSchema,
    r'$',
    failures,
  );
  if (liveDiagnostic) {
    _expectValue(
      root,
      'authorityMode',
      plan398LiveDiagnosticAuthorityMode,
      r'$',
      failures,
    );
  }
  if (root['version'] is! int) {
    failures.add(r'$.version must be an integer');
  }
  if (root['disposition'] is! String) {
    failures.add(r'$.disposition must be a closed diagnostic outcome');
  }
  if (!_isSha256(root['traceAttemptClaimSha256'])) {
    failures.add(r'$.traceAttemptClaimSha256 must be SHA-256');
  }
  await _validatePlan398ExistingStateTraceClaim(
    traceAttemptMarker: traceAttemptMarker,
    expectedSha256: root['traceAttemptClaimSha256'],
    failures: failures,
  );

  final senderDeviceHash = _plan398ExpectedDeviceHash(
    expectedSenderDeviceId,
    r'$.topology.sender',
    failures,
  );
  final recipientDeviceHash = _plan398ExpectedDeviceHash(
    expectedRecipientDeviceId,
    r'$.topology.recipient',
    failures,
  );
  final topology = _mapField(root, 'topology', r'$', failures);
  if (topology != null) {
    _expectExactKeys(
      topology,
      const <String>{'groupType', 'sender', 'recipient'},
      r'$.topology',
      failures,
    );
    _expectValue(topology, 'groupType', 'chat', r'$.topology', failures);
    for (final entry in <(String, String, String)>[
      ('sender', 'android', senderDeviceHash),
      ('recipient', 'ios', recipientDeviceHash),
    ]) {
      final party = _mapField(topology, entry.$1, r'$.topology', failures);
      if (party == null) continue;
      final path = '\$.topology.${entry.$1}';
      _expectExactKeys(
        party,
        const <String>{
          'platform',
          'deviceKind',
          'deviceIdSha256',
          'liveDiscovered',
        },
        path,
        failures,
      );
      _expectValue(party, 'platform', entry.$2, path, failures);
      _expectValue(party, 'deviceKind', 'physical', path, failures);
      _expectValue(party, 'liveDiscovered', true, path, failures);
      if (!_isSha256(party['deviceIdSha256']) ||
          party['deviceIdSha256'] != entry.$3) {
        failures.add('$path.deviceIdSha256 is not live-target bound');
      }
    }
  }

  final installedState = _mapField(root, 'installedState', r'$', failures);
  if (installedState != null) {
    _expectExactKeys(
      installedState,
      const <String>{
        'schema',
        'groupType',
        'matchingChatGroupCount',
        'groupIdSha256',
        'groupKeySha256',
        'targetMessageIdSha256',
        'senderIdentityReceiptSha256',
        'recipientIdentityReceiptSha256',
        'notificationAuthorizationReady',
        'relayPushTokenReady',
        'rawIdentifiersPersisted',
        'rawKeyMaterialPersisted',
        'rawIdentityReceiptsPersisted',
        'rawPushTokensPersisted',
      },
      r'$.installedState',
      failures,
    );
    for (final entry in const <String, Object?>{
      'schema': 'mknoon.plan398.existing-state-installed-state.v1',
      'groupType': 'chat',
      'matchingChatGroupCount': 1,
      'notificationAuthorizationReady': true,
      'relayPushTokenReady': true,
      'rawIdentifiersPersisted': false,
      'rawKeyMaterialPersisted': false,
      'rawIdentityReceiptsPersisted': false,
      'rawPushTokensPersisted': false,
    }.entries) {
      _expectValue(
        installedState,
        entry.key,
        entry.value,
        r'$.installedState',
        failures,
      );
    }
    if (installedState['matchingChatGroupCount'] is! int) {
      failures.add(
        r'$.installedState.matchingChatGroupCount must be an integer',
      );
    }
    for (final key in const <String>[
      'groupIdSha256',
      'groupKeySha256',
      'targetMessageIdSha256',
      'senderIdentityReceiptSha256',
      'recipientIdentityReceiptSha256',
    ]) {
      if (!_isSha256(installedState[key])) {
        failures.add('\$.installedState.$key must be SHA-256');
      }
    }
  }

  final window = _mapField(root, 'window', r'$', failures);
  if (window != null) {
    _validatePlan398DiagnosticWindow(
      window: window,
      recipientDeviceId: expectedRecipientDeviceId,
      expectedDisposition: root['disposition'],
      failures: failures,
    );
    final android = _mapField(
      window,
      'androidObservation',
      r'$.window',
      failures,
    );
    if (installedState != null && android != null) {
      if (installedState['groupIdSha256'] != android['groupIdSha256']) {
        failures.add(
          r'$.installedState.groupIdSha256 is not message-window bound',
        );
      }
      if (installedState['targetMessageIdSha256'] !=
          android['targetMessageIdSha256']) {
        failures.add(
          r'$.installedState.targetMessageIdSha256 is not message-window bound',
        );
      }
    }
  }

  final execution = _mapField(root, 'execution', r'$', failures);
  if (execution != null) {
    final manualMessageSend = execution['automation'] == 'manual_message_send';
    if (liveDiagnostic && !manualMessageSend) {
      failures.add(
        r'$.execution.automation must equal manual_message_send for a live diagnostic',
      );
    }
    final countKeys = <String>[
      'messageSendTapCount',
      if (manualMessageSend) 'manualMessageSendCount',
      'reactionTapCount',
      'notificationTapCount',
      'buildCount',
      'installCount',
      'uninstallCount',
      'appDataClearCount',
      'groupCreateCount',
    ];
    _expectExactKeys(
      execution,
      <String>{'automation', ...countKeys},
      r'$.execution',
      failures,
    );
    for (final key in countKeys) {
      if (execution[key] is! int) {
        failures.add('\$.execution.$key must be an integer');
      }
    }
    final expected = <String, Object?>{
      'automation': manualMessageSend
          ? 'manual_message_send'
          : 'fully_automated',
      'messageSendTapCount': manualMessageSend ? 0 : 1,
      if (manualMessageSend) 'manualMessageSendCount': 1,
      'reactionTapCount': 0,
      'notificationTapCount': 0,
      'buildCount': 0,
      'installCount': 0,
      'uninstallCount': 0,
      'appDataClearCount': 0,
      'groupCreateCount': 0,
    };
    for (final entry in expected.entries) {
      _expectValue(execution, entry.key, entry.value, r'$.execution', failures);
    }
  }

  final redaction = _mapField(root, 'redaction', r'$', failures);
  if (redaction != null) {
    _expectExactKeys(
      redaction,
      const <String>{
        'rawGroupOrTargetIdsPersisted',
        'rawGroupKeysPersisted',
        'rawIdentityReceiptsPersisted',
        'rawPushTokensPersisted',
        'rawPayloadPersisted',
      },
      r'$.redaction',
      failures,
    );
    for (final key in redaction.keys) {
      _expectValue(redaction, key, false, r'$.redaction', failures);
    }
  }
}

Future<void> _validatePlan398ExistingStateTraceClaim({
  required File traceAttemptMarker,
  required Object? expectedSha256,
  required List<String> failures,
}) async {
  const path = r'$.traceAttemptClaimSha256';
  if (traceAttemptMarker.path.split(Platform.pathSeparator).last !=
      plan398ExistingStateTraceClaimFileName) {
    failures.add(
      '$path evidence filename must be '
      'plan398_existing_state_trace_claim.json',
    );
  }
  try {
    final entityType = await FileSystemEntity.type(
      traceAttemptMarker.path,
      followLinks: false,
    );
    if (entityType != FileSystemEntityType.file) {
      failures.add('$path requires a regular durable trace-claim file');
      return;
    }
    final stat = await traceAttemptMarker.stat();
    if ((stat.mode & 0x1ff) != 0x180) {
      failures.add('$path evidence must have private mode 0600');
      return;
    }
    final bytes = await traceAttemptMarker.readAsBytes();
    if (bytes.isEmpty || bytes.length > 4096) {
      failures.add('$path evidence must be a bounded non-empty claim');
      return;
    }
    final encoded = utf8.decode(bytes);
    final decoded = jsonDecode(encoded);
    final claim = _asStringMap(decoded, '$path.authority', failures);
    if (claim == null) return;
    _expectExactKeys(
      claim,
      const <String>{
        'schema',
        'ownerRunId',
        'singleOwnerDeclared',
        'claimValue',
      },
      '$path.authority',
      failures,
    );
    for (final key in claim.keys) {
      final encodedKey = RegExp.escape(jsonEncode(key));
      if (RegExp('$encodedKey\\s*:').allMatches(encoded).length != 1) {
        failures.add('$path.authority contains an ambiguous $key member');
      }
    }
    _expectValue(
      claim,
      'schema',
      'mknoon.plan398.existing-state-trace-claim.v1',
      '$path.authority',
      failures,
    );
    _expectValue(
      claim,
      'ownerRunId',
      'existing-state-trace',
      '$path.authority',
      failures,
    );
    _expectValue(
      claim,
      'singleOwnerDeclared',
      true,
      '$path.authority',
      failures,
    );
    final claimValue = claim['claimValue'];
    if (claimValue is! String ||
        !RegExp(r'^[A-Za-z0-9._:-]{16,160}$').hasMatch(claimValue)) {
      failures.add('$path.authority.claimValue is not canonical');
    }
    if (sha256.convert(bytes).toString() != expectedSha256) {
      failures.add('$path is not bound to the durable trace claim');
    }
  } on Object {
    failures.add('$path evidence is unreadable or invalid JSON');
  }
}

String _plan398ExpectedDeviceHash(
  String value,
  String path,
  List<String> failures,
) {
  if (value.trim().isEmpty || value != value.trim()) {
    failures.add('$path expected device id is invalid');
  }
  return sha256.convert(utf8.encode(value)).toString();
}

void _scanPlan398ExistingStateTraceForbidden(
  String raw,
  List<String> failures,
) {
  for (final field in const <String>[
    '"groupId":',
    '"groupKey":',
    '"targetMessageId":',
    '"senderIdentityReceipt":',
    '"recipientIdentityReceipt":',
    '"pushToken":',
    '"deviceId":',
  ]) {
    if (raw.contains(field)) {
      failures.add(r'$ contains forbidden raw existing-state field ' + field);
    }
  }
}

Future<GroupReactionNotificationArtifactValidation>
validateGroupReactionNotificationArtifact({
  required String scenario,
  required File artifactFile,
  String? expectedSenderDeviceId,
  String? expectedRecipientDeviceId,
  File? plan398DeploymentReceipt,
  File? plan398DiagnosticAttemptMarker,
}) async {
  final failures = <String>[];
  final requirement = groupReactionNotificationScenario(scenario);
  if (requirement == null) {
    failures.add(r'$.scenario is not a registered Plan 257 scenario');
    return GroupReactionNotificationArtifactValidation(failures);
  }
  if (!await artifactFile.exists()) {
    failures.add('missing artifact file ${artifactFile.path}');
    return GroupReactionNotificationArtifactValidation(failures);
  }

  late final String raw;
  try {
    raw = await artifactFile.readAsString();
  } on Object {
    failures.add(r'$ artifact could not be read');
    return GroupReactionNotificationArtifactValidation(failures);
  }
  _scanForbidden(raw, r'$', failures);

  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on Object {
    failures.add(r'$ is not valid JSON');
    return GroupReactionNotificationArtifactValidation(failures);
  }
  final root = _asStringMap(decoded, r'$', failures);
  if (root == null) {
    return GroupReactionNotificationArtifactValidation(failures);
  }

  if (scenario == iosChatGroupMessageAndReactionScenarioId) {
    if (root['schema'] == plan398IosGroupMessageDiagnosticArtifactSchema) {
      await _validatePlan398IosGroupMessageDiagnosticArtifact(
        root: root,
        requirement: requirement,
        expectedSenderDeviceId: expectedSenderDeviceId,
        expectedRecipientDeviceId: expectedRecipientDeviceId,
        deploymentReceipt: plan398DeploymentReceipt,
        diagnosticAttemptMarker: plan398DiagnosticAttemptMarker,
        failures: failures,
      );
    } else if ('${root['schema']}'.startsWith(
      'mknoon.plan398.ios-group-message-diagnostic.',
    )) {
      failures.add(
        r'$.schema is not the current Plan 398 diagnostic artifact schema',
      );
    } else {
      await _validateIosChatGroupMessageAndReactionArtifact(
        root: root,
        artifactFile: artifactFile,
        requirement: requirement,
        expectedSenderDeviceId: expectedSenderDeviceId,
        expectedRecipientDeviceId: expectedRecipientDeviceId,
        failures: failures,
      );
    }
    return GroupReactionNotificationArtifactValidation(failures);
  }

  _expectExactKeys(
    root,
    const <String>{
      'schema',
      'version',
      'scenario',
      'testCase',
      'status',
      'generatedBy',
      'capture',
      'measurements',
      'topology',
      'execution',
      'evidence',
      'redaction',
    },
    r'$',
    failures,
  );
  _expectValue(
    root,
    'schema',
    groupReactionNotificationArtifactSchema,
    r'$',
    failures,
  );
  _expectValue(
    root,
    'version',
    groupReactionNotificationArtifactVersion,
    r'$',
    failures,
  );
  _expectValue(root, 'scenario', scenario, r'$', failures);
  _expectValue(root, 'testCase', requirement.testCase, r'$', failures);
  _expectValue(root, 'status', 'passed', r'$', failures);
  _expectValue(
    root,
    'generatedBy',
    'automated_capture_pipeline',
    r'$',
    failures,
  );

  String? validatedSenderDeviceId;
  String? validatedRecipientDeviceId;
  final topology = _mapField(root, 'topology', r'$', failures);
  if (topology != null) {
    _expectExactKeys(
      topology,
      const <String>{'groupType', 'sender', 'recipient'},
      r'$.topology',
      failures,
    );
    _expectValue(
      topology,
      'groupType',
      requirement.groupType,
      r'$.topology',
      failures,
    );
    final sender = _mapField(topology, 'sender', r'$.topology', failures);
    final recipient = _mapField(topology, 'recipient', r'$.topology', failures);
    final senderId = _validateParty(
      sender,
      path: r'$.topology.sender',
      role: requirement.senderRole,
      platform: requirement.senderPlatform,
      deviceKind: requirement.senderDeviceKind,
      expectedDeviceId: expectedSenderDeviceId,
      failures: failures,
    );
    final recipientId = _validateParty(
      recipient,
      path: r'$.topology.recipient',
      role: requirement.recipientRole,
      platform: requirement.recipientPlatform,
      deviceKind: requirement.recipientDeviceKind,
      expectedDeviceId: expectedRecipientDeviceId,
      failures: failures,
    );
    if (senderId != null && senderId == recipientId) {
      failures.add(r'$.topology sender and recipient device IDs must differ');
    }
    validatedSenderDeviceId = senderId;
    validatedRecipientDeviceId = recipientId;
  }

  final measurements = _mapField(root, 'measurements', r'$', failures);
  _validateMeasurements(
    measurements,
    requirement: requirement,
    failures: failures,
  );

  final capture = _mapField(root, 'capture', r'$', failures);
  await _validateCaptureBundle(
    capture,
    requirement: requirement,
    artifactFile: artifactFile,
    senderDeviceId: validatedSenderDeviceId,
    recipientDeviceId: validatedRecipientDeviceId,
    failures: failures,
  );

  final execution = _mapField(root, 'execution', r'$', failures);
  if (execution != null) {
    _expectExactKeys(
      execution,
      const <String>{
        'automation',
        'manualTaps',
        'forceStopUsed',
        'candidateBuildInstalled',
        'stagingRelay',
        'realProvider',
      },
      r'$.execution',
      failures,
    );
    _expectValue(
      execution,
      'automation',
      'fully_automated',
      r'$.execution',
      failures,
    );
    _expectValue(execution, 'manualTaps', 0, r'$.execution', failures);
    _expectValue(execution, 'forceStopUsed', false, r'$.execution', failures);
    _expectValue(
      execution,
      'candidateBuildInstalled',
      true,
      r'$.execution',
      failures,
    );
    _expectValue(execution, 'stagingRelay', true, r'$.execution', failures);
    _expectValue(execution, 'realProvider', true, r'$.execution', failures);
  }

  final redaction = _mapField(root, 'redaction', r'$', failures);
  if (redaction != null) {
    _expectExactKeys(
      redaction,
      const <String>{
        'pushTokensPersisted',
        'secretKeysPersisted',
        'ciphertextPersisted',
        'plaintextPayloadPersisted',
        'rawPeerIdsPersisted',
      },
      r'$.redaction',
      failures,
    );
    for (final key in const <String>[
      'pushTokensPersisted',
      'secretKeysPersisted',
      'ciphertextPersisted',
      'plaintextPayloadPersisted',
      'rawPeerIdsPersisted',
    ]) {
      _expectValue(redaction, key, false, r'$.redaction', failures);
    }
  }

  await _validateEvidence(
    root['evidence'],
    requirement: requirement,
    artifactFile: artifactFile,
    measurements: measurements,
    failures: failures,
  );
  return GroupReactionNotificationArtifactValidation(failures);
}

Future<File> writeGroupReactionNotificationVerdict({
  required Directory outputDirectory,
  required String scenario,
  required bool ok,
  required String stage,
  required String status,
  required String detail,
}) async {
  await outputDirectory.create(recursive: true);
  final file = File(
    '${outputDirectory.path}${Platform.pathSeparator}'
    '${scenario}_orchestrator_verdict.json',
  );
  await file.writeAsString(
    jsonEncode(<String, Object?>{
      'schema': groupReactionNotificationVerdictSchema,
      'version': 1,
      'scenario': scenario,
      'ok': ok,
      'stage': stage,
      'status': status,
      'detail': detail,
      'recordedAt': DateTime.now().toUtc().toIso8601String(),
    }),
    flush: true,
  );
  return file;
}

Future<File> writePlan398ExistingStateTraceFailure({
  required Directory outputDirectory,
  required String scenario,
  required String status,
  required String stage,
  required String detail,
  required bool traceAttemptClaimed,
  String stackType = 'not_started',
  Iterable<String> completedStages = const <String>[],
}) async {
  await outputDirectory.create(recursive: true);
  final file = File(
    '${outputDirectory.path}${Platform.pathSeparator}'
    '$plan398ExistingStateTraceFailureFileName',
  );
  if (await file.exists()) return file;
  final temporary = File(
    '${file.path}.$pid.'
    '${DateTime.now().toUtc().microsecondsSinceEpoch}.private-temp',
  );
  final encoded = jsonEncode(<String, Object?>{
    'schema': 'mknoon.plan257.capture-failure.v1',
    'scenario': scenario,
    'status': status,
    'stage': stage,
    'detail': detail,
    'traceAttemptClaimed': traceAttemptClaimed,
    'recordedAt': DateTime.now().toUtc().toIso8601String(),
    'stackType': stackType,
    'completedStages': <String>{...completedStages}.toList(growable: false),
  });
  try {
    await temporary.writeAsString(encoded, flush: true);
    final chmod = await Process.run('chmod', <String>['600', temporary.path]);
    if (chmod.exitCode != 0) {
      throw const FileSystemException('private trace failure mode rejected');
    }
    final publish = await Process.run('ln', <String>[
      temporary.path,
      file.path,
    ]);
    if (publish.exitCode != 0 && !await file.exists()) {
      throw const FileSystemException('trace failure publication rejected');
    }
    return file;
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}

String? _validateParty(
  Map<String, Object?>? party, {
  required String path,
  required String role,
  required String platform,
  required String deviceKind,
  required String? expectedDeviceId,
  required List<String> failures,
}) {
  if (party == null) return null;
  _expectExactKeys(
    party,
    const <String>{
      'role',
      'platform',
      'deviceKind',
      'deviceId',
      'liveDiscovered',
      'explicitId',
    },
    path,
    failures,
  );
  _expectValue(party, 'role', role, path, failures);
  _expectValue(party, 'platform', platform, path, failures);
  _expectValue(party, 'deviceKind', deviceKind, path, failures);
  _expectValue(party, 'liveDiscovered', true, path, failures);
  _expectValue(party, 'explicitId', true, path, failures);
  final deviceId = _requiredString(party, 'deviceId', path, failures);
  if (deviceId == null) return null;
  if (!RegExp(r'^[A-Za-z0-9._:-]{4,128}$').hasMatch(deviceId)) {
    failures.add('$path.deviceId is not a safe explicit device ID');
  }
  final looksLikeEmulator = RegExp(r'^emulator-[0-9]+$').hasMatch(deviceId);
  final looksLikePhysicalIos = RegExp(
    r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}$',
  ).hasMatch(deviceId);
  if (deviceKind == 'emulator' && !looksLikeEmulator) {
    failures.add('$path.deviceId must identify an Android emulator');
  }
  if (deviceKind == 'physical' && looksLikeEmulator) {
    failures.add('$path.deviceId must identify a physical device');
  }
  if (platform == 'ios' && !looksLikePhysicalIos) {
    failures.add('$path.deviceId must identify a physical iOS device');
  }
  if (platform == 'android' && looksLikePhysicalIos) {
    failures.add('$path.deviceId must identify an Android device');
  }
  if (expectedDeviceId != null && deviceId != expectedDeviceId) {
    failures.add('$path.deviceId does not match the explicit runner device');
  }
  return deviceId;
}

Future<void> _validateEvidence(
  Object? value, {
  required GroupReactionNotificationScenario requirement,
  required File artifactFile,
  required Map<String, Object?>? measurements,
  required List<String> failures,
}) async {
  if (value is! List) {
    failures.add(r'$.evidence must be a list');
    return;
  }
  final requiredByKind = <String, GroupReactionNotificationEvidenceRequirement>{
    for (final evidence in requirement.evidenceRequirements)
      evidence.kind: evidence,
  };
  final recordsByKind = <String, Map<String, Object?>>{};
  for (var index = 0; index < value.length; index++) {
    final path = '\$.evidence[$index]';
    final record = _asStringMap(value[index], path, failures);
    if (record == null) continue;
    _expectExactKeys(
      record,
      const <String>{'kind', 'path', 'sha256', 'bytes'},
      path,
      failures,
    );
    final kind = _requiredString(record, 'kind', path, failures);
    if (kind == null) continue;
    if (!requiredByKind.containsKey(kind)) {
      failures.add('$path.kind is not required for ${requirement.id}');
      continue;
    }
    if (recordsByKind.containsKey(kind)) {
      failures.add('$path.kind duplicates evidence kind $kind');
      continue;
    }
    recordsByKind[kind] = record;
  }

  for (final kind in requiredByKind.keys) {
    if (!recordsByKind.containsKey(kind)) {
      failures.add('\$.evidence is missing required kind $kind');
    }
  }

  final artifactDirectory = await artifactFile.parent.resolveSymbolicLinks();
  final evidenceTexts = <String, String>{};
  for (final entry in recordsByKind.entries) {
    final record = entry.value;
    final path = '\$.evidence[${entry.key}]';
    final rawPath = _requiredString(record, 'path', path, failures);
    final expectedSha = _requiredString(record, 'sha256', path, failures);
    final expectedBytes = record['bytes'];
    if (expectedBytes is! int || expectedBytes <= 0) {
      failures.add('$path.bytes must be a positive integer');
    }
    if (expectedSha == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedSha)) {
      failures.add('$path.sha256 must be a lowercase SHA-256 digest');
    }
    if (rawPath == null) continue;
    final segments = rawPath.split(RegExp(r'[/\\]'));
    if (File(rawPath).isAbsolute || segments.contains('..')) {
      failures.add('$path.path must stay inside the artifact directory');
      continue;
    }
    final evidenceFile = File(
      '${artifactFile.parent.path}${Platform.pathSeparator}$rawPath',
    );
    if (!await evidenceFile.exists()) {
      failures.add('$path.path is missing');
      continue;
    }
    final resolved = await evidenceFile.resolveSymbolicLinks();
    if (!resolved.startsWith('$artifactDirectory${Platform.pathSeparator}')) {
      failures.add('$path.path must stay inside the artifact directory');
      continue;
    }
    final bytes = await evidenceFile.readAsBytes();
    if (expectedBytes is int && bytes.length != expectedBytes) {
      failures.add('$path.bytes does not match the evidence file');
    }
    if (expectedSha != null &&
        sha256.convert(bytes).toString() != expectedSha) {
      failures.add('$path SHA-256 mismatch');
    }
    late final String text;
    try {
      text = utf8.decode(bytes);
    } on Object {
      failures.add('$path is not UTF-8 evidence');
      continue;
    }
    _scanForbidden(text, path, failures);
    evidenceTexts[entry.key] = text;
  }

  _validateAuthoritativeEvidence(
    requirement: requirement,
    measurements: measurements,
    evidenceTexts: evidenceTexts,
    failures: failures,
  );
}

void _validateMeasurements(
  Map<String, Object?>? measurements, {
  required GroupReactionNotificationScenario requirement,
  required List<String> failures,
}) {
  if (measurements == null) return;
  _expectExactKeys(
    measurements,
    const <String>{
      'appPackage',
      'groupName',
      'actorName',
      'firstMarker',
      'secondMarker',
      'targetMarker',
      'expectedRelayWakeAttempts',
    },
    r'$.measurements',
    failures,
  );
  _requiredString(measurements, 'appPackage', r'$.measurements', failures);
  _requiredString(measurements, 'groupName', r'$.measurements', failures);
  _requiredString(measurements, 'actorName', r'$.measurements', failures);
  for (final key in const <String>[
    'firstMarker',
    'secondMarker',
    'targetMarker',
  ]) {
    if (measurements[key] is! String) {
      failures.add('\$.measurements.$key must be a string');
    }
  }
  _expectValue(
    measurements,
    'expectedRelayWakeAttempts',
    2,
    r'$.measurements',
    failures,
  );
  final messageScenario = requirement.id.endsWith('_message_unread_lifecycle');
  final first = measurements['firstMarker'];
  final second = measurements['secondMarker'];
  final target = measurements['targetMarker'];
  if (messageScenario) {
    if (first is! String ||
        first.isEmpty ||
        second is! String ||
        second.isEmpty) {
      failures.add(
        r'$.measurements message lifecycle requires first/second markers',
      );
    }
    if (target != '') {
      failures.add(r'$.measurements.targetMarker must be empty for messages');
    }
  } else {
    if (target is! String || target.isEmpty) {
      failures.add(r'$.measurements reaction lifecycle requires targetMarker');
    }
    if (first != '' || second != '') {
      failures.add(
        r'$.measurements first/second markers must be empty for reactions',
      );
    }
  }
}

Future<void> _validateCaptureBundle(
  Map<String, Object?>? capture, {
  required GroupReactionNotificationScenario requirement,
  required File artifactFile,
  required String? senderDeviceId,
  required String? recipientDeviceId,
  required List<String> failures,
}) async {
  if (capture == null) return;
  _expectExactKeys(
    capture,
    const <String>{'configuration', 'candidateBuild', 'commandJournal'},
    r'$.capture',
    failures,
  );
  final configuration = await _readReferencedText(
    capture['configuration'],
    artifactFile: artifactFile,
    path: r'$.capture.configuration',
    failures: failures,
  );
  final candidateBuild = await _readReferencedText(
    capture['candidateBuild'],
    artifactFile: artifactFile,
    path: r'$.capture.candidateBuild',
    failures: failures,
  );
  final commandJournal = await _readReferencedText(
    capture['commandJournal'],
    artifactFile: artifactFile,
    path: r'$.capture.commandJournal',
    failures: failures,
  );

  if (configuration != null) {
    final value = _decodeObject(
      configuration,
      r'$.capture.configuration',
      failures,
    );
    if (value != null) {
      if (value['schema'] != 'mknoon.plan257.configuration-verdict.v1' ||
          value['scenario'] != requirement.id ||
          value['ok'] != true ||
          value['environment'] != 'staging' ||
          value['productionDeploymentPerformed'] != false) {
        failures.add(
          r'$.capture.configuration is not an accepted staging verdict',
        );
      }
      final sender = value['sender'];
      final recipient = value['recipient'];
      if (sender is! Map || sender['deviceId'] != senderDeviceId) {
        failures.add(
          r'$.capture.configuration sender does not bind topology device',
        );
      }
      if (recipient is! Map || recipient['deviceId'] != recipientDeviceId) {
        failures.add(
          r'$.capture.configuration recipient does not bind topology device',
        );
      }
      final relay = value['relay'];
      final provider = value['provider'];
      if (relay is! Map ||
          relay['active'] != true ||
          relay['candidateRevisionMatched'] != true ||
          relay['groupReactionRolloutEnabled'] != true ||
          provider is! Map ||
          provider['configurationChecked'] != true) {
        failures.add(
          r'$.capture.configuration lacks live relay/provider qualification',
        );
      }
    }
  }

  var centralPrebuiltAndroid = false;
  var parentPreparedCentralPrebuiltAndroid = false;
  if (candidateBuild != null) {
    final value = _decodeObject(
      candidateBuild,
      r'$.capture.candidateBuild',
      failures,
    );
    if (value != null) {
      final e2eSha256 = value['e2eApkSha256'];
      final normalSha256 = value['normalApkSha256'];
      final sourceProvenance = value['sourceProvenance'];
      centralPrebuiltAndroid =
          requirement.recipientPlatform == 'android' &&
          value['buildMode'] == 'central_prebuilt' &&
          value['buildProfile'] == 'android.production_fcm' &&
          value['childBuildCount'] == 0 &&
          value['parentPreparedAndroidState'] is bool &&
          _isSha256(e2eSha256) &&
          e2eSha256 == normalSha256 &&
          sourceProvenance ==
              'central-prebuilt:android.production_fcm:$e2eSha256';
      parentPreparedCentralPrebuiltAndroid =
          centralPrebuiltAndroid && value['parentPreparedAndroidState'] == true;
      final legacyDistinctBuild =
          _isSha256(e2eSha256) &&
          _isSha256(normalSha256) &&
          e2eSha256 != normalSha256 &&
          sourceProvenance is String &&
          sourceProvenance.contains('+worktree:');
      if (value['schema'] != 'mknoon.plan257.candidate-build.v1' ||
          (!legacyDistinctBuild && !centralPrebuiltAndroid)) {
        failures.add(
          r'$.capture.candidateBuild lacks accepted legacy-distinct or '
          'central-prebuilt candidate provenance',
        );
      }
      if (requirement.recipientPlatform == 'ios') {
        final e2eAppSha = value['iosE2eAppSha256'];
        final normalAppSha = value['iosNormalAppSha256'];
        if (value['iosBundleId'] != 'com.mknoon.app' ||
            value['iosBuildTarget'] != 'build/ios/iphoneos/Runner.app' ||
            !_isSha256(e2eAppSha) ||
            !_isSha256(normalAppSha) ||
            e2eAppSha == normalAppSha ||
            value['iosInstallReceipts'] is! List) {
          failures.add(
            r'$.capture.candidateBuild lacks distinct signed physical-iOS '
            'bundle provenance',
          );
        } else {
          final receipts = value['iosInstallReceipts'] as List;
          final seenModes = <String>{};
          if (receipts.length != 2) {
            failures.add(
              r'$.capture.candidateBuild must bind two physical-iOS install '
              'receipts',
            );
          }
          for (var index = 0; index < receipts.length; index++) {
            final record = _asStringMap(
              receipts[index],
              '\$.capture.candidateBuild.iosInstallReceipts[$index]',
              failures,
            );
            if (record == null) continue;
            _expectExactKeys(
              record,
              const <String>{'mode', 'receipt'},
              '\$.capture.candidateBuild.iosInstallReceipts[$index]',
              failures,
            );
            final mode = _requiredString(
              record,
              'mode',
              '\$.capture.candidateBuild.iosInstallReceipts[$index]',
              failures,
            );
            if (mode == null ||
                !const <String>{'e2e', 'normal'}.contains(mode) ||
                !seenModes.add(mode)) {
              failures.add(
                r'$.capture.candidateBuild has invalid/duplicate iOS install '
                'receipt mode',
              );
            }
            final receipt = await _readReferencedText(
              record['receipt'],
              artifactFile: artifactFile,
              path:
                  '\$.capture.candidateBuild.iosInstallReceipts[$index].receipt',
              failures: failures,
            );
            if (receipt == null ||
                !receipt.contains('com.mknoon.app') ||
                (recipientDeviceId != null &&
                    !receipt.contains(recipientDeviceId))) {
              failures.add(
                r'$.capture.candidateBuild iOS install receipt does not bind '
                'the selected device and bundle',
              );
            }
          }
          if (!seenModes.containsAll(const <String>{'e2e', 'normal'})) {
            failures.add(
              r'$.capture.candidateBuild lacks e2e/normal iOS install receipts',
            );
          }
        }
      }
    }
  }

  if (commandJournal != null) {
    final value = _decodeObject(
      commandJournal,
      r'$.capture.commandJournal',
      failures,
    );
    if (value != null) {
      if (value['schema'] != 'mknoon.plan257.command-journal.v1' ||
          value['scenario'] != requirement.id ||
          value['commands'] is! List) {
        failures.add(r'$.capture.commandJournal has the wrong schema/scenario');
      } else {
        final commands = (value['commands'] as List)
            .whereType<Map>()
            .map((entry) => Map<String, Object?>.from(entry))
            .toList(growable: false);
        _validateCommandJournal(
          commands,
          requirement: requirement,
          senderDeviceId: senderDeviceId,
          recipientDeviceId: recipientDeviceId,
          centralPrebuiltAndroid: centralPrebuiltAndroid,
          parentPreparedCentralPrebuiltAndroid:
              parentPreparedCentralPrebuiltAndroid,
          failures: failures,
        );
      }
    }
  }
}

void _validateCommandJournal(
  List<Map<String, Object?>> commands, {
  required GroupReactionNotificationScenario requirement,
  required String? senderDeviceId,
  required String? recipientDeviceId,
  required bool centralPrebuiltAndroid,
  required bool parentPreparedCentralPrebuiltAndroid,
  required List<String> failures,
}) {
  bool hasCommand(String stage, String executable, String argumentFragment) {
    return commands.any((command) {
      if (command['stage'] != stage || command['executable'] != executable) {
        return false;
      }
      final args = command['args'];
      return args is List &&
          args.any((argument) => '$argument'.contains(argumentFragment));
    });
  }

  bool hasSuccessfulAdbCommand(
    String stage,
    String deviceId,
    Set<String> requiredArguments,
  ) {
    return commands.any((command) {
      final args = command['args'];
      return command['stage'] == stage &&
          command['executable'] == 'adb' &&
          command['exitCode'] == 0 &&
          args is List &&
          args.contains(deviceId) &&
          requiredArguments.every(args.contains);
    });
  }

  bool isInstallCommand(Map<String, Object?> command) {
    final args = command['args'];
    return args is List &&
        (args.contains('install') || args.contains('install-multiple'));
  }

  for (final command in commands) {
    if (command['stage'] is! String ||
        command['executable'] is! String ||
        command['args'] is! List ||
        command['exitCode'] is! int ||
        DateTime.tryParse('${command['recordedAt']}') == null) {
      failures.add(r'$.capture.commandJournal contains a malformed command');
      break;
    }
  }
  final childBuildCommands = commands.where(
    (command) =>
        (command['stage'] == 'candidate_build' ||
            command['stage'] == 'ios_android_sender_build') &&
        command['executable'] == 'flutter' &&
        (command['args'] as List).contains('build'),
  );
  final buildBoundary = centralPrebuiltAndroid
      ? childBuildCommands.isEmpty
      : childBuildCommands.length >= 2;
  final roleInstallCommands = commands.where(
    (command) =>
        command['stage'] ==
            (requirement.recipientPlatform == 'ios'
                ? 'ios_android_sender_build'
                : 'android_role_install') &&
        command['executable'] == 'adb' &&
        isInstallCommand(command),
  );
  final parentPreparedRoleBoundary =
      parentPreparedCentralPrebuiltAndroid &&
      senderDeviceId != null &&
      recipientDeviceId != null &&
      <String>[senderDeviceId, recipientDeviceId].every(
        (deviceId) =>
            hasSuccessfulAdbCommand(
              'android_role_install',
              deviceId,
              const <String>{'shell', 'pm', 'path', 'com.mknoon.app'},
            ) &&
            hasSuccessfulAdbCommand(
              'android_role_install',
              deviceId,
              const <String>{'shell', 'sha256sum'},
            ),
      ) &&
      roleInstallCommands.isEmpty;
  final roleBoundary = parentPreparedCentralPrebuiltAndroid
      ? parentPreparedRoleBoundary
      : roleInstallCommands.isNotEmpty;
  final hasCommonBoundaryCommands =
      hasCommand('device_inventory', 'flutter', 'devices') &&
      hasCommand('device_inventory', 'adb', 'devices') &&
      hasCommand('relay_configuration', 'ssh', 'systemctl') &&
      buildBoundary &&
      roleBoundary;
  if (!hasCommonBoundaryCommands) {
    failures.add(
      r'$.capture.commandJournal is missing common inventory/relay/build/'
      'Android-role preparation boundary commands',
    );
  }
  if (parentPreparedCentralPrebuiltAndroid && !parentPreparedRoleBoundary) {
    failures.add(
      r'$.capture.commandJournal must contain successful both-device pm path '
      'and SHA-256 verification at android_role_install, with no redundant '
      'install for parent-prepared central-prebuilt Android state',
    );
  }
  for (final deviceId in <String?>[senderDeviceId, recipientDeviceId]) {
    if (deviceId != null &&
        !commands.any(
          (command) =>
              command['args'] is List &&
              (command['args'] as List).contains(deviceId),
        )) {
      failures.add(
        r'$.capture.commandJournal does not bind explicit device ' + deviceId,
      );
    }
  }
  if (requirement.recipientPlatform == 'ios') {
    const selectorFragments = <String>[
      'testCreateAnnouncementReactionFixture',
      'testAuthorAnnouncementReactionTarget',
      'testPrepareWarmNotificationTap',
      'testAnnouncementReactionNotificationTap',
    ];
    final missingSelector = selectorFragments.any(
      (selector) => !commands.any(
        (command) =>
            command['executable'] == 'xcodebuild' &&
            command['args'] is List &&
            (command['args'] as List).any(
              (argument) => '$argument'.contains(selector),
            ),
      ),
    );
    final iosInstallCommands = commands
        .where(
          (command) =>
              command['stage'] == 'ios_candidate_install' &&
              command['executable'] == 'xcrun' &&
              command['args'] is List &&
              (command['args'] as List).contains('install'),
        )
        .length;
    if (!hasCommand('ios_candidate_build', 'flutter', 'ios') ||
        iosInstallCommands < 2 ||
        !hasCommand('ios_fixture_staging', 'xcrun', 'copy') ||
        !hasCommand(
          'ios_system_log',
          'idevicesyslog',
          recipientDeviceId ?? '',
        ) ||
        !hasCommand('sqlcipher_observation', 'flutter', _plan257SqlProbe) ||
        missingSelector) {
      failures.add(
        r'$.capture.commandJournal lacks physical iOS build/install/container/'
        'syslog/SQLCipher or named XCUITest boundary commands',
      );
    }
    final lifecycleCommands = commands
        .where((command) => command['stage'] == 'ios_reaction_lifecycle')
        .toList(growable: false);
    if (lifecycleCommands.isEmpty ||
        !lifecycleCommands.any(
          (command) =>
              command['executable'] == 'adb' &&
              (command['args'] as List).contains('input'),
        )) {
      failures.add(
        r'$.capture.commandJournal lacks automated iOS-bound reaction UI '
        'commands',
      );
    }
    if (lifecycleCommands.any(
      (command) => (command['args'] as List).contains('force-stop'),
    )) {
      failures.add(
        r'$.capture.commandJournal used force-stop inside the proof window',
      );
    }
    return;
  }

  final hasSqlCipherBoundary = centralPrebuiltAndroid
      ? hasCommand(
          'sqlcipher_observation',
          'adb',
          'plan257_intro_e2e_config.json',
        )
      : hasCommand('sqlcipher_observation', 'flutter', _plan257SqlProbe);
  final providerInstallCommands = commands.where(
    (command) =>
        command['stage'] == 'provider_registration' &&
        command['executable'] == 'adb' &&
        isInstallCommand(command),
  );
  final providerBoundary = parentPreparedCentralPrebuiltAndroid
      ? recipientDeviceId != null &&
            providerInstallCommands.isEmpty &&
            hasSuccessfulAdbCommand(
              'provider_registration',
              recipientDeviceId,
              const <String>{
                'shell',
                'am',
                'start',
                'com.mknoon.app/.MainActivity',
              },
            )
      : providerInstallCommands.isNotEmpty;
  if (!providerBoundary || !hasSqlCipherBoundary) {
    failures.add(
      r'$.capture.commandJournal is missing Android provider/SQLCipher '
      'boundary commands',
    );
  }
  if (parentPreparedCentralPrebuiltAndroid &&
      providerInstallCommands.isNotEmpty) {
    failures.add(
      r'$.capture.commandJournal contains a forbidden provider reinstall for '
      'parent-prepared central-prebuilt Android state',
    );
  }
  if (centralPrebuiltAndroid &&
      commands.any(
        (command) =>
            command['executable'] == 'flutter' &&
            command['args'] is List &&
            (command['args'] as List).any(
              (argument) => '$argument'.contains(_plan257SqlProbe),
            ),
      )) {
    failures.add(
      r'$.capture.commandJournal contains a forbidden child Flutter '
      'SQLCipher probe for a central-prebuilt Android run',
    );
  }

  final lifecycleStage = requirement.id.endsWith('_message_unread_lifecycle')
      ? 'android_unread_lifecycle'
      : 'android_reaction_lifecycle';
  final processAliveReaction = _processAliveReactionScenarioIds.contains(
    requirement.id,
  );
  final lifecycleCommands = commands
      .where((command) => command['stage'] == lifecycleStage)
      .toList(growable: false);
  if (lifecycleCommands.isEmpty ||
      !lifecycleCommands.any(
        (command) =>
            command['executable'] == 'adb' &&
            (command['args'] as List).contains('input'),
      )) {
    failures.add(
      r'$.capture.commandJournal lacks automated lifecycle UI commands',
    );
  }
  if (lifecycleCommands.any(
    (command) => (command['args'] as List).contains('force-stop'),
  )) {
    failures.add(
      r'$.capture.commandJournal used force-stop inside the proof window',
    );
  }
  if (!requirement.id.endsWith('_message_unread_lifecycle') &&
      !processAliveReaction &&
      (!lifecycleCommands.any(
            (command) => (command['args'] as List).contains('kill'),
          ) ||
          !lifecycleCommands.any(
            (command) => (command['args'] as List).contains('pidof'),
          ))) {
    failures.add(
      r'$.capture.commandJournal lacks killed-process/pidof reaction proof',
    );
  }
  if (processAliveReaction) {
    final homeIndex = lifecycleCommands.indexWhere((command) {
      final args = command['args'] as List;
      return command['executable'] == 'adb' &&
          command['exitCode'] == 0 &&
          (recipientDeviceId == null || args.contains(recipientDeviceId)) &&
          args.contains('input') &&
          args.contains('KEYCODE_HOME');
    });
    final pidIndex = lifecycleCommands.indexWhere((command) {
      final args = command['args'] as List;
      return command['executable'] == 'adb' &&
          command['exitCode'] == 0 &&
          (recipientDeviceId == null || args.contains(recipientDeviceId)) &&
          args.contains('pidof');
    }, homeIndex < 0 ? 0 : homeIndex + 1);
    final usedProcessTermination = lifecycleCommands.any((command) {
      final args = command['args'] as List;
      return args.contains('kill') || args.contains('stop-app');
    });
    if (homeIndex < 0 || pidIndex <= homeIndex || usedProcessTermination) {
      failures.add(
        r'$.capture.commandJournal lacks ordered HOME/pidof process-alive '
        'reaction proof or contains process termination',
      );
    }
  }
  if (!requirement.id.endsWith('_message_unread_lifecycle') &&
      !processAliveReaction) {
    if (centralPrebuiltAndroid) {
      final runtimeProbeIndex = commands.indexWhere(
        (command) =>
            command['stage'] == lifecycleStage &&
            command['executable'] == 'adb' &&
            command['exitCode'] == 0 &&
            command['args'] is List &&
            (command['args'] as List).any(
              (argument) =>
                  '$argument'.contains('plan257_intro_e2e_config.json'),
            ),
      );
      final productionStartIndex = runtimeProbeIndex < 0
          ? -1
          : commands.indexWhere(
              (command) =>
                  command['stage'] == lifecycleStage &&
                  command['executable'] == 'adb' &&
                  command['exitCode'] == 0 &&
                  command['args'] is List &&
                  (command['args'] as List).contains('am') &&
                  (command['args'] as List).contains('start') &&
                  (command['args'] as List).any(
                    (argument) =>
                        '$argument'.contains('com.mknoon.app/.MainActivity'),
                  ),
              runtimeProbeIndex + 1,
            );
      final forbiddenChildProbe = commands.any(
        (command) =>
            command['executable'] == 'flutter' &&
            command['args'] is List &&
            (command['args'] as List).any(
              (argument) => '$argument'.contains(_plan257SqlProbe),
            ),
      );
      if (runtimeProbeIndex < 0 ||
          productionStartIndex <= runtimeProbeIndex ||
          forbiddenChildProbe) {
        failures.add(
          r'$.capture.commandJournal lacks the installed-app exact-ADD '
          'runtime probe and production retry launch, or contains a '
          'forbidden child Flutter probe',
        );
      }
      return;
    }
    final duplicateProbeIndex = commands.indexWhere(
      (command) =>
          command['stage'] == lifecycleStage &&
          command['executable'] == 'flutter' &&
          command['exitCode'] == 0 &&
          command['args'] is List &&
          (command['args'] as List).any(
            (argument) => '$argument'.contains(_plan257SqlProbe),
          ) &&
          (command['args'] as List).contains('drive') &&
          (command['args'] as List).contains('--keep-app-running') &&
          (command['args'] as List).contains(
            'test_driver/integration_test.dart',
          ),
    );
    final normalReinstallIndex = commands.indexWhere(
      (command) =>
          command['stage'] == lifecycleStage &&
          command['executable'] == 'adb' &&
          command['exitCode'] == 0 &&
          command['args'] is List &&
          (command['args'] as List).contains('install') &&
          (command['args'] as List).any(
            (argument) => '$argument'.contains('candidate_normal_arm64.apk'),
          ),
    );
    final productionStartIndex = normalReinstallIndex < 0
        ? -1
        : commands.indexWhere(
            (command) =>
                command['stage'] == lifecycleStage &&
                command['executable'] == 'adb' &&
                command['exitCode'] == 0 &&
                command['args'] is List &&
                (command['args'] as List).contains('shell') &&
                (command['args'] as List).contains('am') &&
                (command['args'] as List).contains('start') &&
                (command['args'] as List).any(
                  (argument) =>
                      '$argument'.contains('com.mknoon.app/.MainActivity'),
                ),
            normalReinstallIndex + 1,
          );
    if (duplicateProbeIndex < 0 ||
        normalReinstallIndex <= duplicateProbeIndex ||
        productionStartIndex <= normalReinstallIndex) {
      failures.add(
        r'$.capture.commandJournal lacks ordered exact-ADD probe and '
        'production retry launch commands',
      );
    }
  }
}

const String _plan257SqlProbe =
    'group_reaction_notification_sqlcipher_probe_test.dart';
const String _plan257DuplicateRedrivePrefix =
    'MKNOON_257_DUPLICATE_REDRIVE_OBSERVATION ';

Future<void> _validatePlan398IosGroupMessageDiagnosticArtifact({
  required Map<String, Object?> root,
  required GroupReactionNotificationScenario requirement,
  required String? expectedSenderDeviceId,
  required String? expectedRecipientDeviceId,
  required File? deploymentReceipt,
  required File? diagnosticAttemptMarker,
  required List<String> failures,
}) async {
  const rootPath = r'$';
  _expectExactKeys(
    root,
    const <String>{
      'schema',
      'version',
      'scenario',
      'testCase',
      'status',
      'generatedBy',
      'diagnosticOnlyMessageWindow',
      'closurePassed',
      'disposition',
      'stagingDeploymentReceiptSha256',
      'singleOwnerDeclared',
      'diagnosticAttemptClaimed',
      'diagnosticAttemptClaimSha256',
      'topology',
      'buildInputs',
      'window',
      'execution',
      'redaction',
    },
    rootPath,
    failures,
  );
  for (final entry in <String, Object?>{
    'schema': plan398IosGroupMessageDiagnosticArtifactSchema,
    'version': plan398IosGroupMessageDiagnosticArtifactVersion,
    'scenario': requirement.id,
    'testCase': requirement.testCase,
    'status': 'diagnostic_complete',
    'generatedBy': 'automated_capture_pipeline',
    'diagnosticOnlyMessageWindow': true,
    'closurePassed': false,
    'singleOwnerDeclared': true,
    'diagnosticAttemptClaimed': true,
  }.entries) {
    _expectValue(root, entry.key, entry.value, rootPath, failures);
  }
  const dispositions = <String>{
    'repo_owned_duplicate_dispatch',
    'candidate_single_unattributed_duplicate',
    'claim_absent_or_noncandidate',
    'local_contender',
    'clean_nonreproduction',
  };
  if (!dispositions.contains(root['disposition'])) {
    failures.add(r'$.disposition is not a closed complete diagnostic outcome');
  }
  for (final key in const <String>[
    'stagingDeploymentReceiptSha256',
    'diagnosticAttemptClaimSha256',
  ]) {
    if (!_isSha256(root[key])) failures.add('\$.$key must be SHA-256');
  }

  Future<(Map<String, Object?>, String)?> readAuthority(
    File? explicit,
    String environmentKey,
    String path,
  ) async {
    final configured =
        explicit ??
        ((Platform.environment[environmentKey]?.trim().isNotEmpty ?? false)
            ? File(Platform.environment[environmentKey]!).absolute
            : null);
    if (configured == null || !await configured.exists()) {
      failures.add('$path requires exported $environmentKey evidence');
      return null;
    }
    try {
      final stat = await configured.stat();
      if ((stat.mode & 0x3f) != 0) {
        failures.add('$path evidence must be private mode 0600');
        return null;
      }
      final bytes = await configured.readAsBytes();
      final decoded = jsonDecode(utf8.decode(bytes));
      final map = _asStringMap(decoded, path, failures);
      if (map == null) return null;
      return (map, sha256.convert(bytes).toString());
    } on Object {
      failures.add('$path evidence is unreadable or invalid JSON');
      return null;
    }
  }

  final deployment = await readAuthority(
    deploymentReceipt,
    'PLAN398_DEPLOYMENT_RECEIPT',
    r'$.stagingDeploymentReceiptSha256',
  );
  if (deployment != null) {
    if (deployment.$1['schema'] !=
            'mknoon.plan398.staging-deployment-receipt.v1' ||
        deployment.$1['ownerRunId'] != 'diagnostic' ||
        deployment.$1['singleOwnerDeclared'] != true ||
        deployment.$2 != root['stagingDeploymentReceiptSha256']) {
      failures.add(
        r'$.stagingDeploymentReceiptSha256 is not bound to closed single-owner authority',
      );
    }
  }
  final marker = await readAuthority(
    diagnosticAttemptMarker,
    'PLAN398_DIAGNOSTIC_ATTEMPT_MARKER',
    r'$.diagnosticAttemptClaimSha256',
  );
  if (marker != null) {
    final claimValue = marker.$1['claimValue'];
    if (marker.$1['schema'] != 'mknoon.plan398.diagnostic-attempt-claim.v1' ||
        marker.$1['ownerRunId'] != 'diagnostic' ||
        claimValue is! String ||
        !RegExp(r'^[A-Za-z0-9._:-]{16,160}$').hasMatch(claimValue) ||
        marker.$2 != root['diagnosticAttemptClaimSha256']) {
      failures.add(
        r'$.diagnosticAttemptClaimSha256 is not bound to the durable diagnostic claim',
      );
    }
  }

  final topology = _mapField(root, 'topology', rootPath, failures);
  String? recipientDeviceId;
  if (topology != null) {
    _expectExactKeys(
      topology,
      const <String>{'groupType', 'sender', 'recipient'},
      r'$.topology',
      failures,
    );
    _expectValue(topology, 'groupType', 'chat', r'$.topology', failures);
    for (final entry in <(String, String, String, String?)>[
      ('sender', 'android', 'physical', expectedSenderDeviceId),
      ('recipient', 'ios', 'physical', expectedRecipientDeviceId),
    ]) {
      final party = _mapField(topology, entry.$1, r'$.topology', failures);
      if (party == null) continue;
      _expectExactKeys(
        party,
        const <String>{'platform', 'deviceKind', 'deviceId', 'liveDiscovered'},
        '\$.topology.${entry.$1}',
        failures,
      );
      _expectValue(
        party,
        'platform',
        entry.$2,
        '\$.topology.${entry.$1}',
        failures,
      );
      _expectValue(
        party,
        'deviceKind',
        entry.$3,
        '\$.topology.${entry.$1}',
        failures,
      );
      _expectValue(
        party,
        'liveDiscovered',
        true,
        '\$.topology.${entry.$1}',
        failures,
      );
      final deviceId = _requiredString(
        party,
        'deviceId',
        '\$.topology.${entry.$1}',
        failures,
      );
      if (entry.$4 != null && deviceId != entry.$4) {
        failures.add(
          '\$.topology.${entry.$1}.deviceId is not live-target bound',
        );
      }
      if (entry.$1 == 'recipient') recipientDeviceId = deviceId;
    }
  }

  final buildInputs = _mapField(root, 'buildInputs', rootPath, failures);
  if (buildInputs != null) {
    _expectExactKeys(
      buildInputs,
      const <String>{
        'androidProfileId',
        'androidInputDigest',
        'androidArtifactDigest',
        'iosProfileId',
        'iosInputDigest',
        'iosArtifactDigest',
        'setupProfileId',
        'setupApplicationSha256',
        'setupPreparationCompileCommands',
        'captureChildBuildCount',
        'centralApplicationSha256',
        'gradedWindowChildBuildCount',
      },
      r'$.buildInputs',
      failures,
    );
    _expectValue(
      buildInputs,
      'androidProfileId',
      'android.production_fcm',
      r'$.buildInputs',
      failures,
    );
    _expectValue(
      buildInputs,
      'iosProfileId',
      'ios.device.production',
      r'$.buildInputs',
      failures,
    );
    _expectValue(
      buildInputs,
      'setupProfileId',
      'ios.device.group_reaction_notification_397',
      r'$.buildInputs',
      failures,
    );
    _expectValue(
      buildInputs,
      'setupPreparationCompileCommands',
      1,
      r'$.buildInputs',
      failures,
    );
    _expectValue(
      buildInputs,
      'captureChildBuildCount',
      0,
      r'$.buildInputs',
      failures,
    );
    _expectValue(
      buildInputs,
      'gradedWindowChildBuildCount',
      0,
      r'$.buildInputs',
      failures,
    );
    for (final key in const <String>[
      'androidInputDigest',
      'androidArtifactDigest',
      'iosInputDigest',
      'iosArtifactDigest',
      'setupApplicationSha256',
      'centralApplicationSha256',
    ]) {
      if (!_isSha256(buildInputs[key])) {
        failures.add('\$.buildInputs.$key must be SHA-256');
      }
    }
  }

  final window = _mapField(root, 'window', rootPath, failures);
  if (window != null) {
    _validatePlan398DiagnosticWindow(
      window: window,
      recipientDeviceId: recipientDeviceId,
      expectedDisposition: root['disposition'],
      failures: failures,
    );
  }

  final execution = _mapField(root, 'execution', rootPath, failures);
  if (execution != null) {
    _expectExactKeys(
      execution,
      const <String>{
        'automation',
        'manualTaps',
        'childBuildsDuringGradedWindows',
        'messageSendCount',
        'reactionAddCount',
        'reactionRemoveCount',
        'reactionReAddCount',
        'notificationTapCount',
      },
      r'$.execution',
      failures,
    );
    for (final entry in const <String, Object?>{
      'automation': 'fully_automated',
      'manualTaps': 0,
      'childBuildsDuringGradedWindows': 0,
      'messageSendCount': 1,
      'reactionAddCount': 0,
      'reactionRemoveCount': 0,
      'reactionReAddCount': 0,
      'notificationTapCount': 0,
    }.entries) {
      _expectValue(execution, entry.key, entry.value, r'$.execution', failures);
    }
  }
  final redaction = _mapField(root, 'redaction', rootPath, failures);
  if (redaction != null) {
    _expectExactKeys(
      redaction,
      const <String>{
        'pushTokensPersisted',
        'secretKeysPersisted',
        'ciphertextPersisted',
        'plaintextPayloadPersisted',
        'rawPeerIdsPersisted',
        'rawGroupOrMessageIdsPersisted',
      },
      r'$.redaction',
      failures,
    );
    for (final key in redaction.keys) {
      _expectValue(redaction, key, false, r'$.redaction', failures);
    }
  }
}

void _validatePlan398DiagnosticWindow({
  required Map<String, Object?> window,
  required String? recipientDeviceId,
  required Object? expectedDisposition,
  required List<String> failures,
}) {
  const path = r'$.window';
  _expectExactKeys(
    window,
    const <String>{
      'phase',
      'ordinal',
      'payloadKind',
      'windowIdSha256',
      'observerRunIdSha256',
      'observerNonceSha256',
      'androidObservation',
      'provider',
      'nse',
      'nativeInventory',
      'diagnostics',
      'relayJournalSha256',
      'relayJournalLineCount',
      'openedAt',
      'closedAt',
    },
    path,
    failures,
  );
  for (final entry in const <String, Object?>{
    'phase': 'message',
    'ordinal': 1,
    'payloadKind': 'group_message',
  }.entries) {
    _expectValue(window, entry.key, entry.value, path, failures);
  }
  for (final key in const <String>[
    'windowIdSha256',
    'observerRunIdSha256',
    'observerNonceSha256',
    'relayJournalSha256',
  ]) {
    if (!_isSha256(window[key])) failures.add('$path.$key must be SHA-256');
  }
  if (window['relayJournalLineCount'] is! int ||
      (window['relayJournalLineCount']! as int) < 1) {
    failures.add('$path.relayJournalLineCount must be positive');
  }
  final opened = DateTime.tryParse('${window['openedAt']}');
  final closed = DateTime.tryParse('${window['closedAt']}');
  if (opened == null || closed == null || closed.isBefore(opened)) {
    failures.add('$path must contain an ordered observation interval');
  }

  final android = _mapField(window, 'androidObservation', path, failures);
  final provider = _mapField(window, 'provider', path, failures);
  final nse = _mapField(window, 'nse', path, failures);
  final native = _mapField(window, 'nativeInventory', path, failures);
  final diagnostics = _mapField(window, 'diagnostics', path, failures);
  if (android == null || provider == null || native == null) return;

  _expectExactKeys(
    android,
    const <String>{
      'schema',
      'phase',
      'groupIdSha256',
      'messageIdSha256',
      'targetMessageIdSha256',
      'eventIdSha256',
      'expectedCollapseIdentifierSha256',
      'reactionIdSha256',
      'reactionTargetIdSha256',
      'firstIncoming',
      'targetIncoming',
      'targetRead',
      'reactionRows',
      'reactionEmojiSha256',
      'rawIdentifiersPersisted',
    },
    '$path.androidObservation',
    failures,
  );
  for (final entry in const <String, Object?>{
    'schema': 'mknoon.plan257.sqlcipher-observation.v1',
    'phase': 'message',
    'reactionIdSha256': null,
    'reactionTargetIdSha256': null,
    'firstIncoming': false,
    'targetIncoming': true,
    'targetRead': true,
    'reactionRows': 0,
    'reactionEmojiSha256': null,
    'rawIdentifiersPersisted': false,
  }.entries) {
    _expectValue(
      android,
      entry.key,
      entry.value,
      '$path.androidObservation',
      failures,
    );
  }
  for (final key in const <String>[
    'groupIdSha256',
    'messageIdSha256',
    'targetMessageIdSha256',
    'eventIdSha256',
    'expectedCollapseIdentifierSha256',
  ]) {
    if (!_isSha256(android[key])) {
      failures.add('$path.androidObservation.$key must be SHA-256');
    }
  }
  if (android['eventIdSha256'] != android['messageIdSha256']) {
    failures.add('$path.androidObservation event must bind the message row');
  }

  final receiptValid = _isValidPlan398NativeObservationReceipt(
    native,
    phase: 'message',
    captureNonceSha256: '${window['observerNonceSha256']}',
    receiverDeviceIdSha256: recipientDeviceId == null
        ? ''
        : sha256.convert(utf8.encode(recipientDeviceId)).toString(),
    expectedGroupIdSha256: '${android['groupIdSha256']}',
    expectedEventIdSha256: '${android['eventIdSha256']}',
    expectedTargetMessageIdSha256: '${android['targetMessageIdSha256']}',
    expectedCollapseIdentifierSha256:
        '${android['expectedCollapseIdentifierSha256']}',
  );
  if (!receiptValid || native['diagnosticComplete'] != true) {
    failures.add(
      '$path.nativeInventory is not a complete exact-bound Plan 398 receipt',
    );
  }

  _expectExactKeys(
    provider,
    const <String>{
      'metricFamily',
      'relayGroupMessageDispatchSource',
      'groupInboxAcceptedDelta',
      'groupInboxFailedDelta',
      'groupContentAcceptedDelta',
      'groupContentFailedDelta',
      'providerSingleFirstAttempt',
      'acceptedDispatchCorrelationSha256',
      'acceptedProviderMessageIdSha256',
      'baselineSha256',
      'finalSha256',
      'deletedOrUnattributedEvidence',
    },
    '$path.provider',
    failures,
  );
  _expectValue(
    provider,
    'metricFamily',
    relayGroupMessageDispatchCounter,
    '$path.provider',
    failures,
  );
  if (!const <String>{
        'groupInbox',
        'groupContent',
      }.contains(provider['relayGroupMessageDispatchSource']) ||
      provider['providerSingleFirstAttempt'] is! bool ||
      provider['deletedOrUnattributedEvidence'] != false) {
    failures.add('$path.provider has open or unattributed evidence');
  }
  final acceptedDispatchCorrelation =
      provider['acceptedDispatchCorrelationSha256'];
  if (!_isSha256(acceptedDispatchCorrelation)) {
    failures.add(
      '$path.provider.acceptedDispatchCorrelationSha256 must be SHA-256',
    );
  }
  if (!_isNullableSha256(provider['acceptedProviderMessageIdSha256'])) {
    failures.add(
      '$path.provider.acceptedProviderMessageIdSha256 must be null or SHA-256',
    );
  }
  if (_isSha256(acceptedDispatchCorrelation)) {
    final rawRecords = native['diagnosticRecords'];
    final acceptedDispatchSeen =
        rawRecords is List &&
        rawRecords.whereType<Map>().any(
          (record) =>
              record['dispatchCorrelationSha256'] ==
              acceptedDispatchCorrelation,
        );
    if (!acceptedDispatchSeen) {
      failures.add(
        '$path.provider.acceptedDispatchCorrelationSha256 does not match '
        'any delivered card',
      );
    }
  }
  for (final key in const <String>[
    'groupInboxAcceptedDelta',
    'groupInboxFailedDelta',
    'groupContentAcceptedDelta',
    'groupContentFailedDelta',
  ]) {
    if (provider[key] is! int || (provider[key]! as int).isNegative) {
      failures.add('$path.provider.$key must be a nonnegative integer');
    }
  }
  for (final key in const <String>['baselineSha256', 'finalSha256']) {
    if (!_isSha256(provider[key])) {
      failures.add('$path.provider.$key must be SHA-256');
    }
  }
  if (provider['baselineSha256'] == provider['finalSha256']) {
    failures.add('$path.provider must bind distinct metric scrapes');
  }

  if (nse != null) {
    _expectExactKeys(
      nse,
      const <String>{
        'payloadKind',
        'decryptOkCount',
        'didReceiveCount',
        'decryptFailureCount',
        'timeoutCount',
        'runOwnedLocalPublicationCount',
        'contenderDisposition',
        'contenderSuppressionCount',
        'windowSha256',
        'rawPayloadPersisted',
      },
      '$path.nse',
      failures,
    );
    for (final entry in const <String, Object?>{
      'payloadKind': 'group_message',
      'decryptOkCount': 1,
      'didReceiveCount': 1,
      'decryptFailureCount': 0,
      'timeoutCount': 0,
      'runOwnedLocalPublicationCount': 0,
      'rawPayloadPersisted': false,
    }.entries) {
      _expectValue(nse, entry.key, entry.value, '$path.nse', failures);
    }
    if (!_isSha256(nse['windowSha256'])) {
      failures.add('$path.nse.windowSha256 must be SHA-256');
    }
  }
  if (diagnostics != null) {
    _expectExactKeys(
      diagnostics,
      const <String>{
        'runOwnedLocalPublicationCount',
        'contenderDisposition',
        'contenderSuppressionCount',
        'rawIdentifiersPersisted',
        'rawPayloadPersisted',
      },
      '$path.diagnostics',
      failures,
    );
    if (diagnostics['rawIdentifiersPersisted'] != false ||
        diagnostics['rawPayloadPersisted'] != false ||
        diagnostics['runOwnedLocalPublicationCount'] !=
            nse?['runOwnedLocalPublicationCount'] ||
        diagnostics['contenderDisposition'] != nse?['contenderDisposition'] ||
        diagnostics['contenderSuppressionCount'] !=
            nse?['contenderSuppressionCount']) {
      failures.add('$path.diagnostics is not redacted and NSE-bound');
    }
  }

  final computed = plan398DiagnosticDisposition(native, provider);
  if (computed == 'incomplete_evidence' || computed != expectedDisposition) {
    failures.add(
      '$path does not select its declared unique diagnostic disposition',
    );
  }
}

String plan398DiagnosticDisposition(
  Map<String, Object?> native,
  Map<String, Object?> provider,
) {
  if (native['diagnosticComplete'] != true ||
      provider['deletedOrUnattributedEvidence'] != false) {
    return 'incomplete_evidence';
  }
  final rawRecords = native['diagnosticRecords'];
  if (rawRecords is! List ||
      rawRecords.any((record) => record is! Map<String, Object?>)) {
    return 'incomplete_evidence';
  }
  final records = rawRecords.cast<Map<String, Object?>>();
  int integer(String key) => provider[key] is int ? provider[key]! as int : -1;
  final inboxAccepted = integer('groupInboxAcceptedDelta');
  final inboxFailed = integer('groupInboxFailedDelta');
  final contentAccepted = integer('groupContentAcceptedDelta');
  final contentFailed = integer('groupContentFailedDelta');
  final source = provider['relayGroupMessageDispatchSource'];
  final expectedClaim = switch (source) {
    'groupInbox' => 'groupInbox',
    'groupContent' => 'groupContent',
    _ => null,
  };
  final accepted = inboxAccepted + contentAccepted;
  final sourceBound =
      expectedClaim != null &&
      ((source == 'groupInbox' &&
              inboxAccepted == accepted &&
              contentAccepted == 0 &&
              contentFailed == 0) ||
          (source == 'groupContent' &&
              contentAccepted == accepted &&
              inboxAccepted == 0 &&
              inboxFailed == 0));
  if (!sourceBound ||
      accepted < 1 ||
      accepted > 2 ||
      inboxFailed != 0 ||
      contentFailed != 0) {
    return 'incomplete_evidence';
  }
  final remote = records
      .where((record) => record['triggerOrigin'] == 'remote')
      .length;
  final local = records
      .where((record) => record['triggerOrigin'] == 'local')
      .length;
  final canonical = records
      .where((record) => record['expectedCollapseIdentifierMatch'] == true)
      .length;
  final allCandidate = records.every(
    (record) => record['dispatchClaim'] == expectedClaim,
  );
  final noncanonical = records
      .where((record) => record['expectedCollapseIdentifierMatch'] == false)
      .toList(growable: false);
  final singleAttempt = provider['providerSingleFirstAttempt'] == true;

  if (records.length == 2 && remote == 2 && local == 0 && canonical == 1) {
    if (accepted == 2 && allCandidate && !singleAttempt) {
      return 'repo_owned_duplicate_dispatch';
    }
    if (accepted == 1 && singleAttempt && allCandidate) {
      return 'candidate_single_unattributed_duplicate';
    }
    if (accepted == 1 &&
        singleAttempt &&
        noncanonical.length == 1 &&
        noncanonical.single['dispatchClaim'] != expectedClaim) {
      return 'claim_absent_or_noncandidate';
    }
  }
  if (records.length == 2 && remote == 1 && local == 1 && accepted == 1) {
    return 'local_contender';
  }
  if (records.length == 1 &&
      remote == 1 &&
      local == 0 &&
      canonical == 1 &&
      accepted == 1 &&
      singleAttempt &&
      allCandidate) {
    return 'clean_nonreproduction';
  }
  return 'incomplete_evidence';
}

Future<void> _validateIosChatGroupMessageAndReactionArtifact({
  required Map<String, Object?> root,
  required File artifactFile,
  required GroupReactionNotificationScenario requirement,
  required String? expectedSenderDeviceId,
  required String? expectedRecipientDeviceId,
  required List<String> failures,
}) async {
  const rootPath = r'$';
  _expectExactKeys(
    root,
    const <String>{
      'schema',
      'version',
      'scenario',
      'testCase',
      'status',
      'generatedBy',
      'topology',
      'centralBuild',
      'capture',
      'identities',
      'windows',
      'execution',
      'redaction',
    },
    rootPath,
    failures,
  );
  _expectValue(
    root,
    'schema',
    iosChatGroupMessageAndReactionArtifactSchema,
    rootPath,
    failures,
  );
  _expectValue(
    root,
    'version',
    iosChatGroupMessageAndReactionArtifactVersion,
    rootPath,
    failures,
  );
  _expectValue(root, 'scenario', requirement.id, rootPath, failures);
  _expectValue(root, 'testCase', requirement.testCase, rootPath, failures);
  _expectValue(root, 'status', 'passed', rootPath, failures);
  _expectValue(
    root,
    'generatedBy',
    'automated_capture_pipeline',
    rootPath,
    failures,
  );

  final topology = _mapField(root, 'topology', rootPath, failures);
  if (topology != null) {
    _expectExactKeys(
      topology,
      const <String>{'groupType', 'sender', 'recipient'},
      r'$.topology',
      failures,
    );
    _expectValue(topology, 'groupType', 'chat', r'$.topology', failures);
    final sender = _mapField(topology, 'sender', r'$.topology', failures);
    final recipient = _mapField(topology, 'recipient', r'$.topology', failures);
    void validateParty(
      Map<String, Object?>? party, {
      required String path,
      required String platform,
      required String deviceKind,
      required String? expectedId,
    }) {
      if (party == null) return;
      _expectExactKeys(
        party,
        const <String>{'platform', 'deviceKind', 'deviceId', 'liveDiscovered'},
        path,
        failures,
      );
      _expectValue(party, 'platform', platform, path, failures);
      _expectValue(party, 'deviceKind', deviceKind, path, failures);
      _expectValue(party, 'liveDiscovered', true, path, failures);
      final deviceId = _requiredString(party, 'deviceId', path, failures);
      if (expectedId != null && deviceId != expectedId) {
        failures.add('$path.deviceId does not match the pinned live target');
      }
    }

    validateParty(
      sender,
      path: r'$.topology.sender',
      platform: 'android',
      deviceKind: 'physical',
      expectedId: expectedSenderDeviceId,
    );
    validateParty(
      recipient,
      path: r'$.topology.recipient',
      platform: 'ios',
      deviceKind: 'physical',
      expectedId: expectedRecipientDeviceId,
    );
  }

  final central = _mapField(root, 'centralBuild', rootPath, failures);
  if (central != null) {
    _expectExactKeys(
      central,
      const <String>{
        'android',
        'ios',
        'setupApplicationSha256',
        'centralApplicationSha256',
        'setupSelectorsReusedOneProduct',
        'setupChildBuildCount',
        'androidChildBuildCount',
        'iosNormalChildBuildCount',
        'normalInstalledInPlace',
        'uninstallBetweenSetupAndNormal',
        'setupContainerPreserved',
      },
      r'$.centralBuild',
      failures,
    );
    final android = _mapField(central, 'android', r'$.centralBuild', failures);
    final ios = _mapField(central, 'ios', r'$.centralBuild', failures);
    void validateCentralProfile(
      Map<String, Object?>? value, {
      required String path,
      required String profile,
    }) {
      if (value == null) return;
      _expectExactKeys(
        value,
        const <String>{
          'profileId',
          'inputDigest',
          'artifactDigest',
          'attestationAdjacent',
        },
        path,
        failures,
      );
      _expectValue(value, 'profileId', profile, path, failures);
      _expectValue(value, 'attestationAdjacent', true, path, failures);
      for (final key in const <String>['inputDigest', 'artifactDigest']) {
        if (!_isSha256(value[key])) {
          failures.add('$path.$key must be a bound SHA-256 digest');
        }
      }
    }

    validateCentralProfile(
      android,
      path: r'$.centralBuild.android',
      profile: 'android.production_fcm',
    );
    validateCentralProfile(
      ios,
      path: r'$.centralBuild.ios',
      profile: 'ios.device.production',
    );
    final setupDigest = central['setupApplicationSha256'];
    final normalDigest = central['centralApplicationSha256'];
    if (!_isSha256(setupDigest) ||
        !_isSha256(normalDigest) ||
        setupDigest == normalDigest) {
      failures.add(
        r'$.centralBuild must bind distinct setup and central app digests',
      );
    }
    for (final entry in const <String, Object?>{
      'setupSelectorsReusedOneProduct': true,
      'setupChildBuildCount': 1,
      'androidChildBuildCount': 0,
      'iosNormalChildBuildCount': 0,
      'normalInstalledInPlace': true,
      'uninstallBetweenSetupAndNormal': false,
      'setupContainerPreserved': true,
    }.entries) {
      _expectValue(
        central,
        entry.key,
        entry.value,
        r'$.centralBuild',
        failures,
      );
    }
  }

  final capture = _mapField(root, 'capture', rootPath, failures);
  if (capture != null) {
    _expectExactKeys(
      capture,
      const <String>{
        'centralBuildProvenance',
        'androidBuildReport',
        'iosBuildReport',
        'androidAttestation',
        'iosAttestation',
        'iosBundleManifest',
        'setupInstall',
        'centralNormalInstall',
        'commandJournal',
      },
      r'$.capture',
      failures,
    );
    final retained = <String, String>{};
    for (final key in const <String>[
      'centralBuildProvenance',
      'androidBuildReport',
      'iosBuildReport',
      'androidAttestation',
      'iosAttestation',
      'iosBundleManifest',
      'setupInstall',
      'centralNormalInstall',
      'commandJournal',
    ]) {
      final text = await _readReferencedText(
        capture[key],
        artifactFile: artifactFile,
        path: r'$.capture.' + key,
        failures: failures,
      );
      if (text != null) retained[key] = text;
    }
    if (central != null) {
      _validatePlan397RetainedCentralFiles(
        retained: retained,
        central: central,
        failures: failures,
      );
    }
  }

  final identities = _mapField(root, 'identities', rootPath, failures);
  if (identities != null) {
    _expectExactKeys(
      identities,
      const <String>{
        'groupNameSha256',
        'messageTextSha256',
        'targetTextSha256',
      },
      r'$.identities',
      failures,
    );
    for (final key in const <String>[
      'groupNameSha256',
      'messageTextSha256',
      'targetTextSha256',
    ]) {
      if (!_isSha256(identities[key])) {
        failures.add('\$.identities.$key must be SHA-256');
      }
    }
    if (identities.values.toSet().length != 3) {
      failures.add(r'$.identities digests must be pairwise distinct');
    }
  }

  final rawWindows = root['windows'];
  if (rawWindows is! List || rawWindows.length != 2) {
    failures.add(r'$.windows must contain exactly message then reaction');
  }
  final windows = rawWindows is List
      ? rawWindows
            .asMap()
            .entries
            .map(
              (entry) => _asStringMap(
                entry.value,
                '\$.windows[${entry.key}]',
                failures,
              ),
            )
            .whereType<Map<String, Object?>>()
            .toList(growable: false)
      : const <Map<String, Object?>>[];
  if (windows.length == 2) {
    final message = _validatePlan397Window(
      window: windows[0],
      index: 0,
      phase: 'message',
      payloadKind: 'group_message',
      expectedMetricFamily: relayPushSentCounter,
      identities: identities,
      expectedRecipientDeviceId: expectedRecipientDeviceId,
      failures: failures,
    );
    final reaction = _validatePlan397Window(
      window: windows[1],
      index: 1,
      phase: 'reaction',
      payloadKind: 'group_reaction',
      expectedMetricFamily: relayGroupReactionWakeCounter,
      identities: identities,
      expectedRecipientDeviceId: expectedRecipientDeviceId,
      failures: failures,
    );
    if (message != null && reaction != null) {
      for (final key in const <String>[
        'groupIdSha256',
        'messageIdSha256',
        'targetMessageIdSha256',
      ]) {
        if (message.android[key] != reaction.android[key]) {
          failures.add(
            r'$.windows must retain the same Android-observed ' + key,
          );
        }
      }
      if (message.android['eventIdSha256'] ==
          reaction.android['eventIdSha256']) {
        failures.add(r'$.windows event identities must be phase-distinct');
      }
      final distinctPairs = <String, List<Object?>>{
        'window ids': <Object?>[
          message.window['windowIdSha256'],
          reaction.window['windowIdSha256'],
        ],
        'observer run ids': <Object?>[
          message.window['observerRunIdSha256'],
          reaction.window['observerRunIdSha256'],
        ],
        'observer nonces': <Object?>[
          message.window['observerNonceSha256'],
          reaction.window['observerNonceSha256'],
        ],
        'provider baselines': <Object?>[
          message.provider['baselineSha256'],
          reaction.provider['baselineSha256'],
        ],
        'provider finals': <Object?>[
          message.provider['finalSha256'],
          reaction.provider['finalSha256'],
        ],
        'NSE windows': <Object?>[
          message.nse['windowSha256'],
          reaction.nse['windowSha256'],
        ],
        'native request identifiers': <Object?>[
          (message.native['requestIdentifierSha256'] as List?)?.singleOrNull,
          (reaction.native['requestIdentifierSha256'] as List?)?.singleOrNull,
        ],
      };
      for (final entry in distinctPairs.entries) {
        if (entry.value.length != 2 || entry.value.toSet().length != 2) {
          failures.add(r'$.windows must use distinct ' + entry.key);
        }
      }
      final messageClosed = DateTime.tryParse('${message.window['closedAt']}');
      final reactionOpened = DateTime.tryParse(
        '${reaction.window['openedAt']}',
      );
      if (messageClosed == null ||
          reactionOpened == null ||
          reactionOpened.isBefore(messageClosed)) {
        failures.add(r'$.windows reaction must open after message closes');
      }
    }
  }

  final execution = _mapField(root, 'execution', rootPath, failures);
  if (execution != null) {
    _expectExactKeys(
      execution,
      const <String>{
        'automation',
        'manualTaps',
        'childBuildsDuringGradedWindows',
        'messageSendCount',
        'reactionAddCount',
        'reactionRemoveCount',
        'reactionReAddCount',
      },
      r'$.execution',
      failures,
    );
    for (final entry in const <String, Object?>{
      'automation': 'fully_automated',
      'manualTaps': 0,
      'childBuildsDuringGradedWindows': 0,
      'messageSendCount': 1,
      'reactionAddCount': 1,
      'reactionRemoveCount': 0,
      'reactionReAddCount': 0,
    }.entries) {
      _expectValue(execution, entry.key, entry.value, r'$.execution', failures);
    }
  }

  final redaction = _mapField(root, 'redaction', rootPath, failures);
  if (redaction != null) {
    _expectExactKeys(
      redaction,
      const <String>{
        'pushTokensPersisted',
        'secretKeysPersisted',
        'ciphertextPersisted',
        'plaintextPayloadPersisted',
        'rawPeerIdsPersisted',
        'rawGroupOrMessageIdsPersisted',
      },
      r'$.redaction',
      failures,
    );
    for (final key in redaction.keys) {
      _expectValue(redaction, key, false, r'$.redaction', failures);
    }
  }
}

final class _Plan397WindowEvidence {
  const _Plan397WindowEvidence({
    required this.window,
    required this.android,
    required this.provider,
    required this.nse,
    required this.native,
  });

  final Map<String, Object?> window;
  final Map<String, Object?> android;
  final Map<String, Object?> provider;
  final Map<String, Object?> nse;
  final Map<String, Object?> native;
}

void _validatePlan397RetainedCentralFiles({
  required Map<String, String> retained,
  required Map<String, Object?> central,
  required List<String> failures,
}) {
  Map<String, Object?>? decode(String key) {
    final raw = retained[key];
    return raw == null ? null : _decodeObject(raw, '\$.capture.$key', failures);
  }

  final provenance = decode('centralBuildProvenance');
  final androidReport = decode('androidBuildReport');
  final iosReport = decode('iosBuildReport');
  final androidAttestation = decode('androidAttestation');
  final iosAttestation = decode('iosAttestation');
  final manifest = decode('iosBundleManifest');
  final centralAndroid = _asStringMap(
    central['android'],
    r'$.centralBuild.android',
    failures,
  );
  final centralIos = _asStringMap(
    central['ios'],
    r'$.centralBuild.ios',
    failures,
  );

  void validateProfile({
    required String profile,
    required Map<String, Object?>? summary,
    required Map<String, Object?>? report,
    required Map<String, Object?>? attestation,
    required String path,
  }) {
    if (summary == null || report == null || attestation == null) return;
    final builds = report['builds'];
    final digests = builds is Map ? builds['artifactDigests'] : null;
    final reportDigest = digests is Map ? digests[profile] : null;
    if (reportDigest != summary['artifactDigest']) {
      failures.add('$path build report is not artifact-digest bound');
    }
    if (attestation['schemaVersion'] != 1 ||
        attestation['profileId'] != profile ||
        attestation['inputDigest'] != summary['inputDigest'] ||
        attestation['artifactDigest'] != summary['artifactDigest']) {
      failures.add('$path adjacent attestation is not summary-bound');
    }
  }

  validateProfile(
    profile: 'android.production_fcm',
    summary: centralAndroid,
    report: androidReport,
    attestation: androidAttestation,
    path: r'$.capture.android',
  );
  validateProfile(
    profile: 'ios.device.production',
    summary: centralIos,
    report: iosReport,
    attestation: iosAttestation,
    path: r'$.capture.ios',
  );

  if (provenance != null) {
    final provenanceAndroid = _asStringMap(
      provenance['android'],
      r'$.capture.centralBuildProvenance.android',
      failures,
    );
    final provenanceIos = _asStringMap(
      provenance['ios'],
      r'$.capture.centralBuildProvenance.ios',
      failures,
    );
    bool sameSummary(
      Map<String, Object?>? retainedSummary,
      Map<String, Object?>? artifactSummary,
    ) {
      if (retainedSummary == null || artifactSummary == null) return false;
      return retainedSummary['profileId'] == artifactSummary['profileId'] &&
          retainedSummary['inputDigest'] == artifactSummary['inputDigest'] &&
          retainedSummary['artifactDigest'] ==
              artifactSummary['artifactDigest'] &&
          retainedSummary['attestationAdjacent'] == true;
    }

    final manifestRaw = retained['iosBundleManifest'];
    final manifestDigest = manifestRaw == null
        ? null
        : sha256.convert(utf8.encode(manifestRaw)).toString();
    if (provenance['schema'] != 'mknoon.plan397.central-build-provenance.v1' ||
        !sameSummary(provenanceAndroid, centralAndroid) ||
        !sameSummary(provenanceIos, centralIos) ||
        provenance['iosBundleManifestSha256'] != manifestDigest ||
        provenance['androidChildBuildCount'] != 0 ||
        provenance['iosNormalChildBuildCount'] != 0 ||
        DateTime.tryParse('${provenance['recordedAt']}') == null) {
      failures.add(
        r'$.capture.centralBuildProvenance is not retained-source bound',
      );
    }
  }

  if (manifest != null &&
      (manifest['schema'] != 'mknoon.sims.ios-device-production-bundle.v1' ||
          manifest['profileId'] != 'ios.device.production' ||
          manifest['centralCompileCommands'] != 1 ||
          manifest['logicalBuildCount'] != 1 ||
          manifest['childBuildCount'] != 0 ||
          manifest['applicationApp'] is! String ||
          manifest['xctestrun'] is! String ||
          manifest['testProducts'] is! String)) {
    failures.add(r'$.capture.iosBundleManifest is not the central bundle');
  }
}

_Plan397WindowEvidence? _validatePlan397Window({
  required Map<String, Object?> window,
  required int index,
  required String phase,
  required String payloadKind,
  required String expectedMetricFamily,
  required Map<String, Object?>? identities,
  required String? expectedRecipientDeviceId,
  required List<String> failures,
}) {
  final path = '\$.windows[$index]';
  _expectExactKeys(
    window,
    const <String>{
      'phase',
      'ordinal',
      'payloadKind',
      'windowIdSha256',
      'observerRunIdSha256',
      'observerNonceSha256',
      'androidObservation',
      'provider',
      'nse',
      'nativeInventory',
      'tap',
      'diagnostics',
      'relayJournalSha256',
      'relayJournalLineCount',
      'openedAt',
      'closedAt',
    },
    path,
    failures,
  );
  _expectValue(window, 'phase', phase, path, failures);
  _expectValue(window, 'ordinal', index + 1, path, failures);
  _expectValue(window, 'payloadKind', payloadKind, path, failures);
  for (final key in const <String>[
    'windowIdSha256',
    'observerRunIdSha256',
    'observerNonceSha256',
    'relayJournalSha256',
  ]) {
    if (!_isSha256(window[key])) failures.add('$path.$key must be SHA-256');
  }
  final opened = DateTime.tryParse('${window['openedAt']}');
  final closed = DateTime.tryParse('${window['closedAt']}');
  if (opened == null || closed == null || closed.isBefore(opened)) {
    failures.add('$path must contain an ordered UTC observation interval');
  }
  if (window['relayJournalLineCount'] is! int ||
      (window['relayJournalLineCount']! as int) < 1) {
    failures.add('$path.relayJournalLineCount must be positive');
  }

  final android = _mapField(window, 'androidObservation', path, failures);
  final provider = _mapField(window, 'provider', path, failures);
  final nse = _mapField(window, 'nse', path, failures);
  final native = _mapField(window, 'nativeInventory', path, failures);
  final tap = _mapField(window, 'tap', path, failures);
  final diagnostics = _mapField(window, 'diagnostics', path, failures);
  if (android == null || provider == null || nse == null || native == null) {
    return null;
  }

  _expectExactKeys(
    android,
    const <String>{
      'schema',
      'phase',
      'groupIdSha256',
      'messageIdSha256',
      'targetMessageIdSha256',
      'eventIdSha256',
      'reactionIdSha256',
      'reactionTargetIdSha256',
      'firstIncoming',
      'targetIncoming',
      'targetRead',
      'reactionRows',
      'reactionEmojiSha256',
      'rawIdentifiersPersisted',
    },
    '$path.androidObservation',
    failures,
  );
  _expectValue(
    android,
    'schema',
    'mknoon.plan257.sqlcipher-observation.v1',
    '$path.androidObservation',
    failures,
  );
  _expectValue(android, 'phase', phase, '$path.androidObservation', failures);
  for (final key in const <String>[
    'groupIdSha256',
    'messageIdSha256',
    'targetMessageIdSha256',
    'eventIdSha256',
  ]) {
    if (!_isSha256(android[key])) {
      failures.add('$path.androidObservation.$key must be SHA-256');
    }
  }
  for (final entry in const <String, Object?>{
    'firstIncoming': false,
    'targetIncoming': true,
    'targetRead': true,
    'rawIdentifiersPersisted': false,
  }.entries) {
    _expectValue(
      android,
      entry.key,
      entry.value,
      '$path.androidObservation',
      failures,
    );
  }
  if (phase == 'message') {
    _expectValue(
      android,
      'reactionIdSha256',
      null,
      '$path.androidObservation',
      failures,
    );
    _expectValue(
      android,
      'reactionTargetIdSha256',
      null,
      '$path.androidObservation',
      failures,
    );
    _expectValue(
      android,
      'reactionEmojiSha256',
      null,
      '$path.androidObservation',
      failures,
    );
    _expectValue(
      android,
      'reactionRows',
      0,
      '$path.androidObservation',
      failures,
    );
    if (android['eventIdSha256'] != android['messageIdSha256']) {
      failures.add('$path message event must bind its Android message digest');
    }
  } else {
    for (final key in const <String>[
      'reactionIdSha256',
      'reactionTargetIdSha256',
      'reactionEmojiSha256',
    ]) {
      if (!_isSha256(android[key])) {
        failures.add('$path.androidObservation.$key must be SHA-256');
      }
    }
    _expectValue(
      android,
      'reactionRows',
      1,
      '$path.androidObservation',
      failures,
    );
    if (android['eventIdSha256'] != android['reactionIdSha256'] ||
        android['reactionTargetIdSha256'] != android['targetMessageIdSha256']) {
      failures.add(
        '$path reaction does not bind its Android ADD/target digests',
      );
    }
  }

  _expectExactKeys(
    provider,
    const <String>{
      'metricFamily',
      'attemptedDelta',
      'pushSuccessDelta',
      'baseline',
      'final',
      'baselineSha256',
      'finalSha256',
      'relayAttributed',
      'providerResultCount',
      'deletedOrUnattributedEvidence',
    },
    '$path.provider',
    failures,
  );
  _expectValue(
    provider,
    'metricFamily',
    expectedMetricFamily,
    '$path.provider',
    failures,
  );
  final baseline = provider['baseline'];
  final finalScrape = provider['final'];
  final messageProvider = phase == 'message';
  if (baseline is! String || finalScrape is! String) {
    failures.add('$path.provider metric scrapes must be strings');
  } else {
    final metrics = parseRelayMetricsWindow(
      '$relayMetricsPhaseMarker$relayMetricsBaselinePhase\n$baseline'
      '$relayMetricsPhaseMarker$relayMetricsFinalPhase\n$finalScrape',
    );
    final attempted = messageProvider
        ? null
        : metrics?.delta(
            relayCounterSeries(expectedMetricFamily, const <String, String>{
              'outcome': 'attempted',
            }),
          );
    final push = metrics == null
        ? null
        : relayCounterFamilyDelta(metrics, relayPushSentCounter);
    if (messageProvider) {
      if (push == null || push < 1) {
        failures.add(
          '$path.provider does not re-derive the shared provider-result floor',
        );
      }
    } else if (attempted != 1 || push != 1) {
      failures.add('$path.provider does not re-derive one attributed send');
    }
    final recordedPush = provider['pushSuccessDelta'];
    if (push != null &&
        (recordedPush is! num || recordedPush.toDouble() != push)) {
      failures.add('$path.provider.pushSuccessDelta is not scrape-derived');
    }
    if (sha256.convert(utf8.encode(baseline)).toString() !=
            provider['baselineSha256'] ||
        sha256.convert(utf8.encode(finalScrape)).toString() !=
            provider['finalSha256'] ||
        baseline == finalScrape) {
      failures.add('$path.provider metric digests are stale or unbound');
    }
  }
  final exactProviderValues = messageProvider
      ? const <String, Object?>{
          'attemptedDelta': null,
          'relayAttributed': false,
          'providerResultCount': null,
          'deletedOrUnattributedEvidence': false,
        }
      : const <String, Object?>{
          'attemptedDelta': 1,
          'pushSuccessDelta': 1,
          'relayAttributed': true,
          'providerResultCount': 1,
          'deletedOrUnattributedEvidence': false,
        };
  for (final entry in exactProviderValues.entries) {
    final actual = provider[entry.key];
    final equal = actual is num && entry.value is num
        ? actual.toDouble() == (entry.value! as num).toDouble()
        : actual == entry.value;
    if (!equal) {
      failures.add('$path.provider.${entry.key} must equal ${entry.value}');
    }
  }
  if (messageProvider &&
      (provider['pushSuccessDelta'] is! num ||
          (provider['pushSuccessDelta']! as num) < 1)) {
    failures.add(
      '$path.provider.pushSuccessDelta must satisfy the shared floor',
    );
  }
  if (!_isSha256(provider['baselineSha256']) ||
      !_isSha256(provider['finalSha256'])) {
    failures.add('$path.provider metric hashes must be SHA-256');
  }

  _expectExactKeys(
    nse,
    const <String>{
      'payloadKind',
      'decryptOkCount',
      'didReceiveCount',
      'decryptFailureCount',
      'timeoutCount',
      'runOwnedLocalPublicationCount',
      'contenderDisposition',
      'contenderSuppressionCount',
      'windowSha256',
      'rawPayloadPersisted',
    },
    '$path.nse',
    failures,
  );
  for (final entry in <String, Object?>{
    'payloadKind': payloadKind,
    'decryptOkCount': 1,
    'didReceiveCount': 1,
    'decryptFailureCount': 0,
    'timeoutCount': 0,
    'runOwnedLocalPublicationCount': 0,
    'rawPayloadPersisted': false,
  }.entries) {
    _expectValue(nse, entry.key, entry.value, '$path.nse', failures);
  }
  if (!_isSha256(nse['windowSha256'])) {
    failures.add('$path.nse.windowSha256 must be SHA-256');
  }
  final contenderDisposition = nse['contenderDisposition'];
  final contenderSuppressionCount = nse['contenderSuppressionCount'];
  if (!<String>{
        'not_observed',
        'suppressed_recent_remote',
      }.contains(contenderDisposition) ||
      contenderSuppressionCount !=
          (contenderDisposition == 'suppressed_recent_remote' ? 1 : 0)) {
    failures.add('$path.nse contender disposition is incomplete');
  }

  _validatePlan397NativeInventory(
    native: native,
    path: '$path.nativeInventory',
    phase: phase,
    android: android,
    observerNonceSha256: window['observerNonceSha256'],
    expectedRecipientDeviceId: expectedRecipientDeviceId,
    failures: failures,
  );

  if (tap != null) {
    _expectExactKeys(
      tap,
      const <String>{
        'selector',
        'passed',
        'sameCardContainer',
        'matchingCardCount',
        'titleMatched',
        'bodyMatched',
        'routeMatched',
        'finalUnreadCount',
        'manualTaps',
        'coldLaunch',
        'expectedTitleSha256',
        'expectedBodySha256',
        'expectedRouteTextSha256',
      },
      '$path.tap',
      failures,
    );
    for (final entry in const <String, Object?>{
      'selector': 'testChatGroupNotificationTap',
      'passed': true,
      'sameCardContainer': true,
      'matchingCardCount': 1,
      'titleMatched': true,
      'bodyMatched': true,
      'routeMatched': true,
      'finalUnreadCount': 0,
      'manualTaps': 0,
      'coldLaunch': true,
    }.entries) {
      _expectValue(tap, entry.key, entry.value, '$path.tap', failures);
    }
    for (final key in const <String>[
      'expectedTitleSha256',
      'expectedBodySha256',
      'expectedRouteTextSha256',
    ]) {
      if (!_isSha256(tap[key])) failures.add('$path.tap.$key must be SHA-256');
    }
    if (identities != null &&
        (tap['expectedTitleSha256'] != identities['groupNameSha256'] ||
            tap['expectedRouteTextSha256'] !=
                identities[phase == 'message'
                    ? 'messageTextSha256'
                    : 'targetTextSha256'])) {
      failures.add('$path.tap title/route digests are not artifact-bound');
    }
  }

  if (diagnostics != null) {
    _expectExactKeys(
      diagnostics,
      const <String>{
        'runOwnedLocalPublicationCount',
        'contenderDisposition',
        'contenderSuppressionCount',
        'rawIdentifiersPersisted',
        'rawPayloadPersisted',
      },
      '$path.diagnostics',
      failures,
    );
    for (final entry in const <String, Object?>{
      'runOwnedLocalPublicationCount': 0,
      'rawIdentifiersPersisted': false,
      'rawPayloadPersisted': false,
    }.entries) {
      _expectValue(
        diagnostics,
        entry.key,
        entry.value,
        '$path.diagnostics',
        failures,
      );
    }
    if (diagnostics['contenderDisposition'] != contenderDisposition ||
        diagnostics['contenderSuppressionCount'] != contenderSuppressionCount) {
      failures.add('$path.diagnostics contender disposition is not NSE-bound');
    }
  }

  return _Plan397WindowEvidence(
    window: window,
    android: android,
    provider: provider,
    nse: nse,
    native: native,
  );
}

void _validatePlan397NativeInventory({
  required Map<String, Object?> native,
  required String path,
  required String phase,
  required Map<String, Object?> android,
  required Object? observerNonceSha256,
  required String? expectedRecipientDeviceId,
  required List<String> failures,
}) {
  _expectExactKeys(
    native,
    const <String>{
      'schema',
      'action',
      'phase',
      'status',
      'containsSecrets',
      'bundleId',
      'captureNonceSha256',
      'receiverDeviceIdSha256',
      'expectedGroupIdSha256',
      'expectedEventIdSha256',
      'expectedTargetMessageIdSha256',
      'matchingRemoteCount',
      'matchingLocalCount',
      'matchingUsefulProviderCount',
      'matchingSanitizedProviderCount',
      'matchingFlutterLocalCount',
      'matchingUnknownCount',
      'matchingTotalCount',
      'stableSampleCount',
      'stableSampleIntervalMilliseconds',
      'observationDeadlineMilliseconds',
      'sampledThroughDeadline',
      'badSourceSeen',
      'duplicateSeen',
      'requestIdentifierSha256',
      'childBuildCount',
      'manualActionCount',
      'runnerTerminated',
      'preTapCleanupLaunchCount',
      'resultCode',
      'completedAt',
    },
    path,
    failures,
  );
  for (final entry in <String, Object?>{
    'schema': 'mknoon.sims.ios-group-notification-observation-host-receipt.v1',
    'action': 'observe-group',
    'phase': phase,
    'status': 'PASS',
    'containsSecrets': false,
    'bundleId': 'com.mknoon.app',
    'matchingRemoteCount': 1,
    'matchingLocalCount': 0,
    'matchingUsefulProviderCount': 1,
    'matchingSanitizedProviderCount': 0,
    'matchingFlutterLocalCount': 0,
    'matchingUnknownCount': 0,
    'matchingTotalCount': 1,
    'stableSampleCount': 3,
    'stableSampleIntervalMilliseconds': 500,
    'observationDeadlineMilliseconds': 8000,
    'sampledThroughDeadline': true,
    'badSourceSeen': false,
    'duplicateSeen': false,
    'childBuildCount': 0,
    'manualActionCount': 0,
    'runnerTerminated': true,
    'preTapCleanupLaunchCount': 0,
    'resultCode': 'ok',
  }.entries) {
    _expectValue(native, entry.key, entry.value, path, failures);
  }
  final digestBindings = <String, Object?>{
    'captureNonceSha256': observerNonceSha256,
    'expectedGroupIdSha256': android['groupIdSha256'],
    'expectedEventIdSha256': android['eventIdSha256'],
    'expectedTargetMessageIdSha256': android['targetMessageIdSha256'],
  };
  if (expectedRecipientDeviceId != null) {
    digestBindings['receiverDeviceIdSha256'] = sha256
        .convert(utf8.encode(expectedRecipientDeviceId))
        .toString();
  }
  for (final entry in digestBindings.entries) {
    if (!_isSha256(native[entry.key]) || native[entry.key] != entry.value) {
      failures.add('$path.${entry.key} is not bound to the phase authority');
    }
  }
  for (final key in const <String>[
    'captureNonceSha256',
    'receiverDeviceIdSha256',
    'expectedGroupIdSha256',
    'expectedEventIdSha256',
    'expectedTargetMessageIdSha256',
  ]) {
    if (!_isSha256(native[key])) failures.add('$path.$key must be SHA-256');
  }
  final identifiers = native['requestIdentifierSha256'];
  if (identifiers is! List ||
      identifiers.length != 1 ||
      !_isSha256(identifiers.single)) {
    failures.add('$path.requestIdentifierSha256 must contain one hashed id');
  }
  if (DateTime.tryParse('${native['completedAt']}') == null) {
    failures.add('$path.completedAt must be an ISO-8601 timestamp');
  }
}

Future<String?> _readReferencedText(
  Object? rawReference, {
  required File artifactFile,
  required String path,
  required List<String> failures,
}) async {
  final reference = _asStringMap(rawReference, path, failures);
  if (reference == null) return null;
  _expectExactKeys(
    reference,
    const <String>{'path', 'sha256', 'bytes'},
    path,
    failures,
  );
  final relativePath = _requiredString(reference, 'path', path, failures);
  final expectedSha = _requiredString(reference, 'sha256', path, failures);
  final expectedBytes = reference['bytes'];
  if (relativePath == null) return null;
  final segments = relativePath.split(RegExp(r'[/\\]'));
  if (File(relativePath).isAbsolute || segments.contains('..')) {
    failures.add('$path.path must stay inside the artifact directory');
    return null;
  }
  final file = File(
    '${artifactFile.parent.path}${Platform.pathSeparator}$relativePath',
  );
  if (!await file.exists()) {
    failures.add('$path.path is missing');
    return null;
  }
  final artifactDirectory = await artifactFile.parent.resolveSymbolicLinks();
  final resolved = await file.resolveSymbolicLinks();
  if (!resolved.startsWith('$artifactDirectory${Platform.pathSeparator}')) {
    failures.add('$path.path must stay inside the artifact directory');
    return null;
  }
  final bytes = await file.readAsBytes();
  if (expectedBytes is! int ||
      expectedBytes <= 0 ||
      bytes.length != expectedBytes) {
    failures.add('$path.bytes does not match a positive evidence length');
  }
  if (!_isSha256(expectedSha) ||
      sha256.convert(bytes).toString() != expectedSha) {
    failures.add('$path SHA-256 mismatch');
  }
  try {
    final text = utf8.decode(bytes);
    _scanForbidden(text, path, failures);
    return text;
  } on Object {
    failures.add('$path is not UTF-8 evidence');
    return null;
  }
}

Map<String, Object?>? _decodeObject(
  String raw,
  String path,
  List<String> failures,
) {
  try {
    final value = jsonDecode(raw);
    return _asStringMap(value, path, failures);
  } on Object {
    failures.add('$path is not valid JSON');
    return null;
  }
}

bool _isSha256(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

bool _isNullableSha256(Object? value) => value == null || _isSha256(value);

void _validateAuthoritativeEvidence({
  required GroupReactionNotificationScenario requirement,
  required Map<String, Object?>? measurements,
  required Map<String, String> evidenceTexts,
  required List<String> failures,
}) {
  if (measurements == null) return;
  if (requirement.recipientPlatform == 'ios') {
    _validateIosAuthoritativeEvidence(
      requirement: requirement,
      measurements: measurements,
      evidenceTexts: evidenceTexts,
      failures: failures,
    );
    return;
  }
  final groupName = measurements['groupName'] as String? ?? '';
  final actorName = measurements['actorName'] as String? ?? '';
  final appPackage = measurements['appPackage'] as String? ?? '';
  final expectedRelayWakeAttempts =
      measurements['expectedRelayWakeAttempts'] as int? ?? -1;
  final relay = evidenceTexts['relay'] ?? '';
  final provider = evidenceTexts['provider_fcm'] ?? '';
  final senderApp = evidenceTexts['sender_app'] ?? '';
  final recipientApp = evidenceTexts['recipient_app'] ?? '';
  final androidLogcat = evidenceTexts['android_logcat'] ?? '';
  final sqlCipher = evidenceTexts['sqlcipher_state'] ?? '';
  final notificationRecords =
      evidenceTexts['android_notification_records'] ?? '';
  final uiAutomation = evidenceTexts['ui_automation'] ?? '';

  final rawRelayLines = relay
      .split('\n')
      .where(
        (line) =>
            line.contains('[GROUP_INBOX]') ||
            line.contains('[PUSH]') ||
            line.contains('[GROUP_REACTION_WAKE]'),
      )
      .toList(growable: false);
  if (rawRelayLines.isEmpty ||
      rawRelayLines.any(
        (line) => !RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(line),
      ) ||
      !rawRelayLines.any(
        (line) => line.contains('[GROUP_INBOX] Stored message for group'),
      )) {
    failures.add(r'$.evidence[relay] is not raw timestamped relay custody');
  }
  final messageScenario = requirement.id.endsWith('_message_unread_lifecycle');
  final processAliveReaction = _processAliveReactionScenarioIds.contains(
    requirement.id,
  );
  // TC-386-03. Relay v1.8.0 emits `[GROUP_REACTION_WAKE] outcome=<word>` and
  // nothing else: the `remote_type=` attribute this used to require was deleted
  // with the rest of the attributed `[PUSH]`/wake vocabulary by `8d86501e4`, so
  // the old conjunct rejected every real journal. `outcome=dispatched` is the
  // line the relay prints once per recipient it actually hands to the provider
  // (`go-relay-server/inbox.go:2797`), which is the same discrimination the old
  // attribute carried. The recipient-side push-origin marker is unchanged and
  // still required, so this stays a three-way discrimination.
  if (processAliveReaction &&
      (!rawRelayLines.any(
            (line) =>
                line.contains('[GROUP_REACTION_WAKE]') &&
                line.contains('outcome=dispatched'),
          ) ||
          !provider.contains('event=group_reaction') ||
          !provider.contains('delivery_matched=true') ||
          !androidLogcat.contains(
            'PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK',
          ))) {
    failures.add(
      r'$.evidence background-connected reaction lacks relay/provider/logcat '
      'push-origin discrimination',
    );
  }

  // TC-386-01/04. Qualitative half: the relay journal must record a real
  // provider acceptance in the capture window. The predicate is Plan 380 W0's,
  // imported rather than re-derived, so exactly one definition of the v1.8.0
  // acceptance grammar exists in the repository.
  if (!relayJournalContainsAndroidProviderSend(provider)) {
    failures.add(
      r'$.evidence[provider_fcm] records no v1.8.0 provider acceptance',
    );
  }

  // TC-386-02. Quantitative half: an exact RELAY COUNTER DELTA, per lane.
  //
  // Counting journal lines cannot work on v1.8.0. What survives is
  // `[PUSH] outcome=success attempt=N total_attempts=N`, which carries no
  // attribution at all and is emitted by the single shared provider path for
  // every push type and every user on a PRODUCTION box. The relay's own
  // Prometheus counters are reaction-scoped, already exported on
  // `:2112/metrics` (`go-relay-server/main.go:261-266`), and already scraped
  // over ssh by five `docker-ws/` scripts, so grading on their growth across
  // the capture window is both sound and existing repo practice.
  final metrics = parseRelayMetricsWindow(evidenceTexts['relay_metrics'] ?? '');
  if (metrics == null) {
    failures.add(
      r'$.evidence[relay_metrics] is not an ordered baseline/final pair of raw '
      'relay counter scrapes',
    );
  } else if (metrics.isProcessContinuous != true) {
    // Both phases must come from the SAME relay process. The sentinel is a
    // plain counter, exported from registration and monotonic within a process,
    // so a missing or regressed one means the file is truncated or the relay
    // restarted mid-capture — either way no delta below means anything.
    failures.add(
      r'$.evidence[relay_metrics] does not span one continuous relay process',
    );
  } else if (messageScenario) {
    // The message lane has NO wake counter and no per-recipient journal line of
    // any kind: `fanOutPush` contains zero `log.Printf`. Its relay-side
    // observables are `[GROUP_INBOX] Stored message for group` (asserted above,
    // and the window-liveness oracle) plus growth of the shared provider
    // counter. A floor is the strongest honest rule here — the counter is not
    // group-scoped.
    final pushDelta = relayCounterFamilyDelta(metrics, relayPushSentCounter);
    if (pushDelta == null || pushDelta < 1) {
      failures.add(
        r'$.evidence[relay_metrics] shows no provider attempt across the '
        'group-message capture window',
      );
    }
  } else {
    final attempted = metrics.delta(
      relayCounterSeries(relayGroupReactionWakeCounter, const <String, String>{
        'outcome': 'attempted',
      }),
    );
    final routeError = metrics.delta(
      relayCounterSeries(relayGroupReactionWakeCounter, const <String, String>{
        'outcome': 'route_error',
      }),
    );
    final incapableSkipped = metrics.delta(
      relayCounterSeries(relayGroupReactionWakeCounter, const <String, String>{
        'outcome': 'incapable_skipped',
      }),
    );
    if (attempted == null || attempted != expectedRelayWakeAttempts) {
      failures.add(
        r'$.evidence[relay_metrics] wake attempts across the capture window '
        'are not exactly the expected count',
      );
    }
    // A recipient the relay silently declined is the failure mode a bare
    // "at least one dispatch" rule cannot see: `route_error` emits NO journal
    // line at all, and `incapable_skipped` means the recipient advertised no
    // usable route. Both must be zero for the count above to mean what it says.
    if (routeError == null || routeError != 0) {
      failures.add(
        r'$.evidence[relay_metrics] records a wake route error in the capture '
        'window',
      );
    }
    if (incapableSkipped == null || incapableSkipped != 0) {
      failures.add(
        r'$.evidence[relay_metrics] records an incapable-skipped wake in the '
        'capture window',
      );
    }
  }

  final senderEvents = _flowEventNames(senderApp);
  if (messageScenario) {
    if (senderEvents
            .where(
              (event) => event.startsWith('GROUP_SEND_MSG_USE_CASE_SUCCESS'),
            )
            .length <
        2) {
      failures.add(
        r'$.evidence[sender_app] lacks two raw group-message send commits',
      );
    }
  } else {
    if (senderEvents
                .where((event) => event == 'GROUP_REACTION_SEND_QUEUED')
                .length !=
            2 ||
        senderEvents
                .where((event) => event == 'GROUP_REACTION_REMOVE_QUEUED')
                .length !=
            1) {
      failures.add(
        r'$.evidence[sender_app] must contain raw ADD/REMOVE/ADD transitions',
      );
    }
    if (!recipientApp.contains('PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK') ||
        !recipientApp.contains('PUSH_ANDROID_DATA_DECRYPT_OK')) {
      failures.add(
        processAliveReaction
            ? r'$.evidence[recipient_app] lacks raw background-connected '
                  'crypto/parity success'
            : r'$.evidence[recipient_app] lacks raw killed-process '
                  'crypto/parity success',
      );
    }
    if (processAliveReaction) {
      _validateBackgroundConnectedObservation(
        recipientApp,
        scenario: requirement.id,
        failures: failures,
      );
    } else {
      // Plan 389 / G11. The graded reaction must not ride the FIRST wake after
      // the kill. That one spawns the background isolate cold, and its first
      // touch — ART profile install, the `libgojni` dlopen, the first encrypted
      // -store open — outruns the 2 s `display_eligibility` phase budget, so no
      // card is posted and the lane grades nothing. The lane absorbs that cost
      // with a throwaway warm-up text, which makes THREE post-kill wakes the
      // floor: warm-up, reaction ADD, reaction re-ADD. Two is exactly what the
      // lane emitted before the warm-up existed, so a ported `>= 2` rule would
      // pass with no warm-up at all.
      //
      // No cursor is needed to make these post-kill. The capture clears the
      // recipient's log at the kill, and `recipient_app` IS that accumulator's
      // text, so every occurrence in this evidence is after the kill by
      // construction.
      //
      // Cardinal, not identity-bound: the reaction push's flow event carries
      // `details: {'kind': 'group_reaction'}` and NO message id, so nothing in
      // `recipient_app` can bind a particular wake to the graded reaction. The
      // same-pid assertion that proves the resident-isolate mechanism rather
      // than luck lives at device tier.
      final postKillWakes = _flowEventNames(
        recipientApp,
      ).where((event) => event == 'PUSH_BACKGROUND_MESSAGE_RECEIVED').length;
      if (postKillWakes < 3) {
        failures.add(
          r'$.evidence[recipient_app] records fewer than three post-kill '
          'background wakes, so the graded reaction rode a cold first wake',
        );
      }
    }
    _validateExactDuplicateRedrive(
      senderApp,
      scenario: requirement.id,
      failures: failures,
    );
  }

  _validateSqlCipherRaw(
    sqlCipher,
    requirement: requirement,
    measurements: measurements,
    failures: failures,
  );
  _validateNotificationRaw(
    notificationRecords,
    messageScenario: messageScenario,
    groupName: groupName,
    actorName: actorName,
    appPackage: appPackage,
    failures: failures,
  );
  _validateUiRaw(
    uiAutomation,
    messageScenario: messageScenario,
    groupName: groupName,
    firstMarker: measurements['firstMarker'] as String? ?? '',
    secondMarker: measurements['secondMarker'] as String? ?? '',
    targetMarker: measurements['targetMarker'] as String? ?? '',
    failures: failures,
  );
}

void _validateBackgroundConnectedObservation(
  String text, {
  required String scenario,
  required List<String> failures,
}) {
  final lines = text
      .split('\n')
      .where(
        (line) =>
            line.startsWith(groupReactionBackgroundConnectedObservationPrefix),
      )
      .toList(growable: false);
  if (lines.length != 1) {
    failures.add(
      r'$.evidence[recipient_app] must contain one background-connected '
      'timing observation',
    );
    return;
  }
  final observed = _decodeObject(
    lines.single.substring(
      groupReactionBackgroundConnectedObservationPrefix.length,
    ),
    r'$.evidence[recipient_app].backgroundConnectedObservation',
    failures,
  );
  if (observed == null) return;
  _expectExactKeys(
    observed,
    const <String>{
      'schema',
      'scenario',
      'pidPresentBeforeDelivery',
      'connectivityEvent',
      'connectivityState',
      'connectivityOk',
      'homeAt',
      'reactionAt',
      'notificationAt',
      'minimumHomeToReactDelayMs',
      'homeToReactDelayMs',
      'notificationObservationWindowMs',
      'reactionToNotificationMs',
    },
    r'$.evidence[recipient_app].backgroundConnectedObservation',
    failures,
  );
  final homeAt = DateTime.tryParse('${observed['homeAt']}')?.toUtc();
  final reactionAt = DateTime.tryParse('${observed['reactionAt']}')?.toUtc();
  final notificationAt = DateTime.tryParse(
    '${observed['notificationAt']}',
  )?.toUtc();
  final homeToReaction = observed['homeToReactDelayMs'];
  final reactionToNotification = observed['reactionToNotificationMs'];
  final timestampsOrdered =
      homeAt != null &&
      reactionAt != null &&
      notificationAt != null &&
      !reactionAt.isBefore(homeAt) &&
      !notificationAt.isBefore(reactionAt);
  final derivedHomeToReaction = timestampsOrdered
      ? reactionAt.difference(homeAt).inMilliseconds
      : -1;
  final derivedReactionToNotification = timestampsOrdered
      ? notificationAt.difference(reactionAt).inMilliseconds
      : -1;
  bool closeToDerived(Object? value, int derived) =>
      value is int && (value - derived).abs() <= 1500;
  if (observed['schema'] !=
          'mknoon.plan315.background-connected-observation.v1' ||
      observed['scenario'] != scenario ||
      observed['pidPresentBeforeDelivery'] != true ||
      observed['connectivityEvent'] != 'P2P_RELAY_PRESENCE_SET_RESPONSE' ||
      observed['connectivityState'] != 'background' ||
      observed['connectivityOk'] != true ||
      observed['minimumHomeToReactDelayMs'] !=
          groupReactionBackgroundConnectedHomeToReactDelayMs ||
      observed['notificationObservationWindowMs'] !=
          groupReactionBackgroundConnectedObservationWindowMs ||
      homeToReaction is! int ||
      homeToReaction < groupReactionBackgroundConnectedHomeToReactDelayMs ||
      homeToReaction >
          groupReactionBackgroundConnectedHomeToReactDelayMs +
              groupReactionBackgroundConnectedHomeToReactAutomationWindowMs ||
      reactionToNotification is! int ||
      reactionToNotification < 0 ||
      reactionToNotification >
          groupReactionBackgroundConnectedObservationWindowMs ||
      !timestampsOrdered ||
      !closeToDerived(homeToReaction, derivedHomeToReaction) ||
      !closeToDerived(reactionToNotification, derivedReactionToNotification)) {
    failures.add(
      r'$.evidence[recipient_app] background-connected process, connectivity, '
      'or timing proof mismatched',
    );
  }
}

void _validateExactDuplicateRedrive(
  String senderApp, {
  required String scenario,
  required List<String> failures,
}) {
  final records = senderApp
      .split('\n')
      .where((line) => line.startsWith(_plan257DuplicateRedrivePrefix))
      .toList(growable: false);
  if (records.length != 1) {
    failures.add(
      r'$.evidence[sender_app] must contain one exact stored-ADD redrive '
      'observation',
    );
    return;
  }
  final observation = _decodeObject(
    records.single.substring(_plan257DuplicateRedrivePrefix.length),
    r'$.evidence[sender_app].duplicateRedrive',
    failures,
  );
  if (observation == null) return;
  final identityHashes = <Object?>[
    observation['transitionIdSha256'],
    observation['reactionStateIdSha256'],
    observation['targetMessageIdSha256'],
  ];
  final exactRetryEvents = _flowEventObjects(senderApp)
      .where(
        (event) => event['event'] == 'RETRY_FAILED_GROUP_REACTION_REPLAY_OK',
      )
      .toList(growable: false);
  final retryDetails = exactRetryEvents.length == 1
      ? exactRetryEvents.single['details']
      : null;
  final retryReactionId = retryDetails is Map
      ? retryDetails['reactionId']
      : null;
  final retryPrefixMatches =
      retryReactionId is String &&
      retryReactionId.isNotEmpty &&
      retryReactionId.length <= 8 &&
      retryDetails is Map &&
      retryDetails['action'] == 'add' &&
      sha256.convert(utf8.encode(retryReactionId)).toString() ==
          observation['transitionIdPrefixSha256'];
  if (observation['schema'] !=
          'mknoon.plan257.duplicate-redrive-observation.v1' ||
      observation['scenario'] != scenario ||
      observation['prepared'] != true ||
      observation['notificationExtensionBound'] != true ||
      observation['signedEnvelopePresent'] != true ||
      observation['previousDeliveryStatus'] != 'stored' ||
      identityHashes.any((value) => !_isSha256(value)) ||
      identityHashes.toSet().length != 3 ||
      !_isSha256(observation['transitionIdPrefixSha256']) ||
      !_isSha256(observation['inboxRetryPayloadSha256']) ||
      exactRetryEvents.length != 1 ||
      !retryPrefixMatches) {
    failures.add(
      r'$.evidence[sender_app] does not prove one production redrive of the '
      'exact stored ADD with distinct transition/state/target identities',
    );
  }
}

void _validateIosAuthoritativeEvidence({
  required GroupReactionNotificationScenario requirement,
  required Map<String, Object?> measurements,
  required Map<String, String> evidenceTexts,
  required List<String> failures,
}) {
  final groupName = measurements['groupName'] as String? ?? '';
  final actorName = measurements['actorName'] as String? ?? '';
  final targetMarker = measurements['targetMarker'] as String? ?? '';
  final expectedRelayWakeAttempts =
      measurements['expectedRelayWakeAttempts'] as int? ?? -1;
  final relay = evidenceTexts['relay'] ?? '';
  final provider = evidenceTexts['provider_apns'] ?? '';
  final senderApp = evidenceTexts['sender_app'] ?? '';
  final recipientApp = evidenceTexts['recipient_app'] ?? '';
  final sqlCipher = evidenceTexts['sqlcipher_state'] ?? '';
  final nseLog = evidenceTexts['nse_log'] ?? '';
  final xcuiTest = evidenceTexts['xcuitest'] ?? '';

  final relayCustody = relay
      .split('\n')
      .where((line) => line.contains('[GROUP_INBOX]'))
      .toList(growable: false);
  if (relayCustody.isEmpty ||
      !relayCustody.any(
        (line) => line.contains('[GROUP_INBOX] Stored message for group'),
      ) ||
      relayCustody.any(
        (line) => !RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(line),
      )) {
    failures.add(r'$.evidence[relay] is not raw timestamped relay custody');
  }

  final providerLines = provider
      .split('\n')
      .where((line) => line.contains('[PUSH] Notification sent to'))
      .toList(growable: false);
  if (providerLines.length != expectedRelayWakeAttempts ||
      providerLines.any(
        (line) => !RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(line),
      )) {
    failures.add(
      r'$.evidence[provider_apns] must contain exactly two raw timestamped '
      'provider accepts after quiescence',
    );
  }

  final senderEvents = _flowEventNames(senderApp);
  if (senderEvents
              .where((event) => event == 'GROUP_REACTION_SEND_QUEUED')
              .length !=
          2 ||
      senderEvents
              .where((event) => event == 'GROUP_REACTION_REMOVE_QUEUED')
              .length !=
          1) {
    failures.add(
      r'$.evidence[sender_app] must contain raw ADD/REMOVE/ADD transitions',
    );
  }

  if (!recipientApp.contains('ios_notification_open_stored_pending') ||
      !recipientApp.contains('IOS_APNS_INITIAL_NOTIFICATION_OPENED') ||
      recipientApp.contains('IOS_APNS_NOTIFICATION_OPEN_ERROR') ||
      recipientApp.contains('NOTIFICATION_TAP_NAV_ERROR') ||
      recipientApp.contains('INITIAL_LOCAL_NOTIFICATION_ROUTE_ERROR')) {
    failures.add(
      r'$.evidence[recipient_app] lacks a raw error-free cold notification '
      'open',
    );
  }

  _validateSqlCipherRaw(
    sqlCipher,
    requirement: requirement,
    measurements: measurements,
    failures: failures,
  );

  final nseEvents = _flowEventNames(nseLog);
  if (nseEvents.where((event) => event == 'PUSH_NSE_DECRYPT_OK').length !=
          expectedRelayWakeAttempts ||
      nseEvents.any(
        (event) =>
            event == 'PUSH_NSE_DECRYPT_FAIL' || event == 'PUSH_NSE_TIMEOUT',
      ) ||
      !nseLog.contains('"kind":"group_reaction"')) {
    failures.add(
      r'$.evidence[nse_log] lacks two raw successful group-reaction NSE '
      'resolutions or contains a failure',
    );
  }

  const observationPrefix = 'MKNOON_257_IOS_NOTIFICATION_OBSERVATION ';
  final observations = xcuiTest
      .split('\n')
      .where((line) => line.contains(observationPrefix))
      .toList(growable: false);
  Map<String, Object?>? observation;
  if (observations.length == 1) {
    final encoded = observations.single.substring(
      observations.single.indexOf(observationPrefix) + observationPrefix.length,
    );
    observation = _decodeObject(
      encoded,
      r'$.evidence[xcuitest].notificationObservation',
      failures,
    );
  }
  final expectedBody = '$actorName reacted 👍 to your message';
  if (observation == null ||
      observation['schema'] !=
          'mknoon.plan257.ios-notification-observation.v1' ||
      observation['title'] != groupName ||
      observation['body'] != expectedBody ||
      observation['matchingCardCount'] != 1 ||
      observation['containsNewMessageCopy'] != false) {
    failures.add(
      r'$.evidence[xcuitest] lacks one raw matching Springboard reaction card',
    );
  }
  if (!xcuiTest.contains('testAnnouncementReactionNotificationTap') ||
      !xcuiTest.contains(
        "Test Case '-[RunnerUITests.NotificationTapUITests ",
      ) ||
      !xcuiTest.contains("testAnnouncementReactionNotificationTap]' passed") ||
      !xcuiTest.contains(
        'MKNOON_257_ANNOUNCEMENT_REACTION_TAP '
        'group_rendered=true target_message_visible=true manual_taps=0 '
        'cold_launch=true',
      ) ||
      !xcuiTest.contains(groupName) ||
      !xcuiTest.contains(targetMarker) ||
      xcuiTest.contains('Test Case') &&
          xcuiTest.contains(
            'testAnnouncementReactionNotificationTap] failed',
          )) {
    failures.add(
      r'$.evidence[xcuitest] lacks raw passed selector/card/tap/UI output',
    );
  }
  if (xcuiTest.toLowerCase().contains('new message')) {
    failures.add(r'$.evidence[xcuitest] exposed forbidden New Message copy');
  }
}

List<String> _flowEventNames(String text) {
  return _flowEventObjects(
    text,
  ).map((value) => value['event']).whereType<String>().toList(growable: false);
}

List<Map<String, Object?>> _flowEventObjects(String text) {
  final result = <Map<String, Object?>>[];
  for (final line in text.split('\n')) {
    final marker = line.indexOf('[FLOW]');
    if (marker < 0) continue;
    final jsonStart = line.indexOf('{', marker);
    if (jsonStart < 0) continue;
    try {
      final value = jsonDecode(line.substring(jsonStart));
      if (value is Map && value['event'] is String) {
        result.add(
          value.map<String, Object?>(
            (key, field) => MapEntry(key.toString(), field),
          ),
        );
      }
    } on Object {
      // A malformed raw line contributes no event and is rejected by counts.
    }
  }
  return result;
}

void _validateSqlCipherRaw(
  String text, {
  required GroupReactionNotificationScenario requirement,
  required Map<String, Object?> measurements,
  required List<String> failures,
}) {
  const prefix = 'MKNOON_257_SQLCIPHER_OBSERVATION ';
  final line = text
      .split('\n')
      .where((candidate) => candidate.startsWith(prefix))
      .toList(growable: false);
  if (line.length != 1) {
    failures.add(
      r'$.evidence[sqlcipher_state] must contain one raw observer record',
    );
    return;
  }
  final observed = _decodeObject(
    line.single.substring(prefix.length),
    r'$.evidence[sqlcipher_state]',
    failures,
  );
  if (observed == null) return;
  if (observed['schema'] != 'mknoon.plan257.sqlcipher-observation.v1' ||
      observed['scenario'] != requirement.id ||
      observed['groupName'] != measurements['groupName'] ||
      observed['groupRows'] != 1 ||
      observed['groupType'] != requirement.groupType ||
      observed['unreadCount'] != 0 ||
      observed['reactionMessageRows'] != 0 ||
      observed['markers'] is! List) {
    failures.add(
      r'$.evidence[sqlcipher_state] core SQLCipher observation mismatched',
    );
    return;
  }
  final markers = (observed['markers'] as List)
      .whereType<Map>()
      .map((entry) => Map<String, Object?>.from(entry))
      .toList(growable: false);
  if (requirement.id.endsWith('_message_unread_lifecycle')) {
    final first = markers.where((entry) => entry['marker'] == 'first');
    final second = markers.where((entry) => entry['marker'] == 'second');
    if (first.length != 1 ||
        second.length != 1 ||
        first.single['incoming'] != true ||
        second.single['incoming'] != true ||
        first.single['read'] != true ||
        second.single['read'] != true ||
        observed['reactionRows'] != 0) {
      failures.add(r'$.evidence[sqlcipher_state] message/read rows mismatched');
    }
  } else {
    final target = markers.where((entry) => entry['marker'] == 'target');
    if (target.length != 1 ||
        target.single['incoming'] != false ||
        observed['reactionRows'] != 1 ||
        observed['reactionEmoji'] != '👍' ||
        observed['reactionTargetIdSha256'] != target.single['idSha256']) {
      failures.add(
        r'$.evidence[sqlcipher_state] reaction/target rows mismatched',
      );
    }
  }
}

Map<String, String> _sourceBlocks(String text) {
  final result = <String, String>{};
  String? current;
  var buffer = StringBuffer();
  void commit() {
    final name = current;
    if (name != null) result[name] = buffer.toString();
  }

  for (final line in text.split('\n')) {
    if (line.startsWith('source_file=')) {
      commit();
      current = line.substring('source_file='.length).trim();
      buffer = StringBuffer();
      continue;
    }
    if (current != null) buffer.writeln(line);
  }
  commit();
  return result;
}

void _validateNotificationRaw(
  String text, {
  required bool messageScenario,
  required String groupName,
  required String actorName,
  required String appPackage,
  required List<String> failures,
}) {
  final blocks = _sourceBlocks(text);
  final required = messageScenario
      ? const <String>[
          'notification_message_first.log',
          'notification_message_second.log',
        ]
      : const <String>[
          'notification_reaction_first.log',
          'notification_reaction_replacement.log',
        ];
  // Plan 389. A killed-recipient reaction lane deliberately posts a card into a
  // SECOND, throwaway group: the first FCM wake after the kill opens SQLCipher
  // cold and outruns the 2 s `display_eligibility` budget, so a warm-up push has
  // to take that hit before the graded reaction arrives. That card is ADMITTED
  // BY NAME, never dismissed — anything outside {graded, warm-up} still reds.
  //
  // The selector below is not optional. `messageScenario` picks only the two
  // file names above; everything from here down is SHARED with the message
  // branch, so widening unconditionally would silently relax the two message
  // scenarios that already pass on device.
  final warmupGroupName = groupReactionNotificationWarmupGroupName(groupName);
  final cards = <({int id, String title, String body})>[];
  for (final name in required) {
    final block = blocks[name];
    if (block == null ||
        !block.contains('NotificationRecord(') ||
        !block.contains('pkg=$appPackage')) {
      failures.add(
        r'$.evidence[android_notification_records] lacks raw ' + name,
      );
      continue;
    }
    final contentCards = extractActiveContentNotificationCards(
      block,
      packageName: appPackage,
    );
    final ActiveNotificationCard card;
    if (messageScenario) {
      if (contentCards.length != 1) {
        failures.add(
          r'$.evidence[android_notification_records] has malformed raw card',
        );
        continue;
      }
      card = contentCards.single;
    } else {
      final unexpected = contentCards
          .where(
            (candidate) =>
                candidate.title != groupName &&
                candidate.title != warmupGroupName,
          )
          .toList(growable: false);
      if (unexpected.isNotEmpty) {
        // The allow-list is CLOSED. Without this arm the widening would also
        // stop seeing a duplicate card in an unrelated conversation, a leaked
        // card, and a card posted by a path the lane never exercises.
        failures.add(
          r'$.evidence[android_notification_records] holds a card outside the '
          'graded and warm-up groups',
        );
        continue;
      }
      final gradedCards = contentCards
          .where((candidate) => candidate.title == groupName)
          .toList(growable: false);
      // Exactly one graded card per BLOCK, not "at least one across the
      // accumulated list". The replacement-identity check below is guarded by
      // `cards.length == 2`; an accumulated-list shape can leave it at 1, so an
      // artifact proving the lane posted one card and never replaced it would
      // validate.
      if (gradedCards.length != 1) {
        failures.add(
          r'$.evidence[android_notification_records] does not hold exactly one '
          'graded group card',
        );
        continue;
      }
      card = gradedCards.single;
    }
    final id = card.id;
    if (id == null || id < 0 || card.title.isEmpty || card.body.isEmpty) {
      failures.add(
        r'$.evidence[android_notification_records] has malformed raw card',
      );
      continue;
    }
    cards.add((id: id, title: card.title, body: card.body));
  }
  if (cards.length == 2 && cards[0].id != cards[1].id) {
    failures.add(
      r'$.evidence[android_notification_records] did not replace one stable '
      'group card',
    );
  }
  // Scoped to graded cards by CONSTRUCTION: for a reaction the loop above adds
  // only the graded-group card, so a warm-up TEXT card legitimately carrying
  // this copy is never scanned. The message branch is unchanged — it still adds
  // the block's single card.
  if (cards.any(
    (card) =>
        card.title.toLowerCase().contains('new message') ||
        card.body.toLowerCase().contains('new message'),
  )) {
    failures.add(
      r'$.evidence[android_notification_records] exposed New Message copy',
    );
  }
  // Body equality only. The title is what SELECTED these cards, so re-testing
  // it here would be an unreachable disjunct; a wrongly-titled card is rejected
  // by the closed allow-list above, not by this line.
  if (!messageScenario &&
      cards.any(
        (card) =>
            card.body !=
            groupReactionNotificationExpectedAndroidReactionBody(actorName),
      )) {
    failures.add(
      r'$.evidence[android_notification_records] reaction title/body mismatch',
    );
  }
}

void _validateUiRaw(
  String text, {
  required bool messageScenario,
  required String groupName,
  required String firstMarker,
  required String secondMarker,
  required String targetMarker,
  required List<String> failures,
}) {
  final blocks = _sourceBlocks(text);
  bool rawBlockContains(String name, List<String> values) {
    final block = blocks[name];
    return block != null &&
        block.contains('<hierarchy') &&
        values.every(block.contains);
  }

  if (messageScenario) {
    final expectations = <String, List<String>>{
      'ui_unread_0.xml': <String>['Open group $groupName'],
      'ui_unread_1.xml': <String>['Open group $groupName, 1 unread message'],
      'ui_unread_1_after_dismiss.xml': <String>[
        'Open group $groupName, 1 unread message',
      ],
      'ui_unread_2.xml': <String>['Open group $groupName, 2 unread messages'],
      'ui_conversation_after_tap.xml': <String>[firstMarker, secondMarker],
      'ui_unread_0_after_tap.xml': <String>['Open group $groupName'],
    };
    for (final entry in expectations.entries) {
      if (!rawBlockContains(entry.key, entry.value)) {
        failures.add(
          r'$.evidence[ui_automation] raw UI snapshot mismatch for ' +
              entry.key,
        );
      }
    }
    for (final name in const <String>[
      'ui_unread_0.xml',
      'ui_unread_0_after_tap.xml',
    ]) {
      if ((blocks[name] ?? '').contains('unread message')) {
        failures.add(
          r'$.evidence[ui_automation] zero state still exposes unread semantics',
        );
      }
    }
  } else {
    for (final entry in <String, List<String>>{
      'ui_reaction_unread_0_before.xml': <String>['Open group $groupName'],
      'ui_reaction_target_after_tap.xml': <String>[targetMarker],
      'ui_reaction_unread_0_after.xml': <String>['Open group $groupName'],
    }.entries) {
      if (!rawBlockContains(entry.key, entry.value)) {
        failures.add(
          r'$.evidence[ui_automation] raw UI snapshot mismatch for ' +
              entry.key,
        );
      }
    }
    // Plan 389. Group-qualified, and as ONE whole-label match rather than two
    // independent scans. A killed-recipient lane leaves its warm-up group
    // holding one unread row, and on device that row is a SIBLING NODE of the
    // graded group's zero-state row inside a single `<hierarchy>` — so both
    // `contains('Open group <graded>')` and `contains('unread message')` are
    // satisfied by the pair, and the two-scan form would red a correct capture.
    final gradedUnreadLabel = RegExp(
      'Open group ${RegExp.escape(groupName)}, \\d+ unread message',
    );
    if (blocks.values.any(gradedUnreadLabel.hasMatch)) {
      failures.add(
        r'$.evidence[ui_automation] reaction created unread semantics',
      );
    }
  }
}

Map<String, Object?>? _asStringMap(
  Object? value,
  String path,
  List<String> failures,
) {
  if (value is! Map) {
    failures.add('$path must be an object');
    return null;
  }
  try {
    return Map<String, Object?>.from(value);
  } on Object {
    failures.add('$path must use string keys');
    return null;
  }
}

Map<String, Object?>? _mapField(
  Map<String, Object?> parent,
  String key,
  String path,
  List<String> failures,
) {
  return _asStringMap(parent[key], '$path.$key', failures);
}

String? _requiredString(
  Map<String, Object?> parent,
  String key,
  String path,
  List<String> failures,
) {
  final value = parent[key];
  if (value is! String || value.trim().isEmpty) {
    failures.add('$path.$key must be a non-empty string');
    return null;
  }
  return value;
}

void _expectValue(
  Map<String, Object?> parent,
  String key,
  Object? expected,
  String path,
  List<String> failures,
) {
  if (parent[key] != expected) {
    failures.add('$path.$key must equal $expected');
  }
}

void _expectExactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String path,
  List<String> failures,
) {
  final actual = value.keys.toSet();
  final missing = expected.difference(actual).toList()..sort();
  final extra = actual.difference(expected).toList()..sort();
  if (missing.isNotEmpty) {
    failures.add('$path missing fields: ${missing.join(', ')}');
  }
  if (extra.isNotEmpty) {
    failures.add('$path unexpected fields: ${extra.join(', ')}');
  }
}

void _scanForbidden(String raw, String path, List<String> failures) {
  for (final field in const <String>[
    '"fcmToken":',
    '"apnsToken":',
    '"secretKey":',
    '"ciphertext":',
    '"plaintext":',
    '"senderPeerId":',
    '"recipientPeerId":',
    '"mknoon_group_message_dispatch_id":',
    '"mknoon_group_message_collapse_id":',
    '"gcm.message_id":',
    '"dispatchCorrelation":',
    '"claimedCollapseIdentifier":',
    '"providerMessageId":',
    '"requestIdentifier":',
  ]) {
    if (raw.contains(field)) {
      failures.add('$path contains forbidden sensitive field $field');
    }
  }
}
