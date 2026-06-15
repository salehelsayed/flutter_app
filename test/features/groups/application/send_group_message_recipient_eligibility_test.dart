import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';

// REG-119 — Group send false-SUCCESS / silent-loss root cause.
//
// PHASE 0 (RED) characterization for
// Test-Flight-Improv/119-group-send-false-failure-reliability.md.
//
// Device evidence (pixel.log / iphone-13.log, 2026-06-13): every send from a
// freshly-joined member (bob -> Pixel) carried expectedRecipientCount:0 and
// inboxStored:false; the offline send (bd49b0b3) was marked `sent` with
// topicPeers:0 yet alice (iPhone) never received it -> silent loss masked as
// success.
//
// CONFIRMED root cause: the recipient-eligibility filter in
// `_loadGroupSendMembership` excludes the incumbent creator via
// `_isMissingInviteStatusInTrackedGroup` whenever, for that member,
//   inviteStatus == null && hasJoinedInviteEvidence && !hasJoinedTimelineEvidence
// all hold. For a joiner this is always true for the creator:
//  - inviteStatus == null: getStatusesForGroupMembers reads only THIS device's
//    invite-attempt rows; a joiner invited no one (true even with the repo
//    wired, so the repo being null is incidental).
//  - hasJoinedInviteEvidence == true: the joiner holds its OWN sys-member_joined
//    entry (memberJoinedTimelineCount:1).
//  - hasJoinedTimelineEvidence == false: the creator never emits a
//    sys-member_joined entry, so the joiner has no join-evidence for them.
//
// These tests pin the DESIRED behavior and therefore FAIL on current HEAD.

class _InboxStoreOkFalseBridge extends FakeBridge {
  _InboxStoreOkFalseBridge() {
    responses['group:inboxStore'] = {
      'ok': false,
      'errorCode': 'INBOX_STORE_FAILED',
    };
  }
}

Future<void> _saveGroupKey(
  InMemoryGroupRepository groupRepo,
  String groupId, {
  int generation = 1,
}) async {
  await groupRepo.saveKey(
    GroupKeyInfo(
      groupId: groupId,
      keyGeneration: generation,
      encryptedKey: 'test-group-key-$generation',
      createdAt: DateTime.now().toUtc(),
    ),
  );
}

List<String> _recipientPeerIdsFromRetryPayload(String inboxRetryPayload) {
  final retryPayload = jsonDecode(inboxRetryPayload) as Map<String, dynamic>;
  return (retryPayload['recipientPeerIds'] as List<dynamic>? ?? const [])
      .cast<String>();
}

Future<List<Map<String, dynamic>>> _captureFlowEvents(
  Future<void> Function() action,
) async {
  final printed = <String>[];
  final previousLogging = flowEventLoggingEnabled;
  final originalDebugPrint = debugPrint;
  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) printed.add(message);
  };
  try {
    await action();
  } finally {
    debugPrint = originalDebugPrint;
    flowEventLoggingEnabled = previousLogging;
  }
  return printed
      .where((line) => line.startsWith('[FLOW] '))
      .map(
        (line) =>
            jsonDecode(line.substring('[FLOW] '.length))
                as Map<String, dynamic>,
      )
      .toList();
}

void main() {
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;

  const groupId = 'group-119-joiner';
  const creatorPeerId = 'peer-1'; // Alice — incumbent creator
  const joinerPeerId = 'peer-2'; // Bob — freshly-joined sender

  setUp(() async {
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();

    // Bob's local view: a Discussion (chat) group created by Alice; Bob is a
    // non-admin member who just joined.
    await groupRepo.saveGroup(
      GroupModel(
        id: groupId,
        name: 'Eid Group',
        type: GroupType.chat,
        topicName: '/mknoon/group/$groupId',
        createdAt: DateTime.utc(2026, 6, 13, 19, 0),
        createdBy: creatorPeerId,
        myRole: GroupRole.member,
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: creatorPeerId,
        username: 'Alice',
        role: MemberRole.admin,
        publicKey: 'pk-alice',
        joinedAt: DateTime.utc(2026, 6, 13, 19, 0),
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: joinerPeerId,
        username: 'Bob',
        role: MemberRole.writer,
        publicKey: 'pk-bob',
        joinedAt: DateTime.utc(2026, 6, 13, 19, 4),
      ),
    );
    await _saveGroupKey(groupRepo, groupId);

    // CRITICAL device-observed state: Bob's local store holds exactly ONE
    // sys-member_joined entry — his OWN join ("Bob joined the group"), matching
    // memberJoinedTimelineCount:1 in pixel.log. (Without this, hasJoinedInvite-
    // Evidence is false and the bug does not trigger — see OB-008, which has no
    // join-timeline messages and correctly resolves recipients.)
    await msgRepo.saveMessage(
      buildMemberJoinedTimelineMessage(
        groupId: groupId,
        joinedPeerId: joinerPeerId,
        joinedUsername: 'Bob',
        eventAt: DateTime.utc(2026, 6, 13, 19, 4),
      ),
    );
  });

  test(
    'REG-119: a freshly-joined member counts the incumbent creator as a '
    'recipient and creates durable custody for them',
    () async {
      // Alice is online (one live topic peer); relay inbox store fails so the
      // resolved recipient set is observable via the persisted retry payload.
      final bridge = _InboxStoreOkFalseBridge()
        ..responses['group:publish'] = {
          'ok': true,
          'messageId': 'm',
          'topicPeers': 1,
        };

      final events = await _captureFlowEvents(() async {
        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: groupId,
          text: 'test',
          senderPeerId: joinerPeerId,
          senderPublicKey: 'pk-bob',
          senderPrivateKey: 'sk-bob',
          senderUsername: 'Bob',
          messageId: 'msg-119',
          // Matches the device (GROUP_SEND_MSG_INVITE_REPO_ABSENT_USING_JOIN_
          // TIMELINE). A non-null-but-empty repo yields the identical exclusion,
          // because a joiner has no invite-attempt rows for incumbents.
          inviteDeliveryAttemptRepo: null,
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
      });

      final timing = events.lastWhere(
        (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
      );
      final details = timing['details'] as Map<String, dynamic>;

      // FAILS on HEAD: actual expectedRecipientCount == 0 (Alice dropped).
      expect(
        details['expectedRecipientCount'],
        greaterThanOrEqualTo(1),
        reason:
            'a confirmed-member joiner must count the incumbent creator as a recipient',
      );

      // FAILS on HEAD: recipientPeerIds == [] (no durable custody for Alice).
      final saved = await msgRepo.getMessage('msg-119');
      expect(saved, isNotNull);
      expect(saved!.inboxRetryPayload, isNotNull);
      expect(
        _recipientPeerIdsFromRetryPayload(saved.inboxRetryPayload!),
        contains(creatorPeerId),
        reason:
            'durable inbox custody must target the incumbent so an offline '
            'creator is not silently dropped',
      );
    },
  );

  test(
    'REG-119b: a freshly-joined member (myRole=member, no invite-attempt rows) '
    'also counts a NON-creator incumbent it never witnessed joining',
    () async {
      // Residual after the creator exemption: in a 3+ member group a joiner
      // (bob) must reach BOTH the creator (alice) AND a non-creator incumbent
      // (charlie) it holds no invite record and no local join-timeline entry
      // for. On HEAD the creator exemption rescues alice, but charlie is still
      // dropped by the timeline-absence exclusion -> expectedRecipientCount:1,
      // charlie gets no custody (the bd49b0b3 silent-loss class, non-creator).
      const incumbentPeerId = 'peer-3'; // Charlie — joiner never witnessed join
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: incumbentPeerId,
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-charlie',
          joinedAt: DateTime.utc(2026, 6, 13, 19, 2),
        ),
      );

      // Alice (creator) is online; relay inbox store fails so the resolved
      // recipient set is observable via the persisted retry payload.
      final bridge = _InboxStoreOkFalseBridge()
        ..responses['group:publish'] = {
          'ok': true,
          'messageId': 'm',
          'topicPeers': 1,
        };

      final events = await _captureFlowEvents(() async {
        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: groupId,
          text: 'test',
          senderPeerId: joinerPeerId,
          senderPublicKey: 'pk-bob',
          senderPrivateKey: 'sk-bob',
          senderUsername: 'Bob',
          messageId: 'msg-119b',
          inviteDeliveryAttemptRepo: null,
        );
        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
      });

      final timing = events.lastWhere(
        (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
      );
      final details = timing['details'] as Map<String, dynamic>;

      // FAILS on HEAD: actual expectedRecipientCount == 1 (only the creator).
      expect(
        details['expectedRecipientCount'],
        2,
        reason:
            'a confirmed-member joiner must count BOTH the creator and a '
            'non-creator incumbent',
      );

      // FAILS on HEAD: charlie absent -> no durable custody -> silent loss
      // if charlie is offline.
      final saved = await msgRepo.getMessage('msg-119b');
      expect(saved, isNotNull);
      expect(saved!.inboxRetryPayload, isNotNull);
      expect(
        _recipientPeerIdsFromRetryPayload(saved.inboxRetryPayload!),
        containsAll(<String>[creatorPeerId, incumbentPeerId]),
        reason:
            'durable inbox custody must target every real incumbent, not just '
            'the creator',
      );
    },
  );

  test(
    'GAP2: a post-publish connected peer marks the send sent even when the '
    'pre-publish mesh topicPeers reads 0',
    () async {
      // Reliable path returns the device "settle race" shape: the pre-publish
      // mesh snapshot (topicPeers) is 0, but the post-publish recount
      // (connectedTopicPeerCount) saw 1 connected peer that floodPublish
      // delivered to. The matrix must trust the connected count -> sent.
      final bridge = FakeBridge()
        ..responses['group:sendReliable'] = {
          'ok': true,
          'messageId': 'msg-gap2',
          'publishSucceeded': true,
          'topicPeerCount': 0,
          'topicPeers': 0,
          'connectedTopicPeerCount': 1,
          'expectedRecipientCount': 1,
          'inboxStored': false,
          'deliveryMode': 'live_only',
          'recipientPeerIds': <String>[creatorPeerId],
          'envelope': 'enc-envelope',
        };

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: groupId,
        text: 'gap2',
        senderPeerId: joinerPeerId,
        senderPublicKey: 'pk-bob',
        senderPrivateKey: 'sk-bob',
        senderUsername: 'Bob',
        messageId: 'msg-gap2',
        inviteDeliveryAttemptRepo: null,
      );

      // Without GAP 2 the pre-publish topicPeers:0 routes this to the in-doubt
      // 'pending' guard; the post-publish connected count (1) proves live
      // delivery, so it is 'sent'.
      expect(message, isNotNull);
      expect(message!.status, 'sent');
      expect(result, SendGroupMessageResult.success);
    },
  );

  test(
    'REG-119 PIN: legacy zero-peer + inbox-fail send is marked failed, not a '
    'silent sent (guards the legacy path stays truthful)',
    () async {
      // PASSES on HEAD — a regression PIN, not a RED.
      //
      // On the LEGACY publish path a zero-peer + inbox-fail send is correctly
      // marked `failed` (GROUP_SEND_MSG_USE_CASE_ZERO_PEERS_INBOX_FAILED). This
      // pins that the legacy path never silently reports `sent`, so the fix for
      // the reliable path does not regress it.
      //
      // NOTE: the device false-SUCCESS (pixel.log bd49b0b3 — marked `sent` with
      // topicPeers:0, no custody, then lost) occurs only on the RELIABLE path,
      // where `canMarkSent = expectedRecipientCount <= 0 || ...` short-circuits
      // to true. That is a downstream consequence of the REG-119 root cause
      // above (expectedRecipientCount:0); once the incumbent is counted it no
      // longer fires. Whether a genuinely-zero-recipient send may report `sent`
      // is owner question OQ-5 in the plan, so it is intentionally not pinned
      // here.
      final bridge = _InboxStoreOkFalseBridge()
        ..responses['group:publish'] = {
          'ok': true,
          'messageId': 'm',
          'topicPeers': 0,
        };

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: groupId,
        text: 'offline',
        senderPeerId: joinerPeerId,
        senderPublicKey: 'pk-bob',
        senderPrivateKey: 'sk-bob',
        senderUsername: 'Bob',
        messageId: 'msg-119-offline',
        inviteDeliveryAttemptRepo: null,
      );

      expect(message, isNotNull);
      expect(
        message!.status,
        isNot('sent'),
        reason:
            'a send that reached zero peers with no custody must not be reported as sent',
      );
      expect(result, isNot(SendGroupMessageResult.success));
    },
  );
}
