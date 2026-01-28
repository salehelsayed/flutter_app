# Task Prompt: FL_XS_03 - buildQRPayload Use Case

## Instructions for AI Agent

You are implementing a specific task for a Flutter/JS application. Follow the task specification exactly. Output complete, working code that can be directly used.

---

## Global Context

```
Milestone: M2 – QR Code Generation

Unsigned Payload Keys (before signing):
  {
    "ns": "peerID/namespace - identifies the user on the P2P network",
    "pk": "base64-encoded Ed25519 public key",
    "rv": "rendezvous multiaddress for P2P connection",
    "ts": "ISO 8601 UTC timestamp"
  }
  Keys MUST be sorted alphabetically for canonical JSON.

Signed Payload Keys (after signing):
  {
    "ns": "...",
    "pk": "...",
    "rv": "...",
    "sig": "base64-encoded Ed25519 signature over the unsigned payload",
    "ts": "..."
  }
  The "sig" field is added after signing the canonical JSON of unsigned fields.

Identity Source:
  The identity data comes from IdentityRepository (M1):
  - loadIdentity() returns IdentityModel? (null if no identity exists)
  - IdentityModel contains:
      - peerId: String (becomes "ns" in payload)
      - publicKey: String (becomes "pk" in payload, base64)
      - privateKey: String (used for signing, base64)
      - mnemonic12: String (not used in QR)
      - createdAt: String
      - updatedAt: String

Signing Boundary:
  Signing MUST happen in JavaScript via the bridge.
  Flutter's role: orchestrate the flow, build unsigned payload, call JS to sign
  JavaScript's role: perform actual Ed25519 cryptographic signing
  DO NOT implement signing in Dart - use callJsSignPayload() bridge function.

RENDEZVOUS_ADDRESS Constant:
  This constant defines the P2P rendezvous point for connections.
  Value: '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g'
  Location: lib/core/constants/network_constants.dart
```

---

## Task Definition

```
[TASK FL_XS_03 – buildQRPayloadUseCase()]

Owner: Flutter

Goal:
  Orchestrate building a signed QR payload from identity data.
  This use case combines identity loading, payload construction, and signing.

What to implement:

  FILE 1: lib/core/constants/network_constants.dart
    Create this file with the RENDEZVOUS_ADDRESS constant.

  FILE 2: lib/features/qr_code/application/build_qr_payload_use_case.dart
    Create this file with:
    - BuildQRPayloadResult enum
    - buildQRPayload() function

  Enum definition:
    enum BuildQRPayloadResult {
      success,
      noIdentity,
      signingError,
    }

  Function signature:
    Future<(BuildQRPayloadResult, String?)> buildQRPayload({
      required IdentityRepository repo,
      required Future<Map<String, dynamic>> Function({
        required String dataToSign,
        required String privateKey,
      }) callJsSign,
    })

  Logic (detailed steps):
    1. Emit flow event: QR_FL_BUILD_PAYLOAD_START
    2. Load identity from repository: await repo.loadIdentity()
    3. If identity is null:
       - Emit flow event: QR_FL_BUILD_PAYLOAD_NO_IDENTITY
       - Return (noIdentity, null)
    4. Emit flow event: QR_FL_BUILD_PAYLOAD_IDENTITY_FOUND
    5. Build unsigned payload map (sorted keys for canonical JSON):
       - pk = identity.publicKey
       - ns = identity.peerId
       - rv = RENDEZVOUS_ADDRESS constant
       - ts = DateTime.now().toUtc().toIso8601String()
    6. Serialize unsigned payload to canonical JSON (sorted keys)
    7. Emit flow event: QR_FL_BUILD_PAYLOAD_SIGNING
    8. Call JS bridge to sign: await callJsSign(dataToSign: ..., privateKey: ...)
    9. If signing response['ok'] != true:
       - Emit flow event: QR_FL_BUILD_PAYLOAD_SIGN_ERROR
       - Return (signingError, null)
    10. Add signature to payload (maintaining sorted keys):
        - sig = response['signature']
    11. Serialize final signed payload to canonical JSON
    12. Emit flow event: QR_FL_BUILD_PAYLOAD_SUCCESS
    13. Return (success, finalJsonString)

Inputs:
  - IdentityRepository repo: Repository to load identity from
  - callJsSign: Function to call JS bridge for signing (dependency injection)

Outputs:
  - Tuple of (BuildQRPayloadResult, String?)
  - On success: (success, '{"ns":"...","pk":"...","rv":"...","sig":"...","ts":"..."}')
  - On no identity: (noIdentity, null)
  - On signing error: (signingError, null)

Flow Events:
  - At start:
      layer: "FL", event: "QR_FL_BUILD_PAYLOAD_START", details: {}
  - After loading identity - found:
      layer: "FL", event: "QR_FL_BUILD_PAYLOAD_IDENTITY_FOUND",
      details: { "peerId": first 12 chars of peerId }
  - After loading identity - not found:
      layer: "FL", event: "QR_FL_BUILD_PAYLOAD_NO_IDENTITY", details: {}
  - Before signing:
      layer: "FL", event: "QR_FL_BUILD_PAYLOAD_SIGNING", details: {}
  - After signing - success:
      layer: "FL", event: "QR_FL_BUILD_PAYLOAD_SUCCESS", details: {}
  - After signing - error:
      layer: "FL", event: "QR_FL_BUILD_PAYLOAD_SIGN_ERROR",
      details: { "errorCode": response errorCode }

Constraints:
  - Dependency injection for testability (repo and callJsSign are parameters)
  - Use SplayTreeMap or sorted map for canonical JSON (alphabetically sorted keys)
  - Do not store or persist the QR payload
  - Return the raw JSON string (UI will render QR)
  - Signing MUST happen via JS bridge (not in Dart)

Deliverables:
  - File: lib/core/constants/network_constants.dart
  - File: lib/features/qr_code/application/build_qr_payload_use_case.dart
```

---

## Output Requirements

### File 1: Network Constants

**File:** `lib/core/constants/network_constants.dart`

```dart
/// Network constants for P2P communication
///
/// These constants define the infrastructure endpoints for
/// the decentralized identity system.

/// Rendezvous point multiaddress for P2P connections.
///
/// This address is included in QR payloads so that scanning devices
/// know where to connect to reach this user on the P2P network.
///
/// Format: /dns4/{domain}/tcp/{port}/wss/p2p/{peerId}
const String RENDEZVOUS_ADDRESS =
    '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';
```

---

### File 2: Build QR Payload Use Case

**File:** `lib/features/qr_code/application/build_qr_payload_use_case.dart`

```dart
import 'dart:convert';
import 'dart:collection';

import 'package:your_app/core/constants/network_constants.dart';
import 'package:your_app/core/utils/flow_event_emitter.dart';
import 'package:your_app/features/identity/domain/repositories/identity_repository.dart';

/// Result of building a QR payload
enum BuildQRPayloadResult {
  /// Successfully built and signed the payload
  success,

  /// No identity found in repository
  noIdentity,

  /// Signing operation failed
  signingError,
}

/// Builds a signed QR payload containing the user's identity information.
///
/// The payload includes:
/// - pk: Public key (base64)
/// - ns: Namespace (peerID)
/// - rv: Rendezvous address
/// - ts: Timestamp
/// - sig: Ed25519 signature (added after signing)
///
/// Signing is performed via the JS bridge - NOT in Dart.
///
/// Returns a tuple of (result, jsonString?).
/// On success, jsonString contains the canonical JSON ready for QR encoding.
Future<(BuildQRPayloadResult, String?)> buildQRPayload({
  required IdentityRepository repo,
  required Future<Map<String, dynamic>> Function({
    required String dataToSign,
    required String privateKey,
  }) callJsSign,
}) async {
  // Step 1: Emit start event
  emitFlowEvent(
    layer: 'FL',
    event: 'QR_FL_BUILD_PAYLOAD_START',
    details: {},
  );

  // Step 2: Load identity from repository
  final identity = await repo.loadIdentity();

  // Step 3: Check if identity exists
  if (identity == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'QR_FL_BUILD_PAYLOAD_NO_IDENTITY',
      details: {},
    );
    return (BuildQRPayloadResult.noIdentity, null);
  }

  // Step 4: Emit identity found event
  emitFlowEvent(
    layer: 'FL',
    event: 'QR_FL_BUILD_PAYLOAD_IDENTITY_FOUND',
    details: {'peerId': identity.peerId.substring(0, 12)},
  );

  // Step 5: Build unsigned payload with sorted keys
  final timestamp = DateTime.now().toUtc().toIso8601String();
  final unsignedPayload = SplayTreeMap<String, dynamic>.from({
    'ns': identity.peerId,
    'pk': identity.publicKey,
    'rv': RENDEZVOUS_ADDRESS,
    'ts': timestamp,
  });

  // Step 6: Serialize to canonical JSON (sorted keys, no extra whitespace)
  final dataToSign = jsonEncode(unsignedPayload);

  // Step 7: Emit signing event
  emitFlowEvent(
    layer: 'FL',
    event: 'QR_FL_BUILD_PAYLOAD_SIGNING',
    details: {},
  );

  // Step 8: Call JS bridge to sign
  final signResponse = await callJsSign(
    dataToSign: dataToSign,
    privateKey: identity.privateKey,
  );

  // Step 9: Check signing result
  if (signResponse['ok'] != true) {
    final errorCode = signResponse['errorCode'] ?? 'UNKNOWN';
    emitFlowEvent(
      layer: 'FL',
      event: 'QR_FL_BUILD_PAYLOAD_SIGN_ERROR',
      details: {'errorCode': errorCode},
    );
    return (BuildQRPayloadResult.signingError, null);
  }

  // Step 10: Add signature to payload (maintaining sorted keys)
  final signature = signResponse['signature'] as String;
  final signedPayload = SplayTreeMap<String, dynamic>.from({
    ...unsignedPayload,
    'sig': signature,
  });

  // Step 11: Serialize final signed payload
  final finalJson = jsonEncode(signedPayload);

  // Step 12: Emit success event
  emitFlowEvent(
    layer: 'FL',
    event: 'QR_FL_BUILD_PAYLOAD_SUCCESS',
    details: {},
  );

  // Step 13: Return success with JSON string
  return (BuildQRPayloadResult.success, finalJson);
}
```

---

## Usage Example

```dart
// In a widget or controller
final (result, qrString) = await buildQRPayload(
  repo: identityRepository,
  callJsSign: ({required dataToSign, required privateKey}) =>
      bridgeClient.callJsSignPayload(
        dataToSign: dataToSign,
        privateKey: privateKey,
      ),
);

switch (result) {
  case BuildQRPayloadResult.success:
    // qrString contains the JSON to encode in QR
    // Example: {"ns":"12D3KooW...","pk":"SGVs...","rv":"/dns4/...","sig":"YWJj...","ts":"2025-01-22T..."}
    showQRCode(qrString!);
    break;
  case BuildQRPayloadResult.noIdentity:
    showError('No identity found. Please create one first.');
    break;
  case BuildQRPayloadResult.signingError:
    showError('Failed to sign QR payload. Please try again.');
    break;
}
```

---

## Test Cases

```dart
// Test with mock
void testBuildQRPayload() async {
  // Mock repository
  final mockRepo = MockIdentityRepository();
  when(mockRepo.loadIdentity()).thenAnswer((_) async => IdentityModel(
    peerId: '12D3KooWTest1234567890',
    publicKey: 'dGVzdC1wdWJsaWMta2V5',
    privateKey: 'dGVzdC1wcml2YXRlLWtleQ==',
    mnemonic12: 'word1 word2 ...',
    createdAt: '2025-01-01T00:00:00Z',
    updatedAt: '2025-01-01T00:00:00Z',
  ));

  // Mock signing function (for testing only - real code uses JS bridge)
  Future<Map<String, dynamic>> mockSign({
    required String dataToSign,
    required String privateKey,
  }) async {
    return {'ok': true, 'signature': 'bW9jay1zaWduYXR1cmU='};
  }

  final (result, qrString) = await buildQRPayload(
    repo: mockRepo,
    callJsSign: mockSign,
  );

  expect(result, BuildQRPayloadResult.success);
  expect(qrString, isNotNull);

  final parsed = jsonDecode(qrString!);
  expect(parsed['pk'], 'dGVzdC1wdWJsaWMta2V5');
  expect(parsed['ns'], '12D3KooWTest1234567890');
  expect(parsed['rv'], contains('mknoun.xyz'));
  expect(parsed['sig'], 'bW9jay1zaWduYXR1cmU=');
  expect(parsed['ts'], isNotNull);

  // Verify keys are sorted alphabetically
  final keys = (parsed as Map<String, dynamic>).keys.toList();
  expect(keys, ['ns', 'pk', 'rv', 'sig', 'ts']);
}

void testBuildQRPayloadNoIdentity() async {
  final mockRepo = MockIdentityRepository();
  when(mockRepo.loadIdentity()).thenAnswer((_) async => null);

  final (result, qrString) = await buildQRPayload(
    repo: mockRepo,
    callJsSign: ({required dataToSign, required privateKey}) async => {},
  );

  expect(result, BuildQRPayloadResult.noIdentity);
  expect(qrString, isNull);
}

void testBuildQRPayloadSigningError() async {
  final mockRepo = MockIdentityRepository();
  when(mockRepo.loadIdentity()).thenAnswer((_) async => IdentityModel(...));

  Future<Map<String, dynamic>> failingSign({
    required String dataToSign,
    required String privateKey,
  }) async {
    return {
      'ok': false,
      'errorCode': 'SIGNING_ERROR',
      'errorMessage': 'Failed to sign',
    };
  }

  final (result, qrString) = await buildQRPayload(
    repo: mockRepo,
    callJsSign: failingSign,
  );

  expect(result, BuildQRPayloadResult.signingError);
  expect(qrString, isNull);
}
```

---

## Begin Implementation

Output both complete Dart files:
1. `lib/core/constants/network_constants.dart` - with RENDEZVOUS_ADDRESS constant
2. `lib/features/qr_code/application/build_qr_payload_use_case.dart` - with enum and function
