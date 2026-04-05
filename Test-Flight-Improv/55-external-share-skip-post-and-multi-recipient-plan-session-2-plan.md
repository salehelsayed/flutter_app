# 55 - External Share Skip Post and Multi-Recipient Plan - Session 2 Plan

## Final Verdict

`execution-safe`

## 1. Real Scope

This session changes only the Flutter external-share picker and delivery slice:

- convert the share picker from one-target route-on-tap behavior to explicit
  multi-select plus send
- introduce one bounded batch-share coordinator under `lib/features/share/`
  that processes shared files once and then fans out per selected contact or
  writable group using the repo's current direct-send and group-send rules
- replace immediate `pushReplacement` routing in `ShareTargetPickerWired` with
  truthful picker-level completion feedback
- preserve cold-start, onboarding, and QR-buffered share routing unless the new
  coordinator requires a narrow dependency thread-through

This session does not change:

- Android native share entry
- normal in-app conversation or group composer UX
- per-target captions, scheduling, retry queues, or parallel fanout
- post composer or post-sharing behavior

## 2. Closure Bar

Session 2 is good enough only when all of the following are true:

- the picker supports selecting 1 or more contacts/groups and no longer routes
  on the first tap
- the picker shows count-aware selection state and one explicit send action
- shared files are processed once before fanout
- direct targets use the current 1:1 send/upload rules and groups use the
  current group send/upload rules
- successful sends complete from the picker without opening multiple composer
  screens
- partial failures stay truthful and preserve successful deliveries
- buffered cold-start, onboarding, and QR share flows still reach the picker
- the direct share tests pass, plus `baseline`, `1to1`, and `groups`

## 3. Source Of Truth

Primary repo evidence for this session:

- `Test-Flight-Improv/55-external-share-skip-post-and-multi-recipient-plan-session-breakdown.md`
- `Test-Flight-Improv/55-external-share-skip-post-and-multi-recipient-plan.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/features/share/presentation/screens/share_target_picker_screen.dart`
- `lib/features/share/presentation/screens/share_target_picker_wired.dart`
- `lib/features/share/presentation/navigation/share_target_picker_route.dart`
- `lib/core/services/share_intent_service.dart`
- `lib/main.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/home/presentation/screens/first_time_experience_wired.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `test/features/share/presentation/share_target_picker_screen_test.dart`
- `test/features/share/presentation/share_target_picker_wired_test.dart`
- `test/features/share/integration/share_to_contact_smoke_test.dart`
- `test/features/groups/presentation/contact_picker_screen_test.dart`

Disagreement rule:

- current code and direct tests beat stale prose
- the session breakdown is the active contract for scope and dependency
- `test-gate-definitions.md` is authoritative for named gate execution

## 4. Session Classification

`implementation-ready`

## 5. Exact Problem Statement

The repo already captures and buffers external share intents correctly, but the
Flutter picker still hard-codes one-target immediate navigation. That leaves two
gaps:

- the picker UI cannot represent multi-recipient selection or explicit
  confirmation
- the share layer has no bounded coordinator that can process a payload once
  and fan it out truthfully across direct contacts and writable groups

This session must land that share-local delivery surface without reopening the
broader composer architecture.

## 6. Files And Repos To Inspect Next

Production files:

- `lib/features/share/presentation/screens/share_target_picker_screen.dart`
- `lib/features/share/presentation/screens/share_target_picker_wired.dart`
- one new coordinator file under `lib/features/share/application/`
- one new small target-selection model/helper under `lib/features/share/`
- `lib/features/share/presentation/navigation/share_target_picker_route.dart`
  only if the coordinator needs a narrow dependency thread-through
- `lib/main.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/home/presentation/screens/first_time_experience_wired.dart`
  only if route builders need the same narrow dependency thread-through

Tests:

- `test/features/share/presentation/share_target_picker_screen_test.dart`
- `test/features/share/presentation/share_target_picker_wired_test.dart`
- one new `test/features/share/application/*_test.dart`
- `test/features/share/integration/share_to_contact_smoke_test.dart`
- `test/features/loading_states_smoke_test.dart` if loading or sending UI
  changes materially
- buffered-route tests under `test/features/home/...` or `test/features/qr_code/...`
  only if route-builder dependencies change

## 7. Existing Tests Covering This Area

Already covered:

- picker screen tests prove preview, search, loading, empty state, cancel, and
  current row-tap callbacks
- picker wired tests prove active-contact and writable-group filtering and the
  current single-target route behavior
- share integration tests prove buffered cold-start/onboarding routing to the
  picker and one-target composer hydration
- group picker tests prove the repo already has a count-aware multi-select
  interaction pattern

Missing and required for this session:

- picker UI proof for multi-select toggling, count text, and explicit send CTA
- coordinator proof for direct plus group fanout and truthful partial failures
- wired proof that send happens once from the picker and no longer routes on
  first tap
- integration proof that buffered share flows still land on the picker and a
  payload can be sent to more than one target

## 8. Regression/Tests To Add First

1. Update `test/features/share/presentation/share_target_picker_screen_test.dart`
   to prove:
   - row taps toggle selection instead of invoking immediate send/navigation
   - the header reflects selected count
   - send CTA visibility depends on selection count
   - in-flight send state disables duplicate submission

2. Add one new `test/features/share/application/*_test.dart` that proves:
   - no send when nothing is selected
   - shared files process once before fanout
   - direct contacts and groups each use their own send path
   - partial failures report success/failure truthfully

3. Update `test/features/share/presentation/share_target_picker_wired_test.dart`
   to prove:
   - multi-select does not navigate on first tap
   - tapping send invokes the coordinator exactly once
   - success dismisses the picker truthfully
   - failure leaves the picker usable and reports the problem

4. Update `test/features/share/integration/share_to_contact_smoke_test.dart`
   so buffered share flows still reach the picker and a payload can be sent to
   more than one target.

## 9. Step-By-Step Implementation Plan

1. Introduce a small share-target selection model that can represent either a
   contact or a writable group in one selection set.
2. Introduce a bounded batch-share coordinator under `lib/features/share/`
   with injectable direct-send, group-send, and media-processing dependencies.
3. Move the current share-file processing helper out of the wired widget or
   make it reusable by the new coordinator so files are processed exactly once.
4. Refactor `ShareTargetPickerScreen` to:
   - accept selected-target ids
   - toggle target selection on row tap
   - render count-aware header text and send CTA
   - expose sending state and disable duplicate submission
5. Refactor `ShareTargetPickerWired` to:
   - own selected-target state
   - invoke the coordinator on send
   - remove immediate route pushes from row taps
   - keep filtering, search, loading, and cancel behavior intact
6. Thread any extra dependencies through route builders only if the
   coordinator truly needs them.
7. Run focused direct tests first, then the named gates, then update the
   breakdown ledger and `00-INDEX.md` if the session closes.

## 10. Risks And Edge Cases

- direct 1:1 media sends currently upload per recipient; the coordinator must
  not fake shared upload reuse across different direct targets
- group sends need current member resolution for `allowedPeers`
- duplicate sends become more expensive once fanout exists, so send-lock logic
  must be real
- partial success must not be reported as atomic success
- buffered share flows must still surface the picker before confirmation

## 11. Exact Tests And Gates To Run

Required direct tests:

- `flutter test test/features/share/presentation/share_target_picker_screen_test.dart`
- `flutter test test/features/share/presentation/share_target_picker_wired_test.dart`
- `flutter test test/features/share/integration/share_to_contact_smoke_test.dart`
- `flutter test test/features/share/application/<new_batch_share_test>.dart`

Conditional direct tests:

- `flutter test test/features/loading_states_smoke_test.dart`
- `flutter test test/features/home/presentation/screens/first_time_experience_wired_test.dart`
- `flutter test test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart`

Named gates:

- `./scripts/run_test_gates.sh baseline`
- `./scripts/run_test_gates.sh 1to1`
- `./scripts/run_test_gates.sh groups`

## 12. Known-Failure Interpretation

There is no accepted red-by-design state for the share-specific suites in this
session. If one of the named gates fails outside the touched share/send seam,
compare against current-branch baseline before attributing it to this session.

## 13. Done Criteria

- the picker is multi-select with explicit send
- the coordinator fans out truthfully across direct contacts and groups
- the picker no longer routes on first tap
- buffered share flows still land on the picker
- focused direct tests pass
- required named gates pass, or unrelated pre-existing failures are documented
- the breakdown ledger and stable maintenance docs reflect the landed result

## 14. Scope Guard

- do not redesign Android share entry
- do not reopen normal composer UX beyond minimal share-path extraction
- do not add parallel fanout, retry queues, or per-target editing
- do not change gate membership by default

## 15. Accepted Differences / Intentionally Out Of Scope

- one-tap single-target composer handoff is intentionally not preserved
- post-send UX may remain a lightweight dismiss plus summary
- exact microcopy and icon polish may follow the existing group picker pattern

## 16. Dependency Impact

- this session depends on Session 1 closing acceptably
- if this session lands, Report 55 may close subject to final closure review
- later external-share polish should build on the new selection/coordinator
  seams rather than reopening the native redirect contract

## Structural Blockers Remaining

- none

## Incremental Details Intentionally Deferred

- exact success/failure microcopy
- richer retry UX
- Android parity

## Accepted Differences Intentionally Left Unchanged

- broader messaging or composer redesign remains out of scope

## Exact Docs/Files Used As Evidence

- `Test-Flight-Improv/55-external-share-skip-post-and-multi-recipient-plan-session-breakdown.md`
- `Test-Flight-Improv/55-external-share-skip-post-and-multi-recipient-plan.md`
- `lib/features/share/presentation/screens/share_target_picker_screen.dart`
- `lib/features/share/presentation/screens/share_target_picker_wired.dart`
- `lib/features/share/presentation/navigation/share_target_picker_route.dart`
- `lib/core/services/share_intent_service.dart`
- `lib/main.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/home/presentation/screens/first_time_experience_wired.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `test/features/share/presentation/share_target_picker_screen_test.dart`
- `test/features/share/presentation/share_target_picker_wired_test.dart`
- `test/features/share/integration/share_to_contact_smoke_test.dart`
- `test/features/groups/presentation/contact_picker_screen_test.dart`

## Why The Plan Is Safe To Implement Now

The repo already has the buffered share-intent path, the current picker surface,
and the existing direct/group send primitives. This session only needs to
replace the picker contract and add one bounded share-local coordinator, which
keeps the blast radius narrower than a composer redesign.
