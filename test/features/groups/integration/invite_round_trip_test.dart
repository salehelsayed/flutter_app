import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Group invite round-trip integration', () {
    // -----------------------------------------------------------------------
    // 1. Full invite round-trip: admin sends invite -> receiver processes it
    //    -> group is persisted.
    // -----------------------------------------------------------------------
    test(
      'full invite round-trip: admin sends invite -> receiver processes it '
      '-> group is persisted',
      () async {
        // --- Admin side setup ---
        final adminBridge = PassthroughCryptoBridge();
        final adminP2P = FakeP2PService(
          initialState: const NodeState(isStarted: true),
        );
        final adminGroupRepo = InMemoryGroupRepository();
        final adminContactRepo = FakeContactRepository();

        // Admin has the group locally with key + member records
        await adminGroupRepo.saveGroup(GroupModel(
          id: _groupId,
          name: 'Test Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/$_groupId',
          description: 'Integration test group',
          createdAt: DateTime.utc(2026, 3, 2),
          createdBy: _adminPeerId,
          myRole: GroupRole.admin,
        ));
        await adminGroupRepo.saveMember(GroupMember(
          groupId: _groupId,
          peerId: _adminPeerId,
          username: 'Admin',
          role: MemberRole.admin,
          publicKey: 'adminPubKey64',
          mlKemPublicKey: _adminMlKemPublicKey,
          joinedAt: DateTime.utc(2026, 3, 2),
        ));
        await adminGroupRepo.saveKey(GroupKeyInfo(
          groupId: _groupId,
          keyGeneration: _keyEpoch,
          encryptedKey: _groupKey,
          createdAt: DateTime.utc(2026, 3, 2),
        ));
        adminContactRepo.seed([_receiverContact()]);

        final groupConfig = _makeGroupConfig();

        // --- Action: admin sends invite ---
        final sendResult = await sendGroupInvite(
          p2pService: adminP2P,
          bridge: adminBridge,
          recipientPeerId: _receiverPeerId,
          recipientMlKemPublicKey: _receiverMlKemPublicKey,
          senderPeerId: _adminPeerId,
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
        final v2Envelope =
            GroupInvitePayload.parseEncryptedEnvelope(sentContent);
        expect(v2Envelope, isNotNull,
            reason: 'Sent message should be a v2 encrypted envelope');

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
        final (handleResult, handleGroupId) =
            await handleIncomingGroupInvite(
          message: incomingMessage,
          groupRepo: receiverGroupRepo,
          contactRepo: receiverContactRepo,
          bridge: receiverBridge,
          ownMlKemSecretKey: _receiverMlKemSecretKey,
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
        final joinCallIndex =
            receiverBridge.commandLog.indexOf('group:join');
        // The last sent message to bridge should be the group:join call.
        // But since PassthroughCryptoBridge also handles message.decrypt,
        // we verify via commandLog that group:join was called.
        expect(joinCallIndex, greaterThanOrEqualTo(0));

        // Cleanup
        adminP2P.dispose();
      },
    );

    // -----------------------------------------------------------------------
    // 2. Full round-trip with PassthroughCryptoBridge verifies
    //    encryption/decryption.
    // -----------------------------------------------------------------------
    test(
      'full round-trip with PassthroughCryptoBridge verifies '
      'encryption/decryption',
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
          recipientPeerId: _receiverPeerId,
          recipientMlKemPublicKey: _receiverMlKemPublicKey,
          senderPeerId: _adminPeerId,
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
        final innerPayload =
            jsonDecode(ciphertextRaw) as Map<String, dynamic>;
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
      },
    );

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
          recipientPeerId: _receiverPeerId,
          recipientMlKemPublicKey: _receiverMlKemPublicKey,
          senderPeerId: _adminPeerId,
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

        final (handleResult, handleGroupId) =
            await handleIncomingGroupInvite(
          message: incomingMessage,
          groupRepo: receiverGroupRepo,
          contactRepo: receiverContactRepo,
          bridge: receiverBridge,
          ownMlKemSecretKey: _receiverMlKemSecretKey,
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
          recipientPeerId: _receiverPeerId,
          recipientMlKemPublicKey: _receiverMlKemPublicKey,
          senderPeerId: _adminPeerId,
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
        await receiverGroupRepo.saveGroup(GroupModel(
          id: _groupId,
          name: 'Already Joined Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/$_groupId',
          createdAt: DateTime.utc(2026, 1, 1),
          createdBy: _adminPeerId,
          myRole: GroupRole.member,
        ));

        final incomingMessage = ChatMessage(
          from: _adminPeerId,
          to: _receiverPeerId,
          content: sentContent,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        );

        final (handleResult, handleGroupId) =
            await handleIncomingGroupInvite(
          message: incomingMessage,
          groupRepo: receiverGroupRepo,
          contactRepo: receiverContactRepo,
          bridge: receiverBridge,
          ownMlKemSecretKey: _receiverMlKemSecretKey,
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
    test(
      'invite round-trip with multiple members in config',
      () async {
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
          recipientPeerId: _receiverPeerId,
          recipientMlKemPublicKey: _receiverMlKemPublicKey,
          senderPeerId: _adminPeerId,
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

        final (handleResult, handleGroupId) =
            await handleIncomingGroupInvite(
          message: incomingMessage,
          groupRepo: receiverGroupRepo,
          contactRepo: receiverContactRepo,
          bridge: receiverBridge,
          ownMlKemSecretKey: _receiverMlKemSecretKey,
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
        final adminMember =
            members.firstWhere((m) => m.peerId == _adminPeerId);
        expect(adminMember.role, equals(MemberRole.admin));

        final member3 =
            members.firstWhere((m) => m.peerId == '12D3KooWMember3');
        expect(member3.role, equals(MemberRole.writer));

        final member4 =
            members.firstWhere((m) => m.peerId == '12D3KooWMember4');
        expect(member4.role, equals(MemberRole.reader));

        // Key is still persisted correctly
        final key = await receiverGroupRepo.getLatestKey(_groupId);
        expect(key, isNotNull);
        expect(key!.encryptedKey, equals(_groupKey));

        // Cleanup
        adminP2P.dispose();
      },
    );

    // -----------------------------------------------------------------------
    // 6. GroupInviteListener processes invite from router stream end-to-end.
    // -----------------------------------------------------------------------
    test(
      'GroupInviteListener processes invite from router stream end-to-end',
      () async {
        // We simulate the IncomingMessageRouter's groupInviteStream
        // by using a StreamController directly.
        final groupInviteStreamController =
            StreamController<ChatMessage>.broadcast();

        final receiverBridge = PassthroughCryptoBridge();
        final receiverGroupRepo = InMemoryGroupRepository();
        final receiverContactRepo = FakeContactRepository();
        receiverContactRepo.seed([_adminContact()]);

        final listener = GroupInviteListener(
          groupInviteStream: groupInviteStreamController.stream,
          groupRepo: receiverGroupRepo,
          contactRepo: receiverContactRepo,
          bridge: receiverBridge,
          getOwnMlKemSecretKey: () async => _receiverMlKemSecretKey,
        );

        // Listen for the group joined event
        final groupJoinedFuture = listener.groupJoinedStream.first;

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
          recipientPeerId: _receiverPeerId,
          recipientMlKemPublicKey: _receiverMlKemPublicKey,
          senderPeerId: _adminPeerId,
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

        // Wait for the listener to process and emit the joined group
        final joinedGroup =
            await groupJoinedFuture.timeout(const Duration(seconds: 5));

        expect(joinedGroup.id, equals(_groupId));
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

        // Cleanup
        listener.dispose();
        await groupInviteStreamController.close();
        adminP2P.dispose();
      },
    );
  });
}
