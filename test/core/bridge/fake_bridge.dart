import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
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
  void Function(Map<String, dynamic>)? onGroupMessageReceived;

  @override
  void Function(Map<String, dynamic>)? onGroupReactionReceived;
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
      return jsonEncode({
        'ok': true,
        'plaintext': payload['ciphertext'],
      });
    }

    // Delegate to FakeBridge for all other commands
    return super.send(message);
  }
}
