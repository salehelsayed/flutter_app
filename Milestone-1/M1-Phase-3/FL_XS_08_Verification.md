### FL_XS_08 - callJsIdentityGenerate()

- [ ] **Function signature:** `Future<Map<String, dynamic>> callJsIdentityGenerate(JsBridge bridge)`
- [ ] **Sends correct message:** `{ "cmd": "identity.generate", "payload": {} }`
- [ ] **Returns decoded response:** Map with `ok`, `identity` or `errorCode`
- [ ] **Flow events:**
  - [ ] Emits `ID_BRIDGE_IDENTITY_GENERATE_REQUEST`
  - [ ] Emits `ID_BRIDGE_IDENTITY_GENERATE_RESPONSE`
