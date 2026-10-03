import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/utils/flow_event_emitter.dart';

/// Serializes group-recovery passes (startup rejoin, app-resume recovery,
/// background retrier sweeps) so they execute one at a time instead of
/// overlapping.
///
/// Two contracts must be preserved:
///   * [activeDepthListenable] / [isActive] continue to report whether a pass
///     is active *or queued* — the group "catching up" UI shell
///     (`group_conversation_wired`) and the group-mutation guards
///     ([isGroupRecoveryInProgress]) depend on this signal being stable across
///     the whole window a pass occupies the gate.
///   * [run] still completes its action and surfaces its result/error to the
///     caller; it now additionally waits for any in-flight or queued pass to
///     finish first, so passes no longer interleave.
class GroupRecoveryGate {
  int _activeDepth = 0;
  final ValueNotifier<int> _activeDepthListenable = ValueNotifier<int>(0);

  /// FIFO queue of starters for passes waiting behind the in-flight pass. We
  /// deliberately serialize via an internal queue rather than by chaining onto
  /// a previous `Future`: chaining off a future created in another zone (e.g.
  /// the root zone) schedules the continuation as a microtask in *that* zone,
  /// which `fakeAsync` cannot drain — stalling tests. The queue keeps every
  /// pass running in the zone of whichever caller dispatched the chain.
  final List<void Function()> _queued = <void Function()>[];
  bool _running = false;

  bool get isActive => _activeDepth > 0;
  ValueListenable<int> get activeDepthListenable => _activeDepthListenable;

  void begin() {
    _activeDepth += 1;
    _activeDepthListenable.value = _activeDepth;
  }

  void end() {
    if (_activeDepth == 0) {
      return;
    }
    _activeDepth -= 1;
    _activeDepthListenable.value = _activeDepth;
  }

  /// Runs [action] serialized behind any in-flight or queued pass. The gate
  /// reports active (depth incremented) from the moment the pass is queued
  /// until its action settles, so callers that reject while recovery is in
  /// progress see a stable signal across the entire queued window.
  ///
  /// The action's result is forwarded to the returned future; an error is
  /// rethrown to the caller while still releasing the gate for the next pass.
  Future<T> run<T>(Future<T> Function() action) {
    begin();
    final Completer<T> completer = Completer<T>();
    final caller = _callerOf(StackTrace.current);
    final queuedAt = DateTime.now();

    void start() {
      _running = true;
      final acquiredAt = DateTime.now();
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_RECOVERY_GATE_ACQUIRED',
        details: {
          'caller': caller,
          'waitedMs': acquiredAt.difference(queuedAt).inMilliseconds,
          'depth': _activeDepth,
        },
      );
      // ignore: unawaited_futures — completion is observed via [completer].
      () async {
        try {
          completer.complete(await action());
        } catch (e, st) {
          completer.completeError(e, st);
        } finally {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_RECOVERY_GATE_RELEASED',
            details: {
              'caller': caller,
              'heldMs': DateTime.now().difference(acquiredAt).inMilliseconds,
              'queued': _queued.length,
            },
          );
          end();
          _running = false;
          if (_queued.isNotEmpty) {
            _queued.removeAt(0)();
          }
        }
      }();
    }

    if (_running) {
      _queued.add(start);
    } else {
      start();
    }
    return completer.future;
  }

  /// Completes `true` once no pass is active or queued, or `false` when
  /// [timeout] elapses first. Lets a user action wait out a short recovery
  /// pass instead of failing while one happens to run.
  Future<bool> whenIdle({required Duration timeout}) {
    if (!isActive) return Future<bool>.value(true);
    if (timeout <= Duration.zero) return Future<bool>.value(false);
    final completer = Completer<bool>();
    Timer? timer;
    void listener() {
      if (_activeDepth == 0 && !completer.isCompleted) {
        timer?.cancel();
        _activeDepthListenable.removeListener(listener);
        completer.complete(true);
      }
    }

    _activeDepthListenable.addListener(listener);
    timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        _activeDepthListenable.removeListener(listener);
        completer.complete(false);
      }
    });
    return completer.future;
  }

  /// Like [run] but returns `null` immediately — without queueing — when a pass
  /// is already active or queued. Used by best-effort retrier sweeps that
  /// should skip rather than pile on behind an in-flight recovery.
  Future<T>? tryRun<T>(Future<T> Function() action) {
    if (isActive) {
      return null;
    }
    return run(action);
  }

  /// The first stack frame outside this file, as `file.dart:line`, naming
  /// which recovery pass entered the gate.
  static String _callerOf(StackTrace trace) {
    for (final line in trace.toString().split('\n')) {
      final match = RegExp(r'([A-Za-z0-9_]+\.dart):(\d+)').firstMatch(line);
      if (match != null && match.group(1) != 'group_recovery_gate.dart') {
        return '${match.group(1)}:${match.group(2)}';
      }
    }
    return 'unknown';
  }

  void resetForTest() {
    _activeDepth = 0;
    _activeDepthListenable.value = 0;
    _queued.clear();
    _running = false;
  }
}

final groupRecoveryGate = GroupRecoveryGate();

/// How long a membership or metadata edit waits for an in-flight recovery
/// pass before it is refused. Recovery passes are short (seconds) but frequent
/// (every relay recovery arms one), so refusing immediately made admin edits
/// fail at random.
const defaultGroupRecoveryEditWait = Duration(seconds: 20);

Duration _groupRecoveryEditWait = defaultGroupRecoveryEditWait;

/// Tests that hold the gate open can make edits refuse immediately.
@visibleForTesting
set debugGroupRecoveryEditWait(Duration wait) => _groupRecoveryEditWait = wait;

/// Waits up to the edit wait for group recovery to finish; `true` when idle.
Future<bool> waitForGroupRecoveryIdle() =>
    groupRecoveryGate.whenIdle(timeout: _groupRecoveryEditWait);

const groupRecoveryPendingError =
    'Group recovery is in progress. Try again after resync completes.';

bool isGroupRecoveryInProgress() => groupRecoveryGate.isActive;

Future<T> runWithGroupRecoveryGate<T>(Future<T> Function() action) {
  return groupRecoveryGate.run(action);
}

/// Best-effort variant: returns `null` (skips) when a pass is already active or
/// queued, so callers can avoid piling redundant work behind an in-flight
/// recovery pass.
Future<T>? runWithGroupRecoveryGateOrSkip<T>(Future<T> Function() action) {
  return groupRecoveryGate.tryRun(action);
}
