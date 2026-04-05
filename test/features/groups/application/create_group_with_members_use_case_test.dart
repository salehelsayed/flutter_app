import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/create_group_with_members_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_membership_limit_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

// --- Test data ---

final testIdentity = IdentityModel(
  peerId: 'peer-admin',
  publicKey: 'pk-admin',
  privateKey: 'sk-admin',
  mnemonic12:
      'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
  mlKemPublicKey: 'mlkem-pk-admin',
  username: 'Admin',
  createdAt: DateTime.now().toUtc().toIso8601String(),
  updatedAt: DateTime.now().toUtc().toIso8601String(),
);

ContactModel makeContact({required String peerId, required String username}) =>
    ContactModel(
      peerId: peerId,
      publicKey: 'pk-$peerId',
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: username,
      signature: 'sig-$peerId',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
      mlKemPublicKey: 'mlkem-pk-$peerId',
    );

final contactAlice = makeContact(peerId: 'peer-alice', username: 'Alice');
final contactBob = makeContact(peerId: 'peer-bob', username: 'Bob');
final contactCharlie = makeContact(peerId: 'peer-charlie', username: 'Charlie');
final contactDave = makeContact(peerId: 'peer-dave', username: 'Dave');

void main() {
  group('createGroupWithMembers', () {
    late PassthroughCryptoBridge bridge;
    late InMemoryGroupRepository groupRepo;
    late FakeP2PService p2pService;

    setUp(() {
      bridge = PassthroughCryptoBridge();
      groupRepo = InMemoryGroupRepository();
      p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true),
      );

      // Set up bridge responses for group:create
      bridge.responses['group:create'] = {
        'ok': true,
        'groupId': 'test-group-id',
        'topicName': 'topic-test-group-id',
        'groupKey': 'base64-group-key',
        'keyEpoch': 0,
      };
    });

    test('creates group and returns GroupModel', () async {
      final result = await createGroupWithMembers(
        bridge: bridge,
        groupRepo: groupRepo,
        p2pService: p2pService,
        identity: testIdentity,
        selectedContacts: [contactAlice],
        type: GroupType.chat,
        name: 'My Group',
      );

      expect(result.group.id, 'test-group-id');
      expect(result.group.name, 'My Group');
      expect(result.group.type, GroupType.chat);
      expect(result.group.myRole, GroupRole.admin);
    });

    test('adds all contacts as writer members', () async {
      final result = await createGroupWithMembers(
        bridge: bridge,
        groupRepo: groupRepo,
        p2pService: p2pService,
        identity: testIdentity,
        selectedContacts: [contactAlice, contactBob],
        type: GroupType.chat,
        name: 'My Group',
      );

      expect(result.membersAdded, 2);

      final members = await groupRepo.getMembers('test-group-id');
      // 3 members: admin (self) + Alice + Bob
      expect(members.length, 3);

      final alice = members.firstWhere((m) => m.peerId == 'peer-alice');
      expect(alice.role, MemberRole.writer);
      expect(alice.username, 'Alice');

      final bob = members.firstWhere((m) => m.peerId == 'peer-bob');
      expect(bob.role, MemberRole.writer);
    });

    test(
      'calls callGroupUpdateConfig once with full member list including self',
      () async {
        await createGroupWithMembers(
          bridge: bridge,
          groupRepo: groupRepo,
          p2pService: p2pService,
          identity: testIdentity,
          selectedContacts: [contactAlice],
          type: GroupType.chat,
          name: 'My Group',
        );

        final updateConfigCalls = bridge.commandLog
            .where((command) => command == 'group:updateConfig')
            .length;
        expect(updateConfigCalls, 1);

        // Find the group:updateConfig command
        final updateConfigMsg = bridge.sentMessages.firstWhere(
          (m) => (jsonDecode(m) as Map)['cmd'] == 'group:updateConfig',
        );
        final parsed = jsonDecode(updateConfigMsg) as Map<String, dynamic>;
        final config = parsed['payload']['groupConfig'] as Map<String, dynamic>;
        final members = config['members'] as List;

        // Should include self (admin) + Alice
        expect(members.length, 2);
        final peerIds = members.map((m) => m['peerId']).toSet();
        expect(peerIds, contains('peer-admin'));
        expect(peerIds, contains('peer-alice'));
      },
    );

    test(
      'broadcasts members_added system message via callGroupPublish',
      () async {
        await createGroupWithMembers(
          bridge: bridge,
          groupRepo: groupRepo,
          p2pService: p2pService,
          identity: testIdentity,
          selectedContacts: [contactAlice, contactBob],
          type: GroupType.chat,
          name: 'My Group',
        );

        // Find the group:publish command
        final publishMsg = bridge.sentMessages.firstWhere(
          (m) => (jsonDecode(m) as Map)['cmd'] == 'group:publish',
        );
        final parsed = jsonDecode(publishMsg) as Map<String, dynamic>;
        final text = parsed['payload']['text'] as String;
        final sysMsg = jsonDecode(text) as Map<String, dynamic>;

        expect(sysMsg['__sys'], 'members_added');
        final members = sysMsg['members'] as List;
        expect(members.length, 2);
      },
    );

    test('sends individual encrypted P2P invites to each contact', () async {
      await createGroupWithMembers(
        bridge: bridge,
        groupRepo: groupRepo,
        p2pService: p2pService,
        identity: testIdentity,
        selectedContacts: [contactAlice, contactBob],
        type: GroupType.chat,
        name: 'My Group',
      );

      // Should have sent 2 P2P messages (one per contact)
      expect(p2pService.sentMessageLog.length, 2);
      final recipientPeerIds = p2pService.sentMessageLog
          .map((r) => r.peerId)
          .toSet();
      expect(recipientPeerIds, contains('peer-alice'));
      expect(recipientPeerIds, contains('peer-bob'));

      // Each message should be a v2 encrypted envelope
      for (final entry in p2pService.sentMessageLog) {
        final envelope = jsonDecode(entry.content) as Map<String, dynamic>;
        expect(envelope['type'], 'group_invite');
        expect(envelope['version'], '2');
      }
    });

    test('uses auto-generated name from usernames when name is null', () async {
      final result = await createGroupWithMembers(
        bridge: bridge,
        groupRepo: groupRepo,
        p2pService: p2pService,
        identity: testIdentity,
        selectedContacts: [contactAlice, contactBob],
        type: GroupType.chat,
        name: null,
      );

      expect(result.group.name, 'Alice, Bob');
    });

    test('uses auto-generated name with +N suffix for 3+ contacts', () async {
      final result = await createGroupWithMembers(
        bridge: bridge,
        groupRepo: groupRepo,
        p2pService: p2pService,
        identity: testIdentity,
        selectedContacts: [
          contactAlice,
          contactBob,
          contactCharlie,
          contactDave,
        ],
        type: GroupType.chat,
        name: null,
      );

      expect(result.group.name, 'Alice, Bob +2');
    });

    test('uses provided name when name is not null', () async {
      final result = await createGroupWithMembers(
        bridge: bridge,
        groupRepo: groupRepo,
        p2pService: p2pService,
        identity: testIdentity,
        selectedContacts: [contactAlice],
        type: GroupType.chat,
        name: 'Custom Name',
      );

      expect(result.group.name, 'Custom Name');
    });

    test('rejects over-limit selection before creating a group', () async {
      final tooManyContacts = List.generate(
        groupMembershipLimit,
        (index) =>
            makeContact(peerId: 'peer-over-$index', username: 'User $index'),
      );

      await expectLater(
        createGroupWithMembers(
          bridge: bridge,
          groupRepo: groupRepo,
          p2pService: p2pService,
          identity: testIdentity,
          selectedContacts: tooManyContacts,
          type: GroupType.chat,
          name: 'Too Large',
        ),
        throwsA(
          isA<GroupMembershipLimitException>()
              .having((e) => e.maxMembers, 'maxMembers', groupMembershipLimit)
              .having((e) => e.currentMemberCount, 'currentMemberCount', 1)
              .having(
                (e) => e.requestedAdditionalMembers,
                'requestedAdditionalMembers',
                groupMembershipLimit,
              ),
        ),
      );

      expect(bridge.commandLog, isEmpty);
      expect(await groupRepo.getGroup('test-group-id'), isNull);
      expect(await groupRepo.getMembers('test-group-id'), isEmpty);
      expect(await groupRepo.getLatestKey('test-group-id'), isNull);
    });

    test('succeeds locally even when P2P invite fails', () async {
      // Make P2P fail
      p2pService.sendMessageResult = false;
      p2pService.storeInInboxResult = false;

      final result = await createGroupWithMembers(
        bridge: bridge,
        groupRepo: groupRepo,
        p2pService: p2pService,
        identity: testIdentity,
        selectedContacts: [contactAlice],
        type: GroupType.chat,
        name: 'My Group',
      );

      // Group still created, member still added
      expect(result.group.id, 'test-group-id');
      expect(result.membersAdded, 1);
      // Invite attempted but failed
      expect(result.invitesSent, 0);
    });

    test(
      'propagates announcement type into created group, saved group, and updateConfig',
      () async {
        final result = await createGroupWithMembers(
          bridge: bridge,
          groupRepo: groupRepo,
          p2pService: p2pService,
          identity: testIdentity,
          selectedContacts: [contactAlice],
          type: GroupType.announcement,
          name: 'Announcements',
        );

        expect(result.group.type, GroupType.announcement);
        expect(result.group.myRole, GroupRole.admin);

        final savedGroup = await groupRepo.getGroup('test-group-id');
        expect(savedGroup, isNotNull);
        expect(savedGroup!.type, GroupType.announcement);
        expect(savedGroup.myRole, GroupRole.admin);

        final updateConfigMsg = bridge.sentMessages.firstWhere(
          (message) =>
              (jsonDecode(message) as Map<String, dynamic>)['cmd'] ==
              'group:updateConfig',
        );
        final config =
            ((jsonDecode(updateConfigMsg) as Map<String, dynamic>)['payload']
                    as Map<String, dynamic>)['groupConfig']
                as Map<String, dynamic>;

        expect(config['groupType'], 'announcement');
        expect(config['createdBy'], testIdentity.peerId);
      },
    );
  });
}
