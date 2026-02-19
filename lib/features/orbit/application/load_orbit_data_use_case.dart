import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';

/// Loads all contacts with their message counts, sorted by messageCount descending.
///
/// This drives the orbital ring placement: top 5 on ring 1, next 8 on ring 2.
Future<List<OrbitFriend>> loadOrbitData({
  required ContactRepository contactRepo,
  required MessageRepository messageRepo,
  bool includeArchived = false,
}) async {
  emitFlowEvent(
    layer: 'UC',
    event: 'LOAD_ORBIT_DATA_START',
    details: {},
  );

  try {
    final contacts = includeArchived
        ? await contactRepo.getArchivedContacts()
        : await contactRepo.getActiveContacts();
    final friends = <OrbitFriend>[];

    for (final contact in contacts) {
      final messageCount = await messageRepo.getMessageCountForContact(
        contact.peerId,
      );
      final latestMessage = await messageRepo.getLatestMessageForContact(
        contact.peerId,
      );
      final unreadCount = await messageRepo.getUnreadCountForContact(
        contact.peerId,
      );

      friends.add(OrbitFriend(
        contact: contact,
        messageCount: messageCount,
        lastActivity: latestMessage?.text,
        lastMessageTimestamp: latestMessage?.timestamp,
        unreadCount: unreadCount,
      ));
    }

    friends.sort((a, b) => b.messageCount.compareTo(a.messageCount));

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
