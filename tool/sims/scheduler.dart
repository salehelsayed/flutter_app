import 'dart:async';

import 'manifest.dart';
import 'planner.dart';
import 'verdict.dart';

typedef SimsTaskExecutor = Future<SimsVerdict> Function(CapabilitySpec row);

class _SimsTaskOutcome {
  const _SimsTaskOutcome({
    required this.row,
    required this.verdict,
    required this.trace,
  });

  final CapabilitySpec row;
  final SimsVerdict verdict;
  final SimsScheduleTrace trace;
}

class SimsScheduleTrace {
  const SimsScheduleTrace({
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

  Map<String, Object?> toJson() => <String, Object?>{
    'capabilityId': capabilityId,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'endedAt': endedAt.toUtc().toIso8601String(),
    'dependencyWaitMs': dependencyWait.inMilliseconds,
    'resources': resources.map((resource) => resource.toJson()).toList(),
  };
}

class SimsScheduleResult {
  const SimsScheduleResult({
    required this.selectedIds,
    required this.attemptedIds,
    required this.verdicts,
    required this.traces,
    required this.maxObservedConcurrency,
    this.causalFailureId,
  });

  final Set<String> selectedIds;
  final Set<String> attemptedIds;
  final List<SimsVerdict> verdicts;
  final List<SimsScheduleTrace> traces;
  final int maxObservedConcurrency;
  final String? causalFailureId;

  Set<String> get terminalIds =>
      verdicts.map((verdict) => verdict.capabilityId).toSet();

  Map<String, Object?> toJson() => <String, Object?>{
    'selectedIds': selectedIds.toList()..sort(),
    'attemptedIds': attemptedIds.toList()..sort(),
    'terminalIds': terminalIds.toList()..sort(),
    'maxObservedConcurrency': maxObservedConcurrency,
    if (causalFailureId != null) 'causalFailureId': causalFailureId,
    'verdicts': verdicts.map((verdict) => verdict.toJson()).toList(),
    'traces': traces.map((trace) => trace.toJson()).toList(),
  };
}

class SimsScheduler {
  const SimsScheduler({this.maxParallel = 4, this.hostCapacity = 4})
    : assert(maxParallel > 0),
      assert(hostCapacity > 0);

  final int maxParallel;
  final int hostCapacity;

  List<String> validate(SimsPlan plan) {
    final errors = <String>[];
    final ids = plan.selectedIds;
    for (final row in plan.rows) {
      if (row.resources.isEmpty && plan.mode == SimsMode.major) {
        errors.add('${row.id} has no resource metadata');
      }
      if (plan.mode == SimsMode.major &&
          row.resources.any((resource) => resource.name == 'unknown')) {
        errors.add('${row.id} has unknown resource metadata');
      }
      for (final resource in row.resources) {
        if (!isKnownSimsResourceName(resource.name)) {
          errors.add('${row.id} has invalid resource ${resource.name}');
        }
      }
      for (final dependency in row.dependencies) {
        if (!ids.contains(dependency)) {
          errors.add('${row.id} depends on unselected row $dependency');
        }
      }
    }

    final remaining = <String, Set<String>>{
      for (final row in plan.rows) row.id: row.dependencies.toSet(),
    };
    while (remaining.isNotEmpty) {
      final ready = remaining.entries
          .where((entry) => entry.value.isEmpty)
          .map((entry) => entry.key)
          .toList();
      if (ready.isEmpty) {
        errors.add('capability dependency graph contains a cycle');
        break;
      }
      for (final id in ready) {
        remaining.remove(id);
        for (final dependencies in remaining.values) {
          dependencies.remove(id);
        }
      }
    }
    return errors;
  }

  void validateOrThrow(SimsPlan plan) {
    final errors = validate(plan);
    if (errors.isNotEmpty) throw StateError(errors.join('\n'));
  }

  Future<SimsScheduleResult> run(
    SimsPlan plan, {
    required bool simultaneous,
    required SimsTaskExecutor executor,
    bool continueOnFailure = false,
  }) async {
    validateOrThrow(plan);
    final runStartedAt = DateTime.now();
    final pending = <String, CapabilitySpec>{
      for (final row in plan.rows) row.id: row,
    };
    final rowById = <String, CapabilitySpec>{
      for (final row in plan.rows) row.id: row,
    };
    final verdictById = <String, SimsVerdict>{};
    final attempted = <String>{};
    final traces = <SimsScheduleTrace>[];
    final syntheticBlockedRows = <CapabilitySpec>[];
    final active = <String, Future<_SimsTaskOutcome>>{};
    var failFastTriggered = false;
    String? causalFailureId;
    var maxRunning = 0;
    final limit = simultaneous ? maxParallel : 1;

    void addSyntheticBlocked(CapabilitySpec row, String detail) {
      attempted.add(row.id);
      verdictById[row.id] = SimsVerdict.blocked(
        row.id,
        blocker: SimsBlockerKind.dependency,
        detail: detail,
      );
      syntheticBlockedRows.add(row);
      pending.remove(row.id);
    }

    String failFastDetail() {
      final causeId = causalFailureId;
      final cause = causeId == null ? null : verdictById[causeId];
      if (cause == null) {
        return 'Fail-fast stopped new work after a prior row did not satisfy '
            'its gate.';
      }
      final blocker = cause.blocker;
      final outcome = blocker == null
          ? cause.status.wireName
          : '${cause.status.wireName} (${blocker.name})';
      return 'Fail-fast stopped new work after ${cause.capabilityId} ended '
          '$outcome without satisfying its gate.';
    }

    void propagateDependencyBlocks() {
      var changed = true;
      while (changed) {
        changed = false;
        for (final row in pending.values.toList(growable: false)) {
          if (!row.dependencies.every(verdictById.containsKey)) continue;
          if (!row.dependencies.any(
            (dependency) =>
                !verdictById[dependency]!.satisfies(rowById[dependency]!),
          )) {
            continue;
          }
          addSyntheticBlocked(row, 'A required dependency did not pass.');
          changed = true;
        }
      }
    }

    Future<_SimsTaskOutcome> execute(CapabilitySpec row) async {
      final startedAt = DateTime.now();
      SimsVerdict verdict;
      try {
        verdict = await executor(row);
        if (verdict.capabilityId != row.id) {
          verdict = SimsVerdict.fail(
            row.id,
            blocker: SimsBlockerKind.harness,
            detail: 'Executor returned verdict for ${verdict.capabilityId}.',
          );
        }
      } on Object catch (error) {
        verdict = SimsVerdict.fail(
          row.id,
          blocker: SimsBlockerKind.harness,
          detail: 'Executor threw: $error',
        );
      }
      final endedAt = DateTime.now();
      return _SimsTaskOutcome(
        row: row,
        verdict: verdict,
        trace: SimsScheduleTrace(
          capabilityId: row.id,
          startedAt: startedAt,
          endedAt: endedAt,
          dependencyWait: startedAt.difference(runStartedAt),
          resources: row.resources,
        ),
      );
    }

    void launch(CapabilitySpec row) {
      pending.remove(row.id);
      attempted.add(row.id);
      active[row.id] = execute(row);
      if (active.length > maxRunning) maxRunning = active.length;
    }

    Future<void> commitNextOutcome() async {
      final outcome = await Future.any(active.values);
      active.remove(outcome.row.id);
      verdictById[outcome.row.id] = outcome.verdict;
      traces.add(outcome.trace);
      if (!outcome.verdict.satisfies(outcome.row)) {
        causalFailureId ??= outcome.row.id;
        failFastTriggered = true;
      }
    }

    while (pending.isNotEmpty || active.isNotEmpty) {
      if (failFastTriggered && !continueOnFailure) {
        if (active.isNotEmpty) {
          await commitNextOutcome();
          continue;
        }
        for (final row in pending.values.toList(growable: false)) {
          addSyntheticBlocked(row, failFastDetail());
        }
        break;
      }

      propagateDependencyBlocks();

      while (active.length < limit) {
        final activeRows = active.keys
            .map((id) => rowById[id]!)
            .toList(growable: false);
        final activeHostRows = activeRows.where(_usesHostCpu).length;
        CapabilitySpec? next;
        for (final candidate in pending.values) {
          if (!candidate.dependencies.every(verdictById.containsKey)) {
            continue;
          }
          if (_usesHostCpu(candidate) && activeHostRows >= hostCapacity) {
            continue;
          }
          if (activeRows.every(
            (running) => resourcesAreCompatible(running, candidate),
          )) {
            next = candidate;
            break;
          }
        }
        if (next == null) break;
        launch(next);
      }

      if (active.isNotEmpty) {
        await commitNextOutcome();
        continue;
      }
      if (pending.isNotEmpty) {
        throw StateError('Scheduler reached a dependency deadlock.');
      }
    }

    // Synthetic blockers are bookkeeping, not work. Timestamp them only after
    // every real task has drained so a zero-duration trace cannot appear to
    // overlap an unrelated active exclusive lock in report reconstruction.
    final syntheticAt = DateTime.now();
    for (final row in syntheticBlockedRows) {
      traces.add(
        SimsScheduleTrace(
          capabilityId: row.id,
          startedAt: syntheticAt,
          endedAt: syntheticAt,
          dependencyWait: syntheticAt.difference(runStartedAt),
          resources: row.resources,
        ),
      );
    }

    final orderedVerdicts = <SimsVerdict>[
      for (final row in plan.rows) verdictById[row.id]!,
    ];
    final planOrder = <String, int>{
      for (var index = 0; index < plan.rows.length; index += 1)
        plan.rows[index].id: index,
    };
    traces.sort(
      (left, right) => planOrder[left.capabilityId]!.compareTo(
        planOrder[right.capabilityId]!,
      ),
    );
    return SimsScheduleResult(
      selectedIds: Set<String>.unmodifiable(plan.selectedIds),
      attemptedIds: Set<String>.unmodifiable(attempted),
      verdicts: List<SimsVerdict>.unmodifiable(orderedVerdicts),
      traces: List<SimsScheduleTrace>.unmodifiable(traces),
      maxObservedConcurrency: maxRunning,
      causalFailureId: causalFailureId,
    );
  }
}

bool resourcesAreCompatible(CapabilitySpec left, CapabilitySpec right) {
  if (left.resources.isEmpty || right.resources.isEmpty) return false;
  if (_hasGlobalExclusive(left) || _hasGlobalExclusive(right)) return false;

  for (final leftLock in left.resources) {
    for (final rightLock in right.resources) {
      if (_sameLogicalResource(leftLock.name, rightLock.name) &&
          !(leftLock.access == ResourceAccess.read &&
              rightLock.access == ResourceAccess.read)) {
        return false;
      }
    }
  }
  return true;
}

bool _hasGlobalExclusive(CapabilitySpec row) => row.resources.any(
  (resource) =>
      resource.name == 'performance.global' || resource.name == 'unknown',
);

bool _sameLogicalResource(String left, String right) {
  if (left == right) return true;
  String? deviceId(String value) {
    for (final prefix in const <String>['device:', 'device-control:']) {
      if (value.startsWith(prefix)) return value.substring(prefix.length);
    }
    return null;
  }

  final leftDevice = deviceId(left);
  final rightDevice = deviceId(right);
  return leftDevice != null && leftDevice == rightDevice;
}

bool _usesHostCpu(CapabilitySpec row) =>
    row.resources.any((resource) => resource.name == 'host.cpu');

bool scheduleResultsAreEquivalent(
  SimsScheduleResult left,
  SimsScheduleResult right,
) {
  if (!_sameSet(left.selectedIds, right.selectedIds) ||
      !_sameSet(left.attemptedIds, right.attemptedIds) ||
      !_sameSet(left.terminalIds, right.terminalIds)) {
    return false;
  }
  final rightById = <String, SimsVerdict>{
    for (final verdict in right.verdicts) verdict.capabilityId: verdict,
  };
  return left.verdicts.every(
    (verdict) => rightById[verdict.capabilityId]?.status == verdict.status,
  );
}

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);
