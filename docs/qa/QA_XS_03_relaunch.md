# QA Test Script: Relaunch with Existing Identity

## Test ID: QA_XS_03
**Test Name:** App Relaunch with Existing Identity
**Test Type:** Manual Integration Test
**Feature:** M1 Identity Initialization - Relaunch behavior
**Last Updated:** 2025-01-17

---

## Test Objective
Verify that the application correctly skips the onboarding flow and navigates directly to the main app when relaunching with an existing identity in the database.

---

## Prerequisites
- Flutter application built and ready to run
- Access to device/emulator console for viewing flow events
- Database inspection tool (e.g., DB Browser for SQLite)
- **IMPORTANT:** An existing identity must be present in the database
  - Complete either QA_XS_01 (new identity) or QA_XS_02 (restore) first
  - OR manually insert a valid identity row into the database

---

## Pre-Test Setup

### Option A: Use Previous Test Result
If you just completed QA_XS_01 or QA_XS_02:
1. Do NOT clear app data
2. Verify identity exists with database query:
```sql
SELECT COUNT(*) FROM identity;
-- Should return: 1

SELECT id, peer_id FROM identity WHERE id = 1;
-- Should return a valid identity row
```

### Option B: Manual Database Setup
If starting fresh, insert test identity:
```sql
INSERT INTO identity (
  id, peer_id, public_key, private_key, mnemonic12, created_at, updated_at
) VALUES (
  1,
  '12D3KooWTestPeer123',
  'test_public_key_base64',
  'test_private_key_base64',
  'test seed phrase with twelve words for testing database state only here',
  '2025-01-17T12:00:00.000Z',
  '2025-01-17T12:00:00.000Z'
);
```

---

## Test Steps

### Step 1: Verify Existing Identity
**Action:**
1. Open database inspection tool
2. Query the identity table

**Database Query:**
```sql
SELECT * FROM identity WHERE id = 1;
```

**Expected Result:**
- One identity row exists with id = 1
- All fields populated (peer_id, public_key, private_key, mnemonic12, timestamps)

**Pre-condition Check:**
- ✅ Identity exists in database
- ✅ Identity has id = 1
- ✅ All required fields are non-null

---

### Step 2: Force-Close Application
**Action:**
1. If app is running, force-close it completely:
   - **Android:**
     - Use Recent Apps → Swipe away
     - OR Settings → Apps → [App Name] → Force Stop
   - **iOS:**
     - Double-tap Home/Swipe up → Swipe app away
   - **Desktop/Emulator:**
     - Stop the Flutter run process
     - Kill any remaining app processes

**Expected Result:**
- App is completely terminated
- No app processes running in background

**Verification:**
```bash
# Check no app processes running (platform-specific)
# Android: adb shell ps | grep [app_package]
# iOS: Check in Xcode device console
# Desktop: ps aux | grep [app_name]
```

---

### Step 3: Relaunch Application
**Action:**
1. Start the application fresh
2. Begin capturing console/log output immediately

**Expected Result:**
- App launches successfully
- Console begins showing flow events

**Initial Flow Events Expected:**
- `ID_STARTUP_FLOW_BEGIN`

---

### Step 4: Verify Loading/Splash Screen
**Action:**
1. Observe the initial screen shown
2. Note the duration of loading state

**Expected Result:**
- Loading or splash screen appears briefly (< 2 seconds)
- Shows loading indicator or app logo
- No onboarding content visible

**Timing:** Loading should be brief, typically 500ms-1500ms

---

### Step 5: Verify Direct Navigation to Main App
**Action:**
1. Wait for navigation to complete
2. Observe the screen that appears

**Expected Result:**
- MainAppScreen is displayed
- Shows "Welcome! Identity loaded." or similar message
- Main app content is visible and functional
- User's identity is loaded (peerId accessible)

**Screenshot Point:** Capture main app screen after relaunch

**Flow Events Expected:**
- `ID_STARTUP_DECIDE_ROUTE_CALL`
- `ID_DB_LOAD_IDENTITY_START`
- `ID_DB_LOAD_IDENTITY_FOUND`
- `ID_REPO_LOAD_IDENTITY_FOUND`
- `ID_STARTUP_HAS_ID`
- `ID_STARTUP_ROUTE_MAIN`

---

### Step 6: Verify Onboarding NOT Shown
**Action:**
1. Confirm current screen
2. Check navigation stack (if debuggable)

**Expected Result:**
- IdentityChoiceScreen is NOT displayed
- No "I'm new here" button visible
- No "Load my key" button visible
- Cannot navigate back to onboarding

**Negative Verification:**
- ❌ IdentityChoiceScreen not shown
- ❌ No onboarding flow initiated

---

### Step 7: Verify Mnemonic Input NOT Shown
**Action:**
1. Confirm no mnemonic-related screens
2. Verify no input fields for recovery phrase

**Expected Result:**
- MnemonicInputScreen is NOT displayed
- No text field for entering mnemonic
- No "Restore identity" button visible

**Negative Verification:**
- ❌ MnemonicInputScreen not shown
- ❌ No restore flow accessible

---

### Step 8: Verify Identity Loaded Correctly
**Action:**
1. Check app state or debug info
2. Verify identity details if displayed in UI

**Expected Result:**
- Identity is loaded and accessible in app
- PeerId matches database value
- App functions normally with loaded identity

**Optional Verification:**
- If app shows peerId in UI, verify it matches database
- If app has identity-dependent features, verify they work

---

## Pass Criteria

✅ **Test passes if ALL of the following are true:**
1. App launches successfully with existing identity
2. Loading/splash screen shown briefly (< 2 seconds)
3. Navigation goes DIRECTLY to MainAppScreen
4. IdentityChoiceScreen is NEVER shown
5. MnemonicInputScreen is NEVER shown
6. No option to access onboarding flow
7. Identity is properly loaded from database
8. All expected flow events fire in correct sequence

---

## Fail Criteria

❌ **Test fails if ANY of the following occur:**
- App crashes on relaunch
- Onboarding screen (IdentityChoiceScreen) appears
- Mnemonic input screen appears
- App fails to load existing identity
- Navigation does not go to main app
- Loading takes excessive time (> 5 seconds)
- Flow events missing or out of sequence
- Identity data not accessible in app

---

## Expected Flow Events Sequence

The complete sequence of events for relaunch with existing identity:

1. `ID_STARTUP_FLOW_BEGIN` - App startup initiated
2. `ID_STARTUP_DECIDE_ROUTE_CALL` - Routing decision started
3. `ID_REPO_LOAD_IDENTITY_CALL` - Repository checking for identity
4. `ID_DB_LOAD_IDENTITY_START` - Database query initiated
5. `ID_DB_LOAD_IDENTITY_FOUND` - Identity found in database
6. `ID_REPO_LOAD_IDENTITY_FOUND` - Repository confirms identity exists
7. `ID_STARTUP_HAS_ID` - Decision: has identity
8. `ID_STARTUP_ROUTE_MAIN` - Routing to main app

**Note:** No onboarding-related events should appear in the sequence.

---

## Additional Test Scenarios

### Scenario A: Multiple Relaunches
1. After Step 8, force-close app again
2. Relaunch a second time
3. Verify same behavior (direct to main)
4. Repeat 3-5 times to ensure consistency

### Scenario B: Quick Relaunch
1. Force-close app
2. Immediately relaunch (< 1 second)
3. Verify no race conditions or errors
4. Verify correct navigation occurs

### Scenario C: Background/Foreground (Mobile)
1. Put app in background (don't force-close)
2. Bring back to foreground
3. Verify identity remains loaded
4. Verify no re-onboarding occurs

---

## Edge Cases to Consider

1. **Corrupted Database:**
   - What if identity row is partially corrupted?
   - App should handle gracefully (error or re-onboard)

2. **Database Lock:**
   - What if database is temporarily locked on startup?
   - App should retry or show appropriate error

3. **Memory Pressure:**
   - Launch with low memory conditions
   - Verify app still loads identity correctly

---

## Test Data Collection

### Screenshots to Capture:
1. Loading/splash screen (if visible)
2. Main app screen after relaunch
3. Any error states encountered

### Logs to Collect:
1. Complete flow event sequence
2. Startup timing (from launch to main screen)
3. Database query timings
4. Any warnings or errors

### Metrics to Record:
- Time from launch to main screen (milliseconds)
- Number of database queries executed
- Memory usage at startup

---

## Regression Testing

This test should be run:
1. After any changes to startup routing logic
2. After identity management updates
3. After database migration changes
4. As part of release testing
5. When onboarding flow is modified

---

## Known Issues / Notes

- Some platforms may cache the app state; ensure complete termination
- Database file location varies by platform
- Flow events may have slight timing variations
- Debug builds may show longer loading times than release builds

---

## Test Sign-off

| Field | Value |
|-------|-------|
| Tester Name | _________________ |
| Test Date | _________________ |
| Build Version | _________________ |
| Device/Platform | _________________ |
| Previous Test | ⬜ QA_XS_01 / ⬜ QA_XS_02 / ⬜ Manual Setup |
| Result | ⬜ PASS / ⬜ FAIL |
| Time to Main Screen | _______ms |
| Notes | _________________ |

---

## Defects Found
If test fails, document defects here:

| Defect ID | Step Failed | Description | Severity |
|-----------|-------------|-------------|----------|
| | | | |

---

END OF TEST SCRIPT QA_XS_03