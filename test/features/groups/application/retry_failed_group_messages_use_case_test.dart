import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_messages_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

IdentityModel _makeIdentity({String peerId = 'peer-1'}) {
  return IdentityModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    privateKey: 'sk-$peerId',
    mnemonic12:
        'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
    username: 'Alice',
    createdAt: '2026-01-15T12:00:00.000Z',
    updatedAt: '2026-01-15T12:00:00.000Z',
  );
}

GroupModel _makeGroup({
  String id = 'group-1',
  GroupType type = GroupType.chat,
  GroupRole myRole = GroupRole.member,
}) {
  return GroupModel(
    id: id,
    name: 'Test Group',
    type: type,
    topicName: 'topic-1',
    createdAt: DateTime.utc(2026, 1, 15, 12),
    createdBy: 'peer-admin',
    myRole: myRole,
  );
}

GroupMessage _makeFailedGroupMessage({
  required String id,
  required String text,
  required String timestampIso,
  String? inboxRetryPayload,
}) {
  return GroupMessage(
    id: id,
    groupId: 'group-1',
    senderPeerId: 'peer-1',
    senderUsername: 'Alice',
    text: text,
    timestamp: DateTime.parse(timestampIso),
    keyGeneration: 0,
    status: 'failed',
    isIncoming: false,
    createdAt: DateTime.parse(timestampIso),
    wireEnvelope: jsonEncode({
      'groupId': 'group-1',
      'text': text,
      'senderPeerId': 'peer-1',
      'senderUsername': 'Alice',
      'messageId': id,
    }),
    inboxStored: false,
    inboxRetryPayload: inboxRetryPayload ??
        jsonEncode({
          'groupId': 'group-1',
          'message': jsonEncode({
            'groupId': 'group-1',
            'senderId': 'peer-1',
            'senderUsername': 'Alice',
            'keyEpoch': 0,
            'text': text,
            'timestamp': timestampIso,
            'messageId': id,
          }),
          'recipientPeerIds': ['peer-2'],
          'pushTitle': 'Test Group',
          'pushBody': 'Alice: $text',
        }),
  );
}

class _FailFirstPublishBridge extends FakeBridge {
  var _publishCalls = 0;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group:publish') {
      _publishCalls++;
      if (_publishCalls == 1) {
        throw Exception('Simulated publish failure');
      }
    }

    return super.send(message);
  }
}

void main() {
  group('retryFailedGroupMessages', () {
    late FakeIdentityRepository identityRepo;
    late InMemoryGroupMessageRepository msgRepo;
    late InMemoryGroupRepository groupRepo;
    late FakeBridge bridge;

    setUp(() {
      identityRepo = FakeIdentityRepository();
      msgRepo = InMemoryGroupMessageRepository();
      groupRepo = InMemoryGroupRepository();
      bridge = FakeBridge(
        initialResponses: {
          'group:publish': {
            'ok': true,
            'messageId': 'msg-1',
            'topicPeers': 1,
          },
        },
      );
    });

    test('returns 0 when identity is null', () async {
      final count = await retryFailedGroupMessages(
        groupMsgRepo: msgRepo,
        groupRepo: groupRepo,
        identityRepo: identityRepo,
        bridge: bridge,
      );

      expect(count, 0);
      expect(bridge.commandLog, isEmpty);
    });

    test('retries a text-only failed row in place using the original ids', () async {
      identityRepo.seed(_makeIdentity());
      await groupRepo.saveGroup(_makeGroup());
      await msgRepo.saveMessage(
        _makeFailedGroupMessage(
          id: 'msg-retry-1',
          text: 'Retry me',
          timestampIso: '2026-01-15T12:00:00.000Z',
        ),
      );

      final count = await retryFailedGroupMessages(
        groupMsgRepo: msgRepo,
        groupRepo: groupRepo,
        identityRepo: identityRepo,
        bridge: bridge,
      );

      expect(count, 1);
      final saved = await msgRepo.getMessage('msg-retry-1');
      expect(saved, isNotNull);
      expect(saved!.status, 'sent');
      expect(saved.timestamp, DateTime.parse('2026-01-15T12:00:00.000Z'));
      expect(bridge.commandLog.where((cmd) => cmd == 'group:publish').length, 1);
    });

    test(
      'retries a failed text row even when inboxRetryPayload was cleared after inbox success',
      () async {
        identityRepo.seed(_makeIdentity());
        await groupRepo.saveGroup(_makeGroup());
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'msg-inbox-ok',
            groupId: 'group-1',
            senderPeerId: 'peer-1',
            senderUsername: 'Alice',
            text: 'Retry me from wireEnvelope',
            timestamp: DateTime.parse('2026-01-15T12:00:00.000Z'),
            keyGeneration: 0,
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.parse('2026-01-15T12:00:00.000Z'),
            wireEnvelope: jsonEncode({
              'groupId': 'group-1',
              'text': 'Retry me from wireEnvelope',
              'senderPeerId': 'peer-1',
              'senderUsername': 'Alice',
              'messageId': 'msg-inbox-ok',
            }),
            inboxStored: true,
            inboxRetryPayload: null,
          ),
        );

        final count = await retryFailedGroupMessages(
          groupMsgRepo: msgRepo,
          groupRepo: groupRepo,
          identityRepo: identityRepo,
          bridge: bridge,
        );

        expect(count, 1);
        final saved = await msgRepo.getMessage('msg-inbox-ok');
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
        expect(saved.wireEnvelope, isNull);
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish').length,
          1,
        );
      },
    );

    test('skips rows that still carry media retry metadata', () async {
      identityRepo.seed(_makeIdentity());
      await groupRepo.saveGroup(_makeGroup());
      await msgRepo.saveMessage(
        _makeFailedGroupMessage(
          id: 'msg-media',
          text: 'Retry later',
          timestampIso: '2026-01-15T12:00:00.000Z',
          inboxRetryPayload: jsonEncode({
            'groupId': 'group-1',
            'message': jsonEncode({
              'groupId': 'group-1',
              'senderId': 'peer-1',
              'senderUsername': 'Alice',
              'keyEpoch': 0,
              'text': 'Retry later',
              'timestamp': '2026-01-15T12:00:00.000Z',
              'messageId': 'msg-media',
              'media': [
                {'id': 'media-1'},
              ],
            }),
          }),
        ),
      );

      final count = await retryFailedGroupMessages(
        groupMsgRepo: msgRepo,
        groupRepo: groupRepo,
        identityRepo: identityRepo,
        bridge: bridge,
      );

      expect(count, 0);
      expect(bridge.commandLog.where((cmd) => cmd == 'group:publish'), isEmpty);
    });

    test('continues after a per-message publish error', () async {
      identityRepo.seed(_makeIdentity());
      await groupRepo.saveGroup(_makeGroup());
      await msgRepo.saveMessage(
        _makeFailedGroupMessage(
          id: 'msg-fail-1',
          text: 'First retry',
          timestampIso: '2026-01-15T12:00:00.000Z',
        ),
      );
      await msgRepo.saveMessage(
        _makeFailedGroupMessage(
          id: 'msg-fail-2',
          text: 'Second retry',
          timestampIso: '2026-01-15T12:01:00.000Z',
        ),
      );

      final failingBridge = _FailFirstPublishBridge();

      final count = await retryFailedGroupMessages(
        groupMsgRepo: msgRepo,
        groupRepo: groupRepo,
        identityRepo: identityRepo,
        bridge: failingBridge,
      );

      expect(count, 1);
      expect((await msgRepo.getMessage('msg-fail-1'))!.status, 'failed');
      expect((await msgRepo.getMessage('msg-fail-2'))!.status, 'sent');
    });
  });
}
