/// Real-bridge device proof for Finding 03 Slice 2 (deferred-distribution
/// convergence). Extends the Slice 1 proof past where it stops: a keyless
/// bystander (Carol) is deferred at rotation time, then GAINS a real ML-KEM key,
/// and the `GroupPendingKeyDistributionRunner` re-distributes the CURRENT group
/// key to her — after which she can decrypt new-epoch traffic, all against the
/// real Go ML-KEM-768 / AES-GCM bridge.
///
/// Also hosts the Finding 02 (undecryptable group-message self-heal) real-crypto
/// proof — folded into THIS entrypoint to reuse its compiled build (0 new app
/// builds, per the 124 integration-harness build-cost rule), since it needs the
/// identical GoBridgeClient + createGroup + offline-replay-envelope harness.
@Tags(['device'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/create_group_use_case.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_distribution_service.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_distribution.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_repair.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_distribution_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

import '../test/shared/fakes/in_memory_group_message_repository.dart';
import '../test/shared/fakes/in_memory_group_pending_key_repair_repository.dart';
import '../test/shared/fakes/in_memory_group_repository.dart';
import '../test/shared/fakes/in_memory_inbox_staging_repository.dart';
import '_support/canonical_runtime_device_test_lease.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final runtimeLease = CanonicalRuntimeDeviceTestLease(
    binding: 'group-removal-rotation-keyless-converge-device-test',
  );
  setUpAll(runtimeLease.acquire);
  tearDownAll(runtimeLease.release);

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

  // Finding 02 (undecryptable group-message self-heal) — folded here to reuse
  // this entrypoint's build (0 new app builds). Same real Go ML-KEM/AES-GCM
  // bridge + createGroup + offline-replay harness as the convergence proof above.
  group(
    'real-crypto undecryptable group-message self-heal (Finding 02 Slice 1)',
    () {
      late GoBridgeClient bridge;
      final flowEvents = <String>[];

      setUp(() async {
        bridge = GoBridgeClient();
        await bridge.initialize();
        flowEventLoggingEnabled = true;
        flowEvents.clear();
        debugSetFlowEventSink((payload) {
          final event = payload['event'];
          if (event is String) flowEvents.add(event);
        });
      });

      tearDown(() {
        debugSetFlowEventSink(null);
        bridge.dispose();
      });

      testWidgets(
        'a message undecryptable while the key is missing self-heals once the '
        'key arrives — real crypto, no duplicate',
        (tester) async {
          final alice = await _generateIdentity(bridge: bridge, username: 'Alice');
          await _startNode(bridge, alice);
          final groupRepo = InMemoryGroupRepository();
          final msgRepo = InMemoryGroupMessageRepository();
          final repairRepo = InMemoryGroupPendingKeyRepairRepository();

          final group = await createGroup(
            bridge: bridge,
            groupRepo: groupRepo,
            name: 'Self-Heal Proof',
            type: GroupType.chat,
            creatorPeerId: alice.peerId,
            creatorPublicKey: alice.publicKey,
            creatorMlKemPublicKey: alice.mlKemPublicKey!,
            creatorUsername: alice.username,
          );
          final groupId = group.id;
          final epochKey = (await groupRepo.getLatestKey(groupId))!;

          const plaintextBody =
              'the message that was undecryptable while the key was missing';
          final innerPlaintext = jsonEncode({
            'text': plaintextBody,
            'senderId': alice.peerId,
            'senderUsername': alice.username,
            'messageId': 'selfheal-1',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          });
          final rawEnvelope = await buildGroupOfflineReplayEnvelope(
            bridge: bridge,
            groupRepo: groupRepo,
            groupId: groupId,
            payloadType: groupOfflineReplayPayloadTypeMessage,
            plaintext: innerPlaintext,
            messageId: 'selfheal-1',
            senderPeerId: alice.peerId,
            senderPublicKey: alice.publicKey,
            senderPrivateKey: alice.privateKey,
            keyInfo: epochKey,
          );
          final replayEnvelope = jsonDecode(rawEnvelope) as Map<String, dynamic>;
          expect(isGroupOfflineReplayEnvelope(replayEnvelope), isTrue);
          final messageId = replayEnvelope['messageId'] as String;
          final repairId = offlineGroupPendingKeyRepairId(
            groupId: groupId,
            messageId: messageId,
          );

          final queued = await queueMissingGroupReplayKeyRepairFromEnvelope(
            pendingKeyRepairRepo: repairRepo,
            msgRepo: msgRepo,
            groupId: groupId,
            relayEnvelope: {
              'from': alice.peerId,
              'timestamp': DateTime.now().toUtc().toIso8601String(),
            },
            replayEnvelope: replayEnvelope,
            requestGroupKeyRepair: (_) async {},
          );
          expect(queued, isTrue);
          expect(
            (await msgRepo.getMessage(messageId))!.text,
            groupPendingKeyRepairPlaceholderText,
          );
          expect(
            (await repairRepo.getRepair(repairId))!.status,
            groupPendingKeyRepairStatusPendingKey,
          );
          expect(await msgRepo.getMessageCount(groupId), 1);

          final replayed = <Map<String, dynamic>>[];
          final runner = GroupPendingKeyRepairRunner(
            bridge: bridge,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            pendingKeyRepairRepo: repairRepo,
            replayGroupEnvelope: (payload) async {
              replayed.add(payload);
              await msgRepo.saveMessage(
                GroupMessage(
                  id: payload['messageId'] as String,
                  groupId: payload['groupId'] as String,
                  senderPeerId: payload['senderId'] as String? ?? 'unknown',
                  transportPeerId: payload['transportPeerId'] as String?,
                  senderUsername: payload['senderUsername'] as String?,
                  text: payload['text'] as String? ?? '',
                  timestamp: DateTime.parse(payload['timestamp'] as String),
                  keyGeneration: payload['keyEpoch'] as int,
                  status: 'delivered',
                  isIncoming: true,
                  createdAt: DateTime.now().toUtc(),
                ),
              );
            },
          );

          // PHASE 1 — offline across the rotation: epoch key absent -> stay pending.
          await groupRepo.removeAllKeys(groupId);
          final healedWhileMissing = await runner.retryAllPending();
          expect(healedWhileMissing, 0);
          final pending = (await repairRepo.getRepair(repairId))!;
          expect(pending.status, groupPendingKeyRepairStatusPendingKey);
          expect(pending.attempts, greaterThan(0));
          expect(
            (await msgRepo.getMessage(messageId))!.text,
            groupPendingKeyRepairPlaceholderText,
            reason: 'a missing key is never terminal — still the placeholder',
          );
          expect(replayed, isEmpty);
          expect(
            flowEvents,
            isNot(contains('GROUP_PENDING_KEY_REPAIR_UNDECRYPTABLE')),
          );

          // PHASE 2 — the epoch key arrives -> real decrypt heals, no duplicate.
          await groupRepo.saveKey(epochKey);
          final healed = await runner.retryAllPending();
          expect(
            healed,
            1,
            reason: 'real Go AES-GCM decrypt recovers the message',
          );
          expect(
            (await repairRepo.getRepair(repairId))!.status,
            groupPendingKeyRepairStatusRepaired,
          );
          final healedMsg = (await msgRepo.getMessage(messageId))!;
          expect(
            healedMsg.text,
            plaintextBody,
            reason: 'the REAL plaintext was recovered via real crypto',
          );
          expect(
            healedMsg.status,
            isNot(groupPendingKeyRepairStatusPendingKey),
          );
          expect(
            await msgRepo.getMessageCount(groupId),
            1,
            reason: 'placeholder superseded in place — no duplicate',
          );
          expect(replayed.single['text'], plaintextBody);
          expect(flowEvents, contains('GROUP_PENDING_KEY_REPAIR_REPAIRED'));
          expect(flowEvents, contains('GROUP_PENDING_KEY_REPAIR_SWEEP'));
        },
      );

      testWidgets(
        'a CONFIRMED ed25519 authenticity failure stays pending until the budget '
        'is spent, then finalizes undecryptable (bounded)',
        (tester) async {
          final alice = await _generateIdentity(bridge: bridge, username: 'Alice');
          await _startNode(bridge, alice);
          final groupRepo = InMemoryGroupRepository();
          final msgRepo = InMemoryGroupMessageRepository();
          final repairRepo = InMemoryGroupPendingKeyRepairRepository();

          final group = await createGroup(
            bridge: bridge,
            groupRepo: groupRepo,
            name: 'Bounded Finalize Proof',
            type: GroupType.chat,
            creatorPeerId: alice.peerId,
            creatorPublicKey: alice.publicKey,
            creatorMlKemPublicKey: alice.mlKemPublicKey!,
            creatorUsername: alice.username,
          );
          final groupId = group.id;
          final epochKey = (await groupRepo.getLatestKey(groupId))!;

          final innerPlaintext = jsonEncode({
            'text': 'authentic body that will never be trusted',
            'senderId': alice.peerId,
            'messageId': 'tamper-src',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          });
          final rawEnvelope = await buildGroupOfflineReplayEnvelope(
            bridge: bridge,
            groupRepo: groupRepo,
            groupId: groupId,
            payloadType: groupOfflineReplayPayloadTypeMessage,
            plaintext: innerPlaintext,
            messageId: 'tamper-src',
            senderPeerId: alice.peerId,
            senderPublicKey: alice.publicKey,
            senderPrivateKey: alice.privateKey,
            keyInfo: epochKey,
          );
          final envelope = jsonDecode(rawEnvelope) as Map<String, dynamic>;
          // Corrupt one byte of the ed25519 signature -> CONFIRMED authenticity
          // failure (signature_invalid); the signedPayload/bindings stay intact.
          final sig = envelope['signature'] as String;
          final flipped = sig[5] == 'A' ? 'B' : 'A';
          envelope['signature'] = sig.replaceRange(5, 6, flipped);
          final tamperedJson = jsonEncode(envelope);

          Future<void> seed(String id, int attempts) async {
            final now = DateTime.now().toUtc();
            await repairRepo.upsertPendingRepair(
              GroupPendingKeyRepair(
                id: id,
                groupId: groupId,
                messageId: id,
                senderPeerId: alice.peerId,
                transportPeerId: alice.peerId,
                payloadType: groupOfflineReplayPayloadTypeMessage,
                keyEpoch: epochKey.keyGeneration,
                replayEnvelopeJson: tamperedJson,
                status: groupPendingKeyRepairStatusPendingKey,
                attempts: attempts,
                createdAt: now,
                updatedAt: now,
              ),
            );
            await msgRepo.saveMessage(
              GroupMessage(
                id: id,
                groupId: groupId,
                senderPeerId: alice.peerId,
                transportPeerId: alice.peerId,
                senderUsername: null,
                text: groupPendingKeyRepairPlaceholderText,
                timestamp: now,
                keyGeneration: epochKey.keyGeneration,
                status: groupPendingKeyRepairStatusPendingKey,
                isIncoming: true,
                createdAt: now,
              ),
            );
          }

          // Below the budget -> one more attempt, stays pending (NOT terminal).
          await seed('tamper-below', kGroupKeyRepairMaxAttempts - 2);
          // At the budget -> this retry finalizes undecryptable.
          await seed('tamper-at', kGroupKeyRepairMaxAttempts);

          final runner = GroupPendingKeyRepairRunner(
            bridge: bridge,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            pendingKeyRepairRepo: repairRepo,
          );
          await runner.retryAllPending();

          final below = (await repairRepo.getRepair('tamper-below'))!;
          expect(below.status, groupPendingKeyRepairStatusPendingKey);
          expect(below.attempts, kGroupKeyRepairMaxAttempts - 1);
          expect(
            (await msgRepo.getMessage('tamper-below'))!.text,
            groupPendingKeyRepairPlaceholderText,
          );

          final at = (await repairRepo.getRepair('tamper-at'))!;
          expect(at.status, groupPendingKeyRepairStatusUndecryptable);
          expect(
            (await msgRepo.getMessage('tamper-at'))!.text,
            'Message could not be decrypted.',
          );
          expect(
            flowEvents,
            contains('GROUP_PENDING_KEY_REPAIR_UNDECRYPTABLE'),
          );
        },
      );
    },
  );
}

Future<P2PServiceImpl> _startNode(
  GoBridgeClient bridge,
  IdentityModel identity,
) async {
  final node = P2PServiceImpl(
    bridge: bridge,
    inboxStagingRepository: InMemoryInboxStagingRepository(),
  );
  addTearDown(() async {
    await node.stopNode();
    node.dispose();
  });
  expect(
    await node.startNodeCore(identity.privateKey, identity.peerId),
    isTrue,
  );
  return node;
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
  Future<void> reopenForRedelivery(
    GroupPendingKeyDistribution distribution,
  ) async {
    final existing = rows[distribution.id];
    if (existing == null) {
      rows[distribution.id] = distribution;
      return;
    }
    final requestedCreatedAt = distribution.createdAt.toUtc();
    final minimumNextCreatedAt = existing.createdAt.toUtc().add(
      const Duration(microseconds: 1),
    );
    rows[distribution.id] = existing.copyWith(
      status: groupPendingKeyDistributionStatusPending,
      keyEpoch: distribution.keyEpoch,
      attempts: 0,
      lastError: null,
      createdAt: requestedCreatedAt.isAfter(minimumNextCreatedAt)
          ? requestedCreatedAt
          : minimumNextCreatedAt,
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
