import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/announce_restored_device_use_case.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_repush.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_runner.dart';
import 'package:flutter_app/features/groups/application/hydrate_groups_from_peers_use_case.dart';
import 'package:flutter_app/features/groups/application/reconcile_missed_group_dissolves_use_case.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/application/self_removed_group_lifecycle_guard.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

class _PendingBroadcastRepository implements GroupPendingBroadcastRepository {
  final Map<String, GroupPendingBroadcast> rows = {};

  @override
  Future<List<GroupPendingBroadcast>> all() async => rows.values.toList();

  @override
  Future<int> countForGroup(String groupId) async =>
      rows.values.where((row) => row.groupId == groupId).length;

  @override
  Future<void> enqueue(GroupPendingBroadcast broadcast) async {
    rows[broadcast.id] = broadcast;
  }

  @override
  Future<List<GroupPendingBroadcast>> forGroup(String groupId) async => rows
      .values
      .where((row) => row.groupId == groupId)
      .toList(growable: false);

  @override
  Future<void> remove(String id) async {
    rows.remove(id);
  }

  @override
  Future<void> removeForGroup(String groupId) async {
    rows.removeWhere((_, row) => row.groupId == groupId);
  }
}

void main() {
  const groupId = 'group-lifecycle';
  final createdAt = DateTime.utc(2026, 7, 20, 15);
  final removedAt = createdAt.add(const Duration(minutes: 1));

  GroupModel group({required String id, DateTime? selfRemovedAt}) => GroupModel(
    id: id,
    name: 'Lifecycle Group',
    type: GroupType.chat,
    topicName: 'topic-$id',
    createdAt: createdAt,
    createdBy: 'peer-self',
    myRole: GroupRole.member,
    selfRemovedAt: selfRemovedAt,
    lastMembershipEventAt: selfRemovedAt,
  );

  Future<void> markRemoved(
    InMemoryGroupRepository repository,
    String id,
  ) async {
    final current = await repository.getGroup(id);
    await repository.updateGroup(
      current!.copyWith(
        selfRemovedAt: removedAt,
        lastMembershipEventAt: removedAt,
      ),
    );
  }

  test(
    'decoded dissolve queued behind B3 performs no timeline or native leave',
    () async {
      final groupRepo = InMemoryGroupRepository();
      final msgRepo = InMemoryGroupMessageRepository();
      final bridge = FakeBridge();
      await groupRepo.saveGroup(
        GroupModel(
          id: groupId,
          name: 'Lifecycle Group',
          type: GroupType.chat,
          topicName: 'topic-$groupId',
          createdAt: createdAt,
          createdBy: 'peer-admin',
          myRole: GroupRole.member,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          joinedAt: createdAt,
        ),
      );
      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
      );
      addTearDown(listener.dispose);

      final markerEntered = Completer<void>();
      final releaseMarker = Completer<void>();
      final marker = runGroupMembershipMutationLocked(
        groupId: groupId,
        action: () async {
          markerEntered.complete();
          await releaseMarker.future;
          await markRemoved(groupRepo, groupId);
        },
      );
      await markerEntered.future;

      // This is the already-decoded callback boundary used after a slow inbox
      // decrypt. B3 owns the phase before the dissolve handler can route it.
      final replay = listener.handleReplayEnvelope({
        'groupId': groupId,
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'messageId': 'dissolve-after-decrypt',
        'text':
            '{"__sys":"group_dissolved","dissolvedAt":"${removedAt.toIso8601String()}","dissolvedBy":"peer-admin"}',
        'timestamp': removedAt.toIso8601String(),
      });
      await Future<void>.delayed(Duration.zero);
      releaseMarker.complete();
      await marker;
      await replay;

      expect((await groupRepo.getGroup(groupId))?.isDissolved, isFalse);
      expect(await msgRepo.getLatestMessage(groupId), isNull);
      expect(bridge.commandLog, isNot(contains('group:leave')));
    },
  );

  test(
    'marked shells and loaded membership work perform zero join inbox hydrate announce dissolve or pending sends',
    () async {
      const orderingGroupId = 'group-ordering';
      final orderingRepo = InMemoryGroupRepository();
      await orderingRepo.saveGroup(group(id: orderingGroupId));

      // An external leaf that already owns the membership lock completes
      // before B3 can mark the shell.
      final actionEntered = Completer<void>();
      final releaseAction = Completer<void>();
      var actionCalls = 0;
      final activeLeaf = runSelfRemovedGroupLifecycleLeaf(
        groupRepo: orderingRepo,
        groupId: orderingGroupId,
        action: (_) async {
          actionCalls++;
          actionEntered.complete();
          await releaseAction.future;
        },
      );
      await actionEntered.future;
      var markerCommitted = false;
      final queuedMarker = runGroupMembershipMutationLocked(
        groupId: orderingGroupId,
        action: () async {
          await markRemoved(orderingRepo, orderingGroupId);
          markerCommitted = true;
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(markerCommitted, isFalse);
      releaseAction.complete();
      final activeResult = await activeLeaf;
      await queuedMarker;
      expect(activeResult.didRun, isTrue);
      expect(actionCalls, 1);
      expect(markerCommitted, isTrue);

      // Work queued behind B3 re-reads authority after the lock resumes and
      // skips the external leaf.
      await orderingRepo.updateGroup(
        (await orderingRepo.getGroup(
          orderingGroupId,
        ))!.copyWith(selfRemovedAt: null),
      );
      final markerLockEntered = Completer<void>();
      final releaseMarkerLock = Completer<void>();
      final markerFirst = runGroupMembershipMutationLocked(
        groupId: orderingGroupId,
        action: () async {
          markerLockEntered.complete();
          await releaseMarkerLock.future;
          await markRemoved(orderingRepo, orderingGroupId);
        },
      );
      await markerLockEntered.future;
      var skippedActionCalls = 0;
      final loadedWork = runSelfRemovedGroupLifecycleLeaf(
        groupRepo: orderingRepo,
        groupId: orderingGroupId,
        action: (_) async => skippedActionCalls++,
      );
      await Future<void>.delayed(Duration.zero);
      releaseMarkerLock.complete();
      await markerFirst;
      final skippedResult = await loadedWork;
      expect(skippedResult.didRun, isFalse);
      expect(
        skippedResult.disposition,
        SelfRemovedGroupLifecycleDisposition.skippedSelfRemoved,
      );
      expect(skippedActionCalls, 0);

      var absentActionCalls = 0;
      final absentResult = await runSelfRemovedGroupLifecycleLeaf(
        groupRepo: orderingRepo,
        groupId: 'group-absent',
        action: (_) async => absentActionCalls++,
      );
      expect(absentResult.didRun, isFalse);
      expect(
        absentResult.disposition,
        SelfRemovedGroupLifecycleDisposition.skippedAbsent,
      );
      expect(absentActionCalls, 0);

      final groupRepo = InMemoryGroupRepository();
      final msgRepo = InMemoryGroupMessageRepository();
      final bridge = FakeBridge();
      await groupRepo.saveGroup(group(id: groupId, selfRemovedAt: removedAt));
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-self',
          username: 'Self',
          role: MemberRole.writer,
          publicKey: 'pk-self',
          joinedAt: createdAt,
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'group-key',
          createdAt: createdAt,
        ),
      );

      await rejoinGroupTopics(bridge: bridge, groupRepo: groupRepo);
      await drainGroupOfflineInboxForGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: groupId,
      );
      expect(
        await hydrateGroupsFromPeers(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          canRejoinForExitIntent: (_) async => true,
          processExitIntent: (_) async {},
          multiDeviceSyncEnabled: true,
        ),
        0,
      );
      expect(
        await announceRestoredDeviceToGroups(
          bridge: bridge,
          groupRepo: groupRepo,
          selfPeerId: 'peer-self',
          accountSigningPublicKey: 'pk-self',
          accountSigningPrivateKey: 'sk-self',
          selfUsername: 'Self',
          announcedDevice: const GroupMemberDeviceIdentity(
            deviceId: 'self-device',
            transportPeerId: 'self-device',
            deviceSigningPublicKey: 'pk-self-device',
          ),
          multiDeviceSyncEnabled: true,
        ),
        0,
      );

      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
      );
      addTearDown(listener.dispose);
      await reconcileMissedGroupDissolves(
        bridge: bridge,
        groupRepo: groupRepo,
        groupMessageListener: listener,
        selfPeerId: 'peer-self',
      );

      final pendingRepo = _PendingBroadcastRepository();
      await pendingRepo.enqueue(
        GroupPendingBroadcast(
          id: 'pending-1',
          groupId: groupId,
          kind: 'group_metadata_updated',
          sysText: '{}',
          recipientPeerIds: const <String>[],
          eventAt: createdAt,
          sourceMessageId: 'source-1',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
      final identityRepo = FakeIdentityRepository()
        ..seed(
          FakeIdentityRepository.makeIdentity(
            peerId: 'peer-self',
            publicKey: 'pk-self',
            privateKey: 'sk-self',
          ),
        );
      final runner = GroupPendingBroadcastRunner(
        repository: pendingRepo,
        rePush: buildGroupPendingBroadcastRePush(
          bridge: bridge,
          groupRepo: groupRepo,
          loadIdentity: identityRepo.loadIdentity,
        ),
      );
      expect(await runner.drainForGroup(groupId), 0);
      expect(await pendingRepo.countForGroup(groupId), 1);
      expect(identityRepo.loadIdentityCallCount, 0);

      expect(
        bridge.commandLog,
        isEmpty,
        reason: 'a marked shell has no native or network lifecycle authority',
      );
    },
  );
}
