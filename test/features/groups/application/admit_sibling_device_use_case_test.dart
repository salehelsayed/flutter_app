import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/admit_sibling_device_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../shared/fakes/in_memory_group_repository.dart';

/// B2 sibling-device admission (Part B / B1b keystone). The flag value is
/// injected as `multiDeviceSyncEnabled: true` to exercise the real logic, since
/// the compile-time `kMultiDeviceSyncEnabled` const is off in CI.
void main() {
  const groupId = 'group-1';
  const memberPeerId = '12D3KooWmemberAccount';
  const accountKey = 'account-signing-key-AAA';

  late InMemoryGroupRepository repo;
  late List<({String groupId, String peerId})> drainCalls;
  late List<({String groupId, String peerId, int keyEpoch})> reopenCalls;

  Future<void> drainSpy({
    required String groupId,
    required String peerId,
  }) async {
    drainCalls.add((groupId: groupId, peerId: peerId));
  }

  Future<void> reopenSpy({
    required String groupId,
    required String peerId,
    required int keyEpoch,
  }) async {
    reopenCalls.add((groupId: groupId, peerId: peerId, keyEpoch: keyEpoch));
  }

  GroupMember member({
    String? publicKey = accountKey,
    List<GroupMemberDeviceIdentity> devices =
        const <GroupMemberDeviceIdentity>[],
  }) => GroupMember(
    groupId: groupId,
    peerId: memberPeerId,
    role: MemberRole.writer,
    publicKey: publicKey,
    mlKemPublicKey: 'member-mlkem',
    devices: devices,
    joinedAt: DateTime.utc(2024, 1, 1),
  );

  setUp(() async {
    repo = InMemoryGroupRepository();
    drainCalls = [];
    reopenCalls = [];
    await repo.saveGroup(
      GroupModel(
        id: groupId,
        name: 'G',
        type: GroupType.chat,
        topicName: 'topic-$groupId',
        createdAt: DateTime.utc(2024, 1, 1),
        createdBy: memberPeerId,
        myRole: GroupRole.admin,
      ),
    );
    // A current epoch exists locally, so admission must enqueue + drain a
    // re-distribution of it to the newly-admitted device.
    await repo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 3,
        encryptedKey: 'epoch-3-key',
        createdAt: DateTime.utc(2024, 1, 1),
      ),
    );
  });

  Future<SiblingDeviceAdmissionOutcome> admit({
    bool enabled = true,
    String deviceId = 'sibling-device-1',
    String transportPeerId = '12D3KooWsiblingTransport',
    String signingKey = 'sibling-signing-key',
    String verifiedAccountKey = accountKey,
  }) {
    return admitSiblingDeviceIfTrusted(
      groupRepo: repo,
      groupId: groupId,
      memberPeerId: memberPeerId,
      announcedDeviceId: deviceId,
      announcedTransportPeerId: transportPeerId,
      announcedDeviceSigningPublicKey: signingKey,
      announcedMlKemPublicKey: 'sibling-mlkem',
      verifiedAccountSigningPublicKey: verifiedAccountKey,
      multiDeviceSyncEnabled: enabled,
      reopenDeferredDistribution: reopenSpy,
      triggerDrain: drainSpy,
    );
  }

  test('disabled flag is a no-op (default-off production behaviour)', () async {
    await repo.saveMemberBypassingValidationForTest(member());

    final outcome = await admit(enabled: false);

    expect(outcome, SiblingDeviceAdmissionOutcome.disabled);
    final saved = await repo.getMember(groupId, memberPeerId);
    expect(saved!.devices, isEmpty);
    expect(drainCalls, isEmpty);
    expect(reopenCalls, isEmpty);
  });

  test('rejects an announce whose account key does not match the member', () async {
    await repo.saveMemberBypassingValidationForTest(member());

    final outcome = await admit(verifiedAccountKey: 'attacker-key');

    expect(outcome, SiblingDeviceAdmissionOutcome.rejectedUntrusted);
    final saved = await repo.getMember(groupId, memberPeerId);
    expect(saved!.devices, isEmpty);
    expect(drainCalls, isEmpty);
    expect(reopenCalls, isEmpty, reason: 'no key delivery to an untrusted device');
  });

  test('memberNotFound when the peer is not a member', () async {
    final outcome = await admit();
    expect(outcome, SiblingDeviceAdmissionOutcome.memberNotFound);
    expect(drainCalls, isEmpty);
  });

  test('invalidDevice when the announce is missing required fields', () async {
    await repo.saveMemberBypassingValidationForTest(member());

    final outcome = await admit(deviceId: '   ');

    expect(outcome, SiblingDeviceAdmissionOutcome.invalidDevice);
    expect(drainCalls, isEmpty);
  });

  test(
    'admits a trusted, distinct sibling device and triggers re-distribution',
    () async {
      await repo.saveMemberBypassingValidationForTest(member());

      final outcome = await admit();

      expect(outcome, SiblingDeviceAdmissionOutcome.admitted);
      final saved = await repo.getMember(groupId, memberPeerId);
      expect(saved!.devices, hasLength(1));
      final device = saved.devices.single;
      expect(device.deviceId, 'sibling-device-1');
      expect(device.transportPeerId, '12D3KooWsiblingTransport');
      expect(device.deviceSigningPublicKey, 'sibling-signing-key');
      expect(device.mlKemPublicKey, 'sibling-mlkem');
      expect(device.isActive, isTrue);
      // Reuses the existing per-device distribution machinery: REOPEN the
      // (group,peer) row to the CURRENT epoch (3), then drain so the runner
      // re-distributes it to the newly-deliverable device.
      expect(reopenCalls, [
        (groupId: groupId, peerId: memberPeerId, keyEpoch: 3),
      ]);
      expect(drainCalls, [(groupId: groupId, peerId: memberPeerId)]);
    },
  );

  test(
    're-announce of the same distinct device re-arms delivery (no duplicate row)',
    () async {
      await repo.saveMemberBypassingValidationForTest(member());

      final first = await admit();
      final second = await admit();

      expect(first, SiblingDeviceAdmissionOutcome.admitted);
      expect(second, SiblingDeviceAdmissionOutcome.alreadyPresent);
      final saved = await repo.getMember(groupId, memberPeerId);
      expect(saved!.devices, hasLength(1), reason: 'no duplicate device row');
      // BOTH the admit and the re-announce reopen + drain, so a device whose
      // first delivery exhausted/finalized can still converge on a later
      // announce (fixes the terminal-row no-op).
      expect(reopenCalls, hasLength(2));
      expect(drainCalls, hasLength(2));
    },
  );

  test('admits but does not re-distribute when no group key exists yet', () async {
    // A fresh repo with the group + member but NO key (setUp's repo has one).
    final keylessRepo = InMemoryGroupRepository();
    await keylessRepo.saveGroup(
      GroupModel(
        id: groupId,
        name: 'G',
        type: GroupType.chat,
        topicName: 'topic-$groupId',
        createdAt: DateTime.utc(2024, 1, 1),
        createdBy: memberPeerId,
        myRole: GroupRole.admin,
      ),
    );
    await keylessRepo.saveMemberBypassingValidationForTest(member());

    final outcome = await admitSiblingDeviceIfTrusted(
      groupRepo: keylessRepo,
      groupId: groupId,
      memberPeerId: memberPeerId,
      announcedDeviceId: 'sibling-device-1',
      announcedTransportPeerId: '12D3KooWsiblingTransport',
      announcedDeviceSigningPublicKey: 'sibling-signing-key',
      announcedMlKemPublicKey: 'sibling-mlkem',
      verifiedAccountSigningPublicKey: accountKey,
      multiDeviceSyncEnabled: true,
      reopenDeferredDistribution: reopenSpy,
      triggerDrain: drainSpy,
    );

    expect(outcome, SiblingDeviceAdmissionOutcome.admitted);
    // With no local key there is nothing to re-distribute: neither reopen nor
    // drain fires. This device converges via the next group key rotation, which
    // enumerates the member's active devices.
    expect(reopenCalls, isEmpty);
    expect(drainCalls, isEmpty);
  });

  test(
    'same-peerId sibling (no distinct key) is alreadyPresent via legacy device',
    () async {
      // Member has no explicit devices, so the account keys synthesize a legacy
      // device whose transportPeerId == member.peerId. An announce that reuses
      // that same transport must NOT create a duplicate.
      await repo.saveMemberBypassingValidationForTest(member());

      final outcome = await admit(
        deviceId: memberPeerId,
        transportPeerId: memberPeerId,
      );

      expect(outcome, SiblingDeviceAdmissionOutcome.alreadyPresent);
      final saved = await repo.getMember(groupId, memberPeerId);
      expect(saved!.devices, isEmpty);
      expect(drainCalls, isEmpty);
    },
  );
}
