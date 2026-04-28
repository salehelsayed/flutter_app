# Decomposition artifact updated

- Artifact path: `Test-Flight-Improv/80-settings-background-choice-session-breakdown.md`
- Source doc path: `Test-Flight-Improv/80-settings-background-choice.md`
- Downstream workflow rule: detailed planning happens one session at a time. Later sessions must be refreshed against landed code, current tests, and current gate definitions before execution.
- Decomposition scope: this artifact belongs only to source doc `80`. It does not execute implementation, create session plans, or change unrelated files.

# Recommended plan count

Recommended plan count: 3

The source doc is one Flutter feature, but it spans three meaningful verification states: the persisted preference/default contract, the visible Settings chooser with honest save behavior, and final acceptance proof for shared default rendering, localization, accessibility, and closure documentation.

# Session ledger

| Session id | Title | Classification | Intended plan file | Depends on | Initial status |
|---|---|---|---|---|---|
| `01-preference-contract` | Default background preference and shared background contract | `implementation-ready` | `Test-Flight-Improv/80-settings-background-choice-session-01-preference-contract-plan.md` | None | `accepted` |
| `02-settings-picker` | Settings background chooser, persistence wiring, localization, and telemetry | `implementation-ready` | `Test-Flight-Improv/80-settings-background-choice-session-02-settings-picker-plan.md` | `01-preference-contract` | `accepted` |
| `03-acceptance-closure` | Visual, semantics, route-inventory, simulator-smoke, and docs closure | `acceptance-only` | `Test-Flight-Improv/80-settings-background-choice-session-03-acceptance-closure-plan.md` | `01-preference-contract`, `02-settings-picker` | `accepted` |

# Overall closure bar

Doc `80` is complete when Settings exposes a background choice with `Default` selected for missing or unknown stored values, choosing `Default` persists and reopens honestly, failed saves do not create silent false success, success/failure attempts emit non-sensitive flow events, Arabic/German/English labels resolve, assistive technologies can identify the control and selected option, and the current animated ambient background remains the shared app-wide default for every existing `AmbientBackground` surface, including pre-Settings onboarding surfaces.

No closure requires adding non-default background artwork, per-chat backgrounds, cross-device preference sync, notification/transport/database changes, or 14 separate route smoke tests. The 14-surface inventory is a checklist plus shared-path proof unless a later implementation intentionally special-cases a surface.

# Source of truth

Primary docs:

- `Test-Flight-Improv/80-settings-background-choice.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/02-integration-test-coverage.md`
- `UI-11-Settings/settings-spec.md`
- `/Users/I560101/.codex/skills/implementation-session-decomposer/SKILL.md`

Current repo facts governing the split:

- `SettingsScreen` currently wraps content in `AmbientBackground` and renders profile, peer ID, photo quality, video quality, nearby sharing, recovery phrase, and debug content, but no background chooser.
- `SettingsWired` currently loads identity, photo/video quality, and nearby sharing; it has no background preference state and no background save failure path.
- Existing image/video quality preference code provides the closest secure-storage pattern: enum model, storage key, `fromStorageString(...)` default fallback, and load/save use cases.
- `SecureKeyStore.write(...)` is asynchronous and can fail, so background saves need explicit failure behavior rather than optimistic false success.
- `FlowEventEmitter` already supports test-observable non-sensitive flow events, and Settings already emits screen, load, username, and avatar error events.
- `AmbientBackground` currently exposes only `child`, owns an infinite animation controller, and renders the existing black/green/red default treatment.
- `AmbientBackground` is used by Feed, Conversation, Posts, Settings, Orbit, Share Target Picker, QR Display, First Time Experience, Identity Choice, Create Group Picker, Contact Picker, Group List, Group Conversation, and Group Info.
- `IdentityChoiceScreen` and `FirstTimeExperienceScreen` use `AmbientBackground` before a user normally reaches Settings, so missing preference must remain a valid default state.
- `l10n.yaml` generates localization from `lib/l10n/app_en.arb`; current supported Settings strings exist in Arabic, German, and English, but no background-choice keys exist.
- Existing Settings tests cover title, back, profile/peer/recovery visibility, bottom navigation, media-quality toggles, and loaded video quality. They do not cover background choice.
- No direct test currently locks the default `AmbientBackground` appearance as a visual or golden-style baseline.

Disagreement rule:

- current code and tests beat stale prose
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` decide named gate membership
- source doc `80` remains the product intent source unless current repo evidence proves a requirement stale or overclaimed

# Ordered session breakdown

## Session 01: Default background preference and shared background contract

- Session id: `01-preference-contract`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/80-settings-background-choice-session-01-preference-contract-plan.md`
- Exact scope:
  - add the background preference domain model with a single user-facing option, `Default`
  - add secure-storage load/save use cases with missing, `default`, and unknown values resolving to `Default`
  - add direct unit coverage for parsing, load, save, overwrite, and unknown fallback behavior
  - introduce or prepare the shared `AmbientBackground` default contract without changing the current visible default treatment
  - keep all non-default artwork, fake variants, per-surface special cases, and sync/restore behavior out of scope
- Why it is its own session:
  - persistence/default parsing is a different seam from the visible Settings control and can be verified independently
  - the shared background contract must be stable before Settings wiring depends on it
- Likely code-entry files:
  - `lib/features/settings/domain/models/background_preference.dart`
  - `lib/features/settings/application/background_preference_use_cases.dart`
  - `lib/features/identity/presentation/widgets/ambient_background.dart`
  - `test/features/settings/application/background_preference_use_cases_test.dart`
  - `test/features/identity/presentation/widgets/ambient_background_test.dart`
- Likely direct tests/regressions:
  - `flutter test test/features/settings/application/background_preference_use_cases_test.dart`
  - `flutter test test/features/identity/presentation/widgets/ambient_background_test.dart`
  - existing image/video preference tests only if shared helper code is refactored
- Likely named gates:
  - none by default; this is feature-local/domain and shared-widget direct coverage
  - run `./scripts/run_test_gates.sh completeness-check` only if gate definitions or test classification docs are edited
- Matrix/closure docs to update when done:
  - this breakdown ledger and the session `01` plan/closure notes
  - `Test-Flight-Improv/test-gate-definitions.md` only if a new cross-feature, integration, core-service, or orchestration test is added
- Dependency on earlier sessions: none.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Session 02: Settings background chooser, persistence wiring, localization, and telemetry

- Session id: `02-settings-picker`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/80-settings-background-choice-session-02-settings-picker-plan.md`
- Exact scope:
  - add a Settings background choice control that shows `Default` selected when no saved preference exists
  - wire `SettingsWired` to load, display, save, and reopen the saved background preference
  - ensure failed saves do not silently present an unsaved choice as persisted; acceptable behavior is either revert to last confirmed selection or show clear failure copy while keeping reopen behavior honest
  - emit non-sensitive flow events for background-choice attempts and save success/failure outcomes
  - add Arabic, German, and English localized labels/options/failure text
  - expose accessible control purpose, available option, and selected state through widget semantics
  - preserve existing profile, peer ID, recovery phrase, photo/video quality, nearby sharing, debug card, close/back, and bottom navigation behavior
  - keep non-default variants, extra preview art, and route-transition changes out of scope
- Why it is its own session:
  - this is the user-visible Settings interaction seam, with UI, l10n, semantics, save-failure, and telemetry regressions that differ from pure preference parsing
  - it depends on the persisted preference contract from Session `01`
- Likely code-entry files:
  - `lib/features/settings/presentation/screens/settings_screen.dart`
  - `lib/features/settings/presentation/screens/settings_wired.dart`
  - `lib/features/settings/presentation/widgets/background_choice_control.dart`
  - `lib/l10n/app_en.arb`
  - `lib/l10n/app_de.arb`
  - `lib/l10n/app_ar.arb`
  - generated localization output if this repo commits generated l10n files
  - `test/features/settings/presentation/screens/settings_screen_test.dart`
  - `test/features/settings/presentation/screens/settings_wired_test.dart`
  - `test/features/settings/presentation/widgets/background_choice_control_test.dart`
- Likely direct tests/regressions:
  - `flutter test test/features/settings/presentation/widgets/background_choice_control_test.dart`
  - `flutter test test/features/settings/presentation/screens/settings_screen_test.dart`
  - `flutter test test/features/settings/presentation/screens/settings_wired_test.dart`
  - focused flow-event assertion using `debugSetFlowEventSink(...)`
  - focused fake `SecureKeyStore` failure test for failed-save honesty
  - static or widget localization checks that Arabic, German, and English background strings are non-empty and not raw keys
- Likely named gates:
  - none by default; Settings feature-local widget and wired tests are direct suites under the gate policy
  - run `./scripts/run_test_gates.sh feed` only if implementation changes Feed/AppShell route handoff or feed card behavior
  - run `./scripts/run_test_gates.sh baseline` only if implementation changes startup routing or QR/loading/posts/groups baseline files
- Matrix/closure docs to update when done:
  - this breakdown ledger and the session `02` plan/closure notes
  - `Test-Flight-Improv/test-gate-definitions.md` only if a new integration/cross-feature test must be classified
- Dependency on earlier sessions: `01-preference-contract`.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Session 03: Visual, semantics, route-inventory, simulator-smoke, and docs closure

- Session id: `03-acceptance-closure`
- Session classification: `acceptance-only`
- Intended plan file: `Test-Flight-Improv/80-settings-background-choice-session-03-acceptance-closure-plan.md`
- Exact scope:
  - validate the current default ambient background still renders as the recognizable black/green/red animated treatment when `Default` is selected
  - validate Settings readability and selected-state affordance remain visually valid under the default background
  - validate the background chooser semantics after final implementation, including purpose, option list, and selected state
  - prove reopen behavior with `Default` selected after leaving and reopening Settings
  - prove at least one representative mounted-route journey such as Feed -> Settings -> close still leaves the route under Settings on the shared default background path
  - smoke or widget-check pre-Settings onboarding surfaces that use `AmbientBackground`, especially `IdentityChoiceScreen` and `FirstTimeExperienceScreen`, for valid default rendering when no preference exists
  - refresh the static `AmbientBackground` call-site inventory and record any intentional special cases
  - perform the requested simulator/emulator smoke if a target is available; if not, record the exact blocked reason and keep host-side widget/visual evidence explicit
  - update closure docs without inventing a new settings-background matrix unless the implementation creates a durable matrix need
- Why it is its own session:
  - it validates the combined behavior of Sessions `01` and `02` across visual, accessibility, route-inventory, and smoke evidence
  - it should not be mixed into product implementation because it may need to rerun after both earlier sessions have landed
- Likely code-entry files:
  - `test/features/identity/presentation/widgets/ambient_background_test.dart`
  - `test/features/settings/presentation/screens/settings_wired_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart` only if a representative Feed route journey is added there
  - `test/features/identity/presentation/screens/identity_choice_screen_test.dart`
  - `test/features/home/presentation/screens/first_time_experience_wired_test.dart` or the closest existing first-time screen test
  - `Test-Flight-Improv/80-settings-background-choice.md`
  - `Test-Flight-Improv/02-integration-test-coverage.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Likely direct tests/regressions:
  - final direct batch from Sessions `01` and `02`
  - visual/golden-style or widget proof for default `AmbientBackground`
  - Settings reopen and failed-save evidence replay
  - representative Feed -> Settings -> close journey only if the implementation touches that route path
  - `flutter test test/features/identity/presentation/screens/identity_choice_screen_test.dart`
  - first-time experience direct test if the implementation makes the shared background preference observable there
  - one simulator/emulator smoke confirming Settings shows `Background` with `Default` selected and reopen preserves it, when a target is available
- Likely named gates:
  - no frozen named gate is required if only feature-local Settings/shared-widget code changed and direct suites cover the change
  - run `./scripts/run_test_gates.sh feed` if Feed route handoff, app shell state, or feed surface behavior changes
  - run `./scripts/run_test_gates.sh baseline` if startup/onboarding routing or baseline surfaces are modified
  - run `./scripts/run_test_gates.sh completeness-check` if any gate definition, matrix, or classification doc is edited
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/80-settings-background-choice.md` with closure evidence or final status if the downstream closure workflow records source-doc outcomes
  - `Test-Flight-Improv/02-integration-test-coverage.md` only if new Settings integration/visual coverage materially changes the stable coverage inventory
  - `Test-Flight-Improv/test-gate-definitions.md` only if new tests fall outside implicit feature-local/component direct suites
  - this breakdown ledger and the session `03` plan/closure notes
- Dependency on earlier sessions: `01-preference-contract`, `02-settings-picker`.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

# Why this is not fewer sessions

Two sessions would force either preference/default parsing or final visual/inventory closure into the Settings UI implementation. That would make it easier to miss one of the source doc's high-risk edges: missing/unknown storage fallback, failed-save honesty, non-sensitive telemetry, accessibility semantics, or shared default rendering across pre-Settings surfaces.

The first session leaves a meaningful verified state with a stable preference contract and default shared background path. The second leaves a meaningful user-visible state in Settings. The third validates the combined acceptance bar after both implementation slices are landed.

# Why this is not more sessions

More sessions would mostly split one Settings control by test case instead of by seam. Localization, semantics, telemetry, failed-save presentation, and preserving existing Settings cards all belong to the same chooser wiring because they are exercised through the same `SettingsScreen` and `SettingsWired` path. The 14 `AmbientBackground` surfaces are not 14 implementation sessions because the source doc allows shared-path proof plus inventory rather than one full route smoke per surface.

Future non-default background variants are intentionally not split into sessions because the source doc marks artwork, future variant names/previews, and future contrast thresholds as out of scope or later-release acceptance.

# Regression and gate contract

`Test-Flight-Improv/14-regression-test-strategy.md` applies by requiring targeted direct regressions for the changed seam first, then named gates only when shared pipelines are touched.

Default contract for this feature:

- feature-local Settings application/domain/widget/wired tests are the primary direct suites
- shared-widget visual or golden-style proof is required for the default `AmbientBackground` treatment
- localization and semantics checks are direct widget/static tests, not named gates
- a simulator/emulator smoke is part of the source doc's default-MVP QA bar when a target is available
- `./scripts/run_test_gates.sh feed` is required only if Feed/AppShell route handoff or feed behavior changes
- `./scripts/run_test_gates.sh baseline` is required only if startup/onboarding routing or baseline surfaces change
- `./scripts/run_test_gates.sh completeness-check` is required only when gate definitions or classification docs change

`Test-Flight-Improv/test-gate-definitions.md` remains the named-gate source of truth, and `scripts/run_test_gates.sh` wins if script and docs disagree.

# Matrix update contract

No dedicated stable settings-background matrix exists today. Do not invent one during planning unless implementation creates a durable matrix need that cannot be represented in the source doc and existing coverage inventory.

Session `03-acceptance-closure` owns closure documentation:

- update `Test-Flight-Improv/80-settings-background-choice.md` with final evidence/status if the downstream closure workflow records source-doc outcomes
- update `Test-Flight-Improv/02-integration-test-coverage.md` only if new Settings integration, visual, or smoke coverage materially changes the stable inventory
- update `Test-Flight-Improv/test-gate-definitions.md` only if new tests need explicit gate/direct-suite classification under its policy
- update this breakdown ledger with session outcomes during downstream execution

# Structural blockers remaining

None. The session set has a stable order, doc-scoped plan paths, direct regression families, named gate triggers, and clear closure ownership.

# Accepted differences intentionally left unchanged

- No non-default backgrounds are introduced.
- No fake background variants are required only to simulate a future release.
- No per-chat, per-group, per-post, or contact-specific background scope is added.
- No cross-device sync, identity-restore sync, relay, backup, notification, transport, database, or messaging behavior is added.
- No 14-route smoke matrix is required; shared-path proof plus refreshed call-site inventory is sufficient unless a route is intentionally special-cased.
- Future non-default contrast/readability acceptance is documented as future work, not part of the default-only MVP.

# Exact docs/files used as evidence

- `Test-Flight-Improv/80-settings-background-choice.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/02-integration-test-coverage.md`
- `UI-11-Settings/settings-spec.md`
- `/Users/I560101/.codex/skills/implementation-session-decomposer/SKILL.md`
- `lib/features/settings/presentation/screens/settings_screen.dart`
- `lib/features/settings/presentation/screens/settings_wired.dart`
- `lib/features/settings/domain/models/image_quality_preference.dart`
- `lib/features/settings/application/image_quality_preference_use_cases.dart`
- `lib/features/identity/presentation/widgets/ambient_background.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/core/secure_storage/secure_key_store.dart`
- `lib/core/secure_storage/flutter_secure_key_store.dart`
- `lib/core/utils/flow_event_emitter.dart`
- `lib/l10n/app_en.arb`
- `lib/l10n/app_de.arb`
- `lib/l10n/app_ar.arb`
- `l10n.yaml`
- `test/features/settings/application/image_quality_preference_use_cases_test.dart`
- `test/features/settings/application/video_quality_preference_use_cases_test.dart`
- `test/features/settings/presentation/screens/settings_screen_test.dart`
- `test/features/settings/presentation/screens/settings_wired_test.dart`
- `test/features/settings/presentation/widgets/image_quality_toggle_test.dart`
- `test/features/identity/presentation/screens/identity_choice_screen_test.dart`
- `test/core/secure_storage/fake_secure_key_store.dart`

# Downstream execution path

Each session should next go through these downstream skills in order:

| Session id | Next downstream path |
|---|---|
| `01-preference-contract` | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| `02-settings-picker` | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| `03-acceptance-closure` | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |

# Why the decomposition is safe to send into downstream planning/execution

The split keeps implementation bounded to one stored preference, one Settings control, and one acceptance/closure pass. It names the code-entry files and direct tests most likely to protect each seam, keeps named gates conditional on actual shared-surface changes, assigns matrix/closure responsibility to the final session, and preserves every non-goal from source doc `80`.

# Pipeline execution result

Final doc verdict: `closed`

Closed on: April 28, 2026

Session outcomes:

- `01-preference-contract`: accepted. Landed `BackgroundPreference`, secure-storage load/save use cases, and the additive `AmbientBackground.preference` default contract.
- `02-settings-picker`: accepted. Landed the Settings `BackgroundChoiceControl`, `SettingsScreen`/`SettingsWired` load-save wiring, localized copy, selected-state semantics, failed-save honesty, and background-choice flow events.
- `03-acceptance-closure`: accepted. Landed stronger default-background rendering proof, static 14-surface `AmbientBackground` call-site inventory, pre-Settings onboarding background checks, and a device-backed Settings-over-Feed smoke.

Verification evidence:

- `flutter test test/features/settings/application/background_preference_use_cases_test.dart test/features/identity/presentation/widgets/ambient_background_test.dart test/features/settings/presentation/widgets/background_choice_control_test.dart test/features/settings/presentation/screens/settings_screen_test.dart test/features/settings/presentation/screens/settings_wired_test.dart test/features/identity/presentation/screens/identity_choice_screen_test.dart test/features/home/presentation/screens/first_time_experience_screen_test.dart`
  - Result: passed.
- `flutter test integration_test/settings_background_choice_smoke_test.dart -d emulator-5554`
  - Result: passed.

Docs updated:

- `Test-Flight-Improv/80-settings-background-choice.md`
- `Test-Flight-Improv/80-settings-background-choice-session-breakdown.md`
- `Test-Flight-Improv/80-settings-background-choice-session-01-preference-contract-plan.md`
- `Test-Flight-Improv/80-settings-background-choice-session-02-settings-picker-plan.md`
- `Test-Flight-Improv/80-settings-background-choice-session-03-acceptance-closure-plan.md`
- `Test-Flight-Improv/02-integration-test-coverage.md`

Residual-only items:

- Future non-default backgrounds remain explicitly out of scope and require their own artwork, naming/preview, live-update, and readability acceptance before release.
