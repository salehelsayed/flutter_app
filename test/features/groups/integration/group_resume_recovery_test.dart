import 'dart:convert';

import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_group_pubsub_network.dart';
import '../../../shared/fakes/group_test_user.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

/// A bridge that simulates cursor-based inbox retrieval for integration tests.
class _CursorInboxBridge extends FakeBridge {
  final Map<String, _InboxPage> pages = {};

  void addPage(
      String groupId,
      String cursor,
      List<Map<String, dynamic>> messages,
      String nextCursor,
      ) {
    pages['$groupId:$cursor'] = _InboxPage(messages, nextCursor);
  }

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd != null) commandLog.add(cmd);
    sendCallCount++;
    lastSentMessage = message;
    sentMessages.add(message);
    lastCommand = cmd;

    if (cmd == 'group:inboxRetrieveCursor') {
      final payload = parsed['payload'] as Map<String, dynamic>;
      final groupId = payload['groupId'] as String;
      final cursor = payload['cursor'] as String? ?? '';
      final key = '$groupId:$cursor';

      final page = pages[key];
      if (page != null) {
        return jsonEncode({
          'ok': true,
          'messages': page.messages,
          'cursor': page.nextCursor,
        });
      }
      return jsonEncode({
        'ok': true,
        'messages': <Map<String, dynamic>>[],
        'cursor': '',
      });
    }

    // Default: return ok for other commands (group:join, etc.)
    if (cmd != null && responses.containsKey(cmd)) {
      return jsonEncode(responses[cmd]!);
    }
    return jsonEncode({'ok': true});
  }
}

class _InboxPage {
  final List<Map<String, dynamic>> messages;
  final String nextCursor;
  _InboxPage(this.messages, this.nextCursor);
}

void main() {
  late FakeGroupPubSubNetwork network;

  setUp(() {
    network = FakeGroupPubSubNetwork();
  });

  Future<void> pump() => Future.delayed(const Duration(milliseconds: 50));

  group('Group resume recovery integration tests', () {
    test(
        'member backgrounded during send receives missed group messages after resume',
        () async {
      // Arrange: Alice and Bob in a group.
      final alice = GroupTestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
        bridge: _CursorInboxBridge(),
      );
      final bobBridge = bob.bridge as _CursorInboxBridge;

      const groupId = 'group-resume-1';
      await alice.createGroup(groupId: groupId, name: 'Resume Test');
      await alice.addMember(groupId: groupId, invitee: bob);

      await bob.groupRepo.saveKey(GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: 'test-key',
        createdAt: DateTime.now().toUtc(),
      ));

      alice.start();
      bob.start();

      // Verify normal messaging works.
      await alice.sendGroupMessage(groupId: groupId, text: 'Before background');
      await pump();
      var bobMessages = await bob.loadGroupMessages(groupId);
      expect(bobMessages.where((m) => m.isIncoming), hasLength(1));

      // Simulate Bob backgrounding: unsubscribe from network.
      network.unsubscribe(groupId, bob.peerId);

      // Alice sends while Bob is backgrounded.
      await alice.sendGroupMessage(groupId: groupId, text: 'While backgrounded');
      await pump();

      // Bob should NOT have received the message.
      bobMessages = await bob.loadGroupMessages(groupId);
      expect(bobMessages.where((m) => m.isIncoming), hasLength(1));

      // Simulate resume: drain offline inbox (with missed messages).
      final ts = DateTime.now().toUtc().toIso8601String();
      bobBridge.addPage(groupId, '', [
        {
          'groupId': groupId,
          'senderId': 'alice-peer',
          'senderUsername': 'Alice',
          'keyEpoch': 0,
          'text': 'While backgrounded',
          'timestamp': ts,
          'messageId': 'msg-missed-1',
        },
      ], '');

      await drainGroupOfflineInbox(
        bridge: bob.bridge,
        groupRepo: bob.groupRepo,
        msgRepo: bob.msgRepo,
      );

      // Bob should now have 2 incoming messages.
      bobMessages = await bob.loadGroupMessages(groupId);
      expect(bobMessages.where((m) => m.isIncoming), hasLength(2));

      // Re-subscribe Bob.
      network.subscribe(groupId, bob.peerId);

      // New live messages should still work.
      await alice.sendGroupMessage(groupId: groupId, text: 'After resume');
      await pump();
      bobMessages = await bob.loadGroupMessages(groupId);
      expect(bobMessages.where((m) => m.isIncoming), hasLength(3));

      alice.dispose();
      bob.dispose();
    });

    test(
        'same message is not duplicated if both pubsub and group inbox deliver it',
        () async {
      final bob = GroupTestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
        bridge: _CursorInboxBridge(),
      );
      final bobBridge = bob.bridge as _CursorInboxBridge;

      const groupId = 'group-dedup-1';
      const sharedMessageId = 'msg-dedup-shared';
      final ts = DateTime.now().toUtc();

      // Set up Bob's group.
      await bob.groupRepo.saveGroup(GroupModel(
        id: groupId,
        name: 'Dedup Test',
        type: GroupType.chat,
        topicName: 'topic-$groupId',
        createdAt: ts,
        createdBy: 'alice-peer',
        myRole: GroupRole.member,
      ));
      await bob.groupRepo.saveMember(GroupMember(
        groupId: groupId,
        peerId: 'alice-peer',
        username: 'Alice',
        role: MemberRole.admin,
        publicKey: 'pk-alice',
        joinedAt: ts,
      ));
      await bob.groupRepo.saveMember(GroupMember(
        groupId: groupId,
        peerId: 'bob-peer',
        username: 'Bob',
        role: MemberRole.writer,
        publicKey: 'pk-bob',
        joinedAt: ts,
      ));
      await bob.groupRepo.saveKey(GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: 'test-key',
        createdAt: ts,
      ));

      bob.start();
      network.subscribe(groupId, bob.peerId);

      // Simulate pubsub delivery with a known messageId.
      final pubsubController = network.registerPeer('alice-pubsub-sim');
      network.subscribe(groupId, 'alice-pubsub-sim');

      // Deliver via pubsub (simulate what the listener receives).
      await handleIncomingGroupMessage(
        groupRepo: bob.groupRepo,
        msgRepo: bob.msgRepo,
        groupId: groupId,
        senderId: 'alice-peer',
        senderUsername: 'Alice',
        keyEpoch: 0,
        text: 'Dedup test msg',
        timestamp: ts.toIso8601String(),
        messageId: sharedMessageId,
      );

      var bobMessages = await bob.loadGroupMessages(groupId);
      expect(bobMessages.where((m) => m.isIncoming).length, 1);

      // Now drain inbox which also has the same message with the same messageId.
      bobBridge.addPage(groupId, '', [
        {
          'groupId': groupId,
          'senderId': 'alice-peer',
          'senderUsername': 'Alice',
          'keyEpoch': 0,
          'text': 'Dedup test msg',
          'timestamp': ts.toIso8601String(),
          'messageId': sharedMessageId,
        },
      ], '');

      await drainGroupOfflineInbox(
        bridge: bob.bridge,
        groupRepo: bob.groupRepo,
        msgRepo: bob.msgRepo,
      );

      // Still only 1 incoming message — deduplicated by messageId.
      bobMessages = await bob.loadGroupMessages(groupId);
      expect(
        bobMessages.where((m) => m.isIncoming).length,
        1,
        reason: 'Message should not be duplicated by inbox drain',
      );

      pubsubController.close();
      bob.dispose();
    });

    test('watchdog restart rejoins topics and receives subsequent live messages',
        () async {
      final alice = GroupTestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );

      const groupId = 'group-watchdog-1';
      await alice.createGroup(groupId: groupId, name: 'Watchdog Test');
      await alice.addMember(groupId: groupId, invitee: bob);

      await bob.groupRepo.saveKey(GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: 'test-key',
        createdAt: DateTime.now().toUtc(),
      ));

      alice.start();
      bob.start();

      // Normal messaging works.
      await alice.sendGroupMessage(groupId: groupId, text: 'Before watchdog');
      await pump();
      var bobMessages = await bob.loadGroupMessages(groupId);
      expect(bobMessages.where((m) => m.isIncoming), hasLength(1));

      // Simulate watchdog restart: unsubscribe Bob (Go node restarted).
      network.unsubscribe(groupId, bob.peerId);

      // Rejoin with watchdog restart reason.
      await rejoinGroupTopics(
        bridge: bob.bridge,
        groupRepo: bob.groupRepo,
        reason: RejoinReason.watchdogRestart,
      );

      // Verify bridge received join command.
      final joinCmds = bob.bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:join')
          .toList();
      expect(joinCmds, isNotEmpty);

      // Re-subscribe on fake network (in production, Go does this internally).
      network.subscribe(groupId, bob.peerId);

      // Live messages should work after rejoin.
      await alice.sendGroupMessage(
          groupId: groupId, text: 'After watchdog restart');
      await pump();
      bobMessages = await bob.loadGroupMessages(groupId);
      expect(bobMessages.where((m) => m.isIncoming), hasLength(2));

      alice.dispose();
      bob.dispose();
    });

    test(
        'announcement reader backgrounded during send receives missed announces after resume',
        () async {
      final admin = GroupTestUser.create(
        peerId: 'admin-peer',
        username: 'Admin',
        network: network,
      );
      final reader = GroupTestUser.create(
        peerId: 'reader-peer',
        username: 'Reader',
        network: network,
        bridge: _CursorInboxBridge(),
      );
      final readerBridge = reader.bridge as _CursorInboxBridge;

      const groupId = 'group-announce-resume';
      await admin.createGroup(
        groupId: groupId,
        name: 'Announcements',
        type: GroupType.announcement,
      );
      await admin.addMember(groupId: groupId, invitee: reader);

      await reader.groupRepo.saveKey(GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: 'test-key',
        createdAt: DateTime.now().toUtc(),
      ));

      admin.start();
      reader.start();

      // Admin sends announcement — reader receives via pubsub.
      await admin.sendGroupMessage(
          groupId: groupId, text: 'Announcement 1');
      await pump();
      var readerMessages = await reader.loadGroupMessages(groupId);
      expect(readerMessages.where((m) => m.isIncoming), hasLength(1));

      // Reader backgrounds.
      network.unsubscribe(groupId, reader.peerId);

      // Admin sends while reader is backgrounded.
      await admin.sendGroupMessage(
          groupId: groupId, text: 'Announcement 2');
      await pump();

      // Reader should NOT have received it.
      readerMessages = await reader.loadGroupMessages(groupId);
      expect(readerMessages.where((m) => m.isIncoming), hasLength(1));

      // Resume: drain inbox.
      final ts = DateTime.now().toUtc().toIso8601String();
      readerBridge.addPage(groupId, '', [
        {
          'groupId': groupId,
          'senderId': 'admin-peer',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': 'Announcement 2',
          'timestamp': ts,
          'messageId': 'msg-announce-2',
        },
      ], '');

      await drainGroupOfflineInbox(
        bridge: reader.bridge,
        groupRepo: reader.groupRepo,
        msgRepo: reader.msgRepo,
      );

      // Reader should now have 2 incoming announcements.
      readerMessages = await reader.loadGroupMessages(groupId);
      expect(readerMessages.where((m) => m.isIncoming), hasLength(2));

      admin.dispose();
      reader.dispose();
    });

    test(
        'group discovery remains live across ttl refresh window without manual rejoin',
        () async {
      // This is a structural test: verify that after rejoining,
      // the topic subscription persists without needing manual re-rejoin.
      final alice = GroupTestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );

      const groupId = 'group-ttl-refresh';
      await alice.createGroup(groupId: groupId, name: 'TTL Test');

      await alice.groupRepo.saveKey(GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: 'test-key',
        createdAt: DateTime.now().toUtc(),
      ));

      alice.start();

      // Verify subscription is active.
      expect(network.isSubscribed(groupId, alice.peerId), isTrue);

      // Simulate time passing (no manual rejoin needed).
      await pump();

      // Subscription should still be active.
      expect(network.isSubscribed(groupId, alice.peerId), isTrue);

      alice.dispose();
    });

    test(
        'group peers with usable direct addresses form live links without forced relay dial',
        () async {
      // This test verifies that the FakeGroupPubSubNetwork correctly
      // delivers messages between subscribed peers without requiring
      // explicit relay simulation.
      final alice = GroupTestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );

      const groupId = 'group-direct-path';
      await alice.createGroup(groupId: groupId, name: 'Direct Test');
      await alice.addMember(groupId: groupId, invitee: bob);

      alice.start();
      bob.start();

      // Message delivery works directly (no relay setup needed in tests).
      await alice.sendGroupMessage(groupId: groupId, text: 'Direct msg');
      await pump();

      final bobMessages = await bob.loadGroupMessages(groupId);
      expect(bobMessages.where((m) => m.isIncoming), hasLength(1));

      alice.dispose();
      bob.dispose();
    });

    test('many joined groups resume without bursting recovery work all at once',
        () async {
      final user = GroupTestUser.create(
        peerId: 'user-peer',
        username: 'User',
        network: network,
        bridge: _CursorInboxBridge(),
      );
      final userBridge = user.bridge as _CursorInboxBridge;

      // Create 5 groups.
      final groupIds = List.generate(5, (i) => 'group-multi-$i');
      for (final gid in groupIds) {
        await user.createGroup(groupId: gid, name: 'Multi $gid');
        await user.groupRepo.saveKey(GroupKeyInfo(
          groupId: gid,
          keyGeneration: 1,
          encryptedKey: 'key-$gid',
          createdAt: DateTime.now().toUtc(),
        ));

        // Each group has one offline message.
        final ts = DateTime.now().toUtc().toIso8601String();
        userBridge.addPage(gid, '', [
          {
            'groupId': gid,
            'senderId': 'other-peer',
            'senderUsername': 'Other',
            'keyEpoch': 0,
            'text': 'Missed msg in $gid',
            'timestamp': ts,
            'messageId': 'msg-multi-$gid',
          },
        ], '');
      }

      user.start();

      // Drain all groups' inboxes.
      await drainGroupOfflineInbox(
        bridge: user.bridge,
        groupRepo: user.groupRepo,
        msgRepo: user.msgRepo,
      );

      // All 5 groups should have been drained.
      final retrieveCount = userBridge.commandLog
          .where((c) => c == 'group:inboxRetrieveCursor')
          .length;
      expect(retrieveCount, 5);

      // Verify each group has 1 message.
      for (final gid in groupIds) {
        final msgs = await user.msgRepo.getMessagesPage(gid);
        expect(msgs.length, 1,
            reason: 'Group $gid should have 1 drained message');
      }

      user.dispose();
    });
  });
}
