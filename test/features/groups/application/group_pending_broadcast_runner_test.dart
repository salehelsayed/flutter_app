import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_repush.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_runner.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_sink.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

class _FakeRepo
    implements
        GroupPendingBroadcastRepository,
        GroupPendingBroadcastExactRepository {
  final Map<String, GroupPendingBroadcast> rows = {};
  Future<void> Function(String groupId)? beforeForGroup;
  Future<void> Function(String id)? beforeRemove;

  @override
  Future<void> enqueue(GroupPendingBroadcast b) async => rows[b.id] = b;

  @override
  Future<List<GroupPendingBroadcast>> forGroup(String groupId) async {
    await beforeForGroup?.call(groupId);
    return rows.values.where((b) => b.groupId == groupId).toList();
  }

  @override
  Future<List<GroupPendingBroadcast>> all() async => rows.values.toList();

  @override
  Future<int> countForGroup(String groupId) async =>
      rows.values.where((b) => b.groupId == groupId).length;

  @override
  Future<void> remove(String id) async {
    await beforeRemove?.call(id);
    rows.remove(id);
  }

  @override
  Future<bool> removeIfExact(GroupPendingBroadcast expected) async {
    final current = rows[expected.id];
    if (current == null || !sameExactGroupPendingBroadcast(current, expected)) {
      return false;
    }
    await beforeRemove?.call(expected.id);
    rows.remove(expected.id);
    return true;
  }

  @override
  Future<void> removeForGroup(String groupId) async {
    rows.removeWhere((_, broadcast) => broadcast.groupId == groupId);
  }
}

GroupPendingBroadcast _b(String id, {String groupId = 'group-1'}) =>
    GroupPendingBroadcast(
      id: id,
      groupId: groupId,
      kind: 'group_metadata_updated',
      sysText: '{}',
      recipientPeerIds: const ['peer-a'],
      eventAt: DateTime.utc(2026, 6, 17),
      sourceMessageId: 'src-$id',
      createdAt: DateTime.utc(2026, 6, 17),
      updatedAt: DateTime.utc(2026, 6, 17),
    );

void main() {
  late _FakeRepo repo;

  setUp(() => repo = _FakeRepo());

  test('drainForGroup re-pushes and clears every row on success', () async {
    await repo.enqueue(_b('b1'));
    await repo.enqueue(_b('b2'));
    final pushed = <String>[];
    final runner = GroupPendingBroadcastRunner(
      repository: repo,
      rePush: (b) async {
        pushed.add(b.id);
        return true;
      },
    );

    final drained = await runner.drainForGroup('group-1');
    expect(drained, 2);
    expect(pushed.toSet(), {'b1', 'b2'});
    expect(await repo.countForGroup('group-1'), 0);
  });

  test('a failed re-push retains the row for the next drain', () async {
    await repo.enqueue(_b('b1'));
    final runner = GroupPendingBroadcastRunner(
      repository: repo,
      rePush: (b) async => false,
    );

    expect(await runner.drainForGroup('group-1'), 0);
    expect(await repo.countForGroup('group-1'), 1);
  });

  test('a throwing re-push retains the row (never bubbles)', () async {
    await repo.enqueue(_b('b1'));
    final runner = GroupPendingBroadcastRunner(
      repository: repo,
      rePush: (b) async => throw Exception('bridge down'),
    );

    expect(await runner.drainForGroup('group-1'), 0);
    expect(await repo.countForGroup('group-1'), 1);
  });

  test('partial success clears only the succeeded rows', () async {
    await repo.enqueue(_b('b1'));
    await repo.enqueue(_b('b2'));
    final runner = GroupPendingBroadcastRunner(
      repository: repo,
      rePush: (b) async => b.id == 'b1',
    );

    expect(await runner.drainForGroup('group-1'), 1);
    final remaining = await repo.forGroup('group-1');
    expect(remaining.map((b) => b.id), ['b2']);
  });

  test('drainAll sweeps across groups', () async {
    await repo.enqueue(_b('b1', groupId: 'group-1'));
    await repo.enqueue(_b('b2', groupId: 'group-2'));
    final runner = GroupPendingBroadcastRunner(
      repository: repo,
      rePush: (b) async => true,
    );

    expect(await runner.drainAll(), 2);
    expect(await repo.all(), isEmpty);
  });

  test(
    'PB264-01 same-group group/all drains serialize, reload, and protect the current tail from a late fourth caller',
    () async {
      await repo.enqueue(_b('first-turn'));
      final releases = <Completer<void>>[];
      final secondLoadEntered = Completer<void>();
      final releaseSecondLoad = Completer<void>();
      final pushed = <String>[];
      var groupLoads = 0;
      var active = 0;
      var maxActive = 0;
      repo.beforeForGroup = (groupId) async {
        if (groupId != 'group-1') return;
        groupLoads++;
        if (groupLoads == 2) {
          secondLoadEntered.complete();
          await releaseSecondLoad.future;
        } else if (groupLoads == 3) {
          await repo.enqueue(_b('third-turn'));
        } else if (groupLoads == 4) {
          await repo.enqueue(_b('fourth-turn'));
        }
      };
      final runner = GroupPendingBroadcastRunner(
        repository: repo,
        rePush: (broadcast) async {
          pushed.add(broadcast.id);
          active++;
          if (active > maxActive) maxActive = active;
          final release = Completer<void>();
          releases.add(release);
          await release.future;
          active--;
          return true;
        },
      );

      addTearDown(() {
        if (!releaseSecondLoad.isCompleted) releaseSecondLoad.complete();
        for (final release in releases) {
          if (!release.isCompleted) release.complete();
        }
      });

      Future<void> waitForCalls(int count) async {
        for (var attempt = 0; attempt < 200; attempt++) {
          if (releases.length >= count) return;
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        fail('Timed out waiting for $count re-push calls');
      }

      final first = runner.drainForGroup('group-1');
      await waitForCalls(1);
      final second = runner.drainAll();
      final third = runner.drainForGroup('group-1');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(maxActive, 1, reason: 'same-group entry points must share a tail');

      releases[0].complete();
      await secondLoadEntered.future;

      // This row did not exist in drainAll's discovery snapshot or in the
      // first turn. It must be loaded inside the second keyed turn and removed
      // exactly once; reusing the old load makes this assertion fail.
      await repo.enqueue(_b('between-turns'));
      releaseSecondLoad.complete();
      await waitForCalls(2);

      // Schedule after the first turn has cleaned up while the second is still
      // active. An old turn must not remove the newer map entry and let this
      // late caller overlap it.
      final fourth = runner.drainForGroup('group-1');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(maxActive, 1, reason: 'late callers must retain the current tail');

      releases[1].complete();
      await waitForCalls(3);
      releases[2].complete();
      await waitForCalls(4);
      releases[3].complete();

      expect(await first, 1);
      expect(await second, 1);
      expect(await third, 1);
      expect(await fourth, 1);
      expect(maxActive, 1);
      expect(pushed, <String>[
        'first-turn',
        'between-turns',
        'third-turn',
        'fourth-turn',
      ]);
      expect(await repo.forGroup('group-1'), isEmpty);
      expect(groupLoads, 5, reason: 'four turns plus the final assertion load');
      expect(releases, hasLength(4), reason: 'every turn reloads the group');
    },
  );

  test(
    'PB264-02 repository failure releases the keyed turn while another group progresses',
    () async {
      await repo.enqueue(_b('load-same', groupId: 'group-1'));
      await repo.enqueue(_b('load-other', groupId: 'group-2'));
      final loadEntered = Completer<void>();
      final releaseLoad = Completer<void>();
      final unrelatedLoadPush = Completer<void>();
      var failFirstGroupLoad = true;
      repo.beforeForGroup = (groupId) async {
        if (groupId == 'group-1' && failFirstGroupLoad) {
          failFirstGroupLoad = false;
          loadEntered.complete();
          await releaseLoad.future;
          throw StateError('injected repository failure');
        }
      };
      final pushed = <String>[];
      final runner = GroupPendingBroadcastRunner(
        repository: repo,
        rePush: (broadcast) async {
          pushed.add(broadcast.id);
          if (broadcast.groupId == 'group-2' &&
              !unrelatedLoadPush.isCompleted) {
            unrelatedLoadPush.complete();
          }
          return true;
        },
      );

      final failed = runner.drainForGroup('group-1');
      await loadEntered.future;
      final sameGroupSuccessor = runner.drainForGroup('group-1');
      final unrelated = runner.drainForGroup('group-2');

      await unrelatedLoadPush.future;
      expect(pushed, [
        'load-other',
      ], reason: 'an unrelated group must cross while group-1 is held');
      releaseLoad.complete();
      await expectLater(failed, throwsStateError);
      expect(await unrelated, 1);
      expect(await sameGroupSuccessor, 1);
      expect(pushed.toSet(), {'load-same', 'load-other'});

      // Runner-owned exact removal is outside the swallowed rePush boundary.
      // Its rejection must release the same keyed tail while preserving the
      // same non-global-lock property.
      final removeRepo = _FakeRepo();
      await removeRepo.enqueue(_b('remove-same', groupId: 'group-1'));
      await removeRepo.enqueue(_b('remove-other', groupId: 'group-2'));
      final removeEntered = Completer<void>();
      final releaseRemove = Completer<void>();
      final unrelatedRemovePush = Completer<void>();
      var rejectFirstRemove = true;
      var samePushes = 0;
      removeRepo.beforeRemove = (id) async {
        if (id == 'remove-same' && rejectFirstRemove) {
          rejectFirstRemove = false;
          removeEntered.complete();
          await releaseRemove.future;
          throw StateError('injected exact remove rejection');
        }
      };
      final removeRunner = GroupPendingBroadcastRunner(
        repository: removeRepo,
        rePush: (broadcast) async {
          if (broadcast.groupId == 'group-1') samePushes++;
          if (broadcast.groupId == 'group-2' &&
              !unrelatedRemovePush.isCompleted) {
            unrelatedRemovePush.complete();
          }
          return true;
        },
      );

      final removeFailed = removeRunner.drainForGroup('group-1');
      await removeEntered.future;
      final removeSuccessor = removeRunner.drainForGroup('group-1');
      final removeUnrelated = removeRunner.drainForGroup('group-2');
      await unrelatedRemovePush.future;
      expect(samePushes, 1, reason: 'same-group successor remains behind tail');
      releaseRemove.complete();
      await expectLater(removeFailed, throwsStateError);
      expect(await removeUnrelated, 1);
      expect(await removeSuccessor, 1);
      expect(samePushes, 2);
      expect(await removeRepo.forGroup('group-1'), isEmpty);
    },
  );

  test(
    'production re-push skips marked shells and finalizes the exact row inside the membership phase',
    () async {
      final createdAt = DateTime.utc(2026, 7, 20, 14);
      final markedAt = createdAt.add(const Duration(minutes: 1));
      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(
        GroupModel(
          id: 'group-1',
          name: 'Group',
          type: GroupType.chat,
          topicName: 'topic-group-1',
          createdAt: createdAt,
          createdBy: 'peer-self',
          myRole: GroupRole.admin,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-self',
          username: 'Self',
          role: MemberRole.admin,
          publicKey: 'pk-self',
          mlKemPublicKey: 'mlkem-self',
          joinedAt: createdAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-a',
          username: 'A',
          role: MemberRole.writer,
          publicKey: 'pk-a',
          mlKemPublicKey: 'mlkem-a',
          joinedAt: createdAt,
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'group-key',
          createdAt: createdAt,
        ),
      );
      await repo.enqueue(_b('guarded'));
      await groupRepo.updateGroup(
        (await groupRepo.getGroup(
          'group-1',
        ))!.copyWith(selfRemovedAt: markedAt),
      );
      final identityRepo = FakeIdentityRepository()
        ..seed(
          FakeIdentityRepository.makeIdentity(
            peerId: 'peer-self',
            publicKey: 'pk-self',
            privateKey: 'sk-self',
            mlKemPublicKey: 'mlkem-self',
          ),
        );
      final bridge = FakeBridge();
      final runner = GroupPendingBroadcastRunner(
        repository: repo,
        rePushFinalizesSuccess: true,
        rePush: buildGroupPendingBroadcastRePush(
          bridge: bridge,
          groupRepo: groupRepo,
          loadIdentity: identityRepo.loadIdentity,
          pendingRepository: repo,
        ),
      );

      expect(await runner.drainForGroup('group-1'), 0);
      expect(await repo.countForGroup('group-1'), 1);
      expect(identityRepo.loadIdentityCallCount, 0);
      expect(bridge.commandLog, isEmpty);

      await groupRepo.updateGroup(
        (await groupRepo.getGroup('group-1'))!.copyWith(selfRemovedAt: null),
      );
      final removeEntered = Completer<void>();
      final releaseRemove = Completer<void>();
      repo.beforeRemove = (_) async {
        removeEntered.complete();
        await releaseRemove.future;
      };
      final activeDrain = runner.drainForGroup('group-1');
      await removeEntered.future;

      var markerCommitted = false;
      final queuedMarker = runGroupMembershipMutationLocked(
        groupId: 'group-1',
        action: () async {
          await groupRepo.updateGroup(
            (await groupRepo.getGroup(
              'group-1',
            ))!.copyWith(selfRemovedAt: markedAt),
          );
          markerCommitted = true;
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(markerCommitted, isFalse);

      releaseRemove.complete();
      expect(await activeDrain, 1);
      expect(await repo.countForGroup('group-1'), 0);
      await queuedMarker;
      expect(markerCommitted, isTrue);
    },
  );

  test(
    'PB264-13 a dissolved group loaded before the lifecycle leaf performs zero re-push network work',
    () async {
      final createdAt = DateTime.utc(2026, 7, 20, 14);
      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(
        GroupModel(
          id: 'group-1',
          name: 'Dissolved',
          type: GroupType.chat,
          topicName: 'topic-group-1',
          createdAt: createdAt,
          createdBy: 'peer-self',
          myRole: GroupRole.admin,
          isDissolved: true,
          dissolvedAt: createdAt.add(const Duration(minutes: 1)),
          dissolvedBy: 'peer-self',
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-self',
          username: 'Self',
          role: MemberRole.admin,
          publicKey: 'pk-self',
          mlKemPublicKey: 'mlkem-self',
          joinedAt: createdAt,
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'group-key',
          createdAt: createdAt,
        ),
      );
      final pending = _b('dissolved-loaded');
      await repo.enqueue(pending);
      final identityRepo = FakeIdentityRepository()
        ..seed(
          FakeIdentityRepository.makeIdentity(
            peerId: 'peer-self',
            publicKey: 'pk-self',
            privateKey: 'sk-self',
            mlKemPublicKey: 'mlkem-self',
          ),
        );
      final bridge = FakeBridge();
      final rePush = buildGroupPendingBroadcastRePush(
        bridge: bridge,
        groupRepo: groupRepo,
        loadIdentity: identityRepo.loadIdentity,
        pendingRepository: repo,
      );

      expect(await rePush(pending), isFalse);
      expect(identityRepo.loadIdentityCallCount, 0);
      expect(bridge.commandLog, isEmpty);
      expect(await repo.forGroup('group-1'), [pending]);
    },
  );

  test(
    'PB264-03 prepared role rows reach the exact commit branch and retain ambiguous state',
    () async {
      final eventAt = DateTime.utc(2026, 6, 17);
      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(
        GroupModel(
          id: 'group-1',
          name: 'Group',
          type: GroupType.chat,
          topicName: 'topic-group-1',
          createdAt: eventAt,
          createdBy: 'peer-self',
          myRole: GroupRole.admin,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-self',
          username: 'Self',
          role: MemberRole.admin,
          publicKey: 'pk-self',
          mlKemPublicKey: 'mlkem-self',
          joinedAt: eventAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-other',
          username: 'Other',
          role: MemberRole.writer,
          publicKey: 'pk-other',
          mlKemPublicKey: 'mlkem-other',
          joinedAt: eventAt,
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'group-key-1',
          createdAt: eventAt,
        ),
      );
      final identityRepo = FakeIdentityRepository()
        ..seed(
          FakeIdentityRepository.makeIdentity(
            peerId: 'peer-self',
            publicKey: 'pk-self',
            privateKey: 'sk-self',
            mlKemPublicKey: 'mlkem-self',
          ),
        );
      final bridge = FakeBridge();
      final rePush = buildGroupPendingBroadcastRePush(
        bridge: bridge,
        groupRepo: groupRepo,
        loadIdentity: identityRepo.loadIdentity,
      );
      final prepared = GroupPendingBroadcast(
        id: 'prepared-role',
        groupId: 'group-1',
        kind: groupPendingBroadcastKindMemberRolePrepared,
        sysText: '{"member":{"peerId":"peer-other","role":"admin"}}',
        recipientPeerIds: const ['peer-other'],
        eventAt: eventAt,
        sourceMessageId: 'role-source',
        createdAt: eventAt,
        updatedAt: eventAt,
      );

      markGroupRolePreparationInFlight(prepared.id);
      addTearDown(() => clearGroupRolePreparationInFlight(prepared.id));
      expect(await rePush(prepared), isFalse);
      expect(bridge.commandLog, isNot(contains('group:publish')));

      await groupRepo.updateMemberRole(
        'group-1',
        'peer-other',
        MemberRole.admin,
      );
      expect(await rePush(prepared), isFalse);
      expect(bridge.commandLog, isNot(contains('group:publish')));

      clearGroupRolePreparationInFlight(prepared.id);
      expect(await rePush(prepared), isFalse);
      expect(bridge.commandLog, isNot(contains('group:publish')));
    },
  );

  test(
    'PB264-03 empty-recipient generic broadcast publishes once, stores no inbox, and removes the exact row',
    () async {
      final eventAt = DateTime.utc(2026, 6, 17);
      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(
        GroupModel(
          id: 'group-1',
          name: 'Group',
          type: GroupType.chat,
          topicName: 'topic-group-1',
          createdAt: eventAt,
          createdBy: 'peer-self',
          myRole: GroupRole.admin,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-self',
          username: 'Self',
          role: MemberRole.admin,
          publicKey: 'pk-self',
          mlKemPublicKey: 'mlkem-self',
          joinedAt: eventAt,
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'group-key-1',
          createdAt: eventAt,
        ),
      );
      final identityRepo = FakeIdentityRepository()
        ..seed(
          FakeIdentityRepository.makeIdentity(
            peerId: 'peer-self',
            publicKey: 'pk-self',
            privateKey: 'sk-self',
            mlKemPublicKey: 'mlkem-self',
          ),
        );
      final broadcast = GroupPendingBroadcast(
        id: 'empty-recipient',
        groupId: 'group-1',
        kind: 'group_metadata_updated',
        sysText: '{}',
        recipientPeerIds: const <String>[],
        eventAt: eventAt,
        sourceMessageId: 'empty-recipient-source',
        createdAt: eventAt,
        updatedAt: eventAt,
      );
      await repo.enqueue(broadcast);
      final bridge = FakeBridge();
      final rePush = buildGroupPendingBroadcastRePush(
        bridge: bridge,
        groupRepo: groupRepo,
        loadIdentity: identityRepo.loadIdentity,
        pendingRepository: repo,
      );

      expect(await rePush(broadcast), isTrue);
      expect(
        bridge.commandLog.where((command) => command == 'group:publish'),
        hasLength(1),
      );
      expect(bridge.commandLog, isNot(contains('group:inboxStore')));
      expect(await repo.forGroup('group-1'), isEmpty);
    },
  );

  test(
    'PB264-03 exact role watermark cannot publish a row without signed transition authority',
    () async {
      final eventAt = DateTime.utc(2026, 6, 17);
      const sourceEventId = 'role-source';
      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(
        GroupModel(
          id: 'group-1',
          name: 'Group',
          type: GroupType.chat,
          topicName: 'topic-group-1',
          createdAt: eventAt,
          createdBy: 'peer-self',
          myRole: GroupRole.admin,
          lastMembershipEventAt: eventAt,
          lastMembershipEventId: sourceEventId,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-self',
          username: 'Self',
          role: MemberRole.admin,
          publicKey: 'pk-self',
          mlKemPublicKey: 'mlkem-self',
          joinedAt: eventAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-other',
          username: 'Other',
          role: MemberRole.admin,
          publicKey: 'pk-other',
          mlKemPublicKey: 'mlkem-other',
          joinedAt: eventAt,
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'group-key-1',
          createdAt: eventAt,
        ),
      );
      final identityRepo = FakeIdentityRepository();
      identityRepo.seed(
        FakeIdentityRepository.makeIdentity(
          peerId: 'peer-self',
          publicKey: 'pk-self',
          privateKey: 'sk-self',
          mlKemPublicKey: 'mlkem-self',
        ),
      );
      final bridge = FakeBridge();
      final rePush = buildGroupPendingBroadcastRePush(
        bridge: bridge,
        groupRepo: groupRepo,
        loadIdentity: identityRepo.loadIdentity,
      );
      final prepared = GroupPendingBroadcast(
        id: 'prepared-role-exact',
        groupId: 'group-1',
        kind: groupPendingBroadcastKindMemberRolePrepared,
        sysText: '{"member":{"peerId":"peer-other","role":"admin"}}',
        recipientPeerIds: const ['peer-other'],
        eventAt: eventAt,
        sourceMessageId: sourceEventId,
        createdAt: eventAt,
        updatedAt: eventAt,
      );

      expect(await rePush(prepared), isFalse);
      expect(identityRepo.loadIdentityCallCount, 1);
      expect(
        bridge.commandLog.where((command) => command == 'group:publish'),
        isEmpty,
      );
      expect(
        bridge.commandLog.where((command) => command == 'group:inboxStore'),
        isEmpty,
      );
    },
  );
}
