# M2 Verification Checklist

Use this checklist to verify each task output before moving to dependent tasks.

M2 is complete only when the automated smoke test (`QA_XS_01`) prints **PASS** using the real runtime path (WebView JS bridge + SQLite identity repo).

---

## Phase 0: Baseline Pre-flight (M1 must already be real)

- [ ] **Real WebView bridge exists (not simulated):**
  - [ ] `lib/core/bridge/webview_js_bridge.dart` is present and used by the app.
  - [ ] No "ProductionJsBridge" / "FakeJsBridge" / "Stub" bridge is used for runtime features.

- [ ] **JS bundling produces the real runtime asset:**
  - [ ] `cd core_lib_js && npm install`
  - [ ] `npm run build`
  - [ ] `assets/js/core_lib.js` exists (generated) and is referenced by `assets/js/bridge.html`

- [ ] **Flutter assets configured:**
  - [ ] `assets/js/bridge.html` and `assets/js/core_lib.js` are listed in `pubspec.yaml` assets.

---

## Task Verification

### JS_XS_01 - QRPayloadJson Type Definition

- [ ] File exists: `core_lib_js/src/types/qr_payload.ts`
- [ ] `UnsignedQRPayload` exported with required fields: `pk`, `ns`, `rv`, `ts`
- [ ] `SignedQRPayload` exported and extends `UnsignedQRPayload` with `sig`
- [ ] No runtime code in the file (types only)
- [ ] TypeScript typecheck passes:
  ```bash
  cd core_lib_js
  npm install
  npx tsc -p tsconfig.json --noEmit
  ```

---

### JS_XS_02 - signPayload() Implementation

- [ ] File exists: `core_lib_js/src/signing/sign_payload.ts`
- [ ] Function signature:
  - [ ] `export async function signPayload(dataToSign: string, privateKeyBase64: string): Promise<string>`
- [ ] Uses the **same private key representation as M1 identity** (do not guess; reuse the same parsing/unmarshal utilities already used in M1 core_lib_js)
- [ ] Signs UTF-8 bytes of the input string
- [ ] Returns **base64 signature** (non-empty; no placeholder)
- [ ] Emits flow events (M2):
  - [ ] `QR_JS_SIGN_PAYLOAD_START`
  - [ ] `QR_JS_SIGN_PAYLOAD_SUCCESS` or `QR_JS_SIGN_PAYLOAD_ERROR`
- [ ] TypeScript typecheck passes (see JS_XS_01)

Realness checks (must be true in smoke test):
- [ ] Signing the same message twice returns the same signature (Ed25519 deterministic)
- [ ] Signing two different messages returns different signatures
- [ ] Signature base64 decodes to a plausible byte length (non-trivial; not `"test"`)

---

### JS_XS_03 - Bridge Handler for payload.sign (+ bundle rebuild)

- [ ] `payload.sign` handler registered in `core_lib_js/src/bridge/handlers.ts`
- [ ] Handler expects payload fields:
  - [ ] `dataToSign` (string)
  - [ ] `privateKey` (string, base64)
- [ ] Handler follows the baseline envelope used by M1:
  - [ ] Request includes `requestId`
  - [ ] Response echoes the same `requestId`
- [ ] Success response shape:
  ```json
  { "ok": true, "requestId": "…", "signature": "base64…" }
  ```
- [ ] Error response shape:
  ```json
  { "ok": false, "requestId": "…", "errorCode": "…", "errorMessage": "…" }
  ```
- [ ] Bundle rebuilt and contains the new handler:
  ```bash
  cd core_lib_js
  npm install
  npm run build
  grep -n "payload.sign" -n ../assets/js/core_lib.js
  ```

---

### FL_XS_01 - QRPayloadModel

- [ ] File exists: `lib/features/qr_code/domain/models/qr_payload_model.dart`
- [ ] Immutable model with fields: `pk`, `ns`, `rv`, `ts`, `sig`
- [ ] `fromJson` / `toJson` round-trip works
- [ ] `toJsonString()` produces **canonical JSON**:
  - [ ] keys sorted alphabetically
  - [ ] no whitespace/newlines
- [ ] `buildUnsignedPayload()` produces only keys: `pk`, `ns`, `rv`, `ts`
- [ ] `flutter analyze` passes:
  ```bash
  flutter analyze
  ```

---

### FL_XS_02 - callJsSignPayload()

- [ ] Added to: `lib/core/bridge/js_bridge_client.dart`
- [ ] Follows existing M1 bridge send pattern (requestId correlation handled consistently)
- [ ] Sends command `payload.sign` with payload fields `dataToSign` and `privateKey`
- [ ] Does NOT implement any "fake" signing in Dart
- [ ] Emits flow events:
  - [ ] `QR_FL_BRIDGE_SIGN_REQUEST`
  - [ ] `QR_FL_BRIDGE_SIGN_RESPONSE`

Verified by smoke test (QA_XS_01):
- [ ] Real request/response crosses WebView boundary
- [ ] requestId matches in response

---

### FL_XS_03 - buildQRPayload use case (+ rendezvous constant)

- [ ] Use case exists: `lib/features/qr_code/application/build_qr_payload_use_case.dart`
- [ ] Defines:
  - [ ] `enum BuildQRPayloadResult { success, noIdentity, signingError }`
  - [ ] `Future<(BuildQRPayloadResult, String?)> buildQRPayload(...)`
- [ ] Loads identity from `IdentityRepository` (SQLite-backed)
- [ ] If no identity → returns `(noIdentity, null)`
- [ ] Uses constant `RENDEZVOUS_ADDRESS` from:
  - [ ] `lib/core/constants/network_constants.dart` (create if missing)
- [ ] Produces final QR JSON with all fields: `pk`, `ns`, `rv`, `ts`, `sig`
- [ ] Canonical JSON rules satisfied (see GLOBAL_CONTEXT.md)

Verified by smoke test (QA_XS_01):
- [ ] `pk/ns` match the persisted identity
- [ ] `rv` equals constant
- [ ] `ts` is a recent UTC ISO timestamp
- [ ] signature changes when payload changes

---

### FL_XS_04 - QRDisplayScreen Layout

- [ ] File exists: `lib/features/qr_code/presentation/screens/qr_display_screen.dart`
- [ ] Uses `qr_flutter` (dependency added in `pubspec.yaml`)
- [ ] Stateless / layout-only (no business logic)
- [ ] Renders QR code for provided `qrData` string

---

### FL_XS_05 - Wire QRDisplayScreen

- [ ] File exists: `lib/features/qr_code/presentation/screens/qr_display_wired.dart`
- [ ] Uses the real `buildQRPayload` use case and real dependencies
- [ ] Has loading/success/error states and retry
- [ ] No placeholder QR data in success state

---

## QA_XS_01 - Automated Smoke Test (M2 gate)

Smoke test MUST:
- exercise WebView JS bridge with the real `assets/js/core_lib.js` runtime,
- exercise SQLite persistence via the real IdentityRepository,
- validate realness (no stub markers).

- [ ] File exists: `lib/smoke_test_m2_qr_generation.dart`
- [ ] Running it on a real device/emulator prints `PASS` and does not crash:
  ```bash
  flutter run -t lib/smoke_test_m2_qr_generation.dart -d <device-id>
  ```

Realness checks that must be enforced by the smoke test:
- [ ] Fail if any output contains: `demo|placeholder|fake|stub|TODO|simulate` (case-insensitive)
- [ ] PeerId looks like a real libp2p PeerId (e.g., starts with `12D3KooW`)
- [ ] Base64 fields decode successfully (pk/privateKey/sig)
- [ ] `sig` is non-empty and differs when the unsigned payload differs
- [ ] Identity is saved to SQLite and reloaded (same peerId)

---

## Final Sign-Off

- [ ] All tasks verified individually
- [ ] JS bundle rebuilt after JS_XS_03
- [ ] Smoke test prints PASS using real runtime boundaries

**M2 QR Code Generation: COMPLETE**
