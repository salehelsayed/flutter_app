# Decomposition artifact updated

- Artifact path: `Test-Flight-Improv/83-mirrored-cosmic-background-option-session-breakdown.md`
- Source doc path: `Test-Flight-Improv/83-mirrored-cosmic-background-option.md`
- Downstream workflow rule: detailed planning happens one session at a time. Later sessions must be refreshed against landed code, current tests, and current gate definitions before execution.
- Decomposition scope: this artifact belongs only to source doc `83`. It does not execute implementation, create session plans, or change product code.

# recommended plan count

Recommended plan count: 3

Doc `83` builds on the closed background-selection foundation from docs `80` through `82`. The smallest safe rollout is three sessions: add the third preference and Settings option, make the mirrored visual production-owned and renderable through the shared app background path, then run combined acceptance/performance/closure evidence. A separate propagation session is not recommended because `AppShellController`, `SettingsScreen`, and the app-wide `AmbientBackground.preference` path already exist; the new propagation risk is covered by the shared rendering and final inventory checks.

# decomposition artifact

- Artifact path: `Test-Flight-Improv/83-mirrored-cosmic-background-option-session-breakdown.md`
- Proposal or source doc path: `Test-Flight-Improv/83-mirrored-cosmic-background-option.md`
- Intended plan file pattern: `Test-Flight-Improv/83-mirrored-cosmic-background-option-session-<session-id>-plan.md`
- Downstream workflow rule: each session should next go through `$implementation-plan-orchestrator`, `$implementation-execution-qa-orchestrator`, and `$implementation-closure-audit-orchestrator`. Later sessions must be refreshed against landed code and tests before execution.

# overall closure bar

Doc `83` is complete when Settings exposes `Default`, existing `Cosmic`, and mirrored cosmic as distinguishable localized and accessible options; the mirrored preference has a stable storage value that loads, saves, overwrites, falls back safely for missing or unknown values, and survives Settings reopen; failed saves do not leave Settings or the app shell claiming a mirrored selection that was not saved; production app code owns the mirrored background under `lib/` rather than importing from `Test-Flight-Improv/`; `AmbientBackground` renders default, existing cosmic, and mirrored cosmic distinctly across the shared-background surfaces already wired by doc `82`; reduced-motion or disabled-animation mode keeps mirrored cosmic static, readable, and recognizable; representative Feed and non-Feed shared-background routes show the mirrored treatment behind content without blocking controls, navigation, overlays, or scroll; existing `Default` and `Cosmic` behavior stays recognizable; and final docs record exact direct, smoke, visual/performance, inventory, and any device-only evidence gaps.

# source of truth

Primary docs:

- `Test-Flight-Improv/83-mirrored-cosmic-background-option.md`
- `Test-Flight-Improv/82-app-wide-background-selection-session-breakdown.md`
- `Test-Flight-Improv/82-app-wide-background-selection-session-04-acceptance-performance-closure-plan.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/02-integration-test-coverage.md`

Current repo facts governing the split:

- `BackgroundPreference` currently contains `defaultBackground` and `cosmic`, serializes to `default` and `cosmic`, and falls back to default for null or unknown storage values.
- `BackgroundChoiceControl` currently renders only `Default` and `Cosmic`; its control-level selected label treats non-default as existing cosmic.
- English, German, and Arabic localization keys currently have no mirrored cosmic option labels, descriptions, or selected-state copy.
- `SettingsWired` already loads the saved background preference, publishes it through `AppShellController`, optimistically updates Settings state, persists successful changes, emits non-sensitive attempt/success/failure flow events, and rolls back on save failure.
- `SettingsScreen` already passes `currentBackgroundPreference` to `AmbientBackground`, so mirrored support can reuse the existing live Settings background path after the enum and renderer exist.
- `AppShellController` already stores the selected `BackgroundPreference` and notifies only on real changes.
- `AmbientBackground` currently switches between the default ambient treatment and production `CosmicBackground`; no production mirrored value or widget exists.
- `test/features/identity/presentation/widgets/ambient_background_test.dart` already covers default/cosmic shared rendering, disabled-animation cosmic behavior, production source ownership, and a static shared-background surface inventory.
- Existing Settings and preference tests cover two-option behavior only.
- `integration_test/settings_background_choice_smoke_test.dart` covers the current Default/Cosmic Settings-to-Feed smoke only.
- `Test-Flight-Improv/Background-Feature/cosmic_background_mirrored.dart` contains the provided mirrored artifact, but no production code or current test references `CosmicBackgroundMirrored`.

Disagreement rule:

- current code and tests beat stale prose
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` decide named gate membership
- source doc `83` remains the product intent source unless repo evidence proves a requirement stale or overclaimed

# session ledger

| Session id | Title | Classification | Intended plan file | Depends on | Current status |
|---|---|---|---|---|---|
| `01-settings-preference-option` | Mirrored preference storage plus Settings third option | `implementation-ready` | `Test-Flight-Improv/83-mirrored-cosmic-background-option-session-01-settings-preference-option-plan.md` | None | `accepted` |
| `02-production-mirrored-background` | Production mirrored visual and shared background rendering | `implementation-ready` | `Test-Flight-Improv/83-mirrored-cosmic-background-option-session-02-production-mirrored-background-plan.md` | `01-settings-preference-option` | `accepted` |
| `03-acceptance-performance-closure` | Mirrored option smoke, readability, performance, inventory, and docs closure | `acceptance-only` | `Test-Flight-Improv/83-mirrored-cosmic-background-option-session-03-acceptance-performance-closure-plan.md` | `01-settings-preference-option`, `02-production-mirrored-background` | `accepted` |

# ordered session breakdown

## Session 01: Mirrored preference storage plus Settings third option

- Session id: `01-settings-preference-option`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/83-mirrored-cosmic-background-option-session-01-settings-preference-option-plan.md`
- Exact scope:
  - add one permanent mirrored cosmic `BackgroundPreference` value with a stable storage string
  - preserve `default` and `cosmic` storage compatibility and null/unknown fallback to `defaultBackground`
  - update load/save/overwrite tests for the mirrored value
  - update `BackgroundChoiceControl` so `Default`, existing `Cosmic`, and mirrored cosmic render as three distinguishable options
  - fix selected-state logic so the control-level semantics value does not collapse all non-default selections into existing cosmic
  - add English, German, and Arabic mirrored option label, description, and selected-state copy
  - extend Settings picker tests for option visibility, tapping, selected icon/state, semantics, supported locales, and failed-save copy with the mirrored option
  - extend Settings wired/screen tests only where needed to prove save success, save failure rollback, telemetry, and live selected state for the mirrored enum
  - avoid production visual ownership work except for the minimum compile-safe handling required until Session `02`
- Why it is its own session:
  - storage, localization, semantics, telemetry, and failed-save honesty are the Settings preference seam and can be verified without choosing final painter details
  - this session leaves a meaningful verified state: the app can represent, persist, reload, and present the third option without corrupting existing `Default` or `Cosmic`
- Likely code-entry files:
  - `lib/features/settings/domain/models/background_preference.dart`
  - `lib/features/settings/application/background_preference_use_cases.dart`
  - `lib/features/settings/presentation/widgets/background_choice_control.dart`
  - `lib/features/settings/presentation/screens/settings_screen.dart`
  - `lib/features/settings/presentation/screens/settings_wired.dart`
  - `lib/features/feed/application/app_shell_controller.dart`
  - `lib/l10n/app_en.arb`
  - `lib/l10n/app_de.arb`
  - `lib/l10n/app_ar.arb`
  - generated localization output if this repo commits it
  - `test/features/settings/application/background_preference_use_cases_test.dart`
  - `test/features/settings/presentation/widgets/background_choice_control_test.dart`
  - `test/features/settings/presentation/screens/settings_screen_test.dart`
  - `test/features/settings/presentation/screens/settings_wired_test.dart`
  - `test/features/posts/phase1/app_shell_controller_test.dart`
- Likely direct tests/regressions:
  - `flutter test test/features/settings/application/background_preference_use_cases_test.dart`
  - `flutter test test/features/settings/presentation/widgets/background_choice_control_test.dart`
  - `flutter test test/features/settings/presentation/screens/settings_screen_test.dart`
  - `flutter test test/features/settings/presentation/screens/settings_wired_test.dart`
  - `flutter test test/features/posts/phase1/app_shell_controller_test.dart`
  - targeted assertions that default/cosmic storage values remain unchanged
  - targeted assertions that mirrored selection attempts, successful saves, save errors, and rollback use the mirrored storage identifier without sensitive telemetry
- Likely named gates:
  - none by default; this is feature-local Settings/domain/widget/wired coverage
  - run `./scripts/run_test_gates.sh completeness-check` only if gate definitions or classification docs are edited
- Matrix/closure docs to update when done:
  - this breakdown ledger and the session `01` plan/closure notes
  - `Test-Flight-Improv/02-integration-test-coverage.md` only if new durable Settings/background coverage is added and should be recorded before final closure
  - `Test-Flight-Improv/test-gate-definitions.md` only if new integration or cross-feature tests are added
- Dependency on earlier sessions: none.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Session 02: Production mirrored visual and shared background rendering

- Session id: `02-production-mirrored-background`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/83-mirrored-cosmic-background-option-session-02-production-mirrored-background-plan.md`
- Exact scope:
  - port or adapt `Test-Flight-Improv/Background-Feature/cosmic_background_mirrored.dart` into production source under `lib/` using the established production `CosmicBackground` patterns where possible
  - ensure runtime app behavior does not import mirrored widgets directly from `Test-Flight-Improv/`
  - integrate the mirrored preference into `AmbientBackground` so default, existing cosmic, and mirrored cosmic each map to the correct treatment
  - keep child layering, hit testing, and route content behavior unchanged
  - make mirrored cosmic visually distinguishable from existing cosmic through stable widget keys, painter configuration, or direct inspectable properties
  - preserve existing `CosmicBackground` behavior, reduced-motion behavior, and performance-minded painting structure
  - add disabled-animation or reduced-motion coverage for mirrored cosmic
  - keep the static shared-background inventory current so every doc `82` shared surface still uses the selected-background path
  - update direct Feed, Settings, and representative non-Feed widget tests only where they need to distinguish existing cosmic from mirrored cosmic
- Why it is its own session:
  - production visual ownership and shared rendering are a different seam from Settings storage/copy
  - this session leaves a meaningful verified state: any shared-background caller with the mirrored preference gets production mirrored cosmic, while `Default` and existing `Cosmic` remain intact
- Likely code-entry files:
  - `Test-Flight-Improv/Background-Feature/cosmic_background_mirrored.dart` as reference only
  - `lib/features/identity/presentation/widgets/cosmic_background.dart`
  - a new production mirrored background widget under `lib/features/identity/presentation/widgets/` if reuse is not clean
  - `lib/features/identity/presentation/widgets/ambient_background.dart`
  - `test/features/identity/presentation/widgets/ambient_background_test.dart`
  - direct tests for the new mirrored widget if created
  - `test/features/feed/presentation/screens/feed_screen_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  - `test/features/home/presentation/screens/first_time_experience_screen_test.dart`
  - `test/features/identity/presentation/screens/identity_choice_screen_test.dart`
  - `test/features/posts/phase1/posts_screen_test.dart`
- Likely direct tests/regressions:
  - `flutter test test/features/identity/presentation/widgets/ambient_background_test.dart`
  - focused mirrored-background widget tests if the production widget gets its own suite
  - `flutter test test/features/feed/presentation/screens/feed_screen_test.dart`
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "background preference"` if Feed rendering assertions are extended
  - representative non-Feed widget tests proving mirrored renders through the existing selected-background path
  - assertions that production code does not import `Test-Flight-Improv`
  - assertions that disabled animations render static mirrored cosmic without continuous animation builders/tickers where practical
  - assertions that existing cosmic still renders existing cosmic, not mirrored cosmic
- Likely named gates:
  - no named gate by default for shared-widget rendering only
  - `./scripts/run_test_gates.sh feed` if Feed route orchestration changes beyond accepting the existing background preference
  - `./scripts/run_test_gates.sh baseline` if startup, QR, or onboarding route wiring changes beyond existing selected-background propagation
  - run `./scripts/run_test_gates.sh completeness-check` only if gate definitions or classification docs are edited
- Matrix/closure docs to update when done:
  - this breakdown ledger and the session `02` plan/closure notes
  - `Test-Flight-Improv/02-integration-test-coverage.md` if durable app-wide background coverage changes materially before final closure
  - `Test-Flight-Improv/test-gate-definitions.md` only if new integration or cross-feature tests are added
- Dependency on earlier sessions: `01-settings-preference-option`.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Session 03: Mirrored option smoke, readability, performance, inventory, and docs closure

- Session id: `03-acceptance-performance-closure`
- Session classification: `acceptance-only`
- Intended plan file: `Test-Flight-Improv/83-mirrored-cosmic-background-option-session-03-acceptance-performance-closure-plan.md`
- Exact scope:
  - validate the combined mirrored option behavior after Sessions `01` and `02`
  - run or extend representative smoke coverage for Settings opening with three options, selecting mirrored cosmic, returning to Feed, reopening Settings with mirrored selected, switching to existing cosmic, switching to default, and restoring default
  - include at least one representative non-Feed shared-background surface in smoke, widget, or simulator evidence
  - validate that existing cosmic and mirrored cosmic remain visibly and programmatically distinguishable
  - validate reduced-motion or disabled-animation mirrored behavior after integration
  - validate readability behind Settings, Feed, and at least one content-heavy or non-Feed surface; use direct/widget evidence plus smoke where practical rather than one route test per surface
  - run Feed performance evidence with mirrored cosmic selected, or record an exact environment block if device/runtime support is missing
  - consider heavy Conversation or non-Feed chat performance only if the implementation changed more than the shared background layer or release confidence requires it
  - update source doc `83`, this breakdown ledger, `Test-Flight-Improv/02-integration-test-coverage.md`, and gate definitions only where final evidence requires it
  - record exact command and environment failure for simulator/device-only acceptance that cannot run locally
- Why it is its own session:
  - smoke, visual/readability, performance, static inventory, and documentation closure are meaningful only after both the Settings option and renderer are landed
  - this prevents acceptance evidence from being scattered across implementation sessions and overclaiming coverage before the combined feature exists
- Likely code-entry files:
  - `integration_test/settings_background_choice_smoke_test.dart`
  - `integration_test/feed_performance_test.dart`
  - representative non-Feed widget or smoke tests selected during planning
  - `test/features/identity/presentation/widgets/ambient_background_test.dart`
  - `test/features/settings/presentation/widgets/background_choice_control_test.dart`
  - `test/features/settings/presentation/screens/settings_wired_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  - `Test-Flight-Improv/83-mirrored-cosmic-background-option.md`
  - `Test-Flight-Improv/83-mirrored-cosmic-background-option-session-breakdown.md`
  - `Test-Flight-Improv/02-integration-test-coverage.md`
  - `Test-Flight-Improv/test-gate-definitions.md` only if new integration/cross-feature tests need classification
- Likely direct tests/regressions:
  - final direct batch from Sessions `01` and `02`
  - `flutter test integration_test/settings_background_choice_smoke_test.dart -d <device>` or the repo's established host/device fallback
  - `flutter test integration_test/feed_performance_test.dart -d <device>` or a documented performance fallback
  - representative non-Feed shared-background evidence for mirrored cosmic
  - static inventory proof that every current shared-background surface remains on the selected-background path
  - analyzer or narrowed analyzer pass if implementation touched generated l10n, shared widgets, or route constructors
- Likely named gates:
  - direct tests are primary
  - `./scripts/run_test_gates.sh baseline` if final smoke or implementation changed startup, QR, first-time, or app bootstrap wiring
  - `./scripts/run_test_gates.sh feed` if Feed route orchestration changed
  - `./scripts/run_test_gates.sh groups` or `./scripts/run_test_gates.sh posts` only if implementation unexpectedly touched group or posts behavior beyond background constructors
  - no `1to1` gate unless conversation send, retry, upload, listener, inbox, or handoff behavior changed
  - run `./scripts/run_test_gates.sh completeness-check` if gate definitions or classification docs are edited
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/83-mirrored-cosmic-background-option.md`
  - `Test-Flight-Improv/83-mirrored-cosmic-background-option-session-breakdown.md`
  - `Test-Flight-Improv/02-integration-test-coverage.md`
  - `Test-Flight-Improv/test-gate-definitions.md` only if new integration/cross-feature tests are added
- Dependency on earlier sessions: `01-settings-preference-option`, `02-production-mirrored-background`.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

# why this is not fewer sessions

Two sessions would force either Settings storage/localization/semantics work into production painter integration, or final smoke/performance/docs closure into implementation. That would hide two different risks: the third option must not corrupt existing preference storage or failed-save honesty, and the mirrored animated background must be production-owned, distinguishable, reduced-motion-safe, and readable across shared surfaces. Keeping acceptance separate also prevents the pipeline from closing the source doc before the combined feature is actually testable.

# why this is not more sessions

More sessions would mostly split one cohesive Settings option by individual test case, or split the mirrored painter from `AmbientBackground` even though the renderer must be reviewed with the central preference switch to avoid orphaned visuals. A separate app-wide propagation session would duplicate doc `82`'s already-landed state path; for doc `83`, propagation should be proven through shared rendering tests, representative surfaces, and final inventory rather than rewritten as a new architectural slice.

# regression and gate contract

`Test-Flight-Improv/14-regression-test-strategy.md` applies by using direct feature tests first and named gates only when the changed seam crosses a gate boundary. For doc `83`:

- Settings/domain/widget/wired tests are the primary regression family for mirrored storage, picker UI, localization, semantics, telemetry, and failed-save honesty.
- `AmbientBackground` and mirrored-background widget tests are the primary regression family for production ownership, default/cosmic preservation, mirrored rendering, reduced motion, and shared-surface inventory.
- Integration smoke and performance checks belong to the acceptance session after both implementation sessions land.
- Named gates are conditional. `baseline` applies if startup/first-route/QR/bootstrap wiring changes; `feed` applies if Feed route orchestration changes; `groups` and `posts` apply only if their behavior is touched beyond passing an existing background preference; `1to1` is not expected unless conversation send/retry/inbox behavior changes.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` remain the source of truth for gate membership. Edit gate definitions only when new integration/cross-feature tests need classification, and keep `./scripts/run_test_gates.sh completeness-check` green after such edits.

# matrix update contract

Use the existing stable coverage inventory rather than creating a new matrix doc.

- `Test-Flight-Improv/02-integration-test-coverage.md` should be updated by Session `03` if durable mirrored-background coverage is added or final evidence materially changes the app-wide background coverage inventory.
- `Test-Flight-Improv/83-mirrored-cosmic-background-option.md` should be updated by Session `03` with final completion evidence, explicit environment blocks, and any evidence-only follow-up.
- This breakdown ledger should be updated by each session's closure pass with status/evidence, then given a final verdict in Session `03`.
- `Test-Flight-Improv/test-gate-definitions.md` should only change if new integration/cross-feature tests are added and require classification.

# downstream execution path

For each session, execute the downstream workflow in order:

| Session id | Next planning | Then execution/QA | Then closure |
|---|---|---|---|
| `01-settings-preference-option` | `$implementation-plan-orchestrator` using `Test-Flight-Improv/83-mirrored-cosmic-background-option-session-01-settings-preference-option-plan.md` | `$implementation-execution-qa-orchestrator` | `$implementation-closure-audit-orchestrator` |
| `02-production-mirrored-background` | `$implementation-plan-orchestrator` using `Test-Flight-Improv/83-mirrored-cosmic-background-option-session-02-production-mirrored-background-plan.md` | `$implementation-execution-qa-orchestrator` | `$implementation-closure-audit-orchestrator` |
| `03-acceptance-performance-closure` | `$implementation-plan-orchestrator` using `Test-Flight-Improv/83-mirrored-cosmic-background-option-session-03-acceptance-performance-closure-plan.md` | `$implementation-execution-qa-orchestrator` | `$implementation-closure-audit-orchestrator` |

# session execution notes

## Session 01: accepted

- Plan artifact: `Test-Flight-Improv/83-mirrored-cosmic-background-option-session-01-settings-preference-option-plan.md`
- Result: added `BackgroundPreference.cosmicMirrored` with storage string `cosmic_mirrored`; added mirrored Settings copy in English, German, and Arabic; regenerated committed l10n output; rendered the third Settings option with distinct selected state and semantics; added a compile-safe `AmbientBackground` enum case for the new value pending the Session `02` production mirrored renderer.
- Verification: `flutter test test/features/settings/application/background_preference_use_cases_test.dart test/features/settings/presentation/widgets/background_choice_control_test.dart test/features/posts/phase1/app_shell_controller_test.dart` passed.
- Residual forwarded: Session `02` must replace the compile-safe renderer fallback with production-owned mirrored cosmic rendering; Session `03` still owns smoke, readability, performance, inventory, and final docs closure.

## Session 02: accepted

- Plan artifact: `Test-Flight-Improv/83-mirrored-cosmic-background-option-session-02-production-mirrored-background-plan.md`
- Result: added production-owned `CosmicBackgroundMirrored`; adapted the provided mirrored visual into the production cosmic lifecycle with deterministic stars, reduced-motion static mode, repaint boundaries, and stable root/painter keys; updated `AmbientBackground` to map `cosmicMirrored` to the mirrored widget while preserving existing `Default` and `Cosmic`.
- Verification: `flutter test test/features/identity/presentation/widgets/ambient_background_test.dart` passed.
- Representative route verification: `flutter test test/features/feed/presentation/screens/feed_screen_test.dart` passed.
- Residual forwarded: Session `03` still owns Settings-to-Feed smoke, non-Feed representative acceptance, readability/performance evidence, durable docs updates, and final doc verdict.

## Session 03: accepted

- Plan artifact: `Test-Flight-Improv/83-mirrored-cosmic-background-option-session-03-acceptance-performance-closure-plan.md`
- Result: extended Settings background smoke for mirrored selection, persistence, Feed rendering, existing-cosmic switch, and default restore; added representative non-Feed Conversation mirrored rendering coverage; added mirrored cosmic Feed performance coverage; updated source and coverage docs.
- Direct verification: `flutter test test/features/settings/application/background_preference_use_cases_test.dart test/features/settings/presentation/widgets/background_choice_control_test.dart test/features/posts/phase1/app_shell_controller_test.dart test/features/identity/presentation/widgets/ambient_background_test.dart test/features/feed/presentation/screens/feed_screen_test.dart test/features/conversation/presentation/screens/conversation_screen_test.dart` passed.
- Smoke verification: `flutter test integration_test/settings_background_choice_smoke_test.dart -d macos` passed. The macOS runner emitted `Failed to foreground app; open returned 1`, but the test completed green.
- Performance verification: `flutter test integration_test/feed_performance_test.dart -d macos` passed. Mirrored cosmic scroll Avg/P90/P99/Worst was `1.85/3.43/7.67/10.87ms` against same-run default baseline `2.00/3.30/7.23/7.45ms`.
- Residual-only follow-up: mobile-device and heavy Conversation-specific performance validation remains optional release-confidence evidence.

# final doc verdict

Verdict: `closed`

Doc `83` is closed because all three sessions are accepted, production code now owns and renders the mirrored cosmic background, Settings exposes and persists it as a third localized accessible option, existing `Default` and `Cosmic` behavior remains covered, representative non-Feed rendering is covered, updated macOS smoke verifies the full Settings-to-Feed switching journey, mirrored Feed performance passed against a same-run default baseline, and durable coverage/source docs record the exact evidence plus the optional mobile/heavy-conversation residual.

# reviewer questions

- Is the recommended session count sufficient, too coarse, or too fragmented? Sufficient: three sessions match the Settings preference seam, production rendering seam, and combined acceptance/closure seam.
- Which proposed sessions should merge? None. Settings storage/copy and production mirrored rendering have different direct tests and failure modes.
- Which proposed sessions must split? None. The Settings work should not be split by locale/semantics/telemetry, and the renderer should not be split from `AmbientBackground`.
- What tests or named gates are missing from the decomposition? No structural gaps. Direct Settings, preference, app-shell, `AmbientBackground`, representative surface, smoke, reduced-motion, visual/readability, and performance evidence are named; named gates are conditional on actual touched seams.
- Does each session end in a meaningful verified state? Yes. Session `01` represents and saves the option, Session `02` renders it through the shared background path, and Session `03` validates the combined user-visible rollout.
- Is the matrix-update responsibility assigned clearly? Yes. Session `03` owns durable coverage/source-doc closure; earlier sessions update this ledger and their plan closure notes only unless they add durable coverage that should be recorded immediately.
- What is the minimum session set that is still safe? Three sessions.

# structural blockers remaining

None.

# accepted differences intentionally left unchanged

- The exact user-facing mirrored option label remains open for the implementation plan, as allowed by the source doc, but must be distinguishable and localized.
- The exact mirrored storage identifier remains open until planning, but it must be stable, shipped, and not break fallback for unknown values.
- The exact preview treatment in Settings remains open; the required outcome is an accessible, clear, three-option picker and correct full-screen/shared background behavior after save.
- Identical star placement across app launches is not required, but production tests should use deterministic or inspectable hooks where needed to avoid flaky visual assertions.
- No per-screen background redesign, device sync, transport, messaging, posts, notification, group, media-quality, nearby-sharing, or identity behavior is included.

# exact docs/files used as evidence

- `Test-Flight-Improv/83-mirrored-cosmic-background-option.md`
- `Test-Flight-Improv/82-app-wide-background-selection-session-breakdown.md`
- `Test-Flight-Improv/82-app-wide-background-selection-session-04-acceptance-performance-closure-plan.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/02-integration-test-coverage.md`
- `Test-Flight-Improv/Background-Feature/cosmic_background_mirrored.dart`
- `lib/features/settings/domain/models/background_preference.dart`
- `lib/features/settings/presentation/widgets/background_choice_control.dart`
- `lib/features/settings/presentation/screens/settings_wired.dart`
- `lib/features/settings/presentation/screens/settings_screen.dart`
- `lib/features/feed/application/app_shell_controller.dart`
- `lib/features/identity/presentation/widgets/ambient_background.dart`
- `lib/features/identity/presentation/widgets/cosmic_background.dart`
- `lib/l10n/app_en.arb`
- `test/features/settings/application/background_preference_use_cases_test.dart`
- `test/features/settings/presentation/widgets/background_choice_control_test.dart`
- `test/features/identity/presentation/widgets/ambient_background_test.dart`
- `integration_test/settings_background_choice_smoke_test.dart`

# why the decomposition is safe to send into downstream planning/execution

The sessions follow the existing background rollout architecture instead of reopening it. Each intended plan path is doc-scoped to source doc `83`, each session has a distinct closure bar and direct regression family, and the final acceptance session owns durable docs and evidence. The split also preserves the key guardrails from the source doc: production code must not import `Test-Flight-Improv`, existing `Default` and `Cosmic` behavior must remain intact, missing and unknown values still fall back to default, and shared-background acceptance can use central widget coverage plus representative route evidence instead of one smoke test per surface.
