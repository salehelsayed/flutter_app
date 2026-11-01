/// Frozen terminal grammar shared by signaling, the reducer, and history.
enum CallEndReason {
  declined('declined'),
  busy('busy'),
  callerCancelled('caller_cancelled'),
  noAnswer('no_answer'),
  remoteHangup('remote_hangup'),
  localHangup('local_hangup'),
  permissionDenied('permission_denied'),

  /// The callee's microphone is off. Only the caller records it, from a
  /// received `permission_denied`; it is never sent.
  remotePermissionDenied('remote_permission_denied'),
  unsupported('unsupported'),
  signalingFailed('signaling_failed'),
  mediaFailed('media_failed'),
  reconnectFailed('reconnect_failed'),
  expired('expired'),
  appShutdown('app_shutdown'),
  policyRejected('policy_rejected');

  const CallEndReason(this.wireName);

  final String wireName;

  /// A reason a peer sent. [remotePermissionDenied] is local-only.
  static CallEndReason parseWire(String value) {
    final reason = parseStored(value);
    if (reason == remotePermissionDenied) {
      throw const FormatException('unsupported call terminal reason');
    }
    return reason;
  }

  /// A reason this device recorded, such as a call history row.
  static CallEndReason parseStored(String value) {
    for (final reason in values) {
      if (reason.wireName == value) return reason;
    }
    throw const FormatException('unsupported call terminal reason');
  }
}
