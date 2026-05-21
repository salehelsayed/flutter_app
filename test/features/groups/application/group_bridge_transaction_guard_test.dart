import 'dart:convert';

import 'package:flutter_app/core/database/db_write_transaction.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/create_group_with_members_use_case.dart';
import 'package:flutter_app/features/groups/application/remove_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

class _Clock {
  int _tick = 0;

  int now() => ++_tick;
}

class _WriteWindow {
  _WriteWindow({required this.op, required this.startedAt});

  final String op;
  final int startedAt;
  int? endedAt;

  bool contains(int tick) {
    final end = endedAt;
    return end == null ? tick >= startedAt : tick >= startedAt && tick <= end;
  }
}

class _InstrumentedBridge extends PassthroughCryptoBridge {
  _InstrumentedBridge(this._clock);

  final _Clock _clock;
  final List<({int at, String cmd})> sendEvents = [];

  @override
  Future<String> send(String message) {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    sendEvents.add((
      at: _clock.now(),
      cmd: parsed['cmd']?.toString() ?? '<unknown>',
    ));
    return super.send(message);
  }
}

class _InstrumentedGroupRepository extends InMemoryGroupRepository {
  _InstrumentedGroupRepository(this._clock);

  final _Clock _clock;
  final List<_WriteWindow> writeWindows = [];

  Future<T> _recordWrite<T>(String op, Future<T> Function() body) async {
    final window = _WriteWindow(op: op, startedAt: _clock.now());
    writeWindows.add(window);
    try {
      return await runInDbWriteTransactionZoneForTest(body);
    } finally {
      window.endedAt = _clock.now();
    }
  }

  @override
  Future<void> saveGroup(GroupModel group) {
    return _recordWrite('saveGroup', () => super.saveGroup(group));
  }

  @override
  Future<void> updateGroup(GroupModel group) {
    return _recordWrite('updateGroup', () => super.updateGroup(group));
  }

  @override
  Future<void> deleteGroup(String id) {
    return _recordWrite('deleteGroup', () => super.deleteGroup(id));
  }

  @override
  Future<void> saveMember(GroupMember member) {
    return _recordWrite('saveMember', () => super.saveMember(member));
  }

  @override
  Future<void> updateMemberRole(
    String groupId,
    String peerId,
    MemberRole role,
  ) {
    return _recordWrite(
      'updateMemberRole',
      () => super.updateMemberRole(groupId, peerId, role),
    );
  }

  @override
  Future<void> removeMember(String groupId, String peerId) {
    return _recordWrite(
      'removeMember',
      () => super.removeMember(groupId, peerId),
    );
  }

  @override
  Future<void> removeAllMembers(String groupId) {
    return _recordWrite(
      'removeAllMembers',
      () => super.removeAllMembers(groupId),
    );
  }

  @override
  Future<void> saveKey(GroupKeyInfo key) {
    return _recordWrite('saveKey', () => super.saveKey(key));
  }

  @override
  Future<void> removeAllKeys(String groupId) {
    return _recordWrite('removeAllKeys', () => super.removeAllKeys(groupId));
  }

  @override
  Future<void> savePendingKeyRotation(GroupKeyInfo key) {
    return _recordWrite(
      'savePendingKeyRotation',
      () => super.savePendingKeyRotation(key),
    );
  }

  @override
  Future<void> clearPendingKeyRotation(String groupId, int keyGeneration) {
    return _recordWrite(
      'clearPendingKeyRotation',
      () => super.clearPendingKeyRotation(groupId, keyGeneration),
    );
  }

  @override
  Future<void> clearPendingKeyRotations(String groupId) {
    return _recordWrite(
      'clearPendingKeyRotations',
      () => super.clearPendingKeyRotations(groupId),
    );
  }
}

class _InstrumentedGroupMessageRepository
    extends InMemoryGroupMessageRepository {
  _InstrumentedGroupMessageRepository(this._clock);

  final _Clock _clock;
  final List<_WriteWindow> writeWindows = [];

  Future<T> _recordWrite<T>(String op, Future<T> Function() body) async {
    final window = _WriteWindow(op: op, startedAt: _clock.now());
    writeWindows.add(window);
    try {
      return await runInDbWriteTransactionZoneForTest(body);
    } finally {
      window.endedAt = _clock.now();
    }
  }

  @override
  Future<void> saveMessage(GroupMessage message) {
    return _recordWrite('saveMessage', () => super.saveMessage(message));
  }

  @override
  Future<void> updateMessageStatus(String id, String status) {
    return _recordWrite(
      'updateMessageStatus',
      () => super.updateMessageStatus(id, status),
    );
  }

  @override
  Future<int> transitionSendingToFailed() {
    return _recordWrite(
      'transitionSendingToFailed',
      () => super.transitionSendingToFailed(),
    );
  }

  @override
  Future<int> deleteMessagesForGroup(String groupId) {
    return _recordWrite(
      'deleteMessagesForGroup',
      () => super.deleteMessagesForGroup(groupId),
    );
  }
}

void main() {
  group('UP-007 bridge transaction guard', () {
    test(
      'UP-007 create add remove re-add and send keep bridge calls outside write transactions',
      () async {
        const groupId = 'up007-group';
        final now = DateTime.utc(2026, 5, 14, 8);
        final clock = _Clock();
        final bridge = _InstrumentedBridge(clock);
        final groupRepo = _InstrumentedGroupRepository(clock);
        final msgRepo = _InstrumentedGroupMessageRepository(clock);
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true),
        );

        bridge.responses['group:create'] = {
          'ok': true,
          'groupId': groupId,
          'topicName': 'topic-$groupId',
          'groupKey': 'up007-group-key-1',
          'keyEpoch': 1,
        };

        final identity = IdentityModel(
          peerId: 'peer-admin',
          publicKey: 'pk-admin',
          privateKey: 'sk-admin',
          mnemonic12:
              'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
          mlKemPublicKey: 'mlkem-pk-admin',
          username: 'Admin',
          createdAt: now.toIso8601String(),
          updatedAt: now.toIso8601String(),
        );

        ContactModel contact({
          required String peerId,
          required String username,
        }) {
          return ContactModel(
            peerId: peerId,
            publicKey: 'pk-$peerId',
            rendezvous: '/dns4/relay/tcp/443/p2p/relay',
            username: username,
            signature: 'sig-$peerId',
            scannedAt: now.toIso8601String(),
            mlKemPublicKey: 'mlkem-pk-$peerId',
          );
        }

        GroupMember member({required String peerId, required String username}) {
          return GroupMember(
            groupId: groupId,
            peerId: peerId,
            username: username,
            role: MemberRole.writer,
            publicKey: 'pk-$peerId',
            mlKemPublicKey: 'mlkem-pk-$peerId',
            joinedAt: now,
          );
        }

        final bob = contact(peerId: 'peer-bob', username: 'Bob');
        final charlie = member(peerId: 'peer-charlie', username: 'Charlie');

        await createGroupWithMembers(
          bridge: bridge,
          groupRepo: groupRepo,
          p2pService: p2pService,
          identity: identity,
          selectedContacts: [bob],
          type: GroupType.chat,
          name: 'UP-007 Group',
        );

        await addGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: groupId,
          newMember: charlie,
          selfPeerId: identity.peerId,
        );

        await removeGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: groupId,
          memberPeerId: charlie.peerId,
          selfPeerId: identity.peerId,
          eventAt: now.add(const Duration(minutes: 1)),
        );

        await addGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: groupId,
          newMember: charlie.copyWith(
            joinedAt: now.add(const Duration(minutes: 2)),
          ),
          selfPeerId: identity.peerId,
        );

        final (sendResult, sentMessage) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: groupId,
          text: 'UP-007 bridge calls outside DB write transactions',
          senderPeerId: identity.peerId,
          senderPublicKey: identity.publicKey,
          senderPrivateKey: identity.privateKey,
          senderUsername: identity.username,
          messageId: 'up007-message-1',
          timestamp: now.add(const Duration(minutes: 3)),
        );

        expect(sendResult, SendGroupMessageResult.success);
        expect(sentMessage, isNotNull);
        expect(groupRepo.writeWindows, isNotEmpty);
        expect(msgRepo.writeWindows, isNotEmpty);
        expect(
          bridge.commandLog,
          containsAll([
            'group:create',
            'group:updateConfig',
            'group:publish',
            'group:inboxStore',
          ]),
        );

        final windows = [...groupRepo.writeWindows, ...msgRepo.writeWindows];
        final overlaps = <({String cmd, String op, int at})>[];
        for (final event in bridge.sendEvents) {
          for (final window in windows) {
            if (window.contains(event.at)) {
              overlaps.add((cmd: event.cmd, op: window.op, at: event.at));
            }
          }
        }

        expect(
          overlaps,
          isEmpty,
          reason:
              'UP-007 requires every native bridge call in create/add/remove/'
              're-add/send to happen outside DB write transaction windows.',
        );
      },
    );
  });
}
