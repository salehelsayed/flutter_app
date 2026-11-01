import 'package:flutter_app/features/conversation/domain/models/conversation_timeline_entry.dart';
import 'package:flutter_app/features/orbit/domain/repositories/orbit_call_activity_source.dart';

import 'call_history_conversation_timeline_source.dart';
import 'call_history_repository.dart';

/// 409: adapts local terminal call history to the Orbit rows.
///
/// Like [CallHistoryConversationTimelineSource] it exposes only the
/// privacy-safe projection — direction, status, timestamps — and never a call
/// handle, route, or signal.
final class CallHistoryOrbitActivitySource implements OrbitCallActivitySource {
  const CallHistoryOrbitActivitySource(
    this.loadLatestForContacts,
    this.loadUnreadCounts, {
    Stream<void>? changes,
  }) : _changes = changes;

  final Stream<void>? _changes;

  /// 412: the same post-projection signal the chat refresh rides. A source
  /// built without it leaves Orbit load-on-mount, which is what it was.
  @override
  Stream<void> get changes => _changes ?? const Stream<void>.empty();

  /// Newest-first rows for the given contacts, batched by the caller.
  final Future<List<CallHistoryEntry>> Function(List<String> contactPeerIds)
  loadLatestForContacts;

  /// 410: unread missed-call counts, batched the same way.
  final Future<Map<String, int>> Function(List<String> contactPeerIds)
  loadUnreadCounts;

  @override
  Future<Map<String, ConversationCallTimelineEntry>> latestCallsForContacts(
    Iterable<String> contactPeerIds,
  ) async {
    final wanted = contactPeerIds
        .where((peerId) => peerId.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (wanted.isEmpty) {
      return const <String, ConversationCallTimelineEntry>{};
    }
    final rows = await loadLatestForContacts(wanted);
    final latest = <String, ConversationCallTimelineEntry>{};
    for (final row in rows) {
      // Rows arrive newest-first per contact, so the first one wins.
      latest.putIfAbsent(
        row.contactAccountPeerId,
        () => projectCallTimelineEntry(row),
      );
    }
    return Map<String, ConversationCallTimelineEntry>.unmodifiable(latest);
  }

  @override
  Future<Map<String, int>> unreadCallCountsForContacts(
    Iterable<String> contactPeerIds,
  ) async {
    final wanted = contactPeerIds
        .where((peerId) => peerId.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (wanted.isEmpty) return const <String, int>{};
    return await loadUnreadCounts(wanted);
  }
}
