### FL_XS_06 - generateNewIdentity()

- [ ] **Enum exists:** `enum GenerateIdentityResult { success, coreLibError, dbError }`
- [ ] **Function signature matches:**
  ```dart
  Future<GenerateIdentityResult> generateNewIdentity({
    required Future<Map<String, dynamic>> Function() callJsGenerate,
    required IdentityRepository repo,
  })
  ```
- [ ] **Logic correct:**
  - [ ] Calls `callJsGenerate()`
  - [ ] Checks `response['ok']`
  - [ ] On ok=false → returns `coreLibError`
  - [ ] On ok=true → builds IdentityModel from `response['identity']`
  - [ ] Calls `repo.saveIdentity()`
  - [ ] On save error → returns `dbError`
  - [ ] On success → returns `success`
- [ ] **Flow events:**
  - [ ] Emits `ID_M1_GENERATE_START`
  - [ ] Emits `ID_M1_GENERATE_JS_CALL`
  - [ ] Emits `ID_M1_GENERATE_JS_OK` or `ID_M1_GENERATE_JS_ERROR`
  - [ ] Emits `ID_M1_DB_SAVE_SUCCESS` or `ID_M1_DB_SAVE_ERROR`
