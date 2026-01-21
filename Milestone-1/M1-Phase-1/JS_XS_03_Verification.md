
### JS_XS_03 - restoreIdentityFromMnemonic()

- [ ] **Function signature:** `async function restoreIdentityFromMnemonic(mnemonic12: string): Promise<IdentityJson>`
- [ ] **Validates word count:** Throws/rejects if != 12
- [ ] **Validates mnemonic:** BIP39 validation
- [ ] **Deterministic:** Same mnemonic → same keypair → same peerId
- [ ] **Flow events:**
  - [ ] Emits `ID_JS_RESTORE_IDENTITY_START`
  - [ ] Emits `ID_JS_RESTORE_IDENTITY_INVALID_WORDCOUNT` if bad count
  - [ ] Emits `ID_JS_RESTORE_IDENTITY_SUCCESS` on success

---
