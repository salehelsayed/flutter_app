# Task Prompt: QA_XS_03 - Manual Test Script: Relaunch with Existing Identity

## Instructions for AI Agent
You are creating a QA test script. Follow the specification exactly.

---

## Task Definition
```
[TASK QA_XS_03 – Manual test script: relaunch with existing identity]

Goal: Verify that app skips onboarding when identity exists.

Preconditions:
  - DB has valid identity row (id=1)
  - Can be achieved by completing QA_XS_01 or QA_XS_02 first

Test Steps:
  1. Ensure identity exists in DB (from prior test)
  2. Force-close app completely
  3. Relaunch app
  4. Verify: Loading/splash shown briefly
  5. Verify: Navigate DIRECTLY to main app
  6. Verify: IdentityChoiceScreen is NOT shown
  7. Verify: MnemonicInputScreen is NOT shown

Pass Criteria:
  - Onboarding is completely bypassed
  - Main app is shown immediately

Expected Flow Events:
  - ID_STARTUP_FLOW_BEGIN
  - ID_STARTUP_DECIDE_ROUTE_CALL
  - ID_DB_LOAD_IDENTITY_START
  - ID_DB_LOAD_IDENTITY_FOUND
  - ID_REPO_LOAD_IDENTITY_FOUND
  - ID_STARTUP_HAS_ID
  - ID_STARTUP_ROUTE_MAIN

Deliverable:
  - File: docs/qa/QA_XS_03_relaunch.md
```

## Begin Implementation
Output the complete test script document.
