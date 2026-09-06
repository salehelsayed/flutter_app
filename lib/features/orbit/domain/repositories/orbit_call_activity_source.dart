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

  /// 410: unread missed-call counts, keyed by contact. Contacts with none are
  /// OMITTED so the caller can merge without zero-writes.
  Future<Map<String, int>> unreadCallCountsForContacts(
    Iterable<String> contactPeerIds,
  );

  /// 412: emits once per terminal call written locally.
  ///
  /// Orbit loads on MOUNT. Device 2026-09-06 00:02:38Z: a call ended and no
  /// `ORBIT_CALL_UNREAD_RESULT` followed, so the ring kept rendering a count
  /// read before the call existed and a missed call could never light it up
  /// while the user was looking. The chat got this signal in 405; the ring
  /// needs the same one.
  Stream<void> get changes;
}
