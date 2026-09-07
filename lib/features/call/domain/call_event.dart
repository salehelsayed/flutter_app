import 'call_end_reason.dart';
import 'call_id.dart';
import 'call_session_snapshot.dart';

enum CallEventType {
  place,
  outgoingInviteReady,
  answer,
  decline,
  cancel,
  end,
  timeout,
  appShutdown,
  nativeAction,
  remoteInvite,
  incomingValidated,
  systemUiPresented,
  remoteRinging,
  remoteAccept,
  remoteReject,
  remoteOffer,
  remoteAnswer,
  remoteIce,
  iceCandidateHandled,
  remoteIceRestart,
  remoteTerminate,
  directAccepted,
  directFailed,
  mailboxStored,
  mailboxRetrieved,
  mailboxAcked,
  mailboxExpired,
  wakeRequested,
  negotiationReady,
  negotiationFailed,
  mediaConnected,
  mediaLost,
  mediaRecovered,
  glareLost,
}

enum IncomingCallAdmission {
  accepted,
  blocked,
  unknownContact,
  wrongDevice,
  unsupportedVersion,
  invalidSignature,
  malformed,
}

enum CallTimeoutKind { noAnswer, inviteExpiry, negotiation, reconnect }

enum CallNativeAction { answer, decline, end }

/// A fixed-shape event. Signaling and media payload bytes remain outside the
/// state machine and are referenced only by bounded opaque event identifiers.
final class CallEvent {
  CallEvent({
    required this.type,
    required this.eventId,
    required DateTime occurredAt,
    this.callId,
    this.contactPeerId,
    this.localAccountPeerId,
    this.localDeviceId,
    this.remoteAccountPeerId,
    this.remoteDeviceId,
    DateTime? expiresAt,
    this.admission = IncomingCallAdmission.accepted,
    this.timeoutKind,
    this.nativeAction,
    this.endReason,
    this.candidateId,
    this.transportRoute,
  }) : occurredAt = occurredAt.toUtc(),
       expiresAt = expiresAt?.toUtc() {
    if (eventId.trim().isEmpty || eventId.length > 128) {
      throw ArgumentError.value(eventId, 'eventId', 'must be 1..128 chars');
    }
    if (candidateId != null &&
        (candidateId!.trim().isEmpty || candidateId!.length > 128)) {
      throw ArgumentError.value(candidateId, 'candidateId');
    }
  }

  final CallEventType type;
  final String eventId;
  final DateTime occurredAt;
  final CallId? callId;
  final String? contactPeerId;
  final String? localAccountPeerId;
  final String? localDeviceId;
  final String? remoteAccountPeerId;
  final String? remoteDeviceId;
  final DateTime? expiresAt;
  final IncomingCallAdmission admission;
  final CallTimeoutKind? timeoutKind;
  final CallNativeAction? nativeAction;
  final CallEndReason? endReason;
  final String? candidateId;
  final CallRouteClass? transportRoute;

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'type': type.name,
    'admission': admission.name,
    'timeoutKind': timeoutKind?.name,
    'nativeAction': nativeAction?.name,
    'hasCallId': callId != null,
    'hasCandidateReference': candidateId != null,
  };

  @override
  String toString() => 'CallEvent(${toDiagnosticMap()})';
}
