# 55 - External Share Skip Post and Multi-Recipient Plan

## Final Verdict

`implementation-ready`

The repo already has the main pieces for external sharing: native share-intent
capture, cold/warm-start buffering, a dedicated Flutter target picker, and
existing 1:1 / group send primitives. The missing work is narrower:

- iOS share entry is intentionally blocked behind the native `Post` composer
- the Flutter picker still encodes one-target immediate navigation instead of
  batch selection and send

The safest bounded fix is to remove the native `Post` gate, convert the picker
to explicit multi-select plus send, and fan out the processed payload per
selected target while preserving existing onboarding buffering and truthful
send failure handling.

## 1. Real Scope

This plan changes only the external-share flow:

- iOS external share from Photos / Files / URLs should open directly into the
  app share picker without showing the native `Post` compose screen first
- the share picker should allow selecting multiple contacts and/or writable
  groups
- the picker should become the confirmation surface for this flow, with an
  explicit send action instead of immediate route-on-tap behavior
- shared text and files should be sent to every selected target using the
  repo's existing direct-chat and group-send rules
- search, preview strip, empty state, loading state, and deferred
  cold-start/onboarding share handling should remain intact

This plan does not redesign:

- in-app post composition
- the normal conversation or group composer UX
- Android-native share entry unless the same first-screen issue is reproduced
- per-target custom captions, editing, scheduling, or background batch queues

## 2. Closure Bar

This area is good enough for the current architecture when all of the
following are true:

- sharing to Mknoon from iOS no longer shows the extra native `Post` screen
- the user lands on the Flutter share picker directly
- the picker supports selecting 1 or more contacts/groups, shows the current
  selection count, and exposes one explicit send action
- a successful batch does not try to open multiple conversation screens; it
  completes from the picker flow and returns truthful success feedback
- a partial failure keeps successful deliveries intact and reports which
  targets failed without pretending the batch was atomic
- shared multi-image payloads still preserve every selected image
- buffered share flows from startup / onboarding / QR recovery still surface
  the picker correctly before send

## 3. Source Of Truth

Primary repo evidence:

- `ios/Share Extension/ShareViewController.swift`
- `ios/Share Extension/RSIShareFallback.swift`
- `lib/main.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/core/services/share_intent_service.dart`
- `lib/features/share/application/handle_share_intent_use_case.dart`
- `lib/features/share/presentation/navigation/share_target_picker_route.dart`
- `lib/features/share/presentation/screens/share_target_picker_wired.dart`
- `lib/features/share/presentation/screens/share_target_picker_screen.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/presentation/screens/contact_picker_wired.dart`
- `lib/features/groups/presentation/screens/contact_picker_screen.dart`

Primary tests and gate docs:

- `test/core/services/share_intent_ios_test.dart`
- `test/features/share/presentation/share_target_picker_screen_test.dart`
- `test/features/share/presentation/share_target_picker_wired_test.dart`
- `test/features/share/integration/share_to_contact_smoke_test.dart`
- `test/features/loading_states_smoke_test.dart`
- `test/features/groups/presentation/contact_picker_screen_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md`

Disagreement rule:

- current code and passing tests beat stale assumptions
- native iOS extension source beats plugin-default assumptions
- current share widget/integration tests intentionally pin the old
  single-target contract and must be updated rather than preserved

## 4. Session Classification

`implementation-ready`

## 5. Exact Problem Statement

The current flow has two user-visible problems.

First problem: the user sees the wrong first screen on iOS.

- `ios/Share Extension/ShareViewController.swift` overrides
  `shouldAutoRedirect()` to `false`
- `RSIShareViewController` only redirects after `didSelectPost()`
- this leaves the native `SLComposeServiceViewController` visible, which is
  the extra `Cancel` / `Post` screen from the screenshot

Second problem: the in-app picker is still hard-coded to one target.

- `ShareTargetPickerScreen` rows call `onContactSelected` /
  `onGroupSelected` directly on tap
- `ShareTargetPickerWired` handles those callbacks by processing shared files
  and immediately `pushReplacement`-ing to one `ConversationWired` or one
  `GroupConversationWired`
- the current tests explicitly prove that one tap routes to one target

Current behavior therefore is:

- iOS share -> native `Post` gate
- tap `Post` -> Flutter share picker
- tap one contact/group -> route into one composer with staged attachments

What must improve:

- iOS share should land directly on the picker
- the picker should support multi-target selection and batch send from that
  screen

What must stay unchanged:

- buffered share capture during startup / onboarding
- active-contact and writable-group filtering
- shared text/file previewing
- truthful send/upload behavior for direct and group delivery

## 6. Files And Repos To Inspect Next

Production files expected to change:

- `ios/Share Extension/ShareViewController.swift`
- `lib/features/share/presentation/screens/share_target_picker_screen.dart`
- `lib/features/share/presentation/screens/share_target_picker_wired.dart`
- one new batch-delivery coordinator/use-case file under
  `lib/features/share/application/`
- one new small share-target selection model/helper file if the picker needs a
  unified contact/group selection type
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
  only if direct-share send logic must be extracted instead of duplicated
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  only if group-share send logic must be extracted instead of duplicated
- `lib/features/conversation/application/upload_media_use_case.dart` if a
  shared helper needs a small surface lift

Production files expected to stay source-of-truth only:

- `ios/Share Extension/RSIShareFallback.swift`
- `lib/main.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/core/services/share_intent_service.dart`
- `lib/features/share/presentation/navigation/share_target_picker_route.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/presentation/screens/contact_picker_wired.dart`
- `lib/features/groups/presentation/screens/contact_picker_screen.dart`

Tests expected to change or be added:

- `test/core/services/share_intent_ios_test.dart`
- `test/features/share/presentation/share_target_picker_screen_test.dart`
- `test/features/share/presentation/share_target_picker_wired_test.dart`
- `test/features/share/integration/share_to_contact_smoke_test.dart`
- one new `test/features/share/application/*_test.dart` for batch delivery
- `test/features/loading_states_smoke_test.dart` if picker loading/sending UI
  changes materially
- direct follow-up startup/onboarding tests if the picker contract change
  affects those routes

## 7. Existing Tests Covering This Area

Already covered:

- `test/core/services/share_intent_ios_test.dart`
  proves the iOS share extension is configured and wired into the app
- `test/features/share/presentation/share_target_picker_screen_test.dart`
  proves the current picker preview/search UI and direct row-tap callbacks
- `test/features/share/presentation/share_target_picker_wired_test.dart`
  proves a selected contact/group immediately routes to one
  `ConversationWired` / `GroupConversationWired` with shared payload staged
- `test/features/share/integration/share_to_contact_smoke_test.dart`
  proves startup/onboarding share buffering reaches the picker and that
  multi-image shares survive into one target conversation
- `test/features/loading_states_smoke_test.dart`
  proves the picker can render loading and empty states without overflow
- `test/features/groups/presentation/contact_picker_screen_test.dart`
  proves the repo already has a multi-select header/count/confirm-button UI
  pattern worth reusing

Currently missing:

- a regression proving iOS auto-redirect happens without the native `Post`
  gate
- picker-level proof for multi-select state, explicit send CTA, and in-flight
  send lockout
- a batch-delivery coordinator test covering mixed direct/group targets
- truthful partial-success / partial-failure result handling
- preservation proof that cold-start/onboarding share buffering still works
  after the picker becomes confirm-based

Current tests that intentionally pin behavior which must change:

- `test/features/share/presentation/share_target_picker_screen_test.dart`
  cases `2e` and `2f` currently assume tap-immediately-calls-select callbacks
- `test/features/share/presentation/share_target_picker_wired_test.dart`
  cases `2k`, `2l`, `2m`, and `2n` currently assume one tap immediately routes
  to one composer
- `test/features/share/integration/share_to_contact_smoke_test.dart`
  currently proves one-target composer hydration, not multi-target batch send

## 8. Regression / Tests To Add First

Add or update these first, before production edits:

1. Extend `test/core/services/share_intent_ios_test.dart` to lock the native
   entry contract.
   - prove the share controller no longer forces `shouldAutoRedirect()` to
     `false`
   - keep this as a source-level regression because Flutter widget tests do not
     exercise the native iOS extension UI

2. Extend `test/features/share/presentation/share_target_picker_screen_test.dart`
   to prove the new picker contract.
   - tapping a row toggles selection state instead of immediately sending or
     routing
   - the header reflects selected count
   - the send button appears only when 1 or more targets are selected
   - search still works while selections exist
   - in-flight send UI disables duplicate submission

3. Add a new batch-delivery coordinator test under
   `test/features/share/application/`.
   - no send when no targets are selected
   - shared files are processed once before fanout
   - direct contacts use the direct-send path per target
   - groups use the group-send path per target
   - partial failures return truthful result data without rolling back success

4. Extend `test/features/share/presentation/share_target_picker_wired_test.dart`.
   - multi-select does not navigate on the first tap
   - tapping send invokes the batch coordinator exactly once
   - sending state blocks double taps and cancel races
   - successful completion exits the picker flow truthfully

5. Update `test/features/share/integration/share_to_contact_smoke_test.dart`.
   - cold start still lands on the picker
   - multi-image share can be sent to more than one target
   - deferred onboarding share still reaches the picker before confirmation

## 9. Step-By-Step Implementation Plan

1. Fix the native iOS entry seam first.
   - update `ios/Share Extension/ShareViewController.swift` so the extension
     auto-redirects once items are loaded instead of waiting for `didSelectPost`
   - keep the plugin fallback/base implementation intact unless the source test
     proves a second native seam is also required
   - stop here if simulator/device validation shows attachments are being lost
     before redirect; do not continue into Flutter picker work until the native
     handoff is sound

2. Convert the Flutter picker from route-on-tap to selection-on-tap.
   - introduce a unified selectable-target model that can represent either a
     contact or a writable group
   - add selected-target state, count-aware header text, selection affordance,
     explicit send CTA, and in-flight sending lockout
   - reuse the existing group contact-picker interaction pattern instead of
     inventing a new selection UX
   - preserve preview strip, search, empty state, loading state, and cancel

3. Build a bounded batch-share coordinator under `features/share/application/`.
   - inputs: `ShareIntent`, selected targets, identity/send dependencies
   - process shared files once into `PendingComposerMedia`
   - fan out one target at a time for the first implementation
   - for direct contacts, preserve the current 1:1 media-send rules:
     local-WiFi media fast path when available, otherwise relay upload plus
     `sendChatMessage`
   - for groups, preserve current group upload rules, including `allowedPeers`
     and final `sendGroupMessage`
   - return structured results: total targets, successes, failures, and failed
     target labels for user feedback

4. Keep attachment ownership truthful during fanout.
   - do not try to reuse one uploaded blob across multiple direct recipients,
     because `uploadMedia` is recipient-scoped today
   - reuse the processed local files as input only
   - ensure each target gets its own attachment ids / message ids / send record
   - do not delete original gallery/source files as part of the share fanout

5. Replace the old picker navigation wiring.
   - remove immediate `pushReplacement` from row taps in
     `ShareTargetPickerWired`
   - route send through the new coordinator instead
   - after full success, finish the picker flow and return to the prior app
     surface with lightweight success feedback
   - after partial failure, keep the result truthful and retryable rather than
     pretending the batch was atomic

6. Preserve startup/onboarding pending-share behavior.
   - keep `main.dart`, `StartupRouter`, and `ShareIntentService` buffering as
     the source of truth for when the picker should appear
   - only pass additional dependencies through route builders if the new batch
     coordinator requires them
   - do not reopen onboarding or QR flow architecture unless a regression test
     proves the new picker contract needs a narrow dependency change

7. Run direct tests first, then named gates, then a native iOS sanity pass.
   - widget/application/integration tests should pass before broader gates
   - complete one manual iOS Photos -> Mknoon validation because the native
     extension seam is not fully covered by Flutter-only tests

## 10. Risks And Edge Cases

- iOS auto-redirect could race attachment loading if the extension entry change
  is too aggressive; this is the first seam to validate manually
- direct 1:1 media sends currently attempt local WiFi before relay upload;
  bypassing that logic in the batch coordinator would be a behavior regression
- group sends need current member resolution for `allowedPeers`; stale group
  membership must fail truthfully
- sending to many targets increases chances of partial success; the UX must be
  honest and non-transactional
- duplicate sends become more expensive; double-submit protection is required
- cancel/back during send must be disabled or handled safely so the batch is not
  silently abandoned
- archived contacts and non-admin announcement groups must remain filtered out
- multi-image or mixed share payloads must still preserve all input files in
  order

## 11. Exact Tests And Gates To Run

Direct tests:

- `flutter test test/core/services/share_intent_ios_test.dart`
- `flutter test test/features/share/presentation/share_target_picker_screen_test.dart`
- `flutter test test/features/share/presentation/share_target_picker_wired_test.dart`
- `flutter test test/features/share/integration/share_to_contact_smoke_test.dart`
- `flutter test test/features/loading_states_smoke_test.dart`
- `flutter test test/features/home/presentation/screens/first_time_experience_wired_test.dart`
- `flutter test test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart`
- one new `flutter test test/features/share/application/<new_batch_share_test>.dart`

Named gates:

- `./scripts/run_test_gates.sh baseline`
- `./scripts/run_test_gates.sh 1to1`
- `./scripts/run_test_gates.sh groups`

Manual/native validation:

- iOS Photos share -> Mknoon -> picker appears directly
- select multiple targets -> send once
- verify success and partial-failure behavior

## 12. Known-Failure Interpretation

- there is no current repo evidence that the share-specific tests above are
  accepted red-by-design suites
- if `baseline`, `1to1`, or `groups` fails outside the share/send blast radius,
  compare against the current branch baseline before attributing the failure to
  this plan
- `test/features/loading_states_smoke_test.dart` is a useful direct smoke, but
  it is not the named Baseline Gate source of truth; that remains
  `integration_test/loading_states_smoke_test.dart` per
  `Test-Flight-Improv/test-gate-definitions.md`
- native iOS share-entry correctness still requires one simulator/device pass;
  a green Flutter test run alone is not enough to declare the first seam fixed

## 13. Done Criteria

- sharing to Mknoon from iOS no longer shows the extra native `Post` screen
- the Flutter picker supports selecting multiple contacts/groups
- the picker exposes one explicit send action and blocks duplicate sends
- shared images/text are delivered to all successful targets with no fake
  all-or-nothing result
- cold-start, warm-start, and deferred onboarding share flows still reach the
  picker correctly
- the direct tests above pass
- the named gates above pass, or any unrelated pre-existing red test is
  documented with evidence as pre-existing
- one native iOS share-sheet sanity check confirms the first-screen regression
  is actually gone

## 14. Scope Guard

- do not redesign Android native share handling unless the same first-screen
  issue is reproduced there
- do not merge this work with post composer, feed composer, or post-sharing
  behavior changes
- do not add per-target caption editing, schedule-send, or background job queue
  logic
- do not parallelize target fanout in the first implementation
- do not rewrite the share-intent plugin or onboarding buffering model beyond
  the minimal changes required for direct iOS redirect and confirm-based send
- do not change normal conversation/group composer behavior outside the minimal
  extraction needed to reuse existing send rules safely

## 15. Accepted Differences / Intentionally Out Of Scope

- single-target external share can move from immediate row-navigation to
  explicit select-then-send; preserving the old one-tap composer handoff is
  intentionally not required here
- post-send UX can remain a simple dismiss plus summary/snackbar instead of a
  brand-new multi-recipient confirmation screen
- exact microcopy, iconography, and selection polish can follow the existing
  group picker visual language rather than inventing a custom design system
- Android native entry behavior remains unchanged unless separately proven
  broken

## 16. Dependency Impact

- this plan becomes the base for any later external-share polish such as richer
  result summaries, retry UX, analytics, or Android parity follow-up
- if later product direction insists on keeping one-tap single-target composer
  handoff, the batch-share coordinator and picker tests must be revisited
  together instead of mixing both contracts
- later caption-editing or share-to-many enhancements should build on the new
  picker selection model rather than reopening the native iOS redirect seam

## Structural Blockers Remaining

- none

## Incremental Details Intentionally Deferred

- exact success/failure microcopy
- whether the selection count lives only in the header or also in a footer
- whether result feedback is a snackbar, banner, or lightweight dialog

## Why This Plan Is Safe To Implement Now

The required seams are identified and bounded:

- the first-screen issue is traced to one native iOS override
- the single-target limit is traced to one picker UI contract plus one picker
  wiring contract
- the current repo already has working send primitives and a proven multi-select
  pattern elsewhere

That makes this safe to implement as a narrow external-share plan instead of a
broader messaging or composer redesign.
