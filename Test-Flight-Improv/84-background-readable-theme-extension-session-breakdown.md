# Decomposition artifact updated

- Artifact path: `Test-Flight-Improv/84-background-readable-theme-extension-session-breakdown.md`
- Source doc path: `Test-Flight-Improv/84-background-readable-theme-extension.md`
- Downstream workflow rule: detailed planning happens one session at a time. Later sessions must be refreshed against landed code, current tests, and current gate definitions before execution.
- Decomposition scope: this artifact belongs only to source doc `84`. It does not execute implementation, create session plans, or change unrelated rollout docs.

# recommended plan count

Recommended plan count: 5

Doc `84` extends the already-landed app-wide selected-background path from docs `82` and `83`. The smallest safe rollout is five sessions because the work spans five different risks: a new readable-color contract and contrast/system-chrome resolver, wiring that contract to selected background state without breaking Settings save honesty, converting the highest-traffic Settings and Feed surfaces, converting representative conversation/group/orbit/overlay surfaces, and then closing the static inventory, integration, performance, and docs evidence.

# decomposition artifact

- Artifact path: `Test-Flight-Improv/84-background-readable-theme-extension-session-breakdown.md`
- Proposal or source doc path: `Test-Flight-Improv/84-background-readable-theme-extension.md`
- Intended plan file pattern: `Test-Flight-Improv/84-background-readable-theme-extension-session-<session-id>-plan.md`
- Downstream workflow rule: each session should next go through `$implementation-plan-orchestrator`, `$implementation-execution-qa-orchestrator`, and `$implementation-closure-audit-orchestrator`. Later sessions must be refreshed against landed code, tests, and any newly classified readable-color inventory before execution.

# overall closure bar

Doc `84` is complete when the app has an app-owned readable-color `ThemeExtension` with the minimum roles from the source doc; readable colors and system chrome resolve from `BackgroundPreference`; current dark backgrounds (`Default`, `Cosmic`, and mirrored cosmic when present) keep readable light foreground treatment; a representative light-background selected state exercises the same resolver path and supplies dark readable foregrounds, adaptive surfaces, borders, glass, scrims, input roles, disabled roles, and dark system-bar icons; Settings save success and failure keep the visible background, selected state, readable theme, and system chrome synchronized with the last confirmed preference; Settings, Feed, Conversation, and at least one Group or Orbit surface render representative content legibly under both dark and representative light readable themes; representative overlays, dialogs, sheets, pickers, loading states, inputs, and disabled states use readable roles or are explicitly proven background-independent; a static inventory classifies all shared-background foreground, border, surface, glass, scrim, input, and icon colors as background-aware or background-independent with contrast evidence; Feed performance remains inside the source doc's concrete frame budgets when readable colors touch Feed rendering paths; and final docs record exact direct, integration, performance, inventory, and any simulator/device-only evidence gaps.

# source of truth

Primary docs:

- `Test-Flight-Improv/84-background-readable-theme-extension.md`
- `Test-Flight-Improv/82-app-wide-background-selection-session-breakdown.md`
- `Test-Flight-Improv/83-mirrored-cosmic-background-option-session-breakdown.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/02-integration-test-coverage.md`

Current repo facts governing the split:

- `AppTheme.darkTheme` is still a dark `ThemeData` without an app-owned readable-color `ThemeExtension`.
- `AppColors` remains a dark palette with black background, white text, muted-white text, and red/green glow colors.
- `BackgroundPreference` currently contains `defaultBackground`, `cosmic`, and `cosmicMirrored`, with null or unknown stored values falling back to `defaultBackground`.
- `AmbientBackground` currently switches the visual background for default, cosmic, and mirrored cosmic preferences, but does not provide a matching readable foreground/surface theme to descendants.
- A search for `ThemeExtension`, `extension<`, `BackgroundReadable`, and `Readable` found no production readable-color extension; matches were unrelated integration-test helper names.
- App-wide shared-background propagation from docs `82` and `83` should be reused rather than rebuilt.
- Existing widget tests already inventory shared-background surfaces in `test/features/identity/presentation/widgets/ambient_background_test.dart`.
- Existing Settings-to-Feed smoke and Feed performance tests are the relevant integration/performance harnesses for final acceptance.
- Hard-coded white, muted-white, black, dark-card, white-border, glass, scrim, input, loading, and icon colors remain spread across shared-background surfaces and must either become readable-theme-backed or be classified as background-independent with contrast evidence.

Disagreement rule:

- current code and tests beat stale prose
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` decide named gate membership
- source doc `84` remains the product intent source unless repo evidence proves a requirement stale or overclaimed

# session ledger

| Session id | Title | Classification | Intended plan file | Depends on | Current status |
|---|---|---|---|---|---|
| `01-readable-theme-contract` | Readable color extension, contrast roles, and system chrome resolver | `implementation-ready` | `Test-Flight-Improv/84-background-readable-theme-extension-session-01-readable-theme-contract-plan.md` | None | `accepted` |
| `02-selected-theme-propagation` | Selected-background readable-theme propagation and Settings save honesty | `implementation-ready` | `Test-Flight-Improv/84-background-readable-theme-extension-session-02-selected-theme-propagation-plan.md` | `01-readable-theme-contract` | `accepted` |
| `03-settings-feed-readable-surfaces` | Settings and Feed readable-surface migration | `implementation-ready` | `Test-Flight-Improv/84-background-readable-theme-extension-session-03-settings-feed-readable-surfaces-plan.md` | `01-readable-theme-contract`, `02-selected-theme-propagation` | `accepted_with_explicit_follow_up` |
| `04-conversation-groups-overlays-readable-surfaces` | Conversation, Group or Orbit, and transient overlay readable-surface migration | `implementation-ready` | `Test-Flight-Improv/84-background-readable-theme-extension-session-04-conversation-groups-overlays-readable-surfaces-plan.md` | `01-readable-theme-contract`, `02-selected-theme-propagation`, `03-settings-feed-readable-surfaces` | `accepted_with_explicit_follow_up` |
| `05-acceptance-performance-inventory-closure` | Integration, performance, inventory, and docs closure | `acceptance-only` | `Test-Flight-Improv/84-background-readable-theme-extension-session-05-acceptance-performance-inventory-closure-plan.md` | `01-readable-theme-contract`, `02-selected-theme-propagation`, `03-settings-feed-readable-surfaces`, `04-conversation-groups-overlays-readable-surfaces` | `accepted_with_explicit_follow_up` |

# ordered session breakdown

## Session 01: Readable color extension, contrast roles, and system chrome resolver

- Session id: `01-readable-theme-contract`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/84-background-readable-theme-extension-session-01-readable-theme-contract-plan.md`
- Exact scope:
  - add an app-owned readable-color `ThemeExtension` with at least `textPrimary`, `textSecondary`, `textMuted`, `iconPrimary`, `iconSecondary`, `iconMuted`, `surfaceBase`, `surfaceRaised`, `surfaceSubtle`, `glassSurface`, `glassBorder`, `border`, `divider`, `overlayScrim`, `inputFill`, `inputBorder`, `placeholderText`, `disabledForeground`, `disabledSurface`, `statusBarIconBrightness`, and `navigationBarIconBrightness`
  - add a resolver that maps `BackgroundPreference` to readable-color profiles, preserving light foreground treatment for all current dark backgrounds
  - add a representative light-background readable profile or test-only fixture that exercises the same resolver path future light preferences will use, without exposing an unfinished production background option unless a later plan intentionally chooses that route
  - add a system chrome style resolver tied to the readable profile and selected background preference
  - add contrast helper/test utilities only where needed to prove the minimum roles meet the source doc's `4.5:1` text and `3:1` icon/control/surface expectations against dark and representative light effective surfaces
  - avoid converting screen widgets in this session except for compile-safe imports or extension registration
- Why it is its own session:
  - the shared contract and contrast math need stable unit coverage before broad UI surfaces depend on it
  - this session leaves a meaningful verified state: the app can resolve readable palettes and system-bar brightness for every current preference plus a representative light profile
- Likely code-entry files:
  - `lib/core/theme/app_theme.dart`
  - `lib/core/theme/app_colors.dart`
  - a new `lib/core/theme/background_readable_colors.dart`
  - a new `lib/core/theme/background_readable_color_resolver.dart` or equivalent focused resolver
  - `lib/features/settings/domain/models/background_preference.dart` only if a non-user-visible representative light fixture is implemented as an enum value; avoid this unless planning proves it is the cleanest path
  - `test/core/theme/background_readable_colors_test.dart`
  - `test/core/theme/background_readable_color_resolver_test.dart`
- Likely direct tests/regressions:
  - `flutter test test/core/theme/background_readable_colors_test.dart`
  - `flutter test test/core/theme/background_readable_color_resolver_test.dart`
  - unit assertions for default, cosmic, mirrored cosmic, missing/unknown fallback behavior through the existing preference parser, and representative light mapping
  - unit assertions for status/navigation icon brightness on dark vs representative light profiles
  - contrast assertions for every minimum role against its intended effective dark and representative light surfaces
- Likely named gates:
  - none by default; this is core theme unit coverage
  - run `./scripts/run_test_gates.sh completeness-check` only if gate definitions or classification docs are edited
- Matrix/closure docs to update when done:
  - this breakdown ledger and the session `01` plan/closure notes
  - `Test-Flight-Improv/02-integration-test-coverage.md` only if durable coverage inventory changes materially
- Dependency on earlier sessions: none.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Session 02: Selected-background readable-theme propagation and Settings save honesty

- Session id: `02-selected-theme-propagation`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/84-background-readable-theme-extension-session-02-selected-theme-propagation-plan.md`
- Exact scope:
  - inject the readable-color extension at the selected-background boundary so `AmbientBackground` descendants receive the readable profile that matches the same `BackgroundPreference` used for the visual background
  - ensure switching preferences updates background visual, readable theme, and system chrome together for already-mounted shared-background surfaces
  - add or update an `AnnotatedRegion<SystemUiOverlayStyle>` or equivalent platform chrome hook so dark backgrounds resolve light system icons and representative light backgrounds resolve dark system icons where Flutter exposes them
  - preserve Settings save honesty: on failed background save, the last confirmed preference wins for visible background, selected-state copy, readable theme, and system chrome while Settings shows the recoverable failure state
  - preserve null and unknown stored preference fallback to the default dark readable treatment
  - avoid broad screen color migrations except for minimal assertions that descendants can read the selected extension
- Why it is its own session:
  - propagation and failed-save synchronization are state-boundary concerns, distinct from the palette contract and broad surface migration
  - this session leaves a meaningful verified state: selected background and selected readable colors move together even before all surfaces have consumed every role
- Likely code-entry files:
  - `lib/features/identity/presentation/widgets/ambient_background.dart`
  - `lib/features/feed/application/app_shell_controller.dart`
  - `lib/features/settings/presentation/screens/settings_screen.dart`
  - `lib/features/settings/presentation/screens/settings_wired.dart`
  - any shared app-shell or route wrapper that already carries selected `BackgroundPreference`
  - `test/features/identity/presentation/widgets/ambient_background_test.dart`
  - `test/features/settings/presentation/screens/settings_screen_test.dart`
  - `test/features/settings/presentation/screens/settings_wired_test.dart`
  - `test/features/posts/phase1/app_shell_controller_test.dart`
- Likely direct tests/regressions:
  - `flutter test test/features/identity/presentation/widgets/ambient_background_test.dart`
  - `flutter test test/features/settings/presentation/screens/settings_screen_test.dart`
  - `flutter test test/features/settings/presentation/screens/settings_wired_test.dart`
  - `flutter test test/features/posts/phase1/app_shell_controller_test.dart`
  - widget assertions that default/cosmic/mirrored descendants receive the dark readable extension
  - widget assertions that representative light selection receives the light readable extension through the same boundary
  - failed-save assertions that visual background, selected state, readable extension, and system chrome roll back or remain on the last confirmed value together
  - rapid-switching assertions that no stale foreground palette remains after a later selected preference wins
- Likely named gates:
  - none by default for theme propagation and Settings-local save honesty
  - `./scripts/run_test_gates.sh feed` only if Feed route orchestration changes beyond consuming the existing selected-background state
  - run `./scripts/run_test_gates.sh completeness-check` only if gate definitions or classification docs are edited
- Matrix/closure docs to update when done:
  - this breakdown ledger and the session `02` plan/closure notes
  - `Test-Flight-Improv/02-integration-test-coverage.md` only if durable Settings/background coverage changes materially
- Dependency on earlier sessions: `01-readable-theme-contract`.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Session 03: Settings and Feed readable-surface migration

- Session id: `03-settings-feed-readable-surfaces`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/84-background-readable-theme-extension-session-03-settings-feed-readable-surfaces-plan.md`
- Exact scope:
  - replace background-sensitive hard-coded foreground, icon, border, glass, scrim, surface, loading, input, placeholder, and disabled colors on Settings and Feed shared-background surfaces with readable-theme roles
  - keep existing product accents, typography, layout, navigation, media quality, nearby sharing, post, transport, notification, and identity behavior unchanged unless a specific color is proven background-sensitive
  - cover Settings header, back controls, background picker selected state, failure copy, localized labels, controls, disabled states, and semantics clarity
  - cover Feed empty/loading states, Feed cards or surfaces touched by the implementation, borders, loading bars, text/icon colors, and any visible input or overlay state owned by the Feed surface
  - add representative dark and light readable-theme widget coverage for Settings and Feed
  - preserve existing dark `Default`, `Cosmic`, and mirrored cosmic appearance unless a small role-backed difference is required for consistency and passes current dark-background expectations
- Why it is its own session:
  - Settings and Feed are the highest-traffic surfaces and have direct acceptance requirements, but their tests and visual states are narrower than Conversation/groups/overlays
  - this session leaves a meaningful verified state: two core selected-background surfaces consume the readable theme on both dark and representative light profiles
- Likely code-entry files:
  - `lib/features/settings/presentation/screens/settings_screen.dart`
  - `lib/features/settings/presentation/widgets/background_choice_control.dart`
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart` only if tests need selected theme plumbing
  - shared Settings/Feed widgets used by these screens
  - `test/features/settings/presentation/screens/settings_screen_test.dart`
  - `test/features/settings/presentation/widgets/background_choice_control_test.dart`
  - `test/features/settings/presentation/screens/settings_wired_test.dart`
  - `test/features/feed/presentation/screens/feed_screen_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/identity/presentation/widgets/ambient_background_test.dart` if the shared inventory or wrapper assertions need tightening
- Likely direct tests/regressions:
  - `flutter test test/features/settings/presentation/screens/settings_screen_test.dart`
  - `flutter test test/features/settings/presentation/widgets/background_choice_control_test.dart`
  - `flutter test test/features/settings/presentation/screens/settings_wired_test.dart`
  - `flutter test test/features/feed/presentation/screens/feed_screen_test.dart`
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
  - contrast or widget assertions for representative Settings and Feed text, icons, surfaces, borders, loading states, selected states, disabled states, and input/hint colors under dark and representative light profiles
  - localization assertions for English, German, and Arabic background option labels and selected-state copy when readable colors are active
- Likely named gates:
  - no named gate by default for feature-local widget migration
  - `./scripts/run_test_gates.sh feed` if Feed card/composer/handoff behavior changes beyond color roles, which should be avoided
  - run `./scripts/run_test_gates.sh completeness-check` only if gate definitions or classification docs are edited
- Matrix/closure docs to update when done:
  - this breakdown ledger and the session `03` plan/closure notes
  - `Test-Flight-Improv/02-integration-test-coverage.md` only if durable Feed/Settings coverage changes materially
- Dependency on earlier sessions: `01-readable-theme-contract`, `02-selected-theme-propagation`.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Session 04: Conversation, Group or Orbit, and transient overlay readable-surface migration

- Session id: `04-conversation-groups-overlays-readable-surfaces`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/84-background-readable-theme-extension-session-04-conversation-groups-overlays-readable-surfaces-plan.md`
- Exact scope:
  - convert representative Conversation header/content controls and one Group or Orbit shared-background surface to readable-theme roles for background-sensitive foreground, icon, surface, border, glass, scrim, input, placeholder, disabled, and divider colors
  - cover representative transient UI required by the source doc, such as dialogs, bottom sheets, media pickers, message overlays, or loading states, using the smallest set of surfaces that proves the shared roles work over dark and representative light backgrounds
  - classify any remaining hard-coded foreground/surface colors encountered in these representative surfaces as background-aware or background-independent with contrast evidence
  - keep message send, retry, upload, inbox, group delivery, post delivery, introduction, notification, transport, and persistence behavior unchanged
  - add widget or visual coverage for Conversation and at least one Group or Orbit surface with both dark and representative light readable themes
  - add overlay/transient-state coverage that proves meaningful text, icons, borders, and disabled/hint states remain legible
- Why it is its own session:
  - Conversation, Group/Orbit, and transient overlays have different state setup and regression risk from Settings/Feed
  - this session leaves a meaningful verified state: representative content-heavy and non-Feed surfaces are readable without widening messaging or transport behavior
- Likely code-entry files:
  - `lib/features/conversation/presentation/widgets/conversation_header.dart`
  - `lib/features/conversation/presentation/screens/conversation_screen.dart`
  - representative overlay, dialog, sheet, picker, media, or loading widgets used by Conversation or shared-background surfaces
  - one or more of:
    - `lib/features/orbit/presentation/screens/orbit_screen.dart`
    - `lib/features/groups/presentation/screens/group_list_screen.dart`
    - `lib/features/groups/presentation/screens/group_conversation_screen.dart`
    - `lib/features/groups/presentation/screens/group_info_screen.dart`
  - `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  - direct tests for `conversation_header` or overlay widgets if they already exist or are easy to add
  - representative group or Orbit widget tests selected during planning
  - `test/features/identity/presentation/widgets/ambient_background_test.dart` if shared inventory classifications are updated
- Likely direct tests/regressions:
  - `flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart`
  - focused header/overlay widget tests if added
  - representative group or Orbit widget tests selected by the plan
  - widget assertions for dark and representative light readable themes across Conversation and the chosen Group or Orbit surface
  - widget assertions for dialogs/sheets/pickers/overlays/loading states under dark and representative light profiles
  - direct contrast assertions for non-text icons, meaningful borders, focus/selection indicators, disabled states, hints, and graphical UI components where practical
- Likely named gates:
  - no `1to1`, `groups`, `posts`, `intro`, or `transport` gate by default because this session should only change presentation color roles
  - run `./scripts/run_test_gates.sh 1to1` if conversation send, retry, upload, listener, inbox, or handoff behavior changes unexpectedly
  - run `./scripts/run_test_gates.sh groups` if group send/receive/retry/resume/invite/announcement behavior changes unexpectedly
  - run `./scripts/run_test_gates.sh completeness-check` only if gate definitions or classification docs are edited
- Matrix/closure docs to update when done:
  - this breakdown ledger and the session `04` plan/closure notes
  - `Test-Flight-Improv/02-integration-test-coverage.md` only if durable Conversation, Group, Orbit, or overlay coverage changes materially
  - `Test-Flight-Improv/test-gate-definitions.md` only if new integration/cross-feature tests need classification
- Dependency on earlier sessions: `01-readable-theme-contract`, `02-selected-theme-propagation`, `03-settings-feed-readable-surfaces`.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Session 05: Integration, performance, inventory, and docs closure

- Session id: `05-acceptance-performance-inventory-closure`
- Session classification: `acceptance-only`
- Intended plan file: `Test-Flight-Improv/84-background-readable-theme-extension-session-05-acceptance-performance-inventory-closure-plan.md`
- Exact scope:
  - validate the combined readable-theme rollout after Sessions `01` through `04`
  - run or extend Settings-to-Feed integration coverage so changing a background preference updates both the visual background and readable foreground treatment together, including bidirectional dark-to-representative-light and light-to-dark paths where the representative light state is testable
  - run or record exact environment blocks for Feed performance with background-aware readable colors active, using the source doc's average build under `8ms`, P99 under `24ms`, worst under `100ms`, or selected-background comparison budget of average below `max(8ms, default + 2ms)`, P99 below `max(24ms, default * 1.25)`, and worst below `max(100ms, default * 1.25)`
  - complete the static or reviewed inventory for all current shared-background foreground, border, surface, glass, scrim, input, and icon colors, classifying each as background-aware or background-independent with evidence
  - verify missing and unknown stored preferences still use the default dark readable treatment
  - verify rapid switching, reduced-motion selected backgrounds, localized English/German/Arabic Settings builds, and assistive semantics remain readable and non-color-only where covered by direct tests
  - update source doc `84`, this breakdown ledger, `Test-Flight-Improv/02-integration-test-coverage.md`, and gate definitions only where final evidence requires it
  - record exact command, platform, and environment failure for simulator/device-only acceptance that cannot run locally
- Why it is its own session:
  - integration, performance, inventory, and documentation closure are meaningful only after the contract, propagation, and representative surfaces are implemented
  - this prevents the source doc from closing on unit/widget evidence alone while integration and inventory gaps remain
- Likely code-entry files:
  - `integration_test/settings_background_choice_smoke_test.dart`
  - `integration_test/feed_performance_test.dart`
  - any focused integration or widget inventory tests added by earlier sessions
  - `test/features/identity/presentation/widgets/ambient_background_test.dart`
  - `test/features/settings/presentation/screens/settings_wired_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  - representative Group or Orbit tests selected in Session `04`
  - `Test-Flight-Improv/84-background-readable-theme-extension.md`
  - `Test-Flight-Improv/84-background-readable-theme-extension-session-breakdown.md`
  - `Test-Flight-Improv/02-integration-test-coverage.md`
  - `Test-Flight-Improv/test-gate-definitions.md` only if new integration/cross-feature tests need classification
- Likely direct tests/regressions:
  - final direct batch from Sessions `01` through `04`
  - `flutter test integration_test/settings_background_choice_smoke_test.dart -d <device>` or the repo's established host/device fallback
  - `flutter test integration_test/feed_performance_test.dart -d <device>` or a documented performance fallback
  - static inventory command(s), likely based on `rg`, proving every relevant hard-coded foreground/surface color is either converted or classified
  - analyzer or narrowed analyzer pass if shared theme files, generated l10n, route constructors, or broad presentation widgets changed
- Likely named gates:
  - direct tests are primary
  - `./scripts/run_test_gates.sh baseline` if final smoke or implementation changed startup, QR, first-time, or app bootstrap wiring
  - `./scripts/run_test_gates.sh feed` if Feed route orchestration, cards, composer, inline reply, or feed-to-conversation handoff behavior changed
  - `./scripts/run_test_gates.sh groups` only if group behavior changed beyond presentation colors
  - no `1to1` gate unless conversation send, retry, upload, listener, inbox, or handoff behavior changed
  - run `./scripts/run_test_gates.sh completeness-check` if gate definitions or classification docs are edited
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/84-background-readable-theme-extension.md`
  - `Test-Flight-Improv/84-background-readable-theme-extension-session-breakdown.md`
  - `Test-Flight-Improv/02-integration-test-coverage.md`
  - `Test-Flight-Improv/test-gate-definitions.md` only if new integration/cross-feature tests are added
- Dependency on earlier sessions: `01-readable-theme-contract`, `02-selected-theme-propagation`, `03-settings-feed-readable-surfaces`, `04-conversation-groups-overlays-readable-surfaces`.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

# why this is not fewer sessions

Fewer sessions would merge contract, propagation, and broad surface migration into one oversized implementation pass. That would make it hard to separate contrast math failures from state-boundary failures, and it would invite broad color churn across Feed, Settings, Conversation, groups, overlays, and performance evidence before the shared roles are stable. Keeping final acceptance separate also prevents the rollout from closing while the static hard-coded-color inventory or Feed performance budget is still unproven.

# why this is not more sessions

More sessions would mostly split the same readable-theme surface migration by individual widget or route. That would add bookkeeping without independent closure value because the source doc only requires representative Settings, Feed, Conversation, and one Group or Orbit surface before full inventory/acceptance closure. Product accents and already background-independent colors should be classified during the relevant surface or final inventory sessions rather than turned into separate implementation sessions.

# regression and gate contract

`Test-Flight-Improv/14-regression-test-strategy.md` applies by using direct feature tests first and named gates only when the changed seam crosses a gate boundary. For doc `84`:

- Core theme resolver and contrast coverage are direct unit tests.
- `AmbientBackground`, Settings, Feed, Conversation, and representative Group/Orbit widget tests are the primary regression family for readable-theme propagation and surface migration.
- Integration smoke and performance checks belong to Session `05` after contract, propagation, and representative surfaces land.
- Named gates are conditional. `baseline` applies if startup, QR, first-time, or bootstrap wiring changes; `feed` applies if Feed route orchestration, cards, composer, inline reply, or feed-to-conversation handoff behavior changes; `groups` applies only if group messaging behavior changes beyond presentation colors; `1to1` applies only if conversation send, retry, upload, listener, inbox, or handoff behavior changes; `posts`, `intro`, and `transport` are not expected for a presentation-theme rollout.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` remain the source of truth for gate membership. Edit gate definitions only when new integration/cross-feature tests need classification, and keep `./scripts/run_test_gates.sh completeness-check` green after such edits.

# matrix update contract

Use existing stable coverage and closure docs rather than creating a new matrix document unless planning proves no existing doc can hold the evidence.

- `Test-Flight-Improv/02-integration-test-coverage.md` should be updated by Session `05` if durable readable-theme integration, performance, or inventory coverage is added.
- `Test-Flight-Improv/84-background-readable-theme-extension.md` should be updated by Session `05` with final completion evidence, explicit environment blocks, and any evidence-only follow-up.
- This breakdown ledger should be updated by each session's closure pass with status/evidence, then given a final verdict in Session `05`.
- `Test-Flight-Improv/test-gate-definitions.md` should only change if new integration/cross-feature tests are added and require classification.

# downstream execution path

For each session, run:

1. `$implementation-plan-orchestrator`
2. `$implementation-execution-qa-orchestrator`
3. `$implementation-closure-audit-orchestrator`

After all runnable sessions are resolved, run one final program-level acceptance/closure pass and persist a final doc verdict in this breakdown artifact.

# final program verdict

Final doc verdict: `accepted_with_explicit_follow_up`

Verdict date: 2026-04-28

Controller path:

- Spawned decomposition attempt: no reusable artifact landed under bounded wait.
- Local decomposition fallback: used; created this reusable breakdown with doc-scoped plan paths.
- Spawned pipeline-controller attempt: no doc `84` plan, ledger, code, test, or final-verdict progress landed under bounded wait.
- Local pipeline fallback: used; executed the session set from this breakdown and persisted this final verdict.

What is accepted:

- App-owned `BackgroundReadableColors` `ThemeExtension` now defines the minimum readable roles from source doc `84`.
- Current dark preferences (`Default`, `Cosmic`, and mirrored cosmic) resolve to the dark readable profile.
- A representative light fixture resolves through the same selected-background readable-theme boundary without exposing a production light background option.
- `AmbientBackground` installs the selected readable profile in `Theme` and applies matching `SystemUiOverlayStyle`.
- Representative Settings, Feed, Conversation, and Orbit surfaces consume readable roles.
- Direct contrast, propagation, and representative widget evidence is green.
- Existing Settings background-choice integration smoke remains green.
- Existing Feed performance integration evidence remains inside the concrete source-doc budgets.

Exact evidence:

- `flutter test --no-pub test/core/theme/background_readable_colors_test.dart` passed.
- `flutter test --no-pub test/features/identity/presentation/widgets/ambient_background_test.dart` passed.
- `flutter test --no-pub test/features/settings/presentation/widgets/background_choice_control_test.dart test/features/settings/presentation/screens/settings_screen_test.dart test/features/feed/presentation/screens/feed_screen_test.dart test/features/conversation/presentation/widgets/conversation_header_test.dart test/features/orbit/presentation/screens/orbit_screen_loading_test.dart` passed.
- `flutter analyze --no-pub lib/core/theme/background_readable_colors.dart lib/core/theme/app_theme.dart lib/features/identity/presentation/widgets/ambient_background.dart test/core/theme/background_readable_colors_test.dart test/features/identity/presentation/widgets/ambient_background_test.dart` passed with no issues.
- `flutter test --no-pub -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/settings_background_choice_smoke_test.dart` passed on iPhone 17 Pro simulator.
- `flutter test --no-pub -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/feed_performance_test.dart` passed on iPhone 17 Pro simulator. Feed scroll evidence included average `2.86ms`, P99 `10.89ms`, worst `19.38ms`; cosmic selected scroll average `1.90ms`, P99 `8.05ms`, worst `8.18ms`; mirrored cosmic selected scroll average `1.65ms`, P99 `7.56ms`, worst `8.66ms`.

Explicit follow-up before shipping a production light background:

- Complete exhaustive static inventory migration/classification for all remaining hard-coded foreground, border, surface, glass, scrim, input, icon, dialog, sheet, media picker, message overlay, and loading colors across every shared-background surface.
- Extend integration coverage to exercise an actual future production light background option once one exists, including dark-to-light and light-to-dark Settings-to-surface foreground/background synchronization.
- Add or extend transient overlay coverage for dialogs, sheets, media pickers, and message overlays under the representative light profile or a production light option.

Why this is safe to continue:

- No production light background option was added.
- Existing dark background behavior and Settings background smoke remain green.
- The shared readable-color contract is now present, tested, and consumed by representative surfaces, so later light-background work can continue by migrating remaining hard-coded colors instead of inventing a new theme path.
