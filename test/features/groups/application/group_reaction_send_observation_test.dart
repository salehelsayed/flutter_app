import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/groups/application/send_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_group_reaction_replay_outbox_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../conversation/domain/repositories/fake_reaction_repository.dart';

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groups;
  late InMemoryGroupMessageRepository messages;
  late FakeReactionRepository reactions;
  late FakeGroupReactionReplayOutboxRepository outbox;
  final events = <Map<String, dynamic>>[];
  final at = DateTime.utc(2026, 9, 28);

  Future<(SendGroupReactionResult, MessageReaction?)> send({
    String group = 'group',
    String sender = 'bob',
  }) => sendGroupReaction(
    bridge: bridge,
    groupRepo: groups,
    msgRepo: messages,
    reactionRepo: reactions,
    reactionReplayOutboxRepo: outbox,
    groupId: group,
    messageId: 'message',
    emoji: '🔥',
    senderPeerId: sender,
    senderPublicKey: 'bob-public',
    senderPrivateKey: 'bob-private',
  );

  Map<String, dynamic> observation() => Map<String, dynamic>.from(
    events.singleWhere(
          (e) => e['event'] == 'GROUP_REACTION_SEND_RESULT',
        )['details']
        as Map,
  );

  setUp(() async {
    bridge = FakeBridge();
    groups = InMemoryGroupRepository();
    messages = InMemoryGroupMessageRepository();
    reactions = FakeReactionRepository();
    outbox = FakeGroupReactionReplayOutboxRepository();
    events.clear();
    debugSetFlowEventSink(events.add);
    await groups.saveGroup(
      GroupModel(
        id: 'group',
        name: 'Group',
        type: GroupType.chat,
        topicName: 'topic',
        createdAt: at,
        createdBy: 'bob',
        myRole: GroupRole.admin,
      ),
    );
    await groups.saveMember(
      GroupMember(
        groupId: 'group',
        peerId: 'bob',
        username: 'Bob',
        role: MemberRole.admin,
        publicKey: 'bob-public',
        joinedAt: at,
      ),
    );
    await groups.saveKey(
      GroupKeyInfo(
        groupId: 'group',
        keyGeneration: 0,
        encryptedKey: 'fixture-secret',
        createdAt: at,
      ),
    );
    await messages.saveMessage(
      GroupMessage(
        id: 'message',
        groupId: 'group',
        senderPeerId: 'alice',
        senderUsername: 'Alice',
        text: 'private message',
        timestamp: at,
        keyGeneration: 0,
        status: 'delivered',
        isIncoming: true,
        createdAt: at,
      ),
    );
    bridge.responses['group:publishReaction'] = {'ok': true};
  });
  tearDown(() => debugSetFlowEventSink(null));

  test(
    'observes the accepted return and exact persisted reaction without secrets',
    () async {
      final result = await send();
      expect(result.$1, SendGroupReactionResult.success);
      final observed = observation();
      expect(observed['outcome'], 'success');
      expect(observed['reactionId'], result.$2!.id);
      expect(
        (await reactions.getReactionsForMessage('message')).single.id,
        result.$2!.id,
      );
      expect(await outbox.getEntry(result.$2!.id), isNotNull);
      for (final entry in {
        'groupSha256': 'group',
        'messageSha256': 'message',
        'senderIdentitySha256': 'bob',
      }.entries) {
        expect(
          observed[entry.key],
          sha256.convert(utf8.encode(entry.value)).toString(),
        );
      }
      expect(observed.toString(), isNot(contains('bob-public')));
      expect(observed.toString(), isNot(contains('bob-private')));
      expect(observed.toString(), isNot(contains('private message')));
      expect(observed.toString(), isNot(contains('fixture-secret')));
    },
  );

  test(
    'local optimistic storage cannot turn a failed live publish into success evidence',
    () async {
      bridge.responses['group:publishReaction'] = {
        'ok': false,
        'error': 'offline',
      };
      final result = await send();
      expect(result.$1, SendGroupReactionResult.queuedForRetry);
      expect(await reactions.getReactionsForMessage('message'), hasLength(1));
      expect(observation()['outcome'], 'queuedForRetry');
      expect(observation()['reactionId'], result.$2!.id);
    },
  );

  test(
    'admission rejection is observed with no reaction or publication',
    () async {
      final result = await send(group: 'absent');
      expect(result.$1, SendGroupReactionResult.groupNotFound);
      expect(observation()['outcome'], 'groupNotFound');
      expect(observation()['reactionId'], isNull);
      expect(bridge.commandLog, isNot(contains('group:publishReaction')));
      expect(await reactions.getReactionsForMessage('message'), isEmpty);
    },
  );

  test(
    'new result-observer failure preserves the real accepted outcome',
    () async {
      debugSetFlowEventSink((event) {
        if (event['event'] == 'GROUP_REACTION_SEND_RESULT') {
          throw StateError('observer failed');
        }
      });
      final result = await send();
      expect(result.$1, SendGroupReactionResult.success);
      expect(
        (await reactions.getReactionsForMessage('message')).single.id,
        result.$2!.id,
      );
    },
  );
}
