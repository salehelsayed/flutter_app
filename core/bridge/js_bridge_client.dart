import 'dart:convert';
import '../utils/flow_event_emitter.dart';

/// Abstract interface for bridge communication.
/// Implementations handle the actual message passing to JavaScript.
abstract class Bridge {
  /// Sends a request to the native layer and returns the raw response string.
  Future<String> send(String message);
}

/// Calls the bridge to generate a new identity.
///
/// Sends the "identity.generate" command to the native layer and returns
/// the parsed response as a Map.
///
/// Returns a Map containing:
/// - On success: `{ "ok": true, "identity": {...} }`
/// - On failure: `{ "ok": false, "errorCode": "...", "errorMessage": "..." }`
Future<Map<String, dynamic>> callIdentityGenerate(Bridge bridge) async {
  final request = {
    'cmd': 'identity.generate',
    'payload': <String, dynamic>{},
  };

  emitFlowEvent(
    layer: 'FL',
    event: 'ID_BRIDGE_IDENTITY_GENERATE_REQUEST',
    details: {'cmd': 'identity.generate'},
  );

  final responseJson = await bridge.send(jsonEncode(request));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'ID_BRIDGE_IDENTITY_GENERATE_RESPONSE',
    details: {'ok': response['ok']},
  );

  return response;
}
/// Calls the bridge to restore an identity from a 12-word mnemonic.
///
/// Sends an `identity.restore` command to the native core-lib and returns
/// the raw response map containing either the restored identity or an error.
///
/// Parameters:
///   - [bridge]: The bridge instance to use for communication
///   - [mnemonic12]: A string containing 12 BIP39 words separated by spaces
///
/// Returns:
///   A Map containing the response with either:
///   - Success: `{ "ok": true, "identity": { ... } }`
///   - Error: `{ "ok": false, "errorCode": "...", "errorMessage": "..." }`
Future<Map<String, dynamic>> callIdentityRestore(
  Bridge bridge,
  String mnemonic12,
) async {
  // Emit flow event before request
  emitFlowEvent(
    layer: 'FL',
    event: 'ID_BRIDGE_IDENTITY_RESTORE_REQUEST',
    details: {
      'wordCount': mnemonic12.split(' ').length,
    },
  );

  // Build the request payload
  final request = {
    'cmd': 'identity.restore',
    'payload': {
      'mnemonic12': mnemonic12,
    },
  };

  // Send request via bridge and get response
  final responseJson = await bridge.send(jsonEncode(request));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  // Emit flow event after response
  emitFlowEvent(
    layer: 'FL',
    event: 'ID_BRIDGE_IDENTITY_RESTORE_RESPONSE',
    details: {
      'ok': response['ok'],
      if (response['ok'] == false) 'errorCode': response['errorCode'],
    },
  );

  return response;
}