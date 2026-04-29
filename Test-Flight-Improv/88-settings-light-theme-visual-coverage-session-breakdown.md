# Decomposition artifact created

- Artifact path: `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-breakdown.md`
- Source doc path: `Test-Flight-Improv/88-settings-light-theme-visual-coverage.md`
- Downstream workflow rule: detailed planning happens one session at a time. Later sessions must be refreshed against landed code, current tests, and current gate definitions before execution.
- Decomposition scope: this artifact belongs only to source doc `88`. It does not execute implementation, create session plans, or change unrelated rollout docs.

# recommended plan count

Recommended plan count: 3

Doc `88` is a focused Settings visual-quality follow-up after the Daylight Lagoon and readable-theme rollouts. The smallest safe split is three sessions: first migrate and prove the lower Settings control cards that still contain fixed dark glass assumptions; then migrate and prove the profile, peer ID, and recovery phrase cards where identity and sensitive-account controls need their own state coverage; then run the complete Settings page journey, optional/debug-section classification, integration or simulator evidence, and closure.

# decomposition artifact

- Artifact path: `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-breakdown.md`
- Proposal or source doc path: `Test-Flight-Improv/88-settings-light-theme-visual-coverage.md`
- Intended plan file pattern: `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-<session-id>-plan.md`
- Downstream workflow rule: each session should next go through `$implementation-plan-orchestrator`, `$implementation-execution-qa-orchestrator`, and `$implementation-closure-audit-orchestrator`. Later sessions must be refreshed against landed code, tests, and any newly classified Settings light-theme evidence before execution.

# overall closure bar

Doc `88` is complete when Settings with `BackgroundPreference.daylightLagoon` is visually coherent from the sticky header through bottom navigation and no user-visible Settings card remains dark-glass-on-light or muted-white-on-light. Profile/avatar editing, background choice, photo and video quality controls, nearby sharing, peer ID copy/copy-confirmed state, recovery phrase hidden/revealed/copy/copied/hide states, optional absence states, and the full all-sections-present scroll state must have direct widget evidence under Daylight Lagoon plus dark-background regression evidence. The Settings background-choice journey must still select Daylight Lagoon, return or remain synchronized, and switch back to a dark/default background without breaking persistence, callbacks, copy behavior, recovery phrase reveal/copy/hide, media-quality callbacks, nearby-sharing toggles, navigation, or bottom navigation. Simulator/device-only visual evidence may remain explicit follow-up only if direct widget and integration evidence are complete and the local environment cannot expose the needed mobile chrome or viewport proof.

# source of truth

Primary docs:

- `Test-Flight-Improv/88-settings-light-theme-visual-coverage.md`
- `Test-Flight-Improv/84-background-readable-theme-extension-session-breakdown.md`
- `Test-Flight-Improv/86-daylight-lagoon-background-option-session-breakdown.md`
- `Test-Flight-Improv/87-app-wide-light-theme-readability-session-03-feed-settings-posts-surfaces-plan.md`
- `Test-Flight-Improv/87-app-wide-light-theme-readability-session-08-acceptance-visual-simulator-closure-plan.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`

Current repo facts governing the split:

- `SettingsScreen` already imports `BackgroundReadableColors`, resolves readable colors for the sticky header, wraps content in `AmbientBackground`, and supports `readableToneOverride` for representative-light tests.
- `BackgroundChoiceControl` already consumes `context.backgroundReadableColors` for its card, option rows, selected state, labels, and error text. Existing tests cover representative-light picker chrome and Daylight selected-state behavior.
- `ImageQualityToggle` still uses fixed `Color.fromRGBO(255, 255, 255, ...)`, fixed dark segmented-control fill, and white/muted-white selected and unselected option copy.
- `PostsNearbySettingsCard` still uses fixed dark glass, white and muted-white text, and an unstyled `Switch.adaptive` without Daylight visual evidence.
- `SettingsPeerIdCard` still uses fixed white/muted-white section label, peer ID, helper text, copy icon, card surface, nested peer ID container, and copy button styling.
- `SettingsRecoveryPhraseCard` still uses fixed white/muted-white section label, card, overlay, word grid, copy/hide controls, word numbers, and hidden/revealed foregrounds.
- `SettingsProfileSection` keeps a fixed dark avatar camera border and white camera icon; its editable username child has behavior tests but needs Daylight visual-state evidence.
- `SettingsIntroductionDebugCard` is passed only when `kDebugMode && introductionRepository != null` in `SettingsWired`, but the widget itself still has fixed dark-theme colors. Its production reachability must be classified before closure.
- Existing Settings widget tests cover rendering and callbacks for profile, peer ID, recovery phrase, media quality, and the Settings screen, but the source doc identifies missing Daylight visual/readability coverage for these lower cards and combined states.
- Existing `integration_test/settings_background_choice_smoke_test.dart` proves the background choice journey, but not complete Settings-page visual coherence across all optional sections.

Disagreement rule:

- current code and tests beat stale prose
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` decide named gate membership
- source doc `88` remains the product intent source unless repo evidence proves a requirement stale or overclaimed

# session ledger

| Session id | Title | Classification | Intended plan file | Depends on | Initial status | Current status | Final execution verdict | Blocker class | Closure docs touched | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| `01-controls-cards` | Media quality and nearby sharing Daylight readable cards | `implementation-ready` | `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-01-controls-cards-plan.md` | none | `pending` | `accepted` | `accepted` | none | `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-breakdown.md`, `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-01-controls-cards-plan.md` | Accepted after `ImageQualityToggle` and `PostsNearbySettingsCard` consumed `BackgroundReadableColors`; focused widget and wired nearby-sharing behavior suites passed. |
| `02-sensitive-profile-cards` | Profile, peer ID, and recovery phrase Daylight readable states | `implementation-ready` | `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-02-sensitive-profile-cards-plan.md` | `01-controls-cards` | `prerequisite-blocked` | `accepted` | `accepted` | none | `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-breakdown.md`, `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-02-sensitive-profile-cards-plan.md` | Accepted after profile, peer ID, and recovery phrase widgets consumed readable roles for Daylight-visible chrome; focused widget suites passed. |
| `03-full-page-acceptance-closure` | Full Settings composition, journey evidence, debug classification, and closure | `acceptance-only` | `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-03-full-page-acceptance-closure-plan.md` | `01-controls-cards`, `02-sensitive-profile-cards` | `prerequisite-blocked` | `accepted_with_explicit_follow_up` | `accepted_with_explicit_follow_up` | none | `Test-Flight-Improv/88-settings-light-theme-visual-coverage.md`, `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-breakdown.md`, `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-03-full-page-acceptance-closure-plan.md`, `Test-Flight-Improv/02-integration-test-coverage.md` | Accepted after full Daylight Settings composition, optional-absence, SettingsWired non-interference, focused Settings batch, and macOS background-choice smoke passed; residual is release-QA visual screenshot evidence only. |

# ordered session breakdown

## Session 01: Media quality and nearby sharing Daylight readable cards

- Session id: `01-controls-cards`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-01-controls-cards-plan.md`
- Exact scope:
  - migrate `ImageQualityToggle` from fixed dark glass, dark segmented fill, white selected labels, muted-white unselected labels, and muted description copy to `BackgroundReadableColors` roles obtained from the ambient readable theme
  - preserve photo and video quality callbacks, selected option logic, option labels, descriptions, layout, and animation behavior
  - migrate `PostsNearbySettingsCard` from fixed dark glass and white/muted-white text to readable surface, border, text, icon/control, and helper roles
  - ensure the nearby sharing `Switch.adaptive` remains visible and understandable in both on and off states under Daylight Lagoon without changing the setting meaning
  - add direct widget evidence for photo quality compressed/original states, video quality compressed/original states, nearby sharing on/off states, and dark-background regression rendering
  - avoid changing Settings persistence, background selection, profile, peer ID, recovery phrase, or nearby-sharing application behavior
- Why it is its own session:
  - these lower control cards share the same low-risk presentation seam and callback tests, and can be accepted before sensitive identity cards are touched
  - this session leaves a meaningful verified state: media and nearby sharing controls no longer visibly carry the dark-theme glass assumptions under Daylight Lagoon
- Likely code-entry files:
  - `lib/features/settings/presentation/widgets/image_quality_toggle.dart`
  - `lib/features/settings/presentation/widgets/posts_nearby_settings_card.dart`
  - `test/features/settings/presentation/widgets/image_quality_toggle_test.dart`
  - `test/features/settings/presentation/screens/settings_wired_posts_nearby_test.dart`
  - `test/features/settings/presentation/screens/settings_screen_test.dart` only if shared helpers or card composition assertions are needed
- Likely direct tests/regressions:
  - `flutter test test/features/settings/presentation/widgets/image_quality_toggle_test.dart`
  - `flutter test test/features/settings/presentation/screens/settings_wired_posts_nearby_test.dart`
  - focused Daylight widget assertions that titles, icons, selected options, unselected options, descriptions, card surfaces, borders, and switch states resolve to readable roles or contrast-safe colors
  - callback regressions proving selected media-quality callbacks and nearby-sharing toggles still fire exactly as before
  - dark-background regression assertions that the same cards remain readable on the dark readable profile
- Likely named gates:
  - none by default; this is Settings-local presentation and widget coverage
  - run `./scripts/run_test_gates.sh posts` only if nearby-sharing implementation unexpectedly touches nearby-post eligibility, delivery, or persistence behavior
  - run `./scripts/run_test_gates.sh completeness-check` only if gate definitions or classification docs are edited
- Matrix/closure docs to update when done:
  - this breakdown ledger and the session `01` plan/closure notes
  - `Test-Flight-Improv/02-integration-test-coverage.md` only if new durable integration coverage is added
- Dependency on earlier sessions: none.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Session 02: Profile, peer ID, and recovery phrase Daylight readable states

- Session id: `02-sensitive-profile-cards`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-02-sensitive-profile-cards-plan.md`
- Exact scope:
  - migrate `SettingsPeerIdCard` from fixed dark glass and fixed white/muted-white copy to readable card, nested peer ID container, section label, peer ID text, helper text, copy button, normal copy icon, and copied check-state roles
  - preserve long peer ID wrapping/readability and copy/copy-confirmed behavior
  - migrate `SettingsRecoveryPhraseCard` from fixed dark glass, hidden overlay, word grid, white/muted-white copy, and copy/hide control styling to readable roles under Daylight Lagoon
  - preserve recovery phrase hidden blur, reveal tap, revealed 12-word grid, word numbers, Copy/Copied, Hide, and warning copy behavior
  - keep warning/accent colors contrast-safe against the Daylight card surface without changing the warning meaning
  - harden `SettingsProfileSection` and its profile/edit affordances under Daylight Lagoon, including avatar camera border/icon contrast and username display/edit state readability
  - add direct widget evidence for normal and copied peer ID states, long peer ID behavior, recovery hidden/revealed/copied states, hide action, profile avatar/camera state, long username, and username editing state
  - avoid changing account identity, clipboard integration, avatar selection, mnemonic reveal/copy semantics, or username update behavior
- Why it is its own session:
  - identity and recovery phrase cards are more sensitive than ordinary controls and need focused state coverage before the full-page acceptance pass
  - this session leaves a meaningful verified state: the important account-safety controls are readable and behavior-preserving under Daylight Lagoon
- Likely code-entry files:
  - `lib/features/settings/presentation/widgets/settings_peer_id_card.dart`
  - `lib/features/settings/presentation/widgets/settings_recovery_phrase_card.dart`
  - `lib/features/settings/presentation/widgets/settings_profile_section.dart`
  - `lib/features/home/presentation/widgets/editable_username_widget.dart` only if Daylight evidence proves the child widget needs role-backed adjustments
  - `test/features/settings/presentation/widgets/settings_peer_id_card_test.dart`
  - `test/features/settings/presentation/widgets/settings_recovery_phrase_card_test.dart`
  - `test/features/settings/presentation/widgets/settings_profile_section_test.dart`
  - existing direct tests for `EditableUsernameWidget` if touched
- Likely direct tests/regressions:
  - `flutter test test/features/settings/presentation/widgets/settings_peer_id_card_test.dart`
  - `flutter test test/features/settings/presentation/widgets/settings_recovery_phrase_card_test.dart`
  - `flutter test test/features/settings/presentation/widgets/settings_profile_section_test.dart`
  - focused Daylight assertions for section labels, card surfaces, nested containers, monospaced text, helper text, buttons, icons, word numbers, word cells, hidden overlay text/icon, warning copy, copied states, and hide action
  - callback regressions proving peer ID copy, recovery reveal/copy/hide, avatar pick, and username submit behavior still work
  - dark-background regression assertions for the same sensitive states
- Likely named gates:
  - none by default; this is Settings-local presentation and widget behavior
  - no `1to1`, `intro`, `posts`, `groups`, or `transport` gate unless implementation unexpectedly changes messaging, introduction, post, group, or network behavior
  - run `./scripts/run_test_gates.sh completeness-check` only if gate definitions or classification docs are edited
- Matrix/closure docs to update when done:
  - this breakdown ledger and the session `02` plan/closure notes
  - `Test-Flight-Improv/02-integration-test-coverage.md` only if durable coverage inventory changes materially
- Dependency on earlier sessions: `01-controls-cards`.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Session 03: Full Settings composition, journey evidence, debug classification, and closure

- Session id: `03-full-page-acceptance-closure`
- Session classification: `acceptance-only`
- Intended plan file: `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-03-full-page-acceptance-closure-plan.md`
- Exact scope:
  - validate the combined Settings page after Sessions `01` and `02`
  - add or tighten full `SettingsScreen` widget evidence for Daylight Lagoon with every optional user-visible section present: profile, background picker, photo quality, video quality, nearby sharing, peer ID, recovery phrase hidden and revealed states, copied states, and bottom navigation
  - add or tighten full `SettingsScreen` evidence for optional sections absent, including no peer ID, no mnemonic, no media-quality callbacks, and no nearby-sharing callback
  - prove sticky header, scroll content, bottom navigation, long username, long peer ID, selected-state copy, save-error copy, disabled/empty states, and dark-background regression rendering remain coherent
  - verify `SettingsIntroductionDebugCard` reachability. If it is debug-only as current `SettingsWired` suggests, record that classification and add targeted evidence only if the debug section is used in accepted local/dev flows; if the plan finds it user-reachable, migrate it to readable roles and add direct Daylight evidence in this session
  - run or extend `settings_background_choice_smoke_test.dart` so the Settings background-choice journey still works for selecting Daylight Lagoon and switching back to a dark/default background, or record the exact environment block if device-backed integration cannot run
  - run final focused Settings widget suites from Sessions `01` and `02`
  - update source doc `88`, this breakdown ledger, and stable coverage or gate docs only where final evidence requires it
  - record explicit follow-up only for simulator/device-specific visual proof that cannot be collected locally, such as physical safe-area chrome, platform switch rendering, keyboard placement, or route-transition screenshots
- Why it is its own session:
  - full-page visual coherence and journey evidence can only be trusted after the individual card migrations and direct tests have landed
  - this session prevents final acceptance from being scattered across implementation sessions or from overclaiming simulator-only evidence
- Likely code-entry files:
  - `lib/features/settings/presentation/screens/settings_screen.dart`
  - `lib/features/settings/presentation/screens/settings_wired.dart`
  - `lib/features/settings/presentation/widgets/settings_introduction_debug_card.dart` only if current evidence proves it needs migration or direct debug-flow acceptance
  - `test/features/settings/presentation/screens/settings_screen_test.dart`
  - `test/features/settings/presentation/screens/settings_wired_test.dart`
  - `integration_test/settings_background_choice_smoke_test.dart`
  - final direct suites from Sessions `01` and `02`
  - `Test-Flight-Improv/88-settings-light-theme-visual-coverage.md`
  - `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-breakdown.md`
  - `Test-Flight-Improv/02-integration-test-coverage.md` only if durable coverage inventory changes materially
  - `Test-Flight-Improv/test-gate-definitions.md` only if new integration or cross-feature tests need classification
- Likely direct tests/regressions:
  - final direct batch from Sessions `01` and `02`
  - `flutter test test/features/settings/presentation/screens/settings_screen_test.dart`
  - `flutter test test/features/settings/presentation/screens/settings_wired_test.dart`
  - `flutter test integration_test/settings_background_choice_smoke_test.dart -d <device>` or the repo's established device-backed command, with an explicit environment block if no device is available
  - full-page widget assertions for Daylight all-sections-present and optional-sections-absent states
  - smoke or widget assertions for Daylight selected-state persistence, save-error readability, switch-back-to-dark readability, and navigation/back controls
- Likely named gates:
  - direct Settings suites are primary
  - `./scripts/run_test_gates.sh baseline` only if implementation touches startup, app bootstrap, QR, or first-time experience wiring
  - `./scripts/run_test_gates.sh feed` only if the Settings-to-Feed journey changes Feed route orchestration beyond the existing background-choice smoke
  - `./scripts/run_test_gates.sh posts` only if nearby-sharing work unexpectedly touches post eligibility, delivery, or persistence behavior
  - `./scripts/run_test_gates.sh completeness-check` if new integration or cross-feature tests are added or gate docs are edited
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/88-settings-light-theme-visual-coverage.md`
  - `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-breakdown.md`
  - `Test-Flight-Improv/02-integration-test-coverage.md` only if durable Settings/background coverage inventory changes materially
  - `Test-Flight-Improv/test-gate-definitions.md` only if newly added integration or cross-feature tests need explicit classification
- Dependency on earlier sessions: `01-controls-cards`, `02-sensitive-profile-cards`.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

# why this is not fewer sessions

One or two sessions would either put every Settings card migration, sensitive recovery-state proof, and full-page acceptance into one broad task, or combine sensitive account controls with final journey evidence before lower-card regressions are isolated. That would make it easy to miss copy/copy-confirmed, reveal/hide, switch, selected/unselected, or optional-section states while still claiming the full page looks coherent.

# why this is not more sessions

Splitting photo quality from video quality, or peer ID from recovery phrase, would create bookkeeping without independent acceptance value. The affected widgets are all Settings-local presentation surfaces that should share the same readable-role approach and focused tests. Debug-section treatment should not be pre-split until Session `03` verifies whether it is user-reachable beyond debug/local flows.

# regression and gate contract

- Direct Settings widget tests are the primary regression vehicle for this doc.
- Named gates are not required by default because the intended work is presentation-only and Settings-local.
- The Posts gate applies only if nearby-sharing implementation touches nearby-post eligibility, delivery, or persistence behavior.
- The Feed gate applies only if Settings-to-Feed route orchestration changes beyond the existing background-choice smoke path.
- Baseline applies only if implementation touches startup, QR, first-time experience, app bootstrap, or other baseline-owned wiring.
- `1to1`, `groups`, `intro`, `transport`, and runtime telemetry gates are out of scope unless implementation unexpectedly changes those subsystems.
- `./scripts/run_test_gates.sh completeness-check` is required if new integration or cross-feature tests are added, or if `Test-Flight-Improv/test-gate-definitions.md` is edited.

# matrix update contract

- Session `01` updates this ledger and its plan/closure notes after media-quality and nearby-sharing card evidence lands.
- Session `02` updates this ledger and its plan/closure notes after profile, peer ID, and recovery phrase evidence lands.
- Session `03` owns final source-doc closure, final breakdown verdict, debug-section classification, durable coverage inventory updates if any, and gate-doc classification if any new integration or cross-feature tests are added.

# downstream execution path

For each session, run:

1. `$implementation-plan-orchestrator`
2. `$implementation-execution-qa-orchestrator`
3. `$implementation-closure-audit-orchestrator`

Later sessions must refresh their plan against landed code, current tests, and current gate definitions before execution.

# reviewer pass

- Recommended session count sufficient: yes, because each session ends in a meaningful verified state and the split follows real Settings UI risk boundaries.
- Too coarse: no. Session `03` is acceptance-focused and should only reopen implementation if final evidence exposes a real Settings light-theme regression.
- Too fragmented: no. The sessions avoid splitting nearly identical card-state migrations into low-value fragments.
- Sessions that should merge: none.
- Sessions that must split: none at decomposition time. If Session `03` proves the debug introduction card is user-reachable and too large to handle inside closure, it should record a concrete follow-up rather than pre-splitting now.
- Missing tests or named gates: no named gates are mandatory by default; direct Settings widget suites plus the background-choice smoke are mandatory.
- Meaningful verified state: yes for all three sessions.
- Matrix-update responsibility: final durable coverage and closure updates belong to Session `03`.

# arbiter

- Structural blockers: none.
- Mergeable sessions: none.
- Required splits: none.
- Accepted differences:
  - The exact readable-color role mapping for each card is left to session planning, but every background-sensitive foreground, border, surface, icon, overlay, helper, selected, disabled, copied, hidden, and revealed state must be covered or explicitly classified.
  - The exact simulator/device evidence can be accepted as explicit follow-up only when direct widget and integration proof is complete and the local environment cannot expose that visual condition.
  - `SettingsIntroductionDebugCard` is treated as an evidence question, not mandatory production-user scope, until Session `03` verifies current reachability.

# structural blockers remaining

None.

# final program verdict

Final program verdict: `accepted_with_explicit_follow_up`

Doc `88` is accepted with explicit release-QA visual follow-up only. Sessions `01` and `02` closed the card-level implementation gaps. Session `03` closed full Settings composition, optional-absence behavior, Daylight background-choice journey smoke, and direct non-interference proof that background selection does not call P2P start/stop/reinitialize/dial paths.

Verification summary:

- `flutter test test/features/settings/presentation/widgets/image_quality_toggle_test.dart` passed.
- `flutter test test/features/settings/presentation/widgets/posts_nearby_settings_card_test.dart` passed.
- `flutter test test/features/settings/presentation/screens/settings_wired_posts_nearby_test.dart` passed.
- `flutter test test/features/settings/presentation/widgets/settings_peer_id_card_test.dart` passed.
- `flutter test test/features/settings/presentation/widgets/settings_recovery_phrase_card_test.dart` passed.
- `flutter test test/features/settings/presentation/widgets/settings_profile_section_test.dart` passed.
- `flutter test test/features/settings/presentation/screens/settings_screen_test.dart` passed.
- `flutter test test/features/settings/presentation/screens/settings_wired_test.dart` passed.
- Combined focused Settings batch passed.
- `flutter test integration_test/settings_background_choice_smoke_test.dart -d macos` passed after the no-device-selector attempt reported multiple available devices.

Explicit follow-up:

- Physical-device/simulator screenshot evidence for safe area, platform switch native rendering, keyboard placement, route transitions, and system chrome remains release-QA visual evidence. No repo-owned implementation or direct-test gap remains open.
