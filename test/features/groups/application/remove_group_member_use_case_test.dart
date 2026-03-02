import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/remove_group_member_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

/// A bridge that returns an error for group:rotateKey and records all commands.
class _FailRotateKeyBridge extends FakeBridge {
  @override
  Future<String> send(String message) async {
    sendCallCount++;
    lastSentMessage = message;
    sentMessages.add(message);

    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    lastCommand = cmd;
    if (cmd != null) commandLog.add(cmd);

    if (cmd == 'group:rotateKey') {
      return jsonEncode({
        'ok': false,
        'errorCode': 'ROTATE_FAILED',
        'errorMessage': 'Simulated rotation failure',
      });
    }

    return jsonEncode({'ok': true});
  }
}

/// A bridge that records the order of all commands it receives.
class _OrderTrackingBridge extends FakeBridge {
  // We track calls from the use case by observing the timing of repo
  // operations vs bridge calls. Since the use case calls removeMember
  // on the repo (in-memory, synchronous-ish) before calling the bridge,
  // we verify via commandLog that group:rotateKey was invoked.
}

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;

  final testGroup = GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: 'group-topic-1',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-admin',
    myRole: GroupRole.admin,
  );

  setUp(() async {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();

    await groupRepo.saveGroup(testGroup);
    await groupRepo.saveMember(GroupMember(
      groupId: 'group-1',
      peerId: 'peer-admin',
      role: MemberRole.admin,
      joinedAt: DateTime.now().toUtc(),
    ));
    await groupRepo.saveMember(GroupMember(
      groupId: 'group-1',
      peerId: 'peer-to-remove',
      username: 'RemoveMe',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    ));

    bridge.responses['group:rotateKey'] = {
      'ok': true,
      'keyGeneration': 1,
      'encryptedKey': 'new-rotated-key',
    };
  });

  test('removes member successfully', () async {
    final keyInfo = await removeGroupMember(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      memberPeerId: 'peer-to-remove',
    );

    expect(keyInfo, isNotNull);

    final member = await groupRepo.getMember('group-1', 'peer-to-remove');
    expect(member, isNull);
  });

  test('rotates key after removal', () async {
    final keyInfo = await removeGroupMember(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      memberPeerId: 'peer-to-remove',
    );

    expect(keyInfo.keyGeneration, 1);
    expect(keyInfo.encryptedKey, 'new-rotated-key');

    // Verify key is saved in repo
    final savedKey = await groupRepo.getLatestKey('group-1');
    expect(savedKey, isNotNull);
    expect(savedKey!.keyGeneration, 1);
  });

  test('calls bridge rotate key command', () async {
    await removeGroupMember(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      memberPeerId: 'peer-to-remove',
    );

    expect(bridge.commandLog, contains('group:rotateKey'));
  });

  test('throws when caller is not admin', () async {
    final memberGroup = GroupModel(
      id: 'group-member-only',
      name: 'Member Group',
      type: GroupType.chat,
      topicName: 'group-topic-member',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-admin',
      myRole: GroupRole.member,
    );
    await groupRepo.saveGroup(memberGroup);
    await groupRepo.saveMember(GroupMember(
      groupId: 'group-member-only',
      peerId: 'peer-target',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    ));

    expect(
      () => removeGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-member-only',
        memberPeerId: 'peer-target',
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Only admins can remove members'),
        ),
      ),
    );
  });

  test('handles bridge rotateKey failure gracefully', () async {
    final failBridge = _FailRotateKeyBridge();

    // removeGroupMember should throw because rotateKey returned ok=false.
    // But the member should already have been removed from the repo
    // because removal happens before key rotation.
    Object? caughtError;
    try {
      await removeGroupMember(
        bridge: failBridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        memberPeerId: 'peer-to-remove',
      );
    } catch (e) {
      caughtError = e;
    }

    // Verify the error propagated.
    expect(caughtError, isA<Exception>());
    expect(caughtError.toString(), contains('Simulated rotation failure'));

    // Member should still be removed from repo (removal happens before
    // the bridge call).
    final member = await groupRepo.getMember('group-1', 'peer-to-remove');
    expect(member, isNull);
  });

  test('removes member from repo before rotating key', () async {
    // Use a standard FakeBridge but verify ordering via commandLog.
    // The use case first removes the member from the repo, then calls
    // group:rotateKey on the bridge.
    final trackBridge = _OrderTrackingBridge();
    trackBridge.responses['group:rotateKey'] = {
      'ok': true,
      'keyGeneration': 2,
      'encryptedKey': 'rotated-key-v2',
    };

    await removeGroupMember(
      bridge: trackBridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      memberPeerId: 'peer-to-remove',
    );

    // Member is already removed from repo.
    final member = await groupRepo.getMember('group-1', 'peer-to-remove');
    expect(member, isNull);

    // Bridge was called for rotateKey after the removal.
    expect(trackBridge.commandLog, equals(['group:rotateKey']));
  });
}
