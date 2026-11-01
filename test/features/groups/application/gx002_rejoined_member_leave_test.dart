import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/accept_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/change_group_member_role_and_broadcast_use_case.dart';
import 'package:flutter_app/features/groups/application/create_group_with_members_use_case.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_key_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_sender_device_binding.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/remove_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_wired.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_member_row.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_pending_group_invite_repository.dart';
import '../../../shared/helpers/durable_group_exit_surface_harness.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

// Each peer owns its persisted repositories and ordinary verified listener.
// The existing bridge fake supplies crypto only; transition admission and
// pre-state hashes are production code and are never overridden here.
class _Peer {
  _Peer(this.name) {
    final at = DateTime.now().toUtc().toIso8601String();
    identity = IdentityModel(
      peerId: 'peer-${name.toLowerCase()}',
      publicKey: 'pk-$name',
      privateKey: 'sk-$name',
      mnemonic12:
          'one two three four five six seven eight nine ten eleven twelve',
      mlKemPublicKey: 'mlkem-$name',
      mlKemSecretKey: 'mlkem-secret-$name',
      username: name,
      createdAt: at,
      updatedAt: at,
    );
    identities.seed(identity);
    bridge.responses['group:publish'] = {'ok': true, 'topicPeers': 2};
    bridge.responses['group:inboxRetrieveCursor'] = {
      'ok': true,
      'messages': <Object>[],
      'cursor': '',
    };
    listener = _newListener();
    keyListener = GroupKeyUpdateListener(
      groupKeyUpdateStream: const Stream<ChatMessage>.empty(),
      groupRepo: groups,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => identity.mlKemSecretKey,
      getOwnPeerId: () async => id,
      getOwnDeviceId: () async => id,
    );
  }

  final String name;
  late final IdentityModel identity;
  final identities = FakeIdentityRepository();
  final groups = InMemoryGroupRepository();
  final messages = InMemoryGroupMessageRepository();
  final invites = InMemoryPendingGroupInviteRepository();
  final contacts = FakeContactRepository();
  final bridge = PassthroughCryptoBridge();
  final p2p = FakeP2PService(initialState: const NodeState(isStarted: true));
  final process = forkIndependentGroupMembershipProcessZoneForTest();
  late GroupMessageListener listener;
  late final GroupKeyUpdateListener keyListener;
  Future<bool> Function(String groupId)? rotateAfterRemoteRemoval;

  String get id => identity.peerId;

  ContactModel get contact => ContactModel(
    peerId: id,
    publicKey: identity.publicKey,
    mlKemPublicKey: identity.mlKemPublicKey,
    username: name,
    rendezvous: '/dns4/relay.test/tcp/443/p2p/relay',
    signature: 'contact-$name',
    scannedAt: identity.createdAt,
  );

  GroupMessageListener _newListener() => GroupMessageListener(
    groupRepo: groups,
    msgRepo: messages,
    bridge: bridge,
    getSelfPeerId: () async => id,
    rotateGroupKeyAfterRemoteRemoval: (groupId) async =>
        await rotateAfterRemoteRemoval?.call(groupId) ?? false,
  );

  Future<void> restartListener() async {
    await listener.stop();
    listener.dispose();
    listener = _newListener();
  }

  Future<void> close() async {
    await listener.stop();
    listener.dispose();
    keyListener.dispose();
    p2p.dispose();
  }
}

Map<String, dynamic> _lastInboxEnvelope(_Peer sender) {
  final command = sender.bridge.sentMessages
      .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
      .lastWhere((message) => message['cmd'] == 'group:inboxStore');
  final payload = command['payload'] as Map<String, dynamic>;
  return jsonDecode(payload['message'] as String) as Map<String, dynamic>;
}

Future<void> _deliver(
  _Peer sender,
  _Peer receiver,
  String groupId,
  Map<String, dynamic> envelope, {
  DateTime? expectedSelfRemovalAt,
}) => receiver.process.run(() async {
  final previous = receiver.bridge.responses['group:inboxRetrieveCursor'];
  receiver.bridge.responses['group:inboxRetrieveCursor'] = {
    'ok': true,
    'messages': [
      {
        'from': sender.id,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'message': jsonEncode(envelope),
      },
    ],
    'cursor': '',
  };
  try {
    // Use the real inbox decoder as well as the verified listener: it carries
    // the authenticated envelope epoch into the system-message consumer when
    // a creator's key update overtakes the earlier removal notice.
    expect(
      await drainGroupOfflineInboxForGroup(
        bridge: receiver.bridge,
        groupRepo: receiver.groups,
        msgRepo: receiver.messages,
        groupMessageListener: receiver.listener,
        groupId: groupId,
        selfPeerId: receiver.id,
      ),
      expectedSelfRemovalAt == null,
    );
    if (expectedSelfRemovalAt != null) {
      // A verified self-removal retains history and intentionally stops drain.
      expect(
        (await receiver.groups.getGroup(groupId))!.selfRemovedAt,
        expectedSelfRemovalAt,
      );
      expect(await receiver.groups.getMember(groupId, receiver.id), isNull);
      expect(await receiver.groups.getLatestKey(groupId), isNull);
    }
  } finally {
    if (previous == null) {
      receiver.bridge.responses.remove('group:inboxRetrieveCursor');
    } else {
      receiver.bridge.responses['group:inboxRetrieveCursor'] = previous;
    }
  }
});

Future<RotateGroupKeyOutcome> _rotateAsPeer(
  _Peer sender,
  List<_Peer> peers,
  String groupId,
  List<({String recipient, int epoch})> keyDeliveries,
) async {
  final previous = (await sender.groups.getLatestKey(groupId))!;
  sender.bridge.responses['group:generateNextKey'] = {
    'ok': true,
    'groupKey': 'gx002-rotated-key-${previous.keyGeneration + 1}',
    'keyEpoch': previous.keyGeneration + 1,
  };
  final sent = <({String peerId, String content})>[];
  final outcome = await sender.process.run(
    () => rotateAndDistributeGroupKey(
      bridge: sender.bridge,
      groupRepo: sender.groups,
      groupId: groupId,
      selfPeerId: sender.id,
      senderPublicKey: sender.identity.publicKey,
      senderPrivateKey: sender.identity.privateKey,
      senderUsername: sender.name,
      sendP2PMessage: (peerId, content) async {
        final delivered = await sender.p2p.sendMessage(peerId, content);
        if (delivered) sent.add((peerId: peerId, content: content));
        return delivered;
      },
      storeP2PMessageInInbox: sender.p2p.storeInInbox,
    ),
  );
  // A successful P2P acknowledgement does not imply remote processing. Deliver
  // the producer's exact bytes after its local promotion, then await each
  // incumbent key consumer before completing the creator's callback.
  for (final message in sent) {
    final receiver = peers.singleWhere((peer) => peer.id == message.peerId);
    await receiver.process.run(
      () => receiver.keyListener.handleProtectedEnvelope(
        ChatMessage(
          from: sender.id,
          to: receiver.id,
          content: message.content,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        ),
      ),
    );
    expect(
      (await receiver.groups.getLatestKey(groupId))!.keyGeneration,
      outcome.key!.keyGeneration,
    );
    keyDeliveries.add((
      recipient: receiver.id,
      epoch: outcome.key!.keyGeneration,
    ));
  }
  return outcome;
}

Future<GroupInvitePayload> _acceptInvite(
  _Peer inviter,
  _Peer receiver,
  String groupId,
) => receiver.process.run(() async {
  final sent = inviter.p2p.sentMessageLog.lastWhere(
    (entry) => entry.peerId == receiver.id,
  );
  final outer = GroupInvitePayload.parseEncryptedEnvelope(sent.content)!;
  final encrypted = outer['encrypted'] as Map<String, dynamic>;
  // Inspect the actual producer's payload through the existing passthrough
  // crypto fixture, without changing its signed watermark or issuance time.
  final payload = GroupInvitePayload.fromInnerJson(
    encrypted['ciphertext'] as String,
  )!;
  final (stored, _) = await storeIncomingPendingGroupInvite(
    message: ChatMessage(
      from: inviter.id,
      to: receiver.id,
      content: sent.content,
      timestamp: DateTime.now().toUtc().toIso8601String(),
      isIncoming: true,
    ),
    groupRepo: receiver.groups,
    pendingInviteRepo: receiver.invites,
    contactRepo: receiver.contacts,
    bridge: receiver.bridge,
    ownPeerId: receiver.id,
    ownMlKemSecretKey: receiver.identity.mlKemSecretKey,
  );
  expect(stored, StorePendingGroupInviteResult.storedPending);
  final (accepted, group) = await acceptPendingGroupInvite(
    pendingInviteRepo: receiver.invites,
    groupRepo: receiver.groups,
    contactRepo: receiver.contacts,
    msgRepo: receiver.messages,
    bridge: receiver.bridge,
    groupMessageListener: receiver.listener,
    groupId: groupId,
    senderPeerId: receiver.id,
    senderPublicKey: receiver.identity.publicKey,
    senderPrivateKey: receiver.identity.privateKey,
    senderUsername: receiver.name,
  );
  expect(accepted, AcceptPendingGroupInviteResult.success);
  expect(group, isNotNull);
  return payload;
});

// Removal and picker re-add composition are widget-private on b06. Mirror only
// their public sign/publish/offline-store plumbing (GroupInfoWired._onRemoveMember
// and ContactPickerWired's members_added broadcast). The caller performs the real
// public mutation first and supplies its pre-mutation hash; the picker publishes
// at its later aggregate event time and commits that watermark below.
Future<Map<String, dynamic>> _publishUiMembershipTransition({
  required _Peer sender,
  required String groupId,
  required String kind,
  required String sourceId,
  required DateTime at,
  required String preStateHash,
  required Map<String, dynamic> subject,
  required List<String> recipients,
  String? replayMessageId,
}) async {
  final group = (await sender.groups.getGroup(groupId))!;
  final binding = await resolveGroupSenderDeviceBinding(
    groupRepo: sender.groups,
    groupId: groupId,
    senderPeerId: sender.id,
    senderPublicKey: sender.identity.publicKey,
  );
  final signed = await signGroupSystemTransitionPayload(
    bridge: sender.bridge,
    groupRepo: sender.groups,
    groupId: groupId,
    transitionType: kind,
    sourceEventId: sourceId,
    eventAt: at,
    actorPeerId: sender.id,
    actorUsername: sender.name,
    actorSigningPublicKey: sender.identity.publicKey,
    actorPrivateKey: sender.identity.privateKey,
    actorDeviceId: binding.deviceId,
    actorTransportPeerId: binding.transportPeerId,
    actorKeyPackageId: binding.keyPackageId,
    preTransitionStateHash: preStateHash,
    systemPayload: {
      '__sys': kind,
      ...subject,
      'groupConfig': buildGroupConfigPayload(
        group,
        await sender.groups.getMembers(groupId),
      ),
    },
  );
  final text = jsonEncode(signed);
  final result = await callGroupPublish(
    sender.bridge,
    groupId: groupId,
    text: text,
    senderPeerId: sender.id,
    senderPublicKey: sender.identity.publicKey,
    senderPrivateKey: sender.identity.privateKey,
    senderUsername: sender.name,
    senderDeviceId: binding.deviceId,
    senderTransportPeerId: binding.transportPeerId,
    senderDevicePublicKey: binding.devicePublicKey,
    senderKeyPackageId: binding.keyPackageId,
    messageId: sourceId,
    timestamp: kind == 'members_added' ? at : null,
  );
  expect(result['ok'], isTrue);
  if (kind == 'members_added') {
    // The picker commits the aggregate publication's time/id only after the
    // clean publish, not the earlier per-member persistence timestamp.
    await recordGroupMembershipEventWatermark(
      groupRepo: sender.groups,
      groupId: groupId,
      eventAt: at,
      eventId: sourceId,
    );
  }
  final envelope = await buildGroupOfflineReplayEnvelope(
    bridge: sender.bridge,
    groupRepo: sender.groups,
    groupId: groupId,
    payloadType: groupOfflineReplayPayloadTypeMessage,
    plaintext: jsonEncode({
      'groupId': groupId,
      'senderId': sender.id,
      'senderUsername': sender.name,
      if (binding.deviceId != null) 'senderDeviceId': binding.deviceId,
      if (binding.transportPeerId != null)
        'transportPeerId': binding.transportPeerId,
      'text': text,
      'messageId': sourceId,
      'timestamp': at.toIso8601String(),
    }),
    senderPeerId: sender.id,
    senderPublicKey: sender.identity.publicKey,
    senderPrivateKey: sender.identity.privateKey,
    senderDeviceId: binding.deviceId,
    senderTransportPeerId: binding.transportPeerId,
    senderKeyPackageId: binding.keyPackageId,
    messageId: replayMessageId ?? sourceId,
    recipientPeerIds: recipients,
  );
  await callGroupInboxStore(
    sender.bridge,
    groupId,
    envelope,
    recipientPeerIds: recipients,
    preserveRecipientPeerIds: true,
  );
  if (kind == 'members_added') {
    final members = (subject['members'] as List).cast<Map<String, dynamic>>();
    await sender.messages.saveMessage(
      buildMembersAddedTimelineMessage(
        groupId: groupId,
        addedMembers: members
            .map(
              (member) => (
                peerId: member['peerId'] as String,
                username: member['username'] as String?,
              ),
            )
            .toList(),
        senderId: sender.id,
        senderUsername: sender.name,
        eventAt: at,
      ),
    );
  }
  return _lastInboxEnvelope(sender);
}

void main() {
  for (final rejoined in [false, true]) {
    testWidgets(
      rejoined
          ? 'GX002 A5 reaccepted B applies promoted C leave after C removed B'
          : 'GX002 A5 fresh-group control applies promoted C leave',
      (tester) async {
        late _Peer a;
        late _Peer b;
        late _Peer c;
        final groupId = rejoined ? 'gx002-rejoined' : 'gx002-fresh';
        final completed = await tester.runAsync(() async {
          // Capture independent process zones inside the real async zone; SQLite
          // work and membership queues must not inherit WidgetTest's fake clock.
          a = _Peer('Alice');
          b = _Peer('Bob');
          c = _Peer('Charlie');
          final peers = [a, b, c];
          final keyDeliveries = <({String recipient, int epoch})>[];
          final creatorRotations = <int>[];
          // Match production bootstrap's creator backstop on BOTH remote
          // removals. It advances epochs and delivers signed key updates; it
          // must not be omitted to make the membership repro easier to obtain.
          a.rotateAfterRemoteRemoval = (id) async {
            final outcome = await _rotateAsPeer(a, peers, id, keyDeliveries);
            if (outcome.rotated)
              creatorRotations.add(outcome.key!.keyGeneration);
            return outcome.rotated;
          };
          addTearDown(() async {
            debugSetFlowEventSink(null);
            for (final peer in peers) {
              await peer.close();
            }
          });
          for (final peer in peers) {
            peer.contacts.seed(peers.map((other) => other.contact).toList());
          }
          a.bridge.responses['group:create'] = {
            'ok': true,
            'groupId': groupId,
            'groupKey': 'gx002-initial-key',
            'keyEpoch': 1,
          };
          final created = await a.process.run(
            () => createGroupWithMembers(
              bridge: a.bridge,
              groupRepo: a.groups,
              p2pService: a.p2p,
              identity: a.identity,
              selectedContacts: [b.contact, c.contact],
              type: GroupType.chat,
              name: 'GX002 membership history',
            ),
          );
          expect(created.membersAdded, 2);
          expect(created.invitesSent, 2);
          await _acceptInvite(a, b, groupId);
          await _deliver(b, a, groupId, _lastInboxEnvelope(b));
          await _acceptInvite(a, c, groupId);
          final cJoined = _lastInboxEnvelope(c);
          await _deliver(c, a, groupId, cJoined);
          await _deliver(c, b, groupId, cJoined);

          final pending = <String, GroupPendingBroadcast>{};
          final promotion = await a.process.run(
            () => changeGroupMemberRoleAndBroadcast(
              bridge: a.bridge,
              groupRepo: a.groups,
              identityRepo: a.identities,
              messageRepo: a.messages,
              groupId: groupId,
              memberPeerId: c.id,
              role: MemberRole.admin,
              enqueuePending: (row) async {
                pending[row.id] = row;
              },
              loadPending: (id) async =>
                  pending.values.where((row) => row.groupId == id).toList(),
              removePending: (id) async {
                pending.remove(id);
              },
            ),
          );
          expect(promotion.updatedMember.role, MemberRole.admin);
          expect(pending, isEmpty);
          final promoted = _lastInboxEnvelope(a);
          await _deliver(a, b, groupId, promoted);
          await _deliver(a, c, groupId, promoted);
          for (final peer in peers) {
            expect(
              (await peer.groups.getMember(groupId, c.id))!.role,
              MemberRole.admin,
            );
          }

          if (rejoined) {
            final originalB = (await c.groups.getMember(groupId, b.id))!;
            final beforeRemove = await buildGroupTransitionStateHash(
              c.groups,
              groupId,
            );
            final removal = await c.process.run(
              () => removeGroupMember(
                bridge: c.bridge,
                groupRepo: c.groups,
                msgRepo: c.messages,
                groupId: groupId,
                memberPeerId: b.id,
                selfPeerId: c.id,
                actorUsername: c.name,
              ),
            );
            final removed = await c.process.run(
              () => _publishUiMembershipTransition(
                sender: c,
                groupId: groupId,
                kind: 'member_removed',
                sourceId: removal.eventId,
                at: removal.eventAt,
                preStateHash: beforeRemove,
                subject: {
                  'member': {'peerId': b.id, 'username': b.name},
                  'removedAt': removal.eventAt.toIso8601String(),
                },
                recipients: [a.id, b.id],
                replayMessageId: buildMemberRemovedTimelineMessage(
                  groupId: groupId,
                  removedPeerId: b.id,
                  removedUsername: b.name,
                  senderId: c.id,
                  senderUsername: c.name,
                  eventAt: removal.eventAt,
                ).id,
              ),
            );
            // GroupInfoWired always attempts this after its removal notice.
            // With A still eligible, the real leader gate must deny C rather
            // than our fixture silently skipping or forcing C's rotation.
            final cRotation = await _rotateAsPeer(
              c,
              peers,
              groupId,
              keyDeliveries,
            );
            expect(cRotation.rotated, isFalse);
            expect(
              c.bridge.commandLog,
              isNot(contains('group:generateNextKey')),
            );
            await _deliver(c, a, groupId, removed);
            await _deliver(
              c,
              b,
              groupId,
              removed,
              expectedSelfRemovalAt: removal.eventAt,
            );
            expect(creatorRotations, [2]);
            expect((await a.groups.getLatestKey(groupId))!.keyGeneration, 2);
            expect((await c.groups.getLatestKey(groupId))!.keyGeneration, 2);
            expect(keyDeliveries.map((delivery) => delivery.recipient), [
              c.id,
            ], reason: 'Removed B must not receive the post-removal key');
            expect(
              (await b.groups.getGroup(groupId))!.selfRemovedAt,
              removal.eventAt,
            );
            expect(await b.groups.getMember(groupId, b.id), isNull);
            expect(await b.groups.getLatestKey(groupId), isNull);

            final beforeAdd = await buildGroupTransitionStateHash(
              a.groups,
              groupId,
            );
            final readdedB = originalB.copyWith(
              joinedAt: DateTime.now().toUtc(),
            );
            expect(readdedB.joinedAt.isAfter(removal.eventAt), isTrue);
            await a.process.run(
              () => addGroupMember(
                bridge: a.bridge,
                groupRepo: a.groups,
                groupId: groupId,
                newMember: readdedB,
                selfPeerId: a.id,
                syncBridgeConfig: false,
              ),
            );
            // The picker batches config sync, then mints a later publication
            // time/id. Preserve that ordering before its invite is issued.
            await callGroupUpdateConfig(
              a.bridge,
              groupId: groupId,
              groupConfig: buildGroupConfigPayload(
                (await a.groups.getGroup(groupId))!,
                await a.groups.getMembers(groupId),
              ),
            );
            final publishedAt = DateTime.now().toUtc();
            expect(publishedAt.isAfter(readdedB.joinedAt), isTrue);
            final added = await a.process.run(
              () => _publishUiMembershipTransition(
                sender: a,
                groupId: groupId,
                kind: 'members_added',
                sourceId:
                    'members_added:$groupId:${a.id}:${publishedAt.microsecondsSinceEpoch}',
                at: publishedAt,
                preStateHash: beforeAdd,
                subject: {
                  'members': [readdedB.toConfigJson()],
                },
                recipients: [c.id],
              ),
            );
            await _deliver(a, c, groupId, added);
            expect(
              await buildGroupTransitionStateHash(a.groups, groupId),
              await buildGroupTransitionStateHash(c.groups, groupId),
            );

            final key = (await a.groups.getLatestKey(groupId))!;
            final inviteConfig = buildGroupConfigPayload(
              (await a.groups.getGroup(groupId))!,
              await a.groups.getMembers(groupId),
            );
            expect(
              await a.process.run(
                () => sendGroupInvite(
                  p2pService: a.p2p,
                  bridge: a.bridge,
                  groupRepo: a.groups,
                  recipientPeerId: b.id,
                  recipientMlKemPublicKey: b.identity.mlKemPublicKey,
                  senderPeerId: a.id,
                  senderPublicKey: a.identity.publicKey,
                  senderPrivateKey: a.identity.privateKey,
                  senderUsername: a.name,
                  groupId: groupId,
                  groupKey: key.encryptedKey,
                  keyEpoch: key.keyGeneration,
                  groupConfig: inviteConfig,
                ),
              ),
              SendGroupInviteResult.success,
            );
            final invite = await _acceptInvite(a, b, groupId);
            final proof = invite.membershipFreshnessProof!;
            expect(
              proof.issuedAt.isAfter(DateTime.parse(proof.membershipWatermark)),
              isTrue,
              reason: 'A5 requires issuance after the signed add watermark',
            );
            final bRejoined = _lastInboxEnvelope(b);
            await _deliver(b, a, groupId, bRejoined);
            await _deliver(b, c, groupId, bRejoined);
          }

          final beforeLeave = <String, Object?>{};
          final beforeLeaveEpoch = (await a.groups.getLatestKey(
            groupId,
          ))!.keyGeneration;
          for (final peer in peers) {
            final group = (await peer.groups.getGroup(groupId))!;
            final members = await peer.groups.getMembers(groupId);
            final key = (await peer.groups.getLatestKey(groupId))!;
            expect(members.map((member) => member.peerId).toSet(), {
              a.id,
              b.id,
              c.id,
            });
            expect(key.keyGeneration, beforeLeaveEpoch);
            beforeLeave[peer.name] = groupTransitionStateHashParts(
              group: group,
              members: members,
              latestKeyGeneration: key.keyGeneration,
            );
          }
          final rejectionReasons = <String>[];
          String? receiving;
          debugSetFlowEventSink((event) {
            if (event['event'] ==
                'GROUP_MESSAGE_LISTENER_SIGNED_AUDIT_REJECTED') {
              final details = event['details'] as Map;
              rejectionReasons.add('$receiving:${details['reason']}');
            }
          });
          final leaveAt = DateTime.now().toUtc();
          final deliveriesBeforeLeave = keyDeliveries.length;
          final exit = await c.process.run(
            () => DurableGroupExitSurfaceHarness.createForSurface(
              groupId: groupId,
              bridge: c.bridge,
              groupRepository: c.groups,
              identityRepository: c.identities,
              messageRepository: c.messages,
              now: () => leaveAt,
            ),
          );
          late Map<String, dynamic> left;
          try {
            final result = await c.process.run(exit.requestLeaveForTest);
            expect(result.status.name, 'started');
            expect(await exit.hasDurableGroup(), isFalse);
            expect(await c.groups.getGroup(groupId), isNull);
            expect(await c.groups.getLatestKey(groupId), isNull);
            left = _lastInboxEnvelope(c);
          } finally {
            await exit.close();
          }
          expect(left['recipientPeerIds'], unorderedEquals([a.id, b.id]));
          expect(left['keyEpoch'], beforeLeaveEpoch);
          receiving = a.name;
          await _deliver(c, a, groupId, left);
          final finalEpoch = (await a.groups.getLatestKey(
            groupId,
          ))!.keyGeneration;
          expect(finalEpoch, beforeLeaveEpoch + 1);
          expect(creatorRotations, rejoined ? [2, 3] : [2]);
          expect(
            keyDeliveries
                .skip(deliveriesBeforeLeave)
                .map((delivery) => delivery.recipient),
            [b.id],
            reason: 'C must not receive the creator backstop key after leaving',
          );
          expect(
            (await b.groups.getLatestKey(groupId))!.keyGeneration,
            finalEpoch,
            reason: 'A/B key agreement is established before B receives C-left',
          );
          final beforeBNotice = groupTransitionStateHashParts(
            group: await b.groups.getGroup(groupId),
            members: await b.groups.getMembers(groupId),
            latestKeyGeneration: finalEpoch,
          );
          receiving = b.name;
          await _deliver(c, b, groupId, left);
          // Retain B's repositories, including its real accepted-reentry state.
          // Restarting its consumer must neither resurrect C nor mask a rejection.
          await b.restartListener();
          receiving = '${b.name}-restarted';
          await _deliver(c, b, groupId, left);
          debugSetFlowEventSink(null);

          final afterDelivery = <String, Object?>{};
          for (final peer in [a, b]) {
            final members = await peer.groups.getMembers(groupId);
            final cRow = await peer.groups.getMember(groupId, c.id);
            afterDelivery[peer.name] = {
              'epoch': (await peer.groups.getLatestKey(groupId))!.keyGeneration,
              'members': members.map((member) => member.peerId).toList(),
              'C_role': cRow?.role.toValue(),
              'C_left_at':
                  (await peer.messages.getLatestSystemEventTimestampForTarget(
                    groupId,
                    eventType: 'member_removed',
                    targetId: c.id,
                  ))?.toUtc().toIso8601String(),
            };
          }
          final causalEvidence = jsonEncode({
            'beforeLeaveHashes': beforeLeave,
            'beforeBNoticeHashes': beforeBNotice,
            'auditRejectionReasons': rejectionReasons,
            'creatorEpochs': creatorRotations,
            'afterDelivery': afterDelivery,
          });
          for (final peer in [a, b]) {
            expect(
              await peer.groups.getMember(groupId, c.id),
              isNull,
              reason: causalEvidence,
            );
            expect(
              (await peer.groups.getMembers(
                groupId,
              )).map((m) => m.peerId).toSet(),
              {a.id, b.id},
              reason: causalEvidence,
            );
            expect(
              (await peer.groups.getLatestKey(groupId))!.keyGeneration,
              finalEpoch,
            );
            expect(
              await peer.messages.getLatestSystemEventTimestampForTarget(
                groupId,
                eventType: 'member_removed',
                targetId: c.id,
              ),
              isNotNull,
              reason: causalEvidence,
            );
            final contentId = 'gx002-after-leave-${peer.name}';
            await peer.listener.handleReplayEnvelope({
              'groupId': groupId,
              'senderId': c.id,
              'senderUsername': c.name,
              'keyEpoch': beforeLeaveEpoch,
              'messageId': contentId,
              'text': 'must not appear after C left',
              'timestamp': leaveAt
                  .add(const Duration(seconds: 1))
                  .toIso8601String(),
            });
            expect(await peer.messages.getMessage(contentId), isNull);
          }
          expect(rejectionReasons, isEmpty, reason: causalEvidence);
          return true;
        });
        if (completed != true) return;

        for (final peer in [a, b]) {
          final group = await tester.runAsync(
            () => peer.groups.getGroup(groupId),
          );
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: GroupInfoWired(
                key: ValueKey(peer.id),
                group: group!,
                groupRepo: peer.groups,
                msgRepo: peer.messages,
                contactRepo: peer.contacts,
                bridge: peer.bridge,
                identityRepo: peer.identities,
                p2pService: peer.p2p,
              ),
            ),
          );
          for (var frame = 0; frame < 5; frame++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(find.byType(GroupMemberRow), findsNWidgets(2));
          expect(find.text(c.name), findsNothing);
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is GroupMemberRow && widget.member.peerId == c.id,
            ),
            findsNothing,
            reason: 'C must have no retained row or admin badge',
          );
          final aRow = find.byWidgetPredicate(
            (widget) =>
                widget is GroupMemberRow && widget.member.peerId == a.id,
          );
          expect(aRow, findsOneWidget);
          final creatorRow = tester.widget<GroupMemberRow>(aRow);
          expect(creatorRow.member.role, MemberRole.admin);
          expect(creatorRow.isCreator, isTrue);
          final l10n = AppLocalizations.of(tester.element(aRow))!;
          expect(
            find.descendant(
              of: aRow,
              matching: find.text(l10n.group_role_admin),
            ),
            findsOneWidget,
          );
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is GroupMemberRow &&
                  widget.member.role == MemberRole.admin,
            ),
            findsOneWidget,
            reason: 'Only A remains admin',
          );
        }
      },
    );
  }
}
