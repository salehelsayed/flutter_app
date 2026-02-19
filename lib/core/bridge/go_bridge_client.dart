import 'dart:convert';

import 'package:flutter/services.dart';

import 'js_bridge_client.dart';
import '../utils/flow_event_emitter.dart';

/// Dart bridge client that communicates with the Go native library
/// via Flutter platform channels.
///
/// Extends [JsBridge] so it can be used as a drop-in replacement
/// for the JS WebView bridge. The [send] method translates the
/// cmd-based protocol to MethodChannel calls.
///
/// Push events from Go (message:received, peer:connected, etc.)
/// are streamed via [eventStream].
class GoBridgeClient extends JsBridge {
  static const _methodChannel = MethodChannel('com.mknoon/go_bridge');
  static const _eventChannel = EventChannel('com.mknoon/go_bridge_events');

  /// Stream of push events from the Go layer as JSON strings.
  ///
  /// Events follow the format: `{ "event": "<name>", "data": { ... } }`
  Stream<String> get eventStream =>
      _eventChannel.receiveBroadcastStream().map((event) => event as String);

  /// Map of cmd to (methodName, hasPayload).
  static const _cmdMap = <String, _CmdSpec>{
    'identity.generate': _CmdSpec('generateIdentity', false),
    'identity.restore': _CmdSpec('restoreIdentity', true),
    'mlkem.keygen': _CmdSpec('mlKemKeygen', false),
    'message.encrypt': _CmdSpec('encryptMessage', true),
    'message.decrypt': _CmdSpec('decryptMessage', true),
    'sign.payload': _CmdSpec('signPayload', true),
    'sign.verify': _CmdSpec('verifyPayload', true),
    'node.start': _CmdSpec('startNode', true),
    'node.stop': _CmdSpec('stopNode', false),
    'node.status': _CmdSpec('nodeStatus', false),
    'node.rendezvousRegister': _CmdSpec('rendezvousRegister', true),
    'node.rendezvousDiscover': _CmdSpec('rendezvousDiscover', true),
    'node.dialPeer': _CmdSpec('dialPeer', true),
    'node.disconnectPeer': _CmdSpec('disconnectPeer', true),
    'node.sendMessage': _CmdSpec('sendMessage', true),
    'node.inboxStore': _CmdSpec('inboxStore', true),
    'node.inboxRetrieve': _CmdSpec('inboxRetrieve', false),
    'node.inboxRegisterToken': _CmdSpec('inboxRegisterToken', true),
  };

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    final cmd = request['cmd'] as String;
    final payload = request['payload'] as Map<String, dynamic>?;

    final spec = _cmdMap[cmd];
    if (spec == null) {
      return jsonEncode({
        'ok': false,
        'errorCode': 'UNKNOWN_COMMAND',
        'errorMessage': 'Unknown command: $cmd',
      });
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'GO_BRIDGE_SEND',
      details: {'cmd': cmd, 'method': spec.methodName},
    );

    try {
      final String? result;
      if (spec.hasPayload && payload != null) {
        result = await _methodChannel.invokeMethod<String>(
          spec.methodName,
          jsonEncode(payload),
        );
      } else {
        result = await _methodChannel.invokeMethod<String>(spec.methodName);
      }

      return result ??
          jsonEncode({
            'ok': false,
            'errorCode': 'NULL_RESPONSE',
            'errorMessage': 'Native bridge returned null',
          });
    } on PlatformException catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GO_BRIDGE_PLATFORM_ERROR',
        details: {'cmd': cmd, 'error': e.message ?? 'unknown'},
      );
      return jsonEncode({
        'ok': false,
        'errorCode': 'PLATFORM_ERROR',
        'errorMessage': e.message ?? 'Platform channel error',
      });
    }
  }
}

class _CmdSpec {
  final String methodName;
  final bool hasPayload;

  const _CmdSpec(this.methodName, this.hasPayload);
}
