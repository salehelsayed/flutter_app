/// Real-bridge device proof for Finding 02 Slice 1 (undecryptable group-message
/// self-heal).
///
/// A group message that is undecryptable while the receiving device is missing
/// the epoch key creates a `pending_key` repair + placeholder. While the key is
/// merely absent the repair is NEVER branded undecryptable (UDM-C non-terminal);
/// once the real key arrives the repair decrypts the REAL Go AES-256-GCM /
/// ed25519 offline-replay envelope and renders the recovered plaintext in place,
/// with NO duplicate (UDM-A supersede + UDM-B sweep). A second case proves the
/// bounded finalize: a CONFIRMED ed25519 authenticity failure stays pending
/// until the attempt budget is spent, then — and only then — finalizes
/// undecryptable (UDM-C). All crypto runs against the real Go ML-KEM-768 bridge.
@Tags(['device'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/create_group_use_case.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_repair.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

import '../test/shared/fakes/in_memory_group_message_repository.dart';
import '../test/shared/fakes/in_memory_group_pending_key_repair_repository.dart';
import '../test/shared/fakes/in_memory_group_repository.dart';
import '../test/shared/fakes/in_memory_inbox_staging_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('real-crypto undecryptable group-message self-heal (Finding 02 Slice 1)',
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
        // createGroup mints the real group key through the Go bridge, which needs
        // a started node (pubsub). Mirror the converge proof's node bootstrap.
        await _startNode(bridge, alice);
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final repairRepo = InMemoryGroupPendingKeyRepairRepository();

        // Real group + real epoch key (Alice is the creator/admin member).
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

        // Alice composes a REAL signed (ed25519) + encrypted (AES-256-GCM)
        // offline-replay envelope. Omitting senderDeviceId/transportPeerId lets
        // them default to her peerId, matching the legacy signing-device
        // synthesized from her creator member — so the signature verifies.
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

        // Receiver stores the pending_key repair + placeholder from the relay.
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

        // The replay/persist seam: on a successful real decrypt, persist the
        // recovered message under the repair's id, replacing the placeholder.
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

        // PHASE 1 — the device is "offline across the rotation": it does not yet
        // hold the epoch key. The repair must stay pending, NEVER undecryptable.
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

        // PHASE 2 — the epoch key ARRIVES (key-update distributed to the device).
        await groupRepo.saveKey(epochKey);
        final healed = await runner.retryAllPending();
        expect(healed, 1, reason: 'real Go AES-GCM decrypt recovers the message');
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
        expect(healedMsg.status, isNot(groupPendingKeyRepairStatusPendingKey));
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
        // createGroup mints the real group key through the Go bridge, which needs
        // a started node (pubsub). Mirror the converge proof's node bootstrap.
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
        // Corrupt one byte of the ed25519 signature — the signedPayload (and so
        // every binding) is untouched, so verification reaches the real ed25519
        // check and fails authentically with `signature_invalid` (a CONFIRMED
        // crypto failure, the only class that may ever finalize undecryptable).
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

        // Below the budget → one more attempt, stays pending (NOT terminal).
        await seed('tamper-below', kGroupKeyRepairMaxAttempts - 2);
        // At the budget → this retry finalizes undecryptable.
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
        expect(flowEvents, contains('GROUP_PENDING_KEY_REPAIR_UNDECRYPTABLE'));
      },
    );
  });
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
