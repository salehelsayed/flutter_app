
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
