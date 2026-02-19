# M1 Identity Initialization - Orchestration Package

## Overview

This package contains everything needed to implement the **M1 Identity Initialization** milestone using AI coding agents. Each task is self-contained and can be executed independently.

## Package Contents

```
m1-orchestration/
├── README.md                      # This file
├── GLOBAL_CONTEXT.md              # Shared context (included in every task)
├── execution-order.md             # Sequence and parallelization guide
├── verification-checklist.md     # How to verify each task
├── file-structure.md              # Where to put generated code
└── tasks/
    ├── DB_XS_01.md                # Database: Identity table migration
    ├── DB_XS_02.md                # Database: Load identity row
    ├── DB_XS_03.md                # Database: Upsert identity row
    ├── FL_XS_01.md                # Flutter: IdentityModel
    ├── FL_XS_02.md                # Flutter: Repository interface
    ├── FL_XS_03.md                # Flutter: loadIdentity() impl
    ├── FL_XS_04.md                # Flutter: saveIdentity() impl
    ├── FL_XS_05.md                # Flutter: Startup decision
    ├── FL_XS_06.md                # Flutter: Generate use-case
    ├── FL_XS_07.md                # Flutter: Restore use-case
    ├── FL_XS_08.md                # Flutter: Bridge generate
    ├── FL_XS_09.md                # Flutter: Bridge restore
    ├── FL_XS_10.md                # Flutter: IdentityChoiceScreen layout
    ├── FL_XS_11.md                # Flutter: Wire "I'm new here"
    ├── FL_XS_12.md                # Flutter: Wire "Load my key"
    ├── FL_XS_13.md                # Flutter: MnemonicInputScreen layout
    ├── FL_XS_14.md                # Flutter: Wire restore screen
    ├── FL_XS_15.md                # Flutter: Startup routing
    ├── JS_XS_01.md                # JS: IdentityJson type
    ├── JS_XS_02.md                # JS: generateIdentity()
    ├── JS_XS_03.md                # JS: restoreIdentityFromMnemonic()
    ├── JS_XS_04.md                # JS: Bridge handlers
    ├── QA_XS_01.md                # QA: New identity test script
    ├── QA_XS_02.md                # QA: Restore test script
    └── QA_XS_03.md                # QA: Relaunch test script
```

## How to Use

### Step 1: Understand the Execution Order

Open `execution-order.md` to see which tasks can run in parallel and which have dependencies.

### Step 2: Execute Tasks

For each task:

1. Open the task file (e.g., `tasks/DB_XS_01.md`)
2. Copy the **entire contents**
3. Paste to your AI coding agent
4. Collect the generated code
5. Place the code in the correct location (see `file-structure.md`)
6. Mark complete on `verification-checklist.md`

### Step 3: Verify

After each task, run the verification steps listed in the task file and checklist.

### Step 4: Integrate

Once all tasks in a phase are complete, run integration verification before moving to the next phase.

## Task Prompt Structure

Each task file contains:

```
┌─────────────────────────────────────────────────────────────────┐
│  SYSTEM INSTRUCTIONS                                            │
│  (Tells the agent how to behave)                                │
├─────────────────────────────────────────────────────────────────┤
│  GLOBAL CONTEXT                                                 │
│  (Shared data contracts, schemas, etc.)                         │
├─────────────────────────────────────────────────────────────────┤
│  TASK DEFINITION                                                │
│  (Specific task with inputs/outputs/flow events)                │
├─────────────────────────────────────────────────────────────────┤
│  OUTPUT REQUIREMENTS                                            │
│  (What files to produce, format, etc.)                          │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

1. Start with Phase 1 tasks (can run in parallel):
   - `DB_XS_01.md` → `DB_XS_02.md` → `DB_XS_03.md`
   - `JS_XS_01.md` → `JS_XS_02.md` → `JS_XS_03.md` → `JS_XS_04.md`
   - `FL_XS_01.md` → `FL_XS_02.md`

2. Continue with Phase 2 (Repository Implementation):
   - `FL_XS_03.md` (needs DB_XS_02)
   - `FL_XS_04.md` (needs DB_XS_03)

3. Continue through remaining phases as documented in `execution-order.md`

## Tips

- **Always include the full prompt** - Each task file is self-contained
- **Don't skip tasks** - Even if they seem simple, the flow events are important
- **Verify before proceeding** - Check outputs match expected signatures
- **Keep outputs organized** - Use the file structure in `file-structure.md`
