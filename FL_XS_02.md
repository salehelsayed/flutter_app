# Task Prompt: FL_XS_02 - callJsSignPayload() Bridge Function

## Instructions for AI Agent

You are implementing a specific task for a Flutter/JS application. Follow the task specification exactly. Output complete, working code that can be directly used.

---

## Global Context

```
Milestone: M2 – QR Code Generation

Baseline M1 Bridge Code:
  The existing JsBridgeClient class from Milestone 1 provides:
  - A configured JsBridge instance for Flutter-JS communication
  - Methods like callJsIdentityGenerate() and callJsIdentityRestore()
  - Flow event emission pattern (emitFlowEvent helper)
  - Message sending via _sendMessage() or bridge.sendMessage()

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
  ADD: callJsSignPayload method to the existing JsBridgeClient class

  Method signature:
    Future<Map<String, dynamic>> callJsSignPayload({
      required String dataToSign,
      required String privateKey,
    })

  Behavior:
    1. Emit flow event: QR_FL_BRIDGE_SIGN_REQUEST
    2. Build message envelope: { "cmd": "payload.sign", "payload": {...} }
    3. Send via bridge (uses existing _sendMessage or bridge.sendMessage)
    4. Await response
    5. Emit flow event: QR_FL_BRIDGE_SIGN_RESPONSE
    6. Return decoded response map (do not interpret success/error)

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
      - details: { "dataLength": dataToSign.length }
  - After receiving:
      - layer: "FL"
      - event: "QR_FL_BRIDGE_SIGN_RESPONSE"
      - details: { "ok": response['ok'] ?? false }

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

3. **Implementation (as class method):**

```dart
// Add this method to existing JsBridgeClient class

/// Calls the JS bridge to sign payload data with Ed25519.
///
/// This method MUST use the real JS bridge for cryptographic signing.
/// Ed25519 signing is implemented in JavaScript - DO NOT fake this in Dart.
///
/// [dataToSign] - The canonical JSON string to sign
/// [privateKey] - Base64-encoded Ed25519 private key
///
/// Returns a map with:
/// - On success: { "ok": true, "signature": "base64..." }
/// - On error: { "ok": false, "errorCode": "...", "errorMessage": "..." }
Future<Map<String, dynamic>> callJsSignPayload({
  required String dataToSign,
  required String privateKey,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'QR_FL_BRIDGE_SIGN_REQUEST',
    details: {'dataLength': dataToSign.length},
  );

  final message = {
    'cmd': 'payload.sign',
    'payload': {
      'dataToSign': dataToSign,
      'privateKey': privateKey,
    },
  };

  final response = await _sendMessage(message);

  emitFlowEvent(
    layer: 'FL',
    event: 'QR_FL_BRIDGE_SIGN_RESPONSE',
    details: {'ok': response['ok'] ?? false},
  );

  return response;
}
```

4. **Alternative (as standalone function):**

```dart
/// Calls the JS bridge to sign payload data with Ed25519.
///
/// This function MUST use the real JS bridge for cryptographic signing.
/// Ed25519 signing is implemented in JavaScript - DO NOT fake this in Dart.
Future<Map<String, dynamic>> callJsSignPayload({
  required JsBridge bridge,
  required String dataToSign,
  required String privateKey,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'QR_FL_BRIDGE_SIGN_REQUEST',
    details: {'dataLength': dataToSign.length},
  );

  final message = {
    'cmd': 'payload.sign',
    'payload': {
      'dataToSign': dataToSign,
      'privateKey': privateKey,
    },
  };

  final response = await bridge.sendMessage(message);

  emitFlowEvent(
    layer: 'FL',
    event: 'QR_FL_BRIDGE_SIGN_RESPONSE',
    details: {'ok': response['ok'] ?? false},
  );

  return response;
}
```

---

## Integration with Existing M1 Bridge Client

The JsBridgeClient class should now have:

```dart
// lib/core/bridge/js_bridge_client.dart

import 'dart:convert';
import 'package:your_app/core/utils/flow_event_emitter.dart';

class JsBridgeClient {
  // ... existing bridge setup code ...

  // ============================================
  // M1 METHODS (existing)
  // ============================================

  /// Calls JS to generate a new identity
  Future<Map<String, dynamic>> callJsIdentityGenerate() async {
    // ... existing M1 implementation
  }

  /// Calls JS to restore identity from mnemonic
  Future<Map<String, dynamic>> callJsIdentityRestore(String mnemonic12) async {
    // ... existing M1 implementation
  }

  // ============================================
  // M2 METHODS (new)
  // ============================================

  /// Calls JS to sign payload data with Ed25519
  /// MUST use real bridge - no fake signing in Dart
  Future<Map<String, dynamic>> callJsSignPayload({
    required String dataToSign,
    required String privateKey,
  }) async {
    // ... new implementation from this task
  }
}
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
    'milestone': 'M2_QR_GENERATION',
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
final bridgeClient = JsBridgeClient();

final response = await bridgeClient.callJsSignPayload(
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
