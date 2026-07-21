import 'dart:async';

import 'package:flutter_app/core/database/helpers/group_media_deletion_journal_db_helpers.dart';
import 'package:flutter_app/features/groups/application/delete_self_removed_group_shell_use_case.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const groupId = 'group-removed';
  const selfPeerId = 'peer-self';
  final marker = DateTime.utc(2026, 7, 20, 12);

  SelfRemovedShellAuthoritySnapshot marked() =>
      SelfRemovedShellAuthoritySnapshot(
        groupId: groupId,
        selfPeerId: selfPeerId,
        shape: SelfRemovedShellAuthorityShape.markedSelfAbsent,
        selfRemovedAt: marker,
        lastMembershipEventAt: marker,
        lastMembershipEventId: 'remove-1',
        selfJoinedAt: null,
        persistenceToken: Object(),
      );

  test(
    'local shell cleanup honors the artifact disposition matrix with zero leave publish or inbox work',
    () async {
      final repository = _FakeShellRepository(marked());
      repository.mediaBatches.add(
        SelfRemovedShellMediaBatch(
          outcome: SelfRemovedShellMutationOutcome.committed,
          authority: repository.authority,
          parents: [
            SelfRemovedShellMediaParent(
              messageId: 'media-1',
              timestamp: marker,
            ),
          ],
          hasOverflow: false,
        ),
      );
      final prepared = <String>[];
      final reconciled = Completer<void>();
      final useCase = DeleteSelfRemovedGroupShellUseCase(
        repository: repository,
        prepareMedia:
            ({
              required groupId,
              required messageId,
              required operationId,
            }) async {
              prepared.add('$groupId:$messageId:$operationId');
              return const GroupMediaDeletePrepareResult(
                GroupMediaDeletePrepareOutcome.prepared,
              );
            },
        runMediaReconciler: () async {
          reconciled.complete();
        },
        snapshotAvatarPath: (_) async {
          repository.callOrder.add('avatar-snapshot');
          return 'media/group_avatars/$groupId.jpg';
        },
        deleteAvatar: (path) async {
          repository.callOrder.add('avatar:$path');
        },
        operationIdFactory: () => 'op-1',
      );

      expect(
        await useCase(groupId: groupId, selfPeerId: selfPeerId),
        DeleteSelfRemovedGroupShellResult.deleted,
      );
      await reconciled.future;
      expect(prepared, ['$groupId:media-1:op-1']);
      expect(repository.callOrder, [
        'load',
        'avatar-snapshot',
        'media',
        'terminal',
        'floor',
        'purge',
        'avatar:media/group_avatars/$groupId.jpg',
      ]);
      expect(
        await useCase(groupId: groupId, selfPeerId: selfPeerId),
        DeleteSelfRemovedGroupShellResult.alreadyAbsent,
      );
    },
  );

  test(
    'local shell cleanup bounds media preparation and refuses conflicting tombstones without crossing groups',
    () async {
      final repository = _FakeShellRepository(marked());
      repository.mediaBatches.addAll([
        SelfRemovedShellMediaBatch(
          outcome: SelfRemovedShellMutationOutcome.committed,
          authority: repository.authority,
          parents: [
            SelfRemovedShellMediaParent(messageId: 'm1', timestamp: marker),
            SelfRemovedShellMediaParent(
              messageId: 'm2',
              timestamp: marker.add(const Duration(seconds: 1)),
            ),
          ],
          hasOverflow: true,
        ),
        SelfRemovedShellMediaBatch(
          outcome: SelfRemovedShellMutationOutcome.committed,
          authority: repository.authority,
          parents: [
            SelfRemovedShellMediaParent(
              messageId: 'm3',
              timestamp: marker.add(const Duration(seconds: 2)),
            ),
          ],
          hasOverflow: false,
        ),
        SelfRemovedShellMediaBatch(
          outcome: SelfRemovedShellMutationOutcome.committed,
          authority: repository.authority,
          parents: [
            SelfRemovedShellMediaParent(
              messageId: 'm3',
              timestamp: marker.add(const Duration(seconds: 2)),
            ),
          ],
          hasOverflow: false,
        ),
        SelfRemovedShellMediaBatch(
          outcome: SelfRemovedShellMutationOutcome.committed,
          authority: repository.authority,
          parents: [
            SelfRemovedShellMediaParent(
              messageId: 'm3',
              timestamp: marker.add(const Duration(seconds: 2)),
            ),
          ],
          hasOverflow: false,
        ),
      ]);
      final prepared = <String>[];
      var m3Attempt = 0;
      final useCase = DeleteSelfRemovedGroupShellUseCase(
        repository: repository,
        mediaPrepareLimit: 2,
        prepareMedia:
            ({
              required groupId,
              required messageId,
              required operationId,
            }) async {
              expect(groupId, 'group-removed');
              prepared.add(messageId);
              if (messageId == 'm2') {
                return const GroupMediaDeletePrepareResult(
                  GroupMediaDeletePrepareOutcome.alreadyDeleted,
                );
              }
              if (messageId == 'm3') {
                m3Attempt++;
                if (m3Attempt == 1) {
                  return const GroupMediaDeletePrepareResult(
                    GroupMediaDeletePrepareOutcome.parentMissing,
                  );
                }
                if (m3Attempt == 2) {
                  return const GroupMediaDeletePrepareResult(
                    GroupMediaDeletePrepareOutcome.conflictingTombstone,
                  );
                }
              }
              return const GroupMediaDeletePrepareResult(
                GroupMediaDeletePrepareOutcome.prepared,
              );
            },
        runMediaReconciler: () async {},
        snapshotAvatarPath: (_) async => null,
        deleteAvatar: (_) async {},
        operationIdFactory: () => 'op-${prepared.length}',
      );

      expect(
        await useCase(groupId: groupId, selfPeerId: selfPeerId),
        DeleteSelfRemovedGroupShellResult.cleanupIncomplete,
      );
      expect(prepared, ['m1', 'm2']);
      expect(repository.terminalCalls, 0);

      expect(
        await useCase(groupId: groupId, selfPeerId: selfPeerId),
        DeleteSelfRemovedGroupShellResult.cleanupIncomplete,
      );
      expect(prepared, ['m1', 'm2', 'm3']);
      expect(repository.terminalCalls, 0);

      expect(
        await useCase(groupId: groupId, selfPeerId: selfPeerId),
        DeleteSelfRemovedGroupShellResult.cleanupIncomplete,
      );
      expect(prepared, ['m1', 'm2', 'm3', 'm3']);
      expect(repository.terminalCalls, 0);

      expect(
        await useCase(groupId: groupId, selfPeerId: selfPeerId),
        DeleteSelfRemovedGroupShellResult.deleted,
      );
      expect(prepared, ['m1', 'm2', 'm3', 'm3', 'm3']);
      expect(repository.terminalCalls, 1);
    },
  );

  test(
    'entry re-read requires matching completed-cleanup evidence and rejects a newer membership watermark',
    () async {
      DeleteSelfRemovedGroupShellUseCase useCase(
        _FakeShellRepository repository,
      ) => DeleteSelfRemovedGroupShellUseCase(
        repository: repository,
        prepareMedia:
            ({
              required groupId,
              required messageId,
              required operationId,
            }) async => const GroupMediaDeletePrepareResult(
              GroupMediaDeletePrepareOutcome.prepared,
            ),
        runMediaReconciler: () async {},
        snapshotAvatarPath: (_) async => null,
        deleteAvatar: (_) async {},
        operationIdFactory: () => 'op',
      );

      final absent = _FakeShellRepository(
        SelfRemovedShellAuthoritySnapshot(
          groupId: groupId,
          selfPeerId: selfPeerId,
          shape: SelfRemovedShellAuthorityShape.absent,
          selfRemovedAt: null,
          lastMembershipEventAt: null,
          lastMembershipEventId: null,
          selfJoinedAt: null,
          persistenceToken: Object(),
        ),
      );
      expect(
        await useCase(absent)(groupId: groupId, selfPeerId: selfPeerId),
        DeleteSelfRemovedGroupShellResult.refusedStateChanged,
      );

      absent.freshnessFloor = SelfRemovedShellFreshnessFloor(
        groupId: groupId,
        selfPeerId: 'another-account',
        selfRemovedAt: marker,
        persistenceToken: Object(),
      );
      expect(
        await useCase(absent)(groupId: groupId, selfPeerId: selfPeerId),
        DeleteSelfRemovedGroupShellResult.refusedStateChanged,
      );

      absent.freshnessFloor = SelfRemovedShellFreshnessFloor(
        groupId: groupId,
        selfPeerId: selfPeerId,
        selfRemovedAt: marker,
        persistenceToken: Object(),
      );
      expect(
        await useCase(absent)(groupId: groupId, selfPeerId: selfPeerId),
        DeleteSelfRemovedGroupShellResult.alreadyAbsent,
      );

      final advanced = _FakeShellRepository(
        SelfRemovedShellAuthoritySnapshot(
          groupId: groupId,
          selfPeerId: selfPeerId,
          shape: SelfRemovedShellAuthorityShape.markedSelfAbsent,
          selfRemovedAt: marker,
          lastMembershipEventAt: marker.add(const Duration(seconds: 1)),
          lastMembershipEventId: 'newer-membership',
          selfJoinedAt: null,
          persistenceToken: Object(),
        ),
      );
      expect(
        await useCase(advanced)(groupId: groupId, selfPeerId: selfPeerId),
        DeleteSelfRemovedGroupShellResult.refusedStateChanged,
      );
      expect(advanced.callOrder, ['load']);
    },
  );

  test(
    'advancing media outcomes dispatch reconciliation after unlock even when terminal cleanup fails',
    () async {
      for (final outcome in <GroupMediaDeletePrepareOutcome>[
        GroupMediaDeletePrepareOutcome.prepared,
        GroupMediaDeletePrepareOutcome.alreadyDeleted,
      ]) {
        final repository = _FakeShellRepository(marked())
          ..faultAt = 'terminal'
          ..mediaBatches.add(
            SelfRemovedShellMediaBatch(
              outcome: SelfRemovedShellMutationOutcome.committed,
              authority: marked(),
              parents: [
                SelfRemovedShellMediaParent(
                  messageId: 'media-${outcome.name}',
                  timestamp: marker,
                ),
              ],
              hasOverflow: false,
            ),
          );
        var reconcilerCalls = 0;
        Future<void> synchronouslyFailingReconciler() {
          reconcilerCalls++;
          throw StateError('sync reconciler failure');
        }

        final useCase = DeleteSelfRemovedGroupShellUseCase(
          repository: repository,
          prepareMedia:
              ({
                required groupId,
                required messageId,
                required operationId,
              }) async => GroupMediaDeletePrepareResult(outcome),
          runMediaReconciler: synchronouslyFailingReconciler,
          snapshotAvatarPath: (_) async => null,
          deleteAvatar: (_) async {},
          operationIdFactory: () => 'op',
        );

        expect(
          await useCase(groupId: groupId, selfPeerId: selfPeerId),
          DeleteSelfRemovedGroupShellResult.cleanupIncomplete,
          reason: outcome.name,
        );
        expect(reconcilerCalls, 1, reason: outcome.name);
      }
    },
  );

  test('exact freshness-floor CAS loss is refusedStateChanged', () async {
    final repository = _FakeShellRepository(marked())
      ..faultAt = 'floorStateChanged'
      ..mediaBatches.add(
        SelfRemovedShellMediaBatch(
          outcome: SelfRemovedShellMutationOutcome.committed,
          authority: marked(),
          parents: const [],
          hasOverflow: false,
        ),
      );
    final useCase = DeleteSelfRemovedGroupShellUseCase(
      repository: repository,
      prepareMedia:
          ({
            required groupId,
            required messageId,
            required operationId,
          }) async => const GroupMediaDeletePrepareResult(
            GroupMediaDeletePrepareOutcome.prepared,
          ),
      runMediaReconciler: () async {},
      snapshotAvatarPath: (_) async => null,
      deleteAvatar: (_) async {},
      operationIdFactory: () => 'op',
    );

    expect(
      await useCase(groupId: groupId, selfPeerId: selfPeerId),
      DeleteSelfRemovedGroupShellResult.refusedStateChanged,
    );
  });

  test(
    'group-last keeps the old avatar delete inside the membership phase and best effort',
    () async {
      final repository = _FakeShellRepository(marked())
        ..mediaBatches.add(
          SelfRemovedShellMediaBatch(
            outcome: SelfRemovedShellMutationOutcome.committed,
            authority: marked(),
            parents: const [],
            hasOverflow: false,
          ),
        );
      final avatarDeleteEntered = Completer<void>();
      final releaseAvatarDelete = Completer<void>();
      var competingAuthorityEntered = false;
      var reconcilerDispatched = false;
      final order = <String>[];
      final useCase = DeleteSelfRemovedGroupShellUseCase(
        repository: repository,
        prepareMedia:
            ({
              required groupId,
              required messageId,
              required operationId,
            }) async => const GroupMediaDeletePrepareResult(
              GroupMediaDeletePrepareOutcome.prepared,
            ),
        runMediaReconciler: () async {
          reconcilerDispatched = true;
        },
        snapshotAvatarPath: (_) async {
          order.add('avatar-snapshot');
          return 'media/group_avatars/$groupId.jpg';
        },
        deleteAvatar: (path) async {
          order.add('avatar-delete-start');
          avatarDeleteEntered.complete();
          await releaseAvatarDelete.future;
          order.add('avatar-delete-end');
          throw StateError('best-effort avatar failure');
        },
        operationIdFactory: () => 'op',
      );

      final cleanup = useCase(groupId: groupId, selfPeerId: selfPeerId);
      await avatarDeleteEntered.future;
      expect(repository.authority.shape, SelfRemovedShellAuthorityShape.absent);
      expect(reconcilerDispatched, isFalse);

      final competingAuthority = runGroupMembershipMutationLocked(
        groupId: groupId,
        action: () async {
          competingAuthorityEntered = true;
          order.add('competing-authority');
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(competingAuthorityEntered, isFalse);

      releaseAvatarDelete.complete();
      expect(await cleanup, DeleteSelfRemovedGroupShellResult.deleted);
      await competingAuthority;
      await Future<void>.delayed(Duration.zero);
      expect(reconcilerDispatched, isTrue);
      expect(order, [
        'avatar-snapshot',
        'avatar-delete-start',
        'avatar-delete-end',
        'competing-authority',
      ]);
    },
  );

  test(
    'secure projection SQL and media failures preserve retry authority and converge',
    () async {
      final repository = _FakeShellRepository(marked())
        ..mediaBatches.add(
          SelfRemovedShellMediaBatch(
            outcome: SelfRemovedShellMutationOutcome.committed,
            authority: marked(),
            parents: [
              SelfRemovedShellMediaParent(
                messageId: 'prepare-fault',
                timestamp: marker,
              ),
            ],
            hasOverflow: false,
          ),
        )
        ..mediaBatches.addAll(
          List<SelfRemovedShellMediaBatch>.generate(
            6,
            (index) => SelfRemovedShellMediaBatch(
              outcome: SelfRemovedShellMutationOutcome.committed,
              authority: marked(),
              parents: [
                SelfRemovedShellMediaParent(
                  messageId: 'prepared-after-fault-$index',
                  timestamp: marker.add(Duration(seconds: index + 1)),
                ),
              ],
              hasOverflow: false,
            ),
          ),
        );
      var snapshotFault = true;
      var prepareFault = true;
      var reconcilerCalls = 0;
      Future<void> synchronouslyFailingReconciler() {
        reconcilerCalls++;
        throw StateError('postcommit');
      }

      final useCase = DeleteSelfRemovedGroupShellUseCase(
        repository: repository,
        prepareMedia:
            ({
              required groupId,
              required messageId,
              required operationId,
            }) async {
              if (prepareFault) throw StateError('prepare');
              return const GroupMediaDeletePrepareResult(
                GroupMediaDeletePrepareOutcome.prepared,
              );
            },
        runMediaReconciler: synchronouslyFailingReconciler,
        snapshotAvatarPath: (_) async {
          if (snapshotFault) throw StateError('snapshot');
          return 'media/group_avatars/$groupId.jpg';
        },
        deleteAvatar: (_) async => throw StateError('postcommit avatar'),
        operationIdFactory: () => 'op',
      );

      expect(
        await useCase(groupId: groupId, selfPeerId: selfPeerId),
        DeleteSelfRemovedGroupShellResult.cleanupIncomplete,
      );
      expect(repository.mediaBatches, hasLength(7));

      snapshotFault = false;
      repository.faultAt = 'media';
      expect(
        await useCase(groupId: groupId, selfPeerId: selfPeerId),
        DeleteSelfRemovedGroupShellResult.cleanupIncomplete,
      );
      expect(repository.mediaBatches, hasLength(7));

      repository.faultAt = null;
      expect(
        await useCase(groupId: groupId, selfPeerId: selfPeerId),
        DeleteSelfRemovedGroupShellResult.cleanupIncomplete,
      );
      expect(repository.mediaBatches, hasLength(6));

      prepareFault = false;
      repository.faultAt = 'terminal';
      expect(
        await useCase(groupId: groupId, selfPeerId: selfPeerId),
        DeleteSelfRemovedGroupShellResult.cleanupIncomplete,
      );

      repository.faultAt = null;
      repository.terminalOutcome =
          SelfRemovedShellMutationOutcome.refusedOutstandingReferences;
      expect(
        await useCase(groupId: groupId, selfPeerId: selfPeerId),
        DeleteSelfRemovedGroupShellResult.cleanupIncomplete,
      );
      expect(
        repository.authority.shape,
        SelfRemovedShellAuthorityShape.markedSelfAbsent,
      );

      repository.terminalOutcome = SelfRemovedShellMutationOutcome.committed;
      repository.faultAt = 'floor';
      expect(
        await useCase(groupId: groupId, selfPeerId: selfPeerId),
        DeleteSelfRemovedGroupShellResult.cleanupIncomplete,
      );
      expect(
        repository.authority.shape,
        SelfRemovedShellAuthorityShape.markedSelfAbsent,
      );

      repository.faultAt = 'purge';
      expect(
        await useCase(groupId: groupId, selfPeerId: selfPeerId),
        DeleteSelfRemovedGroupShellResult.cleanupIncomplete,
      );

      repository.faultAt = null;
      repository.purgeOutcome =
          SelfRemovedShellMutationOutcome.refusedStateChanged;
      expect(
        await useCase(groupId: groupId, selfPeerId: selfPeerId),
        DeleteSelfRemovedGroupShellResult.refusedStateChanged,
      );

      repository.purgeOutcome = SelfRemovedShellMutationOutcome.committed;
      expect(
        await useCase(groupId: groupId, selfPeerId: selfPeerId),
        DeleteSelfRemovedGroupShellResult.deleted,
      );
      expect(reconcilerCalls, 8);
    },
  );
}

class _FakeShellRepository implements SelfRemovedGroupShellRepository {
  _FakeShellRepository(this.authority);

  SelfRemovedShellAuthoritySnapshot authority;
  final List<SelfRemovedShellMediaBatch> mediaBatches = [];
  final List<String> callOrder = [];
  SelfRemovedShellMutationOutcome terminalOutcome =
      SelfRemovedShellMutationOutcome.committed;
  SelfRemovedShellMutationOutcome purgeOutcome =
      SelfRemovedShellMutationOutcome.committed;
  SelfRemovedShellFreshnessFloor? freshnessFloor;
  String? faultAt;
  int terminalCalls = 0;

  @override
  Future<SelfRemovedShellAuthoritySnapshot> loadSelfRemovedShellAuthority({
    required String groupId,
    required String selfPeerId,
  }) async {
    callOrder.add('load');
    if (faultAt == 'load') throw StateError('load');
    return authority;
  }

  @override
  Future<SelfRemovedShellMediaBatch> loadSelfRemovedShellMediaParents({
    required SelfRemovedShellAuthoritySnapshot expected,
    required int limit,
  }) async {
    callOrder.add('media');
    if (faultAt == 'media') throw StateError('media');
    return mediaBatches.removeAt(0);
  }

  @override
  Future<SelfRemovedShellMutationOutcome> terminalizeSelfRemovedShell({
    required SelfRemovedShellAuthoritySnapshot expected,
  }) async {
    callOrder.add('terminal');
    terminalCalls++;
    if (faultAt == 'terminal') throw StateError('terminal');
    return terminalOutcome;
  }

  @override
  Future<SelfRemovedShellFreshnessFloor> appendSelfRemovedShellFreshnessFloor({
    required SelfRemovedShellAuthoritySnapshot expected,
  }) async {
    callOrder.add('floor');
    if (faultAt == 'floor') throw StateError('floor');
    if (faultAt == 'floorStateChanged') {
      throw const SelfRemovedShellStateChangedException();
    }
    return freshnessFloor ??= SelfRemovedShellFreshnessFloor(
      groupId: expected.groupId,
      selfPeerId: expected.selfPeerId,
      selfRemovedAt: expected.selfRemovedAt!,
      persistenceToken: Object(),
    );
  }

  @override
  Future<SelfRemovedShellFreshnessFloor?> loadSelfRemovedShellFreshnessFloor(
    String groupId,
  ) async => freshnessFloor;

  @override
  Future<SelfRemovedAcceptedReentryResult> commitAcceptedReentry({
    required GroupModel group,
    required List<GroupMember> roster,
    required GroupKeyInfo key,
    required String selfPeerId,
    required String authorizationId,
    required String signedMembershipWatermark,
    required String signedIssuedAt,
    required String bindingNonce,
  }) => throw UnimplementedError();

  @override
  Future<SelfRemovedAcceptedRollbackOutcome> rollbackAcceptedReentry({
    required String groupId,
    required String selfPeerId,
    required String authorizationId,
  }) => throw UnimplementedError();

  @override
  Future<SelfRemovedAcceptedRetryAuthorizationOutcome>
  authorizeAcceptedReentryRetry({
    required String groupId,
    required String selfPeerId,
    required String authorizationId,
    required String signedMembershipWatermark,
    required String signedIssuedAt,
    required int keyGeneration,
  }) => throw UnimplementedError();

  @override
  Future<SelfRemovedAcceptedNativeRetryResult> retryAcceptedReentryNative({
    required String groupId,
    required String selfPeerId,
    required String authorizationId,
    required String signedMembershipWatermark,
    required String signedIssuedAt,
    required int keyGeneration,
    required String expectedKeyMaterial,
    required DateTime expectedFreshMembershipAt,
    required DateTime? latestAllowedMetadataAt,
    required Future<void> Function() joinNative,
  }) => throw UnimplementedError();

  @override
  Future<void> commitFreshDirectJoin({
    required GroupModel group,
    required GroupMember selfMember,
    required GroupKeyInfo key,
    required Future<void> Function() joinNative,
  }) => throw UnimplementedError();

  @override
  Future<SelfRemovedAcceptedRollbackOutcome>
  rollbackFreshAcceptedMaterialization({
    required String groupId,
    required String selfPeerId,
    required int keyGeneration,
    required String expectedKeyMaterial,
    required DateTime expectedMembershipAt,
    required DateTime? latestAllowedMetadataAt,
  }) => throw UnimplementedError();

  @override
  Future<SelfRemovedShellMutationOutcome> purgeSelfRemovedShell({
    required SelfRemovedShellAuthoritySnapshot expected,
    required SelfRemovedShellFreshnessFloor floor,
    required DateTime deletedAt,
  }) async {
    callOrder.add('purge');
    if (faultAt == 'purge') throw StateError('purge');
    if (purgeOutcome == SelfRemovedShellMutationOutcome.committed) {
      authority = SelfRemovedShellAuthoritySnapshot(
        groupId: expected.groupId,
        selfPeerId: expected.selfPeerId,
        shape: SelfRemovedShellAuthorityShape.absent,
        selfRemovedAt: null,
        lastMembershipEventAt: null,
        lastMembershipEventId: null,
        selfJoinedAt: null,
        persistenceToken: Object(),
      );
    }
    return purgeOutcome;
  }

  @override
  Future<SelfRemovalAuthorityCommitOutcome> commitSelfRemovalAuthority({
    required String groupId,
    required String selfPeerId,
    required DateTime expectedSelfJoinedAt,
    required DateTime removalAt,
    required String removalEventId,
    required Future<void> Function() leaveNative,
  }) => throw UnimplementedError();
}
