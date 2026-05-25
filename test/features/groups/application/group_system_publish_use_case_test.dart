import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/group_system_publish_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_inbox_stores_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;

  final now = DateTime.utc(2026, 5, 23, 12, 0, 0);
  const groupId = 'group-1';
  const actorPeerId = 'peer-admin';

  setUp(() async {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();

    await groupRepo.saveGroup(
      GroupModel(
        id: groupId,
        name: 'Project Group',
        type: GroupType.chat,
        topicName: 'topic-group-1',
        createdAt: now,
        createdBy: actorPeerId,
        myRole: GroupRole.admin,
      ),
    );
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: 'test-group-key-1',
        createdAt: now,
      ),
    );
  });

  GroupMessage timelineMessage(String id) {
    return GroupMessage(
      id: id,
      groupId: groupId,
      senderPeerId: actorPeerId,
      senderUsername: 'Admin',
      text: 'Admin dissolved the group',
      timestamp: now,
      status: 'delivered',
      isIncoming: true,
      createdAt: now,
    );
  }

  String replayPlaintext(String messageId) {
    return jsonEncode({
      'groupId': groupId,
      'senderId': actorPeerId,
      'senderUsername': 'Admin',
      'text': jsonEncode({'__sys': 'group_dissolved'}),
      'timestamp': now.toIso8601String(),
      'messageId': messageId,
    });
  }

  test(
    'GSPR-001 helper records retryable timeline row when replay store fails',
    () async {
      bridge.responses['group:inboxStore'] = {
        'ok': false,
        'errorCode': 'INBOX_STORE_FAILED',
      };
      const messageId = 'sys-group_dissolved:group-1:peer-admin:1';

      final result = await publishGroupSystemMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        text: jsonEncode({'__sys': 'group_dissolved'}),
        senderPeerId: actorPeerId,
        senderPublicKey: 'pk-admin',
        senderPrivateKey: 'sk-admin',
        senderUsername: 'Admin',
        messageId: messageId,
        replayPlaintext: replayPlaintext(messageId),
        recipientPeerIds: const ['peer-bob'],
        msgRepo: msgRepo,
        timelineMessage: timelineMessage(messageId),
      );

      expect(result.publishResult['ok'], isTrue);
      expect(result.inboxStored, isFalse);
      expect(result.inboxRetryPayload, isNotNull);
      expect(bridge.commandLog, contains('group:publish'));
      expect(bridge.commandLog, contains('group:inboxStore'));

      final saved = await msgRepo.getMessage(messageId);
      expect(saved, isNotNull);
      expect(saved!.inboxStored, isFalse);
      expect(saved.inboxRetryPayload, isNotNull);
      expect(saved.isIncoming, isFalse);
      expect(saved.status, 'sent');

      final eligible = await msgRepo.getMessagesWithFailedInboxStore();
      expect(eligible.map((message) => message.id), contains(messageId));

      bridge.responses['group:inboxStore'] = {'ok': true};
      final retried = await retryFailedGroupInboxStores(
        bridge: bridge,
        msgRepo: msgRepo,
      );

      expect(retried, 1);
      final retriedRow = await msgRepo.getMessage(messageId);
      expect(retriedRow, isNotNull);
      expect(retriedRow!.inboxStored, isTrue);
      expect(retriedRow.inboxRetryPayload, isNull);
      expect(retriedRow.status, 'sent');
    },
  );

  test(
    'GSPR-001 helper clears retry state when replay store succeeds',
    () async {
      const messageId = 'sys-group_dissolved:group-1:peer-admin:2';

      final result = await publishGroupSystemMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        text: jsonEncode({'__sys': 'group_dissolved'}),
        senderPeerId: actorPeerId,
        senderPublicKey: 'pk-admin',
        senderPrivateKey: 'sk-admin',
        senderUsername: 'Admin',
        messageId: messageId,
        replayPlaintext: replayPlaintext(messageId),
        recipientPeerIds: const ['peer-bob'],
        msgRepo: msgRepo,
        timelineMessage: timelineMessage(messageId),
      );

      expect(result.publishResult['ok'], isTrue);
      expect(result.inboxStored, isTrue);
      expect(result.inboxRetryPayload, isNull);
      expect(result.timelineMessage?.inboxStored, isTrue);
      expect(result.timelineMessage?.inboxRetryPayload, isNull);

      final failedRows = await msgRepo.getMessagesWithFailedInboxStore();
      expect(failedRows, isEmpty);
      final saved = await msgRepo.getMessage(messageId);
      expect(saved?.inboxRetryPayload, isNull);
    },
  );
}
