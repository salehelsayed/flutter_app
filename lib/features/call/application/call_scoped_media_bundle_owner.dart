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

/// Owns at most one lazy media bundle while the process coordinator stays
/// stable across sequential calls.
///
/// This class owns lifecycle only. It delegates reducer-approved negotiation
/// effects unchanged and never creates a second coordinator or reducer lane.
final class CallScopedMediaBundleOwner implements CallEffectExecutor {
  CallScopedMediaBundleOwner({
    required CallScopedMediaBundleFactory createBundle,
    this.retiredCallCapacity = 128,
  }) : _createBundle = createBundle {
    if (retiredCallCapacity <= 0) {
      throw ArgumentError.value(retiredCallCapacity, 'retiredCallCapacity');
    }
  }

  final CallScopedMediaBundleFactory _createBundle;
  final int retiredCallCapacity;
  final Set<CallId> _retiredCallIds = <CallId>{};
  final Set<CallId> _failedCloseCallIds = <CallId>{};
  final Map<CallId, CallScopedMediaBundle> _failedCloseBundles =
      <CallId, CallScopedMediaBundle>{};
  final Map<CallId, Future<void>> _failedCloseRetries =
      <CallId, Future<void>>{};
  final ListQueue<CallId> _retiredCallOrder = ListQueue<CallId>();
  final StreamController<CallScopedMediaBundle?> _bundleChanges =
      StreamController<CallScopedMediaBundle?>.broadcast(sync: true);

  CallId? _ownedCallId;
  CallScopedMediaBundle? _currentBundle;
  Future<CallScopedMediaBundle>? _creationFuture;
  CallId? _closingCallId;
  Future<void>? _closingFuture;
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
    try {
      final bundle = await Future<CallScopedMediaBundle>.sync(
        () => _createBundle(callId),
      );
      if (bundle.callId != callId) {
        _retire(callId);
        await _closeRetiredBundle(callId, bundle);
        throw const CallScopedMediaBundleOwnerException(
          CallScopedMediaBundleOwnerErrorCode.invalidBundle,
        );
      }
      if (_closeRequested || _retiredCallIds.contains(callId)) {
        await _closeRetiredBundle(callId, bundle);
        throw CallScopedMediaBundleOwnerException(
          _closeRequested
              ? CallScopedMediaBundleOwnerErrorCode.ownerClosed
              : CallScopedMediaBundleOwnerErrorCode.retiredCall,
        );
      }
      if (_ownedCallId != callId) {
        await _closeRetiredBundle(callId, bundle);
        throw const CallScopedMediaBundleOwnerException(
          CallScopedMediaBundleOwnerErrorCode.activeCallMismatch,
        );
      }
      _currentBundle = bundle;
      if (!_bundleChanges.isClosed) _bundleChanges.add(bundle);
      return bundle;
    } catch (_) {
      _retire(callId);
      if (_ownedCallId == callId && _currentBundle == null) {
        _ownedCallId = null;
      }
      rethrow;
    }
  }

  /// Retires [callId] before cleanup, fencing every late effect immediately.
  Future<void> closeCall(CallId callId) async {
    final retrying = _failedCloseRetries[callId];
    if (retrying != null) return retrying;

    final failedBundle = _failedCloseBundles[callId];
    if (_retiredCallIds.contains(callId) && failedBundle != null) {
      late final Future<void> next;
      next = _retryFailedClose(callId, failedBundle).whenComplete(() {
        if (identical(_failedCloseRetries[callId], next)) {
          _failedCloseRetries.remove(callId);
        }
      });
      _failedCloseRetries[callId] = next;
      return next;
    }

    final closing = _closingFuture;
    if (_closingCallId == callId && closing != null) return closing;

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

    _closingCallId = callId;
    final next = _closeOwnedCall(callId);
    _closingFuture = next;
    return next;
  }

  Future<void> _closeOwnedCall(CallId callId) async {
    final bundle = _currentBundle;
    final creation = _creationFuture;
    _currentBundle = null;
    _ownedCallId = null;
    _creationFuture = null;
    if (!_bundleChanges.isClosed) _bundleChanges.add(null);
    try {
      if (bundle != null) {
        await bundle.close();
      } else if (creation != null) {
        try {
          await creation;
        } on CallScopedMediaBundleOwnerException catch (error) {
          if (error.code == CallScopedMediaBundleOwnerErrorCode.cleanupFailed) {
            rethrow;
          }
          // Retired creation closes any late-returned bundle itself.
        } catch (_) {
          // A factory failure created no owned media to release.
        }
      }
    } catch (_) {
      if (bundle != null) {
        _rememberFailedClose(callId, bundle);
      } else {
        _failedCloseCallIds.add(callId);
      }
      rethrow;
    } finally {
      if (_closingCallId == callId) {
        _closingCallId = null;
        _closingFuture = null;
      }
    }
  }

  Future<void> _retryFailedClose(
    CallId callId,
    CallScopedMediaBundle bundle,
  ) async {
    try {
      await bundle.close();
    } catch (_) {
      _rememberFailedClose(callId, bundle);
      rethrow;
    }
    if (identical(_failedCloseBundles[callId], bundle)) {
      _failedCloseBundles.remove(callId);
      _failedCloseCallIds.remove(callId);
    }
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

  Future<void> _closeRetiredBundle(
    CallId callId,
    CallScopedMediaBundle bundle,
  ) async {
    try {
      await bundle.close();
    } catch (_) {
      _rememberFailedClose(callId, bundle);
      throw const CallScopedMediaBundleOwnerException(
        CallScopedMediaBundleOwnerErrorCode.cleanupFailed,
      );
    }
  }

  void _rememberFailedClose(CallId callId, CallScopedMediaBundle bundle) {
    if (!_retiredCallIds.contains(callId)) return;
    _failedCloseCallIds.add(callId);
    _failedCloseBundles[callId] = bundle;
  }

  void _retire(CallId callId) {
    if (!_retiredCallIds.add(callId)) return;
    _retiredCallOrder.addLast(callId);
    while (_retiredCallOrder.length > retiredCallCapacity) {
      final evicted = _retiredCallOrder.removeFirst();
      _retiredCallIds.remove(evicted);
      _failedCloseCallIds.remove(evicted);
      _failedCloseBundles.remove(evicted);
      _failedCloseRetries.remove(evicted);
    }
  }

  static bool _isNegotiationEffect(CallEffectType type) => switch (type) {
    CallEffectType.startNegotiation ||
    CallEffectType.prepareAcceptedMedia ||
    CallEffectType.deliverOffer ||
    CallEffectType.deliverAnswer ||
    CallEffectType.queueIceCandidate ||
    CallEffectType.restartIce ||
    CallEffectType.requestIceRestart => true,
    _ => false,
  };
}
