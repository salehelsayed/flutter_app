/// Real-bridge device proof for Finding 03 Slice 2 (deferred-distribution
/// convergence). Extends the Slice 1 proof past where it stops: a keyless
/// bystander (Carol) is deferred at rotation time, then GAINS a real ML-KEM key,
/// and the `GroupPendingKeyDistributionRunner` re-distributes the CURRENT group
/// key to her — after which she can decrypt new-epoch traffic, all against the
/// real Go ML-KEM-768 / AES-GCM bridge.
@Tags(['device'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/create_group_use_case.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_distribution_service.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_distribution.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_distribution_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

import '../test/shared/fakes/in_memory_inbox_staging_repository.dart';
import '../test/shared/fakes/in_memory_group_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('real-crypto deferred-distribution convergence (Finding 03 Slice 2)', () {
    late GoBridgeClient bridge;

    setUp(() async {
      bridge = GoBridgeClient();
      await bridge.initialize();
    });

    tearDown(() {
      bridge.dispose();
    });

    testWidgets(
      'a keyless bystander deferred at rotation converges once it regains a key',
      (tester) async {
        final alice = await _generateIdentity(bridge: bridge, username: 'Alice');
        final bob = await _generateIdentity(bridge: bridge, username: 'Bob');
        final carol = await _generateIdentity(bridge: bridge, username: 'Carol');

        final nodeService = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: InMemoryInboxStagingRepository(),
        );
        addTearDown(() async {
          await nodeService.stopNode();
          nodeService.dispose();
        });
        expect(
          await nodeService.startNodeCore(alice.privateKey, alice.peerId),
          isTrue,
        );

        final groupRepo = InMemoryGroupRepository();
        final pendingRepo = _InMemoryDistributionRepo();

        final group = await createGroup(
          bridge: bridge,
          groupRepo: groupRepo,
          name: 'Converge Proof',
          type: GroupType.chat,
          creatorPeerId: alice.peerId,
          creatorPublicKey: alice.publicKey,
          creatorMlKemPublicKey: alice.mlKemPublicKey!,
          creatorUsername: alice.username,
        );
        final groupId = group.id;

        await addGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: groupId,
          newMember: GroupMember(
            groupId: groupId,
            peerId: bob.peerId,
            username: bob.username,
            role: MemberRole.writer,
            publicKey: bob.publicKey,
            mlKemPublicKey: bob.mlKemPublicKey,
            joinedAt: DateTime.now().toUtc(),
          ),
          selfPeerId: alice.peerId,
        );
        // Carol joins KEYLESS (no ML-KEM key) — she will be deferred.
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: carol.peerId,
            username: carol.username,
            role: MemberRole.writer,
            publicKey: carol.publicKey,
            mlKemPublicKey: null,
            joinedAt: DateTime.now().toUtc(),
          ),
        );

        final epoch1 = await groupRepo.getLatestKey(groupId);
        final bobRetainedKey = epoch1!.encryptedKey;

        // 1. Remove Bob, then rotate with the Slice 2 enqueue seam.
        await groupRepo.removeMember(groupId, bob.peerId);
        final outcome = await rotateAndDistributeGroupKey(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sendP2PMessage: (peerId, message) async => true,
          enqueueDeferredDistribution: ({
            required groupId,
            required peerId,
            required keyEpoch,
          }) async {
            final now = DateTime.now().toUtc();
            await pendingRepo.enqueue(
              GroupPendingKeyDistribution(
                id: groupPendingKeyDistributionId(groupId, peerId),
                groupId: groupId,
                peerId: peerId,
                keyEpoch: keyEpoch,
                createdAt: now,
                updatedAt: now,
              ),
            );
          },
        );

        expect(outcome.rotated, isTrue);
        expect(outcome.fullyDistributed, isFalse);
        expect(outcome.deferredPeerIds, <String>[carol.peerId]);
        final epoch2 = await groupRepo.getLatestKey(groupId);
        expect(epoch2!.keyGeneration, epoch1.keyGeneration + 1);
        // Exactly one pending distribution row for Carol at the new epoch.
        final pendingBefore = await pendingRepo.getPendingForGroup(
          groupId: groupId,
        );
        expect(pendingBefore.map((r) => r.peerId), <String>[carol.peerId]);

        // 2. Carol regains a REAL ML-KEM key; her updated config is applied.
        final carolKey = await _generateMlKem(bridge);
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: carol.peerId,
            username: carol.username,
            role: MemberRole.writer,
            publicKey: carol.publicKey,
            mlKemPublicKey: carolKey.publicKey,
            joinedAt: DateTime.now().toUtc(),
          ),
        );

        // 3. Drain — re-distributes the CURRENT key to now-keyed Carol.
        final carolEnvelopes = <String>[];
        final runner = GroupPendingKeyDistributionRunner(
          bridge: bridge,
          groupRepo: groupRepo,
          repository: pendingRepo,
          loadIdentity: () async => alice,
          sendP2PMessage: (peerId, message) async {
            if (peerId == carol.peerId) carolEnvelopes.add(message);
            return true;
          },
        );
        final distributed = await runner.drainPendingForPeer(
          groupId: groupId,
          peerId: carol.peerId,
        );

        expect(distributed, 1);
        expect(carolEnvelopes, hasLength(1));
        // Row finalized; nothing left pending.
        expect(await pendingRepo.getPendingForGroup(groupId: groupId), isEmpty);

        // 4. Convergence with real crypto: Carol decrypts the key-update with her
        // secret key and recovers the CURRENT epoch-2 key (INV-D1/INV-D2).
        final envelope = jsonDecode(carolEnvelopes.single) as Map<String, dynamic>;
        final encrypted = envelope['encrypted'] as Map<String, dynamic>;
        final decryptResponse = await bridge.send(
          jsonEncode({
            'cmd': 'message.decrypt',
            'payload': {
              'secretKey': carolKey.secretKey,
              'kem': encrypted['kem'],
              'ciphertext': encrypted['ciphertext'],
              'nonce': encrypted['nonce'],
            },
          }),
        );
        final decrypted = jsonDecode(decryptResponse) as Map<String, dynamic>;
        expect(decrypted['ok'], isTrue, reason: '$decrypted');
        final keyUpdate =
            jsonDecode(decrypted['plaintext'] as String) as Map<String, dynamic>;
        expect(keyUpdate['keyGeneration'], epoch2.keyGeneration);
        final carolRecoveredKey = keyUpdate['encryptedKey'] as String;
        expect(carolRecoveredKey, epoch2.encryptedKey);

        // 5. Carol now reads a message published at the new epoch; the removed
        // member's retained key still cannot.
        final newEpochCipher = await _groupEncrypt(
          bridge: bridge,
          groupKey: epoch2.encryptedKey,
          plaintext: 'converged new-epoch message',
        );
        expect(
          await _groupDecrypt(
            bridge: bridge,
            groupKey: carolRecoveredKey,
            ciphertext: newEpochCipher,
          ),
          'converged new-epoch message',
          reason: 'formerly-keyless Carol reads the new epoch after the drain',
        );
        final bobDecrypt = await _groupDecryptRaw(
          bridge: bridge,
          groupKey: bobRetainedKey,
          ciphertext: newEpochCipher,
        );
        expect(bobDecrypt['ok'], isNot(true));
      },
    );
  });
}

class _MlKemKey {
  final String publicKey;
  final String secretKey;
  const _MlKemKey(this.publicKey, this.secretKey);
}

Future<_MlKemKey> _generateMlKem(GoBridgeClient bridge) async {
  final response = await bridge.send(
    jsonEncode({'cmd': 'mlkem.keygen', 'payload': {}}),
  );
  final result = jsonDecode(response) as Map<String, dynamic>;
  expect(result['ok'], isTrue, reason: '$result');
  return _MlKemKey(
    result['publicKey'] as String,
    result['secretKey'] as String,
  );
}

Future<IdentityModel> _generateIdentity({
  required GoBridgeClient bridge,
  required String username,
}) async {
  final identityResponse = await bridge.send(
    jsonEncode({'cmd': 'identity.generate', 'payload': {}}),
  );
  final identityResult = jsonDecode(identityResponse) as Map<String, dynamic>;
  expect(identityResult['ok'], isTrue, reason: '$identityResult');
  final identity = identityResult['identity'] as Map<String, dynamic>;

  final mlKem = await _generateMlKem(bridge);

  final now = DateTime.now().toUtc().toIso8601String();
  return IdentityModel(
    peerId: identity['peerId'] as String,
    publicKey: identity['publicKey'] as String,
    privateKey: identity['privateKey'] as String,
    mnemonic12: identity['mnemonic12'] as String? ?? 'integration mnemonic',
    mlKemPublicKey: mlKem.publicKey,
    mlKemSecretKey: mlKem.secretKey,
    username: username,
    createdAt: now,
    updatedAt: now,
  );
}

Future<Map<String, dynamic>> _groupEncryptRaw({
  required GoBridgeClient bridge,
  required String groupKey,
  required String plaintext,
}) async {
  final response = await bridge.send(
    jsonEncode({
      'cmd': 'group.encrypt',
      'payload': {'plaintext': plaintext, 'groupKey': groupKey},
    }),
  );
  return jsonDecode(response) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _groupDecryptRaw({
  required GoBridgeClient bridge,
  required String groupKey,
  required Map<String, dynamic> ciphertext,
}) async {
  final response = await bridge.send(
    jsonEncode({
      'cmd': 'group.decrypt',
      'payload': {
        'ciphertext': ciphertext['ciphertext'],
        'nonce': ciphertext['nonce'],
        'groupKey': groupKey,
      },
    }),
  );
  return jsonDecode(response) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _groupEncrypt({
  required GoBridgeClient bridge,
  required String groupKey,
  required String plaintext,
}) async {
  final encrypted = await _groupEncryptRaw(
    bridge: bridge,
    groupKey: groupKey,
    plaintext: plaintext,
  );
  expect(encrypted['ok'], isTrue, reason: '$encrypted');
  return encrypted;
}

Future<String> _groupDecrypt({
  required GoBridgeClient bridge,
  required String groupKey,
  required Map<String, dynamic> ciphertext,
}) async {
  final decrypted = await _groupDecryptRaw(
    bridge: bridge,
    groupKey: groupKey,
    ciphertext: ciphertext,
  );
  expect(decrypted['ok'], isTrue, reason: '$decrypted');
  return decrypted['plaintext'] as String;
}

class _InMemoryDistributionRepo
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
    return GroupPendingKeyDistributionUpsertResult(
      distribution: existing,
      created: false,
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
  }) async => rows.values
      .where(
        (r) =>
            r.peerId == peerId &&
            (groupId == null || r.groupId == groupId) &&
            r.status == groupPendingKeyDistributionStatusPending,
      )
      .toList();

  @override
  Future<List<GroupPendingKeyDistribution>> getPendingForGroup({
    required String groupId,
    int limit = 50,
  }) async => rows.values
      .where(
        (r) =>
            r.groupId == groupId &&
            r.status == groupPendingKeyDistributionStatusPending,
      )
      .toList();

  @override
  Future<void> recordAttempt(String id, {required String? lastError}) async {
    final e = rows[id];
    if (e == null) return;
    rows[id] = e.copyWith(attempts: e.attempts + 1, lastError: lastError);
  }

  @override
  Future<void> finalizeDistributed(String id) async {
    final e = rows[id];
    if (e == null || e.finalizedAt != null) return;
    rows[id] = e.copyWith(
      status: groupPendingKeyDistributionStatusDistributed,
      finalizedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> finalizeUnreachable(String id, {required String lastError}) async {
    final e = rows[id];
    if (e == null || e.finalizedAt != null) return;
    rows[id] = e.copyWith(
      status: groupPendingKeyDistributionStatusUnreachable,
      lastError: lastError,
      finalizedAt: DateTime.now().toUtc(),
    );
  }
}
