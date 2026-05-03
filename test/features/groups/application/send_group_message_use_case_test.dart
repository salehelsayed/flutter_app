import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';

import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';

const _validContentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

final _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

Future<List<Map<String, dynamic>>> captureFlowEvents(
  Future<void> Function() action,
) async {
  final printed = <String>[];
  final previousLogging = flowEventLoggingEnabled;
  final originalDebugPrint = debugPrint;
  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      printed.add(message);
    }
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

/// A bridge that delays group:publish by [delay] to test concurrency.
class _SlowPublishBridge extends FakeBridge {
  final Duration delay;
  _SlowPublishBridge({this.delay = const Duration(milliseconds: 200)});

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group:publish') {
      await Future<void>.delayed(delay);
    }

    return super.send(message);
  }
}

/// A bridge that blocks group:publish until [publishGate] completes.
class _GatedPublishBridge extends FakeBridge {
  final Completer<void> publishGate = Completer<void>();

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group:publish') {
      await publishGate.future;
    }

    return super.send(message);
  }
}

/// A bridge that returns ok: false for group:publish but tracks all commands.
class _FailPublishBridge extends FakeBridge {
  _FailPublishBridge() {
    responses['group:publish'] = {'ok': false, 'errorCode': 'PUBLISH_FAILED'};
  }
}

/// A bridge that throws on group:inboxStore commands.
class _InboxStoreFailBridge extends FakeBridge {
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
      throw Exception('Relay inbox store failed');
    }

    return super.send(message);
  }
}

/// A bridge that keeps group replay encryption opaque while forcing durable
/// inbox custody to fail so the retry payload remains persisted for inspection.
class _OpaqueReplayInboxStoreFailBridge extends _InboxStoreFailBridge {
  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group.encrypt') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);

      final payload = parsed['payload'] as Map<String, dynamic>;
      final plaintext = payload['plaintext'] as String? ?? '';
      return jsonEncode({
        'ok': true,
        'ciphertext': 'sealed:${base64Url.encode(utf8.encode(plaintext))}',
        'nonce': 'opaque-replay-nonce',
      });
    }

    return super.send(message);
  }
}

/// A bridge that returns ok:false on group:inboxStore.
class _InboxStoreOkFalseBridge extends FakeBridge {
  _InboxStoreOkFalseBridge() {
    responses['group:inboxStore'] = {
      'ok': false,
      'errorCode': 'INBOX_STORE_FAILED',
    };
  }
}

class _GatedInboxStoreBridge extends FakeBridge {
  final Completer<void> inboxGate = Completer<void>();

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
      await inboxGate.future;
      return jsonEncode({'ok': true});
    }

    return super.send(message);
  }
}

class _DelayedGroupRepository extends InMemoryGroupRepository {
  static const _latestKeyDelay = Duration(milliseconds: 100);
  static const _membersDelay = Duration(milliseconds: 100);

  @override
  Future<GroupKeyInfo?> getLatestKey(String groupId) async {
    await Future<void>.delayed(_latestKeyDelay);
    return super.getLatestKey(groupId);
  }

  @override
  Future<List<GroupMember>> getMembers(String groupId) async {
    await Future<void>.delayed(_membersDelay);
    return super.getMembers(groupId);
  }
}

class _SaveTrackingGroupMessageRepository
    extends InMemoryGroupMessageRepository {
  final Completer<GroupMessage> firstSave = Completer<GroupMessage>();
  final List<GroupMessage> savedMessages = [];

  @override
  Future<void> saveMessage(GroupMessage message) async {
    savedMessages.add(message);
    if (!firstSave.isCompleted) {
      firstSave.complete(message);
    }
    await super.saveMessage(message);
  }
}

Map<String, dynamic> _lastGroupInboxStorePayload(FakeBridge bridge) {
  final inboxMsg = bridge.sentMessages.lastWhere(
    (m) => (jsonDecode(m) as Map)['cmd'] == 'group:inboxStore',
  );
  return (jsonDecode(inboxMsg) as Map)['payload'] as Map<String, dynamic>;
}

Map<String, dynamic> _decodedGroupInboxReplayPayload(FakeBridge bridge) {
  final inboxPayload = _lastGroupInboxStorePayload(bridge);
  final envelope =
      jsonDecode(inboxPayload['message'] as String) as Map<String, dynamic>;
  final ciphertext = envelope['ciphertext'];
  if (ciphertext is String && envelope['kind'] == 'group_offline_replay') {
    return jsonDecode(ciphertext) as Map<String, dynamic>;
  }
  return envelope;
}

Map<String, dynamic> _lastGroupOfflineReplayEnvelope(FakeBridge bridge) {
  final inboxPayload = _lastGroupInboxStorePayload(bridge);
  return jsonDecode(inboxPayload['message'] as String) as Map<String, dynamic>;
}

Map<String, dynamic> _offlineReplayEnvelopeFromRetryPayload(
  String inboxRetryPayload,
) {
  final retryPayload = jsonDecode(inboxRetryPayload) as Map<String, dynamic>;
  return jsonDecode(retryPayload['message'] as String) as Map<String, dynamic>;
}

void _expectSignedReplayEnvelope(
  Map<String, dynamic> envelope, {
  required String groupId,
  required String payloadType,
  required String senderPeerId,
  required String senderPublicKey,
  required String messageId,
}) {
  expect(envelope['kind'], 'group_offline_replay');
  expect(envelope['groupId'], groupId);
  expect(envelope['payloadType'], payloadType);
  expect(envelope['senderPeerId'], senderPeerId);
  expect(envelope['senderPublicKey'], senderPublicKey);
  expect(envelope['messageId'], messageId);
  expect(envelope['signatureAlgorithm'], 'ed25519');
  expect(envelope['signedPayload'], isA<String>());
  expect(envelope['signature'], isA<String>());
  final signedPayload =
      jsonDecode(envelope['signedPayload'] as String) as Map<String, dynamic>;
  expect(signedPayload['kind'], 'group_offline_replay');
  expect(signedPayload['groupId'], groupId);
  expect(signedPayload['payloadType'], payloadType);
  expect(signedPayload['senderPeerId'], senderPeerId);
  expect(signedPayload['senderSigningPublicKey'], senderPublicKey);
  expect(signedPayload['messageId'], messageId);
  expect(signedPayload['ciphertextHash'], isA<String>());
  expect(signedPayload['nonceHash'], isA<String>());
  expect(signedPayload['plaintextHash'], isA<String>());
}

void _expectNoProtectedFragments(String raw, Iterable<String> fragments) {
  for (final fragment in fragments) {
    expect(raw, isNot(contains(fragment)));
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

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;

  final testGroup = GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: 'group-topic-1',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-1',
    myRole: GroupRole.admin,
  );

  setUp(() async {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();
    groupRecoveryGate.resetForTest();

    await groupRepo.saveGroup(testGroup);
    await groupRepo.saveMember(
      GroupMember(
        groupId: testGroup.id,
        peerId: 'peer-1',
        username: 'Alice',
        role: MemberRole.admin,
        publicKey: 'pk-1',
        joinedAt: DateTime.now().toUtc(),
      ),
    );
    await _saveGroupKey(groupRepo, testGroup.id);

    bridge.responses['group:publish'] = {'ok': true, 'messageId': 'msg-123'};
  });

  tearDown(() {
    groupRecoveryGate.resetForTest();
  });

  test('sends message successfully', () async {
    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello group!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(result, SendGroupMessageResult.success);
    expect(message, isNotNull);
    expect(message!.text, 'Hello group!');
    expect(message.isIncoming, false);
    expect(message.status, 'sent');
  });

  test(
    'production send resolves registered sender device distinct from member peer id',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: testGroup.id,
          peerId: 'peer-1',
          username: 'Alice',
          role: MemberRole.admin,
          publicKey: 'pk-1',
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: 'peer-1-device-a',
              transportPeerId: 'peer-1-device-a',
              deviceSigningPublicKey: 'pk-1',
              mlKemPublicKey: 'mlkem-peer-1-device-a',
              keyPackageId: 'kp-peer-1-device-a',
            ),
          ],
          joinedAt: DateTime.utc(2026, 5, 1, 12),
        ),
      );

      final trackingMsgRepo = _SaveTrackingGroupMessageRepository();
      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: trackingMsgRepo,
        groupId: 'group-1',
        text: 'Hello from registered device',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'registered-device-send',
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.transportPeerId, 'peer-1-device-a');

      final publishMessage = bridge.sentMessages.firstWhere((raw) {
        final parsed = jsonDecode(raw) as Map<String, dynamic>;
        return parsed['cmd'] == 'group:publish';
      });
      final publishPayload =
          (jsonDecode(publishMessage) as Map<String, dynamic>)['payload']
              as Map<String, dynamic>;
      expect(publishPayload['senderPeerId'], 'peer-1');
      expect(publishPayload['senderDeviceId'], 'peer-1-device-a');
      expect(publishPayload['senderTransportPeerId'], 'peer-1-device-a');
      expect(publishPayload['senderDevicePublicKey'], 'pk-1');

      final saved = await trackingMsgRepo.getMessage('registered-device-send');
      expect(saved, isNotNull);
      final initialSave = trackingMsgRepo.savedMessages.firstWhere(
        (savedMessage) => savedMessage.id == 'registered-device-send',
      );
      final wireEnvelope =
          jsonDecode(initialSave.wireEnvelope!) as Map<String, dynamic>;
      expect(wireEnvelope['senderDeviceId'], 'peer-1-device-a');
      expect(wireEnvelope['transportPeerId'], 'peer-1-device-a');
    },
  );

  test('emits GROUP_SEND_MSG_TIMING with group and media metadata', () async {
    bridge.responses['group:publish'] = {
      'ok': true,
      'messageId': 'msg-flow-proof',
      'topicPeers': 1,
    };

    final events = await captureFlowEvents(() async {
      await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Hello group!',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );
    });

    final begin = events.firstWhere(
      (event) => event['event'] == 'GROUP_SEND_MSG_USE_CASE_BEGIN',
    );
    expect(begin['details']['groupId'], 'group-1');
    expect(begin['details']['textLength'], 'Hello group!'.length);

    final success = events.firstWhere(
      (event) => event['event'] == 'GROUP_SEND_MSG_USE_CASE_SUCCESS',
    );
    expect(success['details']['messageId'], hasLength(8));
    expect(success['details']['topicPeers'], 1);
    expect(success['details']['inboxOk'], isTrue);
    expect(success['details']['inboxPending'], isFalse);

    final timing = events.lastWhere(
      (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
    );
    expect(timing['details']['outcome'], 'success');
    expect(timing['details']['groupId'], 'group-1');
    expect(timing['details']['hasMedia'], isFalse);
    expect(timing['details']['elapsedMs'], isA<int>());
  });

  test('returns groupNotFound for unknown group', () async {
    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'nonexistent',
      text: 'Hello',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(result, SendGroupMessageResult.groupNotFound);
    expect(message, isNull);
  });

  test('returns groupDissolved for a dissolved group', () async {
    await groupRepo.updateGroup(
      testGroup.copyWith(
        isDissolved: true,
        dissolvedAt: DateTime.utc(2026, 4, 5, 12, 0, 0),
        dissolvedBy: 'peer-admin',
      ),
    );

    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Too late',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(result, SendGroupMessageResult.groupDissolved);
    expect(message, isNull);
    expect(bridge.commandLog, isNot(contains('group:publish')));
  });

  test('returns unauthorized for non-admin in announcement group', () async {
    final announcementGroup = GroupModel(
      id: 'group-announce',
      name: 'Announcements',
      type: GroupType.announcement,
      topicName: 'group-topic-announce',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-admin',
      myRole: GroupRole.member,
    );
    await groupRepo.saveGroup(announcementGroup);
    await _saveGroupKey(groupRepo, announcementGroup.id);

    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-announce',
      text: 'Hello',
      senderPeerId: 'peer-2',
      senderPublicKey: 'pk-2',
      senderPrivateKey: 'sk-2',
      senderUsername: 'Bob',
    );

    expect(result, SendGroupMessageResult.unauthorized);
    expect(message, isNull);
  });

  test(
    'returns error for member when bootstrap key is still missing',
    () async {
      final memberGroup = GroupModel(
        id: 'group-bootstrap-pending',
        name: 'Bootstrap Pending',
        type: GroupType.chat,
        topicName: 'group-topic-bootstrap-pending',
        createdAt: DateTime.now().toUtc(),
        createdBy: 'peer-admin',
        myRole: GroupRole.member,
      );
      await groupRepo.saveGroup(memberGroup);

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-bootstrap-pending',
        text: 'Too early',
        senderPeerId: 'peer-member',
        senderPublicKey: 'pk-member',
        senderPrivateKey: 'sk-member',
        senderUsername: 'Member',
      );

      expect(result, SendGroupMessageResult.error);
      expect(message, isNull);
      expect(bridge.commandLog, isEmpty);
      expect(msgRepo.count, 0);
    },
  );

  test('allows discussion send while group recovery is in progress', () async {
    groupRecoveryGate.begin();
    try {
      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Recovery blocked',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.text, 'Recovery blocked');
    } finally {
      groupRecoveryGate.end();
    }

    expect(bridge.commandLog, contains('group:publish'));
    expect(bridge.commandLog, contains('group:inboxStore'));
    expect(msgRepo.count, 1);
  });

  test(
    'blocks announcement send while group recovery is in progress',
    () async {
      final announcementGroup = GroupModel(
        id: 'group-announce-admin',
        name: 'Announcements',
        type: GroupType.announcement,
        topicName: 'group-topic-announce-admin',
        createdAt: DateTime.now().toUtc(),
        createdBy: 'peer-admin',
        myRole: GroupRole.admin,
      );
      await groupRepo.saveGroup(announcementGroup);
      await _saveGroupKey(groupRepo, announcementGroup.id);

      groupRecoveryGate.begin();
      try {
        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-announce-admin',
          text: 'Resume blocked',
          senderPeerId: 'peer-admin',
          senderPublicKey: 'pk-admin',
          senderPrivateKey: 'sk-admin',
          senderUsername: 'Admin',
        );

        expect(result, SendGroupMessageResult.error);
        expect(message, isNull);
      } finally {
        groupRecoveryGate.end();
      }

      expect(bridge.commandLog, isEmpty);
      expect(msgRepo.count, 0);
    },
  );

  test('saves message to repo on success', () async {
    await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello group!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(msgRepo.count, 1);
    final latest = await msgRepo.getLatestMessage('group-1');
    expect(latest, isNotNull);
    expect(latest!.text, 'Hello group!');
  });

  test(
    'propagates quotedMessageId through publish, inbox, and saved message',
    () async {
      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Replying in group',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        quotedMessageId: 'msg-parent-1',
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.quotedMessageId, 'msg-parent-1');

      final publishMsg = bridge.sentMessages.firstWhere(
        (m) => (jsonDecode(m) as Map)['cmd'] == 'group:publish',
      );
      final publishPayload =
          (jsonDecode(publishMsg) as Map)['payload'] as Map<String, dynamic>;
      expect(publishPayload['quotedMessageId'], 'msg-parent-1');

      final innerPayload = _decodedGroupInboxReplayPayload(bridge);
      expect(innerPayload['quotedMessageId'], 'msg-parent-1');

      final saved = await msgRepo.getMessage(message.id);
      expect(saved, isNotNull);
      expect(saved!.quotedMessageId, 'msg-parent-1');
    },
  );

  test(
    'strips dangerous bidi controls and preserves safe markers across publish, inbox, save, and encrypted inbox payload',
    () async {
      const rawText = 'Hello\u202E\u200E group\u200F!';
      const sanitizedText = 'Hello\u200E group\u200F!';

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: rawText,
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.text, sanitizedText);

      final saved = await msgRepo.getMessage(message.id);
      expect(saved, isNotNull);
      expect(saved!.text, sanitizedText);

      final publishMsg = bridge.sentMessages.firstWhere(
        (m) => (jsonDecode(m) as Map)['cmd'] == 'group:publish',
      );
      final publishPayload =
          (jsonDecode(publishMsg) as Map)['payload'] as Map<String, dynamic>;
      expect(publishPayload['text'], sanitizedText);
      expect(publishPayload['text'], isNot(contains('\u202E')));

      final inboxPayload = _lastGroupInboxStorePayload(bridge);
      expect(inboxPayload.containsKey('pushTitle'), isFalse);
      expect(inboxPayload.containsKey('pushBody'), isFalse);

      final innerPayload = _decodedGroupInboxReplayPayload(bridge);
      expect(innerPayload['text'], sanitizedText);
    },
  );

  test('EK004 stores signed offline replay envelope for group_message', () async {
    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello group!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
      messageId: 'msg-ek004-offline-replay',
    );

    expect(result, SendGroupMessageResult.success);
    expect(message, isNotNull);
    // Both operations should run (order is non-deterministic due to parallelism)
    expect(bridge.commandLog, contains('group:publish'));
    expect(bridge.commandLog, contains('group:inboxStore'));

    _expectSignedReplayEnvelope(
      _lastGroupOfflineReplayEnvelope(bridge),
      groupId: 'group-1',
      payloadType: 'group_message',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      messageId: 'msg-ek004-offline-replay',
    );
  });

  test(
    'group send loads members and excludes sender from push recipients',
    () async {
      final joinedAt = DateTime.utc(2026, 1, 1);
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-1',
          username: 'Alice',
          role: MemberRole.admin,
          joinedAt: joinedAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          joinedAt: joinedAt.add(const Duration(seconds: 1)),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-3',
          username: 'Cara',
          role: MemberRole.reader,
          joinedAt: joinedAt.add(const Duration(seconds: 2)),
        ),
      );

      await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Hello group!',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      final inboxPayload = _lastGroupInboxStorePayload(bridge);
      expect(
        inboxPayload['recipientPeerIds'],
        unorderedEquals(['peer-2', 'peer-3']),
      );
      expect(inboxPayload.containsKey('pushTitle'), isFalse);
      expect(inboxPayload.containsKey('pushBody'), isFalse);
    },
  );

  test('text group message does not send plaintext preview fields', () async {
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-2',
        username: 'Bob',
        role: MemberRole.writer,
        joinedAt: DateTime.utc(2026, 1, 2),
      ),
    );

    await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'hello',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Sender',
    );

    final inboxPayload = _lastGroupInboxStorePayload(bridge);
    expect(inboxPayload.containsKey('pushTitle'), isFalse);
    expect(inboxPayload.containsKey('pushBody'), isFalse);
  });

  test(
    'media-only group message does not send plaintext media preview fields',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          joinedAt: DateTime.utc(2026, 1, 2),
        ),
      );

      final voiceAttachment = MediaAttachment(
        id: 'att-voice',
        messageId: '',
        mime: 'audio/mp4',
        size: 48000,
        mediaType: 'audio',
        downloadStatus: 'done',
        createdAt: DateTime.now().toUtc().toIso8601String(),
        localPath: '/tmp/voice.m4a',
        durationMs: 3000,
        waveform: [0.1, 0.5, 0.8, 0.3],
        contentHash: _validContentHash,
        encryptionKeyBase64: 'key-att-voice',
        encryptionNonce: 'nonce-att-voice',
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );

      await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: '',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        mediaAttachments: [voiceAttachment],
      );

      final inboxPayload = _lastGroupInboxStorePayload(bridge);
      expect(inboxPayload.containsKey('pushTitle'), isFalse);
      expect(inboxPayload.containsKey('pushBody'), isFalse);
    },
  );

  test(
    'empty recipient list does not crash and still stores group inbox',
    () async {
      final (result, _) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Only me here',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      expect(result, SendGroupMessageResult.success);
      expect(bridge.commandLog, contains('group:inboxStore'));

      final inboxPayload = _lastGroupInboxStorePayload(bridge);
      expect(inboxPayload.containsKey('recipientPeerIds'), isFalse);
    },
  );

  test(
    'rejects stale send after local membership removal before persistence',
    () async {
      await groupRepo.removeMember('group-1', 'peer-1');
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-2',
          joinedAt: DateTime.utc(2026, 1, 2),
        ),
      );

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Queued stale send',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      expect(result, SendGroupMessageResult.unauthorized);
      expect(message, isNull);
      expect(msgRepo.count, 0);
      expect(bridge.commandLog, isEmpty);
    },
  );

  test('send succeeds even if inbox store throws', () async {
    final failBridge = _InboxStoreFailBridge();
    failBridge.responses['group:publish'] = {
      'ok': true,
      'messageId': 'msg-123',
    };

    final (result, message) = await sendGroupMessage(
      bridge: failBridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    // Send should still succeed despite inbox store failure
    expect(result, SendGroupMessageResult.success);
    expect(message, isNotNull);
    expect(failBridge.commandLog, contains('group:publish'));
    expect(failBridge.commandLog, contains('group:inboxStore'));
  });

  test('returns error when publish returns ok: false', () async {
    bridge.responses['group:publish'] = {
      'ok': false,
      'errorCode': 'PUBLISH_FAILED',
    };

    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(result, SendGroupMessageResult.error);
    // Pre-persist contract: error returns the failed message (not null)
    expect(message, isNotNull);
    expect(message!.status, 'failed');
  });

  test('returns error when publish throws exception', () async {
    bridge.throwOnSend = true;

    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(result, SendGroupMessageResult.error);
    // Pre-persist contract: error returns the failed message (not null)
    expect(message, isNotNull);
    expect(message!.status, 'failed');
  });

  test('persists explicit inbox success when publish fails', () async {
    bridge.responses['group:publish'] = {
      'ok': false,
      'errorCode': 'PUBLISH_FAILED',
    };

    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(result, SendGroupMessageResult.error);
    // Pre-persist contract: row exists with 'failed' status + retry payloads
    expect(msgRepo.count, 1);
    final page = await msgRepo.getMessagesPage('group-1');
    expect(page, hasLength(1));
    expect(page.single.id, message!.id);
    final saved = await msgRepo.getMessage(page.single.id);
    expect(saved, isNotNull);
    expect(saved!.status, 'failed');
    expect(saved.wireEnvelope, isNotNull);
    expect(saved.inboxStored, isTrue);
    expect(saved.inboxRetryPayload, isNull);
  });

  test('publish and inbox store run concurrently', () async {
    final slowBridge = _SlowPublishBridge(
      delay: const Duration(milliseconds: 200),
    );
    slowBridge.responses['group:publish'] = {
      'ok': true,
      'messageId': 'msg-123',
    };

    final stopwatch = Stopwatch()..start();
    await sendGroupMessage(
      bridge: slowBridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );
    stopwatch.stop();

    // If sequential: publish(200ms) + inboxStore(~0ms) > 200ms (plus overhead)
    // If parallel: max(publish(200ms), inboxStore(~0ms)) ≈ 200ms
    // Both should be present
    expect(slowBridge.commandLog, contains('group:publish'));
    expect(slowBridge.commandLog, contains('group:inboxStore'));

    // Wall-clock should be under 400ms (sequential would be ~400ms+ with overhead)
    expect(stopwatch.elapsedMilliseconds, lessThan(400));
  });

  test(
    'getGroup stays sequential while latest key and member lookup run in parallel',
    () async {
      final slowGroupRepo = _DelayedGroupRepository();
      await slowGroupRepo.saveGroup(testGroup);
      await _saveGroupKey(slowGroupRepo, testGroup.id);
      await slowGroupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 0,
          encryptedKey: 'encrypted-key',
          createdAt: DateTime.now().toUtc(),
        ),
      );
      await slowGroupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-1',
          username: 'Alice',
          role: MemberRole.admin,
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await slowGroupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final stopwatch = Stopwatch()..start();
      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: slowGroupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Parallel reads',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );
      stopwatch.stop();

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(stopwatch.elapsedMilliseconds, lessThan(180));
    },
  );

  test('inbox store runs even when publish fails', () async {
    final failBridge = _FailPublishBridge();

    final (result, _) = await sendGroupMessage(
      bridge: failBridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(result, SendGroupMessageResult.error);
    // inbox store should still have run despite publish failure
    expect(failBridge.commandLog, contains('group:publish'));
    expect(failBridge.commandLog, contains('group:inboxStore'));
  });

  // ---------------------------------------------------------------------------
  // Media attachment tests
  // ---------------------------------------------------------------------------
  group('media attachments', () {
    late InMemoryMediaAttachmentRepository mediaRepo;

    final testAttachment = MediaAttachment(
      id: 'att-1',
      messageId: '',
      mime: 'image/jpeg',
      size: 12345,
      mediaType: 'image',
      downloadStatus: 'done',
      createdAt: DateTime.now().toUtc().toIso8601String(),
      localPath: '/tmp/photo.jpg',
      contentHash: _validContentHash,
      encryptionKeyBase64: 'key-att-1',
      encryptionNonce: 'nonce-att-1',
      encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    );

    setUp(() {
      mediaRepo = InMemoryMediaAttachmentRepository();
    });

    test('includes media in publish payload', () async {
      final (result, _) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Check this out',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        mediaAttachments: [testAttachment],
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, SendGroupMessageResult.success);

      // Verify bridge received media in publish payload
      final publishMsg = bridge.sentMessages.firstWhere(
        (m) => (jsonDecode(m) as Map)['cmd'] == 'group:publish',
      );
      final payload =
          (jsonDecode(publishMsg) as Map)['payload'] as Map<String, dynamic>;
      expect(payload['media'], isNotNull);
      expect((payload['media'] as List).length, 1);
      final mediaJson =
          (payload['media'] as List).single as Map<String, dynamic>;
      expect(mediaJson['contentHash'], _validContentHash);
      expect(mediaJson['encryptionKeyBase64'], 'key-att-1');
      expect(mediaJson['encryptionNonce'], 'nonce-att-1');
      expect(
        mediaJson['encryptionScheme'],
        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );
    });

    test('includes media in inbox payload', () async {
      await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Check this out',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        mediaAttachments: [testAttachment],
        mediaAttachmentRepo: mediaRepo,
      );

      // Verify inbox store received media in payload
      final innerPayload = _decodedGroupInboxReplayPayload(bridge);
      expect(innerPayload['media'], isNotNull);
      expect((innerPayload['media'] as List).length, 1);
      final mediaJson =
          (innerPayload['media'] as List).single as Map<String, dynamic>;
      expect(mediaJson['contentHash'], _validContentHash);
      expect(mediaJson['encryptionKeyBase64'], 'key-att-1');
      expect(mediaJson['encryptionNonce'], 'nonce-att-1');
      expect(
        mediaJson['encryptionScheme'],
        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );
    });

    test('saves attachments to MediaAttachmentRepository', () async {
      await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Check this out',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        mediaAttachments: [testAttachment],
        mediaAttachmentRepo: mediaRepo,
      );

      expect(mediaRepo.count, 1);
      // The saved attachment should have a non-empty messageId
      final saved = (await mediaRepo.getPendingDownloads()).isEmpty;
      // Since testAttachment has downloadStatus: 'done', getPendingDownloads returns empty
      expect(saved, isTrue);
    });

    test('includes GIF metadata in publish and inbox payloads', () async {
      final gifAttachment = testAttachment.copyWith(
        id: 'gif-att-1',
        mime: 'image/gif',
        localPath: '/tmp/funny.gif',
      );

      final (result, _) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: '',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        mediaAttachments: [gifAttachment],
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, SendGroupMessageResult.success);

      final publishMsg = bridge.sentMessages.firstWhere(
        (m) => (jsonDecode(m) as Map)['cmd'] == 'group:publish',
      );
      final publishPayload =
          (jsonDecode(publishMsg) as Map)['payload'] as Map<String, dynamic>;
      final publishMedia = publishPayload['media'] as List<dynamic>;
      expect(
        (publishMedia.single as Map<String, dynamic>)['mime'],
        'image/gif',
      );

      final innerPayload = _decodedGroupInboxReplayPayload(bridge);
      final inboxMedia = innerPayload['media'] as List<dynamic>;
      expect((inboxMedia.single as Map<String, dynamic>)['mime'], 'image/gif');
    });

    test(
      'rejects dangerous media MIME before persistence, publish, or inbox store',
      () async {
        final dangerousAttachment = testAttachment.copyWith(
          id: 'bad-att-1',
          mime: 'application/pdf',
          mediaType: 'file',
          localPath: '/tmp/bad.pdf',
        );

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'blocked media',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          mediaAttachments: [dangerousAttachment],
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, SendGroupMessageResult.error);
        expect(message, isNull);
        expect(msgRepo.count, 0);
        expect(mediaRepo.count, 0);
        expect(bridge.commandLog, isNot(contains('group:publish')));
        expect(bridge.commandLog, isNot(contains('group:inboxStore')));
      },
    );

    test(
      'rejects oversized single media before persistence, publish, or inbox store',
      () async {
        final oversizedAttachment = testAttachment.copyWith(
          id: 'oversized-att-1',
          size: kGroupMediaPerAttachmentLimitBytes + 1,
        );

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'blocked oversized media',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          mediaAttachments: [oversizedAttachment],
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, SendGroupMessageResult.error);
        expect(message, isNull);
        expect(msgRepo.count, 0);
        expect(mediaRepo.count, 0);
        expect(bridge.commandLog, isNot(contains('group:publish')));
        expect(bridge.commandLog, isNot(contains('group:inboxStore')));
      },
    );

    test(
      'rejects oversized total media list before persistence, publish, or inbox store',
      () async {
        final first = testAttachment.copyWith(
          id: 'total-att-1',
          size: kGroupMediaTotalMessageLimitBytes,
        );
        final second = testAttachment.copyWith(id: 'total-att-2', size: 1);

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'blocked oversized total',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          mediaAttachments: [first, second],
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, SendGroupMessageResult.error);
        expect(message, isNull);
        expect(msgRepo.count, 0);
        expect(mediaRepo.count, 0);
        expect(bridge.commandLog, isNot(contains('group:publish')));
        expect(bridge.commandLog, isNot(contains('group:inboxStore')));
      },
    );

    test('accepts media at the configured size boundary', () async {
      final boundaryAttachment = testAttachment.copyWith(
        id: 'boundary-att-1',
        size: kGroupMediaPerAttachmentLimitBytes,
      );

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: '',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        mediaAttachments: [boundaryAttachment],
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(bridge.commandLog, contains('group:publish'));
      expect(bridge.commandLog, contains('group:inboxStore'));
      expect(mediaRepo.count, 1);
    });

    test('rejects mediaType mismatch before group publish', () async {
      final mismatchedAttachment = testAttachment.copyWith(
        id: 'bad-att-2',
        mime: 'image/jpeg',
        mediaType: 'video',
      );

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'blocked mismatch',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        mediaAttachments: [mismatchedAttachment],
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, SendGroupMessageResult.error);
      expect(message, isNull);
      expect(msgRepo.count, 0);
      expect(mediaRepo.count, 0);
      expect(bridge.commandLog, isNot(contains('group:publish')));
    });

    test('rejects hashless media before persistence or publish', () async {
      final hashlessAttachment = testAttachment.copyWith(
        id: 'hashless-att',
        clearContentHash: true,
      );

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'blocked hashless',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        mediaAttachments: [hashlessAttachment],
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, SendGroupMessageResult.error);
      expect(message, isNull);
      expect(msgRepo.count, 0);
      expect(mediaRepo.count, 0);
      expect(bridge.commandLog, isNot(contains('group:publish')));
      expect(bridge.commandLog, isNot(contains('group:inboxStore')));
    });

    test('rejects media without encryption metadata before publish', () async {
      final unencryptedAttachment = testAttachment.copyWith(
        id: 'unencrypted-att',
        clearEncryptionKeyBase64: true,
        clearEncryptionNonce: true,
        clearEncryptionScheme: true,
      );

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'blocked unencrypted media',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        mediaAttachments: [unencryptedAttachment],
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, SendGroupMessageResult.error);
      expect(message, isNull);
      expect(msgRepo.count, 0);
      expect(mediaRepo.count, 0);
      expect(bridge.commandLog, isNot(contains('group:publish')));
      expect(bridge.commandLog, isNot(contains('group:inboxStore')));
    });

    test(
      'removes stale upload_pending placeholders before saving final attachments',
      () async {
        const messageId = 'group-media-stable-id';
        await mediaRepo.saveAttachment(
          MediaAttachment(
            id: 'pending-placeholder',
            messageId: messageId,
            mime: 'image/jpeg',
            size: 0,
            mediaType: 'image',
            localPath: 'pending_uploads/$messageId/pending-placeholder.jpg',
            downloadStatus: 'upload_pending',
            createdAt: DateTime.now().toUtc().toIso8601String(),
            contentHash: _validContentHash,
            encryptionKeyBase64: 'key-fixture',
            encryptionNonce: 'nonce-fixture',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
        );

        final (result, _) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Check this out',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: messageId,
          mediaAttachments: [
            testAttachment.copyWith(
              id: 'final-attachment',
              messageId: messageId,
            ),
          ],
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, SendGroupMessageResult.success);

        final savedAttachments = await mediaRepo.getAttachmentsForMessage(
          messageId,
        );
        expect(savedAttachments, hasLength(1));
        expect(savedAttachments.single.id, 'final-attachment');
        expect(savedAttachments.single.downloadStatus, 'done');
      },
    );

    test('uses provided messageId when given', () async {
      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Hello!',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'pre-created-id',
      );

      expect(result, SendGroupMessageResult.success);
      expect(message!.id, 'pre-created-id');
      final saved = await msgRepo.getMessage('pre-created-id');
      expect(saved, isNotNull);
    });

    test('uses provided timestamp when given', () async {
      final fixedTime = DateTime.utc(2026, 1, 15, 12, 0, 0);

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Hello!',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        timestamp: fixedTime,
      );

      expect(result, SendGroupMessageResult.success);
      expect(message!.timestamp, fixedTime);
    });

    test('generates messageId when not provided', () async {
      final (_, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Hello!',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      expect(message!.id, isNotEmpty);
      expect(message.id, isNot('pre-created-id'));
    });

    test('SP003 default message ids are unique UUID v4 values', () async {
      final (firstResult, firstMessage) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'First random id message',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      final (secondResult, secondMessage) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Second random id message',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      expect(firstResult, SendGroupMessageResult.success);
      expect(secondResult, SendGroupMessageResult.success);
      expect(firstMessage, isNotNull);
      expect(secondMessage, isNotNull);
      expect(_uuidV4Pattern.hasMatch(firstMessage!.id), isTrue);
      expect(_uuidV4Pattern.hasMatch(secondMessage!.id), isTrue);
      expect(firstMessage.id, isNot(secondMessage.id));
      expect(await msgRepo.getMessage(firstMessage.id), isNotNull);
      expect(await msgRepo.getMessage(secondMessage.id), isNotNull);
    });

    test(
      'message id collision from generator uses a fresh id without overwriting trusted row',
      () async {
        const collidingId = 'generated-collision-id';
        const resolvedId = 'generated-resolved-id';
        final trustedTimestamp = DateTime.utc(2026, 4, 5, 10);
        await msgRepo.saveMessage(
          GroupMessage(
            id: collidingId,
            groupId: 'group-1',
            senderPeerId: 'peer-1',
            senderUsername: 'Alice',
            text: 'Trusted original',
            timestamp: trustedTimestamp,
            keyGeneration: 1,
            status: 'sent',
            isIncoming: false,
            createdAt: trustedTimestamp,
          ),
        );

        var factoryCallCount = 0;
        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'New generated collision send',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          timestamp: DateTime.utc(2026, 4, 5, 10, 1),
          messageIdFactory: () {
            factoryCallCount++;
            return factoryCallCount == 1 ? collidingId : resolvedId;
          },
        );

        expect(result, SendGroupMessageResult.success);
        expect(message!.id, resolvedId);

        final trusted = await msgRepo.getMessage(collidingId);
        expect(trusted, isNotNull);
        expect(trusted!.text, 'Trusted original');
        expect(trusted.status, 'sent');

        final resolved = await msgRepo.getMessage(resolvedId);
        expect(resolved, isNotNull);
        expect(resolved!.text, 'New generated collision send');
      },
    );

    test(
      'message id collision from explicit id resolves without overwriting trusted row',
      () async {
        const collidingId = 'explicit-collision-id';
        const resolvedId = 'explicit-resolved-id';
        final trustedTimestamp = DateTime.utc(2026, 4, 5, 11);
        await msgRepo.saveMessage(
          GroupMessage(
            id: collidingId,
            groupId: 'group-1',
            senderPeerId: 'peer-1',
            senderUsername: 'Alice',
            text: 'Already sent',
            timestamp: trustedTimestamp,
            keyGeneration: 1,
            status: 'sent',
            isIncoming: false,
            createdAt: trustedTimestamp,
          ),
        );

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Second send with colliding id',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: collidingId,
          timestamp: DateTime.utc(2026, 4, 5, 11, 1),
          messageIdFactory: () => resolvedId,
        );

        expect(result, SendGroupMessageResult.success);
        expect(message!.id, resolvedId);
        expect((await msgRepo.getMessage(collidingId))!.text, 'Already sent');
        expect(
          (await msgRepo.getMessage(resolvedId))!.text,
          'Second send with colliding id',
        );
      },
    );

    test(
      'message id collision guard still allows failed retry in place',
      () async {
        const retryId = 'retry-same-id';
        final retryTimestamp = DateTime.utc(2026, 4, 5, 12);
        await msgRepo.saveMessage(
          GroupMessage(
            id: retryId,
            groupId: 'group-1',
            senderPeerId: 'peer-1',
            senderUsername: 'Alice',
            text: 'Retry same row',
            timestamp: retryTimestamp,
            keyGeneration: 1,
            status: 'failed',
            isIncoming: false,
            createdAt: retryTimestamp,
            wireEnvelope: '{}',
            inboxRetryPayload: '{}',
          ),
        );

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Retry same row',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: retryId,
          timestamp: retryTimestamp,
          messageIdFactory: () => 'should-not-be-used',
        );

        expect(result, SendGroupMessageResult.success);
        expect(message!.id, retryId);
        final saved = await msgRepo.getMessage(retryId);
        expect(saved, isNotNull);
        expect(saved!.text, 'Retry same row');
        expect(saved.status, anyOf('sent', 'pending'));
      },
    );

    test('sends message with empty text and media (voice note)', () async {
      final voiceAttachment = MediaAttachment(
        id: 'att-voice',
        messageId: '',
        mime: 'audio/mp4',
        size: 48000,
        mediaType: 'audio',
        downloadStatus: 'done',
        createdAt: DateTime.now().toUtc().toIso8601String(),
        localPath: '/tmp/voice.m4a',
        durationMs: 3000,
        waveform: [0.1, 0.5, 0.8, 0.3],
        contentHash: _validContentHash,
        encryptionKeyBase64: 'key-att-voice',
        encryptionNonce: 'nonce-att-voice',
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: '',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        mediaAttachments: [voiceAttachment],
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.text, '');
      expect(message.status, 'sent');

      // Verify bridge received media in publish payload
      final publishMsg = bridge.sentMessages.firstWhere(
        (m) => (jsonDecode(m) as Map)['cmd'] == 'group:publish',
      );
      final payload =
          (jsonDecode(publishMsg) as Map)['payload'] as Map<String, dynamic>;
      expect(payload['media'], isNotNull);
      expect((payload['media'] as List).length, 1);

      // Verify attachment saved with resolved messageId
      expect(mediaRepo.count, 1);
    });

    test(
      'announcement voice-only send accepts empty text and writes exact voice push body',
      () async {
        final announcementGroup = GroupModel(
          id: 'group-announce-voice',
          name: 'Voice Announces',
          type: GroupType.announcement,
          topicName: 'group-topic-announce-voice',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'peer-1',
          myRole: GroupRole.admin,
        );
        await groupRepo.saveGroup(announcementGroup);
        await _saveGroupKey(groupRepo, announcementGroup.id);
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-announce-voice',
            keyGeneration: 5,
            encryptedKey: 'voice-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        final voiceAttachment = MediaAttachment(
          id: 'att-announce-voice',
          messageId: '',
          mime: 'audio/mp4',
          size: 64000,
          mediaType: 'audio',
          downloadStatus: 'done',
          createdAt: DateTime.now().toUtc().toIso8601String(),
          localPath: '/tmp/announce-voice.m4a',
          durationMs: 1800,
          waveform: [0.2, 0.4, 0.8],
          contentHash: _validContentHash,
          encryptionKeyBase64: 'key-att-announce-voice',
          encryptionNonce: 'nonce-att-announce-voice',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-announce-voice',
          text: '',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          mediaAttachments: [voiceAttachment],
          mediaAttachmentRepo: mediaRepo,
          messageId: 'msg-announce-voice',
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.id, 'msg-announce-voice');
        expect(message.text, '');
        expect(message.keyGeneration, 5);
        expect(message.status, 'sent');

        final inboxPayload = _lastGroupInboxStorePayload(bridge);
        expect(inboxPayload.containsKey('pushTitle'), isFalse);
        expect(inboxPayload.containsKey('pushBody'), isFalse);
        final inboxEnvelope =
            jsonDecode(inboxPayload['message'] as String)
                as Map<String, dynamic>;
        expect(inboxEnvelope['keyEpoch'], 5);
        expect(inboxEnvelope['messageId'], 'msg-announce-voice');
      },
    );

    test('rejects message with empty text and no media', () async {
      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: '',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      expect(result, SendGroupMessageResult.error);
      expect(message, isNull);
      // Should not have called bridge at all
      expect(bridge.commandLog, isEmpty);
    });

    test('rejects message with whitespace-only text and no media', () async {
      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: '   ',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      expect(result, SendGroupMessageResult.error);
      expect(message, isNull);
    });

    test(
      'topicPeers zero returns successNoPeers when durable inbox store succeeds',
      () async {
        // When the Go pubsub topic has zero peers, publish still returns ok:true
        // because the durable inbox store is the fallback path. The send should
        // return successNoPeers while persisting the row as a successful send.
        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-zero-peers',
          'topicPeers': 0,
        };

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'No peers online',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
        );

        expect(result, SendGroupMessageResult.successNoPeers);
        expect(message, isNotNull);
        expect(message!.text, 'No peers online');
        expect(message.status, 'sent');
        // Both publish and inbox store should have been called
        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));
      },
    );

    test(
      'announcement admin send returns successNoPeers when live fanout is zero',
      () async {
        // Admin in an announcement group should return successNoPeers when
        // no peers are online (zero live fanout), because the durable
        // inbox store ensures offline readers will catch up.
        final announcementGroup = GroupModel(
          id: 'group-announce-zero',
          name: 'Announces',
          type: GroupType.announcement,
          topicName: 'group-topic-announce-zero',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'peer-1',
          myRole: GroupRole.admin,
        );
        await groupRepo.saveGroup(announcementGroup);
        await _saveGroupKey(groupRepo, announcementGroup.id);

        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-announce-zero',
          'topicPeers': 0,
        };

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-announce-zero',
          text: 'Announcement to empty room',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
        );

        expect(result, SendGroupMessageResult.successNoPeers);
        expect(message, isNotNull);
        expect(message!.status, 'sent');
      },
    );

    test(
      'announcement admin send after key rotation uses the new epoch and remains authorized',
      () async {
        final announcementGroup = GroupModel(
          id: 'group-announce-rotated',
          name: 'Announces Rotated',
          type: GroupType.announcement,
          topicName: 'group-topic-announce-rotated',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'peer-1',
          myRole: GroupRole.admin,
        );
        await groupRepo.saveGroup(announcementGroup);
        await _saveGroupKey(groupRepo, announcementGroup.id);
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-announce-rotated',
            keyGeneration: 1,
            encryptedKey: 'old-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-announce-rotated',
            keyGeneration: 2,
            encryptedKey: 'new-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-announce-rotated',
          'topicPeers': 1,
        };

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-announce-rotated',
          text: 'Post-rotation announcement',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-announce-rotated',
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.keyGeneration, 2);
        expect(message.status, 'sent');
        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));

        final inboxPayload = _lastGroupInboxStorePayload(bridge);
        final inboxEnvelope =
            jsonDecode(inboxPayload['message'] as String)
                as Map<String, dynamic>;
        expect(inboxEnvelope['keyEpoch'], 2);
        expect(inboxEnvelope['messageId'], 'msg-announce-rotated');
      },
    );

    test(
      'announcement non-admin remains blocked before any network send starts',
      () async {
        // Non-admin in an announcement group must be rejected before
        // any bridge calls are made (no publish, no inbox store).
        final announcementGroup = GroupModel(
          id: 'group-announce-blocked',
          name: 'Announces Blocked',
          type: GroupType.announcement,
          topicName: 'group-topic-announce-blocked',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'peer-admin',
          myRole: GroupRole.member,
        );
        await groupRepo.saveGroup(announcementGroup);
        await _saveGroupKey(groupRepo, announcementGroup.id);

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-announce-blocked',
          text: 'Trying to announce',
          senderPeerId: 'peer-2',
          senderPublicKey: 'pk-2',
          senderPrivateKey: 'sk-2',
          senderUsername: 'Bob',
        );

        expect(result, SendGroupMessageResult.unauthorized);
        expect(message, isNull);
        // No bridge calls should have been made at all
        expect(bridge.commandLog, isEmpty);
      },
    );

    test('text-only message without media — no media in payload', () async {
      await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Hello!',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      final publishMsg = bridge.sentMessages.firstWhere(
        (m) => (jsonDecode(m) as Map)['cmd'] == 'group:publish',
      );
      final payload =
          (jsonDecode(publishMsg) as Map)['payload'] as Map<String, dynamic>;
      expect(payload.containsKey('media'), isFalse);
    });
  });

  group('MS-018: key rotation epoch binding', () {
    test(
      'send snapshots current epoch for row and replay envelope before publish completes',
      () async {
        final gatedBridge = _GatedPublishBridge();
        gatedBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-ms018-snapshot',
          'topicPeers': 1,
        };
        final trackingRepo = _SaveTrackingGroupMessageRepository();
        final fixedTime = DateTime.utc(2026, 4, 29, 10, 0);

        final sendFuture = sendGroupMessage(
          bridge: gatedBridge,
          groupRepo: groupRepo,
          msgRepo: trackingRepo,
          groupId: 'group-1',
          text: 'Created before epoch commit',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-ms018-snapshot',
          timestamp: fixedTime,
        );

        final firstSaved = await trackingRepo.firstSave.future;
        expect(firstSaved.keyGeneration, 1);
        expect(firstSaved.inboxRetryPayload, isNotNull);

        final prePersistEnvelope = _offlineReplayEnvelopeFromRetryPayload(
          firstSaved.inboxRetryPayload!,
        );
        expect(prePersistEnvelope['keyEpoch'], 1);
        expect(prePersistEnvelope['messageId'], 'msg-ms018-snapshot');

        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 2,
            encryptedKey: 'test-group-key-2',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        gatedBridge.publishGate.complete();
        final (result, message) = await sendFuture;

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.keyGeneration, 1);

        final saved = await trackingRepo.getMessage('msg-ms018-snapshot');
        expect(saved, isNotNull);
        expect(saved!.keyGeneration, 1);

        final storedEnvelope = _lastGroupOfflineReplayEnvelope(gatedBridge);
        expect(storedEnvelope['keyEpoch'], 1);
        expect(storedEnvelope['messageId'], 'msg-ms018-snapshot');
      },
    );

    test(
      'messages before during and after rotation bind to the locally committed epoch',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-bob',
            mlKemPublicKey: 'mlkem-bob',
            joinedAt: DateTime.now().toUtc(),
          ),
        );
        bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': 'test-group-key-2',
          'keyEpoch': 2,
        };
        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'publish-ok',
          'topicPeers': 1,
        };

        final (beforeResult, beforeMessage) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Before rotation commit',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-ms018-before',
        );
        expect(beforeResult, SendGroupMessageResult.success);
        expect(beforeMessage, isNotNull);
        expect(beforeMessage!.keyGeneration, 1);
        expect(_lastGroupOfflineReplayEnvelope(bridge)['keyEpoch'], 1);

        final distributionStarted = Completer<void>();
        final distributionGate = Completer<bool>();
        final rotationFuture = rotateAndDistributeGroupKey(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          selfPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          perRecipientTimeout: const Duration(seconds: 5),
          distributionTimeout: const Duration(seconds: 5),
          sendP2PMessage: (peerId, message) {
            if (!distributionStarted.isCompleted) {
              distributionStarted.complete();
            }
            return distributionGate.future;
          },
        );
        await distributionStarted.future;

        final latestDuringRotation = await groupRepo.getLatestKey('group-1');
        expect(latestDuringRotation, isNotNull);
        expect(latestDuringRotation!.keyGeneration, 1);
        expect(await groupRepo.getKeyByGeneration('group-1', 2), isNull);
        expect(bridge.commandLog, isNot(contains('group:updateKey')));

        final (duringResult, duringMessage) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'During rotation distribution',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-ms018-during',
        );
        expect(duringResult, SendGroupMessageResult.success);
        expect(duringMessage, isNotNull);
        expect(duringMessage!.keyGeneration, 1);
        expect(_lastGroupOfflineReplayEnvelope(bridge)['keyEpoch'], 1);

        distributionGate.complete(true);
        final rotatedKey = await rotationFuture;
        expect(rotatedKey, isNotNull);
        expect(rotatedKey!.keyGeneration, 2);

        final latestAfterRotation = await groupRepo.getLatestKey('group-1');
        expect(latestAfterRotation, isNotNull);
        expect(latestAfterRotation!.keyGeneration, 2);

        final (afterResult, afterMessage) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'After rotation commit',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-ms018-after',
        );
        expect(afterResult, SendGroupMessageResult.success);
        expect(afterMessage, isNotNull);
        expect(afterMessage!.keyGeneration, 2);
        expect(_lastGroupOfflineReplayEnvelope(bridge)['keyEpoch'], 2);

        final beforeSaved = await msgRepo.getMessage('msg-ms018-before');
        final duringSaved = await msgRepo.getMessage('msg-ms018-during');
        final afterSaved = await msgRepo.getMessage('msg-ms018-after');
        expect(beforeSaved!.keyGeneration, 1);
        expect(duringSaved!.keyGeneration, 1);
        expect(afterSaved!.keyGeneration, 2);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // WU-3: Pre-persist, _tryInboxStore, topicPeers, 4-way result matrix
  // ---------------------------------------------------------------------------
  group('WU-3: pre-persist and send contract', () {
    test(
      'pre-persist: message saved with sending status + wireEnvelope + inboxRetryPayload BEFORE bridge call',
      () async {
        final gatedBridge = _GatedPublishBridge();
        gatedBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-123',
          'topicPeers': 2,
        };
        final trackingRepo = _SaveTrackingGroupMessageRepository();

        final fixedTime = DateTime.utc(2026, 1, 15, 12, 0, 0);
        var completed = false;

        final sendFuture =
            sendGroupMessage(
              bridge: gatedBridge,
              groupRepo: groupRepo,
              msgRepo: trackingRepo,
              groupId: 'group-1',
              text: 'Pre-persist test',
              senderPeerId: 'peer-1',
              senderPublicKey: 'pk-1',
              senderPrivateKey: 'sk-1',
              senderUsername: 'Alice',
              messageId: 'pre-persist-id',
              timestamp: fixedTime,
            ).then((value) {
              completed = true;
              return value;
            });

        final firstSaved = await trackingRepo.firstSave.future;
        expect(firstSaved.id, 'pre-persist-id');
        expect(firstSaved.status, 'sending');
        expect(firstSaved.wireEnvelope, isNotNull);
        expect(firstSaved.inboxRetryPayload, isNotNull);

        final savedWhilePublishBlocked = await trackingRepo.getMessage(
          'pre-persist-id',
        );
        expect(savedWhilePublishBlocked, isNotNull);
        expect(savedWhilePublishBlocked!.status, 'sending');
        expect(savedWhilePublishBlocked.wireEnvelope, isNotNull);
        expect(savedWhilePublishBlocked.inboxRetryPayload, isNotNull);
        expect(completed, isFalse);

        gatedBridge.publishGate.complete();
        final (result, message) = await sendFuture;

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);

        final saved = await trackingRepo.getMessage('pre-persist-id');
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
      },
    );

    test('pre-persist: unauthorized caller does NOT persist a row', () async {
      final announcementGroup = GroupModel(
        id: 'group-no-persist',
        name: 'Announcements',
        type: GroupType.announcement,
        topicName: 'group-topic-announce',
        createdAt: DateTime.now().toUtc(),
        createdBy: 'peer-admin',
        myRole: GroupRole.member,
      );
      await groupRepo.saveGroup(announcementGroup);
      await _saveGroupKey(groupRepo, announcementGroup.id);

      final (result, _) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-no-persist',
        text: 'Trying to send',
        senderPeerId: 'peer-2',
        senderPublicKey: 'pk-2',
        senderPrivateKey: 'sk-2',
        senderUsername: 'Bob',
      );

      expect(result, SendGroupMessageResult.unauthorized);
      expect(msgRepo.count, 0);
    });

    test('pre-persist: group-not-found does NOT persist a row', () async {
      final (result, _) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'nonexistent-group',
        text: 'No group',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      expect(result, SendGroupMessageResult.groupNotFound);
      expect(msgRepo.count, 0);
    });
  });

  group('WU-3: 0-peer publish detection and 4-way matrix', () {
    test('0-peer + inbox OK → successNoPeers, status sent', () async {
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'msg-zero-peers',
        'topicPeers': 0,
      };

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'No peers online',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'msg-zero-peers',
      );

      expect(result, SendGroupMessageResult.successNoPeers);
      expect(message, isNotNull);
      expect(message!.status, 'sent');

      final saved = await msgRepo.getMessage('msg-zero-peers');
      expect(saved, isNotNull);
      expect(saved!.status, 'sent');
      expect(saved.inboxStored, isTrue);
    });

    test('0-peer + inbox fail → error', () async {
      final failBridge = _InboxStoreFailBridge();
      failBridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'msg-zero-fail',
        'topicPeers': 0,
      };

      late SendGroupMessageResult result;
      late GroupMessage? message;
      final events = await captureFlowEvents(() async {
        (result, message) = await sendGroupMessage(
          bridge: failBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Zero peers, inbox fail',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-zero-fail',
        );
      });

      expect(result, SendGroupMessageResult.error);
      expect(message, isNotNull);
      // The pre-persisted row should exist with 'failed' status
      final saved = await msgRepo.getMessage('msg-zero-fail');
      expect(saved, isNotNull);
      expect(saved!.status, 'failed');

      final inboxStoreFailed = events.firstWhere(
        (event) => event['event'] == 'GROUP_SEND_MSG_INBOX_STORE_FAILED',
      );
      expect(
        inboxStoreFailed['details']['error'],
        contains('Relay inbox store failed'),
      );

      final zeroPeersFailed = events.firstWhere(
        (event) =>
            event['event'] == 'GROUP_SEND_MSG_USE_CASE_ZERO_PEERS_INBOX_FAILED',
      );
      expect(zeroPeersFailed['details']['messageId'], 'msg-zero');

      final timing = events.lastWhere(
        (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
      );
      expect(timing['details']['outcome'], 'zero_peers_inbox_failed');
      expect(timing['details']['topicPeers'], 0);
      expect(timing['details']['groupId'], 'group-1');
    });

    test('peers > 0 + inbox OK → success, both payloads cleared', () async {
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'msg-peers-ok',
        'topicPeers': 3,
      };

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Normal send',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'msg-peers-ok',
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.status, 'sent');
      expect(message.inboxStored, isTrue);

      final saved = await msgRepo.getMessage('msg-peers-ok');
      expect(saved, isNotNull);
      expect(saved!.wireEnvelope, isNull);
      expect(saved.inboxRetryPayload, isNull);
    });

    test(
      'peers > 0 + inbox fail → success with pending status, wireEnvelope cleared, inboxRetryPayload kept',
      () async {
        final failBridge = _InboxStoreFailBridge();
        failBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-peers-inbox-fail',
          'topicPeers': 3,
        };

        final (result, message) = await sendGroupMessage(
          bridge: failBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Inbox fails but peers OK',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-peers-inbox-fail',
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'pending');
        expect(message.inboxStored, isFalse);
        expect(message.inboxRetryPayload, isNotNull);

        final saved = await msgRepo.getMessage('msg-peers-inbox-fail');
        expect(saved, isNotNull);
        expect(saved!.status, 'pending');
        expect(saved.wireEnvelope, isNull);
        expect(saved.inboxRetryPayload, isNotNull);
      },
    );

    test(
      'EK-002 pending inbox retry stores encrypted replay without protected plaintext',
      () async {
        final privacyBridge = _OpaqueReplayInboxStoreFailBridge();
        privacyBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-ek002-privacy',
          'topicPeers': 2,
        };
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            joinedAt: DateTime.utc(2026, 1, 2),
          ),
        );

        const protectedText = 'EK002 secret message body alpha';
        const inviteSecret = 'invite-token-secret-ek002-beta';
        const privateState = 'private-state-secret-ek002-gamma';
        const mediaKey = 'media-key-secret-ek002-delta';
        final protectedFragments = [
          protectedText,
          inviteSecret,
          privateState,
          mediaKey,
        ];
        final mediaAttachment = MediaAttachment(
          id: 'att-ek002-private',
          messageId: '',
          mime: 'image/png',
          size: 1200,
          mediaType: 'image',
          downloadStatus: 'done',
          createdAt: DateTime.utc(2026, 1, 2).toIso8601String(),
          contentHash: _validContentHash,
          encryptionKeyBase64: mediaKey,
          encryptionNonce: 'media-nonce-secret-ek002',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );

        final (result, message) = await sendGroupMessage(
          bridge: privacyBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: '$protectedText $inviteSecret $privateState',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-ek002-privacy',
          mediaAttachments: [mediaAttachment],
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'pending');
        expect(message.inboxRetryPayload, isNotNull);

        final saved = await msgRepo.getMessage('msg-ek002-privacy');
        expect(saved, isNotNull);
        expect(saved!.inboxRetryPayload, isNotNull);

        final retryRaw = saved.inboxRetryPayload!;
        _expectNoProtectedFragments(retryRaw, protectedFragments);
        final retryPayload = jsonDecode(retryRaw) as Map<String, dynamic>;
        expect(retryPayload['recipientPeerIds'], ['peer-2']);

        final retryEnvelope = _offlineReplayEnvelopeFromRetryPayload(retryRaw);
        expect(retryEnvelope['kind'], 'group_offline_replay');
        expect(retryEnvelope['payloadType'], 'group_message');
        expect(retryEnvelope['keyEpoch'], 1);
        expect(retryEnvelope['messageId'], 'msg-ek002-privacy');
        expect(retryEnvelope['ciphertext'], startsWith('sealed:'));
        expect(retryEnvelope['nonce'], 'opaque-replay-nonce');

        final inboxStoreCommand = privacyBridge.sentMessages.lastWhere(
          (raw) =>
              (jsonDecode(raw) as Map<String, dynamic>)['cmd'] ==
              'group:inboxStore',
        );
        _expectNoProtectedFragments(inboxStoreCommand, protectedFragments);
        final inboxPayload = _lastGroupInboxStorePayload(privacyBridge);
        expect(inboxPayload['message'], retryPayload['message']);
        expect(inboxPayload.containsKey('pushTitle'), isFalse);
        expect(inboxPayload.containsKey('pushBody'), isFalse);
      },
    );

    test(
      'peers > 0 returns pending before inbox store finishes and promotes to sent in background',
      () async {
        final gatedBridge = _GatedInboxStoreBridge();
        gatedBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-peers-bg-inbox',
          'topicPeers': 2,
        };

        final stopwatch = Stopwatch()..start();
        final sendFuture = sendGroupMessage(
          bridge: gatedBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Return before inbox completes',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-peers-bg-inbox',
        );
        final (result, message) = await sendFuture;
        stopwatch.stop();

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'pending');
        expect(message.inboxStored, isFalse);
        expect(message.inboxRetryPayload, isNotNull);
        expect(stopwatch.elapsedMilliseconds, lessThan(150));

        final savedBeforeRelease = await msgRepo.getMessage(
          'msg-peers-bg-inbox',
        );
        expect(savedBeforeRelease, isNotNull);
        expect(savedBeforeRelease!.status, 'pending');
        expect(savedBeforeRelease.inboxStored, isFalse);
        expect(savedBeforeRelease.inboxRetryPayload, isNotNull);

        gatedBridge.inboxGate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final savedAfterRelease = await msgRepo.getMessage(
          'msg-peers-bg-inbox',
        );
        expect(savedAfterRelease, isNotNull);
        expect(savedAfterRelease!.status, 'sent');
        expect(savedAfterRelease.inboxStored, isTrue);
        expect(savedAfterRelease.inboxRetryPayload, isNull);
      },
    );

    test('missing topicPeers + inbox OK → legacy success stays sent', () async {
      // Old bridge response without topicPeers key
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'msg-legacy',
      };

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Legacy bridge',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'msg-legacy',
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.status, 'sent');
      expect(message.inboxStored, isTrue);

      final saved = await msgRepo.getMessage('msg-legacy');
      expect(saved, isNotNull);
      expect(saved!.status, 'sent');
      expect(saved.wireEnvelope, isNull);
      expect(saved.inboxRetryPayload, isNull);
    });

    test(
      'missing topicPeers + inbox fail → legacy success stays pending until inbox retry closes it',
      () async {
        final failBridge = _InboxStoreFailBridge();
        failBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-legacy-inbox-fail',
        };

        final (result, message) = await sendGroupMessage(
          bridge: failBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Legacy bridge with inbox failure',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-legacy-inbox-fail',
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'pending');
        expect(message.inboxStored, isFalse);
        expect(message.inboxRetryPayload, isNotNull);

        final saved = await msgRepo.getMessage('msg-legacy-inbox-fail');
        expect(saved, isNotNull);
        expect(saved!.status, 'pending');
        expect(saved.wireEnvelope, isNull);
        expect(saved.inboxRetryPayload, isNotNull);
      },
    );

    test(
      'publish fail + inbox fail → status failed, both payloads retained',
      () async {
        final failBridge = _InboxStoreFailBridge();
        failBridge.responses['group:publish'] = {
          'ok': false,
          'errorCode': 'PUBLISH_FAILED',
        };

        final (result, message) = await sendGroupMessage(
          bridge: failBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Will fail',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-publish-fail',
        );

        expect(result, SendGroupMessageResult.error);
        // Pre-persisted row should exist with 'failed' status
        final page = await msgRepo.getMessagesPage('group-1');
        expect(page, hasLength(1));
        expect(page.single.id, 'msg-publish-fail');
        final saved = await msgRepo.getMessage(page.single.id);
        expect(saved, isNotNull);
        expect(saved!.status, 'failed');
        expect(saved.wireEnvelope, isNotNull);
        expect(saved.inboxStored, isFalse);
        expect(saved.inboxRetryPayload, isNotNull);
      },
    );

    test(
      'publish fail + inbox OK keeps failed status but persists inbox success explicitly',
      () async {
        final failPublishBridge = _FailPublishBridge();

        final (result, message) = await sendGroupMessage(
          bridge: failPublishBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Publish fails, inbox stores',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-publish-fail-inbox-ok',
        );

        expect(result, SendGroupMessageResult.error);
        expect(message, isNotNull);
        expect(message!.status, 'failed');
        expect(message.inboxStored, isTrue);
        expect(message.inboxRetryPayload, isNull);

        final saved = await msgRepo.getMessage('msg-publish-fail-inbox-ok');
        expect(saved, isNotNull);
        expect(saved!.status, 'failed');
        expect(saved.wireEnvelope, isNotNull);
        expect(saved.inboxStored, isTrue);
        expect(saved.inboxRetryPayload, isNull);
      },
    );

    test(
      'publish timeout + inbox OK surfaces durable success instead of failed',
      () async {
        final timeoutPublishBridge = FakeBridge(
          initialResponses: {
            'group:publish': {'ok': false, 'errorCode': 'BRIDGE_TIMEOUT'},
          },
        );

        final (result, message) = await sendGroupMessage(
          bridge: timeoutPublishBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Publish timed out, inbox stored',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-publish-timeout-inbox-ok',
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'sent');
        expect(message.inboxStored, isTrue);
        expect(message.wireEnvelope, isNull);
        expect(message.inboxRetryPayload, isNull);

        final saved = await msgRepo.getMessage('msg-publish-timeout-inbox-ok');
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
        expect(saved.inboxStored, isTrue);
        expect(saved.wireEnvelope, isNull);
        expect(saved.inboxRetryPayload, isNull);
      },
    );

    test('inbox store ok:false is treated as inbox failure', () async {
      final okFalseBridge = _InboxStoreOkFalseBridge();
      okFalseBridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'msg-inbox-ok-false',
        'topicPeers': 3,
      };

      final (result, message) = await sendGroupMessage(
        bridge: okFalseBridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Inbox bridge says ok false',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'msg-inbox-ok-false',
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.status, 'pending');
      expect(message.inboxStored, isFalse);
      expect(message.inboxRetryPayload, isNotNull);

      final saved = await msgRepo.getMessage('msg-inbox-ok-false');
      expect(saved, isNotNull);
      expect(saved!.status, 'pending');
      expect(saved.inboxStored, isFalse);
      expect(saved.inboxRetryPayload, isNotNull);
    });

    test(
      'inbox store uses exactly one group:inboxStore call on success',
      () async {
        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-single-inbox',
          'topicPeers': 2,
        };

        await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Single inbox call',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
        );

        final inboxCalls = bridge.commandLog
            .where((c) => c == 'group:inboxStore')
            .length;
        expect(inboxCalls, 1);
      },
    );
  });
}
