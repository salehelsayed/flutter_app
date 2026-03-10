import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../test/core/bridge/fake_bridge.dart';
import '../test/shared/fakes/fake_group_pubsub_network.dart';
import '../test/shared/fakes/group_test_user.dart';

/// Simulates cursor-based group inbox retrieval for simulator-backed smoke runs.
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
      final page = pages['$groupId:$cursor'];
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

Future<void> _pumpNetwork() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Group recovery simulator smoke', () {
    late FakeGroupPubSubNetwork network;

    setUp(() {
      network = FakeGroupPubSubNetwork();
    });

    testWidgets(
      'group member receives missed group messages after resume drain',
      (tester) async {
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

        const groupId = 'group-recovery-smoke';
        await alice.createGroup(groupId: groupId, name: 'Recovery Smoke');
        await alice.addMember(groupId: groupId, invitee: bob);

        await bob.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'group-key-smoke',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        alice.start();
        bob.start();

        await alice.sendGroupMessage(
          groupId: groupId,
          text: 'Before background',
        );
        await _pumpNetwork();
        expect(
          (await bob.loadGroupMessages(groupId)).where((m) => m.isIncoming),
          hasLength(1),
        );

        network.unsubscribe(groupId, bob.peerId);
        await alice.sendGroupMessage(
          groupId: groupId,
          text: 'While backgrounded',
        );
        await _pumpNetwork();

        expect(
          (await bob.loadGroupMessages(groupId)).where((m) => m.isIncoming),
          hasLength(1),
        );

        bobBridge.addPage(groupId, '', [
          {
            'groupId': groupId,
            'senderId': 'alice-peer',
            'senderUsername': 'Alice',
            'keyEpoch': 0,
            'text': 'While backgrounded',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'messageId': 'group-missed-1',
          },
        ], '');

        await drainGroupOfflineInbox(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
        );

        expect(
          (await bob.loadGroupMessages(groupId)).where((m) => m.isIncoming),
          hasLength(2),
        );

        alice.dispose();
        bob.dispose();
      },
    );

    testWidgets(
      'announcement reader receives missed announcement after resume drain',
      (tester) async {
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

        const groupId = 'announcement-recovery-smoke';
        await admin.createGroup(
          groupId: groupId,
          name: 'Announcements',
          type: GroupType.announcement,
        );
        await admin.addMember(groupId: groupId, invitee: reader);

        await reader.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'announcement-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        admin.start();
        reader.start();

        await admin.sendGroupMessage(groupId: groupId, text: 'Announcement 1');
        await _pumpNetwork();
        expect(
          (await reader.loadGroupMessages(groupId)).where((m) => m.isIncoming),
          hasLength(1),
        );

        network.unsubscribe(groupId, reader.peerId);
        await admin.sendGroupMessage(groupId: groupId, text: 'Announcement 2');
        await _pumpNetwork();

        expect(
          (await reader.loadGroupMessages(groupId)).where((m) => m.isIncoming),
          hasLength(1),
        );

        readerBridge.addPage(groupId, '', [
          {
            'groupId': groupId,
            'senderId': 'admin-peer',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': 'Announcement 2',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'messageId': 'announcement-missed-1',
          },
        ], '');

        await drainGroupOfflineInbox(
          bridge: reader.bridge,
          groupRepo: reader.groupRepo,
          msgRepo: reader.msgRepo,
        );

        expect(
          (await reader.loadGroupMessages(groupId)).where((m) => m.isIncoming),
          hasLength(2),
        );

        admin.dispose();
        reader.dispose();
      },
    );

    testWidgets(
      'group inbox drain deduplicates message already received live',
      (tester) async {
        final user = GroupTestUser.create(
          peerId: 'bob-peer',
          username: 'Bob',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final userBridge = user.bridge as _CursorInboxBridge;

        const groupId = 'group-dedupe-smoke';
        const messageId = 'group-dedupe-msg';
        final now = DateTime.now().toUtc();

        await user.groupRepo.saveGroup(
          GroupModel(
            id: groupId,
            name: 'Dedupe',
            type: GroupType.chat,
            topicName: 'topic-$groupId',
            createdAt: now,
            createdBy: 'alice-peer',
            myRole: GroupRole.member,
          ),
        );
        await user.groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'alice-peer',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: now,
          ),
        );
        await user.groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'bob-peer',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-bob',
            joinedAt: now,
          ),
        );
        await user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'dedupe-key',
            createdAt: now,
          ),
        );

        user.start();
        network.subscribe(groupId, user.peerId);

        await handleIncomingGroupMessage(
          groupRepo: user.groupRepo,
          msgRepo: user.msgRepo,
          groupId: groupId,
          senderId: 'alice-peer',
          senderUsername: 'Alice',
          keyEpoch: 0,
          text: 'Deduped message',
          timestamp: now.toIso8601String(),
          messageId: messageId,
        );

        userBridge.addPage(groupId, '', [
          {
            'groupId': groupId,
            'senderId': 'alice-peer',
            'senderUsername': 'Alice',
            'keyEpoch': 0,
            'text': 'Deduped message',
            'timestamp': now.toIso8601String(),
            'messageId': messageId,
          },
        ], '');

        await drainGroupOfflineInbox(
          bridge: user.bridge,
          groupRepo: user.groupRepo,
          msgRepo: user.msgRepo,
        );

        expect(
          (await user.loadGroupMessages(groupId)).where((m) => m.isIncoming),
          hasLength(1),
        );

        user.dispose();
      },
    );

    testWidgets(
      'watchdog restart rejoins topics and multi-group drain stays bounded',
      (tester) async {
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

        const rejoinGroupId = 'group-watchdog-smoke';
        await alice.createGroup(groupId: rejoinGroupId, name: 'Watchdog');
        await alice.addMember(groupId: rejoinGroupId, invitee: bob);
        await bob.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: rejoinGroupId,
            keyGeneration: 1,
            encryptedKey: 'watchdog-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        final extraGroupIds = List.generate(4, (i) => 'group-burst-$i');
        for (final groupId in extraGroupIds) {
          await bob.createGroup(groupId: groupId, name: groupId);
          await bob.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: 'key-$groupId',
              createdAt: DateTime.now().toUtc(),
            ),
          );
          bobBridge.addPage(groupId, '', [
            {
              'groupId': groupId,
              'senderId': 'other-peer',
              'senderUsername': 'Other',
              'keyEpoch': 0,
              'text': 'Missed $groupId',
              'timestamp': DateTime.now().toUtc().toIso8601String(),
              'messageId': 'missed-$groupId',
            },
          ], '');
        }
        bobBridge.addPage(rejoinGroupId, '', <Map<String, dynamic>>[], '');

        alice.start();
        bob.start();

        await alice.sendGroupMessage(
          groupId: rejoinGroupId,
          text: 'Before watchdog',
        );
        await _pumpNetwork();
        expect(
          (await bob.loadGroupMessages(
            rejoinGroupId,
          )).where((m) => m.isIncoming),
          hasLength(1),
        );

        network.unsubscribe(rejoinGroupId, bob.peerId);
        await rejoinGroupTopics(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          reason: RejoinReason.watchdogRestart,
        );

        final joinCalls = bob.bridge.sentMessages
            .map((m) => jsonDecode(m) as Map<String, dynamic>)
            .where((m) => m['cmd'] == 'group:join')
            .toList();
        expect(joinCalls.length, greaterThanOrEqualTo(1));

        network.subscribe(rejoinGroupId, bob.peerId);
        await alice.sendGroupMessage(
          groupId: rejoinGroupId,
          text: 'After watchdog',
        );
        await _pumpNetwork();
        expect(
          (await bob.loadGroupMessages(
            rejoinGroupId,
          )).where((m) => m.isIncoming),
          hasLength(2),
        );

        bobBridge.commandLog.clear();
        await drainGroupOfflineInbox(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
        );

        final retrieveCount = bobBridge.commandLog
            .where((cmd) => cmd == 'group:inboxRetrieveCursor')
            .length;
        expect(retrieveCount, extraGroupIds.length + 1);

        for (final groupId in extraGroupIds) {
          expect(await bob.msgRepo.getMessageCount(groupId), 1);
        }
        expect(
          (await bob.loadGroupMessages(
            rejoinGroupId,
          )).where((m) => m.isIncoming),
          hasLength(2),
        );

        alice.dispose();
        bob.dispose();
      },
    );
  });
}
