import 'dart:async';

import 'package:uuid/uuid.dart';

import '../domain/call_engine.dart';
import '../domain/call_id.dart';

/// An exact remote source, issued by the current video session, never a texture.
final class CallPipSource {
  const CallPipSource({
    required this.negotiation,
    required this.rendererEpoch,
    required this.peerConnectionId,
    required this.remoteTrackId,
    required this.isCurrent,
  });

  final CallVideoNegotiation negotiation;
  final int rendererEpoch;
  final String peerConnectionId;
  final String remoteTrackId;
  final bool Function() isCurrent;

  bool sameBinding(CallPipSource other) =>
      identical(negotiation, other.negotiation) &&
      rendererEpoch == other.rendererEpoch &&
      peerConnectionId == other.peerConnectionId &&
      remoteTrackId == other.remoteTrackId;
}

/// Optional native-sink capability; plugin types never reach graph or widgets.
abstract interface class CallVideoPictureInPictureSource {
  CallPipSource? get pictureInPictureSource;
  Stream<void> get pictureInPictureSourceChanges;
}

final class CallPipIdentity {
  const CallPipIdentity(this.callId, this.leaseId, {required this.instanceId});
  final String instanceId;
  final CallId callId;
  final int leaseId;

  @override
  bool operator ==(Object other) =>
      other is CallPipIdentity &&
      instanceId == other.instanceId &&
      callId == other.callId &&
      leaseId == other.leaseId;

  @override
  int get hashCode => Object.hash(instanceId, callId, leaseId);
}

final class CallPipAvailability {
  const CallPipAvailability({
    required this.supported,
    required this.cameraInPip,
  });

  static const unavailable = CallPipAvailability(
    supported: false,
    cameraInPip: false,
  );
  final bool supported;
  final bool cameraInPip;
}

enum CallPipEventType { entered, exited, action, failed, blocked }

final class CallPipEvent {
  const CallPipEvent({
    required this.identity,
    required this.sequence,
    required this.type,
    this.detail,
  });
  final CallPipIdentity identity;
  final int sequence;
  final CallPipEventType type;
  final String? detail;
}

abstract interface class CallPictureInPictureBridge {
  Stream<CallPipEvent> get events;
  Future<CallPipAvailability> availability(CallPipIdentity identity);
  Future<bool> arm(
    CallPipIdentity identity,
    CallPipSource source, {
    required bool muted,
    required bool cameraOn,
    required bool cameraEnabled,
  });
  Future<bool> enter(CallPipIdentity identity);
  Future<bool> update(
    CallPipIdentity identity, {
    required bool muted,
    required bool cameraOn,
    required bool cameraEnabled,
  });
  Future<bool> disarm(CallPipIdentity identity, String reason);
  Future<void> close();
}

enum CallPipPhase { preparing, armed, entered }

final class CallPipLease {
  CallPipLease(this.identity, this.source);
  final CallPipIdentity identity;
  final CallPipSource source;
  CallPipPhase phase = CallPipPhase.preparing;
  bool cameraInPip = false;
  bool entryAccepted = false;
  int lastSequence = 0;
}

/// Owns native sink leases only. Camera consent and call actions stay in graph.
final class CallPictureInPictureController {
  CallPictureInPictureController({
    required this.bridge,
    required this.canApply,
    required this.onEvent,
    this.onReady,
    this.videoEnabled = false,
  });

  final CallPictureInPictureBridge bridge;
  final bool Function(CallPipSource source) canApply;
  final void Function(CallPipLease lease, CallPipEvent event) onEvent;
  final void Function()? onReady;
  final bool videoEnabled;

  final String _instanceId = const Uuid().v4();
  int _nextLease = 0;
  CallPipLease? _current;
  CallPipSource? _source;
  StreamSubscription<CallPipEvent>? _subscription;
  final Map<CallPipIdentity, String> _cleanup = {};
  final Map<CallPipIdentity, int> _cleanupVersions = {};
  int _cleanupVersion = 0;
  bool _closed = false;
  bool _background = false;
  bool _entryRequested = false;
  bool _muted = false;
  bool _cameraOn = false;

  CallPipLease? get current => _current;
  bool get hasPendingCleanup => _cleanup.isNotEmpty;
  bool _valid(CallPipLease lease) =>
      !_closed &&
      identical(_current, lease) &&
      lease.source.isCurrent() &&
      canApply(lease.source);

  void bind(
    CallPipSource? source, {
    required bool muted,
    required bool cameraOn,
  }) {
    if (_closed || !videoEnabled) return;
    final controlsChanged = _muted != muted || _cameraOn != cameraOn;
    _muted = muted;
    _cameraOn = cameraOn;
    if (source != null && _source?.sameBinding(source) == true) {
      final lease = _current;
      if (lease != null && !_valid(lease)) {
        invalidate();
      } else if (lease != null &&
          controlsChanged &&
          lease.phase != CallPipPhase.preparing) {
        unawaited(_update(lease));
      }
      return;
    }
    invalidate();
    _source = source;
    if (source == null || !source.isCurrent() || !canApply(source)) return;
    _subscription ??= bridge.events.listen(
      _receive,
      onError: (Object _) {
        final lease = _current;
        if (lease != null) _fail(lease, 'rendererError');
      },
    );
    final lease = CallPipLease(
      CallPipIdentity(
        source.negotiation.callId,
        ++_nextLease,
        instanceId: _instanceId,
      ),
      source,
    );
    _current = lease;
    unawaited(_arm(lease));
  }

  Future<void> _arm(CallPipLease lease) async {
    try {
      final available = await bridge.availability(lease.identity);
      if (!_valid(lease)) {
        _retireStale(lease);
        return;
      }
      if (!available.supported) {
        _fail(lease, 'enterRejected');
        return;
      }
      lease.cameraInPip = available.cameraInPip;
      final armed = await bridge.arm(
        lease.identity,
        lease.source,
        muted: _muted,
        cameraOn: _cameraOn,
        cameraEnabled: lease.cameraInPip,
      );
      if (!_valid(lease)) {
        _retireStale(lease);
        return;
      }
      if (!armed) {
        _fail(lease, 'enterRejected');
        return;
      }
      if (lease.phase == CallPipPhase.preparing) {
        lease.phase = CallPipPhase.armed;
      }
      unawaited(_update(lease));
      onReady?.call();
      if (_background) _enter(lease);
    } catch (_) {
      if (identical(_current, lease)) {
        _fail(lease, 'rendererError');
      } else {
        _retireStale(lease);
      }
    }
  }

  Future<void> _update(CallPipLease lease) async {
    try {
      final updated = await bridge.update(
        lease.identity,
        muted: _muted,
        cameraOn: _cameraOn,
        cameraEnabled: lease.cameraInPip,
      );
      if (!updated && _valid(lease)) _fail(lease, 'rendererError');
    } catch (_) {
      if (_valid(lease)) _fail(lease, 'rendererError');
    }
  }

  void _retireStale(CallPipLease lease) {
    if (identical(_current, lease)) _current = null;
    _cleanup[lease.identity] = 'retired';
    _cleanupVersions[lease.identity] = ++_cleanupVersion;
    unawaited(_disarm(lease.identity));
  }

  void _fail(CallPipLease lease, String reason) {
    if (!identical(_current, lease)) return;
    invalidate(reason);
    onEvent(
      lease,
      CallPipEvent(
        identity: lease.identity,
        sequence: lease.lastSequence,
        type: CallPipEventType.failed,
        detail: reason,
      ),
    );
  }

  void _receive(CallPipEvent event) {
    final lease = _current;
    if (lease == null || event.identity != lease.identity) return;
    if (!_valid(lease)) {
      invalidate();
      return;
    }
    if (event.sequence <= lease.lastSequence) return;
    lease.lastSequence = event.sequence;
    switch (event.type) {
      case CallPipEventType.entered:
        if (lease.phase == CallPipPhase.entered) return;
        lease.entryAccepted = true;
        lease.phase = CallPipPhase.entered;
      case CallPipEventType.action:
        if (lease.phase != CallPipPhase.entered) return;
      case CallPipEventType.exited:
      case CallPipEventType.failed:
      case CallPipEventType.blocked:
        invalidate(event.detail ?? 'retired');
    }
    onEvent(lease, event);
  }

  void background() {
    _background = true;
    final lease = _current;
    if (lease != null && lease.phase != CallPipPhase.preparing) _enter(lease);
  }

  void _enter(CallPipLease lease) {
    if (_entryRequested ||
        !_valid(lease) ||
        lease.phase == CallPipPhase.entered) {
      return;
    }
    _entryRequested = true;
    unawaited(() async {
      try {
        final entered = await bridge.enter(lease.identity);
        if (entered && _valid(lease)) lease.entryAccepted = true;
        if (!entered && _valid(lease) && lease.phase != CallPipPhase.entered) {
          _fail(lease, 'enterRejected');
        }
      } catch (_) {
        if (_valid(lease)) _fail(lease, 'enterRejected');
      }
    }());
  }

  void foreground() {
    _background = false;
    _entryRequested = false;
    if (_current == null) _source = null;
    unawaited(retryCleanup());
  }

  void invalidate([String reason = 'retired']) {
    final lease = _current;
    _current = null;
    _entryRequested = false;
    if (lease == null) return;
    _cleanup[lease.identity] = reason;
    _cleanupVersions[lease.identity] = ++_cleanupVersion;
    unawaited(_disarm(lease.identity));
  }

  Future<void> _disarm(CallPipIdentity id) async {
    final reason = _cleanup[id];
    final version = _cleanupVersions[id];
    if (reason == null) return;
    try {
      if (await bridge.disarm(id, reason) && _cleanupVersions[id] == version) {
        _cleanup.remove(id);
        _cleanupVersions.remove(id);
      }
    } catch (_) {
      /* Retain ownership for retry. */
    }
  }

  Future<bool> retryCleanup() async {
    await Future.wait(_cleanup.keys.toList().map(_disarm));
    return _cleanup.isEmpty;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    invalidate('shutdown');
    await _subscription?.cancel();
    await retryCleanup();
    await bridge.close();
  }
}
