# MIG-011 Plan: User Journey, Progress UI, Wake Lock, and Migrated-Out UX

Status: closed (MIG-011 host/UI scope only; overall Move Account still open; MIG-006 deferred-last remains evidence-gated)

## Planning Progress

- 2026-06-07 22:44 CEST - Arbiter completed. Files inspected since last update: reviewer findings, mandatory sections, simulator-gate rules, and user override. Decision/blocker: execution-ready for MIG-011 host-side UI/coordinator scope; no structural blocker remains. Next action: execute MIG-011 from this doc-scoped plan without running MIG-006 group simulator/release evidence.
- 2026-06-07 22:42 CEST - Reviewer completed. Files inspected since last update: completed draft, source proposal simulator scenarios, breakdown MIG-011 row, lower-level migration APIs, and named gate contract. Decision/blocker: reviewer pass after requiring explicit accepted differences for physical iOS permission/local-network proof and final paired-device acceptance. Next action: Arbiter classifies the plan.
- 2026-06-07 22:40 CEST - Planner completed. Files inspected since last update: identity choice, startup router, migrated-out screen, settings screen/wired, QR display/scanner screens, wake-lock controller, migration QR/authorization APIs, and direct test patterns. Decision/blocker: draft narrows MIG-011 to UI entry points, progress/wake-lock coordinator, migration QR/confirmation presentation, cancellation/failure states, and migrated-out erase UX; no exporter/importer or MIG-006 evidence expansion. Next action: Reviewer checks sufficiency and gates.
- 2026-06-07 22:36 CEST - Evidence Collector completed. Files inspected since last update: `identity_choice_screen.dart`, `identity_choice_wired.dart`, `startup_router.dart`, `account_migration_blocked_screen.dart`, `settings_screen.dart`, `settings_wired.dart`, QR display/scanner screens, `upload_wake_lock.dart`, migration QR/authorization APIs, l10n ARBs/generated files, and existing widget/direct tests. Decision/blocker: current code has lower-level migration APIs and a blocked screen stub, but lacks the `Move from old phone` onboarding choice, old-phone settings entry, journey/progress UI, foreground wake-lock integration, and erase action. Next action: draft narrow implementation plan.
- 2026-06-07 22:29 CEST - Evidence Collector started. Files inspected since last update: MIG-010 closure artifacts, session breakdown MIG-011 row, source proposal journey/progress/wake-lock/migrated-out requirements, noisy graphify query, and initial UI/wake-lock grep. Decision/blocker: plan artifact was absent and must be created before implementation; MIG-006 remains deliberately deferred-last/evidence-gated, not failed and not closed. Next action: inspect identity onboarding, settings navigation, QR screen/wired seams, wake-lock controller, account-migration lower-level APIs, and existing widget/direct tests.

## Execution Progress

- 2026-06-07 23:32 CEST - Final QA re-review accepted the MIG-011 fix pass with no blockers or non-blocking findings. Resolved checks: migration scanner copy is Move Account-specific, contact scanner defaults remain intact, Settings copy matches old-phone scanning, and docs/inventory/gates close only MIG-011 host/UI scope. QA-cited verification: focused scanner/settings/MIG-011 subset passed (`+42`), completeness-check passed (`805/805`), and `git diff --check` was clean. No MIG-006 simulator or release-evidence commands were run. Next program boundary: MIG-006 remains the final deferred group-evidence gate, and MIG-012/final acceptance must stay open until MIG-006 evidence and final device acceptance are complete.
- 2026-06-07 23:31 CEST - Current phase: MIG-011 fix-pass implementation, docs, and required verification are complete; final handoff in progress. Exact files touched by this fix pass: `lib/features/qr_code/presentation/screens/qr_scanner_screen.dart`; `lib/features/account_migration/presentation/screens/account_migration_journey_wired.dart`; `lib/l10n/app_en.arb`; `lib/l10n/app_de.arb`; `lib/l10n/app_ar.arb`; generated `lib/l10n/app_localizations.dart`; generated `lib/l10n/app_localizations_en.dart`; generated `lib/l10n/app_localizations_de.dart`; generated `lib/l10n/app_localizations_ar.dart`; `test/features/account_migration/presentation/account_migration_journey_screen_test.dart`; `test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart`; `test/features/settings/presentation/screens/settings_screen_test.dart`; `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`; `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md`; this plan; `Test-Flight-Improv/codebase-test-inventory.md`; `Test-Flight-Improv/test-gate-definitions.md`; graph refresh outputs under `graphify-out/`. Commands/results: `flutter gen-l10n` initially failed on ICU braces in the new ARB placeholder, then passed after the placeholder was changed; `dart format ...` passed; focused scanner/settings copy tests passed (`+27`); direct MIG-011 bundle passed (`+63`); affected QR/startup regression bundle passed (`+22`); targeted `flutter analyze ...` passed with no issues; `./scripts/run_test_gates.sh completeness-check` passed (`805/805 test files classified`); `git diff --check` passed, including the final rerun after docs/graph refresh; repeated `graphify update .` refreshes passed after the expected version-skew warning, with the latest rebuilds staying at `93056` nodes / `163716` edges. Blockers: none for MIG-011 host/UI scope. Next action: hand off MIG-011 fix pass for review or proceed to MIG-012/final device acceptance under a separate plan; MIG-006 remains deliberately deferred-last and no MIG-006 group simulator/release-evidence commands were run.
- 2026-06-07 23:18 CEST - Final graph refresh passed. Command/result: `graphify update .` exited 0 after the existing version-skew warning (`skill 0.8.32`, package `0.8.33`), backed up curated graph files, skipped HTML viz due to graph size, and rebuilt `93056` nodes / `163716` edges / `4094` communities on the post-ledger refresh. Decision/blocker: no blocker.
- 2026-06-07 23:16 CEST - Fix-pass Executor completed the QA blocker fixes for MIG-011 host/UI scope. Code/doc changes: `QRScannerScreen` now accepts optional copy while preserving contact defaults; `AccountMigrationJourneyWired.oldPhone` passes migration-specific scan/paste copy; Settings move-account copy now says the old phone scans the migration QR shown on the new phone; source proposal, session breakdown, inventory, gate definitions, and this plan now record MIG-011 session-scope closure only. Commands/results passed: `flutter gen-l10n` (first run exposed ICU braces in the new ARB placeholder; placeholder corrected and rerun passed), focused scanner/settings copy tests passed (`+27`), direct MIG-011 bundle passed (`+63`), affected QR/startup regression bundle passed (`+22`), targeted `flutter analyze ...` passed with no issues, `./scripts/run_test_gates.sh completeness-check` passed (`805/805 test files classified`), and `git diff --check` passed. Decision/blocker: no remaining MIG-011 host/UI blocker; graph refresh remains the final required post-edit command. MIG-006 remains deliberately deferred-last and no MIG-006 group simulator/release-evidence commands were run.
- 2026-06-07 23:02 CEST - QA Reviewer completed and blocked MIG-011 closure on three fixable issues: old-phone migration scan route used generic contact scanner copy; Settings move-account description said to show a QR even though the route opens old-phone scan; closure docs/inventory still marked MIG-011 pending and account_migration test count as 32. Decision/blocker: spawn fresh fix-pass Executor for scanner copy parameterization/test, settings copy+l10n regeneration, MIG-011-only closure docs/inventory/gate classification, and focused reruns. MIG-006 group simulator/release evidence remains out of scope and must not be run.
- 2026-06-07 22:47 CEST - Controller extracted MIG-011 execution contract from this plan. Scope: account-migration UI/coordinator, first-launch move choice, settings move entry, progress/wake-lock, and migrated-out erase UX. Required first tests: identity choice screen/wired, account-migration journey/blocked presentation tests, settings screen/wired, wake-lock test. Required gates: targeted analyzer, baseline, completeness-check, `git diff --check`; affected QR/startup direct tests if shared routes are touched. Decision/blocker: ready to spawn Executor with explicit request `model: gpt-5.5`, `reasoning_effort: xhigh`; do not run MIG-006 group simulator/release evidence.
- 2026-06-07 22:32 CEST - Executor started. Read this plan, graphify skill guidance, Flutter feature/test skill guidance, and scoped source/tests for identity choice, settings, startup router, account-migration QR/authorization, wake lock, secure-storage cleanup, and migrated-out blocked screen. Observed a pre-existing dirty worktree with prior Move Account/MIG work, including untracked account-migration modules and plan files; proceeding additively without reverting unrelated changes. Decision/blocker: no blocker; MIG-006 simulator/release-evidence commands remain explicitly out of scope and will not be run.
- 2026-06-07 22:49 CEST - Progress update requested mid-execution. Current phase: post-implementation verification, with implementation and focused fixes complete. Files touched for MIG-011 so far: this plan; `lib/features/account_migration/presentation/models/account_migration_ui_state.dart`; `lib/features/account_migration/presentation/screens/account_migration_journey_screen.dart`; `lib/features/account_migration/presentation/screens/account_migration_journey_wired.dart`; `lib/features/account_migration/presentation/screens/account_migration_blocked_screen.dart`; `lib/features/identity/presentation/screens/identity_choice_screen.dart`; `lib/features/identity/presentation/screens/identity_choice_wired.dart`; `lib/features/identity/presentation/startup_router.dart`; `lib/features/settings/presentation/screens/settings_screen.dart`; `lib/features/settings/presentation/screens/settings_wired.dart`; `lib/features/settings/presentation/widgets/settings_move_account_card.dart`; `lib/l10n/app_en.arb`; `lib/l10n/app_de.arb`; `lib/l10n/app_ar.arb`; generated `lib/l10n/app_localizations*.dart`; `test/features/account_migration/presentation/account_migration_journey_screen_test.dart`; `test/features/account_migration/presentation/account_migration_blocked_screen_test.dart`; `test/features/identity/presentation/screens/identity_choice_screen_test.dart`; `test/features/identity/presentation/screens/identity_choice_wired_test.dart`; `test/features/settings/presentation/screens/settings_screen_test.dart`; `test/features/settings/presentation/screens/settings_wired_test.dart`. Current command/log: no command running; last command was `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`, exit 0, with existing macOS linker/deployment warnings and `Failed to foreground app; open returned 1`, followed by passing macOS smoke/integration segments. Completed commands/results: `flutter gen-l10n` passed; `dart format ...` passed; direct MIG-011 bundle initially exposed compile/test issues, then passed; affected QR/startup regressions passed; targeted analyzer initially reported infos/one stale fake warning, fixes applied, rerun passed with no issues; direct MIG-011 bundle rerun passed; Baseline Gate passed. Blockers: none. Next action: run `./scripts/run_test_gates.sh completeness-check`, then `git diff --check`, then update this plan with final command results; do not run MIG-006 group simulator/release evidence.
- 2026-06-07 22:53 CEST - Executor final verification ledger. Current phase: MIG-011 host-side implementation and verification complete for this plan's scope; handoff preparation only. Files touched for MIG-011: this plan; `lib/features/account_migration/presentation/models/account_migration_ui_state.dart`; `lib/features/account_migration/presentation/screens/account_migration_journey_screen.dart`; `lib/features/account_migration/presentation/screens/account_migration_journey_wired.dart`; `lib/features/account_migration/presentation/screens/account_migration_blocked_screen.dart`; `lib/features/identity/presentation/screens/identity_choice_screen.dart`; `lib/features/identity/presentation/screens/identity_choice_wired.dart`; `lib/features/identity/presentation/startup_router.dart`; `lib/features/settings/presentation/screens/settings_screen.dart`; `lib/features/settings/presentation/screens/settings_wired.dart`; `lib/features/settings/presentation/widgets/settings_move_account_card.dart`; `lib/l10n/app_en.arb`; `lib/l10n/app_de.arb`; `lib/l10n/app_ar.arb`; generated `lib/l10n/app_localizations*.dart`; `test/features/account_migration/presentation/account_migration_journey_screen_test.dart`; `test/features/account_migration/presentation/account_migration_blocked_screen_test.dart`; `test/features/identity/presentation/screens/identity_choice_screen_test.dart`; `test/features/identity/presentation/screens/identity_choice_wired_test.dart`; `test/features/settings/presentation/screens/settings_screen_test.dart`; `test/features/settings/presentation/screens/settings_wired_test.dart`; `graphify-out/graph.json`; `graphify-out/GRAPH_REPORT.md`. Current command/log: no command running. Completed commands/results: `flutter gen-l10n` passed; `dart format` on touched Dart files passed; direct MIG-011 test bundle passed after implementation fixes (`All tests passed!`, 62 tests); affected QR/startup regression bundle passed (`All tests passed!`, 21 tests); targeted `flutter analyze` passed (`No issues found!`); `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed, with existing macOS linker/deployment warnings and `Failed to foreground app; open returned 1` during macOS foregrounding; `./scripts/run_test_gates.sh completeness-check` passed (`805/805 test files classified`); `git diff --check` passed; `graphify update .` passed after a graphify version-skew warning (`skill 0.8.32`, package `0.8.33`) and rebuilt `92960` nodes / `163613` edges / `4054` communities. Blockers: none for MIG-011 host-side scope. Accepted differences: no full exporter/importer, no physical paired iOS acceptance, no multi-device sync, no final overall Move Account closure claim, and no MIG-006 group simulator/release-evidence commands run; MIG-006 remains deliberately deferred-last. Next action: hand off MIG-011 for review or proceed to later-session acceptance only under a separate plan.

## real scope

MIG-011 owns the host-side user journey and UI/coordinator surface for the Move Account MVP:

- add `Move from old phone` as a third first-launch choice, separate from `I'm new here` and recovery-word restore
- add an old-phone `Move account to new phone` entry from Settings
- add account-migration presentation screens/wired widgets for new-phone QR display, old-phone scan/confirmation, progress stages, retryable failure/cancellation, and migrated-out state
- use the existing migration QR build/parse/authorization APIs instead of contact QR semantics
- hold `UploadWakeLockController` while a migration transfer/progress screen is actively foregrounded and release it on completion, cancellation, failure, dispose, or route replacement
- update the migrated-out old-phone screen to show only blocked-state UX with an erase action
- keep existing onboarding, mnemonic restore, contact QR, settings, and startup behavior intact

This session should introduce only the UI/coordinator layer needed to drive existing lower-level migration seams. It should not implement a new transfer protocol, a full bundle exporter/importer, real iOS permission plumbing, group release evidence, or final paired-device acceptance.

## closure bar

MIG-011 closes when host/widget tests prove the user-visible journey contract below:

| requirement | required proof |
|---|---|
| first launch shows all three choices | identity choice widget test finds `I'm new here`, `Move from old phone`, and restore/recovery wording; new and restore callbacks remain distinct |
| choosing `Move from old phone` does not create/restore identity | `IdentityChoiceWired` test verifies navigation to the migration flow without calling identity generation, restore, ML-KEM identity recovery, or P2P startup |
| new-phone pairing presents migration QR state | account-migration presentation/wired test verifies QR build success, loading, keygen/persistence failure, expiry copy, and no QR secret/private material in UI/debug text |
| old-phone Settings entry exists | settings widget/wired tests verify the action appears for active accounts and navigates to the migration old-phone flow |
| old-phone scan/confirmation stays migration-specific | old-phone flow test feeds migration QR, verifies parse/authorization result handling, confirmation code display from authenticated transcript data, and contact QR rejection without contact side effects |
| progress UI has the proposal stages | migration progress widget test verifies preparing, connecting, encrypting, transferring database/media, checking, finishing, cancelled, and failed states render stable, non-overlapping copy |
| wake lock is foreground-scoped | controller/widget test uses `UploadWakeLockController.debugSetDriver` to prove active progress acquires exactly one hold and releases on success, cancellation, failure, and dispose |
| migrated-out screen blocks normal account UI | startup router test still proves migrated-out/import-staging authority routes to `AccountMigrationBlockedScreen`, not onboarding/feed/P2P |
| erase action is explicit | blocked-screen/wired test verifies erase action requires a deliberate tap/confirmation and calls the existing registry-driven cleanup/authority-clear callback rather than silently erasing |
| existing non-migration flows survive | direct identity/settings/QR tests and Baseline Gate stay green |

## source of truth

- Product source: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`
- Reusable breakdown: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md`
- Active lower-level prerequisites: MIG-001, MIG-002, MIG-003, MIG-007, MIG-008, MIG-009, and MIG-010 plan/closure artifacts
- Named gates: `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`
- Current code wins over stale prose. `test-gate-definitions.md` wins for named gate membership.

## session classification

Implementation-ready for host-side presentation, coordinator, and widget coverage.

Simulator/device proof remains intentionally later-session acceptance. MIG-006 group simulator/release evidence remains deliberately deferred-last by user override and is not part of MIG-011.

## exact problem statement

The app has the migration primitives needed by earlier sessions, but users still cannot start or understand the account move journey. First launch still offers only new identity and mnemonic restore. Settings has no old-phone move entry. The existing migrated-out route is a generic blocked screen with no erase action. There is no migration progress surface that names the proposal stages or holds the wake lock while the user keeps the transfer screen foregrounded.

Without MIG-011, the backend seams remain unreachable or misleading from product UI, and final acceptance cannot prove the intended iOS user journey.

## files and repos to inspect next

Primary UI files:

- `lib/features/identity/presentation/screens/identity_choice_screen.dart`
- `lib/features/identity/presentation/screens/identity_choice_wired.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/settings/presentation/screens/settings_screen.dart`
- `lib/features/settings/presentation/screens/settings_wired.dart`
- `lib/features/account_migration/presentation/screens/account_migration_blocked_screen.dart`
- new account-migration presentation screens/wired widgets under `lib/features/account_migration/presentation/`
- `lib/core/device/upload_wake_lock.dart`

Lower-level APIs to wire, not redesign:

- `lib/features/account_migration/application/migration_qr_payload_use_case.dart`
- `lib/features/account_migration/application/migration_export_authorization.dart`
- `lib/features/account_migration/application/migration_pairing_session_repository_impl.dart`
- `lib/features/account_migration/application/migration_secure_storage_cleanup.dart`
- `lib/features/account_migration/application/migration_secure_storage_registry.dart`
- `lib/features/account_migration/application/account_migration_authority_repository_impl.dart`

Localization files if user-facing copy is localized:

- `lib/l10n/app_en.arb`
- `lib/l10n/app_de.arb`
- `lib/l10n/app_ar.arb`
- generated `lib/l10n/app_localizations*.dart`

## existing tests covering this area

- `test/features/identity/presentation/screens/identity_choice_screen_test.dart` covers the two existing onboarding choices, disabled-card behavior, and readability.
- `test/features/identity/presentation/screens/identity_choice_wired_test.dart` covers new-identity progress-route handoff and restore navigation.
- `test/features/identity/presentation/screens/startup_router_recovery_test.dart` proves migration authority can block onboarding/feed/P2P before normal startup.
- `test/features/settings/presentation/screens/settings_screen_test.dart` and `settings_wired_test.dart` cover existing settings cards and navigation shell behavior.
- `test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart` proves migration QR input is fenced from contact side effects in the shared scanner.
- `test/core/device/upload_wake_lock_test.dart` proves the wake-lock controller is ref-counted.
- MIG-002 direct tests cover migration QR build/parse/session consumption/authorization and contact QR rejection at the application layer.

Missing tests: no direct account-migration presentation tests, no first-launch move-choice test, no settings move-entry test, no migration progress/wake-lock integration test, and no migrated-out erase-action test.

## regression/tests to add first

Add or extend these tests before implementation:

- `test/features/identity/presentation/screens/identity_choice_screen_test.dart`: renders the third `Move from old phone` choice and keeps new/restore copy visible.
- `test/features/identity/presentation/screens/identity_choice_wired_test.dart`: tapping move choice pushes the migration flow and does not call identity generate/restore/ML-KEM keygen.
- `test/features/account_migration/presentation/account_migration_journey_screen_test.dart` or equivalent: new-phone QR loading/success/failure, old-phone scan/confirmation, progress/failure/cancel states, and no sensitive QR/session secret text.
- `test/features/settings/presentation/screens/settings_screen_test.dart`: renders `Move account to new phone` action when callback is supplied.
- `test/features/settings/presentation/screens/settings_wired_test.dart`: action navigates to the old-phone migration flow.
- `test/features/account_migration/presentation/account_migration_blocked_screen_test.dart`: migrated-out screen copy, no normal account UI affordance, explicit erase confirmation/callback.
- `test/core/device/upload_wake_lock_test.dart` or the new account-migration presentation test: active migration progress acquires/releases wake lock across success/cancel/failure/dispose.
- Existing QR scanner/contact tests if scanner route code changes.

## step-by-step implementation plan

1. Add a small account-migration UI state model for role, stage, QR payload state, confirmation code, error/cancel state, and whether the foreground progress wake lock should be held. Keep it presentation/application-local and serializable only if tests need it.
2. Add pure account-migration presentation widgets/screens for:
   - new-phone start/QR pairing
   - old-phone scan/confirmation
   - progress stages
   - failure/cancel/retry state
   - migrated-out blocked screen with erase action
3. Add wired widgets that call existing migration QR payload, parse, session repository, and authorization helpers. Use dependency injection so tests can provide fake builders/authorizers and avoid real camera/network dependencies.
4. Thread the third onboarding choice through `IdentityChoiceScreen` and `IdentityChoiceWired`, then route it from `StartupRouter` to the new-phone migration flow for `needsIdentity`.
5. Add a Settings action/card to `SettingsScreen` and wire `SettingsWired` to open the old-phone migration flow. Keep existing settings layout and nav behavior stable.
6. Integrate `UploadWakeLockController` only around the active migration progress screen. Use a guard so repeated rebuilds do not acquire multiple holds, and release in all terminal/dispose paths.
7. Expand `AccountMigrationBlockedScreen` into the final migrated-out UX with explicit erase action. Use existing registry cleanup/authority clear APIs through an injected callback; do not silently erase on screen load.
8. Add l10n keys for user-facing copy and regenerate localizations if this repo does not use checked-in generated files manually.
9. Run direct tests first; fix UI overflow/readability regressions before named gates.
10. Update source proposal, breakdown, test inventory/gate definitions only after tests pass.

## risks and edge cases

- Wake-lock leaks if progress widgets rebuild or dispose while async terminal callbacks are racing.
- The UI must not show a fake final success state before exporter/importer/device acceptance exists.
- Confirmation code must come from authenticated transcript data, not from QR fields alone.
- Old-phone scan flow must not route contact QR payloads into contact side effects when launched from migration.
- Erase action must be explicit and must not delete registry-owned secrets until the user confirms.
- Long localized strings can overflow compact buttons/cards; tests should cover at least English layout and avoid narrow fixed text boxes.

## exact tests and gates to run

Direct MIG-011 tests:

```sh
flutter test \
  test/features/identity/presentation/screens/identity_choice_screen_test.dart \
  test/features/identity/presentation/screens/identity_choice_wired_test.dart \
  test/features/account_migration/presentation/account_migration_journey_screen_test.dart \
  test/features/account_migration/presentation/account_migration_blocked_screen_test.dart \
  test/features/settings/presentation/screens/settings_screen_test.dart \
  test/features/settings/presentation/screens/settings_wired_test.dart \
  test/core/device/upload_wake_lock_test.dart
```

Affected QR/startup regressions if the implementation touches shared scanner/startup routes:

```sh
flutter test \
  test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart \
  test/features/qr_code/application/handle_scanned_qr_use_case_test.dart \
  test/features/identity/presentation/screens/startup_router_recovery_test.dart
```

Static checks and named gates:

```sh
flutter analyze \
  lib/features/account_migration/presentation \
  lib/features/identity/presentation/screens/identity_choice_screen.dart \
  lib/features/identity/presentation/screens/identity_choice_wired.dart \
  lib/features/settings/presentation/screens/settings_screen.dart \
  lib/features/settings/presentation/screens/settings_wired.dart \
  test/features/account_migration/presentation \
  test/features/identity/presentation/screens/identity_choice_screen_test.dart \
  test/features/identity/presentation/screens/identity_choice_wired_test.dart \
  test/features/settings/presentation/screens/settings_screen_test.dart \
  test/features/settings/presentation/screens/settings_wired_test.dart
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Do not run MIG-006 group simulator or group release-evidence commands during MIG-011.

## known-failure interpretation

- MIG-006 remains deliberately deferred-last/evidence-gated for commands 29-123 and final group verification. Missing MIG-006 group simulator/release evidence is not a MIG-011 failure and must not be marked closed by this session.
- If Baseline Gate fails only because multiple devices are attached and no `FLUTTER_DEVICE_ID` is set, rerun with `FLUTTER_DEVICE_ID=macos`.
- If QR scanner tests fail because migration route launches the shared scanner and triggers contact side effects, that is in scope and must be fixed.
- If a new account-migration presentation test is added, `completeness-check` must classify it before closure.

## done criteria

- First launch has three choices and the move path routes to migration pairing without starting identity generation or recovery.
- Settings exposes an old-phone move-account entry and routes to the migration old-phone flow.
- New-phone and old-phone migration screens cover QR/loading/error/confirmation/progress/failure/cancel states without sensitive material in visible text.
- Active progress acquires and releases the wake lock exactly once per active foreground flow.
- Migrated-out screen has explicit erase action and does not expose normal account UI or history.
- Existing onboarding, restore, settings, contact QR, startup-router, and baseline tests remain green.
- Source proposal, session breakdown, and this plan record MIG-011 closure for its own scope only; MIG-012 and deferred-last MIG-006 remain open.

## scope guard

Do not implement the full bundle exporter/importer.

Do not claim physical iOS-to-iOS migration success.

Do not add multi-device sync or sibling-device semantics.

Do not run or close MIG-006 group simulator/release evidence.

Do not replace existing contact QR parser/scanner behavior for normal contact flows.

Do not silently erase account state from the migrated-out screen; require an explicit user action and a clear callback/confirmation boundary.

## accepted differences / intentionally out of scope

- Host/widget tests prove UI states and callbacks; real camera permission, local-network permission, same-WiFi transfer behavior, iOS lock/call/background lifecycle, and physical paired-device acceptance remain MIG-012.
- MIG-011 can display and drive progress/failure/cancel states through a coordinator/fake adapter, but final success must still be proven by the real exporter/importer/cutover path in MIG-012.
- Wake lock keeps the screen awake while foregrounded; it is not treated as proof against iOS suspension or manual lock.
- Group/NSE release evidence remains MIG-006 deferred-last and must not be bundled into MIG-011.

## dependency impact

MIG-012 depends on MIG-011 for user-visible entry points, progress-state vocabulary, wake-lock behavior, migrated-out UX, and the old/new phone flow hooks used by final device acceptance.

If MIG-011 is revised or skipped, MIG-012 must not claim the full user journey, migrated-out old-phone UX, or wake-lock behavior is release-ready.

## closure progress

- Closed code: identity first-launch move choice, settings old-phone move entry, `QRScannerScreen` copy parameterization with preserved contact defaults, account-migration new/old-phone journey presentation and wired widgets, progress wake-lock wrapper, migrated-out erase UX, localized settings/scanner copy, and direct/widget tests.
- Covered behavior: first-launch three-choice contract; move choice navigation without identity generation/restore; settings route to old-phone migration; new-phone QR loading/success/failure; old-phone migration QR scan, parse, authorization, confirmation-code display, contact-QR rejection, and migration-specific scanner copy; progress-stage copy; wake-lock acquire/release; migrated-out screen and explicit erase confirmation.
- Evidence: `flutter gen-l10n` passed after correcting the ARB placeholder; focused scanner/settings copy tests `+27`; direct MIG-011 bundle `+63`; affected QR/startup regression bundle `+22`; targeted analyzer clean; completeness-check `805/805`; `git diff --check`; `graphify update .` rebuilt `93056` nodes / `163716` edges / `4094` communities.
- Accepted differences: this session proves host/widget UI and coordinator behavior only. Full bundle exporter/importer, real same-WiFi transfer, physical paired iOS-to-iOS success, camera/local-network/storage/version permission proof, iOS lock/call/background lifecycle proof, final migrated database/media/group/post/intro rendering, final program closure, and MIG-006 group release evidence remain out of scope.

## session verdict

MIG-011 is closed for its own host-side user journey, scanner/settings copy, progress wake-lock, and migrated-out UX scope only.

The overall Move Account document remains open. MIG-012 still owns final device acceptance, and MIG-006 remains deliberately deferred-last/evidence-gated with commands 29-123 and final group verification still required.
