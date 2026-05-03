import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message_receipt.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';

/// Shared monotonic clock for ordering bridge sends and tx open/close events.
class _Clock {
  final Stopwatch _sw = Stopwatch()..start();
  int now() => _sw.elapsedMicroseconds;
}

class _Window {
  _Window(this.startedAt);
  final int startedAt;
  int? endedAt;
  bool contains(int t) =>
      endedAt == null ? t >= startedAt : (t >= startedAt && t <= endedAt!);
}

class _InstrumentedBridge extends FakeBridge {
  _InstrumentedBridge(this._clock);

  final _Clock _clock;

  /// Pages keyed by '<groupId>:<cursor>'. Empty cursor = first page.
  final Map<String, List<Map<String, dynamic>>> _pages = {};
  final Map<String, String> _nextCursor = {};

  /// Every send timestamp + command name, in send order.
  final List<({int at, String cmd})> events = [];

  void addPage(
    String groupId,
    String cursor,
    List<Map<String, dynamic>> messages,
    String nextCursor,
  ) {
    _pages['$groupId:$cursor'] = messages;
    _nextCursor['$groupId:$cursor'] = nextCursor;
  }

  @override
  Future<String> send(String message) async {
    final at = _clock.now();
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String? ?? '';
    events.add((at: at, cmd: cmd));

    if (cmd == 'group:inboxRetrieveCursor') {
      final payload = parsed['payload'] as Map<String, dynamic>;
      final groupId = payload['groupId'] as String;
      final cursor = (payload['cursor'] as String?) ?? '';
      final key = '$groupId:$cursor';
      final messages = _pages[key] ?? const <Map<String, dynamic>>[];
      final next = _nextCursor[key] ?? '';
      return jsonEncode({
        'ok': true,
        'messages': messages,
        'cursor': next,
      });
    }

    return super.send(message);
  }
}

class _InstrumentedGroupMessageRepository extends InMemoryGroupMessageRepository {
  _InstrumentedGroupMessageRepository(this._clock);

  final _Clock _clock;
  final List<_Window> txWindows = [];

  @override
  Future<void> runInboxPageTransaction({
    required String groupId,
    required String nextCursor,
    required Future<void> Function(GroupMessageRepository transactionRepo) apply,
    List<GroupMessageReceipt> receipts = const [],
    List<String> markReadMessageIds = const [],
  }) async {
    final w = _Window(_clock.now());
    txWindows.add(w);
    try {
      await super.runInboxPageTransaction(
        groupId: groupId,
        nextCursor: nextCursor,
        apply: apply,
        receipts: receipts,
        markReadMessageIds: markReadMessageIds,
      );
    } finally {
      w.endedAt = _clock.now();
    }
  }
}

class _InstrumentedGroupRepository extends InMemoryGroupRepository {
  _InstrumentedGroupRepository(this._clock);

  final _Clock _clock;
  final List<({int at, String op}) > outerReadEvents = [];

  @override
  Future<GroupKeyInfo?> getKeyByGeneration(String groupId, int generation) {
    outerReadEvents.add((at: _clock.now(), op: 'getKeyByGeneration'));
    return super.getKeyByGeneration(groupId, generation);
  }

  @override
  Future<GroupModel?> getGroup(String id) {
    outerReadEvents.add((at: _clock.now(), op: 'getGroup'));
    return super.getGroup(id);
  }

  @override
  Future<List<GroupMember>> getMembers(String groupId) {
    outerReadEvents.add((at: _clock.now(), op: 'getMembers'));
    return super.getMembers(groupId);
  }
}

void main() {
  late _Clock clock;
  late _InstrumentedBridge bridge;
  late _InstrumentedGroupRepository groupRepo;
  late _InstrumentedGroupMessageRepository msgRepo;

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
    clock = _Clock();
    bridge = _InstrumentedBridge(clock);
    groupRepo = _InstrumentedGroupRepository(clock);
    msgRepo = _InstrumentedGroupMessageRepository(clock);

    await groupRepo.saveGroup(group);
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-sender',
        username: 'Sender',
        role: MemberRole.writer,
        publicKey: 'pk-sender',
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

  Future<String> buildSignedReplay({required String text, required String messageId}) {
    return buildGroupOfflineReplayEnvelope(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      payloadType: groupOfflineReplayPayloadTypeMessage,
      plaintext: jsonEncode({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': text,
        'timestamp': '2026-05-02T07:53:00.000Z',
        'messageId': messageId,
      }),
      messageId: messageId,
      senderPeerId: 'peer-sender',
      senderPublicKey: 'pk-sender',
      senderPrivateKey: 'sk-sender',
    );
  }

  test(
    'no bridge.send falls inside any inbox-page transaction window',
    () async {
      final envelope = await buildSignedReplay(text: 'hello', messageId: 'm-1');
      bridge.addPage('group-1', '', [
        {'from': 'peer-sender', 'message': envelope, 'timestamp': 1},
      ], '');

      // Clear setup-time send events; we only care about drain-time events.
      bridge.events.clear();
      groupRepo.outerReadEvents.clear();

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      expect(msgRepo.txWindows, isNotEmpty,
          reason: 'expected at least one inbox-page transaction');

      final overlapping = <({int at, String cmd, int windowIndex})>[];
      for (var i = 0; i < msgRepo.txWindows.length; i++) {
        final w = msgRepo.txWindows[i];
        for (final e in bridge.events) {
          if (w.contains(e.at)) {
            overlapping.add((at: e.at, cmd: e.cmd, windowIndex: i));
          }
        }
      }

      expect(
        overlapping,
        isEmpty,
        reason:
            'bridge.send was invoked while a runInboxPageTransaction was open. '
            'These overlaps would hold the SQLCipher write lock across native '
            'method-channel hops and are the cause of the 10s "database has '
            'been locked" warnings: $overlapping',
      );
    },
  );

  test(
    'no outer-repo read (getGroup/getMembers/getKeyByGeneration) inside any tx window',
    () async {
      final envelope = await buildSignedReplay(text: 'hello', messageId: 'm-1');
      bridge.addPage('group-1', '', [
        {'from': 'peer-sender', 'message': envelope, 'timestamp': 1},
      ], '');

      bridge.events.clear();
      groupRepo.outerReadEvents.clear();

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      expect(msgRepo.txWindows, isNotEmpty);

      final overlapping = <({int at, String op, int windowIndex})>[];
      for (var i = 0; i < msgRepo.txWindows.length; i++) {
        final w = msgRepo.txWindows[i];
        for (final e in groupRepo.outerReadEvents) {
          if (w.contains(e.at)) {
            overlapping.add((at: e.at, op: e.op, windowIndex: i));
          }
        }
      }

      expect(
        overlapping,
        isEmpty,
        reason:
            'A read on the outer GroupRepository happened inside a '
            'runInboxPageTransaction. Reads via the parent Database handle '
            'queue behind the same lock the transaction holds and '
            'self-deadlock the txn: $overlapping',
      );
    },
  );
}
