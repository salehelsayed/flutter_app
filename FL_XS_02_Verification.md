
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
