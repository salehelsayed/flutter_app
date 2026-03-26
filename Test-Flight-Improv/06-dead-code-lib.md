# Dead Code Analysis: lib/ Directory

## Summary

The project is clean, but the earlier pass overstated removable code. Only a **small set of files** currently looks low-risk to remove immediately. Several earlier candidates are still referenced by tests or smoke flows, so they are **not** “safe to remove” as a quick cleanup batch.

---

## Category 1: Manual Test Entry Points (3 files)

These are not wired into production code, but they are manual `flutter run -t` entry points. Remove only if the team confirms nobody uses that workflow anymore.

| File | Confidence |
|------|-----------|
| `lib/smoke_test_main.dart` | Manual entry point, workflow-dependent |
| `lib/smoke_test_restore.dart` | Manual entry point, workflow-dependent |
| `lib/smoke_test_messages.dart` | Manual entry point, workflow-dependent |

---

## Category 2: Likely Orphaned Files (3 files)

These are the best current cleanup candidates.

| File | Kind | Notes |
|------|------|-------|
| `lib/features/groups/presentation/widgets/group_compose_area.dart` | Widget | Current group UI goes through the newer conversation screen/wired flow |
| `lib/features/groups/presentation/screens/create_group_wired.dart` | Screen | Current creation path is `create_group_with_members` + `create_group_picker_wired` |
| `lib/features/posts/application/post_pass_follow_on_support.dart` | Helper | No active callers found; newer post follow-on flow covers delivery |

---

## Category 3: Production-Unused But Test-Backed (examples — not quick-pass safe)

| File | Why It Is Not Safe To Remove Quickly |
|------|--------------------------------------|
| `lib/features/feed/presentation/widgets/expanded_compose_input.dart` | Exercised by `integration_test/bidi_text_smoke_test.dart` |
| `lib/features/groups/presentation/screens/group_list_wired.dart` | Used by `integration_test/loading_states_smoke_test.dart` |
| `lib/features/posts/presentation/screens/posts_wired.dart` | Used by `test/features/posts/phase1/posts_wired_test.dart` |
| `lib/features/conversation/presentation/widgets/reaction_display.dart` | Used by `test/features/conversation/presentation/widgets/reaction_display_test.dart` |
| `lib/features/qr_code/application/handle_scanned_qr_use_case.dart` | Unit-tested and still part of the QR test surface even if current live flow centers on `qr_scanner_wired.dart` |

---

## Category 4: Files Requiring Product / Workflow Confirmation

| File | Why Confirmation Matters |
|------|--------------------------|
| `lib/smoke_test_main.dart` | Manual smoke workflow may still be used outside CI |
| `lib/smoke_test_restore.dart` | Manual recovery-path validation may still be useful |
| `lib/smoke_test_messages.dart` | Manual DB-layer smoke may still be part of ad hoc debugging |

---

## Verified NOT Dead

- `posts_wired.dart`, `group_list_wired.dart`, `reaction_display.dart`, and `expanded_compose_input.dart` are still used by tests/smokes
- Current QR behavior flows through `qr_scanner_wired.dart`; do not remove QR-related code casually without product intent review
- Bridge code, l10n output, and generated files are still active

---

## Removal Priority

| Priority | Category | Files | Risk |
|----------|----------|-------|------|
| **1** | Likely orphaned files | 3 | Low |
| **2** | Manual smoke entry points | 3 | Workflow-dependent |
| **3** | Test-backed candidates from earlier report | Many | Medium/High |

**Total removable now:** ~3 files with good confidence, plus 3 manual entry points only after workflow confirmation.
