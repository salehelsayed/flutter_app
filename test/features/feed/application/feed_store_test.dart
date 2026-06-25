import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/feed/application/feed_pending_projection.dart';
import 'package:flutter_app/features/feed/application/feed_store.dart';
import 'package:flutter_app/features/feed/application/load_contact_feed_snapshot_use_case.dart';
import 'package:flutter_app/features/feed/application/load_feed_use_case.dart';
import 'package:flutter_app/features/feed/application/load_group_feed_snapshot_use_case.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';

ContactModel _contact({
  required String peerId,
  required String username,
  required String scannedAt,
}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/relay/tcp/443/p2p/relay',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: scannedAt,
  );
}

ConversationMessage _message({
  required String id,
  required String contactPeerId,
  required String senderPeerId,
  required String text,
  required String timestamp,
  required bool isIncoming,
  String? readAt,
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: senderPeerId,
    text: text,
    timestamp: timestamp,
    status: 'delivered',
    isIncoming: isIncoming,
    createdAt: timestamp,
    readAt: readAt,
  );
}

GroupModel _group({
  required String id,
  required String name,
  required DateTime createdAt,
}) {
  return GroupModel(
    id: id,
    name: name,
    type: GroupType.chat,
    topicName: '/mknoon/group/$id',
    createdAt: createdAt,
    createdBy: 'admin',
    myRole: GroupRole.member,
  );
}

GroupMessage _groupMessage({
  required String id,
  required String groupId,
  required String senderPeerId,
  required String text,
  required DateTime timestamp,
}) {
  return GroupMessage(
    id: id,
    groupId: groupId,
    senderPeerId: senderPeerId,
    senderUsername: senderPeerId,
    text: text,
    timestamp: timestamp,
    createdAt: timestamp,
  );
}

List<Map<String, Object?>> _summaries(List<FeedItem> items) {
  return items.map((item) {
    if (item is ConnectionFeedItem) {
      return {
        'type': 'connection',
        'id': item.id,
        'timestamp': item.timestamp.toUtc().toIso8601String(),
        'contactPeerId': item.contactPeerId,
        'contactUsername': item.contactUsername,
      };
    }
    if (item is ThreadFeedItem) {
      return {
        'type': 'thread',
        'id': item.id,
        'timestamp': item.timestamp.toUtc().toIso8601String(),
        'contactPeerId': item.contactPeerId,
        'contactUsername': item.contactUsername,
        'conversationState': item.conversationState.name,
        'messages': item.messages.map((message) => message.id).toList(),
      };
    }
    if (item is GroupThreadFeedItem) {
      return {
        'type': 'group',
        'id': item.id,
        'timestamp': item.timestamp.toUtc().toIso8601String(),
        'groupId': item.groupId,
        'conversationState': item.conversationState.name,
        'messages': item.messages.map((message) => message.id).toList(),
      };
    }
    throw StateError('Unsupported feed item type: ${item.runtimeType}');
  }).toList();
}

void main() {
  late FakeContactRepository contactRepo;
  late InMemoryMessageRepository messageRepo;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository groupMessageRepo;

  setUp(() {
    contactRepo = FakeContactRepository();
    messageRepo = InMemoryMessageRepository();
    groupRepo = InMemoryGroupRepository();
    groupMessageRepo = InMemoryGroupMessageRepository();
  });

  Future<List<FeedItem>> loadFullFeed() {
    return loadFeed(
      contactRepo: contactRepo,
      messageRepo: messageRepo,
      groupRepo: groupRepo,
      groupMsgRepo: groupMessageRepo,
    );
  }

  group('FeedStore', () {
    test(
      'TC-160-04: contactMessageIds is scoped to the preview window on mount '
      '(bounded reaction fan-out)',
      () async {
        // 160 A8: under the batched-summary mount the in-memory thread holds a
        // bounded preview WINDOW (K ids), while the true history is far larger
        // (totalMessageCount). The reaction fan-out (`_loadReactionsForFeed`)
        // reads `FeedStore.contactMessageIds`, so that set MUST reflect the
        // windowed `messages` (K), NOT the whole decrypted history — otherwise
        // the bound is defeated and reactions load for every historical id.
        const windowSize = 8;
        const totalHistory = 40;
        final windowed = List.generate(
          windowSize,
          (i) => ThreadMessage(
            id: 'w$i',
            text: 'w$i',
            time: '08:0$i',
            timestamp: DateTime.utc(2026, 3, 1, 8, i),
            isIncoming: true,
            isUnread: true,
          ),
        );
        final item = ThreadFeedItem(
          id: 'thread_peer-A',
          timestamp: DateTime.utc(2026, 3, 1, 9),
          contactPeerId: 'peer-A',
          contactUsername: 'Alice',
          messages: windowed,
          unreadCount: windowSize,
          isUnreadCard: true,
          conversationState: ConversationState.unread,
          totalMessageCount: totalHistory, // total >> the loaded window
        );

        final store = FeedStore()..replaceContacts([item]);

        // The store exposes ONLY the windowed ids, never `totalMessageCount`.
        expect(store.contactMessageIds.length, windowSize);
        expect(store.contactMessageIds, containsAll(['w0', 'w7']));
        // Membership gate intact: windowed ids resolve true, off-window ids
        // (present in the 40-message history but not loaded) resolve false.
        expect(store.containsMessageId('w3'), isTrue);
        expect(store.containsMessageId('w39'), isFalse);
      },
    );

    test(
      'replaceContactSnapshot updates one keyed contact while preserving unrelated threads',
      () async {
        contactRepo.seed([
          _contact(
            peerId: 'peer-A',
            username: 'Alice',
            scannedAt: '2026-02-01T10:00:00.000Z',
          ),
          _contact(
            peerId: 'peer-B',
            username: 'Bob',
            scannedAt: '2026-02-01T10:05:00.000Z',
          ),
        ]);
        await messageRepo.saveMessage(
          _message(
            id: 'msg-a-1',
            contactPeerId: 'peer-A',
            senderPeerId: 'peer-A',
            text: 'Alpha',
            timestamp: '2026-02-01T11:00:00.000Z',
            isIncoming: true,
          ),
        );
        await messageRepo.saveMessage(
          _message(
            id: 'msg-b-1',
            contactPeerId: 'peer-B',
            senderPeerId: 'peer-B',
            text: 'Beta',
            timestamp: '2026-02-01T11:05:00.000Z',
            isIncoming: true,
          ),
        );
        await groupRepo.saveGroup(
          _group(
            id: 'group-1',
            name: 'Alpha Group',
            createdAt: DateTime.utc(2026, 2, 1),
          ),
        );
        await groupMessageRepo.saveMessage(
          _groupMessage(
            id: 'gm-1',
            groupId: 'group-1',
            senderPeerId: 'peer-C',
            text: 'Group hello',
            timestamp: DateTime.utc(2026, 2, 1, 10, 55),
          ),
        );

        final store = FeedStore()..replaceAll(await loadFullFeed());

        await messageRepo.saveMessage(
          _message(
            id: 'msg-a-2',
            contactPeerId: 'peer-A',
            senderPeerId: 'peer-A',
            text: 'Alpha latest',
            timestamp: '2026-02-01T11:30:00.000Z',
            isIncoming: true,
          ),
        );
        final snapshot = await loadContactFeedSnapshot(
          contactRepo: contactRepo,
          messageRepo: messageRepo,
          contactPeerId: 'peer-A',
        );
        store.replaceContactSnapshot(
          contactPeerId: 'peer-A',
          connectionItem: snapshot.connectionItem,
          threadItem: snapshot.threadItem,
        );

        final fullReload = await loadFullFeed();

        // store.items is the pending projection; compare against the same
        // projection of a full reload (134-P4: connection-vs-thread dedup +
        // pending filter apply to both).
        expect(
          _summaries(store.items),
          _summaries(projectPendingFeed(fullReload, const {})),
        );
        expect(store.messageIdsForContact('peer-B'), {'msg-b-1'});
      },
    );

    test(
      'replaceGroupSnapshot updates one keyed group while preserving contact threads',
      () async {
        contactRepo.seed([
          _contact(
            peerId: 'peer-A',
            username: 'Alice',
            scannedAt: '2026-02-01T10:00:00.000Z',
          ),
        ]);
        await messageRepo.saveMessage(
          _message(
            id: 'msg-a-1',
            contactPeerId: 'peer-A',
            senderPeerId: 'peer-A',
            text: 'Contact hello',
            timestamp: '2026-02-01T11:00:00.000Z',
            isIncoming: true,
          ),
        );
        await groupRepo.saveGroup(
          _group(
            id: 'group-1',
            name: 'Alpha Group',
            createdAt: DateTime.utc(2026, 2, 1),
          ),
        );
        await groupRepo.saveGroup(
          _group(
            id: 'group-2',
            name: 'Beta Group',
            createdAt: DateTime.utc(2026, 2, 2),
          ),
        );
        await groupMessageRepo.saveMessage(
          _groupMessage(
            id: 'gm-1',
            groupId: 'group-1',
            senderPeerId: 'peer-B',
            text: 'Old alpha',
            timestamp: DateTime.utc(2026, 2, 1, 10),
          ),
        );
        await groupMessageRepo.saveMessage(
          _groupMessage(
            id: 'gm-2',
            groupId: 'group-2',
            senderPeerId: 'peer-C',
            text: 'Old beta',
            timestamp: DateTime.utc(2026, 2, 1, 10, 5),
          ),
        );

        final store = FeedStore()..replaceAll(await loadFullFeed());

        await groupMessageRepo.saveMessage(
          _groupMessage(
            id: 'gm-3',
            groupId: 'group-1',
            senderPeerId: 'peer-B',
            text: 'Fresh alpha',
            timestamp: DateTime.utc(2026, 2, 1, 12),
          ),
        );
        final snapshot = await loadGroupFeedSnapshot(
          groupRepo: groupRepo,
          groupMsgRepo: groupMessageRepo,
          groupId: 'group-1',
        );
        store.replaceGroupSnapshot(groupId: 'group-1', threadItem: snapshot);

        final fullReload = await loadFullFeed();

        // store.items is the pending projection; compare against the same
        // projection of a full reload (134-P4: connection-vs-thread dedup +
        // pending filter apply to both).
        expect(
          _summaries(store.items),
          _summaries(projectPendingFeed(fullReload, const {})),
        );
        expect(store.messageIdsForContact('peer-A'), {'msg-a-1'});
      },
    );
  });

  group('FeedStore cleared watermarks (134 P4)', () {
    final int clearWatermarkMs = DateTime.utc(2030).millisecondsSinceEpoch;

    List<String> threadPeers(FeedStore store) => store.items
        .whereType<ThreadFeedItem>()
        .map((t) => t.contactPeerId)
        .toList();

    Future<FeedStore> seedThreeUnreadThreads() async {
      contactRepo.seed([
        _contact(
          peerId: 'peer-A',
          username: 'Alice',
          scannedAt: '2026-02-01T09:00:00.000Z',
        ),
        _contact(
          peerId: 'peer-B',
          username: 'Bob',
          scannedAt: '2026-02-01T09:05:00.000Z',
        ),
        _contact(
          peerId: 'peer-C',
          username: 'Cara',
          scannedAt: '2026-02-01T09:10:00.000Z',
        ),
      ]);
      await messageRepo.saveMessage(_message(
        id: 'm-a',
        contactPeerId: 'peer-A',
        senderPeerId: 'peer-A',
        text: 'a',
        timestamp: '2026-02-01T11:00:00.000Z',
        isIncoming: true,
      ));
      await messageRepo.saveMessage(_message(
        id: 'm-b',
        contactPeerId: 'peer-B',
        senderPeerId: 'peer-B',
        text: 'b',
        timestamp: '2026-02-01T11:05:00.000Z',
        isIncoming: true,
      ));
      await messageRepo.saveMessage(_message(
        id: 'm-c',
        contactPeerId: 'peer-C',
        senderPeerId: 'peer-C',
        text: 'c',
        timestamp: '2026-02-01T11:10:00.000Z',
        isIncoming: true,
      ));
      return FeedStore()..replaceAll(await loadFullFeed());
    }

    test('setClearedWatermarks hides a thread at/under its watermark', () async {
      final store = await seedThreeUnreadThreads();
      expect(threadPeers(store), containsAll(<String>['peer-A']));

      store.setClearedWatermarks(<(String, String), int>{
        ('contact', 'peer-A'): clearWatermarkMs,
      });

      expect(threadPeers(store), isNot(contains('peer-A')));
      // INV-2: a cleared CONTACT thread does not remove the contact's
      // connection letter (different thread kind).
      expect(store.clearedWatermarks[('contact', 'peer-A')], clearWatermarkMs);
    });

    test('markClearedLocally hides; clearClearedLocally re-surfaces in slot',
        () async {
      final store = await seedThreeUnreadThreads();
      // Sorted newest-first by message timestamp: C, B, A.
      expect(threadPeers(store), <String>['peer-C', 'peer-B', 'peer-A']);

      store.markClearedLocally('contact', 'peer-B', clearWatermarkMs);
      expect(threadPeers(store), <String>['peer-C', 'peer-A']);

      // Undo: removing the watermark restores B in its natural sorted slot
      // (index 1) — no positional snapshot needed (TC-25 by re-projection).
      store.clearClearedLocally('contact', 'peer-B');
      expect(threadPeers(store), <String>['peer-C', 'peer-B', 'peer-A']);
    });

    test('setPinnedThread keeps an answered (non-pending) focused thread shown',
        () async {
      contactRepo.seed([
        _contact(
          peerId: 'peer-A',
          username: 'Alice',
          scannedAt: '2026-02-01T09:00:00.000Z',
        ),
      ]);
      await messageRepo.saveMessage(_message(
        id: 'in',
        contactPeerId: 'peer-A',
        senderPeerId: 'peer-A',
        text: 'hi',
        timestamp: '2026-02-01T11:00:00.000Z',
        isIncoming: true,
      ));
      // Outgoing AFTER the incoming → "answered since" → not pending.
      await messageRepo.saveMessage(_message(
        id: 'out',
        contactPeerId: 'peer-A',
        senderPeerId: 'me',
        text: 'reply',
        timestamp: '2026-02-01T11:05:00.000Z',
        isIncoming: false,
      ));
      final store = FeedStore()..replaceAll(await loadFullFeed());

      expect(threadPeers(store), isEmpty, reason: 'answered → dropped');

      store.setPinnedThread('peer-A');
      expect(threadPeers(store), <String>['peer-A'],
          reason: 'focus pin keeps the answered card visible (append-stay)');

      store.setPinnedThread(null);
      expect(threadPeers(store), isEmpty, reason: 'defocus drops the card');
    });
  });
}
