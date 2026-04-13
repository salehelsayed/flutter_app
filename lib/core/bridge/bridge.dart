import 'dart:async';
import 'dart:convert';
import '../../features/p2p/domain/models/chat_message.dart';
import '../../features/p2p/domain/models/connection_state.dart';
import '../utils/flow_event_emitter.dart';

/// Abstract interface for bridge communication.
/// Implementations handle the actual message passing to the native layer.
abstract class Bridge {
  /// Sends a request to the bridge and returns the raw response string.
  Future<String> send(String message);

  /// Initialize the bridge. Must be called before [send].
  Future<void> initialize();

  /// Check if the bridge is still responsive.
  Future<bool> checkHealth();

  /// Tear down and recreate the bridge.
  Future<void> reinitialize();

  /// Release resources held by the bridge.
  void dispose();

  /// Whether the bridge has been initialized.
  bool get isInitialized;

  /// Event callback for incoming chat messages.
  void Function(ChatMessage)? onMessageReceived;

  /// Event callback when a peer connects.
  void Function(ConnectionState)? onPeerConnected;

  /// Event callback when a peer disconnects.
  void Function(ConnectionState)? onPeerDisconnected;

  /// Event callback when local addresses change (circuit relay acquired/lost).
  void Function(List<String> listenAddresses, List<String> circuitAddresses)?
  onAddressesUpdated;

  /// Event callback when relay session state changes.
  void Function(Map<String, dynamic>)? onRelayStateChanged;

  /// Event callback for incoming group messages.
  void Function(Map<String, dynamic>)? onGroupMessageReceived;

  /// Event callback for incoming group reactions.
  void Function(Map<String, dynamic>)? onGroupReactionReceived;
}

final StreamController<Map<String, dynamic>> _mediaUploadProgressController =
    StreamController<Map<String, dynamic>>.broadcast(sync: true);
final StreamController<Map<String, dynamic>> _groupDiagnosticEventController =
    StreamController<Map<String, dynamic>>.broadcast(sync: true);

/// Broadcast stream for relay media-upload progress events emitted by the
/// active bridge implementation.
Stream<Map<String, dynamic>> get mediaUploadProgressStream =>
    _mediaUploadProgressController.stream;

/// Broadcast stream for group diagnostic events emitted by the active bridge.
Stream<Map<String, dynamic>> get groupDiagnosticEventStream =>
    _groupDiagnosticEventController.stream;

/// Publishes a media-upload progress event to Flutter listeners.
void emitMediaUploadProgressEvent(Map<String, dynamic> data) {
  _mediaUploadProgressController.add(Map<String, dynamic>.from(data));
}

/// Publishes a group diagnostic event to Flutter listeners.
void emitGroupDiagnosticEvent(String eventName, Map<String, dynamic> data) {
  _groupDiagnosticEventController.add({
    'event': eventName,
    ...Map<String, dynamic>.from(data),
  });
}

/// Calls the bridge to generate a new identity.
///
/// Sends the "identity.generate" command and returns
/// the parsed response as a Map.
///
/// Returns a Map containing:
/// - On success: `{ "ok": true, "identity": {...} }`
/// - On failure: `{ "ok": false, "errorCode": "...", "errorMessage": "..." }`
Future<Map<String, dynamic>> callIdentityGenerate(
  Bridge bridge, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final request = {'cmd': 'identity.generate', 'payload': <String, dynamic>{}};

  emitFlowEvent(
    layer: 'FL',
    event: 'ID_BRIDGE_IDENTITY_GENERATE_REQUEST',
    details: {'cmd': 'identity.generate'},
  );

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    emitFlowEvent(
      layer: 'FL',
      event: 'ID_BRIDGE_IDENTITY_GENERATE_RESPONSE',
      details: {'ok': response['ok']},
    );

    return response;
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_BRIDGE_IDENTITY_GENERATE_RESPONSE',
      details: {'ok': false, 'errorCode': 'BRIDGE_TIMEOUT'},
    );

    return {
      'ok': false,
      'errorCode': 'BRIDGE_TIMEOUT',
      'errorMessage': 'Bridge call timed out after ${timeout.inSeconds}s',
    };
  }
}

/// Calls the bridge to restore an identity from a 12-word mnemonic.
///
/// Sends an `identity.restore` command to the core-lib and returns
/// the raw response map containing either the restored identity or an error.
///
/// Parameters:
///   - [bridge]: The Bridge instance to use for communication
///   - [mnemonic12]: A string containing 12 BIP39 words separated by spaces
///
/// Returns:
///   A Map containing the response with either:
///   - Success: `{ "ok": true, "identity": { ... } }`
///   - Error: `{ "ok": false, "errorCode": "...", "errorMessage": "..." }`
Future<Map<String, dynamic>> callIdentityRestore(
  Bridge bridge,
  String mnemonic12, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  // Emit flow event before request
  emitFlowEvent(
    layer: 'FL',
    event: 'ID_BRIDGE_IDENTITY_RESTORE_REQUEST',
    details: {'wordCount': mnemonic12.split(' ').length},
  );

  // Build the request payload
  final request = {
    'cmd': 'identity.restore',
    'payload': {'mnemonic12': mnemonic12},
  };

  try {
    // Send request via bridge and get response
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
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
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_BRIDGE_IDENTITY_RESTORE_RESPONSE',
      details: {'ok': false, 'errorCode': 'BRIDGE_TIMEOUT'},
    );

    return {
      'ok': false,
      'errorCode': 'BRIDGE_TIMEOUT',
      'errorMessage': 'Bridge call timed out after ${timeout.inSeconds}s',
    };
  }
}

/// Calls the bridge to verify an Ed25519 signature.
///
/// Parameters:
///   - [bridge]: The Bridge instance to use for communication
///   - [publicKey]: Base64-encoded Ed25519 public key
///   - [data]: The data that was signed (canonical JSON string)
///   - [signature]: Base64-encoded signature to verify
///
/// Returns true if signature is valid, false otherwise.
Future<bool> callVerifyPayload({
  required Bridge bridge,
  required String publicKey,
  required String data,
  required String signature,
  Duration timeout = const Duration(seconds: 10),
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'QR_FL_BRIDGE_VERIFY_REQUEST',
    details: {'dataLength': data.length},
  );

  final request = {
    'cmd': 'payload.verify',
    'payload': {'publicKey': publicKey, 'data': data, 'signature': signature},
  };

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    // Check both: ok means request succeeded, valid means signature is valid
    final requestOk = response['ok'] == true;
    final signatureValid = response['valid'] == true;
    final isValid = requestOk && signatureValid;

    emitFlowEvent(
      layer: 'FL',
      event: 'QR_FL_BRIDGE_VERIFY_RESPONSE',
      details: {
        'requestOk': requestOk,
        'signatureValid': signatureValid,
        if (!requestOk) 'errorCode': response['errorCode'],
        if (!requestOk) 'errorMessage': response['errorMessage'],
      },
    );

    return isValid;
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'QR_FL_BRIDGE_VERIFY_RESPONSE',
      details: {'valid': false, 'errorCode': 'BRIDGE_TIMEOUT'},
    );
    return false;
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'QR_FL_BRIDGE_VERIFY_RESPONSE',
      details: {'valid': false, 'error': e.toString()},
    );
    return false;
  }
}

/// Calls the bridge to sign payload data with Ed25519.
///
/// This function MUST use the real bridge for cryptographic signing.
/// Ed25519 signing is implemented natively - DO NOT fake this in Dart.
///
/// Parameters:
///   - [bridge]: The Bridge instance to use for communication
///   - [dataToSign]: The canonical JSON string to sign
///   - [privateKey]: Base64-encoded Ed25519 private key
///
/// Returns a map with:
/// - On success: `{ "ok": true, "signature": "base64..." }`
/// - On error: `{ "ok": false, "errorCode": "...", "errorMessage": "..." }`
Future<Map<String, dynamic>> callSignPayload({
  required Bridge bridge,
  required String dataToSign,
  required String privateKey,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final correlationId = DateTime.now().microsecondsSinceEpoch.toString();

  emitFlowEvent(
    layer: 'FL',
    event: 'QR_FL_BRIDGE_SIGN_REQUEST',
    details: {'dataLength': dataToSign.length, 'correlationId': correlationId},
  );

  final request = {
    'cmd': 'payload.sign',
    'payload': {'data': dataToSign, 'privateKey': privateKey},
  };

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    emitFlowEvent(
      layer: 'FL',
      event: 'QR_FL_BRIDGE_SIGN_RESPONSE',
      details: {'ok': response['ok'] ?? false, 'correlationId': correlationId},
    );

    return response;
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'QR_FL_BRIDGE_SIGN_RESPONSE',
      details: {
        'ok': false,
        'errorCode': 'BRIDGE_TIMEOUT',
        'correlationId': correlationId,
      },
    );

    return {
      'ok': false,
      'errorCode': 'BRIDGE_TIMEOUT',
      'errorMessage': 'Bridge call timed out after ${timeout.inSeconds}s',
    };
  }
}

/// Calls the bridge to generate an ML-KEM-768 key pair.
///
/// Returns a map with:
/// - On success: `{ "ok": true, "publicKey": "base64...", "secretKey": "base64..." }`
/// - On error: `{ "ok": false, "errorCode": "...", "errorMessage": "..." }`
Future<Map<String, dynamic>> callMlKemKeygen(
  Bridge bridge, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'MLKEM_FL_BRIDGE_KEYGEN_REQUEST',
    details: {},
  );

  final request = {'cmd': 'mlkem.keygen', 'payload': <String, dynamic>{}};

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    emitFlowEvent(
      layer: 'FL',
      event: 'MLKEM_FL_BRIDGE_KEYGEN_RESPONSE',
      details: {'ok': response['ok']},
    );

    return response;
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'MLKEM_FL_BRIDGE_KEYGEN_RESPONSE',
      details: {'ok': false, 'errorCode': 'BRIDGE_TIMEOUT'},
    );

    return {
      'ok': false,
      'errorCode': 'BRIDGE_TIMEOUT',
      'errorMessage': 'Bridge call timed out after ${timeout.inSeconds}s',
    };
  }
}

/// Calls the bridge to encrypt a contact request using X25519 ECDH + AES-256-GCM.
///
/// Returns a map with:
/// - On success: `{ "ok": true, "ephemeralPublicKey": "base64...", "ciphertext": "base64...", "nonce": "base64..." }`
/// - On error: `{ "ok": false, "errorCode": "...", "errorMessage": "..." }`
Future<Map<String, dynamic>> callEncryptContactRequest({
  required Bridge bridge,
  required String recipientPublicKey,
  required String signedPayloadJson,
  required String msgId,
  required String ts,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final correlationId = DateTime.now().microsecondsSinceEpoch.toString();

  emitFlowEvent(
    layer: 'FL',
    event: 'CR_FL_BRIDGE_ENCRYPT_REQUEST',
    details: {
      'plaintextLength': signedPayloadJson.length,
      'correlationId': correlationId,
    },
  );

  final request = {
    'cmd': 'contactrequest.encrypt',
    'payload': {
      'recipientPublicKey': recipientPublicKey,
      'plaintext': signedPayloadJson,
      'msgId': msgId,
      'ts': ts,
    },
  };

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    emitFlowEvent(
      layer: 'FL',
      event: 'CR_FL_BRIDGE_ENCRYPT_RESPONSE',
      details: {'ok': response['ok'] ?? false, 'correlationId': correlationId},
    );

    return response;
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'CR_FL_BRIDGE_ENCRYPT_RESPONSE',
      details: {
        'ok': false,
        'errorCode': 'BRIDGE_TIMEOUT',
        'correlationId': correlationId,
      },
    );

    return {
      'ok': false,
      'errorCode': 'BRIDGE_TIMEOUT',
      'errorMessage': 'Bridge call timed out after ${timeout.inSeconds}s',
    };
  }
}

/// Calls the bridge to decrypt a v2 contact request using own Ed25519 private key.
///
/// Returns a map with:
/// - On success: `{ "ok": true, "plaintext": "..." }`
/// - On error: `{ "ok": false, "errorCode": "...", "errorMessage": "..." }`
Future<Map<String, dynamic>> callDecryptContactRequest({
  required Bridge bridge,
  required String ownPrivateKey,
  required String ephemeralPublicKey,
  required String ciphertext,
  required String nonce,
  required String msgId,
  required String ts,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final correlationId = DateTime.now().microsecondsSinceEpoch.toString();

  emitFlowEvent(
    layer: 'FL',
    event: 'CR_FL_BRIDGE_DECRYPT_REQUEST',
    details: {'correlationId': correlationId},
  );

  final request = {
    'cmd': 'contactrequest.decrypt',
    'payload': {
      'privateKey': ownPrivateKey,
      'ephemeralPublicKey': ephemeralPublicKey,
      'ciphertext': ciphertext,
      'nonce': nonce,
      'msgId': msgId,
      'ts': ts,
    },
  };

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    emitFlowEvent(
      layer: 'FL',
      event: 'CR_FL_BRIDGE_DECRYPT_RESPONSE',
      details: {'ok': response['ok'] ?? false, 'correlationId': correlationId},
    );

    return response;
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'CR_FL_BRIDGE_DECRYPT_RESPONSE',
      details: {
        'ok': false,
        'errorCode': 'BRIDGE_TIMEOUT',
        'correlationId': correlationId,
      },
    );

    return {
      'ok': false,
      'errorCode': 'BRIDGE_TIMEOUT',
      'errorMessage': 'Bridge call timed out after ${timeout.inSeconds}s',
    };
  }
}

/// Calls the bridge to encrypt a message using ML-KEM-768 + AES-256-GCM.
///
/// Returns a map with:
/// - On success: `{ "ok": true, "kem": "base64...", "ciphertext": "base64...", "nonce": "base64..." }`
/// - On error: `{ "ok": false, "errorCode": "...", "errorMessage": "..." }`
Future<Map<String, dynamic>> callEncryptMessage({
  required Bridge bridge,
  required String recipientMlKemPublicKey,
  required String plaintext,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final correlationId = DateTime.now().microsecondsSinceEpoch.toString();

  emitFlowEvent(
    layer: 'FL',
    event: 'MLKEM_FL_BRIDGE_ENCRYPT_REQUEST',
    details: {
      'plaintextLength': plaintext.length,
      'correlationId': correlationId,
    },
  );

  final request = {
    'cmd': 'message.encrypt',
    'payload': {
      'recipientPublicKey': recipientMlKemPublicKey,
      'plaintext': plaintext,
    },
  };

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    emitFlowEvent(
      layer: 'FL',
      event: 'MLKEM_FL_BRIDGE_ENCRYPT_RESPONSE',
      details: {'ok': response['ok'] ?? false, 'correlationId': correlationId},
    );

    return response;
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'MLKEM_FL_BRIDGE_ENCRYPT_RESPONSE',
      details: {
        'ok': false,
        'errorCode': 'BRIDGE_TIMEOUT',
        'correlationId': correlationId,
      },
    );

    return {
      'ok': false,
      'errorCode': 'BRIDGE_TIMEOUT',
      'errorMessage': 'Bridge call timed out after ${timeout.inSeconds}s',
    };
  }
}

/// Calls the bridge to decrypt a message using ML-KEM-768 + AES-256-GCM.
///
/// Returns a map with:
/// - On success: `{ "ok": true, "plaintext": "..." }`
/// - On error: `{ "ok": false, "errorCode": "...", "errorMessage": "..." }`
Future<Map<String, dynamic>> callDecryptMessage({
  required Bridge bridge,
  required String ownMlKemSecretKey,
  required String kem,
  required String ciphertext,
  required String nonce,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final correlationId = DateTime.now().microsecondsSinceEpoch.toString();

  emitFlowEvent(
    layer: 'FL',
    event: 'MLKEM_FL_BRIDGE_DECRYPT_REQUEST',
    details: {'correlationId': correlationId},
  );

  final request = {
    'cmd': 'message.decrypt',
    'payload': {
      'secretKey': ownMlKemSecretKey,
      'kem': kem,
      'ciphertext': ciphertext,
      'nonce': nonce,
    },
  };

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    emitFlowEvent(
      layer: 'FL',
      event: 'MLKEM_FL_BRIDGE_DECRYPT_RESPONSE',
      details: {'ok': response['ok'] ?? false, 'correlationId': correlationId},
    );

    return response;
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'MLKEM_FL_BRIDGE_DECRYPT_RESPONSE',
      details: {
        'ok': false,
        'errorCode': 'BRIDGE_TIMEOUT',
        'correlationId': correlationId,
      },
    );

    return {
      'ok': false,
      'errorCode': 'BRIDGE_TIMEOUT',
      'errorMessage': 'Bridge call timed out after ${timeout.inSeconds}s',
    };
  }
}

/// Calls the bridge to generate a random 32-byte AES-256 symmetric key.
///
/// Returns the key as a base64-encoded string.
Future<String> callBlobKeygen(
  Bridge bridge, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final request = {'cmd': 'blob:keygen', 'payload': <String, dynamic>{}};

  emitFlowEvent(layer: 'FL', event: 'BLOB_KEYGEN_REQUEST', details: {});

  final responseJson = await bridge.send(jsonEncode(request)).timeout(timeout);
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  if (response['ok'] != true) {
    throw StateError(
      'blob:keygen failed: ${response['errorMessage'] ?? 'unknown'}',
    );
  }

  return response['keyBase64'] as String;
}

/// Calls the bridge to encrypt a file with AES-256-GCM.
///
/// Returns the encrypted file path and the base64 nonce.
Future<({String encryptedPath, String nonce})> callBlobEncrypt(
  Bridge bridge, {
  required String filePath,
  required String keyBase64,
  Duration timeout = const Duration(minutes: 5),
}) async {
  final request = {
    'cmd': 'blob:encrypt',
    'payload': {'filePath': filePath, 'keyBase64': keyBase64},
  };

  emitFlowEvent(
    layer: 'FL',
    event: 'BLOB_ENCRYPT_REQUEST',
    details: {'filePath': filePath},
  );

  final responseJson = await bridge.send(jsonEncode(request)).timeout(timeout);
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  if (response['ok'] != true) {
    throw StateError(
      'blob:encrypt failed: ${response['errorMessage'] ?? 'unknown'}',
    );
  }

  return (
    encryptedPath: response['encryptedPath'] as String,
    nonce: response['nonce'] as String,
  );
}

/// Calls the bridge to decrypt a file with AES-256-GCM.
///
/// Returns the decrypted file path.
Future<String> callBlobDecrypt(
  Bridge bridge, {
  required String filePath,
  required String keyBase64,
  required String nonce,
  Duration timeout = const Duration(minutes: 5),
}) async {
  final request = {
    'cmd': 'blob:decrypt',
    'payload': {'filePath': filePath, 'keyBase64': keyBase64, 'nonce': nonce},
  };

  emitFlowEvent(
    layer: 'FL',
    event: 'BLOB_DECRYPT_REQUEST',
    details: {'filePath': filePath},
  );

  final responseJson = await bridge.send(jsonEncode(request)).timeout(timeout);
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  if (response['ok'] != true) {
    throw StateError(
      'blob:decrypt failed: ${response['errorMessage'] ?? 'unknown'}',
    );
  }

  return response['decryptedPath'] as String;
}

/// Requests an iOS background task. Returns the task ID string on success,
/// or null if the OS refused or the bridge call failed.
Future<String?> callBgBegin(Bridge bridge) async {
  try {
    final response = await bridge.send(jsonEncode({'cmd': 'bg:begin'}));
    if (response.isNotEmpty && !response.startsWith('{')) {
      return response;
    }
  } catch (_) {}
  return null;
}

/// Releases an iOS background task. No-op if taskId is null.
Future<void> callBgEnd(Bridge bridge, String? taskId) async {
  if (taskId == null) return;
  try {
    await bridge.send(
      jsonEncode({
        'cmd': 'bg:end',
        'payload': {'taskId': taskId},
      }),
    );
  } catch (_) {}
}
