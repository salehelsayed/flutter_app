# 325 - Accept-Invite Drain Reaction Custody

Status: execution-ready
Type: Bug
Spec: free-text intent — the 5th drain site dropped from plan 322 by `/tdd-review`; no formal spec
Classification: implementation-ready
Closure tier: host (Dart feature tier). No relay, no migration, no deploy.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-02 | Evidence Collector | `accept_pending_group_invite_use_case.dart`, `group_message_listener.dart`, `drain_group_offline_inbox_use_case.dart`, `group_message_listener_reaction_ingress_processor.dart` | The review's "post-accept flush" alternative is a no-op — it replays buffered rows and nothing is buffered | Find a cheaper seam than 10-file threading |
| 2026-08-02 | Planner (verify→refute `wf_4136e17c-b79`, 3 agents) | `orbit_wired.dart`, `production_application_bootstrap.dart`, `group_message_listener_decomposition_contract_test.dart`, `group_media_reliability_wiring_test.dart`, relay backends | Design B confirmed; 2 deterministic reorderings found; 3 mandatory riders | Emit contract |

## Problem And Evidence

- **Behavior to improve:** accepting a group invite drains that group's relay inbox. A drained reaction whose target message has not landed yet is **permanently discarded** instead of buffered. This is the 5th of the 5 unwired drain lanes; plan 322 (`6d52d2d3b`) closed the other four.
- **Impact:** a reaction left on your message is silently missing after you join a group. Unrecoverable — the drain commits its cursor unconditionally (below), and there is no group ack/delete verb, so the relay never re-serves it.
- **Confirmed root cause:** `_drainAcceptedGroupInboxBestEffort` (`accept_pending_group_invite_use_case.dart:1217-1254`) calls `drainGroupOfflineInboxForGroup` at `:1230` and passes **no** `pendingReactionRepo`, although that function accepts one (`drain_group_offline_inbox_use_case.dart:282`, forwarded `:311`). Without it `handleIncomingGroupReaction` emits `GROUP_REACTION_RECEIVE_UNKNOWN_MESSAGE` and drops (`handle_incoming_group_reaction_use_case.dart:203-214`) rather than buffering (`:182-202`).
- **Permanence confirmed:** `drain_group_offline_inbox_use_case.dart:1015-1026` computes `_durableNextGroupInboxCursor` and commits it via `runInboxPageTransaction` on **every** page, unconditionally, after `processDecodedPayload` has run. Relay-cursor form resumes at `startIdx = i+1` (`inbox.go:1820-1827`); the synthetic form becomes `mknoon-since-ms:<maxTs-1>` (`:1207-1228`) which the relay filters with `message.Timestamp <= sinceTimestamp` (`backend_redis.go:712-714`). The entry is never re-served.
- **Reachability — deterministic, not a race.** The relay itself preserves order (append-to-tail Redis LIST, no sort: `backend_redis.go:672-678`, `:694-717`), so the wire always puts the target first. The window is opened *inside the drain*, by two client-side reorderings:
  1. **Unknown-sender deferral inverts target/reaction within one page.** `_shouldDeferUnknownSenderReplay` (`drain_group_offline_inbox_use_case.dart:2233-2245`) returns true **only** for `payloadType == group_message` (`:2245`); deferred messages replay in a second pass that runs after the entire first pass (`:963-990`). Reactions are never deferred (`:959`). So a page `[M(unknown_sender), R(on M)]` processes R first, finds no target, and drops it — while M lands in pass 2. `unknown_sender` is precisely the freshly-accepted-group condition, because the roster is being materialized by this same accept flow.
  2. **The membership flush straddles the drain.** `accept_pending_group_invite_use_case.dart:429` flushes buffered messages → `:434` drains → `:447` flushes again. A target buffered pre-accept lands at `:447`, one statement after the drain at `:434` discarded its reaction.
- **Existing coverage:** `drain_group_offline_inbox_use_case_test.dart:13340` (INV-R4) proves buffering works *when the repo is supplied*. Plan 322's census `TC-322-02` (`group_media_reliability_wiring_test.dart:436-445`) enumerates exactly five production files — **accept is not among them**, which is the mechanical reason 322 missed this lane.
- **Missing coverage:** no test drives reaction custody through `acceptPendingGroupInvite`; no test pins that the single production `GroupMessageListener` construction carries the repo.
- **Refuted findings (do NOT re-introduce):**
  - *"Trigger the post-accept startup flush instead of threading the repo"* (the review's suggested alternative) — **refuted**. `_flushStartupDurablePendingReactions` (`group_message_listener_reaction_ingress_processor.dart:198-213`) reads only `repo.getPendingReactions(...)`; it replays **already-buffered** rows. Nothing is buffered here, so it has nothing to replay. It is a replay mechanism, not an ingestion one.
  - *"Design A — thread the repo through 6 private functions and 4 widget public APIs"* — **refuted as pure cost**. Exactly one `GroupMessageListener(` exists in `lib` (`production_application_bootstrap.dart:3746`) and it always receives the repo (`:3797`, the same instance created at `:2584`); and where the listener is null the accept lane is unreachable (`orbit_wired.dart:1595-1601` returns before accept when `groupMessageListener == null`). A threads the same object through a chain that already carries it.
  - *"Don't drain on accept; let resume/retrier do it"* — **refuted**. The drain result is load-bearing: `accept_pending_group_invite_use_case.dart:465-473` rolls back and returns `bridgeError` when `!inboxDrained && !acceptedGroupAdvanced`.
  - *"Fall back inside the drain (`pendingReactionRepo ?? listener?.repo`)"* — **refuted**. It would silently defeat the per-call-site census: a future lane could omit the argument and still be correct-by-fallback, so plan 322's only regression pin stops meaning anything.
- **Unresolved findings:** none.
- **Affected production / test / gate files:** `accept_pending_group_invite_use_case.dart`, `group_message_listener.dart`; `accept_pending_group_invite_use_case_test.dart`, `group_media_reliability_wiring_test.dart`, `group_message_listener_decomposition_contract_test.dart`.

## Graph Grounding Snapshot
- Graph fingerprint / freshness: refreshed 2026-08-02 via `/claude-host-bin/host-run bash ./graphify-arch/refresh_arch_graph.sh --incremental` (`REFRESH_EXIT=0`) after the stale marker appeared post-`6d52d2d3b`.
- Query / profile: `python3 graphify-arch/tdd_context.py query "accept_pending_group_invite drain accepted group inbox best effort pending reaction buffer" --profile tdd --budget 700` → `confidence=broad`, anchors unhelpful; grounding done by direct source reads and a 3-agent verify→refute (`wf_4136e17c-b79`).
- Anchors: `_drainAcceptedGroupInboxBestEffort`, `drainGroupOfflineInboxForGroup`, `GroupMessageListener._pendingReactionRepo`.
- Surfaced proof/gate files: `accept_pending_group_invite_use_case_test.dart`, `group_media_reliability_wiring_test.dart`, `group_message_listener_decomposition_contract_test.dart`.
- Graph gaps that required raw source search: the accept-lane call chain, the frozen-facade contract, and the Go relay ordering (Go is out of graph scope by design).
- Reuse rule: anchors are search starting points; every conclusion is re-verified in current source.

## Scope Contract And Guard

In scope:
- Expose the pending-reaction repository from `GroupMessageListener` and use it at `accept_pending_group_invite_use_case.dart:1230`, so the accept lane buffers instead of dropping.
- Extend plan 322's drain census to cover the accept lane.
- Pin the invariant design B depends on: the production listener always carries the repo.

Must preserve:
- Accept semantics — a failed drain still rolls back and returns `bridgeError` (`:465-473`) → TC-325-05 GREEN sentinel.
- The accept lane emits no notifications → TC-325-06 GREEN sentinel.
- The frozen facade contract stays meaningful — amended deliberately, not deleted → TC-325-03.
- Buffer bounds (7d TTL + 50/group cap, `handle_incoming_group_reaction_use_case.dart:12`, `:374-380`) unchanged.

Hard `Do not`:
- Do not add a `??` fallback inside the drain (defeats the census — see Refuted).
- Do not thread the repo through the widget tree (Design A — refuted as pure cost).
- Do not add a public *method* to `GroupMessageListener`; a getter matching the `appendGroupEventLogEntry` precedent (`:339`, frozen at contract `:311`) is the whole seam.
- Do not change drain ordering, the unknown-sender deferral, or the pre-join skip. Those are the *conditions* that expose the defect, not the defect.

Deferred / accepted difference:
- **Reactions are exempt from both the pre-join replay skip and the client retention gate**, while messages are not (`drain_…:577-580`, `:636-644`; the reaction projection at `:2080-2087` emits no top-level `timestamp`). So a reaction whose target was pre-join-skipped will buffer and then expire at TTL — correct, but invisible. Not this plan's defect; recorded because it means TC-325-01 must use a fixture where the target *does* land.
- **Relay authorization asymmetry:** reaction recipients are computed with no `joinedAt` cutoff and no invite-status filter (`send_group_reaction_use_case.dart:429-471`), unlike messages (`send_group_message_use_case.dart:113-124`, `:195-201`). A joiner can therefore legitimately receive reactions whose targets the relay will never serve them. Owner: notification-reliability wave. Not fixed here.

Dependencies:
- Builds on plan 322 (`6d52d2d3b`), whose census this plan extends.

## Test Contract
Zero empty cells.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| TC-325-01 | Accepting an invite buffers a drained reaction whose target has not landed | `accept_pending_group_invite_use_case_test.dart::325 accept-invite drain buffers a target-absent reaction` | unit / real `GroupMessageListener` + `InMemoryGroupPendingReactionRepository` (the file already builds real listeners at `:885`…`:2128`) | causal RED (HEAD drops it: zero buffered rows, `GROUP_REACTION_RECEIVE_UNKNOWN_MESSAGE` emitted) → 1 buffered row with matching id/messageId, and NO `…UNKNOWN_MESSAGE` | remove `pendingReactionRepo:` at `accept_…:1230` → TC-325-01 red | `flutter test test/features/groups/application/accept_pending_group_invite_use_case_test.dart`; AUTO (`GROUP_TESTS` `:466`) |
| TC-325-02 | The drain census covers the accept lane | `group_media_reliability_wiring_test.dart::TC-322-02 every production group-inbox drain forwards pendingReactionRepo` (extended) | unit / source census | causal RED (accept file added to the `sites` map at `:436-445` while HEAD's `:1230` lacks the argument) → all six files pass | drop the accept entry from the map → the census silently stops covering it (guarded by TC-325-01, which is behavioral) | same file; AUTO (`GROUP_TESTS`) |
| TC-325-03 | The frozen facade contract is amended deliberately, not broken | `group_message_listener_decomposition_contract_test.dart::(existing public-member equality test)` | unit / reflection over the facade | causal RED (a new getter breaks the `_expectedPublicMembers` equality at `:307-327`) → green after adding the getter's entry, modelled on `:311` | remove the new entry from `_expectedPublicMembers` → TC-325-03 red | `flutter test test/features/groups/application/group_message_listener_decomposition_contract_test.dart`; AUTO (`GROUP_TESTS` `:567`) |
| TC-325-04 | The invariant design B rests on: the production listener always carries the repo | `group_media_reliability_wiring_test.dart::325 the production GroupMessageListener is constructed with a pending-reaction repo` | unit / source census over `production_application_bootstrap.dart` | GREEN sentinel (true today at `:3746`/`:3797`) → still true | delete `pendingReactionRepo:` from the listener construction → TC-325-04 red | same file; AUTO (`GROUP_TESTS`) |
| TC-325-05 | Accept still rolls back when the drain fails | `accept_pending_group_invite_use_case_test.dart::(existing bridgeError/rollback tests)` | unit / fakes | GREEN sentinel → unchanged | make `_drainAcceptedGroupInboxBestEffort` swallow failure and return `true` → existing rollback test reds | same as TC-325-01 |
| TC-325-06 | The accept drain still emits no notification | `accept_pending_group_invite_use_case_test.dart::325 accept-invite drain shows no reaction notification` | unit / `FakeNotificationService` + tracker, self-authored non-incoming target | GREEN sentinel → `notifications.shown` empty | add a notify to the drain's reaction branch → TC-325-06 red | same as TC-325-01 |

### Test Notes
- **TC-325-01 fixture must reproduce reordering (i)**, which is deterministic: seed a page `[M(unknown sender), R(on M)]` so `_shouldDeferUnknownSenderReplay` defers M to pass 2 while R is processed in pass 1. A fixture where the target simply never exists would buffer-then-expire and prove the wrong thing (see Deferred).
- **Discriminator:** assert the buffered row **AND** absence of `GROUP_REACTION_RECEIVE_UNKNOWN_MESSAGE`. Both HEAD and fixed behaviour return a successful-looking drain result, so the row alone does not distinguish drop from buffer.
- **TC-325-02 cannot prove non-null.** Design B satisfies the census textually (`pendingReactionRepo: groupMessageListener?.…` contains the token), so the census is a wiring pin only — TC-325-01 carries the behavioural weight. This is why TC-325-01 is mandatory rather than a nice-to-have.
- TC-325-04 exists solely to close the strongest argument against design B: correctness depends on an invariant the type system does not express. A second listener construction built without the repo would silently reopen the defect while TC-325-02 stayed green. This row makes that invariant a test.

## Implementation Steps
1. Snapshot `git status --short`. Add TC-325-01/02/06 first; confirm 01 and 02 red for the documented reasons, and 06 green.
2. Add to `group_message_listener.dart` a public getter beside `appendGroupEventLogEntry` (`:339`):
   `GroupPendingReactionRepository? get pendingReactionRepository => _pendingReactionRepo;`
   Stop-if: if the field's nullability or ownership has changed such that a getter cannot express it, stop and reconsider design A rather than widening the facade further.
3. At `accept_pending_group_invite_use_case.dart:1230`, pass `pendingReactionRepo: groupMessageListener?.pendingReactionRepository`.
4. Amend `_expectedPublicMembers` (`group_message_listener_decomposition_contract_test.dart:307-327`) with the getter's entry, modelled on `:311`.
5. Add `'lib/features/groups/application/accept_pending_group_invite_use_case.dart': 'drainGroupOfflineInboxForGroup('` to the census `sites` map (`group_media_reliability_wiring_test.dart:436-445`). The map's `bridge:` filter (`:452`) matches the accept invocation, which passes `bridge: bridge` at `:1231`.
6. Add TC-325-04's construction census.
7. Run focused GREEN → sentinels → graph-affected → the `groups` lane.

## Risks And Blind Spots
- **Design B rests on an unexpressed invariant** ("the listener always carries the repo") → made explicit by TC-325-04.
- **Spending a frozen architectural boundary.** `DTR-16 must not expose collaborators or new public facade state` (contract test `:488`). This is the *second* exception after `appendGroupEventLogEntry`, and a second exception is what turns a rule into a negotiable default. Accepted deliberately: the alternative threads the same object through 4 widget public APIs, feeding the silent-omission class that already needed its own freeze test (TC-322-02b).
- Lifecycle / derived-state durability: `_pendingReactionRepo` is `final` (`:147`); `stop()`/`dispose()` never null it, so the getter stays readable. Buffer writes on a stopped listener are bounded by TTL + cap and are the same class the accept lane already performs (it persists messages and reactions in that identical window, `:440`, `:513`, `:855`).
- Sibling-surface consistency: all three accept-lane drain sites (`:434`, `:507`, `:849`) funnel through `_drainAcceptedGroupInboxBestEffort:1230`, so one edit covers them → census TC-325-02.
- Destructive-action side effects: none — the change only adds a durable write where one was previously discarded.
- Invariant re-verification under new transitions: INV-R4 now applies on the accept lane → TC-325-01.
- Construction/call-site census: `grep -n '_drainAcceptedGroupInboxBestEffort\|_drainAcceptedGroupInboxWithRetry' lib` — re-derive at execution; every caller already carries a listener (verified `wf_4136e17c-b79`).
- Build-artifact provenance: N/A — no native artifact.
- Permission/ACL verb symmetry: N/A — no ACL change; the relay is untouched.
- Notification storm: N/A — this plan emits nothing (TC-325-06 locks it).

## Gate Cadence
- Per-plan closure: TC-325-01..04 focused + TC-325-05/06 sentinels + the `groups` curated lane.
- Graph-affected first: after the production edits and BEFORE the lane, run `tdd_context.py affected lib/features/groups/application/accept_pending_group_invite_use_case.dart lib/features/groups/application/group_message_listener.dart --budget 600` and run the test files it names directly.
- Full `host-all` is **not** a per-plan gate. Owned by the notification-reliability wave closure and again at final rollout.
- Shared tests outside the feature/core globs: N/A — none touched.

## Acceptance Gates  (literal — copy/paste)
```bash
git status --short

# Causal RED (before production edits) — must FAIL for the documented reason
flutter test test/features/groups/application/accept_pending_group_invite_use_case_test.dart \
  --plain-name '325 accept-invite drain buffers a target-absent reaction'

# Focused GREEN (after the fix) — exit 0, zero failures
flutter test test/features/groups/application/accept_pending_group_invite_use_case_test.dart
flutter test test/features/groups/integration/group_media_reliability_wiring_test.dart
flutter test test/features/groups/application/group_message_listener_decomposition_contract_test.dart

# Graph-affected dependents BEFORE the lane
python3 graphify-arch/tdd_context.py affected \
  lib/features/groups/application/accept_pending_group_invite_use_case.dart \
  lib/features/groups/application/group_message_listener.dart --budget 600

# Curated lane — exit 0
./scripts/run_test_gates.sh groups

# Registration is grep-verified, never run-verified
grep -c 'test/features/groups/application/accept_pending_group_invite_use_case_test.dart' scripts/run_test_gates.sh    # expect: 1
grep -c 'test/features/groups/application/group_message_listener_decomposition_contract_test.dart' scripts/run_test_gates.sh # expect: 1
./scripts/run_test_gates.sh completeness-check   # expect: PASS, 0 unmatched

# Hygiene
flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria
- Expected RED: TC-325-01 (reaction dropped, zero buffered rows, `GROUP_REACTION_RECEIVE_UNKNOWN_MESSAGE` present), TC-325-02 (accept file added to the census while `:1230` lacks the argument), TC-325-03 (the new getter breaks the frozen public-member equality until its entry is added).
- GREEN sentinel: TC-325-04 (production listener carries the repo), TC-325-05 (rollback intact), TC-325-06 (no notification).
- Pre-existing dirty tree / known failure: the three user-owned claude-docker files — never staged.
- Environment blocker (NOT a product blocker): none — host-only closure.
- Scope drift (BLOCKING): any `??` fallback inside the drain; any widget-tree threading; any change to drain ordering, the unknown-sender deferral, or the pre-join skip.

- [ ] Every behavior has a named test or a justified proof.
- [ ] Causal RED, focused GREEN, and representative mutation re-red are recorded.
- [ ] Preservation sentinels and named gates pass with semantic outcomes.
- [ ] Harness registration is implemented AND verified.
- [ ] Conditional migration / device / relay proof passes when applicable — N/A.
- [ ] `flutter analyze` has no new issues; `git diff --check` is clean.
- [ ] The Scope Contract And Guard is respected.

## Handoff
- First causal RED command: `flutter test test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name '325 accept-invite drain buffers a target-absent reaction'`.
- Preservation command: `flutter test test/features/groups/application/group_message_listener_decomposition_contract_test.dart`.
- Manual registration: none — all three touched test files are already in `GROUP_TESTS` (`:466`, `:567`, and the wiring file).
- Migration: none.
- Boundary closure: host-only. No device leg — this plan emits nothing at the OS boundary.
- Unresolved evidence: none.

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | awaiting accepted plan | contract extraction |
