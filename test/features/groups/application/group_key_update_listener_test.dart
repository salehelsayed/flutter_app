import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/group_key_update_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late InMemoryGroupRepository groupRepo;
  late PassthroughCryptoBridge bridge;
  late StreamController<ChatMessage> controller;
  late GroupKeyUpdateListener listener;
  late String? mlKemSecretKey;

  ChatMessage _makeMessage(String content) {
    return ChatMessage(
      from: 'sender-peer',
      to: 'me',
      content: content,
      timestamp: DateTime.now().toUtc().toIso8601String(),
      isIncoming: true,
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

  test('saves key on successful decrypt', () async {
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

  test('group:updateKey bridge failure keeps the old key active', () async {
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
