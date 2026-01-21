
### JS_XS_04 - Bridge Handlers

- [x] **Handler registered:** `identity.generate`
  - [x] Calls `generateIdentity()`
  - [x] Returns `{ ok: true, identity: ... }` on success
  - [x] Returns `{ ok: false, errorCode: "INTERNAL_ERROR", ... }` on error
- [x] **Handler registered:** `identity.restore`
  - [x] Extracts `mnemonic12` from payload
  - [x] Calls `restoreIdentityFromMnemonic()`
  - [x] Returns `{ ok: true, identity: ... }` on success
  - [x] Returns `{ ok: false, errorCode: "INVALID_MNEMONIC", ... }` on validation error
  - [x] Returns `{ ok: false, errorCode: "INTERNAL_ERROR", ... }` on other errors
- [x] **Flow events:** For both handlers