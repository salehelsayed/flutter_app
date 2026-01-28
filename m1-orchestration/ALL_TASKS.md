# M1 All Tasks - Complete Reference

## Index

| ID | Title |
|----|-------|
| DB_XS_01 | Identity Table Migration |
| DB_XS_02 | Load Identity Row |
| DB_XS_03 | Upsert Identity Row |
| JS_XS_01 | IdentityJson Type Definition |
| JS_XS_02 | generateIdentity() Implementation |
| JS_XS_03 | restoreIdentityFromMnemonic() |
| JS_XS_04 | Bridge Handlers |
| FL_XS_01 | IdentityModel with JSON Mapping |
| FL_XS_02 | IdentityRepository Interface |
| FL_XS_03 | IdentityRepositoryImpl.loadIdentity() |
| FL_XS_04 | IdentityRepositoryImpl.saveIdentity() |
| FL_XS_05 | StartupDecision and decideStartupRoute() |
| FL_XS_06 | generateNewIdentity() Use Case |
| FL_XS_07 | restoreIdentityFromMnemonic() Use Case |
| FL_XS_08 | callJsIdentityGenerate() Bridge Client |
| FL_XS_09 | callJsIdentityRestore() Bridge Client |
| FL_XS_10 | IdentityChoiceScreen Layout |
| FL_XS_11 | Wire "I'm new here" Button |
| FL_XS_12 | Wire "Load my key" Button |
| FL_XS_13 | MnemonicInputScreen Layout |
| FL_XS_14 | Wire MnemonicInputScreen |
| FL_XS_15 | Startup Routing |
| FL_XS_16 | Implement Real JS Bridge Connection (WebView) |
| QA_XS_01 | Manual Test Script: New Identity Path |
| QA_XS_02 | Manual Test Script: Restore Path |
| QA_XS_03 | Manual Test Script: Relaunch with Existing Identity |

---

# Database Tasks

---

## DB_XS_01 - Identity Table Migration

**Goal:** Create a DB migration that creates the identity table.

**What to implement:**
- One migration file/function that runs CREATE TABLE IF NOT EXISTS
- Integrate with migration runner pattern

**Schema:**
```sql
CREATE TABLE IF NOT EXISTS identity (
  id INTEGER PRIMARY KEY,
  peer_id TEXT NOT NULL,
  public_key TEXT NOT NULL,
  private_key TEXT NOT NULL,
  mnemonic12 TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
```

**Flow events:**
- ID_DB_IDENTITY_MIGRATION_START
- ID_DB_IDENTITY_MIGRATION_SUCCESS
- ID_DB_IDENTITY_MIGRATION_ERROR

**Deliverable:** `lib/core/database/migrations/001_identity_table.dart`

---

## DB_XS_02 - Load Identity Row

**Goal:** Helper to read the single identity row (id=1) from DB.

**Signature:** `Future<Map<String, Object?>?> dbLoadIdentityRow(Database db)`

**Behavior:**
- Run: SELECT * FROM identity WHERE id = 1 LIMIT 1
- If row exists → return Map with keys
- If no row → return null

**Flow events:**
- ID_DB_LOAD_IDENTITY_START
- ID_DB_LOAD_IDENTITY_FOUND / ID_DB_LOAD_IDENTITY_NOT_FOUND

**Deliverable:** `lib/core/database/helpers/identity_db_helpers.dart`

---

## DB_XS_03 - Upsert Identity Row

**Goal:** Helper to insert or update the active identity row at id=1.

**Signature:** `Future<void> dbUpsertIdentityRow(Database db, Map<String, Object?> row)`

**Behavior:**
- INSERT OR REPLACE with id=1
- Input keys: peer_id, public_key, private_key, mnemonic12, created_at, updated_at

**Flow events:**
- ID_DB_UPSERT_IDENTITY_START
- ID_DB_UPSERT_IDENTITY_SUCCESS

**Deliverable:** `lib/core/database/helpers/identity_db_helpers.dart`

---

# JavaScript Tasks

---

## JS_XS_01 - IdentityJson Type Definition

**Goal:** Create TypeScript type definition for IdentityJson.

**Interface:**
```typescript
export interface IdentityJson {
  peerId: string;
  publicKey: string;
  privateKey: string;
  mnemonic12: string;
  createdAt: string;
  updatedAt: string;
}
```

**Deliverable:** `core_lib_js/src/types/identity.ts`

---

## JS_XS_02 - generateIdentity() Implementation

**Goal:** Implement generateIdentity() that returns a new IdentityJson.

**Signature:** `async function generateIdentity(): Promise<IdentityJson>`

**Steps:**
1. Generate 12-word BIP39 mnemonic
2. Derive seed from mnemonic
3. Generate Ed25519 keypair from seed
4. Derive peerId from public key
5. Encode keys as base64
6. Set timestamps to current UTC

**Flow events:**
- ID_JS_GENERATE_IDENTITY_START
- ID_JS_GENERATE_IDENTITY_SUCCESS

**Deliverable:** `core_lib_js/src/identity/generate.ts`

---

## JS_XS_03 - restoreIdentityFromMnemonic()

**Goal:** Restore identity from 12-word mnemonic deterministically.

**Signature:** `async function restoreIdentityFromMnemonic(mnemonic12: string): Promise<IdentityJson>`

**Steps:**
1. Validate word count == 12
2. Validate BIP39 checksum
3. Derive seed from mnemonic
4. Derive keypair deterministically
5. Return IdentityJson

**Key property:** Same mnemonic → same keypair → same peerId

**Flow events:**
- ID_JS_RESTORE_IDENTITY_START
- ID_JS_RESTORE_IDENTITY_SUCCESS
- ID_JS_RESTORE_IDENTITY_INVALID_MNEMONIC

**Deliverable:** `core_lib_js/src/identity/restore.ts`

---

## JS_XS_04 - Bridge Handlers

**Goal:** Register handlers for identity.generate and identity.restore commands.

**Handlers:**
- `identity.generate` → call generateIdentity(), return { ok: true, identity }
- `identity.restore` → call restoreIdentityFromMnemonic(), return { ok: true, identity }

**Error responses:**
- { ok: false, errorCode: "INVALID_MNEMONIC", errorMessage }
- { ok: false, errorCode: "INTERNAL_ERROR", errorMessage }

**Deliverable:** `core_lib_js/src/bridge/handlers.ts`

---

# Flutter Tasks

---

## FL_XS_01 - IdentityModel with JSON Mapping

**Goal:** Create immutable Dart model matching IdentityJson.

**Fields:** peerId, publicKey, privateKey, mnemonic12, createdAt, updatedAt

**Methods:**
- `factory IdentityModel.fromJson(Map<String, dynamic> json)`
- `Map<String, dynamic> toJson()`

**Deliverable:** `lib/features/identity/domain/models/identity_model.dart`

---

## FL_XS_02 - IdentityRepository Interface

**Goal:** Define repository interface for identity persistence.

**Methods:**
- `Future<IdentityModel?> loadIdentity()`
- `Future<void> saveIdentity(IdentityModel identity)`

**Deliverable:** `lib/features/identity/domain/repositories/identity_repository.dart`

---

## FL_XS_03 - IdentityRepositoryImpl.loadIdentity()

**Goal:** Implement loadIdentity() using dbLoadIdentityRow().

**Mapping (DB → Model):**
- row["peer_id"] → peerId
- row["public_key"] → publicKey
- row["private_key"] → privateKey
- row["mnemonic12"] → mnemonic12
- row["created_at"] → createdAt
- row["updated_at"] → updatedAt

**Flow events:**
- ID_REPO_LOAD_IDENTITY_CALL
- ID_REPO_LOAD_IDENTITY_FOUND / ID_REPO_LOAD_IDENTITY_NOT_FOUND

**Deliverable:** `lib/features/identity/domain/repositories/identity_repository_impl.dart`

---

## FL_XS_04 - IdentityRepositoryImpl.saveIdentity()

**Goal:** Implement saveIdentity() using dbUpsertIdentityRow().

**Mapping (Model → DB):**
- peerId → "peer_id"
- publicKey → "public_key"
- privateKey → "private_key"
- mnemonic12 → "mnemonic12"
- createdAt → "created_at"
- updatedAt → "updated_at"

**Flow events:**
- ID_REPO_SAVE_IDENTITY_CALL
- ID_REPO_SAVE_IDENTITY_SUCCESS

**Deliverable:** `lib/features/identity/domain/repositories/identity_repository_impl.dart`

---

## FL_XS_05 - StartupDecision and decideStartupRoute()

**Goal:** Decide at startup whether to go to main app or identity onboarding.

**Enum:** `enum StartupDecision { hasIdentity, needsIdentity }`

**Function:**
```dart
Future<StartupDecision> decideStartupRoute(IdentityRepository repo) async {
  final identity = await repo.loadIdentity();
  return identity == null ? StartupDecision.needsIdentity : StartupDecision.hasIdentity;
}
```

**Flow events:**
- ID_STARTUP_DECIDE_ROUTE_CALL
- ID_STARTUP_HAS_ID / ID_STARTUP_NEEDS_ID

**Deliverable:** `lib/features/identity/application/startup_decision.dart`

---

## FL_XS_06 - generateNewIdentity() Use Case

**Goal:** Use case that calls JS bridge, maps result, and persists identity.

**Enum:** `enum GenerateIdentityResult { success, coreLibError, dbError }`

**Signature:**
```dart
Future<GenerateIdentityResult> generateNewIdentity({
  required Future<Map<String, dynamic>> Function() callJsGenerate,
  required IdentityRepository repo,
})
```

**Flow events:**
- ID_M1_GENERATE_START
- ID_M1_GENERATE_JS_CALL
- ID_M1_GENERATE_JS_OK / ID_M1_GENERATE_JS_ERROR
- ID_M1_DB_SAVE_SUCCESS / ID_M1_DB_SAVE_ERROR

**Deliverable:** `lib/features/identity/application/generate_identity_use_case.dart`

---

## FL_XS_07 - restoreIdentityFromMnemonic() Use Case

**Goal:** Validate mnemonic, call JS, and save identity.

**Enum:**
```dart
enum RestoreIdentityResult {
  success,
  invalidMnemonicFormat,
  invalidMnemonicCore,
  coreLibError,
  dbError,
}
```

**Behavior:**
1. Local validation: word count == 12
2. Call callJsRestore(mnemonic)
3. Handle response and save to DB

**Flow events:**
- ID_M1_RESTORE_START
- ID_RESTORE_VALIDATION_FAIL
- ID_M1_RESTORE_JS_OK / ID_RESTORE_INVALID_MNEMONIC_CORE

**Deliverable:** `lib/features/identity/application/restore_identity_use_case.dart`

---

## FL_XS_08 - callJsIdentityGenerate() Bridge Client

**Goal:** Helper to call JS bridge "identity.generate".

**Signature:** `Future<Map<String, dynamic>> callJsIdentityGenerate(JsBridge bridge)`

**Request:** `{ "cmd": "identity.generate", "payload": {} }`

**Flow events:**
- ID_BRIDGE_IDENTITY_GENERATE_REQUEST
- ID_BRIDGE_IDENTITY_GENERATE_RESPONSE

**Deliverable:** `lib/core/bridge/js_bridge_client.dart`

---

## FL_XS_09 - callJsIdentityRestore() Bridge Client

**Goal:** Helper to call JS bridge "identity.restore".

**Signature:** `Future<Map<String, dynamic>> callJsIdentityRestore(JsBridge bridge, String mnemonic12)`

**Request:** `{ "cmd": "identity.restore", "payload": { "mnemonic12": ... } }`

**Flow events:**
- ID_BRIDGE_IDENTITY_RESTORE_REQUEST
- ID_BRIDGE_IDENTITY_RESTORE_RESPONSE

**Deliverable:** `lib/core/bridge/js_bridge_client.dart`

---

## FL_XS_10 - IdentityChoiceScreen Layout

**Goal:** Build onboarding screen with two buttons (pure layout).

**Constructor:**
```dart
IdentityChoiceScreen({
  required VoidCallback onNewHere,
  required VoidCallback onLoadMyKey,
})
```

**UI:** Title, subtitle, "I'm new here" button, "Load my key" button

**Deliverable:** `lib/features/identity/presentation/screens/identity_choice_screen.dart`

---

## FL_XS_11 - Wire "I'm new here" Button

**Goal:** Connect button to generateNewIdentity() use case.

**Behavior:**
1. Call generateNewIdentity(callJsGenerate, repo)
2. On success → navigate to main app
3. On error → show snackbar

**Flow events:**
- ID_BTN_GENERATE_CLICK
- ID_NAV_MAIN_AFTER_GENERATE
- ID_GENERATE_ERROR_SHOWN

**Deliverable:** `lib/features/identity/presentation/screens/identity_choice_wired.dart`

---

## FL_XS_12 - Wire "Load my key" Button

**Goal:** Connect button to navigate to MnemonicInputScreen.

**Behavior:** Navigator.push to MnemonicInputScreen

**Flow events:**
- ID_BTN_RESTORE_NAVIGATE
- ID_NAV_TO_MNEMONIC_SCREEN

**Deliverable:** `lib/features/identity/presentation/screens/identity_choice_wired.dart`

---

## FL_XS_13 - MnemonicInputScreen Layout

**Goal:** Build screen for entering 12-word mnemonic (pure layout).

**Constructor:**
```dart
MnemonicInputScreen({
  required Future<void> Function(String mnemonic) onRestorePressed,
})
```

**UI:** Title, helper text, TextField, "Restore identity" button

**Deliverable:** `lib/features/identity/presentation/screens/mnemonic_input_screen.dart`

---

## FL_XS_14 - Wire MnemonicInputScreen

**Goal:** Connect screen to restoreIdentityFromMnemonic() use case.

**Handle results:**
- success → navigate to main app
- invalidMnemonicFormat → "Please enter exactly 12 words"
- invalidMnemonicCore → "Invalid recovery phrase"
- coreLibError/dbError → generic error

**Flow events:**
- ID_BTN_RESTORE_CLICK
- ID_NAV_MAIN_AFTER_RESTORE

**Deliverable:** `lib/features/identity/presentation/screens/mnemonic_input_wired.dart`

---

## FL_XS_15 - Startup Routing

**Goal:** Route from app startup to main app or IdentityChoiceScreen.

**Behavior:**
- Call decideStartupRoute(repo)
- hasIdentity → main app
- needsIdentity → IdentityChoiceWired

**Flow events:**
- ID_STARTUP_FLOW_BEGIN
- ID_STARTUP_ROUTE_MAIN / ID_STARTUP_ROUTE_ONBOARDING

**Deliverable:** `lib/features/identity/presentation/startup_router.dart`

---

## FL_XS_16 - Implement Real JS Bridge Connection (WebView)

**Goal:** Replace stub ProductionJsBridge with WebView-based implementation.

**Parts:**
1. Bundle JS code with esbuild for browser
2. WebView JsBridge implementation with JavaScript channels
3. Update main.dart to use WebViewJsBridge

**Dependencies:**
- webview_flutter: ^4.10.0
- bip39, @libp2p/crypto, @libp2p/peer-id (npm)

**Deliverables:**
- `core_lib_js/package.json`
- `core_lib_js/build.mjs`
- `assets/js/bridge.html`
- `lib/core/bridge/webview_js_bridge.dart`
- Updated `pubspec.yaml`

---

# QA Tasks

---

## QA_XS_01 - Manual Test Script: New Identity Path

**Goal:** Verify the "I'm new here" flow.

**Steps:**
1. Clear app data / fresh install
2. Launch app
3. Verify: Onboarding screen appears
4. Tap "I'm new here"
5. Verify: Loading indicator shown briefly
6. Verify: Navigate to main app
7. Verify: DB has identity row with id=1

**Pass criteria:** Identity exists in DB with real BIP39 mnemonic

---

## QA_XS_02 - Manual Test Script: Restore Path

**Goal:** Verify restore identity from mnemonic flow.

**Positive path:**
1. Enter valid 12-word mnemonic
2. Tap "Restore identity"
3. Verify: Navigate to main app
4. Verify: DB identity has expected peerId

**Negative path:**
1. Enter only 10 words
2. Verify: Error message shown
3. Verify: Stay on MnemonicInputScreen

---

## QA_XS_03 - Manual Test Script: Relaunch with Existing Identity

**Goal:** Verify app skips onboarding when identity exists.

**Steps:**
1. Ensure identity exists (from prior test)
2. Force-close and relaunch app
3. Verify: Navigate DIRECTLY to main app
4. Verify: Onboarding screens NOT shown

**Pass criteria:** Onboarding completely bypassed
