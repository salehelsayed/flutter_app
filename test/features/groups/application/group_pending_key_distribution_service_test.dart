import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/group_pending_key_distribution_service.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_distribution.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_distribution_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late PassthroughCryptoBridge bridge;
  late InMemoryGroupRepository groupRepo;
  late _InMemoryGroupPendingKeyDistributionRepository pendingRepo;

  const selfPeerId = 'peer-self';
  const groupId = 'group-1';
  final daveRowId = groupPendingKeyDistributionId(groupId, 'peer-dave');

  IdentityModel identity() => IdentityModel(
    peerId: selfPeerId,
    publicKey: 'selfPubKey',
    privateKey: 'selfPrivKey',
    mnemonic12: 'one two three four five six seven eight nine ten eleven twelve',
    mlKemPublicKey: 'selfMlKem',
    username: 'Self',
    createdAt: DateTime.utc(2026, 6, 16).toIso8601String(),
    updatedAt: DateTime.utc(2026, 6, 16).toIso8601String(),
  );

  Future<void> seedGroup({required String? daveMlKem}) async {
    await groupRepo.saveGroup(
      GroupModel(
        id: groupId,
        name: 'G',
        type: GroupType.chat,
        topicName: '/mknoon/group/$groupId',
        createdAt: DateTime.now().toUtc(),
        createdBy: selfPeerId,
        myRole: GroupRole.admin,
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: selfPeerId,
        username: 'Self',
        role: MemberRole.admin,
        publicKey: 'selfPubKey',
        mlKemPublicKey: 'selfMlKem',
        joinedAt: DateTime.now().toUtc(),
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: 'peer-dave',
        username: 'Dave',
        role: MemberRole.writer,
        publicKey: 'davePubKey',
        mlKemPublicKey: daveMlKem,
        joinedAt: DateTime.now().toUtc(),
      ),
    );
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 2,
        encryptedKey: 'epoch2Key==',
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  GroupPendingKeyDistribution daveRow({int keyEpoch = 2}) =>
      GroupPendingKeyDistribution(
        id: daveRowId,
        groupId: groupId,
        peerId: 'peer-dave',
        keyEpoch: keyEpoch,
        createdAt: DateTime.utc(2026, 6, 16),
        updatedAt: DateTime.utc(2026, 6, 16),
      );

  GroupPendingKeyDistributionRunner runner({
    Future<bool> Function(String peerId, String message)? send,
    int attemptCap = 8,
  }) => GroupPendingKeyDistributionRunner(
    bridge: bridge,
    groupRepo: groupRepo,
    repository: pendingRepo,
    loadIdentity: () async => identity(),
    sendP2PMessage: send ?? (peerId, message) async => true,
    attemptCap: attemptCap,
  );

  setUp(() {
    bridge = PassthroughCryptoBridge();
    groupRepo = InMemoryGroupRepository();
    pendingRepo = _InMemoryGroupPendingKeyDistributionRepository();
  });

  test('INV-D1 converges the deferred member once it is keyed', () async {
    await seedGroup(daveMlKem: 'daveMlKem');
    await pendingRepo.enqueue(daveRow());

    final sent = <String>[];
    final count = await runner(
      send: (peerId, message) async {
        sent.add(peerId);
        return true;
      },
    ).drainPendingForPeer(groupId: groupId, peerId: 'peer-dave');

    expect(count, 1);
    expect(sent, isNotEmpty); // Dave's device was targeted
    final row = await pendingRepo.getDistribution(daveRowId);
    expect(row!.status, groupPendingKeyDistributionStatusDistributed);
    expect(row.finalizedAt, isNotNull);
  });

  test('stays pending while the target is still keyless', () async {
    await seedGroup(daveMlKem: null);
    await pendingRepo.enqueue(daveRow());

    final sent = <String>[];
    final count = await runner(
      send: (peerId, message) async {
        sent.add(peerId);
        return true;
      },
    ).drainPendingForPeer(groupId: groupId, peerId: 'peer-dave');

    expect(count, 0);
    expect(sent, isEmpty);
    final row = await pendingRepo.getDistribution(daveRowId);
    expect(row!.status, groupPendingKeyDistributionStatusPending);
    expect(row.attempts, 1);
  });

  test('INV-D2 distributes the CURRENT key even when the row epoch is stale', () async {
    await seedGroup(daveMlKem: 'daveMlKem');
    // Row records the stale epoch 1 while the live key is epoch 2.
    await pendingRepo.enqueue(daveRow(keyEpoch: 1));

    final captured = <String>[];
    await runner(
      send: (peerId, message) async {
        captured.add(message);
        return true;
      },
    ).drainPendingForPeer(groupId: groupId, peerId: 'peer-dave');

    // The passthrough bridge surfaces plaintext as ciphertext, so we can decode
    // the distributed key-update and assert the CURRENT epoch-2 key was sent,
    // never the row's stale epoch-1.
    expect(captured, hasLength(1));
    final envelope = jsonDecode(captured.single) as Map<String, dynamic>;
    final ciphertext =
        (envelope['encrypted'] as Map<String, dynamic>)['ciphertext'] as String;
    final keyPayload = jsonDecode(ciphertext) as Map<String, dynamic>;
    expect(keyPayload['keyGeneration'], 2);
    expect(keyPayload['encryptedKey'], 'epoch2Key==');
  });

  test('INV-D3 finalizes unreachable after the attempt cap', () async {
    await seedGroup(daveMlKem: null); // permanently keyless
    await pendingRepo.enqueue(daveRow());

    final r = runner(attemptCap: 3);
    await r.drainPendingForPeer(groupId: groupId, peerId: 'peer-dave');
    await r.drainPendingForPeer(groupId: groupId, peerId: 'peer-dave');
    var row = await pendingRepo.getDistribution(daveRowId);
    expect(row!.status, groupPendingKeyDistributionStatusPending);
    expect(row.attempts, 2);

    await r.drainPendingForPeer(groupId: groupId, peerId: 'peer-dave');
    row = await pendingRepo.getDistribution(daveRowId);
    expect(row!.status, groupPendingKeyDistributionStatusUnreachable);
    expect(row.attempts, 3);

    // A finalized row is no longer scanned.
    expect(await r.drainPendingForGroup(groupId: groupId), 0);
  });

  test('INV-D4 finalized rows are no-ops on re-drain', () async {
    await seedGroup(daveMlKem: 'daveMlKem');
    await pendingRepo.enqueue(daveRow());

    final r = runner();
    expect(await r.drainPendingForPeer(groupId: groupId, peerId: 'peer-dave'), 1);
    // Already distributed → the second drain finds no pending rows.
    expect(await r.drainPendingForPeer(groupId: groupId, peerId: 'peer-dave'), 0);
  });

  test('member-key-arrival trigger fires the process-wide drain sink', () async {
    final drained = <(String, String)>[];
    setDeferredDistributionDrainSink(({required groupId, required peerId}) async {
      drained.add((groupId, peerId));
    });
    addTearDown(() => setDeferredDistributionDrainSink(null));

    await triggerDeferredDistributionDrainForPeer(
      groupId: 'group-1',
      peerId: 'peer-dave',
    );
    expect(drained, <(String, String)>[('group-1', 'peer-dave')]);
  });

  test('member-key-arrival trigger is a no-op when no sink is set', () async {
    setDeferredDistributionDrainSink(null);
    // Must not throw.
    await triggerDeferredDistributionDrainForPeer(
      groupId: 'group-1',
      peerId: 'peer-dave',
    );
  });
}

class _InMemoryGroupPendingKeyDistributionRepository
    implements GroupPendingKeyDistributionRepository {
  final Map<String, GroupPendingKeyDistribution> rows = {};

  @override
  Future<GroupPendingKeyDistributionUpsertResult> enqueue(
    GroupPendingKeyDistribution distribution,
  ) async {
    final existing = rows[distribution.id];
    if (existing == null) {
      rows[distribution.id] = distribution;
      return GroupPendingKeyDistributionUpsertResult(
        distribution: distribution,
        created: true,
      );
    }
    if (existing.status != groupPendingKeyDistributionStatusPending) {
      return GroupPendingKeyDistributionUpsertResult(
        distribution: existing,
        created: false,
      );
    }
    final merged = existing.copyWith(
      keyEpoch: distribution.keyEpoch,
      updatedAt: distribution.updatedAt,
    );
    rows[distribution.id] = merged;
    return GroupPendingKeyDistributionUpsertResult(
      distribution: merged,
      created: false,
    );
  }

  @override
  Future<void> reopenForRedelivery(
    GroupPendingKeyDistribution distribution,
  ) async {
    final existing = rows[distribution.id];
    if (existing == null) {
      rows[distribution.id] = distribution;
      return;
    }
    rows[distribution.id] = existing.copyWith(
      status: groupPendingKeyDistributionStatusPending,
      keyEpoch: distribution.keyEpoch,
      attempts: 0,
      lastError: null,
      finalizedAt: null,
      updatedAt: distribution.updatedAt,
    );
  }

  @override
  Future<GroupPendingKeyDistribution?> getDistribution(String id) async =>
      rows[id];

  @override
  Future<List<GroupPendingKeyDistribution>> getPendingForPeer({
    required String peerId,
    String? groupId,
    int limit = 50,
  }) async {
    return rows.values
        .where(
          (row) =>
              row.peerId == peerId &&
              (groupId == null || row.groupId == groupId) &&
              row.status == groupPendingKeyDistributionStatusPending,
        )
        .take(limit)
        .toList();
  }

  @override
  Future<List<GroupPendingKeyDistribution>> getPendingForGroup({
    required String groupId,
    int limit = 50,
  }) async {
    return rows.values
        .where(
          (row) =>
              row.groupId == groupId &&
              row.status == groupPendingKeyDistributionStatusPending,
        )
        .take(limit)
        .toList();
  }

  @override
  Future<void> recordAttempt(String id, {required String? lastError}) async {
    final existing = rows[id];
    if (existing == null || existing.status != groupPendingKeyDistributionStatusPending) {
      return;
    }
    rows[id] = existing.copyWith(
      attempts: existing.attempts + 1,
      lastError: lastError,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> finalizeDistributed(String id) async {
    final existing = rows[id];
    if (existing == null || existing.finalizedAt != null) return;
    final now = DateTime.now().toUtc();
    rows[id] = existing.copyWith(
      status: groupPendingKeyDistributionStatusDistributed,
      updatedAt: now,
      finalizedAt: now,
    );
  }

  @override
  Future<void> finalizeUnreachable(String id, {required String lastError}) async {
    final existing = rows[id];
    if (existing == null || existing.finalizedAt != null) return;
    final now = DateTime.now().toUtc();
    rows[id] = existing.copyWith(
      status: groupPendingKeyDistributionStatusUnreachable,
      lastError: lastError,
      updatedAt: now,
      finalizedAt: now,
    );
  }
}
