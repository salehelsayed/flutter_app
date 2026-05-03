import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_consumption.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_revocation.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package_tombstone.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_pending_group_invite_repository.dart';

GroupInviteMembershipFreshnessProof _makeFreshnessProof({
  required String inviteId,
  required String groupId,
  required String? recipientPeerId,
  required Map<String, dynamic> groupConfig,
  required int keyEpoch,
  String? recipientDeviceId,
  String? recipientTransportPeerId,
  String? recipientMlKemPublicKey,
  String? recipientKeyPackageId,
  String? recipientKeyPackagePublicMaterial,
  required DateTime issuedAt,
}) {
  final stateHash = buildGroupConfigStateHash(
    groupId: groupId,
    groupConfig: groupConfig,
  );
  return GroupInviteMembershipFreshnessProof(
    inviteId: inviteId,
    groupId: groupId,
    recipientPeerId: recipientPeerId,
    recipientDeviceId: recipientDeviceId,
    recipientTransportPeerId: recipientTransportPeerId,
    recipientMlKemPublicKey: recipientMlKemPublicKey,
    recipientKeyPackageId: recipientKeyPackageId,
    recipientKeyPackagePublicMaterial: recipientKeyPackagePublicMaterial,
    inviterPeerId: '12D3KooWAlice',
    inviterPublicKey: 'alicePubKey64',
    keyEpoch: keyEpoch,
    groupConfigStateHash: stateHash,
    membershipWatermark: stateHash,
    issuedAt: issuedAt.toUtc(),
    expiresAt: issuedAt.toUtc().add(groupInviteMembershipFreshnessTtl),
    inviterMemberSnapshot: {
      'peerId': '12D3KooWAlice',
      'username': 'Alice',
      'role': 'admin',
      'publicKey': 'alicePubKey64',
      'mlKemPublicKey': 'aliceMlKem64',
    },
  );
}

void main() {
  late InMemoryGroupRepository groupRepo;
  late InMemoryPendingGroupInviteRepository pendingInviteRepo;
  late FakeContactRepository contactRepo;
  late FakeBridge bridge;

  ContactModel aliceContact() {
    return const ContactModel(
      peerId: '12D3KooWAlice',
      publicKey: 'alicePubKey64',
      rendezvous: '/ip4/0.0.0.0',
      username: 'Alice',
      signature: 'sig',
      scannedAt: '2026-01-01T00:00:00Z',
      mlKemPublicKey: 'aliceMlKem64',
    );
  }

  ChatMessage makeMessage({
    String groupId = 'grp-abc123',
    String inviteId = 'invite-1',
    String messageTo = 'myPeerId',
    bool includePolicy = true,
    bool excludeRecipientFromPolicy = false,
    GroupInviteReusePolicy reusePolicy = GroupInviteReusePolicy.singleUse,
    DateTime? policyExpiresAt,
    DateTime? issuedAt,
  }) {
    final issuedAtUtc = (issuedAt ?? DateTime.utc(2026, 3, 2, 12)).toUtc();
    final timestamp = issuedAtUtc.toIso8601String();
    final groupConfig = {
      'name': 'Book Club',
      'groupType': 'chat',
      'description': 'A group for book lovers',
      'members': const [
        {
          'peerId': '12D3KooWAlice',
          'role': 'admin',
          'publicKey': 'alicePubKey64',
        },
        {'peerId': 'myPeerId', 'role': 'writer', 'publicKey': 'myPubKey64'},
      ],
      'createdBy': '12D3KooWAlice',
      'createdAt': '2026-03-02T00:00:00.000Z',
    };
    final payload = GroupInvitePayload(
      id: inviteId,
      groupId: groupId,
      groupKey: 'base64-key',
      keyEpoch: 1,
      groupConfig: groupConfig,
      senderPeerId: '12D3KooWAlice',
      senderUsername: 'Alice',
      recipientPeerId: 'myPeerId',
      invitePolicy: GroupInvitePolicy(
        expiresAt: policyExpiresAt ?? DateTime.utc(2099, 5, 1, 12),
        allowedDevices: const ['myPeerId'],
        assignedRole: 'writer',
        canInviteOthers: false,
        joinMaterialKind: GroupInvitePolicy.inlineGroupKeyKind,
        keyEpoch: 1,
        reusePolicy: reusePolicy,
      ),
      membershipFreshnessProof: _makeFreshnessProof(
        inviteId: inviteId,
        groupId: groupId,
        recipientPeerId: 'myPeerId',
        groupConfig: groupConfig,
        keyEpoch: 1,
        issuedAt: issuedAtUtc,
      ),
      timestamp: timestamp,
    ).withInviteSignature(signature: 'signed-invite-by-alice');
    var content = payload.toJson();
    if (!includePolicy) {
      final envelope = jsonDecode(content) as Map<String, dynamic>;
      (envelope['payload'] as Map<String, dynamic>).remove('invitePolicy');
      content = jsonEncode(envelope);
    } else if (excludeRecipientFromPolicy) {
      final envelope = jsonDecode(content) as Map<String, dynamic>;
      final payloadMap = envelope['payload'] as Map<String, dynamic>;
      (payloadMap['invitePolicy'] as Map<String, dynamic>)['allowedDevices'] = [
        'otherPeerId',
      ];
      content = jsonEncode(envelope);
    }
    return ChatMessage(
      from: '12D3KooWAlice',
      to: messageTo,
      content: content,
      timestamp: timestamp,
      isIncoming: true,
    );
  }

  ChatMessage makeWelcomePackageMessage({
    String groupId = 'grp-abc123',
    String inviteId = 'invite-package-1',
    String packageId = 'my-kp-1',
    String publicMaterial = 'my-kpm-1',
    DateTime? policyExpiresAt,
    DateTime? issuedAt,
  }) {
    final issuedAtUtc = (issuedAt ?? DateTime.utc(2026, 3, 2, 12)).toUtc();
    final timestamp = issuedAtUtc.toIso8601String();
    final expiresAt = policyExpiresAt ?? DateTime.utc(2099, 5, 1, 12);
    final welcomePackage = GroupWelcomeKeyPackage.create(
      packageId: packageId,
      publicMaterial: publicMaterial,
      recipientPeerId: 'myPeerId',
      recipientDeviceId: 'my-device-1',
      recipientTransportPeerId: 'my-transport-1',
      recipientMlKemPublicKey: 'myMlKem64',
      inviteId: inviteId,
      groupId: groupId,
      keyEpoch: 1,
      issuedAt: issuedAtUtc,
      expiresAt: expiresAt,
    );
    final groupConfig = {
      'name': 'Book Club',
      'groupType': 'chat',
      'description': 'A group for book lovers',
      'members': [
        {
          'peerId': '12D3KooWAlice',
          'role': 'admin',
          'publicKey': 'alicePubKey64',
        },
        {
          'peerId': 'myPeerId',
          'role': 'writer',
          'publicKey': 'myPubKey64',
          'devices': [
            {
              'deviceId': 'my-device-1',
              'transportPeerId': 'my-transport-1',
              'deviceSigningPublicKey': 'myPubKey64',
              'mlKemPublicKey': 'myMlKem64',
              'keyPackageId': packageId,
              'keyPackagePublicMaterial': publicMaterial,
              'status': 'active',
            },
          ],
        },
      ],
      'createdBy': '12D3KooWAlice',
      'createdAt': '2026-03-02T00:00:00.000Z',
    };
    final payload = GroupInvitePayload(
      id: inviteId,
      groupId: groupId,
      groupKey: 'base64-key',
      keyEpoch: 1,
      groupConfig: groupConfig,
      senderPeerId: '12D3KooWAlice',
      senderUsername: 'Alice',
      recipientPeerId: 'myPeerId',
      recipientDeviceId: 'my-device-1',
      recipientTransportPeerId: 'my-transport-1',
      recipientMlKemPublicKey: 'myMlKem64',
      recipientKeyPackageId: packageId,
      recipientKeyPackagePublicMaterial: publicMaterial,
      welcomeKeyPackage: welcomePackage,
      invitePolicy: GroupInvitePolicy(
        expiresAt: expiresAt,
        allowedDevices: const ['my-device-1'],
        assignedRole: 'writer',
        canInviteOthers: false,
        joinMaterialKind: GroupInvitePolicy.inlineGroupKeyKind,
        keyEpoch: 1,
        welcomeKeyPackageId: welcomePackage.packageId,
        welcomeKeyPackagePublicMaterialHash: welcomePackage.publicMaterialHash,
        welcomeKeyPackageExpiresAt: welcomePackage.expiresAt,
      ),
      membershipFreshnessProof: _makeFreshnessProof(
        inviteId: inviteId,
        groupId: groupId,
        recipientPeerId: 'myPeerId',
        recipientDeviceId: 'my-device-1',
        recipientTransportPeerId: 'my-transport-1',
        recipientMlKemPublicKey: 'myMlKem64',
        recipientKeyPackageId: packageId,
        recipientKeyPackagePublicMaterial: publicMaterial,
        groupConfig: groupConfig,
        keyEpoch: 1,
        issuedAt: issuedAtUtc,
      ),
      timestamp: timestamp,
    ).withInviteSignature(signature: 'signed-invite-by-alice');
    return ChatMessage(
      from: '12D3KooWAlice',
      to: 'my-transport-1',
      content: payload.toJson(),
      timestamp: timestamp,
      isIncoming: true,
    );
  }

  setUp(() {
    groupRepo = InMemoryGroupRepository();
    pendingInviteRepo = InMemoryPendingGroupInviteRepository();
    contactRepo = FakeContactRepository()..seed([aliceContact()]);
    bridge = FakeBridge();
  });

  group('storeIncomingPendingGroupInvite', () {
    test(
      'stores validated invite as pending without creating group state',
      () async {
        final (result, invite) = await storeIncomingPendingGroupInvite(
          message: makeMessage(),
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: 'myPeerId',
        );

        expect(result, StorePendingGroupInviteResult.storedPending);
        expect(invite, isNotNull);
        expect(invite!.groupName, 'Book Club');
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(
          await pendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
      },
    );

    test('ignores delayed invite copy when invite was revoked', () async {
      final revokedAt = DateTime.utc(2026, 4, 29, 12);
      await pendingInviteRepo.saveRevokedInvite(
        GroupInviteRevocation(
          inviteId: 'invite-1',
          groupId: 'grp-abc123',
          revokedAt: revokedAt,
          expiresAt: revokedAt.add(const Duration(days: 7)),
          revokedBy: '12D3KooWAlice',
        ),
      );

      final (result, invite) = await storeIncomingPendingGroupInvite(
        message: makeMessage(
          issuedAt: revokedAt.add(const Duration(minutes: 10)),
        ),
        groupRepo: groupRepo,
        pendingInviteRepo: pendingInviteRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownPeerId: 'myPeerId',
        receivedAt: revokedAt.add(const Duration(minutes: 10)),
      );

      expect(result, StorePendingGroupInviteResult.revoked);
      expect(invite, isNull);
      expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
      expect(await groupRepo.getGroup('grp-abc123'), isNull);
    });

    test(
      'IJ003 delayed direct and mailbox invite copies after revocation do not recreate pending or group state',
      () async {
        final revokedAt = DateTime.utc(2026, 4, 29, 12);
        await pendingInviteRepo.saveRevokedInvite(
          GroupInviteRevocation(
            inviteId: 'invite-1',
            groupId: 'grp-abc123',
            revokedAt: revokedAt,
            expiresAt: revokedAt.add(const Duration(days: 7)),
            revokedBy: '12D3KooWAlice',
          ),
        );

        final (
          directResult,
          directInvite,
        ) = await storeIncomingPendingGroupInvite(
          message: makeMessage(
            issuedAt: revokedAt.add(const Duration(minutes: 10)),
          ),
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: 'myPeerId',
          receivedAt: revokedAt.add(const Duration(minutes: 10)),
        );
        final (
          mailboxResult,
          mailboxInvite,
        ) = await storeIncomingPendingGroupInvite(
          message: makeMessage(
            issuedAt: revokedAt.add(const Duration(minutes: 15)),
          ),
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: 'myPeerId',
          receivedAt: revokedAt.add(const Duration(minutes: 15)),
        );

        expect(directResult, StorePendingGroupInviteResult.revoked);
        expect(mailboxResult, StorePendingGroupInviteResult.revoked);
        expect(directInvite, isNull);
        expect(mailboxInvite, isNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
      },
    );

    test('ignores delayed invite copy when invite was already used', () async {
      final consumedAt = DateTime.utc(2026, 4, 29, 12);
      await pendingInviteRepo.saveConsumedInvite(
        GroupInviteConsumption(
          inviteId: 'invite-1',
          groupId: 'grp-abc123',
          consumedAt: consumedAt,
          expiresAt: consumedAt.add(const Duration(days: 7)),
        ),
      );

      final (result, invite) = await storeIncomingPendingGroupInvite(
        message: makeMessage(
          issuedAt: consumedAt.add(const Duration(minutes: 10)),
        ),
        groupRepo: groupRepo,
        pendingInviteRepo: pendingInviteRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownPeerId: 'myPeerId',
        receivedAt: consumedAt.add(const Duration(minutes: 10)),
      );

      expect(result, StorePendingGroupInviteResult.alreadyUsed);
      expect(invite, isNull);
      expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
      expect(await groupRepo.getGroup('grp-abc123'), isNull);
    });

    test(
      'IJ005 stores multi-use replay despite a local consumption tombstone',
      () async {
        final consumedAt = DateTime.utc(2026, 4, 29, 12);
        await pendingInviteRepo.saveConsumedInvite(
          GroupInviteConsumption(
            inviteId: 'invite-1',
            groupId: 'grp-abc123',
            consumedAt: consumedAt,
            expiresAt: consumedAt.add(const Duration(days: 7)),
          ),
        );

        final (result, invite) = await storeIncomingPendingGroupInvite(
          message: makeMessage(
            reusePolicy: GroupInviteReusePolicy.multiUse,
            issuedAt: consumedAt.add(const Duration(minutes: 10)),
          ),
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: 'myPeerId',
          receivedAt: consumedAt.add(const Duration(minutes: 10)),
        );

        expect(result, StorePendingGroupInviteResult.storedPending);
        expect(invite, isNotNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), invite);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
      },
    );

    test(
      'EK011 rejects stale welcome key package before pending or group state',
      () async {
        final (result, invite) = await storeIncomingPendingGroupInvite(
          message: makeWelcomePackageMessage(
            policyExpiresAt: DateTime.utc(2026, 4, 30, 12),
            issuedAt: DateTime.utc(2026, 4, 30, 11, 59),
          ),
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: 'myPeerId',
          ownDeviceId: 'my-device-1',
          ownTransportPeerId: 'my-transport-1',
          ownMlKemPublicKey: 'myMlKem64',
          ownKeyPackageId: 'my-kp-1',
          ownKeyPackagePublicMaterial: 'my-kpm-1',
          receivedAt: DateTime.utc(2026, 4, 30, 12, 1),
        );

        expect(result, StorePendingGroupInviteResult.invalidPayload);
        expect(invite, isNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
      },
    );

    test(
      'EK011 rejects replayed package tombstone under changed invite id before pending state',
      () async {
        final consumedAt = DateTime.utc(2026, 4, 29, 12);
        await pendingInviteRepo.saveWelcomeKeyPackageTombstone(
          GroupWelcomeKeyPackageTombstone(
            packageId: 'my-kp-1',
            recipientDeviceId: 'my-device-1',
            groupId: 'grp-abc123',
            inviteId: 'invite-original',
            publicMaterialHash: GroupWelcomeKeyPackage.hashPublicMaterial(
              'my-kpm-1',
            ),
            consumedAt: consumedAt,
            expiresAt: consumedAt.add(pendingGroupInviteTtl),
          ),
        );

        final (result, invite) = await storeIncomingPendingGroupInvite(
          message: makeWelcomePackageMessage(
            inviteId: 'invite-replay',
            issuedAt: consumedAt.add(const Duration(minutes: 10)),
          ),
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: 'myPeerId',
          ownDeviceId: 'my-device-1',
          ownTransportPeerId: 'my-transport-1',
          ownMlKemPublicKey: 'myMlKem64',
          ownKeyPackageId: 'my-kp-1',
          ownKeyPackagePublicMaterial: 'my-kpm-1',
          receivedAt: consumedAt.add(const Duration(minutes: 10)),
        );

        expect(result, StorePendingGroupInviteResult.alreadyUsed);
        expect(invite, isNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
      },
    );

    test(
      'IJ005 rejects expired credential replay before pending or group state',
      () async {
        final (result, invite) = await storeIncomingPendingGroupInvite(
          message: makeMessage(
            policyExpiresAt: DateTime.utc(2026, 4, 30, 12),
            issuedAt: DateTime.utc(2026, 4, 30, 11, 59),
          ),
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: 'myPeerId',
          receivedAt: DateTime.utc(2026, 4, 30, 12, 1),
        );

        expect(result, StorePendingGroupInviteResult.invalidPayload);
        expect(invite, isNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
      },
    );

    test(
      'IJ005 rejects direct credential replay to a different device',
      () async {
        final (result, invite) = await storeIncomingPendingGroupInvite(
          message: makeMessage(messageTo: 'otherPeerId'),
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: 'otherPeerId',
          receivedAt: DateTime.utc(2026, 4, 30, 12),
        );

        expect(result, StorePendingGroupInviteResult.invalidPayload);
        expect(invite, isNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
      },
    );

    test(
      'IJ009 does not store pending invite when local peer identity is unavailable or mismatched',
      () async {
        final (
          missingResult,
          missingInvite,
        ) = await storeIncomingPendingGroupInvite(
          message: makeMessage(),
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          receivedAt: DateTime.utc(2026, 4, 30, 12),
        );

        expect(missingResult, StorePendingGroupInviteResult.invalidPayload);
        expect(missingInvite, isNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));

        groupRepo = InMemoryGroupRepository();
        pendingInviteRepo = InMemoryPendingGroupInviteRepository();
        bridge = FakeBridge();

        final (
          mismatchedResult,
          mismatchedInvite,
        ) = await storeIncomingPendingGroupInvite(
          message: makeMessage(),
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: 'otherPeerId',
          receivedAt: DateTime.utc(2026, 4, 30, 12),
        );

        expect(mismatchedResult, StorePendingGroupInviteResult.invalidPayload);
        expect(mismatchedInvite, isNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
      },
    );

    test(
      'IJ005 rejects missing or unknown reuse policy before state',
      () async {
        Future<void> expectInvalid(
          String label,
          void Function(Map<String, dynamic> policy) mutate,
        ) async {
          final baseMessage = makeMessage();
          final envelope =
              jsonDecode(baseMessage.content) as Map<String, dynamic>;
          final payloadMap = envelope['payload'] as Map<String, dynamic>;
          final policy = payloadMap['invitePolicy'] as Map<String, dynamic>;
          mutate(policy);

          final (result, invite) = await storeIncomingPendingGroupInvite(
            message: ChatMessage(
              from: baseMessage.from,
              to: baseMessage.to,
              content: jsonEncode(envelope),
              timestamp: baseMessage.timestamp,
              isIncoming: true,
            ),
            groupRepo: groupRepo,
            pendingInviteRepo: pendingInviteRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            ownPeerId: 'myPeerId',
          );

          expect(
            result,
            StorePendingGroupInviteResult.invalidPayload,
            reason: label,
          );
          expect(invite, isNull, reason: label);
          expect(
            await pendingInviteRepo.getPendingInvite('grp-abc123'),
            isNull,
            reason: label,
          );
          expect(await groupRepo.getGroup('grp-abc123'), isNull, reason: label);
          expect(
            await groupRepo.getLatestKey('grp-abc123'),
            isNull,
            reason: label,
          );
        }

        await expectInvalid('missing reusePolicy', (policy) {
          policy.remove('reusePolicy');
        });
        await expectInvalid('unknown reusePolicy', (policy) {
          policy['reusePolicy'] = {'mode': 'linkReusable'};
        });
      },
    );

    test('returns duplicateGroup when group already exists', () async {
      await groupRepo.saveGroup(
        GroupModel(
          id: 'grp-abc123',
          name: 'Joined Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/grp-abc123',
          createdAt: DateTime.utc(2026, 3, 2),
          createdBy: '12D3KooWAlice',
          myRole: GroupRole.member,
        ),
      );

      final (result, invite) = await storeIncomingPendingGroupInvite(
        message: makeMessage(),
        groupRepo: groupRepo,
        pendingInviteRepo: pendingInviteRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownPeerId: 'myPeerId',
      );

      expect(result, StorePendingGroupInviteResult.duplicateGroup);
      expect(invite, isNull);
      expect(pendingInviteRepo.count, 0);
    });

    test('returns unknownSender when contact is missing', () async {
      contactRepo.seed([]);

      final (result, invite) = await storeIncomingPendingGroupInvite(
        message: makeMessage(),
        groupRepo: groupRepo,
        pendingInviteRepo: pendingInviteRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownPeerId: 'myPeerId',
      );

      expect(result, StorePendingGroupInviteResult.unknownSender);
      expect(invite, isNull);
      expect(pendingInviteRepo.count, 0);
    });

    test(
      'IJ001 rejects missing first-class policy before pending or group state',
      () async {
        final (result, invite) = await storeIncomingPendingGroupInvite(
          message: makeMessage(includePolicy: false),
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: 'myPeerId',
        );

        expect(result, StorePendingGroupInviteResult.invalidPayload);
        expect(invite, isNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
      },
    );

    test(
      'IJ001 rejects contradictory policy before pending or group state',
      () async {
        final (result, invite) = await storeIncomingPendingGroupInvite(
          message: makeMessage(excludeRecipientFromPolicy: true),
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownPeerId: 'myPeerId',
        );

        expect(result, StorePendingGroupInviteResult.invalidPayload);
        expect(invite, isNull);
        expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(await groupRepo.getLatestKey('grp-abc123'), isNull);
      },
    );
  });
}
