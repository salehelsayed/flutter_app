import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

/// Listens for incoming group_key_update messages (1:1 P2P) and saves
/// the new group key to the local repository.
///
/// These messages are sent by an admin after key rotation (e.g. after
/// removing a member). The new key is encrypted with the recipient's
/// ML-KEM public key.
class GroupKeyUpdateListener {
  final Stream<ChatMessage> _stream;
  final GroupRepository _groupRepo;
  final Bridge _bridge;
  final Future<String?> Function() _getOwnMlKemSecretKey;

  StreamSubscription<ChatMessage>? _subscription;

  GroupKeyUpdateListener({
    required Stream<ChatMessage> groupKeyUpdateStream,
    required GroupRepository groupRepo,
    required Bridge bridge,
    required Future<String?> Function() getOwnMlKemSecretKey,
  }) : _stream = groupKeyUpdateStream,
       _groupRepo = groupRepo,
       _bridge = bridge,
       _getOwnMlKemSecretKey = getOwnMlKemSecretKey;

  void start() {
    if (_subscription != null) return;

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_KEY_UPDATE_LISTENER_START',
      details: {},
    );

    _subscription = _stream.listen(
      _handleMessage,
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_KEY_UPDATE_LISTENER_ERROR',
          details: {'error': error.toString()},
        );
      },
    );
  }

  Future<void> _handleMessage(ChatMessage message) async {
    try {
      final json = jsonDecode(message.content) as Map<String, dynamic>;
      final encrypted = json['encrypted'] as Map<String, dynamic>?;
      if (encrypted == null) return;

      final kem = encrypted['kem'] as String;
      final ciphertext = encrypted['ciphertext'] as String;
      final nonce = encrypted['nonce'] as String;

      final secretKey = await _getOwnMlKemSecretKey();
      if (secretKey == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_KEY_UPDATE_LISTENER_NO_SECRET_KEY',
          details: {},
        );
        return;
      }

      final decryptResult = await callDecryptMessage(
        bridge: _bridge,
        ownMlKemSecretKey: secretKey,
        kem: kem,
        ciphertext: ciphertext,
        nonce: nonce,
      );

      if (decryptResult['ok'] != true) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_KEY_UPDATE_LISTENER_DECRYPT_FAILED',
          details: {'errorCode': decryptResult['errorCode']},
        );
        return;
      }

      final plaintext = decryptResult['plaintext'] as String;
      final keyData = jsonDecode(plaintext) as Map<String, dynamic>;
      final groupId = keyData['groupId'] as String;
      final keyGeneration = keyData['keyGeneration'] as int;
      final encryptedKey = keyData['encryptedKey'] as String;

      try {
        await callGroupUpdateKey(
          _bridge,
          groupId: groupId,
          groupKey: encryptedKey,
          keyEpoch: keyGeneration,
        );
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_KEY_UPDATE_LISTENER_UPDATE_KEY_FAILED',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'keyGeneration': keyGeneration,
            'error': e.toString(),
          },
        );
        return;
      }

      final keyInfo = GroupKeyInfo(
        groupId: groupId,
        keyGeneration: keyGeneration,
        encryptedKey: encryptedKey,
        createdAt: DateTime.now().toUtc(),
      );
      await _groupRepo.saveKey(keyInfo);

      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_KEY_UPDATE_LISTENER_SAVED',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'keyGeneration': keyGeneration,
        },
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_KEY_UPDATE_LISTENER_HANDLE_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stop();
  }
}
