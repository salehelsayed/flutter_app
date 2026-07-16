import 'dart:convert';
import 'dart:io';

import 'build_orchestrator.dart';
import 'manifest.dart';
import 'planner.dart';
import 'report.dart';
import 'scheduler.dart';
import 'verdict.dart';

const simsVerificationCommands = <String>{
  'verify-plan',
  'verify-report',
  'verify-schedule-equivalence',
  'verify-analyzer-delta',
};

Future<int> runSimsVerificationCommand(List<String> arguments) async {
  if (arguments.isEmpty || !simsVerificationCommands.contains(arguments[0])) {
    throw const FormatException('Unknown sims verification command.');
  }
  return switch (arguments[0]) {
    'verify-plan' => _verifyPlan(arguments.skip(1).toList()),
    'verify-report' => _verifyReport(arguments.skip(1).toList()),
    'verify-schedule-equivalence' => _verifyScheduleEquivalence(
      arguments.skip(1).toList(),
    ),
    'verify-analyzer-delta' => _verifyAnalyzerDelta(arguments.skip(1).toList()),
    _ => 64,
  };
}

int _verifyPlan(List<String> arguments) {
  if (arguments.length != 1) {
    throw const FormatException('verify-plan requires one plan JSON path.');
  }
  final decoded = _readObject(arguments.single);
  final plan = SimsPlan.fromJson(decoded);
  final errors = <String>[...SimsScheduler().validate(plan)];
  final ids = <String>{};
  final boundaries = <String>{};
  final commands = <String>{};
  for (final row in plan.rows) {
    if (!ids.add(row.id)) errors.add('duplicate capability ID: ${row.id}');
    if (!boundaries.add(row.proofBoundaryId)) {
      errors.add('duplicate proof boundary: ${row.proofBoundaryId}');
    }
    if (!commands.add(row.commandKey)) {
      errors.add('duplicate command: ${row.command.join(' ')}');
    }
    if (row.lane.isEmpty || row.buildProfileId.isEmpty || row.command.isEmpty) {
      errors.add('${row.id} has incomplete typed plan metadata');
    }
  }

  final manifestPath =
      Platform.environment['SIMS_MANIFEST'] ??
      'tool/sims/critical_features.json';
  final manifestFile = File(manifestPath);
  if (!manifestFile.existsSync()) {
    errors.add('current sims manifest does not exist: $manifestPath');
  } else {
    final manifest = SimsManifest.loadSync(manifestFile);
    errors.addAll(validateSimsFilesystemOwnership(manifest));
    if (plan.manifestDigest != manifest.digest) {
      errors.add('plan manifest digest does not match current manifest');
    }
    try {
      final canonical = SimsPlanner(manifest).compile(
        mode: plan.mode,
        family: plan.family,
        lane: plan.lane,
        onlyId: plan.onlyId,
        simultaneous: plan.simultaneous,
      );
      if (!_sameJson(decoded, canonical.toJson())) {
        errors.add(
          'plan does not exactly match the canonical current selection',
        );
      }
    } on Object catch (error) {
      errors.add('current manifest cannot compile this selection: $error');
    }
  }
  if (errors.isNotEmpty) {
    stderr.writeln('Invalid sims plan:\n${errors.join('\n')}');
    return 1;
  }
  stdout.writeln('PASS: verified ${plan.rows.length} typed sims plan rows.');
  return 0;
}

List<String> validateSimsFilesystemOwnership(
  SimsManifest manifest, {
  Directory? repoRoot,
  Set<String> requiredCorePaths = requiredCriticalCorePaths,
}) {
  final root = repoRoot ?? Directory.current;
  final featuresRoot = Directory('${root.path}/lib/features');
  final featurePaths = <String>{};
  if (featuresRoot.existsSync()) {
    for (final entity in featuresRoot.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = entity.uri.pathSegments
          .where((part) => part.isNotEmpty)
          .last;
      featurePaths.add('lib/features/$name');
    }
  }

  final errors = <String>[
    ...manifest.validate(
      requiredFeaturePaths: featurePaths,
      requiredCorePaths: requiredCorePaths,
    ),
  ];
  final ownerByPath = <String, FeatureOwnership>{
    for (final owner in manifest.ownership) owner.path: owner,
  };
  for (final path in <String>{...featurePaths, ...requiredCorePaths}) {
    final normalized = path.replaceAll('\\', '/');
    final owner = ownerByPath[normalized];
    if (owner == null) continue;
    if (!owner.critical) {
      errors.add('Critical filesystem path is marked noncritical: $normalized');
      continue;
    }
    final capability = manifest.capabilityById(owner.capabilityId);
    if (capability == null) continue;
    if (!capability.active ||
        !capability.required ||
        !capability.modes.contains(SimsMode.major)) {
      errors.add(
        'Critical ownership $normalized points to inactive, optional, or '
        'non-major capability ${capability.id}',
      );
    }
  }
  return List<String>.unmodifiable(errors);
}

/// Recompiles the report's declared selection from the current manifest and
/// compares every capability semantic. Execution-time device IDs are accepted
/// only when they are backed by the report's symbolic assignment map.
List<String> validateSimsReportPlanAgainstManifest(
  SimsReportAudit audit,
  SimsManifest manifest,
) {
  final errors = <String>[];
  late final SimsPlan canonical;
  try {
    canonical = SimsPlanner(manifest).compile(
      mode: audit.plan.mode,
      family: audit.plan.family,
      lane: audit.plan.lane,
      onlyId: audit.plan.onlyId,
      simultaneous: audit.plan.simultaneous,
    );
  } on Object catch (error) {
    return <String>['current manifest cannot compile report selection: $error'];
  }

  final reportedRows = audit.plan.rows;
  final canonicalBuildRows = canonical.rows
      .where(_isBuildPreparationRow)
      .toList(growable: false);
  final isBuildOnlyReport =
      !audit.cleanFullRun &&
      !audit.plan.releaseEligibleCandidate &&
      reportedRows.isNotEmpty &&
      reportedRows.every(_isBuildPreparationRow) &&
      _sameList(
        reportedRows.map((row) => row.id).toList(),
        canonicalBuildRows.map((row) => row.id).toList(),
      );
  final expectedRows = isBuildOnlyReport ? canonicalBuildRows : canonical.rows;
  final reportedIds = reportedRows.map((row) => row.id).toList();
  final expectedIds = expectedRows.map((row) => row.id).toList();
  if (!_sameList(reportedIds, expectedIds)) {
    errors.add(
      'report rows do not exactly match the canonical current selection',
    );
    return List<String>.unmodifiable(errors);
  }

  if (audit.plan.releaseEligibleCandidate !=
      canonical.releaseEligibleCandidate) {
    final safeDiagnosticDowngrade =
        !audit.plan.releaseEligibleCandidate && !audit.cleanFullRun;
    if (!safeDiagnosticDowngrade) {
      errors.add(
        'report release eligibility candidate differs from the canonical plan',
      );
    }
  }

  for (var index = 0; index < expectedRows.length; index++) {
    final expected = expectedRows[index];
    final reported = reportedRows[index];
    if (!_sameCapabilitySemantics(expected, reported)) {
      errors.add('${reported.id} differs from its current manifest semantics');
      continue;
    }
    final verdict = audit.verdictsById[reported.id];
    if (!_sameList(expected.dependencies, reported.dependencies)) {
      final allowedPreflightRewrite =
          reported.dependencies.isEmpty &&
          verdict != null &&
          verdict.status != SimsVerdictStatus.pass;
      if (!allowedPreflightRewrite) {
        errors.add(
          '${reported.id} dependencies differ from the current manifest',
        );
      }
    }
    if (!_resourcesMatchCurrentBinding(
      expected,
      reported,
      audit.deviceAssignments,
      verdict,
    )) {
      errors.add(
        '${reported.id} resources do not match the current manifest and '
        'reported device assignments',
      );
    }
  }
  return List<String>.unmodifiable(errors);
}

bool _isBuildPreparationRow(CapabilitySpec row) =>
    row.command.isNotEmpty && row.command.first == '@prepare-build';

bool _sameCapabilitySemantics(
  CapabilitySpec expected,
  CapabilitySpec reported,
) {
  final expectedJson = Map<String, Object?>.of(expected.toJson())
    ..remove('dependencies')
    ..remove('resources');
  final reportedJson = Map<String, Object?>.of(reported.toJson())
    ..remove('dependencies')
    ..remove('resources');
  return _sameJson(expectedJson, reportedJson);
}

bool _resourcesMatchCurrentBinding(
  CapabilitySpec expected,
  CapabilitySpec reported,
  Map<String, String> assignments,
  SimsVerdict? verdict,
) {
  if (expected.resources.length != reported.resources.length) return false;
  for (var index = 0; index < expected.resources.length; index++) {
    final expectedLock = expected.resources[index];
    final reportedLock = reported.resources[index];
    if (expectedLock.access != reportedLock.access) return false;
    if (!_isDeviceResource(expectedLock.name)) {
      if (expectedLock.name != reportedLock.name) return false;
      continue;
    }
    final targetId = assignments[expectedLock.name];
    final resolvedName = targetId == null
        ? null
        : '${expectedLock.name.substring(0, expectedLock.name.indexOf(':') + 1)}$targetId';
    if (reportedLock.name != expectedLock.name &&
        reportedLock.name != resolvedName) {
      return false;
    }
    if (verdict?.status == SimsVerdictStatus.pass &&
        (resolvedName == null || reportedLock.name != resolvedName)) {
      return false;
    }
  }
  return true;
}

bool _isDeviceResource(String name) =>
    name.startsWith('device:') || name.startsWith('device-control:');

int _verifyScheduleEquivalence(List<String> arguments) {
  if (arguments.length != 2) {
    throw const FormatException(
      'verify-schedule-equivalence requires serial and simultaneous plan or report JSON paths.',
    );
  }
  final serialJson = _readObject(arguments[0]);
  final simultaneousJson = _readObject(arguments[1]);
  final serialIsReport = _looksLikeExecutionReport(serialJson);
  final simultaneousIsReport = _looksLikeExecutionReport(simultaneousJson);
  if (serialIsReport != simultaneousIsReport) {
    stderr.writeln(
      'Non-equivalent sims schedules:\n'
      'both inputs must be plans or both inputs must be execution reports',
    );
    return 1;
  }

  if (!serialIsReport) {
    final serial = SimsPlan.fromJson(serialJson);
    final simultaneous = SimsPlan.fromJson(simultaneousJson);
    final errors = _planEquivalenceErrors(serial, simultaneous);
    if (errors.isNotEmpty) {
      stderr.writeln('Non-equivalent sims schedules:\n${errors.join('\n')}');
      return 1;
    }
    stdout.writeln(
      'PASS: serial and simultaneous plans select the same '
      '${serial.rows.length} capabilities and locks.',
    );
    return 0;
  }

  final manifest = _loadCurrentManifest();
  final sourceExpected = _currentSourceDigest();
  final serialAudit = auditSimsReportJson(
    serialJson,
    expectedManifestDigest: manifest.digest,
    expectedSourceDigest: sourceExpected,
  );
  final simultaneousAudit = auditSimsReportJson(
    simultaneousJson,
    expectedManifestDigest: manifest.digest,
    expectedSourceDigest: sourceExpected,
  );
  final errors = <String>[
    for (final error in serialAudit.errors) 'serial report: $error',
    for (final error in simultaneousAudit.errors) 'simultaneous report: $error',
    for (final error in validateSimsReportPlanAgainstManifest(
      serialAudit,
      manifest,
    ))
      'serial report: $error',
    for (final error in validateSimsReportPlanAgainstManifest(
      simultaneousAudit,
      manifest,
    ))
      'simultaneous report: $error',
    ..._planEquivalenceErrors(serialAudit.plan, simultaneousAudit.plan),
  ];
  if (!_sameSet(serialAudit.attemptedIds, simultaneousAudit.attemptedIds) ||
      !_sameSet(serialAudit.terminalIds, simultaneousAudit.terminalIds)) {
    errors.add('execution report attempted or terminal IDs differ');
  }
  for (final id in serialAudit.terminalIds) {
    final left = serialAudit.verdictsById[id];
    final right = simultaneousAudit.verdictsById[id];
    if (left == null || right == null || !_sameExecutionVerdict(left, right)) {
      errors.add('execution verdict differs between schedules: $id');
    }
  }
  final serialSchedule = serialAudit.schedule;
  final simultaneousSchedule = simultaneousAudit.schedule;
  if (serialSchedule == null || simultaneousSchedule == null) {
    errors.add('both execution reports require schedule traces');
  } else {
    if (serialSchedule.maxObservedConcurrency > 1) {
      errors.add('serial report observed concurrency above one');
    }
    if (!_sameSet(
      serialSchedule.tracesById.keys.toSet(),
      simultaneousSchedule.tracesById.keys.toSet(),
    )) {
      errors.add('execution schedule trace IDs differ');
    }
    for (final id in serialSchedule.tracesById.keys) {
      final left = serialSchedule.tracesById[id];
      final right = simultaneousSchedule.tracesById[id];
      if (left == null ||
          right == null ||
          !_sameList(
            left.resources.map((lock) => lock.toString()).toList()..sort(),
            right.resources.map((lock) => lock.toString()).toList()..sort(),
          )) {
        errors.add('execution schedule trace locks differ for $id');
      }
    }
  }
  if (serialAudit.buildReport.requestedProfiles !=
      simultaneousAudit.buildReport.requestedProfiles) {
    errors.add('execution build profile request counts differ');
  }
  if (!_sameStringMap(
    serialAudit.buildReport.artifactDigests,
    simultaneousAudit.buildReport.artifactDigests,
  )) {
    errors.add('execution artifact digests differ');
  }
  if (!_sameStringMap(
    serialAudit.deviceAssignments,
    simultaneousAudit.deviceAssignments,
  )) {
    errors.add('execution device assignments differ');
  }

  if (errors.isNotEmpty) {
    stderr.writeln('Non-equivalent sims schedules:\n${errors.join('\n')}');
    return 1;
  }
  stdout.writeln(
    'PASS: serial and simultaneous execution reports reconcile '
    '${serialAudit.plan.rows.length} capabilities, verdicts, and traces.',
  );
  return 0;
}

List<String> _planEquivalenceErrors(SimsPlan serial, SimsPlan simultaneous) {
  final errors = <String>[];
  if (serial.simultaneous) errors.add('first plan is not serial');
  if (!simultaneous.simultaneous) errors.add('second plan is not simultaneous');
  if (serial.mode != simultaneous.mode ||
      serial.manifestDigest != simultaneous.manifestDigest ||
      serial.family != simultaneous.family ||
      serial.onlyId != simultaneous.onlyId ||
      serial.lane != simultaneous.lane) {
    errors.add('plan selection metadata differs');
  }
  if (!_sameSet(serial.selectedIds, simultaneous.selectedIds)) {
    errors.add('selected capability IDs differ');
  }
  final rightById = <String, CapabilitySpec>{
    for (final row in simultaneous.rows) row.id: row,
  };
  for (final row in serial.rows) {
    final right = rightById[row.id];
    if (right == null) continue;
    if (!_sameList(row.dependencies, right.dependencies) ||
        row.buildProfileId != right.buildProfileId ||
        !_sameList(
          row.resources.map((lock) => lock.toString()).toList(),
          right.resources.map((lock) => lock.toString()).toList(),
        ) ||
        !_sameList(row.command, right.command) ||
        row.required != right.required) {
      errors.add('${row.id} changes semantics between schedules');
    }
  }
  errors.addAll(SimsScheduler().validate(serial));
  errors.addAll(SimsScheduler().validate(simultaneous));
  return errors;
}

int _verifyReport(List<String> arguments) {
  if (arguments.isEmpty) {
    throw const FormatException('verify-report requires one report JSON path.');
  }
  final path = arguments.first;
  String? requiredMode;
  var requireClean = false;
  for (var index = 1; index < arguments.length; index++) {
    switch (arguments[index]) {
      case '--require-clean-full-run':
        requireClean = true;
      case '--require-mode':
        if (++index >= arguments.length) {
          throw const FormatException('--require-mode requires a value.');
        }
        requiredMode = arguments[index];
      default:
        throw FormatException(
          'Unknown verify-report option: ${arguments[index]}',
        );
    }
  }
  final report = _readObject(path);
  final manifest = _loadCurrentManifest();
  final expectedSourceDigest = _currentSourceDigest();
  final audit = auditSimsReportJson(
    report,
    expectedManifestDigest: manifest.digest,
    expectedSourceDigest: expectedSourceDigest,
  );
  final errors = <String>[...audit.errors];
  errors.addAll(validateSimsFilesystemOwnership(manifest));
  errors.addAll(validateSimsReportPlanAgainstManifest(audit, manifest));
  if (requiredMode != null && audit.plan.mode.wireName != requiredMode) {
    errors.add(
      'report mode is ${audit.plan.mode.wireName}, expected $requiredMode',
    );
  }
  if (requireClean && !audit.cleanFullRun) {
    errors.add('report is not a clean full run');
  }
  if (requireClean && !audit.computedAssessment.releaseEligible) {
    errors.add('reconstructed report is not release eligible');
  }
  if (errors.isNotEmpty) {
    stderr.writeln('Invalid sims report:\n${errors.join('\n')}');
    return 1;
  }
  stdout.writeln(
    'PASS: independently verified report with '
    '${audit.selectedIds.length} capabilities.',
  );
  return 0;
}

int _verifyAnalyzerDelta(List<String> arguments) {
  if (arguments.length != 2) {
    throw const FormatException(
      'verify-analyzer-delta requires before and after machine-output paths.',
    );
  }
  final before = _analyzerIssueCounts(File(arguments[0]));
  final after = _analyzerIssueCounts(File(arguments[1]));
  final added = <String>[];
  for (final entry in after.entries) {
    final excess = entry.value - (before[entry.key] ?? 0);
    for (var index = 0; index < excess; index++) {
      added.add(entry.key);
    }
  }
  if (added.isNotEmpty) {
    stderr.writeln(
      'Analyzer delta introduced ${added.length} issue(s):\n'
      '${added.join('\n')}',
    );
    return 1;
  }
  stdout.writeln('PASS: analyzer introduced 0 new machine-reported issues.');
  return 0;
}

Map<String, int> _analyzerIssueCounts(File file) {
  if (!file.existsSync()) {
    throw FormatException('Analyzer snapshot does not exist: ${file.path}');
  }
  final counts = <String, int>{};
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final fields = line.split('|');
    if (fields.length < 7 ||
        !const <String>{'ERROR', 'WARNING', 'INFO'}.contains(fields.first)) {
      continue;
    }
    final key = fields.join('|');
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

Map<String, Object?> _readObject(String path) {
  final file = File(path);
  if (!file.existsSync()) throw FormatException('JSON file not found: $path');
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map) throw FormatException('$path is not a JSON object.');
  return decoded.map<String, Object?>((key, value) => MapEntry('$key', value));
}

SimsManifest _loadCurrentManifest() {
  final path =
      Platform.environment['SIMS_MANIFEST'] ??
      'tool/sims/critical_features.json';
  final file = File(path);
  if (!file.existsSync()) {
    throw FormatException('Current sims manifest does not exist: $path');
  }
  return SimsManifest.loadSync(file);
}

bool _looksLikeExecutionReport(Map<String, Object?> json) =>
    json['plan'] is Map && json['verdicts'] is List;

String? _cachedCurrentSourceDigest;

String _currentSourceDigest() => _cachedCurrentSourceDigest ??=
    computeSimsSourceClosureDigest(environment: Platform.environment);

bool _sameJson(Object? left, Object? right) =>
    canonicalJson(left) == canonicalJson(right);

bool _sameExecutionVerdict(SimsVerdict left, SimsVerdict right) {
  final leftJson = Map<String, Object?>.of(left.toJson())
    ..remove('artifactEvidence');
  final rightJson = Map<String, Object?>.of(right.toJson())
    ..remove('artifactEvidence');
  // Each report independently re-verifies its runtime proof path, digest, and
  // manifest validator binding. Separate serial and simultaneous executions
  // necessarily produce different content-addressed proof files, so their
  // paths and hashes are not cross-run verdict semantics.
  return _sameJson(leftJson, rightJson);
}

bool _sameStringMap(Map<String, String> left, Map<String, String> right) =>
    left.length == right.length &&
    left.entries.every((entry) => right[entry.key] == entry.value);

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

bool _sameList(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
