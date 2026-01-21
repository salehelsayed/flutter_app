### FL_XS_03 - loadIdentity() Implementation

- [ ] **Class exists:** `IdentityRepositoryImpl implements IdentityRepository`
- [ ] **Dependency injection:** `dbLoadIdentityRow` injected via constructor
- [ ] **Correct mapping:** DB row → IdentityModel field mapping:
  - [ ] `row['peer_id']` → `peerId`
  - [ ] `row['public_key']` → `publicKey`
  - [ ] `row['private_key']` → `privateKey`
  - [ ] `row['mnemonic12']` → `mnemonic12`
  - [ ] `row['created_at']` → `createdAt`
  - [ ] `row['updated_at']` → `updatedAt`
- [ ] **Returns null correctly:** When `dbLoadIdentityRow()` returns null
- [ ] **Flow events:**
  - [ ] Emits `ID_REPO_LOAD_IDENTITY_CALL`
  - [ ] Emits `ID_REPO_LOAD_IDENTITY_FOUND` or `ID_REPO_LOAD_IDENTITY_NOT_FOUND`
