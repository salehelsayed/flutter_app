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
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../test/core/services/fake_p2p_service.dart';
import '../test/shared/fakes/in_memory_inbox_staging_repository.dart';
import '../test/shared/fakes/in_memory_contact_repository.dart';
import '../test/shared/fakes/in_memory_group_repository.dart';
import '_support/canonical_runtime_device_test_lease.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final runtimeLease = CanonicalRuntimeDeviceTestLease(
    binding: 'group-real-crypto-onboarding-device-test',
  );
  setUpAll(runtimeLease.acquire);
  tearDownAll(runtimeLease.release);

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

    testWidgets(
      'GMF-11 forwarded marker survives real Go bridge group encryption and legacy absence defaults false',
      (tester) async {
        // 236: the native Go bridge accepts the optional isForwarded bool,
        // places it in the ALREADY ENCRYPTED group payload extras (never an
        // outer routing field), and real decryption returns it typed. Legacy
        // absence stays false. No relay account is required: the reliable
        // send runs with an explicit empty durable recipient set.
        final alice = await _generateIdentity(
          bridge: bridge,
          username: 'Alice',
        );
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

        final groupRepo = InMemoryGroupRepository();
        final group = await createGroup(
          bridge: bridge,
          groupRepo: groupRepo,
          name: 'Real Crypto Forwarding',
          type: GroupType.chat,
          creatorPeerId: alice.peerId,
          creatorPublicKey: alice.publicKey,
          creatorMlKemPublicKey: alice.mlKemPublicKey!,
          creatorUsername: alice.username,
        );
        final groupKey = await groupRepo.getLatestKey(group.id);
        expect(groupKey, isNotNull);

        Future<Map<String, dynamic>> decryptedPayloadOf(
          Map<String, dynamic> sendResult,
        ) async {
          expect(sendResult['ok'], isTrue, reason: '$sendResult');
          final envelope =
              jsonDecode(sendResult['envelope'] as String)
                  as Map<String, dynamic>;
          // Encrypted-extras-only: the OUTER envelope carries no marker.
          expect(
            envelope.containsKey('isForwarded'),
            isFalse,
            reason: 'the marker must never be an outer routing field',
          );
          final plaintext = await _groupDecrypt(
            bridge: bridge,
            groupKey: groupKey!.encryptedKey,
            ciphertext: (envelope['encrypted'] as Map).cast<String, dynamic>(),
          );
          return jsonDecode(plaintext) as Map<String, dynamic>;
        }

        // Forwarded send: the REAL encrypted payload extras carry typed true.
        final forwardedResult = await callGroupSendReliable(
          bridge,
          groupId: group.id,
          text: 'real forwarded message',
          senderPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          messageId: 'gmf11-forwarded',
          isForwarded: true,
          recipientPeerIds: const [],
          preserveRecipientPeerIds: true,
        );
        final forwardedPayload = await decryptedPayloadOf(forwardedResult);
        final forwardedExtra = (forwardedPayload['extra'] as Map?)
            ?.cast<String, dynamic>();
        expect(forwardedExtra, isNotNull);
        expect(forwardedExtra!['isForwarded'], isTrue);
        // The node's received-event mapping merges extras verbatim, so the
        // Dart exact-bool decode sees typed true.
        expect(forwardedExtra['isForwarded'] == true, isTrue);
        expect(forwardedPayload['text'], 'real forwarded message');

        // Legacy absence: an ordinary send carries NO marker anywhere and the
        // Dart exact-bool decode stays false.
        final legacyResult = await callGroupSendReliable(
          bridge,
          groupId: group.id,
          text: 'real legacy message',
          senderPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          messageId: 'gmf11-legacy',
          recipientPeerIds: const [],
          preserveRecipientPeerIds: true,
        );
        final legacyPayload = await decryptedPayloadOf(legacyResult);
        final legacyExtra = (legacyPayload['extra'] as Map?)
            ?.cast<String, dynamic>();
        expect(
          legacyExtra == null || !legacyExtra.containsKey('isForwarded'),
          isTrue,
          reason: 'legacy sends must not carry the marker key',
        );
        expect(legacyExtra?['isForwarded'] == true, isFalse);
      },
    );

    testWidgets(
      'GPL-12 private media policy survives real Go bridge encrypted group payload',
      (tester) async {
        final alice = await _generateIdentity(
          bridge: bridge,
          username: 'Alice',
        );
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

        final groupRepo = InMemoryGroupRepository();
        final group = await createGroup(
          bridge: bridge,
          groupRepo: groupRepo,
          name: 'Real Crypto Private Media',
          type: GroupType.chat,
          creatorPeerId: alice.peerId,
          creatorPublicKey: alice.publicKey,
          creatorMlKemPublicKey: alice.mlKemPublicKey!,
          creatorUsername: alice.username,
        );
        final groupKey = await groupRepo.getLatestKey(group.id);
        expect(groupKey, isNotNull);

        Future<Map<String, dynamic>> decryptedPayloadOf(
          Map<String, dynamic> sendResult,
        ) async {
          expect(sendResult['ok'], isTrue, reason: '$sendResult');
          final envelope =
              jsonDecode(sendResult['envelope'] as String)
                  as Map<String, dynamic>;
          for (final key in GroupPrivateMediaPolicy.wireKeys) {
            expect(
              envelope.containsKey(key),
              isFalse,
              reason: '$key must stay inside the encrypted payload extras',
            );
          }
          final plaintext = await _groupDecrypt(
            bridge: bridge,
            groupKey: groupKey!.encryptedKey,
            ciphertext: (envelope['encrypted'] as Map).cast<String, dynamic>(),
          );
          return jsonDecode(plaintext) as Map<String, dynamic>;
        }

        final privateResult = await callGroupSendReliable(
          bridge,
          groupId: group.id,
          text: '',
          senderPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          messageId: 'gpl12-private',
          media: const [
            {'id': 'gpl12-blob', 'mime': 'image/png', 'size': 42},
          ],
          privateMediaPolicy: const GroupPrivateMediaPolicy.viewOnce()
              .toWireExtras(),
          recipientPeerIds: const [],
          preserveRecipientPeerIds: true,
        );
        final privatePayload = await decryptedPayloadOf(privateResult);
        final privateExtra = (privatePayload['extra'] as Map?)
            ?.cast<String, dynamic>();
        expect(privateExtra, isNotNull);
        expect(privateExtra!['mediaPolicyVersion'], 1);
        expect(privateExtra['mediaLifecycle'], 'viewOnce');
        expect(privateExtra.containsKey('mediaDurationSeconds'), isTrue);
        expect(privateExtra['mediaDurationSeconds'], isNull);
        expect(privateExtra['mediaProtected'], isTrue);
        expect(
          GroupPrivateMediaPolicy.fromWireExtras(privateExtra),
          const GroupPrivateMediaPolicy.viewOnce(),
        );

        final legacyResult = await callGroupSendReliable(
          bridge,
          groupId: group.id,
          text: '',
          senderPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          messageId: 'gpl12-legacy',
          media: const [
            {'id': 'gpl12-legacy-blob', 'mime': 'image/png', 'size': 42},
          ],
          recipientPeerIds: const [],
          preserveRecipientPeerIds: true,
        );
        final legacyPayload = await decryptedPayloadOf(legacyResult);
        final legacyExtra = (legacyPayload['extra'] as Map?)
            ?.cast<String, dynamic>();
        for (final key in GroupPrivateMediaPolicy.wireKeys) {
          expect(legacyExtra?.containsKey(key) ?? false, isFalse);
        }
        expect(
          GroupPrivateMediaPolicy.fromWireExtras(
            legacyExtra?.cast<String, Object?>() ?? const <String, Object?>{},
          ),
          const GroupPrivateMediaPolicy.ordinary(),
        );
      },
    );

    testWidgets(
      'APL-03D private announcement policy survives the real Go bridge encrypted payload',
      (tester) async {
        final admin = await _generateIdentity(
          bridge: bridge,
          username: 'Announcement admin',
        );
        final nodeService = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: InMemoryInboxStagingRepository(),
        );
        addTearDown(() async {
          await nodeService.stopNode();
          nodeService.dispose();
        });
        expect(
          await nodeService.startNodeCore(admin.privateKey, admin.peerId),
          isTrue,
        );

        final groupRepo = InMemoryGroupRepository();
        final announcement = await createGroup(
          bridge: bridge,
          groupRepo: groupRepo,
          name: 'Real Crypto Private Announcement',
          type: GroupType.announcement,
          creatorPeerId: admin.peerId,
          creatorPublicKey: admin.publicKey,
          creatorMlKemPublicKey: admin.mlKemPublicKey!,
          creatorUsername: admin.username,
        );
        final groupKey = await groupRepo.getLatestKey(announcement.id);
        expect(groupKey, isNotNull);

        final result = await callGroupSendReliable(
          bridge,
          groupId: announcement.id,
          text: '',
          senderPeerId: admin.peerId,
          senderPublicKey: admin.publicKey,
          senderPrivateKey: admin.privateKey,
          senderUsername: admin.username,
          messageId: 'apl03d-private-announcement',
          media: const <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'apl03d-private-blob',
              'mime': 'image/png',
              'size': 42,
            },
          ],
          privateMediaPolicy: const GroupPrivateMediaPolicy.viewOnce()
              .toWireExtras(),
          recipientPeerIds: const <String>[],
          preserveRecipientPeerIds: true,
        );
        expect(result['ok'], isTrue, reason: '$result');
        final envelope =
            jsonDecode(result['envelope'] as String) as Map<String, dynamic>;
        for (final key in GroupPrivateMediaPolicy.wireKeys) {
          expect(
            envelope.containsKey(key),
            isFalse,
            reason: '$key must remain encrypted-inner for announcements',
          );
        }
        final plaintext = await _groupDecrypt(
          bridge: bridge,
          groupKey: groupKey!.encryptedKey,
          ciphertext: (envelope['encrypted'] as Map).cast<String, dynamic>(),
        );
        final payload = jsonDecode(plaintext) as Map<String, dynamic>;
        final extra = (payload['extra'] as Map).cast<String, dynamic>();
        expect(
          GroupPrivateMediaPolicy.fromWireExtras(extra),
          const GroupPrivateMediaPolicy.viewOnce(),
        );
        expect(
          extra.keys.toSet().containsAll(GroupPrivateMediaPolicy.wireKeys),
          isTrue,
        );
        expect(extra.containsKey('mediaConsumedAt'), isFalse);
        expect(extra.containsKey('media_received_at'), isFalse);
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
