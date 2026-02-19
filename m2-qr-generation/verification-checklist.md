# M2 Verification Checklist

Use this checklist to verify each task output before moving to dependent tasks.

---

## How to Use

1. After running a task, check all items in that task's section
2. If any check fails, fix before proceeding
3. Mark the task complete only when ALL checks pass
4. Integration checks should be done after each phase

---

## Phase 0: Baseline Pre-flight (M1 must already be real)

Before starting M2 tasks, verify M1 is fully operational:

- [ ] **Real WebView bridge:** Flutter can send messages to JS and receive responses
  - [ ] Test: `callJsAction('ping', {})` returns valid response
  - [ ] WebView loads without errors
  - [ ] Bridge communication is bidirectional
- [ ] **JS bundling:** Bundle builds successfully and is included in Flutter assets
  - [ ] `core_lib_js/dist/bundle.js` exists
  - [ ] Bundle is copied to `flutter_app/assets/js/bundle.js`
  - [ ] No build errors in `npm run build`
- [ ] **Flutter assets:** JS bundle loads correctly at runtime
  - [ ] Asset declared in `pubspec.yaml`
  - [ ] WebView can execute bundle code
  - [ ] Identity operations from M1 work end-to-end

---

## Task Verification

### JS_XS_01 - QRPayloadJson Type Definition

- [ ] **File exists:** `core_lib_js/src/types/qr_payload.ts`
- [ ] **TypeScript typecheck command passes:**
  ```bash
  cd core_lib_js && npx tsc --noEmit
  ```
- [ ] **UnsignedQRPayload interface defined:**
  - [ ] `pk: string` (public key)
  - [ ] `ns: string` (namespace/peerId)
  - [ ] `rv: string` (rendezvous)
  - [ ] `ts: string` (timestamp)
- [ ] **SignedQRPayload interface defined:**
  - [ ] Extends UnsignedQRPayload
  - [ ] `sig: string` (signature)
- [ ] **Exported:** Both interfaces are exported
- [ ] **TypeScript compiles:** No type errors

```typescript
// Quick test
import { UnsignedQRPayload, SignedQRPayload } from './qr_payload';

const unsigned: UnsignedQRPayload = {
  pk: 'test',
  ns: 'test',
  rv: 'test',
  ts: new Date().toISOString(),
};

const signed: SignedQRPayload = {
  ...unsigned,
  sig: 'test-signature',
};
```

---

### JS_XS_02 - signPayload() Implementation

- [ ] **File exists:** `core_lib_js/src/signing/sign_payload.ts`
- [ ] **Function signature:**
  ```typescript
  async function signPayload(dataToSign: string, privateKeyBase64: string): Promise<string>
  ```
- [ ] **Realness checks:**
  - [ ] Uses real Ed25519 signing (not mock/stub)
  - [ ] Actually decodes base64 private key
  - [ ] Actually signs UTF-8 bytes of dataToSign
  - [ ] Returns real base64-encoded signature
- [ ] **Uses Ed25519:** Proper crypto library imported (@noble/ed25519 or similar)
- [ ] **Decodes private key:** From base64 correctly
- [ ] **Signs UTF-8 bytes:** Of the dataToSign string
- [ ] **Returns base64 signature:** Properly encoded
- [ ] **Flow events:**
  - [ ] Emits `QR_JS_SIGN_PAYLOAD_START`
  - [ ] Emits `QR_JS_SIGN_PAYLOAD_SUCCESS` or `QR_JS_SIGN_PAYLOAD_ERROR`
- [ ] **Error handling:** Catches and rethrows with context

```typescript
// Quick test
const testPrivateKey = 'base64-encoded-ed25519-private-key';
const testData = '{"pk":"test","ns":"test","rv":"test","ts":"2025-01-01T00:00:00Z"}';

const sig = await signPayload(testData, testPrivateKey);
console.log(sig); // Should be base64 string
```

---

### JS_XS_03 - Bridge Handler for payload.sign

- [ ] **Handler registered:** `payload.sign` in handlers map
- [ ] **Extracts parameters:**
  - [ ] `dataToSign` from payload
  - [ ] `privateKey` from payload
- [ ] **Calls signPayload:** With extracted parameters
- [ ] **Realness checks:**
  - [ ] Handler actually invokes real signPayload function
  - [ ] Not a mock or placeholder response
- [ ] **Bundle rebuild verification:**
  ```bash
  cd core_lib_js && npm run build
  # Verify bundle.js contains payload.sign handler
  grep -l "payload.sign" dist/bundle.js
  ```
- [ ] **Success response:**
  ```json
  { "ok": true, "signature": "base64..." }
  ```
- [ ] **Error response:**
  ```json
  { "ok": false, "errorCode": "SIGNING_ERROR", "errorMessage": "..." }
  ```
- [ ] **Flow events:**
  - [ ] Emits `QR_JS_BRIDGE_SIGN_RECEIVED`
  - [ ] Emits `QR_JS_BRIDGE_SIGN_SUCCESS` or `QR_JS_BRIDGE_SIGN_ERROR`

```typescript
// Quick test
const request = {
  cmd: 'payload.sign',
  payload: {
    dataToSign: '{"pk":"test"}',
    privateKey: 'base64-private-key',
  },
};
const response = await handleBridgeMessage(request);
console.log(response.ok); // true or false
```

---

### FL_XS_01 - QRPayloadModel

- [ ] **Class exists:** `QRPayloadModel`
- [ ] **All fields present:**
  - [ ] `String pk`
  - [ ] `String ns`
  - [ ] `String rv`
  - [ ] `String ts`
  - [ ] `String sig`
- [ ] **Immutable:** All fields are `final`
- [ ] **fromJson works:** Factory constructor accepts `Map<String, dynamic>`
- [ ] **toJson works:** Returns `Map<String, dynamic>` with correct keys
- [ ] **toJsonString works:** Returns canonical JSON string (sorted keys: ns, pk, rv, ts)
- [ ] **Canonical JSON verification:**
  - [ ] Keys are sorted alphabetically
  - [ ] No extra whitespace
  - [ ] Consistent ordering for signature verification
- [ ] **Round-trip test passes:**

```dart
final json = {
  'pk': 'public-key-base64',
  'ns': '12D3KooW...',
  'rv': '/dns4/mknoun.xyz/...',
  'ts': '2025-01-22T12:00:00.000Z',
  'sig': 'signature-base64',
};
final model = QRPayloadModel.fromJson(json);
final back = model.toJson();
assert(back['pk'] == json['pk']);
// ... all fields match
```

---

### FL_XS_02 - callJsSignPayload()

- [ ] **Function exists:** In `JsBridgeClient` or standalone
- [ ] **Function signature:**
  ```dart
  Future<Map<String, dynamic>> callJsSignPayload({
    required String dataToSign,
    required String privateKey,
  })
  ```
- [ ] **Sends correct message:**
  ```json
  { "cmd": "payload.sign", "payload": { "dataToSign": "...", "privateKey": "..." } }
  ```
- [ ] **Returns decoded response:** Map with `ok`, `signature` or `errorCode`
- [ ] **Flow events:**
  - [ ] Emits `QR_FL_BRIDGE_SIGN_REQUEST` with dataToSign length
  - [ ] Emits `QR_FL_BRIDGE_SIGN_RESPONSE` with success/failure status
  - [ ] Events include correlation ID for tracing
- [ ] **Error handling:**
  - [ ] Timeout handling for bridge calls
  - [ ] Proper error propagation

---

### FL_XS_03 - buildQRPayloadUseCase()

- [ ] **Enum exists:**
  ```dart
  enum BuildQRPayloadResult { success, noIdentity, signingError }
  ```
- [ ] **Function signature:**
  ```dart
  Future<(BuildQRPayloadResult, String?)> buildQRPayload({
    required IdentityRepository repo,
    required Future<Map<String, dynamic>> Function(String, String) callJsSign,
  })
  ```
- [ ] **Uses RENDEZVOUS_ADDRESS constant:**
  - [ ] Constant defined: `/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`
  - [ ] Used in payload `rv` field
- [ ] **Logic flow:**
  - [ ] Loads identity from repo
  - [ ] Returns `noIdentity` if null
  - [ ] Builds unsigned payload with pk, ns, rv, ts
  - [ ] Serializes to canonical JSON (sorted keys)
  - [ ] Calls JS sign with data and privateKey
  - [ ] Returns `signingError` if signing fails
  - [ ] Adds signature to payload
  - [ ] Returns `success` with final JSON string
- [ ] **Flow events:**
  - [ ] Emits `QR_FL_BUILD_PAYLOAD_START`
  - [ ] Emits `QR_FL_BUILD_PAYLOAD_IDENTITY_LOADED` or `QR_FL_BUILD_PAYLOAD_NO_IDENTITY`
  - [ ] Emits `QR_FL_BUILD_PAYLOAD_SIGNING`
  - [ ] Emits `QR_FL_BUILD_PAYLOAD_SUCCESS` or `QR_FL_BUILD_PAYLOAD_ERROR`

```dart
// Quick test with mock
final result = await buildQRPayload(
  repo: mockRepo,
  callJsSign: (data, key) async => {'ok': true, 'signature': 'test-sig'},
);
assert(result.$1 == BuildQRPayloadResult.success);
assert(result.$2 != null);
final parsed = jsonDecode(result.$2!);
assert(parsed['sig'] == 'test-sig');
```

---

### FL_XS_04 - QRDisplayScreen Layout

- [ ] **Widget exists:** `QRDisplayScreen`
- [ ] **Constructor parameters:**
  - [ ] `String qrData` (the JSON string)
  - [ ] `String peerId` (for display)
  - [ ] `VoidCallback onClose`
  - [ ] `VoidCallback? onShare` (optional)
- [ ] **UI elements:**
  - [ ] AppBar with back/close button
  - [ ] Title "My QR Code"
  - [ ] QR code widget (256x256 minimum)
  - [ ] Instruction text "Scan to connect with me"
  - [ ] Truncated peerId display (first 8 + last 4 chars)
  - [ ] Share button (if onShare provided)
- [ ] **No business logic:** Pure layout/presentation
- [ ] **Uses qr_flutter package:** `QrImageView` widget
- [ ] **Accessibility:** Semantic labels for QR code

```dart
// Quick test
QRDisplayScreen(
  qrData: '{"pk":"test"}',
  peerId: '12D3KooWAbcdef...',
  onClose: () {},
);
// Should render without errors
```

---

### FL_XS_05 - Wire QRDisplayScreen

- [ ] **Widget exists:** `QRDisplayWired` or integrated into navigation
- [ ] **Calls buildQRPayload:** On initialization
- [ ] **Handles all states:**
  - [ ] Loading: Shows CircularProgressIndicator
  - [ ] Success: Shows QRDisplayScreen with data
  - [ ] noIdentity: Shows error message "No identity found"
  - [ ] signingError: Shows error message with retry button
- [ ] **Dependencies injected:** Repository and bridge function
- [ ] **Navigation integrated:**
  - [ ] Can navigate to QR screen from appropriate entry point
  - [ ] Back button returns to previous screen
- [ ] **Flow events:**
  - [ ] Emits `QR_FL_SCREEN_INIT`
  - [ ] Emits `QR_FL_SCREEN_LOADING`
  - [ ] Emits `QR_FL_SCREEN_DISPLAY` on success
  - [ ] Emits `QR_FL_SCREEN_ERROR` on error

---

## QA_XS_01 - Automated Smoke Test (M2 gate)

This is the final verification gate for M2. All items must pass.

### Realness Checks

- [ ] **No mocks in production path:**
  - [ ] signPayload uses real Ed25519 signing
  - [ ] Bridge handler calls real signPayload
  - [ ] Flutter calls real bridge (not mock)
  - [ ] Repository loads real identity
- [ ] **Real data flows through entire stack:**
  - [ ] Identity loaded from secure storage
  - [ ] Private key sent to JS for signing
  - [ ] Signature computed using Ed25519
  - [ ] Signed payload displayed in QR

### End-to-End Verification

- [ ] **Prerequisites verified:**
  - [ ] M1 complete (identity exists)
  - [ ] App builds without errors
  - [ ] WebView bridge operational
- [ ] **QR generation flow:**
  - [ ] Navigate to QR screen
  - [ ] Loading state appears briefly
  - [ ] QR code renders successfully
  - [ ] PeerId displayed correctly
- [ ] **Payload validation:**
  - [ ] Scan QR with external scanner
  - [ ] Payload is valid JSON
  - [ ] All fields present: pk, ns, rv, ts, sig
  - [ ] pk matches identity.publicKey
  - [ ] ns matches identity.peerId
  - [ ] rv equals RENDEZVOUS_ADDRESS constant
  - [ ] ts is valid ISO-8601 timestamp
  - [ ] sig is non-empty base64 string

### Flow Events Trace

Verify complete flow event sequence:

```
QR_FL_SCREEN_INIT
QR_FL_BUILD_PAYLOAD_START
QR_FL_BUILD_PAYLOAD_IDENTITY_LOADED
QR_FL_BRIDGE_SIGN_REQUEST
QR_JS_BRIDGE_SIGN_RECEIVED
QR_JS_SIGN_PAYLOAD_START
QR_JS_SIGN_PAYLOAD_SUCCESS
QR_JS_BRIDGE_SIGN_SUCCESS
QR_FL_BRIDGE_SIGN_RESPONSE
QR_FL_BUILD_PAYLOAD_SUCCESS
QR_FL_SCREEN_DISPLAY
```

### Test Commands

```bash
# Build and run
cd flutter_app && flutter run

# Verify JS bundle
cd core_lib_js && npm run build && npm run test

# Check TypeScript
cd core_lib_js && npx tsc --noEmit

# Run Flutter tests
cd flutter_app && flutter test
```

---

## Integration Verification

### After Phase 1

```typescript
// Test: JS types + signing
import { UnsignedQRPayload } from './types/qr_payload';
import { signPayload } from './signing/sign_payload';

const payload: UnsignedQRPayload = {
  pk: 'test-pk',
  ns: 'test-ns',
  rv: '/dns4/test',
  ts: new Date().toISOString(),
};

const data = JSON.stringify(payload);
const sig = await signPayload(data, testPrivateKey);
console.log('Signature:', sig);
```

### After Phase 2

```dart
// Test: Bridge round-trip
final response = await callJsSignPayload(
  dataToSign: '{"test":"data"}',
  privateKey: 'test-private-key-base64',
);
print(response); // {ok: true/false, ...}
```

### After Phase 3

```dart
// Test: Use case end-to-end
final (result, qrString) = await buildQRPayload(
  repo: realRepo,
  callJsSign: realBridgeFunction,
);
if (result == BuildQRPayloadResult.success) {
  final payload = jsonDecode(qrString!);
  print('PK: ${payload['pk']}');
  print('NS: ${payload['ns']}');
  print('RV: ${payload['rv']}');
  print('TS: ${payload['ts']}');
  print('SIG: ${payload['sig']}');
}
```

### After Phase 4

```
// Test: Full UI flow
1. Ensure identity exists (M1 complete)
2. Navigate to QR display screen
3. Verify loading spinner appears briefly
4. Verify QR code renders
5. Verify peerId shown below QR
6. Use another device/app to scan QR
7. Verify scanned payload is valid JSON
8. Verify all fields present: pk, ns, rv, ts, sig
```

---

## QR Payload Validation

After generating a QR, scan it and verify:

- [ ] **Valid JSON:** Parses without error
- [ ] **pk field:** Base64 string, matches identity.publicKey
- [ ] **ns field:** String, matches identity.peerId
- [ ] **rv field:** Equals `/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`
- [ ] **ts field:** Valid ISO-8601 timestamp
- [ ] **sig field:** Base64 string, non-empty

```json
// Example valid payload
{
  "pk": "SGVsbG8gV29ybGQhIFRoaXMgaXMgYSB0ZXN0Lg==",
  "ns": "12D3KooWA1b2C3d4E5f6G7h8I9j0K1L2M3N4O5P6",
  "rv": "/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g",
  "ts": "2025-01-22T15:30:00.000Z",
  "sig": "U2lnbmF0dXJlQmFzZTY0RW5jb2RlZFN0cmluZw=="
}
```

---

## Final Sign-Off

- [ ] All 9 tasks verified individually
- [ ] Phase 0 pre-flight checks pass (M1 is real)
- [ ] All integration checks pass
- [ ] QA_XS_01 automated smoke test passes
- [ ] All realness checks verified (no mocks in production)
- [ ] QR code is scannable
- [ ] Scanned payload contains all required fields
- [ ] Flow events trace complete path
- [ ] No console errors or warnings
- [ ] UI matches design guidelines (centered QR, chat-app style)

**M2 QR Code Generation: COMPLETE**

Signed: _______________ Date: _______________
