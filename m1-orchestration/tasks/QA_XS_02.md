# Task Prompt: QA_XS_02 - Manual Test Script: Restore Path

## Instructions for AI Agent
You are creating a QA test script. Follow the specification exactly.

---

## Task Definition
```
[TASK QA_XS_02 – Manual test script: restore path]

Goal: Write a manual test script for restoring identity from mnemonic.

Preconditions:
  - Have a known test mnemonic (e.g., from previous generate)
  - Know the expected peerId for that mnemonic

Positive Path Steps:
  1. Clear app data
  2. Launch app → IdentityChoiceScreen
  3. Tap "Load my key"
  4. Verify: MnemonicInputScreen appears
  5. Enter valid 12-word mnemonic
  6. Tap "Restore identity"
  7. Verify: Loading indicator shown briefly
  8. Verify: Success feedback
  9. Verify: Navigate to main app
  10. Verify: DB identity has expected peerId

Negative Path Steps:
  1. On MnemonicInputScreen, enter only 10 words
  2. Tap "Restore identity"
  3. Verify: Error message "Please enter exactly 12 words"
  4. Verify: Stay on MnemonicInputScreen
  5. Verify: DB still has no identity

Pass Criteria:
  - Positive path: Identity restored with correct peerId
  - Negative path: Validation prevents bad data

Deliverable:
  - File: docs/qa/QA_XS_02_restore.md
```

## Begin Implementation
Output the complete test script document.
