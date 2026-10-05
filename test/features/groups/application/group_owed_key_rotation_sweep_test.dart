import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_owed_key_rotation_sweeper.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  const groupId = 'owed-rekey-group';
  const selfId = 'peer-creator';
  final now = DateTime.utc(2026, 10, 4, 12);
  final keyAt = now.subtract(const Duration(hours: 1));
  late InMemoryGroupRepository repo;
  late InMemoryGroupMessageRepository messages;
  late List<String> rotations;
  late bool rotateSucceeds;
  late bool sideEffectsAllowed;
  late List<Map<String, dynamic>> flows;
  late GroupOwedKeyRotationSweeper sweeper;

  Future<void> saveGroup({
    String createdBy = selfId,
    MemberRole bobRole = MemberRole.writer,
  }) async {
    await repo.saveGroup(
      GroupModel(
        id: groupId,
        name: 'Owed rekey',
        type: GroupType.chat,
        topicName: 'owed-topic',
        createdAt: keyAt.subtract(const Duration(hours: 1)),
        createdBy: createdBy,
        myRole: createdBy == selfId ? GroupRole.admin : GroupRole.member,
      ),
    );
    for (final peer in [selfId, 'peer-bob']) {
      await repo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: peer,
          username: peer,
          publicKey: 'pk-$peer',
          role: peer == selfId ? MemberRole.admin : bobRole,
          joinedAt: keyAt.subtract(const Duration(hours: 1)),
        ),
      );
    }
    await repo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 2,
        encryptedKey: 'key-2',
        createdAt: keyAt,
      ),
    );
  }

  Future<void> removalAt(DateTime at) => messages.saveMessage(
    GroupMessage(
      id: 'sys-member_removed:$groupId:peer-charlie:${at.microsecondsSinceEpoch}',
      groupId: groupId,
      senderPeerId: selfId,
      text: 'You removed Charlie',
      timestamp: at,
      createdAt: at,
    ),
  );

  setUp(() {
    repo = InMemoryGroupRepository();
    messages = InMemoryGroupMessageRepository();
    rotations = [];
    rotateSucceeds = true;
    sideEffectsAllowed = true;
    flows = [];
    debugSetFlowEventSink(flows.add);
    sweeper = GroupOwedKeyRotationSweeper(
      groupRepo: repo,
      msgRepo: messages,
      resolveSelfPeerId: () async => selfId,
      rotate: (id) async {
        rotations.add(id);
        return rotateSucceeds;
      },
      allowsSideEffects: ({required operation, data}) async =>
          sideEffectsAllowed,
      now: () => now,
    );
    addTearDown(() {
      sweeper.stop();
      debugSetFlowEventSink(null);
    });
  });

  bool emitted(String event) => flows.any((f) => f['event'] == event);

  test('rotates a group whose removal is newer than its key', () async {
    await saveGroup();
    await removalAt(keyAt.add(const Duration(minutes: 3)));
    await sweeper.sweep();
    expect(rotations, [groupId]);
    expect(emitted('GROUP_CREATOR_OWED_REKEY_ROTATED'), isTrue);
  });

  test('leaves a group whose key already followed the removal', () async {
    await saveGroup();
    await removalAt(keyAt.subtract(const Duration(seconds: 5)));
    await sweeper.sweep();
    expect(rotations, isEmpty);
  });

  test('never rotates when another member is the rotation leader', () async {
    // Bob created the group and may still rotate, so Bob leads.
    await saveGroup(createdBy: 'peer-bob', bobRole: MemberRole.admin);
    await removalAt(keyAt.add(const Duration(minutes: 3)));
    await sweeper.sweep();
    expect(rotations, isEmpty);
  });

  test('rotates a group whose creator was demoted (rotation leader)', () async {
    // Bob created the group but is a writer now; this admin leads.
    await saveGroup(createdBy: 'peer-bob');
    await removalAt(keyAt.add(const Duration(minutes: 3)));
    await sweeper.sweep();
    expect(rotations, [groupId]);
  });

  test('waits for a removal to settle before judging it', () async {
    // The removal flow rotates on its own; a removal 30 seconds old may
    // still be rotating.
    await saveGroup();
    await removalAt(now.subtract(const Duration(seconds: 30)));
    await sweeper.sweep();
    expect(rotations, isEmpty);
  });

  test('does not judge a removal stamped after this device clock', () async {
    await saveGroup();
    await removalAt(now.add(const Duration(minutes: 5)));
    await sweeper.sweep();
    expect(rotations, isEmpty);
  });

  test('respects the account side-effect gate', () async {
    await saveGroup();
    await removalAt(keyAt.add(const Duration(minutes: 3)));
    sideEffectsAllowed = false;
    await sweeper.sweep();
    expect(rotations, isEmpty);
  });

  test('retries a rotation refused inside the grace window', () async {
    await saveGroup();
    await removalAt(keyAt.add(const Duration(minutes: 3)));
    rotateSucceeds = false;
    await sweeper.sweep();
    expect(emitted('GROUP_CREATOR_OWED_REKEY_DEFERRED'), isTrue);
    rotateSucceeds = true;
    await sweeper.sweep();
    expect(rotations, [groupId, groupId]);
  });

  test('does nothing once stopped', () async {
    await saveGroup();
    await removalAt(keyAt.add(const Duration(minutes: 3)));
    sweeper.stop();
    await sweeper.sweep();
    expect(rotations, isEmpty);
  });
}
