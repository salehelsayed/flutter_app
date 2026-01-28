
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