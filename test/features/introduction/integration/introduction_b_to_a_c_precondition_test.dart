import 'dart:convert';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/accept_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_pending_group_invite_repository.dart';
import '../../../shared/fakes/intro_test_user.dart';

Future<IntroductionModel> _waitForIntroPairReceived(IntroTestUser user) {
  return user.introListener.introReceivedStream
      .firstWhere(
        (intro) =>
            intro.introducerId == 'user-b' &&
            intro.recipientId == 'user-a' &&
            intro.introducedId == 'user-c',
      )
      .timeout(const Duration(seconds: 2));
}

Future<IntroductionModel> _waitForIntroStatusChanged(
  IntroTestUser user,
  String introId,
) {
  return user.introListener.introStatusChangedStream
      .firstWhere((intro) => intro.id == introId)
      .timeout(const Duration(seconds: 2));
}

Future<void> _waitForCondition(Future<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for introduction precondition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

GroupInviteMembershipFreshnessProof _freshnessProof({
  required String inviteId,
  required String groupId,
  required Map<String, dynamic> groupConfig,
  required ContactModel inviterContact,
  required DateTime issuedAt,
}) {
  final stateHash = buildGroupConfigStateHash(
    groupId: groupId,
    groupConfig: groupConfig,
  );
  return GroupInviteMembershipFreshnessProof(
    inviteId: inviteId,
    groupId: groupId,
    recipientPeerId: 'user-a',
    inviterPeerId: inviterContact.peerId,
    inviterPublicKey: inviterContact.publicKey,
    keyEpoch: 1,
    groupConfigStateHash: stateHash,
    membershipWatermark: stateHash,
    issuedAt: issuedAt,
    expiresAt: issuedAt.add(const Duration(days: 1)),
    inviterMemberSnapshot: {
      'peerId': inviterContact.peerId,
      'username': inviterContact.username,
      'role': 'admin',
      'publicKey': inviterContact.publicKey,
      'mlKemPublicKey': inviterContact.mlKemPublicKey,
    },
  );
}

PendingGroupInvite _pendingInviteFromCToA({
  required ContactModel cContactFromA,
  required ContactModel aContactFromC,
  required DateTime issuedAt,
}) {
  const inviteId = 'invite-c-to-a-after-intro';
  const groupId = 'group-after-b-introduces-c-to-a';
  final groupConfig = <String, dynamic>{
    'name': 'Introduced Friends',
    'groupType': 'chat',
    'members': [
      {
        'peerId': cContactFromA.peerId,
        'username': cContactFromA.username,
        'role': 'admin',
        'publicKey': cContactFromA.publicKey,
        'mlKemPublicKey': cContactFromA.mlKemPublicKey,
      },
      {
        'peerId': aContactFromC.peerId,
        'username': aContactFromC.username,
        'role': 'writer',
        'publicKey': aContactFromC.publicKey,
        'mlKemPublicKey': aContactFromC.mlKemPublicKey,
      },
    ],
    'createdBy': cContactFromA.peerId,
    'createdAt': issuedAt.toIso8601String(),
  };
  final payload = GroupInvitePayload(
    id: inviteId,
    groupId: groupId,
    groupKey: 'group-key-after-introduction',
    keyEpoch: 1,
    groupConfig: groupConfig,
    senderPeerId: cContactFromA.peerId,
    senderUsername: cContactFromA.username,
    timestamp: issuedAt.toIso8601String(),
    recipientPeerId: aContactFromC.peerId,
    invitePolicy: GroupInvitePolicy(
      expiresAt: issuedAt.add(const Duration(days: 1)),
      allowedDevices: [aContactFromC.peerId],
      assignedRole: 'writer',
      canInviteOthers: false,
      joinMaterialKind: GroupInvitePolicy.inlineGroupKeyKind,
      keyEpoch: 1,
      reusePolicy: GroupInviteReusePolicy.singleUse,
    ),
    membershipFreshnessProof: _freshnessProof(
      inviteId: inviteId,
      groupId: groupId,
      groupConfig: groupConfig,
      inviterContact: cContactFromA,
      issuedAt: issuedAt,
    ),
  ).withInviteSignature(signature: 'signed-by-user-c');

  return PendingGroupInvite.fromPayload(payload, receivedAt: issuedAt);
}

String? _verifiedPublicKey(FakeBridge bridge) {
  for (final message in bridge.sentMessages.reversed) {
    final decoded = jsonDecode(message) as Map<String, dynamic>;
    if (decoded['cmd'] == 'payload.verify') {
      final payload = decoded['payload'] as Map<String, dynamic>;
      return payload['publicKey'] as String?;
    }
  }
  return null;
}

void main() {
  late FakeP2PNetwork network;
  late IntroTestUser userA;
  late IntroTestUser userB;
  late IntroTestUser userC;

  setUp(() {
    network = FakeP2PNetwork();
    userA = IntroTestUser.create(
      peerId: 'user-a',
      username: 'User A',
      network: network,
    );
    userB = IntroTestUser.create(
      peerId: 'user-b',
      username: 'User B',
      network: network,
    );
    userC = IntroTestUser.create(
      peerId: 'user-c',
      username: 'User C',
      network: network,
    );

    userA.addContact(userB);
    userB.addContact(userA);
    userB.addContact(userC);
    userC.addContact(userB);

    userA.start();
    userB.start();
    userC.start();
  });

  tearDown(() {
    userA.dispose();
    userB.dispose();
    userC.dispose();
  });

  test(
    'user-b introducing user-c to user-a creates the A/C contact edge used by group invite acceptance',
    () async {
      expect(await userA.contactRepo.contactExists('user-c'), isFalse);
      expect(await userC.contactRepo.contactExists('user-a'), isFalse);

      final cAsKnownByB = await userB.contactRepo.getContact('user-c');
      final aReceivedFuture = _waitForIntroPairReceived(userA);
      final cReceivedFuture = _waitForIntroPairReceived(userC);
      final intros = await userB.sendIntroductions(
        recipientPeerId: 'user-a',
        friends: [cAsKnownByB!],
      );
      final introId = intros.single.id;

      final aReceived = await aReceivedFuture;
      final cReceived = await cReceivedFuture;
      expect(aReceived.id, introId);
      expect(cReceived.id, introId);
      expect(aReceived.introducerId, 'user-b');
      expect(aReceived.recipientId, 'user-a');
      expect(aReceived.introducedId, 'user-c');
      expect(cReceived, aReceived);

      final cSawAAccept = _waitForIntroStatusChanged(userC, introId);
      await userA.acceptIntro(introId);
      expect((await cSawAAccept).recipientStatus, IntroductionStatus.accepted);
      expect(await userA.contactRepo.contactExists('user-c'), isFalse);

      final aSawCAccept = _waitForIntroStatusChanged(userA, introId);
      await userC.acceptIntro(introId);
      await aSawCAccept;
      await _waitForCondition(() async {
        return await userA.contactRepo.contactExists('user-c') &&
            await userC.contactRepo.contactExists('user-a');
      });

      final aIntro = await userA.introRepo.getIntroduction(introId);
      final cIntro = await userC.introRepo.getIntroduction(introId);
      expect(aIntro!.status, IntroductionOverallStatus.mutualAccepted);
      expect(cIntro!.status, IntroductionOverallStatus.mutualAccepted);

      final cContactFromA = await userA.contactRepo.getContact('user-c');
      final aContactFromC = await userC.contactRepo.getContact('user-a');
      expect(cContactFromA!.introducedByPeerId, 'user-b');
      expect(cContactFromA.introducedBy, 'User B');
      expect(cContactFromA.publicKey, 'pk-user-c');
      expect(cContactFromA.mlKemPublicKey, 'test-mlkem-pk-user-c');
      expect(aContactFromC!.introducedByPeerId, 'user-b');

      final pendingInviteRepo = InMemoryPendingGroupInviteRepository();
      final groupRepo = InMemoryGroupRepository();
      final msgRepo = InMemoryGroupMessageRepository();
      final bridge = FakeBridge();
      bridge.responses['group:inboxRetrieveCursor'] = {
        'ok': true,
        'messages': const [],
        'cursor': '',
      };
      final issuedAt = DateTime.now().toUtc();
      await pendingInviteRepo.savePendingInvite(
        _pendingInviteFromCToA(
          cContactFromA: cContactFromA,
          aContactFromC: aContactFromC,
          issuedAt: issuedAt,
        ),
      );

      final (acceptResult, acceptedGroup) = await acceptPendingGroupInvite(
        pendingInviteRepo: pendingInviteRepo,
        groupRepo: groupRepo,
        contactRepo: userA.contactRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        groupId: 'group-after-b-introduces-c-to-a',
        senderPeerId: 'user-a',
        senderPublicKey: aContactFromC.publicKey,
        senderPrivateKey: 'sk-user-a',
        senderUsername: userA.username,
        now: issuedAt.add(const Duration(minutes: 1)),
      );

      expect(acceptResult, AcceptPendingGroupInviteResult.success);
      expect(acceptedGroup, isNotNull);
      expect(
        await groupRepo.getMember('group-after-b-introduces-c-to-a', 'user-c'),
        isNotNull,
      );
      expect(_verifiedPublicKey(bridge), cContactFromA.publicKey);
      expect(
        await pendingInviteRepo.getPendingInvite(
          'group-after-b-introduces-c-to-a',
        ),
        isNull,
      );
    },
  );
}
