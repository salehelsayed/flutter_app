import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/application/migration_file_manifest_builder.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_file_manifest.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_thread_summary.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/conversation_thread_summary_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/feed/application/load_feed_use_case.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:path/path.dart' as p;
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';

// -- Fake Contact Repository --
class FakeContactRepository implements ContactRepository {
  final List<ContactModel> contacts;

  FakeContactRepository({this.contacts = const []});

  @override
  Future<List<ContactModel>> getAllContacts() async => contacts;

  @override
  Future<ContactModel?> getContact(String peerId) async =>
      contacts.where((c) => c.peerId == peerId).firstOrNull;

  @override
  Future<void> addContact(ContactModel contact) async {}

  @override
  Future<void> deleteContact(String peerId) async {}

  @override
  Future<bool> contactExists(String peerId) async => false;

  @override
  Future<int> getContactCount() async => contacts.length;

  @override
  Future<void> archiveContact(String peerId) async {}

  @override
  Future<void> unarchiveContact(String peerId) async {}

  @override
  Future<void> blockContact(String peerId) async {}

  @override
  Future<void> unblockContact(String peerId) async {}

  @override
  Future<List<ContactModel>> getActiveContacts() async =>
      contacts.where((c) => !c.isArchived).toList();

  @override
  Future<List<ContactModel>> getArchivedContacts() async =>
      contacts.where((c) => c.isArchived).toList();

  @override
  Future<void> dismissIntroBanner(String peerId) async {}

  @override
  Future<void> setIntrosSentAt(String peerId, String timestamp) async {}
}

// -- Fake Message Repository --
//
// 160: implements ConversationThreadSummaryRepository so the production cast in
// loadContactFeedItems resolves HERE (not the per-id fallback), and exposes spy
// counters so TC-160-01/14 can prove the feed mount uses the batched summary +
// bounded windowed pages and NEVER the unbounded per-contact full load.
class FakeMessageRepository
    implements MessageRepository, ConversationThreadSummaryRepository {
  final Map<String, List<ConversationMessage>> messagesByContact;

  FakeMessageRepository({this.messagesByContact = const {}});

  int getMessagesForContactCallCount = 0;
  int getConversationThreadSummariesCallCount = 0;
  final List<(String, int)> getMessagesPageCalls = <(String, int)>[];

  List<ConversationMessage> _visible(String contactPeerId) =>
      (messagesByContact[contactPeerId] ?? const <ConversationMessage>[])
          .where((m) => !m.isHidden)
          .toList();

  ConversationThreadSummary _summaryFor(String contactPeerId) {
    final all = _visible(contactPeerId);
    final notDeleted = all.where((m) => !m.isDeleted).toList();
    DateTime? lastOutgoingAt;
    for (final m in notDeleted) {
      if (!m.isIncoming) {
        final ts = DateTime.tryParse(m.timestamp);
        if (ts != null &&
            (lastOutgoingAt == null || ts.isAfter(lastOutgoingAt))) {
          lastOutgoingAt = ts;
        }
      }
    }
    final sorted = all.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return ConversationThreadSummary(
      contactPeerId: contactPeerId,
      messageCount: notDeleted.length,
      unreadCount: notDeleted
          .where((m) => m.isIncoming && m.readAt == null)
          .length,
      lastOutgoingAt: lastOutgoingAt,
      latestMessage: sorted.isEmpty ? null : sorted.first,
    );
  }

  @override
  Future<ConversationThreadSummary> getConversationThreadSummary(
    String contactPeerId,
  ) async => _summaryFor(contactPeerId);

  @override
  Future<Map<String, ConversationThreadSummary>> getConversationThreadSummaries(
    Iterable<String> contactPeerIds,
  ) async {
    getConversationThreadSummariesCallCount++;
    return {
      for (final id in contactPeerIds.toSet()) id: _summaryFor(id),
    };
  }

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) async {
    getMessagesForContactCallCount++;
    return messagesByContact[contactPeerId] ?? [];
  }

  @override
  Future<void> saveMessage(ConversationMessage message) async {}

  @override
  Future<void> updateMessageStatus(String id, String status) async {}

  @override
  Future<ConversationMessage?> getMessage(String id) async => null;

  @override
  Future<bool> messageExists(String id) async => false;

  @override
  Future<bool> existsByContent(
    String contactPeerId,
    String senderPeerId,
    String text,
    String timestamp,
  ) async => false;

  @override
  Future<bool> existsByDedupKey(
    String contactPeerId,
    String senderPeerId,
    String dedupKey,
  ) async => false;

  @override
  Future<int> markConversationAsRead(String contactPeerId) async => 0;

  @override
  Future<int> getTotalUnreadCount() async => 0;

  @override
  Future<int> getTotalUnreadCountExcludingArchived() async => 0;

  @override
  Future<int> deleteMessagesForContact(String contactPeerId) async => 0;

  @override
  Future<int> deleteMessage(String id) async => 0;

  @override
  Future<List<ConversationMessage>> getMessagesPage(
    String contactPeerId, {
    int limit = 50,
    String? beforeTimestamp,
  }) async {
    getMessagesPageCalls.add((contactPeerId, limit));
    var msgs = _visible(contactPeerId);
    if (beforeTimestamp != null) {
      msgs = msgs
          .where((m) => m.timestamp.compareTo(beforeTimestamp) < 0)
          .toList();
    }
    msgs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return msgs.take(limit).toList().reversed.toList();
  }

  @override
  Future<int> getMessageCountForContact(String contactPeerId) async =>
      _summaryFor(contactPeerId).messageCount;

  @override
  Future<int> getUnreadCountForContact(String contactPeerId) async =>
      _summaryFor(contactPeerId).unreadCount;

  @override
  Future<ConversationMessage?> getLatestMessageForContact(
    String contactPeerId,
  ) async => _summaryFor(contactPeerId).latestMessage;

  @override
  Future<List<ConversationMessage>> getFailedOutgoingMessages() async => [];

  @override
  Future<List<ConversationMessage>> getUnackedOutgoingMessages({
    required Duration olderThan,
  }) async => [];

  @override
  Future<int> recoverStuckSendingMessages({
    required Duration olderThan,
  }) async => 0;

  @override
  Future<void> updateWireEnvelope(String id, String envelope) async {}

  @override
  Future<List<ConversationMessage>> getStuckSendingOutgoingMessages({
    required Duration olderThan,
  }) async => [];

  @override
  Future<List<ConversationMessage>> getSendingOutgoingMessages() async => [];

  @override
  Future<int> conditionalTransitionStatus(
    String id, {
    required String fromStatus,
    required String toStatus,
  }) async => 0;
}

ContactModel _makeContact(String peerId, String username, String scannedAt) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/relay/tcp/443/p2p/relay',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: scannedAt,
  );
}

ConversationMessage _makeMessage({
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

void main() {
  // 162: the loaders resolve media via the static `resolveStoredPathSync`, which
  // resolves against the cached docs dir (not the fake's async override). Seed
  // the cache to the fake's deterministic root so every media test (existing +
  // TC-162-02/03) resolves to the same absolute paths after the swap.
  setUp(() {
    MediaFileManager.cacheDocumentsDir(FakeMediaFileManager.testRootPath);
  });
  tearDown(MediaFileManager.debugResetDocumentsDirCache);

  group('loadFeed', () {
    test('returns empty list when no contacts', () async {
      final result = await loadFeed(
        contactRepo: FakeContactRepository(),
        messageRepo: FakeMessageRepository(),
      );

      expect(result, isEmpty);
    });

    test('returns ConnectionFeedItems for contacts with no messages', () async {
      final contacts = [
        _makeContact('peer-A', 'Alice', '2026-02-09T10:00:00.000Z'),
        _makeContact('peer-B', 'Bob', '2026-02-09T11:00:00.000Z'),
      ];

      final result = await loadFeed(
        contactRepo: FakeContactRepository(contacts: contacts),
        messageRepo: FakeMessageRepository(),
      );

      expect(result.length, 2);
      expect(result.every((item) => item is ConnectionFeedItem), isTrue);
      // Newest-first: Bob (11:00) before Alice (10:00)
      expect((result[0] as ConnectionFeedItem).contactUsername, 'Bob');
      expect((result[1] as ConnectionFeedItem).contactUsername, 'Alice');
    });

    test(
      'groups sent and received messages into ThreadFeedItems by contact',
      () async {
        final contacts = [
          _makeContact('peer-A', 'Alice', '2026-02-09T10:00:00.000Z'),
        ];

        final messages = {
          'peer-A': [
            _makeMessage(
              id: 'msg-1',
              contactPeerId: 'peer-A',
              senderPeerId: 'peer-A',
              text: 'Hello from Alice',
              timestamp: '2026-02-09T12:00:00.000Z',
              isIncoming: true,
            ),
            _makeMessage(
              id: 'msg-2',
              contactPeerId: 'peer-A',
              senderPeerId: 'peer-A',
              text: 'Second message',
              timestamp: '2026-02-09T12:05:00.000Z',
              isIncoming: true,
            ),
            _makeMessage(
              id: 'msg-3',
              contactPeerId: 'peer-A',
              senderPeerId: 'my-peer',
              text: 'My reply',
              timestamp: '2026-02-09T12:01:00.000Z',
              isIncoming: false,
            ),
          ],
        };

        final result = await loadFeed(
          contactRepo: FakeContactRepository(contacts: contacts),
          messageRepo: FakeMessageRepository(messagesByContact: messages),
        );

        final threadItems = result.whereType<ThreadFeedItem>().toList();
        expect(threadItems.length, 1);
        // All 3 messages (sent + received) grouped into one thread
        expect(threadItems[0].messages.length, 3);
        expect(threadItems[0].messages[0].text, 'Hello from Alice');
        expect(threadItems[0].messages[1].text, 'My reply');
        expect(threadItems[0].messages[2].text, 'Second message');
        expect(threadItems[0].contactUsername, 'Alice');
      },
    );

    test('same contact with 24hr gap keeps single card', () async {
      final contacts = [
        _makeContact('peer-A', 'Alice', '2026-02-09T10:00:00.000Z'),
      ];

      final messages = {
        'peer-A': [
          _makeMessage(
            id: 'msg-1',
            contactPeerId: 'peer-A',
            senderPeerId: 'peer-A',
            text: 'Read message',
            timestamp: '2026-02-08T08:00:00.000Z',
            isIncoming: true,
            readAt: '2026-02-08T08:30:00.000Z',
          ),
          // 26 hour gap — still one card per contact
          _makeMessage(
            id: 'msg-2',
            contactPeerId: 'peer-A',
            senderPeerId: 'peer-A',
            text: 'Unread message',
            timestamp: '2026-02-09T10:00:00.000Z',
            isIncoming: true,
          ),
        ],
      };

      final result = await loadFeed(
        contactRepo: FakeContactRepository(contacts: contacts),
        messageRepo: FakeMessageRepository(messagesByContact: messages),
      );

      final threadItems = result.whereType<ThreadFeedItem>().toList();
      // One card per contact, unread takes precedence
      expect(threadItems.length, 1);
      expect(threadItems[0].isUnreadCard, isTrue);
      expect(threadItems[0].messages.length, 2);
      expect(threadItems[0].messages[0].text, 'Read message');
      expect(threadItems[0].messages[1].text, 'Unread message');
    });

    test('sorts all items newest-first across types', () async {
      final contacts = [
        _makeContact('peer-A', 'Alice', '2026-02-09T10:00:00.000Z'),
        _makeContact('peer-B', 'Bob', '2026-02-09T14:00:00.000Z'),
      ];

      final messages = {
        'peer-A': [
          _makeMessage(
            id: 'msg-1',
            contactPeerId: 'peer-A',
            senderPeerId: 'peer-A',
            text: 'Hello',
            timestamp: '2026-02-09T12:00:00.000Z',
            isIncoming: true,
          ),
        ],
      };

      final result = await loadFeed(
        contactRepo: FakeContactRepository(contacts: contacts),
        messageRepo: FakeMessageRepository(messagesByContact: messages),
      );

      expect(result.length, 3);
      // Bob connection at 14:00, thread at 12:00, Alice connection at 10:00
      expect(result[0], isA<ConnectionFeedItem>());
      expect((result[0] as ConnectionFeedItem).contactUsername, 'Bob');
      expect(result[1], isA<ThreadFeedItem>());
      expect(result[2], isA<ConnectionFeedItem>());
      expect((result[2] as ConnectionFeedItem).contactUsername, 'Alice');
    });

    test('includes blocked contacts with isBlocked flag', () async {
      final contacts = [
        _makeContact('peer-A', 'Alice', '2026-02-01T10:00:00.000Z'),
        ContactModel(
          peerId: 'peer-B',
          publicKey: 'pk-peer-B',
          rendezvous: '/dns4/relay/tcp/443/p2p/relay',
          username: 'BlockedBob',
          signature: 'sig-peer-B',
          scannedAt: '2026-02-01T14:00:00.000Z',
          isBlocked: true,
          blockedAt: '2026-02-15T00:00:00.000Z',
        ),
      ];

      final result = await loadFeed(
        contactRepo: FakeContactRepository(contacts: contacts),
        messageRepo: FakeMessageRepository(),
      );

      expect(result.length, 2);
      // Both present, newest first: BlockedBob (14:00) then Alice (10:00)
      final bob = result[0] as ConnectionFeedItem;
      final alice = result[1] as ConnectionFeedItem;
      expect(bob.contactUsername, 'BlockedBob');
      expect(bob.isBlocked, isTrue);
      expect(alice.contactUsername, 'Alice');
      expect(alice.isBlocked, isFalse);
    });
  });

  group('160 contact-feed N+1 → batched summary + bounded window', () {
    List<ConversationMessage> seed_(
      String peerId,
      int count, {
      int unread = 0,
      bool withReply = false,
    }) {
      final base = DateTime.utc(2026, 3, 1, 8);
      final msgs = <ConversationMessage>[];
      for (var i = 0; i < count; i++) {
        final ts = base.add(Duration(minutes: i)).toIso8601String();
        // Newest `unread` incoming are unread; the rest are read.
        final isUnread = i >= count - unread;
        msgs.add(
          _makeMessage(
            id: '$peerId-m$i',
            contactPeerId: peerId,
            senderPeerId: peerId,
            text: 'msg $i',
            timestamp: ts,
            isIncoming: true,
            readAt: isUnread ? null : ts,
          ),
        );
      }
      if (withReply) {
        msgs.add(
          _makeMessage(
            id: '$peerId-reply',
            contactPeerId: peerId,
            senderPeerId: 'my-peer',
            text: 'my reply',
            timestamp: base.subtract(const Duration(minutes: 1)).toIso8601String(),
            isIncoming: false,
          ),
        );
      }
      return msgs;
    }

    test(
      'TC-160-01: contact feed preview uses batched summary, never the '
      'unbounded per-contact loop',
      () async {
        final contacts = [
          _makeContact('peer-A', 'Alice', '2026-02-09T10:00:00.000Z'),
          _makeContact('peer-B', 'Bob', '2026-02-09T11:00:00.000Z'),
          _makeContact('peer-C', 'Carol', '2026-02-09T12:00:00.000Z'),
        ];
        // Each thread is deep (40) and pending (has unread) so all 3 load a
        // window.
        final repo = FakeMessageRepository(
          messagesByContact: {
            'peer-A': seed_('peer-A', 40, unread: 5),
            'peer-B': seed_('peer-B', 40, unread: 5),
            'peer-C': seed_('peer-C', 40, unread: 5),
          },
        );

        await loadContactFeedItems(
          contactRepo: FakeContactRepository(contacts: contacts),
          messageRepo: repo,
        );

        expect(repo.getMessagesForContactCallCount, 0);
        expect(repo.getConversationThreadSummariesCallCount, 1);
        expect(repo.getMessagesPageCalls, hasLength(3));
        for (final call in repo.getMessagesPageCalls) {
          expect(call.$2, greaterThan(1)); // never limit-1, never unbounded/null
        }
      },
    );

    test(
      'TC-160-02: preview-row correctness preserved under the summary path',
      () async {
        // peer-A: deep history, some unread + a reply → active.
        // peer-B: deep history, unread only → unread.
        final contacts = [
          _makeContact('peer-A', 'Alice', '2026-02-09T10:00:00.000Z'),
          _makeContact('peer-B', 'Bob', '2026-02-09T11:00:00.000Z'),
        ];
        final repo = FakeMessageRepository(
          messagesByContact: {
            'peer-A': seed_('peer-A', 30, unread: 4, withReply: true),
            'peer-B': seed_('peer-B', 30, unread: 6),
          },
        );

        final items = await loadContactFeedItems(
          contactRepo: FakeContactRepository(contacts: contacts),
          messageRepo: repo,
        );
        final threads = {
          for (final t in items.whereType<ThreadFeedItem>()) t.contactPeerId: t,
        };

        expect(threads['peer-A']!.unreadCount, 4);
        expect(threads['peer-A']!.conversationState, ConversationState.active);
        expect(threads['peer-A']!.hasReply, isTrue);
        expect(threads['peer-B']!.unreadCount, 6);
        expect(threads['peer-B']!.conversationState, ConversationState.unread);
      },
    );

    test(
      'TC-160-14: an all-read contact (summary unreadCount==0) loads ZERO '
      'messages on mount',
      () async {
        final contacts = [
          _makeContact('peer-pending', 'Pat', '2026-02-09T10:00:00.000Z'),
          _makeContact('peer-allread', 'Reed', '2026-02-09T11:00:00.000Z'),
        ];
        final repo = FakeMessageRepository(
          messagesByContact: {
            'peer-pending': seed_('peer-pending', 12, unread: 3),
            // Fully read deep history.
            'peer-allread': seed_('peer-allread', 25, unread: 0),
          },
        );

        await loadContactFeedItems(
          contactRepo: FakeContactRepository(contacts: contacts),
          messageRepo: repo,
        );

        final pendingCalls = repo.getMessagesPageCalls
            .where((c) => c.$1 == 'peer-pending')
            .length;
        final allReadCalls = repo.getMessagesPageCalls
            .where((c) => c.$1 == 'peer-allread')
            .length;
        expect(allReadCalls, 0); // all-read → zero message reads
        expect(pendingCalls, 1); // pending → exactly one bounded page
        expect(repo.getMessagesForContactCallCount, 0);
      },
    );

    test(
      'TC-160-16: card unreadCount comes from summary.unreadCount, not a window '
      're-scan',
      () async {
        // 30 unread; the loaded window covers them, but the count must be the
        // summary value regardless of window slicing.
        final contacts = [
          _makeContact('peer-A', 'Alice', '2026-02-09T10:00:00.000Z'),
        ];
        final repo = FakeMessageRepository(
          messagesByContact: {'peer-A': seed_('peer-A', 30, unread: 30)},
        );

        final items = await loadContactFeedItems(
          contactRepo: FakeContactRepository(contacts: contacts),
          messageRepo: repo,
        );
        final thread = items.whereType<ThreadFeedItem>().single;
        expect(thread.unreadCount, 30);
        expect(thread.totalMessageCount, 30);
      },
    );
  });

  group('161 group-feed batched preview + bounded window', () {
    // Seeds a group with `readIncoming` read incoming, `unreadIncoming` unread
    // incoming (the newest run), and optionally one OUTGOING reply at the very
    // OLDEST slot (so a newest-first unread-run window EXCLUDES it — the
    // off-window-reply state trap).
    Future<void> seedGroup(
      InMemoryGroupRepository groupRepo,
      InMemoryGroupMessageRepository groupMsgRepo,
      String groupId, {
      int readIncoming = 0,
      int unreadIncoming = 0,
      bool oldOutgoingReply = false,
    }) async {
      await groupRepo.saveGroup(
        GroupModel(
          id: groupId,
          name: 'Group $groupId',
          type: GroupType.chat,
          topicName: '/mknoon/group/$groupId',
          createdAt: DateTime(2026, 2, 1),
          createdBy: 'admin',
          myRole: GroupRole.member,
        ),
      );
      final base = DateTime.utc(2026, 3, 1, 8);
      var minute = 0;
      if (oldOutgoingReply) {
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: '$groupId-oldreply',
            groupId: groupId,
            senderPeerId: 'me',
            text: 'old reply',
            timestamp: base.add(Duration(minutes: minute)),
            createdAt: base.add(Duration(minutes: minute)),
            isIncoming: false,
            status: 'sent',
          ),
        );
        minute++;
      }
      for (var i = 0; i < readIncoming; i++) {
        final ts = base.add(Duration(minutes: minute++));
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: '$groupId-r$i',
            groupId: groupId,
            senderPeerId: 'p1',
            text: 'read $i',
            timestamp: ts,
            createdAt: ts,
            isIncoming: true,
            readAt: ts,
          ),
        );
      }
      for (var i = 0; i < unreadIncoming; i++) {
        final ts = base.add(Duration(minutes: minute++));
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: '$groupId-u$i',
            groupId: groupId,
            senderPeerId: 'p1',
            text: 'unread $i',
            timestamp: ts,
            createdAt: ts,
            isIncoming: true,
          ),
        );
      }
    }

    test(
      'TC-161-03: collapsed group feed batches via getGroupThreadPreviews + a '
      'bounded per-pending window, never the unbounded limit:200 loop',
      () async {
        final groupRepo = InMemoryGroupRepository();
        final groupMsgRepo = InMemoryGroupMessageRepository();
        // 3 deep pending groups (unread > 0, history >> window).
        await seedGroup(groupRepo, groupMsgRepo, 'g1',
            readIncoming: 35, unreadIncoming: 5);
        await seedGroup(groupRepo, groupMsgRepo, 'g2',
            readIncoming: 35, unreadIncoming: 5);
        await seedGroup(groupRepo, groupMsgRepo, 'g3',
            readIncoming: 35, unreadIncoming: 5);

        final items = await loadGroupFeedItems(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
        );

        // ONE batched summary call for all groups.
        expect(groupMsgRepo.getGroupThreadPreviewsCallCount, 1);
        // One BOUNDED window per pending group (mirrors 160 TC-160-01): never
        // the unbounded limit:200 full-page load, never limit-1.
        expect(groupMsgRepo.getMessagesPageCallLog, hasLength(3));
        for (final call in groupMsgRepo.getMessagesPageCallLog) {
          expect(call.$2, greaterThanOrEqualTo(5)); // covers the unread run
          expect(call.$2, lessThan(200)); // bounded, not the full page
        }
        expect(items, hasLength(3));
      },
    );

    test(
      'TC-161-04: unreadCount + ConversationState come from the summary, not the '
      'truncated window (off-window old reply still classifies active)',
      () async {
        final groupRepo = InMemoryGroupRepository();
        final groupMsgRepo = InMemoryGroupMessageRepository();
        // g-active: deep read history + an OLD outgoing reply at the oldest slot
        // (OUTSIDE the newest unread-run window) + a newest unread run → active
        // ONLY if hasSent is sourced from the summary, not the window.
        await seedGroup(groupRepo, groupMsgRepo, 'g-active',
            readIncoming: 30, unreadIncoming: 4, oldOutgoingReply: true);
        // g-unread: deep history, unread only, no outgoing → unread.
        await seedGroup(groupRepo, groupMsgRepo, 'g-unread',
            readIncoming: 30, unreadIncoming: 6);

        final items = await loadGroupFeedItems(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
        );
        final byId = {for (final i in items) i.groupId: i};

        expect(byId['g-active']!.unreadCount, 4);
        expect(
          byId['g-active']!.conversationState,
          ConversationState.active,
          reason: 'old outgoing reply is off-window; state must use the summary',
        );
        expect(byId['g-unread']!.unreadCount, 6);
        expect(byId['g-unread']!.conversationState, ConversationState.unread);
      },
    );

    test(
      'TC-161-11: an all-read group loads ZERO windowed messages (pending '
      'filter); only the pending group loads a bounded window',
      () async {
        final groupRepo = InMemoryGroupRepository();
        final groupMsgRepo = InMemoryGroupMessageRepository();
        await seedGroup(groupRepo, groupMsgRepo, 'g-pending',
            readIncoming: 8, unreadIncoming: 3);
        // Fully-read deep history, no unread.
        await seedGroup(groupRepo, groupMsgRepo, 'g-allread',
            readIncoming: 20, unreadIncoming: 0);

        await loadGroupFeedItems(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
        );

        final pendingCalls = groupMsgRepo.getMessagesPageCallLog
            .where((c) => c.$1 == 'g-pending')
            .length;
        final allReadCalls = groupMsgRepo.getMessagesPageCallLog
            .where((c) => c.$1 == 'g-allread')
            .length;
        expect(allReadCalls, 0); // all-read → zero message reads
        expect(pendingCalls, 1); // pending → exactly one bounded page
      },
    );

    test(
      'TC-161-10: a group with > maxPreview unread loads its full unread run '
      '(window sized to unread + context, not a fixed K)',
      () async {
        final groupRepo = InMemoryGroupRepository();
        final groupMsgRepo = InMemoryGroupMessageRepository();
        await seedGroup(groupRepo, groupMsgRepo, 'g-many',
            readIncoming: 0, unreadIncoming: 20);

        final items = await loadGroupFeedItems(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
        );

        final item = items.single;
        expect(item.unreadCount, 20);
        // The full unread run is loaded into the window (uncapped group letter
        // renders every unread line; a fixed K=8 would truncate this to 8).
        expect(
          item.unreadMessages.length,
          20,
          reason: 'window must cover the whole unread run, never a fixed K',
        );
      },
    );
  });

  group('loadFeed with group messages', () {
    test('returns group thread items when group repos provided', () async {
      final groupRepo = InMemoryGroupRepository();
      final groupMsgRepo = InMemoryGroupMessageRepository();

      await groupRepo.saveGroup(
        GroupModel(
          id: 'g1',
          name: 'Alpha Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/g1',
          createdAt: DateTime(2026, 2, 1),
          createdBy: 'admin',
          myRole: GroupRole.member,
        ),
      );
      await groupMsgRepo.saveMessage(
        GroupMessage(
          id: 'gm-1',
          groupId: 'g1',
          senderPeerId: 'p1',
          senderUsername: 'User1',
          text: 'Hello group!',
          timestamp: DateTime.utc(2026, 2, 9, 12, 0),
          createdAt: DateTime.utc(2026, 2, 9, 12, 0),
        ),
      );

      final result = await loadFeed(
        contactRepo: FakeContactRepository(),
        messageRepo: FakeMessageRepository(),
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
      );

      final groupItems = result.whereType<GroupThreadFeedItem>().toList();
      expect(groupItems.length, 1);
      expect(groupItems[0].groupName, 'Alpha Group');
      expect(groupItems[0].messages.length, 1);
    });

    test('group items merge with contact items sorted by timestamp', () async {
      final groupRepo = InMemoryGroupRepository();
      final groupMsgRepo = InMemoryGroupMessageRepository();

      final contacts = [
        _makeContact('peer-A', 'Alice', '2026-02-09T10:00:00.000Z'),
      ];

      await groupRepo.saveGroup(
        GroupModel(
          id: 'g1',
          name: 'Group Alpha',
          type: GroupType.chat,
          topicName: '/mknoon/group/g1',
          createdAt: DateTime(2026, 2, 1),
          createdBy: 'admin',
          myRole: GroupRole.member,
        ),
      );
      await groupMsgRepo.saveMessage(
        GroupMessage(
          id: 'gm-1',
          groupId: 'g1',
          senderPeerId: 'p1',
          text: 'Group msg',
          timestamp: DateTime.utc(2026, 2, 9, 14, 0),
          createdAt: DateTime.utc(2026, 2, 9, 14, 0),
        ),
      );

      final result = await loadFeed(
        contactRepo: FakeContactRepository(contacts: contacts),
        messageRepo: FakeMessageRepository(),
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
      );

      expect(result.length, 2);
      // Group at 14:00, Alice connection at 10:00
      expect(result[0], isA<GroupThreadFeedItem>());
      expect(result[1], isA<ConnectionFeedItem>());
    });

    test(
      'dissolved groups stay visible but project frozen feed affordances',
      () async {
        final groupRepo = InMemoryGroupRepository();
        final groupMsgRepo = InMemoryGroupMessageRepository();

        await groupRepo.saveGroup(
          GroupModel(
            id: 'g1',
            name: 'Frozen Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/g1',
            createdAt: DateTime(2026, 2, 1),
            createdBy: 'admin',
            myRole: GroupRole.member,
            isDissolved: true,
            dissolvedAt: DateTime.utc(2026, 2, 9, 11, 59),
            dissolvedBy: 'admin',
          ),
        );
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'gm-1',
            groupId: 'g1',
            senderPeerId: 'p1',
            text: 'Frozen history',
            timestamp: DateTime.utc(2026, 2, 9, 12, 0),
            createdAt: DateTime.utc(2026, 2, 9, 12, 0),
          ),
        );

        final result = await loadFeed(
          contactRepo: FakeContactRepository(),
          messageRepo: FakeMessageRepository(),
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
        );

        final groupItems = result.whereType<GroupThreadFeedItem>().toList();
        expect(groupItems, hasLength(1));
        expect(groupItems.first.isDissolved, isTrue);
        expect(groupItems.first.canWrite, isFalse);
        expect(groupItems.first.canReact, isFalse);
      },
    );

    test('no group items when group repos not provided', () async {
      final result = await loadFeed(
        contactRepo: FakeContactRepository(),
        messageRepo: FakeMessageRepository(),
      );

      final groupItems = result.whereType<GroupThreadFeedItem>().toList();
      expect(groupItems, isEmpty);
    });

    test('archived groups excluded from feed', () async {
      final groupRepo = InMemoryGroupRepository();
      final groupMsgRepo = InMemoryGroupMessageRepository();

      await groupRepo.saveGroup(
        GroupModel(
          id: 'g1',
          name: 'Active Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/g1',
          createdAt: DateTime(2026, 2, 1),
          createdBy: 'admin',
          myRole: GroupRole.member,
        ),
      );
      await groupRepo.saveGroup(
        GroupModel(
          id: 'g2',
          name: 'Archived Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/g2',
          createdAt: DateTime(2026, 2, 1),
          createdBy: 'admin',
          myRole: GroupRole.member,
          isArchived: true,
          archivedAt: DateTime(2026, 2, 5),
        ),
      );
      await groupMsgRepo.saveMessage(
        GroupMessage(
          id: 'gm-1',
          groupId: 'g1',
          senderPeerId: 'p1',
          text: 'Active msg',
          timestamp: DateTime.utc(2026, 2, 9, 12, 0),
          createdAt: DateTime.utc(2026, 2, 9, 12, 0),
        ),
      );
      await groupMsgRepo.saveMessage(
        GroupMessage(
          id: 'gm-2',
          groupId: 'g2',
          senderPeerId: 'p1',
          text: 'Archived msg',
          timestamp: DateTime.utc(2026, 2, 9, 13, 0),
          createdAt: DateTime.utc(2026, 2, 9, 13, 0),
        ),
      );

      final result = await loadFeed(
        contactRepo: FakeContactRepository(),
        messageRepo: FakeMessageRepository(),
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
      );

      final groupItems = result.whereType<GroupThreadFeedItem>().toList();
      expect(groupItems.length, 1);
      expect(groupItems[0].groupName, 'Active Group');
    });

    test('groups with no messages produce no thread items', () async {
      final groupRepo = InMemoryGroupRepository();
      final groupMsgRepo = InMemoryGroupMessageRepository();

      await groupRepo.saveGroup(
        GroupModel(
          id: 'g1',
          name: 'Empty Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/g1',
          createdAt: DateTime(2026, 2, 1),
          createdBy: 'admin',
          myRole: GroupRole.member,
        ),
      );

      final result = await loadFeed(
        contactRepo: FakeContactRepository(),
        messageRepo: FakeMessageRepository(),
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
      );

      final groupItems = result.whereType<GroupThreadFeedItem>().toList();
      expect(groupItems, isEmpty);
    });

    test('loadGroupFeedItems batch-loads media attachments', () async {
      final groupRepo = InMemoryGroupRepository();
      final groupMsgRepo = InMemoryGroupMessageRepository();
      final mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
      final mediaFileManager = FakeMediaFileManager();

      await groupRepo.saveGroup(
        GroupModel(
          id: 'g1',
          name: 'Media Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/g1',
          createdAt: DateTime(2026, 2, 1),
          createdBy: 'admin',
          myRole: GroupRole.member,
        ),
      );
      await groupMsgRepo.saveMessage(
        GroupMessage(
          id: 'gm-1',
          groupId: 'g1',
          senderPeerId: 'p1',
          senderUsername: 'User1',
          text: 'Photo',
          timestamp: DateTime.utc(2026, 2, 9, 12, 0),
          createdAt: DateTime.utc(2026, 2, 9, 12, 0),
        ),
      );
      await mediaAttachmentRepo.saveAttachment(
        MediaAttachment(
          id: 'att-g1',
          messageId: 'gm-1',
          mime: 'image/jpeg',
          size: 2048,
          mediaType: 'image',
          localPath: 'media/groups/img.jpg',
          downloadStatus: 'done',
          createdAt: '2026-02-09T12:00:00.000Z',
        ),
      );

      final items = await loadGroupFeedItems(
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
      );

      expect(items, hasLength(1));
      expect(items.first.messages.first.media, hasLength(1));
      expect(items.first.messages.first.media.first.id, 'att-g1');
      // Path should be resolved
      expect(
        items.first.messages.first.media.first.localPath,
        endsWith('test_docs/media/groups/img.jpg'),
      );
    });

    test(
      'loadGroupFeedItems preserves relay-hash done group media plaintext',
      () async {
        final groupRepo = InMemoryGroupRepository();
        final groupMsgRepo = InMemoryGroupMessageRepository();
        final mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
        final mediaFileManager = FakeMediaFileManager();
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));
        const relativePath = 'media/groups/relay-hash.jpg';
        final absolutePath = await mediaFileManager.resolveStoredPath(
          relativePath,
        );
        final file = File(absolutePath)..createSync(recursive: true);
        file.writeAsBytesSync(utf8.encode('plaintext group media bytes'));
        final relayBlobHash = sha256
            .convert(utf8.encode('encrypted relay blob bytes'))
            .toString();

        await groupRepo.saveGroup(
          GroupModel(
            id: 'g1',
            name: 'Media Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/g1',
            createdAt: DateTime(2026, 2, 1),
            createdBy: 'admin',
            myRole: GroupRole.member,
          ),
        );
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'gm-1',
            groupId: 'g1',
            senderPeerId: 'p1',
            senderUsername: 'User1',
            text: 'Tampered',
            timestamp: DateTime.utc(2026, 2, 9, 12, 0),
            createdAt: DateTime.utc(2026, 2, 9, 12, 0),
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          MediaAttachment(
            id: 'att-relay-hash',
            messageId: 'gm-1',
            mime: 'image/jpeg',
            size: file.lengthSync(),
            mediaType: 'image',
            localPath: relativePath,
            downloadStatus: 'done',
            contentHash: relayBlobHash,
            encryptionKeyBase64: 'media-key',
            encryptionNonce: 'media-nonce',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: '2026-02-09T12:00:00.000Z',
          ),
        );

        final items = await loadGroupFeedItems(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
        );

        final attachment = items.single.messages.single.media.single;
        expect(attachment.id, 'att-relay-hash');
        expect(attachment.downloadStatus, kMediaDownloadStatusDone);
        expect(attachment.localPath, absolutePath);
        expect(File(absolutePath).existsSync(), isTrue);
        expect(
          events.map((event) => event['event']),
          containsAll(<String>[
            'GROUP_FEED_MEDIA_DISPLAY_VERIFY_START',
            'GROUP_FEED_MEDIA_PLAINTEXT_HASH_VALIDATION_SKIPPED',
            'GROUP_FEED_MEDIA_DISPLAY_VERIFY_ALLOWED',
          ]),
        );
        final skipped = events.singleWhere(
          (event) =>
              event['event'] ==
              'GROUP_FEED_MEDIA_PLAINTEXT_HASH_VALIDATION_SKIPPED',
        );
        expect(
          skipped['details'],
          allOf(
            containsPair('contentHashScope', 'relay_blob'),
            containsPair('plaintextHashValidationSkipped', true),
            containsPair('deleteAttempted', false),
          ),
        );

        final manifest =
            await MigrationFileManifestBuilder(
              documentsRootPath: p.dirname(p.dirname(p.dirname(absolutePath))),
            ).build(
              chatMediaRows: [
                {
                  'id': 'att-relay-hash',
                  'message_id': 'gm-1',
                  'migration_group_id': 'groups',
                  'local_path': relativePath,
                  'download_status': 'done',
                  'mime': 'image/jpeg',
                  'size': file.lengthSync(),
                  'content_hash': relayBlobHash,
                  'encryption_key_base64': 'media-key',
                  'encryption_nonce': 'media-nonce',
                  'encryption_scheme':
                      kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                },
              ],
              scanDocumentsForCacheAndTransients: false,
            );
        expect(manifest.isValid, isTrue);
        expect(
          manifest.items.single.kind,
          MigrationFileManifestItemKind.chatMedia,
        );
        expect(manifest.items.single.relativePath, relativePath);
      },
    );

    test(
      'loadGroupFeedItems emits missing file telemetry without delete',
      () async {
        final groupRepo = InMemoryGroupRepository();
        final groupMsgRepo = InMemoryGroupMessageRepository();
        final mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
        final mediaFileManager = FakeMediaFileManager();
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));
        const relativePath = 'media/groups/missing-local.jpg';
        final absolutePath = await mediaFileManager.resolveStoredPath(
          relativePath,
        );
        if (File(absolutePath).existsSync()) {
          File(absolutePath).deleteSync();
        }
        final relayBlobHash = sha256
            .convert(utf8.encode('encrypted relay blob bytes'))
            .toString();

        await groupRepo.saveGroup(
          GroupModel(
            id: 'g1',
            name: 'Media Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/g1',
            createdAt: DateTime(2026, 2, 1),
            createdBy: 'admin',
            myRole: GroupRole.member,
          ),
        );
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'gm-1',
            groupId: 'g1',
            senderPeerId: 'p1',
            senderUsername: 'User1',
            text: 'Missing',
            timestamp: DateTime.utc(2026, 2, 9, 12, 0),
            createdAt: DateTime.utc(2026, 2, 9, 12, 0),
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          MediaAttachment(
            id: 'att-missing-file',
            messageId: 'gm-1',
            mime: 'image/jpeg',
            size: 128,
            mediaType: 'image',
            localPath: relativePath,
            downloadStatus: 'done',
            contentHash: relayBlobHash,
            encryptionKeyBase64: 'media-key',
            encryptionNonce: 'media-nonce',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: '2026-02-09T12:00:00.000Z',
          ),
        );

        final items = await loadGroupFeedItems(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
        );

        final attachment = items.single.messages.single.media.single;
        expect(attachment.id, 'att-missing-file');
        expect(attachment.downloadStatus, kMediaDownloadStatusPending);
        expect(attachment.localPath, absolutePath);
        expect(File(absolutePath).existsSync(), isFalse);
        expect(
          events.map((event) => event['event']),
          containsAll(<String>[
            'GROUP_FEED_MEDIA_DISPLAY_VERIFY_START',
            'GROUP_FEED_MEDIA_LOCAL_FILE_MISSING',
            'GROUP_FEED_MEDIA_DISPLAY_VERIFY_BLOCKED',
          ]),
        );
        expect(
          events.map((event) => event['event']),
          isNot(contains('APP_OWNED_MEDIA_DELETE_START')),
        );
        final missing = events.singleWhere(
          (event) => event['event'] == 'GROUP_FEED_MEDIA_LOCAL_FILE_MISSING',
        );
        expect(
          missing['details'],
          allOf(
            containsPair('reason', 'missing_file'),
            containsPair('fileExists', false),
            containsPair('deleteAttempted', false),
          ),
        );
      },
    );

    test('loadFeed includes group media attachments', () async {
      final groupRepo = InMemoryGroupRepository();
      final groupMsgRepo = InMemoryGroupMessageRepository();
      final mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
      final mediaFileManager = FakeMediaFileManager();

      await groupRepo.saveGroup(
        GroupModel(
          id: 'g1',
          name: 'Media Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/g1',
          createdAt: DateTime(2026, 2, 1),
          createdBy: 'admin',
          myRole: GroupRole.member,
        ),
      );
      await groupMsgRepo.saveMessage(
        GroupMessage(
          id: 'gm-1',
          groupId: 'g1',
          senderPeerId: 'p1',
          senderUsername: 'User1',
          text: 'Image message',
          timestamp: DateTime.utc(2026, 2, 9, 12, 0),
          createdAt: DateTime.utc(2026, 2, 9, 12, 0),
        ),
      );
      await mediaAttachmentRepo.saveAttachment(
        MediaAttachment(
          id: 'att-g1',
          messageId: 'gm-1',
          mime: 'image/jpeg',
          size: 2048,
          mediaType: 'image',
          localPath: 'media/groups/img.jpg',
          downloadStatus: 'done',
          createdAt: '2026-02-09T12:00:00.000Z',
        ),
      );

      final result = await loadFeed(
        contactRepo: FakeContactRepository(),
        messageRepo: FakeMessageRepository(),
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
      );

      final groupItems = result.whereType<GroupThreadFeedItem>().toList();
      expect(groupItems, hasLength(1));
      expect(groupItems.first.messages.first.media, hasLength(1));
      expect(groupItems.first.messages.first.media.first.id, 'att-g1');
    });
  });

  group('162 media-resolve sync swap', () {
    test(
      'TC-162-02: loadContactFeedItems (1:1) materializes media via sync '
      'resolution, zero awaited resolves',
      () async {
        final contacts = [
          _makeContact('peer-A', 'Alice', '2026-02-09T10:00:00.000Z'),
        ];
        // One PENDING (unread) incoming message so the bounded window loads and
        // its attachments are resolved through `loadConversationPage` →
        // `_attachMedia` (the 160 path the 1:1 feed resolve now flows through).
        final repo = FakeMessageRepository(
          messagesByContact: {
            'peer-A': [
              _makeMessage(
                id: 'm1',
                contactPeerId: 'peer-A',
                senderPeerId: 'peer-A',
                text: 'Two photos',
                timestamp: '2026-03-01T08:00:00.000Z',
                isIncoming: true,
              ),
            ],
          },
        );
        final mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'a1',
            messageId: 'm1',
            mime: 'image/jpeg',
            size: 2048,
            mediaType: 'image',
            localPath: 'media/peer-A/a1.jpg',
            downloadStatus: 'done',
            createdAt: '2026-03-01T08:00:00.000Z',
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'a2',
            messageId: 'm1',
            mime: 'image/jpeg',
            size: 4096,
            mediaType: 'image',
            localPath: 'media/peer-A/a2.jpg',
            downloadStatus: 'done',
            createdAt: '2026-03-01T08:00:00.000Z',
          ),
        );
        final mediaFileManager = FakeMediaFileManager();

        final items = await loadContactFeedItems(
          contactRepo: FakeContactRepository(contacts: contacts),
          messageRepo: repo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
        );

        // (a) zero awaited async resolves — the loop uses the static sync twin.
        expect(mediaFileManager.resolveStoredPathCount, 0);
        // (b) each attachment resolved exactly as the static twin would.
        final thread = items.whereType<ThreadFeedItem>().single;
        final withMedia = thread.messages.firstWhere((m) => m.media.isNotEmpty);
        expect(withMedia.media.map((m) => m.localPath).toList(), [
          MediaFileManager.resolveStoredPathSync('media/peer-A/a1.jpg'),
          MediaFileManager.resolveStoredPathSync('media/peer-A/a2.jpg'),
        ]);
      },
    );

    test(
      'TC-162-03: loadGroupFeedItems resolves via the sync twin AND preserves '
      'the existsSync/lengthSync verify + GROUP_FEED_MEDIA_* event sequence',
      () async {
        final groupRepo = InMemoryGroupRepository();
        final groupMsgRepo = InMemoryGroupMessageRepository();
        final mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
        final mediaFileManager = FakeMediaFileManager();
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));

        await groupRepo.saveGroup(
          GroupModel(
            id: 'g1',
            name: 'Media Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/g1',
            createdAt: DateTime(2026, 2, 1),
            createdBy: 'admin',
            myRole: GroupRole.member,
          ),
        );
        // Two unread incoming messages → pending group → window loads both.
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'gm-valid',
            groupId: 'g1',
            senderPeerId: 'p1',
            text: 'Valid',
            timestamp: DateTime.utc(2026, 2, 9, 12, 0),
            createdAt: DateTime.utc(2026, 2, 9, 12, 0),
            isIncoming: true,
          ),
        );
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'gm-missing',
            groupId: 'g1',
            senderPeerId: 'p1',
            text: 'Missing',
            timestamp: DateTime.utc(2026, 2, 9, 12, 1),
            createdAt: DateTime.utc(2026, 2, 9, 12, 1),
            isIncoming: true,
          ),
        );

        const validRelative = 'media/groups/sync-valid.jpg';
        final validAbsolute = MediaFileManager.resolveStoredPathSync(
          validRelative,
        );
        final validFile = File(validAbsolute)..createSync(recursive: true);
        validFile.writeAsBytesSync(utf8.encode('group media plaintext'));
        final relayBlobHash = sha256
            .convert(utf8.encode('encrypted relay blob bytes'))
            .toString();
        await mediaAttachmentRepo.saveAttachment(
          MediaAttachment(
            id: 'att-valid',
            messageId: 'gm-valid',
            mime: 'image/jpeg',
            size: validFile.lengthSync(),
            mediaType: 'image',
            localPath: validRelative,
            downloadStatus: 'done',
            contentHash: relayBlobHash,
            encryptionKeyBase64: 'media-key',
            encryptionNonce: 'media-nonce',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: '2026-02-09T12:00:00.000Z',
          ),
        );
        const missingRelative = 'media/groups/sync-missing.jpg';
        final missingAbsolute = MediaFileManager.resolveStoredPathSync(
          missingRelative,
        );
        if (File(missingAbsolute).existsSync()) {
          File(missingAbsolute).deleteSync();
        }
        await mediaAttachmentRepo.saveAttachment(
          MediaAttachment(
            id: 'att-missing',
            messageId: 'gm-missing',
            mime: 'image/jpeg',
            size: 128,
            mediaType: 'image',
            localPath: missingRelative,
            downloadStatus: 'done',
            contentHash: relayBlobHash,
            encryptionKeyBase64: 'media-key',
            encryptionNonce: 'media-nonce',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: '2026-02-09T12:01:00.000Z',
          ),
        );

        final items = await loadGroupFeedItems(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
        );

        // (a) zero awaited async resolves — the group resolve uses the sync twin.
        expect(mediaFileManager.resolveStoredPathCount, 0);

        // (b) the valid attachment resolved to the sync-twin absolute path.
        final allMedia = items
            .single
            .messages
            .expand((m) => m.media)
            .toList();
        final valid = allMedia.singleWhere((m) => m.id == 'att-valid');
        final missing = allMedia.singleWhere((m) => m.id == 'att-missing');
        expect(valid.localPath, validAbsolute);
        expect(valid.downloadStatus, kMediaDownloadStatusDone);
        expect(missing.localPath, missingAbsolute);
        expect(missing.downloadStatus, kMediaDownloadStatusPending);

        // (c) the verify-event sequence is byte-identical: ALLOWED for the valid
        // attachment, LOCAL_FILE_MISSING (NOT ALLOWED) for the absent one — the
        // distinct-event discriminator proving the existsSync gate survives.
        final eventNames = events.map((e) => e['event']).toList();
        expect(
          eventNames,
          containsAll(<String>[
            'GROUP_FEED_MEDIA_DISPLAY_VERIFY_START',
            'GROUP_FEED_MEDIA_PLAINTEXT_HASH_VALIDATION_SKIPPED',
            'GROUP_FEED_MEDIA_DISPLAY_VERIFY_ALLOWED',
            'GROUP_FEED_MEDIA_LOCAL_FILE_MISSING',
            'GROUP_FEED_MEDIA_DISPLAY_VERIFY_BLOCKED',
          ]),
        );
      },
    );
  });
}
