# Decomposition artifact updated

- Artifact path: `Test-Flight-Improv/86-daylight-lagoon-background-option-session-breakdown.md`
- Source doc path: `Test-Flight-Improv/86-daylight-lagoon-background-option.md`
- Downstream workflow rule: detailed planning happens one session at a time. Later sessions must be refreshed against landed code, current tests, and current gate definitions before execution.
- Decomposition scope: this artifact belongs only to source doc `86`. It does not execute implementation, create session plans, or change unrelated rollout docs.

# recommended plan count

Recommended plan count: 3

Doc `86` builds on the app-wide background selection work from docs `82` and `83`, and on the readable foreground contract from doc `84`. The smallest safe rollout is three sessions: first land the Daylight Lagoon option as a vertical production slice so Settings, persistence, the production renderer, readable-tone resolution, and direct widget/unit evidence stay synchronized; then harden and prove representative light-background shared surfaces and transient UI using the real production preference; then run combined integration, performance, inventory, and docs closure evidence.

Splitting the preference picker away from the renderer is not recommended for this doc because it would create a misleading half-state: users could select a light background preference before the app can render the light visual and foreground treatment together.

# decomposition artifact

- Artifact path: `Test-Flight-Improv/86-daylight-lagoon-background-option-session-breakdown.md`
- Proposal or source doc path: `Test-Flight-Improv/86-daylight-lagoon-background-option.md`
- Intended plan file pattern: `Test-Flight-Improv/86-daylight-lagoon-background-option-session-<session-id>-plan.md`
- Downstream workflow rule: each session should next go through `$implementation-plan-orchestrator`, `$implementation-execution-qa-orchestrator`, and `$implementation-closure-audit-orchestrator`. Later sessions must be refreshed against landed code, tests, and any newly classified light-background inventory before execution.

# overall closure bar

Doc `86` is complete when Settings exposes `Default`, `Cosmic`, `Mirrored cosmic`, and `Daylight Lagoon` as distinguishable localized and accessible options; Daylight Lagoon has a stable storage value that saves, reloads, overwrites, falls back safely for missing or unknown stored values, and remains selected after Settings reopen; production code owns the Daylight Lagoon renderer under `lib/` and does not import from `Test-Flight-Improv`; `AmbientBackground` renders Daylight Lagoon through the same app-wide selected-background path used by existing options; Daylight Lagoon resolves to light-background readable colors and dark system chrome icons while existing dark backgrounds continue to resolve to the dark readable profile; failed saves, rapid switching, and Settings-to-Feed navigation never leave the selected visual, readable foreground treatment, selected-state copy, or system chrome out of sync; representative Settings, Feed, Conversation, and at least one Group or Orbit surface remain readable under the real Daylight Lagoon preference; representative dialogs, sheets, overlays, pickers, loading states, disabled states, inputs, borders, and meaningful icons meet the doc `84` contrast targets or are explicitly classified as background-independent; Feed performance stays inside the source doc's frame budgets or records an exact environment block; and final docs record the direct, integration, performance, inventory, and any simulator/device-only evidence gaps without reopening unrelated background docs.

# source of truth

Primary docs:

- `Test-Flight-Improv/86-daylight-lagoon-background-option.md`
- `Test-Flight-Improv/82-app-wide-background-selection-session-breakdown.md`
- `Test-Flight-Improv/83-mirrored-cosmic-background-option-session-breakdown.md`
- `Test-Flight-Improv/84-background-readable-theme-extension-session-breakdown.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/02-integration-test-coverage.md`

Current repo facts governing the split:

- `Test-Flight-Improv/Background-Feature/daylight_lagoon_background.dart` contains the Daylight Lagoon artifact, with a white base, violet/teal/pink drifting blooms, an `18s` drift loop, and no starfield.
- `BackgroundPreference` currently contains `defaultBackground`, `cosmic`, and `cosmicMirrored`, with stored values `default`, `cosmic`, and `cosmic_mirrored`; null or unknown storage values fall back to `defaultBackground`.
- `BackgroundChoiceControl` currently renders three options and resolves selected-state copy only for the three existing preferences.
- English, German, and Arabic Settings localization files currently have no Daylight Lagoon label, description, or selected-state copy.
- `AmbientBackground` already resolves `BackgroundReadableColors` from the selected `BackgroundPreference`, injects the theme extension for descendants, applies matching `SystemUiOverlayStyle`, and switches among default, `CosmicBackground`, and `CosmicBackgroundMirrored`.
- `BackgroundReadableColors` already has dark and representative-light profiles, contrast-covered readable roles, preference resolution, and system chrome mapping; every current production preference resolves to the dark profile.
- Existing preference, Settings picker, ambient-background, readable-color, Settings-to-Feed smoke, and Feed performance tests cover the current dark options but do not cover a real production light background.
- Doc `84` left explicit follow-up before shipping a production light background: exhaustive remaining background-sensitive color classification, real production light-background Settings-to-surface integration coverage, and transient overlay coverage.

Disagreement rule:

- current code and tests beat stale prose
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` decide named gate membership
- source doc `86` remains the product intent source unless repo evidence proves a requirement stale or overclaimed

# session ledger

| Session id | Title | Classification | Intended plan file | Depends on | Current status |
|---|---|---|---|---|---|
| `01-production-daylight-option` | Production Daylight preference, Settings option, renderer, and light readable tone | `implementation-ready` | `Test-Flight-Improv/86-daylight-lagoon-background-option-session-01-production-daylight-option-plan.md` | None | `accepted` |
| `02-light-surface-readability` | Real Daylight shared-surface and transient UI readability hardening | `implementation-ready` | `Test-Flight-Improv/86-daylight-lagoon-background-option-session-02-light-surface-readability-plan.md` | `01-production-daylight-option` | `accepted` |
| `03-acceptance-performance-closure` | Daylight integration smoke, Feed performance, inventory, and docs closure | `acceptance-only` | `Test-Flight-Improv/86-daylight-lagoon-background-option-session-03-acceptance-performance-closure-plan.md` | `01-production-daylight-option`, `02-light-surface-readability` | `accepted_with_explicit_follow_up` |

# ordered session breakdown

## Session 01: Production Daylight preference, Settings option, renderer, and light readable tone

- Session id: `01-production-daylight-option`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/86-daylight-lagoon-background-option-session-01-production-daylight-option-plan.md`
- Exact scope:
  - add one permanent Daylight Lagoon `BackgroundPreference` value with a stable storage string that preserves existing `default`, `cosmic`, and `cosmic_mirrored` values
  - preserve null and unknown stored preference fallback to `defaultBackground`
  - add English, German, and Arabic Daylight Lagoon option label, description, selected-state copy, and accessibility semantics through the existing localization flow
  - update `BackgroundChoiceControl` so the four options render as distinguishable options and the control-level selected-state copy handles every preference explicitly
  - port or adapt `Test-Flight-Improv/Background-Feature/daylight_lagoon_background.dart` into production source under `lib/`, preserving the bright base, pastel lagoon blooms, no starfield, and reduced-motion or disabled-animation recognizability
  - integrate Daylight Lagoon into `AmbientBackground` so the selected preference renders the production Daylight visual through the existing app-wide background boundary
  - map the Daylight Lagoon preference to the light-readable `BackgroundReadableColors` profile, including dark status and navigation icon brightness
  - keep existing `Default`, `Cosmic`, and `Mirrored cosmic` visual behavior and dark-readable tone resolution intact
  - preserve Settings save honesty: failed Daylight saves must keep or restore visible background, readable theme, selected-state copy, and system chrome to the last confirmed preference
  - avoid broad shared-surface color migrations except for direct compile-safe changes and focused assertions needed to prove the Daylight option is synchronized
- Why it is its own session:
  - the model, Settings option, production renderer, ambient selection, and readable-tone resolver are one user-visible selection contract; splitting them would risk a selectable value that cannot honestly render
  - this session leaves a meaningful verified state: the app can represent, persist, display, render, and theme Daylight Lagoon as a real production option
- Likely code-entry files:
  - `lib/features/settings/domain/models/background_preference.dart`
  - `lib/features/settings/application/background_preference_use_cases.dart`
  - `lib/features/settings/presentation/widgets/background_choice_control.dart`
  - `lib/features/settings/presentation/screens/settings_screen.dart`
  - `lib/features/settings/presentation/screens/settings_wired.dart`
  - `lib/features/identity/presentation/widgets/ambient_background.dart`
  - a new production Daylight widget under `lib/features/identity/presentation/widgets/`
  - `lib/core/theme/background_readable_colors.dart`
  - `lib/l10n/app_en.arb`
  - `lib/l10n/app_de.arb`
  - `lib/l10n/app_ar.arb`
  - generated localization output if this repo commits it
  - `test/features/settings/application/background_preference_use_cases_test.dart`
  - `test/features/settings/presentation/widgets/background_choice_control_test.dart`
  - `test/features/settings/presentation/screens/settings_screen_test.dart`
  - `test/features/settings/presentation/screens/settings_wired_test.dart`
  - `test/features/identity/presentation/widgets/ambient_background_test.dart`
  - `test/core/theme/background_readable_colors_test.dart`
- Likely direct tests/regressions:
  - `flutter test test/features/settings/application/background_preference_use_cases_test.dart`
  - `flutter test test/features/settings/presentation/widgets/background_choice_control_test.dart`
  - `flutter test test/features/settings/presentation/screens/settings_screen_test.dart`
  - `flutter test test/features/settings/presentation/screens/settings_wired_test.dart`
  - `flutter test test/features/identity/presentation/widgets/ambient_background_test.dart`
  - `flutter test test/core/theme/background_readable_colors_test.dart`
  - storage round-trip tests for Daylight Lagoon plus regression assertions for existing stored values and fallback behavior
  - widget assertions for Daylight option visibility, selected icon/state, localized copy, semantics, and save-failure rollback
  - ambient-background assertions that Daylight renders the production widget, does not import from `Test-Flight-Improv`, exposes light-readable colors to descendants, and resolves dark system-bar icons
  - reduced-motion or disabled-animation assertions for Daylight Lagoon where the existing background test harness supports them
- Likely named gates:
  - none by default; this is direct Settings/domain/theme/widget coverage
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

## Session 02: Real Daylight shared-surface and transient UI readability hardening

- Session id: `02-light-surface-readability`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/86-daylight-lagoon-background-option-session-02-light-surface-readability-plan.md`
- Exact scope:
  - validate and, where necessary, migrate background-sensitive foreground, icon, border, glass, scrim, surface, input, placeholder, disabled, divider, loading, and overlay colors on representative shared-background surfaces using the real Daylight Lagoon preference
  - cover Settings and Feed with the production Daylight selection, not only the representative-light override from doc `84`
  - cover Conversation and at least one Group or Orbit surface with the production Daylight selection
  - cover representative transient UI such as dialogs, sheets, media pickers, message overlays, loading states, inputs, disabled states, and meaningful icon or asset treatments
  - classify remaining hard-coded foreground/surface/asset colors encountered on shared-background surfaces as background-aware, background-independent, or explicit follow-up with evidence
  - preserve current dark-background appearance for `Default`, `Cosmic`, and `Mirrored cosmic` unless a small role-backed adjustment is required and tested on the dark profiles
  - keep media quality, nearby sharing, identity, contacts, messages, posts, transport, notifications, and group state behavior unchanged
- Why it is its own session:
  - the real Daylight selection exposes the remaining follow-up risk from doc `84`: surfaces that were acceptable under representative fixtures may still need production-light evidence or narrow color migration
  - this session leaves a meaningful verified state: representative content-heavy, route, and transient UI surfaces are readable with the first production light background
- Likely code-entry files:
  - `lib/features/settings/presentation/screens/settings_screen.dart`
  - `lib/features/settings/presentation/widgets/background_choice_control.dart`
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/conversation/presentation/screens/conversation_screen.dart`
  - `lib/features/conversation/presentation/widgets/conversation_header.dart`
  - representative dialog, sheet, picker, media, message overlay, loading, or input widgets selected during planning
  - one or more of:
    - `lib/features/orbit/presentation/screens/orbit_screen.dart`
    - `lib/features/groups/presentation/screens/group_list_screen.dart`
    - `lib/features/groups/presentation/screens/group_conversation_screen.dart`
    - `lib/features/groups/presentation/screens/group_info_screen.dart`
  - `test/features/settings/presentation/screens/settings_screen_test.dart`
  - `test/features/settings/presentation/widgets/background_choice_control_test.dart`
  - `test/features/feed/presentation/screens/feed_screen_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  - representative group or Orbit widget tests selected during planning
  - `test/features/identity/presentation/widgets/ambient_background_test.dart`
  - `test/core/theme/background_readable_colors_test.dart`
- Likely direct tests/regressions:
  - focused widget tests for Settings, Feed, Conversation, and the chosen Group or Orbit surface with `BackgroundPreference.daylightLagoon`
  - contrast or resolved-color assertions for normal text and essential labels at `4.5:1`, and icons, borders, disabled components, controls, and meaningful non-text UI at `3:1`
  - widget coverage for representative dialogs/sheets/pickers/overlays/loading states with Daylight selected
  - rapid dark-to-light and light-to-dark switching assertions proving foreground roles, selected indicators, and system chrome do not remain stale
  - direct regression assertions that existing dark preferences still resolve dark-readable colors and preserve existing option behavior
- Likely named gates:
  - no named gate by default for presentation color-role migration
  - `./scripts/run_test_gates.sh feed` if Feed card/composer/handoff behavior changes beyond consuming readable roles, which should be avoided
  - `./scripts/run_test_gates.sh groups` only if group send/receive/retry/resume/invite/announcement behavior changes unexpectedly
  - no `1to1`, `posts`, `intro`, or `transport` gate unless implementation unexpectedly changes those behavior paths
  - run `./scripts/run_test_gates.sh completeness-check` only if gate definitions or classification docs are edited
- Matrix/closure docs to update when done:
  - this breakdown ledger and the session `02` plan/closure notes
  - `Test-Flight-Improv/84-background-readable-theme-extension.md` only if final closure decides the doc `84` explicit follow-up list should be narrowed based on Daylight evidence
  - `Test-Flight-Improv/02-integration-test-coverage.md` only if durable cross-surface coverage changes materially
  - `Test-Flight-Improv/test-gate-definitions.md` only if new integration or cross-feature tests are added
- Dependency on earlier sessions: `01-production-daylight-option`.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Session 03: Daylight integration smoke, Feed performance, inventory, and docs closure

- Session id: `03-acceptance-performance-closure`
- Session classification: `acceptance-only`
- Intended plan file: `Test-Flight-Improv/86-daylight-lagoon-background-option-session-03-acceptance-performance-closure-plan.md`
- Exact scope:
  - validate the combined Daylight behavior after Sessions `01` and `02`
  - run or extend Settings-to-Feed integration coverage for opening Settings, selecting Daylight Lagoon, returning to Feed with the light background and readable foregrounds synchronized, reopening Settings with Daylight still selected, switching back to a dark background, and restoring default
  - run or extend persistence/reload smoke coverage for the Daylight stored value and selected-state copy
  - run or extend Feed performance evidence for Daylight Lagoon selected against the source doc frame budgets or same-run default comparison budget
  - collect simulator/device evidence for system status/navigation chrome where the local environment exposes it, or record an exact environment block if it cannot be run
  - run the final direct test batch from Sessions `01` and `02` that remains relevant after all code has landed
  - update static or reviewed inventory evidence for remaining shared-background foreground, border, surface, glass, scrim, input, icon, dialog, sheet, media picker, message overlay, loading, and asset colors
  - update source doc `86`, this breakdown ledger, `Test-Flight-Improv/02-integration-test-coverage.md`, `Test-Flight-Improv/00-INDEX.md` if it tracks closure, and gate definitions only where final evidence requires it
  - record explicit follow-up only for evidence that is truly simulator/device/release-environment blocked, not for missing local direct tests
- Why it is its own session:
  - integration smoke, performance, inventory, device chrome evidence, and docs closure are meaningful only after the product option and representative readability work have landed
  - this prevents acceptance evidence from being scattered across implementation sessions and overclaiming closure before the first production light background has been exercised end to end
- Likely code-entry files:
  - `integration_test/settings_background_choice_smoke_test.dart`
  - `integration_test/feed_performance_test.dart`
  - representative non-Feed smoke or widget tests selected during planning
  - final direct suites from Sessions `01` and `02`
  - `Test-Flight-Improv/86-daylight-lagoon-background-option.md`
  - `Test-Flight-Improv/86-daylight-lagoon-background-option-session-breakdown.md`
  - `Test-Flight-Improv/02-integration-test-coverage.md`
  - `Test-Flight-Improv/00-INDEX.md` if the local closure convention requires it
  - `Test-Flight-Improv/test-gate-definitions.md` only if new integration/cross-feature tests need classification
- Likely direct tests/regressions:
  - final direct batch from Sessions `01` and `02`
  - `flutter test integration_test/settings_background_choice_smoke_test.dart -d <device>` or the repo's established device-backed command
  - `flutter test integration_test/feed_performance_test.dart -d <device>` or a documented performance fallback
  - representative non-Feed Daylight evidence for Conversation and one Group or Orbit surface
  - static inventory proof that all current shared-background surfaces remain on the selected-background path and that remaining background-sensitive colors are classified
  - narrowed analyzer pass if implementation touched generated localization, shared widgets, route constructors, or theme extensions
- Likely named gates:
  - direct tests are primary
  - `./scripts/run_test_gates.sh baseline` if final changes touched startup, QR, first-time, or app bootstrap wiring
  - `./scripts/run_test_gates.sh feed` if Feed route orchestration changed beyond visual/readable-color evidence
  - `./scripts/run_test_gates.sh groups` or `./scripts/run_test_gates.sh posts` only if implementation unexpectedly touched group or posts behavior beyond background/readable constructors
  - no `1to1` gate unless conversation send, retry, upload, listener, inbox, or handoff behavior changed
  - `./scripts/run_test_gates.sh completeness-check` if new integration or cross-feature tests were added or gate docs changed
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/86-daylight-lagoon-background-option.md`
  - `Test-Flight-Improv/86-daylight-lagoon-background-option-session-breakdown.md`
  - `Test-Flight-Improv/02-integration-test-coverage.md` if durable coverage inventory changes materially
  - `Test-Flight-Improv/00-INDEX.md` if the local closure convention requires it
  - `Test-Flight-Improv/test-gate-definitions.md` only if newly added integration/cross-feature tests need explicit classification
- Dependency on earlier sessions: `01-production-daylight-option`, `02-light-surface-readability`.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

# why this is not fewer sessions

Two sessions would combine either the production option slice with broad shared-surface hardening, or the surface hardening with integration/performance closure. Both combinations are unsafe. The first would make one session carry storage, localization, rendering, readable-theme resolution, Settings save honesty, representative route hardening, and transient overlay migration at once. The second would let final smoke and performance evidence double as implementation, which makes it too easy to miss remaining hard-coded light-background failures or overclaim closure without a focused inventory pass.

# why this is not more sessions

More sessions would mostly split one coherent background option into bookkeeping fragments. Separate storage-only, localization-only, readable-tone-only, or renderer-only sessions would create partial user-visible states or plans that cannot be accepted independently. Settings and Feed do not need their own Daylight sessions because doc `84` already did the general readable-role groundwork; this doc only needs production-light evidence and narrow hardening where the real Daylight option exposes gaps. Additional route-by-route sessions should be created only if Session `02` discovers a real structural surface category that cannot be verified with representative coverage.

# regression and gate contract

- Direct feature, theme, widget, and integration tests are the primary regression vehicle for this doc.
- The Baseline Gate applies only if implementation touches startup, QR, first-time experience, app bootstrap, or other baseline-owned wiring beyond background/readable constructors.
- The Feed / Surface Gate applies if Feed route orchestration, cards, composer, inline reply, or Feed-to-conversation handoff behavior changes beyond consuming the selected background and readable roles.
- The Group Messaging Gate applies only if group send, receive, retry, resume, invite, membership, or announcement behavior changes unexpectedly.
- The 1:1 Reliability Gate applies only if conversation send, retry, upload, listener, inbox, or handoff behavior changes unexpectedly.
- Posts, Intro, Startup/Transport, and Runtime Telemetry gates are out of scope unless implementation unexpectedly changes those subsystems.
- `./scripts/run_test_gates.sh completeness-check` is required if new integration or cross-feature tests are added, or if `Test-Flight-Improv/test-gate-definitions.md` is edited.

# matrix update contract

- Session `01` updates only its plan/closure notes and this ledger unless it adds durable Settings/background coverage that should be recorded in `Test-Flight-Improv/02-integration-test-coverage.md`.
- Session `02` updates this ledger and records any real Daylight readability inventory deltas. It may narrow doc `84` follow-up notes only if the Daylight work provides truthful replacement evidence.
- Session `03` owns final doc closure updates for `Test-Flight-Improv/86-daylight-lagoon-background-option.md`, this breakdown, `Test-Flight-Improv/02-integration-test-coverage.md`, `Test-Flight-Improv/00-INDEX.md` if applicable, and `Test-Flight-Improv/test-gate-definitions.md` only if new integration or cross-feature tests need classification.

# downstream execution path

For each session, run:

1. `$implementation-plan-orchestrator`
2. `$implementation-execution-qa-orchestrator`
3. `$implementation-closure-audit-orchestrator`

Later sessions must refresh their plan against landed code, current tests, and current gate definitions before execution.

# reviewer pass

- Recommended session count sufficient: yes, because each session ends in a meaningful verified state and the split follows the real risk boundaries.
- Too coarse: no. The broadest session is Session `02`, but it is intentionally representative and inventory-focused because doc `84` already created the readable-role foundation.
- Too fragmented: no. Storage, Settings, renderer, and readable-tone mapping stay together to avoid a selectable Daylight half-state.
- Sessions that should merge: none.
- Sessions that must split: none at decomposition time. If Session `02` finds a new structural category of unreadable surfaces, that session should record a concrete follow-up rather than pre-splitting route-by-route now.
- Missing tests or named gates: no named gates are mandatory by default; direct suites plus Settings-to-Feed integration and Feed performance are mandatory.
- Meaningful verified state: yes for all three sessions.
- Matrix-update responsibility: final durable coverage and closure updates belong to Session `03`.

# arbiter

- Structural blockers: none.
- Mergeable sessions: none.
- Required splits: none.
- Accepted differences:
  - The exact production Dart path and class name for Daylight Lagoon are left to Session `01`.
  - The exact stored value is left to Session `01`, but it must be stable, distinct, and regression-tested.
  - The exact final bloom opacity and animation tuning are left to Session `01`, but it must preserve the artifact's visible identity and pass direct rendering/readability evidence.
  - Device chrome evidence may be accepted with explicit follow-up only if the local environment cannot expose status/navigation bars; unit/widget overlay-style evidence still remains required.

# structural blockers remaining

None.

# accepted differences intentionally left unchanged

- No separate full app light theme is introduced.
- No additional background options are introduced.
- Existing dark backgrounds remain on the dark readable profile.
- Production code must not import from `Test-Flight-Improv`; the artifact is reference-only.
- Route-by-route visual goldens are not required unless planning finds that current widget/integration evidence cannot prove representative readability.

# exact docs/files used as evidence

- `Test-Flight-Improv/86-daylight-lagoon-background-option.md`
- `Test-Flight-Improv/82-app-wide-background-selection-session-breakdown.md`
- `Test-Flight-Improv/83-mirrored-cosmic-background-option-session-breakdown.md`
- `Test-Flight-Improv/84-background-readable-theme-extension-session-breakdown.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/Background-Feature/daylight_lagoon_background.dart`
- `lib/features/settings/domain/models/background_preference.dart`
- `lib/features/settings/presentation/widgets/background_choice_control.dart`
- `lib/features/identity/presentation/widgets/ambient_background.dart`
- `lib/core/theme/background_readable_colors.dart`

# why the decomposition is safe to send into downstream planning/execution

The session set keeps the first production light background synchronized at the user-visible boundary, reuses the app-wide background and readable-color contracts already landed by docs `82` through `84`, names doc-scoped plan paths, assigns final acceptance and docs closure to one session, and limits named gates to the behavior paths actually touched. The remaining ambiguities are implementation choices inside bounded sessions, not structural blockers.

# final program verdict

Verdict: `accepted_with_explicit_follow_up`

Doc `86` is accepted on April 28, 2026 with the production Daylight Lagoon option implemented and verified. The user-visible selection is now represented by `BackgroundPreference.daylightLagoon`, persists as `daylight_lagoon`, appears in localized Settings copy for English, German, and Arabic, renders through the production `DaylightLagoonBackground`, and resolves to the light-readable `BackgroundReadableColors` profile with dark status/navigation icon brightness. Existing `Default`, `Cosmic`, and `Mirrored cosmic` storage values and dark-readable mappings remain covered.

## final execution ledger

| Session id | Final status | Plan file | Tests and evidence | Follow-up |
|---|---|---|---|---|
| `01-production-daylight-option` | `accepted` | `Test-Flight-Improv/86-daylight-lagoon-background-option-session-01-production-daylight-option-plan.md` | `flutter test test/features/settings/application/background_preference_use_cases_test.dart test/features/settings/presentation/widgets/background_choice_control_test.dart test/features/identity/presentation/widgets/ambient_background_test.dart test/core/theme/background_readable_colors_test.dart`; plus `flutter test test/features/settings/presentation/screens/settings_screen_test.dart test/features/settings/presentation/screens/settings_wired_test.dart` | none |
| `02-light-surface-readability` | `accepted` | `Test-Flight-Improv/86-daylight-lagoon-background-option-session-02-light-surface-readability-plan.md` | `flutter test test/features/settings/presentation/screens/settings_screen_test.dart test/features/feed/presentation/screens/feed_screen_test.dart test/features/conversation/presentation/screens/conversation_screen_test.dart test/features/orbit/presentation/screens/orbit_screen_loading_test.dart` | none |
| `03-acceptance-performance-closure` | `accepted_with_explicit_follow_up` | `Test-Flight-Improv/86-daylight-lagoon-background-option-session-03-acceptance-performance-closure-plan.md` | final local direct batch passed; `flutter test -d emulator-5554 integration_test/settings_background_choice_smoke_test.dart` passed; `flutter test -d emulator-5554 integration_test/feed_performance_test.dart` passed with Daylight Lagoon scroll Avg/P99/Worst `2.09/8.83/10.09ms` against same-run default Avg/P99/Worst `2.42/8.16/11.51ms` | run any future release-specific visual/asset inventory or platform chrome screenshot sweep if product QA requires image-level proof beyond the representative widget, smoke, and performance evidence landed here |

## what is now closed

- Settings exposes `Daylight Lagoon` beside the existing three options with selected-state copy and semantics.
- Daylight Lagoon persists, reloads, overwrites, and falls back safely for missing or unknown stored values.
- Production code owns the renderer under `lib/features/identity/presentation/widgets/daylight_lagoon_background.dart` and the production-source test rejects imports from `Test-Flight-Improv`.
- `AmbientBackground` renders Daylight Lagoon and propagates the light-readable profile and dark system chrome icon brightness.
- Representative Settings, Feed, Conversation, and Orbit surfaces render Daylight Lagoon with light-readable foreground roles.
- Settings-to-Feed smoke and Feed performance acceptance include Daylight Lagoon on Android emulator `emulator-5554`.

## accepted follow-up

The main rollout is accepted with one explicit residual QA follow-up: if release QA needs image-level assurance for every remaining background-sensitive asset, run a visual/screenshot inventory sweep across the full shared-background surface list. No code-owned blocker remains in this doc.
