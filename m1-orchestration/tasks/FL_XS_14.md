# Task Prompt: FL_XS_14 - Wire MnemonicInputScreen

## Instructions for AI Agent
You are implementing a specific task for a Flutter application. Follow the task specification exactly.

---

## Task Definition
```
[TASK FL_XS_14 – Wire MnemonicInputScreen to restoreIdentityFromMnemonic()]

Goal: Connect MnemonicInputScreen to the restore use case.

What to implement:
  - A wrapper widget that:
      - Creates MnemonicInputScreen with onRestorePressed callback
      - onRestorePressed implementation:
          1. Call restoreIdentityFromMnemonic(input, callJsRestore, repo)
          2. Handle each result:
             - success → navigate to main app
             - invalidMnemonicFormat → show "Please enter exactly 12 words"
             - invalidMnemonicCore → show "Invalid recovery phrase"
             - coreLibError/dbError → show generic error

Inputs:
  - IdentityRepository repo
  - callJsIdentityRestore function
  - restoreIdentityFromMnemonic use case
  - Navigator

Outputs:
  - On success: Identity saved, navigation to main app
  - On error: Appropriate message shown

Flow_events:
  - On button press: layer: "FL", event: "ID_BTN_RESTORE_CLICK"
  - On validation error shown: layer: "FL", event: "ID_RESTORE_VALIDATION_MESSAGE_SHOWN"
  - On other error shown: layer: "FL", event: "ID_RESTORE_ERROR_SHOWN"
  - After success navigation: layer: "FL", event: "ID_NAV_MAIN_AFTER_RESTORE"

Deliverable:
  - File: lib/features/identity/presentation/screens/mnemonic_input_wired.dart
```

## Begin Implementation
Output the complete wrapper widget code.
