# QA Test Script: Restore Identity Path

## Test ID: QA_XS_02
**Test Name:** Identity Restore from Mnemonic Flow
**Test Type:** Manual Integration Test
**Feature:** M1 Identity Initialization - "Load my key" path
**Last Updated:** 2025-01-17

---

## Test Objective
Verify that users can successfully restore an existing identity using a 12-word mnemonic phrase through the "Load my key" flow, and that invalid mnemonics are properly rejected.

---

## Prerequisites
- Flutter application built and ready to run
- Access to device/emulator console for viewing flow events
- Database inspection tool (e.g., DB Browser for SQLite)
- Clean test environment (no existing identity data)
- Test mnemonic phrase with known peerId (see Test Data section)

---

## Test Data

### Valid Test Mnemonic
```
abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about
```

**Expected Results for Test Mnemonic:**
- PeerId: `12D3KooWEqBfNSWtqDpufPTDv3BdBuPvvoBPUQBKCpfVcR3aTXVX`
- This is the first valid BIP39 mnemonic, commonly used for testing

### Invalid Test Mnemonics
1. **Too few words (10 words):**
   ```
   abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon
   ```

2. **Too many words (13 words):**
   ```
   abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about extra
   ```

3. **Invalid BIP39 words:**
   ```
   invalid word phrase that is not valid bip39 mnemonic twelve words
   ```

---

## POSITIVE PATH TEST

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
  - "I'm new here" button (filled style)
  - "Load my key" button (outlined style)

**Screenshot Point:** Capture onboarding screen

---

### Step 4: Tap "Load my key"
**Action:**
1. Tap the "Load my key" button
2. Observe navigation

**Expected Result:**
- Button responds to tap
- Flow event emitted: `ID_BTN_LOAD_KEY_CLICK`
- Navigation occurs immediately

---

### Step 5: Verify Mnemonic Input Screen
**Action:**
1. Wait for MnemonicInputScreen to appear
2. Observe screen elements

**Expected Result:**
- MnemonicInputScreen is displayed
- Screen contains:
  - Title: "Enter Recovery Phrase"
  - Subtitle: "Enter your 12-word recovery phrase to restore your identity"
  - Large text input field (TextField)
  - Character counter or word counter
  - "Restore identity" button (initially may be disabled)
  - Back button or navigation arrow

**Screenshot Point:** Capture mnemonic input screen

---

### Step 6: Enter Valid Mnemonic
**Action:**
1. Tap on the text input field
2. Enter the test mnemonic:
   ```
   abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about
   ```
3. Observe UI changes

**Expected Result:**
- Keyboard appears
- Text is entered successfully
- Word count shows "12 words" or similar
- "Restore identity" button becomes enabled
- No error messages displayed

---

### Step 7: Tap "Restore identity"
**Action:**
1. Tap the "Restore identity" button
2. Observe UI feedback

**Expected Result:**
- Button responds to tap
- Loading indicator appears (CircularProgressIndicator)
- UI is temporarily disabled/non-interactive
- Flow event emitted: `ID_BTN_RESTORE_CLICK`

---

### Step 8: Verify Loading State
**Action:**
1. Observe the screen during identity restoration

**Expected Result:**
- Loading indicator remains visible
- Flow events in sequence:
  - `ID_M1_RESTORE_START`
  - `ID_M1_RESTORE_JS_CALL`
  - `ID_BRIDGE_IDENTITY_RESTORE_REQUEST`

**Timing:** Loading should display for 1-3 seconds

---

### Step 9: Verify Success Feedback
**Action:**
1. Wait for restoration to complete
2. Observe success indicators

**Expected Result:**
- Loading indicator disappears
- Success feedback shown (SnackBar or navigation)
- Flow events:
  - `ID_BRIDGE_IDENTITY_RESTORE_RESPONSE`
  - `ID_M1_RESTORE_JS_OK`
  - `ID_M1_DB_SAVE_SUCCESS`

---

### Step 10: Verify Navigation to Main App
**Action:**
1. Observe screen transition

**Expected Result:**
- Navigation to MainAppScreen
- Main app displays "Welcome! Identity loaded." or similar
- No back navigation to onboarding available
- Flow event: `ID_NAV_MAIN_AFTER_RESTORE`

**Screenshot Point:** Capture main app screen

---

### Step 11: Verify Database Entry
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
  - `peer_id`: Matches expected value (12D3KooWEqBfNSWtqDpufPTDv3BdBuPvvoBPUQBKCpfVcR3aTXVX)
  - `public_key`: Non-empty base64 string
  - `private_key`: Non-empty base64 string
  - `mnemonic12`: The test mnemonic used
  - `created_at`: ISO timestamp
  - `updated_at`: ISO timestamp

---

## NEGATIVE PATH TEST - Invalid Word Count

### Step 1: Reset to Mnemonic Input Screen
**Action:**
1. Clear app data (repeat Positive Path Step 1)
2. Launch app and navigate to MnemonicInputScreen (Steps 2-5)

---

### Step 2: Enter Invalid Mnemonic (Too Few Words)
**Action:**
1. Enter only 10 words:
   ```
   abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon
   ```
2. Attempt to tap "Restore identity" button

**Expected Result:**
- Word count shows "10 words"
- "Restore identity" button may be disabled OR
- If button is enabled, tapping shows error
- Error message displays: "Please enter exactly 12 words"
- Flow event: `ID_M1_RESTORE_VALIDATION_ERROR`

**Screenshot Point:** Capture error state

---

### Step 3: Verify No Navigation
**Action:**
1. Observe current screen

**Expected Result:**
- App remains on MnemonicInputScreen
- User can modify input
- No navigation to main app occurred

---

### Step 4: Verify Database Still Empty
**Action:**
1. Query the database

**Database Query:**
```sql
SELECT COUNT(*) FROM identity;
```

**Expected Result:**
- Returns 0 (no identity saved)
- Failed validation prevented database write

---

### Step 5: Enter Invalid BIP39 Words
**Action:**
1. Clear the text field
2. Enter 12 non-BIP39 words:
   ```
   invalid word phrase that is not valid bip39 mnemonic twelve words
   ```
3. Tap "Restore identity" button

**Expected Result:**
- Loading indicator appears briefly
- Error message displays: "Invalid recovery phrase" or similar
- Flow events:
  - `ID_M1_RESTORE_START`
  - `ID_BRIDGE_IDENTITY_RESTORE_REQUEST`
  - `ID_BRIDGE_IDENTITY_RESTORE_ERROR`
  - `ID_M1_RESTORE_INVALID_MNEMONIC`
- App remains on MnemonicInputScreen
- Database still empty

---

## Pass Criteria

### Positive Path ✅
- All steps complete without crashes
- Valid mnemonic successfully restores identity
- Restored identity has correct peerId matching the test mnemonic
- Database contains exactly one identity row with id = 1
- Navigation to main app occurs after successful restore
- Flow events fire in correct sequence

### Negative Path ✅
- Invalid word count (not 12) shows validation error
- Invalid BIP39 words show appropriate error
- Failed restoration attempts do not save to database
- User remains on input screen after errors
- User can retry with correct input

---

## Fail Criteria

❌ **Test fails if:**
- App crashes at any point
- Valid mnemonic fails to restore
- Restored peerId doesn't match expected value
- Invalid mnemonics are accepted
- Database contains identity after failed restore
- Navigation occurs with invalid input
- Error messages are missing or unclear
- Flow events are missing or out of sequence

---

## Additional Verification

### Relaunch Test After Restore
After completing successful restore:
1. Close the app completely
2. Relaunch the app
3. **Expected:** App navigates directly to MainAppScreen (skips onboarding)
4. **Flow events:**
   - `ID_STARTUP_FLOW_BEGIN`
   - `ID_STARTUP_HAS_ID`
   - `ID_STARTUP_ROUTE_MAIN`

### Edge Cases to Test
1. **Leading/trailing spaces:** Mnemonic with extra spaces should be trimmed
2. **Case sensitivity:** Mnemonic should work in lowercase
3. **Multiple spaces:** Extra spaces between words should be normalized
4. **Paste from clipboard:** Should support pasting full mnemonic

---

## Test Data Collection

### Screenshots to Capture:
1. Onboarding screen (IdentityChoiceScreen)
2. Mnemonic input screen (empty state)
3. Mnemonic input screen (with valid input)
4. Loading state during restore
5. Error state (invalid word count)
6. Error state (invalid BIP39 words)
7. Main app screen after success
8. Database query results

### Logs to Collect:
1. Complete flow event sequence
2. Any error messages or warnings
3. Restore timing (start to completion)
4. Bridge request/response payloads

---

## Expected Flow Events Sequence

### Successful Restore Flow:
1. `ID_STARTUP_FLOW_BEGIN`
2. `ID_STARTUP_NEEDS_ID`
3. `ID_STARTUP_ROUTE_ONBOARDING`
4. `ID_BTN_LOAD_KEY_CLICK`
5. `ID_NAV_MNEMONIC_INPUT`
6. `ID_BTN_RESTORE_CLICK`
7. `ID_M1_RESTORE_START`
8. `ID_M1_RESTORE_VALIDATE`
9. `ID_M1_RESTORE_JS_CALL`
10. `ID_BRIDGE_IDENTITY_RESTORE_REQUEST`
11. `ID_BRIDGE_IDENTITY_RESTORE_RESPONSE`
12. `ID_M1_RESTORE_JS_OK`
13. `ID_REPO_SAVE_IDENTITY_CALL`
14. `ID_DB_UPSERT_IDENTITY_START`
15. `ID_DB_UPSERT_IDENTITY_SUCCESS`
16. `ID_REPO_SAVE_IDENTITY_SUCCESS`
17. `ID_M1_DB_SAVE_SUCCESS`
18. `ID_NAV_MAIN_AFTER_RESTORE`

### Failed Validation Flow:
1. `ID_BTN_RESTORE_CLICK`
2. `ID_M1_RESTORE_START`
3. `ID_M1_RESTORE_VALIDATE`
4. `ID_M1_RESTORE_VALIDATION_ERROR`
5. `ID_UI_SHOW_ERROR`

---

## Known Issues / Notes

- The test mnemonic "abandon abandon..." is a standard test vector
- Real users should never use this mnemonic for actual identities
- Mnemonic input field should mask or hide the phrase in production
- Consider adding a "show/hide" toggle for mnemonic visibility
- Clipboard access may require additional permissions on some platforms

---

## Test Sign-off

| Field | Value |
|-------|-------|
| Tester Name | _________________ |
| Test Date | _________________ |
| Build Version | _________________ |
| Device/Platform | _________________ |
| Positive Path Result | ⬜ PASS / ⬜ FAIL |
| Negative Path Result | ⬜ PASS / ⬜ FAIL |
| Overall Result | ⬜ PASS / ⬜ FAIL |
| Notes | _________________ |

---

## Defects Found
If test fails, document defects here:

| Defect ID | Test Path | Step Failed | Description | Severity |
|-----------|-----------|-------------|-------------|----------|
| | | | | |

---

END OF TEST SCRIPT QA_XS_02