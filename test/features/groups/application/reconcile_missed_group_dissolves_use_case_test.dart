import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/reconcile_missed_group_dissolves_use_case.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';

// ---------------------------------------------------------------------------
// 123 — Group-Dissolve Rejoin/Recovery Reconciliation (S1 = keyed-offline)
//
// Phase 0 proved (see the plan doc): driving the raw production recovery path
// (rejoinGroupTopics + drainGroupOfflineInbox), the durable dissolve never
// converges through three gates — cursor-skip (T2), pre-join-skip (T3),
// stale-watermark (T4) — and rejoin opens a live re-subscribe window (T1).
// Keyless dissolves (T5) are S2, out of reach without a relay tombstone.
//
// Phase 1 closes S1 with:
//   * reconcileMissedGroupDissolves — a cursor-independent probe run BEFORE
//     rejoin (covers T1/T2/T3 + a dissolve a prior drain dropped-and-advanced);
//   * a listener stale-watermark exemption for a TERMINAL dissolve when the
//     group is not already dissolved (covers T4 for BOTH reconcile and drain).
//
// Harness mirrors PGC-001 in drain_group_offline_inbox_use_case_test.dart.
// ---------------------------------------------------------------------------

const _groupId = 'group-1';
const _adminPeerId = 'peer-admin';
const _adminDeviceId = 'admin-device-1';
const _adminTransportPeerId = 'peer-admin-device-1';
const _adminDevicePublicKey = 'pk-admin-device-1';
const _selfPeerId = 'peer-self';

/// Minimal cursor-paged inbox bridge (mirrors _CursorInboxBridge in the drain
/// test). Records the intercepted command once; everything else falls through
/// to super.send (which records once) to avoid double-counting commands.
class _CursorInboxBridge extends FakeBridge {
  final Map<String, _Page> pages = {};

  void addPage(
    String groupId,
    String cursor,
    List<Map<String, dynamic>> messages,
    String nextCursor,
  ) {
    pages['$groupId:$cursor'] = _Page(messages, nextCursor);
  }

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group:inboxRetrieveCursor') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);

      final payload = parsed['payload'] as Map<String, dynamic>;
      final groupId = payload['groupId'] as String;
      final cursor = payload['cursor'] as String? ?? '';
      final page = pages['$groupId:$cursor'];
      if (page != null) {
        return jsonEncode({
          'ok': true,
          'messages': page.messages,
          'cursor': page.nextCursor,
        });
      }
      return jsonEncode({
        'ok': true,
        'messages': <Map<String, dynamic>>[],
        'cursor': '',
      });
    }

    return super.send(message);
  }
}

class _Page {
  final List<Map<String, dynamic>> messages;
  final String nextCursor;
  _Page(this.messages, this.nextCursor);
}

/// Builds an admin-signed `group_dissolved` offline-replay envelope (the
/// durable copy a frozen recipient drains on next connect).
Future<String> _buildDissolveReplayEnvelope({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required DateTime eventAt,
  int keyGeneration = 1,
  String messageId = 'dissolve-replay-1',
}) {
  final innerSys = jsonEncode({
    '__sys': 'group_dissolved',
    'dissolvedAt': eventAt.toIso8601String(),
    'dissolvedBy': _adminPeerId,
  });
  final plaintext = jsonEncode({
    'groupId': _groupId,
    'senderId': _adminPeerId,
    'senderDeviceId': _adminDeviceId,
    'transportPeerId': _adminTransportPeerId,
    'senderUsername': 'Admin',
    'keyEpoch': keyGeneration,
    'text': innerSys,
    'timestamp': eventAt.toIso8601String(),
    'messageId': messageId,
  });
  return buildGroupOfflineReplayEnvelope(
    bridge: bridge,
    groupRepo: groupRepo,
    groupId: _groupId,
    payloadType: groupOfflineReplayPayloadTypeMessage,
    plaintext: plaintext,
    messageId: messageId,
    senderPeerId: _adminPeerId,
    senderPublicKey: _adminDevicePublicKey,
    senderPrivateKey: 'sk-admin',
    senderDeviceId: _adminDeviceId,
    senderTransportPeerId: _adminTransportPeerId,
    keyInfo: GroupKeyInfo(
      groupId: _groupId,
      keyGeneration: keyGeneration,
      encryptedKey: 'replay-key-$keyGeneration',
      createdAt: DateTime.utc(2026, 5, 2),
    ),
  );
}

/// Captures parsed [FLOW] events emitted while [action] runs.
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
  late _CursorInboxBridge bridge;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;
  late GroupMessageListener listener;

  /// Seeds a keyed, NOT-dissolved local group with the dissolving admin stored
  /// (with device binding) so the durable dissolve can be authorized + verified
  /// — a member who held the epoch key but missed the live publish.
  Future<void> seedKeyedMissedDissolveGroup({
    DateTime? lastMembershipEventAt,
    bool seedSelfMember = false,
    DateTime? selfJoinedAt,
    MemberRole adminRole = MemberRole.admin,
  }) async {
    await groupRepo.saveGroup(
      GroupModel(
        id: _groupId,
        name: 'Group One',
        type: GroupType.chat,
        topicName: 'topic-$_groupId',
        createdAt: DateTime.utc(2026, 4, 1),
        createdBy: _adminPeerId,
        myRole: GroupRole.member,
        isDissolved: false,
        lastMembershipEventAt: lastMembershipEventAt,
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: _groupId,
        peerId: _adminPeerId,
        username: 'Admin',
        role: adminRole,
        publicKey: 'pk-admin',
        devices: const [
          GroupMemberDeviceIdentity(
            deviceId: _adminDeviceId,
            transportPeerId: _adminTransportPeerId,
            deviceSigningPublicKey: _adminDevicePublicKey,
          ),
        ],
        joinedAt: DateTime.utc(2026, 4, 1),
      ),
    );
    if (seedSelfMember) {
      await groupRepo.saveMember(
        GroupMember(
          groupId: _groupId,
          peerId: _selfPeerId,
          username: 'Self',
          role: MemberRole.writer,
          publicKey: 'pk-self',
          joinedAt: selfJoinedAt ?? DateTime.utc(2026, 4, 2),
        ),
      );
    }
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: _groupId,
        keyGeneration: 1,
        encryptedKey: 'replay-key-1',
        createdAt: DateTime.utc(2026, 5, 2),
      ),
    );
  }

  /// Seeds the durable dissolve as an inbox page. Returns the dissolve eventAt.
  Future<DateTime> seedDurableDissolve({
    String firstCursor = '',
    String nextCursor = '',
    DateTime? eventAt,
  }) async {
    final at = eventAt ?? DateTime.now().toUtc().add(const Duration(minutes: 1));
    final envelope = await _buildDissolveReplayEnvelope(
      bridge: bridge,
      groupRepo: groupRepo,
      eventAt: at,
    );
    bridge.addPage(_groupId, firstCursor, [
      {
        'from': _adminTransportPeerId,
        'message': envelope,
        'timestamp': at.millisecondsSinceEpoch,
      },
    ], nextCursor);
    return at;
  }

  int countJoinCommands() {
    return bridge.sentMessages
        .map((m) => jsonDecode(m) as Map<String, dynamic>)
        .where((m) => m['cmd'] == 'group:join')
        .length;
  }

  Future<int> countDissolveTimelineRows() async {
    final page = await msgRepo.getMessagesPage(_groupId, limit: 100);
    return page
        .where((m) => m.id.startsWith('sys-group_dissolved:'))
        .length;
  }

  Future<ReconcileMissedGroupDissolvesResult> reconcile() =>
      reconcileMissedGroupDissolves(
        bridge: bridge,
        groupRepo: groupRepo,
        groupMessageListener: listener,
        selfPeerId: _selfPeerId,
      );

  Future<void> drain({String? selfPeerId}) => drainGroupOfflineInbox(
    bridge: bridge,
    groupRepo: groupRepo,
    msgRepo: msgRepo,
    groupMessageListener: listener,
    selfPeerId: selfPeerId,
  );

  setUp(() {
    bridge = _CursorInboxBridge();
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();
    listener = GroupMessageListener(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      bridge: bridge,
    );
  });

  tearDown(() {
    listener.dispose();
  });

  group('123 S1 — reconcile probe converges keyed-offline missed dissolves', () {
    test('baseline: reconcile converges a durable dissolve (keyed-offline)',
        () async {
      await seedKeyedMissedDissolveGroup();
      await seedDurableDissolve();

      final result = await reconcile();

      final group = await groupRepo.getGroup(_groupId);
      expect(group!.isDissolved, isTrue);
      expect(group.dissolvedBy, _adminPeerId);
      expect(result.dissolvesConverged, 1);
      expect(result.groupsProbed, 1);
    });

    test(
      'T1 ordering: after rejoin re-subscribes, reconcile converges + leaves '
      'the dissolved group (it does not stay live)',
      () async {
        await seedKeyedMissedDissolveGroup();
        await seedDurableDissolve();

        // Production order: rejoin FIRST so active groups re-subscribe
        // immediately (live messages are not delayed), then reconcile.
        await rejoinGroupTopics(bridge: bridge, groupRepo: groupRepo);
        expect(
          countJoinCommands(),
          1,
          reason: 'rejoin transiently re-subscribes the still-live group',
        );
        expect((await groupRepo.getGroup(_groupId))!.isDissolved, isFalse);

        await reconcile();

        final group = await groupRepo.getGroup(_groupId);
        expect(
          group!.isDissolved,
          isTrue,
          reason: 'reconcile converges the dissolve — group does not stay live',
        );
        final leaves = bridge.sentMessages
            .map((m) => jsonDecode(m) as Map<String, dynamic>)
            .where((m) => m['cmd'] == 'group:leave')
            .length;
        expect(
          leaves,
          greaterThanOrEqualTo(1),
          reason: 'a converged terminal dissolve leaves the topic',
        );
      },
    );

    test(
      'T2 cursor-skip: reconcile re-fetches a dissolve the drain cursor '
      'advanced past',
      () async {
        await seedKeyedMissedDissolveGroup();
        await seedDurableDissolve(firstCursor: '');
        // Persisted drain cursor already points PAST the dissolve page.
        await msgRepo.runInboxPageTransaction(
          groupId: _groupId,
          nextCursor: 'cursor-past-dissolve',
          apply: (_) async {},
        );

        // The incremental drain (cursor-based) cannot see it...
        await drain();
        expect((await groupRepo.getGroup(_groupId))!.isDissolved, isFalse);

        // ...but the cursor-independent reconcile probe does.
        await reconcile();
        expect((await groupRepo.getGroup(_groupId))!.isDissolved, isTrue);
      },
    );

    test(
      'T3 pre-join: reconcile converges a dissolve the drain pre-join-skip '
      'would drop',
      () async {
        final eventAt = DateTime.utc(2026, 5, 10, 12);
        await seedKeyedMissedDissolveGroup(
          seedSelfMember: true,
          // Self "re-joined" AFTER the dissolve relay timestamp.
          selfJoinedAt: eventAt.add(const Duration(hours: 1)),
        );
        await seedDurableDissolve(eventAt: eventAt);

        // Drain pre-join-skips it (self joinedAt > dissolve relay ts).
        await drain(selfPeerId: _selfPeerId);
        expect((await groupRepo.getGroup(_groupId))!.isDissolved, isFalse);

        // reconcile bypasses the drain-local pre-join gate.
        await reconcile();
        expect((await groupRepo.getGroup(_groupId))!.isDissolved, isTrue);
      },
    );

    test('reconcile is a no-op when there is no durable dissolve', () async {
      await seedKeyedMissedDissolveGroup();
      // No dissolve seeded — empty inbox.

      final result = await reconcile();

      expect((await groupRepo.getGroup(_groupId))!.isDissolved, isFalse);
      expect(result.dissolvesConverged, 0);
      expect(result.groupsProbed, 1);
    });
  });

  group('123 S1/T4 — terminal-dissolve stale-watermark exemption', () {
    test(
      'drain converges a dissolve whose eventAt precedes the local membership '
      'watermark',
      () async {
        final eventAt = DateTime.utc(2026, 5, 10, 12);
        await seedKeyedMissedDissolveGroup(
          // Watermark is AFTER the dissolve eventAt.
          lastMembershipEventAt: eventAt.add(const Duration(hours: 1)),
        );
        await seedDurableDissolve(eventAt: eventAt);

        await drain();

        expect(
          (await groupRepo.getGroup(_groupId))!.isDissolved,
          isTrue,
          reason: 'terminal dissolve applies despite the ahead watermark',
        );
      },
    );

    test('reconcile also converges a watermark-blocked dissolve', () async {
      final eventAt = DateTime.utc(2026, 5, 10, 12);
      await seedKeyedMissedDissolveGroup(
        lastMembershipEventAt: eventAt.add(const Duration(hours: 1)),
      );
      await seedDurableDissolve(eventAt: eventAt);

      await reconcile();

      expect((await groupRepo.getGroup(_groupId))!.isDissolved, isTrue);
    });
  });

  group('123 — idempotency + masking guard', () {
    test(
      'replaying the same dissolve twice converges once (single timeline row)',
      () async {
        await seedKeyedMissedDissolveGroup();
        final at = DateTime.utc(2026, 5, 10, 12);
        final envelope = await _buildDissolveReplayEnvelope(
          bridge: bridge,
          groupRepo: groupRepo,
          eventAt: at,
        );
        Map<String, dynamic> routePayload() => {
          'groupId': _groupId,
          'senderId': _adminPeerId,
          'senderUsername': 'Admin',
          'keyEpoch': 1,
          'text': jsonEncode({
            '__sys': 'group_dissolved',
            'dissolvedAt': at.toIso8601String(),
            'dissolvedBy': _adminPeerId,
          }),
          'timestamp': at.toIso8601String(),
          'transportPeerId': _adminTransportPeerId,
          'senderDeviceId': _adminDeviceId,
          'messageId': 'dissolve-replay-1',
        };
        // Two deliveries of the SAME terminal dissolve (live + durable replay).
        await listener.handleReplayEnvelope(routePayload());
        await listener.handleReplayEnvelope(routePayload());

        final group = await groupRepo.getGroup(_groupId);
        expect(group!.isDissolved, isTrue);
        expect(
          await countDissolveTimelineRows(),
          1,
          reason: 'idempotent: a replayed terminal dissolve adds no second row',
        );
        // Reference the prebuilt envelope so the build path is exercised.
        expect(envelope, isNotEmpty);
      },
    );

    test(
      'masking guard: an already-dissolved group ignores a replayed dissolve '
      'via the stale-watermark gate',
      () async {
        await seedKeyedMissedDissolveGroup();
        await seedDurableDissolve(eventAt: DateTime.utc(2026, 5, 10, 12));

        // First converge.
        await reconcile();
        expect((await groupRepo.getGroup(_groupId))!.isDissolved, isTrue);
        final rowsAfterFirst = await countDissolveTimelineRows();

        // A second reconcile skips the now-dissolved group entirely.
        final secondResult = await reconcile();
        expect(secondResult.dissolvesConverged, 0);
        expect(await countDissolveTimelineRows(), rowsAfterFirst);
      },
    );
  });

  group('123 — authorization guard', () {
    test('a non-admin durable dissolve is NOT converged', () async {
      // The "admin" is stored as a writer — not authorized to dissolve.
      await seedKeyedMissedDissolveGroup(adminRole: MemberRole.writer);
      await seedDurableDissolve();

      final events = await _captureFlowEvents(() async {
        await reconcile();
      });

      expect(
        (await groupRepo.getGroup(_groupId))!.isDissolved,
        isFalse,
        reason: 'unauthorized sender cannot dissolve the group',
      );
      expect(
        events.any(
          (e) => e['event'] == 'GROUP_MESSAGE_LISTENER_UNAUTHORIZED_MEMBERSHIP_EVENT',
        ),
        isTrue,
      );
    });
  });

  group('123 S2 / residual (out of Phase 1 scope — documents the limits)', () {
    test(
      'keyless dissolve cannot be re-derived (S2 — needs a relay tombstone)',
      () async {
        // Group + admin but NO local epoch key.
        await groupRepo.saveGroup(
          GroupModel(
            id: _groupId,
            name: 'Group One',
            type: GroupType.chat,
            topicName: 'topic-$_groupId',
            createdAt: DateTime.utc(2026, 4, 1),
            createdBy: _adminPeerId,
            myRole: GroupRole.member,
            isDissolved: false,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: _groupId,
            peerId: _adminPeerId,
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'pk-admin',
            devices: const [
              GroupMemberDeviceIdentity(
                deviceId: _adminDeviceId,
                transportPeerId: _adminTransportPeerId,
                deviceSigningPublicKey: _adminDevicePublicKey,
              ),
            ],
            joinedAt: DateTime.utc(2026, 4, 1),
          ),
        );
        // Build the dissolve against a temporary KEYED repo, then probe the
        // keyless repo so decrypt throws "Missing group replay key".
        final keyedRepo = InMemoryGroupRepository();
        await keyedRepo.saveKey(
          GroupKeyInfo(
            groupId: _groupId,
            keyGeneration: 1,
            encryptedKey: 'replay-key-1',
            createdAt: DateTime.utc(2026, 5, 2),
          ),
        );
        final at = DateTime.now().toUtc().add(const Duration(minutes: 1));
        final envelope = await _buildDissolveReplayEnvelope(
          bridge: bridge,
          groupRepo: keyedRepo,
          eventAt: at,
        );
        bridge.addPage(_groupId, '', [
          {
            'from': _adminTransportPeerId,
            'message': envelope,
            'timestamp': at.millisecondsSinceEpoch,
          },
        ], '');

        final result = await reconcile();

        expect((await groupRepo.getGroup(_groupId))!.isDissolved, isFalse);
        expect(result.dissolvesConverged, 0);
      },
    );
  });
}
