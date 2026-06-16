import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/admit_sibling_device_use_case.dart';
import 'package:flutter_app/features/groups/application/group_key_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_distribution_service.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_distribution.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/group_test_user.dart';
import '../../../shared/fakes/fake_group_pubsub_network.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_pending_key_distribution_repository.dart';

/// B1b END-TO-END sim (Part B of 12-P2): the keystone path the unit test stubs.
///
/// admit a DISTINCT same-user sibling device -> the real
/// GroupPendingKeyDistributionRunner re-distributes the CURRENT group key to it
/// over the (captured + replayed) 1:1 channel -> the sibling's own repo converges
/// to the current epoch and decrypts. Proves admission actually delivers the key,
/// not the unit test's drain spy. FakeBridge crypto is passthrough, so this
/// proves WIRING/ROUTING (admit -> enqueue -> drain -> distribute -> listener),
/// not real ML-KEM confidentiality (that needs the device matrix).
void main() {
  const groupId = 'group-b1b-sibling';
  const epochOneKey = 'group-key-epoch-1';
  const siblingDeviceId = 'bob-tablet';
  // In this identity model a device's transport peer id equals its device id.
  const siblingTransport = siblingDeviceId;
  const siblingSigningKey = 'bob-tablet-signing'; // DISTINCT per-device signing key
  const siblingMlKem = 'mlkem-bob-tablet'; // DISTINCT per-device ML-KEM key

  late FakeGroupPubSubNetwork network;
  late GroupTestUser alice;
  late GroupTestUser bob;

  // The sibling (bob's restored tablet): its own local DB + key-update listener,
  // hydrated with group state (B3 stand-in) but holding NO key yet.
  late InMemoryGroupRepository tabletRepo;
  late FakeBridge tabletBridge;
  late StreamController<ChatMessage> tabletKeyUpdates;
  late GroupKeyUpdateListener tabletKeyUpdateListener;

  late InMemoryGroupPendingKeyDistributionRepository pendingRepo;
  late GroupPendingKeyDistributionRunner runner;
  late List<String> sentTransports;

  final createdAt = DateTime.utc(2026, 6, 16, 12);

  Future<void> pump() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  IdentityModel aliceIdentity() => IdentityModel(
    peerId: alice.peerId,
    publicKey: alice.publicKey,
    privateKey: alice.privateKey,
    mlKemPublicKey: alice.mlKemPublicKey,
    username: alice.username,
    mnemonic12: 'a b c d e f g h i j k l',
    createdAt: createdAt.toIso8601String(),
    updatedAt: createdAt.toIso8601String(),
  );

  setUp(() async {
    network = FakeGroupPubSubNetwork();
    sentTransports = [];
    alice = GroupTestUser.create(peerId: 'alice', username: 'Alice', network: network);
    bob = GroupTestUser.create(peerId: 'bob', username: 'Bob', network: network);

    await alice.createGroup(groupId: groupId, name: 'B1b', createdAt: createdAt);
    await alice.addMember(
      groupId: groupId,
      invitee: bob,
      joinedAt: createdAt.add(const Duration(minutes: 1)),
    );

    Future<void> saveKey(GroupTestUser u) => u.groupRepo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: epochOneKey,
        createdAt: createdAt,
      ),
    );
    await saveKey(alice);
    await saveKey(bob);

    alice.start();
    bob.start();

    // Sibling tablet: hydrate group + roster (B3 stand-in copy), NO key.
    tabletRepo = InMemoryGroupRepository();
    final group = await alice.groupRepo.getGroup(groupId);
    await tabletRepo.saveGroup(group!.copyWith(myRole: GroupRole.member));
    for (final m in await alice.groupRepo.getMembers(groupId)) {
      await tabletRepo.saveMember(m);
    }
    // The restored tablet knows its OWN device identity, so its local roster's
    // bob member includes the tablet device (this is what the key-update
    // recipient-binding checks against). The admin's roster learns it via the
    // admission under test.
    final bobInTablet = await tabletRepo.getMember(groupId, bob.peerId);
    await tabletRepo.saveMember(
      bobInTablet!.copyWith(
        devices: [
          ...bobInTablet.devices,
          const GroupMemberDeviceIdentity(
            deviceId: siblingDeviceId,
            transportPeerId: siblingTransport,
            deviceSigningPublicKey: siblingSigningKey,
            mlKemPublicKey: siblingMlKem,
          ),
        ],
      ),
    );
    tabletBridge = FakeBridge();
    tabletKeyUpdates = StreamController<ChatMessage>.broadcast();
    tabletKeyUpdateListener = GroupKeyUpdateListener(
      groupKeyUpdateStream: tabletKeyUpdates.stream,
      groupRepo: tabletRepo,
      bridge: tabletBridge,
      getOwnMlKemSecretKey: () async => 'mlkem-secret-$siblingDeviceId',
      getOwnPeerId: () async => bob.peerId,
      getOwnDeviceId: () async => siblingDeviceId,
    );
    tabletKeyUpdateListener.start();

    // Real durable distribution runner driven by alice (the admin/sender),
    // with sendP2PMessage capturing the 1:1 key-update and replaying the one
    // addressed to the tablet into its listener stream.
    pendingRepo = InMemoryGroupPendingKeyDistributionRepository();
    runner = GroupPendingKeyDistributionRunner(
      bridge: alice.bridge,
      groupRepo: alice.groupRepo,
      repository: pendingRepo,
      loadIdentity: () async => aliceIdentity(),
      sendP2PMessage: (transportPeerId, message) async {
        sentTransports.add(transportPeerId);
        if (transportPeerId == siblingTransport) {
          tabletKeyUpdates.add(
            ChatMessage(
              from: alice.deviceId,
              to: transportPeerId,
              content: message,
              timestamp: createdAt
                  .add(const Duration(minutes: 5))
                  .toIso8601String(),
              isIncoming: true,
            ),
          );
        }
        return true;
      },
    );

    // Wire the process-wide enqueue + reopen + drain sinks to the in-memory repo
    // + runner, exactly as main.dart wires them in production. Admission uses the
    // REOPEN sink (which re-arms a terminal row); enqueue is wired for parity.
    GroupPendingKeyDistribution rowFor(String groupId, String peerId, int keyEpoch) =>
        GroupPendingKeyDistribution(
          id: groupPendingKeyDistributionId(groupId, peerId),
          groupId: groupId,
          peerId: peerId,
          keyEpoch: keyEpoch,
          createdAt: createdAt,
          updatedAt: createdAt,
        );
    setDeferredGroupKeyDistributionSink(({
      required String groupId,
      required String peerId,
      required int keyEpoch,
    }) async {
      await pendingRepo.enqueue(rowFor(groupId, peerId, keyEpoch));
    });
    setDeferredGroupKeyDistributionReopenSink(({
      required String groupId,
      required String peerId,
      required int keyEpoch,
    }) async {
      await pendingRepo.reopenForRedelivery(rowFor(groupId, peerId, keyEpoch));
    });
    setDeferredDistributionDrainSink(({
      required String groupId,
      required String peerId,
    }) async {
      await runner.drainPendingForPeer(groupId: groupId, peerId: peerId);
    });

    addTearDown(() async {
      setDeferredGroupKeyDistributionSink(null);
      setDeferredGroupKeyDistributionReopenSink(null);
      setDeferredDistributionDrainSink(null);
      await tabletKeyUpdates.close();
      tabletKeyUpdateListener.dispose();
      alice.dispose();
      bob.dispose();
    });
  });

  test(
    'admitting a distinct sibling device re-distributes the current key so the '
    'sibling converges',
    () async {
      // Precondition: the tablet has the group/roster but NOT the key.
      expect(await tabletRepo.getLatestKey(groupId), isNull);

      final bobMember = await alice.groupRepo.getMember(groupId, bob.peerId);

      final outcome = await admitSiblingDeviceIfTrusted(
        groupRepo: alice.groupRepo,
        groupId: groupId,
        memberPeerId: bob.peerId,
        announcedDeviceId: siblingDeviceId,
        announcedTransportPeerId: siblingTransport,
        announcedDeviceSigningPublicKey: siblingSigningKey,
        announcedMlKemPublicKey: siblingMlKem,
        verifiedAccountSigningPublicKey: bobMember!.publicKey!,
        multiDeviceSyncEnabled: true,
        // default enqueue + drain triggers hit the wired sinks above
      );
      await pump();

      expect(outcome, SiblingDeviceAdmissionOutcome.admitted);

      // The sibling device is now on bob's roster in the admin's repo.
      final updatedBob = await alice.groupRepo.getMember(groupId, bob.peerId);
      expect(
        updatedBob!.devices.any((d) => d.deviceId == siblingDeviceId),
        isTrue,
      );

      // The durable distribution row was created and finalized as distributed.
      final row = await pendingRepo.getDistribution(
        groupPendingKeyDistributionId(groupId, bob.peerId),
      );
      expect(row, isNotNull);
      expect(row!.status, groupPendingKeyDistributionStatusDistributed);

      // THE PROOF: the sibling converged to the CURRENT epoch via the runner
      // (re-distribution), not via a hand-copied key.
      final tabletKey = await tabletRepo.getLatestKey(groupId);
      expect(tabletKey, isNotNull);
      expect(tabletKey!.keyGeneration, 1);
      expect(tabletKey.encryptedKey, epochOneKey);
    },
  );

  test('an untrusted (wrong account key) announce delivers no key', () async {
    final outcome = await admitSiblingDeviceIfTrusted(
      groupRepo: alice.groupRepo,
      groupId: groupId,
      memberPeerId: bob.peerId,
      announcedDeviceId: siblingDeviceId,
      announcedTransportPeerId: siblingTransport,
      announcedDeviceSigningPublicKey: siblingSigningKey,
      announcedMlKemPublicKey: siblingMlKem,
      verifiedAccountSigningPublicKey: 'attacker-account-key',
      multiDeviceSyncEnabled: true,
    );
    await pump();

    expect(outcome, SiblingDeviceAdmissionOutcome.rejectedUntrusted);
    final updatedBob = await alice.groupRepo.getMember(groupId, bob.peerId);
    expect(
      updatedBob!.devices.any((d) => d.deviceId == siblingDeviceId),
      isFalse,
    );
    expect(
      await pendingRepo.getDistribution(
        groupPendingKeyDistributionId(groupId, bob.peerId),
      ),
      isNull,
    );
    expect(await tabletRepo.getLatestKey(groupId), isNull);
  });

  test(
    'a SECOND distinct device admitted after the row finalized still gets the '
    'key (terminal-row reopen regression)',
    () async {
      Future<SiblingDeviceAdmissionOutcome> admit(
        String deviceId,
        String signingKey,
        String mlKem,
      ) async {
        final bobMember = await alice.groupRepo.getMember(groupId, bob.peerId);
        return admitSiblingDeviceIfTrusted(
          groupRepo: alice.groupRepo,
          groupId: groupId,
          memberPeerId: bob.peerId,
          announcedDeviceId: deviceId,
          announcedTransportPeerId: deviceId,
          announcedDeviceSigningPublicKey: signingKey,
          announcedMlKemPublicKey: mlKem,
          verifiedAccountSigningPublicKey: bobMember!.publicKey!,
          multiDeviceSyncEnabled: true,
        );
      }

      final rowId = groupPendingKeyDistributionId(groupId, bob.peerId);

      // Device A (tablet) converges and FINALIZES the (group,peer) row.
      await admit(siblingDeviceId, siblingSigningKey, siblingMlKem);
      await pump();
      expect(
        (await pendingRepo.getDistribution(rowId))!.status,
        groupPendingKeyDistributionStatusDistributed,
      );

      // Device B (laptop), a SECOND distinct device of the SAME member. Without
      // the reopen fix the terminal row would block re-delivery and the laptop
      // would stay keyless; with it, the row reopens and the runner re-targets
      // ALL of bob's deliverable devices.
      sentTransports.clear();
      const laptopDeviceId = 'bob-laptop';
      final outcome = await admit(
        laptopDeviceId,
        'bob-laptop-signing',
        'mlkem-bob-laptop',
      );
      await pump();

      expect(outcome, SiblingDeviceAdmissionOutcome.admitted);
      expect(
        (await pendingRepo.getDistribution(rowId))!.status,
        groupPendingKeyDistributionStatusDistributed,
        reason: 'row reopened then re-finalized for the 2nd device',
      );
      expect(
        sentTransports,
        contains(laptopDeviceId),
        reason: 'the runner re-targeted the newly-admitted 2nd device',
      );
    },
  );
}
