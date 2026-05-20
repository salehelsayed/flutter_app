import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/accept_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/decline_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/remove_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/application/revoke_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart'
    as group_send;
import 'package:flutter_app/features/groups/application/send_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_pending_group_invite_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

// ---------------------------------------------------------------------------
// Shared test constants
// ---------------------------------------------------------------------------

const _adminPeerId = '12D3KooWAdminPeerId';
const _receiverPeerId = '12D3KooWReceiverPeerId';
const _groupId = 'grp-round-trip-001';
const _groupKey = 'base64GroupKeyRoundTrip==';
const _keyEpoch = 1;

const _adminMlKemPublicKey = 'adminMlKemPub64';
const _receiverMlKemPublicKey = 'receiverMlKemPub64';
const _receiverMlKemSecretKey = 'receiverMlKemSecret64';

Map<String, dynamic> _makeGroupConfig({
  List<Map<String, dynamic>>? extraMembers,
}) {
  final members = <Map<String, dynamic>>[
    {
      'peerId': _adminPeerId,
      'username': 'Admin',
      'role': 'admin',
      'publicKey': 'adminPubKey64',
      'mlKemPublicKey': _adminMlKemPublicKey,
    },
    {
      'peerId': _receiverPeerId,
      'username': 'Receiver',
      'role': 'writer',
      'publicKey': 'receiverPubKey64',
      'mlKemPublicKey': _receiverMlKemPublicKey,
    },
    if (extraMembers != null) ...extraMembers,
  ];

  return {
    'name': 'Test Group',
    'groupType': 'chat',
    'description': 'Integration test group',
    'members': members,
    'createdBy': _adminPeerId,
    'createdAt': '2026-03-02T00:00:00.000Z',
  };
}

GroupInvitePolicy _makeInvitePolicy({
  required String recipientPeerId,
  String assignedRole = 'writer',
  DateTime? expiresAt,
  int keyEpoch = _keyEpoch,
  GroupInviteReusePolicy reusePolicy = GroupInviteReusePolicy.singleUse,
}) {
  return GroupInvitePolicy(
    expiresAt: expiresAt ?? DateTime.utc(2099, 3, 9, 12),
    allowedDevices: [recipientPeerId],
    assignedRole: assignedRole,
    canInviteOthers: false,
    joinMaterialKind: GroupInvitePolicy.inlineGroupKeyKind,
    keyEpoch: keyEpoch,
    reusePolicy: reusePolicy,
  );
}

ContactModel _adminContact() {
  return const ContactModel(
    peerId: _adminPeerId,
    publicKey: 'adminPubKey64',
    rendezvous: '/ip4/0.0.0.0',
    username: 'Admin',
    signature: 'adminSig',
    scannedAt: '2026-01-01T00:00:00Z',
    mlKemPublicKey: _adminMlKemPublicKey,
  );
}

ContactModel _receiverContact() {
  return const ContactModel(
    peerId: _receiverPeerId,
    publicKey: 'receiverPubKey64',
    rendezvous: '/ip4/0.0.0.0',
    username: 'Receiver',
    signature: 'receiverSig',
    scannedAt: '2026-01-01T00:00:00Z',
    mlKemPublicKey: _receiverMlKemPublicKey,
  );
}

Map<String, dynamic> _lastGroupInboxStorePayload(FakeBridge bridge) {
  final inboxMsg = bridge.sentMessages.lastWhere(
    (message) =>
        (jsonDecode(message) as Map<String, dynamic>)['cmd'] ==
        'group:inboxStore',
  );
  return (jsonDecode(inboxMsg) as Map<String, dynamic>)['payload']
      as Map<String, dynamic>;
}

Future<InMemoryGroupRepository> _repoFromConfig(
  Map<String, dynamic> groupConfig, {
  String groupId = _groupId,
}) async {
  final repo = InMemoryGroupRepository();
  final createdAt =
      DateTime.tryParse(groupConfig['createdAt'] as String? ?? '')?.toUtc() ??
      DateTime.utc(2026, 3, 2);
  await repo.saveGroup(
    GroupModel(
      id: groupId,
      name: groupConfig['name'] as String? ?? 'Test Group',
      type: GroupType.fromValue(groupConfig['groupType'] as String? ?? 'chat'),
      topicName: '/mknoon/group/$groupId',
      description: groupConfig['description'] as String?,
      createdAt: createdAt,
      createdBy: groupConfig['createdBy'] as String? ?? _adminPeerId,
      myRole: GroupRole.admin,
      lastMembershipEventAt: createdAt,
      lastMetadataEventAt: createdAt,
    ),
  );
  for (final member in groupConfig['members'] as List<dynamic>? ?? const []) {
    await repo.saveMember(
      GroupMember.fromConfigMap(
        groupId: groupId,
        map: Map<String, dynamic>.from(member as Map),
        joinedAt: createdAt,
      ),
    );
  }
  return repo;
}

GroupInviteMembershipFreshnessProof _makeFreshnessProof({
  required String inviteId,
  required String groupId,
  required String? recipientPeerId,
  required Map<String, dynamic> groupConfig,
  required int keyEpoch,
  required DateTime issuedAt,
  DateTime? expiresAt,
}) {
  final stateHash = buildGroupConfigStateHash(
    groupId: groupId,
    groupConfig: groupConfig,
  );
  return GroupInviteMembershipFreshnessProof(
    inviteId: inviteId,
    groupId: groupId,
    recipientPeerId: recipientPeerId,
    inviterPeerId: _adminPeerId,
    inviterPublicKey: 'adminPubKey64',
    keyEpoch: keyEpoch,
    groupConfigStateHash: stateHash,
    membershipWatermark: stateHash,
    issuedAt: issuedAt.toUtc(),
    expiresAt:
        expiresAt ?? issuedAt.toUtc().add(groupInviteMembershipFreshnessTtl),
    inviterMemberSnapshot: {
      'peerId': _adminPeerId,
      'username': 'Admin',
      'role': 'admin',
      'publicKey': 'adminPubKey64',
      'mlKemPublicKey': _adminMlKemPublicKey,
    },
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Group invite round-trip integration', () {
    // -----------------------------------------------------------------------
    // 1. Full invite round-trip: admin sends invite -> receiver processes it
    //    -> group is persisted.
    // -----------------------------------------------------------------------
    test('full invite round-trip: admin sends invite -> receiver processes it '
        '-> group is persisted', () async {
      // --- Admin side setup ---
      final adminBridge = PassthroughCryptoBridge();
      final adminP2P = FakeP2PService(
        initialState: const NodeState(isStarted: true),
      );
      final adminGroupRepo = InMemoryGroupRepository();
      final adminContactRepo = FakeContactRepository();

      // Admin has the group locally with key + member records
      await adminGroupRepo.saveGroup(
        GroupModel(
          id: _groupId,
          name: 'Test Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/$_groupId',
          description: 'Integration test group',
          createdAt: DateTime.utc(2026, 3, 2),
          createdBy: _adminPeerId,
          myRole: GroupRole.admin,
        ),
      );
      await adminGroupRepo.saveMember(
        GroupMember(
          groupId: _groupId,
          peerId: _adminPeerId,
          username: 'Admin',
          role: MemberRole.admin,
          publicKey: 'adminPubKey64',
          mlKemPublicKey: _adminMlKemPublicKey,
          joinedAt: DateTime.utc(2026, 3, 2),
        ),
      );
      await adminGroupRepo.saveKey(
        GroupKeyInfo(
          groupId: _groupId,
          keyGeneration: _keyEpoch,
          encryptedKey: _groupKey,
          createdAt: DateTime.utc(2026, 3, 2),
        ),
      );
      adminContactRepo.seed([_receiverContact()]);

      final groupConfig = _makeGroupConfig();

      // --- Action: admin sends invite ---
      final sendResult = await sendGroupInvite(
        p2pService: adminP2P,
        bridge: adminBridge,
        groupRepo: await _repoFromConfig(groupConfig),
        recipientPeerId: _receiverPeerId,
        recipientMlKemPublicKey: _receiverMlKemPublicKey,
        senderPeerId: _adminPeerId,
        senderPublicKey: 'adminPubKey64',
        senderPrivateKey: 'adminPrivKey64',
        senderUsername: 'Admin',
        groupId: _groupId,
        groupKey: _groupKey,
        keyEpoch: _keyEpoch,
        groupConfig: groupConfig,
      );

      expect(sendResult, equals(SendGroupInviteResult.success));

      // Capture the message that was sent over P2P
      final sentContent = adminP2P.lastSendMessageContent!;

      // Verify it is a v2 encrypted envelope
      final v2Envelope = GroupInvitePayload.parseEncryptedEnvelope(sentContent);
      expect(
        v2Envelope,
        isNotNull,
        reason: 'Sent message should be a v2 encrypted envelope',
      );
      final cleartextEnvelope = Map<String, dynamic>.from(v2Envelope!)
        ..remove('encrypted');
      expect(cleartextEnvelope.toString(), isNot(contains('invitePolicy')));
      final encrypted = v2Envelope['encrypted'] as Map<String, dynamic>;
      final inner =
          jsonDecode(encrypted['ciphertext'] as String) as Map<String, dynamic>;
      final policy = inner['invitePolicy'] as Map<String, dynamic>;
      expect(policy['allowedDevices'], [_receiverPeerId]);
      expect(policy['invitePermissions']['assignedRole'], 'writer');
      expect(policy['joinMaterialRef']['kind'], 'inlineGroupKey');
      expect(policy['joinMaterialRef']['keyEpoch'], _keyEpoch);

      // --- Receiver side setup ---
      final receiverBridge = PassthroughCryptoBridge();
      final receiverGroupRepo = InMemoryGroupRepository();
      final receiverContactRepo = FakeContactRepository();
      receiverContactRepo.seed([_adminContact()]);

      // Simulate the incoming message as the receiver would see it
      final incomingMessage = ChatMessage(
        from: _adminPeerId,
        to: _receiverPeerId,
        content: sentContent,
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
      );

      // --- Action: receiver handles the invite ---
      final (handleResult, handleGroupId) = await handleIncomingGroupInvite(
        message: incomingMessage,
        groupRepo: receiverGroupRepo,
        contactRepo: receiverContactRepo,
        bridge: receiverBridge,
        ownMlKemSecretKey: _receiverMlKemSecretKey,
        ownPeerId: _receiverPeerId,
      );

      // --- Assertions ---
      expect(handleResult, equals(HandleGroupInviteResult.success));
      expect(handleGroupId, equals(_groupId));

      // Group is persisted
      final group = await receiverGroupRepo.getGroup(_groupId);
      expect(group, isNotNull);
      expect(group!.name, equals('Test Group'));
      expect(group.type, equals(GroupType.chat));
      expect(group.myRole, equals(GroupRole.member));
      expect(group.createdBy, equals(_adminPeerId));
      expect(group.description, equals('Integration test group'));

      // Members from the config are persisted
      final members = await receiverGroupRepo.getMembers(_groupId);
      expect(members, hasLength(2));
      expect(members.any((m) => m.peerId == _adminPeerId), isTrue);
      expect(members.any((m) => m.peerId == _receiverPeerId), isTrue);

      // Key is persisted
      final key = await receiverGroupRepo.getLatestKey(_groupId);
      expect(key, isNotNull);
      expect(key!.encryptedKey, equals(_groupKey));
      expect(key.keyGeneration, equals(_keyEpoch));

      // Bridge received a group:join command with correct payload
      expect(receiverBridge.commandLog, contains('group:join'));
      final joinCallIndex = receiverBridge.commandLog.indexOf('group:join');
      // The last sent message to bridge should be the group:join call.
      // But since PassthroughCryptoBridge also handles message.decrypt,
      // we verify via commandLog that group:join was called.
      expect(joinCallIndex, greaterThanOrEqualTo(0));

      // Cleanup
      adminP2P.dispose();
    });

    test(
      'new member history stays future-only while post-join replay is allowed',
      () async {
        const groupId = 'grp-new-member-history-001';
        const preJoinText = 'Before join history';
        const postJoinReplayText = 'After join replay';

        final adminBridge = PassthroughCryptoBridge();
        adminBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-prejoin-history',
          'topicPeers': 0,
        };
        final adminP2P = FakeP2PService(
          initialState: const NodeState(isStarted: true),
        );
        final adminGroupRepo = InMemoryGroupRepository();
        final adminMsgRepo = InMemoryGroupMessageRepository();

        await adminGroupRepo.saveGroup(
          GroupModel(
            id: groupId,
            name: 'History Policy Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/$groupId',
            description: 'Future-only history policy integration test group',
            createdAt: DateTime.utc(2026, 3, 4),
            createdBy: _adminPeerId,
            myRole: GroupRole.admin,
          ),
        );
        await adminGroupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: _adminPeerId,
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'adminPubKey64',
            mlKemPublicKey: _adminMlKemPublicKey,
            joinedAt: DateTime.utc(2026, 3, 4),
          ),
        );
        await adminGroupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: _keyEpoch,
            encryptedKey: _groupKey,
            createdAt: DateTime.utc(2026, 3, 4),
          ),
        );

        final (preJoinSendResult, _) = await group_send.sendGroupMessage(
          bridge: adminBridge,
          groupRepo: adminGroupRepo,
          msgRepo: adminMsgRepo,
          groupId: groupId,
          text: preJoinText,
          senderPeerId: _adminPeerId,
          senderPublicKey: 'adminPubKey64',
          senderPrivateKey: 'adminPrivKey64',
          senderUsername: 'Admin',
          messageId: 'msg-prejoin-history',
          timestamp: DateTime.utc(2026, 3, 4, 0, 0, 30),
        );

        expect(
          preJoinSendResult,
          anyOf(
            group_send.SendGroupMessageResult.success,
            group_send.SendGroupMessageResult.successNoPeers,
          ),
        );
        expect(await adminMsgRepo.getMessageCount(groupId), 1);

        await adminGroupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: _receiverPeerId,
            username: 'Receiver',
            role: MemberRole.writer,
            publicKey: 'receiverPubKey64',
            mlKemPublicKey: _receiverMlKemPublicKey,
            joinedAt: DateTime.utc(2026, 3, 4, 0, 1),
          ),
        );

        final adminGroup = await adminGroupRepo.getGroup(groupId);
        final adminMembers = await adminGroupRepo.getMembers(groupId);
        final groupConfig = {
          'name': adminGroup!.name,
          'groupType': adminGroup.type.toValue(),
          if (adminGroup.description != null)
            'description': adminGroup.description,
          'members': adminMembers
              .map(
                (member) => {
                  'peerId': member.peerId,
                  'username': member.username,
                  'role': member.role.toValue(),
                  'publicKey': member.publicKey,
                  if (member.mlKemPublicKey != null)
                    'mlKemPublicKey': member.mlKemPublicKey,
                },
              )
              .toList(),
          'createdBy': adminGroup.createdBy,
          'createdAt': adminGroup.createdAt.toUtc().toIso8601String(),
        };

        final sendInviteResult = await sendGroupInvite(
          p2pService: adminP2P,
          bridge: adminBridge,
          groupRepo: await _repoFromConfig(groupConfig, groupId: groupId),
          recipientPeerId: _receiverPeerId,
          recipientMlKemPublicKey: _receiverMlKemPublicKey,
          senderPeerId: _adminPeerId,
          senderPublicKey: 'adminPubKey64',
          senderPrivateKey: 'adminPrivKey64',
          senderUsername: 'Admin',
          groupId: groupId,
          groupKey: _groupKey,
          keyEpoch: _keyEpoch,
          groupConfig: groupConfig,
        );

        expect(sendInviteResult, SendGroupInviteResult.success);

        final receiverBridge = PassthroughCryptoBridge();
        final receiverGroupRepo = InMemoryGroupRepository();
        final receiverMsgRepo = InMemoryGroupMessageRepository();
        final receiverContactRepo = FakeContactRepository();
        receiverContactRepo.seed([_adminContact()]);

        final incomingInvite = ChatMessage(
          from: _adminPeerId,
          to: _receiverPeerId,
          content: adminP2P.lastSendMessageContent!,
          timestamp: DateTime.utc(2026, 3, 4, 0, 2).toIso8601String(),
          isIncoming: true,
        );

        final (handleResult, handleGroupId) = await handleIncomingGroupInvite(
          message: incomingInvite,
          groupRepo: receiverGroupRepo,
          contactRepo: receiverContactRepo,
          bridge: receiverBridge,
          ownMlKemSecretKey: _receiverMlKemSecretKey,
          ownPeerId: _receiverPeerId,
        );

        expect(handleResult, HandleGroupInviteResult.success);
        expect(handleGroupId, groupId);
        expect(
          await receiverMsgRepo.getMessageCount(groupId),
          0,
          reason: 'Invite bootstrap should not preload pre-join history',
        );

        final receiverListener = GroupMessageListener(
          groupRepo: receiverGroupRepo,
          msgRepo: receiverMsgRepo,
          getSelfPeerId: () async => _receiverPeerId,
        );

        await receiverListener.handleReplayEnvelope({
          'groupId': groupId,
          'senderId': _adminPeerId,
          'senderUsername': 'Admin',
          'keyEpoch': _keyEpoch,
          'text': postJoinReplayText,
          'timestamp': DateTime.utc(2026, 3, 4, 0, 3).toIso8601String(),
          'messageId': 'msg-postjoin-replay',
        });

        final receiverIncoming = (await receiverMsgRepo.getMessagesPage(
          groupId,
        )).where((message) => message.isIncoming).toList();
        expect(receiverIncoming.map((message) => message.text).toList(), [
          postJoinReplayText,
        ]);
        expect(receiverIncoming.single.text, isNot(preJoinText));
        expect(receiverIncoming.single.keyGeneration, _keyEpoch);

        receiverListener.dispose();
        adminP2P.dispose();
      },
    );

    test(
      'BB-007 accepted pending invite joins with exact full config and replays accepted epoch',
      () async {
        const groupId = 'grp-bb007-accepted-pending';
        const groupKey = 'base64BB007AcceptedGroupKey==';
        const keyEpoch = 7;
        const replayMessageId = 'bb007-replay-at-accepted-epoch';
        final receivedAt = DateTime.utc(2026, 5, 10, 20);
        final groupConfig = _makeGroupConfig();
        final receiverBridge = FakeBridge();
        final receiverPendingInviteRepo =
            InMemoryPendingGroupInviteRepository();
        final receiverGroupRepo = InMemoryGroupRepository();
        final receiverMsgRepo = InMemoryGroupMessageRepository();
        final receiverContactRepo = FakeContactRepository()
          ..seed([_adminContact()]);

        await receiverPendingInviteRepo.savePendingInvite(
          PendingGroupInvite.fromPayload(
            GroupInvitePayload(
              id: 'invite-bb007-exact-material',
              groupId: groupId,
              groupKey: groupKey,
              keyEpoch: keyEpoch,
              groupConfig: groupConfig,
              senderPeerId: _adminPeerId,
              senderUsername: 'Admin',
              timestamp: receivedAt.toIso8601String(),
              recipientPeerId: _receiverPeerId,
              invitePolicy: _makeInvitePolicy(
                recipientPeerId: _receiverPeerId,
                expiresAt: receivedAt.add(pendingGroupInviteTtl),
                keyEpoch: keyEpoch,
              ),
              membershipFreshnessProof: _makeFreshnessProof(
                inviteId: 'invite-bb007-exact-material',
                groupId: groupId,
                recipientPeerId: _receiverPeerId,
                groupConfig: groupConfig,
                keyEpoch: keyEpoch,
                issuedAt: receivedAt,
              ),
            ).withInviteSignature(signature: 'signed-invite-by-admin'),
            receivedAt: receivedAt,
          ),
        );

        final (acceptResult, acceptedGroup) = await acceptPendingGroupInvite(
          pendingInviteRepo: receiverPendingInviteRepo,
          groupRepo: receiverGroupRepo,
          contactRepo: receiverContactRepo,
          msgRepo: receiverMsgRepo,
          bridge: receiverBridge,
          groupId: groupId,
          senderPeerId: _receiverPeerId,
          senderPublicKey: 'receiverPubKey64',
          senderPrivateKey: 'receiverPrivKey64',
          senderUsername: 'Receiver',
          now: receivedAt.add(const Duration(minutes: 1)),
        );

        expect(acceptResult, AcceptPendingGroupInviteResult.success);
        expect(acceptedGroup, isNotNull);

        final joinCommands = receiverBridge.sentMessages
            .map((message) => jsonDecode(message) as Map<String, dynamic>)
            .where((message) => message['cmd'] == 'group:join')
            .toList();
        expect(joinCommands, hasLength(1));
        final joinPayload =
            joinCommands.single['payload'] as Map<String, dynamic>;
        expect(joinPayload['groupId'], groupId);
        expect(joinPayload['groupConfig'], equals(groupConfig));
        expect(joinPayload['groupKey'], groupKey);
        expect(joinPayload['keyEpoch'], keyEpoch);
        expect(joinPayload, isNot(contains('topicName')));

        final latestKey = await receiverGroupRepo.getLatestKey(groupId);
        expect(latestKey, isNotNull);
        expect(latestKey!.encryptedKey, groupKey);
        expect(latestKey.keyGeneration, keyEpoch);

        final replayListener = GroupMessageListener(
          groupRepo: receiverGroupRepo,
          msgRepo: receiverMsgRepo,
          bridge: receiverBridge,
          getSelfPeerId: () async => _receiverPeerId,
        );
        addTearDown(replayListener.dispose);

        final replayEnvelope = await buildGroupOfflineReplayEnvelope(
          bridge: receiverBridge,
          groupRepo: receiverGroupRepo,
          groupId: groupId,
          payloadType: groupOfflineReplayPayloadTypeMessage,
          plaintext: jsonEncode({
            'groupId': groupId,
            'messageId': replayMessageId,
            'senderId': _adminPeerId,
            'senderUsername': 'Admin',
            'keyEpoch': keyEpoch,
            'text': 'BB-007 replayed at accepted epoch',
            'timestamp': receivedAt
                .add(const Duration(minutes: 2))
                .toIso8601String(),
          }),
          messageId: replayMessageId,
          senderPeerId: _adminPeerId,
          senderPublicKey: 'adminPubKey64',
          senderPrivateKey: 'adminPrivKey64',
        );
        receiverBridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': [
            {'from': _adminPeerId, 'message': replayEnvelope},
          ],
          'cursor': '',
        };

        await drainGroupOfflineInboxForGroup(
          bridge: receiverBridge,
          groupRepo: receiverGroupRepo,
          msgRepo: receiverMsgRepo,
          groupId: groupId,
          groupMessageListener: replayListener,
        );

        final recoveredMessage = await receiverMsgRepo.getMessage(
          replayMessageId,
        );
        expect(recoveredMessage, isNotNull);
        expect(recoveredMessage!.text, 'BB-007 replayed at accepted epoch');
        expect(recoveredMessage.senderPeerId, _adminPeerId);
        expect(recoveredMessage.keyGeneration, keyEpoch);
      },
    );

    test(
      'remove -> rotate -> re-invite round-trip gives the rejoined member the rotated epoch',
      () async {
        final adminBridge = PassthroughCryptoBridge();
        final adminP2P = FakeP2PService(
          initialState: const NodeState(isStarted: true),
        );
        final adminGroupRepo = InMemoryGroupRepository();

        await adminGroupRepo.saveGroup(
          GroupModel(
            id: _groupId,
            name: 'Test Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/$_groupId',
            description: 'Integration test group',
            createdAt: DateTime.utc(2026, 3, 2),
            createdBy: _adminPeerId,
            myRole: GroupRole.admin,
          ),
        );
        await adminGroupRepo.saveMember(
          GroupMember(
            groupId: _groupId,
            peerId: _adminPeerId,
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'adminPubKey64',
            mlKemPublicKey: _adminMlKemPublicKey,
            joinedAt: DateTime.utc(2026, 3, 2),
          ),
        );
        await adminGroupRepo.saveMember(
          GroupMember(
            groupId: _groupId,
            peerId: _receiverPeerId,
            username: 'Receiver',
            role: MemberRole.writer,
            publicKey: 'receiverPubKey64',
            mlKemPublicKey: _receiverMlKemPublicKey,
            joinedAt: DateTime.utc(2026, 3, 2),
          ),
        );
        await adminGroupRepo.saveKey(
          GroupKeyInfo(
            groupId: _groupId,
            keyGeneration: 1,
            encryptedKey: _groupKey,
            createdAt: DateTime.utc(2026, 3, 2),
          ),
        );

        adminBridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': 'rotated-reinvite-key==',
          'keyEpoch': 2,
        };

        await removeGroupMember(
          bridge: adminBridge,
          groupRepo: adminGroupRepo,
          groupId: _groupId,
          memberPeerId: _receiverPeerId,
        );

        final rotatedKey = await rotateAndDistributeGroupKey(
          bridge: adminBridge,
          groupRepo: adminGroupRepo,
          groupId: _groupId,
          selfPeerId: _adminPeerId,
          senderPublicKey: 'adminPubKey64',
          senderPrivateKey: 'adminPrivKey64',
          senderUsername: 'Admin',
          sendP2PMessage: (_, _) async => true,
        );

        expect(rotatedKey, isNotNull);
        expect(rotatedKey!.keyGeneration, 2);
        expect(rotatedKey.encryptedKey, 'rotated-reinvite-key==');

        await adminGroupRepo.saveMember(
          GroupMember(
            groupId: _groupId,
            peerId: _receiverPeerId,
            username: 'Receiver',
            role: MemberRole.writer,
            publicKey: 'receiverPubKey64',
            mlKemPublicKey: _receiverMlKemPublicKey,
            joinedAt: DateTime.utc(2026, 3, 2, 0, 1),
          ),
        );

        final adminGroup = await adminGroupRepo.getGroup(_groupId);
        final adminMembers = await adminGroupRepo.getMembers(_groupId);
        final rejoinConfig = {
          'name': adminGroup!.name,
          'groupType': adminGroup.type.toValue(),
          if (adminGroup.description != null)
            'description': adminGroup.description,
          'members': adminMembers
              .map(
                (member) => {
                  'peerId': member.peerId,
                  'username': member.username,
                  'role': member.role.toValue(),
                  'publicKey': member.publicKey,
                  if (member.mlKemPublicKey != null)
                    'mlKemPublicKey': member.mlKemPublicKey,
                },
              )
              .toList(),
          'createdBy': adminGroup.createdBy,
          'createdAt': adminGroup.createdAt.toUtc().toIso8601String(),
        };

        final sendResult = await sendGroupInvite(
          p2pService: adminP2P,
          bridge: adminBridge,
          groupRepo: await _repoFromConfig(rejoinConfig),
          recipientPeerId: _receiverPeerId,
          recipientMlKemPublicKey: _receiverMlKemPublicKey,
          senderPeerId: _adminPeerId,
          senderPublicKey: 'adminPubKey64',
          senderPrivateKey: 'adminPrivKey64',
          senderUsername: 'Admin',
          groupId: _groupId,
          groupKey: rotatedKey.encryptedKey,
          keyEpoch: rotatedKey.keyGeneration,
          groupConfig: rejoinConfig,
        );

        expect(sendResult, equals(SendGroupInviteResult.success));

        final reinviteContent = adminP2P.lastSendMessageContent!;
        final outerEnvelope =
            jsonDecode(reinviteContent) as Map<String, dynamic>;
        final encrypted = outerEnvelope['encrypted'] as Map<String, dynamic>;
        final inviteInner =
            jsonDecode(encrypted['ciphertext'] as String)
                as Map<String, dynamic>;
        expect(inviteInner['groupKey'], 'rotated-reinvite-key==');
        expect(inviteInner['keyEpoch'], 2);

        final receiverBridge = PassthroughCryptoBridge();
        receiverBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-reinvite-epoch-2',
          'topicPeers': 1,
        };
        final receiverGroupRepo = InMemoryGroupRepository();
        final receiverMsgRepo = InMemoryGroupMessageRepository();
        final receiverContactRepo = FakeContactRepository();
        receiverContactRepo.seed([_adminContact()]);

        final incomingMessage = ChatMessage(
          from: _adminPeerId,
          to: _receiverPeerId,
          content: reinviteContent,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        );

        final (handleResult, handleGroupId) = await handleIncomingGroupInvite(
          message: incomingMessage,
          groupRepo: receiverGroupRepo,
          contactRepo: receiverContactRepo,
          bridge: receiverBridge,
          ownMlKemSecretKey: _receiverMlKemSecretKey,
          ownPeerId: _receiverPeerId,
        );

        expect(handleResult, equals(HandleGroupInviteResult.success));
        expect(handleGroupId, equals(_groupId));

        final receiverKey = await receiverGroupRepo.getLatestKey(_groupId);
        expect(receiverKey, isNotNull);
        expect(receiverKey!.encryptedKey, 'rotated-reinvite-key==');
        expect(receiverKey.keyGeneration, 2);

        final (sendAfterReinviteResult, rejoinedMessage) = await group_send
            .sendGroupMessage(
              bridge: receiverBridge,
              groupRepo: receiverGroupRepo,
              msgRepo: receiverMsgRepo,
              groupId: _groupId,
              text: 'Rejoined on fresh epoch',
              senderPeerId: _receiverPeerId,
              senderPublicKey: 'receiverPubKey64',
              senderPrivateKey: 'receiverPrivKey64',
              senderUsername: 'Receiver',
              messageId: 'msg-reinvite-epoch-2',
            );

        expect(
          sendAfterReinviteResult,
          group_send.SendGroupMessageResult.success,
        );
        expect(rejoinedMessage, isNotNull);
        expect(rejoinedMessage!.keyGeneration, 2);

        final inboxPayload = _lastGroupInboxStorePayload(receiverBridge);
        final inboxEnvelope =
            jsonDecode(inboxPayload['message'] as String)
                as Map<String, dynamic>;
        expect(inboxEnvelope['keyEpoch'], 2);
        expect(inboxEnvelope['messageId'], 'msg-reinvite-epoch-2');

        adminP2P.dispose();
      },
    );

    test(
      'offline removed member reconnects later from inbox-fallback re-invite on the rotated epoch',
      () async {
        const groupId = 'grp-reinvite-offline-010';

        final adminBridge = PassthroughCryptoBridge();
        final adminP2P = FakeP2PService(
          initialState: const NodeState(isStarted: true),
          sendMessageResult: false,
          storeInInboxResult: true,
        );
        final adminGroupRepo = InMemoryGroupRepository();

        await adminGroupRepo.saveGroup(
          GroupModel(
            id: groupId,
            name: 'Offline Reinvite Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/$groupId',
            description: 'Offline reinvite integration test group',
            createdAt: DateTime.utc(2026, 3, 3),
            createdBy: _adminPeerId,
            myRole: GroupRole.admin,
          ),
        );
        await adminGroupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: _adminPeerId,
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'adminPubKey64',
            mlKemPublicKey: _adminMlKemPublicKey,
            joinedAt: DateTime.utc(2026, 3, 3),
          ),
        );
        await adminGroupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: _receiverPeerId,
            username: 'Receiver',
            role: MemberRole.writer,
            publicKey: 'receiverPubKey64',
            mlKemPublicKey: _receiverMlKemPublicKey,
            joinedAt: DateTime.utc(2026, 3, 3),
          ),
        );
        await adminGroupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: _groupKey,
            createdAt: DateTime.utc(2026, 3, 3),
          ),
        );

        adminBridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': 'rotated-offline-reinvite-key==',
          'keyEpoch': 2,
        };

        await removeGroupMember(
          bridge: adminBridge,
          groupRepo: adminGroupRepo,
          groupId: groupId,
          memberPeerId: _receiverPeerId,
        );

        final rotatedKey = await rotateAndDistributeGroupKey(
          bridge: adminBridge,
          groupRepo: adminGroupRepo,
          groupId: groupId,
          selfPeerId: _adminPeerId,
          senderPublicKey: 'adminPubKey64',
          senderPrivateKey: 'adminPrivKey64',
          senderUsername: 'Admin',
          sendP2PMessage: (_, _) async => true,
        );

        expect(rotatedKey, isNotNull);
        expect(rotatedKey!.keyGeneration, 2);
        expect(rotatedKey.encryptedKey, 'rotated-offline-reinvite-key==');

        await adminGroupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: _receiverPeerId,
            username: 'Receiver',
            role: MemberRole.writer,
            publicKey: 'receiverPubKey64',
            mlKemPublicKey: _receiverMlKemPublicKey,
            joinedAt: DateTime.utc(2026, 3, 3, 0, 1),
          ),
        );

        final adminGroup = await adminGroupRepo.getGroup(groupId);
        final adminMembers = await adminGroupRepo.getMembers(groupId);
        final rejoinConfig = {
          'name': adminGroup!.name,
          'groupType': adminGroup.type.toValue(),
          if (adminGroup.description != null)
            'description': adminGroup.description,
          'members': adminMembers
              .map(
                (member) => {
                  'peerId': member.peerId,
                  'username': member.username,
                  'role': member.role.toValue(),
                  'publicKey': member.publicKey,
                  if (member.mlKemPublicKey != null)
                    'mlKemPublicKey': member.mlKemPublicKey,
                },
              )
              .toList(),
          'createdBy': adminGroup.createdBy,
          'createdAt': adminGroup.createdAt.toUtc().toIso8601String(),
        };

        final sendResult = await sendGroupInvite(
          p2pService: adminP2P,
          bridge: adminBridge,
          groupRepo: await _repoFromConfig(rejoinConfig, groupId: groupId),
          recipientPeerId: _receiverPeerId,
          recipientMlKemPublicKey: _receiverMlKemPublicKey,
          senderPeerId: _adminPeerId,
          senderPublicKey: 'adminPubKey64',
          senderPrivateKey: 'adminPrivKey64',
          senderUsername: 'Admin',
          groupId: groupId,
          groupKey: rotatedKey.encryptedKey,
          keyEpoch: rotatedKey.keyGeneration,
          groupConfig: rejoinConfig,
        );

        expect(sendResult, equals(SendGroupInviteResult.queued));
        expect(
          adminP2P.sendMessageCallCount,
          1,
          reason: 'The admin should attempt a direct re-invite first',
        );
        expect(
          adminP2P.storeInInboxCallCount,
          1,
          reason: 'Offline re-invites should fall back to inbox storage',
        );

        final storedInviteContent = adminP2P.lastStoreInInboxMessage;
        expect(storedInviteContent, isNotNull);
        expect(adminP2P.lastStoreInInboxPeerId, _receiverPeerId);

        final storedEnvelope = GroupInvitePayload.parseEncryptedEnvelope(
          storedInviteContent!,
        );
        expect(storedEnvelope, isNotNull);
        final storedEncrypted =
            storedEnvelope!['encrypted'] as Map<String, dynamic>;
        final storedInner =
            jsonDecode(storedEncrypted['ciphertext'] as String)
                as Map<String, dynamic>;
        expect(storedInner['groupId'], groupId);
        expect(storedInner['groupKey'], 'rotated-offline-reinvite-key==');
        expect(storedInner['keyEpoch'], 2);

        final receiverBridge = PassthroughCryptoBridge();
        receiverBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-offline-reinvite-epoch-2',
          'topicPeers': 1,
        };
        final receiverGroupRepo = InMemoryGroupRepository();
        final receiverMsgRepo = InMemoryGroupMessageRepository();
        final receiverContactRepo = FakeContactRepository();
        receiverContactRepo.seed([_adminContact()]);

        final incomingMessage = ChatMessage(
          from: _adminPeerId,
          to: _receiverPeerId,
          content: storedInviteContent,
          timestamp: DateTime.utc(2026, 3, 3, 0, 2).toIso8601String(),
          isIncoming: true,
        );

        final (handleResult, handleGroupId) = await handleIncomingGroupInvite(
          message: incomingMessage,
          groupRepo: receiverGroupRepo,
          contactRepo: receiverContactRepo,
          bridge: receiverBridge,
          ownMlKemSecretKey: _receiverMlKemSecretKey,
          ownPeerId: _receiverPeerId,
        );

        expect(handleResult, equals(HandleGroupInviteResult.success));
        expect(handleGroupId, equals(groupId));

        final receiverGroup = await receiverGroupRepo.getGroup(groupId);
        expect(receiverGroup, isNotNull);
        expect(receiverGroup!.name, 'Offline Reinvite Group');
        expect(receiverGroup.myRole, GroupRole.member);

        final receiverMembers = await receiverGroupRepo.getMembers(groupId);
        expect(receiverMembers.map((member) => member.peerId).toSet(), {
          _adminPeerId,
          _receiverPeerId,
        });

        final receiverKey = await receiverGroupRepo.getLatestKey(groupId);
        expect(receiverKey, isNotNull);
        expect(receiverKey!.encryptedKey, 'rotated-offline-reinvite-key==');
        expect(receiverKey.keyGeneration, 2);

        final (sendAfterReconnectResult, rejoinedMessage) = await group_send
            .sendGroupMessage(
              bridge: receiverBridge,
              groupRepo: receiverGroupRepo,
              msgRepo: receiverMsgRepo,
              groupId: groupId,
              text: 'Back after offline rejoin',
              senderPeerId: _receiverPeerId,
              senderPublicKey: 'receiverPubKey64',
              senderPrivateKey: 'receiverPrivKey64',
              senderUsername: 'Receiver',
              messageId: 'msg-offline-reinvite-epoch-2',
            );

        expect(
          sendAfterReconnectResult,
          group_send.SendGroupMessageResult.success,
        );
        expect(rejoinedMessage, isNotNull);
        expect(rejoinedMessage!.keyGeneration, 2);

        final inboxPayload = _lastGroupInboxStorePayload(receiverBridge);
        final inboxEnvelope =
            jsonDecode(inboxPayload['message'] as String)
                as Map<String, dynamic>;
        expect(inboxEnvelope['keyEpoch'], 2);
        expect(inboxEnvelope['messageId'], 'msg-offline-reinvite-epoch-2');

        adminP2P.dispose();
      },
    );

    // -----------------------------------------------------------------------
    // 2. Full round-trip with PassthroughCryptoBridge verifies
    //    encryption/decryption.
    // -----------------------------------------------------------------------
    test('full round-trip with PassthroughCryptoBridge verifies '
        'encryption/decryption', () async {
      final adminBridge = PassthroughCryptoBridge();
      final adminP2P = FakeP2PService(
        initialState: const NodeState(isStarted: true),
      );

      final groupConfig = _makeGroupConfig();

      // Admin sends invite
      final sendResult = await sendGroupInvite(
        p2pService: adminP2P,
        bridge: adminBridge,
        groupRepo: await _repoFromConfig(groupConfig),
        recipientPeerId: _receiverPeerId,
        recipientMlKemPublicKey: _receiverMlKemPublicKey,
        senderPeerId: _adminPeerId,
        senderPublicKey: 'adminPubKey64',
        senderPrivateKey: 'adminPrivKey64',
        senderUsername: 'Admin',
        groupId: _groupId,
        groupKey: _groupKey,
        keyEpoch: _keyEpoch,
        groupConfig: groupConfig,
      );
      expect(sendResult, equals(SendGroupInviteResult.success));

      final sentContent = adminP2P.lastSendMessageContent!;

      // With PassthroughCryptoBridge, ciphertext == inner JSON (plaintext)
      final envelope = jsonDecode(sentContent) as Map<String, dynamic>;
      final encrypted = envelope['encrypted'] as Map<String, dynamic>;
      final ciphertextRaw = encrypted['ciphertext'] as String;

      // The ciphertext is the inner JSON because PassthroughCryptoBridge
      // returns plaintext as-is in the ciphertext field.
      final innerPayload = jsonDecode(ciphertextRaw) as Map<String, dynamic>;
      expect(innerPayload['groupId'], equals(_groupId));
      expect(innerPayload['groupKey'], equals(_groupKey));
      expect(innerPayload['keyEpoch'], equals(_keyEpoch));
      expect(innerPayload['senderPeerId'], equals(_adminPeerId));
      expect(innerPayload['senderUsername'], equals('Admin'));
      expect(innerPayload['groupConfig'], isA<Map<String, dynamic>>());

      // Now receiver decrypts using PassthroughCryptoBridge
      final receiverBridge = PassthroughCryptoBridge();
      final receiverGroupRepo = InMemoryGroupRepository();
      final receiverContactRepo = FakeContactRepository();
      receiverContactRepo.seed([_adminContact()]);

      final incomingMessage = ChatMessage(
        from: _adminPeerId,
        to: _receiverPeerId,
        content: sentContent,
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
      );

      final (handleResult, _) = await handleIncomingGroupInvite(
        message: incomingMessage,
        groupRepo: receiverGroupRepo,
        contactRepo: receiverContactRepo,
        bridge: receiverBridge,
        ownMlKemSecretKey: _receiverMlKemSecretKey,
        ownPeerId: _receiverPeerId,
      );

      expect(handleResult, equals(HandleGroupInviteResult.success));

      // Verify the decrypted payload matches the original
      final group = await receiverGroupRepo.getGroup(_groupId);
      expect(group, isNotNull);
      expect(group!.name, equals('Test Group'));
      expect(group.description, equals('Integration test group'));

      final persistedKey = await receiverGroupRepo.getLatestKey(_groupId);
      expect(persistedKey!.encryptedKey, equals(_groupKey));
      expect(persistedKey.keyGeneration, equals(_keyEpoch));

      // Cleanup
      adminP2P.dispose();
    });

    // -----------------------------------------------------------------------
    // 3. Receiver rejects invite from unknown sender (not in contacts).
    // -----------------------------------------------------------------------
    test(
      'receiver rejects invite from unknown sender (not in contacts)',
      () async {
        final adminBridge = PassthroughCryptoBridge();
        final adminP2P = FakeP2PService(
          initialState: const NodeState(isStarted: true),
        );

        final groupConfig = _makeGroupConfig();

        // Admin sends invite
        final sendResult = await sendGroupInvite(
          p2pService: adminP2P,
          bridge: adminBridge,
          groupRepo: await _repoFromConfig(groupConfig),
          recipientPeerId: _receiverPeerId,
          recipientMlKemPublicKey: _receiverMlKemPublicKey,
          senderPeerId: _adminPeerId,
          senderPublicKey: 'adminPubKey64',
          senderPrivateKey: 'adminPrivKey64',
          senderUsername: 'Admin',
          groupId: _groupId,
          groupKey: _groupKey,
          keyEpoch: _keyEpoch,
          groupConfig: groupConfig,
        );
        expect(sendResult, equals(SendGroupInviteResult.success));

        final sentContent = adminP2P.lastSendMessageContent!;

        // Receiver side: EMPTY contact repo (admin is NOT a contact)
        final receiverBridge = PassthroughCryptoBridge();
        final receiverGroupRepo = InMemoryGroupRepository();
        final receiverContactRepo = FakeContactRepository();
        // No contacts seeded!

        final incomingMessage = ChatMessage(
          from: _adminPeerId,
          to: _receiverPeerId,
          content: sentContent,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        );

        final (handleResult, handleGroupId) = await handleIncomingGroupInvite(
          message: incomingMessage,
          groupRepo: receiverGroupRepo,
          contactRepo: receiverContactRepo,
          bridge: receiverBridge,
          ownMlKemSecretKey: _receiverMlKemSecretKey,
          ownPeerId: _receiverPeerId,
        );

        expect(handleResult, equals(HandleGroupInviteResult.unknownSender));
        expect(handleGroupId, isNull);

        // Group is NOT saved
        final group = await receiverGroupRepo.getGroup(_groupId);
        expect(group, isNull);
        expect(receiverGroupRepo.groupCount, equals(0));

        // Cleanup
        adminP2P.dispose();
      },
    );

    // -----------------------------------------------------------------------
    // 4. Receiver rejects duplicate invite for group already joined.
    // -----------------------------------------------------------------------
    test(
      'receiver rejects duplicate invite for group already joined',
      () async {
        final adminBridge = PassthroughCryptoBridge();
        final adminP2P = FakeP2PService(
          initialState: const NodeState(isStarted: true),
        );

        final groupConfig = _makeGroupConfig();

        // Admin sends invite
        final sendResult = await sendGroupInvite(
          p2pService: adminP2P,
          bridge: adminBridge,
          groupRepo: await _repoFromConfig(groupConfig),
          recipientPeerId: _receiverPeerId,
          recipientMlKemPublicKey: _receiverMlKemPublicKey,
          senderPeerId: _adminPeerId,
          senderPublicKey: 'adminPubKey64',
          senderPrivateKey: 'adminPrivKey64',
          senderUsername: 'Admin',
          groupId: _groupId,
          groupKey: _groupKey,
          keyEpoch: _keyEpoch,
          groupConfig: groupConfig,
        );
        expect(sendResult, equals(SendGroupInviteResult.success));

        final sentContent = adminP2P.lastSendMessageContent!;

        // Receiver already has the group in their repo
        final receiverBridge = PassthroughCryptoBridge();
        final receiverGroupRepo = InMemoryGroupRepository();
        final receiverContactRepo = FakeContactRepository();
        receiverContactRepo.seed([_adminContact()]);

        // Pre-populate the group
        await receiverGroupRepo.saveGroup(
          GroupModel(
            id: _groupId,
            name: 'Already Joined Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/$_groupId',
            createdAt: DateTime.utc(2026, 1, 1),
            createdBy: _adminPeerId,
            myRole: GroupRole.member,
          ),
        );

        final incomingMessage = ChatMessage(
          from: _adminPeerId,
          to: _receiverPeerId,
          content: sentContent,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        );

        final (handleResult, handleGroupId) = await handleIncomingGroupInvite(
          message: incomingMessage,
          groupRepo: receiverGroupRepo,
          contactRepo: receiverContactRepo,
          bridge: receiverBridge,
          ownMlKemSecretKey: _receiverMlKemSecretKey,
          ownPeerId: _receiverPeerId,
        );

        expect(handleResult, equals(HandleGroupInviteResult.duplicateGroup));
        expect(handleGroupId, isNull);

        // Group name is unchanged (no overwrite)
        final group = await receiverGroupRepo.getGroup(_groupId);
        expect(group!.name, equals('Already Joined Group'));

        // No extra members or keys saved
        final members = await receiverGroupRepo.getMembers(_groupId);
        expect(members, isEmpty);

        final key = await receiverGroupRepo.getLatestKey(_groupId);
        expect(key, isNull);

        // Cleanup
        adminP2P.dispose();
      },
    );

    // -----------------------------------------------------------------------
    // 5. Invite round-trip with multiple members in config.
    // -----------------------------------------------------------------------
    test('invite round-trip with multiple members in config', () async {
      final adminBridge = PassthroughCryptoBridge();
      final adminP2P = FakeP2PService(
        initialState: const NodeState(isStarted: true),
      );

      // Group has 3 existing members + inviting a 4th
      final extraMembers = [
        {
          'peerId': '12D3KooWMember3',
          'username': 'Member3',
          'role': 'writer',
          'publicKey': 'member3PubKey64',
          'mlKemPublicKey': 'member3MlKem64',
        },
        {
          'peerId': '12D3KooWMember4',
          'username': 'Member4',
          'role': 'reader',
          'publicKey': 'member4PubKey64',
          'mlKemPublicKey': 'member4MlKem64',
        },
      ];
      final groupConfig = _makeGroupConfig(extraMembers: extraMembers);

      // Admin sends invite to receiver (who is 1 of 4 members)
      final sendResult = await sendGroupInvite(
        p2pService: adminP2P,
        bridge: adminBridge,
        groupRepo: await _repoFromConfig(groupConfig),
        recipientPeerId: _receiverPeerId,
        recipientMlKemPublicKey: _receiverMlKemPublicKey,
        senderPeerId: _adminPeerId,
        senderPublicKey: 'adminPubKey64',
        senderPrivateKey: 'adminPrivKey64',
        senderUsername: 'Admin',
        groupId: _groupId,
        groupKey: _groupKey,
        keyEpoch: _keyEpoch,
        groupConfig: groupConfig,
      );
      expect(sendResult, equals(SendGroupInviteResult.success));

      final sentContent = adminP2P.lastSendMessageContent!;

      // Receiver side
      final receiverBridge = PassthroughCryptoBridge();
      final receiverGroupRepo = InMemoryGroupRepository();
      final receiverContactRepo = FakeContactRepository();
      receiverContactRepo.seed([_adminContact()]);

      final incomingMessage = ChatMessage(
        from: _adminPeerId,
        to: _receiverPeerId,
        content: sentContent,
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
      );

      final (handleResult, handleGroupId) = await handleIncomingGroupInvite(
        message: incomingMessage,
        groupRepo: receiverGroupRepo,
        contactRepo: receiverContactRepo,
        bridge: receiverBridge,
        ownMlKemSecretKey: _receiverMlKemSecretKey,
        ownPeerId: _receiverPeerId,
      );

      expect(handleResult, equals(HandleGroupInviteResult.success));
      expect(handleGroupId, equals(_groupId));

      // Receiver's persisted group has ALL 4 members
      final members = await receiverGroupRepo.getMembers(_groupId);
      expect(members, hasLength(4));

      final peerIds = members.map((m) => m.peerId).toSet();
      expect(peerIds, contains(_adminPeerId));
      expect(peerIds, contains(_receiverPeerId));
      expect(peerIds, contains('12D3KooWMember3'));
      expect(peerIds, contains('12D3KooWMember4'));

      // Verify roles
      final adminMember = members.firstWhere((m) => m.peerId == _adminPeerId);
      expect(adminMember.role, equals(MemberRole.admin));

      final member3 = members.firstWhere((m) => m.peerId == '12D3KooWMember3');
      expect(member3.role, equals(MemberRole.writer));

      final member4 = members.firstWhere((m) => m.peerId == '12D3KooWMember4');
      expect(member4.role, equals(MemberRole.reader));

      // Key is still persisted correctly
      final key = await receiverGroupRepo.getLatestKey(_groupId);
      expect(key, isNotNull);
      expect(key!.encryptedKey, equals(_groupKey));

      // Cleanup
      adminP2P.dispose();
    });

    // -----------------------------------------------------------------------
    // 6. GroupInviteListener processes invite from router stream end-to-end.
    // -----------------------------------------------------------------------
    test(
      'GroupInviteListener stores pending invite and explicit accept completes the join flow',
      () async {
        // We simulate the IncomingMessageRouter's groupInviteStream
        // by using a StreamController directly.
        final groupInviteStreamController =
            StreamController<ChatMessage>.broadcast();

        final receiverBridge = PassthroughCryptoBridge();
        final receiverGroupRepo = InMemoryGroupRepository();
        final receiverPendingInviteRepo =
            InMemoryPendingGroupInviteRepository();
        final receiverMsgRepo = InMemoryGroupMessageRepository();
        final receiverContactRepo = FakeContactRepository()
          ..seed([_adminContact()]);

        final listener = GroupInviteListener(
          groupInviteStream: groupInviteStreamController.stream,
          groupRepo: receiverGroupRepo,
          contactRepo: receiverContactRepo,
          pendingInviteRepo: receiverPendingInviteRepo,
          bridge: receiverBridge,
          msgRepo: receiverMsgRepo,
          getOwnMlKemSecretKey: () async => _receiverMlKemSecretKey,
          getOwnPeerId: () async => _receiverPeerId,
        );

        final pendingInviteFuture = listener.pendingInviteStream.first;

        listener.start();

        // Build a v2 encrypted invite (what sendGroupInvite would produce)
        final adminBridge = PassthroughCryptoBridge();
        final adminP2P = FakeP2PService(
          initialState: const NodeState(isStarted: true),
        );
        final groupConfig = _makeGroupConfig();

        await sendGroupInvite(
          p2pService: adminP2P,
          bridge: adminBridge,
          groupRepo: await _repoFromConfig(groupConfig),
          recipientPeerId: _receiverPeerId,
          recipientMlKemPublicKey: _receiverMlKemPublicKey,
          senderPeerId: _adminPeerId,
          senderPublicKey: 'adminPubKey64',
          senderPrivateKey: 'adminPrivKey64',
          senderUsername: 'Admin',
          groupId: _groupId,
          groupKey: _groupKey,
          keyEpoch: _keyEpoch,
          groupConfig: groupConfig,
        );

        final sentContent = adminP2P.lastSendMessageContent!;

        // Feed the message through the stream (simulating what
        // IncomingMessageRouter would do after routing a group_invite)
        final incomingMessage = ChatMessage(
          from: _adminPeerId,
          to: _receiverPeerId,
          content: sentContent,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        );
        groupInviteStreamController.add(incomingMessage);

        final pendingInvite = await pendingInviteFuture.timeout(
          const Duration(seconds: 5),
        );

        expect(pendingInvite.groupId, equals(_groupId));
        expect(pendingInvite.groupName, equals('Test Group'));
        expect(await receiverGroupRepo.getGroup(_groupId), isNull);
        final pendingPayload = pendingInvite.toPayload();
        expect(pendingPayload, isNotNull);
        expect(pendingPayload!.invitePolicy.allowedDevices, [_receiverPeerId]);
        expect(pendingPayload.invitePolicy.assignedRole, 'writer');
        expect(pendingPayload.invitePolicy.keyEpoch, _keyEpoch);
        expect(pendingInvite.expiresAt, pendingPayload.invitePolicy.expiresAt);

        final (acceptResult, joinedGroup) = await acceptPendingGroupInvite(
          pendingInviteRepo: receiverPendingInviteRepo,
          groupRepo: receiverGroupRepo,
          contactRepo: receiverContactRepo,
          msgRepo: receiverMsgRepo,
          bridge: receiverBridge,
          groupId: _groupId,
        );

        expect(acceptResult, AcceptPendingGroupInviteResult.success);
        expect(joinedGroup, isNotNull);
        expect(joinedGroup!.id, equals(_groupId));
        expect(joinedGroup.name, equals('Test Group'));
        expect(joinedGroup.myRole, equals(GroupRole.member));

        // Verify group is persisted in the repo
        final persistedGroup = await receiverGroupRepo.getGroup(_groupId);
        expect(persistedGroup, isNotNull);
        expect(persistedGroup!.name, equals('Test Group'));

        // Verify members are persisted
        final members = await receiverGroupRepo.getMembers(_groupId);
        expect(members, hasLength(2));

        // Verify key is persisted
        final key = await receiverGroupRepo.getLatestKey(_groupId);
        expect(key, isNotNull);
        expect(key!.encryptedKey, equals(_groupKey));
        expect(
          await receiverPendingInviteRepo.getPendingInvite(_groupId),
          isNull,
        );

        // Cleanup
        listener.dispose();
        await groupInviteStreamController.close();
        adminP2P.dispose();
      },
    );

    test(
      'IJ005 multi-use direct credential replay is duplicate-safe',
      () async {
        final receivedAt = DateTime.utc(2026, 4, 30, 12);
        final receiverBridge = FakeBridge();
        final receiverGroupRepo = InMemoryGroupRepository();
        final receiverPendingInviteRepo =
            InMemoryPendingGroupInviteRepository();
        final receiverMsgRepo = InMemoryGroupMessageRepository();
        final receiverContactRepo = FakeContactRepository()
          ..seed([_adminContact()]);

        final replayableInvite = PendingGroupInvite.fromPayload(
          GroupInvitePayload(
            id: 'invite-multi-use-replay',
            groupId: _groupId,
            groupKey: _groupKey,
            keyEpoch: _keyEpoch,
            groupConfig: _makeGroupConfig(),
            senderPeerId: _adminPeerId,
            senderUsername: 'Admin',
            timestamp: receivedAt.toIso8601String(),
            recipientPeerId: _receiverPeerId,
            invitePolicy: _makeInvitePolicy(
              recipientPeerId: _receiverPeerId,
              expiresAt: receivedAt.add(pendingGroupInviteTtl),
              reusePolicy: GroupInviteReusePolicy.multiUse,
            ),
            membershipFreshnessProof: _makeFreshnessProof(
              inviteId: 'invite-multi-use-replay',
              groupId: _groupId,
              recipientPeerId: _receiverPeerId,
              groupConfig: _makeGroupConfig(),
              keyEpoch: _keyEpoch,
              issuedAt: receivedAt,
            ),
          ).withInviteSignature(signature: 'signed-invite-by-admin'),
          receivedAt: receivedAt,
        );

        await receiverPendingInviteRepo.savePendingInvite(replayableInvite);
        final (firstResult, firstGroup) = await acceptPendingGroupInvite(
          pendingInviteRepo: receiverPendingInviteRepo,
          groupRepo: receiverGroupRepo,
          contactRepo: receiverContactRepo,
          msgRepo: receiverMsgRepo,
          bridge: receiverBridge,
          groupId: _groupId,
          now: receivedAt.add(const Duration(minutes: 1)),
        );

        expect(firstResult, AcceptPendingGroupInviteResult.success);
        expect(firstGroup, isNotNull);
        expect(
          await receiverPendingInviteRepo.getPendingInvite(_groupId),
          isNull,
        );
        expect(
          await receiverPendingInviteRepo.getConsumedInvite(
            'invite-multi-use-replay',
          ),
          isNull,
        );
        expect(receiverGroupRepo.groupCount, 1);
        expect(await receiverGroupRepo.getMembers(_groupId), hasLength(2));
        expect(await receiverGroupRepo.getLatestKey(_groupId), isNotNull);

        await receiverPendingInviteRepo.savePendingInvite(replayableInvite);
        final (replayResult, replayGroup) = await acceptPendingGroupInvite(
          pendingInviteRepo: receiverPendingInviteRepo,
          groupRepo: receiverGroupRepo,
          contactRepo: receiverContactRepo,
          msgRepo: receiverMsgRepo,
          bridge: receiverBridge,
          groupId: _groupId,
          now: receivedAt.add(const Duration(minutes: 2)),
        );

        expect(replayResult, AcceptPendingGroupInviteResult.duplicateGroup);
        expect(replayGroup, isNull);
        expect(
          await receiverPendingInviteRepo.getPendingInvite(_groupId),
          isNull,
        );
        expect(receiverGroupRepo.groupCount, 1);
        expect(await receiverGroupRepo.getMembers(_groupId), hasLength(2));
        expect(await receiverGroupRepo.getLatestKey(_groupId), isNotNull);
        expect(
          receiverBridge.commandLog.where((cmd) => cmd == 'group:join'),
          hasLength(1),
        );
        expect(
          await receiverPendingInviteRepo.getConsumedInvite(
            'invite-multi-use-replay',
          ),
          isNull,
        );
      },
    );

    test(
      'IJ003 revoked invite removes pending state and delayed direct plus mailbox copies stay rejected',
      () async {
        final groupInviteStreamController =
            StreamController<ChatMessage>.broadcast();

        final receiverBridge = PassthroughCryptoBridge();
        final receiverGroupRepo = InMemoryGroupRepository();
        final receiverPendingInviteRepo =
            InMemoryPendingGroupInviteRepository();
        final receiverMsgRepo = InMemoryGroupMessageRepository();
        final receiverContactRepo = FakeContactRepository()
          ..seed([_adminContact()]);

        final listener = GroupInviteListener(
          groupInviteStream: groupInviteStreamController.stream,
          groupRepo: receiverGroupRepo,
          contactRepo: receiverContactRepo,
          pendingInviteRepo: receiverPendingInviteRepo,
          bridge: receiverBridge,
          msgRepo: receiverMsgRepo,
          getOwnMlKemSecretKey: () async => _receiverMlKemSecretKey,
          getOwnPeerId: () async => _receiverPeerId,
          now: () => DateTime.utc(2026, 4, 30, 12, 10),
        );
        addTearDown(listener.dispose);
        addTearDown(groupInviteStreamController.close);

        listener.start();

        final adminBridge = PassthroughCryptoBridge();
        final adminP2P = FakeP2PService(
          initialState: const NodeState(isStarted: true),
        );
        addTearDown(adminP2P.dispose);
        final groupConfig = _makeGroupConfig();

        final sendResult = await sendGroupInvite(
          p2pService: adminP2P,
          bridge: adminBridge,
          groupRepo: await _repoFromConfig(groupConfig),
          recipientPeerId: _receiverPeerId,
          recipientMlKemPublicKey: _receiverMlKemPublicKey,
          senderPeerId: _adminPeerId,
          senderPublicKey: 'adminPubKey64',
          senderPrivateKey: 'adminPrivKey64',
          senderUsername: 'Admin',
          groupId: _groupId,
          groupKey: _groupKey,
          keyEpoch: _keyEpoch,
          groupConfig: groupConfig,
        );
        expect(sendResult, SendGroupInviteResult.success);

        final inviteContent = adminP2P.lastSendMessageContent!;
        final inviteEnvelope =
            jsonDecode(inviteContent) as Map<String, dynamic>;
        final inviteId = inviteEnvelope['id'] as String;

        final pendingInviteFuture = listener.pendingInviteStream.first;
        groupInviteStreamController.add(
          ChatMessage(
            from: _adminPeerId,
            to: _receiverPeerId,
            content: inviteContent,
            timestamp: DateTime.utc(2026, 4, 30, 12).toIso8601String(),
            isIncoming: true,
          ),
        );
        final pendingInvite = await pendingInviteFuture.timeout(
          const Duration(seconds: 5),
        );
        expect(pendingInvite.inviteId, inviteId);
        expect(
          await receiverPendingInviteRepo.getPendingInvite(_groupId),
          isNotNull,
        );

        final revokeResult = await sendGroupInviteRevocation(
          p2pService: adminP2P,
          bridge: adminBridge,
          inviteId: inviteId,
          groupId: _groupId,
          recipientPeerId: _receiverPeerId,
          recipientMlKemPublicKey: _receiverMlKemPublicKey,
          senderPeerId: _adminPeerId,
          senderPublicKey: 'adminPubKey64',
          senderPrivateKey: 'adminPrivKey64',
          groupConfig: groupConfig,
          now: DateTime.utc(2026, 4, 30, 12, 5),
        );
        expect(revokeResult, SendGroupInviteRevocationResult.success);

        final revocationContent = adminP2P.lastSendMessageContent!;
        final refreshFuture = listener.pendingInviteStream.firstWhere(
          (invite) => invite.inviteId == inviteId,
        );
        groupInviteStreamController.add(
          ChatMessage(
            from: _adminPeerId,
            to: _receiverPeerId,
            content: revocationContent,
            timestamp: DateTime.utc(2026, 4, 30, 12, 5).toIso8601String(),
            isIncoming: true,
          ),
        );
        await refreshFuture.timeout(const Duration(seconds: 5));

        expect(
          await receiverPendingInviteRepo.getPendingInvite(_groupId),
          isNull,
        );
        expect(
          await receiverPendingInviteRepo.getRevokedInvite(inviteId),
          isNotNull,
        );
        expect(await receiverGroupRepo.getGroup(_groupId), isNull);
        expect(await receiverGroupRepo.getLatestKey(_groupId), isNull);

        groupInviteStreamController.add(
          ChatMessage(
            from: _adminPeerId,
            to: _receiverPeerId,
            content: inviteContent,
            timestamp: DateTime.utc(2026, 4, 30, 12, 10).toIso8601String(),
            isIncoming: true,
          ),
        );
        groupInviteStreamController.add(
          ChatMessage(
            from: _adminPeerId,
            to: _receiverPeerId,
            content: inviteContent,
            timestamp: DateTime.utc(2026, 4, 30, 12, 15).toIso8601String(),
            isIncoming: true,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(
          await receiverPendingInviteRepo.getPendingInvite(_groupId),
          isNull,
        );
        expect(await receiverGroupRepo.getGroup(_groupId), isNull);
        expect(await receiverGroupRepo.getLatestKey(_groupId), isNull);

        final (acceptResult, acceptedGroup) = await acceptPendingGroupInvite(
          pendingInviteRepo: receiverPendingInviteRepo,
          groupRepo: receiverGroupRepo,
          contactRepo: receiverContactRepo,
          msgRepo: receiverMsgRepo,
          bridge: receiverBridge,
          groupId: _groupId,
        );

        expect(acceptResult, AcceptPendingGroupInviteResult.notFound);
        expect(acceptedGroup, isNull);
        expect(
          await receiverPendingInviteRepo.getConsumedInvite(inviteId),
          isNull,
        );
        expect(await receiverGroupRepo.getGroup(_groupId), isNull);
        expect(await receiverGroupRepo.getLatestKey(_groupId), isNull);
        expect(receiverBridge.commandLog, isNot(contains('group:join')));
        expect(receiverMsgRepo.count, 0);
      },
    );

    test(
      'ML-018 decline expiry and cancellation never create active membership',
      () async {
        final receiverBridge = PassthroughCryptoBridge();
        final receiverGroupRepo = InMemoryGroupRepository();
        final receiverPendingInviteRepo =
            InMemoryPendingGroupInviteRepository();
        final receiverMsgRepo = InMemoryGroupMessageRepository();
        final receiverContactRepo = FakeContactRepository()
          ..seed([_adminContact()]);

        final adminBridge = PassthroughCryptoBridge();
        final adminP2P = FakeP2PService(
          initialState: const NodeState(isStarted: true),
        );
        addTearDown(adminP2P.dispose);

        ChatMessage inviteMessage(
          String content, {
          required DateTime timestamp,
        }) {
          return ChatMessage(
            from: _adminPeerId,
            to: _receiverPeerId,
            content: content,
            timestamp: timestamp.toUtc().toIso8601String(),
            isIncoming: true,
          );
        }

        Future<(StorePendingGroupInviteResult, PendingGroupInvite?)>
        storeInviteContent(String content, {required DateTime receivedAt}) {
          return storeIncomingPendingGroupInvite(
            message: inviteMessage(content, timestamp: receivedAt),
            groupRepo: receiverGroupRepo,
            pendingInviteRepo: receiverPendingInviteRepo,
            contactRepo: receiverContactRepo,
            bridge: receiverBridge,
            ownMlKemSecretKey: _receiverMlKemSecretKey,
            ownPeerId: _receiverPeerId,
            ownMlKemPublicKey: _receiverMlKemPublicKey,
            receivedAt: receivedAt,
          );
        }

        Future<void> expectNoReceiverState(String groupId) async {
          expect(
            await receiverPendingInviteRepo.getPendingInvite(groupId),
            isNull,
          );
          expect(await receiverGroupRepo.getGroup(groupId), isNull);
          expect(await receiverGroupRepo.getLatestKey(groupId), isNull);
          expect(await receiverGroupRepo.getMembers(groupId), isEmpty);
          expect(receiverBridge.commandLog, isNot(contains('group:join')));
          expect(receiverMsgRepo.count, 0);
        }

        Future<
          ({String content, String inviteId, Map<String, dynamic> groupConfig})
        >
        sendNetworkInvite(String groupId) async {
          final groupConfig = _makeGroupConfig();
          final sendResult = await sendGroupInvite(
            p2pService: adminP2P,
            bridge: adminBridge,
            groupRepo: await _repoFromConfig(groupConfig, groupId: groupId),
            recipientPeerId: _receiverPeerId,
            recipientMlKemPublicKey: _receiverMlKemPublicKey,
            senderPeerId: _adminPeerId,
            senderPublicKey: 'adminPubKey64',
            senderPrivateKey: 'adminPrivKey64',
            senderUsername: 'Admin',
            groupId: groupId,
            groupKey: _groupKey,
            keyEpoch: _keyEpoch,
            groupConfig: groupConfig,
          );
          expect(sendResult, SendGroupInviteResult.success);

          final content = adminP2P.lastSendMessageContent!;
          final envelope = jsonDecode(content) as Map<String, dynamic>;
          return (
            content: content,
            inviteId: envelope['id'] as String,
            groupConfig: groupConfig,
          );
        }

        String signedInviteContent({
          required String groupId,
          required String inviteId,
          required DateTime issuedAt,
          required DateTime policyExpiresAt,
        }) {
          final groupConfig = _makeGroupConfig();
          return GroupInvitePayload(
            id: inviteId,
            groupId: groupId,
            groupKey: _groupKey,
            keyEpoch: _keyEpoch,
            groupConfig: groupConfig,
            senderPeerId: _adminPeerId,
            senderUsername: 'Admin',
            timestamp: issuedAt.toUtc().toIso8601String(),
            recipientPeerId: _receiverPeerId,
            invitePolicy: _makeInvitePolicy(
              recipientPeerId: _receiverPeerId,
              expiresAt: policyExpiresAt,
            ),
            membershipFreshnessProof: _makeFreshnessProof(
              inviteId: inviteId,
              groupId: groupId,
              recipientPeerId: _receiverPeerId,
              groupConfig: groupConfig,
              keyEpoch: _keyEpoch,
              issuedAt: issuedAt,
              expiresAt: issuedAt.add(groupInviteMembershipFreshnessTtl),
            ),
          ).withInviteSignature(signature: 'signed-invite-by-admin').toJson();
        }

        final declineReceivedAt = DateTime.utc(2026, 4, 30, 13);
        const declineGroupId = 'grp-ml018-decline';
        final declineInvite = await sendNetworkInvite(declineGroupId);
        final (declineStoreResult, declinePending) = await storeInviteContent(
          declineInvite.content,
          receivedAt: declineReceivedAt,
        );
        expect(declineStoreResult, StorePendingGroupInviteResult.storedPending);
        expect(declinePending, isNotNull);

        final declineResult = await declinePendingGroupInvite(
          pendingInviteRepo: receiverPendingInviteRepo,
          groupId: declineGroupId,
          now: declineReceivedAt.add(const Duration(minutes: 1)),
        );
        expect(declineResult, DeclinePendingGroupInviteResult.success);
        expect(
          await receiverPendingInviteRepo.getConsumedInvite(
            declineInvite.inviteId,
          ),
          isNotNull,
        );

        final (
          delayedDeclineResult,
          delayedDeclinePending,
        ) = await storeInviteContent(
          declineInvite.content,
          receivedAt: declineReceivedAt.add(const Duration(minutes: 2)),
        );
        expect(delayedDeclineResult, StorePendingGroupInviteResult.alreadyUsed);
        expect(delayedDeclinePending, isNull);

        final (
          declinedAcceptResult,
          declinedGroup,
        ) = await acceptPendingGroupInvite(
          pendingInviteRepo: receiverPendingInviteRepo,
          groupRepo: receiverGroupRepo,
          contactRepo: receiverContactRepo,
          msgRepo: receiverMsgRepo,
          bridge: receiverBridge,
          groupId: declineGroupId,
        );
        expect(declinedAcceptResult, AcceptPendingGroupInviteResult.notFound);
        expect(declinedGroup, isNull);
        await expectNoReceiverState(declineGroupId);

        final expiryReceivedAt = DateTime.utc(2026, 4, 30, 14);
        const expiryGroupId = 'grp-ml018-expiry';
        final expiryContent = signedInviteContent(
          groupId: expiryGroupId,
          inviteId: 'invite-ml018-expiry',
          issuedAt: expiryReceivedAt,
          policyExpiresAt: expiryReceivedAt.add(const Duration(minutes: 1)),
        );
        final (expiryStoreResult, expiryPending) = await storeInviteContent(
          expiryContent,
          receivedAt: expiryReceivedAt,
        );
        expect(expiryStoreResult, StorePendingGroupInviteResult.storedPending);
        expect(expiryPending, isNotNull);

        final (
          expiryAcceptResult,
          expiryGroup,
        ) = await acceptPendingGroupInvite(
          pendingInviteRepo: receiverPendingInviteRepo,
          groupRepo: receiverGroupRepo,
          contactRepo: receiverContactRepo,
          msgRepo: receiverMsgRepo,
          bridge: receiverBridge,
          groupId: expiryGroupId,
          now: expiryReceivedAt.add(const Duration(minutes: 2)),
        );
        expect(expiryAcceptResult, AcceptPendingGroupInviteResult.expired);
        expect(expiryGroup, isNull);
        await expectNoReceiverState(expiryGroupId);

        final cancellationReceivedAt = DateTime.utc(2026, 4, 30, 15);
        const cancellationGroupId = 'grp-ml018-cancel';
        final cancellationInvite = await sendNetworkInvite(cancellationGroupId);
        final (
          cancellationStoreResult,
          cancellationPending,
        ) = await storeInviteContent(
          cancellationInvite.content,
          receivedAt: cancellationReceivedAt,
        );
        expect(
          cancellationStoreResult,
          StorePendingGroupInviteResult.storedPending,
        );
        expect(cancellationPending, isNotNull);

        final revokeResult = await sendGroupInviteRevocation(
          p2pService: adminP2P,
          bridge: adminBridge,
          inviteId: cancellationInvite.inviteId,
          groupId: cancellationGroupId,
          recipientPeerId: _receiverPeerId,
          recipientMlKemPublicKey: _receiverMlKemPublicKey,
          senderPeerId: _adminPeerId,
          senderPublicKey: 'adminPubKey64',
          senderPrivateKey: 'adminPrivKey64',
          groupConfig: cancellationInvite.groupConfig,
          now: cancellationReceivedAt.add(const Duration(minutes: 1)),
        );
        expect(revokeResult, SendGroupInviteRevocationResult.success);

        final (
          revocationHandleResult,
          removedPending,
        ) = await handleIncomingGroupInviteRevocation(
          message: inviteMessage(
            adminP2P.lastSendMessageContent!,
            timestamp: cancellationReceivedAt.add(const Duration(minutes: 1)),
          ),
          pendingInviteRepo: receiverPendingInviteRepo,
          contactRepo: receiverContactRepo,
          bridge: receiverBridge,
          ownMlKemSecretKey: _receiverMlKemSecretKey,
          ownPeerId: _receiverPeerId,
          now: cancellationReceivedAt.add(const Duration(minutes: 1)),
        );
        expect(
          revocationHandleResult,
          HandleGroupInviteRevocationResult.revoked,
        );
        expect(removedPending, isNotNull);
        expect(
          await receiverPendingInviteRepo.getRevokedInvite(
            cancellationInvite.inviteId,
          ),
          isNotNull,
        );

        final (
          delayedCancellationResult,
          delayedCancellationPending,
        ) = await storeInviteContent(
          cancellationInvite.content,
          receivedAt: cancellationReceivedAt.add(const Duration(minutes: 2)),
        );
        expect(
          delayedCancellationResult,
          StorePendingGroupInviteResult.revoked,
        );
        expect(delayedCancellationPending, isNull);

        final (
          cancelAcceptResult,
          cancelGroup,
        ) = await acceptPendingGroupInvite(
          pendingInviteRepo: receiverPendingInviteRepo,
          groupRepo: receiverGroupRepo,
          contactRepo: receiverContactRepo,
          msgRepo: receiverMsgRepo,
          bridge: receiverBridge,
          groupId: cancellationGroupId,
        );
        expect(cancelAcceptResult, AcceptPendingGroupInviteResult.notFound);
        expect(cancelGroup, isNull);
        await expectNoReceiverState(cancellationGroupId);
      },
    );

    test(
      'ML-019 KE-016 stale invite cannot replace latest re-add package before accept',
      () async {
        const groupId = 'grp-ml019-stale-invite';
        final receiverBridge = PassthroughCryptoBridge();
        final receiverGroupRepo = InMemoryGroupRepository();
        final receiverPendingInviteRepo =
            InMemoryPendingGroupInviteRepository();
        final receiverMsgRepo = InMemoryGroupMessageRepository();
        final receiverContactRepo = FakeContactRepository()
          ..seed([_adminContact()]);

        ChatMessage inviteMessage(
          String content, {
          required DateTime timestamp,
        }) {
          return ChatMessage(
            from: _adminPeerId,
            to: _receiverPeerId,
            content: content,
            timestamp: timestamp.toUtc().toIso8601String(),
            isIncoming: true,
          );
        }

        String signedInviteContent({
          required String inviteId,
          required String groupKey,
          required int keyEpoch,
          required Map<String, dynamic> groupConfig,
          required DateTime issuedAt,
        }) {
          return GroupInvitePayload(
            id: inviteId,
            groupId: groupId,
            groupKey: groupKey,
            keyEpoch: keyEpoch,
            groupConfig: groupConfig,
            senderPeerId: _adminPeerId,
            senderUsername: 'Admin',
            timestamp: issuedAt.toUtc().toIso8601String(),
            recipientPeerId: _receiverPeerId,
            invitePolicy: _makeInvitePolicy(
              recipientPeerId: _receiverPeerId,
              keyEpoch: keyEpoch,
              expiresAt: issuedAt.add(pendingGroupInviteTtl),
            ),
            membershipFreshnessProof: _makeFreshnessProof(
              inviteId: inviteId,
              groupId: groupId,
              recipientPeerId: _receiverPeerId,
              groupConfig: groupConfig,
              keyEpoch: keyEpoch,
              issuedAt: issuedAt,
              expiresAt: issuedAt.add(groupInviteMembershipFreshnessTtl),
            ),
          ).withInviteSignature(signature: 'signed-invite-by-admin').toJson();
        }

        final oldIssuedAt = DateTime.utc(2026, 5, 1, 12);
        final newIssuedAt = oldIssuedAt.add(const Duration(minutes: 10));
        final oldConfig = {
          ..._makeGroupConfig(),
          'metadataUpdatedAt': oldIssuedAt.toIso8601String(),
        };
        final newConfig = {
          ..._makeGroupConfig(),
          'metadataUpdatedAt': newIssuedAt.toIso8601String(),
        };
        final oldContent = signedInviteContent(
          inviteId: 'invite-ml019-old',
          groupKey: 'old-key',
          keyEpoch: 1,
          groupConfig: oldConfig,
          issuedAt: oldIssuedAt,
        );
        final newContent = signedInviteContent(
          inviteId: 'invite-ml019-new',
          groupKey: 'fresh-key',
          keyEpoch: 2,
          groupConfig: newConfig,
          issuedAt: newIssuedAt,
        );

        final (
          newStoreResult,
          newPending,
        ) = await storeIncomingPendingGroupInvite(
          message: inviteMessage(newContent, timestamp: newIssuedAt),
          groupRepo: receiverGroupRepo,
          pendingInviteRepo: receiverPendingInviteRepo,
          contactRepo: receiverContactRepo,
          bridge: receiverBridge,
          ownPeerId: _receiverPeerId,
          ownMlKemPublicKey: _receiverMlKemPublicKey,
          receivedAt: newIssuedAt,
        );
        expect(newStoreResult, StorePendingGroupInviteResult.storedPending);
        expect(newPending, isNotNull);

        final (
          oldStoreResult,
          oldPending,
        ) = await storeIncomingPendingGroupInvite(
          message: inviteMessage(
            oldContent,
            timestamp: newIssuedAt.add(const Duration(minutes: 1)),
          ),
          groupRepo: receiverGroupRepo,
          pendingInviteRepo: receiverPendingInviteRepo,
          contactRepo: receiverContactRepo,
          bridge: receiverBridge,
          ownPeerId: _receiverPeerId,
          ownMlKemPublicKey: _receiverMlKemPublicKey,
          receivedAt: newIssuedAt.add(const Duration(minutes: 1)),
        );
        expect(oldStoreResult, StorePendingGroupInviteResult.invalidPayload);
        expect(oldPending, isNull);
        final pending = await receiverPendingInviteRepo.getPendingInvite(
          groupId,
        );
        expect(pending, isNotNull);
        expect(pending!.inviteId, 'invite-ml019-new');

        final (acceptResult, acceptedGroup) = await acceptPendingGroupInvite(
          pendingInviteRepo: receiverPendingInviteRepo,
          groupRepo: receiverGroupRepo,
          contactRepo: receiverContactRepo,
          msgRepo: receiverMsgRepo,
          bridge: receiverBridge,
          groupId: groupId,
          senderPeerId: _receiverPeerId,
          now: newIssuedAt.add(const Duration(minutes: 2)),
        );
        expect(acceptResult, AcceptPendingGroupInviteResult.success);
        expect(acceptedGroup, isNotNull);
        expect(
          await receiverPendingInviteRepo.getPendingInvite(groupId),
          isNull,
        );
        final latestKey = await receiverGroupRepo.getLatestKey(groupId);
        expect(latestKey, isNotNull);
        expect(latestKey!.keyGeneration, 2);
        expect(latestKey.encryptedKey, 'fresh-key');
        final selfMember = await receiverGroupRepo.getMember(
          groupId,
          _receiverPeerId,
        );
        expect(selfMember, isNotNull);
        final joinPayload =
            (jsonDecode(
                      receiverBridge.sentMessages.firstWhere(
                        (message) =>
                            (jsonDecode(message)
                                as Map<String, dynamic>)['cmd'] ==
                            'group:join',
                      ),
                    )
                    as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        expect(joinPayload['keyEpoch'], 2);
        expect(joinPayload['groupKey'], 'fresh-key');
      },
    );

    test(
      'RA-004 IJ003 revoked old invite stays rejected before current re-add succeeds',
      () async {
        final groupInviteStreamController =
            StreamController<ChatMessage>.broadcast();

        final receiverBridge = PassthroughCryptoBridge();
        final receiverGroupRepo = InMemoryGroupRepository();
        final receiverPendingInviteRepo =
            InMemoryPendingGroupInviteRepository();
        final receiverMsgRepo = InMemoryGroupMessageRepository();
        final receiverContactRepo = FakeContactRepository()
          ..seed([_adminContact()]);

        final listener = GroupInviteListener(
          groupInviteStream: groupInviteStreamController.stream,
          groupRepo: receiverGroupRepo,
          contactRepo: receiverContactRepo,
          pendingInviteRepo: receiverPendingInviteRepo,
          bridge: receiverBridge,
          msgRepo: receiverMsgRepo,
          getOwnMlKemSecretKey: () async => _receiverMlKemSecretKey,
          getOwnPeerId: () async => _receiverPeerId,
          now: () => DateTime.utc(2026, 4, 30, 12, 10),
        );
        addTearDown(listener.dispose);
        addTearDown(groupInviteStreamController.close);

        listener.start();

        final adminBridge = PassthroughCryptoBridge();
        final adminP2P = FakeP2PService(
          initialState: const NodeState(isStarted: true),
        );
        addTearDown(adminP2P.dispose);
        final groupConfig = _makeGroupConfig();

        final sendResult = await sendGroupInvite(
          p2pService: adminP2P,
          bridge: adminBridge,
          groupRepo: await _repoFromConfig(groupConfig),
          recipientPeerId: _receiverPeerId,
          recipientMlKemPublicKey: _receiverMlKemPublicKey,
          senderPeerId: _adminPeerId,
          senderPublicKey: 'adminPubKey64',
          senderPrivateKey: 'adminPrivKey64',
          senderUsername: 'Admin',
          groupId: _groupId,
          groupKey: _groupKey,
          keyEpoch: _keyEpoch,
          groupConfig: groupConfig,
        );
        expect(sendResult, SendGroupInviteResult.success);

        final inviteContent = adminP2P.lastSendMessageContent!;
        final inviteEnvelope =
            jsonDecode(inviteContent) as Map<String, dynamic>;
        final inviteId = inviteEnvelope['id'] as String;

        final pendingInviteFuture = listener.pendingInviteStream.first;
        groupInviteStreamController.add(
          ChatMessage(
            from: _adminPeerId,
            to: _receiverPeerId,
            content: inviteContent,
            timestamp: DateTime.utc(2026, 4, 30, 12).toIso8601String(),
            isIncoming: true,
          ),
        );
        final pendingInvite = await pendingInviteFuture.timeout(
          const Duration(seconds: 5),
        );
        expect(pendingInvite.inviteId, inviteId);
        expect(
          await receiverPendingInviteRepo.getPendingInvite(_groupId),
          isNotNull,
        );

        final revokeResult = await sendGroupInviteRevocation(
          p2pService: adminP2P,
          bridge: adminBridge,
          inviteId: inviteId,
          groupId: _groupId,
          recipientPeerId: _receiverPeerId,
          recipientMlKemPublicKey: _receiverMlKemPublicKey,
          senderPeerId: _adminPeerId,
          senderPublicKey: 'adminPubKey64',
          senderPrivateKey: 'adminPrivKey64',
          groupConfig: groupConfig,
          now: DateTime.utc(2026, 4, 30, 12, 5),
        );
        expect(revokeResult, SendGroupInviteRevocationResult.success);

        final revocationContent = adminP2P.lastSendMessageContent!;
        final refreshFuture = listener.pendingInviteStream.firstWhere(
          (invite) => invite.inviteId == inviteId,
        );
        groupInviteStreamController.add(
          ChatMessage(
            from: _adminPeerId,
            to: _receiverPeerId,
            content: revocationContent,
            timestamp: DateTime.utc(2026, 4, 30, 12, 5).toIso8601String(),
            isIncoming: true,
          ),
        );
        await refreshFuture.timeout(const Duration(seconds: 5));

        expect(
          await receiverPendingInviteRepo.getPendingInvite(_groupId),
          isNull,
        );
        expect(
          await receiverPendingInviteRepo.getRevokedInvite(inviteId),
          isNotNull,
        );
        expect(await receiverGroupRepo.getGroup(_groupId), isNull);
        expect(await receiverGroupRepo.getLatestKey(_groupId), isNull);

        groupInviteStreamController.add(
          ChatMessage(
            from: _adminPeerId,
            to: _receiverPeerId,
            content: inviteContent,
            timestamp: DateTime.utc(2026, 4, 30, 12, 10).toIso8601String(),
            isIncoming: true,
          ),
        );
        groupInviteStreamController.add(
          ChatMessage(
            from: _adminPeerId,
            to: _receiverPeerId,
            content: inviteContent,
            timestamp: DateTime.utc(2026, 4, 30, 12, 15).toIso8601String(),
            isIncoming: true,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(
          await receiverPendingInviteRepo.getPendingInvite(_groupId),
          isNull,
        );
        expect(await receiverGroupRepo.getGroup(_groupId), isNull);
        expect(await receiverGroupRepo.getLatestKey(_groupId), isNull);

        final (acceptResult, acceptedGroup) = await acceptPendingGroupInvite(
          pendingInviteRepo: receiverPendingInviteRepo,
          groupRepo: receiverGroupRepo,
          contactRepo: receiverContactRepo,
          msgRepo: receiverMsgRepo,
          bridge: receiverBridge,
          groupId: _groupId,
        );

        expect(acceptResult, AcceptPendingGroupInviteResult.notFound);
        expect(acceptedGroup, isNull);
        expect(
          await receiverPendingInviteRepo.getConsumedInvite(inviteId),
          isNull,
        );
        expect(await receiverGroupRepo.getGroup(_groupId), isNull);
        expect(await receiverGroupRepo.getLatestKey(_groupId), isNull);
        expect(receiverBridge.commandLog, isNot(contains('group:join')));
        expect(receiverMsgRepo.count, 0);

        final currentSendResult = await sendGroupInvite(
          p2pService: adminP2P,
          bridge: adminBridge,
          groupRepo: await _repoFromConfig(groupConfig),
          recipientPeerId: _receiverPeerId,
          recipientMlKemPublicKey: _receiverMlKemPublicKey,
          senderPeerId: _adminPeerId,
          senderPublicKey: 'adminPubKey64',
          senderPrivateKey: 'adminPrivKey64',
          senderUsername: 'Admin',
          groupId: _groupId,
          groupKey: 'current-readd-key',
          keyEpoch: 2,
          groupConfig: groupConfig,
        );
        expect(currentSendResult, SendGroupInviteResult.success);

        final currentInviteContent = adminP2P.lastSendMessageContent!;
        final currentInviteEnvelope =
            jsonDecode(currentInviteContent) as Map<String, dynamic>;
        final currentInviteId = currentInviteEnvelope['id'] as String;
        final currentPendingFuture = listener.pendingInviteStream.firstWhere(
          (invite) => invite.inviteId == currentInviteId,
        );
        groupInviteStreamController.add(
          ChatMessage(
            from: _adminPeerId,
            to: _receiverPeerId,
            content: currentInviteContent,
            timestamp: DateTime.utc(2026, 4, 30, 12, 20).toIso8601String(),
            isIncoming: true,
          ),
        );
        final currentPending = await currentPendingFuture.timeout(
          const Duration(seconds: 5),
        );
        expect(currentPending.toPayload()!.keyEpoch, 2);

        final (
          currentAcceptResult,
          currentAcceptedGroup,
        ) = await acceptPendingGroupInvite(
          pendingInviteRepo: receiverPendingInviteRepo,
          groupRepo: receiverGroupRepo,
          contactRepo: receiverContactRepo,
          msgRepo: receiverMsgRepo,
          bridge: receiverBridge,
          groupId: _groupId,
          senderPeerId: _receiverPeerId,
          now: DateTime.utc(2026, 4, 30, 12, 21),
        );

        expect(currentAcceptResult, AcceptPendingGroupInviteResult.success);
        expect(currentAcceptedGroup, isNotNull);
        expect(
          await receiverPendingInviteRepo.getPendingInvite(_groupId),
          isNull,
        );
        final currentKey = await receiverGroupRepo.getLatestKey(_groupId);
        expect(currentKey, isNotNull);
        expect(currentKey!.keyGeneration, 2);
        expect(currentKey.encryptedKey, 'current-readd-key');
        expect(
          receiverBridge.commandLog.where((cmd) => cmd == 'group:join'),
          hasLength(1),
        );
      },
    );

    test(
      'PREREQ-INVITER-FRESHNESS offline invite after inviter removal is rejected',
      () async {
        final adminBridge = PassthroughCryptoBridge();
        final adminP2P = FakeP2PService(
          initialState: const NodeState(isStarted: true),
        );
        addTearDown(adminP2P.dispose);
        final groupConfig = _makeGroupConfig();
        final adminGroupRepo = await _repoFromConfig(groupConfig);

        final sendResult = await sendGroupInvite(
          p2pService: adminP2P,
          bridge: adminBridge,
          groupRepo: adminGroupRepo,
          recipientPeerId: _receiverPeerId,
          recipientMlKemPublicKey: _receiverMlKemPublicKey,
          senderPeerId: _adminPeerId,
          senderPublicKey: 'adminPubKey64',
          senderPrivateKey: 'adminPrivKey64',
          senderUsername: 'Admin',
          groupId: _groupId,
          groupKey: _groupKey,
          keyEpoch: _keyEpoch,
          groupConfig: groupConfig,
        );
        expect(sendResult, SendGroupInviteResult.success);

        await adminGroupRepo.removeMember(_groupId, _adminPeerId);

        final replayedEnvelope = GroupInvitePayload.parseEncryptedEnvelope(
          adminP2P.lastSendMessageContent!,
        )!;
        final replayedEncrypted =
            replayedEnvelope['encrypted'] as Map<String, dynamic>;
        final replayedInner =
            jsonDecode(replayedEncrypted['ciphertext'] as String)
                as Map<String, dynamic>;
        final originalInviteTimestamp = DateTime.parse(
          replayedInner['timestamp'] as String,
        ).toUtc();
        final replayedAfterFreshnessWindow = originalInviteTimestamp
            .add(groupInviteMembershipFreshnessTtl)
            .add(const Duration(seconds: 1));
        final receiverGroupRepo = InMemoryGroupRepository();
        final receiverPendingRepo = InMemoryPendingGroupInviteRepository();
        final receiverMsgRepo = InMemoryGroupMessageRepository();
        final receiverContactRepo = FakeContactRepository()
          ..seed([_adminContact()]);
        final stream = StreamController<ChatMessage>.broadcast();
        final receiverBridge = PassthroughCryptoBridge();
        final listener = GroupInviteListener(
          groupInviteStream: stream.stream,
          groupRepo: receiverGroupRepo,
          pendingInviteRepo: receiverPendingRepo,
          contactRepo: receiverContactRepo,
          bridge: receiverBridge,
          msgRepo: receiverMsgRepo,
          getOwnMlKemSecretKey: () async => _receiverMlKemSecretKey,
          getOwnPeerId: () async => _receiverPeerId,
          now: () => replayedAfterFreshnessWindow,
        );
        final pendingInvites = <PendingGroupInvite>[];
        listener.pendingInviteStream.listen(pendingInvites.add);
        listener.start();
        addTearDown(() async {
          listener.dispose();
          await stream.close();
        });

        stream.add(
          ChatMessage(
            from: _adminPeerId,
            to: _receiverPeerId,
            content: adminP2P.lastSendMessageContent!,
            timestamp: originalInviteTimestamp.toIso8601String(),
            isIncoming: true,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 100));

        expect(pendingInvites, isEmpty);
        expect(receiverPendingRepo.count, 0);
        expect(await receiverPendingRepo.getPendingInvite(_groupId), isNull);
        expect(await receiverGroupRepo.getGroup(_groupId), isNull);
        expect(await receiverGroupRepo.getLatestKey(_groupId), isNull);
        expect(receiverBridge.commandLog, isNot(contains('group:join')));
        expect(receiverMsgRepo.count, 0);
      },
    );

    test(
      'accept publishes a durable join event that existing members can render',
      () async {
        final receiverBridge = PassthroughCryptoBridge();
        final receiverGroupRepo = InMemoryGroupRepository();
        final receiverPendingInviteRepo =
            InMemoryPendingGroupInviteRepository();
        final receiverMsgRepo = InMemoryGroupMessageRepository();
        final receiverContactRepo = FakeContactRepository()
          ..seed([_adminContact()]);

        await receiverPendingInviteRepo.savePendingInvite(
          PendingGroupInvite.fromPayload(
            GroupInvitePayload(
              id: 'invite-join-event',
              groupId: _groupId,
              groupKey: _groupKey,
              keyEpoch: _keyEpoch,
              groupConfig: _makeGroupConfig(),
              senderPeerId: _adminPeerId,
              senderUsername: 'Admin',
              timestamp: DateTime.now().toUtc().toIso8601String(),
              recipientPeerId: _receiverPeerId,
              invitePolicy: _makeInvitePolicy(recipientPeerId: _receiverPeerId),
              membershipFreshnessProof: _makeFreshnessProof(
                inviteId: 'invite-join-event',
                groupId: _groupId,
                recipientPeerId: _receiverPeerId,
                groupConfig: _makeGroupConfig(),
                keyEpoch: _keyEpoch,
                issuedAt: DateTime.now().toUtc(),
              ),
            ).withInviteSignature(signature: 'signed-invite-by-admin'),
            receivedAt: DateTime.now().toUtc(),
          ),
        );

        final adminGroupRepo = InMemoryGroupRepository();
        final adminMsgRepo = InMemoryGroupMessageRepository();
        final adminGroup = GroupModel(
          id: _groupId,
          name: 'Test Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/$_groupId',
          description: 'Integration test group',
          createdAt: DateTime.utc(2026, 3, 2),
          createdBy: _adminPeerId,
          myRole: GroupRole.admin,
        );
        await adminGroupRepo.saveGroup(adminGroup);
        await adminGroupRepo.saveMember(
          GroupMember(
            groupId: _groupId,
            peerId: _adminPeerId,
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'adminPubKey64',
            mlKemPublicKey: _adminMlKemPublicKey,
            joinedAt: DateTime.utc(2026, 3, 2),
          ),
        );
        await adminGroupRepo.saveMember(
          GroupMember(
            groupId: _groupId,
            peerId: _receiverPeerId,
            username: 'Receiver',
            role: MemberRole.writer,
            publicKey: 'receiverPubKey64',
            mlKemPublicKey: _receiverMlKemPublicKey,
            joinedAt: DateTime.utc(2026, 3, 2, 0, 1),
          ),
        );

        final adminListenerStream = StreamController<Map<String, dynamic>>();
        final adminListener = GroupMessageListener(
          groupRepo: adminGroupRepo,
          msgRepo: adminMsgRepo,
          bridge: FakeBridge(),
          getSelfPeerId: () async => _adminPeerId,
        );
        adminListener.start(adminListenerStream.stream);

        final (acceptResult, _) = await acceptPendingGroupInvite(
          pendingInviteRepo: receiverPendingInviteRepo,
          groupRepo: receiverGroupRepo,
          contactRepo: receiverContactRepo,
          msgRepo: receiverMsgRepo,
          bridge: receiverBridge,
          groupId: _groupId,
          senderPeerId: _receiverPeerId,
          senderPublicKey: 'receiverPubKey64',
          senderPrivateKey: 'receiverPrivKey64',
          senderUsername: 'Receiver',
        );

        expect(acceptResult, AcceptPendingGroupInviteResult.success);
        expect(receiverBridge.commandLog, contains('group:publish'));

        final publishMessage = receiverBridge.sentMessages.firstWhere((
          message,
        ) {
          final parsed = jsonDecode(message) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:publish';
        });
        final publishPayload =
            (jsonDecode(publishMessage) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final sysText = publishPayload['text'] as String;

        adminListenerStream.add({
          'groupId': _groupId,
          'senderId': _receiverPeerId,
          'senderUsername': 'Receiver',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future<void>.delayed(const Duration(milliseconds: 50));

        final latestMessage = await adminMsgRepo.getLatestMessage(_groupId);
        expect(latestMessage, isNotNull);
        expect(latestMessage!.text, 'Receiver joined the group');

        await adminListenerStream.close();
        adminListener.dispose();
      },
    );

    test(
      'bridgeError accept later rejoin and drain converge without the pending invite row',
      () async {
        final receiverBridge = FakeBridge();
        final receiverGroupRepo = InMemoryGroupRepository();
        final receiverPendingInviteRepo =
            InMemoryPendingGroupInviteRepository();
        final receiverMsgRepo = InMemoryGroupMessageRepository();
        final receiverContactRepo = FakeContactRepository()
          ..seed([_adminContact()]);
        final adminGroupRepo = InMemoryGroupRepository();
        final adminMsgRepo = InMemoryGroupMessageRepository();
        final adminGroup = GroupModel(
          id: _groupId,
          name: 'Test Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/$_groupId',
          description: 'Integration test group',
          createdAt: DateTime.utc(2026, 3, 2),
          createdBy: _adminPeerId,
          myRole: GroupRole.admin,
        );
        await adminGroupRepo.saveGroup(adminGroup);
        await adminGroupRepo.saveMember(
          GroupMember(
            groupId: _groupId,
            peerId: _adminPeerId,
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'adminPubKey64',
            mlKemPublicKey: _adminMlKemPublicKey,
            joinedAt: DateTime.utc(2026, 3, 2),
          ),
        );
        await adminGroupRepo.saveMember(
          GroupMember(
            groupId: _groupId,
            peerId: _receiverPeerId,
            username: 'Receiver',
            role: MemberRole.writer,
            publicKey: 'receiverPubKey64',
            mlKemPublicKey: _receiverMlKemPublicKey,
            joinedAt: DateTime.utc(2026, 3, 2, 0, 1),
          ),
        );
        final adminListenerStream = StreamController<Map<String, dynamic>>();
        final adminListener = GroupMessageListener(
          groupRepo: adminGroupRepo,
          msgRepo: adminMsgRepo,
          bridge: FakeBridge(),
          getSelfPeerId: () async => _adminPeerId,
        );
        adminListener.start(adminListenerStream.stream);
        addTearDown(() async {
          await adminListenerStream.close();
          adminListener.dispose();
        });
        final replayListener = GroupMessageListener(
          groupRepo: receiverGroupRepo,
          msgRepo: receiverMsgRepo,
          bridge: receiverBridge,
          getSelfPeerId: () async => _receiverPeerId,
        );
        addTearDown(replayListener.dispose);

        await receiverPendingInviteRepo.savePendingInvite(
          PendingGroupInvite.fromPayload(
            GroupInvitePayload(
              id: 'invite-bridge-error',
              groupId: _groupId,
              groupKey: _groupKey,
              keyEpoch: _keyEpoch,
              groupConfig: _makeGroupConfig(),
              senderPeerId: _adminPeerId,
              senderUsername: 'Admin',
              timestamp: DateTime.now().toUtc().toIso8601String(),
              recipientPeerId: _receiverPeerId,
              invitePolicy: _makeInvitePolicy(recipientPeerId: _receiverPeerId),
              membershipFreshnessProof: _makeFreshnessProof(
                inviteId: 'invite-bridge-error',
                groupId: _groupId,
                recipientPeerId: _receiverPeerId,
                groupConfig: _makeGroupConfig(),
                keyEpoch: _keyEpoch,
                issuedAt: DateTime.now().toUtc(),
              ),
            ).withInviteSignature(signature: 'signed-invite-by-admin'),
            receivedAt: DateTime.now().toUtc(),
          ),
        );

        receiverBridge.responses['group:join'] = {
          'ok': false,
          'errorCode': 'JOIN_FAILED',
        };

        final (acceptResult, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: receiverPendingInviteRepo,
          groupRepo: receiverGroupRepo,
          contactRepo: receiverContactRepo,
          msgRepo: receiverMsgRepo,
          bridge: receiverBridge,
          groupId: _groupId,
          senderPeerId: _receiverPeerId,
          senderPublicKey: 'receiverPubKey64',
          senderPrivateKey: 'receiverPrivKey64',
          senderUsername: 'Receiver',
        );

        expect(acceptResult, AcceptPendingGroupInviteResult.bridgeError);
        expect(group, isNotNull);
        expect(
          await receiverPendingInviteRepo.getPendingInvite(_groupId),
          isNull,
        );
        expect(await receiverGroupRepo.getGroup(_groupId), isNotNull);
        expect(receiverBridge.commandLog, contains('group:publish'));
        expect(receiverBridge.commandLog, contains('group:inboxStore'));

        final publishMessage = receiverBridge.sentMessages.firstWhere((
          message,
        ) {
          final parsed = jsonDecode(message) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:publish';
        });
        final publishPayload =
            (jsonDecode(publishMessage) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final sysText = publishPayload['text'] as String;

        adminListenerStream.add({
          'groupId': _groupId,
          'senderId': _receiverPeerId,
          'senderUsername': 'Receiver',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future<void>.delayed(const Duration(milliseconds: 50));

        final adminLatestMessage = await adminMsgRepo.getLatestMessage(
          _groupId,
        );
        expect(adminLatestMessage, isNotNull);
        expect(adminLatestMessage!.text, 'Receiver joined the group');

        final receiverHistoryAfterAccept = await receiverMsgRepo
            .getMessagesPage(_groupId, limit: 10);
        expect(
          receiverHistoryAfterAccept.where(
            (message) => message.text == 'Receiver joined the group',
          ),
          hasLength(1),
        );

        final replayTimestamp = DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 2))
            .toIso8601String();
        final replayEnvelope = await buildGroupOfflineReplayEnvelope(
          bridge: receiverBridge,
          groupRepo: receiverGroupRepo,
          groupId: _groupId,
          payloadType: groupOfflineReplayPayloadTypeMessage,
          plaintext: jsonEncode({
            'groupId': _groupId,
            'messageId': 'bridge-error-recovered-msg',
            'senderId': _adminPeerId,
            'senderUsername': 'Admin',
            'keyEpoch': _keyEpoch,
            'text': 'Recovered after bridge error',
            'timestamp': replayTimestamp,
          }),
          messageId: 'bridge-error-recovered-msg',
          senderPeerId: _adminPeerId,
          senderPublicKey: 'adminPubKey64',
          senderPrivateKey: 'adminPrivKey64',
        );
        receiverBridge.responses['group:join'] = {'ok': true};
        receiverBridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': [
            {'from': _adminPeerId, 'message': replayEnvelope},
          ],
          'cursor': '',
        };

        final rejoinResult = await rejoinGroupTopics(
          bridge: receiverBridge,
          groupRepo: receiverGroupRepo,
          reason: RejoinReason.inPlaceRecovery,
        );
        expect(rejoinResult.joinedGroupCount, 1);
        expect(rejoinResult.errorCount, 0);

        await drainGroupOfflineInboxForGroup(
          bridge: receiverBridge,
          groupRepo: receiverGroupRepo,
          msgRepo: receiverMsgRepo,
          groupId: _groupId,
          groupMessageListener: replayListener,
        );

        final recoveredMessage = await receiverMsgRepo.getMessage(
          'bridge-error-recovered-msg',
        );
        expect(recoveredMessage, isNotNull);
        expect(recoveredMessage!.text, 'Recovered after bridge error');
        expect(
          await receiverPendingInviteRepo.getPendingInvite(_groupId),
          isNull,
        );

        final receiverHistoryAfterRecovery = await receiverMsgRepo
            .getMessagesPage(_groupId, limit: 20);
        expect(
          receiverHistoryAfterRecovery.where(
            (message) => message.text == 'Receiver joined the group',
          ),
          hasLength(1),
        );

        final joinCommands = receiverBridge.sentMessages
            .map((message) => jsonDecode(message) as Map<String, dynamic>)
            .where((message) => message['cmd'] == 'group:join')
            .toList();
        expect(joinCommands, hasLength(2));
      },
    );

    test(
      'concurrent pending accepts converge members, key epoch, and sendability',
      () async {
        const charliePeerId = '12D3KooWCharliePeerId';
        const davePeerId = '12D3KooWDavePeerId';
        const groupId = 'grp-concurrent-joins';
        const groupKey = 'base64ConcurrentJoinKey==';
        const keyEpoch = 3;
        final receivedAt = DateTime.utc(2026, 4, 29, 12);
        final groupConfig = {
          'name': 'Concurrent Joins',
          'groupType': 'chat',
          'description': 'Concurrent invite accept proof',
          'members': [
            {
              'peerId': _adminPeerId,
              'username': 'Admin',
              'role': 'admin',
              'publicKey': 'adminPubKey64',
              'mlKemPublicKey': _adminMlKemPublicKey,
            },
            {
              'peerId': charliePeerId,
              'username': 'Charlie',
              'role': 'writer',
              'publicKey': 'charliePubKey64',
              'mlKemPublicKey': 'charlieMlKemPub64',
            },
            {
              'peerId': davePeerId,
              'username': 'Dave',
              'role': 'writer',
              'publicKey': 'davePubKey64',
              'mlKemPublicKey': 'daveMlKemPub64',
            },
          ],
          'createdBy': _adminPeerId,
          'createdAt': receivedAt
              .subtract(const Duration(days: 1))
              .toIso8601String(),
        };

        PendingGroupInvite makePendingInvite({required String inviteId}) {
          return PendingGroupInvite.fromPayload(
            GroupInvitePayload(
              id: inviteId,
              groupId: groupId,
              groupKey: groupKey,
              keyEpoch: keyEpoch,
              groupConfig: groupConfig,
              senderPeerId: _adminPeerId,
              senderUsername: 'Admin',
              timestamp: receivedAt.toIso8601String(),
              recipientPeerId: inviteId == 'invite-charlie'
                  ? charliePeerId
                  : davePeerId,
              invitePolicy: _makeInvitePolicy(
                recipientPeerId: inviteId == 'invite-charlie'
                    ? charliePeerId
                    : davePeerId,
                expiresAt: receivedAt.add(pendingGroupInviteTtl),
                keyEpoch: keyEpoch,
              ),
              membershipFreshnessProof: _makeFreshnessProof(
                inviteId: inviteId,
                groupId: groupId,
                recipientPeerId: inviteId == 'invite-charlie'
                    ? charliePeerId
                    : davePeerId,
                groupConfig: groupConfig,
                keyEpoch: keyEpoch,
                issuedAt: receivedAt,
              ),
            ).withInviteSignature(signature: 'signed-invite-by-admin'),
            receivedAt: receivedAt,
          );
        }

        final charliePendingRepo = InMemoryPendingGroupInviteRepository();
        final davePendingRepo = InMemoryPendingGroupInviteRepository();
        final charlieGroupRepo = InMemoryGroupRepository();
        final daveGroupRepo = InMemoryGroupRepository();
        final charlieMsgRepo = InMemoryGroupMessageRepository();
        final daveMsgRepo = InMemoryGroupMessageRepository();
        final charlieContactRepo = FakeContactRepository()
          ..seed([_adminContact()]);
        final daveContactRepo = FakeContactRepository()
          ..seed([_adminContact()]);
        final charlieBridge = FakeBridge();
        final daveBridge = FakeBridge();

        await charliePendingRepo.savePendingInvite(
          makePendingInvite(inviteId: 'invite-charlie'),
        );
        await davePendingRepo.savePendingInvite(
          makePendingInvite(inviteId: 'invite-dave'),
        );

        final acceptResults = await Future.wait([
          acceptPendingGroupInvite(
            pendingInviteRepo: charliePendingRepo,
            groupRepo: charlieGroupRepo,
            contactRepo: charlieContactRepo,
            msgRepo: charlieMsgRepo,
            bridge: charlieBridge,
            groupId: groupId,
            senderPeerId: charliePeerId,
            senderPublicKey: 'charliePubKey64',
            senderPrivateKey: 'charliePrivKey64',
            senderUsername: 'Charlie',
            now: receivedAt.add(const Duration(minutes: 1)),
          ),
          acceptPendingGroupInvite(
            pendingInviteRepo: davePendingRepo,
            groupRepo: daveGroupRepo,
            contactRepo: daveContactRepo,
            msgRepo: daveMsgRepo,
            bridge: daveBridge,
            groupId: groupId,
            senderPeerId: davePeerId,
            senderPublicKey: 'davePubKey64',
            senderPrivateKey: 'davePrivKey64',
            senderUsername: 'Dave',
            now: receivedAt.add(const Duration(minutes: 1)),
          ),
        ]);

        expect(acceptResults[0].$1, AcceptPendingGroupInviteResult.success);
        expect(acceptResults[1].$1, AcceptPendingGroupInviteResult.success);

        Future<void> expectConvergedReceiver({
          required InMemoryGroupRepository repo,
          required String receiverPeerId,
        }) async {
          final group = await repo.getGroup(groupId);
          expect(group, isNotNull);
          expect(group!.myRole, GroupRole.member);

          final members = await repo.getMembers(groupId);
          expect(members.map((member) => member.peerId).toSet(), {
            _adminPeerId,
            charliePeerId,
            davePeerId,
          });
          expect(
            members.where((member) => member.peerId == receiverPeerId),
            hasLength(1),
          );
          expect(
            members.firstWhere((member) => member.peerId == _adminPeerId).role,
            MemberRole.admin,
          );
          expect(
            members.firstWhere((member) => member.peerId == charliePeerId).role,
            MemberRole.writer,
          );
          expect(
            members.firstWhere((member) => member.peerId == davePeerId).role,
            MemberRole.writer,
          );

          final latestKey = await repo.getLatestKey(groupId);
          expect(latestKey, isNotNull);
          expect(latestKey!.keyGeneration, keyEpoch);
          expect(latestKey.encryptedKey, groupKey);
        }

        await expectConvergedReceiver(
          repo: charlieGroupRepo,
          receiverPeerId: charliePeerId,
        );
        await expectConvergedReceiver(
          repo: daveGroupRepo,
          receiverPeerId: davePeerId,
        );

        final (charlieSendResult, charlieMessage) = await group_send
            .sendGroupMessage(
              bridge: charlieBridge,
              groupRepo: charlieGroupRepo,
              msgRepo: charlieMsgRepo,
              groupId: groupId,
              text: 'Charlie can send after convergence',
              senderPeerId: charliePeerId,
              senderPublicKey: 'charliePubKey64',
              senderPrivateKey: 'charliePrivKey64',
              senderUsername: 'Charlie',
            );
        final (daveSendResult, daveMessage) = await group_send.sendGroupMessage(
          bridge: daveBridge,
          groupRepo: daveGroupRepo,
          msgRepo: daveMsgRepo,
          groupId: groupId,
          text: 'Dave can send after convergence',
          senderPeerId: davePeerId,
          senderPublicKey: 'davePubKey64',
          senderPrivateKey: 'davePrivKey64',
          senderUsername: 'Dave',
        );

        expect(charlieSendResult, group_send.SendGroupMessageResult.success);
        expect(charlieMessage, isNotNull);
        expect(daveSendResult, group_send.SendGroupMessageResult.success);
        expect(daveMessage, isNotNull);
        expect(await charliePendingRepo.getPendingInvite(groupId), isNull);
        expect(await davePendingRepo.getPendingInvite(groupId), isNull);
        expect(
          await charliePendingRepo.getConsumedInvite('invite-charlie'),
          isNotNull,
        );
        expect(
          await davePendingRepo.getConsumedInvite('invite-dave'),
          isNotNull,
        );
      },
    );
  });
}
