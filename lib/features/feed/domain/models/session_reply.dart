/// An in-memory record of a reply sent during the current app session.
///
/// Used to immediately collapse an open-mode card and show "Just now"
/// without waiting for a full feed refresh from the database.
class SessionReply {
  final String text;
  final DateTime time;

  const SessionReply({required this.text, required this.time});

  /// Creates a session reply stamped at the current time.
  factory SessionReply.justNow(String text) =>
      SessionReply(text: text, time: DateTime.now());
}

/// In-memory tracker keyed by contact peer ID.
class SessionReplyTracker {
  final Map<String, SessionReply> _replies = {};

  void track(String contactPeerId, SessionReply reply) {
    _replies[contactPeerId] = reply;
  }

  SessionReply? get(String contactPeerId) => _replies[contactPeerId];

  bool hasReply(String contactPeerId) => _replies.containsKey(contactPeerId);

  void clear(String contactPeerId) {
    _replies.remove(contactPeerId);
  }
}
