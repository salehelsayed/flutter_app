import 'dart:async';
import 'dart:collection';

import '../domain/call_id.dart';

/// An explicitly transferred video resource, never an audio or call bundle.
///
/// [resource] is its stable ownership identity. A current or retiring resource
/// cannot be transferred again; capture and renderer handles have distinct
/// identities. [dispose] must release only this video resource.
final class CallVideoResource {
  CallVideoResource({
    required this.callId,
    required this.resource,
    required FutureOr<void> Function() dispose,
  }) : _dispose = dispose;

  final CallId callId;
  final Object resource;
  final FutureOr<void> Function() _dispose;
}

/// Preparation is asynchronous; these exact-binding commits are synchronous.
/// Detach must affect only this binding, even after a replacement has attached.
final class CallVideoRendererBinding {
  CallVideoRendererBinding({
    required this.resource,
    required void Function() attach,
    required void Function() detach,
  }) : _attach = attach,
       _detach = detach;

  final CallVideoResource resource;
  final void Function() _attach;
  final void Function() _detach;
  bool _attached = false;
}

final class CallVideoCaptureIntent {
  CallVideoCaptureIntent._(this._owner, this.callId, this.generation);

  final CallVideoMediaOwner _owner;
  final CallId callId;
  final int generation;
  Future<bool>? _attempt;
}

final class CallVideoRendererIntent {
  CallVideoRendererIntent._(
    this._owner,
    this.callId,
    this.generation,
    this.slot,
    this.captureIntent,
  );

  final CallVideoMediaOwner _owner;
  final CallId callId;
  final int generation;
  final Object slot;
  final CallVideoCaptureIntent? captureIntent;
  Future<bool>? _attempt;
}

/// Executes granted video intents without owning consent, audio, or the engine.
///
/// The caller supplies a fresh grant after its consent/permission checks and
/// opens its send gate only while [captureFor] still returns that capture. This
/// owner only closes the gate. Off/pause uses [stopCapture]; abort/audio fallback
/// uses [retireVideo]; terminal teardown uses [close]. Failed cleanup remains
/// owned until an explicit [retryCleanup] succeeds, including after close.
final class CallVideoMediaOwner {
  CallVideoMediaOwner({
    required this.callId,
    required void Function() closeLocalVideoSendGate,
  }) : _closeLocalVideoSendGate = closeLocalVideoSendGate {
    _closeGate();
  }

  final CallId callId;
  final void Function() _closeLocalVideoSendGate;
  final Map<Object, CallVideoRendererIntent> _rendererIntents = {};
  final Map<Object, CallVideoRendererBinding> _renderers = {};
  final Map<Object, _VideoCleanup> _cleanup = HashMap.identity();
  final Set<Object> _released = HashSet.identity();
  CallVideoCaptureIntent? _captureIntent;
  CallVideoResource? _capture;
  int _captureGeneration = 0;
  int _rendererGeneration = 0;
  bool _closed = false;
  bool _gateCloseFailed = false;

  bool get hasPendingCleanup => _gateCloseFailed || _cleanup.isNotEmpty;

  CallVideoCaptureIntent? beginGrantedCapture(CallId expectedCallId) {
    if (_closed || expectedCallId != callId) return null;
    unawaited(stopCapture().then<void>((_) {}));
    if (_closed || _gateCloseFailed) return null;
    return _captureIntent = CallVideoCaptureIntent._(
      this,
      callId,
      ++_captureGeneration,
    );
  }

  Future<bool> acquireCapture(
    CallVideoCaptureIntent intent,
    FutureOr<CallVideoResource> Function() acquire,
  ) {
    if (!_isCurrentCapture(intent)) return Future<bool>.value(false);
    final pending = intent._attempt;
    if (pending != null) return pending;
    final result = Completer<bool>();
    intent._attempt = result.future;
    unawaited(_acquire(intent, acquire).then<void>(result.complete));
    return result.future;
  }

  Future<bool> _acquire(
    CallVideoCaptureIntent intent,
    FutureOr<CallVideoResource> Function() acquire,
  ) async {
    try {
      final resource = await Future<CallVideoResource>.sync(acquire);
      if (resource.callId != callId) return false;
      if (!_isCurrentCapture(intent) || !_canAdopt(resource)) {
        _queueCleanup(resource);
        await _drainCleanup();
        return false;
      }
      _capture = resource;
      return true;
    } catch (_) {
      if (_isCurrentCapture(intent)) {
        unawaited(stopCapture().then<void>((_) {}));
      }
      return false;
    }
  }

  CallVideoResource? captureFor(CallVideoCaptureIntent intent) =>
      _isCurrentCapture(intent) ? _capture : null;

  bool _isCurrentCapture(CallVideoCaptureIntent intent) =>
      !_closed &&
      !_gateCloseFailed &&
      intent.callId == callId &&
      identical(intent._owner, this) &&
      identical(_captureIntent, intent);

  CallVideoRendererIntent? beginRenderer(
    CallId expectedCallId,
    Object slot, {
    CallVideoCaptureIntent? captureIntent,
  }) {
    if (_closed || expectedCallId != callId) return null;
    if (captureIntent != null && captureFor(captureIntent) == null) return null;
    unawaited(detachRenderer(slot).then<void>((_) {}));
    if (_closed ||
        (captureIntent != null && captureFor(captureIntent) == null)) {
      return null;
    }
    return _rendererIntents[slot] = CallVideoRendererIntent._(
      this,
      callId,
      ++_rendererGeneration,
      slot,
      captureIntent,
    );
  }

  Future<bool> attachRenderer(
    CallVideoRendererIntent intent,
    FutureOr<CallVideoRendererBinding> Function() prepare,
  ) {
    if (!_isCurrentRenderer(intent)) return Future<bool>.value(false);
    final pending = intent._attempt;
    if (pending != null) return pending;
    final result = Completer<bool>();
    intent._attempt = result.future;
    unawaited(_attach(intent, prepare).then<void>(result.complete));
    return result.future;
  }

  Future<bool> _attach(
    CallVideoRendererIntent intent,
    FutureOr<CallVideoRendererBinding> Function() prepare,
  ) async {
    CallVideoRendererBinding? binding;
    try {
      binding = await Future<CallVideoRendererBinding>.sync(prepare);
      if (binding.resource.callId != callId) return false;
      if (!_isCurrentRenderer(intent) || !_canAdopt(binding.resource)) {
        _queueCleanup(binding.resource, binding: binding);
        await _drainCleanup();
        return false;
      }
      // Even a throwing attach may have changed the native binding.
      binding._attached = true;
      binding._attach();
      if (!_isCurrentRenderer(intent)) {
        _queueCleanup(binding.resource, binding: binding);
        await _drainCleanup();
        return false;
      }
      _renderers[intent.slot] = binding;
      return true;
    } catch (_) {
      if (identical(_rendererIntents[intent.slot], intent)) {
        _rendererIntents.remove(intent.slot);
      }
      if (binding != null) {
        _queueCleanup(binding.resource, binding: binding);
        await _drainCleanup();
      }
      return false;
    }
  }

  CallVideoRendererBinding? rendererFor(CallVideoRendererIntent intent) {
    return _isCurrentRenderer(intent) ? _renderers[intent.slot] : null;
  }

  bool _isCurrentRenderer(CallVideoRendererIntent intent) =>
      !_closed &&
      intent.callId == callId &&
      identical(intent._owner, this) &&
      identical(_rendererIntents[intent.slot], intent) &&
      (intent.captureIntent == null ||
          captureFor(intent.captureIntent!) != null);

  Future<bool> stopCapture() {
    final resource = _capture;
    _capture = null;
    _captureIntent = null;
    final previews = <CallVideoRendererBinding>[];
    for (final entry in _rendererIntents.entries.toList()) {
      if (entry.value.captureIntent == null) continue;
      _rendererIntents.remove(entry.key);
      final binding = _renderers.remove(entry.key);
      if (binding != null) previews.add(binding);
    }
    _closeGate();
    for (final binding in previews) {
      _queueCleanup(binding.resource, binding: binding);
    }
    if (resource != null) _queueCleanup(resource);
    return _drainCleanup();
  }

  Future<bool> detachRenderer(Object slot) {
    _rendererIntents.remove(slot);
    final binding = _renderers.remove(slot);
    if (binding != null) _queueCleanup(binding.resource, binding: binding);
    return _drainCleanup();
  }

  Future<bool> retireVideo() {
    final capture = _capture;
    final renderers = _renderers.values.toList();
    _capture = null;
    _captureIntent = null;
    _rendererIntents.clear();
    _renderers.clear();
    _closeGate();
    for (final binding in renderers) {
      _queueCleanup(binding.resource, binding: binding);
    }
    if (capture != null) _queueCleanup(capture);
    return _drainCleanup();
  }

  Future<bool> close() {
    _closed = true;
    return retireVideo();
  }

  Future<bool> retryCleanup() {
    if (_gateCloseFailed) _closeGate();
    return _drainCleanup(retry: true);
  }

  void _closeGate() {
    try {
      _closeLocalVideoSendGate();
      _gateCloseFailed = false;
    } catch (_) {
      _gateCloseFailed = true;
    }
  }

  bool _isOwned(Object resource) =>
      identical(_capture?.resource, resource) ||
      _renderers.values.any(
        (binding) => identical(binding.resource.resource, resource),
      );

  bool _canAdopt(CallVideoResource resource) =>
      !_isOwned(resource.resource) &&
      !_cleanup.containsKey(resource.resource) &&
      !_released.contains(resource.resource);

  void _queueCleanup(
    CallVideoResource resource, {
    CallVideoRendererBinding? binding,
  }) {
    // A late alias does not transfer ownership away from a current resource.
    if (resource.callId != callId ||
        _isOwned(resource.resource) ||
        _released.contains(resource.resource)) {
      return;
    }
    _cleanup.putIfAbsent(
      resource.resource,
      () => _VideoCleanup(resource, binding),
    );
  }

  Future<bool> _drainCleanup({bool retry = false}) async {
    final results = await Future.wait(
      _cleanup.entries.toList().map((entry) async {
        final okay = await entry.value.attempt(retry: retry);
        if (okay && identical(_cleanup[entry.key], entry.value)) {
          _cleanup.remove(entry.key);
          _released.add(entry.key);
        }
        return okay;
      }),
    );
    return !_gateCloseFailed && results.every((okay) => okay);
  }
}

/// One retired handle, with successful cleanup stages memoized independently.
final class _VideoCleanup {
  _VideoCleanup(this.resource, this.binding)
    : _detached = binding == null || !binding._attached;

  final CallVideoResource resource;
  final CallVideoRendererBinding? binding;
  bool _detached;
  bool _disposed = false;
  bool _attempted = false;
  Future<bool>? _pending;

  Future<bool> attempt({required bool retry}) {
    if (_detached && _disposed) return Future<bool>.value(true);
    final pending = _pending;
    if (pending != null) return pending;
    if (_attempted && !retry) return Future<bool>.value(false);
    _attempted = true;
    final result = Completer<bool>();
    _pending = result.future;
    unawaited(
      _run().then<void>((okay) {
        _pending = null;
        result.complete(okay);
      }),
    );
    return result.future;
  }

  Future<bool> _run() async {
    if (!_detached) {
      try {
        binding!._detach();
        binding!._attached = false;
        _detached = true;
      } catch (_) {
        // Retain detach for an explicit retry, but still release the resource.
      }
    }
    if (!_disposed) {
      try {
        await Future<void>.sync(resource._dispose);
        _disposed = true;
      } catch (_) {
        // A failed dispose remains owned; successful stages never repeat.
      }
    }
    return _detached && _disposed;
  }
}
