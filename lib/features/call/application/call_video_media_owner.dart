import 'dart:async';

import '../domain/call_id.dart';

/// An explicitly transferred video resource, never an audio or call bundle.
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
final class CallVideoMediaOwner {
  CallVideoMediaOwner({
    required this.callId,
    required void Function() closeLocalVideoSendGate,
  }) : _closeLocalVideoSendGate = closeLocalVideoSendGate {
    _closeLocalVideoSendGate();
  }

  final CallId callId;
  final void Function() _closeLocalVideoSendGate;
  final Map<Object, CallVideoRendererIntent> _rendererIntents = {};
  final Map<Object, CallVideoRendererBinding> _renderers = {};
  final List<Future<bool>> _cleanupAttempts = [];
  CallVideoCaptureIntent? _captureIntent;
  CallVideoResource? _capture;
  int _captureGeneration = 0;
  int _rendererGeneration = 0;
  bool _closed = false;

  bool get hasPendingCleanup => false;

  CallVideoCaptureIntent? beginGrantedCapture(CallId expectedCallId) {
    if (_closed || expectedCallId != callId) return null;
    unawaited(stopCapture().then<void>((_) {}));
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
    if (_closed ||
        !identical(intent._owner, this) ||
        !identical(_captureIntent, intent)) {
      return Future<bool>.value(false);
    }
    return intent._attempt ??= _acquire(acquire);
  }

  Future<bool> _acquire(FutureOr<CallVideoResource> Function() acquire) async {
    try {
      final resource = await Future<CallVideoResource>.sync(acquire);
      if (resource.callId != callId) return false;
      _capture = resource;
      return true;
    } catch (_) {
      return false;
    }
  }

  CallVideoResource? captureFor(CallVideoCaptureIntent intent) =>
      !_closed &&
          identical(intent._owner, this) &&
          identical(_captureIntent, intent)
      ? _capture
      : null;

  CallVideoRendererIntent? beginRenderer(
    CallId expectedCallId,
    Object slot, {
    CallVideoCaptureIntent? captureIntent,
  }) {
    if (_closed || expectedCallId != callId) return null;
    if (captureIntent != null && captureFor(captureIntent) == null) return null;
    unawaited(detachRenderer(slot).then<void>((_) {}));
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
    if (_closed ||
        !identical(intent._owner, this) ||
        !identical(_rendererIntents[intent.slot], intent)) {
      return Future<bool>.value(false);
    }
    return intent._attempt ??= _attach(intent, prepare);
  }

  Future<bool> _attach(
    CallVideoRendererIntent intent,
    FutureOr<CallVideoRendererBinding> Function() prepare,
  ) async {
    try {
      final binding = await Future<CallVideoRendererBinding>.sync(prepare);
      if (binding.resource.callId != callId) return false;
      binding._attached = true;
      binding._attach();
      _renderers[intent.slot] = binding;
      return true;
    } catch (_) {
      return false;
    }
  }

  CallVideoRendererBinding? rendererFor(CallVideoRendererIntent intent) {
    if (_closed ||
        !identical(intent._owner, this) ||
        !identical(_rendererIntents[intent.slot], intent)) {
      return null;
    }
    if (intent.captureIntent != null &&
        captureFor(intent.captureIntent!) == null) {
      return null;
    }
    return _renderers[intent.slot];
  }

  Future<bool> stopCapture() async {
    final resource = _capture;
    final okay = resource == null ? true : await _release(resource);
    _capture = null;
    _closeLocalVideoSendGate();
    return okay;
  }

  Future<bool> detachRenderer(Object slot) async {
    final binding = _renderers[slot];
    final okay = binding == null
        ? true
        : await _release(binding.resource, binding: binding);
    _renderers.remove(slot);
    return okay;
  }

  Future<bool> retireVideo() async {
    var okay = await stopCapture();
    for (final slot in _renderers.keys.toList()) {
      if (!await detachRenderer(slot)) okay = false;
    }
    return okay;
  }

  Future<bool> close() {
    _closed = true;
    return retireVideo();
  }

  Future<bool> retryCleanup() async =>
      (await Future.wait(_cleanupAttempts)).every((okay) => okay);

  Future<bool> _release(
    CallVideoResource resource, {
    CallVideoRendererBinding? binding,
  }) {
    final attempt = Future<bool>.sync(() async {
      try {
        if (binding != null && binding._attached) {
          binding._detach();
          binding._attached = false;
        }
        await Future<void>.sync(resource._dispose);
        return true;
      } catch (_) {
        return false;
      }
    });
    _cleanupAttempts.add(attempt);
    return attempt;
  }
}
