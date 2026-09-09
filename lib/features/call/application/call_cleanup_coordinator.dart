import 'dart:collection';

import '../domain/call_id.dart';
import '../domain/call_session_snapshot.dart';

typedef CallCleanupAction = Future<void> Function(CallSessionSnapshot snapshot);
typedef CallCleanupReportObserver = void Function(CallCleanupReport report);

final class CallCleanupStep {
  const CallCleanupStep(
    this.name,
    this.action, {
    this.requiredForTerminalAck = false,
  });

  final String name;
  final CallCleanupAction action;
  final bool requiredForTerminalAck;
}

final class CallCleanupReport {
  const CallCleanupReport({
    this.callId,
    required this.completed,
    required this.alreadyCompleted,
    required this.terminalAckReady,
    required this.failedStepNames,
  });

  /// Private correlation only; never part of a diagnostic payload.
  final CallId? callId;
  final bool completed;
  final bool alreadyCompleted;
  final bool terminalAckReady;
  final List<String> failedStepNames;

  @override
  String toString() =>
      'CallCleanupReport(completed: $completed, '
      'alreadyCompleted: $alreadyCompleted, '
      'terminalAckReady: $terminalAckReady, '
      'failedSteps: $failedStepNames)';
}

/// Runs each successful release action at most once per call ID. Failures are
/// retained by fixed step index for bounded exact-call retry and never prevent
/// later actions from running.
final class CallCleanupCoordinator {
  CallCleanupCoordinator(
    List<CallCleanupStep> steps, {
    this.stepTimeout = const Duration(seconds: 5),
    this.completedTombstoneCapacity = 128,
    this.onReport,
  }) : _steps = List<CallCleanupStep>.unmodifiable(steps) {
    final validName = RegExp(r'^[a-z0-9_-]{1,64}$');
    if (_steps.any((step) => !validName.hasMatch(step.name)) ||
        _steps.map((step) => step.name).toSet().length != _steps.length ||
        stepTimeout <= Duration.zero ||
        completedTombstoneCapacity <= 0) {
      throw ArgumentError('cleanup step names must be fixed safe labels');
    }
  }

  final List<CallCleanupStep> _steps;
  final Duration stepTimeout;
  final int completedTombstoneCapacity;
  final CallCleanupReportObserver? onReport;
  final Set<CallId> _completed = <CallId>{};
  final ListQueue<CallId> _completedOrder = ListQueue<CallId>();
  final Map<CallId, Set<int>> _pendingStepIndexes = <CallId, Set<int>>{};
  final Map<CallId, Future<CallCleanupReport>> _inFlight =
      <CallId, Future<CallCleanupReport>>{};

  Future<CallCleanupReport> cleanup(CallSessionSnapshot snapshot) {
    final callId = snapshot.callId;
    if (callId == null) {
      return Future<CallCleanupReport>.error(
        StateError('cleanup requires an active call identity'),
      );
    }
    if (_completed.contains(callId)) {
      return Future<CallCleanupReport>.value(
        _observe(
          CallCleanupReport(
            callId: callId,
            completed: true,
            alreadyCompleted: true,
            terminalAckReady: true,
            failedStepNames: <String>[],
          ),
        ),
      );
    }
    final existing = _inFlight[callId];
    if (existing != null) return existing;
    if (!_pendingStepIndexes.containsKey(callId)) {
      if (_pendingStepIndexes.length >= completedTombstoneCapacity) {
        return Future<CallCleanupReport>.value(
          _observe(
            CallCleanupReport(
              callId: callId,
              completed: false,
              alreadyCompleted: false,
              terminalAckReady: false,
              failedStepNames: <String>['cleanup_capacity'],
            ),
          ),
        );
      }
      _pendingStepIndexes[callId] = <int>{
        for (var index = 0; index < _steps.length; index++) index,
      };
    }
    final future = _run(callId, snapshot);
    _inFlight[callId] = future;
    return future;
  }

  Future<CallCleanupReport> _run(
    CallId callId,
    CallSessionSnapshot snapshot,
  ) async {
    final pending = _pendingStepIndexes[callId]!;
    try {
      for (final index in List<int>.of(pending)) {
        final step = _steps[index];
        try {
          await step.action(snapshot).timeout(stepTimeout);
          pending.remove(index);
        } catch (_) {
          // Retain only this fixed step index for a later exact-call retry.
        }
      }
      final completed = pending.isEmpty;
      if (completed && _completed.add(callId)) {
        _pendingStepIndexes.remove(callId);
        _completedOrder.addLast(callId);
        while (_completedOrder.length > completedTombstoneCapacity) {
          _completed.remove(_completedOrder.removeFirst());
        }
      }
      final failures = pending
          .map((index) => _steps[index].name)
          .toList(growable: false);
      return _observe(
        CallCleanupReport(
          callId: callId,
          completed: completed,
          alreadyCompleted: false,
          terminalAckReady: pending.every(
            (index) => !_steps[index].requiredForTerminalAck,
          ),
          failedStepNames: List<String>.unmodifiable(failures),
        ),
      );
    } finally {
      _inFlight.remove(callId);
    }
  }

  bool hasCompleted(CallId callId) => _completed.contains(callId);

  CallCleanupReport _observe(CallCleanupReport report) {
    try {
      onReport?.call(report);
    } catch (_) {
      // Fixed-shape cleanup diagnostics cannot change cleanup authority.
    }
    return report;
  }
}
