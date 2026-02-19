# M1 Execution Order

This document shows the recommended order for executing tasks, including which tasks can run in parallel.

---

## Dependency Graph (Visual)

```
PHASE 1: Foundation (Parallel Tracks)
═══════════════════════════════════════════════════════════════════════════════

  DB Track              JS Track                Flutter Model Track
  ─────────             ────────                ───────────────────
      │                     │                           │
      ▼                     ▼                           ▼
  ┌─────────┐         ┌─────────┐                 ┌─────────┐
  │DB_XS_01 │         │JS_XS_01 │                 │FL_XS_01 │
  │Migration│         │Type def │                 │Model    │
  └────┬────┘         └────┬────┘                 └────┬────┘
       │                   │                           │
       ▼                   ▼                           ▼
  ┌─────────┐         ┌─────────┐                 ┌─────────┐
  │DB_XS_02 │         │JS_XS_02 │                 │FL_XS_02 │
  │Load     │         │Generate │                 │Interface│
  └────┬────┘         └────┬────┘                 └─────────┘
       │                   │                           
       ▼                   ▼                           
  ┌─────────┐         ┌─────────┐                      
  │DB_XS_03 │         │JS_XS_03 │                      
  │Upsert   │         │Restore  │                      
  └─────────┘         └────┬────┘                      
                           │                           
                           ▼                           
                      ┌─────────┐                      
                      │JS_XS_04 │                      
                      │Handlers │                      
                      └─────────┘                      


PHASE 2: Repository Implementation
═══════════════════════════════════════════════════════════════════════════════

  Requires: DB_XS_02, DB_XS_03, FL_XS_01, FL_XS_02

  ┌─────────┐         ┌─────────┐
  │FL_XS_03 │         │FL_XS_04 │
  │loadId() │         │saveId() │
  └─────────┘         └─────────┘


PHASE 3: Bridge & Use Cases
═══════════════════════════════════════════════════════════════════════════════

  Requires: JS_XS_04 for bridge, FL_XS_03/04 for use cases

  Bridge (needs JS_XS_04)        Use Cases (need FL_XS_03, FL_XS_04)
  ─────────────────────          ─────────────────────────────────
         │                                    │
         ▼                                    ▼
    ┌─────────┐                         ┌─────────┐
    │FL_XS_08 │                         │FL_XS_05 │
    │Generate │                         │Startup  │
    └────┬────┘                         │Decision │
         │                              └─────────┘
         ▼                                    
    ┌─────────┐                               
    │FL_XS_09 │                               
    │Restore  │                               
    └─────────┘                               
         │
         ▼
    ┌─────────┐         ┌─────────┐
    │FL_XS_06 │         │FL_XS_07 │
    │Gen UC   │         │Restore  │
    │         │         │UC       │
    └─────────┘         └─────────┘


PHASE 4: UI Layer
═══════════════════════════════════════════════════════════════════════════════

  Layout (no dependencies)       Wiring (needs use cases)
  ────────────────────────       ───────────────────────
         │                                │
         ▼                                │
    ┌─────────┐                           │
    │FL_XS_10 │                           │
    │Choice   │                           │
    │Layout   │                           │
    └────┬────┘                           │
         │                                │
         ▼                                ▼
    ┌─────────┐                     ┌─────────┐
    │FL_XS_13 │                     │FL_XS_11 │ (needs FL_XS_06, FL_XS_10)
    │Mnemonic │                     │Wire Gen │
    │Layout   │                     └─────────┘
    └─────────┘                           
                                    ┌─────────┐
                                    │FL_XS_12 │ (needs FL_XS_10)
                                    │Wire Nav │
                                    └─────────┘

                                    ┌─────────┐
                                    │FL_XS_14 │ (needs FL_XS_07, FL_XS_13)
                                    │Wire     │
                                    │Restore  │
                                    └─────────┘


PHASE 5: App Integration
═══════════════════════════════════════════════════════════════════════════════

  Requires: FL_XS_05, FL_XS_10 (and transitively all wiring)

    ┌─────────┐
    │FL_XS_15 │
    │Startup  │
    │Router   │
    └─────────┘


PHASE 6: QA Verification
═══════════════════════════════════════════════════════════════════════════════

  Requires: All implementation tasks complete

    ┌─────────┐   ┌─────────┐   ┌─────────┐
    │QA_XS_01 │   │QA_XS_02 │   │QA_XS_03 │
    │New ID   │   │Restore  │   │Relaunch │
    └─────────┘   └─────────┘   └─────────┘
```

---

## Execution Checklist

### Phase 1: Foundation (Can Run in Parallel)

**Track A: Database**
- [ ] `DB_XS_01` - Identity table migration
- [ ] `DB_XS_02` - dbLoadIdentityRow()
- [ ] `DB_XS_03` - dbUpsertIdentityRow()

**Track B: JavaScript Core-Lib**
- [ ] `JS_XS_01` - IdentityJson type definition
- [ ] `JS_XS_02` - generateIdentity()
- [ ] `JS_XS_03` - restoreIdentityFromMnemonic()
- [ ] `JS_XS_04` - Bridge handlers

**Track C: Flutter Model**
- [ ] `FL_XS_01` - IdentityModel with JSON mapping
- [ ] `FL_XS_02` - IdentityRepository interface

**Phase 1 Verification:**
- [ ] DB migration runs without error
- [ ] JS functions can be called from Node.js directly
- [ ] IdentityModel compiles and JSON round-trips correctly

---

### Phase 2: Repository Implementation

**Prerequisites:** DB_XS_02, DB_XS_03, FL_XS_01, FL_XS_02

- [ ] `FL_XS_03` - IdentityRepositoryImpl.loadIdentity()
- [ ] `FL_XS_04` - IdentityRepositoryImpl.saveIdentity()

**Phase 2 Verification:**
- [ ] Can save an IdentityModel and load it back
- [ ] Flow events fire correctly

---

### Phase 3: Bridge & Use Cases

**Prerequisites:** JS_XS_04, FL_XS_03, FL_XS_04

**Bridge Client:**
- [ ] `FL_XS_08` - callJsIdentityGenerate()
- [ ] `FL_XS_09` - callJsIdentityRestore()

**Use Cases:**
- [ ] `FL_XS_05` - decideStartupRoute()
- [ ] `FL_XS_06` - generateNewIdentity() (needs FL_XS_08)
- [ ] `FL_XS_07` - restoreIdentityFromMnemonic() (needs FL_XS_09)

**Phase 3 Verification:**
- [ ] Bridge can call JS and receive responses
- [ ] Use cases return correct result types
- [ ] Flow events trace complete path

---

### Phase 4: UI Layer

**Layout (No Prerequisites):**
- [ ] `FL_XS_10` - IdentityChoiceScreen layout
- [ ] `FL_XS_13` - MnemonicInputScreen layout

**Wiring (Prerequisites: Use Cases + Layouts):**
- [ ] `FL_XS_11` - Wire "I'm new here" button (needs FL_XS_06, FL_XS_10)
- [ ] `FL_XS_12` - Wire "Load my key" button (needs FL_XS_10)
- [ ] `FL_XS_14` - Wire MnemonicInputScreen (needs FL_XS_07, FL_XS_13)

**Phase 4 Verification:**
- [ ] Screens render correctly
- [ ] Button callbacks trigger correct use cases
- [ ] Navigation works between screens

---

### Phase 5: App Integration

**Prerequisites:** FL_XS_05, FL_XS_10, all wiring complete

- [ ] `FL_XS_15` - Startup routing

**Phase 5 Verification:**
- [ ] Fresh app shows onboarding
- [ ] App with identity goes to main

---

### Phase 6: QA Verification

**Prerequisites:** All implementation complete

- [ ] `QA_XS_01` - Execute new identity test script
- [ ] `QA_XS_02` - Execute restore test script
- [ ] `QA_XS_03` - Execute relaunch test script

**Phase 6 Verification:**
- [ ] All test scripts pass
- [ ] Flow events match expected sequence

---

## Parallel Execution Guide

If you have multiple agents available:

```
┌─────────────────────────────────────────────────────────────────┐
│  TIME    │  AGENT 1      │  AGENT 2      │  AGENT 3            │
├──────────┼───────────────┼───────────────┼─────────────────────┤
│  T+0     │  DB_XS_01     │  JS_XS_01     │  FL_XS_01           │
│  T+1     │  DB_XS_02     │  JS_XS_02     │  FL_XS_02           │
│  T+2     │  DB_XS_03     │  JS_XS_03     │  (wait)             │
│  T+3     │  FL_XS_03     │  JS_XS_04     │  FL_XS_10           │
│  T+4     │  FL_XS_04     │  FL_XS_08     │  FL_XS_13           │
│  T+5     │  FL_XS_05     │  FL_XS_09     │  FL_XS_12           │
│  T+6     │  FL_XS_06     │  FL_XS_11     │  (wait)             │
│  T+7     │  FL_XS_07     │  FL_XS_14     │  FL_XS_15           │
│  T+8     │  QA_XS_01     │  QA_XS_02     │  QA_XS_03           │
└──────────┴───────────────┴───────────────┴─────────────────────┘
```

---

## Critical Path

The longest dependency chain (critical path) is:

```
DB_XS_01 → DB_XS_02 → FL_XS_03 → FL_XS_06 → FL_XS_11 → FL_XS_15
    │                     ↑
    └→ DB_XS_03 → FL_XS_04┘

JS_XS_01 → JS_XS_02 → JS_XS_04 → FL_XS_08 → FL_XS_06
              ↓
           JS_XS_03
```

**Minimum sequential steps:** 8 (if parallelized optimally)

**If running sequentially:** 22 tasks total
