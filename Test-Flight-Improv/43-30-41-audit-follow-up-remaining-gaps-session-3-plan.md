# Audit 43 Session 3 Plan: Delete-for-Everyone Sender Honesty And Lifecycle Convergence

## Real scope

- Keep delete-for-everyone sender state visible and truthful while the delete is
  still `sending`, `sent`, or `failed`, instead of hiding the sender row before
  remote delete finalization under the app's current delivery contract.
- Preserve the existing recipient-side deleted placeholder contract and the
  already-landed delete affordance program from Report `33`.
- Add delete-specific lifecycle and ordering proof so pause/resume and
  delete-after-original ordering resolve to one honest outcome.

## Closure bar

- A sender-visible delete-for-everyone row does not silently disappear while
  the delete is still pending or failed.
- The sender-visible row becomes hidden only once the delete has actually
  finalized under the current durable-send semantics.
- Shared retry and resume recovery continue to carry delete tombstones forward
  without reintroducing the original content or leaving the row permanently
  visible after final delivery.
- Recipients still converge to the deleted placeholder for successful online and
  offline ordering paths.
- Orbit and Feed both refresh to the same honest sender-visible state.
- Required direct suites pass, plus `1to1`, `baseline`, and `feed` if feed
  parity changes.

## Source of truth

- Active controller artifact:
  `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-breakdown.md`
- Reopened seam analysis:
  `Test-Flight-Improv/37-1to1-delete-for-everyone-reliability.md`
- Older landed rollout context:
  `Test-Flight-Improv/33-delete-message-for-me-everyone-session-breakdown.md`
- Policy/gates:
  `Test-Flight-Improv/14-regression-test-strategy.md`,
  `Test-Flight-Improv/test-gate-definitions.md`
- Stable maintenance references still owned by later closure:
  `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`,
  `Test-Flight-Improv/00-INDEX.md`
- Current code and tests beat stale closure prose if they disagree.

## Session classification

- `implementation-ready`

## Exact problem statement

- `lib/features/conversation/application/delete_message_use_case.dart`
  currently writes a sender tombstone with `hiddenAt` already set while the
  delete is still `sending`, and it keeps the tombstone hidden on later `sent`
  or `failed` outcomes too.
- `lib/core/database/helpers/messages_db_helpers.dart` visible message queries
  require `hidden_at IS NULL`, so the sender loses visible context immediately
  even when the delete is still pending or has failed.
- The shared retry and unacked loaders still include hidden tombstones, so the
  delete can continue retrying in the background while the sender-visible row is
  already gone.
- `conversation_wired.dart` and `feed_wired.dart` both treat any returned
  updated tombstone as enough to refresh and return; they do not distinguish
  between a truthful visible pending/failed state and a finalized hidden result.
- Existing tests prove the current hidden tombstone behavior, but that behavior
  is exactly the reopened trust gap from Audit `43` / Report `37`.

## Files and repos to inspect next

- `lib/features/conversation/application/delete_message_use_case.dart`
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
- `lib/features/conversation/application/retry_unacked_messages_use_case.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/core/database/helpers/messages_db_helpers.dart`
  only if the final fix truly requires query changes beyond tombstone timing
- `test/features/conversation/application/delete_message_use_case_test.dart`
- `test/features/conversation/integration/message_deletion_roundtrip_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/conversation/integration/send_then_lock_delivery_test.dart`

## Existing tests covering this area

- `test/features/conversation/application/delete_message_use_case_test.dart`
  currently proves the wrong sender-hidden failure contract.
- `test/features/conversation/integration/message_deletion_roundtrip_test.dart`
  covers online success and offline delete-after-original ordering for the
  recipient final state.
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  currently proves hidden outgoing tombstones disappear from Orbit.
- `test/features/feed/presentation/screens/feed_wired_test.dart`
  proves incoming deleted refresh behavior and delete-for-everyone feed parity,
  but not the sender-visible pending/failed delete contract.
- `test/features/conversation/integration/send_then_lock_delivery_test.dart`
  is already in the `1to1` gate and is the right place to add delete-specific
  pause/resume convergence proof.

## Regression/tests to add first

- Flip the delete use-case regression in
  `test/features/conversation/application/delete_message_use_case_test.dart`
  from "hidden failed tombstone" to "sender-visible failed tombstone" while
  keeping delete metadata and retryability intact.
- Add Orbit refresh proof in
  `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  that a sender-visible deleted placeholder remains in the list for pending or
  failed delete-for-everyone state instead of disappearing immediately.
- Add Feed parity proof in
  `test/features/feed/presentation/screens/feed_wired_test.dart`
  that the latest visible row becomes the deleted placeholder while sender-side
  delete is still pending/failed, then clears once finalized if that is the
  landed contract.
- Add one delete-specific lifecycle proof adjacent to
  `test/features/conversation/integration/send_then_lock_delivery_test.dart`
  covering pause/resume or lock/unlock convergence.

## Step-by-step implementation plan

1. Change the outgoing delete tombstone contract so sender-side delete rows stay
   visible while status is `sending`, `sent`, or `failed`.
2. Hide the sender tombstone only when delete finalization reaches
   `status == 'delivered'` under the current direct/inbox contract.
3. Make shared failed/unacked retry success paths preserve that same contract
   for deleted outgoing tombstones so resume recovery hides only finalized
   deletes.
4. Refresh Orbit and Feed sender surfaces against the new visible tombstone
   behavior and show failure feedback only as much as needed to keep the state
   truthful.
5. Add the smallest direct and lifecycle regressions that prove sender-visible
   honesty and finalization convergence.
6. Run the exact direct suites first.
7. Run `1to1`, `baseline`, and `feed`, then stop unless the landed fix truly
   widens into shared lifecycle handler logic that requires `transport`.

## Risks and edge cases

- A delivered delete that was stored in inbox rather than directly acknowledged
  still needs one honest sender-visible finalization rule; do not leave it
  visible forever by accident.
- Shared retry success for deleted tombstones must not clear delete metadata or
  resurrect original text/media.
- Recipient delete-before-original ordering must continue to converge to the
  deleted placeholder once ordering catches up.
- Feed latest-message projection must not drop the whole thread prematurely when
  the sender still needs visible pending/failed delete context.
- Do not reopen delete-for-me, group delete, or the broader Report `33`
  affordance rollout.

## Exact tests and gates to run

- Direct tests:
  - `flutter test test/features/conversation/application/delete_message_use_case_test.dart`
  - `flutter test test/features/conversation/integration/message_deletion_roundtrip_test.dart`
  - `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart`
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
- Conditional direct tests:
  - `flutter test test/features/conversation/application/retry_unacked_messages_use_case_test.dart`
    if the landed fix changes unacked retry semantics directly
  - `flutter test test/features/conversation/application/retry_failed_messages_use_case_test.dart`
    equivalent direct coverage is already present through delete/lifecycle
    tests unless the final implementation widens generic failed-message
    behavior beyond deleted tombstones
  - `flutter test test/core/lifecycle/handle_app_resumed_test.dart`
    only if the final implementation edits lifecycle handlers directly
- Named gates:
  - `./scripts/run_test_gates.sh 1to1`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh feed`
- Conditional named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport`
    only if the landed fix changes lifecycle handler wiring, startup ordering,
    or transport-owned recovery rather than staying inside the delete/tombstone
    contract

## Known-failure interpretation

- Treat failures in delete use-case tests, Orbit/Feed delete refresh tests, the
  delete lifecycle regression, or the named gates as session-relevant until
  proven otherwise.
- If `baseline` fails only because the local machine has multiple Flutter
  devices attached, rerun it with an explicit `FLUTTER_DEVICE_ID` instead of
  classifying that as a product blocker.
- Do not classify the current hidden-tombstone assertions as pre-existing gate
  noise; they are the reopened behavior this session is supposed to change.

## Done criteria

- Sender-visible delete-for-everyone state remains honest while pending/failed.
- Finalized delete-for-everyone state hides the sender row only after the delete
  has actually reached the current durable finalization boundary.
- Orbit and Feed both refresh to the same truthful sender-visible outcome.
- Recipient final-state regressions still pass.
- Required direct tests pass.
- Required named gates pass, or any unrelated pre-existing failure is
  explicitly evidenced under the gate definitions.

## Scope guard

- Do not redesign the delete protocol or add a new recipient acknowledgement
  system in this session.
- Do not reopen delete-for-me, group delete, or time-window delete policy work.
- Do not widen into a generic message-status redesign outside deleted tombstone
  visibility/finalization semantics.
- Do not edit frozen gate definitions.

## Accepted differences / intentionally out of scope

- No promise of cryptographic proof that the recipient already rendered the
  tombstone; the session only needs one honest sender-visible state under the
  current transport contract.
- No new delete-specific copy system beyond the smallest truthful UI signals
  already supported by current status and placeholder rendering.
- No group or announcement delete parity work.

## Dependency impact

- Session `7` depends on this session landing with sender-visible delete truth
  and lifecycle proof so the final closure sweep can honestly refresh Reports
  `33`, `37`, and `19`.
- Sessions `4` and `5` remain otherwise independent.
- Session `6` still depends only on Session `5`.
