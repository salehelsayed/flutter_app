import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_thread_summary.dart';
import 'package:flutter_app/features/conversation/domain/models/media_preview_descriptor.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/conversation_thread_summary_repository.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_timeline_entry.dart';
import 'package:flutter_app/features/orbit/domain/repositories/orbit_call_activity_source.dart';
import 'package:flutter_app/features/orbit/application/load_latest_media_descriptors.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';

/// Loads all contacts with their message activity, sorted by most recent message first.
///
/// This drives the orbital ring placement: top 5 on ring 1, next 8 on ring 2.
Future<List<OrbitFriend>> loadOrbitData({
  required ContactRepository contactRepo,
  required MessageRepository messageRepo,
  MediaAttachmentRepository? mediaAttachmentRepo,
  // 409: newest terminal call per contact. Null keeps Orbit message-only.
  OrbitCallActivitySource? callActivitySource,
  bool includeArchived = false,
}) async {
  emitFlowEvent(layer: 'UC', event: 'LOAD_ORBIT_DATA_START', details: {});

  try {
    final contacts = includeArchived
        ? await contactRepo.getArchivedContacts()
        : await contactRepo.getActiveContacts();
    final summaries = await _loadConversationThreadSummaries(
      messageRepo: messageRepo,
      contactPeerIds: contacts.map((contact) => contact.peerId),
    );
    final descriptors = await loadLatestMediaDescriptors(
      mediaAttachmentRepo: mediaAttachmentRepo,
      messageIds: _previewableLatestIds(summaries.values),
      owner: MediaOwnerLane.direct,
    );
    final latestCalls = await _loadLatestCalls(
      callActivitySource: callActivitySource,
      contactPeerIds: contacts.map((contact) => contact.peerId),
    );
    final unreadCalls = await _loadUnreadCallCounts(
      callActivitySource: callActivitySource,
      contactPeerIds: contacts.map((contact) => contact.peerId),
    );
    final friends = contacts
        .map(
          (contact) => _buildOrbitFriend(
            contact: contact,
            summary:
                summaries[contact.peerId] ??
                ConversationThreadSummary(contactPeerId: contact.peerId),
            descriptors: descriptors,
            latestCall: latestCalls[contact.peerId],
            unreadCalls: unreadCalls[contact.peerId] ?? 0,
          ),
        )
        .toList(growable: false);

    _sortOrbitFriends(friends);

    emitFlowEvent(
      layer: 'UC',
      event: 'LOAD_ORBIT_DATA_SUCCESS',
      details: {'count': friends.length},
    );

    return friends;
  } catch (e) {
    emitFlowEvent(
      layer: 'UC',
      event: 'LOAD_ORBIT_DATA_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

Future<OrbitFriend?> loadOrbitFriendSnapshot({
  required ContactRepository contactRepo,
  required MessageRepository messageRepo,
  required String contactPeerId,
  MediaAttachmentRepository? mediaAttachmentRepo,
  // 409: keep a single-row refresh as call-aware as the full load.
  OrbitCallActivitySource? callActivitySource,
}) async {
  emitFlowEvent(
    layer: 'UC',
    event: 'LOAD_ORBIT_FRIEND_SNAPSHOT_START',
    details: {'peerId': contactPeerId},
  );

  try {
    final contact = await contactRepo.getContact(contactPeerId);
    if (contact == null) {
      emitFlowEvent(
        layer: 'UC',
        event: 'LOAD_ORBIT_FRIEND_SNAPSHOT_SUCCESS',
        details: {'peerId': contactPeerId, 'found': false},
      );
      return null;
    }

    final summary = await _loadConversationThreadSummary(
      messageRepo: messageRepo,
      contactPeerId: contactPeerId,
    );
    final descriptors = await loadLatestMediaDescriptors(
      mediaAttachmentRepo: mediaAttachmentRepo,
      messageIds: _previewableLatestIds([summary]),
      owner: MediaOwnerLane.direct,
    );
    final latestCalls = await _loadLatestCalls(
      callActivitySource: callActivitySource,
      contactPeerIds: <String>[contactPeerId],
    );
    final unreadCalls = await _loadUnreadCallCounts(
      callActivitySource: callActivitySource,
      contactPeerIds: <String>[contactPeerId],
    );
    final friend = _buildOrbitFriend(
      contact: contact,
      summary: summary,
      descriptors: descriptors,
      latestCall: latestCalls[contactPeerId],
      unreadCalls: unreadCalls[contactPeerId] ?? 0,
    );

    emitFlowEvent(
      layer: 'UC',
      event: 'LOAD_ORBIT_FRIEND_SNAPSHOT_SUCCESS',
      details: {'peerId': contactPeerId, 'found': true},
    );
    return friend;
  } catch (e) {
    emitFlowEvent(
      layer: 'UC',
      event: 'LOAD_ORBIT_FRIEND_SNAPSHOT_ERROR',
      details: {'peerId': contactPeerId, 'error': e.toString()},
    );
    rethrow;
  }
}

/// 410: unread missed-call counts, or an empty map.
///
/// Best effort for the same reason as the call activity itself: the badge is
/// worth less than the roster being on screen at all.
Future<Map<String, int>> _loadUnreadCallCounts({
  required OrbitCallActivitySource? callActivitySource,
  required Iterable<String> contactPeerIds,
}) async {
  if (callActivitySource == null) return const <String, int>{};
  try {
    final counts = await callActivitySource.unreadCallCountsForContacts(
      contactPeerIds,
    );
    // Without this a zero count and a broken query look identical in a
    // capture: ORBIT_CALL_UNREAD_SKIPPED only fires when the query THROWS.
    emitFlowEvent(
      layer: 'UC',
      event: 'ORBIT_CALL_UNREAD_RESULT',
      details: <String, Object?>{
        'contacts': counts.length,
        'total': counts.values.fold<int>(0, (sum, value) => sum + value),
      },
    );
    return counts;
  } catch (error) {
    emitFlowEvent(
      layer: 'UC',
      event: 'ORBIT_CALL_UNREAD_SKIPPED',
      details: {'errorType': error.runtimeType.toString()},
    );
    return const <String, int>{};
  }
}

/// 409: the newest terminal call per contact, or an empty map.
///
/// Best effort by construction: a call source that is absent or failing must
/// never keep the roster off screen. Orbit is the app's home surface.
Future<Map<String, ConversationCallTimelineEntry>> _loadLatestCalls({
  required OrbitCallActivitySource? callActivitySource,
  required Iterable<String> contactPeerIds,
}) async {
  if (callActivitySource == null) {
    return const <String, ConversationCallTimelineEntry>{};
  }
  try {
    return await callActivitySource.latestCallsForContacts(contactPeerIds);
  } catch (error) {
    emitFlowEvent(
      layer: 'UC',
      event: 'ORBIT_CALL_ACTIVITY_SKIPPED',
      details: {'errorType': error.runtimeType.toString()},
    );
    return const <String, ConversationCallTimelineEntry>{};
  }
}

OrbitFriend _buildOrbitFriend({
  required ContactModel contact,
  required ConversationThreadSummary summary,
  Map<String, MediaPreviewDescriptor> descriptors =
      const <String, MediaPreviewDescriptor>{},
  ConversationCallTimelineEntry? latestCall,
  int unreadCalls = 0,
}) {
  final latest = summary.latestMessage;
  final isDeleted = latest?.deletedAt != null;
  // A soft-deleted latest message must NOT resurrect its (still-present) media
  // attachments as a preview label — the row shows the deleted placeholder.
  // The summary SQL filters hidden_at but not deleted_at, so this is the gate.
  final descriptor = (latest != null && !isDeleted)
      ? descriptors[latest.id]
      : null;
  return OrbitFriend(
    contact: contact,
    messageCount: summary.messageCount,
    lastActivity: isDeleted ? null : latest?.text,
    lastMessageTimestamp: latest?.timestamp,
    // 410: one badge for the whole conversation. A missed call the user has
    // not seen counts exactly like an unread message, because from the row's
    // point of view both mean "something here is waiting for you".
    unreadCount: summary.unreadCount + unreadCalls,
    latestMedia: descriptor,
    isLatestDeleted: isDeleted,
    // Only a call NEWER than the latest message takes over the row, so the
    // preview rule downstream stays a single null check.
    latestCall: _callIfNewer(latestCall, latest?.timestamp),
  );
}

ConversationCallTimelineEntry? _callIfNewer(
  ConversationCallTimelineEntry? call,
  String? latestMessageTimestamp,
) {
  if (call == null) return null;
  if (latestMessageTimestamp == null) return call;
  final messageAt = DateTime.tryParse(latestMessageTimestamp);
  // An unparseable message timestamp must not silently promote the call: the
  // incumbent row ordering already treats such a message as its own activity.
  if (messageAt == null) return null;
  return call.endedAt.isAfter(messageAt.toUtc()) ? call : null;
}

/// Latest-message ids worth a media lookup: present and not soft-deleted.
/// Deleted latests are skipped so we never label a deleted message's media.
List<String> _previewableLatestIds(
  Iterable<ConversationThreadSummary> summaries,
) {
  final ids = <String>[];
  for (final summary in summaries) {
    final latest = summary.latestMessage;
    if (latest != null && latest.deletedAt == null) {
      ids.add(latest.id);
    }
  }
  return ids;
}

Future<ConversationThreadSummary> _loadConversationThreadSummary({
  required MessageRepository messageRepo,
  required String contactPeerId,
}) async {
  final summaryRepo = messageRepo is ConversationThreadSummaryRepository
      ? messageRepo as ConversationThreadSummaryRepository
      : null;
  if (summaryRepo != null) {
    return summaryRepo.getConversationThreadSummary(contactPeerId);
  }

  final latestMessage = await messageRepo.getLatestMessageForContact(
    contactPeerId,
  );
  return ConversationThreadSummary(
    contactPeerId: contactPeerId,
    messageCount: await messageRepo.getMessageCountForContact(contactPeerId),
    unreadCount: await messageRepo.getUnreadCountForContact(contactPeerId),
    latestMessage: latestMessage,
  );
}

Future<Map<String, ConversationThreadSummary>>
_loadConversationThreadSummaries({
  required MessageRepository messageRepo,
  required Iterable<String> contactPeerIds,
}) async {
  final ids = contactPeerIds.toList(growable: false);
  if (ids.isEmpty) return const <String, ConversationThreadSummary>{};

  final summaryRepo = messageRepo is ConversationThreadSummaryRepository
      ? messageRepo as ConversationThreadSummaryRepository
      : null;
  if (summaryRepo != null) {
    return summaryRepo.getConversationThreadSummaries(ids);
  }

  final summaries = <String, ConversationThreadSummary>{};
  for (final contactPeerId in ids) {
    summaries[contactPeerId] = await _loadConversationThreadSummary(
      messageRepo: messageRepo,
      contactPeerId: contactPeerId,
    );
  }
  return summaries;
}

void _sortOrbitFriends(List<OrbitFriend> friends) {
  friends.sort((a, b) {
    final aTime = a.lastActivityAt ?? '';
    final bTime = b.lastActivityAt ?? '';
    return bTime.compareTo(aTime);
  });
}
