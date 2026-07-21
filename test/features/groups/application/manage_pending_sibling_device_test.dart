import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/admit_sibling_device_use_case.dart';
import 'package:flutter_app/features/groups/application/manage_pending_sibling_device.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_sibling_device.dart';

import '../../../shared/fakes/in_memory_group_repository.dart';

/// R2: hold-pending / verify-admit / reject use cases. The trust wrapper above
/// the raw admit primitive — an account-signed announce is NOT auto-admitted.
void main() {
  const groupId = 'g1';
  const bob = 'bob';
  const bobAccountKey = 'pk-bob';
  late InMemoryGroupRepository repo;

  setUp(() async {
    repo = InMemoryGroupRepository();
    await repo.saveGroup(
      GroupModel(
        id: groupId,
        name: 'g',
        type: GroupType.chat,
        topicName: 't',
        createdAt: DateTime.utc(2026, 1, 1),
        createdBy: 'alice',
        myRole: GroupRole.admin,
      ),
    );
    await repo.saveMemberBypassingValidationForTest(
      GroupMember(
        groupId: groupId,
        peerId: bob,
        role: MemberRole.writer,
        publicKey: bobAccountKey,
        mlKemPublicKey: 'mlkem-bob',
        joinedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await repo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 2,
        encryptedKey: 'k2',
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    );
  });

  Future<void> hold({required bool enabled, String account = bobAccountKey}) =>
      holdPendingSiblingDevice(
        pendingRepo: repo,
        groupRepo: repo,
        groupId: groupId,
        memberPeerId: bob,
        announcedDeviceId: 'bob-tablet',
        announcedTransportPeerId: 'bob-tablet',
        announcedDeviceSigningPublicKey: 'sign-tablet',
        verifiedAccountSigningPublicKey: account,
        announcedMlKemPublicKey: 'mlkem-tablet',
        multiDeviceSyncEnabled: enabled,
        nowUtc: () => DateTime.utc(2026, 6, 17),
      );

  test('hold is a no-op when the flag is off', () async {
    await hold(enabled: false);
    expect(await repo.getPendingSiblingDevicesForGroup(groupId), isEmpty);
  });

  test('hold persists a NEW device as pending (not admitted)', () async {
    await hold(enabled: true);

    final pending = await repo.getPendingSiblingDevicesForGroup(groupId);
    expect(pending, hasLength(1));
    expect(pending.single.deviceId, 'bob-tablet');
    expect(pending.single.verifiedAccountSigningPublicKey, bobAccountKey);
    // NOT admitted: bob's roster has no tablet device yet.
    final member = await repo.getMember(groupId, bob);
    expect(member!.devices.any((d) => d.deviceId == 'bob-tablet'), isFalse);
  });

  test('hold is a no-op when the device is already on the roster', () async {
    await repo.saveMemberBypassingValidationForTest(
      GroupMember(
        groupId: groupId,
        peerId: bob,
        role: MemberRole.writer,
        publicKey: bobAccountKey,
        mlKemPublicKey: 'mlkem-bob',
        devices: const [
          GroupMemberDeviceIdentity(
            deviceId: 'bob-tablet',
            transportPeerId: 'bob-tablet',
            deviceSigningPublicKey: 'sign-tablet',
            mlKemPublicKey: 'mlkem-tablet',
          ),
        ],
        joinedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await hold(enabled: true);
    expect(await repo.getPendingSiblingDevicesForGroup(groupId), isEmpty);
  });

  PendingSiblingDevice pendingDevice() => PendingSiblingDevice(
    groupId: groupId,
    memberPeerId: bob,
    deviceId: 'bob-tablet',
    transportPeerId: 'bob-tablet',
    deviceSigningPublicKey: 'sign-tablet',
    mlKemPublicKey: 'mlkem-tablet',
    verifiedAccountSigningPublicKey: bobAccountKey,
    announcedAt: DateTime.utc(2026, 6, 17),
  );

  test('verify admits the device and clears the pending entry', () async {
    await repo.savePendingSiblingDevice(pendingDevice());

    final outcome = await verifyAndAdmitPendingSiblingDevice(
      pendingRepo: repo,
      groupRepo: repo,
      pending: pendingDevice(),
      multiDeviceSyncEnabled: true,
    );

    expect(outcome, SiblingDeviceAdmissionOutcome.admitted);
    final member = await repo.getMember(groupId, bob);
    expect(member!.devices.any((d) => d.deviceId == 'bob-tablet'), isTrue);
    expect(await repo.getPendingSiblingDevicesForGroup(groupId), isEmpty);
  });

  test(
    'marked shells skip pending sibling hold verify and reject leaves',
    () async {
      await repo.savePendingSiblingDevice(pendingDevice());
      await repo.updateGroup(
        (await repo.getGroup(
          groupId,
        ))!.copyWith(selfRemovedAt: DateTime.utc(2026, 7, 20)),
      );
      var drainCalls = 0;

      expect(
        await verifyAndAdmitPendingSiblingDevice(
          pendingRepo: repo,
          groupRepo: repo,
          pending: pendingDevice(),
          multiDeviceSyncEnabled: true,
          triggerDrain: ({required groupId, required peerId}) async {
            drainCalls++;
          },
        ),
        SiblingDeviceAdmissionOutcome.memberNotFound,
      );
      await rejectPendingSiblingDevice(
        pendingRepo: repo,
        groupRepo: repo,
        pending: pendingDevice(),
      );
      await hold(enabled: true);

      expect(drainCalls, 0);
      expect((await repo.getMember(groupId, bob))!.devices, isEmpty);
      expect(
        await repo.getPendingSiblingDevicesForGroup(groupId),
        hasLength(1),
      );
    },
  );

  test('reject drops the pending entry and never admits', () async {
    await repo.savePendingSiblingDevice(pendingDevice());

    await rejectPendingSiblingDevice(
      pendingRepo: repo,
      groupRepo: repo,
      pending: pendingDevice(),
    );

    expect(await repo.getPendingSiblingDevicesForGroup(groupId), isEmpty);
    final member = await repo.getMember(groupId, bob);
    expect(member!.devices, isEmpty);
  });
}
