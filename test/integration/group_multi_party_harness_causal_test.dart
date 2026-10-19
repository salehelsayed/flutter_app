import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';

import '../../integration_test/_support/group_key_transport.dart';
import '../../integration_test/scripts/run_group_multi_party_device_real.dart';
import '../core/services/fake_p2p_service.dart';
import '../shared/fakes/fake_group_pubsub_network.dart';
import '../shared/fakes/group_test_user.dart';

const _groupId = 'grp-harness-causal';

Future<(GroupTestUser, GroupTestUser)> _groupWithBob() async {
  final network = FakeGroupPubSubNetwork();
  final alice = GroupTestUser.create(
    peerId: 'peer-causal-alice',
    username: 'Alice',
    network: network,
  );
  final bob = GroupTestUser.create(
    peerId: 'peer-causal-bob',
    username: 'Bob',
    network: network,
  );
  addTearDown(() {
    alice.dispose();
    bob.dispose();
  });
  await alice.createGroup(groupId: _groupId, name: 'Causal Group');
  for (final user in [alice, bob]) {
    await user.groupRepo.saveKey(
      GroupKeyInfo(
        groupId: _groupId,
        keyGeneration: 1,
        encryptedKey: 'causal-initial-key',
        createdAt: DateTime.now().toUtc(),
      ),
    );
    if (user == alice) await alice.addMember(groupId: _groupId, invitee: bob);
  }
  alice.bridge.responses['group:generateNextKey'] = {
    'ok': true,
    'groupKey': 'causal-rotated-key',
    'keyEpoch': 2,
  };
  return (alice, bob);
}

Future<void> _rotate(
  GroupTestUser alice, {
  required GroupKeyDelivery send,
  GroupKeyDelivery? inbox,
}) => rotateAndDistributeGroupKey(
  bridge: alice.bridge,
  groupRepo: alice.groupRepo,
  groupId: _groupId,
  selfPeerId: alice.peerId,
  senderPublicKey: alice.publicKey,
  senderPrivateKey: alice.privateKey,
  senderUsername: alice.username,
  sourceDeviceId: alice.deviceId,
  sendP2PMessage: send,
  storeP2PMessageInInbox: inbox,
);

void main() {
  test('an unacknowledged key send is reported as such and reaches the '
      'inbox fallback', () async {
    final (alice, bob) = await _groupWithBob();
    final p2p = FakeP2PService(sendMessageResult: false);
    final transport = groupKeyTransport(p2p);

    expect(await transport.send(bob.peerId, 'probe'), isFalse);
    p2p.sendMessageCallCount = 0;

    await _rotate(alice, send: transport.send, inbox: transport.inbox);

    expect(p2p.sendMessageCallCount, greaterThan(0));
    expect(p2p.storeInInboxCallCount, greaterThan(0));
  });

  test('a dropped or held key update never reaches the inbox', () async {
    final (alice, bob) = await _groupWithBob();
    final p2p = FakeP2PService(sendMessageResult: false);
    String? held;
    final holding = groupKeySendIntercepting(
      p2p,
      intercepts: (peerId, message) {
        if (peerId != bob.peerId) return false;
        held = message;
        return true;
      },
    );

    await _rotate(alice, send: holding);

    expect(held, isNotNull);
    expect(p2p.sendMessageCallCount, 0);
    expect(p2p.storeInInboxCallCount, 0);
    expect(await holding('peer-not-intercepted', 'probe'), isFalse);
    expect(p2p.sendMessageCallCount, 1);
  });

  test('an active role exit beats an unresolved checkpoint', () async {
    final bobExit = Completer<int>();
    final wait = checkpointOrRoleExit(
      Completer<String>().future,
      scenario: 'private_process_death_matrix',
      activeRoleExits: {
        'bob': (exitCode: bobExit.future, logPath: '/tmp/bob.log'),
      },
    );
    bobExit.complete(3);
    await expectLater(
      wait,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'private_process_death_matrix/bob exited with code 3 before the '
              'awaited checkpoint; log=/tmp/bob.log',
        ),
      ),
    );
  });

  test('a deliberate kill after a resolved checkpoint does not poison the '
      'next wait', () async {
    final firstBobExit = Completer<int>();
    final first = await checkpointOrRoleExit(
      Future.value('remove-checkpoint'),
      scenario: 'private_process_death_matrix',
      activeRoleExits: {
        'bob': (exitCode: firstBobExit.future, logPath: '/tmp/bob.log'),
      },
    );
    expect(first, 'remove-checkpoint');

    firstBobExit.complete(-9);
    await Future<void>.delayed(Duration.zero);

    final relaunchedExit = Completer<int>();
    final next = Completer<String>();
    final second = checkpointOrRoleExit(
      next.future,
      scenario: 'private_process_death_matrix',
      activeRoleExits: {
        'bob': (
          exitCode: relaunchedExit.future,
          logPath: '/tmp/bob_after_remove_relaunch.log',
        ),
      },
    );
    next.complete('remove-recovered');
    expect(await second, 'remove-recovered');
  });
}
