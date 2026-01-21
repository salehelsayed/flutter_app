
### FL_XS_09 - callJsIdentityRestore()

- [ ] **Function signature:** `Future<Map<String, dynamic>> callJsIdentityRestore(JsBridge bridge, String mnemonic12)`
- [ ] **Sends correct message:** `{ "cmd": "identity.restore", "payload": { "mnemonic12": ... } }`
- [ ] **Returns decoded response:** Map with `ok`, `identity` or `errorCode`
- [ ] **Flow events:**
  - [ ] Emits `ID_BRIDGE_IDENTITY_RESTORE_REQUEST`
  - [ ] Emits `ID_BRIDGE_IDENTITY_RESTORE_RESPONSE`

---