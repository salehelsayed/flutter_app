/// Frozen terminal grammar shared by signaling, the reducer, and history.
enum CallEndReason {
  declined('declined'),
  busy('busy'),
  callerCancelled('caller_cancelled'),
  noAnswer('no_answer'),
  remoteHangup('remote_hangup'),
  localHangup('local_hangup'),
  permissionDenied('permission_denied'),
  unsupported('unsupported'),
  signalingFailed('signaling_failed'),
  mediaFailed('media_failed'),
  reconnectFailed('reconnect_failed'),
  expired('expired'),
  appShutdown('app_shutdown'),
  policyRejected('policy_rejected');

  const CallEndReason(this.wireName);

  final String wireName;

  static CallEndReason parseWire(String value) {
    for (final reason in values) {
      if (reason.wireName == value) return reason;
    }
    throw const FormatException('unsupported call terminal reason');
  }
}
