import 'package:flutter_app/features/conversation/domain/models/conversation_timeline_entry.dart';
import 'package:flutter_app/features/conversation/domain/repositories/conversation_call_timeline_source.dart';

import '../domain/call_session_snapshot.dart';
import 'call_history_repository.dart';

/// Adapts local terminal call history to the typed conversation timeline.
///
/// The adapter intentionally omits transport route and every signaling,
/// mailbox, wake, and cryptographic field.
final class CallHistoryConversationTimelineSource
    implements ConversationCallTimelineSource {
  const CallHistoryConversationTimelineSource(this.repository);

  final CallHistoryRepository repository;

  @override
  Future<List<ConversationCallTimelineEntry>> listCallsForContact(
    String contactPeerId,
  ) async {
    if (contactPeerId.trim().isEmpty) {
      return const <ConversationCallTimelineEntry>[];
    }
    final rows = await repository.listForContact(contactPeerId);
    return List<ConversationCallTimelineEntry>.unmodifiable(
      rows
          .where((row) => row.contactAccountPeerId == contactPeerId)
          .map(
            (row) => ConversationCallTimelineEntry(
              callId: row.callId.value,
              contactPeerId: row.contactAccountPeerId,
              direction: switch (row.direction) {
                CallDirection.incoming => ConversationCallDirection.incoming,
                CallDirection.outgoing => ConversationCallDirection.outgoing,
              },
              status: switch (row.status) {
                CallHistoryStatus.completed => ConversationCallStatus.completed,
                CallHistoryStatus.missed => ConversationCallStatus.missed,
                CallHistoryStatus.declined => ConversationCallStatus.declined,
                CallHistoryStatus.busy => ConversationCallStatus.busy,
                CallHistoryStatus.cancelled => ConversationCallStatus.cancelled,
                CallHistoryStatus.failed => ConversationCallStatus.failed,
              },
              startedAt: row.startedAt,
              endedAt: row.endedAt,
              duration: row.duration,
            ),
          ),
    );
  }
}
