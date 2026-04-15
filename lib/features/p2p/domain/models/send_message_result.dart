/// Result of sending a P2P message, including optional reply/ack.
class SendMessageResult {
  final bool sent;
  final bool? acked;
  final String? reply;
  final String? transport;
  final int? streamOpenMs;
  final int? writeMs;
  final int? ackWaitMs;

  const SendMessageResult({
    required this.sent,
    this.acked,
    this.reply,
    this.transport,
    this.streamOpenMs,
    this.writeMs,
    this.ackWaitMs,
  });

  /// Whether the remote peer acknowledged receipt.
  ///
  /// When [acked] is explicitly set (from new Go bridge), uses that directly.
  /// Falls back to old inference (non-empty reply = acked) for backward compat.
  bool get acknowledged =>
      sent && (acked ?? (reply != null && reply!.isNotEmpty));
}
