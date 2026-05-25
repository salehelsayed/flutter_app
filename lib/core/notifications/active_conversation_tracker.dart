/// Tracks which conversation the user is currently viewing.
///
/// Used to suppress notifications when the user is already looking at
/// the sender's conversation.
class ActiveConversationTracker {
  String? _activePeerId;

  /// Mark a conversation as actively being viewed.
  void setActive(String peerId) {
    _activePeerId = normalizeActiveKey(peerId);
  }

  /// Clear the active conversation (e.g. when leaving the screen).
  void clear() {
    _activePeerId = null;
  }

  /// Clear only when [peerId] still represents the active conversation.
  void clearIfActive(String peerId) {
    if (isViewing(peerId)) {
      _activePeerId = null;
    }
  }

  /// Returns true if the user is currently viewing this peer's conversation.
  bool isViewing(String peerId) => _activePeerId == normalizeActiveKey(peerId);

  static String normalizeActiveKey(String peerId) {
    final trimmed = peerId.trim();
    if (!trimmed.startsWith('group:')) {
      return trimmed;
    }

    const messageMarker = '|message:';
    final markerIndex = trimmed.indexOf(messageMarker);
    if (markerIndex < 0) {
      return trimmed;
    }

    final groupKey = trimmed.substring(0, markerIndex).trim();
    return groupKey.isEmpty ? trimmed : groupKey;
  }
}
