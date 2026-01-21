### JS_XS_02 - generateIdentity()

- [x] **Function signature:** `async function generateIdentity(): Promise<IdentityJson>`
- [x] **Generates keypair:** Ed25519 or appropriate algorithm
- [x] **Derives peerId:** From public key
- [x] **Generates mnemonic:** 12 BIP39 words
- [x] **Sets timestamps:** createdAt and updatedAt to current UTC
- [x] **Returns valid IdentityJson:** All fields populated
- [x] **Flow events:**
  - [x] Emits `ID_JS_GENERATE_IDENTITY_START`
  - [x] Emits `ID_JS_GENERATE_IDENTITY_SUCCESS`

---