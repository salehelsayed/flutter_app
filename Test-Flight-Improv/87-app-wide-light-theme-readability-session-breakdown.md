# Decomposition artifact

- Artifact path: `Test-Flight-Improv/87-app-wide-light-theme-readability-session-breakdown.md`
- Source doc path: `Test-Flight-Improv/87-app-wide-light-theme-readability.md`
- Downstream workflow rule: detailed planning happens one session at a time. Later sessions must be refreshed against landed code, current tests, and current gate definitions before execution.
- Decomposition scope: this artifact belongs only to source doc `87`. It does not execute implementation, create session plans, or change unrelated rollout docs.

# recommended plan count

Recommended plan count: 8

Doc `87` is wider than docs `84` and `86`: it is not just a readable-color contract or a single production light background. It is an app-wide closure pass for every primary selected-background surface, missing surface, major card, modal, sheet, dialog, overlay, and media chrome that can appear while Daylight Lagoon is active.

The smallest safe split is eight sessions. The first establishes a reusable inventory and contrast evidence harness so later sessions do not make unreviewable one-off color edits. The next six sessions close independently testable product surface families: Orbit, Feed/Settings/Posts, one-to-one Conversation, Groups, Share/QR/Introduction/Identity, and cross-app transient/media surfaces. The final session performs end-to-end acceptance, simulator/device classification, performance smoke where relevant, and docs closure.

# decomposition artifact

- Artifact path: `Test-Flight-Improv/87-app-wide-light-theme-readability-session-breakdown.md`
- Proposal or source doc path: `Test-Flight-Improv/87-app-wide-light-theme-readability.md`
- Intended plan file pattern: `Test-Flight-Improv/87-app-wide-light-theme-readability-session-<session-id>-plan.md`
- Downstream execution path: each runnable session should next go through `$implementation-plan-orchestrator`, `$implementation-execution-qa-orchestrator`, and `$implementation-closure-audit-orchestrator`. After all runnable sessions, run one final whole-program acceptance and closure pass before persisting the final program verdict.
- Later-session refresh rule: every session must re-check current code, direct tests, and this ledger before implementation because earlier sessions may convert shared widgets or add helpers that later sessions should reuse.

# overall closure bar

Doc `87` is complete when Daylight Lagoon users can navigate every primary selected-background screen and every user-reachable screen, card, list row, sheet, dialog, overlay, picker, and media chrome named in the source doc without unreadable white-on-light or pale-on-light foregrounds. All in-scope selected-background adaptive surfaces must use the app-readable color contract or an equivalent tested local treatment, with normal text and essential labels meeting at least `4.5:1` contrast and meaningful icons, borders, dividers, disabled controls, focus/selection indicators, and other non-text UI meeting at least `3:1` against the effective surface.

Dark backgrounds must keep their current readable light-foreground appearance. Intentionally dark camera/media/pre-preference surfaces may remain dark only when they are explicitly classified and their own chrome, copy, actions, error states, and disabled/progress states remain readable. Static inventory is required for every source-doc screen and major transient group, but static inventory alone is not enough for selected-background adaptive surfaces: each major family needs widget, visual, integration, smoke, or simulator evidence with actual content and representative empty/loading/disabled/destructive/error states where those states exist.

Final closure may use `accepted_with_explicit_follow_up` only for narrow evidence that is genuinely simulator/device/release-environment blocked or for explicitly classified future visual inventory that does not leave a known current Daylight Lagoon readability failure open.

# source of truth

Primary docs:

- `Test-Flight-Improv/87-app-wide-light-theme-readability.md`
- `Test-Flight-Improv/84-background-readable-theme-extension.md`
- `Test-Flight-Improv/84-background-readable-theme-extension-session-breakdown.md`
- `Test-Flight-Improv/86-daylight-lagoon-background-option.md`
- `Test-Flight-Improv/86-daylight-lagoon-background-option-session-breakdown.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/02-integration-test-coverage.md`

Current repo facts governing the split:

- `AmbientBackground` and `BackgroundReadableColors` already define the selected-background boundary and readable-color contract that doc `87` should reuse instead of rebuilding.
- Daylight Lagoon exists as the current production light background and resolves to the representative-light readable profile.
- Prior docs have partial evidence for Feed, Settings, Conversation header, Orbit loading placeholders, and Daylight option plumbing, but doc `87` identifies many visible content paths, row/card widgets, transient surfaces, and missing inventory screens that still need explicit closure.
- Orbit is the observed failure and should be closed before broader families because it gives the most concrete app-visible regression.
- Named gates in `Test-Flight-Improv/test-gate-definitions.md` remain the execution source of truth. Feature-local widget tests are preferred for pure color/readability changes; named feature gates run only when behavior paths change beyond color-role consumption.

Disagreement rule:

- current code and tests beat stale prose
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` decide named gate membership
- source doc `87` remains the product intent source unless repo evidence proves a requirement stale, already covered, or overclaimed

# session ledger

| Session id | Title | Classification | Intended plan file | Depends on | Current status |
|---|---|---|---|---|---|
| `01-readability-inventory-harness` | App-wide readability inventory and contrast evidence harness | `implementation-ready` | `Test-Flight-Improv/87-app-wide-light-theme-readability-session-01-readability-inventory-harness-plan.md` | None | `accepted` |
| `02-orbit-visible-content` | Orbit visible content and observed Daylight failure closure | `implementation-ready` | `Test-Flight-Improv/87-app-wide-light-theme-readability-session-02-orbit-visible-content-plan.md` | `01-readability-inventory-harness` | `accepted` |
| `03-feed-settings-posts-surfaces` | Feed, Settings, and Posts light-background surface closure | `implementation-ready` | `Test-Flight-Improv/87-app-wide-light-theme-readability-session-03-feed-settings-posts-surfaces-plan.md` | `01-readability-inventory-harness` | `accepted` |
| `04-conversation-message-surfaces` | One-to-one Conversation cards, composer, attachments, and message overlays | `implementation-ready` | `Test-Flight-Improv/87-app-wide-light-theme-readability-session-04-conversation-message-surfaces-plan.md` | `01-readability-inventory-harness` | `accepted` |
| `05-group-surfaces` | Group list, group conversation, group info, invite cards, and group overlays | `implementation-ready` | `Test-Flight-Improv/87-app-wide-light-theme-readability-session-05-group-surfaces-plan.md` | `01-readability-inventory-harness`, `04-conversation-message-surfaces` | `accepted` |
| `06-share-qr-intro-identity-surfaces` | Share, QR, introduction, onboarding, and identity edge-surface classification | `implementation-ready` | `Test-Flight-Improv/87-app-wide-light-theme-readability-session-06-share-qr-intro-identity-surfaces-plan.md` | `01-readability-inventory-harness` | `accepted` |
| `07-cross-app-transients-media-surfaces` | Cross-app dialogs, sheets, pickers, reaction details, and media chrome | `implementation-ready` | `Test-Flight-Improv/87-app-wide-light-theme-readability-session-07-cross-app-transients-media-surfaces-plan.md` | `02-orbit-visible-content`, `03-feed-settings-posts-surfaces`, `04-conversation-message-surfaces`, `05-group-surfaces`, `06-share-qr-intro-identity-surfaces` | `accepted` |
| `08-acceptance-visual-simulator-closure` | Final integration, visual/simulator evidence, performance check, and docs closure | `acceptance-only` | `Test-Flight-Improv/87-app-wide-light-theme-readability-session-08-acceptance-visual-simulator-closure-plan.md` | `02-orbit-visible-content`, `03-feed-settings-posts-surfaces`, `04-conversation-message-surfaces`, `05-group-surfaces`, `06-share-qr-intro-identity-surfaces`, `07-cross-app-transients-media-surfaces` | `accepted_with_explicit_follow_up` |

# ordered session breakdown

## Session 01: App-wide readability inventory and contrast evidence harness

- Session id: `01-readability-inventory-harness`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/87-app-wide-light-theme-readability-session-01-readability-inventory-harness-plan.md`
- Exact scope:
  - create or tighten reusable widget-test helpers for Daylight Lagoon/readable-color contrast assertions so later sessions can prove `4.5:1` text and `3:1` icon/control/surface thresholds without duplicating ad hoc math
  - create a doc-owned static inventory table or section that tracks every source-doc screen and major transient/card group as `selected-background adaptive`, `intentionally dark/camera/media`, or `out of selected-background scope`
  - seed the inventory with the source-doc screen list and update it only with current-code evidence
  - identify already-covered surfaces from docs `84` and `86` without marking doc `87` closed for visible paths that still lack actual content evidence
  - add focused tests for the helper/harness if it is production-test utility code, and avoid broad UI code migrations in this session
- Why it is its own session:
  - the source doc spans too many surfaces to implement safely without a shared evidence vocabulary and closure ledger
  - this session leaves a meaningful verified state: later surface sessions can add comparable evidence and avoid subjective color-only claims
- Likely code-entry files:
  - `test/helpers/` or existing test utility location for contrast/readability helpers
  - `test/core/theme/background_readable_colors_test.dart`
  - `test/features/identity/presentation/widgets/ambient_background_test.dart`
  - `Test-Flight-Improv/87-app-wide-light-theme-readability.md`
  - `Test-Flight-Improv/87-app-wide-light-theme-readability-session-breakdown.md`
- Likely direct tests/regressions:
  - direct Flutter test for any new helper coverage
  - existing `test/core/theme/background_readable_colors_test.dart` if helper integration touches readable-color expectations
  - static inventory review against all source-doc screen and transient rows
- Likely named gates:
  - no named gate by default
  - `./scripts/run_test_gates.sh completeness-check` only if gate definitions or classification docs are edited
- Matrix/closure docs to update when done:
  - this breakdown ledger
  - doc `87` inventory/classification section
  - `Test-Flight-Improv/02-integration-test-coverage.md` only if durable integration coverage classification changes materially
- Dependency on earlier sessions: none.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Session 02: Orbit visible content and observed Daylight failure closure

- Session id: `02-orbit-visible-content`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/87-app-wide-light-theme-readability-session-02-orbit-visible-content-plan.md`
- Exact scope:
  - close the reported Orbit failure for Daylight Lagoon visible content, not just loading placeholders
  - migrate or classify the top labels, Orbit visualization labels, QR/scan controls, `Friends` header, filter tabs and count badges, friend rows, group rows, intro banner, archived/no-results empty states, unread badges, search dock, bottom navigation affordances, borders, dividers, glass/card surfaces, disabled states, and action controls
  - reuse `context.backgroundReadableColors` and existing readable roles where possible
  - add Daylight Lagoon widget or visual evidence with actual friend and group rows, long names/previews, timestamps, selected filters, archived/no-results states, and search/no-result state
  - preserve dark-background Orbit appearance and existing intro/follow-up behavior
- Why it is its own session:
  - Orbit is the observed user-facing failure and has a direct, independently verifiable closure bar
  - Orbit has dedicated widgets and tests that can land without changing Feed, Conversation, or group behavior
- Likely code-entry files:
  - `lib/features/orbit/presentation/screens/orbit_screen.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart` only if selected-background route setup is needed for tests
  - `lib/features/orbit/presentation/widgets/friends_list_header.dart`
  - `lib/features/orbit/presentation/widgets/friends_filter_toggle.dart`
  - `lib/features/orbit/presentation/widgets/friend_row.dart`
  - `lib/features/orbit/presentation/widgets/group_row.dart`
  - `lib/features/orbit/presentation/widgets/archived_empty_state.dart`
  - `lib/features/orbit/presentation/widgets/orbit_search_dock.dart`
  - `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
  - new or existing Orbit widget tests for visible content
- Likely direct tests/regressions:
  - focused Orbit widget tests with `BackgroundPreference.daylightLagoon`
  - contrast assertions for labels, rows, timestamps, tabs, badges, card surfaces, borders, icons, and disabled/no-results states
  - dark-background regression assertions for the same representative row/filter/header path
  - direct Orbit intro wiring tests only if Orbit behavior changes, which should be avoided for pure readability work
- Likely named gates:
  - no named gate by default for pure presentation readability
  - run `./scripts/run_test_gates.sh intro` only if implementation changes introduction send/resend/accept/pass/listener behavior
  - if intro follow-up wiring changes, also run the direct Orbit/Feed companion tests listed in `test-gate-definitions.md`
- Matrix/closure docs to update when done:
  - this breakdown ledger
  - doc `87` Orbit inventory rows and evidence notes
- Dependency on earlier sessions: `01-readability-inventory-harness`.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Session 03: Feed, Settings, and Posts light-background surface closure

- Session id: `03-feed-settings-posts-surfaces`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/87-app-wide-light-theme-readability-session-03-feed-settings-posts-surfaces-plan.md`
- Exact scope:
  - close remaining Daylight Lagoon readability gaps on Feed, Settings, Posts, pinned posts, post compose/comments/pass/edit sheets, cards, loading/empty states, inputs, disabled states, selected states, upload/progress indicators, and actions
  - distinguish surfaces already proven by docs `84` and `86` from visible content paths that still require doc `87` evidence
  - migrate background-sensitive hard-coded white, muted-white, translucent-white, fixed dark-card, pale border, input, icon, and disabled colors to readable roles or classify them as background-independent with evidence
  - add representative widget evidence for actual Feed cards/previews/reply controls, Settings cards/pickers/error states, and Posts cards/sheets/actions under Daylight Lagoon
  - preserve existing dark-background appearance and avoid changing post delivery, nearby presence, feed handoff, media upload, notification, or persistence behavior
- Why it is its own session:
  - Feed, Settings, and Posts share high-traffic app-shell surfaces and card/sheet presentation work, but can be verified without touching message/group transport behavior
  - this session leaves a meaningful verified state: the main non-chat content surfaces no longer depend on dark-background-only colors
- Likely code-entry files:
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart` only if tests need route-selected background setup
  - `lib/features/settings/presentation/screens/settings_screen.dart`
  - `lib/features/settings/presentation/widgets/background_choice_control.dart`
  - `lib/features/posts/presentation/screens/posts_screen.dart`
  - `lib/features/posts/presentation/widgets/post_card.dart`
  - `lib/features/posts/presentation/widgets/pinned_posts_section.dart`
  - `lib/features/posts/presentation/widgets/compose_post_sheet.dart`
  - `lib/features/posts/presentation/widgets/comments_sheet.dart`
  - `lib/features/posts/presentation/widgets/pass_post_along_sheet.dart`
  - `lib/features/posts/presentation/widgets/edit_pinned_post_sheet.dart`
  - relevant Feed, Settings, and Posts widget tests
- Likely direct tests/regressions:
  - `flutter test test/features/feed/presentation/screens/feed_screen_test.dart`
  - `flutter test test/features/settings/presentation/screens/settings_screen_test.dart`
  - `flutter test test/features/settings/presentation/widgets/background_choice_control_test.dart`
  - representative Posts widget tests selected during planning
  - contrast assertions for actual content, long text, localized/mixed-direction text, loading/empty/disabled/error/submitting states, selected states, sheet controls, and action buttons
- Likely named gates:
  - no named gate by default for pure presentation readability
  - `./scripts/run_test_gates.sh feed` if feed card, composer, inline reply, or feed-to-conversation handoff behavior changes
  - `./scripts/run_test_gates.sh posts` if posts delivery, privacy, replay, or nearby-presence behavior changes
- Matrix/closure docs to update when done:
  - this breakdown ledger
  - doc `87` Feed, Settings, Posts, and post-transient evidence rows
  - `Test-Flight-Improv/02-integration-test-coverage.md` only if durable integration coverage changes materially
- Dependency on earlier sessions: `01-readability-inventory-harness`.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Session 04: One-to-one Conversation cards, composer, attachments, and message overlays

- Session id: `04-conversation-message-surfaces`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/87-app-wide-light-theme-readability-session-04-conversation-message-surfaces-plan.md`
- Exact scope:
  - close Daylight Lagoon readability for one-to-one Conversation beyond the existing header-only proof
  - migrate or classify `LetterCard`, sender labels, message body, quote/reply states, reactions, transport/status icons, deleted/failed states, media/audio card chrome, composer, upload banner, attachment preview strip, attachment/delete sheets, full emoji picker, and message context overlay
  - include actual message content, long names, long text, localized/mixed-direction text, failed send, deleted message, quote unavailable, upload/progress, disabled, destructive, and empty/loading states where the widgets support them
  - preserve message send, retry, upload ordering, inbox, notification, reaction, quote/reply, and persistence behavior
  - keep intentionally dark media surfaces readable if they remain classified as media chrome
- Why it is its own session:
  - message cards and overlays have specialized state and high blast radius; they need focused tests distinct from Feed/Posts card work
  - this session can land independently while preserving messaging behavior gates
- Likely code-entry files:
  - `lib/features/conversation/presentation/screens/conversation_screen.dart`
  - `lib/features/conversation/presentation/screens/conversation_wired.dart` only for sheet route setup or tests
  - `lib/features/conversation/presentation/widgets/letter_card.dart`
  - `lib/features/conversation/presentation/widgets/upload_progress_banner.dart`
  - `lib/features/conversation/presentation/widgets/attachment_preview_strip.dart`
  - `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
  - `lib/features/conversation/presentation/widgets/full_emoji_picker.dart`
  - direct Conversation widget tests selected during planning
- Likely direct tests/regressions:
  - `flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart`
  - `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart` if present or added
  - focused widget tests for upload banner, attachment preview, context overlay, and emoji picker where present
  - contrast assertions for actual messages, quote/reply bars, media/audio surfaces, reactions, failed/deleted states, disabled/destructive actions, and dark-background preservation
- Likely named gates:
  - no named gate by default for pure presentation readability
  - `./scripts/run_test_gates.sh 1to1` if shared 1:1 send, retry, upload, listener, inbox, feed-originated entry, reaction, or quote/reply behavior changes
- Matrix/closure docs to update when done:
  - this breakdown ledger
  - doc `87` Conversation and message-overlay evidence rows
  - `Test-Flight-Improv/02-integration-test-coverage.md` only if durable Conversation coverage changes materially
- Dependency on earlier sessions: `01-readability-inventory-harness`.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Session 05: Group list, group conversation, group info, invite cards, and group overlays

- Session id: `05-group-surfaces`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/87-app-wide-light-theme-readability-session-05-group-surfaces-plan.md`
- Exact scope:
  - close Daylight Lagoon readability for Group List, Group Conversation, Group Info, group cards, pending invite cards, member rows, admin actions, dissolved/read-only banners, empty/loading states, group message cards, composer, reaction details, confirmation dialogs, metadata edit actions, and member action controls
  - reuse shared Conversation/message-card readability work where group message cards share presentation patterns
  - include group names/descriptions, long member names, localized/mixed-direction text, expired/disabled invites, destructive/admin actions, unread counts, loading rows, and empty states
  - preserve group send/receive/retry/resume/invite/announcement/member-role behavior
  - classify intentionally dark media or modal surfaces only when they remain readable on their own effective surface
- Why it is its own session:
  - group surfaces combine card/list readability with group-specific membership, invite, and admin states
  - they need the group gate only if behavior paths change, and can otherwise be verified through focused presentation tests
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_list_screen.dart`
  - `lib/features/groups/presentation/screens/group_conversation_screen.dart`
  - `lib/features/groups/presentation/screens/group_info_screen.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart` only for dialog tests or route setup
  - `lib/features/groups/presentation/widgets/group_card.dart`
  - `lib/features/groups/presentation/widgets/pending_group_invite_card.dart`
  - `lib/features/groups/presentation/widgets/group_member_row.dart`
  - `lib/features/groups/presentation/widgets/group_reaction_details_sheet.dart`
  - direct Group widget tests selected during planning
- Likely direct tests/regressions:
  - focused widget tests for group list cards/invites, group conversation banners/message path, group info/member rows, and reaction details
  - contrast assertions for actual content, timestamps, badges, disabled/expired states, destructive/admin actions, dialogs/sheets, borders, and dark-background preservation
- Likely named gates:
  - no named gate by default for pure presentation readability
  - `./scripts/run_test_gates.sh groups` if group send, receive, retry, resume, invite, announcement, membership, or admin behavior changes
  - run `test/features/contact_request/integration/contact_request_flow_test.dart` only if group invite/contact-entry behavior changes
- Matrix/closure docs to update when done:
  - this breakdown ledger
  - doc `87` Group List, Group Conversation, Group Info, invite, member, and group-overlay evidence rows
  - `Test-Flight-Improv/02-integration-test-coverage.md` only if durable Group coverage changes materially
- Dependency on earlier sessions: `01-readability-inventory-harness`, `04-conversation-message-surfaces`.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Session 06: Share, QR, introduction, onboarding, and identity edge-surface classification

- Session id: `06-share-qr-intro-identity-surfaces`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/87-app-wide-light-theme-readability-session-06-share-qr-intro-identity-surfaces-plan.md`
- Exact scope:
  - close or explicitly classify the source-doc surfaces that were missing or incomplete in the shared-background inventory: Share Target Picker, QR Display, QR Scanner, First Time Experience, Identity Choice, Create Group Picker, Contact Picker, introduction friend picker, sent confirmation screen, mnemonic restore input, and identity progress screen
  - for selected-background adaptive surfaces, migrate or classify picker rows, QR cards/hints, scan/add cards, choice cards, headers, preview/caption blocks, search inputs, create/invite controls, loading/empty/error/no-identity states, disabled/progress states, and dialog copy/actions
  - for QR scanner and any pre-preference identity surfaces, record whether the product surface is intentionally dark/camera/pre-preference or selected-background adaptive, then prove its own effective surface remains readable
  - preserve QR scan/paste, contact request, introduction send/pass/accept, group creation, identity generation, restore, share target send/skip, and onboarding behavior
- Why it is its own session:
  - these surfaces sit at route and onboarding edges where shared-background assumptions can be wrong
  - they need explicit classification instead of being silently covered by the main app-shell inventory
- Likely code-entry files:
  - `lib/features/share/presentation/screens/share_target_picker_screen.dart`
  - `lib/features/qr_code/presentation/screens/qr_display_screen.dart`
  - `lib/features/qr_code/presentation/screens/qr_display_wired.dart`
  - `lib/features/qr_code/presentation/screens/qr_scanner_screen.dart`
  - `lib/features/qr_code/presentation/screens/qr_scanner_wired.dart`
  - `lib/features/home/presentation/screens/first_time_experience_screen.dart`
  - `lib/features/home/presentation/screens/first_time_experience_wired.dart`
  - `lib/features/home/presentation/widgets/qr_code_section.dart`
  - `lib/features/home/presentation/widgets/scan_friend_card.dart`
  - `lib/features/home/presentation/widgets/empty_circle_state.dart`
  - `lib/features/identity/presentation/screens/identity_choice_screen.dart`
  - `lib/features/identity/presentation/widgets/choice_card.dart`
  - `lib/features/identity/presentation/screens/mnemonic_input_screen.dart`
  - `lib/features/identity/presentation/screens/identity_progress_screen.dart`
  - `lib/features/introduction/presentation/screens/friend_picker_screen.dart`
  - `lib/features/introduction/presentation/screens/sent_confirmation_screen.dart`
  - `lib/features/groups/presentation/screens/create_group_picker_screen.dart`
  - `lib/features/groups/presentation/screens/contact_picker_screen.dart`
  - direct widget tests selected during planning
- Likely direct tests/regressions:
  - focused widget tests for representative share picker, QR display, QR scanner chrome/dialogs, onboarding cards, identity choice/progress/restore states, introduction picker/confirmation, create group picker, and contact picker
  - contrast assertions for headers, row copy, QR hints, cards, buttons, search inputs, loading/empty/error/no-identity states, disabled/progress states, and dialog actions
  - dark/camera/pre-preference classification assertions where selected background should not apply
- Likely named gates:
  - no named gate by default for pure presentation readability
  - `./scripts/run_test_gates.sh intro` if introduction send/resend/accept/pass/listener behavior changes
  - `./scripts/run_test_gates.sh groups` if group invite/create behavior changes
  - Baseline gate QR scanner file only if QR scan wiring behavior changes
- Matrix/closure docs to update when done:
  - this breakdown ledger
  - doc `87` Share, QR, Introduction, Onboarding, Identity, Create Group, and Contact Picker classification/evidence rows
  - `Test-Flight-Improv/02-integration-test-coverage.md` only if durable integration coverage changes materially
- Dependency on earlier sessions: `01-readability-inventory-harness`.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Session 07: Cross-app dialogs, sheets, pickers, reaction details, and media chrome

- Session id: `07-cross-app-transients-media-surfaces`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/87-app-wide-light-theme-readability-session-07-cross-app-transients-media-surfaces-plan.md`
- Exact scope:
  - close the remaining major transient and media/card groups that cut across earlier sessions: contact request dialogs, QR success/already-exists/paste dialogs, Orbit confirmation dialogs, group info confirmation dialogs, delete message sheets, attachment source sheets, full emoji picker, reaction bars/details, full-screen media viewer chrome, media error overlays, and other source-doc transient groups not already closed by Sessions `03` through `06`
  - consolidate any shared dialog/sheet/media chrome helpers only when that reduces real duplication and matches existing local patterns
  - prove dialog backgrounds, title/body copy, buttons, disabled/progress states, focus/selection indicators, destructive actions, selected message preview, emoji/category labels, participant rows, controls, captions, counts, and error states are readable on their effective surfaces
  - preserve behavior for requests, QR, deletion, attachment picking, reactions, media viewing, upload, and navigation
  - avoid reopening already-accepted surface rows unless current evidence shows their transient state is still unreadable
- Why it is its own session:
  - transient surfaces often share UI primitives across features and are easiest to miss when each screen session focuses on the main content path
  - running this after the primary surface sessions lets it close gaps without duplicating their main-screen work
- Likely code-entry files:
  - `lib/features/contact_request/presentation/widgets/contact_request_dialog.dart`
  - `lib/features/qr_code/presentation/screens/qr_scanner_wired.dart`
  - `lib/features/conversation/presentation/widgets/full_emoji_picker.dart`
  - `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`
  - `lib/features/groups/presentation/widgets/group_reaction_details_sheet.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
  - `lib/shared/widgets/media/full_screen_image_viewer.dart`
  - any shared dialog/sheet helper selected during planning
  - representative transient widget tests selected during planning
- Likely direct tests/regressions:
  - focused widget tests for contact request dialog, QR dialogs, delete/attachment sheets, emoji picker, reaction details, full-screen media viewer chrome, and representative confirmation dialogs
  - contrast assertions for actual content, disabled/progress/destructive/error states, focus/selection indicators, media chrome, controls, and dark-background preservation
- Likely named gates:
  - no named gate by default for pure presentation readability
  - run feature gates only if behavior paths change: `1to1` for message deletion/attachments/reactions, `groups` for group reactions/info actions, `intro` for introduction dialogs, or Baseline QR scanner if scan wiring changes
- Matrix/closure docs to update when done:
  - this breakdown ledger
  - doc `87` transient/media/card inventory rows and evidence notes
  - `Test-Flight-Improv/02-integration-test-coverage.md` only if durable integration coverage changes materially
- Dependency on earlier sessions: `02-orbit-visible-content`, `03-feed-settings-posts-surfaces`, `04-conversation-message-surfaces`, `05-group-surfaces`, `06-share-qr-intro-identity-surfaces`.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Session 08: Final integration, visual/simulator evidence, performance check, and docs closure

- Session id: `08-acceptance-visual-simulator-closure`
- Session classification: `acceptance-only`
- Intended plan file: `Test-Flight-Improv/87-app-wide-light-theme-readability-session-08-acceptance-visual-simulator-closure-plan.md`
- Exact scope:
  - reconcile the doc `87` inventory against current code, tests, and all prior session closure notes
  - run the final direct test batch selected by Sessions `01` through `07`
  - run or extend integration/smoke evidence for Settings-to-Feed, Feed-to-Orbit, and light-background-to-transient-surface journeys
  - run representative visual or simulator evidence for phone viewport safety, system chrome, keyboard/search, camera scanner chrome, bottom navigation, route transitions, and modal/overlay placement when the local environment supports it
  - run Feed or relevant UI performance smoke if earlier sessions touched Feed/Posts/Orbit/large scrolling surfaces in ways that could affect frame budget
  - update doc `87`, this breakdown ledger, `Test-Flight-Improv/02-integration-test-coverage.md`, `Test-Flight-Improv/00-INDEX.md` if local convention requires it, and `Test-Flight-Improv/test-gate-definitions.md` only when durable integration/cross-feature tests were added
  - persist a final program verdict in this breakdown: `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `stale/already-covered`
- Why it is its own session:
  - app-wide acceptance is only meaningful after all surface families have landed
  - it prevents early sessions from overclaiming closure while simulator, integration, performance, and doc evidence are still unresolved
- Likely code-entry files:
  - final direct test files from Sessions `01` through `07`
  - `integration_test/settings_background_choice_smoke_test.dart` or the current Settings background integration smoke
  - `integration_test/feed_performance_test.dart` if Feed performance is touched and runnable
  - any Playwright/screenshot/simulator artifact path already used by the repo, if present
  - `Test-Flight-Improv/87-app-wide-light-theme-readability.md`
  - `Test-Flight-Improv/87-app-wide-light-theme-readability-session-breakdown.md`
  - `Test-Flight-Improv/02-integration-test-coverage.md`
  - `Test-Flight-Improv/00-INDEX.md` if the local closure convention requires it
  - `Test-Flight-Improv/test-gate-definitions.md` only if new gate-classified tests were added
- Likely direct tests/regressions:
  - all focused tests added or changed by Sessions `01` through `07`
  - existing Daylight Lagoon tests from docs `84` and `86` that remain relevant
  - Settings-to-Feed and Feed-to-Orbit smoke coverage
  - representative transient-surface launch coverage under Daylight Lagoon
  - simulator/device evidence or exact environment-block note for phone viewport/system chrome/camera scanner cases
- Likely named gates:
  - `./scripts/run_test_gates.sh completeness-check` if gate definitions or integration coverage classifications changed
  - named feature gates only for behavior changes made in earlier sessions; pure presentation-role migrations should remain covered by focused direct tests
- Matrix/closure docs to update when done:
  - this breakdown ledger with final program verdict
  - doc `87` final evidence and residual/follow-up section
  - `Test-Flight-Improv/02-integration-test-coverage.md` for durable integration coverage updates
  - `Test-Flight-Improv/00-INDEX.md` if it tracks closed rollout docs
- Dependency on earlier sessions: `02-orbit-visible-content`, `03-feed-settings-posts-surfaces`, `04-conversation-message-surfaces`, `05-group-surfaces`, `06-share-qr-intro-identity-surfaces`, `07-cross-app-transients-media-surfaces`.
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
  - final whole-program acceptance/closure review

# why this is not fewer sessions

Combining Orbit with the rest of app-wide work would hide the concrete reported failure behind a broad theming pass. Combining Feed/Settings/Posts with Conversation or Groups would mix card/sheet styling with message, transport-adjacent, and membership state setup that need different tests and different named-gate triggers. Combining QR/Share/Introduction/Identity with primary app-shell surfaces would risk assuming selected-background coverage applies to camera, onboarding, or pre-preference routes where the product classification may differ. Combining transients/media into each owning screen session would leave cross-app dialogs and media chrome easy to miss, while running them before the main surface sessions would duplicate fixes. Final integration, visual/simulator, performance, and docs closure must remain separate because it can only truthfully validate the combined app after the surface families have landed.

# reviewer and arbiter notes

- Structural blockers: none identified for decomposition. The rollout is large, but every session has a doc-scoped plan path, a distinct verification family, and a clear dependency chain.
- Required splits accepted: transient/media surfaces are split from primary screens because they cross feature boundaries and have their own evidence states.
- Mergeable sessions rejected: Feed, Settings, and Posts are kept together because they are high-traffic selected-background card/sheet surfaces with similar presentation tests and no required behavior-gate changes when scoped correctly.
- Accepted differences: QR scanner and some identity/onboarding routes may be intentionally dark, camera-specific, or pre-preference rather than selected-background adaptive; they still require explicit readable evidence on their own effective surface.

# session closure notes

## Session 01: App-wide readability inventory and contrast evidence harness

- Closure verdict: `accepted`
- Plan file: `Test-Flight-Improv/87-app-wide-light-theme-readability-session-01-readability-inventory-harness-plan.md`
- Code/test/doc delta:
  - Added `test/shared/helpers/readability_test_helpers.dart` with alpha-aware contrast ratio helpers and text/component threshold assertions.
  - Updated `test/core/theme/background_readable_colors_test.dart` to consume the reusable helper instead of private local contrast functions.
  - Added the doc `87` static classification ledger so every required screen and major transient/card group has an owner and explicit evidence state.
- Verification:
  - `flutter test test/core/theme/background_readable_colors_test.dart`
- Closure note: static inventory is now present, but selected-background surfaces remain open until their owning sessions add actual content evidence. No production UI colors were changed in this session.

## Session 02: Orbit visible content and observed Daylight failure closure

- Closure verdict: `accepted`
- Plan file: `Test-Flight-Improv/87-app-wide-light-theme-readability-session-02-orbit-visible-content-plan.md`
- Code/test/doc delta:
  - Updated Orbit top label, Friends header, QR/scan pills, filter toggle, friend rows, group rows, archived empty state, intro banner, and search dock to consume `BackgroundReadableColors` roles instead of fixed white-on-glass styling.
  - Updated `GroupTypeBadge` with light-surface-safe accent colors so Orbit group rows keep their type badge readable on Daylight Lagoon.
  - Added a Daylight Lagoon visible-content regression in `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart` with actual friend and group rows, mixed-direction preview text, header labels, and chevron evidence.
- Verification:
  - `flutter test test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
- Closure note: Orbit's main visible content path now has direct Daylight Lagoon widget evidence. Swipe action gradients and Orbit confirmation dialogs remain owned by Session 07 unless a real regression appears.

## Session 03: Feed, Settings, and Posts light-background surface closure

- Closure verdict: `accepted`
- Plan file: `Test-Flight-Improv/87-app-wide-light-theme-readability-session-03-feed-settings-posts-surfaces-plan.md`
- Code/test/doc delta:
  - Updated Posts screen header, status copy, time-section labels, caught-up copy, empty state, post cards, delivery chips, media skeleton/voice wrappers, metric actions, pinned posts summary/cards, avatar badges, and pinned see-all chrome to consume `BackgroundReadableColors` roles.
  - Added a Daylight Lagoon Posts visible-content regression with actual post body and pinned content in `test/features/posts/phase1/posts_screen_test.dart`.
  - Re-ran existing Feed and Settings screen tests that carry Daylight readable evidence.
- Verification:
  - `flutter test test/features/posts/phase1/posts_screen_test.dart`
  - `flutter test test/features/feed/presentation/screens/feed_screen_test.dart`
  - `flutter test test/features/settings/presentation/screens/settings_screen_test.dart`
- Closure note: main Posts screen/card/pinned content is now role-backed and directly covered. Full post compose/comment/pass/edit sheets remain transient surfaces for Session 07.

## Session 04: One-to-one Conversation cards, composer, attachments, and message overlays

- Closure verdict: `accepted`
- Plan file: `Test-Flight-Improv/87-app-wide-light-theme-readability-session-04-conversation-message-surfaces-plan.md`
- Code/test/doc delta:
  - Updated `LetterCard` message card surfaces, borders, sender/body/deleted/quote/timestamp/edit/status/reaction foregrounds, and status colors to consume readable roles while preserving existing dark pending-status expectations.
  - Updated upload progress banner and attachment preview placeholder/processing states to consume readable roles.
  - Added representative-light readability assertions to `letter_card_test.dart` and `attachment_preview_strip_test.dart`.
- Verification:
  - `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart`
  - `flutter test test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart`
  - `flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart`
- Closure note: Conversation visible message/card/upload/attachment states are now role-backed and directly covered. Full emoji picker, context overlay menus, delete sheets, attachment source sheets, and media viewer chrome remain Session 07 transient surfaces.

## Session 05: Group list, group conversation, group info, invite cards, and group overlays

- Closure verdict: `accepted`
- Plan file: `Test-Flight-Improv/87-app-wide-light-theme-readability-session-05-group-surfaces-plan.md`
- Code/test/doc delta:
  - Updated Group List, `GroupCard`, pending invite cards, group avatars, group dissolved badges, loading rows, empty states, section labels, and invite disabled/expired states to consume `BackgroundReadableColors` roles.
  - Updated Group Info header, group metadata, mute card, member rows, role colors, admin/member actions, dissolved status, destructive actions, and local-delete card to resolve readable roles from the `AmbientBackground` theme scope.
  - Updated Group Conversation header, backlog banner, empty/loading states, read-only banner, highlighted row shell, and group loading placeholders to consume readable roles while continuing to reuse Session 04 message-card coverage.
  - Added Daylight Lagoon readability assertions for group cards, group list/invite content, group info/member content, and group conversation chrome.
- Verification:
  - `flutter test test/features/groups/presentation/group_card_test.dart`
  - `flutter test test/features/groups/presentation/group_list_screen_test.dart`
  - `flutter test test/features/groups/presentation/group_info_screen_test.dart`
  - `flutter test test/features/groups/presentation/group_conversation_screen_test.dart`
- Closure note: persistent group list/info/conversation surfaces are now role-backed and directly covered. Reaction detail sheets, metadata edit dialogs, destructive confirmation dialogs, attachment source sheets, and full media chrome remain Session 07 transient/media surfaces.

## Session 06: Share, QR, introduction, onboarding, and identity edge-surface classification

- Closure verdict: `accepted`
- Plan file: `Test-Flight-Improv/87-app-wide-light-theme-readability-session-06-share-qr-intro-identity-surfaces-plan.md`
- Code/test/doc delta:
  - Updated Share Target Picker header, preview/caption/search surfaces, loading/empty state, section labels, contact/group rows, selection icons, send CTA, and sending overlay to consume readable roles from the `AmbientBackground` subtree.
  - Updated QR display close button and reusable QR/scan/empty-circle/glass widgets so selected-background QR display copy and cards stay readable on Daylight Lagoon.
  - Updated Create Group Picker, Contact Picker, shared contact picker rows, and `GroupNamePanel` to consume readable roles under selected backgrounds.
  - Updated identity choice brand/header/card/footer copy and shared glass containers for Daylight Lagoon while preserving the existing default/cosmic onboarding behavior.
  - Classified introduction friend picker/sent confirmation, mnemonic input, identity progress, and QR scan overlay as intentionally dark or pre-preference/default surfaces for this session; their current focused tests remain green.
- Verification:
  - `flutter test test/features/share/presentation/share_target_picker_screen_test.dart`
  - `flutter test test/features/qr_code/presentation/screens/qr_display_wired_test.dart`
  - `flutter test test/features/groups/presentation/contact_picker_screen_test.dart`
  - `flutter test test/features/groups/presentation/create_group_picker_screen_test.dart`
  - `flutter test test/features/identity/presentation/screens/identity_choice_screen_test.dart`
  - `flutter test test/features/introduction/presentation/screens/friend_picker_test.dart`
  - `flutter test test/features/introduction/presentation/screens/sent_confirmation_test.dart`
  - `flutter test test/features/identity/presentation/screens/mnemonic_input_screen_test.dart`
  - `flutter test test/features/identity/presentation/screens/identity_progress_screen_test.dart`
  - `flutter test test/features/qr_code/presentation/widgets/scan_overlay_test.dart`
- Closure note: selected-background Share, QR display, group/contact picker, and identity choice content is now role-backed and directly covered. QR scanner camera chrome, introduction bottom-sheet internals beyond focused current tests, and remaining dialogs/sheets/media chrome stay with Session 07 or final simulator evidence.

## Session 07: Cross-app dialogs, sheets, pickers, reaction details, and media chrome

- Closure verdict: `accepted`
- Plan file: `Test-Flight-Improv/87-app-wide-light-theme-readability-session-07-cross-app-transients-media-surfaces-plan.md`
- Code/test/doc delta:
  - Updated contact request dialogs, one-to-one attachment source sheets, group attachment source sheets, conversation context overlay menus, quick reaction bars, full emoji picker, group reaction detail sheets, and group metadata editor fields to consume `BackgroundReadableColors` roles where those surfaces can appear over selected backgrounds.
  - Kept QR scanner and full-screen media viewer as intentionally dark surfaces, while fixing green primary action foregrounds and Orbit danger confirmation contrast on their actual dark/accent surfaces.
  - Added focused readability regressions for contact request dialog copy, overlay action labels, emoji category labels, group reaction participant rows, Orbit danger action contrast, and QR scanner success action foreground.
  - Added doc `87` Session 07 evidence and transient/media residual ownership notes.
- Verification:
  - `flutter test test/features/contact_request/presentation/widgets/contact_request_dialog_test.dart test/features/conversation/presentation/widgets/message_context_overlay_test.dart test/features/conversation/presentation/widgets/full_emoji_picker_test.dart test/features/groups/presentation/widgets/group_reaction_details_sheet_test.dart test/shared/widgets/media/full_screen_image_viewer_test.dart`
  - `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart test/features/conversation/presentation/screens/conversation_wired_gif_test.dart test/features/conversation/presentation/screens/conversation_wired_bg_task_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/presentation/group_info_wired_test.dart`
  - `flutter test test/features/orbit/presentation/widgets/confirmation_dialog_test.dart test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart test/features/qr_code/presentation/widgets/scan_overlay_test.dart`
- Closure note: selected-background transient surfaces now have direct role-backed evidence, and intentionally dark camera/media/confirmation surfaces retain dark treatment with focused contrast checks. Simulator-only visual proof for camera framing, route transitions, keyboard/search placement, and system chrome remains Session 08 final evidence.

## Session 08: Final integration, visual/simulator evidence, performance check, and docs closure

- Closure verdict: `accepted_with_explicit_follow_up`
- Plan file: `Test-Flight-Improv/87-app-wide-light-theme-readability-session-08-acceptance-visual-simulator-closure-plan.md`
- Code/test/doc delta:
  - Ran the final direct acceptance batch across the readability contract, Orbit, Feed, Settings, Posts, Conversation, Groups, Share, QR, Contact/Create Group Picker, Identity, Introduction, and Contact Request surface families.
  - Ran the existing Settings background choice integration smoke on the local macOS target after Flutter required an explicit device selection due multiple connected devices.
  - Added doc `87` final acceptance and residual evidence notes.
  - Did not update `Test-Flight-Improv/02-integration-test-coverage.md` because no new durable integration category or gate definition was added.
- Verification:
  - `flutter test test/core/theme/background_readable_colors_test.dart test/features/orbit/presentation/screens/orbit_screen_loading_test.dart test/features/orbit/presentation/widgets/confirmation_dialog_test.dart test/features/posts/phase1/posts_screen_test.dart test/features/feed/presentation/screens/feed_screen_test.dart test/features/settings/presentation/screens/settings_screen_test.dart test/features/conversation/presentation/widgets/letter_card_test.dart test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart test/features/conversation/presentation/widgets/message_context_overlay_test.dart test/features/conversation/presentation/widgets/full_emoji_picker_test.dart test/features/conversation/presentation/screens/conversation_screen_test.dart test/shared/widgets/media/full_screen_image_viewer_test.dart test/features/groups/presentation/group_card_test.dart test/features/groups/presentation/group_list_screen_test.dart test/features/groups/presentation/group_info_screen_test.dart test/features/groups/presentation/group_conversation_screen_test.dart test/features/groups/presentation/widgets/group_reaction_details_sheet_test.dart test/features/share/presentation/share_target_picker_screen_test.dart test/features/qr_code/presentation/screens/qr_display_wired_test.dart test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart test/features/qr_code/presentation/widgets/scan_overlay_test.dart test/features/groups/presentation/contact_picker_screen_test.dart test/features/groups/presentation/create_group_picker_screen_test.dart test/features/identity/presentation/screens/identity_choice_screen_test.dart test/features/introduction/presentation/screens/friend_picker_test.dart test/features/introduction/presentation/screens/sent_confirmation_test.dart test/features/identity/presentation/screens/mnemonic_input_screen_test.dart test/features/identity/presentation/screens/identity_progress_screen_test.dart test/features/contact_request/presentation/widgets/contact_request_dialog_test.dart`
  - `flutter test -d macos integration_test/settings_background_choice_smoke_test.dart`
- Closure note: local direct and macOS integration evidence passed. Remaining work is explicit device/simulator visual proof only: camera scanner framing and permission overlays, phone system status/navigation chrome, route-transition screenshots, keyboard/search placement, and platform-specific media controls.

# final program verdict

- Verdict: `accepted_with_explicit_follow_up`
- Stop reason: all planned sessions are resolved; only explicitly documented device/simulator visual evidence remains.
- Docs completed:
  - `Test-Flight-Improv/87-app-wide-light-theme-readability.md`
  - `Test-Flight-Improv/87-app-wide-light-theme-readability-session-breakdown.md`
- Durable test-matrix docs unchanged:
  - `Test-Flight-Improv/02-integration-test-coverage.md` was not updated because no new integration category, gate definition, or durable cross-feature test was added.
