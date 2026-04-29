# Decomposition artifact updated

- Artifact path: `Test-Flight-Improv/82-app-wide-background-selection-session-breakdown.md`
- Source doc path: `Test-Flight-Improv/82-app-wide-background-selection.md`
- Downstream workflow rule: detailed planning happens one session at a time. Later sessions must be refreshed against landed code, current tests, and current gate definitions before execution.
- Decomposition scope: this artifact belongs only to source doc `82`. It does not execute implementation, create session plans, or change unrelated files.

# recommended plan count

Recommended plan count: 4

Doc `82` supersedes the Feed-only limit from doc `81`. The smallest safe rollout is four sessions because the work spans four distinct risks: the shared background primitive must stop filtering cosmic to Feed, the app needs one saved preference state source that Settings can update live and honestly, every current shared-background surface must receive that selected state, and final acceptance must prove readability, lifecycle, performance, inventory, and docs closure across the broader app-wide surface.

# decomposition artifact

- Artifact path: `Test-Flight-Improv/82-app-wide-background-selection-session-breakdown.md`
- Proposal or source doc path: `Test-Flight-Improv/82-app-wide-background-selection.md`
- Intended plan file pattern: `Test-Flight-Improv/82-app-wide-background-selection-session-<session-id>-plan.md`
- Downstream workflow rule: each session should next go through `$implementation-plan-orchestrator`, `$implementation-execution-qa-orchestrator`, and `$implementation-closure-audit-orchestrator`. Later sessions must be refreshed against landed code and tests before execution.

# overall closure bar

Doc `82` is complete when the saved background preference applies to every current shared `AmbientBackground` surface named by the source doc; selecting `Cosmic` in Settings changes Settings itself during the same successful session, survives reopen, updates Feed and already-mounted return paths without restart, and appears on representative non-Feed and pre-identity surfaces; selecting `Default`, missing storage, and unknown storage all render the existing default ambient treatment everywhere; failed saves remain honest and do not show a background the rest of the app will not use; Arabic/German/English copy and semantics remain meaningful; reduced-motion disables continuous cosmic motion while preserving a recognizable readable visual; rapid navigation and overlays do not stack duplicate backgrounds or leak animation lifecycle errors; representative Feed and heavy non-Feed chat performance remain within established expectations; and a final audited inventory records every current shared-background surface as covered or intentionally excluded by a later spec.

# source of truth

Primary docs:

- `Test-Flight-Improv/82-app-wide-background-selection.md`
- `Test-Flight-Improv/81-feed-cosmic-background-option-session-breakdown.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/02-integration-test-coverage.md`
- `/Users/I560101/.codex/skills/implementation-session-decomposer/SKILL.md`

Current repo facts governing the split:

- `BackgroundPreference` already has `defaultBackground` and `cosmic`; null or unknown stored values already fall back to default.
- `SettingsWired` already loads, saves, reverts on failed save, and emits attempt/saved/save-error background preference flow events.
- `SettingsScreen` currently passes `BackgroundPreference.defaultBackground` to `AmbientBackground`, so Settings does not show the selected cosmic full-screen background.
- `AmbientBackground` currently renders `CosmicBackground` only when `preference == cosmic` and `isFeedSurface == true`; non-Feed cosmic falls back to default.
- `AmbientBackground` tests currently assert the obsolete Feed-only filter and include an auditable static inventory of current shared-background call sites.
- `FeedWired` currently loads the saved preference from secure storage and refreshes it after returning from Settings, then passes it to `FeedScreen`.
- Current non-Feed call sites use `AmbientBackground` without the saved preference: Conversation, Posts, Settings, Orbit, Share Target Picker, QR Display, First Time Experience, Identity Choice, Create Group Picker, Contact Picker, Group List, Group Conversation, and Group Info.
- `integration_test/settings_background_choice_smoke_test.dart` currently proves the Feed -> Settings -> Cosmic -> Feed -> Default restore journey, but not Settings live full-screen background or non-Feed app-wide behavior.
- `Test-Flight-Improv/02-integration-test-coverage.md` already records doc `81` Settings/Feed/cosmic coverage and should be updated only if durable coverage inventory changes materially.

Disagreement rule:

- current code and tests beat stale prose
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` decide named gate membership
- source doc `82` remains the product intent source unless repo evidence proves a requirement stale or overclaimed

# session ledger

| Session id | Title | Classification | Intended plan file | Depends on | Current status |
|---|---|---|---|---|---|
| `01-shared-background-contract` | App-wide `AmbientBackground` selected-preference contract and inventory baseline | `implementation-ready` | `Test-Flight-Improv/82-app-wide-background-selection-session-01-shared-background-contract-plan.md` | None | `accepted` |
| `02-preference-state-and-settings` | Shared preference state source plus Settings live background and save honesty | `implementation-ready` | `Test-Flight-Improv/82-app-wide-background-selection-session-02-preference-state-and-settings-plan.md` | `01-shared-background-contract` | `accepted` |
| `03-surface-propagation` | Propagate selected background to non-Feed, pre-identity, and group surfaces | `implementation-ready` | `Test-Flight-Improv/82-app-wide-background-selection-session-03-surface-propagation-plan.md` | `01-shared-background-contract`, `02-preference-state-and-settings` | `accepted` |
| `04-acceptance-performance-closure` | App-wide readability, lifecycle, performance, smoke, inventory, and docs closure | `acceptance-only` | `Test-Flight-Improv/82-app-wide-background-selection-session-04-acceptance-performance-closure-plan.md` | `01-shared-background-contract`, `02-preference-state-and-settings`, `03-surface-propagation` | `accepted_with_explicit_follow_up` |

# ordered session breakdown

## Session 01: App-wide `AmbientBackground` selected-preference contract and inventory baseline

- Session id: `01-shared-background-contract`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/82-app-wide-background-selection-session-01-shared-background-contract-plan.md`
- Exact scope:
  - change the shared `AmbientBackground` contract so `BackgroundPreference.cosmic` renders `CosmicBackground` for any shared-background surface, not only Feed
  - retire, ignore, or compatibility-preserve `isFeedSurface` only as needed to avoid unsafe call-site churn; it must no longer be the condition that blocks cosmic on non-Feed surfaces
  - keep `BackgroundPreference.defaultBackground`, missing storage, and unknown storage resolving to the existing default ambient treatment
  - preserve child layout, hit testing, default ambient visual treatment, and cosmic reduced-motion behavior from doc `81`
  - replace obsolete Feed-only widget assertions with app-wide selected-background assertions
  - keep or tighten the static inventory of current shared-background call sites named by doc `82`
- Why it is its own session:
  - the shared primitive can be made truthful before broader route state propagation starts
  - this session leaves a meaningful verified state: any caller that supplies `cosmic` now gets cosmic, and any caller that supplies default still gets the old ambient background
- Likely code-entry files:
  - `lib/features/identity/presentation/widgets/ambient_background.dart`
  - `lib/features/identity/presentation/widgets/cosmic_background.dart`
  - `lib/features/settings/domain/models/background_preference.dart`
  - `test/features/identity/presentation/widgets/ambient_background_test.dart`
  - `test/features/settings/application/background_preference_use_cases_test.dart`
- Likely direct tests/regressions:
  - `flutter test test/features/identity/presentation/widgets/ambient_background_test.dart`
  - `flutter test test/features/settings/application/background_preference_use_cases_test.dart`
  - widget assertions that `cosmic` renders `CosmicBackground` without a Feed flag
  - widget assertions that default remains the default ambient treatment
  - reduced-motion or disabled-animation assertions for cosmic static rendering
  - static inventory assertion for all shared-background surface files named in doc `82`
- Likely named gates:
  - none by default; this is direct shared-widget and settings-domain coverage
  - run `./scripts/run_test_gates.sh completeness-check` only if gate definitions or classification docs are edited
- Matrix/closure docs to update when done:
  - this breakdown ledger and the session `01` plan/closure notes
  - `Test-Flight-Improv/02-integration-test-coverage.md` only if the durable coverage inventory changes materially
- Dependency on earlier sessions: none.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Session 02: Shared preference state source plus Settings live background and save honesty

- Session id: `02-preference-state-and-settings`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/82-app-wide-background-selection-session-02-preference-state-and-settings-plan.md`
- Exact scope:
  - establish or extend a single app-level background preference state source so shared-background surfaces can observe the saved preference without each inventing its own storage read path
  - load the saved preference from `SecureKeyStore`, default missing and unknown values to `defaultBackground`, and expose change notifications or rebuild triggers through an existing local pattern
  - update Settings so `SettingsScreen` passes `currentBackgroundPreference` to `AmbientBackground`
  - ensure a successful Settings selection changes the Settings full-screen background in the same Settings session
  - preserve failed-save honesty: if saving `Cosmic` or `Default` fails, Settings reverts to the last confirmed background or shows the existing recoverable failure state without claiming a saved selected background
  - preserve background flow telemetry as selection attempt, successful save, and failed save only; do not add per-surface render/apply events
  - keep Arabic, German, and English picker copy and selected-state semantics meaningful after Settings itself becomes a selected-background surface
- Why it is its own session:
  - app-wide preference ownership and Settings live feedback are a state-management seam, distinct from the shared rendering primitive and broad call-site propagation
  - this session makes Settings truthful and creates the state contract later surfaces can consume
- Likely code-entry files:
  - `lib/features/feed/application/app_shell_controller.dart` or a new focused background preference controller/helper in the existing feature/application style
  - `lib/features/settings/application/background_preference_use_cases.dart`
  - `lib/features/settings/presentation/screens/settings_screen.dart`
  - `lib/features/settings/presentation/screens/settings_wired.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart` if Feed moves from private storage reads to the shared source
  - `lib/l10n/app_en.arb`
  - `lib/l10n/app_de.arb`
  - `lib/l10n/app_ar.arb`
  - generated localization output if this repo commits generated l10n files
  - `test/features/settings/presentation/screens/settings_screen_test.dart`
  - `test/features/settings/presentation/screens/settings_wired_test.dart`
  - `test/features/settings/presentation/widgets/background_choice_control_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart` if Feed refresh behavior is touched
- Likely direct tests/regressions:
  - `flutter test test/features/settings/presentation/screens/settings_screen_test.dart`
  - `flutter test test/features/settings/presentation/screens/settings_wired_test.dart`
  - `flutter test test/features/settings/presentation/widgets/background_choice_control_test.dart`
  - focused controller/helper unit tests if a new state source is introduced
  - Settings widget coverage that cosmic selected means full-screen `CosmicBackground` plus picker selected state remains readable
  - Settings wired coverage that successful selection updates the full-screen background in-session
  - failed-save coverage proving the visual background and selected state revert or remain explicitly recoverable
  - telemetry assertions for attempt, saved, and save-error outcomes without per-surface telemetry
- Likely named gates:
  - none by default; this is feature-local Settings/application/widget/wired coverage
  - run `./scripts/run_test_gates.sh feed` only if Feed route orchestration changes beyond consuming the shared preference state
  - run `./scripts/run_test_gates.sh completeness-check` only if gate definitions or classification docs are edited
- Matrix/closure docs to update when done:
  - this breakdown ledger and the session `02` plan/closure notes
  - `Test-Flight-Improv/02-integration-test-coverage.md` only if new durable Settings/background coverage is added
- Dependency on earlier sessions: `01-shared-background-contract`.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Session 03: Propagate selected background to non-Feed, pre-identity, and group surfaces

- Session id: `03-surface-propagation`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/82-app-wide-background-selection-session-03-surface-propagation-plan.md`
- Exact scope:
  - route the selected background preference into every current shared-background surface named by doc `82`
  - cover Feed, Conversation, Posts, Settings, Orbit, Share Target Picker, QR Display, First Time Experience, Identity Choice, Create Group Picker, Contact Picker, Group List, Group Conversation, and Group Info
  - ensure returning from Settings to an already-mounted route reflects the selected background without app restart
  - ensure pre-identity and first-time surfaces reflect a stored valid `Cosmic` preference when one exists, while users with no stored preference still see default
  - keep `Default` restore behavior consistent across Feed and representative non-Feed surfaces
  - avoid changing chat/message, posts, group, onboarding, QR, share, media-quality, nearby sharing, notification, or transport behavior except for the background layer behind existing content
  - update direct tests or static inventory so every current shared-background surface is accounted for as covered or intentionally excluded by a later spec
- Why it is its own session:
  - broad route and constructor propagation is a high-blast-radius call-site seam that should not be mixed with the Settings state source or final performance acceptance
  - this session leaves the product-visible app-wide behavior in place before slower acceptance gates run
- Likely code-entry files:
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/conversation/presentation/screens/conversation_screen.dart`
  - `lib/features/posts/presentation/screens/posts_screen.dart`
  - `lib/features/settings/presentation/screens/settings_screen.dart`
  - `lib/features/orbit/presentation/screens/orbit_screen.dart`
  - `lib/features/share/presentation/screens/share_target_picker_screen.dart`
  - `lib/features/qr_code/presentation/screens/qr_display_screen.dart`
  - `lib/features/home/presentation/screens/first_time_experience_screen.dart`
  - `lib/features/identity/presentation/screens/identity_choice_screen.dart`
  - `lib/features/groups/presentation/screens/create_group_picker_screen.dart`
  - `lib/features/groups/presentation/screens/contact_picker_screen.dart`
  - `lib/features/groups/presentation/screens/group_list_screen.dart`
  - `lib/features/groups/presentation/screens/group_conversation_screen.dart`
  - `lib/features/groups/presentation/screens/group_info_screen.dart`
  - the wired/route-builder files that construct those screens
  - `test/features/identity/presentation/widgets/ambient_background_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  - `test/features/home/presentation/screens/first_time_experience_screen_test.dart`
  - `test/features/identity/presentation/screens/identity_choice_screen_test.dart`
  - representative group, posts, orbit, QR, and share screen tests as needed by the actual call-site changes
  - `integration_test/settings_background_choice_smoke_test.dart`
- Likely direct tests/regressions:
  - `flutter test test/features/identity/presentation/widgets/ambient_background_test.dart`
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
  - `flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart`
  - `flutter test test/features/home/presentation/screens/first_time_experience_screen_test.dart`
  - `flutter test test/features/identity/presentation/screens/identity_choice_screen_test.dart`
  - representative non-Feed surface widget coverage showing stored or supplied `Cosmic` renders cosmic
  - representative non-Feed default restore coverage
  - pre-identity or first-time stored-cosmic coverage
  - static inventory assertion that every current shared-background surface named by doc `82` participates in the selected-background path or records a future-spec exclusion
  - Settings-to-returned-route smoke coverage for an already-mounted route when practical
- Likely named gates:
  - `./scripts/run_test_gates.sh baseline` if startup, onboarding, QR, or first route selection changes
  - `./scripts/run_test_gates.sh feed` if Feed route orchestration or feed surface behavior changes beyond receiving the selected background
  - `./scripts/run_test_gates.sh posts` only if posts delivery/privacy logic changes, which should be avoided
  - `./scripts/run_test_gates.sh groups` only if group send/receive/invite/recovery logic changes, which should be avoided
  - no `1to1` gate unless conversation send, retry, upload, listener, inbox, or handoff behavior changes
  - run `./scripts/run_test_gates.sh completeness-check` only if gate definitions or classification docs are edited
- Matrix/closure docs to update when done:
  - this breakdown ledger and the session `03` plan/closure notes
  - `Test-Flight-Improv/02-integration-test-coverage.md` if the durable app-wide background inventory or smoke coverage changes materially
  - `Test-Flight-Improv/test-gate-definitions.md` only if newly added integration/cross-feature tests need explicit classification
- Dependency on earlier sessions: `01-shared-background-contract`, `02-preference-state-and-settings`.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Session 04: App-wide readability, lifecycle, performance, smoke, inventory, and docs closure

- Session id: `04-acceptance-performance-closure`
- Session classification: `acceptance-only`
- Intended plan file: `Test-Flight-Improv/82-app-wide-background-selection-session-04-acceptance-performance-closure-plan.md`
- Exact scope:
  - validate the combined app-wide selected-background behavior after Sessions `01` through `03`
  - run or extend representative smoke coverage for Settings selecting `Cosmic`, Settings live feedback, return to Feed, representative non-Feed surface, reopen Settings selected state, switch to `Default`, and default restore
  - validate rapid navigation across multiple shared-background surfaces with `Cosmic` selected does not crash, leak ticker/animation lifecycle errors, leave stacked duplicate background layers, or flash blank backgrounds
  - validate representative overlay readability over a cosmic surface without adding a second independent background layer
  - validate reduced-motion or disabled-animation cosmic behavior on representative shared-background surfaces
  - run Feed performance evidence with `Cosmic` and either run or add equivalent heavy non-Feed chat-surface performance evidence for Conversation
  - complete the auditable inventory for all current shared-background surfaces named by doc `82`
  - update source doc `82`, this breakdown ledger, stable coverage inventory, and gate definitions only where final evidence requires it
  - record exact command and environment failure for any simulator/device-only acceptance that cannot run locally
- Why it is its own session:
  - readability, lifecycle stress, representative route smoke, performance, and final documentation are meaningful only after the app-wide implementation lands
  - this keeps acceptance evidence from being diluted across broad implementation sessions
- Likely code-entry files:
  - `integration_test/settings_background_choice_smoke_test.dart`
  - `integration_test/feed_performance_test.dart`
  - a focused Conversation or non-Feed chat performance test if needed
  - representative overlay/readability widget or integration tests near the affected surface
  - `test/features/identity/presentation/widgets/ambient_background_test.dart`
  - `test/features/settings/presentation/screens/settings_wired_test.dart`
  - `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  - `Test-Flight-Improv/82-app-wide-background-selection.md`
  - `Test-Flight-Improv/82-app-wide-background-selection-session-breakdown.md`
  - `Test-Flight-Improv/02-integration-test-coverage.md`
  - `Test-Flight-Improv/test-gate-definitions.md` only if new integration/cross-feature tests need classification
- Likely direct tests/regressions:
  - final direct batch from Sessions `01`, `02`, and `03`
  - `flutter test integration_test/settings_background_choice_smoke_test.dart -d <device>` or the repo's established host/device fallback
  - `flutter test integration_test/feed_performance_test.dart -d <device>` or a documented performance fallback
  - focused Conversation performance coverage with `Cosmic` selected, or a documented equivalent heavy non-Feed chat-surface performance run
  - widget/integration coverage for reduced-motion cosmic on representative non-Feed surfaces
  - widget/integration coverage for rapid navigation disposal across several cosmic surfaces
  - widget/integration coverage for overlay readability on a cosmic shared-background surface
  - final static inventory proof for every shared-background surface named by doc `82`
- Likely named gates:
  - `./scripts/run_test_gates.sh baseline` if startup/onboarding/QR route changes landed
  - `./scripts/run_test_gates.sh feed` if Feed route orchestration changed
  - `./scripts/run_test_gates.sh posts` only if posts logic changed unexpectedly
  - `./scripts/run_test_gates.sh groups` only if group logic changed unexpectedly
  - `./scripts/run_test_gates.sh completeness-check` if gate definitions or classification docs are edited
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/82-app-wide-background-selection.md` with final evidence/status if the downstream closure workflow records source-doc outcomes
  - this breakdown ledger with session outcomes and final doc verdict
  - `Test-Flight-Improv/02-integration-test-coverage.md` if durable app-wide background coverage inventory changes
  - `Test-Flight-Improv/test-gate-definitions.md` only if newly added tests require explicit gate/direct-suite classification
- Dependency on earlier sessions: `01-shared-background-contract`, `02-preference-state-and-settings`, `03-surface-propagation`.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

# why this is not fewer sessions

Three sessions would force either broad route propagation into the same plan as shared preference state, or final lifecycle/performance acceptance into an implementation plan. That would hide the main risk introduced by doc `82`: a formerly Feed-only animated background now applies to many independently mounted route surfaces. Keeping the shared widget contract, preference/Settings state, broad surface propagation, and final acceptance separate lets each session end in a verified state and gives later sessions concrete artifacts to refresh against.

# why this is not more sessions

Splitting one session per surface would create bookkeeping without independent closure value because the surfaces should consume one selected-background path, not invent separate behavior. The route propagation session can own the call-site inventory and representative tests while final acceptance owns the broader smoke, performance, overlay, lifecycle, and documentation proof. Settings localization, semantics, telemetry, and failed-save behavior are already established by doc `81`; doc `82` only needs to preserve and retarget them while Settings becomes a selected-background surface.

# regression and gate contract

`Test-Flight-Improv/14-regression-test-strategy.md` says high-blast-radius changes should run the named gates that match touched subsystems plus focused direct tests. For doc `82`, the default regression contract is direct widget/wired/integration coverage around Settings, `AmbientBackground`, Feed, representative non-Feed surfaces, and route smoke. Named gates are conditional:

- Baseline Gate: run when startup, onboarding, QR, or first-route selection changes.
- Feed / Surface Gate: run when Feed route orchestration or feed surface behavior changes beyond merely receiving the selected background preference.
- Posts / Privacy Gate: run only if posts delivery, nearby presence, privacy, or replay behavior changes; this rollout should avoid that.
- Group Messaging Gate: run only if group send, receive, retry, resume, invite, or announcement logic changes; this rollout should avoid that.
- 1:1 Reliability Gate: run only if conversation send, retry, upload, listener, inbox, or feed-to-conversation handoff behavior changes; this rollout should avoid that.
- Completeness Check: run if `Test-Flight-Improv/test-gate-definitions.md`, gate classifications, or durable integration/cross-feature test classifications are edited.

Device-backed or performance evidence may be blocked by simulator availability. A block is acceptable only when the command, device expectation, and exact failure are recorded in the relevant session closure and final doc verdict.

# matrix update contract

No new matrix doc is required. The stable docs to update only when evidence changes are:

- `Test-Flight-Improv/82-app-wide-background-selection.md` for final evidence/status
- `Test-Flight-Improv/82-app-wide-background-selection-session-breakdown.md` for session ledger outcomes and final doc verdict
- `Test-Flight-Improv/02-integration-test-coverage.md` if durable app-wide background coverage or inventory materially changes
- `Test-Flight-Improv/test-gate-definitions.md` only if newly added integration/cross-feature tests need explicit classification

Session `04-acceptance-performance-closure` owns final source-doc, inventory, and coverage-doc closure updates after implementation sessions land. Earlier sessions should update this breakdown ledger and their doc-scoped plan/closure notes as they finish.

# downstream execution path

For every pending session in this breakdown:

1. Create or refresh the doc-scoped session plan with `$implementation-plan-orchestrator`.
2. Execute the plan with `$implementation-execution-qa-orchestrator`.
3. Close the session with `$implementation-closure-audit-orchestrator`.
4. Update this breakdown ledger before moving to the next pending session.

After all runnable sessions are resolved, run one final program-level acceptance/closure pass and persist one of the allowed final doc verdicts in this breakdown.

# session closure outcomes

## Session 01: `01-shared-background-contract`

Outcome: `accepted`.

Implemented `AmbientBackground` so `BackgroundPreference.cosmic` renders `CosmicBackground` without the Feed-only gate while preserving default ambient behavior and reduced-motion static cosmic rendering.

Evidence:

- `flutter test test/features/identity/presentation/widgets/ambient_background_test.dart`
- `flutter test test/features/settings/application/background_preference_use_cases_test.dart`

## Session 02: `02-preference-state-and-settings`

Outcome: `accepted`.

Implemented shared background preference state on `AppShellController`, moved Feed to the shared state source, and made Settings publish loaded/successfully saved preferences while keeping failed saves honest.

Evidence:

- `flutter test test/features/posts/phase1/app_shell_controller_test.dart`
- `flutter test test/features/settings/presentation/widgets/background_choice_control_test.dart`
- `flutter test test/features/settings/presentation/screens/settings_screen_test.dart`
- `flutter test test/features/settings/presentation/screens/settings_wired_test.dart`
- `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "background preference"`

## Session 03: `03-surface-propagation`

Outcome: `accepted`.

Threaded selected background preferences through current shared-background surfaces, startup/pre-identity routing, share routes, QR display/routes, conversation routes, posts, orbit, and group descendants. Static inventory now asserts every current shared-background surface uses `AmbientBackground(` with a `preference:` argument.

Evidence:

- `flutter test test/features/identity/presentation/widgets/ambient_background_test.dart`
- `flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `flutter test test/features/home/presentation/screens/first_time_experience_screen_test.dart`
- `flutter test test/features/identity/presentation/screens/identity_choice_screen_test.dart`
- `flutter test test/features/posts/phase1/posts_screen_test.dart`
- `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "background preference"`

## Session 04: `04-acceptance-performance-closure`

Outcome: `accepted_with_explicit_follow_up`.

Completed source-doc and coverage-doc closure with passing direct tests, passing macOS Settings smoke, and passing macOS Feed performance evidence. Full analyzer status is recorded as nonzero due existing lint/warning debt, with no implementation errors found in the narrowed touched-file analyzer pass.

Evidence:

- `flutter test integration_test/settings_background_choice_smoke_test.dart -d macos`
- `flutter test integration_test/feed_performance_test.dart -d macos`
- `flutter analyze` reported `1706 issues found` across existing repo-wide lint/warning debt.
- Narrowed touched-file `flutter analyze ...` reported no implementation errors but exited nonzero on existing warnings/infos.

Explicit follow-up:

- Run device-backed mobile smoke/performance on one selected iOS or Android target for the Settings background journey.
- Add or run heavy Conversation-specific performance evidence with `Cosmic` selected if release confidence requires a non-Feed chat performance number beyond the passing Conversation widget suite.

# final program verdict

Final verdict: `accepted_with_explicit_follow_up`.

Doc `82` implementation is complete for local behavior and direct/macOS acceptance. Remaining work is explicit evidence-only follow-up for mobile-device and heavy Conversation-specific performance confidence; no additional implementation session is open from this doc.

# reviewer questions

- Is the recommended session count sufficient, too coarse, or too fragmented? Sufficient: four sessions isolate the shared widget contract, app preference/Settings state, broad surface propagation, and final acceptance closure.
- Which proposed sessions should merge? None. Session `02` and Session `03` are coupled but have different closure bars: state source and Settings live feedback versus broad route call-site propagation.
- Which proposed sessions must split? None initially. Session `03` is broad but owns one mechanical selected-background propagation seam and can use static inventory plus representative direct tests rather than one plan per surface.
- What tests or named gates are missing from the decomposition? No named gate is always required; Baseline and Feed gates become required only if the implementation touches their route behavior. Direct non-Feed surface, pre-identity, reduced-motion, rapid navigation, overlay, and performance evidence are explicitly assigned.
- Does each session end in a meaningful verified state? Yes: shared primitive truth, Settings/live state truth, app-wide route propagation, and final acceptance closure.
- Is the matrix-update responsibility assigned clearly? Yes. Session `04` owns final source-doc, coverage inventory, and gate/classification closure; earlier sessions update their plan notes and the breakdown ledger.
- What is the minimum session set that is still safe? Four.

# structural blockers remaining

None for decomposition. The implementation pipeline must still discover the exact state propagation mechanism from current code before editing Session `02`.

# accepted differences intentionally left unchanged

- The breakdown does not prescribe whether the shared state source lives in `AppShellController`, a new focused controller/helper, or a dependency passed through existing constructors. That choice belongs in Session `02` planning after reading current route ownership.
- The breakdown does not require one full route smoke test per surface. It requires a complete audited inventory plus representative route/widget/smoke coverage, matching doc `82`.
- The breakdown does not widen runtime telemetry beyond existing Settings selection attempt/success/failure events.

# exact docs/files used as evidence

- `Test-Flight-Improv/82-app-wide-background-selection.md`
- `Test-Flight-Improv/81-feed-cosmic-background-option-session-breakdown.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/02-integration-test-coverage.md`
- `lib/features/identity/presentation/widgets/ambient_background.dart`
- `test/features/identity/presentation/widgets/ambient_background_test.dart`
- `lib/features/settings/presentation/screens/settings_screen.dart`
- `lib/features/settings/presentation/screens/settings_wired.dart`
- `lib/features/feed/application/app_shell_controller.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `integration_test/settings_background_choice_smoke_test.dart`
- `test/features/settings/presentation/screens/settings_screen_test.dart`
- `test/features/settings/presentation/screens/settings_wired_test.dart`
- current `AmbientBackground(` call-site inventory from `lib/features/**`

# why the decomposition is safe to send into downstream planning/execution

The split is doc-scoped, uses only `Test-Flight-Improv/82-app-wide-background-selection-session-<session-id>-plan.md` plan paths, preserves doc `82` as product intent, records the obsolete doc `81` Feed-only behavior as superseded rather than deleting its evidence, assigns direct tests and conditional named gates by actual blast radius, and leaves final inventory/performance/lifecycle closure to a dedicated acceptance session after implementation has landed.
