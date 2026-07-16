import 'artifact_evidence.dart';
import 'manifest.dart';
import 'planner.dart';

enum SimsVerdictStatus { pass, fail, blocked, skip, notApplicable }

extension SimsVerdictStatusName on SimsVerdictStatus {
  String get wireName => switch (this) {
    SimsVerdictStatus.pass => 'PASS',
    SimsVerdictStatus.fail => 'FAIL',
    SimsVerdictStatus.blocked => 'BLOCKED',
    SimsVerdictStatus.skip => 'SKIP',
    SimsVerdictStatus.notApplicable => 'N/A',
  };

  static SimsVerdictStatus parse(String value) => switch (value) {
    'PASS' => SimsVerdictStatus.pass,
    'FAIL' => SimsVerdictStatus.fail,
    'BLOCKED' => SimsVerdictStatus.blocked,
    'SKIP' => SimsVerdictStatus.skip,
    'N/A' => SimsVerdictStatus.notApplicable,
    _ => throw FormatException('Unknown sims verdict: $value'),
  };
}

enum SimsBlockerKind {
  targetUnavailable,
  credentials,
  permissions,
  missingArtifact,
  missingDriver,
  deviceLost,
  dependency,
  product,
  test,
  harness,
  environment,
  flake,
}

class SimsVerdict {
  const SimsVerdict({
    required this.capabilityId,
    required this.status,
    required this.assertionsAttempted,
    required this.exitCode,
    required this.artifactPresent,
    required this.printOnly,
    required this.blocker,
    required this.targetCapabilityAvailable,
    required this.reason,
    required this.detail,
    this.artifactEvidence,
  });

  factory SimsVerdict.fromJson(Map<String, Object?> json) => SimsVerdict(
    capabilityId: json['capabilityId']! as String,
    status: SimsVerdictStatusName.parse(json['status']! as String),
    assertionsAttempted: json['assertionsAttempted']! as int,
    exitCode: json['exitCode'] as int?,
    artifactPresent: json['artifactPresent']! as bool,
    printOnly: json['printOnly']! as bool,
    blocker: json['blocker'] == null
        ? null
        : SimsBlockerKind.values.byName(json['blocker']! as String),
    targetCapabilityAvailable: json['targetCapabilityAvailable'] as bool?,
    reason: json['reason'] as String?,
    detail: json['detail'] as String? ?? '',
    artifactEvidence: json['artifactEvidence'] == null
        ? null
        : SimsArtifactEvidence.fromJson(json['artifactEvidence']),
  );

  factory SimsVerdict.pass(
    String capabilityId, {
    required int assertionsAttempted,
    int exitCode = 0,
    bool artifactPresent = true,
    bool printOnly = false,
    String detail = '',
    SimsArtifactEvidence? artifactEvidence,
  }) => SimsVerdict(
    capabilityId: capabilityId,
    status: SimsVerdictStatus.pass,
    assertionsAttempted: assertionsAttempted,
    exitCode: exitCode,
    artifactPresent: artifactPresent,
    printOnly: printOnly,
    blocker: null,
    targetCapabilityAvailable: null,
    reason: null,
    detail: detail,
    artifactEvidence: artifactEvidence,
  );

  factory SimsVerdict.fail(
    String capabilityId, {
    int assertionsAttempted = 1,
    int exitCode = 1,
    SimsBlockerKind blocker = SimsBlockerKind.product,
    String detail = '',
  }) => SimsVerdict(
    capabilityId: capabilityId,
    status: SimsVerdictStatus.fail,
    assertionsAttempted: assertionsAttempted,
    exitCode: exitCode,
    artifactPresent: false,
    printOnly: false,
    blocker: blocker,
    targetCapabilityAvailable: null,
    reason: null,
    detail: detail,
  );

  factory SimsVerdict.blocked(
    String capabilityId, {
    required SimsBlockerKind blocker,
    String detail = '',
  }) => SimsVerdict(
    capabilityId: capabilityId,
    status: SimsVerdictStatus.blocked,
    assertionsAttempted: 0,
    exitCode: blocker == SimsBlockerKind.missingDriver ? 78 : null,
    artifactPresent: false,
    printOnly: false,
    blocker: blocker,
    targetCapabilityAvailable: null,
    reason: null,
    detail: detail,
  );

  factory SimsVerdict.skip(String capabilityId, {String detail = ''}) =>
      SimsVerdict(
        capabilityId: capabilityId,
        status: SimsVerdictStatus.skip,
        assertionsAttempted: 0,
        exitCode: 0,
        artifactPresent: false,
        printOnly: false,
        blocker: null,
        targetCapabilityAvailable: null,
        reason: null,
        detail: detail,
      );

  factory SimsVerdict.notApplicable(
    String capabilityId, {
    required SimsBlockerKind blocker,
    required bool targetCapabilityAvailable,
    required String reason,
    String detail = '',
  }) => SimsVerdict(
    capabilityId: capabilityId,
    status: SimsVerdictStatus.notApplicable,
    assertionsAttempted: 0,
    exitCode: null,
    artifactPresent: false,
    printOnly: false,
    blocker: blocker,
    targetCapabilityAvailable: targetCapabilityAvailable,
    reason: reason,
    detail: detail,
  );

  final String capabilityId;
  final SimsVerdictStatus status;
  final int assertionsAttempted;
  final int? exitCode;
  final bool artifactPresent;
  final bool printOnly;
  final SimsBlockerKind? blocker;
  final bool? targetCapabilityAvailable;
  final String? reason;
  final String detail;
  final SimsArtifactEvidence? artifactEvidence;

  bool satisfies(CapabilitySpec capability) {
    if (status == SimsVerdictStatus.pass) {
      return exitCode == 0 &&
          assertionsAttempted > 0 &&
          !printOnly &&
          blocker == null &&
          targetCapabilityAvailable == null &&
          reason == null &&
          (!capability.artifactRequired ||
              (artifactPresent &&
                  (capability.command.first == '@prepare-build' ||
                      artifactEvidence != null)));
    }
    if (status == SimsVerdictStatus.notApplicable) {
      return (exitCode == null || exitCode == 0) &&
          assertionsAttempted == 0 &&
          !artifactPresent &&
          !printOnly &&
          artifactEvidence == null &&
          capability.allowedNaReason == targetUnavailableNaReason &&
          reason == targetUnavailableNaReason &&
          blocker == SimsBlockerKind.targetUnavailable &&
          targetCapabilityAvailable == false;
    }
    return false;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'capabilityId': capabilityId,
    'status': status.wireName,
    'assertionsAttempted': assertionsAttempted,
    if (exitCode != null) 'exitCode': exitCode,
    'artifactPresent': artifactPresent,
    'printOnly': printOnly,
    if (blocker != null) 'blocker': blocker!.name,
    if (targetCapabilityAvailable != null)
      'targetCapabilityAvailable': targetCapabilityAvailable,
    if (reason != null) 'reason': reason,
    if (detail.isNotEmpty) 'detail': detail,
    if (artifactEvidence != null)
      'artifactEvidence': artifactEvidence!.toJson(),
  };
}

class SimsReleaseAssessment {
  const SimsReleaseAssessment({
    required this.releaseEligible,
    required this.reconciled,
    required this.reasons,
    required this.selectedIds,
    required this.attemptedIds,
    required this.terminalIds,
  });

  final bool releaseEligible;
  final bool reconciled;
  final List<String> reasons;
  final Set<String> selectedIds;
  final Set<String> attemptedIds;
  final Set<String> terminalIds;

  Map<String, Object?> toJson() => <String, Object?>{
    'releaseEligible': releaseEligible,
    'reconciled': reconciled,
    'reasons': reasons,
    'selectedIds': selectedIds.toList()..sort(),
    'attemptedIds': attemptedIds.toList()..sort(),
    'terminalIds': terminalIds.toList()..sort(),
  };
}

class SimsVerdictEvaluator {
  const SimsVerdictEvaluator();

  SimsReleaseAssessment evaluate({
    required SimsPlan plan,
    required Iterable<String> attemptedIds,
    required List<SimsVerdict> verdicts,
    required bool cleanFullRun,
    bool diagnosticContinuation = false,
  }) {
    final reasons = <String>[];
    final selected = plan.selectedIds;
    final attempted = attemptedIds.toSet();
    final terminal = verdicts.map((verdict) => verdict.capabilityId).toSet();
    final reconciled =
        _sameSet(selected, attempted) &&
        _sameSet(selected, terminal) &&
        terminal.length == verdicts.length;

    if (!reconciled) {
      reasons.add('selected, attempted, and terminal capability IDs differ');
    }
    if (!plan.releaseEligibleCandidate) {
      reasons.add(
        'filtered, partial, smoke, or full plan is not release eligible',
      );
    }
    if (!cleanFullRun) {
      reasons.add(
        'retry/resume evidence requires a final clean full major run',
      );
    }
    if (diagnosticContinuation) {
      reasons.add('diagnostic continuation cannot produce release green');
    }

    final verdictById = <String, SimsVerdict>{
      for (final verdict in verdicts) verdict.capabilityId: verdict,
    };
    for (final capability in plan.rows.where((row) => row.required)) {
      final verdict = verdictById[capability.id];
      if (verdict == null) continue;
      if (!verdict.satisfies(capability)) {
        reasons.add(
          '${capability.id} ended ${verdict.status.wireName} without required evidence',
        );
      }
    }

    return SimsReleaseAssessment(
      releaseEligible: reasons.isEmpty,
      reconciled: reconciled,
      reasons: List<String>.unmodifiable(reasons),
      selectedIds: Set<String>.unmodifiable(selected),
      attemptedIds: Set<String>.unmodifiable(attempted),
      terminalIds: Set<String>.unmodifiable(terminal),
    );
  }
}

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);
