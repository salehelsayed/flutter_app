import '../models/conversation_thread_summary.dart';

abstract class ConversationThreadSummaryRepository {
  Future<ConversationThreadSummary> getConversationThreadSummary(
    String contactPeerId,
  );

  Future<Map<String, ConversationThreadSummary>> getConversationThreadSummaries(
    Iterable<String> contactPeerIds,
  );
}
