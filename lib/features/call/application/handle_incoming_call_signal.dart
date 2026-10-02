import 'dart:async';

import '../../../core/utils/flow_event_emitter.dart';
import '../diagnostics/call_diagnostics.dart';
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

enum IncomingCallSignalOutcome {
  accepted,
  duplicate,
  rejected,
  deferred,

  /// An invite whose call the caller already ended within the same mailbox
  /// page. It is acknowledged without ringing or dispatch.
  superseded,
}

/// Flow event recorded once for every incoming call signal that does not end
/// [IncomingCallSignalOutcome.accepted]. Its details hold fixed codes only:
/// never call ids, handles, peer ids, or envelope content.
const String incomingCallSignalNotAcceptedEvent =
    'CALL_INCOMING_SIGNAL_NOT_ACCEPTED';

/// Closed reason codes for [incomingCallSignalNotAcceptedEvent]. Each names
/// the gate that refused the signal. Admission gates add
/// [IncomingCallPrePresentationAdmissionException.reasonCode] values such as
/// `sender_unknown` or `envelope_excessiveClockSkew`.
abstract final class IncomingCallSignalRefusal {
  static const networkEffectsBlocked = 'network_effects_blocked';
  static const expiredBeforeAuthentication = 'expired_before_authentication';
  static const superseded = 'superseded';
  static const expiredDuringPresentation = 'expired_during_presentation';
  static const sessionChangedDuringPresentation =
      'session_changed_during_presentation';
  static const presentationFailed = 'presentation_failed';
  static const systemUiRejected = 'system_ui_rejected';
  static const handlerException = 'handler_exception';
  static const laneSaturated = 'lane_saturated';
  static const runtimeDisposed = 'runtime_disposed';

  static String negotiationMaterial(
    CallNegotiationMaterialStoreDecision decision,
  ) => 'negotiation_material_${decision.name}';

  static String coordinator(CallEventDecision decision) =>
      'coordinator_${decision.name}';

  static String validation(CallEventDecision decision) =>
      'validation_${decision.name}';
}

/// Records one incoming call signal that was not accepted. [signal] is known
/// only after authentication. Never throws.
void emitIncomingCallSignalNotAccepted({
  required CallRouteClass route,
  required IncomingCallSignalOutcome outcome,
  required String reason,
  CallSignalType? signal,
  CallReductionReason? reduction,
}) {
  try {
    emitFlowEvent(
      layer: 'FL',
      event: incomingCallSignalNotAcceptedEvent,
      details: <String, Object?>{
        'route': switch (route) {
          CallRouteClass.direct => 'direct',
          CallRouteClass.circuitRelay => 'relay',
          CallRouteClass.ephemeralMailbox => 'mailbox',
        },
        'signal': signal?.wireName ?? 'unknown',
        'outcome': outcome.name,
        'reason': reason,
        if (reduction != null) 'reduction': reduction.name,
      },
    );
  } catch (_) {
    // Diagnostics never change call handling.
  }
}

/// Proof produced only after the ordinary authenticated terminal handling
/// path commits replay custody. It never authorizes presentation or media.
final class AuthenticatedIncomingCallTerminal {
  const AuthenticatedIncomingCallTerminal._({
    required this.callHandle,
    required this.signal,
  });

  final String callHandle;
  final CallSignal signal;

  @override
  String toString() => 'AuthenticatedIncomingCallTerminal(redacted)';
}

final class IncomingCallMailboxHandlingResult {
  const IncomingCallMailboxHandlingResult({
    required this.outcome,
    this.authenticatedTerminal,
  });

  final IncomingCallSignalOutcome outcome;
  final AuthenticatedIncomingCallTerminal? authenticatedTerminal;
}

/// What a mailbox event is, read without consuming it. Lets a drain see that
/// a terminal signal follows an invite before either is handled.
final class IncomingCallSignalPeek {
  const IncomingCallSignalPeek({required this.callId, required this.event});

  final CallId callId;
  final CallSignalType event;

  bool get isInvite => event == CallSignalType.invite;

  bool get isTerminal =>
      event == CallSignalType.reject || event == CallSignalType.terminate;

  @override
  String toString() => 'IncomingCallSignalPeek(redacted)';
}

final class IncomingCallSignalFrame {
  const IncomingCallSignalFrame({
    required this.envelopeJson,
    required this.authenticatedTransportPeerId,
    required this.route,
    this.expectedCallHandle,
    this.expectedMessageId,
    this.expectedExpiresAtMs,
    this.expectedRecipientDevicePeerId,
    this.terminalFollows = false,
  });

  final String envelopeJson;
  final String authenticatedTransportPeerId;
  final CallRouteClass route;
  final String? expectedCallHandle;
  final String? expectedMessageId;
  final int? expectedExpiresAtMs;
  final String? expectedRecipientDevicePeerId;

  /// A terminal signal for the same call sits behind this frame in the same
  /// mailbox page: the caller already ended the call this invite announces.
  final bool terminalFollows;

  @override
  String toString() => 'IncomingCallSignalFrame(redacted)';
}

final class IncomingCallPresentation {
  const IncomingCallPresentation({
    required this.callId,
    required this.callerAccountPeerId,
    required this.expiresAt,
    this.displayName,
  });

  final CallId callId;
  final String callerAccountPeerId;
  final DateTime expiresAt;
  final String? displayName;

  @override
  String toString() => 'IncomingCallPresentation(redacted)';
}

/// A valid invite cannot be surfaced in this runtime configuration.
final class IncomingCallPresentationUnavailable implements Exception {
  const IncomingCallPresentationUnavailable();
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

typedef AndroidAuthenticatedContactPresenter =
    Future<bool> Function(CallId callId, String displayName);

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
    AndroidAuthenticatedContactPresenter? androidAuthenticatedContactPresenter,
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
       _androidAuthenticatedContactPresenter =
           androidAuthenticatedContactPresenter,
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
  final AndroidAuthenticatedContactPresenter?
  _androidAuthenticatedContactPresenter;
  final AuthenticatedCallSignalingContextObserver? _signalingContextObserver;
  final CallNegotiationMaterialStore _negotiationMaterialStore;

  /// Authenticates [frame] and reports its call and event without consuming
  /// it: the replay reservation is rolled back so [handle] can admit the same
  /// envelope afterwards. Any failure reads as null.
  Future<IncomingCallSignalPeek?> peek(IncomingCallSignalFrame frame) async {
    AuthenticatedIncomingCallAdmission admitted;
    try {
      admitted = await _admission.authenticateSignal(
        envelopeJson: frame.envelopeJson,
        authenticatedTransportPeerId: frame.authenticatedTransportPeerId,
        expectedCallHandle: frame.expectedCallHandle,
        expectedMessageId: frame.expectedMessageId,
        expectedExpiresAtMs: frame.expectedExpiresAtMs,
        expectedRecipientDevicePeerId: frame.expectedRecipientDevicePeerId,
      );
    } catch (_) {
      return null;
    }
    try {
      return IncomingCallSignalPeek(
        callId: admitted.signal.callId,
        event: admitted.signal.event,
      );
    } finally {
      admitted.rollbackReplay();
    }
  }

  Future<IncomingCallSignalOutcome> handle(IncomingCallSignalFrame frame) =>
      _handle(frame);

  Future<IncomingCallMailboxHandlingResult> handleMailbox(
    IncomingCallSignalFrame frame,
  ) async {
    AuthenticatedIncomingCallTerminal? terminal;
    final outcome = await _handle(
      frame,
      onCommittedTerminal: (proof) => terminal = proof,
    );
    return IncomingCallMailboxHandlingResult(
      outcome: outcome,
      authenticatedTerminal: terminal,
    );
  }

  Future<IncomingCallSignalOutcome> _handle(
    IncomingCallSignalFrame frame, {
    void Function(AuthenticatedIncomingCallTerminal)? onCommittedTerminal,
  }) async {
    // Every outcome other than accepted leaves one record naming its gate.
    IncomingCallSignalOutcome refused(
      IncomingCallSignalOutcome outcome,
      String reason, {
      CallSignalType? signal,
      CallReductionReason? reduction,
    }) {
      emitIncomingCallSignalNotAccepted(
        route: frame.route,
        outcome: outcome,
        reason: reason,
        signal: signal,
        reduction: reduction,
      );
      return outcome;
    }

    var networkEffectsAllowed = false;
    try {
      networkEffectsAllowed = await callNetworkEffectsAreAllowed(
        _networkEffectsAllowed,
      );
    } catch (_) {
      networkEffectsAllowed = false;
    }
    if (!networkEffectsAllowed) {
      return refused(
        IncomingCallSignalOutcome.deferred,
        IncomingCallSignalRefusal.networkEffectsBlocked,
      );
    }

    final expectedExpiry = frame.expectedExpiresAtMs;
    final expectedHandle = frame.expectedCallHandle;
    if (expectedExpiry != null &&
        expectedHandle != null &&
        _coordinator.clock().millisecondsSinceEpoch >= expectedExpiry) {
      await _expireSafely(expectedHandle);
      return refused(
        IncomingCallSignalOutcome.rejected,
        IncomingCallSignalRefusal.expiredBeforeAuthentication,
      );
    }

    AuthenticatedIncomingCallAdmission? admitted;
    CallNegotiationMaterial? stagedMaterial;
    CallSignal? capturedSignal;
    CallSignalType? authenticatedEvent;

    IncomingCallSignalOutcome settle(
      IncomingCallSignalOutcome outcome,
      String reason, {
      CallReductionReason? reduction,
    }) {
      final signal = capturedSignal;
      if (signal != null && _shouldPurgeSignalingContext(signal, outcome)) {
        _purgeSignalingContextSafely(signal.callId);
      }
      if (outcome == IncomingCallSignalOutcome.accepted) return outcome;
      return refused(
        outcome,
        reason,
        signal: authenticatedEvent,
        reduction: reduction,
      );
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
      authenticatedEvent = signal.event;
      final diagnostics = CallDiagnostics.instance;
      final existingTrace = diagnostics.traceForCall(
        callId: signal.callId.value,
        callHandle: admitted.callHandle,
      );
      final traceId =
          existingTrace ??
          (signal.event == CallSignalType.invite
              ? diagnostics.beginAttempt(role: 'callee')
              : null);
      if (traceId != null) {
        diagnostics.bindCall(
          callId: signal.callId.value,
          callHandle: admitted.callHandle,
          traceId: traceId,
          role:
              signal.event == CallSignalType.invite ||
                  _coordinator.activeSession?.direction ==
                      CallDirection.incoming
              ? 'callee'
              : 'caller',
        );
        diagnostics.record(
          stage: 'signaling',
          action: 'receive',
          outcome: 'ok',
          traceId: traceId,
        );
        if (signal.event == CallSignalType.invite && existingTrace == null) {
          final callHandle = admitted.callHandle;
          unawaited(
            diagnostics.resolveTraceForCall(callHandle: callHandle).then((
              resolved,
            ) {
              if (resolved != null) {
                diagnostics.bindCall(
                  callId: signal.callId.value,
                  callHandle: callHandle,
                  traceId: resolved,
                  role: 'callee',
                );
              }
            }),
          );
        }
      }

      if (signal.event == CallSignalType.invite && frame.terminalFollows) {
        // Ringing now would announce a call that is already over. The
        // terminal signal behind this invite still retires any native
        // presentation the wake made for it.
        emitFlowEvent(
          layer: 'FL',
          event: 'CALL_INCOMING_INVITE_SUPERSEDED',
          details: const <String, Object?>{},
        );
        admitted.commitReplay();
        return settle(
          IncomingCallSignalOutcome.superseded,
          IncomingCallSignalRefusal.superseded,
        );
      }

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
            IncomingCallSignalRefusal.negotiationMaterial(storeDecision),
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
      // Media preparation can wait for permission or TURN. Once admitted,
      // release the inbound lane so a subsequent remote hang-up can interrupt
      // it. The coordinator still owns effect failures and terminal cleanup.
      final admission =
          signal.event == CallSignalType.accept ||
              signal.event == CallSignalType.offer
          ? Completer<CallReduction>()
          : null;
      final dispatch = _coordinator.dispatch(
        _toCoordinatorEvent(signal, frame.route),
        onApplied: admission?.complete,
      );
      final reduction = await (admission == null
          ? dispatch
          : Future.any<CallReduction>(<Future<CallReduction>>[
              admission.future,
              dispatch,
            ]));
      _settleNegotiationMaterial(stagedMaterial, reduction);
      final initialOutcome = _outcome(reduction);
      if (signal.event != CallSignalType.invite) {
        admitted.commitReplay();
        if (isAuthenticatedRemoteTerminal &&
            frame.route == CallRouteClass.ephemeralMailbox &&
            frame.expectedCallHandle == admitted.callHandle &&
            frame.expectedMessageId == signal.messageId &&
            frame.expectedExpiresAtMs == signal.expiresAtMs &&
            frame.expectedRecipientDevicePeerId ==
                signal.recipientDevicePeerId) {
          onCommittedTerminal?.call(
            AuthenticatedIncomingCallTerminal._(
              callHandle: admitted.callHandle,
              signal: signal,
            ),
          );
        }
        return settle(
          initialOutcome,
          IncomingCallSignalRefusal.coordinator(reduction.decision),
          reduction: reduction.reason,
        );
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
        return settle(
          initialOutcome,
          IncomingCallSignalRefusal.coordinator(reduction.decision),
          reduction: reduction.reason,
        );
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
          return settle(
            _outcome(validated),
            IncomingCallSignalRefusal.validation(validated.decision),
            reduction: validated.reason,
          );
        }
      }

      String? initialDisplayName;
      try {
        final name = (await _authenticatedDisplayNameResolver?.call(
          signal.senderAccountPeerId,
        ))?.trim();
        if (name != null && name.isNotEmpty && name.length <= 128) {
          initialDisplayName = name;
        }
      } catch (_) {}
      final presentation = IncomingCallPresentation(
        displayName: initialDisplayName,
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
      diagnostics.record(
        stage: 'presentation',
        action: 'present',
        outcome: 'started',
        traceId: traceId,
      );
      var presented = false;
      var presentationThrew = false;
      var presentationUnavailable = false;
      try {
        presented = await _incomingCallPresenter.present(presentation);
      } on IncomingCallPresentationUnavailable {
        presentationUnavailable = true;
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
      diagnostics.record(
        stage: 'presentation',
        action: 'present',
        outcome: presented
            ? 'ok'
            : (presentationUnavailable ? 'unavailable' : 'failed'),
        reason: presented
            ? 'none'
            : (presentationUnavailable
                  ? 'capability_unavailable'
                  : 'native_lifecycle_failed'),
        traceId: traceId,
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
        return settle(
          IncomingCallSignalOutcome.rejected,
          expiredAfterPresentation
              ? IncomingCallSignalRefusal.expiredDuringPresentation
              : IncomingCallSignalRefusal.sessionChangedDuringPresentation,
        );
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
            // A refused or failed native surface does not establish that
            // microphone permission was denied.
            endReason: presentationUnavailable
                ? CallEndReason.unsupported
                : CallEndReason.signalingFailed,
          ),
        );
        admitted.commitReplay();
        return settle(
          IncomingCallSignalOutcome.rejected,
          IncomingCallSignalRefusal.presentationFailed,
        );
      }

      if (!contactNameApplied && signal.event == CallSignalType.invite) {
        // The presentation created the native descriptor: apply the verified
        // caller name now so CallKit never stays on the generic label.
        await _updateAuthenticatedContactSafely(
          admitted.callHandle,
          signal.senderAccountPeerId,
        );
      }
      if (signal.event == CallSignalType.invite) {
        // Android may have no foreground Flutter view while its process is in
        // the background. The authenticated native notification still needs
        // the local contact name after the descriptor has been presented.
        await _updateAndroidAuthenticatedContactSafely(
          signal.callId,
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
        return settle(
          IncomingCallSignalOutcome.rejected,
          IncomingCallSignalRefusal.systemUiRejected,
          reduction: shown.reason,
        );
      }
      admitted.commitReplay();
      return settle(
        _outcome(shown),
        IncomingCallSignalRefusal.systemUiRejected,
        reduction: shown.reason,
      );
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
      return settle(outcome, error.reasonCode);
    } catch (_) {
      _settleNegotiationMaterialAfterFailure(stagedMaterial);
      admitted?.rollbackReplay();
      return settle(
        IncomingCallSignalOutcome.deferred,
        IncomingCallSignalRefusal.handlerException,
      );
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

  Future<void> _updateAndroidAuthenticatedContactSafely(
    CallId callId,
    String contactAccountPeerId,
  ) async {
    final resolver = _authenticatedDisplayNameResolver;
    final presenter = _androidAuthenticatedContactPresenter;
    if (resolver == null || presenter == null) return;
    try {
      final displayName = (await resolver(contactAccountPeerId))?.trim();
      if (displayName == null ||
          displayName.isEmpty ||
          displayName.length > 128) {
        return;
      }
      await presenter(callId, displayName);
    } catch (_) {
      // A display update cannot change authenticated call admission.
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
