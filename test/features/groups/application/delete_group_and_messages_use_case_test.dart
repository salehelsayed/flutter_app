import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/features/groups/application/delete_group_and_messages_use_case.dart';
import 'package:flutter_app/features/groups/application/group_exit_terminal_diagnostics.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_sink.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_diagnostic.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import '../../../../test/shared/fakes/in_memory_group_repository.dart';
import '../../../../test/shared/fakes/in_memory_group_message_repository.dart';
import '../../../../test/core/bridge/fake_bridge.dart';

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository groupMessageRepo;
  const groupId = 'test-group-id-12345';

  setUp(() {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();
    groupMessageRepo = InMemoryGroupMessageRepository();

    // Pre-configure bridge to respond to group:leave
    bridge.responses['group:leave'] = {'ok': true};
  });

  group('deleteGroupAndMessages', () {
    test(
      'strict local-only cleanup refuses active state and clears dissolved local state',
      () async {
        final now = DateTime.now().toUtc();
        final missingRepo = InMemoryGroupRepository();
        await expectLater(
          deleteGroupAndMessages(
            bridge: bridge,
            groupRepo: missingRepo,
            groupMessageRepo: groupMessageRepo,
            groupId: groupId,
            deleteLocallyIfDissolved: true,
          ),
          throwsA(isA<StateError>()),
        );
        expect(bridge.commandLog, isNot(contains('group:leave')));

        await groupRepo.saveGroup(
          GroupModel(
            id: groupId,
            name: 'Active Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/$groupId',
            createdBy: 'creator-peer',
            myRole: GroupRole.member,
            createdAt: now,
          ),
        );
        await expectLater(
          deleteGroupAndMessages(
            bridge: bridge,
            groupRepo: groupRepo,
            groupMessageRepo: groupMessageRepo,
            groupId: groupId,
            deleteLocallyIfDissolved: true,
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              strictDissolvedLocalDeleteRequiredMessage,
            ),
          ),
        );
        expect(bridge.commandLog, isNot(contains('group:leave')));
        expect(await groupRepo.getGroup(groupId), isNotNull);

        final observedDissolved = (await groupRepo.getGroup(groupId))!.copyWith(
          isDissolved: true,
          dissolvedAt: now,
          dissolvedBy: 'creator-peer',
        );
        final flippingRepo = _FlippingGroupRepository(
          observed: observedDissolved,
          committed: (await groupRepo.getGroup(groupId))!,
        );
        final flipMessageRepo = InMemoryGroupMessageRepository();
        await flipMessageRepo.saveMessage(
          GroupMessage(
            id: 'state-flip-message',
            groupId: groupId,
            senderPeerId: 'creator-peer',
            text: 'preserve on stale state',
            timestamp: now,
            createdAt: now,
            isIncoming: true,
          ),
        );
        await expectLater(
          deleteGroupAndMessages(
            bridge: bridge,
            groupRepo: flippingRepo,
            groupMessageRepo: flipMessageRepo,
            groupId: groupId,
            deleteLocallyIfDissolved: true,
          ),
          throwsA(isA<StateError>()),
        );
        expect(
          await flipMessageRepo.getMessage('state-flip-message'),
          isNotNull,
        );
        expect(flippingRepo.destructiveWriteCount, 0);
        expect(bridge.commandLog, isNot(contains('group:leave')));

        await groupRepo.updateGroup(
          (await groupRepo.getGroup(groupId))!.copyWith(
            isDissolved: true,
            dissolvedAt: now,
            dissolvedBy: 'creator-peer',
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'creator-peer',
            role: MemberRole.admin,
            joinedAt: now,
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'key',
            createdAt: now,
          ),
        );
        await groupRepo.recordGroupRejoinFailure(
          groupId,
          nextEligibleAt: now.add(const Duration(hours: 1)),
        );
        await groupMessageRepo.saveMessage(
          GroupMessage(
            id: 'strict-local-message',
            groupId: groupId,
            senderPeerId: 'creator-peer',
            text: 'history',
            timestamp: now,
            createdAt: now,
            isIncoming: true,
          ),
        );
        final pending = <GroupPendingBroadcast>[
          GroupPendingBroadcast(
            id: 'target-pending',
            groupId: groupId,
            kind: 'member_role_updated',
            sysText: '{}',
            recipientPeerIds: const ['peer-b'],
            eventAt: now,
            createdAt: now,
            updatedAt: now,
          ),
          GroupPendingBroadcast(
            id: 'other-pending',
            groupId: 'other-group',
            kind: 'group_metadata_updated',
            sysText: '{}',
            recipientPeerIds: const ['peer-c'],
            eventAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        ];
        setGroupPendingBroadcastAccessSinks(
          loadForGroup: (id) async =>
              pending.where((row) => row.groupId == id).toList(),
          discardForGroup: (id) async =>
              pending.removeWhere((row) => row.groupId == id),
        );
        addTearDown(
          () => setGroupPendingBroadcastAccessSinks(
            loadForGroup: null,
            discardForGroup: null,
          ),
        );

        await deleteGroupAndMessages(
          bridge: bridge,
          groupRepo: groupRepo,
          groupMessageRepo: groupMessageRepo,
          groupId: groupId,
          deleteLocallyIfDissolved: true,
        );
        expect(await groupRepo.getGroup(groupId), isNull);
        expect(await groupRepo.getMembers(groupId), isEmpty);
        expect(await groupRepo.getLatestKey(groupId), isNull);
        expect(
          await groupMessageRepo.getMessage('strict-local-message'),
          isNull,
        );
        expect(
          await groupRepo.loadGroupRejoinStates(),
          isNot(contains(groupId)),
        );
        expect(pending.map((row) => row.id), ['other-pending']);
        expect(bridge.commandLog, isNot(contains('group:leave')));

        await groupRepo.saveGroup(
          GroupModel(
            id: groupId,
            name: 'Dissolved again',
            type: GroupType.chat,
            topicName: '/mknoon/group/$groupId',
            createdBy: 'creator-peer',
            myRole: GroupRole.admin,
            createdAt: now,
            isDissolved: true,
            dissolvedAt: now,
            dissolvedBy: 'creator-peer',
          ),
        );
        pending.add(
          GroupPendingBroadcast(
            id: 'failure-pending',
            groupId: groupId,
            kind: 'member_role_updated',
            sysText: '{}',
            recipientPeerIds: const ['peer-b'],
            eventAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
        await expectLater(
          deleteGroupAndMessages(
            bridge: bridge,
            groupRepo: groupRepo,
            groupMessageRepo: _DeleteFailingMessageRepository(),
            groupId: groupId,
            deleteLocallyIfDissolved: true,
          ),
          throwsA(isA<StateError>()),
        );
        expect(await groupRepo.getGroup(groupId), isNotNull);
        expect(pending.map((row) => row.id), [
          'other-pending',
          'failure-pending',
        ]);
        expect(bridge.commandLog, isNot(contains('group:leave')));
      },
    );

    test(
      'strict local-only cleanup remains retryable across non-cascading cleanup failures',
      () async {
        final now = DateTime.utc(2026, 7, 19, 18);
        final retryingGroupRepo = _RetryableStrictCleanupGroupRepository();
        await retryingGroupRepo.saveGroup(
          GroupModel(
            id: groupId,
            name: 'Retryable dissolved group',
            type: GroupType.chat,
            topicName: '/mknoon/group/$groupId',
            createdBy: 'creator-peer',
            myRole: GroupRole.admin,
            createdAt: now,
            isDissolved: true,
            dissolvedAt: now,
            dissolvedBy: 'creator-peer',
          ),
        );
        await retryingGroupRepo.recordGroupRejoinFailure(
          groupId,
          nextEligibleAt: now.add(const Duration(hours: 1)),
        );
        await groupMessageRepo.saveMessage(
          GroupMessage(
            id: 'retryable-cleanup-message',
            groupId: groupId,
            senderPeerId: 'creator-peer',
            text: 'safe to remove idempotently',
            timestamp: now,
            createdAt: now,
            isIncoming: true,
          ),
        );

        final pending = <GroupPendingBroadcast>[
          GroupPendingBroadcast(
            id: 'retryable-cleanup-pending',
            groupId: groupId,
            kind: 'group_metadata_updated',
            sysText: '{}',
            recipientPeerIds: const ['peer-b'],
            eventAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        ];
        var discardCalls = 0;
        setGroupPendingBroadcastAccessSinks(
          loadForGroup: (id) async =>
              pending.where((row) => row.groupId == id).toList(),
          discardForGroup: (id) async {
            discardCalls++;
            if (discardCalls == 1) {
              throw StateError('forced pending cleanup failure');
            }
            pending.removeWhere((row) => row.groupId == id);
          },
        );
        addTearDown(
          () => setGroupPendingBroadcastAccessSinks(
            loadForGroup: null,
            discardForGroup: null,
          ),
        );

        Future<void> runStrictDelete() => deleteGroupAndMessages(
          bridge: bridge,
          groupRepo: retryingGroupRepo,
          groupMessageRepo: groupMessageRepo,
          groupId: groupId,
          deleteLocallyIfDissolved: true,
        );

        await expectLater(runStrictDelete(), throwsA(isA<StateError>()));
        expect(
          (await retryingGroupRepo.getGroup(groupId))?.isDissolved,
          isTrue,
        );
        expect(
          await retryingGroupRepo.loadGroupRejoinStates(),
          contains(groupId),
        );
        expect(retryingGroupRepo.deleteGroupCalls, 0);
        expect(discardCalls, 0);

        // Failed group deletion is still before the pending-row commit
        // boundary, so its target row must remain untouched.
        await expectLater(runStrictDelete(), throwsA(isA<StateError>()));
        expect(
          (await retryingGroupRepo.getGroup(groupId))?.isDissolved,
          isTrue,
        );
        expect(await retryingGroupRepo.loadGroupRejoinStates(), isEmpty);
        expect(pending, hasLength(1));
        expect(retryingGroupRepo.deleteGroupCalls, 1);
        expect(discardCalls, 0);

        // A post-delete queue failure restores only the dissolved row, so the
        // next strict invocation remains authorized and idempotent.
        await expectLater(runStrictDelete(), throwsA(isA<StateError>()));
        expect(
          (await retryingGroupRepo.getGroup(groupId))?.isDissolved,
          isTrue,
        );
        expect(
          await groupMessageRepo.getMessage('retryable-cleanup-message'),
          isNull,
        );
        expect(pending, hasLength(1));
        expect(retryingGroupRepo.deleteGroupCalls, 2);
        expect(discardCalls, 1);

        await runStrictDelete();

        expect(await retryingGroupRepo.getGroup(groupId), isNull);
        expect(await retryingGroupRepo.loadGroupRejoinStates(), isEmpty);
        expect(pending, isEmpty);
        expect(retryingGroupRepo.deleteGroupCalls, 3);
        expect(discardCalls, 2);
        expect(bridge.commandLog, isNot(contains('group:leave')));
      },
    );

    test('leaves group then deletes its messages', () async {
      // Save a group and some messages
      final now = DateTime.now().toUtc();
      await groupRepo.saveGroup(
        GroupModel(
          id: groupId,
          name: 'Test Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/$groupId',
          createdBy: 'creator-peer',
          myRole: GroupRole.admin,
          createdAt: now,
        ),
      );

      await groupMessageRepo.saveMessage(
        GroupMessage(
          id: 'msg-1',
          groupId: groupId,
          senderPeerId: 'sender-1',
          senderUsername: 'Alice',
          text: 'Hello',
          timestamp: now,
          createdAt: now,
          isIncoming: true,
          status: 'delivered',
        ),
      );

      await groupMessageRepo.saveMessage(
        GroupMessage(
          id: 'msg-2',
          groupId: groupId,
          senderPeerId: 'sender-2',
          senderUsername: 'Bob',
          text: 'World',
          timestamp: now,
          createdAt: now,
          isIncoming: true,
          status: 'delivered',
        ),
      );

      await deleteGroupAndMessages(
        bridge: bridge,
        groupRepo: groupRepo,
        groupMessageRepo: groupMessageRepo,
        groupId: groupId,
      );

      // Messages should be deleted
      expect(groupMessageRepo.count, 0);

      // Group should be deleted (leaveGroup removes it)
      final group = await groupRepo.getGroup(groupId);
      expect(group, isNull);

      // Bridge should have been called for group:leave
      expect(bridge.commandLog, contains('group:leave'));
    });

    test('LP003 active delete dispatches one group leave', () async {
      final now = DateTime.now().toUtc();
      await groupRepo.saveGroup(
        GroupModel(
          id: groupId,
          name: 'Active Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/$groupId',
          createdBy: 'creator-peer',
          myRole: GroupRole.member,
          createdAt: now,
        ),
      );

      await deleteGroupAndMessages(
        bridge: bridge,
        groupRepo: groupRepo,
        groupMessageRepo: groupMessageRepo,
        groupId: groupId,
      );

      expect(
        bridge.commandLog.where((command) => command == 'group:leave'),
        hasLength(1),
      );
      expect(await groupRepo.getGroup(groupId), isNull);
    });

    test('preserves messages when leave is blocked', () async {
      final now = DateTime.now().toUtc();
      await groupRepo.saveGroup(
        GroupModel(
          id: groupId,
          name: 'Only Admin Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/$groupId',
          createdBy: 'creator-peer',
          myRole: GroupRole.admin,
          createdAt: now,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'creator-peer',
          username: 'Creator',
          role: MemberRole.admin,
          joinedAt: now,
        ),
      );
      await groupMessageRepo.saveMessage(
        GroupMessage(
          id: 'msg-admin-only',
          groupId: groupId,
          senderPeerId: 'creator-peer',
          senderUsername: 'Creator',
          text: 'Do not lose this',
          timestamp: now,
          createdAt: now,
          isIncoming: true,
          status: 'delivered',
        ),
      );

      await expectLater(
        deleteGroupAndMessages(
          bridge: bridge,
          groupRepo: groupRepo,
          groupMessageRepo: groupMessageRepo,
          groupId: groupId,
        ),
        throwsA(isA<StateError>()),
      );

      expect(await groupRepo.getGroup(groupId), isNotNull);
      expect(await groupMessageRepo.getMessage('msg-admin-only'), isNotNull);
      expect(bridge.commandLog, isNot(contains('group:leave')));
    });

    test(
      'BB-010 active delete preserves group messages when native leave fails',
      () async {
        final now = DateTime.now().toUtc();
        await groupRepo.saveGroup(
          GroupModel(
            id: groupId,
            name: 'Active Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/$groupId',
            createdBy: 'creator-peer',
            myRole: GroupRole.member,
            createdAt: now,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'creator-peer',
            username: 'Creator',
            role: MemberRole.admin,
            joinedAt: now,
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'test-group-key-1',
            createdAt: now,
          ),
        );
        await groupMessageRepo.saveMessage(
          GroupMessage(
            id: 'msg-bb010-preserved',
            groupId: groupId,
            senderPeerId: 'creator-peer',
            senderUsername: 'Creator',
            text: 'Keep this after failed leave',
            timestamp: now,
            createdAt: now,
            isIncoming: true,
            status: 'delivered',
          ),
        );
        bridge.responses['group:leave'] = {
          'ok': false,
          'errorCode': 'GROUP_ERROR',
          'errorMessage': 'forced leave failure',
        };

        await expectLater(
          deleteGroupAndMessages(
            bridge: bridge,
            groupRepo: groupRepo,
            groupMessageRepo: groupMessageRepo,
            groupId: groupId,
          ),
          throwsA(
            isA<BridgeCommandException>()
                .having((error) => error.command, 'command', 'group:leave')
                .having((error) => error.errorCode, 'errorCode', 'GROUP_ERROR'),
          ),
        );

        expect(await groupRepo.getGroup(groupId), isNotNull);
        expect(await groupRepo.getMembers(groupId), hasLength(1));
        expect(await groupRepo.getLatestKey(groupId), isNotNull);
        expect(
          await groupMessageRepo.getMessage('msg-bb010-preserved'),
          isNotNull,
        );
        expect(groupMessageRepo.count, 1);
        expect(
          bridge.commandLog.where((command) => command == 'group:leave'),
          hasLength(1),
        );
      },
    );

    test('does not delete messages for other groups', () async {
      const otherGroupId = 'other-group-id-67890';
      final now = DateTime.now().toUtc();
      await groupRepo.saveGroup(
        GroupModel(
          id: groupId,
          name: 'Target Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/$groupId',
          createdBy: 'creator-peer',
          myRole: GroupRole.member,
          createdAt: now,
        ),
      );
      await groupRepo.saveGroup(
        GroupModel(
          id: otherGroupId,
          name: 'Other Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/$otherGroupId',
          createdBy: 'creator-peer',
          myRole: GroupRole.member,
          createdAt: now,
        ),
      );
      await groupMessageRepo.saveMessage(
        GroupMessage(
          id: 'msg-target',
          groupId: groupId,
          senderPeerId: 'sender-1',
          senderUsername: 'Alice',
          text: 'Delete this',
          timestamp: now,
          createdAt: now,
          isIncoming: true,
          status: 'delivered',
        ),
      );
      await groupMessageRepo.saveMessage(
        GroupMessage(
          id: 'msg-other',
          groupId: otherGroupId,
          senderPeerId: 'sender-2',
          senderUsername: 'Bob',
          text: 'Keep this',
          timestamp: now,
          createdAt: now,
          isIncoming: true,
          status: 'delivered',
        ),
      );

      await deleteGroupAndMessages(
        bridge: bridge,
        groupRepo: groupRepo,
        groupMessageRepo: groupMessageRepo,
        groupId: groupId,
      );

      expect(await groupMessageRepo.getMessage('msg-target'), isNull);
      expect(await groupMessageRepo.getMessage('msg-other'), isNotNull);
      expect(await groupRepo.getGroup(groupId), isNull);
      expect(await groupRepo.getGroup(otherGroupId), isNotNull);
    });

    test(
      'dissolved local cleanup deletes group state without publishing group leave',
      () async {
        final now = DateTime.now().toUtc();
        await groupRepo.saveGroup(
          GroupModel(
            id: groupId,
            name: 'Dissolved Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/$groupId',
            createdBy: 'creator-peer',
            myRole: GroupRole.member,
            createdAt: now,
            isDissolved: true,
            dissolvedAt: now,
            dissolvedBy: 'creator-peer',
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'creator-peer',
            username: 'Creator',
            role: MemberRole.admin,
            joinedAt: now,
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'test-group-key-1',
            createdAt: now,
          ),
        );
        await groupMessageRepo.saveMessage(
          GroupMessage(
            id: 'msg-dissolved',
            groupId: groupId,
            senderPeerId: 'creator-peer',
            senderUsername: 'Creator',
            text: 'Group dissolved',
            timestamp: now,
            createdAt: now,
            isIncoming: true,
            status: 'delivered',
          ),
        );

        await deleteGroupAndMessages(
          bridge: bridge,
          groupRepo: groupRepo,
          groupMessageRepo: groupMessageRepo,
          groupId: groupId,
          deleteLocallyIfDissolved: true,
        );

        expect(groupMessageRepo.count, 0);
        expect(await groupRepo.getGroup(groupId), isNull);
        expect(await groupRepo.getMembers(groupId), isEmpty);
        expect(await groupRepo.getLatestKey(groupId), isNull);
        expect(bridge.commandLog, isNot(contains('group:leave')));
      },
    );

    test(
      'LP003 dissolved local cleanup does not publish a second group leave',
      () async {
        final now = DateTime.now().toUtc();
        bridge.commandLog.add(
          'group:leave',
        ); // Prior group_dissolved unsubscribe.
        await groupRepo.saveGroup(
          GroupModel(
            id: groupId,
            name: 'Dissolved Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/$groupId',
            createdBy: 'creator-peer',
            myRole: GroupRole.member,
            createdAt: now,
            isDissolved: true,
            dissolvedAt: now,
            dissolvedBy: 'creator-peer',
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'creator-peer',
            username: 'Creator',
            role: MemberRole.admin,
            joinedAt: now,
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'test-group-key-1',
            createdAt: now,
          ),
        );

        await deleteGroupAndMessages(
          bridge: bridge,
          groupRepo: groupRepo,
          groupMessageRepo: groupMessageRepo,
          groupId: groupId,
          deleteLocallyIfDissolved: true,
        );

        expect(
          bridge.commandLog.where((command) => command == 'group:leave'),
          hasLength(1),
        );
        expect(await groupRepo.getGroup(groupId), isNull);
        expect(await groupRepo.getMembers(groupId), isEmpty);
        expect(await groupRepo.getLatestKey(groupId), isNull);
      },
    );

    test('propagates errors from message deletion', () async {
      final failingMsgRepo = _FailingGroupMessageRepository();

      expect(
        () => deleteGroupAndMessages(
          bridge: bridge,
          groupRepo: groupRepo,
          groupMessageRepo: failingMsgRepo,
          groupId: groupId,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'PB266-12 diagnosing dissolved local action preserves throw and records once',
      () async {
        final now = DateTime.utc(2026, 7, 21, 10);
        final diagnostics = <GroupExitDiagnostic>[];
        var deleteCalls = 0;

        final missingAuthority = DiagnosingDeleteDissolvedGroupShellAction(
          inner: null,
          submit: (rows) async => diagnostics.addAll(rows),
          now: () => now,
        );
        final unavailable = await missingAuthority(groupId);
        expect(
          unavailable.status,
          DeleteDissolvedGroupShellActionStatus.authorityUnavailable,
        );
        expect(unavailable.publicCode, GroupExitDiagnosticPublicCode.ex01);
        expect(deleteCalls, 0);
        expect(diagnostics, hasLength(1));
        expect(
          diagnostics.single.publicCode,
          GroupExitDiagnosticPublicCode.ex01,
        );

        diagnostics.clear();
        final stateRace = DiagnosingDeleteDissolvedGroupShellAction(
          inner: (id) async {
            deleteCalls++;
            throw DissolvedGroupDeleteStateChangedException();
          },
          submit: (rows) async => diagnostics.addAll(rows),
          now: () => now,
        );
        await expectLater(
          stateRace(groupId),
          throwsA(isA<DissolvedGroupDeleteStateChangedException>()),
        );
        expect(deleteCalls, 1);
        expect(diagnostics, isEmpty);

        final thrown = StateError('hostile dissolved cleanup failure');
        final originalStack = StackTrace.current;
        final failing = DiagnosingDeleteDissolvedGroupShellAction(
          inner: (id) async {
            deleteCalls++;
            Error.throwWithStackTrace(thrown, originalStack);
          },
          submit: (rows) async => diagnostics.addAll(rows),
          now: () => now,
        );
        Object? caught;
        StackTrace? caughtStack;
        try {
          await failing(groupId);
        } catch (error, stackTrace) {
          caught = error;
          caughtStack = stackTrace;
        }
        expect(caught, same(thrown));
        expect(caughtStack.toString(), originalStack.toString());
        expect(deleteCalls, 2);
        expect(diagnostics, hasLength(1));
        expect(
          diagnostics.single.publicCode,
          GroupExitDiagnosticPublicCode.ex10,
        );

        diagnostics.clear();
        final success = DiagnosingDeleteDissolvedGroupShellAction(
          inner: (id) async {
            deleteCalls++;
          },
          submit: (rows) async => diagnostics.addAll(rows),
          now: () => now,
        );
        expect(
          (await success(groupId)).status,
          DeleteDissolvedGroupShellActionStatus.deleted,
        );
        expect(deleteCalls, 3);
        expect(diagnostics, isEmpty);
        expect(bridge.commandLog, isNot(contains('group:leave')));
      },
    );
  });
}

class _FailingGroupMessageRepository extends InMemoryGroupMessageRepository {
  @override
  Future<int> deleteMessagesForGroup(String groupId) async {
    throw Exception('DB error');
  }
}

class _DeleteFailingMessageRepository extends InMemoryGroupMessageRepository {
  @override
  Future<int> deleteMessagesForGroup(String groupId) async {
    throw StateError('forced strict cleanup failure');
  }
}

class _RetryableStrictCleanupGroupRepository extends InMemoryGroupRepository {
  var _failRejoinCleanup = true;
  var _failDelete = true;
  var deleteGroupCalls = 0;

  @override
  Future<void> clearGroupRejoinState(String groupId) async {
    if (_failRejoinCleanup) {
      _failRejoinCleanup = false;
      throw StateError('forced rejoin cleanup failure');
    }
    await super.clearGroupRejoinState(groupId);
  }

  @override
  Future<void> deleteGroup(String id) async {
    deleteGroupCalls++;
    if (_failDelete) {
      _failDelete = false;
      throw StateError('forced group delete failure');
    }
    await super.deleteGroup(id);
  }
}

class _FlippingGroupRepository extends InMemoryGroupRepository {
  _FlippingGroupRepository({required this.observed, required this.committed});

  final GroupModel observed;
  final GroupModel committed;
  var _readCount = 0;
  var destructiveWriteCount = 0;

  @override
  Future<GroupModel?> getGroup(String id) async {
    _readCount++;
    return _readCount == 1 ? observed : committed;
  }

  @override
  Future<void> removeAllMembers(String groupId) async {
    destructiveWriteCount++;
  }

  @override
  Future<void> removeAllKeys(String groupId) async {
    destructiveWriteCount++;
  }

  @override
  Future<void> deleteGroup(String id) async {
    destructiveWriteCount++;
  }

  @override
  Future<void> clearGroupRejoinState(String groupId) async {
    destructiveWriteCount++;
  }
}
