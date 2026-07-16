import 'dart:convert';
import 'dart:io';

import 'artifact_evidence.dart';
import 'manifest.dart';
import 'verdict.dart';

const simsResultPrefix = 'SIMS_RESULT_JSON=';

final class SimsCommandExecution {
  const SimsCommandExecution({
    required this.verdict,
    required this.stdoutText,
    required this.stderrText,
    required this.logPath,
  });

  final SimsVerdict verdict;
  final String stdoutText;
  final String stderrText;
  final String logPath;
}

/// Executes one manifest row without interpreting a zero process exit as
/// device proof. Device/artifact rows must emit the structured result sentinel;
/// ordinary host aggregate gates retain a strict exit-code adapter.
final class SimsProcessExecutor {
  SimsProcessExecutor({
    Directory? logDirectory,
    Map<String, String>? environment,
    Map<String, Map<String, String>> environmentByCapabilityId =
        const <String, Map<String, String>>{},
    this.preparedArtifacts = const <String, String>{},
    this.buildFailures = const <String, String>{},
    this.preflightVerdicts = const <String, SimsVerdict>{},
  }) : logDirectory = logDirectory ?? Directory('build/sims/logs'),
       environment = Map<String, String>.unmodifiable(
         environment ?? Platform.environment,
       ),
       environmentByCapabilityId =
           Map<String, Map<String, String>>.unmodifiable(
             <String, Map<String, String>>{
               for (final entry in environmentByCapabilityId.entries)
                 entry.key: Map<String, String>.unmodifiable(entry.value),
             },
           );

  final Directory logDirectory;
  final Map<String, String> environment;
  final Map<String, Map<String, String>> environmentByCapabilityId;
  final Map<String, String> preparedArtifacts;
  final Map<String, String> buildFailures;
  final Map<String, SimsVerdict> preflightVerdicts;

  Future<SimsCommandExecution> execute(CapabilitySpec row) async {
    final preflight = preflightVerdicts[row.id];
    if (preflight != null) {
      final detail = preflight.detail.isEmpty
          ? 'Capability ended during live-target preflight.'
          : preflight.detail;
      final logPath = _writeLog(
        row,
        stdoutText: '',
        stderrText: detail,
        exitCode: preflight.exitCode ?? 0,
      );
      return SimsCommandExecution(
        verdict: preflight,
        stdoutText: '',
        stderrText: detail,
        logPath: logPath,
      );
    }
    if (row.command.first == '@prepare-build') {
      final failure = buildFailures[row.buildProfileId];
      if (failure != null) {
        return _internalBlocked(row, SimsBlockerKind.environment, failure);
      }
      final artifact = preparedArtifacts[row.buildProfileId];
      if (artifact == null || !_preparedArtifactExists(artifact)) {
        return _internalBlocked(
          row,
          SimsBlockerKind.missingArtifact,
          'Prepared artifact is missing for ${row.buildProfileId}.',
        );
      }
      final detail = 'Attested artifact prepared for ${row.buildProfileId}.';
      final logPath = _writeLog(
        row,
        stdoutText: detail,
        stderrText: '',
        exitCode: 0,
      );
      return SimsCommandExecution(
        verdict: SimsVerdict.pass(
          row.id,
          assertionsAttempted: 1,
          artifactPresent: true,
          detail: detail,
        ),
        stdoutText: detail,
        stderrText: '',
        logPath: logPath,
      );
    }

    final childEnvironment = <String, String>{
      ...environment,
      ...?environmentByCapabilityId[row.id],
    }..removeWhere((name, _) => name.startsWith('SIMS_ARTIFACT_'));
    childEnvironment.addAll(<String, String>{
      'SIMS_CAPABILITY_ID': row.id,
      'SIMS_ARTIFACT_PROFILE_ID': row.buildProfileId,
      'SIMS_PROOF_DIRECTORY': Directory(
        'build/sims/proofs/${_safeFileName(row.id)}',
      ).absolute.path,
      _artifactEnvironmentName(row.buildProfileId):
          ?preparedArtifacts[row.buildProfileId],
    });
    String executable = row.command.first;
    File? buildViolationLog;
    if (!row.declaredBuildException) {
      final guard = _installBuildGuard(row, childEnvironment);
      if (guard.error != null) {
        return _internalBlocked(row, SimsBlockerKind.harness, guard.error!);
      }
      childEnvironment['PATH'] = guard.path!;
      childEnvironment['SIMS_BUILD_GUARD_LOG'] = guard.log!.path;
      buildViolationLog = guard.log;
      executable =
          _resolveExecutable(row.command.first, environment) ??
          row.command.first;
    }
    late final List<String> arguments;
    try {
      arguments = row.command
          .skip(1)
          .map((argument) => _expandEnvironment(argument, childEnvironment))
          .toList(growable: false);
    } on FormatException catch (error) {
      return _internalBlocked(row, SimsBlockerKind.harness, error.message);
    }

    ProcessResult result;
    try {
      result = await Process.run(
        executable,
        arguments,
        environment: childEnvironment,
      );
    } on ProcessException catch (error) {
      return _internalBlocked(
        row,
        SimsBlockerKind.missingDriver,
        'Unable to start command: ${error.message}',
      );
    }

    final stdoutText = '${result.stdout}';
    final stderrText = '${result.stderr}';
    final logPath = _writeLog(
      row,
      stdoutText: stdoutText,
      stderrText: stderrText,
      exitCode: result.exitCode,
    );
    final sentinel = _sentinelFrom(stdoutText);
    final violation = buildViolationLog?.existsSync() == true
        ? buildViolationLog!.readAsStringSync().trim()
        : '';
    final verdict = violation.isNotEmpty
        ? SimsVerdict.fail(
            row.id,
            assertionsAttempted: 1,
            exitCode: result.exitCode == 0 ? 91 : result.exitCode,
            blocker: SimsBlockerKind.harness,
            detail: 'Undeclared child build command rejected: $violation',
          )
        : sentinel == null
        ? _fallbackVerdict(
            row,
            exitCode: result.exitCode,
            stdoutText: stdoutText,
            stderrText: stderrText,
          )
        : _verdictFromSentinel(row, sentinel, processExitCode: result.exitCode);
    return SimsCommandExecution(
      verdict: verdict,
      stdoutText: stdoutText,
      stderrText: stderrText,
      logPath: logPath,
    );
  }

  _BuildGuardInstallation _installBuildGuard(
    CapabilitySpec row,
    Map<String, String> childEnvironment,
  ) {
    final guardDirectory = Directory(
      '${logDirectory.path}/.build-guard/${_safeFileName(row.id)}',
    );
    if (guardDirectory.existsSync()) {
      guardDirectory.deleteSync(recursive: true);
    }
    guardDirectory.createSync(recursive: true);
    final violationLog = File('${guardDirectory.path}/violations.log');
    final wrappers = <String, String>{};
    for (final tool in const <String>[
      'flutter',
      'gradle',
      'gradlew',
      'xcodebuild',
    ]) {
      final resolved = _resolveExecutable(tool, childEnvironment);
      if (resolved != null) wrappers[tool] = resolved;
    }

    for (final entry in wrappers.entries) {
      final wrapper = File('${guardDirectory.path}/${entry.key}');
      wrapper.writeAsStringSync(
        _buildGuardScript(entry.key, entry.value),
        flush: true,
      );
      final chmod = Process.runSync('chmod', <String>['700', wrapper.path]);
      if (chmod.exitCode != 0) {
        return _BuildGuardInstallation.error(
          'Unable to make build guard executable for ${entry.key}.',
        );
      }
    }

    final originalPath = childEnvironment['PATH'] ?? '';
    final pathListSeparator = Platform.isWindows ? ';' : ':';
    return _BuildGuardInstallation.success(
      '${guardDirectory.path}$pathListSeparator$originalPath',
      violationLog,
    );
  }

  SimsCommandExecution _internalBlocked(
    CapabilitySpec row,
    SimsBlockerKind blocker,
    String detail,
  ) {
    final logPath = _writeLog(
      row,
      stdoutText: '',
      stderrText: detail,
      exitCode: blocker == SimsBlockerKind.missingDriver ? 78 : 1,
    );
    return SimsCommandExecution(
      verdict: SimsVerdict.blocked(row.id, blocker: blocker, detail: detail),
      stdoutText: '',
      stderrText: detail,
      logPath: logPath,
    );
  }

  String _writeLog(
    CapabilitySpec row, {
    required String stdoutText,
    required String stderrText,
    required int exitCode,
  }) {
    logDirectory.createSync(recursive: true);
    final safeId = row.id.replaceAll(RegExp('[^A-Za-z0-9_.-]'), '_');
    final file = File('${logDirectory.path}/$safeId.log');
    file.writeAsStringSync(
      'capability=${row.id}\n'
      'exitCode=$exitCode\n'
      '--- stdout ---\n$stdoutText\n'
      '--- stderr ---\n$stderrText\n',
      flush: true,
    );
    return file.path;
  }
}

final class _BuildGuardInstallation {
  const _BuildGuardInstallation._({this.path, this.log, this.error});

  factory _BuildGuardInstallation.success(String path, File log) =>
      _BuildGuardInstallation._(path: path, log: log);

  factory _BuildGuardInstallation.error(String error) =>
      _BuildGuardInstallation._(error: error);

  final String? path;
  final File? log;
  final String? error;
}

String _buildGuardScript(String tool, String realExecutable) {
  final quotedExecutable = _shellQuote(realExecutable);
  return switch (tool) {
    'flutter' =>
      '''#!/bin/sh
if [ "\${1-}" = "build" ]; then
  printf 'flutter' >>"\${SIMS_BUILD_GUARD_LOG:?}"
  printf ' %s' "\$@" >>"\$SIMS_BUILD_GUARD_LOG"
  printf '\n' >>"\$SIMS_BUILD_GUARD_LOG"
  exit 91
fi
exec $quotedExecutable "\$@"
''',
    'gradle' || 'gradlew' =>
      '''#!/bin/sh
for arg in "\$@"; do
  case "\$arg" in
    build|assemble|assemble*|bundle|bundle*)
      printf '$tool' >>"\${SIMS_BUILD_GUARD_LOG:?}"
      printf ' %s' "\$@" >>"\$SIMS_BUILD_GUARD_LOG"
      printf '\n' >>"\$SIMS_BUILD_GUARD_LOG"
      exit 91
      ;;
  esac
done
exec $quotedExecutable "\$@"
''',
    'xcodebuild' =>
      '''#!/bin/sh
for arg in "\$@"; do
  case "\$arg" in
    build|archive)
      printf 'xcodebuild' >>"\${SIMS_BUILD_GUARD_LOG:?}"
      printf ' %s' "\$@" >>"\$SIMS_BUILD_GUARD_LOG"
      printf '\n' >>"\$SIMS_BUILD_GUARD_LOG"
      exit 91
      ;;
  esac
done
exec $quotedExecutable "\$@"
''',
    _ => throw StateError('Unsupported guarded tool: $tool'),
  };
}

String? _resolveExecutable(String executable, Map<String, String> environment) {
  if (executable.contains(Platform.pathSeparator)) return executable;
  final path = environment['PATH'];
  if (path == null || path.isEmpty) return null;
  for (final directory in path.split(Platform.isWindows ? ';' : ':')) {
    if (directory.isEmpty) continue;
    final candidate = File('$directory${Platform.pathSeparator}$executable');
    if (candidate.existsSync()) return candidate.absolute.path;
  }
  return null;
}

String _shellQuote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

String _safeFileName(String value) =>
    value.replaceAll(RegExp('[^A-Za-z0-9_.-]'), '_');

bool _preparedArtifactExists(String path) {
  final type = FileSystemEntity.typeSync(path, followLinks: true);
  return type == FileSystemEntityType.file ||
      type == FileSystemEntityType.directory;
}

Map<String, Object?>? _sentinelFrom(String output) {
  final matches = <String>[];
  for (final line in LineSplitter.split(output)) {
    var searchFrom = 0;
    while (true) {
      final marker = line.indexOf(simsResultPrefix, searchFrom);
      if (marker < 0) break;
      matches.add(line.substring(marker + simsResultPrefix.length).trim());
      searchFrom = marker + simsResultPrefix.length;
    }
  }
  if (matches.isEmpty) return null;
  if (matches.length != 1) {
    return <String, Object?>{
      'status': 'FAIL',
      'assertionsAttempted': 0,
      'artifactPresent': false,
      'printOnly': false,
      'blocker': 'harness',
      'detail': 'Command emitted more than one SIMS_RESULT_JSON sentinel.',
    };
  }
  try {
    final decoded = jsonDecode(matches.single);
    if (decoded is! Map) {
      throw const FormatException('result sentinel root is not an object');
    }
    return decoded.map<String, Object?>(
      (key, value) => MapEntry('$key', value),
    );
  } on FormatException catch (error) {
    return <String, Object?>{
      'status': 'FAIL',
      'assertionsAttempted': 0,
      'artifactPresent': false,
      'printOnly': false,
      'blocker': 'harness',
      'detail': 'Invalid SIMS_RESULT_JSON sentinel: ${error.message}',
    };
  }
}

SimsVerdict _verdictFromSentinel(
  CapabilitySpec row,
  Map<String, Object?> json, {
  required int processExitCode,
}) {
  try {
    final statusValue = json['status'];
    final attempts = json['assertionsAttempted'];
    final artifactPresent = json['artifactPresent'];
    final printOnly = json['printOnly'];
    if (statusValue is! String ||
        attempts is! int ||
        attempts < 0 ||
        artifactPresent is! bool ||
        printOnly is! bool) {
      throw const FormatException(
        'status, assertionsAttempted, artifactPresent, and printOnly are required',
      );
    }
    final status = SimsVerdictStatusName.parse(statusValue);
    final blockerValue = json['blocker'];
    final blocker = blockerValue == null
        ? null
        : SimsBlockerKind.values.byName('$blockerValue');
    final targetAvailable = json['targetCapabilityAvailable'];
    if (targetAvailable != null && targetAvailable is! bool) {
      throw const FormatException('targetCapabilityAvailable must be boolean');
    }
    final declaredExit = json['exitCode'];
    if (declaredExit != null && declaredExit is! int) {
      throw const FormatException('exitCode must be an integer');
    }
    if (declaredExit != null && declaredExit != processExitCode) {
      throw FormatException(
        'declared exitCode $declaredExit does not match process exit '
        '$processExitCode',
      );
    }
    final reasonValue = json['reason'];
    if (reasonValue != null && reasonValue is! String) {
      throw const FormatException('reason must be a string');
    }
    SimsArtifactEvidence? artifactEvidence;
    final encodedEvidence = json['artifactEvidence'];
    if (encodedEvidence != null) {
      artifactEvidence = SimsArtifactEvidence.fromJson(encodedEvidence);
    }
    _validateStructuredStatus(
      row,
      status: status,
      processExitCode: processExitCode,
      assertionsAttempted: attempts,
      artifactPresent: artifactPresent,
      printOnly: printOnly,
      blocker: blocker,
      targetCapabilityAvailable: targetAvailable as bool?,
      reason: reasonValue as String?,
      artifactEvidence: artifactEvidence,
    );
    if (status == SimsVerdictStatus.pass && row.artifactRequired) {
      if (!artifactPresent) {
        throw const FormatException(
          'artifact-required PASS must set artifactPresent=true',
        );
      }
      if (artifactEvidence == null) {
        throw const FormatException(
          'artifact-required PASS must emit path, SHA-256, and validator IDs',
        );
      }
      final audit = auditSimsArtifactEvidence(
        evidence: artifactEvidence,
        expectedValidatorIds: row.artifactValidators,
      );
      if (!audit.isValid) {
        throw FormatException(audit.detail);
      }
      artifactEvidence = artifactEvidence.copyWith(path: audit.canonicalPath!);
    }
    return SimsVerdict(
      capabilityId: row.id,
      status: status,
      assertionsAttempted: attempts,
      exitCode: processExitCode,
      artifactPresent: artifactPresent,
      printOnly: printOnly,
      blocker: blocker,
      targetCapabilityAvailable: targetAvailable,
      reason: reasonValue,
      detail: json['detail'] as String? ?? '',
      artifactEvidence: artifactEvidence,
    );
  } on Object catch (error) {
    return SimsVerdict(
      capabilityId: row.id,
      status: SimsVerdictStatus.fail,
      assertionsAttempted: 0,
      exitCode: processExitCode,
      artifactPresent: false,
      printOnly: false,
      blocker: SimsBlockerKind.harness,
      targetCapabilityAvailable: null,
      reason: null,
      detail: 'Invalid structured result: $error',
    );
  }
}

void _validateStructuredStatus(
  CapabilitySpec row, {
  required SimsVerdictStatus status,
  required int processExitCode,
  required int assertionsAttempted,
  required bool artifactPresent,
  required bool printOnly,
  required SimsBlockerKind? blocker,
  required bool? targetCapabilityAvailable,
  required String? reason,
  required SimsArtifactEvidence? artifactEvidence,
}) {
  switch (status) {
    case SimsVerdictStatus.pass:
      if (processExitCode != 0 ||
          assertionsAttempted <= 0 ||
          printOnly ||
          blocker != null ||
          targetCapabilityAvailable != null ||
          reason != null) {
        throw const FormatException(
          'PASS requires exit 0, attempted assertions, and no blocker, '
          'target-unavailable state, reason, or print-only marker',
        );
      }
      if (!row.artifactRequired && artifactEvidence != null) {
        throw const FormatException(
          'non-artifact PASS cannot attach unregistered artifact evidence',
        );
      }
    case SimsVerdictStatus.notApplicable:
      if (processExitCode != 0 ||
          assertionsAttempted != 0 ||
          artifactPresent ||
          printOnly ||
          artifactEvidence != null ||
          blocker != SimsBlockerKind.targetUnavailable ||
          targetCapabilityAvailable != false ||
          reason != targetUnavailableNaReason ||
          row.allowedNaReason != targetUnavailableNaReason) {
        throw const FormatException(
          'N/A requires exit 0, zero proof, and the exact policy-valid '
          'unavailable-target reason',
        );
      }
    case SimsVerdictStatus.fail:
      if (processExitCode == 0 || blocker == null) {
        throw const FormatException(
          'FAIL requires a nonzero process exit and a blocker classification',
        );
      }
    case SimsVerdictStatus.blocked:
      if (processExitCode != 78 ||
          assertionsAttempted != 0 ||
          printOnly ||
          blocker == null ||
          targetCapabilityAvailable == false ||
          reason != null ||
          artifactEvidence != null) {
        throw const FormatException(
          'BLOCKED requires exit 78, zero assertions, and one non-target '
          'blocker classification',
        );
      }
    case SimsVerdictStatus.skip:
      if (processExitCode != 0 ||
          assertionsAttempted != 0 ||
          artifactPresent ||
          printOnly ||
          blocker != null ||
          targetCapabilityAvailable != null ||
          reason != null ||
          artifactEvidence != null) {
        throw const FormatException(
          'SKIP requires exit 0 and cannot carry proof or blocker metadata',
        );
      }
  }
}

SimsVerdict _fallbackVerdict(
  CapabilitySpec row, {
  required int exitCode,
  required String stdoutText,
  required String stderrText,
}) {
  final detail = _boundedDetail(
    stderrText.isNotEmpty ? stderrText : stdoutText,
  );
  if (exitCode == 78) {
    return SimsVerdict.blocked(
      row.id,
      blocker: SimsBlockerKind.missingDriver,
      detail: detail,
    );
  }
  if (exitCode != 0) {
    return SimsVerdict.fail(
      row.id,
      assertionsAttempted: 1,
      exitCode: exitCode,
      blocker: SimsBlockerKind.test,
      detail: detail,
    );
  }
  if (row.artifactRequired) {
    return SimsVerdict(
      capabilityId: row.id,
      status: SimsVerdictStatus.fail,
      assertionsAttempted: 0,
      exitCode: 0,
      artifactPresent: false,
      printOnly: stdoutText.toLowerCase().contains('catalog'),
      blocker: SimsBlockerKind.missingArtifact,
      targetCapabilityAvailable: null,
      reason: null,
      detail: 'Structured proof result/artifact evidence was not emitted.',
    );
  }
  return SimsVerdict.pass(
    row.id,
    assertionsAttempted: row.assertionIds.isEmpty ? 1 : row.assertionIds.length,
    artifactPresent: true,
    detail: detail,
  );
}

String _boundedDetail(String value) {
  final normalized = value.trim();
  if (normalized.length <= 1000) return normalized;
  return '${normalized.substring(0, 1000)}…';
}

String _artifactEnvironmentName(String profileId) =>
    'SIMS_ARTIFACT_${profileId.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '_')}';

String _expandEnvironment(String argument, Map<String, String> environment) {
  return argument.replaceAllMapped(RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}'), (
    match,
  ) {
    final name = match.group(1)!;
    final value = environment[name];
    if (value == null || value.isEmpty) {
      throw FormatException('Required command environment is unset: $name');
    }
    return value;
  });
}
