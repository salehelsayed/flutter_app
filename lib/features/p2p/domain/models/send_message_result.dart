/// Result of sending a P2P message, including optional reply/ack.
class SendMessageResult {
  final bool sent;
  final String? reply;

  const SendMessageResult({required this.sent, this.reply});

  /// Whether the remote peer acknowledged receipt.
  bool get acknowledged => sent && reply != null && reply!.isNotEmpty;
}
