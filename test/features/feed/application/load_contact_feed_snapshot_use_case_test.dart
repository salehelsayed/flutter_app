import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/feed/application/load_contact_feed_snapshot_use_case.dart';

import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';

ContactModel _contact(String peerId, String username) => ContactModel(
  peerId: peerId,
  publicKey: 'pk-$peerId',
  rendezvous: '/dns4/relay/tcp/443/p2p/relay',
  username: username,
  signature: 'sig-$peerId',
  scannedAt: '2026-03-01T10:00:00.000Z',
);

ConversationMessage _msg({
  required String id,
  required String contactPeerId,
  required String text,
  required String timestamp,
  required bool isIncoming,
  String? readAt,
}) => ConversationMessage(
  id: id,
  contactPeerId: contactPeerId,
  senderPeerId: isIncoming ? contactPeerId : 'me',
  text: text,
  timestamp: timestamp,
  status: 'delivered',
  isIncoming: isIncoming,
  createdAt: timestamp,
  readAt: readAt,
);

void main() {
  test(
    'TC-160-09: paged snapshot yields a correct ThreadFeedItem (hasReply true, '
    'multi-message preview intact, NOT a single summary row)',
    () async {
      final contactRepo = FakeContactRepository()
        ..seed([_contact('peer-A', 'Alice')]);
      final messageRepo = InMemoryMessageRepository();
      // A mixed page: incoming, an outgoing reply, then another incoming.
      await messageRepo.saveMessage(
        _msg(
          id: 'm1',
          contactPeerId: 'peer-A',
          text: 'hi',
          timestamp: '2026-03-01T12:00:00.000Z',
          isIncoming: true,
          readAt: '2026-03-01T12:01:00.000Z',
        ),
      );
      await messageRepo.saveMessage(
        _msg(
          id: 'm2',
          contactPeerId: 'peer-A',
          text: 'my reply',
          timestamp: '2026-03-01T12:02:00.000Z',
          isIncoming: false,
        ),
      );
      await messageRepo.saveMessage(
        _msg(
          id: 'm3',
          contactPeerId: 'peer-A',
          text: 'and again',
          timestamp: '2026-03-01T12:03:00.000Z',
          isIncoming: true,
        ),
      );

      final snapshot = await loadContactFeedSnapshot(
        contactRepo: contactRepo,
        messageRepo: messageRepo,
        contactPeerId: 'peer-A',
        pageSize: 30,
      );

      final thread = snapshot.threadItem;
      expect(thread, isNotNull);
      // Multi-message preview preserved — NOT collapsed to one summary row.
      expect(thread!.messages.length, 3);
      expect(thread.hasReply, isTrue);
      // Newest-first cap → the newest message is the latest, in display order.
      expect(thread.latestMessage.id, 'm3');
    },
  );

  test(
    'TC-160-09b: paged snapshot caps NEWEST-first — the newest message survives '
    'a page smaller than the history',
    () async {
      final contactRepo = FakeContactRepository()
        ..seed([_contact('peer-A', 'Alice')]);
      final messageRepo = InMemoryMessageRepository();
      for (var i = 0; i < 10; i++) {
        await messageRepo.saveMessage(
          _msg(
            id: 'm$i',
            contactPeerId: 'peer-A',
            text: 'msg $i',
            timestamp: '2026-03-01T12:0$i:00.000Z',
            isIncoming: true,
          ),
        );
      }

      final snapshot = await loadContactFeedSnapshot(
        contactRepo: contactRepo,
        messageRepo: messageRepo,
        contactPeerId: 'peer-A',
        pageSize: 4,
      );

      final thread = snapshot.threadItem!;
      // A 4-row newest-first page off a 10-row history keeps the newest row.
      expect(thread.messages.length, 4);
      expect(thread.latestMessage.id, 'm9');
      // totalMessageCount comes from the summary (10), not the page size (4).
      expect(thread.totalMessageCount, 10);
      expect(thread.hasEarlierHistory, isTrue);
    },
  );
}
