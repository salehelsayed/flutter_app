/// Real-bridge group onboarding crypto coverage for Report 85.
@Tags(['device'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/create_group_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../test/core/services/fake_p2p_service.dart';
import '../test/shared/fakes/in_memory_inbox_staging_repository.dart';
import '../test/shared/fakes/in_memory_contact_repository.dart';
import '../test/shared/fakes/in_memory_group_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('real-crypto group onboarding', () {
    late GoBridgeClient bridge;

    setUp(() async {
      bridge = GoBridgeClient();
      await bridge.initialize();
    });

    tearDown(() {
      bridge.dispose();
    });

    testWidgets(
      'ML-007 re-add uses current group config and key while retained old key cannot decrypt',
      (tester) async {
        final alice = await _generateIdentity(
          bridge: bridge,
          username: 'Alice',
        );
        final bob = await _generateIdentity(bridge: bridge, username: 'Bob');
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

        final aliceGroupRepo = InMemoryGroupRepository();
        final bobGroupRepo = InMemoryGroupRepository();
        final bobContactRepo = InMemoryContactRepository()
          ..addTestContact(_contactFor(alice));
        final aliceP2p = FakeP2PService(
          initialState: const NodeState(isStarted: true),
        );

        final group = await createGroup(
          bridge: bridge,
          groupRepo: aliceGroupRepo,
          name: 'Real Crypto Onboarding',
          type: GroupType.chat,
          creatorPeerId: alice.peerId,
          creatorPublicKey: alice.publicKey,
          creatorMlKemPublicKey: alice.mlKemPublicKey!,
          creatorUsername: alice.username,
        );
        await addGroupMember(
          bridge: bridge,
          groupRepo: aliceGroupRepo,
          groupId: group.id,
          newMember: _memberFor(groupId: group.id, identity: bob),
          selfPeerId: alice.peerId,
        );

        final groupId = group.id;
        final aliceFirstKey = await aliceGroupRepo.getLatestKey(groupId);
        expect(aliceFirstKey, isNotNull);
        final firstMembers = await aliceGroupRepo.getMembers(groupId);
        final firstInviteResult = await sendGroupInvite(
          p2pService: aliceP2p,
          bridge: bridge,
          groupRepo: aliceGroupRepo,
          recipientPeerId: bob.peerId,
          recipientMlKemPublicKey: bob.mlKemPublicKey,
          senderPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          groupId: groupId,
          groupKey: aliceFirstKey!.encryptedKey,
          keyEpoch: aliceFirstKey.keyGeneration,
          groupConfig: buildGroupConfigPayload(group, firstMembers),
        );
        expect(firstInviteResult, SendGroupInviteResult.success);
        final firstInvite = aliceP2p.sentMessageLog.single.content;
        final (
          firstAcceptResult,
          firstAcceptedGroupId,
        ) = await handleIncomingGroupInvite(
          message: _inviteMessage(
            from: alice.peerId,
            to: bob.peerId,
            content: firstInvite,
          ),
          groupRepo: bobGroupRepo,
          contactRepo: bobContactRepo,
          bridge: bridge,
          ownMlKemSecretKey: bob.mlKemSecretKey,
          ownPeerId: bob.peerId,
          ownMlKemPublicKey: bob.mlKemPublicKey,
        );
        expect(firstAcceptResult, HandleGroupInviteResult.success);
        expect(firstAcceptedGroupId, groupId);

        final bobFirstKey = await bobGroupRepo.getLatestKey(groupId);
        expect(bobFirstKey, isNotNull);
        expect(bobFirstKey!.encryptedKey, aliceFirstKey.encryptedKey);
        expect(bobFirstKey.keyGeneration, aliceFirstKey.keyGeneration);

        final firstCiphertext = await _groupEncrypt(
          bridge: bridge,
          groupKey: aliceFirstKey.encryptedKey,
          plaintext: 'first-add real crypto message',
        );
        expect(
          await _groupDecrypt(
            bridge: bridge,
            groupKey: bobFirstKey.encryptedKey,
            ciphertext: firstCiphertext,
          ),
          'first-add real crypto message',
        );

        final retainedOldKey = bobFirstKey.encryptedKey;
        await _removeBobFromRepos(
          aliceGroupRepo: aliceGroupRepo,
          bobGroupRepo: bobGroupRepo,
          groupId: groupId,
          bobPeerId: bob.peerId,
        );

        final generatedNextKey = await callGroupKeygen(bridge);
        final nextEpoch = aliceFirstKey.keyGeneration + 1;
        await callGroupUpdateKey(
          bridge,
          groupId: groupId,
          groupKey: generatedNextKey,
          keyEpoch: nextEpoch,
        );
        final nextKey = GroupKeyInfo(
          groupId: groupId,
          keyGeneration: nextEpoch,
          encryptedKey: generatedNextKey,
          createdAt: DateTime.now().toUtc(),
        );
        await aliceGroupRepo.saveKey(nextKey);
        await _saveBobAsCurrentMember(
          aliceGroupRepo: aliceGroupRepo,
          groupId: groupId,
          bob: bob,
        );

        aliceP2p.sentMessageLog.clear();
        final readdGroup = await aliceGroupRepo.getGroup(groupId);
        final members = await aliceGroupRepo.getMembers(groupId);
        final readdResult = await sendGroupInvite(
          p2pService: aliceP2p,
          bridge: bridge,
          groupRepo: aliceGroupRepo,
          recipientPeerId: bob.peerId,
          recipientMlKemPublicKey: bob.mlKemPublicKey,
          senderPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          groupId: groupId,
          groupKey: nextKey.encryptedKey,
          keyEpoch: nextKey.keyGeneration,
          groupConfig: buildGroupConfigPayload(readdGroup!, members),
        );
        expect(readdResult, SendGroupInviteResult.success);

        final readdInvite = aliceP2p.sentMessageLog.single.content;
        final (
          readdAcceptResult,
          readdGroupId,
        ) = await handleIncomingGroupInvite(
          message: _inviteMessage(
            from: alice.peerId,
            to: bob.peerId,
            content: readdInvite,
          ),
          groupRepo: bobGroupRepo,
          contactRepo: bobContactRepo,
          bridge: bridge,
          ownMlKemSecretKey: bob.mlKemSecretKey,
          ownPeerId: bob.peerId,
          ownMlKemPublicKey: bob.mlKemPublicKey,
        );
        expect(readdAcceptResult, HandleGroupInviteResult.success);
        expect(readdGroupId, groupId);

        final bobReaddKey = await bobGroupRepo.getLatestKey(groupId);
        expect(bobReaddKey, isNotNull);
        expect(bobReaddKey!.keyGeneration, nextKey.keyGeneration);
        expect(bobReaddKey.encryptedKey, nextKey.encryptedKey);

        final readdCiphertext = await _groupEncrypt(
          bridge: bridge,
          groupKey: nextKey.encryptedKey,
          plaintext: 're-add real crypto message',
        );
        expect(
          await _groupDecrypt(
            bridge: bridge,
            groupKey: bobReaddKey.encryptedKey,
            ciphertext: readdCiphertext,
          ),
          're-add real crypto message',
        );

        final oldKeyDecrypt = await _groupDecryptRaw(
          bridge: bridge,
          groupKey: retainedOldKey,
          ciphertext: readdCiphertext,
        );
        expect(oldKeyDecrypt['ok'], isNot(true));
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

ContactModel _contactFor(IdentityModel identity) {
  return ContactModel(
    peerId: identity.peerId,
    publicKey: identity.publicKey,
    rendezvous: '/dns4/relay/tcp/443/p2p/relay',
    username: identity.username,
    signature: 'sig-${identity.peerId}',
    scannedAt: DateTime.now().toUtc().toIso8601String(),
    mlKemPublicKey: identity.mlKemPublicKey,
  );
}

GroupMember _memberFor({
  required String groupId,
  required IdentityModel identity,
}) {
  return GroupMember(
    groupId: groupId,
    peerId: identity.peerId,
    username: identity.username,
    role: MemberRole.writer,
    publicKey: identity.publicKey,
    mlKemPublicKey: identity.mlKemPublicKey,
    joinedAt: DateTime.now().toUtc(),
  );
}

ChatMessage _inviteMessage({
  required String from,
  required String to,
  required String content,
}) {
  return ChatMessage(
    from: from,
    to: to,
    content: content,
    timestamp: DateTime.now().toUtc().toIso8601String(),
    isIncoming: true,
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

Future<void> _removeBobFromRepos({
  required InMemoryGroupRepository aliceGroupRepo,
  required InMemoryGroupRepository bobGroupRepo,
  required String groupId,
  required String bobPeerId,
}) async {
  await aliceGroupRepo.removeMember(groupId, bobPeerId);
  await bobGroupRepo.removeAllMembers(groupId);
  await bobGroupRepo.removeAllKeys(groupId);
  await bobGroupRepo.deleteGroup(groupId);
}

Future<void> _saveBobAsCurrentMember({
  required InMemoryGroupRepository aliceGroupRepo,
  required String groupId,
  required IdentityModel bob,
}) async {
  await aliceGroupRepo.saveMember(
    GroupMember(
      groupId: groupId,
      peerId: bob.peerId,
      username: bob.username,
      role: MemberRole.writer,
      publicKey: bob.publicKey,
      mlKemPublicKey: bob.mlKemPublicKey,
      joinedAt: DateTime.now().toUtc(),
    ),
  );
}
