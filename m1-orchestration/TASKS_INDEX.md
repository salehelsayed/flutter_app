# M1 Tasks Index

All tasks for M1 Identity Initialization milestone.

---

## Database Layer (DB)

| ID | Title | File |
|----|-------|------|
| DB_XS_01 | Identity Table Migration | `tasks/DB_XS_01.md` |
| DB_XS_02 | Load Identity Row | `tasks/DB_XS_02.md` |
| DB_XS_03 | Upsert Identity Row | `tasks/DB_XS_03.md` |

---

## JavaScript Core-Lib (JS)

| ID | Title | File |
|----|-------|------|
| JS_XS_01 | IdentityJson Type Definition | `tasks/JS_XS_01.md` |
| JS_XS_02 | generateIdentity() Implementation | `tasks/JS_XS_02.md` |
| JS_XS_03 | restoreIdentityFromMnemonic() | `tasks/JS_XS_03.md` |
| JS_XS_04 | Bridge Handlers | `tasks/JS_XS_04.md` |

---

## Flutter Layer (FL)

### Domain (Models & Repository)

| ID | Title | File |
|----|-------|------|
| FL_XS_01 | IdentityModel with JSON Mapping | `tasks/FL_XS_01.md` |
| FL_XS_02 | IdentityRepository Interface | `tasks/FL_XS_02.md` |
| FL_XS_03 | IdentityRepositoryImpl.loadIdentity() | `tasks/FL_XS_03.md` |
| FL_XS_04 | IdentityRepositoryImpl.saveIdentity() | `tasks/FL_XS_04.md` |

### Application (Use Cases)

| ID | Title | File |
|----|-------|------|
| FL_XS_05 | StartupDecision and decideStartupRoute() | `tasks/FL_XS_05.md` |
| FL_XS_06 | generateNewIdentity() Use Case | `tasks/FL_XS_06.md` |
| FL_XS_07 | restoreIdentityFromMnemonic() Use Case | `tasks/FL_XS_07.md` |

### Bridge

| ID | Title | File |
|----|-------|------|
| FL_XS_08 | callJsIdentityGenerate() Bridge Client | `tasks/FL_XS_08.md` |
| FL_XS_09 | callJsIdentityRestore() Bridge Client | `tasks/FL_XS_09.md` |
| FL_XS_16 | Implement Real JS Bridge Connection (WebView) | `tasks/FL_XS_16.md` |

### Presentation (UI)

| ID | Title | File |
|----|-------|------|
| FL_XS_10 | IdentityChoiceScreen Layout | `tasks/FL_XS_10.md` |
| FL_XS_11 | Wire "I'm new here" Button | `tasks/FL_XS_11.md` |
| FL_XS_12 | Wire "Load my key" Button | `tasks/FL_XS_12.md` |
| FL_XS_13 | MnemonicInputScreen Layout | `tasks/FL_XS_13.md` |
| FL_XS_14 | Wire MnemonicInputScreen | `tasks/FL_XS_14.md` |
| FL_XS_15 | Startup Routing | `tasks/FL_XS_15.md` |

---

## QA Verification (QA)

| ID | Title | File |
|----|-------|------|
| QA_XS_01 | Manual Test Script: New Identity Path | `tasks/QA_XS_01.md` |
| QA_XS_02 | Manual Test Script: Restore Path | `tasks/QA_XS_02.md` |
| QA_XS_03 | Manual Test Script: Relaunch with Existing Identity | `tasks/QA_XS_03.md` |

---

## Summary

| Layer | Count |
|-------|-------|
| Database (DB) | 3 |
| JavaScript (JS) | 4 |
| Flutter (FL) | 16 |
| QA | 3 |
| **Total** | **26** |
