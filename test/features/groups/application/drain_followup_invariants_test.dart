import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/domain/models/group_history_gap_repair.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_message_receipt.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_history_gap_repair_repository.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';

/// Cursor-page bridge backed by FakeBridge so its passthrough sign / verify
/// / encrypt / decrypt handlers let `buildGroupOfflineReplayEnvelope` produce
/// properly-shaped signed envelopes that `decodeInboxMessage` will accept.
class _PageBridge extends FakeBridge {
  final Map<String, List<Map<String, dynamic>>> _pages = {};
  final Map<String, String> _nextCursor = {};
  final Map<String, List<Map<String, dynamic>>> _historyGaps = {};

  void addPage(
    String groupId,
    String cursor,
    List<Map<String, dynamic>> messages,
    String nextCursor, {
    List<Map<String, dynamic>> historyGaps = const <Map<String, dynamic>>[],
  }) {
    _pages['$groupId:$cursor'] = messages;
    _nextCursor['$groupId:$cursor'] = nextCursor;
    if (historyGaps.isNotEmpty) {
      _historyGaps['$groupId:$cursor'] = historyGaps;
    }
  }

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String? ?? '';
    if (cmd == 'group:inboxRetrieveCursor') {
      final payload = parsed['payload'] as Map<String, dynamic>;
      final groupId = payload['groupId'] as String;
      final cursor = (payload['cursor'] as String?) ?? '';
      final key = '$groupId:$cursor';
      return jsonEncode({
        'ok': true,
        'messages': _pages[key] ?? const <Map<String, dynamic>>[],
        'cursor': _nextCursor[key] ?? '',
        if (_historyGaps[key] != null) 'historyGaps': _historyGaps[key]!,
      });
    }
    if (cmd == 'group:leave') {
      return jsonEncode({'ok': true});
    }
    return super.send(message);
  }
}

class _InMemoryGroupHistoryGapRepairRepository
    implements GroupHistoryGapRepairRepository {
  final Map<String, GroupHistoryGapRepair> repairs = {};

  String _key(String groupId, String gapId) => '$groupId:$gapId';

  @override
  Future<GroupHistoryGapRepairUpsertResult> upsertDetected(
    GroupHistoryGapRepair repair,
  ) async {
    final key = _key(repair.groupId, repair.gapId);
    final existing = repairs[key];
    if (existing == null) {
      repairs[key] = repair;
      return GroupHistoryGapRepairUpsertResult(repair: repair, created: true);
    }
    if (existing.isTerminal) {
      return GroupHistoryGapRepairUpsertResult(
        repair: existing,
        created: false,
      );
    }
    final merged = existing.copyWith(updatedAt: repair.updatedAt);
    repairs[key] = merged;
    return GroupHistoryGapRepairUpsertResult(repair: merged, created: false);
  }

  @override
  Future<GroupHistoryGapRepair?> getRepair({
    required String groupId,
    required String gapId,
  }) async {
    return repairs[_key(groupId, gapId)];
  }

  @override
  Future<GroupHistoryGapRepair?> getLatestRepairForGroup(String groupId) async {
    final groupRepairs =
        repairs.values.where((r) => r.groupId == groupId).toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return groupRepairs.isEmpty ? null : groupRepairs.first;
  }

  @override
  Future<List<GroupHistoryGapRepair>> getVisibleRepairsForGroup(
    String groupId, {
    int limit = 20,
  }) async {
    final visible = repairs.values.where((r) => r.groupId == groupId).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return visible.take(limit).toList();
  }

  @override
  Future<void> markRepairing({
    required String groupId,
    required String gapId,
  }) async {
    final r = repairs[_key(groupId, gapId)];
    if (r == null || r.isTerminal) return;
    repairs[_key(groupId, gapId)] = r.copyWith(
      status: groupHistoryGapRepairStatusRepairing,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> recordAttempt({
    required String groupId,
    required String gapId,
    required String sourcePeerId,
    required String? lastError,
  }) async {}

  @override
  Future<void> markRepaired({
    required String groupId,
    required String gapId,
    required List<String> repairedMessageIds,
  }) async {
    final r = repairs[_key(groupId, gapId)];
    if (r == null) return;
    repairs[_key(groupId, gapId)] = r.copyWith(
      status: groupHistoryGapRepairStatusRepaired,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> markFailed({
    required String groupId,
    required String gapId,
    required String reason,
  }) async {
    final r = repairs[_key(groupId, gapId)];
    if (r == null) return;
    repairs[_key(groupId, gapId)] = r.copyWith(
      status: groupHistoryGapRepairStatusFailed,
      updatedAt: DateTime.now().toUtc(),
    );
  }
}

void main() {
  group('drain follow-up invariants from /ultrareview merged_bug_009', () {
    late _PageBridge bridge;
    late InMemoryGroupRepository groupRepo;
    late InMemoryGroupMessageRepository msgRepo;

    final group = GroupModel(
      id: 'group-1',
      name: 'G1',
      type: GroupType.chat,
      topicName: '/mknoon/group/group-1',
      createdAt: DateTime.utc(2026, 5, 1),
      createdBy: 'peer-admin',
      myRole: GroupRole.member,
    );

    setUp(() async {
      bridge = _PageBridge();
      groupRepo = InMemoryGroupRepository();
      msgRepo = InMemoryGroupMessageRepository();
      await groupRepo.saveGroup(group);
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-self',
          username: 'Self',
          role: MemberRole.writer,
          publicKey: 'pk-self',
          joinedAt: DateTime.utc(2026, 5, 1),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          publicKey: 'pk-admin',
          joinedAt: DateTime.utc(2026, 5, 1),
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'replay-key-1',
          createdAt: DateTime.utc(2026, 5, 1),
        ),
      );
    });

    Future<Map<String, dynamic>> signedRelayMessage({
      required String messageId,
      required String text,
      required DateTime timestamp,
      String senderPeerId = 'peer-admin',
      String senderPublicKey = 'pk-admin',
    }) async {
      final envelope = await buildGroupOfflineReplayEnvelope(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        payloadType: groupOfflineReplayPayloadTypeMessage,
        plaintext: jsonEncode({
          'groupId': 'group-1',
          'senderId': senderPeerId,
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': text,
          'timestamp': timestamp.toUtc().toIso8601String(),
          'messageId': messageId,
        }),
        messageId: messageId,
        senderPeerId: senderPeerId,
        senderPublicKey: senderPublicKey,
        senderPrivateKey: 'sk-$senderPeerId',
      );
      return {
        'from': senderPeerId,
        'message': envelope,
        'timestamp': timestamp.toUtc().millisecondsSinceEpoch,
      };
    }

    test(
      'detected history gaps are persisted before the cursor commit so they '
      'survive a Phase 2 transaction failure',
      () async {
        final historyRepo = _InMemoryGroupHistoryGapRepairRepository();
        final msg = await signedRelayMessage(
          messageId: 'msg-after-gap',
          text: 'first message after gap',
          timestamp: DateTime.utc(2026, 5, 2, 12),
        );

        bridge.addPage(
          'group-1',
          '',
          [msg],
          'cursor-after-page-1',
          historyGaps: [
            {
              'groupId': 'group-1',
              'gapId': 'gap-1',
              'missingAfterMessageId': 'msg-anchor-before',
              'missingBeforeMessageId': 'msg-after-gap',
              'expectedRangeHash': 'hash-1',
              'expectedHeadMessageId': 'msg-after-gap',
              'candidateSourcePeerIds': ['peer-admin'],
            },
          ],
        );

        msgRepo.failInboxPageTransaction = true;

        await drainGroupOfflineInbox(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          historyGapRepairRepo: historyRepo,
        );

        expect(
          historyRepo.repairs.containsKey('group-1:gap-1'),
          isTrue,
          reason:
              'Gap stub must be persisted via upsertDetected BEFORE the Phase 2 '
              'cursor commit. Otherwise a crash between Phase 2 and Phase 3 '
              'leaves the cursor advanced past a page whose gap was never '
              'recorded — the relay-side gap detector only emits a gap on the '
              'page where it is first observed, so the gap is lost forever.',
        );
        expect(
          await msgRepo.getInboxCursor('group-1'),
          isNull,
          reason: 'cursor must NOT advance when Phase 2 fails',
        );
      },
    );

    test(
      'local-delivered receipts are re-derived on dedup so a Phase 2 retry '
      'does not lose them',
      () async {
        final messageId = 'msg-dedup-receipt';
        final ts = DateTime.utc(2026, 5, 2, 12);

        // Pre-seed the message in msgRepo to simulate "Phase 1 of a previous
        // drain attempt persisted this message; Phase 2 then failed; the
        // current drain re-fetches the same page".
        await msgRepo.saveMessage(
          GroupMessage(
            id: messageId,
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Sender',
            text: 'pre-seeded',
            timestamp: ts,
            keyGeneration: 1,
            status: 'delivered',
            isIncoming: true,
            createdAt: ts,
          ),
        );

        final msg = await signedRelayMessage(
          messageId: messageId,
          text: 'pre-seeded',
          timestamp: ts,
        );
        bridge.addPage('group-1', '', [msg], '');

        await drainGroupOfflineInbox(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          selfPeerId: 'peer-self',
        );

        final receipts = await msgRepo.getReceiptsForMessage(
          'group-1',
          messageId,
        );
        expect(
          receipts.any(
            (r) =>
                r.memberPeerId == 'peer-self' &&
                r.receiptType == groupMessageReceiptTypeDelivered &&
                r.messageId == messageId,
          ),
          isTrue,
          reason:
              'On re-drain of an already-persisted message, the local-delivered '
              'receipt must still be added to pageReceipts. Otherwise a Phase 2 '
              'failure permanently loses the receipt: handleIncomingGroupMessage '
              'returns null on dedup, the original code skipped receipt '
              'generation, and there is no other call site that derives '
              '"local-delivered" from an existing message row.',
        );
      },
    );

    test(
      'mid-page sys-removal cleans up earlier-persisted messages so no rows '
      'orphan against the deleted groupId',
      () async {
        final listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
        );
        addTearDown(listener.dispose);

        final t0 = DateTime.utc(2026, 5, 2, 12);
        final t1 = DateTime.utc(2026, 5, 2, 12, 0, 1);
        final t2 = DateTime.utc(2026, 5, 2, 12, 0, 2);

        final pre = await signedRelayMessage(
          messageId: 'msg-before-removal',
          text: 'pre-removal chatter',
          timestamp: t1,
        );

        // sys "member_removed" envelope addressed to peer-self
        final sysEnvelope = await buildGroupOfflineReplayEnvelope(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          payloadType: groupOfflineReplayPayloadTypeMessage,
          plaintext: jsonEncode({
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': jsonEncode({
              '__sys': 'member_removed',
              'member': {'peerId': 'peer-self', 'username': 'Self'},
              'groupConfig': {
                'name': 'G1',
                'groupType': 'chat',
                'members': [
                  {'peerId': 'peer-admin', 'role': 'admin'},
                ],
                'createdBy': 'peer-admin',
                'createdAt': t0.toIso8601String(),
              },
            }),
            'timestamp': t2.toIso8601String(),
            'messageId': 'msg-remove-self',
          }),
          messageId: 'msg-remove-self',
          senderPeerId: 'peer-admin',
          senderPublicKey: 'pk-admin',
          senderPrivateKey: 'sk-peer-admin',
        );
        final sysMsg = {
          'from': 'peer-admin',
          'message': sysEnvelope,
          'timestamp': t2.millisecondsSinceEpoch,
        };

        // Page order: [normal-msg-FIRST, sys-removal-SECOND]. Phase 1 commits
        // the normal message via the outer msgRepo before reaching the sys
        // payload that deletes the group — so without explicit cleanup the
        // normal message orphans against a now-deleted groupId.
        bridge.addPage('group-1', '', [pre, sysMsg], 'cursor-after-removal');

        await drainGroupOfflineInbox(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupMessageListener: listener,
        );

        expect(
          await groupRepo.getGroup('group-1'),
          isNull,
          reason: 'sys-removal handler must run leaveGroup → deleteGroup',
        );
        expect(
          msgRepo.count,
          0,
          reason:
              'When a sys "member_removed" payload appears mid-page, the drain '
              'must clean up any group-1 rows already written in Phase 1 of '
              'the same page so they do not orphan against the now-deleted '
              'groupId. Rows committed via the outer msgRepo are durable '
              'until explicitly deleted; the prior runInboxPageTransaction '
              'shape rolled them back via the SQLCipher txn, but the new '
              'three-phase shape has no implicit rollback for outer-repo '
              'writes — fix must call deleteMessagesForGroup before exit.',
        );
      },
    );

    test(
      'drain → listener: malformed envelope decoding to text-less, '
      'media-less payload does NOT persist an empty row',
      () async {
        // Cross-system regression for the user-reported "test delete shows
        // empty bubbles" symptom. The listener-side empty-drop guard is
        // pinned by GroupMessageListener tests in
        // test/features/groups/application/group_message_listener_test.dart
        // (see "drops events with neither text nor media — empty bubble
        // after cold restart regression"). What was missing: a test that
        // confirms the SAME guard fires when the malformed event arrives
        // through the offline-drain path, not via the live GossipSub
        // stream. Production hardware soak hit this case (the Go side
        // sometimes emits skeleton replay envelopes with no `text` after
        // partial decrypt) and our well-formed-input drain test could
        // never reach it.
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        addTearDown(() => debugSetFlowEventSink(null));

        final listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
        );
        addTearDown(listener.dispose);

        // Build a perfectly-signed envelope whose decrypted plaintext has
        // an empty text field and no media. decodeInboxMessage will
        // accept it (signature verifies, ciphertext decrypts to the
        // plaintext we provided) and the drain will dispatch it through
        // the listener, where the empty-drop guard must fire.
        final emptyEnvelope = await buildGroupOfflineReplayEnvelope(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          payloadType: groupOfflineReplayPayloadTypeMessage,
          plaintext: jsonEncode({
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 1,
            'text': '', // <-- empty after decrypt
            'timestamp': DateTime.utc(2026, 5, 2, 12).toIso8601String(),
            'messageId': 'msg-empty-from-drain',
            // no 'media' key — text-less + media-less is the regression
          }),
          messageId: 'msg-empty-from-drain',
          senderPeerId: 'peer-admin',
          senderPublicKey: 'pk-admin',
          senderPrivateKey: 'sk-peer-admin',
        );

        bridge.addPage('group-1', '', [
          {
            'from': 'peer-admin',
            'message': emptyEnvelope,
            'timestamp':
                DateTime.utc(2026, 5, 2, 12).millisecondsSinceEpoch,
          },
        ], '');

        await drainGroupOfflineInbox(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupMessageListener: listener,
        );

        expect(
          msgRepo.count,
          0,
          reason:
              'Drain must NOT persist an envelope whose decoded payload '
              'has no text and no media — that produces an empty bubble '
              'on the conversation screen that survives cold restart.',
        );
        expect(
          await msgRepo.getMessage('msg-empty-from-drain'),
          isNull,
          reason: 'no row should exist for the empty envelope',
        );
        expect(
          flowEvents
              .where(
                (e) => e['event'] == 'GROUP_MESSAGE_LISTENER_EMPTY_DROP',
              )
              .toList(),
          hasLength(1),
          reason:
              'GROUP_MESSAGE_LISTENER_EMPTY_DROP must fire so production '
              'logs can identify which upstream events are malformed.',
        );
      },
    );
  });
}
