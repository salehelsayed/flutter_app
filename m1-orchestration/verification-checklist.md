# M1 Verification Checklist

Use this checklist to verify each task output before moving to dependent tasks.

---

## How to Use

1. After running a task, check all items in that task's section
2. If any check fails, fix before proceeding
3. Mark the task complete only when ALL checks pass
4. Integration checks should be done after each phase

---

## Task Verification

### DB_XS_01 - Identity Table Migration

- [ ] **File exists:** Migration file created at expected location
- [ ] **Syntax valid:** SQL syntax is correct
- [ ] **Idempotent:** Running twice doesn't error (CREATE TABLE IF NOT EXISTS)
- [ ] **Schema matches:** All columns match GLOBAL_CONTEXT specification:
  - [ ] `id INTEGER PRIMARY KEY`
  - [ ] `peer_id TEXT NOT NULL`
  - [ ] `public_key TEXT NOT NULL`
  - [ ] `private_key TEXT NOT NULL`
  - [ ] `mnemonic12 TEXT NOT NULL`
  - [ ] `created_at TEXT NOT NULL`
  - [ ] `updated_at TEXT NOT NULL`
- [ ] **Flow events:** Emits `ID_DB_IDENTITY_MIGRATION_START` and `ID_DB_IDENTITY_MIGRATION_SUCCESS`

```sql
-- Quick test: Run this after migration
SELECT sql FROM sqlite_master WHERE name = 'identity';
-- Should return the CREATE TABLE statement
```

---

### DB_XS_02 - dbLoadIdentityRow()

- [ ] **Function signature:** `Future<Map<String, Object?>?> dbLoadIdentityRow()`
- [ ] **Returns Map when row exists:** All column keys present
- [ ] **Returns null when no row:** Not an empty map, actual `null`
- [ ] **Column names correct:** Uses `peer_id`, `public_key`, etc. (snake_case)
- [ ] **Flow events:**
  - [ ] Emits `ID_DB_LOAD_IDENTITY_START`
  - [ ] Emits `ID_DB_LOAD_IDENTITY_FOUND` or `ID_DB_LOAD_IDENTITY_NOT_FOUND`
- [ ] **Error handling:** DB errors surface as exceptions

```dart
// Quick test
final row = await dbLoadIdentityRow();
print(row); // null on empty DB
```

---

### DB_XS_03 - dbUpsertIdentityRow()

- [ ] **Function signature:** `Future<void> dbUpsertIdentityRow(Map<String, Object?> row)`
- [ ] **Accepts correct keys:** `peer_id`, `public_key`, `private_key`, `mnemonic12`, `created_at`, `updated_at`
- [ ] **Always writes id=1:** Hardcoded or enforced
- [ ] **Upsert behavior:** INSERT OR REPLACE works correctly
- [ ] **Flow events:**
  - [ ] Emits `ID_DB_UPSERT_IDENTITY_START`
  - [ ] Emits `ID_DB_UPSERT_IDENTITY_SUCCESS`
- [ ] **Error handling:** DB errors surface as exceptions

```dart
// Quick test
await dbUpsertIdentityRow({
  'peer_id': 'test',
  'public_key': 'test',
  'private_key': 'test',
  'mnemonic12': 'test',
  'created_at': '2025-01-01T00:00:00.000Z',
  'updated_at': '2025-01-01T00:00:00.000Z',
});
final row = await dbLoadIdentityRow();
assert(row != null);
assert(row!['peer_id'] == 'test');
```

---

### FL_XS_01 - IdentityModel

- [ ] **Class exists:** `IdentityModel` class defined
- [ ] **All fields present:**
  - [ ] `String peerId`
  - [ ] `String publicKey`
  - [ ] `String privateKey`
  - [ ] `String mnemonic12`
  - [ ] `String createdAt`
  - [ ] `String updatedAt`
- [ ] **Immutable:** All fields are `final`
- [ ] **fromJson works:** Factory constructor accepts `Map<String, dynamic>`
- [ ] **toJson works:** Returns `Map<String, dynamic>` with correct keys
- [ ] **Round-trip test passes:**

```dart
final json = {
  'peerId': '12D3KooW...',
  'publicKey': 'base64...',
  'privateKey': 'base64...',
  'mnemonic12': 'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
  'createdAt': '2025-01-01T00:00:00.000Z',
  'updatedAt': '2025-01-01T00:00:00.000Z',
};
final model = IdentityModel.fromJson(json);
final back = model.toJson();
assert(back['peerId'] == json['peerId']);
// ... all fields match
```

---

### FL_XS_02 - IdentityRepository Interface

- [ ] **Abstract class exists:** `abstract class IdentityRepository`
- [ ] **Methods defined:**
  - [ ] `Future<IdentityModel?> loadIdentity()`
  - [ ] `Future<void> saveIdentity(IdentityModel identity)`
- [ ] **Doc comments present:** Describe behavior and return values
- [ ] **No implementation:** Pure interface, no method bodies

---

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

---

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

---

### FL_XS_05 - decideStartupRoute()

- [ ] **Enum exists:** `enum StartupDecision { hasIdentity, needsIdentity }`
- [ ] **Function signature:** `Future<StartupDecision> decideStartupRoute(IdentityRepository repo)`
- [ ] **Correct logic:**
  - [ ] Calls `repo.loadIdentity()`
  - [ ] Returns `hasIdentity` when identity != null
  - [ ] Returns `needsIdentity` when identity == null
- [ ] **Flow events:**
  - [ ] Emits `ID_STARTUP_DECIDE_ROUTE_CALL`
  - [ ] Emits `ID_STARTUP_HAS_ID` or `ID_STARTUP_NEEDS_ID`

---

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

---

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

---

### FL_XS_08 - callJsIdentityGenerate()

- [ ] **Function signature:** `Future<Map<String, dynamic>> callJsIdentityGenerate()`
- [ ] **Sends correct message:** `{ "cmd": "identity.generate", "payload": {} }`
- [ ] **Returns decoded response:** Map with `ok`, `identity` or `errorCode`
- [ ] **Flow events:**
  - [ ] Emits `ID_BRIDGE_IDENTITY_GENERATE_REQUEST`
  - [ ] Emits `ID_BRIDGE_IDENTITY_GENERATE_RESPONSE`

---

### FL_XS_09 - callJsIdentityRestore()

- [ ] **Function signature:** `Future<Map<String, dynamic>> callJsIdentityRestore(String mnemonic12)`
- [ ] **Sends correct message:** `{ "cmd": "identity.restore", "payload": { "mnemonic12": ... } }`
- [ ] **Returns decoded response:** Map with `ok`, `identity` or `errorCode`
- [ ] **Flow events:**
  - [ ] Emits `ID_BRIDGE_IDENTITY_RESTORE_REQUEST`
  - [ ] Emits `ID_BRIDGE_IDENTITY_RESTORE_RESPONSE`

---

### JS_XS_01 - IdentityJson Type

- [ ] **Interface defined:**
  ```typescript
  interface IdentityJson {
    peerId: string;
    publicKey: string;
    privateKey: string;
    mnemonic12: string;
    createdAt: string;
    updatedAt: string;
  }
  ```
- [ ] **Exported:** Can be imported by other modules

---

### JS_XS_02 - generateIdentity()

- [ ] **Function signature:** `async function generateIdentity(): Promise<IdentityJson>`
- [ ] **Generates keypair:** Ed25519 or appropriate algorithm
- [ ] **Derives peerId:** From public key
- [ ] **Generates mnemonic:** 12 BIP39 words
- [ ] **Sets timestamps:** createdAt and updatedAt to current UTC
- [ ] **Returns valid IdentityJson:** All fields populated
- [ ] **Flow events:**
  - [ ] Emits `ID_JS_GENERATE_IDENTITY_START`
  - [ ] Emits `ID_JS_GENERATE_IDENTITY_SUCCESS`

---

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

### JS_XS_04 - Bridge Handlers

- [ ] **Handler registered:** `identity.generate`
  - [ ] Calls `generateIdentity()`
  - [ ] Returns `{ ok: true, identity: ... }` on success
  - [ ] Returns `{ ok: false, errorCode: "INTERNAL_ERROR", ... }` on error
- [ ] **Handler registered:** `identity.restore`
  - [ ] Extracts `mnemonic12` from payload
  - [ ] Calls `restoreIdentityFromMnemonic()`
  - [ ] Returns `{ ok: true, identity: ... }` on success
  - [ ] Returns `{ ok: false, errorCode: "INVALID_MNEMONIC", ... }` on validation error
  - [ ] Returns `{ ok: false, errorCode: "INTERNAL_ERROR", ... }` on other errors
- [ ] **Flow events:** For both handlers

---

### FL_XS_10 - IdentityChoiceScreen Layout

- [ ] **Widget exists:** `IdentityChoiceScreen`
- [ ] **Callbacks in constructor:**
  - [ ] `VoidCallback onNewHere`
  - [ ] `VoidCallback onLoadMyKey`
- [ ] **UI elements:**
  - [ ] Title/welcome text
  - [ ] "I'm new here" button → calls `onNewHere`
  - [ ] "Load my key" button → calls `onLoadMyKey`
- [ ] **No business logic:** Pure layout

---

### FL_XS_11 - Wire "I'm new here"

- [ ] **Calls generateNewIdentity:** With correct dependencies
- [ ] **Handles success:** Navigates to main app
- [ ] **Handles errors:** Shows snackbar/error message
- [ ] **Flow events:**
  - [ ] Emits `ID_BTN_GENERATE_CLICK`
  - [ ] Emits `ID_NAV_MAIN_AFTER_GENERATE` on success

---

### FL_XS_12 - Wire "Load my key"

- [ ] **Navigates to MnemonicInputScreen:** On button press
- [ ] **Flow events:**
  - [ ] Emits `ID_BTN_RESTORE_NAVIGATE`
  - [ ] Emits `ID_NAV_TO_MNEMONIC_SCREEN`

---

### FL_XS_13 - MnemonicInputScreen Layout

- [ ] **Widget exists:** `MnemonicInputScreen`
- [ ] **Callback in constructor:** `Future<void> Function(String) onRestorePressed`
- [ ] **UI elements:**
  - [ ] TextField for mnemonic input
  - [ ] Helper text about 12 words
  - [ ] "Restore identity" button → calls `onRestorePressed(mnemonic)`
- [ ] **No business logic:** Pure layout

---

### FL_XS_14 - Wire MnemonicInputScreen

- [ ] **Calls restoreIdentityFromMnemonic:** With correct dependencies
- [ ] **Handles all result cases:**
  - [ ] `success` → navigate to main
  - [ ] `invalidMnemonicFormat` → show "enter 12 words" message
  - [ ] `invalidMnemonicCore` → show "invalid mnemonic" message
  - [ ] `coreLibError`/`dbError` → show generic error
- [ ] **Flow events:** As specified in task

---

### FL_XS_15 - Startup Router

- [ ] **Widget exists:** `StartupRouter`
- [ ] **Calls decideStartupRoute:** On initialization
- [ ] **Routes correctly:**
  - [ ] `hasIdentity` → main app screen
  - [ ] `needsIdentity` → IdentityChoiceScreen
- [ ] **Shows loading:** While deciding
- [ ] **Flow events:**
  - [ ] Emits `ID_STARTUP_FLOW_BEGIN`
  - [ ] Emits `ID_STARTUP_ROUTE_MAIN` or `ID_STARTUP_ROUTE_ONBOARDING`

---

## Integration Verification

### After Phase 1

```dart
// Test: DB + Model integration
await runMigration();
final model = IdentityModel(...);
final row = model.toJson(); // Verify keys
```

### After Phase 2

```dart
// Test: Repository round-trip
final repo = IdentityRepositoryImpl(...);
await repo.saveIdentity(model);
final loaded = await repo.loadIdentity();
assert(loaded != null);
assert(loaded.peerId == model.peerId);
```

### After Phase 3

```dart
// Test: Use case execution
final result = await generateNewIdentity(
  callJsGenerate: mockJsGenerate,
  repo: repo,
);
assert(result == GenerateIdentityResult.success);
```

### After Phase 5

```
// Test: Full app flow
1. Clear DB
2. Launch app
3. Verify onboarding screen appears
4. Tap "I'm new here"
5. Verify main app appears
6. Relaunch app
7. Verify main app appears directly
```

---

## Final Sign-Off

- [ ] All 22 tasks verified individually
- [ ] All integration checks pass
- [ ] QA_XS_01 test script passes
- [ ] QA_XS_02 test script passes
- [ ] QA_XS_03 test script passes
- [ ] Flow events trace complete path for both flows
- [ ] No console errors or warnings

**M1 Identity Initialization: COMPLETE**

Signed: _______________ Date: _______________
