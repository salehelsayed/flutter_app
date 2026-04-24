import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/features/groups/application/dissolve_group_use_case.dart'
    as group_dissolve;
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_wired.dart';

import '../test/core/bridge/fake_bridge.dart';
import '../test/core/services/fake_p2p_service.dart';
import '../test/features/identity/domain/repositories/fake_identity_repository.dart';
import '../test/shared/fakes/fake_group_pubsub_network.dart';
import '../test/shared/fakes/group_test_user.dart';
import '../test/shared/fakes/in_memory_contact_repository.dart';

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

Future<void> _pumpFrames(WidgetTester tester, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Map<String, dynamic> _decodeReplayPayload(Map<String, dynamic> inboxPayload) {
  final envelope =
      jsonDecode(inboxPayload['message'] as String) as Map<String, dynamic>;
  final ciphertext = envelope['ciphertext'];
  if (envelope['kind'] == 'group_offline_replay' && ciphertext is String) {
    return jsonDecode(ciphertext) as Map<String, dynamic>;
  }
  return envelope;
}

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
      'offline recovered dissolved group exposes local-only cleanup on Group Info',
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

        const groupId = 'group-dissolved-cleanup-smoke';
        final now = DateTime.now().toUtc();

        await alice.createGroup(
          groupId: groupId,
          name: 'Cleanup Smoke',
          createdAt: now,
        );
        await alice.addMember(groupId: groupId, invitee: bob, joinedAt: now);
        await alice.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'cleanup-key',
            createdAt: now,
          ),
        );
        await bob.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'cleanup-key',
            createdAt: now,
          ),
        );

        alice.start();

        final (result, dissolvedGroup) = await alice.dissolveGroupViaBridge(
          groupId: groupId,
        );
        expect(result, group_dissolve.DissolveGroupResult.success);
        expect(dissolvedGroup, isNotNull);
        expect(dissolvedGroup!.isDissolved, isTrue);

        final inboxRaw = alice.bridge.sentMessages.lastWhere(
          (message) =>
              (jsonDecode(message) as Map<String, dynamic>)['cmd'] ==
              'group:inboxStore',
        );
        final inboxPayload =
            (jsonDecode(inboxRaw) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final replayPayload = _decodeReplayPayload(inboxPayload);
        bobBridge.addPage(groupId, '', [replayPayload], '');

        await drainGroupOfflineInbox(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
          groupMessageListener: bob.groupMessageListener,
        );

        final recoveredGroup = await bob.groupRepo.getGroup(groupId);
        expect(recoveredGroup, isNotNull);
        final resolvedGroup = recoveredGroup!;
        expect(resolvedGroup.isDissolved, isTrue);
        expect(await bob.msgRepo.getMessageCount(groupId), 1);

        final identityRepo = FakeIdentityRepository()
          ..seed(
            FakeIdentityRepository.makeIdentity(
              peerId: bob.peerId,
              publicKey: bob.publicKey,
              privateKey: bob.privateKey,
            ),
          );

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GroupInfoWired(
                          group: resolvedGroup,
                          groupRepo: bob.groupRepo,
                          msgRepo: bob.msgRepo,
                          contactRepo: InMemoryContactRepository(),
                          bridge: bob.bridge,
                          identityRepo: identityRepo,
                          p2pService: FakeP2PService(),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Info'),
                ),
              ),
            ),
          ),
        );
        await _pumpFrames(tester, count: 5);

        await tester.tap(find.text('Open Info'));
        await _pumpFrames(tester, count: 20);

        expect(find.text('Group dissolved'), findsOneWidget);
        expect(
          find.text(
            'This conversation is now read-only. Previous messages stay available for reference.',
          ),
          findsOneWidget,
        );
        expect(find.text('Delete from this device'), findsOneWidget);

        bobBridge.commandLog.clear();

        final deleteButton = find.byKey(
          const ValueKey('group-delete-local-button'),
        );
        await tester.scrollUntilVisible(
          deleteButton,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await _pumpFrames(tester, count: 5);
        await tester.tap(deleteButton);
        await _pumpFrames(tester, count: 5);

        expect(
          find.byKey(const ValueKey('group-delete-local-confirm')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('group-delete-local-confirm')),
        );
        await _pumpFrames(tester, count: 20);

        expect(await bob.groupRepo.getGroup(groupId), isNull);
        expect(await bob.groupRepo.getMembers(groupId), isEmpty);
        expect(await bob.groupRepo.getLatestKey(groupId), isNull);
        expect(await bob.msgRepo.getMessageCount(groupId), 0);
        expect(bobBridge.commandLog, isNot(contains('group:leave')));
        expect(find.byType(GroupInfoWired), findsNothing);
        expect(find.text('Open Info'), findsOneWidget);

        alice.dispose();
        bob.dispose();
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
