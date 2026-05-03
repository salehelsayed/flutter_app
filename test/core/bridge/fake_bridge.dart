import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/db_write_transaction.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';

/// In-memory [Bridge] for tests.
///
/// Pre-canned responses per command, tracks call counts and last arguments.
class FakeBridge implements Bridge {
  bool _isInitialized = false;

  // Pre-canned JSON responses keyed by command name
  final Map<String, Map<String, dynamic>> responses = {};

  // Call tracking
  int sendCallCount = 0;
  int initializeCallCount = 0;
  int checkHealthCallCount = 0;
  int reinitializeCallCount = 0;
  int _blobKeygenCount = 0;

  /// Ordered log of all command names sent to the bridge.
  final List<String> commandLog = [];

  /// Ordered log of all raw JSON messages sent to the bridge.
  final List<String> sentMessages = [];

  // Last arguments
  String? lastSentMessage;
  String? lastCommand;

  // Configurable
  bool checkHealthResult = true;
  bool throwOnSend = false;
  String? throwOnSendMessage;
  bool throwOnCheckHealth = false;
  bool throwOnReinitialize = false;

  FakeBridge({Map<String, Map<String, dynamic>>? initialResponses}) {
    if (initialResponses != null) {
      responses.addAll(initialResponses);
    }
  }

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize() async {
    initializeCallCount++;
    _isInitialized = true;
  }

  @override
  Future<String> send(String message) async {
    // Mirror the production guard: never allow a bridge call to be issued
    // from inside a dbWriteTransaction body, so unit tests catch the
    // anti-pattern locally instead of relying on the live device's sqflite
    // "database has been locked" warning.
    final cmdPreview = (() {
      try {
        return (jsonDecode(message) as Map<String, dynamic>)['cmd']
                as String? ??
            '';
      } catch (_) {
        return '';
      }
    })();
    assertNotInsideDbWriteTransaction(commandPreview: cmdPreview);

    sendCallCount++;
    lastSentMessage = message;
    sentMessages.add(message);

    if (throwOnSend) {
      throw Exception(throwOnSendMessage ?? 'FakeBridge: send error');
    }

    // Parse command from message
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    lastCommand = cmd;
    if (cmd != null) commandLog.add(cmd);

    if (cmd == 'message.encrypt' && !responses.containsKey(cmd)) {
      final payload = parsed['payload'] as Map<String, dynamic>;
      return jsonEncode({
        'ok': true,
        'kem': 'fake-kem',
        'ciphertext': payload['plaintext'],
        'nonce': 'fake-nonce',
      });
    }

    if (cmd == 'message.decrypt' && !responses.containsKey(cmd)) {
      final payload = parsed['payload'] as Map<String, dynamic>;
      return jsonEncode({'ok': true, 'plaintext': payload['ciphertext']});
    }

    if (cmd == 'payload.sign' && !responses.containsKey(cmd)) {
      return jsonEncode({'ok': true, 'signature': 'fake-signature'});
    }

    if (cmd == 'payload.verify' && !responses.containsKey(cmd)) {
      return jsonEncode({'ok': true, 'valid': true});
    }

    if (cmd == 'group.encrypt' && !responses.containsKey(cmd)) {
      final payload = parsed['payload'] as Map<String, dynamic>;
      return jsonEncode({
        'ok': true,
        'ciphertext': payload['plaintext'],
        'nonce': 'fake-group-nonce',
      });
    }

    if (cmd == 'group.decrypt' && !responses.containsKey(cmd)) {
      final payload = parsed['payload'] as Map<String, dynamic>;
      return jsonEncode({'ok': true, 'plaintext': payload['ciphertext']});
    }

    if (cmd == 'blob:keygen' && !responses.containsKey(cmd)) {
      _blobKeygenCount++;
      return jsonEncode({
        'ok': true,
        'keyBase64': 'fake-blob-key-$_blobKeygenCount',
      });
    }

    if (cmd == 'blob:encrypt' && !responses.containsKey(cmd)) {
      final payload = parsed['payload'] as Map<String, dynamic>;
      final filePath = payload['filePath'] as String;
      final encryptedPath = '$filePath.enc';
      final source = File(filePath);
      if (await source.exists()) {
        await source.copy(encryptedPath);
      } else {
        await File(encryptedPath).writeAsBytes(<int>[1, 2, 3, 4]);
      }
      return jsonEncode({
        'ok': true,
        'encryptedPath': encryptedPath,
        'nonce': 'fake-blob-nonce-$_blobKeygenCount',
      });
    }

    if (cmd == 'blob:decrypt' && !responses.containsKey(cmd)) {
      final payload = parsed['payload'] as Map<String, dynamic>;
      final filePath = payload['filePath'] as String;
      final decryptedPath = '$filePath.dec';
      final encrypted = File(filePath);
      if (await encrypted.exists()) {
        await encrypted.copy(decryptedPath);
      } else {
        await File(decryptedPath).writeAsBytes(<int>[1, 2, 3, 4]);
      }
      return jsonEncode({'ok': true, 'decryptedPath': decryptedPath});
    }

    // Return pre-canned response or default success
    if (cmd != null && responses.containsKey(cmd)) {
      return jsonEncode(responses[cmd]!);
    }

    // Default: return ok response
    return jsonEncode({'ok': true});
  }

  @override
  Future<bool> checkHealth() async {
    checkHealthCallCount++;
    if (throwOnCheckHealth) {
      throw Exception('FakeBridge: checkHealth error');
    }
    return checkHealthResult;
  }

  @override
  Future<void> reinitialize() async {
    reinitializeCallCount++;
    if (throwOnReinitialize) {
      throw Exception('FakeBridge: reinitialize error');
    }
    _isInitialized = true;
  }

  @override
  void dispose() {
    _isInitialized = false;
  }

  @override
  void Function(ChatMessage)? onMessageReceived;

  @override
  void Function(ConnectionState)? onPeerConnected;

  @override
  void Function(ConnectionState)? onPeerDisconnected;

  @override
  void Function(List<String> listenAddresses, List<String> circuitAddresses)?
  onAddressesUpdated;

  @override
  void Function(Map<String, dynamic>)? onRelayStateChanged;

  @override
  void Function(Map<String, dynamic>)? onGroupMessageReceived;

  @override
  void Function(Map<String, dynamic>)? onGroupReactionReceived;

  // Upload media stubbing for smoke tests
  MediaAttachment? uploadMediaResult;
  List<MediaAttachment?> uploadMediaResultByCallIndex = [];
  int _uploadCallIndex = 0;

  /// Tracks total upload calls for multi-attachment assertions.
  int get uploadCallCount => _uploadCallIndex;

  MediaAttachment? consumeUploadMediaResult() {
    if (uploadMediaResultByCallIndex.isNotEmpty &&
        _uploadCallIndex < uploadMediaResultByCallIndex.length) {
      return uploadMediaResultByCallIndex[_uploadCallIndex++];
    }
    _uploadCallIndex++;
    return uploadMediaResult;
  }
}

/// A [FakeBridge] that passes plaintext through encrypt/decrypt transparently.
///
/// - `message.encrypt`: returns the plaintext as-is in the `ciphertext` field
/// - `message.decrypt`: returns the `ciphertext` field as-is in `plaintext`
///
/// This allows integration tests to exercise the full V2 encrypted path
/// without needing real cryptography.
class PassthroughCryptoBridge extends FakeBridge {
  @override
  Future<String> send(String message) async {
    // Peek at the command to intercept encrypt/decrypt
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    // Mirror the parent guard so the message.encrypt and message.decrypt
    // shortcut branches below cannot be invoked from inside a
    // dbWriteTransaction body. Without this, the parent's guard at the top
    // of FakeBridge.send is bypassed for those two commands because the
    // override returns before delegating to super.send.
    assertNotInsideDbWriteTransaction(commandPreview: cmd ?? '');

    if (cmd == 'message.encrypt') {
      // Track (same bookkeeping as FakeBridge.send)
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);

      final payload = parsed['payload'] as Map<String, dynamic>;
      return jsonEncode({
        'ok': true,
        'kem': 'fake-kem',
        'ciphertext': payload['plaintext'],
        'nonce': 'fake-nonce',
      });
    }

    if (cmd == 'message.decrypt') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);

      final payload = parsed['payload'] as Map<String, dynamic>;
      return jsonEncode({'ok': true, 'plaintext': payload['ciphertext']});
    }

    // Delegate to FakeBridge for all other commands
    return super.send(message);
  }
}

/// A [FakeBridge] that reports `topicPeers: 0` for `group:publish`.
class ZeroPeerPublishBridge extends FakeBridge {
  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    // Same dbWriteTransaction guard as the parent + the sibling subclass:
    // group:publish is also intercepted with an early return that would
    // otherwise bypass FakeBridge.send's guard.
    assertNotInsideDbWriteTransaction(commandPreview: cmd ?? '');

    if (cmd == 'group:publish') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);

      final payload = parsed['payload'] as Map<String, dynamic>;
      return jsonEncode({
        'ok': true,
        'messageId': payload['messageId'] ?? '',
        'topicPeers': 0,
      });
    }

    return super.send(message);
  }
}
