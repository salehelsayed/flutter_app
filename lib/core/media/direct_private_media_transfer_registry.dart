/// Process-local ownership registry for native direct-private transfers.
///
/// Transfer I/O deliberately does not hold the attachment lifecycle lock.
/// Terminal cleanup consults this registry and retains the exact attachment
/// row while native code may still write staged bytes. A process restart
/// clears the registry, making the retained row immediate cleanup authority.
class DirectPrivateMediaTransferRegistry {
  final Map<String, Set<Object>> _tokens = <String, Set<Object>>{};
  final Map<String, String?> _messageIds = <String, String?>{};

  /// Atomically acquires process-local ownership. A second encryption
  /// discriminator for the same attachment must not replace the first token.
  Object? tryBegin(String attachmentId, {String? messageId}) {
    if (_tokens.containsKey(attachmentId)) return null;
    final token = Object();
    (_tokens[attachmentId] ??= <Object>{}).add(token);
    final normalizedMessageId = messageId?.trim();
    _messageIds[attachmentId] =
        normalizedMessageId == null || normalizedMessageId.isEmpty
        ? null
        : normalizedMessageId;
    return token;
  }

  bool isActive(String attachmentId) => _tokens.containsKey(attachmentId);

  bool isActiveForMessage(String messageId) =>
      _messageIds.values.any((activeMessageId) => activeMessageId == messageId);

  /// True while any direct-private transfer has process-local byte custody.
  ///
  /// Broad destructive operations such as contact deletion cannot prove that
  /// a newly inserted or already detached parent is outside their purge set,
  /// so they must conservatively defer until the registry is empty.
  bool get hasAnyActive => _tokens.isNotEmpty;

  /// True for legacy/incoming claims that did not publish parent ownership.
  /// A destructive parent operation cannot prove such a claim is unrelated,
  /// so it must conservatively defer until the token is released.
  bool get hasUnscopedActive =>
      _messageIds.values.any((value) => value == null);

  bool owns(String attachmentId, Object token) =>
      _tokens[attachmentId]?.contains(token) ?? false;

  void end(String attachmentId, Object token) {
    final tokens = _tokens[attachmentId];
    if (tokens == null) return;
    tokens.remove(token);
    if (tokens.isEmpty) {
      _tokens.remove(attachmentId);
      _messageIds.remove(attachmentId);
    }
  }
}

final DirectPrivateMediaTransferRegistry directPrivateMediaTransferRegistry =
    DirectPrivateMediaTransferRegistry();
