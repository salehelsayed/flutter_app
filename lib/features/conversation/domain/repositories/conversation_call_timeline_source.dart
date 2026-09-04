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
}
