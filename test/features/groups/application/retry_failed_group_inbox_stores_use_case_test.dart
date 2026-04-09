import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/retry_failed_group_inbox_stores_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';

/// Bridge that fails on the first N group:inboxStore calls and succeeds after.
class _FailFirstNInboxBridge extends FakeBridge {
  int _failCount;
  int _callIndex = 0;
  _FailFirstNInboxBridge({int failCount = 1}) : _failCount = failCount;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group:inboxStore') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      _callIndex++;
      if (_callIndex <= _failCount) {
        throw Exception('Simulated inbox store failure #$_callIndex');
      }
      return jsonEncode({'ok': true});
    }
    return super.send(message);
  }
}

GroupMessage _makeRetryEligible(
  String id, {
  String status = 'sent',
  bool inboxStored = false,
  String? inboxRetryPayload,
  bool isIncoming = false,
}) {
  final now = DateTime.utc(2026, 1, 15, 12, 0, 0);
  return GroupMessage(
    id: id,
    groupId: 'group-1',
    senderPeerId: 'peer-1',
    senderUsername: 'Alice',
    text: 'Test message $id',
    timestamp: now,
    keyGeneration: 0,
    status: status,
    isIncoming: isIncoming,
    createdAt: now,
    inboxStored: inboxStored,
    inboxRetryPayload: inboxRetryPayload ??
        (isIncoming || inboxStored
            ? null
            : jsonEncode({
                'groupId': 'group-1',
                'message': jsonEncode({
                  'groupId': 'group-1',
                  'senderId': 'peer-1',
                  'text': 'Test message $id',
                  'timestamp': now.toIso8601String(),
                  'messageId': id,
                }),
                'recipientPeerIds': ['peer-2'],
                'pushTitle': 'Test Group',
                'pushBody': 'Alice: Test message $id',
              })),
  );
}

void main() {
  late FakeBridge bridge;
  late InMemoryGroupMessageRepository msgRepo;

  setUp(() {
    bridge = FakeBridge();
    msgRepo = InMemoryGroupMessageRepository();
  });

  test('retries eligible sent messages and clears inbox retry state', () async {
    final msg = _makeRetryEligible('msg-1');
    await msgRepo.saveMessage(msg);

    final retried = await retryFailedGroupInboxStores(
      bridge: bridge,
      msgRepo: msgRepo,
    );

    expect(retried, 1);
    final saved = await msgRepo.getMessage('msg-1');
    expect(saved!.inboxStored, isTrue);
    expect(saved.status, 'sent');
    expect(saved.inboxRetryPayload, isNull);
    expect(bridge.commandLog, contains('group:inboxStore'));
  });

  test('retries eligible pending messages and promotes them to sent', () async {
    final msg = _makeRetryEligible('msg-pending', status: 'pending');
    await msgRepo.saveMessage(msg);

    final retried = await retryFailedGroupInboxStores(
      bridge: bridge,
      msgRepo: msgRepo,
    );

    expect(retried, 1);
    final saved = await msgRepo.getMessage('msg-pending');
    expect(saved, isNotNull);
    expect(saved!.status, 'sent');
    expect(saved.inboxStored, isTrue);
    expect(saved.inboxRetryPayload, isNull);
  });

  test('skips messages that are already inbox_stored', () async {
    final msg = _makeRetryEligible('msg-stored', inboxStored: true);
    await msgRepo.saveMessage(msg);

    final retried = await retryFailedGroupInboxStores(
      bridge: bridge,
      msgRepo: msgRepo,
    );

    expect(retried, 0);
    expect(bridge.commandLog, isEmpty);
  });

  test('handles callGroupInboxStore failure gracefully', () async {
    final failBridge = _FailFirstNInboxBridge(failCount: 1);
    final msg1 = _makeRetryEligible('msg-fail');
    final msg2 = _makeRetryEligible('msg-ok');
    await msgRepo.saveMessage(msg1);
    await msgRepo.saveMessage(msg2);

    final retried = await retryFailedGroupInboxStores(
      bridge: failBridge,
      msgRepo: msgRepo,
    );

    // First fails, second succeeds
    expect(retried, 1);
    final saved1 = await msgRepo.getMessage('msg-fail');
    expect(saved1!.inboxStored, isFalse);
    expect(saved1.status, 'sent');
    expect(saved1.inboxRetryPayload, isNotNull);
    final saved2 = await msgRepo.getMessage('msg-ok');
    expect(saved2!.inboxStored, isTrue);
    expect(saved2.status, 'sent');
    expect(saved2.inboxRetryPayload, isNull);
  });

  test('respects batch limit', () async {
    // Create 25 retry-eligible messages
    for (var i = 0; i < 25; i++) {
      await msgRepo.saveMessage(_makeRetryEligible('msg-$i'));
    }

    final retried = await retryFailedGroupInboxStores(
      bridge: bridge,
      msgRepo: msgRepo,
      limit: 20,
    );

    expect(retried, 20);
    // Verify exactly 20 inboxStore calls
    final inboxCalls =
        bridge.commandLog.where((c) => c == 'group:inboxStore').length;
    expect(inboxCalls, 20);
  });

  test('returns 0 when no eligible messages', () async {
    // incoming message — not eligible
    await msgRepo.saveMessage(
      _makeRetryEligible('msg-incoming', isIncoming: true),
    );
    // already stored — not eligible
    await msgRepo.saveMessage(
      _makeRetryEligible('msg-stored', inboxStored: true),
    );
    // failed status — not eligible
    await msgRepo.saveMessage(
      _makeRetryEligible('msg-failed', status: 'failed'),
    );

    final retried = await retryFailedGroupInboxStores(
      bridge: bridge,
      msgRepo: msgRepo,
    );

    expect(retried, 0);
    expect(bridge.commandLog, isEmpty);
  });

  test('skips legacy rows with null inbox_retry_payload', () async {
    final legacyMsg = GroupMessage(
      id: 'msg-legacy',
      groupId: 'group-1',
      senderPeerId: 'peer-1',
      senderUsername: 'Alice',
      text: 'Legacy message',
      timestamp: DateTime.utc(2026, 1, 15),
      status: 'sent',
      isIncoming: false,
      createdAt: DateTime.utc(2026, 1, 15),
      inboxStored: false,
      inboxRetryPayload: null,
    );
    await msgRepo.saveMessage(legacyMsg);

    final retried = await retryFailedGroupInboxStores(
      bridge: bridge,
      msgRepo: msgRepo,
    );

    expect(retried, 0);
    expect(bridge.commandLog, isEmpty);
  });
}
