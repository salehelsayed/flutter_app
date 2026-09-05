import '../models/conversation_timeline_entry.dart';

/// Optional source for call rows shown alongside ordinary conversation data.
///
/// Conversation loading remains chat-only unless a caller explicitly enables
/// this source. That keeps existing callers and feature-disabled builds
/// byte-for-byte compatible at the model boundary.
abstract interface class ConversationCallTimelineSource {
  Future<List<ConversationCallTimelineEntry>> listCallsForContact(
    String contactPeerId,
  );

  /// 410: stamps this contact's unread missed calls as read.
  ///
  /// Called from the same seam that marks messages read, so opening a
  /// conversation clears the whole badge rather than half of it.
  Future<void> markCallsRead(String contactPeerId);

  /// Emits once per terminal call written locally.
  ///
  /// A conversation that is already on screen when a call happens is never
  /// rebuilt or resumed — the call surface is a layer above it, not a route —
  /// so this is the only thing that can bring the new row in. A source with no
  /// signal returns an empty stream and the chat stays load-on-open.
  Stream<void> get changes;
}
