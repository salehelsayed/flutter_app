import 'dart:async';
import 'dart:collection';

import '../domain/call_engine.dart';
import '../domain/call_event.dart';
import '../domain/call_id.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_state.dart';
import 'call_audio_controller.dart';
import 'call_coordinator.dart';

typedef CallScopedMediaBundleFactory =
    FutureOr<CallScopedMediaBundle> Function(CallId callId);

enum CallScopedMediaBundleOwnerErrorCode {
  activeCallMismatch,
  retiredCall,
  ownerClosed,
  invalidBundle,
  cleanupFailed,
}

/// A fixed-shape lifecycle refusal. Call IDs are excluded from diagnostics.
final class CallScopedMediaBundleOwnerException implements Exception {
  const CallScopedMediaBundleOwnerException(this.code);

  final CallScopedMediaBundleOwnerErrorCode code;

  @override
  String toString() => 'CallScopedMediaBundleOwnerException(${code.name})';
}

/// One call's one-shot engine, audio controls, and negotiation executor.
///
/// [close] must clean every resource in this bundle. Concurrent calls share
/// one attempt, successful cleanup stays memoized, and a failed attempt may be
/// retried by the lifecycle owner.
final class CallScopedMediaBundle {
  CallScopedMediaBundle({
    required this.callId,
    required this.engine,
    required this.audioController,
    required this.negotiationExecutor,
    required Future<void> Function() close,
  }) : _close = close;

  final CallId callId;
  final CallEngine engine;
  final CallAudioController audioController;

  /// Production supplies a CallNegotiationEffectExecutor through this seam.
  final CallEffectExecutor negotiationExecutor;
  final Future<void> Function() _close;

  Future<void>? _closeFuture;

  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    late final Future<void> next;
    next = Future<void>.sync(_close).onError((
      Object error,
      StackTrace stackTrace,
    ) {
      if (identical(_closeFuture, next)) _closeFuture = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
    _closeFuture = next;
    return next;
  }
}

/// The holder identity Go hands out with a grant. Go clears its holder only
/// for exactly this pair, so handing one back can never clear a later grant,
/// not even one with the same generation after a node restart.
final class CallMediaProtectionGrant {
  const CallMediaProtectionGrant({
    required this.generation,
    required this.incarnation,
  });

  final int generation;
  final int incarnation;

  @override
  bool operator ==(Object other) =>
      other is CallMediaProtectionGrant &&
      other.generation == generation &&
      other.incarnation == incarnation;

  @override
  int get hashCode => Object.hash(generation, incarnation);

  @override
  String toString() => 'CallMediaProtectionGrant($generation, $incarnation)';
}

/// Go's answer to one [CallMediaProtectionLease.acquire].
sealed class CallMediaProtectionAdmission {
  const CallMediaProtectionAdmission();
}

/// Go holds [grant] for this owner. Native media may open.
final class CallMediaProtectionGranted extends CallMediaProtectionAdmission {
  const CallMediaProtectionGranted(this.grant);

  final CallMediaProtectionGrant grant;
}

/// Go answered without granting. [reason] is Go's fixed word
/// (`restart_in_progress`, `not_started`, `superseded`), the bridge's error
/// code, or `timeout`. The owner asks again while the call still wants media.
final class CallMediaProtectionRefused extends CallMediaProtectionAdmission {
  const CallMediaProtectionRefused(this.reason);

  final String reason;
}

/// No protection exists to obtain: the native binary has no
/// `callMediaProtection` method. The only case in which media opens without
/// a grant. It is safe to open because Dart and the Go binary ship in one app
/// build: the method can be missing only in a mismatched build (an iOS
/// xcframework or an AAR older than this Dart), where no broker exists to
/// wait for. A broker that exists and refuses is never this case.
final class CallMediaProtectionUnavailable
    extends CallMediaProtectionAdmission {
  const CallMediaProtectionUnavailable();
}

/// Protection for a live call's native media against a full node restart.
///
/// While a grant is held, the Go relay recovery broker keeps its host and does
/// only in-place work. Implementations never throw and answer within a
/// bounded time. A grant that arrives after the caller stopped waiting is the
/// implementation's to hand back.
abstract interface class CallMediaProtectionLease {
  Future<CallMediaProtectionAdmission> acquire();

  Future<void> release(CallMediaProtectionGrant grant);
}

/// Owners without a recovery broker (tests, a platform without the binding).
final class NoCallMediaProtection implements CallMediaProtectionLease {
  const NoCallMediaProtection();

  @override
  Future<CallMediaProtectionAdmission> acquire() async =>
      const CallMediaProtectionUnavailable();

  @override
  Future<void> release(CallMediaProtectionGrant grant) async {}
}

/// A bundle whose cleanup failed, together with the grant that still
/// protects its media until a retry confirms the cleanup.
final class _UnconfirmedCleanup {
  const _UnconfirmedCleanup(this.bundle, this.grant);

  final CallScopedMediaBundle bundle;
  final CallMediaProtectionGrant? grant;
}

/// Owns at most one lazy media bundle while the process coordinator stays
/// stable across sequential calls.
///
/// This class owns lifecycle only. It delegates reducer-approved negotiation
/// effects unchanged and never creates a second coordinator or reducer lane.
final class CallScopedMediaBundleOwner implements CallEffectExecutor {
  CallScopedMediaBundleOwner({
    required CallScopedMediaBundleFactory createBundle,
    this.protection = const NoCallMediaProtection(),
    this.protectionRetryInterval = const Duration(milliseconds: 250),
    this.retiredCallCapacity = 128,
  }) : _createBundle = createBundle {
    if (retiredCallCapacity <= 0) {
      throw ArgumentError.value(retiredCallCapacity, 'retiredCallCapacity');
    }
  }

  final CallScopedMediaBundleFactory _createBundle;

  /// Held from before a bundle's media exists until its cleanup is confirmed.
  final CallMediaProtectionLease protection;

  /// Pause between two refused admissions. The whole wait is bounded by the
  /// coordinator's media-preparation budget: when that expires the call ends
  /// and its cleanup retires the pending call here, which stops the asking.
  final Duration protectionRetryInterval;
  final int retiredCallCapacity;
  final Set<CallId> _retiredCallIds = <CallId>{};
  final Set<CallId> _failedCloseCallIds = <CallId>{};

  /// Calls whose media close is running and still holds a grant. Each entry
  /// leaves only when its own close settles, so a later call's cleanup cannot
  /// drop an earlier call's protection.
  final Set<CallId> _protectedCloses = <CallId>{};
  final Map<CallId, Future<void>> _closingFutures = <CallId, Future<void>>{};
  final Map<CallId, _UnconfirmedCleanup> _unconfirmedCleanups =
      <CallId, _UnconfirmedCleanup>{};
  final Map<CallId, Future<void>> _failedCloseRetries =
      <CallId, Future<void>>{};
  final ListQueue<CallId> _retiredCallOrder = ListQueue<CallId>();
  final StreamController<CallScopedMediaBundle?> _bundleChanges =
      StreamController<CallScopedMediaBundle?>.broadcast(sync: true);

  CallId? _ownedCallId;
  CallScopedMediaBundle? _currentBundle;

  /// The grant the installed bundle holds, if any.
  CallMediaProtectionGrant? _heldProtection;
  Future<CallScopedMediaBundle>? _creationFuture;
  Future<void>? _closeFuture;
  bool _closeRequested = false;

  /// Emits the exact call-scoped bundle as soon as it is installed and null
  /// when it is retired. This is projection-only lifecycle evidence; the
  /// canonical reducer remains the sole owner of call state transitions.
  Stream<CallScopedMediaBundle?> get bundleChanges => _bundleChanges.stream;

  /// Returns controls only when [callId] is the exact current lifecycle owner.
  CallAudioController? currentAudioController(CallId callId) {
    final bundle = _currentBundle;
    if (_closeRequested ||
        _retiredCallIds.contains(callId) ||
        bundle == null ||
        bundle.callId != callId ||
        _ownedCallId != callId) {
      return null;
    }
    return bundle.audioController;
  }

  /// Returns coarse foreground state through the same exact-call fence.
  CallAudioControlState? currentAudioState(CallId callId) =>
      currentAudioController(callId)?.state;

  @override
  Future<CallEvent?> execute(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async {
    if (!_isNegotiationEffect(effect.type)) return null;
    final callId = snapshot.callId;
    if (callId == null) return null;

    final bundle = await _bundleFor(callId);
    if (_closeRequested) {
      throw const CallScopedMediaBundleOwnerException(
        CallScopedMediaBundleOwnerErrorCode.ownerClosed,
      );
    }
    if (_retiredCallIds.contains(callId) ||
        _ownedCallId != callId ||
        !identical(_currentBundle, bundle)) {
      throw const CallScopedMediaBundleOwnerException(
        CallScopedMediaBundleOwnerErrorCode.retiredCall,
      );
    }
    return bundle.negotiationExecutor.execute(effect, snapshot);
  }

  Future<CallScopedMediaBundle> _bundleFor(CallId callId) async {
    if (_closeRequested) {
      throw const CallScopedMediaBundleOwnerException(
        CallScopedMediaBundleOwnerErrorCode.ownerClosed,
      );
    }
    if (_retiredCallIds.contains(callId)) {
      throw const CallScopedMediaBundleOwnerException(
        CallScopedMediaBundleOwnerErrorCode.retiredCall,
      );
    }

    final ownedCallId = _ownedCallId;
    if (ownedCallId != null && ownedCallId != callId) {
      throw const CallScopedMediaBundleOwnerException(
        CallScopedMediaBundleOwnerErrorCode.activeCallMismatch,
      );
    }

    final current = _currentBundle;
    if (current != null) return current;
    final creation = _creationFuture;
    if (creation != null) return creation;

    _ownedCallId = callId;
    late final Future<CallScopedMediaBundle> next;
    next = _createAndInstall(callId).whenComplete(() {
      if (identical(_creationFuture, next)) _creationFuture = null;
    });
    _creationFuture = next;
    return next;
  }

  Future<CallScopedMediaBundle> _createAndInstall(CallId callId) async {
    CallMediaProtectionGrant? grant;
    // A bundle the call no longer owns is closed here; its grant moves with
    // it, so the catch below must not release it a second time.
    Future<Never> retireLate(
      CallScopedMediaBundle bundle,
      CallScopedMediaBundleOwnerException failure,
    ) async {
      final protectedBy = grant;
      grant = null;
      await _closeRetiredBundle(callId, bundle, protectedBy);
      throw failure;
    }

    try {
      grant = await _admit(callId);
      final bundle = await Future<CallScopedMediaBundle>.sync(
        () => _createBundle(callId),
      );
      if (bundle.callId != callId) {
        _retire(callId);
        await retireLate(
          bundle,
          const CallScopedMediaBundleOwnerException(
            CallScopedMediaBundleOwnerErrorCode.invalidBundle,
          ),
        );
      }
      final departure = _departureOf(callId);
      if (departure != null) await retireLate(bundle, departure);
      _currentBundle = bundle;
      _heldProtection = grant;
      if (!_bundleChanges.isClosed) _bundleChanges.add(bundle);
      return bundle;
    } catch (_) {
      _retire(callId);
      if (_ownedCallId == callId && _currentBundle == null) {
        _ownedCallId = null;
      }
      _releaseProtection(grant);
      rethrow;
    }
  }

  /// The pending state before media exists: asks Go until it grants, says no
  /// protection exists, or the call leaves this owner. A refusal
  /// (`restart_in_progress` and the like) is asked again after
  /// [protectionRetryInterval]; the media factory never runs on one.
  Future<CallMediaProtectionGrant?> _admit(CallId callId) async {
    while (true) {
      if (_olderMediaStillProtected(callId)) {
        // An earlier call's media close is pending or unconfirmed and still
        // holds the one broker lease. A new grant would replace it, so wait
        // like a refusal until that cleanup is confirmed.
        await Future<void>.delayed(protectionRetryInterval);
        final waiting = _departureOf(callId);
        if (waiting != null) throw waiting;
        continue;
      }
      final admission = await protection.acquire();
      final departure = _departureOf(callId);
      switch (admission) {
        case CallMediaProtectionGranted(:final grant):
          if (departure == null) return grant;
          // The call stopped waiting first. The exact pair goes back and
          // cannot touch whatever a successor holds.
          _releaseProtection(grant);
          throw departure;
        case CallMediaProtectionUnavailable():
          // The one fail-open case: no native method, so no broker exists to
          // wait for (a mismatched build; see CallMediaProtectionUnavailable).
          if (departure != null) throw departure;
          return null;
        case CallMediaProtectionRefused():
          if (departure != null) throw departure;
      }
      await Future<void>.delayed(protectionRetryInterval);
      final late = _departureOf(callId);
      if (late != null) throw late;
    }
  }

  /// True while another call's media close is still running, or failed and
  /// keeps its grant for a retry.
  bool _olderMediaStillProtected(CallId callId) {
    if (_protectedCloses.any((closing) => closing != callId)) return true;
    return _unconfirmedCleanups.entries.any(
      (entry) => entry.key != callId && entry.value.grant != null,
    );
  }

  /// Why [callId] may no longer open or keep media, or null while it may.
  CallScopedMediaBundleOwnerException? _departureOf(CallId callId) {
    if (_closeRequested) {
      return const CallScopedMediaBundleOwnerException(
        CallScopedMediaBundleOwnerErrorCode.ownerClosed,
      );
    }
    if (_retiredCallIds.contains(callId)) {
      return const CallScopedMediaBundleOwnerException(
        CallScopedMediaBundleOwnerErrorCode.retiredCall,
      );
    }
    if (_ownedCallId != callId) {
      return const CallScopedMediaBundleOwnerException(
        CallScopedMediaBundleOwnerErrorCode.activeCallMismatch,
      );
    }
    return null;
  }

  /// Not awaited by callers: the broker's answer must not delay cleanup, and
  /// Go ignores a release for a holder it no longer has.
  void _releaseProtection(CallMediaProtectionGrant? grant) {
    if (grant != null) unawaited(protection.release(grant));
  }

  /// Retires [callId] before cleanup, fencing every late effect immediately.
  Future<void> closeCall(CallId callId) async {
    final retrying = _failedCloseRetries[callId];
    if (retrying != null) return retrying;

    final unconfirmed = _unconfirmedCleanups[callId];
    if (_retiredCallIds.contains(callId) && unconfirmed != null) {
      late final Future<void> next;
      next = _retryFailedClose(callId, unconfirmed).whenComplete(() {
        if (identical(_failedCloseRetries[callId], next)) {
          _failedCloseRetries.remove(callId);
        }
      });
      _failedCloseRetries[callId] = next;
      return next;
    }

    final closing = _closingFutures[callId];
    if (closing != null) return closing;

    final ownedCallId = _ownedCallId;
    if (ownedCallId != null && ownedCallId != callId) {
      throw const CallScopedMediaBundleOwnerException(
        CallScopedMediaBundleOwnerErrorCode.activeCallMismatch,
      );
    }
    if (_retiredCallIds.contains(callId) && ownedCallId == null) {
      if (_failedCloseCallIds.contains(callId)) {
        throw const CallScopedMediaBundleOwnerException(
          CallScopedMediaBundleOwnerErrorCode.cleanupFailed,
        );
      }
      return;
    }

    _retire(callId);
    if (ownedCallId == null) return;

    late final Future<void> next;
    next = _closeOwnedCall(callId).whenComplete(() {
      if (identical(_closingFutures[callId], next)) {
        _closingFutures.remove(callId);
      }
    });
    _closingFutures[callId] = next;
    return next;
  }

  Future<void> _closeOwnedCall(CallId callId) async {
    final bundle = _currentBundle;
    final creation = _creationFuture;
    final grant = _heldProtection;
    if (bundle != null && grant != null) _protectedCloses.add(callId);
    _currentBundle = null;
    _ownedCallId = null;
    _creationFuture = null;
    _heldProtection = null;
    if (!_bundleChanges.isClosed) _bundleChanges.add(null);
    try {
      if (bundle != null) {
        try {
          await bundle.close();
        } catch (_) {
          _rememberFailedClose(callId, bundle, grant);
          rethrow;
        }
        _releaseProtection(grant);
      } else if (creation != null) {
        try {
          await creation;
        } on CallScopedMediaBundleOwnerException catch (error) {
          if (error.code == CallScopedMediaBundleOwnerErrorCode.cleanupFailed) {
            _failedCloseCallIds.add(callId);
            rethrow;
          }
          // Retired creation closes any late-returned bundle itself.
        } catch (_) {
          // A factory failure created no owned media to release.
        }
      }
    } finally {
      _protectedCloses.remove(callId);
    }
  }

  Future<void> _retryFailedClose(
    CallId callId,
    _UnconfirmedCleanup cleanup,
  ) async {
    try {
      await cleanup.bundle.close();
    } catch (_) {
      _rememberFailedClose(callId, cleanup.bundle, cleanup.grant);
      rethrow;
    }
    if (identical(_unconfirmedCleanups[callId], cleanup)) {
      _unconfirmedCleanups.remove(callId);
      _failedCloseCallIds.remove(callId);
    }
    _releaseProtection(cleanup.grant);
  }

  /// Permanently closes this process owner and its current call, if any.
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    _closeRequested = true;
    final next = _closeOnce();
    _closeFuture = next;
    return next;
  }

  Future<void> _closeOnce() async {
    try {
      final callId = _ownedCallId;
      if (callId != null) await closeCall(callId);
    } finally {
      if (!_bundleChanges.isClosed) await _bundleChanges.close();
    }
  }

  /// Closes a bundle its call no longer owns. A confirmed close hands the
  /// grant back; a failed close keeps it with the bundle for the retry.
  Future<void> _closeRetiredBundle(
    CallId callId,
    CallScopedMediaBundle bundle,
    CallMediaProtectionGrant? grant,
  ) async {
    if (grant != null) _protectedCloses.add(callId);
    try {
      await bundle.close();
    } catch (_) {
      _rememberFailedClose(callId, bundle, grant);
      throw const CallScopedMediaBundleOwnerException(
        CallScopedMediaBundleOwnerErrorCode.cleanupFailed,
      );
    } finally {
      _protectedCloses.remove(callId);
    }
    _releaseProtection(grant);
  }

  void _rememberFailedClose(
    CallId callId,
    CallScopedMediaBundle bundle,
    CallMediaProtectionGrant? grant,
  ) {
    if (!_retiredCallIds.contains(callId)) {
      // Nothing will retry this cleanup, so nothing else would ever hand the
      // grant back.
      _releaseProtection(grant);
      return;
    }
    _failedCloseCallIds.add(callId);
    _unconfirmedCleanups[callId] = _UnconfirmedCleanup(bundle, grant);
  }

  void _retire(CallId callId) {
    if (!_retiredCallIds.add(callId)) return;
    _retiredCallOrder.addLast(callId);
    var excess = _retiredCallOrder.length - retiredCallCapacity;
    for (final evicted in _retiredCallOrder.toList()) {
      if (excess <= 0) break;
      // Media whose close is pending or unconfirmed keeps its tombstone and
      // its grant: running out of tombstones is not native teardown.
      if (_holdsProtectedMedia(evicted)) continue;
      _retiredCallOrder.remove(evicted);
      _retiredCallIds.remove(evicted);
      _failedCloseCallIds.remove(evicted);
      _unconfirmedCleanups.remove(evicted);
      _failedCloseRetries.remove(evicted);
      excess--;
    }
  }

  bool _holdsProtectedMedia(CallId callId) =>
      _protectedCloses.contains(callId) ||
      _unconfirmedCleanups[callId]?.grant != null;

  static bool _isNegotiationEffect(CallEffectType type) => switch (type) {
    CallEffectType.startNegotiation ||
    CallEffectType.prepareAcceptedMedia ||
    CallEffectType.deliverOffer ||
    CallEffectType.deliverAnswer ||
    CallEffectType.queueIceCandidate ||
    CallEffectType.restartIce ||
    CallEffectType.requestIceRestart ||
    CallEffectType.resumeRecoverySignals => true,
    _ => false,
  };
}
