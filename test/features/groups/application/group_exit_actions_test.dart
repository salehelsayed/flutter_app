import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/features/groups/application/broadcast_voluntary_leave_use_case.dart';
import 'package:flutter_app/features/groups/application/change_group_member_role_and_broadcast_use_case.dart';
import 'package:flutter_app/features/groups/application/dissolve_group_use_case.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_runner.dart';
import 'package:flutter_app/features/groups/application/group_exit_policy.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_repush.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_runner.dart';
import 'package:flutter_app/features/groups/application/group_sender_device_binding.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/application/update_group_member_role_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_intent.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_intent_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
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

  test('PB264-03 self-only role transition rejects empty recipients', () async {
    final groupRepo = InMemoryGroupRepository();
    final bridge = FakeBridge();
    final identities = identityRepository();
    await groupRepo.saveGroup(group());
    await groupRepo.saveMember(member(selfPeerId, MemberRole.admin));
    await seedReplayKey(groupRepo);

    await expectLater(
      changeGroupMemberRoleAndBroadcast(
        bridge: bridge,
        groupRepo: groupRepo,
        identityRepo: identities,
        groupId: groupId,
        memberPeerId: selfPeerId,
        role: MemberRole.writer,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Role transition requires at least one recipient',
        ),
      ),
    );

    expect(identities.loadIdentityCallCount, 1);
    expect(bridge.commandLog, contains('payload.sign'));
    expect(bridge.commandLog, isNot(contains('group:updateConfig')));
    expect(bridge.commandLog, isNot(contains('group:publish')));
    expect(bridge.commandLog, isNot(contains('group:inboxStore')));
    expect(
      (await groupRepo.getMember(groupId, selfPeerId))?.role,
      MemberRole.admin,
    );
  });

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

  test(
    'PB264-03 native role commit ambiguity retains the exact prepared fence',
    () async {
      Future<void> run({
        required String reason,
        required InMemoryGroupRepository groupRepo,
        required FakeBridge bridge,
      }) async {
        await groupRepo.saveGroup(group());
        await groupRepo.saveMember(member(selfPeerId, MemberRole.admin));
        await groupRepo.saveMember(member(otherPeerId, MemberRole.writer));
        await seedReplayKey(groupRepo);
        final pending = _DissolvePendingBroadcastRepository();
        var removeCalls = 0;

        await expectLater(
          changeGroupMemberRoleAndBroadcast(
            bridge: bridge,
            groupRepo: groupRepo,
            identityRepo: identityRepository(),
            groupId: groupId,
            memberPeerId: otherPeerId,
            role: MemberRole.reader,
            enqueuePending: pending.enqueue,
            loadPending: pending.forGroup,
            removePending: (id) async {
              removeCalls++;
              await pending.remove(id);
            },
          ),
          throwsA(isA<GroupMemberRoleCommitAmbiguous>()),
          reason: reason,
        );

        expect(removeCalls, 0, reason: reason);
        expect(pending.rows, hasLength(1), reason: reason);
        expect(
          pending.rows.single.kind,
          groupPendingBroadcastKindMemberRolePrepared,
          reason: reason,
        );
        expect(
          (await groupRepo.getMember(groupId, otherPeerId))?.role,
          MemberRole.writer,
          reason: reason,
        );
        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          hasLength(1),
          reason: reason,
        );
        expect(bridge.commandLog, isNot(contains('group:publish')));

        final rePush = buildGroupPendingBroadcastRePush(
          bridge: bridge,
          groupRepo: groupRepo,
          loadIdentity: identityRepository().loadIdentity,
          pendingRepository: pending,
        );
        expect(
          await rePush(pending.rows.single),
          isTrue,
          reason: '$reason must converge on retry',
        );
        expect(pending.rows, isEmpty, reason: reason);
        expect(
          (await groupRepo.getMember(groupId, otherPeerId))?.role,
          MemberRole.reader,
          reason: reason,
        );
        expect(
          (await groupRepo.getGroup(groupId))?.lastMembershipEventId,
          isNotNull,
          reason: reason,
        );
        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));
      }

      await run(
        reason: 'native response lost after command was accepted',
        groupRepo: InMemoryGroupRepository(),
        bridge: _CommitUnknownUpdateConfigBridge(),
      );
      await run(
        reason: 'local watermark failed after native success',
        groupRepo: _WatermarkFailingGroupRepository(),
        bridge: FakeBridge(),
      );
    },
  );

  test(
    'PB264-03 role SQL projection failure retains and reconciles an exact self-demotion post-state',
    () async {
      final groupRepo = _RoleProjectionThrowsAfterSqlGroupRepository();
      final bridge = FakeBridge();
      final pending = _DissolvePendingBroadcastRepository();
      await groupRepo.saveGroup(group());
      await groupRepo.saveMember(member(selfPeerId, MemberRole.admin));
      await groupRepo.saveMember(member(otherPeerId, MemberRole.admin));
      await seedReplayKey(groupRepo);

      await expectLater(
        changeGroupMemberRoleAndBroadcast(
          bridge: bridge,
          groupRepo: groupRepo,
          identityRepo: identityRepository(),
          groupId: groupId,
          memberPeerId: selfPeerId,
          role: MemberRole.writer,
          enqueuePending: pending.enqueue,
          loadPending: pending.forGroup,
          removePending: pending.remove,
        ),
        throwsA(isA<GroupMemberRoleCommitAmbiguous>()),
      );

      expect(groupRepo.roleWriteCalls, 2);
      expect(
        (await groupRepo.getMember(groupId, selfPeerId))?.role,
        MemberRole.writer,
        reason: 'member SQL committed before its projection threw',
      );
      expect((await groupRepo.getGroup(groupId))?.myRole, GroupRole.admin);
      expect(pending.rows, hasLength(1));
      expect(
        pending.rows.single.kind,
        groupPendingBroadcastKindMemberRolePrepared,
      );
      expect(bridge.commandLog, isNot(contains('group:updateConfig')));

      final rePush = buildGroupPendingBroadcastRePush(
        bridge: bridge,
        groupRepo: groupRepo,
        loadIdentity: identityRepository().loadIdentity,
        pendingRepository: pending,
      );
      expect(await rePush(pending.rows.single), isTrue);
      expect(pending.rows, isEmpty);
      expect(
        (await groupRepo.getMember(groupId, selfPeerId))?.role,
        MemberRole.writer,
      );
      expect((await groupRepo.getGroup(groupId))?.myRole, GroupRole.member);
      expect(
        (await groupRepo.getGroup(groupId))?.lastMembershipEventId,
        isNotNull,
      );
      expect(
        bridge.commandLog.where((command) => command == 'group:updateConfig'),
        hasLength(1),
      );
      expect(bridge.commandLog, contains('group:publish'));
      expect(bridge.commandLog, contains('group:inboxStore'));
    },
  );

  test(
    'PB264-03 role retries pause before native reconciliation or publish when the signed device binding changed',
    () async {
      GroupMemberDeviceIdentity device(String suffix) =>
          GroupMemberDeviceIdentity(
            deviceId: 'device-$suffix',
            transportPeerId: 'transport-$suffix',
            deviceSigningPublicKey: 'pk-self',
            mlKemPublicKey: 'mlkem-device-$suffix',
            keyPackageId: 'package-$suffix',
          );

      Future<
        ({
          InMemoryGroupRepository groupRepo,
          _DissolvePendingBroadcastRepository pending,
        })
      >
      seeded() async {
        final groupRepo = InMemoryGroupRepository();
        final pending = _DissolvePendingBroadcastRepository();
        await groupRepo.saveGroup(group());
        await groupRepo.saveMember(
          member(
            selfPeerId,
            MemberRole.admin,
          ).copyWith(devices: [device('signed')]),
        );
        await groupRepo.saveMember(member(otherPeerId, MemberRole.writer));
        await seedReplayKey(groupRepo);
        return (groupRepo: groupRepo, pending: pending);
      }

      final prepared = await seeded();
      final ambiguousBridge = _CommitUnknownUpdateConfigBridge();
      await expectLater(
        changeGroupMemberRoleAndBroadcast(
          bridge: ambiguousBridge,
          groupRepo: prepared.groupRepo,
          identityRepo: identityRepository(),
          groupId: groupId,
          memberPeerId: otherPeerId,
          role: MemberRole.reader,
          enqueuePending: prepared.pending.enqueue,
          loadPending: prepared.pending.forGroup,
          removePending: prepared.pending.remove,
        ),
        throwsA(isA<GroupMemberRoleCommitAmbiguous>()),
      );
      final changedPreparedActor = await prepared.groupRepo.getMember(
        groupId,
        selfPeerId,
      );
      await prepared.groupRepo.saveMember(
        changedPreparedActor!.copyWith(devices: [device('replacement')]),
      );
      final updateConfigCallsBefore = ambiguousBridge.commandLog
          .where((command) => command == 'group:updateConfig')
          .length;
      expect(
        await buildGroupPendingBroadcastRePush(
          bridge: ambiguousBridge,
          groupRepo: prepared.groupRepo,
          loadIdentity: identityRepository().loadIdentity,
          pendingRepository: prepared.pending,
        )(prepared.pending.rows.single),
        isFalse,
      );
      expect(
        ambiguousBridge.commandLog
            .where((command) => command == 'group:updateConfig')
            .length,
        updateConfigCallsBefore,
      );
      expect(ambiguousBridge.commandLog, isNot(contains('group:publish')));
      expect(prepared.pending.rows, hasLength(1));

      final committed = await seeded();
      final firstAttemptBridge = FakeBridge();
      firstAttemptBridge.responses['group:publish'] = {
        'ok': false,
        'errorCode': 'BRIDGE_TIMEOUT',
      };
      final result = await changeGroupMemberRoleAndBroadcast(
        bridge: firstAttemptBridge,
        groupRepo: committed.groupRepo,
        identityRepo: identityRepository(),
        groupId: groupId,
        memberPeerId: otherPeerId,
        role: MemberRole.reader,
        enqueuePending: committed.pending.enqueue,
        loadPending: committed.pending.forGroup,
        removePending: committed.pending.remove,
      );
      expect(
        result.outcome,
        ChangeGroupMemberRoleAndBroadcastOutcome.pendingSync,
      );
      expect(
        committed.pending.rows.single.kind,
        groupPendingBroadcastKindMemberRoleUpdated,
      );
      final changedCommittedActor = await committed.groupRepo.getMember(
        groupId,
        selfPeerId,
      );
      await committed.groupRepo.saveMember(
        changedCommittedActor!.copyWith(devices: [device('replacement')]),
      );
      final retryBridge = FakeBridge();
      expect(
        await buildGroupPendingBroadcastRePush(
          bridge: retryBridge,
          groupRepo: committed.groupRepo,
          loadIdentity: identityRepository().loadIdentity,
          pendingRepository: committed.pending,
        )(committed.pending.rows.single),
        isFalse,
      );
      expect(retryBridge.commandLog, isEmpty);
      expect(committed.pending.rows, hasLength(1));
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
    'PB264 voluntary leave prepare preserves caller source and event time',
    () async {
      final groupRepo = InMemoryGroupRepository();
      final bridge = FakeBridge();
      await groupRepo.saveGroup(group(myRole: GroupRole.member));
      await groupRepo.saveMember(member(selfPeerId, MemberRole.writer));
      await groupRepo.saveMember(member(otherPeerId, MemberRole.admin));
      await seedReplayKey(groupRepo);
      const sourceEventId = 'member_removed:stable-source';
      final eventAt = DateTime.utc(2026, 7, 21, 15, 30);

      final first = await prepareVoluntaryLeaveNotice(
        bridge: bridge,
        groupRepo: groupRepo,
        group: group(myRole: GroupRole.member),
        identityRepo: identityRepository(),
        expectedSelfPeerId: selfPeerId,
        sourceEventId: sourceEventId,
        eventAt: eventAt,
      );
      final second = await prepareVoluntaryLeaveNotice(
        bridge: bridge,
        groupRepo: groupRepo,
        group: group(myRole: GroupRole.member),
        identityRepo: identityRepository(),
        expectedSelfPeerId: selfPeerId,
        sourceEventId: sourceEventId,
        eventAt: eventAt,
      );

      expect(first.didPrepare, isTrue);
      expect(second.didPrepare, isTrue);
      final firstNotice = first.prepared!;
      final secondNotice = second.prepared!;
      expect(
        sameExactGroupPendingBroadcast(
          firstNotice.pendingBroadcast,
          secondNotice.pendingBroadcast,
        ),
        isTrue,
      );
      expect(firstNotice.pendingBroadcast.sourceMessageId, sourceEventId);
      expect(
        firstNotice.pendingBroadcast.kind,
        groupPendingBroadcastKindExitLeaveNotice,
      );
      expect(firstNotice.pendingBroadcast.eventAt, eventAt);
      expect(firstNotice.timelineMessage.timestamp, eventAt);
      expect(firstNotice.timelineMessage.id, secondNotice.timelineMessage.id);
      final systemPayload =
          jsonDecode(firstNotice.pendingBroadcast.sysText)
              as Map<String, dynamic>;
      final audit =
          systemPayload['signedTransitionAudit'] as Map<String, dynamic>;
      expect(systemPayload['removedAt'], eventAt.toIso8601String());
      expect(audit['sourceEventId'], sourceEventId);
      expect(audit['eventAt'], eventAt.toIso8601String());
    },
  );

  test(
    'PB264 voluntary leave prepare has no side effects beyond signing',
    () async {
      final groupRepo = InMemoryGroupRepository();
      final bridge = FakeBridge();
      await groupRepo.saveGroup(group(myRole: GroupRole.member));
      await groupRepo.saveMember(member(selfPeerId, MemberRole.writer));
      await groupRepo.saveMember(member(otherPeerId, MemberRole.admin));
      await seedReplayKey(groupRepo);
      final eventAt = DateTime.utc(2026, 7, 21, 15, 31);

      final result = await prepareVoluntaryLeaveNotice(
        bridge: bridge,
        groupRepo: groupRepo,
        group: group(myRole: GroupRole.member),
        identityRepo: identityRepository(),
        expectedSelfPeerId: selfPeerId,
        sourceEventId: 'member_removed:sign-only',
        eventAt: eventAt,
      );

      expect(result.didPrepare, isTrue);
      expect(bridge.commandLog, ['payload.sign']);
      expect(await groupRepo.getGroup(groupId), isNotNull);
      expect(await groupRepo.getMembers(groupId), hasLength(2));
      expect((await groupRepo.getLatestKey(groupId))?.keyGeneration, 1);
      expect(result.prepared!.remainingMembers.map((value) => value.peerId), [
        otherPeerId,
      ]);
      expect(result.prepared!.recipientPeerIds, [otherPeerId]);
    },
  );

  test(
    'PB265 voluntary leave aggregate failure stays aggregate without peer attribution',
    () async {
      const thirdPeerId = 'peer-third';
      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(group(myRole: GroupRole.member));
      await groupRepo.saveMember(member(selfPeerId, MemberRole.writer));
      await groupRepo.saveMember(member(otherPeerId, MemberRole.admin));
      await groupRepo.saveMember(member(thirdPeerId, MemberRole.writer));
      await seedReplayKey(groupRepo);
      final prepareBridge = FakeBridge();
      final preparation = await prepareVoluntaryLeaveNotice(
        bridge: prepareBridge,
        groupRepo: groupRepo,
        group: group(myRole: GroupRole.member),
        identityRepo: identityRepository(),
        expectedSelfPeerId: selfPeerId,
        sourceEventId: 'member_removed:aggregate-only',
        eventAt: DateTime.utc(2026, 7, 21, 15, 32),
      );
      final attemptBridge = FakeBridge();
      attemptBridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'member_removed:aggregate-only',
        'topicPeers': 2,
      };
      attemptBridge.responseSequences['group:inboxStore'] = [
        {'ok': false, 'errorCode': 'AGGREGATE_OFFLINE_STORE_FAILED'},
      ];

      final attempt = await attemptPreparedVoluntaryLeaveNotice(
        bridge: attemptBridge,
        groupRepo: groupRepo,
        prepared: preparation.prepared!,
        expectedSelfPeerId: selfPeerId,
      );

      expect(
        attempt.classification,
        VoluntaryLeaveNoticeAttemptClassification.degraded,
      );
      expect(attempt.livePublishResult?['ok'], isTrue);
      expect(
        attempt.offlineReplayStatus,
        VoluntaryLeaveOfflineReplayStatus.aggregateStoreDegraded,
      );
      expect(
        attemptBridge.commandLog.where(
          (command) => command == 'group:inboxStore',
        ),
        hasLength(1),
      );
      final inboxStorePayloads = attemptBridge.sentMessages
          .map((message) => jsonDecode(message) as Map<String, dynamic>)
          .where((message) => message['cmd'] == 'group:inboxStore')
          .map((message) => message['payload'] as Map<String, dynamic>)
          .toList(growable: false);
      expect(
        inboxStorePayloads.map(
          (payload) => payload['preserveRecipientPeerIds'],
        ),
        everyElement(isTrue),
      );
      final inboxStorePayload = inboxStorePayloads.single;
      expect(inboxStorePayload['recipientPeerIds'], [otherPeerId, thirdPeerId]);
      final replayEnvelope =
          jsonDecode(inboxStorePayload['message'] as String)
              as Map<String, dynamic>;
      expect(replayEnvelope['recipientPeerIds'], [otherPeerId, thirdPeerId]);
      final replaySignedPayload =
          jsonDecode(replayEnvelope['signedPayload'] as String)
              as Map<String, dynamic>;
      final expectedRecipientSetHash = sha256
          .convert(utf8.encode(jsonEncode(<String>[otherPeerId, thirdPeerId])))
          .toString();
      expect(replayEnvelope['recipientSetHash'], expectedRecipientSetHash);
      expect(replaySignedPayload['recipientSetHash'], expectedRecipientSetHash);
      expect(
        attemptBridge.commandLog.where((command) => command == 'group:publish'),
        hasLength(1),
      );
      expect(
        attemptBridge.commandLog,
        isNot(contains('group:generateNextKey')),
      );
    },
  );

  test(
    'PB265 replay encrypt and replay-sign failures degrade without inbox storage',
    () async {
      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(group(myRole: GroupRole.member));
      await groupRepo.saveMember(member(selfPeerId, MemberRole.writer));
      await groupRepo.saveMember(member(otherPeerId, MemberRole.admin));
      await seedReplayKey(groupRepo);
      final preparation = await prepareVoluntaryLeaveNotice(
        bridge: FakeBridge(),
        groupRepo: groupRepo,
        group: group(myRole: GroupRole.member),
        identityRepo: identityRepository(),
        expectedSelfPeerId: selfPeerId,
        sourceEventId: 'member_removed:replay-preparation-faults',
        eventAt: DateTime.utc(2026, 7, 21, 15, 32, 30),
      );

      Future<void> runCase({
        required String label,
        required void Function(FakeBridge bridge) arrange,
      }) async {
        final bridge = FakeBridge();
        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'member_removed:replay-preparation-faults',
          'topicPeers': 1,
        };
        arrange(bridge);

        final attempt = await attemptPreparedVoluntaryLeaveNotice(
          bridge: bridge,
          groupRepo: groupRepo,
          prepared: preparation.prepared!,
          expectedSelfPeerId: selfPeerId,
        );

        expect(
          attempt.classification,
          VoluntaryLeaveNoticeAttemptClassification.degraded,
          reason: label,
        );
        expect(
          attempt.offlineReplayStatus,
          VoluntaryLeaveOfflineReplayStatus.preparationDegraded,
          reason: label,
        );
        expect(
          bridge.commandLog,
          isNot(contains('group:inboxStore')),
          reason: label,
        );
      }

      await runCase(
        label: 'group.encrypt returned non-ok',
        arrange: (bridge) {
          bridge.responses['group.encrypt'] = {
            'ok': false,
            'errorCode': 'GROUP_ENCRYPT_FAILED',
          };
        },
      );
      await runCase(
        label: 'replay payload.sign returned non-ok',
        arrange: (bridge) {
          bridge.responses['payload.sign'] = {
            'ok': true,
            'signature': 'unused-fallback-signature',
          };
          bridge.responseSequences['payload.sign'] = [
            {'ok': true, 'signature': 'key-pair-proof-signature'},
            {'ok': false, 'errorCode': 'REPLAY_SIGN_FAILED'},
          ];
        },
      );
    },
  );

  test('PB265 replay preparation exception classification is opt-in', () async {
    final groupRepo = InMemoryGroupRepository();
    await groupRepo.saveGroup(group(myRole: GroupRole.member));
    await seedReplayKey(groupRepo);

    Future<String> build({required bool classify}) {
      final bridge = FakeBridge();
      bridge.responses['group.encrypt'] = {
        'ok': false,
        'errorCode': 'GROUP_ENCRYPT_FAILED',
      };
      return buildGroupOfflineReplayEnvelope(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        payloadType: groupOfflineReplayPayloadTypeMessage,
        plaintext: '{}',
        senderPeerId: selfPeerId,
        senderPublicKey: 'pk-$selfPeerId',
        senderPrivateKey: 'sk-$selfPeerId',
        recipientPeerIds: const [otherPeerId],
        classifyPreparationCryptoFailures: classify,
      );
    }

    await expectLater(
      build(classify: false),
      throwsA(isA<BridgeCommandException>()),
    );
    await expectLater(
      build(classify: true),
      throwsA(
        isA<GroupOfflineReplayPreparationException>().having(
          (error) => error.operation,
          'operation',
          GroupOfflineReplayPreparationOperation.groupEncrypt,
        ),
      ),
    );
  });

  test(
    'PB265 nonempty live delivery requires ok and positive numeric topic peers',
    () async {
      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(group(myRole: GroupRole.member));
      await groupRepo.saveMember(member(selfPeerId, MemberRole.writer));
      await groupRepo.saveMember(member(otherPeerId, MemberRole.admin));
      await seedReplayKey(groupRepo);
      final preparation = await prepareVoluntaryLeaveNotice(
        bridge: FakeBridge(),
        groupRepo: groupRepo,
        group: group(myRole: GroupRole.member),
        identityRepo: identityRepository(),
        expectedSelfPeerId: selfPeerId,
        sourceEventId: 'member_removed:live-topic-peers',
        eventAt: DateTime.utc(2026, 7, 21, 15, 32, 45),
      );
      final cases =
          <
            ({
              String label,
              Map<String, dynamic> response,
              VoluntaryLeaveNoticeAttemptClassification expected,
            })
          >[
            (
              label: 'positive numeric peers',
              response: {'ok': true, 'topicPeers': 1},
              expected: VoluntaryLeaveNoticeAttemptClassification.delivered,
            ),
            (
              label: 'zero peers',
              response: {'ok': true, 'topicPeers': 0},
              expected: VoluntaryLeaveNoticeAttemptClassification.degraded,
            ),
            (
              label: 'missing peers',
              response: {'ok': true},
              expected: VoluntaryLeaveNoticeAttemptClassification.degraded,
            ),
            (
              label: 'negative peers',
              response: {'ok': true, 'topicPeers': -1},
              expected: VoluntaryLeaveNoticeAttemptClassification.degraded,
            ),
            (
              label: 'malformed peers',
              response: {'ok': true, 'topicPeers': '1'},
              expected: VoluntaryLeaveNoticeAttemptClassification.degraded,
            ),
            (
              label: 'non-ok with peers',
              response: {'ok': false, 'topicPeers': 1},
              expected: VoluntaryLeaveNoticeAttemptClassification.degraded,
            ),
          ];

      for (final testCase in cases) {
        final bridge = FakeBridge();
        bridge.responses['group:publish'] = testCase.response;

        final attempt = await attemptPreparedVoluntaryLeaveNotice(
          bridge: bridge,
          groupRepo: groupRepo,
          prepared: preparation.prepared!,
          expectedSelfPeerId: selfPeerId,
        );

        expect(
          attempt.classification,
          testCase.expected,
          reason: testCase.label,
        );
        expect(
          attempt.offlineReplayStatus,
          VoluntaryLeaveOfflineReplayStatus.aggregateAccepted,
          reason: testCase.label,
        );
      }
    },
  );

  test(
    'PB264-09 persisted leave recipients survive roster drift during restart attempt',
    () async {
      const departedPeerId = 'peer-departed-after-prepare';
      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(group(myRole: GroupRole.member));
      await groupRepo.saveMember(member(selfPeerId, MemberRole.writer));
      await groupRepo.saveMember(member(otherPeerId, MemberRole.admin));
      await groupRepo.saveMember(member(departedPeerId, MemberRole.writer));
      await seedReplayKey(groupRepo);
      final preparation = await prepareVoluntaryLeaveNotice(
        bridge: FakeBridge(),
        groupRepo: groupRepo,
        group: group(myRole: GroupRole.member),
        identityRepo: identityRepository(),
        expectedSelfPeerId: selfPeerId,
        sourceEventId: 'member_removed:restart-roster-drift',
        eventAt: DateTime.utc(2026, 7, 21, 15, 33),
      );
      final persisted = preparation.prepared!;
      await groupRepo.removeMember(groupId, departedPeerId);
      final currentRemaining = (await groupRepo.getMembers(
        groupId,
      )).where((member) => member.peerId != selfPeerId).toList(growable: false);
      final restarted = PreparedVoluntaryLeaveNotice(
        pendingBroadcast: persisted.pendingBroadcast,
        timelineMessage: persisted.timelineMessage,
        identity: persisted.identity,
        senderBinding: persisted.senderBinding,
        remainingMembers: currentRemaining,
      );
      final attemptBridge = FakeBridge();
      attemptBridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'member_removed:restart-roster-drift',
        'topicPeers': 2,
      };

      final attempt = await attemptPreparedVoluntaryLeaveNotice(
        bridge: attemptBridge,
        groupRepo: groupRepo,
        prepared: restarted,
        expectedSelfPeerId: selfPeerId,
      );

      expect(attempt.canAdvance, isTrue);
      expect(
        attempt.offlineReplayStatus,
        VoluntaryLeaveOfflineReplayStatus.aggregateAccepted,
      );
      final inboxStore = attemptBridge.sentMessages
          .map((message) => jsonDecode(message) as Map<String, dynamic>)
          .singleWhere((message) => message['cmd'] == 'group:inboxStore');
      expect(
        (inboxStore['payload'] as Map<String, dynamic>)['recipientPeerIds'],
        [departedPeerId, otherPeerId],
      );
    },
  );

  test(
    'PB264-09 restart pauses an immutable leave notice when actor credentials changed',
    () async {
      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(group(myRole: GroupRole.member));
      await groupRepo.saveMember(member(selfPeerId, MemberRole.writer));
      await groupRepo.saveMember(member(otherPeerId, MemberRole.admin));
      await seedReplayKey(groupRepo);
      final preparation = await prepareVoluntaryLeaveNotice(
        bridge: FakeBridge(),
        groupRepo: groupRepo,
        group: group(myRole: GroupRole.member),
        identityRepo: identityRepository(),
        expectedSelfPeerId: selfPeerId,
        sourceEventId: 'member_removed:restart-actor-binding',
        eventAt: DateTime.utc(2026, 7, 21, 15, 34),
      );
      final persisted = preparation.prepared!;
      final original = persisted.identity;
      final changedIdentity = IdentityModel(
        peerId: original.peerId,
        publicKey: 'pk-replaced-after-prepare',
        privateKey: 'sk-replaced-after-prepare',
        mnemonic12: original.mnemonic12,
        mlKemPublicKey: original.mlKemPublicKey,
        mlKemSecretKey: original.mlKemSecretKey,
        username: 'Renamed after prepare',
        createdAt: original.createdAt,
        updatedAt: DateTime.utc(2026, 7, 21, 15, 35).toIso8601String(),
      );
      final restarted = PreparedVoluntaryLeaveNotice(
        pendingBroadcast: persisted.pendingBroadcast,
        timelineMessage: persisted.timelineMessage,
        identity: changedIdentity,
        senderBinding: const GroupSenderDeviceBinding(
          deviceId: 'device-replaced',
          transportPeerId: 'transport-replaced',
          devicePublicKey: 'device-pk-replaced',
          keyPackageId: 'package-replaced',
        ),
        remainingMembers: persisted.remainingMembers,
      );
      final intent = GroupExitIntent(
        groupId: groupId,
        intentId: 'restart-actor-binding-intent',
        selfPeerId: selfPeerId,
        selfJoinedAt: now,
        state: GroupExitIntentState.leaveNoticePending,
        pendingBroadcastId: persisted.pendingBroadcast.id,
        sourceEventId: persisted.pendingBroadcast.sourceMessageId,
        eventAt: persisted.pendingBroadcast.eventAt,
        createdAt: now,
        updatedAt: now,
      );
      final intentRepo = _DissolveExitIntentRepository(intent);
      final pendingRepo = _DissolvePendingBroadcastRepository([
        persisted.pendingBroadcast,
      ]);
      final attemptBridge = FakeBridge();
      var rotations = 0;
      var nativeLeaves = 0;
      final runner = GroupExitIntentRunner(
        intentRepository: intentRepo,
        pendingRepository: pendingRepo,
        pendingBroadcastRunner: GroupPendingBroadcastRunner(
          repository: pendingRepo,
          rePush: (_) async => true,
        ),
        groupRepository: groupRepo,
        loadCurrentSelfPeerId: () async => selfPeerId,
        prepareNotice:
            ({
              required intent,
              required sourceEventId,
              required eventAt,
            }) async => throw StateError('must reuse the durable notice'),
        attemptNotice: ({required intent, required pendingBroadcast}) async {
          final attempt = await attemptPreparedVoluntaryLeaveNotice(
            bridge: attemptBridge,
            groupRepo: groupRepo,
            prepared: restarted,
            expectedSelfPeerId: selfPeerId,
          );
          return attempt.canAdvance
              ? GroupExitNoticeAttemptDisposition.delivered
              : GroupExitNoticeAttemptDisposition.retryable;
        },
        rotateKeys: (_) async => rotations++,
        nativeLeave: (_) async => nativeLeaves++,
      );

      final result = await runner.processGroup(
        groupId,
        drainRoleBroadcasts: false,
      );

      expect(result.status, GroupExitIntentProcessStatus.waitingForNoticeRetry);
      expect(intentRepo.current, same(intent));
      expect(pendingRepo.rows, hasLength(1));
      expect(
        sameExactGroupPendingBroadcast(
          pendingRepo.rows.single,
          persisted.pendingBroadcast,
        ),
        isTrue,
      );
      expect(attemptBridge.commandLog, isEmpty);
      expect(rotations, 0);
      expect(nativeLeaves, 0);
    },
  );

  test(
    'PB264-09 invalid leave audit or mismatched private key keeps the runner fenced before group network',
    () async {
      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(group(myRole: GroupRole.member));
      await groupRepo.saveMember(member(selfPeerId, MemberRole.writer));
      await groupRepo.saveMember(member(otherPeerId, MemberRole.admin));
      await seedReplayKey(groupRepo);
      final preparation = await prepareVoluntaryLeaveNotice(
        bridge: FakeBridge(),
        groupRepo: groupRepo,
        group: group(myRole: GroupRole.member),
        identityRepo: identityRepository(),
        expectedSelfPeerId: selfPeerId,
        sourceEventId: 'member_removed:cryptographic-restart',
        eventAt: DateTime.utc(2026, 7, 21, 15, 36),
      );
      final persisted = preparation.prepared!;

      GroupPendingBroadcast withSysText(String sysText) =>
          GroupPendingBroadcast(
            id: persisted.pendingBroadcast.id,
            groupId: persisted.pendingBroadcast.groupId,
            kind: persisted.pendingBroadcast.kind,
            sysText: sysText,
            recipientPeerIds: persisted.pendingBroadcast.recipientPeerIds,
            eventAt: persisted.pendingBroadcast.eventAt,
            sourceMessageId: persisted.pendingBroadcast.sourceMessageId,
            createdAt: persisted.pendingBroadcast.createdAt,
            updatedAt: persisted.pendingBroadcast.updatedAt,
          );

      final tamperedPayload =
          jsonDecode(persisted.pendingBroadcast.sysText)
              as Map<String, dynamic>;
      final tamperedAudit = Map<String, dynamic>.from(
        tamperedPayload[signedGroupTransitionAuditField]
            as Map<String, dynamic>,
      )..['signature'] = 'tampered-signature';
      tamperedPayload[signedGroupTransitionAuditField] = tamperedAudit;
      final tamperedPending = withSysText(jsonEncode(tamperedPayload));
      final originalIdentity = persisted.identity;
      final wrongPrivateKeyIdentity = IdentityModel(
        peerId: originalIdentity.peerId,
        publicKey: originalIdentity.publicKey,
        privateKey: 'sk-does-not-match-public-key',
        mnemonic12: originalIdentity.mnemonic12,
        mlKemPublicKey: originalIdentity.mlKemPublicKey,
        mlKemSecretKey: originalIdentity.mlKemSecretKey,
        username: originalIdentity.username,
        createdAt: originalIdentity.createdAt,
        updatedAt: originalIdentity.updatedAt,
      );

      Future<void> runCase({
        required String reason,
        required GroupPendingBroadcast pendingBroadcast,
        required IdentityModel identity,
      }) async {
        final intent = GroupExitIntent(
          groupId: groupId,
          intentId: 'cryptographic-restart-$reason',
          selfPeerId: selfPeerId,
          selfJoinedAt: now,
          state: GroupExitIntentState.leaveNoticePending,
          pendingBroadcastId: pendingBroadcast.id,
          sourceEventId: pendingBroadcast.sourceMessageId,
          eventAt: pendingBroadcast.eventAt,
          createdAt: now,
          updatedAt: now,
        );
        final intentRepo = _DissolveExitIntentRepository(intent);
        final pendingRepo = _DissolvePendingBroadcastRepository([
          pendingBroadcast,
        ]);
        final bridge = _LeaveNoticeCryptographicProofBridge();
        var rotations = 0;
        var nativeLeaves = 0;
        final restarted = PreparedVoluntaryLeaveNotice(
          pendingBroadcast: pendingBroadcast,
          timelineMessage: persisted.timelineMessage,
          identity: identity,
          senderBinding: persisted.senderBinding,
          remainingMembers: persisted.remainingMembers,
        );
        final runner = GroupExitIntentRunner(
          intentRepository: intentRepo,
          pendingRepository: pendingRepo,
          pendingBroadcastRunner: GroupPendingBroadcastRunner(
            repository: pendingRepo,
            rePush: (_) async => true,
          ),
          groupRepository: groupRepo,
          loadCurrentSelfPeerId: () async => selfPeerId,
          prepareNotice:
              ({
                required intent,
                required sourceEventId,
                required eventAt,
              }) async => throw StateError('must reuse the durable notice'),
          attemptNotice: ({required intent, required pendingBroadcast}) async {
            final attempt = await attemptPreparedVoluntaryLeaveNotice(
              bridge: bridge,
              groupRepo: groupRepo,
              prepared: restarted,
              expectedSelfPeerId: selfPeerId,
            );
            return attempt.canAdvance
                ? GroupExitNoticeAttemptDisposition.delivered
                : GroupExitNoticeAttemptDisposition.retryable;
          },
          rotateKeys: (_) async => rotations++,
          nativeLeave: (_) async => nativeLeaves++,
        );

        final result = await runner.processGroup(
          groupId,
          drainRoleBroadcasts: false,
        );

        expect(
          result.status,
          GroupExitIntentProcessStatus.waitingForNoticeRetry,
          reason: reason,
        );
        expect(intentRepo.current, same(intent), reason: reason);
        expect(pendingRepo.rows, [pendingBroadcast], reason: reason);
        expect(
          bridge.commandLog.where(
            (command) =>
                command == 'group:publish' ||
                command == 'group:inboxStore' ||
                command == 'group:leave',
          ),
          isEmpty,
          reason: reason,
        );
        expect(rotations, 0, reason: reason);
        expect(nativeLeaves, 0, reason: reason);
      }

      await runCase(
        reason: 'tampered-audit',
        pendingBroadcast: tamperedPending,
        identity: originalIdentity,
      );
      await runCase(
        reason: 'mismatched-private-key',
        pendingBroadcast: persisted.pendingBroadcast,
        identity: wrongPrivateKeyIdentity,
      );
    },
  );

  test(
    'PB264-19 separate Dissolve cannot bypass queued intent or pending role',
    () async {
      Future<
        ({
          FakeBridge bridge,
          InMemoryGroupRepository groupRepo,
          InMemoryGroupMessageRepository messageRepo,
        })
      >
      seeded() async {
        final bridge = FakeBridge();
        final groupRepo = InMemoryGroupRepository();
        final messageRepo = InMemoryGroupMessageRepository();
        await groupRepo.saveGroup(group());
        await groupRepo.saveMember(member(selfPeerId, MemberRole.admin));
        await groupRepo.saveMember(member(otherPeerId, MemberRole.writer));
        await seedReplayKey(groupRepo);
        return (bridge: bridge, groupRepo: groupRepo, messageRepo: messageRepo);
      }

      Future<DissolveGroupResult> dissolve(
        ({
          FakeBridge bridge,
          InMemoryGroupRepository groupRepo,
          InMemoryGroupMessageRepository messageRepo,
        })
        fixture, {
        required _DissolveExitIntentRepository intents,
        required _DissolvePendingBroadcastRepository pending,
      }) async {
        final (result, _) = await dissolveGroup(
          bridge: fixture.bridge,
          groupRepo: fixture.groupRepo,
          msgRepo: fixture.messageRepo,
          preflightAuthority: GroupDissolvePreflightAuthority(
            intentRepository: intents,
            pendingRepository: pending,
          ),
          groupId: groupId,
          actorPeerId: selfPeerId,
          actorUsername: selfPeerId,
          actorPublicKey: 'pk-self',
          actorPrivateKey: 'sk-self',
          dissolvedAt: now.add(const Duration(hours: 1)),
        );
        return result;
      }

      for (final state in [
        GroupExitIntentState.queued,
        GroupExitIntentState.leaveNoticePending,
      ]) {
        final fixture = await seeded();
        final expected = _exitIntent(groupId, selfPeerId, now, state);
        final intents = _DissolveExitIntentRepository(expected);
        final result = await dissolve(
          fixture,
          intents: intents,
          pending: _DissolvePendingBroadcastRepository(),
        );

        expect(result, DissolveGroupResult.exitWorkPending, reason: state.name);
        expect(intents.current, same(expected));
        expect(
          (await fixture.groupRepo.getGroup(groupId))!.isDissolved,
          isFalse,
        );
        expect(fixture.bridge.commandLog, isEmpty);
      }

      for (final kind in [
        groupPendingBroadcastKindMemberRoleUpdated,
        groupPendingBroadcastKindMemberRolePrepared,
      ]) {
        final fixture = await seeded();
        final pending = _DissolvePendingBroadcastRepository([
          _pendingBroadcast(groupId, now, kind),
        ]);
        final result = await dissolve(
          fixture,
          intents: _DissolveExitIntentRepository(),
          pending: pending,
        );

        expect(result, DissolveGroupResult.exitWorkPending, reason: kind);
        expect(pending.rows, hasLength(1));
        expect(
          (await fixture.groupRepo.getGroup(groupId))!.isDissolved,
          isFalse,
        );
        expect(fixture.bridge.commandLog, isEmpty);
      }

      final cancelledFixture = await seeded();
      final queued = _exitIntent(
        groupId,
        selfPeerId,
        now,
        GroupExitIntentState.queued,
      );
      final cancelledIntents = _DissolveExitIntentRepository(queued);
      final pendingRole = _DissolvePendingBroadcastRepository([
        _pendingBroadcast(
          groupId,
          now,
          groupPendingBroadcastKindMemberRoleUpdated,
        ),
      ]);
      final cancellation = await cancelledIntents.cancelQueued(
        queued,
        updatedAt: now.add(const Duration(minutes: 1)),
      );
      expect(cancellation.committed, isTrue);
      expect(cancelledIntents.current, isNull);
      expect(
        await dissolve(
          cancelledFixture,
          intents: cancelledIntents,
          pending: pendingRole,
        ),
        DissolveGroupResult.exitWorkPending,
      );
      expect(pendingRole.rows, hasLength(1));
      expect(cancelledFixture.bridge.commandLog, isEmpty);

      final clearFixture = await seeded();
      final metadata = _DissolvePendingBroadcastRepository([
        _pendingBroadcast(groupId, now, 'group_metadata_updated'),
      ]);
      expect(
        await dissolve(
          clearFixture,
          intents: _DissolveExitIntentRepository(),
          pending: metadata,
        ),
        DissolveGroupResult.success,
      );
      expect(
        (await clearFixture.groupRepo.getGroup(groupId))!.isDissolved,
        isTrue,
      );
      for (final command in [
        'group:publish',
        'group:inboxStore',
        'group:leave',
      ]) {
        expect(
          clearFixture.bridge.commandLog.where((value) => value == command),
          hasLength(1),
          reason: command,
        );
      }
    },
  );

  test(
    'PB264-19 Dissolve propagates preflight storage and classification errors',
    () async {
      Future<void> expectFailure({
        required _DissolveExitIntentRepository intents,
        required _DissolvePendingBroadcastRepository pending,
        required Object error,
        bool Function(String kind)? classifier,
      }) async {
        final bridge = FakeBridge();
        final groupRepo = InMemoryGroupRepository();
        final messageRepo = InMemoryGroupMessageRepository();
        await groupRepo.saveGroup(group());
        await groupRepo.saveMember(member(selfPeerId, MemberRole.admin));
        await groupRepo.saveMember(member(otherPeerId, MemberRole.writer));
        await seedReplayKey(groupRepo);

        await expectLater(
          dissolveGroup(
            bridge: bridge,
            groupRepo: groupRepo,
            msgRepo: messageRepo,
            preflightAuthority: GroupDissolvePreflightAuthority(
              intentRepository: intents,
              pendingRepository: pending,
              isRoleBroadcastKind:
                  classifier ?? isPendingGroupMemberRoleBroadcastKind,
            ),
            groupId: groupId,
            actorPeerId: selfPeerId,
            actorUsername: selfPeerId,
            actorPublicKey: 'pk-self',
            actorPrivateKey: 'sk-self',
          ),
          throwsA(same(error)),
        );
        expect((await groupRepo.getGroup(groupId))!.isDissolved, isFalse);
        expect(bridge.commandLog, isEmpty);
      }

      final intentStorageError = StateError('exit intent storage unavailable');
      await expectFailure(
        intents: _DissolveExitIntentRepository()
          ..loadError = intentStorageError,
        pending: _DissolvePendingBroadcastRepository(),
        error: intentStorageError,
      );

      final pendingStorageError = StateError('pending storage unavailable');
      await expectFailure(
        intents: _DissolveExitIntentRepository(),
        pending: _DissolvePendingBroadcastRepository()
          ..loadError = pendingStorageError,
        error: pendingStorageError,
      );

      final classificationError = FormatException('invalid pending kind');
      await expectFailure(
        intents: _DissolveExitIntentRepository(),
        pending: _DissolvePendingBroadcastRepository([
          _pendingBroadcast(groupId, now, 'unclassifiable-kind'),
        ]),
        error: classificationError,
        classifier: (_) => throw classificationError,
      );
    },
  );

  test(
    'PB264-09 notice preparation trusts exact self-admin row over stale projection',
    () async {
      final groupRepo = InMemoryGroupRepository();
      final projected = group(myRole: GroupRole.member);
      await groupRepo.saveGroup(projected);
      await groupRepo.saveMember(member(selfPeerId, MemberRole.admin));
      await groupRepo.saveMember(member(otherPeerId, MemberRole.writer));
      final bridge = FakeBridge();

      final result = await prepareVoluntaryLeaveNotice(
        bridge: bridge,
        groupRepo: groupRepo,
        group: projected,
        identityRepo: identityRepository(),
        expectedSelfPeerId: selfPeerId,
        sourceEventId: 'member_removed:stale-role-projection',
        eventAt: now,
      );

      expect(result.skipReason, VoluntaryLeaveBroadcastSkipReason.lastAdmin);
      expect(result.prepared, isNull);
      expect(bridge.commandLog, isEmpty);
    },
  );

  test(
    'PB264-19 Dissolve rechecks intent and role authority in its final membership phase',
    () async {
      Future<void> runRace({required bool insertIntent}) async {
        final groupRepo = InMemoryGroupRepository();
        final messageRepo = InMemoryGroupMessageRepository();
        final intents = _DissolveExitIntentRepository();
        final pending = _DissolvePendingBroadcastRepository();
        await groupRepo.saveGroup(group());
        await groupRepo.saveMember(member(selfPeerId, MemberRole.admin));
        await groupRepo.saveMember(member(otherPeerId, MemberRole.writer));
        await seedReplayKey(groupRepo);

        final bridge = _AfterFirstSignBridge(() async {
          if (insertIntent) {
            intents.current = _exitIntent(
              groupId,
              selfPeerId,
              now,
              GroupExitIntentState.queued,
            );
          } else {
            pending.rows.add(
              _pendingBroadcast(
                groupId,
                now,
                groupPendingBroadcastKindMemberRoleUpdated,
              ),
            );
          }
        });

        final (result, returnedGroup) = await dissolveGroup(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: messageRepo,
          preflightAuthority: GroupDissolvePreflightAuthority(
            intentRepository: intents,
            pendingRepository: pending,
          ),
          groupId: groupId,
          actorPeerId: selfPeerId,
          actorUsername: selfPeerId,
          actorPublicKey: 'pk-self',
          actorPrivateKey: 'sk-self',
          dissolvedAt: now.add(const Duration(hours: 1)),
        );

        expect(result, DissolveGroupResult.exitWorkPending);
        expect(returnedGroup?.isDissolved, isFalse);
        expect((await groupRepo.getGroup(groupId))?.isDissolved, isFalse);
        expect(
          bridge.commandLog,
          isNot(anyOf(contains('group:publish'), contains('group:leave'))),
        );
        expect(bridge.commandLog, isNot(contains('group:inboxStore')));
      }

      await runRace(insertIntent: true);
      await runRace(insertIntent: false);
    },
  );

  test(
    'PB264-19 Dissolve refuses a role transition that fully converges while signing',
    () async {
      final groupRepo = InMemoryGroupRepository();
      final messageRepo = InMemoryGroupMessageRepository();
      final pending = _DissolvePendingBroadcastRepository();
      await groupRepo.saveGroup(group());
      await groupRepo.saveMember(member(selfPeerId, MemberRole.admin));
      await groupRepo.saveMember(member(otherPeerId, MemberRole.admin));
      await seedReplayKey(groupRepo);

      final roleBridge = FakeBridge();
      DateTime? committedRoleAt;
      final dissolveBridge = _AfterFirstSignBridge(() async {
        final roleResult = await changeGroupMemberRoleAndBroadcast(
          bridge: roleBridge,
          groupRepo: groupRepo,
          identityRepo: identityRepository(),
          groupId: groupId,
          memberPeerId: selfPeerId,
          role: MemberRole.writer,
          enqueuePending: (row) async => _upsertPending(pending.rows, row),
          loadPending: pending.forGroup,
          removePending: (id) async =>
              pending.rows.removeWhere((row) => row.id == id),
        );
        expect(
          roleResult.outcome,
          ChangeGroupMemberRoleAndBroadcastOutcome.readyToLeave,
        );
        committedRoleAt = roleResult.eventAt;
      });

      final (result, returnedGroup) = await dissolveGroup(
        bridge: dissolveBridge,
        groupRepo: groupRepo,
        msgRepo: messageRepo,
        preflightAuthority: GroupDissolvePreflightAuthority(
          intentRepository: _DissolveExitIntentRepository(),
          pendingRepository: pending,
        ),
        groupId: groupId,
        actorPeerId: selfPeerId,
        actorUsername: selfPeerId,
        actorPublicKey: 'pk-self',
        actorPrivateKey: 'sk-self',
        dissolvedAt: now.add(const Duration(hours: 1)),
      );

      expect(result, DissolveGroupResult.unauthorized);
      expect(returnedGroup?.isDissolved, isFalse);
      expect(returnedGroup?.myRole, GroupRole.member);
      expect(pending.rows, isEmpty);
      final stored = await groupRepo.getGroup(groupId);
      expect(stored?.isDissolved, isFalse);
      expect(stored?.myRole, GroupRole.member);
      expect(stored?.lastMembershipEventAt, committedRoleAt);
      expect(
        (await groupRepo.getMember(groupId, selfPeerId))?.role,
        MemberRole.writer,
      );
      expect(dissolveBridge.commandLog, contains('payload.sign'));
      expect(dissolveBridge.commandLog, isNot(contains('group:publish')));
      expect(dissolveBridge.commandLog, isNot(contains('group:inboxStore')));
      expect(dissolveBridge.commandLog, isNot(contains('group:leave')));
    },
  );

  test(
    'PB264-19 exit and role claims cannot commit after final Dissolve preflight',
    () async {
      final groupRepo = _DissolvePublishBarrierGroupRepository();
      final messageRepo = InMemoryGroupMessageRepository();
      final intents = _DissolveExitIntentRepository();
      final pending = _DissolvePendingBroadcastRepository();
      await groupRepo.saveGroup(group());
      await groupRepo.saveMember(member(selfPeerId, MemberRole.admin));
      await groupRepo.saveMember(member(otherPeerId, MemberRole.admin));
      await seedReplayKey(groupRepo);
      final authority = _BarrierDissolvePreflightAuthority(
        intentRepository: intents,
        pendingRepository: pending,
        groupRepository: groupRepo,
      );
      final dissolveBridge = FakeBridge();

      final dissolveFuture = dissolveGroup(
        bridge: dissolveBridge,
        groupRepo: groupRepo,
        msgRepo: messageRepo,
        preflightAuthority: authority,
        groupId: groupId,
        actorPeerId: selfPeerId,
        actorUsername: selfPeerId,
        actorPublicKey: 'pk-self',
        actorPrivateKey: 'sk-self',
        dissolvedAt: now.add(const Duration(hours: 1)),
      );
      await groupRepo.finalPublishReadEntered.future.timeout(
        const Duration(seconds: 2),
      );
      expect(authority.evaluations, 2);
      expect(dissolveBridge.commandLog, isNot(contains('group:publish')));

      final coordinator = GroupExitIntentCoordinator(
        intentRepository: intents,
        pendingRepository: pending,
        pendingBroadcastRunner: GroupPendingBroadcastRunner(
          repository: pending,
          rePush: (_) async => true,
        ),
        processor: const _NoopGroupExitIntentProcessor(),
        groupRepository: groupRepo,
        identityRepository: identityRepository(),
        newId: () => 'race-id',
        now: () => now,
      );
      final exitClaim = coordinator.queueLeaveWhenSyncCompletes(groupId);

      final roleSigned = Completer<void>();
      final roleBridge = _AfterFirstSignBridge(() async {
        if (!roleSigned.isCompleted) roleSigned.complete();
      });
      final roleClaim = expectLater(
        changeGroupMemberRoleAndBroadcast(
          bridge: roleBridge,
          groupRepo: groupRepo,
          identityRepo: identityRepository(),
          groupId: groupId,
          memberPeerId: otherPeerId,
          role: MemberRole.reader,
          enqueuePending: (row) async => pending.rows.add(row),
          loadPending: pending.forGroup,
          removePending: (id) async =>
              pending.rows.removeWhere((row) => row.id == id),
        ),
        throwsA(isA<StateError>()),
      );
      await roleSigned.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);
      expect(intents.current, isNull);
      expect(pending.rows, isEmpty);

      groupRepo.releaseFinalPublishRead();
      final (dissolveResult, _) = await dissolveFuture;
      expect(dissolveResult, DissolveGroupResult.success);
      expect((await groupRepo.getGroup(groupId))?.isDissolved, isTrue);

      final exitResult = await exitClaim;
      expect(exitResult.status, GroupExitIntentRequestStatus.noOp);
      expect(intents.current, isNull);
      await roleClaim;
      expect(pending.rows, isEmpty);
      expect(roleBridge.commandLog, isNot(contains('group:updateConfig')));
      expect(roleBridge.commandLog, isNot(contains('group:publish')));
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

GroupExitIntent _exitIntent(
  String groupId,
  String selfPeerId,
  DateTime now,
  GroupExitIntentState state,
) {
  final hasNotice = state.hasLeaveNoticeIdentity;
  return GroupExitIntent(
    groupId: groupId,
    intentId: 'exit-intent-${state.databaseValue}',
    selfPeerId: selfPeerId,
    selfJoinedAt: now,
    state: state,
    pendingBroadcastId: 'exit-notice-${state.databaseValue}',
    sourceEventId: hasNotice ? 'exit-source-${state.databaseValue}' : null,
    eventAt: hasNotice ? now.add(const Duration(minutes: 1)) : null,
    createdAt: now,
    updatedAt: now,
  );
}

GroupPendingBroadcast _pendingBroadcast(
  String groupId,
  DateTime now,
  String kind,
) => GroupPendingBroadcast(
  id: 'pending-$kind',
  groupId: groupId,
  kind: kind,
  sysText: '{}',
  recipientPeerIds: const ['peer-other'],
  eventAt: now,
  sourceMessageId: 'source-$kind',
  createdAt: now,
  updatedAt: now,
);

class _DissolveExitIntentRepository implements GroupExitIntentRepository {
  _DissolveExitIntentRepository([this.current]);

  GroupExitIntent? current;
  Object? loadError;

  @override
  Future<GroupExitIntent?> forGroup(String groupId) async {
    final error = loadError;
    if (error != null) throw error;
    return current?.groupId == groupId ? current : null;
  }

  @override
  Future<GroupExitIntentMutationResult> enqueue(GroupExitIntent intent) async {
    final loaded = current;
    if (loaded != null) {
      return GroupExitIntentMutationResult(
        disposition: GroupExitIntentMutationDisposition.refusedConflict,
        current: loaded,
      );
    }
    current = intent;
    return GroupExitIntentMutationResult(
      disposition: GroupExitIntentMutationDisposition.committed,
      current: intent,
    );
  }

  @override
  Future<GroupExitIntentMutationResult> cancelQueued(
    GroupExitIntent expected, {
    required DateTime updatedAt,
  }) async {
    final loaded = current;
    if (loaded == null) {
      return const GroupExitIntentMutationResult(
        disposition: GroupExitIntentMutationDisposition.absent,
      );
    }
    if (!sameExactGroupExitIntent(loaded, expected)) {
      return GroupExitIntentMutationResult(
        disposition: GroupExitIntentMutationDisposition.refusedConflict,
        current: loaded,
      );
    }
    if (!loaded.isCancelable) {
      return GroupExitIntentMutationResult(
        disposition:
            GroupExitIntentMutationDisposition.refusedInvalidTransition,
        current: loaded,
      );
    }
    current = null;
    return const GroupExitIntentMutationResult(
      disposition: GroupExitIntentMutationDisposition.committed,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DissolvePendingBroadcastRepository
    implements GroupPendingBroadcastRepository {
  _DissolvePendingBroadcastRepository([
    List<GroupPendingBroadcast> rows = const [],
  ]) : rows = List<GroupPendingBroadcast>.of(rows);

  final List<GroupPendingBroadcast> rows;
  Object? loadError;

  @override
  Future<void> enqueue(GroupPendingBroadcast broadcast) async {
    _upsertPending(rows, broadcast);
  }

  @override
  Future<List<GroupPendingBroadcast>> forGroup(String groupId) async {
    final error = loadError;
    if (error != null) throw error;
    return rows.where((row) => row.groupId == groupId).toList(growable: false);
  }

  @override
  Future<List<GroupPendingBroadcast>> all() async => List.of(rows);

  @override
  Future<int> countForGroup(String groupId) async =>
      rows.where((row) => row.groupId == groupId).length;

  @override
  Future<void> remove(String id) async {
    rows.removeWhere((row) => row.id == id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DissolvePublishBarrierGroupRepository extends InMemoryGroupRepository {
  final Completer<void> finalPublishReadEntered = Completer<void>();
  final Completer<void> _releaseFinalPublishRead = Completer<void>();
  bool _blockNextGroupRead = false;

  void armFinalPublishRead() => _blockNextGroupRead = true;

  @override
  Future<GroupModel?> getGroup(String id) async {
    if (_blockNextGroupRead) {
      _blockNextGroupRead = false;
      if (!finalPublishReadEntered.isCompleted) {
        finalPublishReadEntered.complete();
      }
      await _releaseFinalPublishRead.future;
    }
    return super.getGroup(id);
  }

  void releaseFinalPublishRead() {
    if (!_releaseFinalPublishRead.isCompleted) {
      _releaseFinalPublishRead.complete();
    }
  }
}

class _BarrierDissolvePreflightAuthority
    extends GroupDissolvePreflightAuthority {
  _BarrierDissolvePreflightAuthority({
    required super.intentRepository,
    required super.pendingRepository,
    required this.groupRepository,
  });

  final _DissolvePublishBarrierGroupRepository groupRepository;
  int evaluations = 0;

  @override
  Future<GroupDissolvePreflightDisposition> evaluate(String groupId) async {
    final disposition = await super.evaluate(groupId);
    evaluations++;
    if (evaluations == 2) groupRepository.armFinalPublishRead();
    return disposition;
  }
}

class _NoopGroupExitIntentProcessor implements GroupExitIntentProcessor {
  const _NoopGroupExitIntentProcessor();

  @override
  Future<GroupExitIntentProcessResult> processGroup(
    String groupId, {
    bool drainRoleBroadcasts = true,
  }) async => const GroupExitIntentProcessResult(
    status: GroupExitIntentProcessStatus.noIntent,
  );

  @override
  Future<Map<String, GroupExitIntentProcessResult>> processAll() async =>
      const <String, GroupExitIntentProcessResult>{};
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

class _CommitUnknownUpdateConfigBridge extends FakeBridge {
  var _lostFirstResponse = false;

  @override
  Future<String> send(String message) async {
    final response = await super.send(message);
    final command = (jsonDecode(message) as Map<String, dynamic>)['cmd'];
    if (command == 'group:updateConfig' && !_lostFirstResponse) {
      _lostFirstResponse = true;
      throw TimeoutException('native response was lost after config commit');
    }
    return response;
  }
}

class _LeaveNoticeCryptographicProofBridge extends FakeBridge {
  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final command = parsed['cmd'] as String?;
    if (command != 'payload.sign' && command != 'payload.verify') {
      return super.send(message);
    }
    sendCallCount++;
    lastSentMessage = message;
    sentMessages.add(message);
    lastCommand = command;
    commandLog.add(command!);
    final payload = parsed['payload'] as Map<String, dynamic>;
    if (command == 'payload.sign') {
      final validPrivateKey = payload['privateKey'] == 'sk-self';
      return jsonEncode({
        'ok': true,
        'signature': validPrivateKey
            ? 'key-pair-proof-valid'
            : 'key-pair-proof-invalid',
      });
    }
    final signature = payload['signature'];
    final valid =
        signature == 'fake-signature' ||
        (signature == 'key-pair-proof-valid' &&
            payload['publicKey'] == 'pk-self');
    return jsonEncode({'ok': true, 'valid': valid});
  }
}

class _WatermarkFailingGroupRepository extends InMemoryGroupRepository {
  var _failedOnce = false;

  @override
  Future<bool> advanceGroupMembershipWatermark({
    required String groupId,
    required DateTime eventAt,
    String? eventId,
  }) async {
    if (!_failedOnce) {
      _failedOnce = true;
      throw StateError('forced post-native watermark failure');
    }
    return super.advanceGroupMembershipWatermark(
      groupId: groupId,
      eventAt: eventAt,
      eventId: eventId,
    );
  }
}

class _RoleProjectionThrowsAfterSqlGroupRepository
    extends InMemoryGroupRepository {
  int roleWriteCalls = 0;

  @override
  Future<void> updateMemberRole(
    String groupId,
    String peerId,
    MemberRole role,
  ) async {
    roleWriteCalls++;
    if (roleWriteCalls == 1) {
      await super.updateMemberRole(groupId, peerId, role);
      throw StateError('member projection failed after role SQL committed');
    }
    if (roleWriteCalls == 2) {
      throw StateError('rollback projection unavailable');
    }
    await super.updateMemberRole(groupId, peerId, role);
  }
}
