# Dead Code Analysis: lib/ Directory

## Summary

This file is an early triage aid, not the current deletion authority. The
decision-controlled status lives in
`dead-code-and-technical-debt-removal-roadmap.md`. In particular, DTR-11
resolved the final 11 test/integration-only app leaves: ten were retired and
the push-preview release calculator was moved unchanged out of `lib/` to
`tool/telemetry/`.

---

## Category 1: Manual Test Entry Points (3 files)

These are not wired into production code, but they are manual `flutter run -t` entry points. Remove only if the team confirms nobody uses that workflow anymore.

| File | Confidence |
|------|-----------|
| `lib/smoke_test_main.dart` | Manual entry point, workflow-dependent |
| `lib/smoke_test_restore.dart` | Manual entry point, workflow-dependent |
| `lib/smoke_test_messages.dart` | Manual entry point, workflow-dependent |

---

## Category 2: Likely Orphaned Files (2 files)

These are the best current cleanup candidates.

| File | Kind | Notes |
|------|------|-------|
| `lib/features/groups/presentation/widgets/group_compose_area.dart` | Widget | Current group UI goes through the newer conversation screen/wired flow |
| `lib/features/posts/application/post_pass_follow_on_support.dart` | Helper | No active callers found; newer post follow-on flow covers delivery |

---

## Category 3: Production-Unused But Test-Backed (historical examples)

| File | Current disposition |
|------|---------------------|
| `lib/features/feed/presentation/widgets/expanded_compose_input.dart` | Exercised by `integration_test/bidi_text_smoke_test.dart` |
| `lib/features/posts/presentation/screens/posts_wired.dart` | Used by `test/features/posts/phase1/posts_wired_test.dart` |
| `lib/features/conversation/presentation/widgets/reaction_display.dart` | Retired by DTR-11; live reaction behavior and proof belong to `LetterCard` |
| `lib/features/qr_code/application/handle_scanned_qr_use_case.dart` | Retired by DTR-11 after encrypted-request/profile-failure proof moved to `qr_scanner_wired_test.dart` |

The remaining DTR-11 leaves were also dispositioned atomically under
`DTR11-AUTH-01`: the pending-request badge, duplicate Feed projection,
automatic secure-store recovery wrapper, duplicate Intros tab, three thin P2P
wrappers, and stale QR payload model were retired; the telemetry calculator
was relocated to tooling. None remains an unexplained runtime root.

---

## Category 4: Files Requiring Product / Workflow Confirmation

| File | Why Confirmation Matters |
|------|--------------------------|
| `lib/smoke_test_main.dart` | Manual smoke workflow may still be used outside CI |
| `lib/smoke_test_restore.dart` | Manual recovery-path validation may still be useful |
| `lib/smoke_test_messages.dart` | Manual DB-layer smoke may still be part of ad hoc debugging |

---

## Verified NOT Dead

- `posts_wired.dart` and `expanded_compose_input.dart` are still used by
  tests/smokes.
- Current QR behavior flows through `qr_scanner_wired.dart`, canonical
  `buildQRPayload`, and canonical `parseQRPayload`; those live paths are not
  dead-code candidates.
- Bridge code, l10n output, and generated files are still active

---

## Removal Priority

| Priority | Category | Files | Risk |
|----------|----------|-------|------|
| **1** | Likely orphaned files | 3 | Low |
| **2** | Manual smoke entry points | 3 | Workflow-dependent |
| **3** | Test-backed candidates from earlier report | Many | Medium/High |

These figures are historical triage estimates. Use the current DTR roadmap and
an owner-approved plan for any further removal.
