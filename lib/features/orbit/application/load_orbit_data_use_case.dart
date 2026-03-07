import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_thread_summary.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/conversation_thread_summary_repository.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';

/// Loads all contacts with their message activity, sorted by most recent message first.
///
/// This drives the orbital ring placement: top 5 on ring 1, next 8 on ring 2.
Future<List<OrbitFriend>> loadOrbitData({
  required ContactRepository contactRepo,
  required MessageRepository messageRepo,
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
    final friends = contacts
        .map(
          (contact) => _buildOrbitFriend(
            contact: contact,
            summary: summaries[contact.peerId] ??
                ConversationThreadSummary(contactPeerId: contact.peerId),
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
    final friend = _buildOrbitFriend(contact: contact, summary: summary);

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

OrbitFriend _buildOrbitFriend({
  required ContactModel contact,
  required ConversationThreadSummary summary,
}) {
  return OrbitFriend(
    contact: contact,
    messageCount: summary.messageCount,
    lastActivity: summary.latestMessage?.text,
    lastMessageTimestamp: summary.latestMessage?.timestamp,
    unreadCount: summary.unreadCount,
  );
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

Future<Map<String, ConversationThreadSummary>> _loadConversationThreadSummaries({
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
    final aTime = a.lastMessageTimestamp ?? '';
    final bTime = b.lastMessageTimestamp ?? '';
    return bTime.compareTo(aTime);
  });
}
