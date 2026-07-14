import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const String kPictureInPictureMethodChannel = 'mknoon/picture_in_picture';
const String kPictureInPictureEventChannel = 'mknoon/picture_in_picture/events';

enum PictureInPictureHostPlatform { android, iOS, other }

enum PictureInPictureCapabilityReason {
  available,
  iOSDisabled,
  unsupportedPlatform,
  androidUnavailable,
  pipUnavailable,
  unsupported,
  channelFailure,
}

@immutable
class PictureInPictureCapability {
  const PictureInPictureCapability.androidSupported()
    : isVisible = true,
      isSupported = true,
      reason = PictureInPictureCapabilityReason.available;

  const PictureInPictureCapability.androidUnsupported()
    : isVisible = false,
      isSupported = false,
      reason = PictureInPictureCapabilityReason.androidUnavailable;

  const PictureInPictureCapability.hidden(this.reason)
    : isVisible = false,
      isSupported = false;

  const PictureInPictureCapability.channelFailure()
    : isVisible = false,
      isSupported = false,
      reason = PictureInPictureCapabilityReason.channelFailure;

  final bool isVisible;
  final bool isSupported;
  final PictureInPictureCapabilityReason reason;
}

enum PictureInPictureStartOutcome {
  started,
  hidden,
  unsupportedPlatform,
  pipUnavailable,
  unsupported,
  invalidPath,
  busy,
  activityUnavailable,
  staleSession,
  badArguments,
  rejected,
  platformFailure,
}

enum PictureInPictureFailureReason {
  unsupportedPlatform,
  pipUnavailable,
  unsupported,
  invalidPath,
  busy,
  activityUnavailable,
  staleSession,
  badArguments,
  channelFailure,
  platformFailure,
}

@immutable
class PictureInPictureCommandResult {
  const PictureInPictureCommandResult.success()
    : accepted = true,
      failureReason = null;

  const PictureInPictureCommandResult.rejected(
    PictureInPictureFailureReason reason,
  ) : accepted = false,
      failureReason = reason;

  final bool accepted;
  final PictureInPictureFailureReason? failureReason;
}

@immutable
class PictureInPictureRequest {
  const PictureInPictureRequest({
    required this.session,
    required this.attachment,
    required this.path,
    required this.positionMs,
    this.durationMs,
  });

  final String session;
  final String attachment;
  final String path;
  final int positionMs;
  final int? durationMs;

  bool get isValid =>
      session.trim().isNotEmpty &&
      attachment.trim().isNotEmpty &&
      path.trim().isNotEmpty &&
      positionMs >= 0 &&
      (durationMs == null || durationMs! > 0) &&
      (durationMs == null || positionMs <= durationMs!);

  Map<String, Object?> toMap() => <String, Object?>{
    'session': session,
    'attachment': attachment,
    'path': path,
    'positionMs': positionMs,
    'durationMs': durationMs,
  };

  @override
  String toString() =>
      'PictureInPictureRequest(session: redacted, attachment: $attachment, '
      'positionMs: $positionMs, durationMs: $durationMs)';
}

enum PictureInPictureState {
  nativeReady,
  active,
  checkpoint,
  restoring,
  stopped,
  completed,
  failed,
}

enum PictureInPictureTerminalReason {
  systemReturn,
  systemClose,
  explicitStop,
  interrupted,
  completed,
  activityDestroyed,
  flutterEngineDetached,
  hostDestroyed,
  playbackError,

  /// Dart-only fail-closed terminal; never accepted from native payloads.
  channelFailure,
}

@immutable
class PictureInPictureEvent {
  const PictureInPictureEvent({
    required this.session,
    required this.attachment,
    required this.state,
    required this.positionMs,
    this.durationMs,
    this.reason,
  });

  final String session;
  final String attachment;
  final PictureInPictureState state;
  final int positionMs;
  final int? durationMs;
  final PictureInPictureTerminalReason? reason;

  bool get isTerminal => switch (state) {
    PictureInPictureState.restoring ||
    PictureInPictureState.stopped ||
    PictureInPictureState.completed ||
    PictureInPictureState.failed => true,
    _ => false,
  };
}

abstract interface class PictureInPictureGateway {
  Stream<PictureInPictureEvent> get events;

  Future<PictureInPictureCapability> capability();

  Future<PictureInPictureStartOutcome> start(PictureInPictureRequest request);

  Future<PictureInPictureCommandResult> activate(
    String session,
    String attachment,
  );

  Future<PictureInPictureCommandResult> stop(String session, String attachment);

  Future<void> dispose();
}

typedef PictureInPictureInvoke =
    Future<Object?> Function(String method, Map<String, Object?>? arguments);

/// Strict Android channel owner for one native PiP session at a time.
///
/// iOS and non-Android hosts are deliberately hidden and make zero channel
/// calls under the selected Android-only product path.
class PictureInPictureChannelGateway implements PictureInPictureGateway {
  PictureInPictureChannelGateway({
    required this.platform,
    required PictureInPictureInvoke invokeMethod,
    required Stream<Object?> nativeEvents,
  }) : _invokeMethod = invokeMethod {
    if (platform == PictureInPictureHostPlatform.android) {
      _nativeSubscription = nativeEvents.listen(
        _handleNativeEvent,
        onError: (_, _) => _failActive(),
        onDone: _failActive,
        cancelOnError: false,
      );
    }
  }

  factory PictureInPictureChannelGateway.platform() {
    final platform = _currentHostPlatform();
    if (platform != PictureInPictureHostPlatform.android) {
      return PictureInPictureChannelGateway(
        platform: platform,
        invokeMethod: (_, _) async => null,
        nativeEvents: const Stream<Object?>.empty(),
      );
    }
    const method = MethodChannel(kPictureInPictureMethodChannel);
    const events = EventChannel(kPictureInPictureEventChannel);
    return PictureInPictureChannelGateway(
      platform: platform,
      invokeMethod: (name, arguments) =>
          method.invokeMethod<Object?>(name, arguments),
      nativeEvents: events.receiveBroadcastStream().cast<Object?>(),
    );
  }

  final PictureInPictureHostPlatform platform;
  final PictureInPictureInvoke _invokeMethod;
  final StreamController<PictureInPictureEvent> _events =
      StreamController<PictureInPictureEvent>.broadcast(sync: true);
  StreamSubscription<Object?>? _nativeSubscription;
  PictureInPictureRequest? _active;
  bool _nativeReady = false;
  bool _stopRequested = false;
  bool _disposed = false;
  int _lastPositionMs = 0;
  int? _lastDurationMs;

  @override
  Stream<PictureInPictureEvent> get events => _events.stream;

  @override
  Future<PictureInPictureCapability> capability() async {
    if (platform == PictureInPictureHostPlatform.iOS) {
      return const PictureInPictureCapability.hidden(
        PictureInPictureCapabilityReason.iOSDisabled,
      );
    }
    if (platform != PictureInPictureHostPlatform.android) {
      return const PictureInPictureCapability.hidden(
        PictureInPictureCapabilityReason.unsupportedPlatform,
      );
    }
    if (_disposed) return const PictureInPictureCapability.channelFailure();
    try {
      final raw = await _invokeMethod('capability', null);
      if (!_hasExactKeys(raw, const <String>{'supported'})) {
        return const PictureInPictureCapability.channelFailure();
      }
      final response = raw as Map<dynamic, dynamic>;
      if (response['supported'] is! bool) {
        return const PictureInPictureCapability.channelFailure();
      }
      return response['supported'] as bool
          ? const PictureInPictureCapability.androidSupported()
          : const PictureInPictureCapability.androidUnsupported();
    } on MissingPluginException {
      return const PictureInPictureCapability.channelFailure();
    } on PlatformException catch (error) {
      return switch (_failureReasonForCode(error.code)) {
        PictureInPictureFailureReason.pipUnavailable =>
          const PictureInPictureCapability.hidden(
            PictureInPictureCapabilityReason.pipUnavailable,
          ),
        PictureInPictureFailureReason.unsupported =>
          const PictureInPictureCapability.hidden(
            PictureInPictureCapabilityReason.unsupported,
          ),
        _ => const PictureInPictureCapability.channelFailure(),
      };
    } catch (_) {
      return const PictureInPictureCapability.channelFailure();
    }
  }

  @override
  Future<PictureInPictureStartOutcome> start(
    PictureInPictureRequest request,
  ) async {
    if (platform != PictureInPictureHostPlatform.android) {
      return PictureInPictureStartOutcome.unsupportedPlatform;
    }
    if (_disposed) return PictureInPictureStartOutcome.platformFailure;
    if (!request.isValid) return PictureInPictureStartOutcome.rejected;
    if (_active != null) return PictureInPictureStartOutcome.busy;
    final available = await capability();
    if (!available.isSupported) {
      return switch (available.reason) {
        PictureInPictureCapabilityReason.androidUnavailable ||
        PictureInPictureCapabilityReason.pipUnavailable =>
          PictureInPictureStartOutcome.pipUnavailable,
        PictureInPictureCapabilityReason.unsupported =>
          PictureInPictureStartOutcome.unsupported,
        PictureInPictureCapabilityReason.iOSDisabled ||
        PictureInPictureCapabilityReason.unsupportedPlatform =>
          PictureInPictureStartOutcome.unsupportedPlatform,
        PictureInPictureCapabilityReason.channelFailure ||
        PictureInPictureCapabilityReason.available =>
          PictureInPictureStartOutcome.platformFailure,
      };
    }

    _active = request;
    _nativeReady = false;
    _stopRequested = false;
    _lastPositionMs = request.positionMs;
    _lastDurationMs = request.durationMs;
    try {
      final raw = await _invokeMethod('start', request.toMap());
      if (!_accepted(raw) || !identical(_active, request)) {
        if (identical(_active, request)) _clearActive();
        return PictureInPictureStartOutcome.platformFailure;
      }
      return PictureInPictureStartOutcome.started;
    } on MissingPluginException {
      _clearActive();
      return PictureInPictureStartOutcome.platformFailure;
    } on PlatformException catch (error) {
      _clearActive();
      return _startOutcomeForFailure(_failureReasonForCode(error.code));
    } catch (_) {
      _clearActive();
      return PictureInPictureStartOutcome.platformFailure;
    }
  }

  @override
  Future<PictureInPictureCommandResult> activate(
    String session,
    String attachment,
  ) async {
    if (platform != PictureInPictureHostPlatform.android) {
      return const PictureInPictureCommandResult.rejected(
        PictureInPictureFailureReason.unsupportedPlatform,
      );
    }
    final active = _active;
    if (_disposed) {
      return const PictureInPictureCommandResult.rejected(
        PictureInPictureFailureReason.channelFailure,
      );
    }
    if (active == null ||
        !_nativeReady ||
        active.session != session ||
        active.attachment != attachment) {
      return const PictureInPictureCommandResult.rejected(
        PictureInPictureFailureReason.staleSession,
      );
    }
    PictureInPictureFailureReason failureReason =
        PictureInPictureFailureReason.channelFailure;
    try {
      final raw = await _invokeMethod('activate', <String, Object?>{
        'session': session,
        'attachment': attachment,
      });
      if (_accepted(raw)) {
        return const PictureInPictureCommandResult.success();
      }
    } on PlatformException catch (error) {
      failureReason = _failureReasonForCode(error.code);
    } on MissingPluginException {
      failureReason = PictureInPictureFailureReason.channelFailure;
    } catch (_) {
      failureReason = PictureInPictureFailureReason.channelFailure;
    }
    _failActive();
    return PictureInPictureCommandResult.rejected(failureReason);
  }

  @override
  Future<PictureInPictureCommandResult> stop(
    String session,
    String attachment,
  ) async {
    if (platform != PictureInPictureHostPlatform.android) {
      return const PictureInPictureCommandResult.rejected(
        PictureInPictureFailureReason.unsupportedPlatform,
      );
    }
    final active = _active;
    if (_disposed) {
      return const PictureInPictureCommandResult.rejected(
        PictureInPictureFailureReason.channelFailure,
      );
    }
    if (active == null ||
        _stopRequested ||
        active.session != session ||
        active.attachment != attachment) {
      return const PictureInPictureCommandResult.rejected(
        PictureInPictureFailureReason.staleSession,
      );
    }
    _stopRequested = true;
    PictureInPictureFailureReason failureReason =
        PictureInPictureFailureReason.channelFailure;
    try {
      final raw = await _invokeMethod('stop', <String, Object?>{
        'session': session,
        'attachment': attachment,
      });
      if (_accepted(raw)) {
        return const PictureInPictureCommandResult.success();
      }
    } on PlatformException catch (error) {
      failureReason = _failureReasonForCode(error.code);
    } on MissingPluginException {
      failureReason = PictureInPictureFailureReason.channelFailure;
    } catch (_) {
      failureReason = PictureInPictureFailureReason.channelFailure;
    }
    _failActive();
    return PictureInPictureCommandResult.rejected(failureReason);
  }

  void _handleNativeEvent(Object? raw) {
    final active = _active;
    if (_disposed || active == null) return;
    if (raw is Map) {
      final rawSession = raw['session'];
      final rawAttachment = raw['attachment'];
      if (rawSession is String &&
          rawAttachment is String &&
          (rawSession != active.session ||
              rawAttachment != active.attachment)) {
        return;
      }
    }
    final event = _decodeEvent(raw, active);
    if (event == null) {
      _failActive();
      return;
    }
    _lastPositionMs = event.positionMs;
    _lastDurationMs = event.durationMs ?? _lastDurationMs;
    if (event.state == PictureInPictureState.nativeReady) {
      _nativeReady = true;
    }
    _events.add(event);
    if (event.isTerminal) _clearActive();
  }

  PictureInPictureEvent? _decodeEvent(
    Object? raw,
    PictureInPictureRequest active,
  ) {
    const keys = <String>{
      'session',
      'attachment',
      'state',
      'positionMs',
      'durationMs',
      'reason',
    };
    if (!_hasExactKeys(raw, keys)) return null;
    final envelope = raw as Map<dynamic, dynamic>;
    final session = envelope['session'];
    final attachment = envelope['attachment'];
    final stateName = envelope['state'];
    final positionMs = envelope['positionMs'];
    final durationMs = envelope['durationMs'];
    final reasonName = envelope['reason'];
    if (session != active.session ||
        attachment != active.attachment ||
        stateName is! String ||
        positionMs is! int ||
        positionMs < 0 ||
        (durationMs != null && (durationMs is! int || durationMs <= 0)) ||
        (durationMs is int && positionMs > durationMs) ||
        (reasonName != null && reasonName is! String)) {
      return null;
    }
    final state = _states[stateName];
    final reason = reasonName == null ? null : _nativeReasons[reasonName];
    if (state == null || (reasonName != null && reason == null)) return null;
    final terminal = const <PictureInPictureState>{
      PictureInPictureState.restoring,
      PictureInPictureState.stopped,
      PictureInPictureState.completed,
      PictureInPictureState.failed,
    }.contains(state);
    if (terminal != (reason != null)) return null;
    if (terminal && _terminalStateForReason[reason] != state) {
      return null;
    }
    if (state == PictureInPictureState.completed && positionMs != 0) {
      return null;
    }
    return PictureInPictureEvent(
      session: session as String,
      attachment: attachment as String,
      state: state,
      positionMs: positionMs,
      durationMs: durationMs as int?,
      reason: reason,
    );
  }

  void _failActive() {
    final active = _active;
    if (_disposed || active == null) return;
    final arguments = <String, Object?>{
      'session': active.session,
      'attachment': active.attachment,
    };
    _events.add(
      PictureInPictureEvent(
        session: active.session,
        attachment: active.attachment,
        state: PictureInPictureState.failed,
        positionMs: _lastPositionMs,
        durationMs: _lastDurationMs,
        reason: PictureInPictureTerminalReason.channelFailure,
      ),
    );
    _clearActive();
    unawaited(_bestEffortStop(arguments));
  }

  Future<void> _bestEffortStop(Map<String, Object?> arguments) async {
    try {
      await _invokeMethod('stop', arguments);
    } catch (_) {
      // The synthetic terminal above already failed closed.
    }
  }

  bool _accepted(Object? raw) {
    if (!_hasExactKeys(raw, const <String>{'accepted'})) return false;
    return (raw as Map<dynamic, dynamic>)['accepted'] == true;
  }

  bool _hasExactKeys(Object? raw, Set<String> expected) =>
      raw is Map &&
      raw.length == expected.length &&
      raw.keys.every((key) => key is String && expected.contains(key));

  void _clearActive() {
    _active = null;
    _nativeReady = false;
    _stopRequested = false;
    _lastPositionMs = 0;
    _lastDurationMs = null;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    final active = _active;
    if (active != null && !_stopRequested) {
      try {
        await _invokeMethod('stop', <String, Object?>{
          'session': active.session,
          'attachment': active.attachment,
        });
      } catch (_) {
        // Disposal is already terminal on the Dart side.
      }
    }
    _disposed = true;
    _clearActive();
    await _nativeSubscription?.cancel();
    await _events.close();
  }
}

PictureInPictureHostPlatform _currentHostPlatform() {
  if (kIsWeb) return PictureInPictureHostPlatform.other;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => PictureInPictureHostPlatform.android,
    TargetPlatform.iOS => PictureInPictureHostPlatform.iOS,
    _ => PictureInPictureHostPlatform.other,
  };
}

const Map<String, PictureInPictureState> _states =
    <String, PictureInPictureState>{
      'nativeReady': PictureInPictureState.nativeReady,
      'active': PictureInPictureState.active,
      'checkpoint': PictureInPictureState.checkpoint,
      'restoring': PictureInPictureState.restoring,
      'stopped': PictureInPictureState.stopped,
      'completed': PictureInPictureState.completed,
      'failed': PictureInPictureState.failed,
    };

const Map<String, PictureInPictureTerminalReason> _nativeReasons =
    <String, PictureInPictureTerminalReason>{
      'system_return': PictureInPictureTerminalReason.systemReturn,
      'system_close': PictureInPictureTerminalReason.systemClose,
      'explicit_stop': PictureInPictureTerminalReason.explicitStop,
      'interrupted': PictureInPictureTerminalReason.interrupted,
      'completed': PictureInPictureTerminalReason.completed,
      'activity_destroyed': PictureInPictureTerminalReason.activityDestroyed,
      'flutter_engine_detached':
          PictureInPictureTerminalReason.flutterEngineDetached,
      'host_destroyed': PictureInPictureTerminalReason.hostDestroyed,
      'playback_error': PictureInPictureTerminalReason.playbackError,
    };

const Map<PictureInPictureTerminalReason, PictureInPictureState>
_terminalStateForReason =
    <PictureInPictureTerminalReason, PictureInPictureState>{
      PictureInPictureTerminalReason.systemReturn:
          PictureInPictureState.restoring,
      PictureInPictureTerminalReason.systemClose: PictureInPictureState.stopped,
      PictureInPictureTerminalReason.explicitStop:
          PictureInPictureState.stopped,
      PictureInPictureTerminalReason.interrupted: PictureInPictureState.stopped,
      PictureInPictureTerminalReason.completed: PictureInPictureState.completed,
      PictureInPictureTerminalReason.activityDestroyed:
          PictureInPictureState.stopped,
      PictureInPictureTerminalReason.flutterEngineDetached:
          PictureInPictureState.stopped,
      PictureInPictureTerminalReason.hostDestroyed:
          PictureInPictureState.stopped,
      PictureInPictureTerminalReason.playbackError:
          PictureInPictureState.failed,
    };

PictureInPictureFailureReason _failureReasonForCode(String code) =>
    switch (code) {
      'pip_unavailable' => PictureInPictureFailureReason.pipUnavailable,
      'unsupported' => PictureInPictureFailureReason.unsupported,
      'invalid_path' => PictureInPictureFailureReason.invalidPath,
      'busy' => PictureInPictureFailureReason.busy,
      'activity_unavailable' =>
        PictureInPictureFailureReason.activityUnavailable,
      'stale_session' => PictureInPictureFailureReason.staleSession,
      'bad_args' => PictureInPictureFailureReason.badArguments,
      _ => PictureInPictureFailureReason.platformFailure,
    };

PictureInPictureStartOutcome _startOutcomeForFailure(
  PictureInPictureFailureReason reason,
) => switch (reason) {
  PictureInPictureFailureReason.unsupportedPlatform =>
    PictureInPictureStartOutcome.unsupportedPlatform,
  PictureInPictureFailureReason.pipUnavailable =>
    PictureInPictureStartOutcome.pipUnavailable,
  PictureInPictureFailureReason.unsupported =>
    PictureInPictureStartOutcome.unsupported,
  PictureInPictureFailureReason.invalidPath =>
    PictureInPictureStartOutcome.invalidPath,
  PictureInPictureFailureReason.busy => PictureInPictureStartOutcome.busy,
  PictureInPictureFailureReason.activityUnavailable =>
    PictureInPictureStartOutcome.activityUnavailable,
  PictureInPictureFailureReason.staleSession =>
    PictureInPictureStartOutcome.staleSession,
  PictureInPictureFailureReason.badArguments =>
    PictureInPictureStartOutcome.badArguments,
  PictureInPictureFailureReason.channelFailure ||
  PictureInPictureFailureReason.platformFailure =>
    PictureInPictureStartOutcome.platformFailure,
};
