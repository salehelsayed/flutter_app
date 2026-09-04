import 'call_wake_handle_grant.dart';

/// Receiver-side authority for grants issued by contact accounts.
abstract interface class ReceivedCallWakeHandleStore {
  Future<CallWakeHandleGrant?> readForIssuer(String issuerAccountPeerId);

  /// Atomically stores [grant] only when it is current and strictly newer than
  /// the issuer's durable anti-rollback watermark. The grant's recipient is the
  /// issuer/callee endpoint, not the remote contact receiving this capability.
  Future<bool> storeIfStrictlyNewer({
    required String issuerAccountPeerId,
    required CallWakeHandleGrant grant,
    required int nowMs,
  });

  Future<void> removeForIssuer(String issuerAccountPeerId);

  Future<void> clear();
}
