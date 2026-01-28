# Task Prompt: FL_XS_12 - Wire "Load my key" Button

## Instructions for AI Agent
You are implementing a specific task for a Flutter application. Follow the task specification exactly.

---

## Task Definition
```
[TASK FL_XS_12 – Wire IdentityChoiceScreen "Load my key" button]

Goal: Connect the "Load my key" button to navigate to MnemonicInputScreen.

What to implement:
  - In the same wrapper widget as FL_XS_11:
      - Provide onLoadMyKey callback
      - onLoadMyKey implementation:
          - Navigator.push to MnemonicInputScreen

Inputs:
  - Navigator for routing

Outputs:
  - Navigation to MnemonicInputScreen

Flow_events:
  - On button tap: layer: "FL", event: "ID_BTN_RESTORE_NAVIGATE"
  - After navigation: layer: "FL", event: "ID_NAV_TO_MNEMONIC_SCREEN"

Constraints:
  - No restore logic here, just navigation

Deliverable:
  - Add to: lib/features/identity/presentation/screens/identity_choice_wired.dart
```

## Begin Implementation
Output the onLoadMyKey callback implementation.
