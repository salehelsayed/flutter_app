# Task Prompt: FL_XS_02 - callJsSignPayload() Bridge Function

## Instructions for AI Agent

You are implementing a specific task for a Flutter/JS application. Follow the task specification exactly. Output complete, working code that can be directly used.

---

## Global Context

```
Milestone: M2 – QR Code Generation

Baseline M1 Bridge Code:
  The existing js_bridge_client.dart from Milestone 1 provides:
  - An abstract JsBridge interface with send(String message) method
  - Top-level functions: callJsIdentityGenerate() and callJsIdentityRestore()
  - Flow event emission pattern (emitFlowEvent helper)
  - Communication via bridge.send(jsonEncode(request)) returning raw JSON strings

  Location: lib/core/bridge/js_bridge_client.dart

Envelope with requestId:
  Each bridge message is wrapped in an envelope with a unique requestId
  for correlating async responses. The bridge infrastructure handles this
  automatically - callers just build the command payload.

M2 Command "payload.sign":
  Request Envelope:
    {
      "cmd": "payload.sign",
      "payload": {
        "dataToSign": "canonical-json-string",
        "privateKey": "base64-encoded-private-key"
      }
    }

  Success Response:
    {
      "ok": true,
      "signature": "base64-encoded-signature"
    }

  Error Response:
    {
      "ok": false,
      "errorCode": "SIGNING_ERROR" | "INVALID_PRIVATE_KEY" | "INTERNAL_ERROR",
      "errorMessage": "Description of what went wrong"
    }

Critical Constraint:
  Flutter MUST use the real JS bridge for signing. Ed25519 signing is
  implemented in JavaScript (using noble-ed25519). DO NOT implement
  fake signing or placeholder signing in Dart - the actual cryptographic
  operation must happen in JavaScript via the bridge.
```

---

## Task Definition

```
[TASK FL_XS_02 – callJsSignPayload() bridge client function]

Owner: Flutter

Goal:
  Provide a Flutter function to call the JS payload.sign command via bridge.
  This function serves as the Dart-side interface to JavaScript's Ed25519 signing.

What to implement:
  MODIFY: lib/core/bridge/js_bridge_client.dart
  ADD: callJsSignPayload as a top-level function (matching M1 pattern)

  Function signature:
    Future<Map<String, dynamic>> callJsSignPayload({
      required JsBridge bridge,
      required String dataToSign,
      required String privateKey,
      Duration timeout = const Duration(seconds: 10),
    })

  Behavior:
    1. Generate correlationId for tracing
    2. Emit flow event: QR_FL_BRIDGE_SIGN_REQUEST (with dataLength and correlationId)
    3. Build message envelope: { "cmd": "payload.sign", "payload": {...} }
    4. Send via bridge.send(jsonEncode(request)) with timeout
    5. Decode JSON response
    6. Emit flow event: QR_FL_BRIDGE_SIGN_RESPONSE (with ok and correlationId)
    7. Return decoded response map (do not interpret success/error)
    8. On timeout: return { "ok": false, "errorCode": "BRIDGE_TIMEOUT", ... }

Inputs:
  - dataToSign: String - The canonical JSON string to sign
  - privateKey: String - Base64-encoded Ed25519 private key from identity

Outputs:
  - Map<String, dynamic> with response:
      - On success: { "ok": true, "signature": "base64..." }
      - On error: { "ok": false, "errorCode": "...", "errorMessage": "..." }

Flow Events:
  - Before sending:
      - layer: "FL"
      - event: "QR_FL_BRIDGE_SIGN_REQUEST"
      - details: { "dataLength": dataToSign.length, "correlationId": correlationId }
  - After receiving:
      - layer: "FL"
      - event: "QR_FL_BRIDGE_SIGN_RESPONSE"
      - details: { "ok": response['ok'] ?? false, "correlationId": correlationId }

Constraints:
  - MUST use real bridge - no fake signing in Dart
  - Does not interpret success/error, just returns response map
  - Follows existing M1 bridge client patterns
  - This is an ADDITION to js_bridge_client.dart (do not remove M1 methods)

Deliverable:
  - Addition to: lib/core/bridge/js_bridge_client.dart
```

---

## Output Requirements

1. **File:** `lib/core/bridge/js_bridge_client.dart` (addition to existing file)

2. **Must include:**
   - The `callJsSignPayload` method
   - Flow event emissions (QR_FL_BRIDGE_SIGN_REQUEST, QR_FL_BRIDGE_SIGN_RESPONSE)
   - Proper message format with cmd: "payload.sign"
   - Response handling that preserves the full response map

3. **Implementation (top-level function, matching M1 pattern):**

```dart
/// Calls the JS bridge to sign payload data with Ed25519.
///
/// This function MUST use the real JS bridge for cryptographic signing.
/// Ed25519 signing is implemented in JavaScript - DO NOT fake this in Dart.
///
/// Parameters:
///   - [bridge]: The JsBridge instance to use for communication
///   - [dataToSign]: The canonical JSON string to sign
///   - [privateKey]: Base64-encoded Ed25519 private key
///
/// Returns a map with:
/// - On success: { "ok": true, "signature": "base64..." }
/// - On error: { "ok": false, "errorCode": "...", "errorMessage": "..." }
Future<Map<String, dynamic>> callJsSignPayload({
  required JsBridge bridge,
  required String dataToSign,
  required String privateKey,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final correlationId = DateTime.now().microsecondsSinceEpoch.toString();

  emitFlowEvent(
    layer: 'FL',
    event: 'QR_FL_BRIDGE_SIGN_REQUEST',
    details: {
      'dataLength': dataToSign.length,
      'correlationId': correlationId,
    },
  );

  final request = {
    'cmd': 'payload.sign',
    'payload': {
      'dataToSign': dataToSign,
      'privateKey': privateKey,
    },
  };

  try {
    final responseJson = await bridge
        .send(jsonEncode(request))
        .timeout(timeout);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    emitFlowEvent(
      layer: 'FL',
      event: 'QR_FL_BRIDGE_SIGN_RESPONSE',
      details: {
        'ok': response['ok'] ?? false,
        'correlationId': correlationId,
      },
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
```

---

## Integration with Existing M1 Bridge Client

The file uses top-level functions (not a class). After this task it should contain:

```dart
// lib/core/bridge/js_bridge_client.dart

import 'dart:async';
import 'dart:convert';
import '../utils/flow_event_emitter.dart';

/// Abstract interface for JS bridge communication.
abstract class JsBridge {
  Future<String> send(String message);
}

// ============================================
// M1 FUNCTIONS (existing)
// ============================================

Future<Map<String, dynamic>> callJsIdentityGenerate(JsBridge bridge) async { ... }
Future<Map<String, dynamic>> callJsIdentityRestore(JsBridge bridge, String mnemonic12) async { ... }

// ============================================
// M2 FUNCTIONS (new)
// ============================================

Future<Map<String, dynamic>> callJsSignPayload({
  required JsBridge bridge,
  required String dataToSign,
  required String privateKey,
  Duration timeout = const Duration(seconds: 10),
}) async { ... }
```

---

## Flow Event Helper

Assume this exists (from M1):

```dart
void emitFlowEvent({
  required String layer,
  required String event,
  required Map<String, dynamic> details,
}) {
  final payload = {
    'ts': DateTime.now().toUtc().toIso8601String(),
    'milestone': 'M1_IDENTITY_INIT',
    'layer': layer,
    'event': event,
    'details': details,
  };
  print('[FLOW] ${jsonEncode(payload)}');
}
```

---

## Usage Example

```dart
// In use case or other calling code
final response = await callJsSignPayload(
  bridge: myBridgeInstance,
  dataToSign: '{"ns":"12D3KooW...","pk":"SGVsbG8=","rv":"/dns4/...","ts":"2025-01-22T00:00:00Z"}',
  privateKey: 'BASE64_PRIVATE_KEY_FROM_IDENTITY',
);

if (response['ok'] == true) {
  final signature = response['signature'] as String;
  print('Got signature: $signature');
} else {
  final errorCode = response['errorCode'] as String;
  final errorMessage = response['errorMessage'] as String;
  print('Signing failed: $errorCode - $errorMessage');
}
```

---

## Begin Implementation

Output the code that should be ADDED to the existing js_bridge_client.dart file. Show the complete method implementation.
