# Task Prompt: FL_XS_10 - IdentityChoiceScreen Layout

## Instructions for AI Agent
You are implementing a specific task for a Flutter application. Follow the task specification exactly.

---

## Task Definition
```
[TASK FL_XS_10 – IdentityChoiceScreen layout]

Goal: Build the onboarding screen with two buttons (pure layout, no business logic).

What to implement:
  - StatelessWidget: IdentityChoiceScreen
  - Constructor with callbacks:
      final VoidCallback onNewHere;
      final VoidCallback onLoadMyKey;
  - Layout:
      - Title: "Welcome"
      - Subtitle explaining the two options
      - Button A: "I'm new here" → calls onNewHere
      - Button B: "Load my key" → calls onLoadMyKey

Inputs:
  - onNewHere: VoidCallback
  - onLoadMyKey: VoidCallback

Outputs:
  - Widget tree with styled layout
  - No side-effects (callbacks handle logic)

Flow_events:
  - None (pure layout widget)

Constraints:
  - No business logic - just call the callbacks
  - Use Material Design components

Deliverable:
  - File: lib/features/identity/presentation/screens/identity_choice_screen.dart
```

## UI Mockup
```
┌─────────────────────────────────────┐
│                                     │
│            Welcome                  │
│                                     │
│   Generate a new identity or        │
│   restore from recovery phrase      │
│                                     │
│     ┌─────────────────────┐         │
│     │   I'm new here      │         │
│     └─────────────────────┘         │
│                                     │
│     ┌─────────────────────┐         │
│     │   Load my key       │         │
│     └─────────────────────┘         │
│                                     │
└─────────────────────────────────────┘
```

## Begin Implementation
Output the complete widget code.
