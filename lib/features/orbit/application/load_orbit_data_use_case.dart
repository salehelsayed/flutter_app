import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
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
    final friends = <OrbitFriend>[];

    for (final contact in contacts) {
      friends.add(
        await _buildOrbitFriend(
          contactPeerId: contact.peerId,
          contactRepo: contactRepo,
          messageRepo: messageRepo,
          contactOverride: contact,
        ),
      );
    }

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

    final friend = await _buildOrbitFriend(
      contactPeerId: contactPeerId,
      contactRepo: contactRepo,
      messageRepo: messageRepo,
      contactOverride: contact,
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

Future<OrbitFriend> _buildOrbitFriend({
  required String contactPeerId,
  required ContactRepository contactRepo,
  required MessageRepository messageRepo,
  ContactModel? contactOverride,
}) async {
  final contact =
      contactOverride ?? await contactRepo.getContact(contactPeerId);
  if (contact == null) {
    throw StateError('Contact not found for Orbit snapshot: $contactPeerId');
  }

  final messageCount = await messageRepo.getMessageCountForContact(
    contactPeerId,
  );
  final latestMessage = await messageRepo.getLatestMessageForContact(
    contactPeerId,
  );
  final unreadCount = await messageRepo.getUnreadCountForContact(contactPeerId);

  return OrbitFriend(
    contact: contact,
    messageCount: messageCount,
    lastActivity: latestMessage?.text,
    lastMessageTimestamp: latestMessage?.timestamp,
    unreadCount: unreadCount,
  );
}

void _sortOrbitFriends(List<OrbitFriend> friends) {
  friends.sort((a, b) {
    final aTime = a.lastMessageTimestamp ?? '';
    final bTime = b.lastMessageTimestamp ?? '';
    return bTime.compareTo(aTime);
  });
}
