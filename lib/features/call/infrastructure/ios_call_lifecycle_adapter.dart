import 'dart:async';

import '../application/call_audio_controller.dart';
import '../application/call_coordinator.dart';
import '../application/handle_incoming_call_signal.dart';
import '../domain/call_end_reason.dart';
import '../domain/call_engine.dart';
import '../domain/call_id.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_state.dart';
import 'android_call_lifecycle_adapter.dart';

typedef IosCallMethodInvoker = NativeCallLifecycleMethodInvoker;
typedef IosNativeMuteApplier = NativeCallMuteApplier;
typedef IosAudioActivationDelay = Future<void> Function(Duration delay);

/// iOS system calling is authorized only when the complete canonical Dart
/// graph can be constructed. Merely registering native channels is inert.
bool isIosNativeCallCapabilityAuthorized(Map<String, bool> featureFlags) =>
    featureFlags['voice_call_capability_v1'] == true &&
    featureFlags['voice_call_incoming_enabled'] == true &&
    featureFlags['voice_call_turn_enabled'] == true &&
    featureFlags['voice_call_ios_native_enabled'] == true;

/// Removes persisted CallKit/PushKit capability when the iOS rollout gate is
/// off. Enabling remains owned by the authenticated, fully built adapter.
Future<void> enforceIosCallCapabilityRollback({
  required bool isIos,
  required bool capabilityEnabled,
  required IosCallMethodInvoker invokeMethod,
}) async {
  if (!isIos || capabilityEnabled) return;
  try {
    final disabled = await invokeMethod(
      'setCapabilityEnabled',
      const <String, Object?>{
        'version': IosCallLifecycleAdapter.protocolVersion,
        'enabled': false,
      },
    );
    if (disabled == true) return;
  } catch (_) {
    // The fixed-shape error below does not expose native values.
  }
  throw const IosCallLifecycleException(
    IosCallLifecycleErrorCode.nativeFailure,
  );
}

enum IosCallLifecycleErrorCode {
  closed,
  unavailable,
  malformedResponse,
  nativeFailure,
}

/// A fixed-shape iOS boundary error which never includes a call handle or
/// native payload.
final class IosCallLifecycleException implements Exception {
  const IosCallLifecycleException(this.code);

  final IosCallLifecycleErrorCode code;

  @override
  String toString() => 'IosCallLifecycleException(${code.name})';
}

final class IosCallAudioState {
  IosCallAudioState({
    required this.active,
    required this.muted,
    required this.route,
    required List<CallAudioOutputRoute> availableRoutes,
  }) : availableRoutes = List<CallAudioOutputRoute>.unmodifiable(
         availableRoutes,
       );

  final bool active;
  final bool muted;
  final CallAudioOutputRoute route;
  final List<CallAudioOutputRoute> availableRoutes;
}

/// Thin iOS boundary over the proven strict v1 native journal reconciler.
///
/// CallKit owns presentation and AVAudioSession timing; the wrapped reconciler
/// continues to bind every event to the one process-owned [CallCoordinator].
/// The wrapper deliberately exposes iOS channel constants and iOS-only error
/// values without copying the reconciliation state machine.
final class IosCallLifecycleAdapter
    implements
        NativeCallLifecycleInvalidations,
        NativeCallLifecycleAdapter,
        CallAudioOutputRouteChangeSource,
        ProvisionalNativeIncomingCallLifecycle {
  IosCallLifecycleAdapter({
    required IosCallMethodInvoker invokeMethod,
    required Stream<Object?> nativeEvents,
    required CallCoordinator coordinator,
    required AuthenticatedCallHandleResolver resolveAuthenticatedHandle,
    DateTime Function()? clock,
    int maxEventsPerBatch = 32,
    this.audioActivationMaxAttempts = 40,
    this.audioActivationRetryInterval = const Duration(milliseconds: 50),
    IosAudioActivationDelay? audioActivationDelay,
    NativeOutgoingRegistrationResultObserver? onOutgoingRegistrationResult,
  }) : _invokeMethod = invokeMethod,
       _audioActivationDelay =
           audioActivationDelay ?? _defaultAudioActivationDelay,
       _delegate = AndroidCallLifecycleAdapter(
         invokeMethod: invokeMethod,
         nativeEvents: nativeEvents,
         coordinator: coordinator,
         resolveAuthenticatedHandle: resolveAuthenticatedHandle,
         clock: clock,
         maxEventsPerBatch: maxEventsPerBatch,
         projectState: _projectIosState,
         projectTerminalBeforeEnd: true,
         requireAdoptionForAudio: true,
         failStartOnAttachError: true,
         onOutgoingRegistrationResult: onOutgoingRegistrationResult,
       ) {
    if (audioActivationMaxAttempts <= 0 ||
        audioActivationRetryInterval <= Duration.zero) {
      throw ArgumentError('iOS audio activation retry bounds must be positive');
    }
  }

  static const int protocolVersion =
      AndroidCallLifecycleAdapter.protocolVersion;
  static const String methodChannelName = 'mknoon/ios_call_lifecycle';
  static const String eventChannelName = 'mknoon/ios_call_lifecycle/events';
  static const int maxRetiredCallFences =
      AndroidCallLifecycleAdapter.maxRetiredCallFences;
  static const Duration outgoingRegistrationTtl =
      AndroidCallLifecycleAdapter.outgoingRegistrationTtl;

  final IosCallMethodInvoker _invokeMethod;
  final int audioActivationMaxAttempts;
  final Duration audioActivationRetryInterval;
  final IosAudioActivationDelay _audioActivationDelay;
  final AndroidCallLifecycleAdapter _delegate;

  @override
  Stream<CallAudioSessionInterruption> get interruptions =>
      _delegate.interruptions;

  Stream<bool> get muteChanges => _delegate.muteChanges;

  @override
  Stream<CallAudioOutputRoute> get outputRouteChanges =>
      _delegate.outputRouteChanges;

  @override
  bool get ownsSession => _delegate.ownsSession;

  @override
  CallAudioOutputRoute get selectedRoute => _delegate.selectedRoute;

  @override
  bool isBoundTo(CallId callId) => _delegate.isBoundTo(callId);

  @override
  void bindNativeMuteApplier(IosNativeMuteApplier applier) =>
      _delegate.bindNativeMuteApplier(applier);

  @override
  void notifyNativeMuteTargetReady(CallId callId) =>
      _delegate.notifyNativeMuteTargetReady(callId);

  @override
  Future<void> start() => _translate(_delegate.start());

  @override
  Future<bool> present(IncomingCallPresentation presentation) =>
      _translate(_delegate.present(presentation));

  @override
  Future<void> dismiss(IncomingCallPresentation presentation) =>
      _translate(_delegate.dismiss(presentation));

  @override
  Future<bool> reconcileBeforeOutgoing() =>
      _translate(_delegate.reconcileBeforeOutgoing());

  @override
  Future<bool> registerOutgoing(CallId callId, {required DateTime expiresAt}) =>
      _translate(_delegate.registerOutgoing(callId, expiresAt: expiresAt));

  Future<IosCallAudioState> readAudioState() async {
    final state = await _translate(_delegate.readAudioState());
    return IosCallAudioState(
      active: state.active,
      muted: state.muted,
      route: state.route,
      availableRoutes: state.availableRoutes,
    );
  }

  Future<void> requestRoute(CallAudioOutputRoute route) =>
      _translate(_delegate.requestRoute(route));

  /// CallKit may deliver `didActivate` or the native adoption replay just
  /// after authenticated acceptance reaches Dart. The real method channel
  /// reports that not-ready state immediately, so keep the media effect
  /// pending for one short, hard-bounded readiness window instead of
  /// terminalizing an otherwise valid call.
  Future<void> activateAudio() async {
    for (var attempt = 1; attempt <= audioActivationMaxAttempts; attempt++) {
      try {
        await _translate(_delegate.activateAudio());
        return;
      } on IosCallLifecycleException catch (error) {
        final readinessPending =
            error.code == IosCallLifecycleErrorCode.unavailable ||
            error.code == IosCallLifecycleErrorCode.nativeFailure;
        if (!readinessPending || attempt == audioActivationMaxAttempts) {
          rethrow;
        }
        await _audioActivationDelay(audioActivationRetryInterval);
      }
    }
  }

  Future<void> deactivateAudio() => _translate(_delegate.deactivateAudio());

  /// Routes an in-app Answer through CallKit (see the delegate).
  Future<bool> answer(CallId callId) => _delegate.answerNatively(callId);

  @override
  Stream<void> get invalidations => _delegate.invalidations;

  @override
  Future<void> authenticationFailed(String callHandle) => _invokeRequired(
    'authenticationFailed',
    <String, Object?>{'version': protocolVersion, 'callHandle': callHandle},
    valid: _validCallId(callHandle),
  );

  @override
  Future<void> remoteCancel(String callHandle) => _invokeRequired(
    'remoteCancel',
    <String, Object?>{'version': protocolVersion, 'callHandle': callHandle},
    valid: _validCallId(callHandle),
  );

  @override
  Future<void> expire(String callHandle) => _invokeRequired(
    'expire',
    <String, Object?>{'version': protocolVersion, 'callHandle': callHandle},
    valid: _validCallId(callHandle),
  );

  @override
  Future<void> updateAuthenticatedContact({
    required String callHandle,
    required String displayName,
  }) => _invokeRequired(
    'updateAuthenticatedContact',
    <String, Object?>{
      'version': protocolVersion,
      'callHandle': callHandle,
      'displayName': displayName,
    },
    valid:
        _validCallId(callHandle) &&
        displayName.trim() == displayName &&
        displayName.isNotEmpty &&
        displayName.length <= 128,
  );

  /// Publishes the recipient-authenticated display name for a call-only wake
  /// handle before a PushKit wake arrives. This boundary deliberately has no
  /// call descriptor or signaling identifier.
  Future<void> publishOpaqueContact({
    required String wakeHandle,
    required String displayName,
  }) => _invokeRequired(
    'publishOpaqueContact',
    <String, Object?>{
      'version': protocolVersion,
      'wakeHandle': wakeHandle,
      'displayName': displayName,
    },
    valid: _validWakeHandle(wakeHandle) && _validOpaqueDisplayName(displayName),
  );

  /// Revokes one pre-published call-only mapping without requiring an active
  /// or persisted call descriptor.
  Future<void> revokeOpaqueContactHandle(String wakeHandle) => _invokeRequired(
    'revokeOpaqueContactHandle',
    <String, Object?>{'version': protocolVersion, 'wakeHandle': wakeHandle},
    valid: _validWakeHandle(wakeHandle),
  );

  @override
  Future<void> revokeOpaqueContact(String callHandle) => _invokeRequired(
    'revokeOpaqueContact',
    <String, Object?>{'version': protocolVersion, 'callHandle': callHandle},
    valid: _validCallId(callHandle),
  );

  @override
  Future<void> activate() => activateAudio();

  @override
  Future<void> deactivate() => deactivateAudio();

  @override
  Future<List<CallAudioOutputRoute>> supportedOutputRoutes() =>
      _translate(_delegate.supportedOutputRoutes());

  @override
  Future<void> selectOutputRoute(CallAudioOutputRoute route) =>
      requestRoute(route);

  @override
  Future<void> close() => _translate(_delegate.close());

  /// Durably disables native iOS call delivery before relay authority is
  /// withdrawn. Literal native success is required because a false result can
  /// mean either the persisted capability or PushKit registration failed to
  /// converge.
  Future<void> disableCapability() => _invokeRequired(
    'setCapabilityEnabled',
    const <String, Object?>{'version': protocolVersion, 'enabled': false},
    valid: true,
  );

  /// Forces the native iOS boundary closed when token authority is withdrawn.
  /// The production graph closes this adapter immediately afterwards; this
  /// command removes any persisted CallKit presentation window first.
  Future<void> failClosed() async {
    try {
      final result = await _invokeMethod('failClosed', const <String, Object?>{
        'version': protocolVersion,
      });
      if (result != true) {
        throw const IosCallLifecycleException(
          IosCallLifecycleErrorCode.nativeFailure,
        );
      }
    } on IosCallLifecycleException {
      rethrow;
    } catch (_) {
      throw const IosCallLifecycleException(
        IosCallLifecycleErrorCode.nativeFailure,
      );
    }
  }

  Future<void> _invokeRequired(
    String method,
    Map<String, Object?> arguments, {
    required bool valid,
  }) async {
    if (!valid) {
      throw const IosCallLifecycleException(
        IosCallLifecycleErrorCode.unavailable,
      );
    }
    try {
      if (await _invokeMethod(method, arguments) != true) {
        throw const IosCallLifecycleException(
          IosCallLifecycleErrorCode.nativeFailure,
        );
      }
    } on IosCallLifecycleException {
      rethrow;
    } catch (_) {
      throw const IosCallLifecycleException(
        IosCallLifecycleErrorCode.nativeFailure,
      );
    }
  }

  static bool _validCallId(String value) => CallId.tryParse(value) != null;

  static Future<void> _defaultAudioActivationDelay(Duration delay) =>
      Future<void>.delayed(delay);

  static final RegExp _wakeHandlePattern = RegExp(
    r'^(?:[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})$',
  );

  static bool _validWakeHandle(String value) =>
      _wakeHandlePattern.hasMatch(value);

  static bool _validOpaqueDisplayName(String value) =>
      value.isNotEmpty &&
      value.trim() == value &&
      value.length <= 80 &&
      !value.runes.any(
        (scalar) => scalar <= 0x1f || (scalar >= 0x7f && scalar <= 0x9f),
      );

  static String _projectIosState(CallSessionSnapshot snapshot) {
    if (snapshot.isTerminal) {
      if (snapshot.endReason == CallEndReason.declined) return 'declined';
      if (const <CallEndReason>{
        CallEndReason.permissionDenied,
        CallEndReason.unsupported,
        CallEndReason.signalingFailed,
        CallEndReason.mediaFailed,
        CallEndReason.reconnectFailed,
        CallEndReason.policyRejected,
      }.contains(snapshot.endReason)) {
        return 'failed';
      }
      return 'ended';
    }
    return switch (snapshot.state) {
      CallState.incomingValidating || CallState.ringing => 'ringing',
      CallState.connected => 'connected',
      _ => 'connecting',
    };
  }

  static Future<T> _translate<T>(Future<T> operation) async {
    try {
      return await operation;
    } on AndroidCallLifecycleException catch (error) {
      throw IosCallLifecycleException(switch (error.code) {
        AndroidCallLifecycleErrorCode.closed =>
          IosCallLifecycleErrorCode.closed,
        AndroidCallLifecycleErrorCode.unavailable =>
          IosCallLifecycleErrorCode.unavailable,
        AndroidCallLifecycleErrorCode.malformedResponse =>
          IosCallLifecycleErrorCode.malformedResponse,
        AndroidCallLifecycleErrorCode.nativeFailure =>
          IosCallLifecycleErrorCode.nativeFailure,
      });
    }
  }
}
