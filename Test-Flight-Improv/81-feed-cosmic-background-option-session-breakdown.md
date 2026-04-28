# Decomposition artifact updated

- Artifact path: `Test-Flight-Improv/81-feed-cosmic-background-option-session-breakdown.md`
- Source doc path: `Test-Flight-Improv/81-feed-cosmic-background-option.md`
- Downstream workflow rule: detailed planning happens one session at a time. Later sessions must be refreshed against landed code, current tests, and current gate definitions before execution.
- Decomposition scope: this artifact belongs only to source doc `81`. It does not execute implementation, create session plans, or change unrelated files.

# recommended plan count

Recommended plan count: 4

Doc `81` builds on the closed default-background foundation from doc `80`, but it spans four independently risky seams: the permanent stored `cosmic` preference and Settings option, production ownership of the cosmic background plus the shared Feed-only filter, Feed preference loading/live-return behavior, and final readability/performance/simulator closure.

# decomposition artifact

- Artifact path: `Test-Flight-Improv/81-feed-cosmic-background-option-session-breakdown.md`
- Proposal or source doc path: `Test-Flight-Improv/81-feed-cosmic-background-option.md`
- Intended plan file pattern: `Test-Flight-Improv/81-feed-cosmic-background-option-session-<session-id>-plan.md`
- Downstream workflow rule: each session should next go through `$implementation-plan-orchestrator`, `$implementation-execution-qa-orchestrator`, and `$implementation-closure-audit-orchestrator`. Later sessions must be refreshed against landed code and tests before execution.

# overall closure bar

Doc `81` is complete when Settings exposes `Default` and `Cosmic`, persists and reloads the shipped `cosmic` storage value honestly, emits non-sensitive success/failure flow telemetry, and resolves Arabic/German/English copy and accessible selected-state semantics; the app owns the cosmic background under production source; `AmbientBackground` renders cosmic only for the explicit Feed surface with a stored cosmic preference and defaults everywhere else; Feed loads the saved preference, updates after returning from Settings without restart, and can switch back to default; reduced-motion or disabled animation leaves a recognizable readable static cosmic treatment; representative Feed states remain readable and interactive; established Feed performance expectations are not regressed; and a simulator or emulator smoke records the Settings-to-Feed cosmic journey or the exact environment block.

# source of truth

Primary docs:

- `Test-Flight-Improv/81-feed-cosmic-background-option.md`
- `Test-Flight-Improv/80-settings-background-choice-session-breakdown.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `/Users/I560101/.codex/skills/implementation-session-decomposer/SKILL.md`

Current repo facts governing the split:

- `BackgroundPreference` currently has only `defaultBackground`, stores `default`, and falls back to default for null or unknown values.
- `loadBackgroundPreference` and `saveBackgroundPreference` already use `SecureKeyStore`.
- `SettingsWired` already loads, saves, reverts on failed save, and emits background-choice flow events for the default-only option.
- `BackgroundChoiceControl` currently renders one option, `Default`, with selected-state semantics and localized copy.
- `SettingsScreen` currently passes its selected preference to `AmbientBackground`, so cosmic must be filtered there rather than making the Settings route itself cosmic.
- `AmbientBackground` currently accepts a preference but has no surface discriminator and only renders the default ambient treatment.
- `FeedScreen` wraps its content in `AmbientBackground` without a preference, and `FeedWired` opens `SettingsWired` from the Feed route.
- The standalone cosmic design exists only under `Test-Flight-Improv/Background-Feature/cosmic_background.dart`; production runtime should not import from that path.
- The cosmic design uses an 18 second repeating controller, stopwatch-driven twinkle, and random stars on mount, so production tests need deterministic or reduced-motion proof rather than waiting for animation settlement.
- `integration_test/feed_performance_test.dart` already owns Feed frame-timing/performance expectations.
- `integration_test/settings_background_choice_smoke_test.dart` currently proves only the default Settings-over-Feed path.
- Existing doc `80` closed the default-background foundation and recorded direct tests for preference parsing, Settings picker, `AmbientBackground`, onboarding surfaces, and default Settings-over-Feed smoke.

Disagreement rule:

- current code and tests beat stale prose
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` decide named gate membership
- source doc `81` remains the product intent source unless repo evidence proves a requirement stale or overclaimed

# session ledger

| Session id | Title | Classification | Intended plan file | Depends on | Current status |
|---|---|---|---|---|---|
| `01-settings-cosmic-option` | Cosmic preference value, Settings option, localization, semantics, and telemetry | `implementation-ready` | `Test-Flight-Improv/81-feed-cosmic-background-option-session-01-settings-cosmic-option-plan.md` | None | `accepted` |
| `02-cosmic-background-filter` | Production cosmic background and shared Feed-only AmbientBackground filter | `implementation-ready` | `Test-Flight-Improv/81-feed-cosmic-background-option-session-02-cosmic-background-filter-plan.md` | `01-settings-cosmic-option` | `accepted` |
| `03-feed-preference-wiring` | Feed preference loading, Settings return refresh, and default restore | `implementation-ready` | `Test-Flight-Improv/81-feed-cosmic-background-option-session-03-feed-preference-wiring-plan.md` | `01-settings-cosmic-option`, `02-cosmic-background-filter` | `accepted` |
| `04-acceptance-performance-closure` | Cosmic readability, reduced-motion, Feed performance, simulator smoke, and docs closure | `acceptance-only` | `Test-Flight-Improv/81-feed-cosmic-background-option-session-04-acceptance-performance-closure-plan.md` | `01-settings-cosmic-option`, `02-cosmic-background-filter`, `03-feed-preference-wiring` | `accepted` |

# ordered session breakdown

## Session 01: Cosmic preference value, Settings option, localization, semantics, and telemetry

- Session id: `01-settings-cosmic-option`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/81-feed-cosmic-background-option-session-01-settings-cosmic-option-plan.md`
- Exact scope:
  - add the permanent production `cosmic` storage value to `BackgroundPreference`
  - keep null and unknown stored values falling back to `defaultBackground`
  - extend background preference load/save unit coverage for missing, `default`, `cosmic`, overwrite, and unknown values
  - extend `BackgroundChoiceControl` to show both `Default` and `Cosmic`
  - keep Settings itself on the default background even when `Cosmic` is selected
  - keep failed-save honesty for the cosmic path: revert to last confirmed value or otherwise make the failed state explicit, with reopen behavior truthful
  - extend non-sensitive background-choice flow telemetry so success and failure for `cosmic` are observable
  - add Arabic, German, and English localized labels/descriptions/selected-state copy for `Cosmic`
  - preserve existing Settings cards, media-quality preferences, nearby sharing, profile, recovery phrase, close/back, and bottom navigation behavior
- Why it is its own session:
  - the shipped storage identifier and Settings picker contract are a stable user-visible contract that can be verified before any production cosmic rendering or Feed route wiring lands
  - save-failure, localization, semantics, and telemetry regressions sit in the Settings seam, not the Feed rendering seam
- Likely code-entry files:
  - `lib/features/settings/domain/models/background_preference.dart`
  - `lib/features/settings/application/background_preference_use_cases.dart`
  - `lib/features/settings/presentation/widgets/background_choice_control.dart`
  - `lib/features/settings/presentation/screens/settings_screen.dart`
  - `lib/features/settings/presentation/screens/settings_wired.dart`
  - `lib/l10n/app_en.arb`
  - `lib/l10n/app_de.arb`
  - `lib/l10n/app_ar.arb`
  - generated localization output if this repo commits generated l10n files
  - `test/features/settings/application/background_preference_use_cases_test.dart`
  - `test/features/settings/presentation/widgets/background_choice_control_test.dart`
  - `test/features/settings/presentation/screens/settings_screen_test.dart`
  - `test/features/settings/presentation/screens/settings_wired_test.dart`
- Likely direct tests/regressions:
  - `flutter test test/features/settings/application/background_preference_use_cases_test.dart`
  - `flutter test test/features/settings/presentation/widgets/background_choice_control_test.dart`
  - `flutter test test/features/settings/presentation/screens/settings_screen_test.dart`
  - `flutter test test/features/settings/presentation/screens/settings_wired_test.dart`
  - focused telemetry assertions using the repo's flow-event test sink
  - localized-copy assertions for Arabic, German, and English cosmic option copy
  - semantics assertions that the control, `Default`, `Cosmic`, and selected option are discoverable without relying on color
- Likely named gates:
  - none by default; this is feature-local Settings/domain/widget/wired coverage
  - run `./scripts/run_test_gates.sh completeness-check` only if gate definitions or classification docs are edited
- Matrix/closure docs to update when done:
  - this breakdown ledger and the session `01` plan/closure notes
  - no new matrix doc unless implementation creates a durable matrix need
- Dependency on earlier sessions: none.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Session 02: Production cosmic background and shared Feed-only AmbientBackground filter

- Session id: `02-cosmic-background-filter`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/81-feed-cosmic-background-option-session-02-cosmic-background-filter-plan.md`
- Exact scope:
  - move or port the provided cosmic background into production app source under `lib/`
  - keep production runtime and tests from importing `Test-Flight-Improv/Background-Feature/cosmic_background.dart`
  - integrate the cosmic treatment through `AmbientBackground`
  - add an explicit per-call surface signal, such as a Feed flag or typed surface enum, so `AmbientBackground` renders cosmic only for Feed plus stored `cosmic`
  - ensure every non-Feed call with `cosmic`, every non-Feed call with default, and every Feed call with default renders the existing default treatment
  - keep the default ambient background visually unchanged
  - add reduced-motion or disabled-animation behavior so cosmic can render a recognizable readable static treatment without continuous drift or twinkle motion
  - make the cosmic visual testable without relying on random star placement or indefinite animation settlement
  - preserve child hit testing and layout so background layers stay behind route content
- Why it is its own session:
  - production background ownership, animation lifecycle, reduced-motion, and shared filtering are different risks from the Settings storage/control work
  - this session can leave a verified shared background primitive before Feed state wiring depends on it
- Likely code-entry files:
  - `lib/features/identity/presentation/widgets/ambient_background.dart`
  - a new production cosmic background widget under `lib/features/identity/presentation/widgets/` or another established shared widget location
  - `Test-Flight-Improv/Background-Feature/cosmic_background.dart` as read-only source evidence only
  - `test/features/identity/presentation/widgets/ambient_background_test.dart`
  - any focused production cosmic widget test if the implementation creates a separate public widget
- Likely direct tests/regressions:
  - `flutter test test/features/identity/presentation/widgets/ambient_background_test.dart`
  - widget coverage for all four combinations of (Feed flag x stored preference): Feed/cosmic renders cosmic; Feed/default, non-Feed/cosmic, and non-Feed/default render default
  - widget or visual-style proof that the cosmic background renders base gradient, blooms, stars, and child content from production source
  - reduced-motion or disabled-animation widget coverage that continuous cosmic motion stops while the visual remains recognizable
  - static assertion or import scan proving runtime app code does not import from `Test-Flight-Improv/`
- Likely named gates:
  - none by default; this is direct shared-widget coverage
  - run `./scripts/run_test_gates.sh baseline` only if startup/onboarding route code changes
  - run `./scripts/run_test_gates.sh completeness-check` only if gate definitions or classification docs are edited
- Matrix/closure docs to update when done:
  - this breakdown ledger and the session `02` plan/closure notes
  - `Test-Flight-Improv/02-integration-test-coverage.md` only if new stable visual/widget coverage materially changes the coverage inventory
- Dependency on earlier sessions: `01-settings-cosmic-option`.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Session 03: Feed preference loading, Settings return refresh, and default restore

- Session id: `03-feed-preference-wiring`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/81-feed-cosmic-background-option-session-03-feed-preference-wiring-plan.md`
- Exact scope:
  - load the stored background preference for Feed
  - pass the stored preference to `FeedScreen`/`AmbientBackground` with the explicit Feed surface signal
  - refresh the already-mounted Feed route after returning from Settings so selecting `Cosmic` or `Default` does not require app restart
  - prove selecting `Cosmic` changes Feed to the cosmic background and selecting `Default` restores the existing default background
  - prove Conversation and other Feed sub-routes opened from Feed do not inherit the cosmic background
  - prove Identity Choice and First Time Experience still use the default background with a stored `cosmic` value if this session's state plumbing touches those surfaces
  - keep Feed cards, header, empty state, inline replies, reactions, navigation, and Settings access behavior unchanged except for the background behind them
- Why it is its own session:
  - Feed route state, Settings-return refresh, and sub-route containment are separate from the reusable background widget and carry Feed/AppShell route-risk
  - this session leaves a meaningful product state: the saved preference is visible on Feed and can be restored to default
- Likely code-entry files:
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/settings/presentation/screens/settings_wired.dart` only if return callbacks are needed
  - `lib/features/identity/presentation/widgets/ambient_background.dart`
  - `test/features/feed/presentation/screens/feed_screen_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/conversation/presentation/screens/conversation_screen_test.dart` or the closest direct non-Feed surface test if needed
  - `test/features/identity/presentation/screens/identity_choice_screen_test.dart`
  - `test/features/home/presentation/screens/first_time_experience_screen_test.dart`
  - `integration_test/settings_background_choice_smoke_test.dart`
- Likely direct tests/regressions:
  - `flutter test test/features/feed/presentation/screens/feed_screen_test.dart`
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
  - `flutter test integration_test/settings_background_choice_smoke_test.dart` on host or with a device, depending on existing test constraints
  - focused non-Feed surface coverage for stored `cosmic` staying default, especially Conversation from Feed if practical
  - direct Settings-to-Feed journey coverage for cosmic selection, reopen selected state, and switch back to default
- Likely named gates:
  - `./scripts/run_test_gates.sh feed` if Feed route handoff, feed card behavior, or Feed surface orchestration changes beyond passing the background preference
  - `./scripts/run_test_gates.sh baseline` if startup/onboarding routing changes
  - no `1to1` gate unless feed-originated 1:1 send, retry, or conversation handoff behavior changes
- Matrix/closure docs to update when done:
  - this breakdown ledger and the session `03` plan/closure notes
  - `Test-Flight-Improv/test-gate-definitions.md` only if a new integration/cross-feature test needs explicit classification
- Dependency on earlier sessions: `01-settings-cosmic-option`, `02-cosmic-background-filter`.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Session 04: Cosmic readability, reduced-motion, Feed performance, simulator smoke, and docs closure

- Session id: `04-acceptance-performance-closure`
- Session classification: `acceptance-only`
- Intended plan file: `Test-Flight-Improv/81-feed-cosmic-background-option-session-04-acceptance-performance-closure-plan.md`
- Exact scope:
  - validate the combined Settings-to-Feed cosmic journey after Sessions `01` through `03`
  - validate Feed readability and usability with cosmic behind empty Feed, populated Feed, header, cards, badges, navigation, inline replies, reactions, and Settings access
  - validate the reduced-motion or disabled-animation cosmic state after final implementation
  - run or extend Feed performance coverage so cosmic Feed scrolling and common interactions stay within established expectations
  - run a simulator or emulator smoke for selecting `Cosmic`, seeing it on Feed, reopening Settings with `Cosmic` selected, switching back to `Default`, and seeing default restored; if the environment blocks it, record the exact command and failure
  - refresh stable coverage inventory or gate definitions only when new durable tests require it
  - update source doc `81`, this breakdown ledger, and session plan closure notes with final evidence and verdict
- Why it is its own session:
  - performance, visual/readability, reduced-motion acceptance, and simulator smoke must be evaluated after the implementation sessions land
  - closure evidence spans multiple seams and should not be hidden inside one implementation session
- Likely code-entry files:
  - `integration_test/feed_performance_test.dart`
  - `integration_test/settings_background_choice_smoke_test.dart`
  - `test/features/feed/presentation/screens/feed_screen_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/identity/presentation/widgets/ambient_background_test.dart`
  - `Test-Flight-Improv/81-feed-cosmic-background-option.md`
  - `Test-Flight-Improv/81-feed-cosmic-background-option-session-breakdown.md`
  - `Test-Flight-Improv/02-integration-test-coverage.md` only if coverage inventory materially changes
  - `Test-Flight-Improv/test-gate-definitions.md` only if new integration/cross-feature tests need explicit classification
- Likely direct tests/regressions:
  - final direct batch from Sessions `01`, `02`, and `03`
  - `flutter test integration_test/feed_performance_test.dart -d <device>` or the repo's established equivalent for Feed performance
  - `flutter test integration_test/settings_background_choice_smoke_test.dart -d <device>` or a documented host/device fallback
  - targeted widget/visual/readability checks for cosmic Feed empty and populated states
  - targeted reduced-motion proof for cosmic on Feed
- Likely named gates:
  - `./scripts/run_test_gates.sh feed` if Feed surface behavior or Feed route orchestration changed
  - `./scripts/run_test_gates.sh baseline` if startup/onboarding routing changed
  - `./scripts/run_test_gates.sh completeness-check` if gate definitions or classification docs are edited
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/81-feed-cosmic-background-option.md` with final evidence/status if the downstream closure workflow records source-doc outcomes
  - this breakdown ledger with session outcomes and final doc verdict
  - `Test-Flight-Improv/02-integration-test-coverage.md` only if durable Settings/Feed/cosmic coverage inventory changes
  - `Test-Flight-Improv/test-gate-definitions.md` only if newly added tests require explicit gate/direct-suite classification
- Dependency on earlier sessions: `01-settings-cosmic-option`, `02-cosmic-background-filter`, `03-feed-preference-wiring`.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

# why this is not fewer sessions

Three sessions would force either Feed live-wiring into the shared background primitive or performance/readability closure into implementation. That would hide two high-risk edges: the app-wide default filter for non-Feed surfaces, and the post-implementation proof that animated cosmic visuals do not make Feed unreadable or slow. Keeping Settings, shared background filtering, Feed state, and acceptance closure separate lets each session end in a verified state with the right direct tests.

# why this is not more sessions

More sessions would mostly split one coherent Settings option by individual test case, or split the cosmic painter from the `AmbientBackground` filter even though they must be reviewed together to prevent non-Feed surfaces from becoming cosmic. Localization, semantics, telemetry, and failed-save honesty belong to the Settings option seam. Feed empty/populated readability, performance, and simulator smoke belong to the final acceptance pass because they need the landed feature.

# regression and gate contract

`Test-Flight-Improv/14-regression-test-strategy.md` applies by requiring targeted direct regressions for the changed seam first, then named gates only when shared pipelines or frozen surfaces are touched.

Default contract for this feature:

- Settings/domain/widget/wired tests are the primary direct suites for the `cosmic` option, save behavior, localization, semantics, and telemetry.
- `AmbientBackground` widget tests are the primary direct suite for production cosmic rendering, default preservation, the Feed-only filter, and reduced-motion behavior.
- Feed screen/wired tests plus the existing Settings background smoke own the Settings-to-Feed route behavior and live refresh after returning from Settings.
- Feed performance evidence must use `integration_test/feed_performance_test.dart` or the repo's established equivalent if cosmic rendering changes frame timing risk.
- A simulator/emulator smoke is part of the source doc's QA bar when a target is available.
- `./scripts/run_test_gates.sh feed` is required if Feed route handoff, feed card behavior, composer, inline reply, or Feed surface orchestration changes beyond isolated background preference plumbing.
- `./scripts/run_test_gates.sh baseline` is required if startup/onboarding routing or baseline surfaces change.
- `./scripts/run_test_gates.sh completeness-check` is required only when gate definitions or classification docs change.
- `./scripts/run_test_gates.sh 1to1` is not required unless the implementation changes feed-originated 1:1 send, retry, upload, listener, inbox, or conversation handoff behavior.

`Test-Flight-Improv/test-gate-definitions.md` remains the named-gate source of truth, and `scripts/run_test_gates.sh` wins if script and docs disagree.

# matrix update contract

No dedicated stable background/cosmic matrix exists today. Do not invent one during planning unless implementation creates a durable matrix need that cannot be represented in the source doc, this breakdown, the session plans, and the existing coverage inventory.

Session `04-acceptance-performance-closure` owns closure documentation:

- update `Test-Flight-Improv/81-feed-cosmic-background-option.md` with final evidence/status if the downstream closure workflow records source-doc outcomes
- update this breakdown ledger with session outcomes and final doc verdict
- update `Test-Flight-Improv/02-integration-test-coverage.md` only if new durable Settings/Feed/cosmic integration, visual, performance, or smoke coverage materially changes the stable inventory
- update `Test-Flight-Improv/test-gate-definitions.md` only if new tests need explicit gate/direct-suite classification under its policy

# downstream execution path

Each session should next go through these downstream skills in order:

| Session id | Next downstream path |
|---|---|
| `01-settings-cosmic-option` | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| `02-cosmic-background-filter` | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| `03-feed-preference-wiring` | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| `04-acceptance-performance-closure` | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |

# reviewer pass

- Is the recommended session count sufficient, too coarse, or too fragmented? Sufficient. Four sessions match the real seams and avoid hiding performance/readability closure inside implementation.
- Which proposed sessions should merge? None. Settings/storage, shared background filtering, Feed live wiring, and final acceptance each require different direct tests.
- Which proposed sessions must split? None. Splitting localization, semantics, telemetry, or save-failure out of Session `01` would create bookkeeping without a separate verified product state.
- What tests or named gates are missing from the decomposition? None structurally. The plan names direct Settings, `AmbientBackground`, Feed, smoke, reduced-motion, and performance coverage, with feed/baseline/completeness gates conditional on actual touched surfaces.
- Does each session end in a meaningful verified state? Yes: Settings can select/store cosmic; the shared background can render/filter cosmic; Feed can load/refresh the preference; final acceptance can close readability/performance/smoke evidence.
- Is the matrix-update responsibility assigned clearly? Yes. Session `04` owns source-doc, breakdown, coverage-inventory, and gate-doc closure updates.
- What is the minimum session set that is still safe? Four sessions.

# arbiter pass

- Structural blockers: none.
- Mergeable sessions: none.
- Required splits: none.
- Accepted differences:
  - exact user-facing cosmic label can be finalized during Session `01` as long as Arabic/German/English copy is meaningful and tests do not accept raw keys
  - exact production source location for the cosmic widget can be finalized during Session `02` as long as runtime code lives under `lib/` and does not import from `Test-Flight-Improv/`
  - exact reduced-motion visual treatment can be finalized during Session `02` as long as continuous motion stops and readability is covered
  - exact simulator/emulator target can be chosen during Session `04`; environment blocks must be recorded with command and failure

# structural blockers remaining

None. The session set has doc-scoped plan paths, direct regression families, named gate triggers, a clear dependency order, and explicit closure ownership.

# accepted differences intentionally left unchanged

- No background options beyond `Default` and `Cosmic` are introduced.
- No cosmic background is applied to Conversation, Posts, Orbit, QR, share, onboarding, group, or other non-Feed surfaces outside any contained Settings picker preview.
- No star-position persistence across separate Feed mounts is required.
- No Feed card, navigation, inline reply, reaction, media, profile, Settings layout, transport, relay, notification, identity restore, backup, or cross-device sync behavior is redesigned.
- No repo-wide reduced-motion audit is required beyond the cosmic background acceptance for this feature.
- No new locales beyond Arabic, German, and English are introduced.

# Exact docs/files used as evidence

- `Test-Flight-Improv/81-feed-cosmic-background-option.md`
- `Test-Flight-Improv/80-settings-background-choice-session-breakdown.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `/Users/I560101/.codex/skills/implementation-session-decomposer/SKILL.md`
- `Test-Flight-Improv/Background-Feature/cosmic_background.dart`
- `lib/features/settings/domain/models/background_preference.dart`
- `lib/features/settings/application/background_preference_use_cases.dart`
- `lib/features/settings/presentation/widgets/background_choice_control.dart`
- `lib/features/settings/presentation/screens/settings_screen.dart`
- `lib/features/settings/presentation/screens/settings_wired.dart`
- `lib/features/identity/presentation/widgets/ambient_background.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/l10n/app_en.arb`
- `lib/l10n/app_de.arb`
- `lib/l10n/app_ar.arb`
- `test/features/settings/application/background_preference_use_cases_test.dart`
- `test/features/settings/presentation/widgets/background_choice_control_test.dart`
- `test/features/settings/presentation/screens/settings_screen_test.dart`
- `test/features/settings/presentation/screens/settings_wired_test.dart`
- `test/features/identity/presentation/widgets/ambient_background_test.dart`
- `test/features/feed/presentation/screens/feed_screen_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `integration_test/settings_background_choice_smoke_test.dart`
- `integration_test/feed_performance_test.dart`

# Why the decomposition is safe to send into downstream planning/execution

The split keeps implementation bounded to one shipped preference value, one Settings picker extension, one production background/filter primitive, one Feed state-wiring pass, and one final acceptance/performance closure. It names the code-entry files and direct tests most likely to protect each seam, keeps named gates conditional on actual shared-surface changes, assigns closure docs to the final session, and preserves the non-goals and Feed-only rule from source doc `81`.

# Pipeline execution progress

- Session `01-settings-cosmic-option`: `accepted` on April 28, 2026. Landed the permanent `cosmic` storage value, two-option Settings picker, Settings default-route guard, localized copy, semantics, and background-choice flow telemetry coverage. Verification passed:
  `flutter test test/features/settings/application/background_preference_use_cases_test.dart test/features/settings/presentation/widgets/background_choice_control_test.dart test/features/settings/presentation/screens/settings_screen_test.dart test/features/settings/presentation/screens/settings_wired_test.dart`.
- Session `02-cosmic-background-filter`: `accepted` on April 28, 2026. Landed production `CosmicBackground`, deterministic/testable starfield rendering, disabled-animation static mode, and the central `AmbientBackground.isFeedSurface` filter. Verification passed:
  `flutter test test/features/identity/presentation/widgets/ambient_background_test.dart`.
- Session `03-feed-preference-wiring`: `accepted` on April 28, 2026. Landed Feed background preference loading, Feed `isFeedSurface` opt-in, and Settings-return preference refresh. Verification passed:
  `flutter test test/features/feed/presentation/screens/feed_screen_test.dart test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "background"` and
  `flutter test test/features/feed/presentation/screens/feed_screen_test.dart`.
- Session `04-acceptance-performance-closure`: `accepted` on April 28, 2026. Extended the device smoke to cover Default -> Cosmic -> Feed -> reopen Settings -> Default restore, added a cosmic Feed scroll performance scenario with same-run default baseline comparison, and updated closure/coverage docs. Verification passed:
  `flutter test integration_test/settings_background_choice_smoke_test.dart -d emulator-5554` and
  `flutter test integration_test/feed_performance_test.dart -d emulator-5554 --plain-name "Cosmic scroll performance"`.

# Final doc verdict

Verdict: `closed`

Doc `81` is closed on April 28, 2026. Settings exposes and persists `Default` and `Cosmic`, Feed renders the stored cosmic preference only through the explicit Feed surface path, non-Feed `AmbientBackground` callers fall back to the default treatment, reduced-motion cosmic rendering is covered, the Settings-to-Feed device smoke passes on Android emulator `emulator-5554`, and the cosmic scroll performance scenario passes on Android emulator `emulator-5554` against a same-run default Feed baseline.

Spawned rollout note: the decomposition and pipeline controller agents did not produce bounded progress, so the controller used the single allowed local decomposition fallback and the single allowed local pipeline fallback against this doc-owned breakdown. No extra breakdown artifact or competing retry tier was created.
