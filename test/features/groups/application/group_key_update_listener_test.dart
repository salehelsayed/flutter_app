import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/group_key_update_listener.dart';
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

    controller.add(_makeMessage(_validEnvelope(
      groupId: 'group-42',
      keyGeneration: 3,
      encryptedKey: 'new-key-abc',
    )));

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
    final failBridge = FakeBridge(initialResponses: {
      'message.decrypt': {'ok': false, 'errorCode': 'DECRYPT_FAILED'},
    });

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

  test('does not crash on malformed JSON', () async {
    listener.start();

    controller.add(_makeMessage('this is not valid json {{{'));

    await Future<void>.delayed(Duration.zero);

    // No key saved, no crash.
    final saved = await groupRepo.getLatestKey('group-1');
    expect(saved, isNull);
    expect(bridge.commandLog, isEmpty);
  });
}
