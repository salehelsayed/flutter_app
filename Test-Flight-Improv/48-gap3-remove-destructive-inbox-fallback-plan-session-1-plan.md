# Session 1 Plan - Remove Destructive Fallback From Automatic 1:1 Inbox Drain

## Final verdict

`implementation-ready`

Current repo evidence still matches the Report `48` breakdown: the automatic
offline inbox drain in
`lib/core/services/p2p_service_impl.dart` can still fall from durable
`inbox:retrieve_pending` back to destructive `inbox:retrieve`, and the direct
service/lifecycle tests still encode that fallback as expected behavior.
Because production wiring in `lib/main.dart` already injects an inbox staging
repository, this session can stay local to the Flutter tree and close the
automatic-drain seam without widening into relay or public-API cleanup work.

## Final plan

### real scope

What changes in this session:

- make `_inboxStagingRepository` non-nullable in `P2PServiceImpl` and land the
  constructor seam coherently across direct callers/tests
- remove the automatic-drain fallback from `_retrievePendingInboxPage(...)` so
  `retrieve_pending` exception/error/noisy-page cases return safe no-progress
  results instead of switching to `inbox:retrieve`
- change malformed-page handling so valid entries still stage/ack/replay while
  malformed rows are skipped with explicit telemetry
- delete dead automatic-drain legacy helpers once no durable drain path still
  uses them:
  - `fallbackToLegacyRetrieve(...)`
  - `_retrieveInboxPage(...)`
  - `_continueDrainingOfflineInbox(...)`
  - `_emitInboxMessages(...)` if it becomes legacy-only dead code
- update the direct service, stop-race, and lifecycle proofs so automatic drain
  now means durable `retrieve_pending` semantics and absence of destructive
  fallback
- refresh the stable closure docs and the current breakdown ledger after the
  implementation and proof land

What does not change in this session:

- no relay/server or Go bridge protocol redesign; Report `41` already landed
  staged retrieve plus ack
- no claim that public `retrieveInbox()` is removed or made non-destructive
- no new quarantine/cleanup architecture for permanently malformed relay rows
- no broader transport/lifecycle redesign beyond the constructor/drain seam
- no new matrix doc or gate-definition rewrite

### closure bar

Session `1` is sufficient only when all of the following are true:

- warm start, resume, and explicit `drainOfflineInbox()` stay on the durable
  staged path and do not automatically call `inbox:retrieve`
- `retrieve_pending` exception or `ok != true` responses leave relay rows
  untouched and return a safe no-progress result
- partially malformed pages still stage/ack/replay valid entries, log the
  malformed skips explicitly, and do not abandon the whole page to destructive
  fallback
- direct regressions prove the automatic drain path no longer calls
  `inbox:retrieve`
- the required named gates pass
- the stable 1:1 closure docs and the current breakdown ledger reflect the
  narrower truth honestly: automatic drain is durable, but the public
  destructive inbox API remains intentionally out of scope

### source of truth

Authoritative inputs for this session:

- session controller artifact:
  `Test-Flight-Improv/48-gap3-remove-destructive-inbox-fallback-plan-session-breakdown.md`
- proposal/spec:
  `Test-Flight-Improv/48-gap3-remove-destructive-inbox-fallback-plan.md`
- regression policy:
  `Test-Flight-Improv/14-regression-test-strategy.md`
- named gate policy:
  `Test-Flight-Improv/test-gate-definitions.md`
- stable closure docs to refresh:
  `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  `Test-Flight-Improv/00-INDEX.md`

Current repo evidence that governs this plan:

- `lib/core/services/p2p_service_impl.dart` still declares
  `_inboxStagingRepository` nullable, defines
  `fallbackToLegacyRetrieve(...)`, and routes `_retrievePendingInboxPage(...)`
  into `_retrieveInboxPage(...)` on `retrieve_pending` exception, error, or
  unstageable-page conditions
- `lib/core/services/p2p_service_impl.dart` still keeps the legacy destructive
  helpers `_retrieveInboxPage(...)`, `_continueDrainingOfflineInbox(...)`, and
  the nullable branch in `_drainOfflineInbox()`
- `lib/main.dart` already constructs `InboxStagingRepositoryImpl` and injects
  it into `P2PServiceImpl`, so production bootstrap is already on the durable
  path once the type is tightened
- `test/core/services/p2p_service_impl_test.dart` already covers staged happy
  path, ack, replay, and retryable staged-row behavior, but it still includes
  tests that explicitly expect automatic drain to fall back to
  `inbox:retrieve`
- `test/core/services/p2p_service_stop_race_test.dart`,
  `test/core/lifecycle/background_reconnect_smoke_test.dart`, and
  `test/core/lifecycle/connectivity_lifecycle_test.dart` still instantiate
  `P2PServiceImpl` without a staging repository and/or still describe drain in
  destructive `inbox:retrieve` terms

Conflict rules:

- the session breakdown controls scope, ordering, and closure ownership unless
  current repo evidence proves it stale
- current code and tests beat stale prose
- `scripts/run_test_gates.sh` is the execution source of truth if it ever
  disagrees with `test-gate-definitions.md`

### session classification

`implementation-ready`

### exact problem statement

The automatic 1:1 offline inbox drain is still unsafe in current Flutter code.
Even though the repo now has durable staged retrieve plus explicit ack support,
three automatic-drain branches still switch back to destructive
`inbox:retrieve`:

- staging repository nullable path
- `retrieve_pending` exception / `ok != true`
- any page containing one unstageable raw message

That means automatic inbox recovery can still delete relay rows before Flutter
has durably staged and replayed them. The direct service/lifecycle tests also
still encode that unsafe behavior as expected, so Report `48` is not closed
until code, direct proofs, named gates, and closure docs all move together.

User-visible behavior that must improve:

- automatic inbox recovery prefers delay/retry over destructive message loss
- valid inbox entries continue to recover even when some rows are malformed
- startup/resume behavior stays truthful after the staging-repository seam is
  tightened

Behavior that must stay unchanged unless current code proves otherwise:

- public `retrieveInbox()` remains available and intentionally out of scope
- staged happy-path replay/ack semantics stay intact
- poison rows may remain on the relay for later retry/expiry rather than
  gaining a new cleanup subsystem here

### files and repos to inspect next

Production files:

- `lib/core/services/p2p_service_impl.dart`
- `lib/main.dart`

Direct tests:

- `test/core/services/p2p_service_impl_test.dart`
- `test/core/services/p2p_service_stop_race_test.dart`
- `test/core/lifecycle/background_reconnect_smoke_test.dart`
- `test/core/lifecycle/connectivity_lifecycle_test.dart`

Closure docs:

- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/00-INDEX.md`
- `Test-Flight-Improv/48-gap3-remove-destructive-inbox-fallback-plan-session-breakdown.md`
- optional supporting refresh only if needed:
  `Test-Flight-Improv/47-message-reliability-roadmap.md`

### existing tests covering this area

Already covered today:

- `test/core/services/p2p_service_impl_test.dart` proves the durable staged
  happy path, ack-after-stage flow, and replay/retryable outcomes
- the same suite already exercises `retrieve_pending` error cases and malformed
  rows, but it currently encodes legacy fallback-to-`inbox:retrieve`
  expectations that must be rewritten
- `test/core/services/p2p_service_stop_race_test.dart` covers stop/dispose
  behavior during reconnect/inbox-drain races, which becomes part of this seam
  once the staging repository is required
- lifecycle tests under `test/core/lifecycle/*.dart` already treat inbox drain
  as part of resume/startup behavior and therefore are part of the same blast
  radius

Missing or stale today:

- no direct regression yet proves `retrieve_pending` exception/error returns
  safe no-progress without any automatic `inbox:retrieve` call
- no direct regression yet proves mixed valid-plus-malformed pages still
  stage/ack/replay the valid rows while skipping the malformed row(s)
- startup/resume and stop-race tests still need coherent constructor wiring and
  automatic-drain assertions aligned with the durable path

### regression/tests to add first

Add or rewrite these direct proofs before trusting broader gates:

- in `test/core/services/p2p_service_impl_test.dart`:
  - `retrieve_pending` throws -> automatic drain returns safe no-progress and
    does not call `inbox:retrieve`
  - `retrieve_pending` returns `ok != true` -> same no-progress / no-fallback
    result
  - mixed valid plus malformed page -> valid rows stage/ack/replay, malformed
    rows are skipped/logged, and no destructive fallback occurs
  - if needed, all-malformed page -> no-progress result with truthful `hasMore`
    handling and no destructive fallback
- in `test/core/services/p2p_service_stop_race_test.dart`:
  - tighten constructor setup around the required staging repository and keep
    the stop/race assertions on the durable drain path
- in lifecycle tests:
  - update any direct command assertions or comments that still assume
    `drainOfflineInbox()` may call `inbox:retrieve`

### step-by-step implementation plan

1. Re-read the active automatic-drain seam in
   `lib/core/services/p2p_service_impl.dart` and the direct tests before
   editing. Merge carefully with unrelated local changes already in the tree.
2. Tighten the constructor seam: make `_inboxStagingRepository` non-nullable,
   remove the dead nullable branch from `_drainOfflineInbox()`, and update all
   direct instantiations touched by this seam coherently.
3. Remove `fallbackToLegacyRetrieve(...)` from
   `_retrievePendingInboxPage(...)`. Replace the exception/error branches with
   explicit telemetry plus safe `(replayed: 0, staged: 0, hasMore: false)` or
   equivalent no-progress results that leave relay rows untouched.
4. Change raw-message staging so malformed rows are skipped individually while
   valid entries still proceed through stage -> ack -> replay. Emit explicit
   telemetry for skipped malformed rows.
5. Delete dead automatic-drain legacy helpers once the durable path no longer
   references them. Keep public `retrieveInbox()` untouched unless a compile
   error proves a narrower helper extraction is necessary.
6. Rewrite/add the direct regressions listed above so the dangerous legacy
   fallback behavior is no longer encoded as correct.
7. Run the exact direct suites and required named gates below.
8. Refresh the stable closure docs and the current breakdown ledger so they
   reflect the landed result without overclaiming broader destructive-API
   removal.
9. Stop and re-evaluate if execution unexpectedly requires relay/bridge
   changes, public API removal, new poison-row cleanup architecture, or a
   broader startup/transport redesign. Those are outside Report `48` Session
   `1`.

### risks and edge cases

- mixed pages must not lose valid entries just because one row is malformed
- ack should stay bounded to staged entries only; malformed skipped rows should
  not be acked accidentally
- the required constructor seam must land coherently across service, stop-race,
  and lifecycle tests in one pass to avoid half-wired compile failures
- returning no-progress on `retrieve_pending` failure changes the old
  fail-open behavior; that is the intended tradeoff because delayed delivery is
  safer than destructive loss
- closure docs must not overstate the result as “all destructive inbox APIs are
  gone”

### exact tests and gates to run

Direct tests:

- `flutter test test/core/services/p2p_service_impl_test.dart`
- `flutter test test/core/services/p2p_service_stop_race_test.dart`
- `flutter test test/core/lifecycle/background_reconnect_smoke_test.dart`
- `flutter test test/core/lifecycle/connectivity_lifecycle_test.dart`
  if the final constructor/drain assertions or comments require lifecycle-file
  changes; otherwise confirm why it stayed untouched

Required named gates:

- `./scripts/run_test_gates.sh 1to1`
- `./scripts/run_test_gates.sh transport`
- `./scripts/run_test_gates.sh baseline`

### known-failure interpretation

- There is no accepted known-failure exemption for retaining automatic
  `inbox:retrieve` fallback in this session. If direct proofs still show that
  fallback, the session is not done.
- A pre-existing unrelated failure elsewhere in the repo should be recorded
  explicitly, but it does not waive the direct service/lifecycle suites or the
  named gates required by this session.
- If `transport` exposes an unrelated pre-existing integration harness issue,
  record the exact failing file and why it is judged pre-existing before
  calling the session blocked or accepted with follow-up.

### done criteria

- `_inboxStagingRepository` is required for `P2PServiceImpl` and the direct
  constructor seam compiles/tests coherently
- automatic drain no longer calls `inbox:retrieve` on
  `retrieve_pending` exception, error, or malformed-page conditions
- valid rows from mixed pages still stage/ack/replay while malformed rows are
  skipped/logged
- required direct suites pass
- required named gates pass
- closure docs and the breakdown ledger are refreshed to the narrower truthful
  closure state

### scope guard

Stop and re-evaluate if any of these become necessary:

- relay/server or Go-bridge protocol changes
- removal or redesign of public `retrieveInbox()`
- a new quarantine, journaling, or cleanup subsystem for poison rows
- broad lifecycle or transport architecture changes beyond the durable drain
  seam
- gate-definition or roadmap redesign instead of a local closure refresh

### accepted differences / intentionally out of scope

- public `retrieveInbox()` remains intentionally out of scope for Report `48`
- malformed poison rows may remain on the relay for later retry/expiry instead
  of gaining a new cleanup architecture here
- this session hardens only the automatic 1:1 inbox drain seam, not every
  possible historical destructive inbox helper in the repo

### dependency impact

- Session `1` is the only runnable session in the Report `48` breakdown, so a
  successful landing allows the breakdown artifact itself to become the
  maintenance-time closure ledger for this report
- later 1:1 maintenance work should reuse the refreshed closure docs rather
  than reopening Report `48` unless a real automatic-drain regression appears
- if this session unexpectedly cannot be closed without public API cleanup or
  relay changes, the breakdown must record that as a real blocker rather than
  silently broadening scope

## Structural blockers remaining

- none

## Incremental details intentionally deferred

- whether `Test-Flight-Improv/47-message-reliability-roadmap.md` needs a
  supporting wording refresh should be decided after the actual landed diff;
  it is not required for execution safety

## Accepted differences intentionally left unchanged

- public destructive `retrieveInbox()` remains available
- poison-row expiry/cleanup remains a separate future concern, not part of
  this session

## Exact docs/files used as evidence

- `Test-Flight-Improv/48-gap3-remove-destructive-inbox-fallback-plan-session-breakdown.md`
- `Test-Flight-Improv/48-gap3-remove-destructive-inbox-fallback-plan.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/00-INDEX.md`
- `lib/core/services/p2p_service_impl.dart`
- `lib/main.dart`
- `test/core/services/p2p_service_impl_test.dart`
- `test/core/services/p2p_service_stop_race_test.dart`
- `test/core/lifecycle/background_reconnect_smoke_test.dart`
- `test/core/lifecycle/connectivity_lifecycle_test.dart`

## Why the plan is safe to implement now

The plan stays inside one coherent Flutter-side seam that the repo already
exposes clearly: automatic staged inbox drain plus its direct startup/resume
proofs. The production prerequisite wiring is already present in `lib/main.dart`,
the dangerous fallback branches are concrete and localized in
`p2p_service_impl.dart`, and the direct tests already sit on the same seam.
That makes this session narrow enough to implement without inventing new
architecture while still requiring the exact proofs and named gates needed to
close the escaped bug honestly.
