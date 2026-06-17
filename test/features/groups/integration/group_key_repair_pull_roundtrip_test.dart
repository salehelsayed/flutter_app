import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/group_key_repair_responder_listener.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

/// G-B (Finding 02 Slice 2 / UDM-G): the active key-pull end-to-end.
///
/// The sender ([GroupKeyRepairRequestSender]) and responder
/// ([GroupKeyRepairResponderListener]) each had isolated unit coverage, but NO
/// single test exercised both across a transport — so envelope-shape drift,
/// admin-transport resolution, or placeholder-supersede regressions could pass
/// both isolated suites. This wires Bob's REAL sender to Alice's REAL responder
/// over a routed channel: Bob's signed `group_key_repair_request` is delivered
/// verbatim (no test-crafted replay envelope) and Alice re-delivers the EXACT
/// requested epoch via `getKeyByGeneration` — never `getLatestKey`, never a mint.
///
/// Real ML-KEM 2-device crypto stays the device-matrix proof; here FakeBridge's
/// sign/verify round-trip stands in for the signature plumbing.
void main() {
  const groupId = 'grp-udmg-roundtrip';

  const alicePeerId = 'alice-admin';
  const aliceDeviceId = 'alice-device';
  const aliceTransport = 'alice-transport';

  const bobPeerId = 'bob';
  const bobDeviceId = 'bob-device';
  const bobTransport = 'bob-transport';
  const bobSigningKey = 'sign-bob';

  GroupModel group() => GroupModel(
    id: groupId,
    name: 'Round Trip Group',
    type: GroupType.chat,
    topicName: '/mknoon/group/$groupId',
    createdAt: DateTime.utc(2026, 4, 5, 12),
    createdBy: alicePeerId, // creator => responder self-authz passes
    myRole: GroupRole.admin,
  );

  GroupMember aliceMember() => GroupMember(
    groupId: groupId,
    peerId: alicePeerId,
    username: 'Alice',
    role: MemberRole.admin,
    publicKey: 'pk-alice',
    mlKemPublicKey: 'mlkem-alice',
    devices: const [
      GroupMemberDeviceIdentity(
        deviceId: aliceDeviceId,
        transportPeerId: aliceTransport,
        deviceSigningPublicKey: 'sign-alice',
        mlKemPublicKey: 'mlkem-alice-device',
      ),
    ],
    joinedAt: DateTime.utc(2026, 4, 5, 12),
  );

  GroupMember bobMember() => GroupMember(
    groupId: groupId,
    peerId: bobPeerId,
    username: 'Bob',
    role: MemberRole.writer,
    publicKey: 'pk-bob',
    mlKemPublicKey: 'mlkem-bob',
    devices: const [
      GroupMemberDeviceIdentity(
        deviceId: bobDeviceId,
        transportPeerId: bobTransport,
        deviceSigningPublicKey: bobSigningKey,
        mlKemPublicKey: 'mlkem-bob-device',
      ),
    ],
    joinedAt: DateTime.utc(2026, 4, 5, 12, 1),
  );

  GroupKeyInfo keyAt(int epoch) => GroupKeyInfo(
    groupId: groupId,
    keyGeneration: epoch,
    encryptedKey: 'key-v$epoch',
    createdAt: DateTime.utc(2026, 4, 5, 12, epoch),
  );

  late FakeBridge bridge;
  late InMemoryGroupRepository adminRepo; // Alice — responder side
  late InMemoryGroupRepository bobRepo; // Bob — requester side
  late StreamController<ChatMessage> adminInbox;
  late GroupKeyRepairResponderListener responder;
  late GroupKeyRepairRequestSender sender;
  late List<({String groupId, String peerId, int keyEpoch})> deliveries;
  late List<(String, String)> bobSends;

  // Builds the two-party topology. [adminKnowsBob] lets the non-member case
  // omit Bob from Alice's roster while still routing his real request to her.
  Future<void> wireParties({bool adminKnowsBob = true}) async {
    bridge = FakeBridge(); // payload.sign returns a signature; payload.verify valid
    adminRepo = InMemoryGroupRepository();
    bobRepo = InMemoryGroupRepository();
    adminInbox = StreamController<ChatMessage>.broadcast();
    deliveries = [];
    bobSends = [];

    // Alice (admin) holds epochs 1, 2, 3 (latest 3). Bob requests epoch 2 — the
    // missing middle epoch — so a correct responder serves epoch 2 (held, via
    // getKeyByGeneration) and a buggy one serving getLatestKey would serve 3.
    await adminRepo.saveGroup(group());
    await adminRepo.saveMember(aliceMember());
    if (adminKnowsBob) {
      await adminRepo.saveMember(bobMember());
    }
    await adminRepo.saveKey(keyAt(1));
    await adminRepo.saveKey(keyAt(2));
    await adminRepo.saveKey(keyAt(3));

    // Bob holds only epoch 1 (behind) and knows Alice as admin so his sender can
    // resolve her transport peer.
    await bobRepo.saveGroup(group().copyWith(myRole: GroupRole.member));
    await bobRepo.saveMember(aliceMember());
    await bobRepo.saveMember(bobMember());
    await bobRepo.saveKey(keyAt(1));

    responder = GroupKeyRepairResponderListener(
      groupKeyRepairRequestStream: adminInbox.stream,
      groupRepo: adminRepo,
      bridge: bridge,
      getOwnPeerId: () async => alicePeerId,
      distributeGroupKeyAtEpochToPeer: ({
        required String groupId,
        required String peerId,
        required int keyEpoch,
      }) async {
        deliveries.add((groupId: groupId, peerId: peerId, keyEpoch: keyEpoch));
        // Simulate the ML-KEM re-delivery landing in the recipient's store: only
        // the EXACT epoch the responder resolved via getKeyByGeneration, never a
        // mint. (Real per-device encryption is the device-matrix proof.)
        final epochKey = await adminRepo.getKeyByGeneration(groupId, keyEpoch);
        if (epochKey != null && peerId == bobPeerId) {
          await bobRepo.saveKey(epochKey);
        }
        return epochKey == null ? 0 : 1;
      },
    );
    responder.start();

    sender = GroupKeyRepairRequestSender(
      bridge: bridge,
      groupRepo: bobRepo,
      getOwnPeerId: () async => bobPeerId,
      getOwnDeviceId: () async => bobDeviceId,
      getOwnPrivateKey: () async => 'sk-bob',
      // The "network": route Bob's direct send verbatim into Alice's responder
      // stream as the incoming repair request.
      sendP2PMessage: (peer, message) async {
        bobSends.add((peer, message));
        adminInbox.add(
          ChatMessage(
            from: bobTransport,
            to: peer,
            content: message,
            timestamp: DateTime.now().toUtc().toIso8601String(),
            isIncoming: true,
          ),
        );
        return true;
      },
    );
  }

  tearDown(() async {
    responder.dispose();
    await adminInbox.close();
  });

  Future<void> bobRequests(int epoch) async {
    await sender.call(
      GroupKeyRepairRequest(
        groupId: groupId,
        keyEpoch: epoch,
        reason: 'received_message_epoch_missing_local_key',
        messageId: 'msg-epoch-$epoch',
      ),
    );
    // Let the responder's serialized processing drain.
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }

  test(
    'Bob real sender -> Alice real responder re-delivers the EXACT missing '
    'epoch (getKeyByGeneration, never getLatestKey, never a mint) and Bob '
    'converges',
    () async {
      await wireParties();
      // Precondition: Bob is behind — he lacks epoch 2.
      expect(await bobRepo.getKeyByGeneration(groupId, 2), isNull);

      await bobRequests(2);

      // The real sender produced exactly one signed request to Alice's transport.
      expect(bobSends, hasLength(1));
      expect(bobSends.single.$1, aliceTransport);
      final envelope = jsonDecode(bobSends.single.$2) as Map<String, dynamic>;
      expect(envelope['type'], groupKeyRepairRequestType);
      final payload = envelope['payload'] as Map<String, dynamic>;
      // The request binds the requester's device/transport identity (guards the
      // B4-dissolve device/transport_mismatch trap).
      expect(payload['requesterPeerId'], bobPeerId);
      expect(payload['requesterDeviceId'], bobDeviceId);
      expect(payload['keyEpoch'], 2);
      expect((payload['signature'] as String).isNotEmpty, isTrue);
      expect(bridge.commandLog, contains('payload.sign'));

      // The responder actually ran its signature-verification gate on the
      // received request (the adversarial test below proves it is load-bearing).
      expect(bridge.commandLog, contains('payload.verify'));

      // The responder served the EXACT requested epoch — not the latest (3).
      expect(deliveries, hasLength(1));
      expect(deliveries.single.peerId, bobPeerId);
      expect(deliveries.single.keyEpoch, 2);

      // No epoch minted / promoted: Alice never calls group:updateKey and her
      // latest key is unchanged.
      expect(bridge.commandLog, isNot(contains('group:updateKey')));
      expect((await adminRepo.getLatestKey(groupId))!.keyGeneration, 3);

      // Bob converged on the requested epoch ONLY (the responder delivered the
      // exact epoch, not the latest — Bob did not silently gain epoch 3).
      final bobEpoch2 = await bobRepo.getKeyByGeneration(groupId, 2);
      expect(bobEpoch2, isNotNull);
      expect(bobEpoch2!.encryptedKey, 'key-v2');
      expect(await bobRepo.getKeyByGeneration(groupId, 3), isNull);
    },
  );

  test('duplicate identical requests are rate-limited to one re-delivery',
      () async {
    await wireParties();

    await bobRequests(2);
    await bobRequests(2);
    await bobRequests(2);

    // The sender sent three real requests; the responder served exactly one.
    expect(bobSends, hasLength(3));
    expect(deliveries.where((d) => d.keyEpoch == 2), hasLength(1));
  });

  test('a request for a peer Alice does not recognize as a member is rejected',
      () async {
    await wireParties(adminKnowsBob: false);

    await bobRequests(2);

    // Bob's real request still reached Alice over the channel...
    expect(bobSends, hasLength(1));
    // ...but the responder rejected it (requester_not_member) — no re-delivery
    // and Bob stays behind.
    expect(deliveries, isEmpty);
    expect(await bobRepo.getKeyByGeneration(groupId, 2), isNull);
  });

  test(
    'a request whose signature fails verification is rejected (the responder '
    'signature gate is load-bearing)',
    () async {
      await wireParties();
      // Force the responder's signature-verification gate to fail. Bob still
      // signs and sends a well-formed request (payload.sign is unaffected), so
      // a regression that dropped the verify gate would otherwise deliver.
      bridge.responses['payload.verify'] = {'ok': true, 'valid': false};

      await bobRequests(2);

      expect(bobSends, hasLength(1));
      expect(bridge.commandLog, contains('payload.verify'));
      // Rejected on invalid_signature: no re-delivery, Bob stays behind.
      expect(deliveries, isEmpty);
      expect(await bobRepo.getKeyByGeneration(groupId, 2), isNull);
    },
  );
}
