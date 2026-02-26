/// Tracks which conversation the user is currently viewing.
///
/// Used to suppress notifications when the user is already looking at
/// the sender's conversation.
class ActiveConversationTracker {
  String? _activePeerId;

  /// Mark a conversation as actively being viewed.
  void setActive(String peerId) {
    _activePeerId = peerId;
  }

  /// Clear the active conversation (e.g. when leaving the screen).
  void clear() {
    _activePeerId = null;
  }

  /// Returns true if the user is currently viewing this peer's conversation.
  bool isViewing(String peerId) => _activePeerId == peerId;
}
