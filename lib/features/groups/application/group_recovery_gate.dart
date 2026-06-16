import 'dart:async';

import 'package:flutter/foundation.dart';

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

    void start() {
      _running = true;
      // ignore: unawaited_futures — completion is observed via [completer].
      () async {
        try {
          completer.complete(await action());
        } catch (e, st) {
          completer.completeError(e, st);
        } finally {
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

  /// Like [run] but returns `null` immediately — without queueing — when a pass
  /// is already active or queued. Used by best-effort retrier sweeps that
  /// should skip rather than pile on behind an in-flight recovery.
  Future<T>? tryRun<T>(Future<T> Function() action) {
    if (isActive) {
      return null;
    }
    return run(action);
  }

  void resetForTest() {
    _activeDepth = 0;
    _activeDepthListenable.value = 0;
    _queued.clear();
    _running = false;
  }
}

final groupRecoveryGate = GroupRecoveryGate();

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
