import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/features/groups/application/change_group_member_role_and_broadcast_use_case.dart';
import 'package:flutter_app/features/groups/application/group_exit_policy.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/leave_group_and_delete_local_history_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  const groupId = 'group-exit-actions';
  const selfPeerId = 'peer-self';
  const otherPeerId = 'peer-other';
  final now = DateTime.utc(2026, 7, 19, 12);

  FakeIdentityRepository identityRepository() {
    final repo = FakeIdentityRepository();
    repo.seed(
      FakeIdentityRepository.makeIdentity(
        peerId: selfPeerId,
        publicKey: 'pk-self',
        privateKey: 'sk-self',
        mlKemPublicKey: 'mlkem-self',
      ),
    );
    return repo;
  }

  GroupModel group({GroupRole myRole = GroupRole.admin}) => GroupModel(
    id: groupId,
    name: 'Exit actions',
    type: GroupType.chat,
    topicName: 'topic-$groupId',
    createdAt: now,
    createdBy: selfPeerId,
    myRole: myRole,
  );

  GroupMember member(String peerId, MemberRole role) => GroupMember(
    groupId: groupId,
    peerId: peerId,
    username: peerId,
    role: role,
    publicKey: 'pk-$peerId',
    mlKemPublicKey: 'mlkem-$peerId',
    joinedAt: now,
  );

  Future<void> seedReplayKey(InMemoryGroupRepository repo) => repo.saveKey(
    GroupKeyInfo(
      groupId: groupId,
      keyGeneration: 1,
      encryptedKey: 'group-key-1',
      createdAt: now,
    ),
  );

  test(
    'promotion readiness requires current candidate and completed signed distribution',
    () async {
      Future<
        ({
          InMemoryGroupRepository groupRepo,
          InMemoryGroupMessageRepository messageRepo,
        })
      >
      seeded() async {
        final groupRepo = InMemoryGroupRepository();
        final messageRepo = InMemoryGroupMessageRepository();
        await groupRepo.saveGroup(group());
        await groupRepo.saveMember(member(selfPeerId, MemberRole.admin));
        await groupRepo.saveMember(member(otherPeerId, MemberRole.writer));
        await seedReplayKey(groupRepo);
        await messageRepo.saveMessage(
          buildMemberJoinedTimelineMessage(
            groupId: groupId,
            joinedPeerId: otherPeerId,
            joinedUsername: otherPeerId,
            eventAt: now.add(const Duration(minutes: 1)),
          ),
        );
        return (groupRepo: groupRepo, messageRepo: messageRepo);
      }

      final success = await seeded();
      final successBridge = FakeBridge();
      final directSent = Completer<void>();
      var inboxCompletedBeforeDirect = false;
      final successResult = await changeGroupMemberRoleAndBroadcast(
        bridge: successBridge,
        groupRepo: success.groupRepo,
        identityRepo: identityRepository(),
        groupId: groupId,
        memberPeerId: otherPeerId,
        role: MemberRole.admin,
        messageRepo: success.messageRepo,
        sendP2PMessage: (peerId, message) async {
          inboxCompletedBeforeDirect = successBridge.commandLog.contains(
            'group:inboxStore',
          );
          if (!directSent.isCompleted) directSent.complete();
          return true;
        },
      );
      await directSent.future.timeout(const Duration(seconds: 1));
      expect(
        successResult.outcome,
        ChangeGroupMemberRoleAndBroadcastOutcome.readyToLeave,
      );
      expect(successResult.publishResult?['ok'], isTrue);
      expect(
        successBridge.commandLog.indexOf('payload.sign'),
        lessThan(successBridge.commandLog.indexOf('group:updateConfig')),
      );
      expect(
        successBridge.commandLog.indexOf('group:updateConfig'),
        lessThan(successBridge.commandLog.indexOf('group:publish')),
      );
      expect(
        successBridge.commandLog.indexOf('group:publish'),
        lessThan(successBridge.commandLog.indexOf('group:inboxStore')),
      );
      expect(inboxCompletedBeforeDirect, isTrue);

      final queued = await seeded();
      final queuedBridge = FakeBridge();
      queuedBridge.responses['group:publish'] = {
        'ok': false,
        'errorCode': 'BRIDGE_TIMEOUT',
      };
      final pending = <GroupPendingBroadcast>[];
      final queuedResult = await changeGroupMemberRoleAndBroadcast(
        bridge: queuedBridge,
        groupRepo: queued.groupRepo,
        identityRepo: identityRepository(),
        groupId: groupId,
        memberPeerId: otherPeerId,
        role: MemberRole.admin,
        messageRepo: queued.messageRepo,
        enqueuePending: (row) async {
          _upsertPending(pending, row);
        },
        loadPending: (_) async => List.of(pending),
      );
      expect(
        queuedResult.outcome,
        ChangeGroupMemberRoleAndBroadcastOutcome.pendingSync,
      );
      expect(
        await queued.groupRepo.getMember(groupId, otherPeerId),
        isA<GroupMember>().having(
          (value) => value.role,
          'committed role',
          MemberRole.admin,
        ),
      );
      expect(pending, hasLength(1));
      final roundTripped = GroupPendingBroadcast.fromMap(
        pending.single.toMap(),
      );
      expect(roundTripped.kind, 'member_role_updated');
      expect(roundTripped.sysText, isNotEmpty);
      expect(roundTripped.recipientPeerIds, contains(otherPeerId));
      expect(roundTripped.sourceMessageId, queuedResult.sourceEventId);
      expect(roundTripped.eventAt, queuedResult.eventAt);
      final queuedSystemPayload =
          jsonDecode(roundTripped.sysText) as Map<String, dynamic>;
      expect(queuedSystemPayload['__sys'], 'member_role_updated');
      expect(
        queuedSystemPayload['eventAt'],
        queuedResult.eventAt!.toUtc().toIso8601String(),
      );

      final inboxQueued = await seeded();
      final inboxFailureBridge = FakeBridge();
      inboxFailureBridge.responses['group:inboxStore'] = {
        'ok': false,
        'errorCode': 'INBOX_FAILED',
      };
      final inboxPending = <GroupPendingBroadcast>[];
      final inboxQueuedResult = await changeGroupMemberRoleAndBroadcast(
        bridge: inboxFailureBridge,
        groupRepo: inboxQueued.groupRepo,
        identityRepo: identityRepository(),
        groupId: groupId,
        memberPeerId: otherPeerId,
        role: MemberRole.admin,
        messageRepo: inboxQueued.messageRepo,
        enqueuePending: (row) async {
          _upsertPending(inboxPending, row);
        },
        loadPending: (_) async => List.of(inboxPending),
      );
      expect(
        inboxQueuedResult.outcome,
        ChangeGroupMemberRoleAndBroadcastOutcome.pendingSync,
      );
      expect(inboxQueuedResult.publishResult?['ok'], isTrue);
      expect(
        inboxPending.single.sourceMessageId,
        inboxQueuedResult.sourceEventId,
      );

      final unrelatedPending = GroupPendingBroadcast(
        id: 'pending-metadata',
        groupId: groupId,
        kind: 'group_metadata_updated',
        sysText: '{}',
        recipientPeerIds: const [otherPeerId],
        eventAt: now,
        createdAt: now,
        updatedAt: now,
      );
      pending.add(unrelatedPending);
      expect(
        await retryPendingGroupRoleTransition(
          groupId: groupId,
          sourceEventId: queuedResult.sourceEventId!,
          drain: (_) async {
            pending.removeWhere(
              (row) => row.sourceMessageId == queuedResult.sourceEventId,
            );
            return 0;
          },
          loadPending: (_) async => List.of(pending),
        ),
        isTrue,
      );
      expect(pending, [unrelatedPending]);

      final unsigned = await seeded();
      final signingBridge = FakeBridge();
      signingBridge.responses['payload.sign'] = {'ok': false};
      await expectLater(
        changeGroupMemberRoleAndBroadcast(
          bridge: signingBridge,
          groupRepo: unsigned.groupRepo,
          identityRepo: identityRepository(),
          groupId: groupId,
          memberPeerId: otherPeerId,
          role: MemberRole.admin,
          messageRepo: unsigned.messageRepo,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        (await unsigned.groupRepo.getMember(groupId, otherPeerId))?.role,
        MemberRole.writer,
      );
      expect(signingBridge.commandLog, isNot(contains('group:updateConfig')));
      expect(signingBridge.commandLog, isNot(contains('group:publish')));

      final stale = await seeded();
      final staleBridge = _AfterFirstSignBridge(() async {
        await stale.messageRepo.saveMessage(
          buildMemberRemovedTimelineMessage(
            groupId: groupId,
            removedPeerId: otherPeerId,
            removedUsername: otherPeerId,
            senderId: selfPeerId,
            senderUsername: selfPeerId,
            eventAt: now.add(const Duration(minutes: 2)),
          ),
        );
      });
      await expectLater(
        changeGroupMemberRoleAndBroadcast(
          bridge: staleBridge,
          groupRepo: stale.groupRepo,
          identityRepo: identityRepository(),
          groupId: groupId,
          memberPeerId: otherPeerId,
          role: MemberRole.admin,
          messageRepo: stale.messageRepo,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        (await stale.groupRepo.getMember(groupId, otherPeerId))?.role,
        MemberRole.writer,
      );
      expect(
        (await stale.groupRepo.getGroup(groupId))?.lastMembershipEventAt,
        isNull,
      );
      expect(staleBridge.commandLog, isNot(contains('group:updateConfig')));
      expect(staleBridge.commandLog, isNot(contains('group:publish')));
      expect(staleBridge.commandLog, isNot(contains('group:leave')));

      final stateDrift = await seeded();
      final stateDriftBridge = _AfterFirstSignBridge(() async {
        final currentGroup = await stateDrift.groupRepo.getGroup(groupId);
        await stateDrift.groupRepo.updateGroup(
          currentGroup!.copyWith(name: 'Renamed while role signing'),
        );
      });
      await expectLater(
        changeGroupMemberRoleAndBroadcast(
          bridge: stateDriftBridge,
          groupRepo: stateDrift.groupRepo,
          identityRepo: identityRepository(),
          groupId: groupId,
          memberPeerId: otherPeerId,
          role: MemberRole.admin,
          messageRepo: stateDrift.messageRepo,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            groupRoleTransitionStateChangedMessage,
          ),
        ),
      );
      expect(
        (await stateDrift.groupRepo.getMember(groupId, otherPeerId))?.role,
        MemberRole.writer,
      );
      expect(
        (await stateDrift.groupRepo.getGroup(groupId))?.name,
        'Renamed while role signing',
      );
      expect(
        stateDriftBridge.commandLog,
        isNot(contains('group:updateConfig')),
      );
      expect(stateDriftBridge.commandLog, isNot(contains('group:publish')));

      final queueWriteFailure = await seeded();
      final queueWriteFailureBridge = FakeBridge();
      await expectLater(
        changeGroupMemberRoleAndBroadcast(
          bridge: queueWriteFailureBridge,
          groupRepo: queueWriteFailure.groupRepo,
          identityRepo: identityRepository(),
          groupId: groupId,
          memberPeerId: otherPeerId,
          role: MemberRole.admin,
          messageRepo: queueWriteFailure.messageRepo,
          enqueuePending: (_) async {
            throw StateError('forced durable queue write failure');
          },
          loadPending: (_) async => const <GroupPendingBroadcast>[],
          removePending: (_) async {},
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        (await queueWriteFailure.groupRepo.getMember(
          groupId,
          otherPeerId,
        ))?.role,
        MemberRole.writer,
      );
      expect(
        queueWriteFailureBridge.commandLog.where(
          (command) => command == 'group:updateConfig',
        ),
        isEmpty,
      );
      expect(
        queueWriteFailureBridge.commandLog,
        isNot(contains('group:publish')),
      );
      expect(
        queueWriteFailureBridge.commandLog,
        isNot(contains('group:inboxStore')),
      );
      final reopened = await resolveGroupExitSnapshot(
        groupRepo: queueWriteFailure.groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        messageRepo: queueWriteFailure.messageRepo,
        loadPendingBroadcasts: (_) async => const <GroupPendingBroadcast>[],
      );
      expect(reopened.disposition, GroupExitDisposition.soleAdminRecovery);
    },
  );

  test('role preparation rejects a colliding durable payload', () async {
    final groupRepo = InMemoryGroupRepository();
    final messageRepo = InMemoryGroupMessageRepository();
    final bridge = FakeBridge();
    await groupRepo.saveGroup(group());
    await groupRepo.saveMember(member(selfPeerId, MemberRole.admin));
    await groupRepo.saveMember(member(otherPeerId, MemberRole.writer));
    await seedReplayKey(groupRepo);
    await messageRepo.saveMessage(
      buildMemberJoinedTimelineMessage(
        groupId: groupId,
        joinedPeerId: otherPeerId,
        joinedUsername: otherPeerId,
        eventAt: now,
      ),
    );
    final pending = <GroupPendingBroadcast>[];
    var removeCalls = 0;

    await expectLater(
      changeGroupMemberRoleAndBroadcast(
        bridge: bridge,
        groupRepo: groupRepo,
        identityRepo: identityRepository(),
        groupId: groupId,
        memberPeerId: otherPeerId,
        role: MemberRole.admin,
        messageRepo: messageRepo,
        enqueuePending: (row) async {
          pending.add(
            GroupPendingBroadcast(
              id: row.id,
              groupId: row.groupId,
              kind: row.kind,
              sysText: '{"collision":true}',
              recipientPeerIds: row.recipientPeerIds,
              eventAt: row.eventAt,
              sourceMessageId: row.sourceMessageId,
              createdAt: row.createdAt,
              updatedAt: row.updatedAt,
            ),
          );
        },
        loadPending: (_) async => List.of(pending),
        removePending: (_) async {
          removeCalls++;
        },
      ),
      throwsA(isA<StateError>()),
    );

    expect(removeCalls, 0);
    expect(pending.single.sysText, '{"collision":true}');
    expect(
      (await groupRepo.getMember(groupId, otherPeerId))?.role,
      MemberRole.writer,
    );
    expect(bridge.commandLog, isNot(contains('group:updateConfig')));
  });

  test('concurrent role preparations retain distinct signed rows', () async {
    const thirdPeerId = 'peer-third';
    final groupRepo = InMemoryGroupRepository();
    final messageRepo = InMemoryGroupMessageRepository();
    final bridge = FakeBridge();
    bridge.responses['group:publish'] = {
      'ok': false,
      'errorCode': 'BRIDGE_TIMEOUT',
    };
    await groupRepo.saveGroup(
      group().copyWith(
        lastMembershipEventAt: DateTime.utc(2099, 1, 1),
        lastMembershipEventId: 'future-watermark',
      ),
    );
    await groupRepo.saveMember(member(selfPeerId, MemberRole.admin));
    await groupRepo.saveMember(member(otherPeerId, MemberRole.writer));
    await groupRepo.saveMember(member(thirdPeerId, MemberRole.writer));
    await seedReplayKey(groupRepo);
    for (final peerId in [otherPeerId, thirdPeerId]) {
      await messageRepo.saveMessage(
        buildMemberJoinedTimelineMessage(
          groupId: groupId,
          joinedPeerId: peerId,
          joinedUsername: peerId,
          eventAt: now,
        ),
      );
    }
    final pending = <GroupPendingBroadcast>[];

    Future<ChangeGroupMemberRoleAndBroadcastResult> promote(String peerId) =>
        changeGroupMemberRoleAndBroadcast(
          bridge: bridge,
          groupRepo: groupRepo,
          identityRepo: identityRepository(),
          groupId: groupId,
          memberPeerId: peerId,
          role: MemberRole.admin,
          messageRepo: messageRepo,
          enqueuePending: (row) async => _upsertPending(pending, row),
          loadPending: (_) async => List.of(pending),
        );

    final results = await Future.wait([
      promote(otherPeerId),
      promote(thirdPeerId),
    ]);

    expect(
      results.map((result) => result.outcome),
      everyElement(ChangeGroupMemberRoleAndBroadcastOutcome.pendingSync),
    );
    expect(results.map((result) => result.sourceEventId).toSet(), hasLength(2));
    expect(pending, hasLength(2));
    expect(
      pending.map((row) => row.kind),
      everyElement(groupPendingBroadcastKindMemberRoleUpdated),
    );
    expect(
      (await groupRepo.getMember(groupId, otherPeerId))?.role,
      MemberRole.admin,
    );
    expect(
      (await groupRepo.getMember(groupId, thirdPeerId))?.role,
      MemberRole.admin,
    );
  });

  test(
    'active exit completes durable prework before native leave and target cleanup',
    () async {
      for (final livePublishOk in [true, false]) {
        final groupRepo = InMemoryGroupRepository();
        final messageRepo = InMemoryGroupMessageRepository();
        final bridge = FakeBridge();
        if (!livePublishOk) {
          bridge.responses['group:publish'] = {
            'ok': false,
            'errorCode': 'BRIDGE_TIMEOUT',
          };
        }
        bridge.responses['group:leave'] = {'ok': true};
        await groupRepo.saveGroup(group(myRole: GroupRole.member));
        await groupRepo.saveGroup(
          GroupModel(
            id: 'other-group',
            name: 'Other group',
            type: GroupType.chat,
            topicName: 'topic-other-group',
            createdAt: now,
            createdBy: otherPeerId,
            myRole: GroupRole.member,
          ),
        );
        await groupRepo.saveMember(member(selfPeerId, MemberRole.writer));
        await groupRepo.saveMember(member(otherPeerId, MemberRole.admin));
        await seedReplayKey(groupRepo);
        await messageRepo.saveMessage(
          GroupMessage(
            id: 'target-$livePublishOk',
            groupId: groupId,
            senderPeerId: otherPeerId,
            text: 'target',
            timestamp: now,
            createdAt: now,
            isIncoming: true,
          ),
        );
        await messageRepo.saveMessage(
          GroupMessage(
            id: 'other-message-$livePublishOk',
            groupId: 'other-group',
            senderPeerId: otherPeerId,
            text: 'preserve',
            timestamp: now,
            createdAt: now,
            isIncoming: true,
          ),
        );
        final pending = <GroupPendingBroadcast>[
          GroupPendingBroadcast(
            id: 'target-pending-$livePublishOk',
            groupId: groupId,
            kind: 'member_role_updated',
            sysText: '{}',
            recipientPeerIds: const [otherPeerId],
            eventAt: now,
            createdAt: now,
            updatedAt: now,
          ),
          GroupPendingBroadcast(
            id: 'other-pending-$livePublishOk',
            groupId: 'other-group',
            kind: 'group_metadata_updated',
            sysText: '{}',
            recipientPeerIds: const [otherPeerId],
            eventAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        ];
        final action = LeaveGroupAndDeleteLocalHistoryUseCase(
          bridge: bridge,
          groupRepo: groupRepo,
          groupMessageRepo: messageRepo,
          identityRepo: identityRepository(),
          discardPendingBroadcasts: (id) async {
            pending.removeWhere((row) => row.groupId == id);
          },
        );

        final result = await action.call(groupId);
        expect(result.status, LeaveGroupAndDeleteLocalHistoryStatus.left);
        expect(result.broadcastResult?.livePublishResult?['ok'], livePublishOk);
        expect(result.broadcastResult?.rotationDeferred, isTrue);
        expect(
          bridge.commandLog.indexOf('group:publish'),
          lessThan(bridge.commandLog.indexOf('group:inboxStore')),
        );
        expect(
          bridge.commandLog.indexOf('group:inboxStore'),
          lessThan(bridge.commandLog.indexOf('group:leave')),
        );
        expect(
          bridge.commandLog.where((command) => command == 'group:leave'),
          hasLength(1),
        );
        expect(await groupRepo.getGroup(groupId), isNull);
        expect(await groupRepo.getGroup('other-group'), isNotNull);
        expect(await messageRepo.getMessage('target-$livePublishOk'), isNull);
        expect(
          await messageRepo.getMessage('other-message-$livePublishOk'),
          isNotNull,
        );
        expect(pending.map((row) => row.id), ['other-pending-$livePublishOk']);
      }
    },
  );

  test(
    'active exit distinguishes prework native and post-commit cleanup failures',
    () async {
      Future<
        ({
          InMemoryGroupRepository groupRepo,
          InMemoryGroupMessageRepository messageRepo,
        })
      >
      seeded({
        InMemoryGroupRepository? repository,
        bool fullRetainedWindow = false,
      }) async {
        final groupRepo = repository ?? InMemoryGroupRepository();
        final messageRepo = InMemoryGroupMessageRepository();
        await groupRepo.saveGroup(group(myRole: GroupRole.member));
        await groupRepo.saveMember(member(selfPeerId, MemberRole.writer));
        await groupRepo.saveMember(member(otherPeerId, MemberRole.admin));
        if (fullRetainedWindow) {
          for (var generation = 1; generation <= 8; generation++) {
            await groupRepo.saveKey(
              GroupKeyInfo(
                groupId: groupId,
                keyGeneration: generation,
                encryptedKey: 'retained-key-$generation',
                createdAt: now.add(Duration(minutes: generation)),
              ),
            );
          }
          await groupRepo.savePendingKeyRotation(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 9,
              encryptedKey: 'prior-draft-key',
              createdAt: now.add(const Duration(minutes: 9)),
            ),
          );
        } else {
          await seedReplayKey(groupRepo);
        }
        return (groupRepo: groupRepo, messageRepo: messageRepo);
      }

      final prework = await seeded();
      final inboxFailureBridge = FakeBridge();
      inboxFailureBridge.responses['group:inboxStore'] = {
        'ok': false,
        'errorCode': 'INBOX_FAILED',
      };
      final preworkResult = await LeaveGroupAndDeleteLocalHistoryUseCase(
        bridge: inboxFailureBridge,
        groupRepo: prework.groupRepo,
        groupMessageRepo: prework.messageRepo,
        identityRepo: identityRepository(),
      ).call(groupId);
      expect(
        preworkResult.status,
        LeaveGroupAndDeleteLocalHistoryStatus.preworkFailed,
      );
      expect(inboxFailureBridge.commandLog, isNot(contains('group:leave')));
      expect(await prework.groupRepo.getGroup(groupId), isNotNull);
      expect(
        await prework.messageRepo.getLatestSystemEventTimestampForTarget(
          groupId,
          eventType: 'member_removed',
          targetId: selfPeerId,
        ),
        isNull,
      );

      final rejected = await seeded(fullRetainedWindow: true);
      final rejectedBridge = FakeBridge();
      rejectedBridge.responses['group:leave'] = {
        'ok': false,
        'errorCode': 'REJECTED',
      };
      final rejectedResult = await LeaveGroupAndDeleteLocalHistoryUseCase(
        bridge: rejectedBridge,
        groupRepo: rejected.groupRepo,
        groupMessageRepo: rejected.messageRepo,
        identityRepo: identityRepository(),
      ).call(groupId);
      expect(
        rejectedResult.status,
        LeaveGroupAndDeleteLocalHistoryStatus.nativeLeaveFailed,
      );
      expect(
        (await rejected.groupRepo.getLatestKey(groupId))?.keyGeneration,
        8,
      );
      for (var generation = 1; generation <= 8; generation++) {
        expect(
          (await rejected.groupRepo.getKeyByGeneration(
            groupId,
            generation,
          ))?.encryptedKey,
          'retained-key-$generation',
        );
      }
      expect(await rejected.groupRepo.getKeyByGeneration(groupId, 9), isNull);
      expect(
        (await rejected.groupRepo.getPendingKeyRotation(groupId))?.encryptedKey,
        'prior-draft-key',
      );
      expect(await rejected.groupRepo.getGroup(groupId), isNotNull);
      expect(
        await rejected.messageRepo.getLatestSystemEventTimestampForTarget(
          groupId,
          eventType: 'member_removed',
          targetId: selfPeerId,
        ),
        isNull,
      );

      final uncertain = await seeded();
      final hangingBridge = _HangingLeaveBridge();
      final uncertainResult = await LeaveGroupAndDeleteLocalHistoryUseCase(
        bridge: hangingBridge,
        groupRepo: uncertain.groupRepo,
        groupMessageRepo: uncertain.messageRepo,
        identityRepo: identityRepository(),
        nativeLeaveTimeout: const Duration(milliseconds: 1),
      ).call(groupId);
      expect(
        uncertainResult.status,
        LeaveGroupAndDeleteLocalHistoryStatus.nativeLeaveUncertain,
      );
      expect(await uncertain.groupRepo.getGroup(groupId), isNotNull);
      expect(
        await uncertain.messageRepo.getLatestSystemEventTimestampForTarget(
          groupId,
          eventType: 'member_removed',
          targetId: selfPeerId,
        ),
        isNotNull,
      );
      hangingBridge.completeLeave();
      await Future<void>.delayed(Duration.zero);
      expect(await uncertain.groupRepo.getGroup(groupId), isNotNull);
      expect(
        hangingBridge.commandLog.where((command) => command == 'group:leave'),
        hasLength(1),
      );

      final failingRepo = _CleanupFailingGroupRepository();
      final incomplete = await seeded(repository: failingRepo);
      final cleanupBridge = FakeBridge();
      cleanupBridge.responses['group:leave'] = {'ok': true};
      final cleanupAction = LeaveGroupAndDeleteLocalHistoryUseCase(
        bridge: cleanupBridge,
        groupRepo: incomplete.groupRepo,
        groupMessageRepo: incomplete.messageRepo,
        identityRepo: identityRepository(),
      );
      expect(
        (await cleanupAction.call(groupId)).status,
        LeaveGroupAndDeleteLocalHistoryStatus.leftCleanupIncomplete,
      );
      await cleanupAction.call(groupId);
      expect(
        cleanupBridge.commandLog.where((command) => command == 'group:leave'),
        hasLength(1),
      );
      expect(
        cleanupBridge.commandLog.where((command) => command == 'group:publish'),
        hasLength(1),
      );

      final soleRepo = InMemoryGroupRepository();
      await soleRepo.saveGroup(group());
      await soleRepo.saveMember(member(selfPeerId, MemberRole.admin));
      await seedReplayKey(soleRepo);
      final soleBridge = FakeBridge();
      final soleResult = await LeaveGroupAndDeleteLocalHistoryUseCase(
        bridge: soleBridge,
        groupRepo: soleRepo,
        groupMessageRepo: InMemoryGroupMessageRepository(),
        identityRepo: identityRepository(),
      ).call(groupId);
      expect(
        soleResult.status,
        LeaveGroupAndDeleteLocalHistoryStatus.blockedLastAdmin,
      );
      expect(soleBridge.commandLog, isNot(contains('group:publish')));
      expect(soleBridge.commandLog, isNot(contains('group:leave')));
    },
  );

  test(
    'completed cleanup does not skip native leave after a later rejoin',
    () async {
      final groupRepo = InMemoryGroupRepository();
      final messageRepo = InMemoryGroupMessageRepository();
      final bridge = FakeBridge();
      final action = LeaveGroupAndDeleteLocalHistoryUseCase(
        bridge: bridge,
        groupRepo: groupRepo,
        groupMessageRepo: messageRepo,
        identityRepo: identityRepository(),
      );

      Future<void> seedJoinedState() async {
        await groupRepo.saveGroup(group(myRole: GroupRole.member));
        await groupRepo.saveMember(member(selfPeerId, MemberRole.writer));
        await groupRepo.saveMember(member(otherPeerId, MemberRole.admin));
        await seedReplayKey(groupRepo);
      }

      await seedJoinedState();
      expect(
        (await action.call(groupId)).status,
        LeaveGroupAndDeleteLocalHistoryStatus.left,
      );
      await seedJoinedState();
      expect(
        (await action.call(groupId)).status,
        LeaveGroupAndDeleteLocalHistoryStatus.left,
      );
      expect(
        bridge.commandLog.where((command) => command == 'group:leave'),
        hasLength(2),
      );
      expect(
        bridge.commandLog.where((command) => command == 'group:publish'),
        hasLength(2),
      );
    },
  );

  test(
    'incomplete cleanup marker is scoped to the membership that left',
    () async {
      final groupRepo = _CleanupFailsOnceGroupRepository();
      final messageRepo = InMemoryGroupMessageRepository();
      final bridge = FakeBridge();
      final action = LeaveGroupAndDeleteLocalHistoryUseCase(
        bridge: bridge,
        groupRepo: groupRepo,
        groupMessageRepo: messageRepo,
        identityRepo: identityRepository(),
      );

      await groupRepo.saveGroup(group(myRole: GroupRole.member));
      await groupRepo.saveMember(member(selfPeerId, MemberRole.writer));
      await groupRepo.saveMember(member(otherPeerId, MemberRole.admin));
      await seedReplayKey(groupRepo);
      expect(
        (await action.call(groupId)).status,
        LeaveGroupAndDeleteLocalHistoryStatus.leftCleanupIncomplete,
      );

      await groupRepo.saveGroup(group(myRole: GroupRole.member));
      await groupRepo.saveMember(
        member(
          selfPeerId,
          MemberRole.writer,
        ).copyWith(joinedAt: now.add(const Duration(days: 1))),
      );
      await groupRepo.saveMember(
        member(
          otherPeerId,
          MemberRole.admin,
        ).copyWith(joinedAt: now.add(const Duration(days: 1))),
      );
      await seedReplayKey(groupRepo);

      expect(
        (await action.call(groupId)).status,
        LeaveGroupAndDeleteLocalHistoryStatus.left,
      );
      expect(
        bridge.commandLog.where((command) => command == 'group:publish'),
        hasLength(2),
      );
      expect(
        bridge.commandLog.where((command) => command == 'group:leave'),
        hasLength(2),
      );
    },
  );

  test(
    'cleanup retry never deletes a current group with unresolved membership',
    () async {
      final groupRepo = _DeleteGroupFailsOnceRepository();
      final bridge = FakeBridge();
      await groupRepo.saveGroup(group(myRole: GroupRole.member));
      await groupRepo.saveMember(member(selfPeerId, MemberRole.writer));
      await groupRepo.saveMember(member(otherPeerId, MemberRole.admin));
      await seedReplayKey(groupRepo);
      final action = LeaveGroupAndDeleteLocalHistoryUseCase(
        bridge: bridge,
        groupRepo: groupRepo,
        groupMessageRepo: InMemoryGroupMessageRepository(),
        identityRepo: identityRepository(),
      );

      expect(
        (await action.call(groupId)).status,
        LeaveGroupAndDeleteLocalHistoryStatus.leftCleanupIncomplete,
      );
      await groupRepo.saveGroup(
        group(
          myRole: GroupRole.member,
        ).copyWith(lastMembershipEventAt: now.add(const Duration(days: 1))),
      );
      expect(await groupRepo.getMember(groupId, selfPeerId), isNull);

      final retry = await action.call(groupId);
      expect(
        retry.status,
        LeaveGroupAndDeleteLocalHistoryStatus.leftCleanupIncomplete,
      );
      expect(retry.cause.toString(), contains('membership is being resolved'));
      expect(await groupRepo.getGroup(groupId), isNotNull);
      expect(
        bridge.commandLog.where((command) => command == 'group:publish'),
        hasLength(1),
      );
      expect(
        bridge.commandLog.where((command) => command == 'group:leave'),
        hasLength(1),
      );
    },
  );

  test(
    'rapid active exit calls coalesce before publish and native leave',
    () async {
      final groupRepo = InMemoryGroupRepository();
      final messageRepo = InMemoryGroupMessageRepository();
      final bridge = _HangingLeaveBridge();
      await groupRepo.saveGroup(group(myRole: GroupRole.member));
      await groupRepo.saveMember(member(selfPeerId, MemberRole.writer));
      await groupRepo.saveMember(member(otherPeerId, MemberRole.admin));
      await seedReplayKey(groupRepo);
      final action = LeaveGroupAndDeleteLocalHistoryUseCase(
        bridge: bridge,
        groupRepo: groupRepo,
        groupMessageRepo: messageRepo,
        identityRepo: identityRepository(),
      );

      final first = action.call(groupId);
      final second = action.call(groupId);
      expect(identical(first, second), isTrue);
      for (var attempt = 0; attempt < 100; attempt++) {
        if (bridge.commandLog.contains('group:leave')) break;
        await Future<void>.delayed(Duration.zero);
      }
      expect(bridge.commandLog, contains('group:leave'));
      bridge.completeLeave();

      final results = await Future.wait([first, second]);
      expect(
        results.map((result) => result.status),
        everyElement(LeaveGroupAndDeleteLocalHistoryStatus.left),
      );
      expect(
        bridge.commandLog.where((command) => command == 'group:publish'),
        hasLength(1),
      );
      expect(
        bridge.commandLog.where((command) => command == 'group:leave'),
        hasLength(1),
      );
    },
  );

  test(
    'active exit blocks while an exact role transition is pending',
    () async {
      final groupRepo = InMemoryGroupRepository();
      final messageRepo = InMemoryGroupMessageRepository();
      final bridge = FakeBridge();
      await groupRepo.saveGroup(group());
      await groupRepo.saveMember(member(selfPeerId, MemberRole.admin));
      await groupRepo.saveMember(member(otherPeerId, MemberRole.admin));
      await seedReplayKey(groupRepo);
      final pendingRole = GroupPendingBroadcast(
        id: 'pending-role-before-leave',
        groupId: groupId,
        kind: 'member_role_updated',
        sysText: '{}',
        recipientPeerIds: const [otherPeerId],
        eventAt: now,
        sourceMessageId: 'member_role_updated:$groupId:pending',
        createdAt: now,
        updatedAt: now,
      );

      final result = await LeaveGroupAndDeleteLocalHistoryUseCase(
        bridge: bridge,
        groupRepo: groupRepo,
        groupMessageRepo: messageRepo,
        identityRepo: identityRepository(),
        loadPendingBroadcasts: (_) async => [pendingRole],
      ).call(groupId);

      expect(
        result.status,
        LeaveGroupAndDeleteLocalHistoryStatus.preworkFailed,
      );
      expect(result.cause.toString(), contains('finish syncing'));
      expect(await groupRepo.getGroup(groupId), isNotNull);
      expect(bridge.commandLog, isNot(contains('group:publish')));
      expect(bridge.commandLog, isNot(contains('group:leave')));
    },
  );

  test(
    'active exit rechecks pending role sync at the native leave boundary',
    () async {
      final groupRepo = InMemoryGroupRepository();
      final messageRepo = InMemoryGroupMessageRepository();
      final bridge = FakeBridge();
      await groupRepo.saveGroup(group(myRole: GroupRole.member));
      await groupRepo.saveMember(member(selfPeerId, MemberRole.writer));
      await groupRepo.saveMember(member(otherPeerId, MemberRole.admin));
      await seedReplayKey(groupRepo);
      final pendingRole = GroupPendingBroadcast(
        id: 'prepared-role-before-native-leave',
        groupId: groupId,
        kind: groupPendingBroadcastKindMemberRolePrepared,
        sysText: '{}',
        recipientPeerIds: const [otherPeerId],
        eventAt: now,
        sourceMessageId: 'member_role_updated:$groupId:prepared',
        createdAt: now,
        updatedAt: now,
      );
      var pendingReads = 0;

      final result = await LeaveGroupAndDeleteLocalHistoryUseCase(
        bridge: bridge,
        groupRepo: groupRepo,
        groupMessageRepo: messageRepo,
        identityRepo: identityRepository(),
        loadPendingBroadcasts: (_) async {
          pendingReads++;
          return pendingReads == 1 ? const [] : [pendingRole];
        },
      ).call(groupId);

      expect(
        result.status,
        LeaveGroupAndDeleteLocalHistoryStatus.preworkFailed,
      );
      expect(result.cause.toString(), contains('finish syncing'));
      expect(bridge.commandLog, contains('group:publish'));
      expect(bridge.commandLog, contains('group:inboxStore'));
      expect(bridge.commandLog, isNot(contains('group:leave')));
      expect(
        await messageRepo.getLatestSystemEventTimestampForTarget(
          groupId,
          eventType: 'member_removed',
          targetId: selfPeerId,
        ),
        isNull,
      );
    },
  );

  test(
    'last-admin race rolls back its exact tentative leave timeline',
    () async {
      final groupRepo = InMemoryGroupRepository();
      final messageRepo = InMemoryGroupMessageRepository();
      await groupRepo.saveGroup(group());
      await groupRepo.saveMember(member(selfPeerId, MemberRole.admin));
      await groupRepo.saveMember(member(otherPeerId, MemberRole.admin));
      await seedReplayKey(groupRepo);
      final bridge = _AfterFirstSignBridge(() async {
        await groupRepo.updateMemberRole(
          groupId,
          otherPeerId,
          MemberRole.writer,
        );
      });
      bridge.responses['group:generateNextKey'] = {
        'ok': true,
        'groupKey': 'rotated-key-2',
        'keyEpoch': 2,
      };

      final result = await LeaveGroupAndDeleteLocalHistoryUseCase(
        bridge: bridge,
        groupRepo: groupRepo,
        groupMessageRepo: messageRepo,
        identityRepo: identityRepository(),
        sendP2PMessage: (_, _) async => true,
      ).call(groupId);

      expect(
        result.status,
        LeaveGroupAndDeleteLocalHistoryStatus.blockedLastAdmin,
        reason: result.cause?.toString(),
      );
      expect(bridge.commandLog, isNot(contains('group:leave')));
      expect(
        await messageRepo.getLatestSystemEventTimestampForTarget(
          groupId,
          eventType: 'member_removed',
          targetId: selfPeerId,
        ),
        isNull,
      );
    },
  );

  test(
    'leave rollback deletes only its own timeline when a later event arrives',
    () async {
      final groupRepo = InMemoryGroupRepository();
      final messageRepo = _ConcurrentRemovalMessageRepository(
        groupId: groupId,
        peerId: selfPeerId,
      );
      final bridge = FakeBridge();
      bridge.responses['group:leave'] = {'ok': false, 'errorCode': 'REJECTED'};
      await groupRepo.saveGroup(group(myRole: GroupRole.member));
      await groupRepo.saveMember(member(selfPeerId, MemberRole.writer));
      await groupRepo.saveMember(member(otherPeerId, MemberRole.admin));
      await seedReplayKey(groupRepo);

      final result = await LeaveGroupAndDeleteLocalHistoryUseCase(
        bridge: bridge,
        groupRepo: groupRepo,
        groupMessageRepo: messageRepo,
        identityRepo: identityRepository(),
      ).call(groupId);

      expect(
        result.status,
        LeaveGroupAndDeleteLocalHistoryStatus.nativeLeaveFailed,
      );
      expect(messageRepo.tentativeMessageId, isNotNull);
      expect(
        await messageRepo.getMessage(messageRepo.tentativeMessageId!),
        isNull,
      );
      expect(messageRepo.concurrentMessageId, isNotNull);
      expect(
        await messageRepo.getMessage(messageRepo.concurrentMessageId!),
        isNotNull,
      );
    },
  );

  test(
    'snapshot and rollback repository errors remain typed failures',
    () async {
      final snapshotRepo = _SnapshotFailingGroupRepository();
      await snapshotRepo.saveGroup(group(myRole: GroupRole.member));
      await snapshotRepo.saveMember(member(selfPeerId, MemberRole.writer));
      await snapshotRepo.saveMember(member(otherPeerId, MemberRole.admin));
      final snapshotBridge = FakeBridge();
      final snapshotResult = await LeaveGroupAndDeleteLocalHistoryUseCase(
        bridge: snapshotBridge,
        groupRepo: snapshotRepo,
        groupMessageRepo: InMemoryGroupMessageRepository(),
        identityRepo: identityRepository(),
      ).call(groupId);
      expect(
        snapshotResult.status,
        LeaveGroupAndDeleteLocalHistoryStatus.preworkFailed,
      );
      expect(snapshotResult.cause, isA<StateError>());
      expect(snapshotBridge.commandLog, isNot(contains('group:leave')));

      final rollbackRepo = _RollbackFailingGroupRepository();
      final rollbackMessages = InMemoryGroupMessageRepository();
      await rollbackRepo.saveGroup(group(myRole: GroupRole.member));
      await rollbackRepo.saveMember(member(selfPeerId, MemberRole.writer));
      await rollbackRepo.saveMember(member(otherPeerId, MemberRole.admin));
      await seedReplayKey(rollbackRepo);
      final rollbackBridge = FakeBridge();
      rollbackBridge.responses['group:inboxStore'] = {
        'ok': false,
        'errorCode': 'INBOX_FAILED',
      };
      final rollbackResult = await LeaveGroupAndDeleteLocalHistoryUseCase(
        bridge: rollbackBridge,
        groupRepo: rollbackRepo,
        groupMessageRepo: rollbackMessages,
        identityRepo: identityRepository(),
      ).call(groupId);
      expect(
        rollbackResult.status,
        LeaveGroupAndDeleteLocalHistoryStatus.preworkFailed,
      );
      expect(rollbackResult.cause.toString(), contains('rollback also failed'));
      expect(rollbackBridge.commandLog, isNot(contains('group:leave')));
    },
  );
}

void _upsertPending(
  List<GroupPendingBroadcast> pending,
  GroupPendingBroadcast row,
) {
  final roundTripped = GroupPendingBroadcast.fromMap(row.toMap());
  final index = pending.indexWhere(
    (existing) =>
        existing.groupId == row.groupId &&
        existing.sourceMessageId == row.sourceMessageId,
  );
  if (index < 0) {
    pending.add(roundTripped);
  } else {
    pending[index] = roundTripped;
  }
}

class _AfterFirstSignBridge extends FakeBridge {
  _AfterFirstSignBridge(this.afterFirstSign);

  final Future<void> Function() afterFirstSign;
  var _didRun = false;

  @override
  Future<String> send(String message) async {
    final response = await super.send(message);
    final command = (jsonDecode(message) as Map<String, dynamic>)['cmd'];
    if (!_didRun && command == 'payload.sign') {
      _didRun = true;
      await afterFirstSign();
    }
    return response;
  }
}

class _HangingLeaveBridge extends FakeBridge {
  final Completer<String> _leave = Completer<String>();

  @override
  Future<String> send(String message) {
    final command = (jsonDecode(message) as Map<String, dynamic>)['cmd'];
    if (command == 'group:leave') {
      sendCallCount++;
      commandLog.add('group:leave');
      sentMessages.add(message);
      return _leave.future;
    }
    return super.send(message);
  }

  void completeLeave() {
    if (!_leave.isCompleted) _leave.complete(jsonEncode({'ok': true}));
  }
}

class _CleanupFailingGroupRepository extends InMemoryGroupRepository {
  @override
  Future<void> removeAllMembers(String groupId) async {
    throw StateError('forced local cleanup failure');
  }
}

class _CleanupFailsOnceGroupRepository extends InMemoryGroupRepository {
  var _failed = false;

  @override
  Future<void> removeAllMembers(String groupId) async {
    if (!_failed) {
      _failed = true;
      throw StateError('forced one-time local cleanup failure');
    }
    await super.removeAllMembers(groupId);
  }
}

class _DeleteGroupFailsOnceRepository extends InMemoryGroupRepository {
  var _failed = false;

  @override
  Future<void> deleteGroup(String groupId) async {
    if (!_failed) {
      _failed = true;
      throw StateError('forced one-time group deletion failure');
    }
    await super.deleteGroup(groupId);
  }
}

class _ConcurrentRemovalMessageRepository
    extends InMemoryGroupMessageRepository {
  _ConcurrentRemovalMessageRepository({
    required this.groupId,
    required this.peerId,
  });

  final String groupId;
  final String peerId;
  String? tentativeMessageId;
  String? concurrentMessageId;

  @override
  Future<void> saveMessage(GroupMessage message) async {
    await super.saveMessage(message);
    if (tentativeMessageId != null ||
        !message.id.startsWith('sys-member_removed:$groupId:$peerId:')) {
      return;
    }
    tentativeMessageId = message.id;
    final concurrent = buildMemberRemovedTimelineMessage(
      groupId: groupId,
      removedPeerId: peerId,
      removedUsername: peerId,
      senderId: 'peer-concurrent-admin',
      senderUsername: 'Concurrent admin',
      eventAt: message.timestamp.add(const Duration(microseconds: 1)),
    );
    concurrentMessageId = concurrent.id;
    await super.saveMessage(concurrent);
  }
}

class _SnapshotFailingGroupRepository extends InMemoryGroupRepository {
  @override
  Future<GroupKeyInfo?> getLatestKey(String groupId) async {
    throw StateError('forced snapshot failure');
  }
}

class _RollbackFailingGroupRepository extends InMemoryGroupRepository {
  @override
  Future<void> removeAllKeys(String groupId) async {
    throw StateError('forced rollback failure');
  }
}
