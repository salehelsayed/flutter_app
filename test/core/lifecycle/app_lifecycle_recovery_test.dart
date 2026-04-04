import 'dart:convert';

import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../bridge/fake_bridge.dart';
import '../services/fake_p2p_service.dart';
import '../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../shared/fakes/in_memory_group_message_repository.dart';
import '../../shared/fakes/in_memory_group_repository.dart';

IdentityModel _makeIdentity({String? mlKemPublicKey = 'own-mlkem-pk'}) {
  return IdentityModel(
    peerId: 'my-peer-id-1234567890',
    publicKey: 'my-public-key',
    privateKey: 'my-private-key',
    mnemonic12:
        'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
    mlKemPublicKey: mlKemPublicKey,
    mlKemSecretKey: mlKemPublicKey != null ? 'own-mlkem-sk' : null,
    createdAt: '2024-01-01T00:00:00Z',
    updatedAt: '2024-01-01T00:00:00Z',
  );
}

ContactModel _makeContact(String peerId) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/p2p-circuit/rendezvous',
    username: 'user-$peerId',
    signature: 'sig-$peerId',
    scannedAt: '2024-01-01T00:00:00Z',
  );
}

void main() {
  late FakeBridge bridge;
  late FakeP2PService p2pService;

  setUp(() {
    bridge = FakeBridge();
    p2pService = FakeP2PService();
  });

  group('handleAppResumed', () {
    test('calls checkHealth on bridge', () async {
      await handleAppResumed(bridge: bridge, p2pService: p2pService);

      expect(bridge.checkHealthCallCount, equals(1));
    });

    test('does not reinitialize when bridge is healthy', () async {
      bridge.checkHealthResult = true;

      await handleAppResumed(bridge: bridge, p2pService: p2pService);

      expect(bridge.reinitializeCallCount, equals(0));
    });

    test('reinitializes bridge when health check fails', () async {
      bridge.checkHealthResult = false;

      await handleAppResumed(bridge: bridge, p2pService: p2pService);

      expect(bridge.reinitializeCallCount, equals(1));
    });

    test('calls performImmediateHealthCheck on p2pService', () async {
      await handleAppResumed(bridge: bridge, p2pService: p2pService);

      expect(p2pService.performImmediateHealthCheckCallCount, equals(1));
    });

    test('calls drainOfflineInbox on p2pService', () async {
      await handleAppResumed(bridge: bridge, p2pService: p2pService);

      expect(p2pService.drainOfflineInboxCallCount, equals(1));
    });

    test('retries push registration on normal resume', () async {
      var retryCount = 0;

      await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        retryPushRegistrationFn: () async {
          retryCount += 1;
        },
      );

      expect(retryCount, 1);
    });

    test('swallows push-registration retry errors during resume', () async {
      await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        retryPushRegistrationFn: () async {
          throw StateError('retry failed');
        },
      );

      expect(p2pService.drainOfflineInboxCallCount, 1);
    });

    test('retries incomplete key exchanges when repos are provided', () async {
      final runningP2P = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'my-peer-id-1234567890',
        ),
      );
      runningP2P.discoverPeerResult = const DiscoveredPeer(
        id: 'target-peer-1234567890',
        addresses: ['/ip4/127.0.0.1/tcp/4001'],
      );
      final contactRepo = FakeContactRepository()
        ..seed([_makeContact('target-peer-1234567890')]);
      final identityRepo = FakeIdentityRepository()..seed(_makeIdentity());

      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};
      bridge.responses['contactrequest.encrypt'] = {
        'ok': true,
        'ephemeralPublicKey': 'ephPub',
        'ciphertext': 'ct',
        'nonce': 'nonce',
      };

      await handleAppResumed(
        bridge: bridge,
        p2pService: runningP2P,
        contactRepo: contactRepo,
        identityRepo: identityRepo,
      );

      // sendContactRequest now uses sendMessageWithReply (not sendMessage)
      expect(runningP2P.sendMessageWithReplyCallCount, equals(1));
      expect(runningP2P.storeInInboxCallCount, equals(0));
      // 2 bridge calls: payload.sign + contactrequest.encrypt (v2 envelope)
      expect(bridge.sendCallCount, equals(2));
      runningP2P.dispose();
    });

    test('does not retry key exchange when repos are not provided', () async {
      final runningP2P = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'my-peer-id-1234567890',
        ),
      );

      await handleAppResumed(bridge: bridge, p2pService: runningP2P);

      expect(runningP2P.sendMessageCallCount, equals(0));
      expect(runningP2P.storeInInboxCallCount, equals(0));
      expect(bridge.sendCallCount, equals(0));
      runningP2P.dispose();
    });

    test('skips resume retry when own ML-KEM key is missing', () async {
      final runningP2P = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'my-peer-id-1234567890',
        ),
      );
      final contactRepo = FakeContactRepository()
        ..seed([_makeContact('target-peer-1234567890')]);
      final identityRepo = FakeIdentityRepository()
        ..seed(_makeIdentity(mlKemPublicKey: null));

      await handleAppResumed(
        bridge: bridge,
        p2pService: runningP2P,
        contactRepo: contactRepo,
        identityRepo: identityRepo,
      );

      expect(runningP2P.sendMessageCallCount, equals(0));
      expect(runningP2P.storeInInboxCallCount, equals(0));
      expect(bridge.sendCallCount, equals(0));
      runningP2P.dispose();
    });

    test('continues after bridge checkHealth exception', () async {
      bridge.throwOnCheckHealth = true;

      final result = await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
      );

      expect(result, isNull);
    });

    test('continues after bridge reinitialize exception', () async {
      bridge.checkHealthResult = false;
      bridge.throwOnReinitialize = true;

      final result = await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
      );

      expect(result, isNull);
    });

    test('continues after p2pService health check exception', () async {
      p2pService.throwOnHealthCheck = true;

      final result = await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
      );

      expect(result, isNull);
    });

    test('returns true when bridge was healthy', () async {
      bridge.checkHealthResult = true;

      final result = await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
      );

      expect(result, isTrue);
    });

    test('returns false when bridge was unhealthy', () async {
      bridge.checkHealthResult = false;

      final result = await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
      );

      expect(result, isFalse);
    });

    test('rejoins and acknowledges when Go signals group recovery', () async {
      final groupRepo = InMemoryGroupRepository();
      final groupMsgRepo = InMemoryGroupMessageRepository();
      final now = DateTime.now().toUtc();

      await groupRepo.saveGroup(
        GroupModel(
          id: 'group-needs-recovery',
          name: 'Recovery Group',
          type: GroupType.chat,
          topicName: 'topic-group-needs-recovery',
          createdAt: now,
          createdBy: 'admin-peer',
          myRole: GroupRole.admin,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-needs-recovery',
          peerId: 'admin-peer',
          username: 'Admin',
          role: MemberRole.admin,
          publicKey: 'pk-admin',
          joinedAt: now,
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-needs-recovery',
          keyGeneration: 1,
          encryptedKey: 'group-key',
          createdAt: now,
        ),
      );

      final runningP2P = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'my-peer-id-1234567890',
          needsGroupRecovery: true,
        ),
        recoveryMethod: 'in_place',
      );

      await handleAppResumed(
        bridge: bridge,
        p2pService: runningP2P,
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
      );

      expect(bridge.commandLog, contains('group:join'));
      expect(bridge.commandLog, contains('group:acknowledgeRecovery'));
      runningP2P.dispose();
    });

    test('in-place recovery without Go signal skips rejoin and ack', () async {
      final groupRepo = InMemoryGroupRepository();
      final groupMsgRepo = InMemoryGroupMessageRepository();
      final now = DateTime.now().toUtc();

      await groupRepo.saveGroup(
        GroupModel(
          id: 'group-skip-rejoin',
          name: 'Skip Group',
          type: GroupType.chat,
          topicName: 'topic-group-skip-rejoin',
          createdAt: now,
          createdBy: 'admin-peer',
          myRole: GroupRole.admin,
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-skip-rejoin',
          keyGeneration: 1,
          encryptedKey: 'group-key',
          createdAt: now,
        ),
      );

      final runningP2P = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'my-peer-id-1234567890',
          needsGroupRecovery: false,
        ),
        recoveryMethod: 'in_place',
      );

      await handleAppResumed(
        bridge: bridge,
        p2pService: runningP2P,
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
      );

      expect(bridge.commandLog, isNot(contains('group:join')));
      expect(bridge.commandLog, isNot(contains('group:acknowledgeRecovery')));
      runningP2P.dispose();
    });

    test('skips resume group recovery when feature flag is disabled', () async {
      final groupRepo = InMemoryGroupRepository();
      final groupMsgRepo = InMemoryGroupMessageRepository();
      final now = DateTime.now().toUtc();

      await groupRepo.saveGroup(
        GroupModel(
          id: 'group-phase7',
          name: 'Phase 7',
          type: GroupType.chat,
          topicName: 'topic-group-phase7',
          createdAt: now,
          createdBy: 'admin-peer',
          myRole: GroupRole.admin,
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-phase7',
          keyGeneration: 1,
          encryptedKey: 'group-key',
          createdAt: now,
        ),
      );

      final runningP2P = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'my-peer-id-1234567890',
          featureFlags: {'enableResumeGroupRecovery': false},
        ),
        recoveryMethod: 'watchdog_restart',
      );

      await handleAppResumed(
        bridge: bridge,
        p2pService: runningP2P,
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
      );

      expect(bridge.commandLog, isNot(contains('group:join')));
      expect(bridge.commandLog, isNot(contains('group:inboxRetrieveCursor')));
      runningP2P.dispose();
    });

    test('retry key exchange: command sequence is sign → encrypt', () async {
      final runningP2P = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'my-peer-id-1234567890',
        ),
      );
      runningP2P.storeInInboxResult = true;
      final contactRepo = FakeContactRepository()
        ..seed([_makeContact('target-peer-1234567890')]);
      final identityRepo = FakeIdentityRepository()..seed(_makeIdentity());

      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};
      bridge.responses['contactrequest.encrypt'] = {
        'ok': true,
        'ephemeralPublicKey': 'ephPub',
        'ciphertext': 'ct',
        'nonce': 'nonce',
      };

      await handleAppResumed(
        bridge: bridge,
        p2pService: runningP2P,
        contactRepo: contactRepo,
        identityRepo: identityRepo,
      );

      // Verify command order: payload.sign then contactrequest.encrypt
      expect(bridge.commandLog, contains('payload.sign'));
      expect(bridge.commandLog, contains('contactrequest.encrypt'));
      final signIdx = bridge.commandLog.indexOf('payload.sign');
      final encryptIdx = bridge.commandLog.indexOf('contactrequest.encrypt');
      expect(encryptIdx, greaterThan(signIdx));

      // Verify stored message is v2 envelope
      final storedMsg = runningP2P.lastStoreInInboxMessage;
      if (storedMsg != null) {
        final envelope = jsonDecode(storedMsg) as Map<String, dynamic>;
        expect(envelope['version'], equals('2'));
        expect(envelope['encrypted'], isA<Map>());
      }

      runningP2P.dispose();
    });
  });
}
