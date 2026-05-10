import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/create_group_with_members_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_membership_limit_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
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

ContactModel makeContact({
  required String peerId,
  required String username,
  String? mlKemPublicKey,
  bool omitMlKemPublicKey = false,
}) => ContactModel(
  peerId: peerId,
  publicKey: 'pk-$peerId',
  rendezvous: '/dns4/relay/tcp/443/p2p/relay',
  username: username,
  signature: 'sig-$peerId',
  scannedAt: DateTime.now().toUtc().toIso8601String(),
  mlKemPublicKey: omitMlKemPublicKey
      ? null
      : (mlKemPublicKey ?? 'mlkem-pk-$peerId'),
);

final contactAlice = makeContact(peerId: 'peer-alice', username: 'Alice');
final contactBob = makeContact(peerId: 'peer-bob', username: 'Bob');
final contactCharlie = makeContact(peerId: 'peer-charlie', username: 'Charlie');
final contactDave = makeContact(peerId: 'peer-dave', username: 'Dave');

const _gl005ForbiddenPublicRouteKeys = {
  'visibility',
  'ispublic',
  'discoverable',
  'isdiscoverable',
  'openjoin',
  'allowopenjoin',
  'joinpolicy',
  'invitelink',
  'joinlink',
  'publicpreview',
  'publiclisting',
  'publiccatalog',
  'publicroom',
  'publicgroup',
};

void _expectNoPublicRouteFields(Object? value, {String path = 'payload'}) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString();
      final normalized = key.replaceAll(RegExp(r'[_-]'), '').toLowerCase();
      expect(
        _gl005ForbiddenPublicRouteKeys,
        isNot(contains(normalized)),
        reason: 'GL-005 forbids public/open route field "$key" at $path',
      );
      _expectNoPublicRouteFields(entry.value, path: '$path.$key');
    }
  } else if (value is Iterable) {
    var index = 0;
    for (final item in value) {
      _expectNoPublicRouteFields(item, path: '$path[$index]');
      index++;
    }
  }
}

class _FailingSaveMemberGroupRepository extends InMemoryGroupRepository {
  _FailingSaveMemberGroupRepository({required this.failingPeerIds});

  final Set<String> failingPeerIds;

  @override
  Future<void> saveMember(GroupMember member) async {
    if (failingPeerIds.contains(member.peerId)) {
      throw StateError('Injected saveMember failure for ${member.peerId}');
    }
    await super.saveMember(member);
  }
}

class _TrackingInviteDeliveryAttemptRepository
    implements GroupInviteDeliveryAttemptRepository {
  final Map<String, GroupInviteDeliveryAttempt> attempts = {};

  String _key(String groupId, String peerId) => '$groupId::$peerId';

  @override
  Future<void> saveAttempt(GroupInviteDeliveryAttempt attempt) async {
    attempts[_key(attempt.groupId, attempt.peerId)] = attempt;
  }

  @override
  Future<GroupInviteDeliveryAttempt?> getAttempt({
    required String groupId,
    required String peerId,
  }) async {
    return attempts[_key(groupId, peerId)];
  }

  @override
  Future<List<GroupInviteDeliveryAttempt>> getAttemptsForGroup(
    String groupId,
  ) async {
    return attempts.values
        .where((attempt) => attempt.groupId == groupId)
        .toList(growable: false);
  }

  @override
  Future<GroupInviteDeliveryStatus> getStatusForMember({
    required String groupId,
    required String peerId,
  }) async {
    return attempts[_key(groupId, peerId)]?.status ??
        GroupInviteDeliveryStatus.unknown;
  }

  @override
  Future<Map<String, GroupInviteDeliveryStatus>> getStatusesForGroupMembers(
    String groupId,
  ) async {
    return {
      for (final attempt in attempts.values.where((a) => a.groupId == groupId))
        attempt.peerId: attempt.status,
    };
  }

  @override
  Future<void> updateStatus({
    required String groupId,
    required String peerId,
    required GroupInviteDeliveryStatus status,
    DateTime? updatedAt,
  }) async {
    final existing = attempts[_key(groupId, peerId)];
    final now = updatedAt ?? DateTime.now().toUtc();
    attempts[_key(groupId, peerId)] =
        existing?.copyWith(
          status: status,
          updatedAt: now,
          clearLastError: true,
        ) ??
        GroupInviteDeliveryAttempt(
          groupId: groupId,
          peerId: peerId,
          status: status,
          attemptedAt: now,
          updatedAt: now,
        );
  }

  @override
  Future<void> markJoined({
    required String groupId,
    required String peerId,
    String? username,
    DateTime? joinedAt,
  }) async {
    await updateStatus(
      groupId: groupId,
      peerId: peerId,
      status: GroupInviteDeliveryStatus.joined,
      updatedAt: joinedAt,
    );
  }

  @override
  Future<int> deleteAttempt({
    required String groupId,
    required String peerId,
  }) async {
    return attempts.remove(_key(groupId, peerId)) == null ? 0 : 1;
  }

  @override
  Future<int> deleteAttemptsForGroup(String groupId) async {
    final before = attempts.length;
    attempts.removeWhere((_, attempt) => attempt.groupId == groupId);
    return before - attempts.length;
  }
}

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
        'keyEpoch': 1,
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
      'persists the creator username and exports it in group config',
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

        final members = await groupRepo.getMembers('test-group-id');
        final admin = members.firstWhere(
          (member) => member.peerId == 'peer-admin',
        );
        expect(admin.username, 'Admin');
        expect(admin.role, MemberRole.admin);

        final updateConfigMsg = bridge.sentMessages.firstWhere(
          (m) => (jsonDecode(m) as Map)['cmd'] == 'group:updateConfig',
        );
        final updateConfig =
            (jsonDecode(updateConfigMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final configMembers =
            (updateConfig['groupConfig'] as Map<String, dynamic>)['members']
                as List<dynamic>;
        final configAdmin = configMembers
            .cast<Map<String, dynamic>>()
            .firstWhere((member) => member['peerId'] == 'peer-admin');
        expect(configAdmin['username'], 'Admin');
        expect(configAdmin['role'], 'admin');
      },
    );

    test(
      'excludes failed add-member recipients from persisted members, config, publish payload, and invite fan-out',
      () async {
        groupRepo = _FailingSaveMemberGroupRepository(
          failingPeerIds: {'peer-bob'},
        );

        final result = await createGroupWithMembers(
          bridge: bridge,
          groupRepo: groupRepo,
          p2pService: p2pService,
          identity: testIdentity,
          selectedContacts: [contactAlice, contactBob, contactCharlie],
          type: GroupType.chat,
          name: 'My Group',
        );

        expect(result.group.id, 'test-group-id');
        expect(result.membersAdded, 2);
        expect(result.invitesSent, 2);

        final members = await groupRepo.getMembers('test-group-id');
        expect(members.length, 3);
        final memberPeerIds = members.map((m) => m.peerId).toSet();
        expect(
          memberPeerIds,
          equals({'peer-admin', 'peer-alice', 'peer-charlie'}),
        );
        expect(memberPeerIds, isNot(contains('peer-bob')));

        final updateConfigMsg = bridge.sentMessages.firstWhere(
          (m) => (jsonDecode(m) as Map)['cmd'] == 'group:updateConfig',
        );
        final updateConfig =
            (jsonDecode(updateConfigMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final configMembers =
            (updateConfig['groupConfig'] as Map<String, dynamic>)['members']
                as List<dynamic>;
        final configPeerIds = configMembers
            .map((member) => (member as Map<String, dynamic>)['peerId'])
            .toSet();
        expect(
          configPeerIds,
          equals({'peer-admin', 'peer-alice', 'peer-charlie'}),
        );
        expect(configPeerIds, isNot(contains('peer-bob')));

        final publishMsg = bridge.sentMessages.firstWhere(
          (m) => (jsonDecode(m) as Map)['cmd'] == 'group:publish',
        );
        final publishPayload =
            (jsonDecode(publishMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final sysMsg =
            jsonDecode(publishPayload['text'] as String)
                as Map<String, dynamic>;
        final publishedMembers = sysMsg['members'] as List<dynamic>;
        final publishedPeerIds = publishedMembers
            .map((member) => (member as Map<String, dynamic>)['peerId'])
            .toSet();
        expect(publishedPeerIds, equals({'peer-alice', 'peer-charlie'}));
        expect(publishedPeerIds, isNot(contains('peer-bob')));

        final invitePeerIds = p2pService.sentMessageLog
            .map((entry) => entry.peerId)
            .toSet();
        expect(invitePeerIds, equals({'peer-alice', 'peer-charlie'}));
        expect(invitePeerIds, isNot(contains('peer-bob')));
      },
    );

    test(
      'GL-005 config, members_added, and invite fanout stay selected-member-only without public route flags',
      () async {
        final result = await createGroupWithMembers(
          bridge: bridge,
          groupRepo: groupRepo,
          p2pService: p2pService,
          identity: testIdentity,
          selectedContacts: [contactAlice, contactBob],
          type: GroupType.chat,
          name: 'Private Selected Members',
        );

        expect(result.membersAdded, 2);
        expect(result.invitesSent, 2);

        final storedMembers = await groupRepo.getMembers('test-group-id');
        final storedPeerIds = storedMembers
            .map((member) => member.peerId)
            .toSet();
        expect(storedPeerIds, {'peer-admin', 'peer-alice', 'peer-bob'});
        expect(storedPeerIds, isNot(contains(contactCharlie.peerId)));

        final updateConfigMsg = bridge.sentMessages.firstWhere(
          (message) =>
              (jsonDecode(message) as Map<String, dynamic>)['cmd'] ==
              'group:updateConfig',
        );
        final updateConfigPayload =
            (jsonDecode(updateConfigMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final groupConfig =
            updateConfigPayload['groupConfig'] as Map<String, dynamic>;
        _expectNoPublicRouteFields(groupConfig, path: 'groupConfig');

        final configPeerIds = (groupConfig['members'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((member) => member['peerId'])
            .toSet();
        expect(configPeerIds, storedPeerIds);
        expect(configPeerIds, isNot(contains(contactCharlie.peerId)));

        final publishMsg = bridge.sentMessages.firstWhere(
          (message) =>
              (jsonDecode(message) as Map<String, dynamic>)['cmd'] ==
              'group:publish',
        );
        final publishPayload =
            (jsonDecode(publishMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final sysMsg =
            jsonDecode(publishPayload['text'] as String)
                as Map<String, dynamic>;
        expect(sysMsg['__sys'], 'members_added');
        _expectNoPublicRouteFields(sysMsg, path: 'members_added');

        final publishedPeerIds = (sysMsg['members'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((member) => member['peerId'])
            .toSet();
        expect(publishedPeerIds, {'peer-alice', 'peer-bob'});
        expect(publishedPeerIds, isNot(contains(contactCharlie.peerId)));

        final invitePeerIds = p2pService.sentMessageLog
            .map((entry) => entry.peerId)
            .toSet();
        expect(invitePeerIds, {'peer-alice', 'peer-bob'});
        expect(invitePeerIds, isNot(contains(contactCharlie.peerId)));

        for (final entry in p2pService.sentMessageLog) {
          final envelope = jsonDecode(entry.content) as Map<String, dynamic>;
          _expectNoPublicRouteFields(envelope, path: 'inviteEnvelope');
          final encrypted = envelope['encrypted'] as Map<String, dynamic>;
          final innerPayload =
              jsonDecode(encrypted['ciphertext'] as String)
                  as Map<String, dynamic>;
          _expectNoPublicRouteFields(innerPayload, path: 'invitePayload');
          expect(innerPayload['recipientPeerId'], entry.peerId);
          final inviteConfig =
              innerPayload['groupConfig'] as Map<String, dynamic>;
          final inviteConfigPeerIds = (inviteConfig['members'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((member) => member['peerId'])
              .toSet();
          expect(inviteConfigPeerIds, storedPeerIds);
          expect(inviteConfigPeerIds, isNot(contains(contactCharlie.peerId)));
        }
      },
    );

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

    test(
      'PREREQ-INVITER-FRESHNESS create fanout sends invites with signed freshness proof',
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

        expect(p2pService.sentMessageLog.length, 2);
        for (final entry in p2pService.sentMessageLog) {
          final envelope = jsonDecode(entry.content) as Map<String, dynamic>;
          final encrypted = envelope['encrypted'] as Map<String, dynamic>;
          final payload = GroupInvitePayload.fromInnerJson(
            encrypted['ciphertext'] as String,
          );
          expect(payload, isNotNull);
          expect(payload!.membershipFreshnessProof, isNotNull);
          expect(
            payload.inviteSignature!.signedPayload,
            contains(groupInviteMembershipFreshnessProofField),
          );
          expect(
            payload.membershipFreshnessProof!.groupConfigStateHash,
            payload.groupConfig['stateHash'],
          );
        }
      },
    );

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
      final inviteStatusRepo = _TrackingInviteDeliveryAttemptRepository();

      final result = await createGroupWithMembers(
        bridge: bridge,
        groupRepo: groupRepo,
        p2pService: p2pService,
        identity: testIdentity,
        selectedContacts: [contactAlice],
        type: GroupType.chat,
        name: 'My Group',
        inviteDeliveryAttemptRepo: inviteStatusRepo,
      );

      // Group still created, member still added
      expect(result.group.id, 'test-group-id');
      expect(result.membersAdded, 1);
      // Invite attempted but failed
      expect(result.invitesSent, 0);
      expect(result.hasWarnings, isTrue);
      expect(result.inviteBatchResult, isNotNull);
      expect(result.inviteBatchResult!.failures, hasLength(1));
      expect(
        result.inviteBatchResult!.failures.single.result,
        SendGroupInviteResult.sendFailed,
      );
      expect(
        await inviteStatusRepo.getStatusForMember(
          groupId: 'test-group-id',
          peerId: 'peer-alice',
        ),
        GroupInviteDeliveryStatus.needsResend,
      );
    });

    test(
      'reports missing secure keys as explicit invite degradation',
      () async {
        final noKeyContact = makeContact(
          peerId: 'peer-no-key',
          username: 'NoKey',
          omitMlKemPublicKey: true,
        );
        final inviteStatusRepo = _TrackingInviteDeliveryAttemptRepository();

        final result = await createGroupWithMembers(
          bridge: bridge,
          groupRepo: groupRepo,
          p2pService: p2pService,
          identity: testIdentity,
          selectedContacts: [contactAlice, noKeyContact],
          type: GroupType.chat,
          name: 'My Group',
          inviteDeliveryAttemptRepo: inviteStatusRepo,
        );

        expect(result.membersAdded, 2);
        expect(result.invitesSent, 1);
        expect(result.hasWarnings, isTrue);
        expect(result.inviteBatchResult, isNotNull);
        expect(result.inviteBatchResult!.failures, hasLength(1));
        expect(result.inviteBatchResult!.failures.single.displayName, 'NoKey');
        expect(
          result.inviteBatchResult!.failures.single.result,
          SendGroupInviteResult.encryptionRequired,
        );
        expect(
          result.buildCreateWarningMessage(),
          contains('NoKey (missing secure key)'),
        );
        expect(
          await inviteStatusRepo.getStatusForMember(
            groupId: 'test-group-id',
            peerId: 'peer-alice',
          ),
          GroupInviteDeliveryStatus.sent,
        );
        expect(
          await inviteStatusRepo.getStatusForMember(
            groupId: 'test-group-id',
            peerId: 'peer-no-key',
          ),
          GroupInviteDeliveryStatus.cannotSend,
        );
        final noKeyAttempt = await inviteStatusRepo.getAttempt(
          groupId: 'test-group-id',
          peerId: 'peer-no-key',
        );
        expect(noKeyAttempt, isNotNull);
        expect(noKeyAttempt!.lastError, 'missing_secure_key');
      },
    );

    test(
      'rolls back added members when config sync fails after create',
      () async {
        bridge.responses['group:updateConfig'] = {
          'ok': false,
          'errorCode': 'CONFIG_SYNC_FAILED',
          'errorMessage': 'bridge rejected config',
        };

        final result = await createGroupWithMembers(
          bridge: bridge,
          groupRepo: groupRepo,
          p2pService: p2pService,
          identity: testIdentity,
          selectedContacts: [contactAlice],
          type: GroupType.chat,
          name: 'My Group',
        );

        expect(result.membersAdded, 0);
        expect(result.membershipSyncRolledBack, isTrue);
        expect(result.invitesSent, 0);
        expect(result.buildCreateWarningMessage(), isNotNull);

        final members = await groupRepo.getMembers('test-group-id');
        expect(members.map((member) => member.peerId).toSet(), {'peer-admin'});
        expect(bridge.commandLog, isNot(contains('group:publish')));
        expect(p2pService.sentMessageLog, isEmpty);
      },
    );

    test(
      'keeps created members but reports publish failures explicitly',
      () async {
        bridge.responses['group:publish'] = {
          'ok': false,
          'errorCode': 'PUBLISH_FAILED',
          'errorMessage': 'publish rejected',
        };

        final result = await createGroupWithMembers(
          bridge: bridge,
          groupRepo: groupRepo,
          p2pService: p2pService,
          identity: testIdentity,
          selectedContacts: [contactAlice],
          type: GroupType.chat,
          name: 'My Group',
        );

        expect(result.membersAdded, 1);
        expect(result.membersAddedPublishFailed, isTrue);
        expect(
          result.buildCreateWarningMessage(),
          contains('could not be published'),
        );

        final members = await groupRepo.getMembers('test-group-id');
        expect(
          members.map((member) => member.peerId).toSet(),
          contains('peer-alice'),
        );
      },
    );

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
