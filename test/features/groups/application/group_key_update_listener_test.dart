import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/features/groups/application/group_key_update_listener.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late InMemoryGroupRepository groupRepo;
  late PassthroughCryptoBridge bridge;
  late StreamController<ChatMessage> controller;
  late GroupKeyUpdateListener listener;
  late String? mlKemSecretKey;

  ChatMessage _makeMessage(String content, {String? confirmNonce}) {
    return ChatMessage(
      from: 'sender-peer',
      to: 'me',
      content: content,
      timestamp: DateTime.now().toUtc().toIso8601String(),
      isIncoming: true,
      confirmNonce: confirmNonce,
    );
  }

  /// Builds a valid encrypted envelope whose inner plaintext is a JSON
  /// key-update payload.  Because PassthroughCryptoBridge echoes
  /// ciphertext back as plaintext, we set ciphertext = the key JSON.
  String _validEnvelope({
    String groupId = 'group-1',
    int keyGeneration = 2,
    String encryptedKey = 'base64-key-material',
  }) {
    final innerJson = jsonEncode({
      'groupId': groupId,
      'keyGeneration': keyGeneration,
      'encryptedKey': encryptedKey,
    });
    return jsonEncode({
      'encrypted': {
        'kem': 'fake-kem',
        'ciphertext': innerJson,
        'nonce': 'fake-nonce',
      },
    });
  }

  Future<void> _saveActiveGroup(String groupId) async {
    await groupRepo.saveGroup(
      GroupModel(
        id: groupId,
        name: 'Group $groupId',
        type: GroupType.chat,
        topicName: '/mknoon/group/$groupId',
        createdAt: DateTime.utc(2026, 4, 5, 12, 0),
        createdBy: 'sender-peer',
        myRole: GroupRole.member,
      ),
    );
  }

  Map<String, dynamic> _lastGroupOfflineReplayEnvelope(FakeBridge bridge) {
    final inboxMsg = bridge.sentMessages.lastWhere(
      (m) =>
          (jsonDecode(m) as Map<String, dynamic>)['cmd'] == 'group:inboxStore',
    );
    final payload =
        (jsonDecode(inboxMsg) as Map<String, dynamic>)['payload']
            as Map<String, dynamic>;
    return jsonDecode(payload['message'] as String) as Map<String, dynamic>;
  }

  setUp(() {
    groupRepo = InMemoryGroupRepository();
    bridge = PassthroughCryptoBridge();
    controller = StreamController<ChatMessage>.broadcast();
    mlKemSecretKey = 'my-secret-key';

    listener = GroupKeyUpdateListener(
      groupKeyUpdateStream: controller.stream,
      groupRepo: groupRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => mlKemSecretKey,
    );
  });

  tearDown(() {
    listener.dispose();
    controller.close();
  });

  test(
    'logs key update and rejects tampered replay before replacing key',
    () async {
      await _saveActiveGroup('group-log');
      final eventLog = _FakeEventLog();
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        appendGroupEventLogEntry: eventLog.append,
      );
      listener.start();

      controller.add(
        _makeMessage(
          _validEnvelope(
            groupId: 'group-log',
            keyGeneration: 2,
            encryptedKey: 'key-v2',
          ),
          confirmNonce: 'key-event-1',
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(eventLog.entries, hasLength(1));
      expect(eventLog.entries.single['eventType'], 'group_key_update');
      expect(eventLog.entries.single['sourceEventId'], 'key-event-1');
      expect(
        (await groupRepo.getLatestKey('group-log'))!.encryptedKey,
        'key-v2',
      );

      controller.add(
        _makeMessage(
          _validEnvelope(
            groupId: 'group-log',
            keyGeneration: 2,
            encryptedKey: 'tampered-key-v2',
          ),
          confirmNonce: 'key-event-1',
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(eventLog.entries, hasLength(1));
      expect(
        (await groupRepo.getLatestKey('group-log'))!.encryptedKey,
        'key-v2',
      );
    },
  );

  test(
    'exact duplicate key update replay keeps one log entry and final key',
    () async {
      await _saveActiveGroup('group-exact-replay');
      final eventLog = _FakeEventLog();
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        appendGroupEventLogEntry: eventLog.append,
      );
      listener.start();

      final message = _makeMessage(
        _validEnvelope(
          groupId: 'group-exact-replay',
          keyGeneration: 2,
          encryptedKey: 'key-v2',
        ),
        confirmNonce: 'key-exact-replay-1',
      );

      controller.add(message);
      controller.add(message);

      await Future<void>.delayed(Duration.zero);

      expect(eventLog.entries, hasLength(1));
      expect(eventLog.entries.single['eventType'], 'group_key_update');
      expect(eventLog.entries.single['sourceEventId'], 'key-exact-replay-1');

      final saved = await groupRepo.getLatestKey('group-exact-replay');
      expect(saved, isNotNull);
      expect(saved!.keyGeneration, 2);
      expect(saved.encryptedKey, 'key-v2');
    },
  );

  test(
    'direct key guard ignores missing group without bridge update, log, or key save',
    () async {
      final eventLog = _FakeEventLog();
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        appendGroupEventLogEntry: eventLog.append,
      );
      listener.start();

      controller.add(
        _makeMessage(
          _validEnvelope(
            groupId: 'missing-direct-key-group',
            keyGeneration: 2,
            encryptedKey: 'new-key-for-missing-group',
          ),
          confirmNonce: 'missing-direct-key-event',
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(bridge.commandLog, contains('message.decrypt'));
      expect(bridge.commandLog, isNot(contains('group:updateKey')));
      expect(eventLog.entries, isEmpty);
      expect(await groupRepo.getLatestKey('missing-direct-key-group'), isNull);
    },
  );

  test(
    'direct key guard ignores dissolved group without bridge update, log, or key replacement',
    () async {
      await groupRepo.saveGroup(
        GroupModel(
          id: 'dissolved-direct-key-group',
          name: 'Dissolved Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/dissolved-direct-key-group',
          createdAt: DateTime.utc(2026, 4, 5, 12, 0),
          createdBy: 'sender-peer',
          myRole: GroupRole.member,
          isDissolved: true,
          dissolvedAt: DateTime.utc(2026, 4, 5, 12, 30),
          dissolvedBy: 'sender-peer',
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'dissolved-direct-key-group',
          keyGeneration: 1,
          encryptedKey: 'old-dissolved-key',
          createdAt: DateTime.utc(2026, 4, 5, 12, 1),
        ),
      );
      final eventLog = _FakeEventLog();
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        appendGroupEventLogEntry: eventLog.append,
      );
      listener.start();

      controller.add(
        _makeMessage(
          _validEnvelope(
            groupId: 'dissolved-direct-key-group',
            keyGeneration: 2,
            encryptedKey: 'new-dissolved-key',
          ),
          confirmNonce: 'dissolved-direct-key-event',
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(bridge.commandLog, contains('message.decrypt'));
      expect(bridge.commandLog, isNot(contains('group:updateKey')));
      expect(eventLog.entries, isEmpty);
      final latest = await groupRepo.getLatestKey('dissolved-direct-key-group');
      expect(latest, isNotNull);
      expect(latest!.keyGeneration, 1);
      expect(latest.encryptedKey, 'old-dissolved-key');
      expect(
        await groupRepo.getKeyByGeneration('dissolved-direct-key-group', 2),
        isNull,
      );
    },
  );

  test('saves key on successful decrypt', () async {
    await _saveActiveGroup('group-42');
    listener.start();

    controller.add(
      _makeMessage(
        _validEnvelope(
          groupId: 'group-42',
          keyGeneration: 3,
          encryptedKey: 'new-key-abc',
        ),
      ),
    );

    // Allow the async listener pipeline to complete.
    await Future<void>.delayed(Duration.zero);

    final saved = await groupRepo.getLatestKey('group-42');
    expect(saved, isNotNull);
    expect(saved!.groupId, 'group-42');
    expect(saved.keyGeneration, 3);
    expect(saved.encryptedKey, 'new-key-abc');

    // Verify the bridge was called with message.decrypt
    expect(bridge.commandLog, contains('message.decrypt'));
  });

  test('promotes key only after group:updateKey succeeds', () async {
    await _saveActiveGroup('group-delay');
    final updateCompleter = Completer<String>();
    final delayedBridge = _DelayedUpdateKeyBridge(updateCompleter);

    final delayedListener = GroupKeyUpdateListener(
      groupKeyUpdateStream: controller.stream,
      groupRepo: groupRepo,
      bridge: delayedBridge,
      getOwnMlKemSecretKey: () async => 'my-secret-key',
    );
    delayedListener.start();

    controller.add(
      _makeMessage(
        _validEnvelope(
          groupId: 'group-delay',
          keyGeneration: 2,
          encryptedKey: 'pending-key',
        ),
      ),
    );

    await Future<void>.delayed(Duration.zero);

    expect(delayedBridge.commandLog, contains('message.decrypt'));
    expect(delayedBridge.commandLog, contains('group:updateKey'));
    expect(await groupRepo.getLatestKey('group-delay'), isNull);

    updateCompleter.complete(jsonEncode({'ok': true}));
    await Future<void>.delayed(Duration.zero);

    final saved = await groupRepo.getLatestKey('group-delay');
    expect(saved, isNotNull);
    expect(saved!.keyGeneration, 2);
    expect(saved.encryptedKey, 'pending-key');

    delayedListener.dispose();
  });

  test(
    'send during pending key update uses old epoch until local update commits',
    () async {
      await groupRepo.saveGroup(
        GroupModel(
          id: 'group-pending-send',
          name: 'Pending Send Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/group-pending-send',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'peer-b',
          myRole: GroupRole.member,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-pending-send',
          peerId: 'peer-b',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-b',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-pending-send',
          keyGeneration: 1,
          encryptedKey: 'old-key',
          createdAt: DateTime.now().toUtc(),
        ),
      );

      final updateCompleter = Completer<String>();
      final delayedBridge = _DelayedUpdateKeyBridge(updateCompleter);
      delayedBridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'publish-ok',
        'topicPeers': 1,
      };
      final delayedListener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: delayedBridge,
        getOwnMlKemSecretKey: () async => 'my-secret-key',
      );
      final msgRepo = InMemoryGroupMessageRepository();

      delayedListener.start();
      controller.add(
        _makeMessage(
          _validEnvelope(
            groupId: 'group-pending-send',
            keyGeneration: 2,
            encryptedKey: 'new-key',
          ),
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(delayedBridge.commandLog, contains('group:updateKey'));
      final latestWhilePending = await groupRepo.getLatestKey(
        'group-pending-send',
      );
      expect(latestWhilePending, isNotNull);
      expect(latestWhilePending!.keyGeneration, 1);
      expect(
        await groupRepo.getKeyByGeneration('group-pending-send', 2),
        isNull,
      );

      final (duringResult, duringMessage) = await sendGroupMessage(
        bridge: delayedBridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-pending-send',
        text: 'During pending key update',
        senderPeerId: 'peer-b',
        senderPublicKey: 'pk-b',
        senderPrivateKey: 'sk-b',
        senderUsername: 'Bob',
        messageId: 'msg-pending-update-during',
      );

      expect(duringResult, SendGroupMessageResult.success);
      expect(duringMessage, isNotNull);
      expect(duringMessage!.keyGeneration, 1);
      expect(_lastGroupOfflineReplayEnvelope(delayedBridge)['keyEpoch'], 1);

      updateCompleter.complete(jsonEncode({'ok': true}));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final latestAfterCommit = await groupRepo.getLatestKey(
        'group-pending-send',
      );
      expect(latestAfterCommit, isNotNull);
      expect(latestAfterCommit!.keyGeneration, 2);

      final (afterResult, afterMessage) = await sendGroupMessage(
        bridge: delayedBridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-pending-send',
        text: 'After pending key update',
        senderPeerId: 'peer-b',
        senderPublicKey: 'pk-b',
        senderPrivateKey: 'sk-b',
        senderUsername: 'Bob',
        messageId: 'msg-pending-update-after',
      );

      expect(afterResult, SendGroupMessageResult.success);
      expect(afterMessage, isNotNull);
      expect(afterMessage!.keyGeneration, 2);
      expect(_lastGroupOfflineReplayEnvelope(delayedBridge)['keyEpoch'], 2);

      delayedListener.dispose();
    },
  );

  test('returns early when encrypted field is null', () async {
    listener.start();

    // Envelope without the 'encrypted' key.
    final content = jsonEncode({'type': 'group_key_update', 'payload': {}});
    controller.add(_makeMessage(content));

    await Future<void>.delayed(Duration.zero);

    // No key should have been saved.
    final saved = await groupRepo.getLatestKey('group-1');
    expect(saved, isNull);

    // Bridge should NOT have been called at all.
    expect(bridge.commandLog, isEmpty);
  });

  test('returns early when own ML-KEM secret key is null', () async {
    mlKemSecretKey = null;
    listener.start();

    controller.add(_makeMessage(_validEnvelope()));

    await Future<void>.delayed(Duration.zero);

    // No decrypt should have been attempted.
    expect(bridge.commandLog, isEmpty);

    // No key saved.
    final saved = await groupRepo.getLatestKey('group-1');
    expect(saved, isNull);
  });

  test('returns early when decrypt fails (ok: false)', () async {
    // Override message.decrypt to return a failure response.
    final failBridge = FakeBridge(
      initialResponses: {
        'message.decrypt': {'ok': false, 'errorCode': 'DECRYPT_FAILED'},
      },
    );

    final failListener = GroupKeyUpdateListener(
      groupKeyUpdateStream: controller.stream,
      groupRepo: groupRepo,
      bridge: failBridge,
      getOwnMlKemSecretKey: () async => 'my-secret-key',
    );

    failListener.start();

    controller.add(_makeMessage(_validEnvelope()));

    await Future<void>.delayed(Duration.zero);

    // Decrypt was called but returned ok: false.
    expect(failBridge.commandLog, contains('message.decrypt'));

    // No key saved.
    final saved = await groupRepo.getLatestKey('group-1');
    expect(saved, isNull);

    failListener.dispose();
  });

  test('saves key to DB AND updates Go via group:updateKey', () async {
    await _saveActiveGroup('group-99');
    listener.start();

    controller.add(
      _makeMessage(
        _validEnvelope(
          groupId: 'group-99',
          keyGeneration: 5,
          encryptedKey: 'rotated-key-xyz',
        ),
      ),
    );

    // Allow the async listener pipeline to complete.
    await Future<void>.delayed(Duration.zero);

    // Verify key was saved to DB.
    final saved = await groupRepo.getLatestKey('group-99');
    expect(saved, isNotNull);
    expect(saved!.groupId, 'group-99');
    expect(saved.keyGeneration, 5);
    expect(saved.encryptedKey, 'rotated-key-xyz');

    // Verify bridge was called with message.decrypt (for decryption)
    // AND group:updateKey (to update Go's stored key).
    expect(bridge.commandLog, contains('message.decrypt'));
    expect(bridge.commandLog, contains('group:updateKey'));
  });

  test('does not crash on malformed JSON', () async {
    listener.start();

    controller.add(_makeMessage('this is not valid json {{{'));

    await Future<void>.delayed(Duration.zero);

    // No key saved, no crash.
    final saved = await groupRepo.getLatestKey('group-1');
    expect(saved, isNull);
    expect(bridge.commandLog, isEmpty);
  });

  test(
    'group:updateKey payload contains correct groupId, groupKey, keyEpoch',
    () async {
      await _saveActiveGroup('group-77');
      listener.start();

      controller.add(
        _makeMessage(
          _validEnvelope(
            groupId: 'group-77',
            keyGeneration: 4,
            encryptedKey: 'specific-key-material',
          ),
        ),
      );

      await Future<void>.delayed(Duration.zero);

      // Find the group:updateKey command in sentMessages
      final updateKeyMsg = bridge.sentMessages.firstWhere((m) {
        final parsed = jsonDecode(m) as Map<String, dynamic>;
        return parsed['cmd'] == 'group:updateKey';
      });
      final payload =
          (jsonDecode(updateKeyMsg) as Map<String, dynamic>)['payload']
              as Map<String, dynamic>;

      expect(payload['groupId'], 'group-77');
      expect(payload['groupKey'], 'specific-key-material');
      expect(payload['keyEpoch'], 4);
    },
  );

  test('handles sequential key updates (epoch 2 then epoch 3)', () async {
    await _saveActiveGroup('group-seq');
    listener.start();

    // Send epoch 2
    controller.add(
      _makeMessage(
        _validEnvelope(
          groupId: 'group-seq',
          keyGeneration: 2,
          encryptedKey: 'key-epoch-2',
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    // Send epoch 3
    controller.add(
      _makeMessage(
        _validEnvelope(
          groupId: 'group-seq',
          keyGeneration: 3,
          encryptedKey: 'key-epoch-3',
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    // Both should be saved to DB
    final key2 = await groupRepo.getKeyByGeneration('group-seq', 2);
    expect(key2, isNotNull);
    expect(key2!.encryptedKey, 'key-epoch-2');

    final key3 = await groupRepo.getKeyByGeneration('group-seq', 3);
    expect(key3, isNotNull);
    expect(key3!.encryptedKey, 'key-epoch-3');

    // Latest key should be epoch 3
    final latest = await groupRepo.getLatestKey('group-seq');
    expect(latest!.keyGeneration, 3);

    // Both should have triggered group:updateKey
    final updateKeyCount = bridge.commandLog
        .where((c) => c == 'group:updateKey')
        .length;
    expect(updateKeyCount, 2);
  });

  test(
    'conflicting same-generation key updates converge to one final stored key',
    () async {
      await _saveActiveGroup('group-race');
      listener.start();

      controller.add(
        _makeMessage(
          _validEnvelope(
            groupId: 'group-race',
            keyGeneration: 2,
            encryptedKey: 'key-epoch-2a',
          ),
        ),
      );
      controller.add(
        _makeMessage(
          _validEnvelope(
            groupId: 'group-race',
            keyGeneration: 2,
            encryptedKey: 'key-epoch-2b',
          ),
        ),
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final converged = await groupRepo.getKeyByGeneration('group-race', 2);
      expect(converged, isNotNull);
      expect(converged!.encryptedKey, 'key-epoch-2b');

      final latest = await groupRepo.getLatestKey('group-race');
      expect(latest, isNotNull);
      expect(latest!.keyGeneration, 2);
      expect(latest.encryptedKey, 'key-epoch-2b');

      final updateKeyCount = bridge.commandLog
          .where((c) => c == 'group:updateKey')
          .length;
      expect(updateKeyCount, 2);
    },
  );

  test('group:updateKey bridge failure keeps the old key active', () async {
    await _saveActiveGroup('group-fail');
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: 'group-fail',
        keyGeneration: 1,
        encryptedKey: 'old-key',
        createdAt: DateTime.now().toUtc(),
      ),
    );

    // Custom bridge that passes decrypt but fails updateKey
    final failUpdateKeyBridge = _UpdateKeyFailBridge();

    final failListener = GroupKeyUpdateListener(
      groupKeyUpdateStream: controller.stream,
      groupRepo: groupRepo,
      bridge: failUpdateKeyBridge,
      getOwnMlKemSecretKey: () async => 'my-secret-key',
    );

    failListener.start();

    controller.add(
      _makeMessage(
        _validEnvelope(
          groupId: 'group-fail',
          keyGeneration: 2,
          encryptedKey: 'key-despite-bridge-fail',
        ),
      ),
    );

    await Future<void>.delayed(Duration.zero);

    final saved = await groupRepo.getLatestKey('group-fail');
    expect(saved, isNotNull);
    expect(saved!.encryptedKey, 'old-key');
    expect(saved.keyGeneration, 1);
    expect(await groupRepo.getKeyByGeneration('group-fail', 2), isNull);

    // Bridge was called for both decrypt and updateKey
    expect(failUpdateKeyBridge.commandLog, contains('message.decrypt'));
    expect(failUpdateKeyBridge.commandLog, contains('group:updateKey'));

    failListener.dispose();
  });
}

/// A PassthroughCryptoBridge that returns {ok: false} for group:updateKey
/// but handles encrypt/decrypt normally.
class _UpdateKeyFailBridge extends PassthroughCryptoBridge {
  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:updateKey') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      return jsonEncode({'ok': false, 'errorCode': 'UPDATE_KEY_FAILED'});
    }
    return super.send(message);
  }
}

class _DelayedUpdateKeyBridge extends PassthroughCryptoBridge {
  final Completer<String> _updateCompleter;

  _DelayedUpdateKeyBridge(this._updateCompleter);

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:updateKey') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      return _updateCompleter.future;
    }
    return super.send(message);
  }
}

class _FakeEventLog {
  final entries = <Map<String, Object?>>[];
  final _payloadBySourceEventId = <String, String>{};

  Future<Map<String, Object?>> append({
    required String groupId,
    required String eventType,
    required String sourcePeerId,
    required String sourceEventId,
    required String sourceTimestamp,
    required Map<String, Object?> payload,
    DateTime? createdAt,
  }) async {
    final canonical = canonicalizeGroupEventLogPayload(payload);
    final existing = _payloadBySourceEventId[sourceEventId];
    if (existing != null && existing != canonical) {
      throw GroupEventLogTamperException('conflicting replay');
    }
    _payloadBySourceEventId[sourceEventId] = canonical;
    final entry = {
      'groupId': groupId,
      'eventType': eventType,
      'sourcePeerId': sourcePeerId,
      'sourceEventId': sourceEventId,
      'sourceTimestamp': sourceTimestamp,
      'payload': payload,
    };
    if (existing == null) {
      entries.add(entry);
    }
    return entry;
  }
}
