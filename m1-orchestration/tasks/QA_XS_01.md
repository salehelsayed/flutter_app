# Task Prompt: QA_XS_01 - Manual Test Script: New Identity Path

## Instructions for AI Agent
You are creating a QA test script. Follow the specification exactly.

---

## Task Definition
```
[TASK QA_XS_01 – Manual test script: new identity path]

Goal: Write a manual test script that verifies the "I'm new here" flow.

Test Steps:
  1. Clear app data / fresh install
  2. Launch app
  3. Verify: Onboarding screen (IdentityChoiceScreen) appears
  4. Tap "I'm new here"
  5. Verify: Loading indicator shown briefly
  6. Verify: Success feedback (snackbar or dialog)
  7. Verify: Navigate to main app screen
  8. Verify: DB has identity row with id=1

Pass Criteria:
  - Each step completes without error
  - Identity exists in DB after completion
  - Flow events fire in expected sequence

Expected Flow Events (in order):
  - ID_STARTUP_FLOW_BEGIN
  - ID_STARTUP_NEEDS_ID
  - ID_STARTUP_ROUTE_ONBOARDING
  - ID_BTN_GENERATE_CLICK
  - ID_M1_GENERATE_START
  - ID_M1_GENERATE_JS_CALL
  - ID_JS_BRIDGE_IDENTITY_GENERATE_RECEIVED
  - ID_JS_GENERATE_IDENTITY_START
  - ID_JS_GENERATE_IDENTITY_SUCCESS
  - ID_JS_BRIDGE_IDENTITY_GENERATE_SUCCESS
  - ID_BRIDGE_IDENTITY_GENERATE_RESPONSE
  - ID_M1_GENERATE_JS_OK
  - ID_DB_UPSERT_IDENTITY_START
  - ID_DB_UPSERT_IDENTITY_SUCCESS
  - ID_M1_DB_SAVE_SUCCESS
  - ID_NAV_MAIN_AFTER_GENERATE

Deliverable:
  - File: docs/qa/QA_XS_01_new_identity.md
```

## Begin Implementation
Output the complete test script document.
