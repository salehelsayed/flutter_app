# Task Prompt: FL_XS_11 - Wire "I'm new here" Button

## Instructions for AI Agent
You are implementing a specific task for a Flutter application. Follow the task specification exactly.

---

## Task Definition
```
[TASK FL_XS_11 – Wire IdentityChoiceScreen "I'm new here" button]

Goal: Connect the "I'm new here" button to generateNewIdentity() use case.

What to implement:
  - A wrapper StatefulWidget that:
      - Provides onNewHere callback to IdentityChoiceScreen
      - onNewHere implementation:
          1. Call generateNewIdentity(callJsGenerate, repo)
          2. On success → navigate to main app
          3. On error → show snackbar with error message

Inputs:
  - IdentityRepository repo (injected)
  - callJsIdentityGenerate function (injected)
  - generateNewIdentity use case
  - Navigator for routing

Outputs:
  - On success: Identity saved, navigation to main app
  - On error: Snackbar shown

Flow_events:
  - On button tap: layer: "FL", event: "ID_BTN_GENERATE_CLICK"
  - After success navigation: layer: "FL", event: "ID_NAV_MAIN_AFTER_GENERATE"
  - On error shown: layer: "FL", event: "ID_GENERATE_ERROR_SHOWN"

Deliverable:
  - File: lib/features/identity/presentation/screens/identity_choice_wired.dart (partial)
```

## Begin Implementation
Output the wrapper widget code that wires the "I'm new here" button.
