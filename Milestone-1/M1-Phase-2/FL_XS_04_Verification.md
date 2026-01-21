### FL_XS_04 - saveIdentity() Implementation

- [ ] **Method implemented:** `saveIdentity(IdentityModel identity)`
- [ ] **Correct mapping:** IdentityModel → DB row:
  - [ ] `peerId` → `'peer_id'`
  - [ ] `publicKey` → `'public_key'`
  - [ ] `privateKey` → `'private_key'`
  - [ ] `mnemonic12` → `'mnemonic12'`
  - [ ] `createdAt` → `'created_at'`
  - [ ] `updatedAt` → `'updated_at'`
- [ ] **Calls dbUpsertIdentityRow:** With mapped data
- [ ] **Flow events:**
  - [ ] Emits `ID_REPO_SAVE_IDENTITY_CALL`
  - [ ] Emits `ID_REPO_SAVE_IDENTITY_SUCCESS`
