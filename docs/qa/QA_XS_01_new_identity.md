# QA Test Script: New Identity Path

## Test ID: QA_XS_01
**Test Name:** New Identity Generation Flow
**Test Type:** Manual Integration Test
**Feature:** M1 Identity Initialization - "I'm new here" path
**Last Updated:** 2025-01-17

---

## Test Objective
Verify that new users can successfully generate an identity through the "I'm new here" flow, and that the identity is properly persisted to the database.

---

## Prerequisites
- Flutter application built and ready to run
- Access to device/emulator console for viewing flow events
- Database inspection tool (e.g., DB Browser for SQLite)
- Clean test environment (no existing identity data)

---

## Test Steps

### Step 1: Clear App Data / Fresh Install
**Action:**
1. Uninstall the app completely from device/emulator, OR
2. Clear app data through device settings:
   - Android: Settings → Apps → [App Name] → Storage → Clear Data
   - iOS: Delete and reinstall app

**Expected Result:**
- App data completely cleared
- No existing database files

**Verification:**
```bash
# Check database is empty (if accessible)
sqlite3 [path_to_db] "SELECT COUNT(*) FROM identity;"
# Should return 0 or error (table doesn't exist)
```

---

### Step 2: Launch App
**Action:**
1. Start the application
2. Observe console output for flow events

**Expected Result:**
- App launches successfully
- Loading screen appears briefly
- Flow events in console:
  - `ID_STARTUP_FLOW_BEGIN`
  - `ID_STARTUP_NEEDS_ID`
  - `ID_STARTUP_ROUTE_ONBOARDING`

---

### Step 3: Verify Onboarding Screen
**Action:**
1. Wait for navigation to complete
2. Observe the screen content

**Expected Result:**
- IdentityChoiceScreen is displayed
- Screen contains:
  - Welcome title text
  - Subtitle explaining identity options
  - "I'm new here" button (prominent/filled style)
  - "Load my key" button (outlined style)

**Screenshot Point:** Capture onboarding screen

---

### Step 4: Tap "I'm new here"
**Action:**
1. Tap the "I'm new here" button
2. Observe immediate UI feedback

**Expected Result:**
- Button responds to tap
- Flow event emitted: `ID_BTN_GENERATE_CLICK`

---

### Step 5: Verify Loading Indicator
**Action:**
1. Observe the screen during identity generation

**Expected Result:**
- Loading indicator appears (CircularProgressIndicator)
- UI is temporarily disabled/non-interactive
- Flow events in sequence:
  - `ID_M1_GENERATE_START`
  - `ID_M1_GENERATE_JS_CALL`
  - `ID_BRIDGE_IDENTITY_GENERATE_REQUEST`

**Timing:** Loading should display for 1-3 seconds

---

### Step 6: Verify Success Feedback
**Action:**
1. Wait for generation to complete
2. Observe success indicators

**Expected Result:**
- Loading indicator disappears
- Success feedback shown (SnackBar or navigation)
- Flow events:
  - `ID_BRIDGE_IDENTITY_GENERATE_RESPONSE`
  - `ID_M1_GENERATE_JS_OK`
  - `ID_M1_DB_SAVE_SUCCESS`

---

### Step 7: Verify Navigation to Main App
**Action:**
1. Observe screen transition

**Expected Result:**
- Navigation to MainAppScreen
- Main app displays "Welcome! Identity loaded." or similar
- No back navigation to onboarding available
- Flow event: `ID_NAV_MAIN_AFTER_GENERATE`

**Screenshot Point:** Capture main app screen

---

### Step 8: Verify Database Entry
**Action:**
1. Access the app's database file
2. Query the identity table

**Database Query:**
```sql
SELECT * FROM identity WHERE id = 1;
```

**Expected Result:**
- Exactly one row exists with id = 1
- Row contains:
  - `peer_id`: Non-empty string (e.g., "12D3KooW...")
  - `public_key`: Non-empty base64 string
  - `private_key`: Non-empty base64 string
  - `mnemonic12`: 12 space-separated words
  - `created_at`: ISO timestamp
  - `updated_at`: ISO timestamp

---

## Pass Criteria

✅ **All steps complete without errors**
- No crashes or unhandled exceptions
- All UI elements respond correctly
- Navigation flows smoothly

✅ **Identity successfully created and persisted**
- Database contains exactly one identity row
- All identity fields populated correctly
- Identity has id = 1

✅ **Flow events fire in correct sequence**
Expected sequence (in order):
1. `ID_STARTUP_FLOW_BEGIN`
2. `ID_STARTUP_NEEDS_ID`
3. `ID_STARTUP_ROUTE_ONBOARDING`
4. `ID_BTN_GENERATE_CLICK`
5. `ID_M1_GENERATE_START`
6. `ID_M1_GENERATE_JS_CALL`
7. `ID_BRIDGE_IDENTITY_GENERATE_REQUEST`
8. `ID_BRIDGE_IDENTITY_GENERATE_RESPONSE`
9. `ID_M1_GENERATE_JS_OK`
10. `ID_REPO_SAVE_IDENTITY_CALL`
11. `ID_DB_UPSERT_IDENTITY_START`
12. `ID_DB_UPSERT_IDENTITY_SUCCESS`
13. `ID_REPO_SAVE_IDENTITY_SUCCESS`
14. `ID_M1_DB_SAVE_SUCCESS`
15. `ID_NAV_MAIN_AFTER_GENERATE`

---

## Fail Criteria

❌ **Test fails if:**
- App crashes at any point
- Onboarding screen doesn't appear on fresh install
- "I'm new here" button is non-functional
- Identity generation fails or times out
- Navigation to main app doesn't occur
- Database remains empty after completion
- Flow events are missing or out of sequence

---

## Additional Verification

### Relaunch Test
After completing the main test:
1. Close the app completely
2. Relaunch the app
3. **Expected:** App navigates directly to MainAppScreen (skips onboarding)
4. **Flow events:**
   - `ID_STARTUP_FLOW_BEGIN`
   - `ID_STARTUP_HAS_ID`
   - `ID_STARTUP_ROUTE_MAIN`

---

## Test Data Collection

### Screenshots to Capture:
1. Onboarding screen (IdentityChoiceScreen)
2. Loading state during generation
3. Main app screen after success
4. Database query results

### Logs to Collect:
1. Complete flow event sequence
2. Any error messages or warnings
3. Generation timing (start to completion)

---

## Known Issues / Notes

- Loading indicator should be visible but brief (1-3 seconds typical)
- Mnemonic phrase is generated but not displayed to user in this flow
- Identity uses Ed25519 keypair derived from random seed
- PeerId follows libp2p format (starts with "12D3KooW")

---

## Test Sign-off

| Field | Value |
|-------|-------|
| Tester Name | _________________ |
| Test Date | _________________ |
| Build Version | _________________ |
| Device/Platform | _________________ |
| Result | ⬜ PASS / ⬜ FAIL |
| Notes | _________________ |

---

## Defects Found
If test fails, document defects here:

| Defect ID | Step Failed | Description | Severity |
|-----------|-------------|-------------|----------|
| | | | |

---

END OF TEST SCRIPT QA_XS_01