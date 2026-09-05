import 'package:flutter_app/features/conversation/domain/models/conversation_timeline_entry.dart';

/// 409: the newest terminal call per contact, for the Orbit rows.
///
/// Batched on purpose: Orbit renders every contact at once, so a per-contact
/// query would scale with the roster the way the thread summaries and media
/// descriptors deliberately do not.
///
/// A null source keeps Orbit message-only, exactly as it was before calls had
/// a row of their own.
abstract interface class OrbitCallActivitySource {
  Future<Map<String, ConversationCallTimelineEntry>> latestCallsForContacts(
    Iterable<String> contactPeerIds,
  );
}
