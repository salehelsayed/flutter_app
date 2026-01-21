### FL_XS_07 - restoreIdentityFromMnemonic()

- [ ] **Enum exists:**
  ```dart
  enum RestoreIdentityResult {
    success,
    invalidMnemonicFormat,
    invalidMnemonicCore,
    coreLibError,
    dbError,
  }
  ```
- [ ] **Local validation:** Checks word count == 12
- [ ] **Error code handling:**
  - [ ] `INVALID_MNEMONIC` → `invalidMnemonicCore`
  - [ ] Other errors → `coreLibError`
- [ ] **Flow events:**
  - [ ] Emits `ID_M1_RESTORE_START`
  - [ ] Emits `ID_RESTORE_VALIDATION_FAIL` on bad word count
  - [ ] Emits `ID_M1_RESTORE_JS_CALL`
  - [ ] Emits appropriate result events