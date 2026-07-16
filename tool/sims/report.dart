import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'artifact_evidence.dart';
import 'manifest.dart';
import 'planner.dart';
import 'scheduler.dart';
import 'verdict.dart';

final class SimsBuildReport {
  const SimsBuildReport({
    required this.requestedProfiles,
    required this.actualBuilds,
    required this.hits,
    required this.misses,
    required this.invalidations,
    required this.artifactDigests,
    required this.declaredExceptions,
    this.builtProfileIds = const <String>[],
    this.cacheHitProfileIds = const <String>[],
    this.failedProfileIds = const <String>[],
    this.profileElapsedMs = const <String, int>{},
    this.totalElapsedMs = 0,
  });

  static const empty = SimsBuildReport(
    requestedProfiles: 0,
    actualBuilds: 0,
    hits: 0,
    misses: 0,
    invalidations: <String>[],
    artifactDigests: <String, String>{},
    declaredExceptions: <String>[],
    builtProfileIds: <String>[],
    cacheHitProfileIds: <String>[],
    failedProfileIds: <String>[],
    profileElapsedMs: <String, int>{},
    totalElapsedMs: 0,
  );

  factory SimsBuildReport.fromJson(
    Map<String, Object?> json,
  ) => SimsBuildReport(
    requestedProfiles: _auditInt(json, 'requestedProfiles'),
    actualBuilds: _auditInt(json, 'actualBuilds'),
    hits: _auditInt(json, 'hits'),
    misses: _auditInt(json, 'misses'),
    invalidations: _auditStringList(
      json['invalidations'],
      'builds.invalidations',
    ),
    artifactDigests: _auditStringMap(
      json['artifactDigests'],
      'builds.artifactDigests',
    ),
    declaredExceptions: _auditStringList(
      json['declaredExceptions'],
      'builds.declaredExceptions',
    ),
    builtProfileIds: json.containsKey('builtProfileIds')
        ? _auditStringList(json['builtProfileIds'], 'builds.builtProfileIds')
        : const <String>[],
    cacheHitProfileIds: json.containsKey('cacheHitProfileIds')
        ? _auditStringList(
            json['cacheHitProfileIds'],
            'builds.cacheHitProfileIds',
          )
        : const <String>[],
    failedProfileIds: json.containsKey('failedProfileIds')
        ? _auditStringList(json['failedProfileIds'], 'builds.failedProfileIds')
        : const <String>[],
    profileElapsedMs: json.containsKey('profileElapsedMs')
        ? _auditIntMap(json['profileElapsedMs'], 'builds.profileElapsedMs')
        : const <String, int>{},
    totalElapsedMs: json.containsKey('totalElapsedMs')
        ? _auditInt(json, 'totalElapsedMs')
        : 0,
  );

  final int requestedProfiles;
  final int actualBuilds;
  final int hits;
  final int misses;
  final List<String> invalidations;
  final Map<String, String> artifactDigests;
  final List<String> declaredExceptions;
  final List<String> builtProfileIds;
  final List<String> cacheHitProfileIds;
  final List<String> failedProfileIds;
  final Map<String, int> profileElapsedMs;
  final int totalElapsedMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'requestedProfiles': requestedProfiles,
    'actualBuilds': actualBuilds,
    'hits': hits,
    'misses': misses,
    'invalidations': invalidations,
    'artifactDigests': artifactDigests,
    'declaredExceptions': declaredExceptions,
    'builtProfileIds': builtProfileIds,
    'cacheHitProfileIds': cacheHitProfileIds,
    'failedProfileIds': failedProfileIds,
    'profileElapsedMs': profileElapsedMs,
    'totalElapsedMs': totalElapsedMs,
  };
}

final class SimsReport {
  const SimsReport({
    required this.plan,
    required this.attemptedIds,
    required this.verdicts,
    required this.assessment,
    required this.buildReport,
    required this.cleanFullRun,
    required this.diagnosticContinuation,
    required this.generatedAt,
    required this.sourceDigest,
    this.schedule,
    this.deviceAssignments = const <String, String>{},
    this.deviceInventoryDigest,
  });

  final SimsPlan plan;
  final Set<String> attemptedIds;
  final List<SimsVerdict> verdicts;
  final SimsReleaseAssessment assessment;
  final SimsBuildReport buildReport;
  final bool cleanFullRun;
  final bool diagnosticContinuation;
  final DateTime generatedAt;
  final SimsScheduleResult? schedule;
  final Map<String, String> deviceAssignments;
  final String? deviceInventoryDigest;
  final String sourceDigest;

  Set<String> get terminalIds =>
      verdicts.map((verdict) => verdict.capabilityId).toSet();

  List<String> get validationErrors {
    final errors = <String>[];
    final selected = plan.selectedIds;
    if (!_sameSet(selected, attemptedIds)) {
      errors.add('selectedIds and attemptedIds differ');
    }
    if (!_sameSet(selected, terminalIds) ||
        terminalIds.length != verdicts.length) {
      errors.add('selectedIds and terminalIds differ or contain duplicates');
    }
    if (!_sameSet(selected, assessment.selectedIds) ||
        !_sameSet(attemptedIds, assessment.attemptedIds) ||
        !_sameSet(terminalIds, assessment.terminalIds)) {
      errors.add('report IDs differ from release assessment IDs');
    }
    if (assessment.releaseEligible &&
        (!cleanFullRun || diagnosticContinuation || !assessment.reconciled)) {
      errors.add('release-eligible report violates clean-run invariants');
    }
    if (!_isSha256(sourceDigest)) {
      errors.add('source digest is not a SHA-256 digest');
    }
    if (buildReport.actualBuilds > buildReport.requestedProfiles) {
      errors.add('actual builds exceed requested profiles');
    }
    if (buildReport.totalElapsedMs < 0 ||
        buildReport.profileElapsedMs.values.any((value) => value < 0)) {
      errors.add('build elapsed times cannot be negative');
    }
    errors.addAll(
      validateSimsRuntimeArtifactEvidence(plan, <String, SimsVerdict>{
        for (final verdict in verdicts) verdict.capabilityId: verdict,
      }),
    );
    final scheduleResult = schedule;
    if (cleanFullRun && scheduleResult != null) {
      if (!_sameSet(selected, scheduleResult.selectedIds) ||
          !_sameSet(attemptedIds, scheduleResult.attemptedIds) ||
          !_sameSet(terminalIds, scheduleResult.terminalIds)) {
        errors.add('clean-run schedule IDs differ from report IDs');
      }
    }
    return List<String>.unmodifiable(errors);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'plan': plan.toJson(),
    'selectedIds': plan.rows.map((row) => row.id).toList(),
    'attemptedIds': attemptedIds.toList()..sort(),
    'terminalIds': terminalIds.toList()..sort(),
    'verdicts': verdicts.map((verdict) => verdict.toJson()).toList(),
    'assessment': assessment.toJson(),
    'builds': buildReport.toJson(),
    'cleanFullRun': cleanFullRun,
    'diagnosticContinuation': diagnosticContinuation,
    'sourceDigest': sourceDigest,
    if (schedule != null) 'schedule': schedule!.toJson(),
    'devices': <String, Object?>{
      'assignments': deviceAssignments,
      if (deviceInventoryDigest != null)
        'inventoryDigest': deviceInventoryDigest,
    },
    'validationErrors': validationErrors,
  };
}

/// Parsed schedule evidence retained by [auditSimsReportJson]. Timestamps are
/// evidence, not trusted declarations: the audit independently checks trace
/// completeness, dependency ordering, lock compatibility, and concurrency.
final class SimsAuditedTrace {
  const SimsAuditedTrace({
    required this.capabilityId,
    required this.startedAt,
    required this.endedAt,
    required this.dependencyWait,
    required this.resources,
  });

  final String capabilityId;
  final DateTime startedAt;
  final DateTime endedAt;
  final Duration dependencyWait;
  final List<ResourceLock> resources;
}

final class SimsAuditedSchedule {
  const SimsAuditedSchedule({
    required this.selectedIds,
    required this.attemptedIds,
    required this.terminalIds,
    required this.verdictsById,
    required this.tracesById,
    required this.maxObservedConcurrency,
  });

  final Set<String> selectedIds;
  final Set<String> attemptedIds;
  final Set<String> terminalIds;
  final Map<String, SimsVerdict> verdictsById;
  final Map<String, SimsAuditedTrace> tracesById;
  final int maxObservedConcurrency;
}

final class SimsReportAudit {
  const SimsReportAudit({
    required this.plan,
    required this.selectedIds,
    required this.attemptedIds,
    required this.terminalIds,
    required this.verdictsById,
    required this.computedAssessment,
    required this.buildReport,
    required this.schedule,
    required this.deviceAssignments,
    required this.deviceInventoryDigest,
    required this.sourceDigest,
    required this.cleanFullRun,
    required this.diagnosticContinuation,
    required this.errors,
  });

  final SimsPlan plan;
  final Set<String> selectedIds;
  final Set<String> attemptedIds;
  final Set<String> terminalIds;
  final Map<String, SimsVerdict> verdictsById;
  final SimsReleaseAssessment computedAssessment;
  final SimsBuildReport buildReport;
  final SimsAuditedSchedule? schedule;
  final Map<String, String> deviceAssignments;
  final String? deviceInventoryDigest;
  final String? sourceDigest;
  final bool cleanFullRun;
  final bool diagnosticContinuation;
  final List<String> errors;

  bool get isValid => errors.isEmpty;
}

/// Audits an execution report from primitive evidence. Serialized selected /
/// terminal sets, release assessment, validationErrors, and schedule summaries
/// are compared with independently reconstructed values and never treated as
/// authoritative.
SimsReportAudit auditSimsReportJson(
  Map<String, Object?> json, {
  String? expectedManifestDigest,
  String? expectedSourceDigest,
}) {
  final errors = <String>[];
  if (json['schemaVersion'] != 1) {
    errors.add('report schemaVersion must be 1');
  }
  final generatedAt = json['generatedAt'];
  if (generatedAt is! String || DateTime.tryParse(generatedAt) == null) {
    errors.add('report.generatedAt must be an ISO-8601 timestamp');
  }

  final plan = SimsPlan.fromJson(_auditObject(json['plan'], 'report.plan'));
  errors.addAll(SimsScheduler().validate(plan));
  if (!_isSha256(plan.manifestDigest)) {
    errors.add('report plan manifestDigest is not a SHA-256 digest');
  }
  if (expectedManifestDigest != null &&
      plan.manifestDigest != expectedManifestDigest) {
    errors.add('report manifest digest does not match current manifest');
  }
  final planObject = _auditObject(json['plan'], 'report.plan');
  if (planObject['schemaVersion'] != 1) {
    errors.add('report plan schemaVersion must be 1');
  }
  if (planObject.containsKey('selectedIds')) {
    final declaredPlanIds = _auditUniqueStringSet(
      planObject['selectedIds'],
      'report.plan.selectedIds',
      errors,
    );
    if (!_sameSet(declaredPlanIds, plan.selectedIds)) {
      errors.add('plan selectedIds do not match plan rows');
    }
  } else {
    errors.add('report plan selectedIds are required');
  }

  final selected = _auditUniqueStringSet(
    json['selectedIds'],
    'report.selectedIds',
    errors,
  );
  final attempted = _auditUniqueStringSet(
    json['attemptedIds'],
    'report.attemptedIds',
    errors,
  );
  final declaredTerminal = _auditUniqueStringSet(
    json['terminalIds'],
    'report.terminalIds',
    errors,
  );
  if (!_sameSet(selected, plan.selectedIds)) {
    errors.add('report selectedIds do not match plan rows');
  }

  final verdicts = <SimsVerdict>[];
  final verdictById = <String, SimsVerdict>{};
  for (final item in _auditObjectList(json['verdicts'], 'report.verdicts')) {
    final verdict = _auditVerdict(item, 'report.verdicts[]');
    verdicts.add(verdict);
    if (verdictById.containsKey(verdict.capabilityId)) {
      errors.add('duplicate verdict ID: ${verdict.capabilityId}');
    } else {
      verdictById[verdict.capabilityId] = verdict;
    }
  }
  final derivedTerminal = verdictById.keys.toSet();
  if (!_sameSet(declaredTerminal, derivedTerminal)) {
    errors.add('report terminalIds do not match parsed verdicts');
  }
  if (!_sameSet(selected, attempted) || !_sameSet(selected, derivedTerminal)) {
    errors.add('selected, attempted, and terminal IDs do not reconcile');
  }
  for (final id in verdictById.keys) {
    if (!plan.selectedIds.contains(id)) {
      errors.add('verdict references unselected capability: $id');
    }
  }

  final cleanFullRun = _auditBool(json, 'cleanFullRun');
  final diagnosticContinuation = _auditBool(json, 'diagnosticContinuation');
  final computedAssessment = SimsVerdictEvaluator().evaluate(
    plan: plan,
    attemptedIds: attempted,
    verdicts: verdicts,
    cleanFullRun: cleanFullRun,
    diagnosticContinuation: diagnosticContinuation,
  );
  _auditSerializedAssessment(json['assessment'], computedAssessment, errors);

  final rowById = <String, CapabilitySpec>{
    for (final row in plan.rows) row.id: row,
  };
  for (final verdict in verdicts) {
    final row = rowById[verdict.capabilityId];
    if (row == null) continue;
    if (verdict.status == SimsVerdictStatus.notApplicable &&
        (verdict.blocker != SimsBlockerKind.targetUnavailable ||
            verdict.reason != targetUnavailableNaReason ||
            verdict.targetCapabilityAvailable != false ||
            row.allowedNaReason != targetUnavailableNaReason)) {
      errors.add(
        '${row.id} has invalid N/A evidence; targetUnavailable blocker, '
        'policy reason, unavailable target, and row allowance are required',
      );
    }
  }
  errors.addAll(validateSimsRuntimeArtifactEvidence(plan, verdictById));

  final buildReport = SimsBuildReport.fromJson(
    _auditObject(json['builds'], 'report.builds'),
  );
  _auditBuildReport(plan, buildReport, errors);

  final devices = _auditObject(json['devices'], 'report.devices');
  final assignments = _auditStringMap(
    devices['assignments'],
    'report.devices.assignments',
  );
  final inventoryDigest = devices['inventoryDigest'];
  if (inventoryDigest != null && inventoryDigest is! String) {
    throw const FormatException(
      'report.devices.inventoryDigest must be a string',
    );
  }
  _auditDeviceAssignments(
    plan,
    verdictById,
    assignments,
    inventoryDigest as String?,
    errors,
  );

  final sourceDigestValue = json['sourceDigest'];
  final sourceDigest =
      sourceDigestValue is String && sourceDigestValue.isNotEmpty
      ? sourceDigestValue
      : null;
  if (sourceDigest == null) {
    errors.add('report sourceDigest is required');
  } else if (!_isSha256(sourceDigest)) {
    errors.add('report sourceDigest is not a SHA-256 digest');
  }
  if (sourceDigest != null &&
      expectedSourceDigest != null &&
      sourceDigest != expectedSourceDigest) {
    errors.add('report source digest does not match current source');
  }

  SimsAuditedSchedule? schedule;
  if (json['schedule'] == null) {
    errors.add('report has no schedule evidence');
  } else {
    schedule = _auditSchedule(
      _auditObject(json['schedule'], 'report.schedule'),
      plan,
      verdictById,
      attempted,
      cleanFullRun,
      errors,
    );
  }

  final serializedValidationErrors = json['validationErrors'];
  if (serializedValidationErrors is! List ||
      serializedValidationErrors.any((item) => item is! String)) {
    throw const FormatException(
      'report.validationErrors must be a string array',
    );
  }
  if (serializedValidationErrors.isNotEmpty) {
    errors.add('report producer recorded validation errors');
  }

  return SimsReportAudit(
    plan: plan,
    selectedIds: Set<String>.unmodifiable(selected),
    attemptedIds: Set<String>.unmodifiable(attempted),
    terminalIds: Set<String>.unmodifiable(derivedTerminal),
    verdictsById: Map<String, SimsVerdict>.unmodifiable(verdictById),
    computedAssessment: computedAssessment,
    buildReport: buildReport,
    schedule: schedule,
    deviceAssignments: Map<String, String>.unmodifiable(assignments),
    deviceInventoryDigest: inventoryDigest,
    sourceDigest: sourceDigest,
    cleanFullRun: cleanFullRun,
    diagnosticContinuation: diagnosticContinuation,
    errors: List<String>.unmodifiable(errors),
  );
}

/// Re-verifies durable proof files represented by artifact-required PASS
/// verdicts. Build preparation rows are exempt because their artifacts are
/// independently covered by the central build report and cache attestation.
List<String> validateSimsRuntimeArtifactEvidence(
  SimsPlan plan,
  Map<String, SimsVerdict> verdictsById,
) {
  final errors = <String>[];
  for (final row in plan.rows) {
    if (!row.artifactRequired || _isBuildPreparationRow(row)) continue;
    final verdict = verdictsById[row.id];
    if (verdict == null || verdict.status != SimsVerdictStatus.pass) continue;
    final evidence = verdict.artifactEvidence;
    if (!verdict.artifactPresent || evidence == null) {
      errors.add(
        '${row.id} PASS has no durable artifact path, SHA-256, and validator binding',
      );
      continue;
    }
    final audit = auditSimsArtifactEvidence(
      evidence: evidence,
      expectedValidatorIds: row.artifactValidators,
    );
    if (!audit.isValid) {
      errors.add('${row.id} artifact evidence is invalid: ${audit.detail}');
    }
  }
  return List<String>.unmodifiable(errors);
}

bool _isBuildPreparationRow(CapabilitySpec row) =>
    row.command.isNotEmpty && row.command.first == '@prepare-build';

void _auditSerializedAssessment(
  Object? value,
  SimsReleaseAssessment computed,
  List<String> errors,
) {
  final serialized = _auditObject(value, 'report.assessment');
  if (serialized['releaseEligible'] is! bool ||
      serialized['releaseEligible'] != computed.releaseEligible) {
    errors.add('serialized releaseEligible differs from reconstructed result');
  }
  if (serialized['reconciled'] is! bool ||
      serialized['reconciled'] != computed.reconciled) {
    errors.add('serialized reconciled differs from reconstructed result');
  }
  final reasons = _auditStringList(
    serialized['reasons'],
    'report.assessment.reasons',
  );
  if (!_sameOrderedStrings(reasons, computed.reasons)) {
    errors.add(
      'serialized assessment reasons differ from reconstructed result',
    );
  }
  final selected = _auditUniqueStringSet(
    serialized['selectedIds'],
    'report.assessment.selectedIds',
    errors,
  );
  final attempted = _auditUniqueStringSet(
    serialized['attemptedIds'],
    'report.assessment.attemptedIds',
    errors,
  );
  final terminal = _auditUniqueStringSet(
    serialized['terminalIds'],
    'report.assessment.terminalIds',
    errors,
  );
  if (!_sameSet(selected, computed.selectedIds) ||
      !_sameSet(attempted, computed.attemptedIds) ||
      !_sameSet(terminal, computed.terminalIds)) {
    errors.add('serialized assessment IDs differ from reconstructed result');
  }
}

void _auditBuildReport(
  SimsPlan plan,
  SimsBuildReport report,
  List<String> errors,
) {
  for (final entry in <String, int>{
    'requestedProfiles': report.requestedProfiles,
    'actualBuilds': report.actualBuilds,
    'hits': report.hits,
    'misses': report.misses,
  }.entries) {
    if (entry.value < 0) errors.add('build ${entry.key} cannot be negative');
  }
  if (report.hits + report.misses != report.requestedProfiles) {
    errors.add('build hits + misses must equal requestedProfiles');
  }
  if (report.actualBuilds > report.misses) {
    errors.add('actualBuilds cannot exceed cache misses');
  }
  if (report.artifactDigests.length != report.hits + report.actualBuilds) {
    errors.add(
      'artifact digest count must equal cache hits plus actual builds',
    );
  }

  final buildRows = plan.rows.where(
    (row) => row.command.isNotEmpty && row.command.first == '@prepare-build',
  );
  final buildProfiles = buildRows.map((row) => row.buildProfileId).toSet();
  if (report.requestedProfiles > buildProfiles.length) {
    errors.add('requestedProfiles exceeds selected unique build profiles');
  }
  for (final entry in report.artifactDigests.entries) {
    if (!buildProfiles.contains(entry.key)) {
      errors.add('artifact digest references unselected profile: ${entry.key}');
    }
    if (!_isSha256(entry.value)) {
      errors.add('artifact digest for ${entry.key} is not SHA-256');
    }
  }
  final exceptionProfiles = buildRows
      .where((row) => row.declaredBuildException)
      .map((row) => row.buildProfileId)
      .toSet();
  if (report.declaredExceptions.toSet().length !=
      report.declaredExceptions.length) {
    errors.add('declared build exceptions contain duplicates');
  }
  for (final profile in report.declaredExceptions) {
    if (!exceptionProfiles.contains(profile)) {
      errors.add('undeclared build exception in report: $profile');
    }
  }
  for (final profile in report.artifactDigests.keys) {
    if (exceptionProfiles.contains(profile) &&
        !report.declaredExceptions.contains(profile)) {
      errors.add('build exception artifact was not declared: $profile');
    }
  }
  if (report.invalidations.any((reason) => reason.trim().isEmpty)) {
    errors.add('build invalidation reasons must be nonempty');
  }
  if (report.totalElapsedMs < 0 ||
      report.profileElapsedMs.values.any((value) => value < 0)) {
    errors.add('build elapsed times cannot be negative');
  }
  final outcomeIds = <String>[
    ...report.builtProfileIds,
    ...report.cacheHitProfileIds,
    ...report.failedProfileIds,
  ];
  if (outcomeIds.isNotEmpty) {
    if (outcomeIds.toSet().length != outcomeIds.length) {
      errors.add('build outcome profile IDs overlap or contain duplicates');
    }
    if (report.builtProfileIds.length != report.actualBuilds) {
      errors.add('builtProfileIds count must equal actualBuilds');
    }
    if (report.cacheHitProfileIds.length != report.hits) {
      errors.add('cacheHitProfileIds count must equal hits');
    }
    if (report.failedProfileIds.length != report.misses - report.actualBuilds) {
      errors.add('failedProfileIds count must equal failed cache misses');
    }
    if (outcomeIds.length != report.requestedProfiles) {
      errors.add('build outcome profile IDs must cover requestedProfiles');
    }
  }
  for (final profile in <String>{
    ...outcomeIds,
    ...report.profileElapsedMs.keys,
  }) {
    if (!buildProfiles.contains(profile)) {
      errors.add(
        'build timing/outcome references unselected profile: $profile',
      );
    }
  }
  if (report.profileElapsedMs.isNotEmpty &&
      report.profileElapsedMs.keys.toSet().length != report.requestedProfiles) {
    errors.add('build profileElapsedMs must cover requestedProfiles');
  }
}

void _auditDeviceAssignments(
  SimsPlan plan,
  Map<String, SimsVerdict> verdictById,
  Map<String, String> assignments,
  String? inventoryDigest,
  List<String> errors,
) {
  for (final entry in assignments.entries) {
    if ((!entry.key.startsWith('device:') &&
            !entry.key.startsWith('device-control:')) ||
        entry.value.trim().isEmpty) {
      errors.add('invalid device assignment: ${entry.key}');
    }
  }

  var executedDeviceRow = false;
  for (final row in plan.rows) {
    final locks = row.resources
        .where(
          (lock) =>
              lock.name.startsWith('device:') ||
              lock.name.startsWith('device-control:'),
        )
        .toList(growable: false);
    if (locks.isEmpty) continue;
    final verdict = verdictById[row.id];
    if (verdict == null) continue;
    final usedTarget =
        verdict.status == SimsVerdictStatus.pass ||
        verdict.assertionsAttempted > 0 ||
        verdict.blocker == SimsBlockerKind.deviceLost;
    if (!usedTarget) continue;
    executedDeviceRow = true;
    for (final lock in locks) {
      final target = lock.name.substring(lock.name.indexOf(':') + 1);
      final hasAssignment =
          assignments.containsKey(lock.name) ||
          assignments.values.contains(target);
      if (!hasAssignment) {
        errors.add('${row.id} has no reported assignment for ${lock.name}');
      }
    }
  }
  if (executedDeviceRow) {
    if (inventoryDigest == null || !_isSha256(inventoryDigest)) {
      errors.add(
        'executed device rows require a SHA-256 device inventory digest',
      );
    }
  } else if (inventoryDigest != null && !_isSha256(inventoryDigest)) {
    errors.add('device inventory digest is not SHA-256');
  }
}

SimsAuditedSchedule _auditSchedule(
  Map<String, Object?> json,
  SimsPlan plan,
  Map<String, SimsVerdict> outerVerdicts,
  Set<String> outerAttempted,
  bool cleanFullRun,
  List<String> errors,
) {
  final selected = _auditUniqueStringSet(
    json['selectedIds'],
    'report.schedule.selectedIds',
    errors,
  );
  final attempted = _auditUniqueStringSet(
    json['attemptedIds'],
    'report.schedule.attemptedIds',
    errors,
  );
  final declaredTerminal = _auditUniqueStringSet(
    json['terminalIds'],
    'report.schedule.terminalIds',
    errors,
  );
  if (!plan.selectedIds.containsAll(selected)) {
    errors.add('schedule contains capabilities outside the report plan');
  }
  if (!_sameSet(selected, attempted) || !_sameSet(selected, declaredTerminal)) {
    errors.add('schedule selected, attempted, and terminal IDs differ');
  }

  final verdictById = <String, SimsVerdict>{};
  for (final item in _auditObjectList(
    json['verdicts'],
    'report.schedule.verdicts',
  )) {
    final verdict = _auditVerdict(item, 'report.schedule.verdicts[]');
    if (verdictById.containsKey(verdict.capabilityId)) {
      errors.add('duplicate schedule verdict ID: ${verdict.capabilityId}');
    } else {
      verdictById[verdict.capabilityId] = verdict;
    }
  }
  if (!_sameSet(verdictById.keys.toSet(), declaredTerminal)) {
    errors.add('schedule terminalIds do not match schedule verdicts');
  }
  for (final entry in verdictById.entries) {
    final outer = outerVerdicts[entry.key];
    if (outer == null || !_sameVerdict(outer, entry.value)) {
      errors.add('schedule verdict differs from report verdict: ${entry.key}');
    }
  }

  final rowById = <String, CapabilitySpec>{
    for (final row in plan.rows) row.id: row,
  };
  final traces = <String, SimsAuditedTrace>{};
  for (final item in _auditObjectList(
    json['traces'],
    'report.schedule.traces',
  )) {
    final id = item['capabilityId'];
    if (id is! String || id.isEmpty) {
      throw const FormatException(
        'schedule trace capabilityId must be a nonempty string',
      );
    }
    final startedAt = _auditDateTime(item['startedAt'], 'trace.startedAt');
    final endedAt = _auditDateTime(item['endedAt'], 'trace.endedAt');
    if (endedAt.isBefore(startedAt)) {
      errors.add('schedule trace ends before it starts: $id');
    }
    final waitMs = item['dependencyWaitMs'];
    if (waitMs is! int || waitMs < 0) {
      throw FormatException(
        'schedule trace dependencyWaitMs must be nonnegative: $id',
      );
    }
    final resources = _auditObjectList(
      item['resources'],
      'report.schedule.traces[].resources',
    ).map(ResourceLock.fromJson).toList(growable: false);
    if (traces.containsKey(id)) {
      errors.add('duplicate schedule trace ID: $id');
      continue;
    }
    final row = rowById[id];
    if (row == null) {
      errors.add('schedule trace references unselected capability: $id');
    } else if (!_sameResourceLocks(resources, row.resources)) {
      errors.add('schedule trace resources differ from plan row: $id');
    }
    traces[id] = SimsAuditedTrace(
      capabilityId: id,
      startedAt: startedAt,
      endedAt: endedAt,
      dependencyWait: Duration(milliseconds: waitMs),
      resources: List<ResourceLock>.unmodifiable(resources),
    );
  }
  if (!_sameSet(traces.keys.toSet(), selected)) {
    errors.add('schedule traces are incomplete or contain extra IDs');
  }

  if (cleanFullRun) {
    if (!_sameSet(selected, plan.selectedIds) ||
        !_sameSet(attempted, outerAttempted)) {
      errors.add('clean full run schedule does not cover the complete report');
    }
  } else if (!outerAttempted.containsAll(attempted)) {
    errors.add('schedule attempted IDs are absent from the report');
  }

  for (final row in plan.rows) {
    final trace = traces[row.id];
    if (trace == null) continue;
    for (final dependency in row.dependencies) {
      final dependencyTrace = traces[dependency];
      if (dependencyTrace != null &&
          trace.startedAt.isBefore(dependencyTrace.endedAt)) {
        errors.add('${row.id} started before dependency $dependency ended');
      }
    }
  }

  final traceList = traces.values.toList(growable: false);
  for (var leftIndex = 0; leftIndex < traceList.length; leftIndex++) {
    for (
      var rightIndex = leftIndex + 1;
      rightIndex < traceList.length;
      rightIndex++
    ) {
      final leftTrace = traceList[leftIndex];
      final rightTrace = traceList[rightIndex];
      if (!_tracesOverlap(leftTrace, rightTrace)) continue;
      final leftRow = rowById[leftTrace.capabilityId];
      final rightRow = rowById[rightTrace.capabilityId];
      if (leftRow == null || rightRow == null) continue;
      if (!plan.simultaneous) {
        errors.add('serial schedule overlaps ${leftRow.id} and ${rightRow.id}');
      }
      if (!resourcesAreCompatible(leftRow, rightRow)) {
        errors.add(
          'conflicting schedule locks overlap: ${leftRow.id} and ${rightRow.id}',
        );
      }
    }
  }

  final maxObserved = json['maxObservedConcurrency'];
  if (maxObserved is! int || maxObserved < 0) {
    throw const FormatException(
      'report.schedule.maxObservedConcurrency must be nonnegative',
    );
  }
  final reconstructedMax = _maxTraceConcurrency(traceList);
  if (maxObserved != reconstructedMax) {
    errors.add(
      'maxObservedConcurrency is $maxObserved, reconstructed '
      'as $reconstructedMax',
    );
  }

  return SimsAuditedSchedule(
    selectedIds: Set<String>.unmodifiable(selected),
    attemptedIds: Set<String>.unmodifiable(attempted),
    terminalIds: Set<String>.unmodifiable(declaredTerminal),
    verdictsById: Map<String, SimsVerdict>.unmodifiable(verdictById),
    tracesById: Map<String, SimsAuditedTrace>.unmodifiable(traces),
    maxObservedConcurrency: maxObserved,
  );
}

SimsVerdict _auditVerdict(Map<String, Object?> json, String label) {
  try {
    return SimsVerdict.fromJson(json);
  } on Object catch (error) {
    throw FormatException('$label is invalid: $error');
  }
}

bool _sameVerdict(SimsVerdict left, SimsVerdict right) =>
    jsonEncode(left.toJson()) == jsonEncode(right.toJson());

bool _sameResourceLocks(List<ResourceLock> left, List<ResourceLock> right) {
  if (left.length != right.length) return false;
  final leftValues = left.map((lock) => lock.toString()).toList()..sort();
  final rightValues = right.map((lock) => lock.toString()).toList()..sort();
  return _sameOrderedStrings(leftValues, rightValues);
}

bool _tracesOverlap(SimsAuditedTrace left, SimsAuditedTrace right) =>
    left.startedAt.isBefore(right.endedAt) &&
    right.startedAt.isBefore(left.endedAt);

int _maxTraceConcurrency(List<SimsAuditedTrace> traces) {
  var maximum = 0;
  for (final candidate in traces) {
    if (!candidate.endedAt.isAfter(candidate.startedAt)) continue;
    var running = 0;
    for (final trace in traces) {
      if (!trace.endedAt.isAfter(trace.startedAt)) continue;
      if (!trace.startedAt.isAfter(candidate.startedAt) &&
          trace.endedAt.isAfter(candidate.startedAt)) {
        running += 1;
      }
    }
    if (running > maximum) maximum = running;
  }
  return maximum;
}

Map<String, Object?> _auditObject(Object? value, String label) {
  if (value is! Map) throw FormatException('$label must be an object');
  return value.map<String, Object?>((key, item) => MapEntry('$key', item));
}

List<Map<String, Object?>> _auditObjectList(Object? value, String label) {
  if (value is! List) throw FormatException('$label must be an array');
  return value
      .map((item) => _auditObject(item, '$label[]'))
      .toList(growable: false);
}

List<String> _auditStringList(Object? value, String label) {
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('$label must be a string array');
  }
  return List<String>.unmodifiable(value.cast<String>());
}

Set<String> _auditUniqueStringSet(
  Object? value,
  String label,
  List<String> errors,
) {
  final items = _auditStringList(value, label);
  final result = items.toSet();
  if (result.length != items.length) errors.add('$label contains duplicates');
  return result;
}

Map<String, String> _auditStringMap(Object? value, String label) {
  if (value is! Map ||
      value.entries.any(
        (entry) => entry.key is! String || entry.value is! String,
      )) {
    throw FormatException('$label must be a string map');
  }
  return Map<String, String>.unmodifiable(value.cast<String, String>());
}

Map<String, int> _auditIntMap(Object? value, String label) {
  if (value is! Map ||
      value.entries.any(
        (entry) => entry.key is! String || entry.value is! int,
      )) {
    throw FormatException('$label must be an integer map');
  }
  return Map<String, int>.unmodifiable(value.cast<String, int>());
}

int _auditInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('builds.$key must be an integer');
  return value;
}

bool _auditBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('report.$key must be a boolean');
  return value;
}

DateTime _auditDateTime(Object? value, String label) {
  if (value is! String) throw FormatException('$label must be a timestamp');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('$label must be a timestamp');
  return parsed.toUtc();
}

bool _isSha256(String value) => RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);

bool _sameOrderedStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

List<String> redactCommand(List<String> command) {
  final output = <String>[];
  var redactNext = false;
  for (final argument in command) {
    if (redactNext) {
      output.add(_hashedValue(argument));
      redactNext = false;
      continue;
    }
    final equals = argument.indexOf('=');
    if (equals > 0) {
      final key = argument.substring(0, equals);
      final value = argument.substring(equals + 1);
      if (_isSensitiveKey(key)) {
        output.add('$key=${_hashedValue(value)}');
      } else {
        output.add(argument);
      }
      continue;
    }
    output.add(argument);
    if (_isSensitiveKey(argument)) redactNext = true;
  }
  return List<String>.unmodifiable(output);
}

bool _isSensitiveKey(String key) {
  final normalized = key.toLowerCase().replaceAll('-', '').replaceAll('_', '');
  return const <String>{
    'token',
    'pushtoken',
    'waketoken',
    'secret',
    'password',
    'credential',
    'apikey',
    'signingkey',
  }.any(normalized.endsWith);
}

String _hashedValue(String value) =>
    'sha256:${sha256.convert(utf8.encode(value))}';

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);
