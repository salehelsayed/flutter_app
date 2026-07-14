/// Process-local ownership registry for native direct-private transfers.
///
/// Transfer I/O deliberately does not hold the attachment lifecycle lock.
/// Terminal cleanup consults this registry and retains the exact attachment
/// row while native code may still write staged bytes. A process restart
/// clears the registry, making the retained row immediate cleanup authority.
class DirectPrivateMediaTransferRegistry {
  final Map<String, Set<Object>> _tokens = <String, Set<Object>>{};

  /// Atomically acquires process-local ownership. A second encryption
  /// discriminator for the same attachment must not replace the first token.
  Object? tryBegin(String attachmentId) {
    if (_tokens.containsKey(attachmentId)) return null;
    final token = Object();
    (_tokens[attachmentId] ??= <Object>{}).add(token);
    return token;
  }

  bool isActive(String attachmentId) => _tokens.containsKey(attachmentId);

  bool owns(String attachmentId, Object token) =>
      _tokens[attachmentId]?.contains(token) ?? false;

  void end(String attachmentId, Object token) {
    final tokens = _tokens[attachmentId];
    if (tokens == null) return;
    tokens.remove(token);
    if (tokens.isEmpty) {
      _tokens.remove(attachmentId);
    }
  }
}

final DirectPrivateMediaTransferRegistry directPrivateMediaTransferRegistry =
    DirectPrivateMediaTransferRegistry();
