String shortenPeerId(String peerId, {int maxLength = 10}) {
  if (peerId.length <= maxLength) return peerId;
  return peerId.substring(0, maxLength);
}

String shortenMessageId(String messageId, {int maxLength = 8}) {
  if (messageId.length <= maxLength) return messageId;
  return messageId.substring(0, maxLength);
}

String buildTextPreview(String text, {int maxLength = 120}) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= maxLength) return normalized;
  return '${normalized.substring(0, maxLength)}...';
}

void logChatOutgoing({
  required String messageId,
  required String toPeerId,
  required String status,
  required String text,
  int? attempt,
}) {
  final attemptPart = attempt == null ? '' : ' attempt=$attempt';
  final preview = buildTextPreview(text);
  print(
    '[CHAT_OUT] id=${shortenMessageId(messageId)} to=${shortenPeerId(toPeerId)} '
    'status=$status$attemptPart text="$preview"',
  );
}

void logChatIncoming({
  required String messageId,
  required String fromPeerId,
  required String status,
  required String text,
}) {
  final preview = buildTextPreview(text);
  print(
    '[CHAT_IN] id=${shortenMessageId(messageId)} from=${shortenPeerId(fromPeerId)} '
    'status=$status text="$preview"',
  );
}

void logChatTransportIncoming({
  required String fromPeerId,
  required String toPeerId,
  required int contentLength,
  required bool isIncoming,
  String? envelopeType,
}) {
  final type = envelopeType ?? 'unknown';
  print(
    '[CHAT_TRANSPORT_IN] from=${shortenPeerId(fromPeerId)} to=${shortenPeerId(toPeerId)} '
    'incoming=$isIncoming contentLength=$contentLength type=$type',
  );
}
