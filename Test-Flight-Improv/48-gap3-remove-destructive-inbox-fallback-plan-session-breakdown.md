# 48 - GAP-3 Remove Destructive Inbox Retrieve Fallbacks Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/48-gap3-remove-destructive-inbox-fallback-plan-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/48-gap3-remove-destructive-inbox-fallback-plan.md`
- Decomposition date:
  `2026-04-03`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Recommended plan count

- `1`

## Overall closure bar

Report `48` is closed only when the automatic 1:1 offline inbox drain no longer
has any production path from durable `retrieve_pending` back to destructive
`inbox:retrieve`:

- warm start, resume, and explicit `drainOfflineInbox()` always stay on the
  durable stage-then-ack path
- `retrieve_pending` exceptions or error responses leave relay rows untouched
  and return a safe no-progress result instead of deleting on read
- partially malformed pages still stage valid entries and emit explicit skip
  telemetry rather than abandoning the whole page to destructive fallback
- direct regressions prove the automatic drain path does not call
  `inbox:retrieve` anymore
- the stable 1:1 closure docs are refreshed without overclaiming that every
  destructive inbox API in the repo is gone

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/48-gap3-remove-destructive-inbox-fallback-plan.md`
- `Test-Flight-Improv/47-message-reliability-roadmap.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/00-INDEX.md`

Current repo facts that govern the split:

- `lib/core/services/p2p_service_impl.dart` still keeps
  `_inboxStagingRepository` nullable, still defines
  `fallbackToLegacyRetrieve(...)`, and still falls from
  `_retrievePendingInboxPage(...)` into `_retrieveInboxPage(...)` when
  `retrieve_pending` throws, returns `ok != true`, or yields unstageable raw
  messages.
- `lib/core/services/p2p_service_impl.dart` still carries the legacy
  destructive helpers `_retrieveInboxPage(...)` and
  `_continueDrainingOfflineInbox(...)`, plus the nullable branch in
  `_drainOfflineInbox()`.
- `lib/main.dart` already constructs and injects `inboxStagingRepository` into
  `P2PServiceImpl`, so this report does not need a prerequisite session just to
  make production wiring durable.
- `test/core/services/p2p_service_impl_test.dart` already proves the durable
  happy path, staged replay, and retryable staged-row behavior, but it still
  encodes the exact dangerous fallback behavior in tests that expect automatic
  drain to call `inbox:retrieve` when `retrieve_pending` is unsupported or when
  pending rows are malformed.
- `test/core/services/p2p_service_impl_test.dart` warm-start and resume tests
  still gate/assert `inbox:retrieve`, which means the constructor/type
  tightening and automatic-drain contract change must update adjacent startup
  proofs in the same slice.
- `test/core/services/p2p_service_stop_race_test.dart` instantiates
  `P2PServiceImpl` without a staging repository and gates `inbox:retrieve`,
  so the stop/dispose race suite is part of the same implementation seam once
  the staging repository becomes required.
- `test/core/lifecycle/background_reconnect_smoke_test.dart` and
  `test/core/lifecycle/connectivity_lifecycle_test.dart` already treat inbox
  drain as part of resume/startup behavior, which is why the startup/transport
  gate still matters for this report even though the destructive fallback is a
  1:1 reliability bug.
- `lib/core/services/p2p_service.dart` and
  `lib/core/services/p2p_service_impl.dart` still expose public
  `retrieveInbox()`, and repo search shows no current production caller under
  `lib/` beyond that interface/implementation pair. The report can therefore
  stay scoped to automatic drain behavior without pretending the public
  destructive API is already removed.
- Report `41` already landed the relay/bridge-side `retrieve_pending` plus
  `ack` contract, so this report is implementation-ready in one local Flutter
  session rather than needing another relay/Go prerequisite phase.

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Execution verdict | Closure docs touched | Blocker note | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Remove destructive fallback from automatic 1:1 inbox drain` | `implementation-ready` | `Test-Flight-Improv/48-gap3-remove-destructive-inbox-fallback-plan-session-1-plan.md` | none | `accepted` | `accepted` | `Test-Flight-Improv/48-gap3-remove-destructive-inbox-fallback-plan-session-breakdown.md`, `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`, `Test-Flight-Improv/00-INDEX.md` | none | Automatic drain now stays on durable `retrieve_pending` -> stage -> `ack`, skips malformed rows without destructive fallback, and keeps public `retrieveInbox()` intentionally out of scope. |

## Ordered session breakdown

### Session 1

- Title:
  `Remove destructive fallback from automatic 1:1 inbox drain`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/48-gap3-remove-destructive-inbox-fallback-plan-session-1-plan.md`
- Exact scope:
  - make `_inboxStagingRepository` non-nullable in `P2PServiceImpl` and remove
    the dead nullable branch from `_drainOfflineInbox()`
  - delete `fallbackToLegacyRetrieve(...)`,
    `_retrieveInboxPage(...)`, and `_continueDrainingOfflineInbox(...)` once no
    automatic drain path still depends on them
  - change `retrieve_pending` exception/error handling to emit explicit
    no-progress telemetry and leave relay rows untouched instead of switching
    to `inbox:retrieve`
  - change partially malformed page handling so valid entries still stage/ack
    while malformed rows are skipped and logged
  - update startup, warm-background, resume, and stop-race tests so they prove
    durable automatic drain semantics and absence of destructive fallback
  - refresh the stable 1:1 closure/maintenance docs after the implementation
    and proof land
- Why it is its own session:
  - this is one coherent Flutter-side automatic-drain seam
  - constructor tightening, fallback deletion, malformed-page behavior, and
    startup/resume test rewrites all share the same blast radius and the same
    named-gate contract
  - splitting code changes from proof or closure refresh would add bookkeeping
    only; the report is not closed until the same session both removes the
    fallback and proves it stayed removed across startup/resume behavior
- Likely code-entry files:
  - `lib/core/services/p2p_service_impl.dart`
  - `lib/main.dart`
  - `test/core/services/p2p_service_impl_test.dart`
  - `test/core/services/p2p_service_stop_race_test.dart`
  - `test/core/lifecycle/background_reconnect_smoke_test.dart`
  - `test/core/lifecycle/connectivity_lifecycle_test.dart`
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  - `Test-Flight-Improv/00-INDEX.md`
  - `Test-Flight-Improv/48-gap3-remove-destructive-inbox-fallback-plan-session-breakdown.md`
- Likely direct tests/regressions:
  - `test/core/services/p2p_service_impl_test.dart`
  - `test/core/services/p2p_service_stop_race_test.dart`
  - `test/core/lifecycle/background_reconnect_smoke_test.dart`
  - `test/core/lifecycle/connectivity_lifecycle_test.dart` if the final
    command-level assertions still mention destructive retrieve behavior
  - one new direct regression for the mixed valid-plus-malformed
    `retrieve_pending` page if the existing service suite does not already make
    the no-fallback requirement explicit enough
- Likely named gates:
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh transport`
  - `./scripts/run_test_gates.sh baseline`
- Matrix/closure docs to update when done:
  - required:
    - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
    - `Test-Flight-Improv/00-INDEX.md`
    - `Test-Flight-Improv/48-gap3-remove-destructive-inbox-fallback-plan-session-breakdown.md`
  - optional supporting refresh:
    - `Test-Flight-Improv/47-message-reliability-roadmap.md` if the team still
      wants the blocker ledger there to read as current state rather than
      historical rationale
- Dependency on earlier sessions:
  - none

## Reviewer pass

- Is the recommended session count sufficient, too coarse, or too fragmented:
  - sufficient; one local implementation session is the minimum safe set
- Which proposed sessions should merge:
  - none
- Which proposed sessions must split:
  - none
- What tests or named gates are missing from the decomposition:
  - direct service coverage must explicitly prove no automatic drain branch
    still calls `inbox:retrieve`
  - the `transport` gate must remain in scope because this seam still runs
    during warm start and resume, not just in isolated 1:1 business logic
- Does each session end in a meaningful verified state:
  - yes; Session `1` ends only when the destructive automatic-drain fallback is
    removed, adjacent startup/resume proofs are updated, and closure ownership
    is refreshed
- Is the matrix-update responsibility assigned clearly:
  - yes; Session `1` owns the stable closure refresh because there is only one
    meaningful implementation seam
- What is the minimum session set that is still safe:
  - `1`

## Arbiter outcome

- Structural blockers:
  - none
- Mergeable sessions:
  - none
- Required splits:
  - none
- Accepted differences:
  - public `retrieveInbox()` remains intentionally out of scope
  - malformed poison rows may still remain on the relay for later retry/expiry
    instead of gaining a new quarantine/cleanup architecture here

## Why this is not fewer sessions

- Zero sessions or a docs-only pass would leave the production fallback path
  intact.
- The report only closes when code, direct regressions, named gates, and
  closure refresh land together; treating any one of those as “follow-up later”
  would leave a misleading half-state.

## Why this is not more sessions

- No separate prerequisite session is justified because `retrieve_pending` plus
  `ack` already landed in Report `41`, and `lib/main.dart` already injects the
  staging repository in production.
- No separate acceptance-only session is justified because the same direct test
  family and the same named gates own the entire seam.
- No separate public-API cleanup session is justified for this report because
  repo evidence shows no production `lib/` caller currently depends on
  `retrieveInbox()`.

## Regression and gate contract

- Use `Test-Flight-Improv/14-regression-test-strategy.md` as the policy
  reference and `Test-Flight-Improv/test-gate-definitions.md` as the execution
  source of truth.
- Add or rewrite the direct regressions first for the escaped seam:
  - `retrieve_pending` throws or returns `ok != true` -> automatic drain
    returns safe no-progress and does not call `inbox:retrieve`
  - mixed valid plus malformed page -> valid entries still stage/ack/replay,
    malformed entries are skipped/logged, and no destructive fallback occurs
  - startup/resume/stop-race paths use the durable automatic-drain contract
    after constructor tightening
- Required direct suites:
  - `flutter test test/core/services/p2p_service_impl_test.dart`
  - `flutter test test/core/services/p2p_service_stop_race_test.dart`
  - lifecycle direct suites as needed if command-level assumptions change
- Required named gates after the direct suites:
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh transport`
  - `./scripts/run_test_gates.sh baseline`

## Matrix update contract

- Reuse the existing stable closure docs:
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  - `Test-Flight-Improv/00-INDEX.md`
- This breakdown artifact remains the doc-scoped execution ledger.
- Session `1` owns the closure update because there is no second independent
  implementation seam to wait for.
- Do not create a new matrix doc.
- If `Test-Flight-Improv/47-message-reliability-roadmap.md` is refreshed, keep
  it secondary to the stable closure docs above.

## Downstream execution path

- Session `1` should next go through:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Session 1 closure result

- Execution verdict:
  `accepted`
- Landed scope:
  - `lib/core/services/p2p_service_impl.dart` now keeps automatic drain on the
    durable `retrieve_pending` path, requires
    `_inboxStagingRepository` for that path, removes the dead automatic-drain
    destructive helpers, and returns safe no-progress instead of falling back
    to destructive `inbox:retrieve`
  - mixed valid-plus-malformed pending pages now still stage/ack/replay valid
    rows while skipped malformed rows emit explicit telemetry
  - direct service, stop-race, lifecycle, and transport-adjacent tests now
    prove durable automatic-drain semantics instead of encoding the legacy
    destructive fallback as correct behavior
- Direct proof run on `2026-04-03`:
  - `flutter test test/core/services/p2p_service_impl_test.dart`
  - `flutter test test/core/services/p2p_service_stop_race_test.dart`
  - `flutter test test/core/lifecycle/background_reconnect_smoke_test.dart`
  - `flutter test test/core/lifecycle/connectivity_lifecycle_test.dart`
  - `flutter test test/core/services/p2p_service_addresses_updated_test.dart`
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh 1to1`
  - `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport`
- Closure outcome:
  - the stable 1:1 closure reference and folder index now carry the
    maintenance-time meaning for this seam without overclaiming removal of the
    public destructive inbox API

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- `P2PService.retrieveInbox()` / `P2PServiceImpl.retrieveInbox()` remains a
  destructive public API and should not be silently described as fixed by this
  report unless a later dedicated session changes or removes it.
- A fully malformed relay page may still remain on the relay for later retry,
  TTL expiry, or manual cleanup; this report does not widen into poison-message
  quarantine architecture.
- No relay-server, Go-node, or bridge protocol work is reopened here because
  the durable staged fetch plus explicit ack contract is already part of the
  landed Report `41` surface.

## Exact docs/files used as evidence

- `Test-Flight-Improv/48-gap3-remove-destructive-inbox-fallback-plan.md`
- `Test-Flight-Improv/47-message-reliability-roadmap.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/00-INDEX.md`
- `lib/core/services/p2p_service.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/main.dart`
- `test/core/services/p2p_service_impl_test.dart`
- `test/core/services/p2p_service_stop_race_test.dart`
- `test/core/lifecycle/background_reconnect_smoke_test.dart`
- `test/core/lifecycle/connectivity_lifecycle_test.dart`

## Why the decomposition is safe to send into downstream planning/execution

- The proposal maps to one real remaining seam in the current repo: the
  Flutter automatic-drain fallback back to destructive `inbox:retrieve`.
- The split does not invent extra prerequisite work because the durable
  relay/bridge contract is already landed and production already injects the
  staging repository.
- The required proof family is explicit: direct service/lifecycle regressions
  plus the existing `1to1`, `transport`, and `baseline` gates.
- The closure docs are named up front, so execution does not stop at “tests
  passed” while leaving the maintenance-time reliability contract stale.

## Final program acceptance review

- Sessions processed:
  `1`
- Sessions accepted:
  `1`
- Sessions accepted_with_explicit_follow_up:
  none
- Sessions blocked:
  none
- Sessions skipped_due_to_dependency:
  none
- Final program acceptance verdict:
  `closed`
- Final program blocker:
  none
- Why the rollout is safe to complete:
  - no automatic production path remains from `retrieve_pending` back to
    destructive `inbox:retrieve`
  - warm start, resume, and explicit `drainOfflineInbox()` stay on durable
    stage-then-ack semantics; error cases leave relay rows untouched and mixed
    malformed pages still recover valid entries
  - the direct suites plus `baseline`, `1to1`, and device-backed `transport`
    all passed on `2026-04-03`
  - the stable closure docs now encode the narrow truth that automatic drain is
    durable while public `retrieveInbox()` removal stays intentionally out of
    scope
