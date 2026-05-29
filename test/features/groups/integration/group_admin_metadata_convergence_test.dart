import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/accept_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_membership_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/application/update_group_metadata_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/services/fake_p2p_service.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../shared/fakes/fake_group_pubsub_network.dart';
import '../../../shared/fakes/group_test_user.dart';
import '../../../shared/fakes/in_memory_pending_group_invite_repository.dart';

const groupAdminMetadataConvergenceLabel =
    'A/B/C metadata, admin promotion, member add, fanout, and avatar updates converge';
const promotedAdminAddsMemberConvergenceLabel =
    'promoted admin can add C and A/B/C metadata, fanout, and avatar updates converge';
const exactScenario3PromotedAdminJourneyLabel =
    'exact Scenario 3 promoted admin invite, metadata, fanout, and photo journey passes';
const exactScenario4AdminDemotionEnforcementLabel =
    'exact Scenario 4 admin demotion enforcement journey passes';
const promotedAdminRecoverySaveConvergenceLabel =
    'promoted admin recovery-blocked save waits then metadata and photo converge';

enum GroupAdminMetadataMemberAdder { alice, bob }

Future<void> _pump() => Future<void>.delayed(const Duration(milliseconds: 50));

Future<String?> _fakeDownloadGroupAvatar({
  required Bridge bridge,
  required String groupId,
  required String blobId,
}) async {
  return 'media/group_avatars/$groupId.jpg';
}

Future<void> _waitUntil(
  Future<bool> Function() condition, {
  String reason = 'condition',
}) async {
  for (var i = 0; i < 40; i++) {
    if (await condition()) return;
    await _pump();
  }
  fail('Timed out waiting for $reason');
}

Future<void> _saveKey({
  required GroupTestUser user,
  required String groupId,
  required int epoch,
}) async {
  await user.groupRepo.saveKey(
    GroupKeyInfo(
      groupId: groupId,
      keyGeneration: epoch,
      encryptedKey: 'group-key-epoch-$epoch',
      createdAt: DateTime.utc(2026, 5, 25, 10).add(Duration(minutes: epoch)),
    ),
  );
}

Future<Map<String, dynamic>> _buildSnapshot({
  required GroupTestUser user,
  required String groupId,
}) async {
  final group = await user.groupRepo.getGroup(groupId);
  expect(group, isNotNull, reason: '${user.username} group snapshot source');
  final members = await user.groupRepo.getMembers(groupId);
  return buildGroupConfigPayload(group!, members);
}

Future<Set<String>> _memberPeerIds({
  required GroupTestUser user,
  required String groupId,
}) async {
  final members = await user.groupRepo.getMembers(groupId);
  return members.map((member) => member.peerId).toSet();
}

List<String> _inboxStoreRecipientPeerIdsForMessage(
  GroupTestUser user,
  String messageId,
) {
  for (final rawMessage in user.bridge.sentMessages.reversed) {
    final parsed = jsonDecode(rawMessage) as Map<String, dynamic>;
    if (parsed['cmd'] != 'group:inboxStore') continue;
    final payload = parsed['payload'] as Map<String, dynamic>;
    final replayEnvelope =
        jsonDecode(payload['message'] as String) as Map<String, dynamic>;
    if (replayEnvelope['messageId'] != messageId) continue;
    return (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
        .cast<String>();
  }
  fail('Missing group:inboxStore for $messageId');
}

void _expectPhotoSnapshot(
  Map<String, dynamic> snapshot, {
  required String groupId,
  required String blobId,
  required String mime,
  required DateTime updatedAt,
}) {
  expect(snapshot['avatarBlobId'], blobId);
  expect(snapshot['avatarMime'], mime);
  expect(snapshot['metadataUpdatedAt'], updatedAt.toUtc().toIso8601String());
  expect(snapshot[groupConfigStateHashField], isA<String>());
  expect(
    isGroupConfigStateHashValid(groupId: groupId, groupConfig: snapshot),
    isTrue,
  );
}

Future<void> _promoteBob({
  required GroupTestUser alice,
  required GroupTestUser bob,
  required String groupId,
  required DateTime changedAt,
}) async {
  await alice.updateMemberRole(
    groupId: groupId,
    memberPeerId: bob.peerId,
    role: MemberRole.admin,
    changedAt: changedAt,
  );
  await _waitUntil(() async {
    final bobGroup = await bob.groupRepo.getGroup(groupId);
    final bobMember = await bob.groupRepo.getMember(groupId, bob.peerId);
    return bobGroup?.myRole == GroupRole.admin &&
        bobMember?.role == MemberRole.admin;
  }, reason: 'Bob admin promotion');
}

ContactModel _contactFor(GroupTestUser user, DateTime scannedAt) {
  return ContactModel(
    peerId: user.peerId,
    publicKey: user.publicKey,
    rendezvous: '/ip4/0.0.0.0',
    username: user.username,
    signature: 'sig-${user.peerId}',
    scannedAt: scannedAt.toUtc().toIso8601String(),
    mlKemPublicKey: user.mlKemPublicKey,
  );
}

GroupMember _memberFor({
  required GroupTestUser user,
  required String groupId,
  required DateTime joinedAt,
  MemberRole role = MemberRole.writer,
}) {
  return GroupMember(
    groupId: groupId,
    peerId: user.peerId,
    username: user.username,
    role: role,
    permissions: GroupMemberPermissions.empty,
    publicKey: user.publicKey,
    mlKemPublicKey: user.mlKemPublicKey,
    devices: [user.deviceIdentity],
    joinedAt: joinedAt.toUtc(),
  );
}

class _DirectMembershipUpdateHarness {
  final _controllers = <String, StreamController<ChatMessage>>{};
  final _listeners = <GroupMembershipUpdateListener>[];

  void attach(GroupTestUser user) {
    final controller = StreamController<ChatMessage>.broadcast();
    final listener = GroupMembershipUpdateListener(
      groupMembershipUpdateStream: controller.stream,
      groupRepo: user.groupRepo,
      bridge: user.bridge,
      groupMessageListener: user.groupMessageListener,
    );
    listener.start();
    _controllers[user.peerId] = controller;
    _listeners.add(listener);
  }

  Future<bool> deliver({
    required String fromPeerId,
    required String toPeerId,
    required String content,
    required DateTime timestamp,
  }) async {
    final controller = _controllers[toPeerId];
    if (controller == null || controller.isClosed) return false;
    controller.add(
      ChatMessage(
        from: fromPeerId,
        to: toPeerId,
        content: content,
        timestamp: timestamp.toUtc().toIso8601String(),
        isIncoming: true,
      ),
    );
    return true;
  }

  Future<void> dispose() async {
    for (final listener in _listeners) {
      listener.dispose();
    }
    for (final controller in _controllers.values) {
      await controller.close();
    }
    _listeners.clear();
    _controllers.clear();
  }
}

Future<void> _sendDirectReplay({
  required _DirectMembershipUpdateHarness directHarness,
  required GroupTestUser sender,
  required String groupId,
  required List<GroupTestUser> recipients,
  required String sysText,
  required DateTime timestamp,
  required String messageId,
}) async {
  if (recipients.isEmpty) return;

  final replayPlaintext = jsonEncode({
    'groupId': groupId,
    'senderId': sender.peerId,
    'senderUsername': sender.username,
    'senderDeviceId': sender.deviceId,
    'transportPeerId': sender.deviceId,
    'text': sysText,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'messageId': messageId,
  });
  final replayEnvelope = await buildGroupOfflineReplayEnvelope(
    bridge: sender.bridge,
    groupRepo: sender.groupRepo,
    groupId: groupId,
    payloadType: groupOfflineReplayPayloadTypeMessage,
    plaintext: replayPlaintext,
    senderPeerId: sender.peerId,
    senderPublicKey: sender.publicKey,
    senderPrivateKey: sender.privateKey,
    senderDeviceId: sender.deviceId,
    senderTransportPeerId: sender.deviceId,
    senderKeyPackageId: sender.deviceIdentity.keyPackageId,
    messageId: messageId,
    recipientPeerIds: recipients.map((user) => user.peerId).toList(),
  );

  for (final recipient in recipients) {
    final sent = await sendGroupMembershipUpdateDirect(
      sendP2PMessage: (peerId, message) {
        return directHarness.deliver(
          fromPeerId: sender.peerId,
          toPeerId: peerId,
          content: message,
          timestamp: timestamp,
        );
      },
      recipientPeerId: recipient.peerId,
      groupId: groupId,
      senderPeerId: sender.peerId,
      replayEnvelope: replayEnvelope,
      timestamp: timestamp,
      messageId: messageId,
      attemptCount: 1,
    );
    expect(
      sent,
      isTrue,
      reason: 'direct replay delivered to ${recipient.peerId}',
    );
  }
}

Future<void> _inviteAndAcceptViaPendingFlow({
  required GroupTestUser inviter,
  required GroupTestUser invitee,
  required String groupId,
  required DateTime joinedAt,
  required DateTime inviteReceivedAt,
  required _DirectMembershipUpdateHarness directHarness,
  List<GroupTestUser> existingRecipientsForMembershipReplay = const [],
}) async {
  final preTransitionStateHash = await buildGroupTransitionStateHash(
    inviter.groupRepo,
    groupId,
  );
  final newMember = _memberFor(
    user: invitee,
    groupId: groupId,
    joinedAt: joinedAt,
  );
  await addGroupMember(
    bridge: inviter.bridge,
    groupRepo: inviter.groupRepo,
    groupId: groupId,
    newMember: newMember,
    selfPeerId: inviter.peerId,
  );

  final group = await inviter.groupRepo.getGroup(groupId);
  expect(
    group,
    isNotNull,
    reason: '${inviter.username} has group before invite',
  );
  final allMembers = await inviter.groupRepo.getMembers(groupId);
  final groupConfig = buildGroupConfigPayload(group!, allMembers);

  if (existingRecipientsForMembershipReplay.isNotEmpty) {
    final sourceEventId =
        'members_added:$groupId:${inviter.peerId}:${joinedAt.microsecondsSinceEpoch}';
    final signedPayload = await signGroupSystemTransitionPayload(
      bridge: inviter.bridge,
      groupRepo: inviter.groupRepo,
      groupId: groupId,
      transitionType: 'members_added',
      sourceEventId: sourceEventId,
      eventAt: joinedAt,
      actorPeerId: inviter.peerId,
      actorUsername: inviter.username,
      actorSigningPublicKey: inviter.publicKey,
      actorPrivateKey: inviter.privateKey,
      actorDeviceId: inviter.deviceId,
      actorTransportPeerId: inviter.deviceId,
      actorKeyPackageId: inviter.deviceIdentity.keyPackageId,
      preTransitionStateHash: preTransitionStateHash,
      systemPayload: {
        '__sys': 'members_added',
        'eventAt': joinedAt.toUtc().toIso8601String(),
        'members': [newMember.toConfigJson()],
        'groupConfig': groupConfig,
      },
    );
    await _sendDirectReplay(
      directHarness: directHarness,
      sender: inviter,
      groupId: groupId,
      recipients: existingRecipientsForMembershipReplay,
      sysText: jsonEncode(signedPayload),
      timestamp: joinedAt,
      messageId: sourceEventId,
    );
  }

  final latestKey = await inviter.groupRepo.getLatestKey(groupId);
  expect(latestKey, isNotNull, reason: '${inviter.username} has group key');
  final inviteP2P = FakeP2PService(
    initialState: NodeState(isStarted: true, peerId: inviter.peerId),
  );
  final sendResult = await sendGroupInvite(
    p2pService: inviteP2P,
    bridge: inviter.bridge,
    groupRepo: inviter.groupRepo,
    recipientPeerId: invitee.peerId,
    recipientMlKemPublicKey: invitee.mlKemPublicKey,
    recipientDeviceId: invitee.deviceId,
    senderPeerId: inviter.peerId,
    senderPublicKey: inviter.publicKey,
    senderPrivateKey: inviter.privateKey,
    senderUsername: inviter.username,
    senderDeviceId: inviter.deviceId,
    groupId: groupId,
    groupKey: latestKey!.encryptedKey,
    keyEpoch: latestKey.keyGeneration,
    groupConfig: groupConfig,
  );
  expect(sendResult, SendGroupInviteResult.success);

  final deliveredInvite = inviteP2P.sentMessageLog.singleWhere(
    (entry) =>
        entry.peerId == invitee.deviceId || entry.peerId == invitee.peerId,
  );
  final pendingInviteRepo = InMemoryPendingGroupInviteRepository();
  final receiverContacts = FakeContactRepository()
    ..seed([_contactFor(inviter, inviteReceivedAt)]);
  final (storeResult, pendingInvite) = await storeIncomingPendingGroupInvite(
    message: ChatMessage(
      from: inviter.peerId,
      to: deliveredInvite.peerId,
      content: deliveredInvite.content,
      timestamp: inviteReceivedAt.toUtc().toIso8601String(),
      isIncoming: true,
    ),
    groupRepo: invitee.groupRepo,
    pendingInviteRepo: pendingInviteRepo,
    contactRepo: receiverContacts,
    bridge: invitee.bridge,
    ownMlKemSecretKey: invitee.privateKey,
    ownPeerId: invitee.peerId,
    ownDeviceId: invitee.deviceId,
    ownTransportPeerId: invitee.deviceId,
    ownMlKemPublicKey: invitee.mlKemPublicKey,
    ownKeyPackageId: invitee.keyPackageId,
    ownKeyPackagePublicMaterial: invitee.keyPackagePublicMaterial,
    receivedAt: inviteReceivedAt,
  );
  expect(storeResult, StorePendingGroupInviteResult.storedPending);
  expect(pendingInvite?.groupId, groupId);

  final (acceptResult, acceptedGroup) = await acceptPendingGroupInvite(
    pendingInviteRepo: pendingInviteRepo,
    groupRepo: invitee.groupRepo,
    contactRepo: receiverContacts,
    msgRepo: invitee.msgRepo,
    bridge: invitee.bridge,
    groupId: groupId,
    groupMessageListener: invitee.groupMessageListener,
    senderPeerId: invitee.peerId,
    senderPublicKey: invitee.publicKey,
    senderPrivateKey: invitee.privateKey,
    senderUsername: invitee.username,
    ownDeviceId: invitee.deviceId,
    ownTransportPeerId: invitee.deviceId,
    ownMlKemPublicKey: invitee.mlKemPublicKey,
    ownKeyPackageId: invitee.keyPackageId,
    ownKeyPackagePublicMaterial: invitee.keyPackagePublicMaterial,
    now: inviteReceivedAt.add(const Duration(seconds: 1)),
    downloadGroupAvatarFn: _fakeDownloadGroupAvatar,
  );
  expect(acceptResult, AcceptPendingGroupInviteResult.success);
  expect(acceptedGroup?.id, groupId);
  expect(await pendingInviteRepo.getPendingInvite(groupId), isNull);
  invitee.subscribeToGroup(groupId);
}

Future<void> _updateMetadataAndReplay({
  required GroupTestUser sender,
  required String groupId,
  required String name,
  required String description,
  String? avatarBlobId,
  String? avatarMime,
  String? avatarPath,
  required DateTime changedAt,
  required _DirectMembershipUpdateHarness directHarness,
  required List<GroupTestUser> recipients,
}) async {
  final preTransitionStateHash = await buildGroupTransitionStateHash(
    sender.groupRepo,
    groupId,
  );
  String? signedSysText;

  await updateGroupMetadata(
    groupRepo: sender.groupRepo,
    groupId: groupId,
    name: name,
    description: description,
    avatarBlobId: avatarBlobId,
    avatarMime: avatarMime,
    avatarPath: avatarPath,
    eventAt: changedAt,
    beforePersist: (updatedGroup) async {
      final members = await sender.groupRepo.getMembers(groupId);
      final groupConfig = buildGroupConfigPayload(updatedGroup, members);
      final actorPayload = buildGroupMetadataActorEventPayload(
        groupId: groupId,
        updatedAt: changedAt,
        actorPeerId: sender.peerId,
        actorUsername: sender.username,
        actorPublicKey: sender.publicKey,
        groupConfig: groupConfig,
      );
      final canonicalPayload = canonicalizeGroupMetadataActorEventPayload(
        actorPayload,
      );
      final signResponse = await callSignPayload(
        bridge: sender.bridge,
        dataToSign: canonicalPayload,
        privateKey: sender.privateKey,
      );
      final signature = signResponse['signature'];
      expect(signResponse['ok'], isTrue);
      expect(signature, isA<String>());
      final sourceEventId =
          'group_metadata_updated:$groupId:${sender.peerId}:${changedAt.microsecondsSinceEpoch}';
      final unsignedPayload = {
        '__sys': 'group_metadata_updated',
        'updatedAt': changedAt.toUtc().toIso8601String(),
        'groupConfig': groupConfig,
        groupMetadataActorEventEnvelopeField:
            buildSignedGroupMetadataActorEventEnvelope(
              signedPayload: canonicalPayload,
              signature: signature as String,
            ),
      };
      final signedPayload = await signGroupSystemTransitionPayload(
        bridge: sender.bridge,
        groupRepo: sender.groupRepo,
        groupId: groupId,
        transitionType: 'group_metadata_updated',
        sourceEventId: sourceEventId,
        eventAt: changedAt,
        actorPeerId: sender.peerId,
        actorUsername: sender.username,
        actorSigningPublicKey: sender.publicKey,
        actorPrivateKey: sender.privateKey,
        actorDeviceId: sender.deviceId,
        actorTransportPeerId: sender.deviceId,
        actorKeyPackageId: sender.deviceIdentity.keyPackageId,
        preTransitionStateHash: preTransitionStateHash,
        systemPayload: unsignedPayload,
      );
      signedSysText = jsonEncode(signedPayload);
    },
  );

  final sysText = signedSysText;
  expect(sysText, isNotNull);
  final sourceEventId =
      'group_metadata_updated:$groupId:${sender.peerId}:${changedAt.microsecondsSinceEpoch}';
  await _sendDirectReplay(
    directHarness: directHarness,
    sender: sender,
    groupId: groupId,
    recipients: recipients,
    sysText: sysText!,
    timestamp: changedAt,
    messageId: sourceEventId,
  );
}

Future<void> _sendUnauthorizedMetadataReplay({
  required GroupTestUser sender,
  required String groupId,
  required DateTime changedAt,
  required _DirectMembershipUpdateHarness directHarness,
  required List<GroupTestUser> recipients,
}) async {
  final group = await sender.groupRepo.getGroup(groupId);
  expect(group, isNotNull, reason: 'sender has group for metadata replay');
  final members = await sender.groupRepo.getMembers(groupId);
  final rogueGroup = group!.copyWith(
    name: 'bob should not win',
    description: 'demoted bob metadata must be rejected',
    avatarBlobId: 'blob-scenario4-by-demoted-b',
    avatarMime: 'image/jpeg',
    avatarPath: 'media/group_avatars/$groupId-demoted-b.jpg',
    lastMetadataEventAt: changedAt.toUtc(),
  );
  final sysText = jsonEncode({
    '__sys': 'group_metadata_updated',
    'updatedAt': changedAt.toUtc().toIso8601String(),
    'groupConfig': buildGroupConfigPayload(rogueGroup, members),
  });
  final messageId =
      'group_metadata_updated:$groupId:${sender.peerId}:${changedAt.microsecondsSinceEpoch}:unauthorized';
  await _sendDirectReplay(
    directHarness: directHarness,
    sender: sender,
    groupId: groupId,
    recipients: recipients,
    sysText: sysText,
    timestamp: changedAt,
    messageId: messageId,
  );
}

Future<void> _sendUnauthorizedMembersAddedReplay({
  required GroupTestUser sender,
  required GroupTestUser addedUser,
  required String groupId,
  required DateTime eventAt,
  required _DirectMembershipUpdateHarness directHarness,
  required List<GroupTestUser> recipients,
}) async {
  final group = await sender.groupRepo.getGroup(groupId);
  expect(group, isNotNull, reason: 'sender has group for members replay');
  final existingMembers = await sender.groupRepo.getMembers(groupId);
  final newMember = _memberFor(
    user: addedUser,
    groupId: groupId,
    joinedAt: eventAt,
  );
  final groupConfig = buildGroupConfigPayload(group!, <GroupMember>[
    ...existingMembers,
    newMember,
  ], configVersionOverride: eventAt.toUtc());
  final sysText = jsonEncode({
    '__sys': 'members_added',
    'eventAt': eventAt.toUtc().toIso8601String(),
    'members': [newMember.toConfigJson()],
    'groupConfig': groupConfig,
  });
  final messageId =
      'members_added:$groupId:${sender.peerId}:${eventAt.microsecondsSinceEpoch}:unauthorized';
  await _sendDirectReplay(
    directHarness: directHarness,
    sender: sender,
    groupId: groupId,
    recipients: recipients,
    sysText: sysText,
    timestamp: eventAt,
    messageId: messageId,
  );
}

Future<void> _expectGroupMetadata({
  required GroupTestUser user,
  required String groupId,
  required String name,
  required String description,
  required String avatarBlobId,
  required String avatarMime,
}) async {
  final group = await user.groupRepo.getGroup(groupId);
  expect(group?.name, name, reason: '${user.username} name');
  expect(group?.description, description, reason: '${user.username} desc');
  expect(group?.avatarBlobId, avatarBlobId, reason: '${user.username} avatar');
  expect(group?.avatarMime, avatarMime, reason: '${user.username} avatar mime');
}

Future<void> _expectDemotionTimeline({
  required GroupTestUser user,
  required String groupId,
}) async {
  final messages = await user.loadGroupMessages(groupId);
  expect(
    messages.map((message) => message.text),
    contains('User A removed admin from User B'),
    reason: '${user.username} demotion timeline',
  );
}

Future<void> runExactScenario4AdminDemotionEnforcementJourney() async {
  final network = FakeGroupPubSubNetwork();
  final directHarness = _DirectMembershipUpdateHarness();
  addTearDown(directHarness.dispose);

  const groupId = 'grp-exact-scenario-4-admin-demotion';
  const groupKeyEpoch = 1;
  final createdAt = DateTime.utc(2026, 5, 25, 20);
  const validName = 'test me';
  const validDescription = 'do you see me?';
  const validAvatarBlobId = 'blob-scenario4-by-a';
  const validAvatarMime = 'image/jpeg';

  final alice = GroupTestUser.create(
    peerId: 'scenario4-user-a',
    deviceId: 'scenario4-device-a',
    username: 'User A',
    network: network,
    downloadGroupAvatarFn: _fakeDownloadGroupAvatar,
  );
  final bob = GroupTestUser.create(
    peerId: 'scenario4-user-b',
    deviceId: 'scenario4-device-b',
    username: 'User B',
    network: network,
    downloadGroupAvatarFn: _fakeDownloadGroupAvatar,
  );
  final charlie = GroupTestUser.create(
    peerId: 'scenario4-user-c',
    deviceId: 'scenario4-device-c',
    username: 'User C',
    network: network,
    downloadGroupAvatarFn: _fakeDownloadGroupAvatar,
  );
  final dana = GroupTestUser.create(
    peerId: 'scenario4-user-d',
    deviceId: 'scenario4-device-d',
    username: 'User D',
    network: network,
    downloadGroupAvatarFn: _fakeDownloadGroupAvatar,
  );
  addTearDown(() {
    alice.dispose();
    bob.dispose();
    charlie.dispose();
    dana.dispose();
  });

  alice.start();
  bob.start();
  charlie.start();
  dana.start();
  directHarness.attach(alice);
  directHarness.attach(bob);
  directHarness.attach(charlie);

  await alice.createGroup(groupId: groupId, name: 'test', createdAt: createdAt);
  await _saveKey(user: alice, groupId: groupId, epoch: groupKeyEpoch);

  await _inviteAndAcceptViaPendingFlow(
    inviter: alice,
    invitee: bob,
    groupId: groupId,
    joinedAt: createdAt.add(const Duration(minutes: 1)),
    inviteReceivedAt: createdAt.add(const Duration(minutes: 1, seconds: 10)),
    directHarness: directHarness,
  );

  await _promoteBob(
    alice: alice,
    bob: bob,
    groupId: groupId,
    changedAt: createdAt.add(const Duration(minutes: 2)),
  );

  await _updateMetadataAndReplay(
    sender: bob,
    groupId: groupId,
    name: validName,
    description: validDescription,
    avatarBlobId: 'blob-scenario4-by-b',
    avatarMime: validAvatarMime,
    avatarPath: 'media/group_avatars/$groupId.jpg',
    changedAt: createdAt.add(const Duration(minutes: 3)),
    directHarness: directHarness,
    recipients: [alice],
  );
  await _waitUntil(() async {
    final group = await alice.groupRepo.getGroup(groupId);
    return group?.name == validName &&
        group?.description == validDescription &&
        group?.avatarBlobId == 'blob-scenario4-by-b';
  }, reason: 'Alice receives Bob metadata before demotion');

  await _inviteAndAcceptViaPendingFlow(
    inviter: bob,
    invitee: charlie,
    groupId: groupId,
    joinedAt: createdAt.add(const Duration(minutes: 4)),
    inviteReceivedAt: createdAt.add(const Duration(minutes: 4, seconds: 10)),
    directHarness: directHarness,
    existingRecipientsForMembershipReplay: [alice],
  );
  await _waitUntil(() async {
    final aliceSeesCharlie = await alice.groupRepo.getMember(
      groupId,
      charlie.peerId,
    );
    final charlieGroup = await charlie.groupRepo.getGroup(groupId);
    return aliceSeesCharlie != null &&
        charlieGroup?.name == validName &&
        charlieGroup?.description == validDescription &&
        charlieGroup?.avatarBlobId == 'blob-scenario4-by-b';
  }, reason: 'Charlie joins with Bob metadata and Alice learns Charlie');

  final (aliceSendResult, _) = await alice.sendGroupMessageViaBridge(
    groupId: groupId,
    text: 'scenario4 from A',
    messageId: 'scenario4-from-a',
    timestamp: createdAt.add(const Duration(minutes: 5)),
  );
  expect(aliceSendResult.name, 'success');
  final (bobSendResult, _) = await bob.sendGroupMessageViaBridge(
    groupId: groupId,
    text: 'scenario4 from B',
    messageId: 'scenario4-from-b',
    timestamp: createdAt.add(const Duration(minutes: 5, seconds: 20)),
  );
  expect(bobSendResult.name, 'success');
  final (charlieSendResult, _) = await charlie.sendGroupMessageViaBridge(
    groupId: groupId,
    text: 'scenario4 from C',
    messageId: 'scenario4-from-c',
    timestamp: createdAt.add(const Duration(minutes: 5, seconds: 40)),
  );
  expect(charlieSendResult.name, 'success');
  await _waitUntil(() async {
    final aliceMessages = await alice.loadGroupMessages(groupId);
    final bobMessages = await bob.loadGroupMessages(groupId);
    final charlieMessages = await charlie.loadGroupMessages(groupId);
    return aliceMessages.any((message) => message.text == 'scenario4 from B') &&
        aliceMessages.any((message) => message.text == 'scenario4 from C') &&
        bobMessages.any((message) => message.text == 'scenario4 from A') &&
        bobMessages.any((message) => message.text == 'scenario4 from C') &&
        charlieMessages.any((message) => message.text == 'scenario4 from A') &&
        charlieMessages.any((message) => message.text == 'scenario4 from B');
  }, reason: 'Scenario 4 A/B/C fanout before demotion');

  await _updateMetadataAndReplay(
    sender: alice,
    groupId: groupId,
    name: validName,
    description: validDescription,
    avatarBlobId: validAvatarBlobId,
    avatarMime: validAvatarMime,
    avatarPath: 'media/group_avatars/$groupId.jpg',
    changedAt: createdAt.add(const Duration(minutes: 6)),
    directHarness: directHarness,
    recipients: [bob, charlie],
  );
  await _waitUntil(() async {
    final bobGroup = await bob.groupRepo.getGroup(groupId);
    final charlieGroup = await charlie.groupRepo.getGroup(groupId);
    return bobGroup?.avatarBlobId == validAvatarBlobId &&
        charlieGroup?.avatarBlobId == validAvatarBlobId;
  }, reason: 'Alice avatar update reaches Bob and Charlie');

  await alice.updateMemberRole(
    groupId: groupId,
    memberPeerId: bob.peerId,
    role: MemberRole.writer,
    changedAt: createdAt.add(const Duration(minutes: 7)),
  );
  await _waitUntil(() async {
    final aliceBob = await alice.groupRepo.getMember(groupId, bob.peerId);
    final bobGroup = await bob.groupRepo.getGroup(groupId);
    final bobSelf = await bob.groupRepo.getMember(groupId, bob.peerId);
    final charlieBob = await charlie.groupRepo.getMember(groupId, bob.peerId);
    return aliceBob?.role == MemberRole.writer &&
        bobGroup?.myRole == GroupRole.member &&
        bobSelf?.role == MemberRole.writer &&
        charlieBob?.role == MemberRole.writer;
  }, reason: 'Bob demotion converges on A/B/C');

  await _expectDemotionTimeline(user: alice, groupId: groupId);
  await _expectDemotionTimeline(user: bob, groupId: groupId);
  await _expectDemotionTimeline(user: charlie, groupId: groupId);
  expect(
    (await alice.groupRepo.getMember(groupId, alice.peerId))?.role,
    MemberRole.admin,
  );
  expect(
    (await charlie.groupRepo.getMember(groupId, charlie.peerId))?.role,
    MemberRole.writer,
  );

  await expectLater(
    bob.updateMetadata(
      groupId: groupId,
      name: 'bob local should fail',
      description: 'demoted local metadata edit',
      changedAt: createdAt.add(const Duration(minutes: 8)),
    ),
    throwsA(isA<StateError>()),
  );
  await expectLater(
    addGroupMember(
      bridge: bob.bridge,
      groupRepo: bob.groupRepo,
      groupId: groupId,
      newMember: _memberFor(
        user: dana,
        groupId: groupId,
        joinedAt: createdAt.add(const Duration(minutes: 8, seconds: 20)),
      ),
      selfPeerId: bob.peerId,
    ),
    throwsA(isA<StateError>()),
  );

  await _sendUnauthorizedMetadataReplay(
    sender: bob,
    groupId: groupId,
    changedAt: createdAt.add(const Duration(minutes: 9)),
    directHarness: directHarness,
    recipients: [alice, charlie],
  );
  await _sendUnauthorizedMembersAddedReplay(
    sender: bob,
    addedUser: dana,
    groupId: groupId,
    eventAt: createdAt.add(const Duration(minutes: 10)),
    directHarness: directHarness,
    recipients: [alice, charlie],
  );
  await Future<void>.delayed(const Duration(milliseconds: 250));

  await _expectGroupMetadata(
    user: alice,
    groupId: groupId,
    name: validName,
    description: validDescription,
    avatarBlobId: validAvatarBlobId,
    avatarMime: validAvatarMime,
  );
  await _expectGroupMetadata(
    user: charlie,
    groupId: groupId,
    name: validName,
    description: validDescription,
    avatarBlobId: validAvatarBlobId,
    avatarMime: validAvatarMime,
  );

  for (final user in [alice, bob, charlie]) {
    expect(
      await user.groupRepo.getMember(groupId, dana.peerId),
      isNull,
      reason: '${user.username} must not contain Dana',
    );
    expect(
      await _memberPeerIds(user: user, groupId: groupId),
      {alice.peerId, bob.peerId, charlie.peerId},
      reason: '${user.username} final active members',
    );
  }
  expect(await dana.groupRepo.getGroup(groupId), isNull);
}

Future<void> runExactScenario3PromotedAdminJourney() async {
  final network = FakeGroupPubSubNetwork();
  final directHarness = _DirectMembershipUpdateHarness();
  addTearDown(directHarness.dispose);

  const groupId = 'grp-exact-scenario-3-promoted-admin';
  const groupKeyEpoch = 1;
  final createdAt = DateTime.utc(2026, 5, 25, 18);

  final alice = GroupTestUser.create(
    peerId: 'user-a',
    deviceId: 'device-a',
    username: 'User A',
    network: network,
    downloadGroupAvatarFn: _fakeDownloadGroupAvatar,
  );
  final bob = GroupTestUser.create(
    peerId: 'user-b',
    deviceId: 'device-b',
    username: 'User B',
    network: network,
    downloadGroupAvatarFn: _fakeDownloadGroupAvatar,
  );
  final charlie = GroupTestUser.create(
    peerId: 'user-c',
    deviceId: 'device-c',
    username: 'User C',
    network: network,
    downloadGroupAvatarFn: _fakeDownloadGroupAvatar,
  );
  addTearDown(() {
    alice.dispose();
    bob.dispose();
    charlie.dispose();
  });

  alice.start();
  bob.start();
  charlie.start();
  directHarness.attach(alice);
  directHarness.attach(bob);
  directHarness.attach(charlie);

  final aliceBobContact = _contactFor(bob, createdAt);
  final bobAliceContact = _contactFor(alice, createdAt);
  final bobCharlieContact = _contactFor(charlie, createdAt);
  final charlieBobContact = _contactFor(bob, createdAt);
  expect(aliceBobContact.peerId, bob.peerId, reason: 'A and B are friends');
  expect(bobAliceContact.peerId, alice.peerId, reason: 'B and A are friends');
  expect(
    bobCharlieContact.peerId,
    charlie.peerId,
    reason: 'B and C are friends',
  );
  expect(charlieBobContact.peerId, bob.peerId, reason: 'C and B are friends');

  await alice.createGroup(groupId: groupId, name: 'test', createdAt: createdAt);
  await _saveKey(user: alice, groupId: groupId, epoch: groupKeyEpoch);

  await _inviteAndAcceptViaPendingFlow(
    inviter: alice,
    invitee: bob,
    groupId: groupId,
    joinedAt: createdAt.add(const Duration(minutes: 1)),
    inviteReceivedAt: createdAt.add(const Duration(minutes: 1, seconds: 10)),
    directHarness: directHarness,
  );

  await alice.sendGroupMessage(
    groupId: groupId,
    text: 'A and B can chat',
    messageId: 'scenario3-a-b-chat',
    timestamp: createdAt.add(const Duration(minutes: 2)),
  );
  await bob.sendGroupMessage(
    groupId: groupId,
    text: 'B and A can chat',
    messageId: 'scenario3-b-a-chat',
    timestamp: createdAt.add(const Duration(minutes: 2, seconds: 30)),
  );
  await _waitUntil(() async {
    final aliceMessages = await alice.loadGroupMessages(groupId);
    final bobMessages = await bob.loadGroupMessages(groupId);
    return aliceMessages.any((message) => message.text == 'B and A can chat') &&
        bobMessages.any((message) => message.text == 'A and B can chat');
  }, reason: 'A/B chat after B accepts invite');

  await _promoteBob(
    alice: alice,
    bob: bob,
    groupId: groupId,
    changedAt: createdAt.add(const Duration(minutes: 3)),
  );
  expect((await bob.groupRepo.getGroup(groupId))?.myRole, GroupRole.admin);
  expect(
    (await bob.groupRepo.getMember(groupId, bob.peerId))?.role,
    MemberRole.admin,
  );

  await _updateMetadataAndReplay(
    sender: bob,
    groupId: groupId,
    name: 'test me',
    description: 'do you see me?',
    avatarBlobId: 'blob-scenario3-by-b',
    avatarMime: 'image/jpeg',
    avatarPath: 'media/group_avatars/$groupId.jpg',
    changedAt: createdAt.add(const Duration(minutes: 4)),
    directHarness: directHarness,
    recipients: [alice],
  );

  Future<bool> aliceSeesBobMetadata() async {
    final group = await alice.groupRepo.getGroup(groupId);
    return group?.name == 'test me' &&
        group?.description == 'do you see me?' &&
        group?.avatarBlobId == 'blob-scenario3-by-b' &&
        group?.avatarMime == 'image/jpeg' &&
        group?.avatarPath == 'media/group_avatars/$groupId.jpg';
  }

  await _waitUntil(
    aliceSeesBobMetadata,
    reason: 'bug-1 A receives B metadata and photo update',
  );

  await _inviteAndAcceptViaPendingFlow(
    inviter: bob,
    invitee: charlie,
    groupId: groupId,
    joinedAt: createdAt.add(const Duration(minutes: 5)),
    inviteReceivedAt: createdAt.add(const Duration(minutes: 5, seconds: 10)),
    directHarness: directHarness,
    existingRecipientsForMembershipReplay: [alice],
  );

  await _waitUntil(() async {
    final aliceSeesCharlie = await alice.groupRepo.getMember(
      groupId,
      charlie.peerId,
    );
    final charlieGroup = await charlie.groupRepo.getGroup(groupId);
    return aliceSeesCharlie != null &&
        charlieGroup?.name == 'test me' &&
        charlieGroup?.description == 'do you see me?' &&
        charlieGroup?.avatarBlobId == 'blob-scenario3-by-b' &&
        charlieGroup?.avatarMime == 'image/jpeg' &&
        charlieGroup?.avatarPath == 'media/group_avatars/$groupId.jpg';
  }, reason: 'C accepts with latest metadata/photo and A learns C');

  expect(await _memberPeerIds(user: charlie, groupId: groupId), {
    alice.peerId,
    bob.peerId,
    charlie.peerId,
  });

  final (aliceSendResult, _) = await alice.sendGroupMessageViaBridge(
    groupId: groupId,
    text: 'from A to B and C',
    messageId: 'scenario3-from-a-to-b-c',
    timestamp: createdAt.add(const Duration(minutes: 6)),
  );
  expect(aliceSendResult.name, 'success');
  expect(
    _inboxStoreRecipientPeerIdsForMessage(alice, 'scenario3-from-a-to-b-c'),
    containsAll([bob.peerId, charlie.peerId]),
  );

  final (bobSendResult, _) = await bob.sendGroupMessageViaBridge(
    groupId: groupId,
    text: 'from B to A and C',
    messageId: 'scenario3-from-b-to-a-c',
    timestamp: createdAt.add(const Duration(minutes: 7)),
  );
  expect(bobSendResult.name, 'success');
  expect(
    _inboxStoreRecipientPeerIdsForMessage(bob, 'scenario3-from-b-to-a-c'),
    containsAll([alice.peerId, charlie.peerId]),
  );

  final (charlieSendResult, _) = await charlie.sendGroupMessageViaBridge(
    groupId: groupId,
    text: 'from C to A and B',
    messageId: 'scenario3-from-c-to-a-b',
    timestamp: createdAt.add(const Duration(minutes: 8)),
  );
  expect(charlieSendResult.name, 'success');
  final charlieRecipients = _inboxStoreRecipientPeerIdsForMessage(
    charlie,
    'scenario3-from-c-to-a-b',
  );
  expect(charlieRecipients, containsAll([alice.peerId, bob.peerId]));
  expect(charlieRecipients, isNot(contains(charlie.peerId)));

  await _waitUntil(() async {
    final aliceMessages = await alice.loadGroupMessages(groupId);
    final bobMessages = await bob.loadGroupMessages(groupId);
    final charlieMessages = await charlie.loadGroupMessages(groupId);
    return aliceMessages.any(
          (message) => message.text == 'from B to A and C',
        ) &&
        aliceMessages.any((message) => message.text == 'from C to A and B') &&
        bobMessages.any((message) => message.text == 'from A to B and C') &&
        bobMessages.any((message) => message.text == 'from C to A and B') &&
        charlieMessages.any((message) => message.text == 'from A to B and C') &&
        charlieMessages.any((message) => message.text == 'from B to A and C');
  }, reason: 'bug-2 C message reaches A and B, and A/B reach all peers');

  await _updateMetadataAndReplay(
    sender: alice,
    groupId: groupId,
    name: 'test me',
    description: 'do you see me?',
    avatarBlobId: 'blob-scenario3-by-a',
    avatarMime: 'image/jpeg',
    avatarPath: 'media/group_avatars/$groupId.jpg',
    changedAt: createdAt.add(const Duration(minutes: 9)),
    directHarness: directHarness,
    recipients: [bob, charlie],
  );

  await _waitUntil(() async {
    final aliceGroup = await alice.groupRepo.getGroup(groupId);
    final charlieGroup = await charlie.groupRepo.getGroup(groupId);
    return aliceGroup?.avatarBlobId == 'blob-scenario3-by-a' &&
        aliceGroup?.avatarMime == 'image/jpeg' &&
        charlieGroup?.avatarBlobId == 'blob-scenario3-by-a' &&
        charlieGroup?.avatarMime == 'image/jpeg' &&
        charlieGroup?.avatarPath == 'media/group_avatars/$groupId.jpg';
  }, reason: 'bug-3 A photo update is visible to A and C');
}

Future<void> runPromotedAdminRecoverySaveConvergenceScenario() async {
  groupRecoveryGate.resetForTest();
  addTearDown(groupRecoveryGate.resetForTest);

  final network = FakeGroupPubSubNetwork();
  final directHarness = _DirectMembershipUpdateHarness();
  addTearDown(directHarness.dispose);

  const groupId = 'grp-promoted-admin-recovery-save';
  const groupKeyEpoch = 1;
  final createdAt = DateTime.utc(2026, 5, 25, 23);
  const savedName = 'after recovery details';
  const savedDescription = 'all members see this after recovery clears';
  const savedAvatarBlobId = 'blob-recovery-save-by-c';
  const savedAvatarMime = 'image/jpeg';
  const savedAvatarPath = 'media/group_avatars/$groupId.jpg';

  final alice = GroupTestUser.create(
    peerId: 'recovery-user-a',
    deviceId: 'recovery-device-a',
    username: 'User A',
    network: network,
  );
  final bob = GroupTestUser.create(
    peerId: 'recovery-user-b',
    deviceId: 'recovery-device-b',
    username: 'User B',
    network: network,
  );
  final charlie = GroupTestUser.create(
    peerId: 'recovery-user-c',
    deviceId: 'recovery-device-c',
    username: 'User C',
    network: network,
  );
  addTearDown(() {
    alice.dispose();
    bob.dispose();
    charlie.dispose();
  });

  alice.start();
  bob.start();
  charlie.start();
  directHarness.attach(alice);
  directHarness.attach(bob);
  directHarness.attach(charlie);

  final aliceBobContact = _contactFor(bob, createdAt);
  final bobCharlieContact = _contactFor(charlie, createdAt);
  expect(aliceBobContact.peerId, bob.peerId, reason: 'A and B are friends');
  expect(
    bobCharlieContact.peerId,
    charlie.peerId,
    reason: 'B and C are friends',
  );
  expect(alice.peerId, isNot(charlie.peerId), reason: 'A and C are distinct');

  await alice.createGroup(groupId: groupId, name: 'test', createdAt: createdAt);
  await _saveKey(user: alice, groupId: groupId, epoch: groupKeyEpoch);

  await _inviteAndAcceptViaPendingFlow(
    inviter: alice,
    invitee: bob,
    groupId: groupId,
    joinedAt: createdAt.add(const Duration(minutes: 1)),
    inviteReceivedAt: createdAt.add(const Duration(minutes: 1, seconds: 10)),
    directHarness: directHarness,
  );

  await _promoteBob(
    alice: alice,
    bob: bob,
    groupId: groupId,
    changedAt: createdAt.add(const Duration(minutes: 2)),
  );

  await _inviteAndAcceptViaPendingFlow(
    inviter: bob,
    invitee: charlie,
    groupId: groupId,
    joinedAt: createdAt.add(const Duration(minutes: 3)),
    inviteReceivedAt: createdAt.add(const Duration(minutes: 3, seconds: 10)),
    directHarness: directHarness,
    existingRecipientsForMembershipReplay: [alice],
  );
  await _waitUntil(() async {
    final aliceSeesCharlie = await alice.groupRepo.getMember(
      groupId,
      charlie.peerId,
    );
    final charlieGroup = await charlie.groupRepo.getGroup(groupId);
    return aliceSeesCharlie != null && charlieGroup?.name == 'test';
  }, reason: 'C joins via promoted B and A learns C');

  await alice.updateMemberRole(
    groupId: groupId,
    memberPeerId: charlie.peerId,
    role: MemberRole.admin,
    changedAt: createdAt.add(const Duration(minutes: 4)),
  );
  await _waitUntil(() async {
    final aliceCharlie = await alice.groupRepo.getMember(
      groupId,
      charlie.peerId,
    );
    final bobCharlie = await bob.groupRepo.getMember(groupId, charlie.peerId);
    final charlieGroup = await charlie.groupRepo.getGroup(groupId);
    final charlieSelf = await charlie.groupRepo.getMember(
      groupId,
      charlie.peerId,
    );
    return aliceCharlie?.role == MemberRole.admin &&
        bobCharlie?.role == MemberRole.admin &&
        charlieGroup?.myRole == GroupRole.admin &&
        charlieSelf?.role == MemberRole.admin;
  }, reason: 'C admin promotion converges');

  groupRecoveryGate.begin();
  try {
    await expectLater(
      charlie.updateMetadata(
        groupId: groupId,
        name: 'blocked local name',
        description: 'blocked local description',
        avatarBlobId: 'blob-blocked-local-only',
        avatarMime: savedAvatarMime,
        avatarPath: savedAvatarPath,
        changedAt: createdAt.add(const Duration(minutes: 5)),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          groupRecoveryPendingError,
        ),
      ),
    );
  } finally {
    groupRecoveryGate.end();
  }

  for (final user in [alice, bob, charlie]) {
    final group = await user.groupRepo.getGroup(groupId);
    expect(group?.name, 'test', reason: '${user.username} blocked name');
    expect(
      group?.description,
      isNull,
      reason: '${user.username} blocked description',
    );
    expect(
      group?.avatarBlobId,
      isNull,
      reason: '${user.username} blocked avatar',
    );
  }

  await charlie.updateMetadata(
    groupId: groupId,
    name: savedName,
    description: savedDescription,
    avatarBlobId: savedAvatarBlobId,
    avatarMime: savedAvatarMime,
    avatarPath: savedAvatarPath,
    changedAt: createdAt.add(const Duration(minutes: 6)),
  );

  await _waitUntil(() async {
    final aliceGroup = await alice.groupRepo.getGroup(groupId);
    final bobGroup = await bob.groupRepo.getGroup(groupId);
    return aliceGroup?.name == savedName &&
        aliceGroup?.description == savedDescription &&
        aliceGroup?.avatarBlobId == savedAvatarBlobId &&
        bobGroup?.name == savedName &&
        bobGroup?.description == savedDescription &&
        bobGroup?.avatarBlobId == savedAvatarBlobId;
  }, reason: 'C post-recovery metadata/photo reaches A and B');

  for (final user in [alice, bob, charlie]) {
    await _expectGroupMetadata(
      user: user,
      groupId: groupId,
      name: savedName,
      description: savedDescription,
      avatarBlobId: savedAvatarBlobId,
      avatarMime: savedAvatarMime,
    );
    expect(
      await _memberPeerIds(user: user, groupId: groupId),
      {alice.peerId, bob.peerId, charlie.peerId},
      reason: '${user.username} final members',
    );
  }
}

Future<void> runGroupAdminMetadataConvergenceScenario({
  GroupAdminMetadataMemberAdder charlieAdder =
      GroupAdminMetadataMemberAdder.alice,
}) async {
  final network = FakeGroupPubSubNetwork();

  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 50));

  Future<void> waitUntil(
    Future<bool> Function() condition, {
    String reason = 'condition',
  }) async {
    for (var i = 0; i < 40; i++) {
      if (await condition()) return;
      await pump();
    }
    fail('Timed out waiting for $reason');
  }

  const groupId = 'grp-admin-metadata-convergence';
  final createdAt = DateTime.utc(2026, 5, 25, 10);

  final alice = GroupTestUser.create(
    peerId: 'peer-a',
    deviceId: 'device-a',
    username: 'User A',
    network: network,
  );
  final bob = GroupTestUser.create(
    peerId: 'peer-b',
    deviceId: 'device-b',
    username: 'User B',
    network: network,
  );
  final charlie = GroupTestUser.create(
    peerId: 'peer-c',
    deviceId: 'device-c',
    username: 'User C',
    network: network,
  );
  addTearDown(() {
    alice.dispose();
    bob.dispose();
    charlie.dispose();
  });

  alice.start();
  bob.start();
  charlie.start();

  await alice.createGroup(groupId: groupId, name: 'test', createdAt: createdAt);
  await alice.addMember(
    groupId: groupId,
    invitee: bob,
    joinedAt: createdAt.add(const Duration(minutes: 1)),
  );

  await alice.updateMetadata(
    groupId: groupId,
    name: 'test me',
    description: 'do you see me?',
    changedAt: createdAt.add(const Duration(minutes: 2)),
  );
  await waitUntil(() async {
    final group = await bob.groupRepo.getGroup(groupId);
    return group?.name == 'test me' && group?.description == 'do you see me?';
  }, reason: 'Bob metadata update');

  await alice.updateMemberRole(
    groupId: groupId,
    memberPeerId: bob.peerId,
    role: MemberRole.admin,
    changedAt: createdAt.add(const Duration(minutes: 3)),
  );
  await waitUntil(() async {
    final group = await bob.groupRepo.getGroup(groupId);
    final member = await bob.groupRepo.getMember(groupId, bob.peerId);
    return group?.myRole == GroupRole.admin && member?.role == MemberRole.admin;
  }, reason: 'Bob admin promotion');

  final addingAdmin = switch (charlieAdder) {
    GroupAdminMetadataMemberAdder.alice => alice,
    GroupAdminMetadataMemberAdder.bob => bob,
  };
  await addingAdmin.addMember(
    groupId: groupId,
    invitee: charlie,
    joinedAt: createdAt.add(const Duration(minutes: 4)),
  );
  await addingAdmin.broadcastMemberAdded(
    groupId: groupId,
    newMember: charlie,
    eventAt: createdAt.add(const Duration(minutes: 4)),
  );
  await waitUntil(() async {
    final aliceSeesCharlie = await alice.groupRepo.getMember(
      groupId,
      charlie.peerId,
    );
    final bobSeesCharlie = await bob.groupRepo.getMember(
      groupId,
      charlie.peerId,
    );
    final charlieGroup = await charlie.groupRepo.getGroup(groupId);
    return aliceSeesCharlie != null &&
        bobSeesCharlie != null &&
        charlieGroup?.name == 'test me' &&
        charlieGroup?.description == 'do you see me?';
  }, reason: 'Charlie membership and metadata convergence');

  await alice.sendGroupMessage(
    groupId: groupId,
    text: 'from A',
    messageId: 'msg-from-a',
    timestamp: createdAt.add(const Duration(minutes: 5)),
  );
  await bob.sendGroupMessage(
    groupId: groupId,
    text: 'from B',
    messageId: 'msg-from-b',
    timestamp: createdAt.add(const Duration(minutes: 6)),
  );
  await charlie.sendGroupMessage(
    groupId: groupId,
    text: 'from C',
    messageId: 'msg-from-c',
    timestamp: createdAt.add(const Duration(minutes: 7)),
  );

  await waitUntil(() async {
    final aliceMessages = await alice.loadGroupMessages(groupId);
    final bobMessages = await bob.loadGroupMessages(groupId);
    final charlieMessages = await charlie.loadGroupMessages(groupId);
    return aliceMessages.any((message) => message.text == 'from B') &&
        aliceMessages.any((message) => message.text == 'from C') &&
        bobMessages.any((message) => message.text == 'from A') &&
        bobMessages.any((message) => message.text == 'from C') &&
        charlieMessages.any((message) => message.text == 'from A') &&
        charlieMessages.any((message) => message.text == 'from B');
  }, reason: 'three-way group message fanout');

  await alice.updateMetadata(
    groupId: groupId,
    name: 'test me',
    description: 'do you see me?',
    avatarBlobId: 'blob-group-photo-2',
    avatarMime: 'image/jpeg',
    avatarPath: 'media/group_avatars/$groupId.jpg',
    changedAt: createdAt.add(const Duration(minutes: 8)),
  );
  await waitUntil(() async {
    final bobGroup = await bob.groupRepo.getGroup(groupId);
    final charlieGroup = await charlie.groupRepo.getGroup(groupId);
    return bobGroup?.avatarBlobId == 'blob-group-photo-2' &&
        bobGroup?.avatarMime == 'image/jpeg' &&
        charlieGroup?.avatarBlobId == 'blob-group-photo-2' &&
        charlieGroup?.avatarMime == 'image/jpeg';
  }, reason: 'avatar metadata convergence');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Group admin metadata convergence', () {
    setUp(groupRecoveryGate.resetForTest);
    tearDown(groupRecoveryGate.resetForTest);

    test(
      groupAdminMetadataConvergenceLabel,
      runGroupAdminMetadataConvergenceScenario,
    );

    test(promotedAdminAddsMemberConvergenceLabel, () {
      return runGroupAdminMetadataConvergenceScenario(
        charlieAdder: GroupAdminMetadataMemberAdder.bob,
      );
    });

    test(
      exactScenario3PromotedAdminJourneyLabel,
      runExactScenario3PromotedAdminJourney,
    );

    test(
      exactScenario4AdminDemotionEnforcementLabel,
      runExactScenario4AdminDemotionEnforcementJourney,
    );

    test(
      promotedAdminRecoverySaveConvergenceLabel,
      runPromotedAdminRecoverySaveConvergenceScenario,
    );

    test(
      'group_snapshot_contains_photo_fetch_and_encryption_metadata',
      () async {
        final network = FakeGroupPubSubNetwork();
        const groupId = 'grp-photo-snapshot-metadata';
        const photoBlobId = 'blob-photo-before-c';
        const photoMime = 'image/jpeg';
        const epoch = 1;
        final createdAt = DateTime.utc(2026, 5, 25, 10);
        final photoUpdatedAt = createdAt.add(const Duration(minutes: 2));

        final alice = GroupTestUser.create(
          peerId: 'peer-photo-a',
          deviceId: 'device-photo-a',
          username: 'User A',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-photo-b',
          deviceId: 'device-photo-b',
          username: 'User B',
          network: network,
          downloadGroupAvatarFn: _fakeDownloadGroupAvatar,
        );
        final charlieAvatarFetches = <Map<String, String>>[];
        late final GroupTestUser charlie;
        charlie = GroupTestUser.create(
          peerId: 'peer-photo-c',
          deviceId: 'device-photo-c',
          username: 'User C',
          network: network,
          downloadGroupAvatarFn:
              ({
                required bridge,
                required String groupId,
                required String blobId,
              }) async {
                expect(bridge, same(charlie.bridge));
                charlieAvatarFetches.add({
                  'groupId': groupId,
                  'blobId': blobId,
                });
                return 'media/group_avatars/$groupId.jpg';
              },
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        alice.start();
        bob.start();
        charlie.start();

        await alice.createGroup(
          groupId: groupId,
          name: 'Photo Snapshot',
          createdAt: createdAt,
        );
        await _saveKey(user: alice, groupId: groupId, epoch: epoch);
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        );
        await _saveKey(user: bob, groupId: groupId, epoch: epoch);

        await alice.updateMetadata(
          groupId: groupId,
          name: 'Photo Snapshot',
          description: 'Photo exists before C joins',
          avatarBlobId: photoBlobId,
          avatarMime: photoMime,
          avatarPath: 'media/group_avatars/$groupId.jpg',
          changedAt: photoUpdatedAt,
        );
        await _waitUntil(() async {
          final bobGroup = await bob.groupRepo.getGroup(groupId);
          return bobGroup?.avatarBlobId == photoBlobId &&
              bobGroup?.avatarMime == photoMime &&
              bobGroup?.lastMetadataEventAt == photoUpdatedAt;
        }, reason: 'Bob receives pre-join photo metadata');

        final snapshotForCharlie = await _buildSnapshot(
          user: bob,
          groupId: groupId,
        );
        _expectPhotoSnapshot(
          snapshotForCharlie,
          groupId: groupId,
          blobId: photoBlobId,
          mime: photoMime,
          updatedAt: photoUpdatedAt,
        );
        expect(snapshotForCharlie['createdBy'], alice.peerId);
        expect(
          (snapshotForCharlie['members'] as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .map((member) => member['peerId']),
          containsAll([alice.peerId, bob.peerId]),
        );

        await bob.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt.add(const Duration(minutes: 3)),
        );
        expect(charlieAvatarFetches, [
          {'groupId': groupId, 'blobId': photoBlobId},
        ]);
        await _saveKey(user: charlie, groupId: groupId, epoch: epoch);
        final charlieGroup = await charlie.groupRepo.getGroup(groupId);
        expect(charlieGroup, isNotNull);
        expect(charlieGroup!.avatarBlobId, photoBlobId);
        expect(charlieGroup.avatarMime, photoMime);
        expect(charlieGroup.avatarPath, 'media/group_avatars/$groupId.jpg');
        await _waitUntil(() async {
          final reloadedCharlieGroup = await charlie.groupRepo.getGroup(
            groupId,
          );
          return reloadedCharlieGroup?.avatarBlobId == photoBlobId &&
              reloadedCharlieGroup?.avatarMime == photoMime &&
              reloadedCharlieGroup?.avatarPath ==
                  'media/group_avatars/$groupId.jpg';
        }, reason: 'Charlie receives photo snapshot');

        final charlieKey = await charlie.groupRepo.getLatestKey(groupId);
        expect(charlieKey?.keyGeneration, epoch);
      },
    );

    test('promoted_admin_can_update_all_group_metadata_fields', () async {
      final network = FakeGroupPubSubNetwork();
      const groupId = 'grp-promoted-admin-all-metadata';
      final createdAt = DateTime.utc(2026, 5, 25, 11);
      final promotedAt = createdAt.add(const Duration(minutes: 2));
      final metadataAt = createdAt.add(const Duration(minutes: 3));

      final alice = GroupTestUser.create(
        peerId: 'peer-meta-a',
        deviceId: 'device-meta-a',
        username: 'User A',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'peer-meta-b',
        deviceId: 'device-meta-b',
        username: 'User B',
        network: network,
      );
      final charlie = GroupTestUser.create(
        peerId: 'peer-meta-c',
        deviceId: 'device-meta-c',
        username: 'User C',
        network: network,
      );
      final diana = GroupTestUser.create(
        peerId: 'peer-meta-d',
        deviceId: 'device-meta-d',
        username: 'User D',
        network: network,
      );
      addTearDown(() {
        alice.dispose();
        bob.dispose();
        charlie.dispose();
        diana.dispose();
      });

      alice.start();
      bob.start();
      charlie.start();
      diana.start();

      await alice.createGroup(
        groupId: groupId,
        name: 'Before',
        createdAt: createdAt,
      );
      await alice.addMember(
        groupId: groupId,
        invitee: bob,
        joinedAt: createdAt.add(const Duration(minutes: 1)),
      );
      await alice.addMember(
        groupId: groupId,
        invitee: charlie,
        joinedAt: createdAt.add(const Duration(minutes: 1, seconds: 30)),
      );
      await _promoteBob(
        alice: alice,
        bob: bob,
        groupId: groupId,
        changedAt: promotedAt,
      );

      await bob.updateMetadata(
        groupId: groupId,
        name: 'After Bob',
        description: 'Bob changed every metadata field',
        avatarBlobId: 'blob-promoted-admin-photo',
        avatarMime: 'image/jpeg',
        avatarPath: 'media/group_avatars/$groupId.jpg',
        changedAt: metadataAt,
      );

      Future<bool> hasAllMetadata(GroupTestUser user) async {
        final group = await user.groupRepo.getGroup(groupId);
        return group?.name == 'After Bob' &&
            group?.description == 'Bob changed every metadata field' &&
            group?.avatarBlobId == 'blob-promoted-admin-photo' &&
            group?.avatarMime == 'image/jpeg' &&
            group?.lastMetadataEventAt == metadataAt;
      }

      await _waitUntil(() => hasAllMetadata(alice), reason: 'A gets updates');
      await _waitUntil(() => hasAllMetadata(charlie), reason: 'C gets updates');

      await bob.addMember(
        groupId: groupId,
        invitee: diana,
        joinedAt: createdAt.add(const Duration(minutes: 4)),
      );
      final dianaGroup = await diana.groupRepo.getGroup(groupId);
      expect(dianaGroup, isNotNull);
      expect(dianaGroup!.name, 'After Bob');
      expect(dianaGroup.description, 'Bob changed every metadata field');
      expect(dianaGroup.avatarBlobId, 'blob-promoted-admin-photo');
      expect(dianaGroup.avatarMime, 'image/jpeg');
      expect(dianaGroup.avatarPath, 'media/group_avatars/$groupId.jpg');
    });

    test('creator_learns_about_member_invited_by_promoted_admin', () async {
      final network = FakeGroupPubSubNetwork();
      const groupId = 'grp-creator-learns-promoted-admin-invite';
      final createdAt = DateTime.utc(2026, 5, 25, 12);

      final alice = GroupTestUser.create(
        peerId: 'peer-learn-a',
        deviceId: 'device-learn-a',
        username: 'User A',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'peer-learn-b',
        deviceId: 'device-learn-b',
        username: 'User B',
        network: network,
      );
      final charlie = GroupTestUser.create(
        peerId: 'peer-learn-c',
        deviceId: 'device-learn-c',
        username: 'User C',
        network: network,
      );
      addTearDown(() {
        alice.dispose();
        bob.dispose();
        charlie.dispose();
      });

      alice.start();
      bob.start();
      charlie.start();

      await alice.createGroup(
        groupId: groupId,
        name: 'Creator Learns',
        createdAt: createdAt,
      );
      await alice.addMember(
        groupId: groupId,
        invitee: bob,
        joinedAt: createdAt.add(const Duration(minutes: 1)),
      );
      await _promoteBob(
        alice: alice,
        bob: bob,
        groupId: groupId,
        changedAt: createdAt.add(const Duration(minutes: 2)),
      );

      await bob.addMember(
        groupId: groupId,
        invitee: charlie,
        joinedAt: createdAt.add(const Duration(minutes: 3)),
      );
      await bob.broadcastMemberAdded(
        groupId: groupId,
        newMember: charlie,
        eventAt: createdAt.add(const Duration(minutes: 3)),
      );
      await _waitUntil(() async {
        return (await _memberPeerIds(
          user: alice,
          groupId: groupId,
        )).contains(charlie.peerId);
      }, reason: 'creator learns C membership');

      await charlie.sendGroupMessage(
        groupId: groupId,
        text: 'C can speak to creator',
        messageId: 'msg-c-to-a-after-b-invite',
        timestamp: createdAt.add(const Duration(minutes: 4)),
      );
      await _waitUntil(() async {
        final aliceMessages = await alice.loadGroupMessages(groupId);
        return aliceMessages.any(
          (message) =>
              message.senderPeerId == charlie.peerId &&
              message.text == 'C can speak to creator',
        );
      }, reason: 'A accepts inbound group message from C');

      final aliceSnapshot = await _buildSnapshot(user: alice, groupId: groupId);
      expect(
        isGroupConfigStateHashValid(
          groupId: groupId,
          groupConfig: aliceSnapshot,
        ),
        isTrue,
      );
      final members = aliceSnapshot['members'] as List<dynamic>;
      expect(
        members.whereType<Map<String, dynamic>>().map(
          (member) => member['peerId'],
        ),
        contains(charlie.peerId),
      );
      final charlieMember = await alice.groupRepo.getMember(
        groupId,
        charlie.peerId,
      );
      expect(charlieMember, isNotNull);
      expect(charlieMember!.publicKey, charlie.publicKey);
      expect(charlieMember.devices.map((device) => device.deviceId), [
        charlie.deviceId,
      ]);
    });

    test('photo_update_authorization_uses_admin_set_not_creator_id', () async {
      final network = FakeGroupPubSubNetwork();
      const groupId = 'grp-photo-auth-admin-set';
      final createdAt = DateTime.utc(2026, 5, 25, 13);
      final photoAt = createdAt.add(const Duration(minutes: 3));

      final alice = GroupTestUser.create(
        peerId: 'peer-photo-auth-a',
        deviceId: 'device-photo-auth-a',
        username: 'User A',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'peer-photo-auth-b',
        deviceId: 'device-photo-auth-b',
        username: 'User B',
        network: network,
      );
      final charlie = GroupTestUser.create(
        peerId: 'peer-photo-auth-c',
        deviceId: 'device-photo-auth-c',
        username: 'User C',
        network: network,
      );
      addTearDown(() {
        alice.dispose();
        bob.dispose();
        charlie.dispose();
      });

      alice.start();
      bob.start();
      charlie.start();

      await alice.createGroup(
        groupId: groupId,
        name: 'Photo Auth',
        createdAt: createdAt,
      );
      await alice.addMember(
        groupId: groupId,
        invitee: bob,
        joinedAt: createdAt.add(const Duration(minutes: 1)),
      );
      await alice.addMember(
        groupId: groupId,
        invitee: charlie,
        joinedAt: createdAt.add(const Duration(minutes: 1, seconds: 30)),
      );
      await _promoteBob(
        alice: alice,
        bob: bob,
        groupId: groupId,
        changedAt: createdAt.add(const Duration(minutes: 2)),
      );

      final bobGroupBefore = await bob.groupRepo.getGroup(groupId);
      expect(bobGroupBefore, isNotNull);
      expect(bobGroupBefore!.createdBy, isNot(bob.peerId));
      expect(bobGroupBefore.myRole, GroupRole.admin);

      await bob.updateMetadata(
        groupId: groupId,
        name: 'Photo Auth',
        description: 'Updated by promoted admin',
        avatarBlobId: 'blob-photo-by-bob',
        avatarMime: 'image/jpeg',
        avatarPath: 'media/group_avatars/$groupId.jpg',
        changedAt: photoAt,
      );

      Future<bool> hasPhoto(GroupTestUser user) async {
        final group = await user.groupRepo.getGroup(groupId);
        return group?.avatarBlobId == 'blob-photo-by-bob' &&
            group?.avatarMime == 'image/jpeg' &&
            group?.lastMetadataEventAt == photoAt;
      }

      await _waitUntil(() => hasPhoto(alice), reason: 'A receives photo');
      await _waitUntil(() => hasPhoto(charlie), reason: 'C receives photo');
    });

    test(
      'promoted_admin_invited_member_receives_latest_group_photo_snapshot',
      () async {
        final network = FakeGroupPubSubNetwork();
        const groupId = 'grp-promoted-admin-photo-snapshot';
        final createdAt = DateTime.utc(2026, 5, 25, 14);
        final photoAt = createdAt.add(const Duration(minutes: 3));

        final alice = GroupTestUser.create(
          peerId: 'peer-photo-snapshot-a',
          deviceId: 'device-photo-snapshot-a',
          username: 'User A',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-photo-snapshot-b',
          deviceId: 'device-photo-snapshot-b',
          username: 'User B',
          network: network,
          downloadGroupAvatarFn: _fakeDownloadGroupAvatar,
        );
        final charlieAvatarFetches = <Map<String, String>>[];
        late final GroupTestUser charlie;
        charlie = GroupTestUser.create(
          peerId: 'peer-photo-snapshot-c',
          deviceId: 'device-photo-snapshot-c',
          username: 'User C',
          network: network,
          downloadGroupAvatarFn:
              ({
                required bridge,
                required String groupId,
                required String blobId,
              }) async {
                expect(bridge, same(charlie.bridge));
                charlieAvatarFetches.add({
                  'groupId': groupId,
                  'blobId': blobId,
                });
                return 'media/group_avatars/$groupId.jpg';
              },
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        alice.start();
        bob.start();
        charlie.start();

        await alice.createGroup(
          groupId: groupId,
          name: 'Photo Snapshot',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        );
        await _promoteBob(
          alice: alice,
          bob: bob,
          groupId: groupId,
          changedAt: createdAt.add(const Duration(minutes: 2)),
        );
        await alice.updateMetadata(
          groupId: groupId,
          name: 'Photo Snapshot',
          description: 'Existing photo',
          avatarBlobId: 'blob-existing-before-c',
          avatarMime: 'image/jpeg',
          avatarPath: 'media/group_avatars/$groupId.jpg',
          changedAt: photoAt,
        );
        await _waitUntil(() async {
          final bobGroup = await bob.groupRepo.getGroup(groupId);
          return bobGroup?.avatarBlobId == 'blob-existing-before-c';
        }, reason: 'B receives existing photo');

        await bob.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt.add(const Duration(minutes: 4)),
        );
        expect(charlieAvatarFetches, [
          {'groupId': groupId, 'blobId': 'blob-existing-before-c'},
        ]);

        final charlieGroup = await charlie.groupRepo.getGroup(groupId);
        expect(charlieGroup, isNotNull);
        expect(charlieGroup!.avatarBlobId, 'blob-existing-before-c');
        expect(charlieGroup.avatarMime, 'image/jpeg');
        expect(charlieGroup.avatarPath, 'media/group_avatars/$groupId.jpg');
      },
    );

    test(
      'member_invited_by_promoted_admin_can_send_to_all_group_members',
      () async {
        final network = FakeGroupPubSubNetwork();
        const groupId = 'grp-promoted-admin-invited-member-send';
        final createdAt = DateTime.utc(2026, 5, 25, 15);

        final alice = GroupTestUser.create(
          peerId: 'peer-send-a',
          deviceId: 'device-send-a',
          username: 'User A',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-send-b',
          deviceId: 'device-send-b',
          username: 'User B',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-send-c',
          deviceId: 'device-send-c',
          username: 'User C',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        alice.start();
        bob.start();
        charlie.start();

        await alice.createGroup(
          groupId: groupId,
          name: 'Promoted Send',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        );
        await _promoteBob(
          alice: alice,
          bob: bob,
          groupId: groupId,
          changedAt: createdAt.add(const Duration(minutes: 2)),
        );
        await bob.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt.add(const Duration(minutes: 3)),
        );
        await bob.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: createdAt.add(const Duration(minutes: 3)),
        );
        await _waitUntil(() async {
          return (await _memberPeerIds(
            user: alice,
            groupId: groupId,
          )).contains(charlie.peerId);
        }, reason: 'A learns C before C sends');

        await charlie.sendGroupMessage(
          groupId: groupId,
          text: 'C to everyone',
          messageId: 'msg-c-to-all-promoted-admin',
          timestamp: createdAt.add(const Duration(minutes: 4)),
        );

        await _waitUntil(() async {
          final aliceMessages = await alice.loadGroupMessages(groupId);
          final bobMessages = await bob.loadGroupMessages(groupId);
          return aliceMessages.any(
                (message) => message.text == 'C to everyone',
              ) &&
              bobMessages.any((message) => message.text == 'C to everyone');
        }, reason: 'C to A/B delivery succeeds');
      },
    );

    test(
      'promoted_admin_photo_update_reaches_creator_and_all_members',
      () async {
        final network = FakeGroupPubSubNetwork();
        const groupId = 'grp-promoted-admin-photo-fanout';
        final createdAt = DateTime.utc(2026, 5, 25, 16);
        final photoAt = createdAt.add(const Duration(minutes: 3));

        final alice = GroupTestUser.create(
          peerId: 'peer-photo-fanout-a',
          deviceId: 'device-photo-fanout-a',
          username: 'User A',
          network: network,
          downloadGroupAvatarFn: _fakeDownloadGroupAvatar,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-photo-fanout-b',
          deviceId: 'device-photo-fanout-b',
          username: 'User B',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-photo-fanout-c',
          deviceId: 'device-photo-fanout-c',
          username: 'User C',
          network: network,
          downloadGroupAvatarFn: _fakeDownloadGroupAvatar,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        alice.start();
        bob.start();
        charlie.start();

        await alice.createGroup(
          groupId: groupId,
          name: 'Photo Fanout',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt.add(const Duration(minutes: 1, seconds: 30)),
        );
        await _promoteBob(
          alice: alice,
          bob: bob,
          groupId: groupId,
          changedAt: createdAt.add(const Duration(minutes: 2)),
        );

        await bob.updateMetadata(
          groupId: groupId,
          name: 'Photo Fanout',
          description: 'Promoted admin photo fanout',
          avatarBlobId: 'blob-photo-fanout-by-b',
          avatarMime: 'image/jpeg',
          avatarPath: 'media/group_avatars/$groupId.jpg',
          changedAt: photoAt,
        );

        Future<bool> photoReached(GroupTestUser user) async {
          final group = await user.groupRepo.getGroup(groupId);
          return group?.avatarBlobId == 'blob-photo-fanout-by-b' &&
              group?.avatarMime == 'image/jpeg' &&
              group?.avatarPath == 'media/group_avatars/$groupId.jpg';
        }

        await _waitUntil(
          () => photoReached(alice),
          reason: 'creator receives promoted admin photo',
        );
        await _waitUntil(
          () => photoReached(charlie),
          reason: 'member receives promoted admin photo',
        );
      },
    );
  });
}
