import '../../../core/utils/flow_event_emitter.dart';
import '../application/handle_incoming_call_signal.dart';
import '../domain/call_id.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_signal.dart';
import '../domain/issued_call_wake_handle_store.dart';
import 'call_signaling_runtime.dart';

/// Captured custody of one native placeholder, never an incoming-call grant.
final class AndroidCallAdmissionToken {
  const AndroidCallAdmissionToken._(
    this.nativeCallId,
    this.ownerId,
    this.expiresAtMs,
    this.wakeHandle,
  );

  static AndroidCallAdmissionToken? fromWire(Object? value) {
    if (value is! Map ||
        value.length != 4 ||
        value.keys.toSet().difference(const <String>{
          'nativeCallId',
          'ownerId',
          'expiresAtMs',
          'wakeHandle',
        }).isNotEmpty) {
      return null;
    }
    final callId = value['nativeCallId'];
    final owner = value['ownerId'];
    final expiry = value['expiresAtMs'];
    final wake = value['wakeHandle'];
    if (callId is! String ||
        CallId.tryParse(callId) == null ||
        owner is! String ||
        CallId.tryParse(owner) == null ||
        expiry is! int ||
        expiry <= 0 ||
        expiry > 9007199254740991 ||
        wake is! String ||
        !(RegExp(r'^[0-9a-f]{32}$').hasMatch(wake) ||
            CallId.tryParse(wake) != null)) {
      return null;
    }
    return AndroidCallAdmissionToken._(callId, owner, expiry, wake);
  }

  final String nativeCallId;
  final String ownerId;
  final int expiresAtMs;
  final String wakeHandle;

  Map<String, Object?> toWire() => <String, Object?>{
    'nativeCallId': nativeCallId,
    'ownerId': ownerId,
    'expiresAtMs': expiresAtMs,
    'wakeHandle': wakeHandle,
  };

  @override
  String toString() => 'AndroidCallAdmissionToken(redacted)';
}

abstract interface class AndroidCallAdmissionSettlementPort {
  bool get admissionSettlementAvailable;
  Future<AndroidCallAdmissionToken?> captureAdmissionSettlement(
    String nativeCallId,
  );
  Future<bool> settleAuthenticatedAdmission(AndroidCallAdmissionToken token);
}

/// Captures before authentication/ACK, then binds the verified terminal to the
/// exact row and current issuer-side wake authority. Empty, invalid, expired,
/// duplicate, and deferred rows cannot manufacture the private terminal proof.
Future<CommitCallMailboxSettlement?> prepareAndroidCallAdmissionSettlement({
  required IncomingCallSignalFrame frame,
  required AndroidCallAdmissionSettlementPort native,
  required IssuedCallWakeHandleStore issuedWakeHandles,
  required String localAccountPeerId,
  required String localDevicePeerId,
  required int localDeviceKeyEpoch,
  required Future<bool> Function() isCurrentLocalAuthority,
  required int Function() nowMs,
}) async {
  final handle = frame.expectedCallHandle;
  if (!native.admissionSettlementAvailable ||
      frame.route != CallRouteClass.ephemeralMailbox ||
      handle == null ||
      CallId.tryParse(handle) == null ||
      frame.expectedMessageId == null ||
      frame.expectedExpiresAtMs == null ||
      frame.expectedRecipientDevicePeerId == null) {
    return null;
  }
  final token = await native.captureAdmissionSettlement(handle);
  if (token == null ||
      token.nativeCallId != handle ||
      !native.admissionSettlementAvailable) {
    return null;
  }
  _diagnostic('capture', 'ready');
  return (terminal, {required canApply}) async {
    bool current() => canApply() && native.admissionSettlementAvailable;
    final signal = terminal.signal;
    if (!current() ||
        terminal.callHandle != handle ||
        terminal.callHandle != token.nativeCallId ||
        signal.messageId != frame.expectedMessageId ||
        signal.expiresAtMs != frame.expectedExpiresAtMs ||
        signal.senderDevicePeerId != frame.authenticatedTransportPeerId ||
        signal.recipientDevicePeerId != frame.expectedRecipientDevicePeerId ||
        signal.recipientAccountPeerId != localAccountPeerId ||
        signal.recipientDevicePeerId != localDevicePeerId ||
        (signal.event != CallSignalType.reject &&
            signal.event != CallSignalType.terminate)) {
      _diagnostic('authority', 'rejected');
      return;
    }
    if (!await isCurrentLocalAuthority() || !current()) return;
    final record = await issuedWakeHandles.readForContact(
      signal.senderAccountPeerId,
    );
    if (!current() ||
        record == null ||
        record.contactAccountPeerId != signal.senderAccountPeerId ||
        record.revokePending ||
        record.distributionPending ||
        !record.hasCurrentDistributionReceipt ||
        !record.authorizedSenderDevicePeerIds.contains(
          signal.senderDevicePeerId,
        ) ||
        record.grant.handle != token.wakeHandle ||
        record.grant.recipientDevicePeerId != localDevicePeerId ||
        record.grant.deviceKeyEpoch != localDeviceKeyEpoch ||
        !record.grant.isValidAt(nowMs())) {
      _diagnostic('authority', 'rejected');
      return;
    }
    if (!await isCurrentLocalAuthority() || !current()) return;
    // A grant rotation/revocation during the preceding account read must not
    // authorize release under the previously captured wake generation.
    final latest = await issuedWakeHandles.readForContact(
      signal.senderAccountPeerId,
    );
    if (!current() ||
        latest == null ||
        latest.grant != record.grant ||
        latest.contactAccountPeerId != record.contactAccountPeerId ||
        latest.revokePending ||
        latest.distributionPending ||
        !latest.hasCurrentDistributionReceipt ||
        !latest.authorizedSenderDevicePeerIds.contains(
          signal.senderDevicePeerId,
        ) ||
        !latest.grant.isValidAt(nowMs())) {
      return;
    }
    // The final grant read may wait behind a storage mutation. Recheck the
    // account/key binding after it, immediately before native dispatch.
    if (!await isCurrentLocalAuthority() || !current()) return;
    final applied = await native.settleAuthenticatedAdmission(token);
    _diagnostic('native_commit', applied ? 'applied' : 'rejected');
  };
}

void _diagnostic(String stage, String outcome) {
  try {
    emitFlowEvent(
      layer: 'FL',
      event: 'CALL_FOREGROUND_ADMISSION_SETTLEMENT',
      details: <String, Object?>{'stage': stage, 'outcome': outcome},
    );
  } catch (_) {
    // Diagnostic sinks do not participate in custody or trust decisions.
  }
}
