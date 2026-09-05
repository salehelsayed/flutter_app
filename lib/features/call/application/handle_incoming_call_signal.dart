import '../../../core/utils/flow_event_emitter.dart';
import '../domain/call_end_reason.dart';
import '../domain/call_event.dart';
import '../domain/call_id.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_signal.dart';
import '../domain/call_state.dart';
import '../infrastructure/call_trusted_roster_provider.dart';
import '../infrastructure/secure_call_envelope_codec.dart';
import 'call_coordinator.dart';
import 'call_negotiation_material_store.dart';
import 'call_network_gate.dart';
import 'call_signaling_context_store.dart';
import 'incoming_call_pre_presentation_admission.dart';

export 'incoming_call_pre_presentation_admission.dart'
    show CallLocalAuthorityProvider, CallLocalDeviceAuthority;

enum IncomingCallSignalOutcome { accepted, duplicate, rejected, deferred }

final class IncomingCallSignalFrame {
  const IncomingCallSignalFrame({
    required this.envelopeJson,
    required this.authenticatedTransportPeerId,
    required this.route,
    this.expectedCallHandle,
    this.expectedMessageId,
    this.expectedExpiresAtMs,
    this.expectedRecipientDevicePeerId,
  });

  final String envelopeJson;
  final String authenticatedTransportPeerId;
  final CallRouteClass route;
  final String? expectedCallHandle;
  final String? expectedMessageId;
  final int? expectedExpiresAtMs;
  final String? expectedRecipientDevicePeerId;

  @override
  String toString() => 'IncomingCallSignalFrame(redacted)';
}

final class IncomingCallPresentation {
  const IncomingCallPresentation({
    required this.callId,
    required this.callerAccountPeerId,
    required this.expiresAt,
  });

  final CallId callId;
  final String callerAccountPeerId;
  final DateTime expiresAt;

  @override
  String toString() => 'IncomingCallPresentation(redacted)';
}

abstract interface class IncomingCallPresenter {
  /// Returns true only after the platform call surface has been accepted.
  /// Ringing signaling is forbidden until this completes successfully.
  Future<bool> present(IncomingCallPresentation presentation);

  /// Removes a surface that completed after the call was already terminal or
  /// expired. Implementations must be idempotent.
  Future<void> dismiss(IncomingCallPresentation presentation);
}

typedef AuthenticatedCallDisplayNameResolver =
    Future<String?> Function(String contactAccountPeerId);

/// Optional iOS provisional-call boundary. Every argument is an opaque call
/// handle; wake-authority/contact handles remain native-private.
abstract interface class ProvisionalNativeIncomingCallLifecycle {
  Future<void> authenticationFailed(String callHandle);

  Future<void> remoteCancel(String callHandle);

  Future<void> expire(String callHandle);

  Future<void> updateAuthenticatedContact({
    required String callHandle,
    required String displayName,
  });

  Future<void> revokeOpaqueContact(String callHandle);
}

final class NoopIncomingCallPresenter implements IncomingCallPresenter {
  const NoopIncomingCallPresenter();

  @override
  Future<bool> present(IncomingCallPresentation presentation) async => false;

  @override
  Future<void> dismiss(IncomingCallPresentation presentation) async {}
}

/// Authenticates one direct/mailbox frame and maps the canonical signal into
/// the single process-wide coordinator. No chat, outbox, retry, or ordinary
/// notification service participates in this path.
final class HandleIncomingCallSignal {
  HandleIncomingCallSignal({
    required SecureCallEnvelopeCodec codec,
    required CallCoordinator coordinator,
    required CallTrustedRosterProvider trustedRosterProvider,
    required CallLocalAuthorityProvider localAuthorityProvider,
    required IncomingCallPresenter incomingCallPresenter,
    required CallNetworkEffectsAllowed networkEffectsAllowed,
    CallNegotiationMaterialStore? negotiationMaterialStore,
    AuthenticatedCallSignalingContextObserver? signalingContextObserver,
    ProvisionalNativeIncomingCallLifecycle? provisionalNativeLifecycle,
    AuthenticatedCallDisplayNameResolver? authenticatedDisplayNameResolver,
    Duration provisionalNativeTerminalTimeout = const Duration(seconds: 2),
  }) : assert(provisionalNativeTerminalTimeout > Duration.zero),
       _admission = IncomingCallPrePresentationAdmission(
         codec: codec,
         trustedRosterProvider: trustedRosterProvider,
         localAuthorityProvider: localAuthorityProvider,
       ),
       _coordinator = coordinator,
       _incomingCallPresenter = incomingCallPresenter,
       _networkEffectsAllowed = networkEffectsAllowed,
       _provisionalNativeLifecycle = provisionalNativeLifecycle,
       _provisionalNativeTerminalTimeout = provisionalNativeTerminalTimeout,
       _authenticatedDisplayNameResolver = authenticatedDisplayNameResolver,
       _signalingContextObserver = signalingContextObserver,
       _negotiationMaterialStore =
           negotiationMaterialStore ?? CallNegotiationMaterialStore();

  final IncomingCallPrePresentationAdmission _admission;
  final CallCoordinator _coordinator;
  final IncomingCallPresenter _incomingCallPresenter;
  final CallNetworkEffectsAllowed _networkEffectsAllowed;
  final ProvisionalNativeIncomingCallLifecycle? _provisionalNativeLifecycle;
  final Duration _provisionalNativeTerminalTimeout;
  final AuthenticatedCallDisplayNameResolver? _authenticatedDisplayNameResolver;
  final AuthenticatedCallSignalingContextObserver? _signalingContextObserver;
  final CallNegotiationMaterialStore _negotiationMaterialStore;

  Future<IncomingCallSignalOutcome> handle(
    IncomingCallSignalFrame frame,
  ) async {
    try {
      if (!await callNetworkEffectsAreAllowed(_networkEffectsAllowed)) {
        return IncomingCallSignalOutcome.deferred;
      }
    } catch (_) {
      return IncomingCallSignalOutcome.deferred;
    }

    final expectedExpiry = frame.expectedExpiresAtMs;
    final expectedHandle = frame.expectedCallHandle;
    if (expectedExpiry != null &&
        expectedHandle != null &&
        _coordinator.clock().millisecondsSinceEpoch >= expectedExpiry) {
      await _expireSafely(expectedHandle);
      return IncomingCallSignalOutcome.rejected;
    }

    AuthenticatedIncomingCallAdmission? admitted;
    CallNegotiationMaterial? stagedMaterial;
    CallSignal? capturedSignal;

    IncomingCallSignalOutcome settle(IncomingCallSignalOutcome outcome) {
      final signal = capturedSignal;
      if (signal != null && _shouldPurgeSignalingContext(signal, outcome)) {
        _purgeSignalingContextSafely(signal.callId);
      }
      return outcome;
    }

    try {
      admitted = await _admission.authenticateSignal(
        envelopeJson: frame.envelopeJson,
        authenticatedTransportPeerId: frame.authenticatedTransportPeerId,
        expectedCallHandle: frame.expectedCallHandle,
        expectedMessageId: frame.expectedMessageId,
        expectedExpiresAtMs: frame.expectedExpiresAtMs,
        expectedRecipientDevicePeerId: frame.expectedRecipientDevicePeerId,
      );
      final signal = admitted.signal;

      _signalingContextObserver?.captureAuthenticated(
        signal: signal,
        callHandle: admitted.callHandle,
      );
      capturedSignal = signal;
      // A PushKit-first call already has a native descriptor, so the verified
      // name lands now; a Dart-first call gets its descriptor in `present`
      // below and is retried right after it (see contactNameApplied).
      var contactNameApplied = false;
      if (signal.event == CallSignalType.invite) {
        contactNameApplied = await _updateAuthenticatedContactSafely(
          admitted.callHandle,
          signal.senderAccountPeerId,
        );
      }

      if (_hasNegotiationMaterial(signal.event)) {
        stagedMaterial = CallNegotiationMaterial.fromSignal(signal);
        final storeDecision = _negotiationMaterialStore.store(stagedMaterial);
        if (storeDecision != CallNegotiationMaterialStoreDecision.stored) {
          admitted.commitReplay();
          return settle(
            storeDecision == CallNegotiationMaterialStoreDecision.duplicate
                ? IncomingCallSignalOutcome.duplicate
                : IncomingCallSignalOutcome.rejected,
          );
        }
      }

      final isAuthenticatedRemoteTerminal =
          signal.event == CallSignalType.reject ||
          signal.event == CallSignalType.terminate;
      if (isAuthenticatedRemoteTerminal) {
        // CallKit's snapshot subscriber projects terminal coordinator state as
        // a generic end. Retire the authenticated native presentation first so
        // the OS records the authoritative remote-cancel reason instead.
        await _remoteCancelSafely(admitted.callHandle);
      }
      final reduction = await _coordinator.dispatch(
        _toCoordinatorEvent(signal, frame.route),
      );
      _settleNegotiationMaterial(stagedMaterial, reduction);
      final initialOutcome = _outcome(reduction);
      if (signal.event != CallSignalType.invite) {
        admitted.commitReplay();
        return settle(initialOutcome);
      }
      final resumableInvite = _canResumeIncomingInvite(
        _coordinator.activeSession,
        signal,
      );
      if (initialOutcome != IncomingCallSignalOutcome.accepted &&
          !(initialOutcome == IncomingCallSignalOutcome.duplicate &&
              resumableInvite)) {
        if (initialOutcome == IncomingCallSignalOutcome.rejected) {
          await _remoteCancelSafely(admitted.callHandle);
        }
        admitted.commitReplay();
        return settle(initialOutcome);
      }

      final validated = await _coordinator.dispatch(
        _derivedEvent(
          signal,
          CallEventType.incomingValidated,
          'validated',
          frame.route,
        ),
      );
      if (validated.decision != CallEventDecision.applied) {
        final active = _coordinator.activeSession;
        if (!_canResumeIncomingInvite(active, signal) ||
            active?.incomingValidated != true ||
            _outcome(validated) != IncomingCallSignalOutcome.duplicate) {
          admitted.commitReplay();
          await _remoteCancelSafely(admitted.callHandle);
          return settle(_outcome(validated));
        }
      }

      final presentation = IncomingCallPresentation(
        callId: signal.callId,
        callerAccountPeerId: signal.senderAccountPeerId,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          signal.expiresAtMs,
          isUtc: true,
        ),
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'CALL_INCOMING_PRESENTATION_ATTEMPT',
        details: const <String, Object?>{},
      );
      var presented = false;
      var presentationThrew = false;
      try {
        presented = await _incomingCallPresenter.present(presentation);
      } catch (_) {
        presentationThrew = true;
        presented = false;
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'CALL_INCOMING_PRESENTATION_RESULT',
        details: <String, Object?>{
          'presented': presented,
          'threw': presentationThrew,
        },
      );
      final now = _coordinator.clock();
      final activeAfterPresentation = _coordinator.activeSession;
      final expiredAfterPresentation =
          now.millisecondsSinceEpoch >= signal.expiresAtMs;
      final canAdoptPresentation =
          _canResumeIncomingInvite(activeAfterPresentation, signal) &&
          activeAfterPresentation?.incomingValidated == true &&
          !expiredAfterPresentation;
      if (!canAdoptPresentation) {
        if (presented) await _dismissSafely(presentation);
        if (expiredAfterPresentation) {
          await _expireSafely(admitted.callHandle);
        } else {
          await _remoteCancelSafely(admitted.callHandle);
        }
        if (expiredAfterPresentation &&
            activeAfterPresentation?.callId == signal.callId &&
            activeAfterPresentation?.isTerminal == false) {
          await _coordinator.dispatch(
            CallEvent(
              type: CallEventType.timeout,
              eventId: '${signal.messageId}:presentation-expired',
              occurredAt: now,
              callId: signal.callId,
              contactPeerId: signal.senderAccountPeerId,
              remoteAccountPeerId: signal.senderAccountPeerId,
              remoteDeviceId: signal.senderDevicePeerId,
              timeoutKind: CallTimeoutKind.inviteExpiry,
            ),
          );
        }
        admitted.commitReplay();
        return settle(IncomingCallSignalOutcome.rejected);
      }
      if (!presented) {
        await _authenticationFailedSafely(admitted.callHandle);
        await _coordinator.dispatch(
          CallEvent(
            type: CallEventType.negotiationFailed,
            eventId: '${signal.messageId}:presentation-failed',
            occurredAt: _occurredAt(signal),
            callId: signal.callId,
            contactPeerId: signal.senderAccountPeerId,
            remoteAccountPeerId: signal.senderAccountPeerId,
            remoteDeviceId: signal.senderDevicePeerId,
            endReason: CallEndReason.permissionDenied,
          ),
        );
        admitted.commitReplay();
        return settle(IncomingCallSignalOutcome.rejected);
      }

      if (!contactNameApplied && signal.event == CallSignalType.invite) {
        // The presentation created the native descriptor: apply the verified
        // caller name now so CallKit never stays on the generic label.
        await _updateAuthenticatedContactSafely(
          admitted.callHandle,
          signal.senderAccountPeerId,
        );
      }

      final shown = await _coordinator.dispatch(
        _derivedEvent(
          signal,
          CallEventType.systemUiPresented,
          'system-ui',
          frame.route,
        ),
      );
      if (shown.decision != CallEventDecision.applied) {
        await _dismissSafely(presentation);
        await _remoteCancelSafely(admitted.callHandle);
        admitted.commitReplay();
        return settle(IncomingCallSignalOutcome.rejected);
      }
      admitted.commitReplay();
      return settle(_outcome(shown));
    } on IncomingCallPrePresentationAdmissionException catch (error) {
      final outcome = switch (error.code) {
        IncomingCallPrePresentationAdmissionFailureCode.duplicate =>
          IncomingCallSignalOutcome.duplicate,
        IncomingCallPrePresentationAdmissionFailureCode.permanentReject =>
          IncomingCallSignalOutcome.rejected,
        IncomingCallPrePresentationAdmissionFailureCode.deferred =>
          IncomingCallSignalOutcome.deferred,
      };
      if (error.code ==
              IncomingCallPrePresentationAdmissionFailureCode.permanentReject &&
          frame.expectedCallHandle != null) {
        await _revokeOpaqueContactSafely(frame.expectedCallHandle!);
        await _authenticationFailedSafely(frame.expectedCallHandle!);
      }
      return settle(outcome);
    } catch (_) {
      _settleNegotiationMaterialAfterFailure(stagedMaterial);
      admitted?.rollbackReplay();
      return settle(IncomingCallSignalOutcome.deferred);
    }
  }

  bool _shouldPurgeSignalingContext(
    CallSignal signal,
    IncomingCallSignalOutcome outcome,
  ) {
    final live = _coordinator.activeSession;
    if (live != null && live.callId == signal.callId && !live.isTerminal) {
      // The signal belongs to the live call. Every later control and
      // negotiation send reads this context, so a stray or rejected signal
      // (a stale candidate, a duplicate offer) must never strip it. Terminal
      // cleanup purges it when the call ends.
      return false;
    }
    if (outcome == IncomingCallSignalOutcome.rejected ||
        signal.event == CallSignalType.reject ||
        signal.event == CallSignalType.terminate) {
      return true;
    }
    final active = _coordinator.activeSession;
    if (active?.callId == signal.callId && active?.isTerminal == true) {
      return true;
    }
    final last = _coordinator.lastSnapshot;
    return last?.callId == signal.callId && last?.isTerminal == true;
  }

  void _purgeSignalingContextSafely(CallId callId) {
    try {
      _signalingContextObserver?.purge(callId);
    } catch (_) {
      // Context disposal remains privacy-safe and cannot change wire outcome.
    }
  }

  Future<void> _dismissSafely(IncomingCallPresentation presentation) async {
    try {
      await _incomingCallPresenter.dismiss(presentation);
    } catch (_) {
      // Cleanup remains fail closed and never reveals call authority values.
    }
  }

  Future<void> _authenticationFailedSafely(String callHandle) async {
    try {
      await _provisionalNativeLifecycle?.authenticationFailed(callHandle);
    } catch (_) {
      // Canonical rejection remains authoritative if native is already gone.
    }
  }

  Future<void> _remoteCancelSafely(String callHandle) async {
    try {
      final lifecycle = _provisionalNativeLifecycle;
      if (lifecycle == null) return;
      await lifecycle
          .remoteCancel(callHandle)
          .timeout(_provisionalNativeTerminalTimeout);
    } catch (_) {
      // Canonical terminal state remains authoritative.
    }
  }

  Future<void> _expireSafely(String callHandle) async {
    try {
      await _provisionalNativeLifecycle?.expire(callHandle);
    } catch (_) {
      // Expiry remains fail closed even if native already retired the call.
    }
  }

  /// Returns true only when native accepted the verified display name for a
  /// live descriptor of [callHandle]. A refusal (no descriptor yet, or any
  /// native failure) keeps the privacy-safe generic label and is retryable.
  Future<bool> _updateAuthenticatedContactSafely(
    String callHandle,
    String contactAccountPeerId,
  ) async {
    final resolver = _authenticatedDisplayNameResolver;
    final lifecycle = _provisionalNativeLifecycle;
    if (resolver == null || lifecycle == null) return false;
    try {
      final displayName = (await resolver(contactAccountPeerId))?.trim();
      if (displayName == null ||
          displayName.isEmpty ||
          displayName.length > 128) {
        return false;
      }
      await lifecycle.updateAuthenticatedContact(
        callHandle: callHandle,
        displayName: displayName,
      );
      return true;
    } catch (_) {
      // The privacy-safe generic native label remains valid.
      return false;
    }
  }

  Future<void> _revokeOpaqueContactSafely(String callHandle) async {
    try {
      await _provisionalNativeLifecycle?.revokeOpaqueContact(callHandle);
    } catch (_) {
      // Authentication rejection below still retires the provisional call.
    }
  }

  static bool _canResumeIncomingInvite(
    CallSessionSnapshot? active,
    CallSignal signal,
  ) =>
      active?.callId == signal.callId &&
      active?.direction == CallDirection.incoming &&
      active?.state == CallState.incomingValidating;

  static CallEvent _toCoordinatorEvent(
    CallSignal signal,
    CallRouteClass route,
  ) => CallEvent(
    type: switch (signal.event) {
      CallSignalType.invite => CallEventType.remoteInvite,
      CallSignalType.ringing => CallEventType.remoteRinging,
      CallSignalType.accept => CallEventType.remoteAccept,
      CallSignalType.reject => CallEventType.remoteReject,
      CallSignalType.offer => CallEventType.remoteOffer,
      CallSignalType.answer => CallEventType.remoteAnswer,
      CallSignalType.ice => CallEventType.remoteIce,
      CallSignalType.iceRestart => CallEventType.remoteIceRestart,
      CallSignalType.terminate => CallEventType.remoteTerminate,
    },
    eventId: signal.messageId,
    occurredAt: _occurredAt(signal),
    callId: signal.callId,
    contactPeerId: signal.senderAccountPeerId,
    localAccountPeerId: signal.recipientAccountPeerId,
    localDeviceId: signal.recipientDevicePeerId,
    remoteAccountPeerId: signal.senderAccountPeerId,
    remoteDeviceId: signal.senderDevicePeerId,
    expiresAt: DateTime.fromMillisecondsSinceEpoch(
      signal.expiresAtMs,
      isUtc: true,
    ),
    admission: IncomingCallAdmission.accepted,
    endReason: _endReason(signal),
    candidateId: signal.event == CallSignalType.ice ? signal.messageId : null,
    transportRoute: route,
  );

  static CallEvent _derivedEvent(
    CallSignal signal,
    CallEventType type,
    String suffix,
    CallRouteClass route,
  ) => CallEvent(
    type: type,
    eventId: '${signal.messageId}:$suffix',
    occurredAt: _occurredAt(signal),
    callId: signal.callId,
    contactPeerId: signal.senderAccountPeerId,
    localAccountPeerId: signal.recipientAccountPeerId,
    localDeviceId: signal.recipientDevicePeerId,
    remoteAccountPeerId: signal.senderAccountPeerId,
    remoteDeviceId: signal.senderDevicePeerId,
    expiresAt: DateTime.fromMillisecondsSinceEpoch(
      signal.expiresAtMs,
      isUtc: true,
    ),
    admission: IncomingCallAdmission.accepted,
    transportRoute: route,
  );

  static DateTime _occurredAt(CallSignal signal) =>
      DateTime.fromMillisecondsSinceEpoch(signal.createdAtMs, isUtc: true);

  static bool _hasNegotiationMaterial(CallSignalType type) => switch (type) {
    CallSignalType.offer ||
    CallSignalType.answer ||
    CallSignalType.ice ||
    CallSignalType.iceRestart => true,
    _ => false,
  };

  void _settleNegotiationMaterial(
    CallNegotiationMaterial? material,
    CallReduction reduction,
  ) {
    final callId = reduction.snapshot.callId ?? material?.callId;
    if (callId != null && reduction.snapshot.isTerminal) {
      _negotiationMaterialStore.purgeCall(callId);
      return;
    }
    if (material == null) return;
    if (reduction.decision == CallEventDecision.applied) {
      _negotiationMaterialStore.commitEvent(material.callId, material.eventId);
    } else {
      _negotiationMaterialStore.purgeEvent(material.callId, material.eventId);
    }
  }

  void _settleNegotiationMaterialAfterFailure(
    CallNegotiationMaterial? material,
  ) {
    if (material == null) return;
    final snapshot = _coordinator.activeSession?.callId == material.callId
        ? _coordinator.activeSession
        : _coordinator.lastSnapshot?.callId == material.callId
        ? _coordinator.lastSnapshot
        : null;
    if (snapshot?.isTerminal == true) {
      _negotiationMaterialStore.purgeCall(material.callId);
    } else if (snapshot?.recentEventIds.contains(material.eventId) == true) {
      _negotiationMaterialStore.commitEvent(material.callId, material.eventId);
    } else {
      _negotiationMaterialStore.purgeEvent(material.callId, material.eventId);
    }
  }

  static CallEndReason? _endReason(CallSignal signal) {
    if (signal.event != CallSignalType.reject &&
        signal.event != CallSignalType.terminate) {
      return null;
    }
    return CallEndReason.parseWire(signal.payload['reason']! as String);
  }

  static IncomingCallSignalOutcome _outcome(CallReduction reduction) {
    if (reduction.decision == CallEventDecision.applied) {
      return IncomingCallSignalOutcome.accepted;
    }
    if (reduction.reason == CallReductionReason.duplicateEvent ||
        reduction.reason == CallReductionReason.duplicateSession ||
        reduction.reason == CallReductionReason.terminalDominates) {
      return IncomingCallSignalOutcome.duplicate;
    }
    return IncomingCallSignalOutcome.rejected;
  }
}
