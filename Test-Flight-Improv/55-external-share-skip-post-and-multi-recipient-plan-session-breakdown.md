# 55 - External Share Skip Post and Multi-Recipient Plan Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/55-external-share-skip-post-and-multi-recipient-plan-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/55-external-share-skip-post-and-multi-recipient-plan.md`
- Decomposition date:
  `2026-04-04`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Recommended plan count

- `2`

## Overall closure bar

Report `55` is closed only when the external-share flow becomes truthful end to
end without widening into unrelated composer or Android redesign work:

- iOS share from Photos, Files, and URL entry points opens the Flutter share
  picker directly, without the extra native `Post` gate, and shared payloads
  still survive the redirect intact
- the picker supports selecting 1 or more active contacts and writable groups,
  shows the current selection count, and uses one explicit send action instead
  of immediate route-on-tap navigation
- shared text and files are processed once, then fanned out per selected
  target through the existing direct-chat and group-send rules, with truthful
  partial-success reporting rather than fake atomic semantics
- warm-start, cold-start, onboarding, and QR-buffered share flows still land
  on the picker correctly before confirmation
- the repo has direct regression proof for the native redirect seam, the
  picker multi-select contract, the batch fanout contract, and the buffered
  share-flow contract
- the required named gates for the Flutter send-path session pass, and one
  iOS simulator or device sanity pass confirms the first-screen regression is
  actually gone
- closure is recorded in this breakdown artifact and `Test-Flight-Improv/00-INDEX.md`,
  with broader 1:1 or group closure docs updated only if the landed code
  materially changes shared send semantics rather than staying share-local

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/55-external-share-skip-post-and-multi-recipient-plan.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/00-INDEX.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`

Current repo facts that govern the split:

- `ios/Share Extension/ShareViewController.swift` currently overrides
  `shouldAutoRedirect()` to `false`, which is the concrete native seam behind
  the extra `Post` screen.
- `test/core/services/share_intent_ios_test.dart` already treats the iOS share
  extension as a source-level contract and is the correct direct regression
  family for the native entry seam.
- `lib/features/share/presentation/screens/share_target_picker_screen.dart`
  currently exposes one-target row-tap callbacks and has no selection state,
  count-aware header, or explicit send CTA.
- `lib/features/share/presentation/screens/share_target_picker_wired.dart`
  currently processes shared files on the first row tap and immediately
  `pushReplacement`s into one `ConversationWired` or one
  `GroupConversationWired`.
- `test/features/share/presentation/share_target_picker_screen_test.dart`,
  `test/features/share/presentation/share_target_picker_wired_test.dart`, and
  `test/features/share/integration/share_to_contact_smoke_test.dart`
  intentionally pin the old single-target contract and therefore must change.
- `test/features/groups/presentation/contact_picker_screen_test.dart` already
  proves the repo has a multi-select header/count/confirm-button pattern worth
  reusing instead of inventing a new picker interaction model.
- `lib/core/services/share_intent_service.dart`,
  `lib/features/share/application/handle_share_intent_use_case.dart`,
  `lib/features/share/application/settle_share_intent_flow.dart`,
  `lib/main.dart`,
  `lib/features/identity/presentation/startup_router.dart`,
  `lib/features/home/presentation/screens/first_time_experience_wired.dart`,
  and `test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart`
  already provide the buffering and replay path for cold-start, onboarding,
  and QR recovery shares; these stay source-of-truth unless execution proves a
  narrow dependency-threading change is required.
- `lib/features/conversation/application/send_chat_message_use_case.dart` and
  `lib/features/groups/application/send_group_message_use_case.dart` already
  own the truthful direct and group send contracts, so the share work should
  reuse or lightly extract those rules instead of inventing a new delivery
  stack.

Source-of-truth conflicts that materially affected decomposition:

- the proposal lists startup/onboarding routing files as possible edits, but
  current route-builder evidence shows the pending-share routing contract is
  already isolated; those files should stay source-of-truth-only unless the
  batch coordinator needs one narrow dependency thread-through
- there is no stable share-specific closure or matrix doc today, so this
  breakdown artifact must become the doc-scoped closure ledger and
  `Test-Flight-Improv/00-INDEX.md` remains the stable maintenance ledger
- the native iOS redirect seam cannot be trusted on Flutter-only tests, so the
  split must preserve a native handoff checkpoint before the larger Flutter
  batch-send slice

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `iOS auto-redirect handoff proof` | `evidence-gated` | `Test-Flight-Improv/55-external-share-skip-post-and-multi-recipient-plan-session-1-plan.md` | none | `blocked` | `Test-Flight-Improv/55-external-share-skip-post-and-multi-recipient-plan-session-breakdown.md` | Local plan fallback wrote the session plan. `ShareViewController.shouldAutoRedirect()` now returns `true`, `flutter test test/core/services/share_intent_ios_test.dart` passed, but the required real iOS share-entry proof for text-or-URL plus file-bearing payload preservation was not captured in this automated run, so the session remains blocked on native handoff evidence. |
| `2` | `Picker multi-select batch send and closure` | `implementation-ready` | `Test-Flight-Improv/55-external-share-skip-post-and-multi-recipient-plan-session-2-plan.md` | `1` | `skipped_due_to_dependency` | `Test-Flight-Improv/55-external-share-skip-post-and-multi-recipient-plan-session-breakdown.md`, `Test-Flight-Improv/00-INDEX.md`, `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md` only if shared direct-send semantics materially change, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md` only if shared group-send semantics materially change | Session `1` did not close because the mandatory native redirect sanity pass is still missing, so the Flutter picker/batch-send slice was not started. |

## Ordered session breakdown

### Session 1

- Title:
  `iOS auto-redirect handoff proof`
- Session id:
  `1`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/55-external-share-skip-post-and-multi-recipient-plan-session-1-plan.md`
- Exact scope:
  - update the iOS share-extension entry contract so the app redirects into
    Mknoon without waiting for the native `Post` button
  - add or update the source-level iOS regression so the repo no longer
    accepts `shouldAutoRedirect() == false` as the contract
  - run one iOS simulator or device sanity pass that covers at least shared
    text or URL plus a file-bearing share to prove the redirect does not drop
    the payload before the Flutter picker loads
  - if the native handoff loses payloads, stop and record that blocker before
    Session `2`; do not continue into picker or batch-send work on assumptions
- Why it is its own session:
  - this is a different seam from the Flutter picker and send logic
  - the closure bar for this seam depends on native evidence that the current
    Flutter test inventory cannot provide
  - combining it with the larger Flutter batch-send slice would hide the
    highest-risk prerequisite and make failure triage ambiguous
- Likely code-entry files:
  - `ios/Share Extension/ShareViewController.swift`
  - `test/core/services/share_intent_ios_test.dart`
  - `ios/Share Extension/RSIShareFallback.swift` only as a source-of-truth
    reference unless evidence proves a second native seam is needed
- Likely direct tests/regressions:
  - `flutter test test/core/services/share_intent_ios_test.dart`
  - one manual iOS Photos or Files share sanity pass
  - one manual iOS URL or text share sanity pass if the first check does not
    already cover both redirect and payload preservation
- Likely named gates:
  - none by default; this native-only seam is closed by the source regression
    plus the manual iOS handoff proof
  - run `./scripts/run_test_gates.sh baseline` only if Session `1` widens into
    Flutter startup or share-routing code
- Matrix/closure docs to update when done:
  - required:
    - `Test-Flight-Improv/55-external-share-skip-post-and-multi-recipient-plan-session-breakdown.md`
  - not yet required:
    - `Test-Flight-Improv/00-INDEX.md` should wait for Session `2`, because
      the feature is not user-closed until the Flutter picker/send flow lands
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

### Session 2

- Title:
  `Picker multi-select batch send and closure`
- Session id:
  `2`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/55-external-share-skip-post-and-multi-recipient-plan-session-2-plan.md`
- Exact scope:
  - convert the share picker from route-on-tap to selection-on-tap with a
    count-aware header, selection affordance, explicit send CTA, and in-flight
    send lockout
  - add the smallest unified selection model or helper needed to represent
    contacts and groups in one batch-send surface
  - introduce one bounded batch-share coordinator under
    `lib/features/share/application/` that processes shared files once and
    then fans out to selected direct contacts and groups using the existing
    send/upload rules
  - replace the current immediate `pushReplacement` flow in
    `ShareTargetPickerWired` with truthful completion feedback from the picker
    itself, including partial-success reporting without pretending the batch is
    atomic
  - preserve active-contact and writable-group filtering, preview strip,
    search, loading state, empty state, cancel behavior, and buffered
    cold-start/onboarding/QR share routing
  - refresh the doc-scoped closure ledger and shared maintenance index after
    direct tests, named gates, and the final combined share-flow validation
- Why it is its own session:
  - picker UI, batch coordinator, wired integration, buffered-flow regressions,
    and truthful completion feedback form one user-visible external-share slice
    with one direct regression family and one closure bar
  - splitting "UI selection" from "delivery coordinator" would create a
    misleading half-state where the picker no longer routes immediately but
    also does not yet close the new share contract
  - splitting closure refresh away from this session would add bookkeeping
    without independent verification value because the feature is only closed
    when behavior, proofs, gates, and maintenance docs all land together
- Likely code-entry files:
  - `lib/features/share/presentation/screens/share_target_picker_screen.dart`
  - `lib/features/share/presentation/screens/share_target_picker_wired.dart`
  - one new file under `lib/features/share/application/` for the batch-share
    coordinator
  - one new small share-target selection model or helper under
    `lib/features/share/`
  - `lib/features/share/presentation/navigation/share_target_picker_route.dart`
    only if the coordinator needs a narrow dependency thread-through
  - `lib/main.dart`
  - `lib/features/identity/presentation/startup_router.dart`
  - `lib/features/home/presentation/screens/first_time_experience_wired.dart`
    only if route builders need the same narrow dependency thread-through
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`,
    `lib/features/groups/presentation/screens/group_conversation_wired.dart`,
    or upload/send helper files only if a small extraction is required to
    reuse current direct or group send rules safely
- Likely direct tests/regressions:
  - `test/features/share/presentation/share_target_picker_screen_test.dart`
  - `test/features/share/presentation/share_target_picker_wired_test.dart`
  - one new `test/features/share/application/*_test.dart` for the batch-share
    coordinator
  - `test/features/share/integration/share_to_contact_smoke_test.dart`
  - `test/features/loading_states_smoke_test.dart` if the send-lock or loading
    UX changes materially
  - `test/features/home/presentation/screens/first_time_experience_wired_test.dart`
    only if buffered onboarding-share wiring changes
  - `test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart`
    only if buffered QR-share wiring changes
- Likely named gates:
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh transport` only if the final implementation
    widens into bootstrap, reconnect, inbox-drain, or broader share-buffering
    architecture beyond the current route builders
- Matrix/closure docs to update when done:
  - required:
    - `Test-Flight-Improv/55-external-share-skip-post-and-multi-recipient-plan-session-breakdown.md`
    - `Test-Flight-Improv/00-INDEX.md`
  - conditional:
    - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
      only if landed code materially changes shared direct-send or direct-media
      semantics instead of staying share-entry-local
    - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
      only if landed code materially changes shared group-send or group-media
      semantics instead of staying share-entry-local
    - `Test-Flight-Improv/test-gate-definitions.md` only if execution
      intentionally reclassifies a share-specific direct suite or expands named
      gate membership; do not change it by default
- Dependency on earlier sessions:
  - Session `1` must finish first and prove the iOS redirect preserves
    attachments and text through the native handoff
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Reviewer pass

- Is the recommended session count sufficient, too coarse, or too fragmented:
  - sufficient; `2` sessions is the minimum safe split
- Which proposed sessions should merge:
  - none
- Which proposed sessions must split:
  - none
- What tests or named gates are missing from the decomposition:
  - a new share batch-coordinator direct test is still missing in the repo and
    must be added in Session `2`
  - the current picker screen and wired tests that pin row-tap routing must be
    rewritten, not preserved
  - the manual iOS redirect sanity pass is mandatory for Session `1`
  - onboarding or QR buffered-share tests are conditional but must be run
    directly if dependency-threading changes touch those routes
- Does each session end in a meaningful verified state:
  - yes; Session `1` clears the native prerequisite, and Session `2` lands the
    user-visible feature plus closure evidence
- Is the matrix-update responsibility assigned clearly:
  - yes; Session `2` owns the final maintenance refresh, while Session `1`
    updates only this breakdown if the prerequisite evidence changes scope
- What is the minimum session set that is still safe:
  - `2`

## Arbiter outcome

- Structural blockers:
  - none
- Mergeable sessions:
  - none
- Required splits:
  - none
- Accepted differences:
  - Android native entry remains unchanged unless separate evidence later
    proves the same first-screen defect there
  - one-tap single-target composer handoff is intentionally not preserved
  - no per-target caption editing, scheduling, or background batch queue
  - no new share-specific matrix doc is introduced while this breakdown and
    `00-INDEX.md` are sufficient closure artifacts

## Why this is not fewer sessions

- One session would be unsafe because the native iOS handoff is a prerequisite
  with a different proof requirement from the Flutter picker and batch-send
  work.
- If the redirect change drops attachments before the Flutter picker loads, the
  right action is to stop, document the blocker, and avoid building the larger
  picker flow on false assumptions.
- The minimum safe set is therefore one prerequisite native checkpoint plus one
  implementation session for the full Flutter share-flow slice.

## Why this is not more sessions

- A separate session for picker visuals alone would leave a misleading half
  state with no truthful send contract.
- A separate session for the batch coordinator alone would not provide
  independent user-visible verification because the picker surface must drive
  it.
- A separate closure-only session would be bookkeeping overhead here; the
  final maintenance refresh naturally belongs with Session `2`, where the
  direct proofs, named gates, and combined-flow validation are already run.

## Regression and gate contract

- Use `Test-Flight-Improv/14-regression-test-strategy.md` as the planning
  policy reference and `Test-Flight-Improv/test-gate-definitions.md` as the
  execution source of truth.
- Session `1` must add or update the native source regression first, then
  complete the manual iOS redirect sanity pass before Session `2` begins.
- Session `2` must update the direct share tests first for:
  - picker selection toggling and count-aware UI
  - explicit send CTA and in-flight lockout
  - batch fanout across direct contacts and groups
  - truthful partial-success or failure reporting
  - preserved cold-start, onboarding, and QR-buffered share routing if those
    seams are touched
- Session `2` must run the exact direct suites for touched files, then:
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh groups`
- Do not widen named gate membership by default; share-specific tests remain
  direct suites unless execution intentionally reclassifies them.
- Run `./scripts/run_test_gates.sh transport` only if the final implementation
  broadens into startup, reconnect, or inbox-drain routing beyond the current
  share-buffering contract.

## Matrix update contract

- No stable share-specific closure or matrix doc currently exists in
  `Test-Flight-Improv/`.
- This breakdown artifact is therefore the live doc-scoped closure ledger for
  Report `55`.
- `Test-Flight-Improv/00-INDEX.md` is the stable shared maintenance ledger and
  must be refreshed when Session `2` closes.
- Session `2` owns the final closure refresh during its downstream
  `$implementation-closure-audit-orchestrator` pass.
- `Test-Flight-Improv/test-gate-definitions.md` stays the gate source of truth
  but should only be updated if execution intentionally changes suite
  classification, not just because new direct share regressions were added.

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- Android native share entry is unchanged
- normal in-app conversation and group composer UX is unchanged
- post composer and post-sharing behavior are unchanged
- per-target captions, scheduling, retry queues, and parallel batch fanout are
  intentionally out of scope

## Exact docs/files used as evidence

- `Test-Flight-Improv/55-external-share-skip-post-and-multi-recipient-plan.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/00-INDEX.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `ios/Share Extension/ShareViewController.swift`
- `lib/main.dart`
- `lib/core/services/share_intent_service.dart`
- `lib/features/share/application/handle_share_intent_use_case.dart`
- `lib/features/share/application/settle_share_intent_flow.dart`
- `lib/features/share/presentation/navigation/share_target_picker_route.dart`
- `lib/features/share/presentation/screens/share_target_picker_screen.dart`
- `lib/features/share/presentation/screens/share_target_picker_wired.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/home/presentation/screens/first_time_experience_wired.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `test/core/services/share_intent_ios_test.dart`
- `test/features/share/presentation/share_target_picker_screen_test.dart`
- `test/features/share/presentation/share_target_picker_wired_test.dart`
- `test/features/share/integration/share_to_contact_smoke_test.dart`
- `test/features/groups/presentation/contact_picker_screen_test.dart`
- `test/features/home/presentation/screens/first_time_experience_wired_test.dart`
- `test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart`

## Why the decomposition is safe to send into downstream planning/execution

- the split isolates the only prerequisite seam that still needs native proof
  before larger Flutter work can be trusted
- the second session keeps the entire Flutter share-flow slice together so the
  user-visible contract, direct regressions, gates, and closure refresh all
  land as one verified state
- the decomposition reuses existing gate definitions, buffering architecture,
  and shared send primitives instead of inventing new architecture or a new
  matrix doc

## Pipeline execution update

- Controller run date:
  `2026-04-04`
- Session `1` plan result:
  - reusable plan now exists at
    `Test-Flight-Improv/55-external-share-skip-post-and-multi-recipient-plan-session-1-plan.md`
  - planning used the single allowed local fallback after the spawned planning
    step produced no trustworthy artifact
- Session `1` execution result:
  - final execution verdict: `blocked`
  - blocker class: `environment_blocker`
  - code/test delta tied to Session `1`:
    - `ios/Share Extension/ShareViewController.swift` now auto-redirects
    - `test/core/services/share_intent_ios_test.dart` now rejects the old
      `false` redirect contract and asserts the new auto-redirect seam
  - exact direct test run:
    - `flutter test test/core/services/share_intent_ios_test.dart` on
      `2026-04-04` -> passed
  - remaining blocker:
    - the required real iOS sanity proof was not captured for at least one
      shared text-or-URL flow and one file-bearing flow that both land on the
      Flutter picker with payload intact
    - available local evidence reached only source-level proof plus simulator
      availability; it did not honestly exercise the share entry seam end to
      end, so Session `1` cannot advance as accepted
- Session `2` execution result:
  - final status: `skipped_due_to_dependency`
  - reason:
    - Session `1` remains blocked, so the picker multi-select and batch-send
      slice must not start on assumptions

## Final program acceptance

- Final program verdict:
  `still_open`
- Why the verdict remains open:
  - Report `55` requires native redirect proof before the Flutter picker and
    batch-send slice may proceed
  - Session `1` still lacks the mandatory real iOS handoff evidence
  - Session `2` therefore remains unresolved and was not executed
- Stable docs updated in this controller run:
  - `Test-Flight-Improv/55-external-share-skip-post-and-multi-recipient-plan-session-breakdown.md`
  - `Test-Flight-Improv/55-external-share-skip-post-and-multi-recipient-plan-session-1-plan.md`
- Stable docs intentionally not updated:
  - `Test-Flight-Improv/00-INDEX.md` stays unchanged because Report `55` is
    not closed
