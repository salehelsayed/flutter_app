# 264 - Durable “Leave When Sync Completes” For Pending Role Broadcasts

Status: planned v3 (recommendation selected and review findings folded in
2026-07-20); execution prerequisite-blocked on Plan 263's immutable handoff
Type: Bug + reliability hardening + UX
Spec: when a signed role change is still pending, leaving must remain safe without
trapping the user on the current screen or pretending uncertain delivery never
happened
Classification: post-263 DB/schema + application + lifecycle + wired UI
Closure tier: host causal proof, real SQLite/SQLCipher boundary proof, one existing
Go idempotence contract; no new relay, wire, crypto, native-handler, or two-peer
production behavior

## Selected Product Decision

The prior terminal-policy blocker is resolved in favor of a durable queued exit:

1. When a fresh Leave snapshot contains a role-kind row, the app performs exactly
   one coordinated immediate Retry of that group's pending broadcasts. A no-role
   Leave does not pay this network delay.
2. If every fresh role-kind row is gone (initially or after Retry), the app persists
   an exit intent and starts the normal signed leave immediately.
3. If a role row remains, the recovery sheet shows:
   - title: **Finishing a role change**;
   - body: **You can leave this screen. We’ll leave the group as soon as the role
     update is safely delivered.**;
   - primary: **Leave when sync completes**;
   - secondary: **Try again**;
   - tertiary: **Stay in group**.
4. Choosing the primary action persists the intent before dismissing the sheet and
   returns the user to the group list/Orbit immediately. The row remains visible as
   **Leaving…** and the conversation remains readable but not writable.
5. Opening an already queued row shows **Try again**, **Cancel queued leave**, and
   **Close**. A queued intent can be cancelled only before signed voluntary-leave work is
   durably claimed. Cancellation deletes only the intent; the role change keeps
   syncing and is never rolled back, discarded, age-capped, or attempt-capped.
6. After signed leave work starts, cancellation truthfully reports “too late” and
   refreshes current state. There is no force-local or divergence action.
7. **Dissolve for everyone** remains a separate, explicitly confirmed sole-admin
   operation. It is not shown in the pending/queued stage and is not the terminal
   escape for this bug.

This is the fastest safe interaction: one automatic recovery attempt, one explicit
durable choice only when needed, immediate navigation freedom after persistence,
and no spinner that asks the user to keep a screen open.

## Planning Progress

| Time | Role | Files inspected | Decision / finding | Next |
|---|---|---|---|---|
| 2026-07-20 | Initial planner | leave guard/policy, Orbit recovery, pending sink | Drafted retry/discard hypotheses before reading the complete queue. | Re-ground. |
| 2026-07-20 | Evidence collector / requested `$tdd-plan` | runner, repush, v086 storage, role writer, leave actions, Group Info/List/Orbit, gates | Empty-recipient retention and “Retry is missing” were refuted; unlocked drains, indefinite retention, generic Group Info failure, and two raw stuck-row bypasses were confirmed. | Build one evidence-backed contract. |
| 2026-07-20 | Independent requested `$tdd-review` | plan plus source counterexamples | Found vacuous fixtures, keyed-tail cleanup/error gaps, optional-sink fail-open, post-snapshot role races, Dissolve bypass/cleanup issues, and incomplete preflight. Verdict was not ready while terminal policy remained open. | Select terminal behavior and triage findings. |
| 2026-07-20 | Product/UX decision | recovery sheet and durable status surfaces | Selected immediate Retry → **Leave when sync completes**; keep Dissolve separate; never offer force-local divergence. | Replan as post-v102 durable work. |
| 2026-07-20 | State/restart grounding | v102 registry, Plan-263 authority, voluntary-leave prework, pending outbox, native `LeaveGroupTopic`, startup/resume/rejoin | A process-memory leave marker is insufficient. Native leave is idempotent, but signed notice, rotation, cleanup, membership generation, and rejoin ordering need durable phases. | Execute only after immutable Plan 263 handoff. |

## Confirmed Problem And Source Evidence

- A valid `member_role_updated` or `member_role_updated_prepared` row blocks active
  leave before signed prework and is checked again at the native boundary in
  `leave_group_and_delete_local_history_use_case.dart`. That lower guard is correct:
  a drain count, timeout, missing parent, or UI snapshot cannot prove convergence.
- `GroupPendingBroadcastRunner.drainForGroup` and `drainAll` currently enter the
  same unlocked drain body. Manual Retry, per-group rejoin, and resume `drainAll`
  can process one row concurrently.
- Failed and throwing re-pushes deliberately retain rows. v086 has no attempt cap
  or delivery phase; deleting an uncertain role row could contradict native config,
  the monotonic membership watermark, and peers that already received it.
- Orbit's normal exit already has Retry followed by a fresh role-row load. Group
  Info falls through to generic leave failure, while Group List and Orbit stuck
  rejoin handlers can fall through to raw `leaveGroup` on pending state, null
  identity, or classification failure. Raw leave has no pending-role predicate.
- The current signed leave remembers native commit only in the in-memory
  `_nativeLeaveCommittedGroups` map. A restart after native success can remint
  `member_removed`, rotate again, or lose cleanup authority.
- Voluntary-leave prework currently mints `leftAt`/`sourceEventId` in memory,
  publishes before any durable retry row, and may rotate a new epoch on each rerun.
  Therefore “persist only the user choice, then rerun the old use case” is not a
  restart-safe implementation.
- Go `Node.LeaveGroupTopic` returns success when the topic is already absent and
  removes its topic/config/key state when present. Reissuing only native leave is
  safe for the same exact membership instance if queued-exit rejoin is excluded at
  the correct phase; this contract gets an explicit Go sentinel.
- Plan 263 currently establishes DB v102 `groups.self_removed_at`, exact
  `selfPeerId + joinedAt` membership-instance authority, membership serialization,
  and terminal work manifests. Its in-flight workspace is user-owned and must not
  be edited by Plan 264.
- Current DB version on the planning workspace is 102. Version 103 is the expected
  reservation, but execution must recheck the next free version after Plan 263's
  immutable handoff.

Planning baseline: committed `HEAD 19dc1ca3a79277baa7079772352d77190d7c870b` plus
the user's uncommitted Plan 263 implementation as prerequisite evidence only.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `6e239a985c1da4d8`;
  `confidence=anchored`, `freshness=stale:lib/main.dart`.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "Plan 264 durable queued group leave after pending member_role_updated: LeaveGroupAndDeleteLocalHistoryUseCase nativeLeaveUncertain leftCleanupIncomplete GroupPendingBroadcastRunner retryPendingGroupRoleTransition GroupExitRecoverySheet GroupExitPolicy group_info_wired group_list_wired orbit_wired database migrations currentIdentityDatabaseVersion GROUP_TESTS core-host-all real SQLCipher; find storage authority, restart lifecycle, cancellation race, tests, gates, and Plan 263 overlap" --profile tdd --budget 700`.
- Anchors: `retryPendingGroupRoleTransition`, `GroupPendingBroadcastRunner`, and
  `GroupExitRecoverySheet`. Targeted source verification added v102 migration and
  helpers, voluntary-leave/key-rotation phases, Go native leave, rejoin/resume,
  all wired surfaces, l10n, and gates.
- Reuse rule: re-run the compact query and re-anchor every line/name against the
  immutable post-263 base. No graph refresh is performed for this plan-only edit.

## Durable Authority And State Machine

### DB v103 `group_exit_intents`

Create a standalone table with no foreign key or cascade so confirmed native-leave
and cleanup authority is not destroyed when the `groups` parent is deleted:

| Column | Contract |
|---|---|
| `group_id TEXT PRIMARY KEY` | At most one current exit intent per group id. |
| `intent_id TEXT NOT NULL UNIQUE` | Random immutable operation identity; never derived from display data. |
| `self_peer_id TEXT NOT NULL` | Identity that requested this exit. |
| `self_joined_at TEXT NOT NULL` | Exact UTC membership generation; same-id re-entry must differ. |
| `state TEXT NOT NULL` | CHECK-constrained state listed below. |
| `pending_broadcast_id TEXT NOT NULL UNIQUE` | Stable id for this intent's leave-notice outbox row. |
| `source_event_id TEXT UNIQUE` | Null while queued; minted once after role convergence, then reused as the signed `member_removed` wire/dedup id. |
| `event_at TEXT` | Null while queued; minted strictly after the fresh membership watermark, then reused by signature, timeline, and retries. |
| `revision INTEGER NOT NULL DEFAULT 0` | Monotonic CAS token; every mutation increments it. |
| `last_error_code TEXT` | Bounded non-sensitive diagnostic code, never raw payload/error text. |
| `created_at`, `updated_at TEXT NOT NULL` | UTC lifecycle timestamps. |

Add a state/updated index and a state-shape CHECK: `queued` has null source/time,
whereas every later state has both. Legacy v102 → v103 backfill is deliberately
empty: no existing role row can prove the user previously chose automatic leave.
Migration, onCreate/onUpgrade registry, full-chain, idempotent rerun, reopen,
wrong-key, and downgrade behavior are causal closure requirements.

Every write is compare-and-set by `group_id + intent_id + expected state + revision`.
Creation and execution also verify an active, non-dissolved, non-self-removed group
and the exact current `self_peer_id + joined_at` row. Missing self while a group is
present is ambiguous and pauses; a different `joinedAt` retires only the stale intent
and preserves the newer membership.

### States

```text
queued (cancelable)
  -> leave_notice_pending
  -> leave_notice_attempted
  -> rotation_claimed
  -> native_leave_pending
  -> cleanup_pending
  -> intent deleted last
```

- `queued`: the user choice is durable. The runner may drain role rows outside the
  membership lock, then reacquires authority and requires every fresh role-kind row
  to be absent. Last-admin state pauses here with a typed error; no notice is minted,
  and the user must safely cancel the intent before using the separate choose-admin
  recovery flow.
- `leave_notice_pending`: under the membership phase, one stable signed
  `member_removed` event is minted strictly after the freshly converged membership
  watermark. Its source/time, signed payload, deterministic timeline row, exact
  pending broadcast row, and intent transition are persisted atomically before
  network work. New role preparation is refused while an intent exists; activation
  of the already-existing exact prepared row is still allowed only while `queued`.
- `leave_notice_attempted`: one exact transaction completes the leave-notice row
  and advances the intent. Signed payload/timeline creation is mandatory. The folded
  Plan-265 policy preserves live publish as best-effort and makes per-recipient
  offline notice explicitly best-effort: a typed delivered or explicitly classified
  degraded attempt may advance, while storage/identity/state ambiguity may not.
  Generic and role pending rows remain success-only and are never retired by this
  policy.
- `rotation_claimed`: CAS before the existing best-effort rotation. Only the winner
  attempts rotation. A restart in this state does not rotate another epoch; it
  records rotation deferred and proceeds, relying on the remaining-admin rekey path
  already used by voluntary leave. This is an intentional at-most-once degradation.
- `native_leave_pending`: persisted before `group:leave`. Timeout, arbitrary bridge
  failure, or crash stays here and retries only idempotent native leave for the exact
  membership. Signed notice and rotation never rerun. Rejoin is disabled from this
  phase onward.
- `cleanup_pending`: native success is durable. Retry performs cleanup only and can
  never publish, rotate, or native-leave again. Exact local SQL cleanup is one
  membership-CAS transaction; the intent is deleted last. Group absence means an
  already-completed cleanup; current self absence pauses; later membership preserves
  all current data and retires only the stale intent.

`group_exit_intents` is added to Plan 263's membership-instance terminalization
manifest. Authenticated self-removal/self-ban, B3, absence, and accepted same-id
re-entry must retire the old intent and exact leave-notice row atomically or cause
the worker to refuse without network work. A freshly dissolved group likewise
terminalizes the intent and makes a previously loaded re-push perform zero network.

## Lifecycle And Lock Ordering

1. `GroupPendingBroadcastRunner` gets one identity-safe keyed tail per group.
   `drainAll` discovers group ids and routes each through the same per-group entry.
   It reloads inside every turn, releases after repository load/removal errors, and
   never blocks unrelated groups.
2. The exit worker first awaits the coordinated role drain **without** holding Plan
   263's membership lock. It then acquires that lock for the fresh authority read and
   one bounded state transition. The pending re-push chain remains
   `runSelfRemovedGroupLifecycleLeaf -> runGroupMembershipMutationLocked`; no nested
   membership lock or batch-spanning lock is allowed.
3. Enqueue and manual **Try again** trigger the exact group worker immediately.
4. Rejoin completes the exact group's pending-broadcast drain, then triggers its exit
   worker. `queued`, `leave_notice_pending`, and `leave_notice_attempted` may still
   need the topic. A restarted `rotation_claimed` operation deliberately skips a
   second rotation, so `rotation_claimed` and every later phase are excluded from
   rejoin.
5. Cold start runs process-all after startup rejoin/drain; a fresh launch cannot rely
   on receiving an initial `resumed` callback.
6. Resume uses one error-isolated unawaited wrapper that awaits drain-all and then
   process-all in that order. Exit work is event-driven; no tight retry loop, silent
   attempt cap, or new OS background-service claim is introduced.

## Scope Contract

In scope:

- DB v103 migration, helpers, typed model/repository, exact CAS operations, real
  SQLite and real SQLCipher proof.
- Keyed pending-broadcast drain coordination, with non-vacuous preservation fixtures.
- A required-dependency exit request/coordinator and durable phase runner. Exit
  authority may not use optional global sinks that fabricate `0`, `[]`, or success
  when unwired.
- Refactor active voluntary leave into durable prepare/notice/rotation/native/cleanup
  phases while preserving signed payload and receiver dedup contracts.
- Exact membership-generation cleanup and Plan-263 terminalization integration.
- One immediate Retry, durable queue/cancel/try-again actions, `Leaving…` projections,
  read-only conversation state, startup/resume/rejoin continuation, and en/de/ar copy.
- Route Orbit primary, Group Info, Group List stuck, and Orbit stuck exits through
  one typed coordinator. Null identity, classification/storage failure, and a role
  row inserted after the UI snapshot all fail closed with zero raw/native leave.
- Narrow Dissolve interaction only: local Dissolve fails closed while any exit intent
  or role-kind row exists; it never silently cancels the user's queued choice. The
  user may explicitly cancel a still-`queued` intent, but the role row must still
  converge before the separate Dissolve preflight can pass. Fresh authoritative
  dissolved state (for example an accepted remote dissolve) terminalizes stale
  intent/notice work without voluntary leave.

Localization keys are explicit rather than inferred during execution. Add them to
en/de/ar and generated APIs, with these exact English contracts:

- `group_exit_sync_finishing_title`: `Finishing a role change`
- `group_exit_sync_finishing_body`: `You can leave this screen. We’ll leave the group as soon as the role update is safely delivered.`
- `group_exit_leave_when_sync_completes`: `Leave when sync completes`
- `group_exit_try_again`: `Try again`
- `group_exit_cancel_queued_leave`: `Cancel queued leave`
- `group_exit_cancel_queued_leave_body`: `This cancels automatic leave. The role change will keep syncing.`
- `group_exit_leaving_status`: `Leaving…`
- `group_exit_leaving_read_only`: `This group is read-only while we finish leaving.`
- `group_exit_cancel_too_late`: `Leaving has already started and can’t be cancelled.`

Must preserve:

- A role row clears only after its exact signed distribution succeeds or it is proven
  superseded by existing authority; false/throw/timeout never age it out.
- Prepared role rows require exact commit watermark, active parent, usable identity,
  and correct membership state before publish.
- Dissolved and Plan-263 self-removed authority outrank queued/pending work.
- Existing signed transition/audit, receiver stale/dedup, key-rotation authorization,
  last-admin, and active-leave native-boundary guards.
- Normal no-pending Leave and separately confirmed sole-admin Dissolve remain
  reachable through their authoritative paths.

Hard `Do not`:

- Do not discard, roll back, force-complete, attempt-cap, or age-cap an uncertain
  role broadcast. Do not infer readiness from drain count or optional-sink defaults.
- Do not expose Dissolve, Continue, Discard role change, or Force leave in the
  pending/queued stage.
- Do not cancel after `leave_notice_pending`; a peer may already have observed the
  signed departure.
- Do not issue native leave or cleanup for an absent/ambiguous/different membership.
- Do not hold the membership lock across a group drain, drain-all sweep, or nested
  re-push.
- Do not change wire payloads, relay schema, crypto, native handlers, or add a
  cross-device claim under this plan.
- Do not edit Plan 263's active workspace or execute Plan 265 concurrently. Plan 264's
  durable notice phases subsume Plan 265's non-durable voluntary-prework outline;
  Plan 265 must be folded/resequenced and re-reviewed before either implementation.

Explicitly deferred:

- The review correctly found general Dissolve `commitUnknown` reporting and
  read-then-unconditional same-id cleanup races. Because Dissolve is no longer this
  plan's terminal behavior, a separate Dissolve-hardening owner must add typed
  commit-unknown and generation-CAS cleanup. Plan 264 does not claim to solve it.
- Per-row diagnostics/backoff beyond the bounded intent error code remains Plan 266.
- Optional real-relay two-peer confidence is not closure: this plan changes local
  persistence/orchestration and reuses existing signed/wire behavior.

## Dependencies And Execution Preconditions

- Plan 263 is a hard prerequisite. Its owner must hand off an immutable accepted SHA
  or patch; shared DB/helpers/lifecycle/policy/UI/tests must no longer be edited in
  parallel. Re-run all grounding on that base.
- Confirm DB remains v102 and v103 is free; otherwise reserve the actual next version
  and update every filename/test/command before RED.
- Confirm accepted re-entry changes exact self `joined_at`, the pending re-push owns
  one bounded membership leaf, and Plan 263's terminalizer can atomically include the
  new intent table.
- The current in-flight self-ban branch still raw-leaves. Require Plan 263's handoff
  to provide a named authenticated self-ban terminalization sentinel, or land a
  separately reviewed prerequisite. Plan 264 must not build a competing ban engine.
- Confirm the post-263 lock hierarchy permits cleanup-only execution without nesting.
- Full `host-all` belongs to the Plans 263-267 wave and release closure, not this plan.

## Test Contract

| Case | Behavior and named proof | Fixture / discriminator | RED -> GREEN and mutation | Gate / registration |
|---|---|---|---|---|
| TC-264-01 | `group_pending_broadcast_runner_test.dart::PB264-01 same-group group/all drains serialize, reload, and protect the current tail from a late fourth caller` | Four controlled callers; second remains active when first completes; row enqueued between turns; max-active counter | Current unlocked runner overlaps. GREEN requires one exact push, reload inside each turn, and identity-safe tail removal. Remove `identical` cleanup or reuse an old load -> red. | Focused file; add once to `GROUP_TESTS`. |
| TC-264-02 | `::PB264-02 repository failure releases the keyed turn while another group progresses` | `repository.forGroup` and runner-owned remove rejection, not `rePush` throw (which is swallowed); unrelated-group barrier | Current code has no keyed turn. GREEN releases same-group successor and never creates a global lock. Globalize/leak tail -> red. | Same focused file/registration. |
| TC-264-03 | `::PB264-03 empty-recipient and prepared-row sentinels reach their claimed branches`; `group_exit_actions_test.dart::PB264-03 self-only role transition rejects empty recipients` | Active parent, self row, usable identity/key; generic empty row publishes once/inbox zero/removes exact row; prepared fixture has exact parent/identity/key/watermark; literal self-only role fixture | Existing claims can pass vacuously through absent-parent/null-identity. GREEN proves the leaf is reached. Remove recipient rejection or watermark guard -> named red. | Focused runner/actions; both once in `GROUP_TESTS`. |
| TC-264-04 | `103_group_exit_intents_test.dart::PB264-04 v103 schema, empty backfill, constraints, registry, and rerun are exact`; full migration-chain preservation | Real SQLite v102 seed, onCreate/onUpgrade, CHECK/unique/index inspection, run twice, v102 rows byte-equal | Compile/schema RED before v103. Drop a constraint, guess a legacy intent, misorder registry -> red. | Add migration test once to `GROUP_TESTS`; `core-host-all`. |
| TC-264-05 | `group_exit_intents_sqlcipher_proof_test.dart::PB264-05 real SQLCipher v102 to v103 survives reopen and rejects wrong key/downgrade` | Production callbacks on explicit available Android; upgrade + fresh + reopen + rerun + `PRAGMA cipher_version` | Device RED before migration; GREEN proves encrypted production boundary. Remove registry/version or use plaintext DB -> red. | Manual discovery classifier; run on discovered `21071FDF600CSC` while available, otherwise policy `N/A`. |
| TC-264-06 | `group_exit_intents_db_helpers_test.dart::PB264-06 exact membership enqueue and cancel-versus-start CAS have one winner` | Active/absent/dissolved/self-removed/different-joinedAt table; two DB handles/barriers; repeat cancel | GREEN permits cancel only from exact `queued`, increments revision, deletes no role/group/history row, and refuses later phase. Remove revision/state/joinedAt predicate -> red. | Add helper test once; `core-host-all` + groups. |
| TC-264-07 | `::PB264-07 role absence claim is atomic with role prepare/activation` | Misleading drain counts; multiple role rows; metadata control; new role prepare racing claim; activation of pre-existing prepared row | Current read/check can race. GREEN: either role row wins and intent stays queued, or exit claim wins and new prepare is refused; never native leave with a role row. Split transaction or inspect first row/count -> red. | Helper + role action focused files. |
| TC-264-08 | `group_exit_intent_coordinator_test.dart::PB264-08 unavailable storage or queue authority cannot authorize leave` | Required concrete repositories whose load/write throws typed unavailable; optional global sinks deliberately unwired | Current sink APIs fabricate `0`/`[]`. GREEN persists nothing, returns typed failure, and issues zero notice/rotation/native/cleanup. Reintroduce a null/no-op default -> red. | Add coordinator test once to `GROUP_TESTS`; `feature-host-all`. |
| TC-264-09 | `group_exit_intent_runner_test.dart::PB264-09 signed leave notice is watermark-newer, stable, and atomically handed off` | Converged role watermark, fixed clock/id, transaction fault points, restart, delivered and explicitly degraded live/inbox outcomes, generic role-row failure control | GREEN mints once strictly after the role watermark, never remints time/signature, atomically saves source/time + timeline + exact outbox + phase, and atomically completes only that notice. Missing row is not success; role rows retain success-only policy. Mint at queue time, rerun old prework, or delete generic failure -> red. | Add runner test once; groups + `feature-host-all`. |
| TC-264-10 | `::PB264-10 process recreation at every durable phase never repeats an earlier side effect` | Recreate repository/runner after `queued`, notice pending/attempted, rotation claimed, native pending, cleanup pending; call counters | GREEN: stable notice may dedup-retry; rotation is at most once; native-only and cleanup-only phases never publish/sign/rotate. Remove phase persistence -> red. | Same runner file. |
| TC-264-11 | `go-mknoon/node/pubsub_test.go::TestPB264LeaveGroupTopicRepeatedIsIdempotent`; `rejoin_group_topics_use_case_test.dart::PB264-11 rejoin eligibility follows exit phase` | Join then native leave twice; topic/config/key absence; queued/notice/rotation/native phase matrix | Existing Go implementation should be a GREEN contract; new Flutter phase gating starts RED. Rejoin after native-pending or make second native leave fail -> red. | Exact Go test from `go-mknoon/`; focused rejoin; no device pair. |
| TC-264-12 | `group_exit_intent_runner_test.dart::PB264-12 confirmed cleanup is atomic and membership-generation safe` | Cleanup transaction failure/reopen; group absent; group present/self missing; later same-id joinedAt; exact old membership | GREEN leaves no partial SQL state, pauses ambiguity, deletes intent last, and preserves every row of a later membership. Restore sequential read/delete or group-id-only cleanup -> red. | Runner + real SQLite helper; groups/core family. |
| TC-264-13 | `self_removed_group_shell_db_helpers_test.dart::PB264-13 Plan-263 terminalization retires exact exit work`; listener sentinel for authenticated self-ban; dissolved loaded-repush sentinel | B3/self-ban/absent/dissolved/same-id re-entry; already-loaded outbox held behind barrier; network counters | GREEN atomically removes/refuses old intent + leave notice and performs zero later network. Omit table from manifest or check dissolved only before load -> red. | Exact Plan-263 helper/listener/repush files; hard prerequisite sentinel. |
| TC-264-14 | `group_exit_intent_coordinator_test.dart::PB264-14 pending-role Leave retries once before offering or starting durable exit` | Role clears, remains, drain throws, metadata/no-role control, sole admin; exact immediate-drain counter | GREEN pending-role fixtures drain exactly once; clear starts one durable exit; remaining/throw returns queue choice with no intent until primary tap; metadata/no-role starts without a drain; queue persistence precedes sheet dismissal. Trust count, drain an already-ready exit, or retry twice -> red. | Coordinator test once in `GROUP_TESTS`. |
| TC-264-15 | `group_exit_recovery_sheet_test.dart::PB264-15 pending and queued stages use the selected hierarchy without destructive escape` plus l10n parity/integrity | Callback spies/completers; 2x text scale; RTL; pending versus already queued | GREEN exact EN hierarchy/copy, single-flight, queued Try again + Cancel, no Dissolve/Continue/discard/force. Change primary order/copy or expose destructive action -> red. | Existing sheet test once; exact l10n tests. |
| TC-264-16 | Group Info/List/Orbit named `PB264-16 ... routes every active/stuck Leave through the durable coordinator and fails closed` tests | Table: pending snapshot, identity null, classifier/load throw, role row inserted after snapshot, ordinary no-pending control; bridge command log | Current Group Info generic-fails and two stuck paths raw-leave. GREEN opens recovery/queues or fails typed; zero raw/native leave on error/pending; ordinary control still starts signed durable exit. Any fallthrough -> red. | Existing Group Info/List/Orbit files already once in `GROUP_TESTS`. |
| TC-264-17 | `group_conversation_wired_test.dart::PB264-17 queued exit is restart-visible, read-only, and cancel-refreshable`; matching Group List/Orbit row tests; resumed recovery test | Cold open, return from Info, resume, status precedence over rejoin; composer/attachment/record/quote/reaction spies | GREEN row says `Leaving…`; conversation readable with Info reachable but every mutation disabled; cancel restores writes only after fresh absence. Ephemeral widget latch or partial composer gate -> red. | Existing conversation/list/orbit/lifecycle files once; `feature-host-all`. |
| TC-264-18 | `group_exit_intent_runner_test.dart::PB264-18 enqueue, startup, rejoin, resume, and manual retry share one processor`; lifecycle exact test | Process recreation; initial startup without resumed callback; drain-before-process ordering; same/different group barriers | GREEN resumes durable rows across restart, serializes same group, lets other groups progress, and isolates errors. Resume-only wiring or process-before-drain -> red. | Runner + lifecycle/rejoin focused files. |
| TC-264-19 | `group_exit_actions_test.dart::PB264-19 separate Dissolve cannot bypass queued intent or pending role`; existing Plan-261/263 preservation selectors | Queued/noncancelable intent, pending-role-only, ordinary clear control, confirmed direct Group Info dissolve, fresh remote-dissolved state, unrelated rows | GREEN local dissolve refuses while either authority exists and never silently cancels; after explicit safe cancel it still waits for role convergence; ordinary clear control dissolves once; fresh remote-dissolved state terminalizes the stale intent/notice with zero voluntary leave. General commit-unknown remains deferred. Bypass preflight or expose Dissolve in queued sheet -> red. | Actions/Group Info/policy focused files; no new dissolve engine. |

### Test Notes

- TC-264-01's late fourth caller is mandatory. Two callers alone do not catch an old
  turn unconditionally removing the newer keyed tail.
- TC-264-02 injects repository load or runner-owned removal rejection because
  `rePush` exceptions are caught internally and cannot prove tail release.
- TC-264-03 fixtures must contain the active parent, exact self, usable identity,
  and key so Plan 263's parent/identity guards cannot explain the result.
- TC-264-07 and TC-264-12 use real SQLite transactions, not only in-memory repos.
- TC-264-09's degraded completion applies only to this intent's signed voluntary
  leave notice and must be cause-coded. It cannot leak into role/metadata queues.
- TC-264-16 uses `group:leave` command absence plus persisted row/state identity as
  discriminators; widget appearance alone is insufficient.
- Re-anchor all Plan-263 preservation selectors after the immutable handoff. Preserve
  substance if its owner renames a test; do not copy stale selectors blindly.

Manual registration is explicit. Add each new/changed headline file exactly once to
`GROUP_TESTS`:

- `test/features/groups/application/group_pending_broadcast_runner_test.dart`
- `test/core/database/migrations/103_group_exit_intents_test.dart`
- `test/core/database/helpers/group_exit_intents_db_helpers_test.dart`
- `test/features/groups/domain/repositories/group_exit_intent_repository_impl_test.dart`
- `test/features/groups/application/group_exit_intent_coordinator_test.dart`
- `test/features/groups/application/group_exit_intent_runner_test.dart`
- `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`

The recovery/action/Group Info/List/conversation/Orbit files already occur once and
must remain single entries. Add the SQLCipher proof once to the reliability discovery
classifier; the Go test stays an exact direct command.

## Implementation Steps

1. **Prerequisite freeze.** Receive Plan 263's immutable accepted handoff. Verify the
   DB version, exact joinedAt re-entry, membership lock chain, terminal manifest,
   self-ban sentinel, and current test/gate names. Run the compact Graphify query on
   that base. Stop on any material mismatch.
2. **Resolve plan ownership.** Mark Plan 265 folded into/resequenced after this durable
   design; do not edit voluntary-leave files from two sessions. Record v103 (or the
   actual next free version) before adding tests.
3. Add TC-264-01 through TC-264-08 RED tests first. Correct the existing vacuous
   pending-runner fixtures before treating them as preservation evidence.
4. Implement the identity-safe per-group drain tail and route group/all drains through
   it. Preserve Plan 263's one-row membership leaf and success-only generic semantics.
5. Add v103 migration/registry/version, DB helpers, typed model/repository, CAS results,
   full-chain tests, and the Android SQLCipher proof. Empty legacy backfill only.
6. Add the required-dependency exit coordinator. Route all authority decisions through
   concrete repositories; keep optional global sinks only for non-authoritative legacy
   presentation/trigger uses until they can be removed separately.
7. Refactor voluntary leave into durable notice prepare/completion, at-most-once
   rotation claim, idempotent native phase, and exact cleanup phase. Add kind-specific
   typed notice completion without changing role-row retirement.
8. Wire role prepare/activation and exit claim into one SQLite ordering contract. Add
   the new table to Plan 263 terminalization and make dissolved loaded re-pushes skip
   network.
9. Wire enqueue/manual/startup/rejoin/resume triggers in the documented order. Add
   TC-264-09 through TC-264-14 and capture causal RED before UI edits.
10. Add en/de/ar keys and generated localization APIs. Extend the recovery sheet, row
    projections, conversation read-only state, and safe cancellation UI. Preserve
    Info reachability and text-scale/RTL behavior.
11. Route Group Info, Orbit primary/stuck, and Group List stuck through the shared
    coordinator. Add the narrow fail-closed Dissolve interaction guard; do not absorb
    the deferred general Dissolve redesign.
12. Run focused GREEN/mutation re-red, exact Plan-261/263 sentinels, registration and
    discovery checks, groups, justified `core-host-all` and `feature-host-all`, device
    SQLCipher, Go sentinel, analyzer, and diff hygiene. Refresh the architecture graph
    once after the coherent app-owned implementation.

Stop-if conditions:

- Plan 263 remains dirty/in flight, v103 is no longer free, exact joinedAt does not
  change on accepted re-entry, self-ban still bypasses terminalization without an
  owned prerequisite, or the lock hierarchy would nest.
- Signed notice/timeline/outbox cannot be atomically persisted or exact-completed.
- Implementation would reclassify a role-row failure as success, infer readiness from
  count/absence hidden by parent filtering, or delete uncertain role work.
- Cleanup cannot be membership-CAS/transaction safe or requires deleting an ambiguous
  current membership.
- Native leave is no longer idempotent, or a phase would rejoin between native attempts.
- Plan 265 starts independently, or a relay/wire/native-handler change becomes needed.
  Merge/replan/re-review instead of expanding silently.

## Risks And Blind Spots

- **Network can remain unavailable indefinitely.** The durable intent makes this
  visible, retryable, restart-safe, and cancellable while safe; it cannot promise
  delivery without connectivity and never launders that into force-local success.
- **Killed apps do not execute Dart.** The intent survives process death and resumes
  at cold start; this plan promises “leave this screen,” not a new always-on OS job.
- **Key rotation crash window.** `rotation_claimed` favors at-most-once over a second
  epoch. A crash before rotation degrades to the existing remaining-admin rekey path;
  TC-264-10 locks this explicit tradeoff.
- **Head-of-line blocking.** Per-group tails and unrelated-group barriers prevent a
  global lock; repository errors must release identity-safely.
- **Same-id re-entry.** No group-id-only cleanup or outbox publish is permitted; exact
  joinedAt and CAS tests cover old intent, missing self, and new membership.
- **Dissolve interaction.** This plan prevents conflict with its own intent but does
  not fix pre-existing general dissolve commit-unknown/cleanup races; that limitation
  must remain visible in closure notes.
- **Sibling UI drift.** Group Info, Group List, Orbit, conversation, and recovery sheet
  have separate refresh paths; TC-264-15 through TC-264-18 cover each one.

## Gate Cadence

- While Plan 263 is active, perform read-only grounding only. Do not add RED tests or
  touch its shared files.
- Plan closure runs focused causal tests, exact Plan-261/263 preservation sentinels,
  exact l10n/integrity and registration/discovery checks, `groups`, justified
  `core-host-all` for v103/DB helpers, and justified `feature-host-all` for lifecycle
  and wired UI.
- Required real-SQLCipher proof uses the explicitly rediscovered available Android
  target. Current planning discovery found USB Android `21071FDF600CSC` (API 36), plus
  emulators `emulator-5554` and `emulator-5556`. If no Android is available at
  execution, record the device leg `N/A (target unavailable by project policy)`.
- No two-phone, iOS, relay, or unavailable API-band leg is required.
- Full `host-all` runs once after the Plans 263-267 dependency wave and once at final
  rollout/release closure, not per plan.

## Acceptance Gates

Do not execute the RED/GREEN block until Plan 263 has handed off a stable base.

```bash
# Prerequisite and ownership preflight. Record the immutable base and expect no
# concurrent output for every planned shared path.
git rev-parse HEAD
git status --short -- lib/main.dart lib/core/database/app_database_version.dart lib/core/database/production_migration_registry.dart lib/core/database/migrations lib/core/database/helpers lib/features/groups/application lib/features/groups/domain lib/features/groups/presentation lib/features/orbit/presentation lib/l10n test/core/database test/features/groups test/features/orbit test/l10n integration_test scripts/run_test_gates.sh scripts/check_reliability_simulation_discovery.sh
rg -n 'currentIdentityDatabaseVersion = 102' lib/core/database/app_database_version.dart
rg -n 'runSelfRemovedGroupLifecycleLeaf' lib/features/groups/application/group_pending_broadcast_repush.dart
rg -n 'runGroupMembershipMutationLocked' lib/features/groups/application/self_removed_group_lifecycle_guard.dart
rg -n 'member_banned|self.*ban' test/features/groups/application/group_message_listener_test.dart
flutter devices --machine
adb devices

# First causal RED: exact keyed-drain race.
flutter test test/features/groups/application/group_pending_broadcast_runner_test.dart --plain-name 'PB264-01 same-group group/all drains serialize, reload, and protect the current tail from a late fourth caller'

# Storage/CAS RED block, then GREEN after v103 implementation.
flutter test test/core/database/migrations/103_group_exit_intents_test.dart test/core/database/helpers/group_exit_intents_db_helpers_test.dart test/features/groups/domain/repositories/group_exit_intent_repository_impl_test.dart
flutter test test/core/database/integration/full_migration_chain_test.dart

# Application/phase RED then focused GREEN.
flutter test test/features/groups/application/group_pending_broadcast_runner_test.dart test/features/groups/application/group_exit_intent_coordinator_test.dart test/features/groups/application/group_exit_intent_runner_test.dart test/features/groups/application/group_exit_actions_test.dart test/features/groups/application/rejoin_group_topics_use_case_test.dart test/core/lifecycle/handle_app_resumed_group_recovery_test.dart

# Wired UI and localization RED/GREEN.
flutter gen-l10n
flutter test test/features/groups/presentation/widgets/group_exit_recovery_sheet_test.dart test/features/groups/presentation/group_info_wired_test.dart test/features/groups/presentation/group_list_wired_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/orbit/presentation/screens/orbit_wired_test.dart
flutter test test/l10n/orbit_strings_parity_test.dart test/l10n/l10n_integrity_test.dart

# Exact Plan-263 authority preservation, re-anchored after handoff.
flutter test test/features/groups/application/group_exit_policy_test.dart --plain-name 'durably removed shell outranks stale pending-role and removed-admin snapshots'
flutter test test/core/database/helpers/self_removed_group_shell_db_helpers_test.dart
flutter test test/features/groups/application/group_message_listener_test.dart --plain-name 'PB264-13 authenticated self-ban terminalizes queued exit without voluntary leave'

# Native idempotence contract.
go -C go-mknoon test ./node -run '^TestPB264LeaveGroupTopicRepeatedIsIdempotent$' -count=1

# Real encrypted boundary on the explicitly rediscovered target while available.
flutter test -d 21071FDF600CSC integration_test/group_exit_intents_sqlcipher_proof_test.dart
./scripts/check_reliability_simulation_discovery.sh --records-tsv | rg '^group\ttest\tintegration_test/group_exit_intents_sqlcipher_proof_test\.dart\t'

# Registration and affected lanes.
test "$(rg -c 'test/features/groups/application/group_pending_broadcast_runner_test.dart' scripts/run_test_gates.sh)" -eq 1
test "$(rg -c 'test/core/database/migrations/103_group_exit_intents_test.dart' scripts/run_test_gates.sh)" -eq 1
test "$(rg -c 'test/core/database/helpers/group_exit_intents_db_helpers_test.dart' scripts/run_test_gates.sh)" -eq 1
test "$(rg -c 'test/features/groups/domain/repositories/group_exit_intent_repository_impl_test.dart' scripts/run_test_gates.sh)" -eq 1
test "$(rg -c 'test/features/groups/application/group_exit_intent_coordinator_test.dart' scripts/run_test_gates.sh)" -eq 1
test "$(rg -c 'test/features/groups/application/group_exit_intent_runner_test.dart' scripts/run_test_gates.sh)" -eq 1
test "$(rg -c 'test/features/groups/application/rejoin_group_topics_use_case_test.dart' scripts/run_test_gates.sh)" -eq 1
test "$(rg -c 'test/core/lifecycle/handle_app_resumed_group_recovery_test.dart' scripts/run_test_gates.sh)" -eq 1
./scripts/run_test_gates.sh completeness-check
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh core-host-all --batch-flutter --concurrency 4 --reporter failures-only
./scripts/run_host_test_gates.sh feature-host-all --batch-flutter --concurrency 4 --reporter failures-only

# Analysis and scoped hygiene.
flutter analyze --no-pub
git diff --check -- lib/main.dart lib/core/database lib/features/groups lib/features/orbit lib/l10n test/core/database test/features/groups test/features/orbit test/l10n integration_test scripts Test-Flight-Improv/264-pending-role-broadcast-convergence-tdd-plan.md Test-Flight-Improv/00-INDEX.md

# After coherent app-owned implementation only.
./graphify-arch/refresh_arch_graph.sh --incremental
```

Semantic outcomes, not historical totals, are authoritative: every named selector is
discovered once; causal RED fails for the named missing behavior; GREEN and mutation
re-red are recorded; SQLCipher proves the production migration boundary; role rows
never clear on uncertain delivery; no pending/error surface issues raw leave; l10n,
registration, affected lanes, analyzer, and diff hygiene pass. Full `host-all` is not
a per-plan command.

## Done Criteria

- [ ] Plan 263 has an immutable accepted handoff, v103 is execution-time free, its
      terminalization/lock/re-entry contracts are re-verified, and a self-ban sentinel
      exists.
- [ ] Plan 265 is folded/resequenced; no concurrent voluntary-leave implementation is
      active.
- [ ] Every test-contract row has causal RED or an explicitly recorded GREEN sentinel
      plus representative mutation re-red.
- [ ] Same-group drains serialize/reload/release identity-safely; unrelated groups
      progress and non-vacuous queue sentinels pass.
- [ ] The v103 intent survives restart, binds exact membership, and advances only by
      revision/state CAS through notice, rotation, native, and cleanup phases.
- [ ] Cancellation wins only while queued and deletes no role/group/history state.
- [ ] Role absence is atomically rechecked; count, optional sink, classification error,
      and post-snapshot insertion cannot authorize leave.
- [ ] Startup, rejoin, resume, enqueue, and manual retry continue durable work without
      rejoining native/cleanup phases.
- [ ] All exit surfaces use the shared coordinator; queued rows show `Leaving…`, the
      conversation is comprehensively read-only, and refresh/cancel behavior is durable.
- [ ] Pending/queued UI uses the selected hierarchy and exact localized en/de/ar copy;
      no force-local, discard, Continue, or Dissolve escape appears there.
- [ ] Fresh self-removal/self-ban/dissolution/re-entry terminalizes stale intent/outbox
      work with zero network; exact cleanup cannot delete a newer membership.
- [ ] General Dissolve commit-unknown/CAS hardening remains explicitly deferred and is
      not falsely claimed by closure.
- [ ] Focused tests, Plan-261/263 sentinels, SQLCipher, Go contract, registrations,
      groups, justified core/feature host families, l10n, analyzer, and diff hygiene pass.
- [ ] The architecture graph is refreshed once after coherent implementation, and full
      `host-all` remains at wave/release cadence.

## Handoff

- First causal RED:
  `flutter test test/features/groups/application/group_pending_broadcast_runner_test.dart --plain-name 'PB264-01 same-group group/all drains serialize, reload, and protect the current tail from a late fourth caller'`.
- Test Contract: 19 rows spanning keyed drains, v103/SQLCipher, exact CAS, signed
  notice phases, native/rejoin, cleanup/re-entry, Plan-263 terminalization, UX, all
  wired surfaces, lifecycle, and narrow Dissolve interaction.
- New durable authority: `group_exit_intents`, expected DB v103, empty legacy backfill,
  exact `selfPeerId + joinedAt`, no FK/cascade, revisioned state CAS.
- Manual proof: real SQLCipher on an explicitly available Android; exact Go repeated
  native-leave sentinel. No two-peer/relay/iOS leg.
- Gate cadence: focused + sentinels + groups + justified `core-host-all` and
  `feature-host-all`; full `host-all` only at dependency-wave and release closure.
- Confirmed review findings incorporated: keyed tail/error/late-caller race, vacuous
  empty/prepared fixtures, raw stuck-row bypass, optional-sink fail-open, post-snapshot
  role race, self-ban/terminal manifest dependency, l10n/schema/gate preflight.
- Review findings deliberately deferred: general Dissolve commit-unknown and
  same-id cleanup redesign, because Dissolve is no longer this plan's exit terminal.

## Execution Progress

| Time | Phase | Files | Last command/result | Evidence / blocker | Next |
|---|---|---|---|---|---|
| 2026-07-20 | planning complete | plan + index only | read-only Graphify/source/device grounding; no tests run | Plan 263 remains active in another session; Plan 264 production/test edits are blocked. | Receive immutable Plan 263 handoff, re-anchor, then begin TC-264-01 RED. |
