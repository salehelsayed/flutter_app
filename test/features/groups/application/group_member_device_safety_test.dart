import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/group_member_device_safety.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../shared/fakes/in_memory_group_repository.dart';

/// B4 (R3): the TOFU read-path resolver.
void main() {
  late InMemoryGroupRepository repo;

  GroupMember member({List<GroupMemberDeviceIdentity> devices = const []}) =>
      GroupMember(
        groupId: 'g1',
        peerId: 'bob',
        role: MemberRole.writer,
        publicKey: 'pk-bob',
        mlKemPublicKey: 'mlkem-bob',
        devices: devices,
        joinedAt: DateTime.utc(2026, 1, 1),
      );

  ContactModel contact() => ContactModel(
    peerId: 'bob',
    username: 'Bob',
    publicKey: 'pk-bob',
    rendezvous: 'rv',
    signature: 'sig',
    scannedAt: '2026-01-01T00:00:00Z',
    mlKemPublicKey: 'mlkem-bob',
  );

  GroupMemberDeviceIdentity device(String id) => GroupMemberDeviceIdentity(
    deviceId: id,
    transportPeerId: id,
    deviceSigningPublicKey: 'sign-$id',
    mlKemPublicKey: 'mlkem-$id',
  );

  setUp(() async {
    repo = InMemoryGroupRepository();
    await repo.saveGroup(
      GroupModel(
        id: 'g1',
        name: 'g',
        type: GroupType.chat,
        topicName: 't',
        createdAt: DateTime.utc(2026, 1, 1),
        createdBy: 'alice',
        myRole: GroupRole.admin,
      ),
    );
  });

  test('TOFU: first observe baselines the current devices (no change)', () async {
    final m = member(devices: [device('bob-phone')]);

    final safety = await resolveGroupMemberDeviceSafety(
      member: m,
      savedContact: contact(),
      snapshotRepo: repo,
      multiDeviceSyncEnabled: true,
      nowUtc: () => DateTime.utc(2026, 6, 16),
    );

    expect(safety!.identityChanged, isFalse, reason: 'first observe = trusted');
    // The baseline was persisted.
    final saved = await repo.loadGroupMemberDeviceSnapshot('g1', 'bob');
    expect(saved, isNotNull);
    expect(saved!.single.deviceId, 'bob-phone');
  });

  test('a device added AFTER the baseline flags identityChanged', () async {
    // Baseline observe with one device.
    await resolveGroupMemberDeviceSafety(
      member: member(devices: [device('bob-phone')]),
      savedContact: contact(),
      snapshotRepo: repo,
      multiDeviceSyncEnabled: true,
    );

    // Later: a second device appears.
    final safety = await resolveGroupMemberDeviceSafety(
      member: member(devices: [device('bob-phone'), device('bob-tablet')]),
      savedContact: contact(),
      snapshotRepo: repo,
      multiDeviceSyncEnabled: true,
    );

    expect(safety!.identityChanged, isTrue);
  });

  test('null snapshotRepo → account-level (v1) behaviour, no snapshot', () async {
    final safety = await resolveGroupMemberDeviceSafety(
      member: member(devices: [device('bob-phone')]),
      savedContact: contact(),
      snapshotRepo: null,
    );
    expect(safety!.identityChanged, isFalse);
    expect(await repo.loadGroupMemberDeviceSnapshot('g1', 'bob'), isNull);
  });
}
