import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/fake_group_pubsub_network.dart';
import '../../../shared/fakes/group_test_user.dart';

const groupAdminMetadataConvergenceLabel =
    'A/B/C metadata, admin promotion, member add, fanout, and avatar updates converge';
const promotedAdminAddsMemberConvergenceLabel =
    'promoted admin can add C and A/B/C metadata, fanout, and avatar updates converge';

enum GroupAdminMetadataMemberAdder { alice, bob }

Future<void> runGroupAdminMetadataConvergenceScenario({
  GroupAdminMetadataMemberAdder charlieAdder =
      GroupAdminMetadataMemberAdder.alice,
}) async {
  final network = FakeGroupPubSubNetwork();

  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 50));

  Future<void> waitUntil(
    Future<bool> Function() condition, {
    String reason = 'condition',
  }) async {
    for (var i = 0; i < 40; i++) {
      if (await condition()) return;
      await pump();
    }
    fail('Timed out waiting for $reason');
  }

  const groupId = 'grp-admin-metadata-convergence';
  final createdAt = DateTime.utc(2026, 5, 25, 10);

  final alice = GroupTestUser.create(
    peerId: 'peer-a',
    deviceId: 'device-a',
    username: 'User A',
    network: network,
  );
  final bob = GroupTestUser.create(
    peerId: 'peer-b',
    deviceId: 'device-b',
    username: 'User B',
    network: network,
  );
  final charlie = GroupTestUser.create(
    peerId: 'peer-c',
    deviceId: 'device-c',
    username: 'User C',
    network: network,
  );
  addTearDown(() {
    alice.dispose();
    bob.dispose();
    charlie.dispose();
  });

  alice.start();
  bob.start();
  charlie.start();

  await alice.createGroup(groupId: groupId, name: 'test', createdAt: createdAt);
  await alice.addMember(
    groupId: groupId,
    invitee: bob,
    joinedAt: createdAt.add(const Duration(minutes: 1)),
  );

  await alice.updateMetadata(
    groupId: groupId,
    name: 'test me',
    description: 'do you see me?',
    changedAt: createdAt.add(const Duration(minutes: 2)),
  );
  await waitUntil(() async {
    final group = await bob.groupRepo.getGroup(groupId);
    return group?.name == 'test me' && group?.description == 'do you see me?';
  }, reason: 'Bob metadata update');

  await alice.updateMemberRole(
    groupId: groupId,
    memberPeerId: bob.peerId,
    role: MemberRole.admin,
    changedAt: createdAt.add(const Duration(minutes: 3)),
  );
  await waitUntil(() async {
    final group = await bob.groupRepo.getGroup(groupId);
    final member = await bob.groupRepo.getMember(groupId, bob.peerId);
    return group?.myRole == GroupRole.admin && member?.role == MemberRole.admin;
  }, reason: 'Bob admin promotion');

  final addingAdmin = switch (charlieAdder) {
    GroupAdminMetadataMemberAdder.alice => alice,
    GroupAdminMetadataMemberAdder.bob => bob,
  };
  await addingAdmin.addMember(
    groupId: groupId,
    invitee: charlie,
    joinedAt: createdAt.add(const Duration(minutes: 4)),
  );
  await addingAdmin.broadcastMemberAdded(
    groupId: groupId,
    newMember: charlie,
    eventAt: createdAt.add(const Duration(minutes: 4)),
  );
  await waitUntil(() async {
    final aliceSeesCharlie = await alice.groupRepo.getMember(
      groupId,
      charlie.peerId,
    );
    final bobSeesCharlie = await bob.groupRepo.getMember(
      groupId,
      charlie.peerId,
    );
    final charlieGroup = await charlie.groupRepo.getGroup(groupId);
    return aliceSeesCharlie != null &&
        bobSeesCharlie != null &&
        charlieGroup?.name == 'test me' &&
        charlieGroup?.description == 'do you see me?';
  }, reason: 'Charlie membership and metadata convergence');

  await alice.sendGroupMessage(
    groupId: groupId,
    text: 'from A',
    messageId: 'msg-from-a',
    timestamp: createdAt.add(const Duration(minutes: 5)),
  );
  await bob.sendGroupMessage(
    groupId: groupId,
    text: 'from B',
    messageId: 'msg-from-b',
    timestamp: createdAt.add(const Duration(minutes: 6)),
  );
  await charlie.sendGroupMessage(
    groupId: groupId,
    text: 'from C',
    messageId: 'msg-from-c',
    timestamp: createdAt.add(const Duration(minutes: 7)),
  );

  await waitUntil(() async {
    final aliceMessages = await alice.loadGroupMessages(groupId);
    final bobMessages = await bob.loadGroupMessages(groupId);
    final charlieMessages = await charlie.loadGroupMessages(groupId);
    return aliceMessages.any((message) => message.text == 'from B') &&
        aliceMessages.any((message) => message.text == 'from C') &&
        bobMessages.any((message) => message.text == 'from A') &&
        bobMessages.any((message) => message.text == 'from C') &&
        charlieMessages.any((message) => message.text == 'from A') &&
        charlieMessages.any((message) => message.text == 'from B');
  }, reason: 'three-way group message fanout');

  await alice.updateMetadata(
    groupId: groupId,
    name: 'test me',
    description: 'do you see me?',
    avatarBlobId: 'blob-group-photo-2',
    avatarMime: 'image/jpeg',
    avatarPath: 'media/group_avatars/$groupId.jpg',
    changedAt: createdAt.add(const Duration(minutes: 8)),
  );
  await waitUntil(() async {
    final bobGroup = await bob.groupRepo.getGroup(groupId);
    final charlieGroup = await charlie.groupRepo.getGroup(groupId);
    return bobGroup?.avatarBlobId == 'blob-group-photo-2' &&
        bobGroup?.avatarMime == 'image/jpeg' &&
        charlieGroup?.avatarBlobId == 'blob-group-photo-2' &&
        charlieGroup?.avatarMime == 'image/jpeg';
  }, reason: 'avatar metadata convergence');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Group admin metadata convergence', () {
    test(
      groupAdminMetadataConvergenceLabel,
      runGroupAdminMetadataConvergenceScenario,
    );

    test(promotedAdminAddsMemberConvergenceLabel, () {
      return runGroupAdminMetadataConvergenceScenario(
        charlieAdder: GroupAdminMetadataMemberAdder.bob,
      );
    });
  });
}
