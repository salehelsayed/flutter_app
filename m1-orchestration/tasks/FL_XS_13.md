# Task Prompt: FL_XS_13 - MnemonicInputScreen Layout

## Instructions for AI Agent
You are implementing a specific task for a Flutter application. Follow the task specification exactly.

---

## Task Definition
```
[TASK FL_XS_13 – MnemonicInputScreen layout]

Goal: Build screen for entering 12-word mnemonic (pure layout).

What to implement:
  - StatefulWidget: MnemonicInputScreen
  - Constructor with callback:
      final Future<void> Function(String mnemonic) onRestorePressed;
  - Layout:
      - Title: "Enter Recovery Phrase"
      - Helper text about entering 12 words
      - TextField for mnemonic input (multiline)
      - "Restore identity" button → calls onRestorePressed(text)

Inputs:
  - onRestorePressed: Async callback receiving mnemonic string

Outputs:
  - Widget tree with input form
  - Passes raw text to callback

Flow_events:
  - None (pure layout)

Constraints:
  - No validation logic - just pass input to callback

Deliverable:
  - File: lib/features/identity/presentation/screens/mnemonic_input_screen.dart
```

## UI Mockup
```
┌─────────────────────────────────────┐
│  ← Back                             │
│                                     │
│     Enter Recovery Phrase           │
│                                     │
│  Enter your 12-word recovery        │
│  phrase below                       │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ word1 word2 word3 word4     │    │
│  │ word5 word6 word7 word8     │    │
│  │ word9 word10 word11 word12  │    │
│  └─────────────────────────────┘    │
│                                     │
│     ┌─────────────────────┐         │
│     │  Restore identity   │         │
│     └─────────────────────┘         │
│                                     │
└─────────────────────────────────────┘
```

## Begin Implementation
Output the complete widget code.
