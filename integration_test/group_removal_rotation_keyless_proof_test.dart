/// Real-bridge device proof for Finding 03 Slice 1 (removal-rotation fails-closed).
///
/// Scenario (the P0): an admin removes a keyed member (Bob) while a *different*
/// remaining member (Carol) is KEYLESS (no ML-KEM key). Promote-then-defer must:
///   1. still GENERATE + PROMOTE a real new epoch (the removed member loses the
///      live key — forward secrecy for the boundary), and
///   2. record the keyless bystander as DEFERRED, not abort the rotation.
///
/// Verified end-to-end against the REAL Go ML-KEM / AES-GCM bridge on-device:
/// a message published at the new epoch is readable with the new key but NOT with
/// the removed member's retained old key.
@Tags(['device'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/create_group_use_case.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

import '../test/shared/fakes/in_memory_inbox_staging_repository.dart';
import '../test/shared/fakes/in_memory_group_repository.dart';
import '_support/canonical_runtime_device_test_lease.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final runtimeLease = CanonicalRuntimeDeviceTestLease(
    binding: 'group-removal-rotation-keyless-device-test',
  );
  setUpAll(runtimeLease.acquire);
  tearDownAll(runtimeLease.release);

  group('real-crypto removal-rotation fails-closed (Finding 03 Slice 1)', () {
    late GoBridgeClient bridge;

    setUp(() async {
      bridge = GoBridgeClient();
      await bridge.initialize();
    });

    tearDown(() {
      bridge.dispose();
    });

    testWidgets(
      'admin removal promotes a real new epoch and defers the keyless bystander; '
      'removed member cannot read new-epoch traffic',
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
        final group = await createGroup(
          bridge: bridge,
          groupRepo: groupRepo,
          name: 'Removal Rotation Proof',
          type: GroupType.chat,
          creatorPeerId: alice.peerId,
          creatorPublicKey: alice.publicKey,
          creatorMlKemPublicKey: alice.mlKemPublicKey!,
          creatorUsername: alice.username,
        );
        final groupId = group.id;

        // Bob is a keyed member who will be removed (the boundary).
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
        // Carol is a KEYLESS remaining bystander (no ML-KEM key on any device).
        // Pre-fix this aborted the rotation and re-granted Bob the key.
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
        expect(epoch1, isNotNull);
        // The last group key Bob legitimately held before removal.
        final bobRetainedKey = epoch1!.encryptedKey;

        // 1. Remove Bob from the group (boundary member out).
        await groupRepo.removeMember(groupId, bob.peerId);

        // 2. Rotate against the REAL bridge with a keyless remaining bystander.
        final sentTargets = <String>[];
        final outcome = await rotateAndDistributeGroupKey(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sendP2PMessage: (peerId, message) async {
            sentTargets.add(peerId);
            return true;
          },
        );

        // Promote-then-defer: a REAL new epoch was generated + promoted even
        // though Carol is keyless (INV-R1 durable exclusion, INV-R4).
        expect(outcome.rotated, isTrue, reason: 'real epoch must promote');
        expect(outcome.key!.keyGeneration, epoch1.keyGeneration + 1);
        expect(outcome.fullyDistributed, isFalse);
        expect(outcome.deferredPeerIds, <String>[carol.peerId]);

        final epoch2 = await groupRepo.getLatestKey(groupId);
        expect(epoch2!.keyGeneration, epoch1.keyGeneration + 1);
        expect(
          epoch2.encryptedKey,
          isNot(epoch1.encryptedKey),
          reason: 'a genuinely new real key must be persisted',
        );
        // Bob is gone and stays gone; he was never a distribution target.
        expect(await groupRepo.getMember(groupId, bob.peerId), isNull);
        expect(sentTargets, isNot(contains(bob.peerId)));

        // 3. Forward secrecy against the REAL crypto: a message published at the
        // NEW epoch is readable with the new key, but NOT with Bob's retained
        // OLD key (the removed member can no longer read new-epoch traffic).
        final newEpochCipher = await _groupEncrypt(
          bridge: bridge,
          groupKey: epoch2.encryptedKey,
          plaintext: 'post-removal new-epoch message',
        );
        expect(
          await _groupDecrypt(
            bridge: bridge,
            groupKey: epoch2.encryptedKey,
            ciphertext: newEpochCipher,
          ),
          'post-removal new-epoch message',
          reason: 'a current member reads the new epoch with the new key',
        );
        final bobDecrypt = await _groupDecryptRaw(
          bridge: bridge,
          groupKey: bobRetainedKey,
          ciphertext: newEpochCipher,
        );
        expect(
          bobDecrypt['ok'],
          isNot(true),
          reason: 'removed member must not read new-epoch traffic with old key',
        );
      },
    );
  });
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

  final mlKemResponse = await bridge.send(
    jsonEncode({'cmd': 'mlkem.keygen', 'payload': {}}),
  );
  final mlKemResult = jsonDecode(mlKemResponse) as Map<String, dynamic>;
  expect(mlKemResult['ok'], isTrue, reason: '$mlKemResult');

  final now = DateTime.now().toUtc().toIso8601String();
  return IdentityModel(
    peerId: identity['peerId'] as String,
    publicKey: identity['publicKey'] as String,
    privateKey: identity['privateKey'] as String,
    mnemonic12: identity['mnemonic12'] as String? ?? 'integration mnemonic',
    mlKemPublicKey: mlKemResult['publicKey'] as String,
    mlKemSecretKey: mlKemResult['secretKey'] as String,
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
