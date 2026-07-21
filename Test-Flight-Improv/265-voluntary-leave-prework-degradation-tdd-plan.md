# 265 - Voluntary-Leave Prework Must Degrade, Not Abort

Status: evidence-gated residual after the accepted Plan 264 implementation
(post-handoff audit 2026-07-21); not stale-already-covered and not implemented
Type: Bug (reliability hardening)
Spec: free-text intent from 2026-07-20 — an unambiguous voluntary leave must not be
vetoed by best-effort live delivery, offline replay, or key rotation
Classification: post-264 residual / re-review required
Closure tier: host (application/fake-bridge decision seam); no new real-crypto,
relay, simulator, device, or migration claim

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-20 | Planner | `broadcast_voluntary_leave_use_case.dart`, `leave_group_and_delete_local_history_use_case.dart`, bridge helpers | Drafted a non-durable per-leg tolerance outline | Re-ground after Plan 264 ownership decision |
| 2026-07-21 | Evidence Collector / Planner | Plan 264; voluntary-leave, replay-envelope, rotation, signed-transition, bridge, Go inbox, current tests, gates | Current aggregate inbox-store failure is causal; per-recipient-key premise is refuted; Plan 264 subsumes the durable leave phases | Resequence 265 after 264; audit this post-handoff contract |
| 2026-07-21 | Reviewer / Planner | Review graph plus state/CAS, bridge recipient, zero-peer publish, gate, and current selector sources | Initial `not-ready` blockers corrected in one structural pass; plan is review-ready only as a prerequisite-gated contract | Await immutable 264 handoff, then choose stale or residual RED branch |
| 2026-07-21 | Post-264 residual audit | accepted Plan 264 runner, broadcast delivery path, bounded error field, PB264 tests | Branch B is required: current per-recipient salvage conflicts with TC-265-09's aggregate-only contract; a later rotation degradation can overwrite notice degradation in the single `last_error_code`, leaving TC-265-11 uncovered; the remaining fault matrix is not yet mapped row by row. | Pause implementation, reconcile TC-265-09/11, map all rows, then select the literal first uncovered causal RED and re-review. |

## Historical Problem And Post-264 Residual Evidence

- Historical pre-264 behavior: a member who made a valid voluntary-leave choice could
  receive `preworkFailed` and never reach native leave when a secondary delivery leg
  threw. The old monolithic `broadcastVoluntaryLeaveAndRotateKey` path awaited offline
  replay without a degradable leg boundary, and its encompassing catch suppressed
  `group:leave`. The then-current `group_exit_actions_test.dart::active exit
  distinguishes prework native and post-commit cleanup failures` sentinel captured
  inbox failure -> `preworkFailed`, zero native leave, retained group, and rolled-back
  timeline.
- Plan 264 replaced that exit path with durable notice, rotation, native, and cleanup
  phases. `prepareVoluntaryLeaveNotice` now owns mandatory signed authority;
  `attemptPreparedVoluntaryLeaveNotice` classifies transport failures only after that
  authority exists; `GroupExitIntentRunner` catches a rotation throw after its durable
  claim and records bounded `rotation_deferred` before advancing to native leave.
- The historical GREEN baseline
  `group_exit_actions_test.dart::active exit completes durable prework before native
  leave and target cleanup` remains a preservation sentinel rather than the current
  orchestration entry point.
- Existing guard behavior: the exact
  `member_removal_integration_test.dart::GM-015 blocked creator leave keeps
  remaining-member sends healthy` selector passed on 2026-07-21, proving the
  last-admin block and subsequent remaining-member sends stay healthy.
- Remaining coverage is not yet mapped row by row. Plan 264 covers mandatory notice
  authority, degraded completion, and at-most-once rotation throws, but Plan 265 still
  must classify the full delivery/preparation fault matrix against those accepted
  seams before choosing a first causal RED.
- Refuted finding: v1 claimed one recipient could fail because that member lacked key
  material. The envelope is encrypted once with the group replay key and signs one
  normalized recipient set at
  `lib/features/groups/application/group_offline_replay_envelope.dart:87-169`; Go runs
  one aggregate logical inbox operation and returns one final aggregate status at
  `go-mknoon/node/group_inbox.go:229-298`, although that operation may try more than one
  relay/recovery path internally. Plan 264's fallback deliberately performs
  per-recipient salvage after an aggregate attempt fails, so the old “cannot identify
  a failed member” statement is no longer a current implementation fact.
- Recipient authority: `callGroupInboxStore` preserves the caller's explicit
  recipient ids only when `preserveRecipientPeerIds: true` at
  `lib/core/bridge/bridge_group_helpers.dart:849-875`; otherwise Go may re-derive the
  joined-group set. The delivered aggregate and per-recipient Plan 264 calls set that
  flag, but the per-recipient salvage shape conflicts with TC-265-09's aggregate-only
  contract and therefore requires reconciliation rather than an implementation claim.
- Confirmed ambiguity boundary: replay-envelope construction resolves the group key,
  identity, and sender binding through repositories before its isolated crypto calls.
  Repository/identity/key ambiguity and a refused/throwing completion CAS are state
  failures, not best-effort transport failures; TC-265-06/07 keep them fail-closed.
- Confirmed no-custody case: live publish may return `ok: true` with `topicPeers: 0`,
  and inbox store exposes only aggregate relay acceptance, not recipient observation.
  TC-265-05 therefore proves local exit policy without asserting delivery or eventual
  convergence.
- Refuted disposition: v1's inline "retry signing once, then fail" is incompatible
  with Plan 264. The primary signed `member_removed` notice is mandatory and durable;
  signing failure must retain retryable intent authority and issue no unsigned
  delivery or native leave.
- Post-handoff disposition: Plan 264 delivered the durable notice/rotation/native/
  cleanup state machine and satisfies several preservation rows, but it does not cover
  this plan completely. Its per-recipient salvage path conflicts with TC-265-09's
  aggregate-only contract, and the single bounded error field can lose notice
  degradation when rotation writes a later code (TC-265-11). The remaining fault
  matrix still requires exact mapping; therefore this plan is a residual, not a
  `stale-already-covered` close.
- Affected files, conditional on that handoff: the post-264 exit runner/delivery seam,
  `test/features/groups/application/voluntary_leave_prework_degradation_test.dart`,
  and `scripts/run_test_gates.sh`. No Plan 264 file may be edited while its session is
  active.

## Graph Grounding Snapshot

- Historical planning fingerprint was `5e1d16f2b028fce7` against pre-264 HEAD
  `19dc1ca3a79277baa7079772352d77190d7c870b`.
- The pre-correction post-264 residual audit used the then-current architecture graph with
  `confidence=anchored`, `freshness=current`, fingerprint `7b7d2c6210119196` and the
  exact anchors `attemptPreparedVoluntaryLeaveNotice`, `lastErrorCode`, and the wired
  `groupExitIntentRunner`.
- Planning query / profile:
  `python3 graphify-arch/tdd_context.py query "Plan 265 voluntary leave prework degradation: broadcastVoluntaryLeaveAndRotateKey signGroupSystemTransitionPayload storeGroupOfflineReplayEnvelope LeaveGroupAndDeleteLocalHistoryResult plus Plan 264 pending-role exit dependency, causal tests and gate registration" --profile tdd --budget 700`.
- Anchors: `signGroupSystemTransitionPayload` ->
  `lib/features/groups/application/signed_group_transition_audit.dart:74`;
  `LeaveGroupAndDeleteLocalHistoryResult` ->
  `lib/features/groups/application/leave_group_and_delete_local_history_use_case.dart:26`;
  `broadcastVoluntaryLeaveAndRotateKey` ->
  `lib/features/groups/application/broadcast_voluntary_leave_use_case.dart:64`.
- Surfaced proof/gate files: `group_exit_actions_test.dart`,
  `member_removal_integration_test.dart`, `scripts/run_test_gates.sh`, and
  `scripts/run_host_test_gates.sh` after targeted verification.
- Graph gaps requiring source search: the compact graph did not surface the causal
  inbox-failure selector, aggregate Go relay semantics, or the in-flight Plan 264
  contract; these were verified directly.
- Reuse rule: any later Plan 265 review must start from the immutable Plan 264 handoff,
  remap the remaining fault matrix, and re-query these post-264 anchors before a RED.

## Scope Contract And Guard

In scope:

- Rebase on the accepted post-264 durable exit runner. Define typed, narrow boundaries
  after exact membership authority and the stable signed `member_removed` notice,
  timeline, outbox identity, and intent phase are durably committed. Only live-publish
  transport/decode, replay `group.encrypt`, the replay envelope's second
  `payload.sign`, aggregate inbox transport, and rotation execution after a durable
  rotation claim may become cause-coded degradations that cannot veto native leave.
- Resolve and pin exact identity, sender binding, membership generation, replay key,
  and state/CAS authority outside those degradable catches. A missing/throwing lookup,
  mismatch, or completion-CAS refusal retains the stable notice and blocks rotation,
  native leave, and cleanup until safely retried.
- Preserve one aggregate offline-replay attempt for the exact normalized recipient set.
  Its signed recipient set/hash, outer explicit recipient ids, and bridge preservation
  flag must agree. Record only bounded leg-level facts that the response can prove;
  reuse Plan 264's `last_error_code`/typed outcome rather than adding a schema column.
- Add only residual causal cases not already proven by Plan 264. Prefer its final
  runner seam; do not add a parallel leave engine or test-only production API.

Must preserve:

- Primary transition signing is mandatory: no unsigned `member_removed` publish,
  inbox envelope, rotation, native leave, or cleanup. Plan 264's stable source/time and
  retry contract remain authoritative -> TC-265-06/07 plus accepted PB264-09/PB264-10
  sentinels.
- Identity, exact membership generation, last-admin, pending-role, self-removed,
  dissolved, durable-persistence, and native commit-unknown guards remain fail-closed
  -> TC-265-06/07/12 and Plan 264's PB264-06/07/12/13/14/19 sentinels.
- Successful delivery ordering, creator rotation, plain-member deferred rotation,
  at-most-once side effects, and exact cleanup remain unchanged -> TC-265-10/12.

Hard `Do not`:

- Do not implement 265 concurrently with Plan 264 or edit its dirty workspace before
  an immutable accepted handoff. Do not treat the current pre-264 RED as execution RED.
- Do not catch pre-checkpoint errors, repository/key/identity ambiguity, or phase/CAS
  failures as degradation. A broad catch around replay-envelope construction is
  forbidden; isolate only the named crypto/transport calls after inputs are pinned.
- Do not retry primary signing inline with a newly minted source/time, publish an
  unsigned transition, repeat rotation after its claim, or repeat native leave after a
  confirmed commit.
- Do not invent per-recipient failure attribution from an aggregate response, equate a
  final aggregate status with one relay attempt, or split the request into per-recipient
  transport calls under this plan.
- Do not change DB schema/version, wire payload, relay, Go/native handlers, crypto,
  dissolve/role-change policy, UI, or cross-device behavior.

Deferred / accepted difference:

- Local exit intentionally wins even when live publish reports `ok: true` with zero
  topic peers and aggregate inbox store fails. After confirmed native leave and exact
  local cleanup, no durable local custodian may remain; remote membership and forward-
  secrecy convergence can therefore remain stale indefinitely. This is an explicit,
  irreversible accepted difference—not an eventual-delivery claim. Any post-leave
  retry/custody remedy requires a separately numbered, reviewed plan after 264/265.
- User-visible diagnostics and persisted release evidence remain Plan 266's ownership;
  Plan 266 must rebase its `EX04 envelope-failed` assumption on this contract.
- Dissolve and role-change tolerance remain intentionally stricter sibling policies.

Dependencies:

- Hard prerequisite: the corrected tip of accepted `refs/plan-handoffs/264`, whose
  retained initial-freeze parent is
  `f0a5d2777dfd104407d239e111a4a0b8d95651ac`, including DB v103, the exit-runner API,
  PB264-09/PB264-10/PB264-12 names, bounded outcome vocabulary, observation seam, and
  gate registration. Exact final tip metadata is recorded in Plan 264's post-commit
  working closure to avoid an immutable-tree self-reference.
- Plan 263 authority/terminalization remains inherited through Plan 264 and is not
  reopened here. Plan 266 consumes bounded outcomes after 265.

## Test Contract

The named PB265 file is created only when the post-264 preflight finds a residual gap.
For each causal row, execution HEAD must fail for the named reason before production
edits. If the equivalent post-264 assertion already passes, map its exact existing test;
if all causal rows are covered, reclassify `stale-already-covered` and do not fabricate
RED, production edits, or mutations.

Outcome names below are semantic requirements, not permission to invent persisted
uppercase strings or a new result field. Before the first RED, the immutable 264 handoff
must replace them with its exact accepted, allowlisted constants and observation seam.
If one bounded `last_error_code` cannot represent delivery plus rotation without raw
text or information loss, stop and re-review the outcome contract rather than silently
overwriting one degradation with the next.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-265-01 | Aggregate inbox non-OK cannot veto an already-durable signed leave | `test/features/groups/application/voluntary_leave_prework_degradation_test.dart::PB265-01 aggregate inbox non-ok advances signed leave with offline degradation` | Host application; accepted runner/repository fakes; command-indexed `FakeBridge` | Historical pre-264 baseline was `preworkFailed` with zero native leave. Residual RED or stale mapping -> GREEN completes the exact notice once, reaches native leave once, and exposes the accepted bounded offline-store degradation without raw text. | Reclassify `BridgeCommandException(group:inboxStore)` as blocking -> PB265-01 red | `flutter test test/features/groups/application/voluntary_leave_prework_degradation_test.dart --plain-name 'PB265-01 aggregate inbox non-ok advances signed leave with offline degradation'`; new file AUTO (`feature-host-all`) and add once to `GROUP_TESTS` if created |
| TC-265-02 | Inbox timeout and arbitrary transport throw have the same narrow post-checkpoint outcome | `test/features/groups/application/voluntary_leave_prework_degradation_test.dart::PB265-02 inbox timeout and throw degrade only after durable notice checkpoint` | Host; timeout/generic-throw table; phase spy | Residual RED if either error escapes or is caught before authority is pinned -> GREEN proves the checkpoint, one aggregate logical bridge command, one native leave, and no raw exception persisted. | Widen the catch or omit generic throw -> PB265-02 red | `flutter test test/features/groups/application/voluntary_leave_prework_degradation_test.dart --plain-name 'PB265-02 inbox timeout and throw degrade only after durable notice checkpoint'`; AUTO + one-time `GROUP_TESTS` registration if created |
| TC-265-03 | Only replay encryption and the second signature are degradable preparation faults | `test/features/groups/application/voluntary_leave_prework_degradation_test.dart::PB265-03 replay encrypt and second-sign faults degrade after state inputs are pinned` | Host; successfully resolved exact key/identity/sender binding; ordered `group.encrypt` and second `payload.sign` faults | Residual RED if either isolated crypto fault traps the intent -> GREEN skips inbox store, preserves the mandatory signed transition identity, records the accepted replay-preparation degradation, and continues once. | Catch the primary sign/key lookup too, or require a replay envelope to advance -> PB265-03 red | `flutter test test/features/groups/application/voluntary_leave_prework_degradation_test.dart --plain-name 'PB265-03 replay encrypt and second-sign faults degrade after state inputs are pinned'`; AUTO + same registration |
| TC-265-04 | Live-publish returned non-OK, timeout/malformed response, and throw stay best-effort and still permit inbox attempt | `test/features/groups/application/voluntary_leave_prework_degradation_test.dart::PB265-04 live publish non-ok and throw stay degraded and still attempt offline replay` | Host; response/throw table and ordered command log | The historical non-OK subcase was GREEN; the post-264 throw matrix still needs exact mapping. Residual RED or mapping -> GREEN attempts inbox replay and records the accepted bounded live-publish degradation for every non-success shape. | Treat returned non-OK as delivered, let throw escape, or return before inbox -> PB265-04 red | `flutter test test/features/groups/application/voluntary_leave_prework_degradation_test.dart --plain-name 'PB265-04 live publish non-ok and throw stay degraded and still attempt offline replay'`; AUTO + same registration |
| TC-265-05 | No delivery custody can be established without vetoing local leave | `test/features/groups/application/voluntary_leave_prework_degradation_test.dart::PB265-05 zero-peer or failed live plus inbox failure leaves once without custody claim` | Host; cases for live non-OK plus inbox non-OK, live `ok` with zero peers plus inbox non-OK, and live throw plus inbox non-OK | Residual RED if all-delivery uncertainty vetoes. GREEN records the accepted combined notice-delivery degradation, claims rotation once, invokes native leave once, and never reports delivered, peer-observed, or eventual convergence. | Add an all-failed veto or equate `ok/topicPeers:0` with peer delivery -> PB265-05 red | `flutter test test/features/groups/application/voluntary_leave_prework_degradation_test.dart --plain-name 'PB265-05 zero-peer or failed live plus inbox failure leaves once without custody claim'`; AUTO + same registration |
| TC-265-06 | Primary sign, exact-authority revalidation, and durable notice persistence remain mandatory | `test/features/groups/application/voluntary_leave_prework_degradation_test.dart::PB265-06 pre-checkpoint failures retain intent and emit zero downstream commands` | Host; first `payload.sign` failure; membership/identity mismatch; notice transaction throw | GREEN sentinel from mandatory signing plus accepted 264 authority -> retains retryable intent, does not advance notice phase, and emits zero publish/inbox/rotation/native/cleanup commands. | Broaden degradation across signing/revalidation/notice commit -> PB265-06 red | `flutter test test/features/groups/application/voluntary_leave_prework_degradation_test.dart --plain-name 'PB265-06 pre-checkpoint failures retain intent and emit zero downstream commands'`; AUTO + same registration; accepted PB264 authority selectors run directly |
| TC-265-07 | Post-checkpoint key/identity/state ambiguity or completion-CAS failure stays blocking | `test/features/groups/application/voluntary_leave_prework_degradation_test.dart::PB265-07 state lookup or completion CAS failure retains the exact notice` | Host; replay-key lookup missing/throw, sender-binding mismatch, completion CAS false/throw, recreated runner | Residual RED if any state fault is laundered into degradation -> GREEN keeps the exact notice pending, performs zero rotation/native/cleanup, and reuses its source/time after restart; a delivery attempt before CAS failure is not reported complete. | Catch repository/CAS failure as transport degradation or mint a new notice -> PB265-07 red | `flutter test test/features/groups/application/voluntary_leave_prework_degradation_test.dart --plain-name 'PB265-07 state lookup or completion CAS failure retains the exact notice'`; AUTO + same registration; PB264-09 runs directly |
| TC-265-08 | Rotation throw after its durable claim is deferred, at-most-once, and cannot veto native leave | `test/features/groups/application/voluntary_leave_prework_degradation_test.dart::PB265-08 rotation throw advances once and restart never rotates again` | Host; repository/bridge throw after `rotation_claimed`; recreated runner | Plan 264 now catches the runner seam and records `rotation_deferred`; map that accepted PB264 proof before deciding whether any residual RED remains. GREEN preserves one claim, reaches native once, and restart repeats no sign/publish/inbox/rotation. | Advance only on non-throw return or clear the durable claim -> PB265-08 red | `flutter test test/features/groups/application/voluntary_leave_prework_degradation_test.dart --plain-name 'PB265-08 rotation throw advances once and restart never rotates again'`; AUTO + same registration; PB264-10 runs directly |
| TC-265-09 | Aggregate recipient semantics preserve the exact signed set without peer blame | `test/features/groups/application/voluntary_leave_prework_degradation_test.dart::PB265-09 aggregate attempt preserves signed recipients and explicit bridge authority` | Host; three-member fixture; inspect signed normalized set/hash and bridge command | Handoff guard -> signed set/hash equals outer explicit ids, `preserveRecipientPeerIds` is true, one aggregate logical operation yields one final status, and no member-specific failure is invented. If the immutable handoff lacks this, stop/replan instead of making a relay claim under 265. | Clear the preservation flag, drift either set, split commands, or blame one member -> PB265-09 red | `flutter test test/features/groups/application/voluntary_leave_prework_degradation_test.dart --plain-name 'PB265-09 aggregate attempt preserves signed recipients and explicit bridge authority'`; AUTO + same registration |
| TC-265-10 | Success, live non-OK, and permission-denied rotation remain non-regressed | `test/features/groups/application/voluntary_leave_prework_degradation_test.dart::PB265-10 successful and expected-degraded legs preserve ordering`; `test/features/groups/application/group_exit_actions_test.dart::active exit completes durable prework before native leave and target cleanup` | Host; current fakes plus accepted runner fixture | GREEN sentinel -> successful ordering stays unchanged; live non-OK is bounded degradation; rotation null/deferred still reaches native once; none reorder native before mandatory notice. | Make expected non-OK/null blocking or reorder native -> PB265-10/current sentinel red | `flutter test test/features/groups/application/voluntary_leave_prework_degradation_test.dart --plain-name 'PB265-10 successful and expected-degraded legs preserve ordering'`; exact current selector; PB265 AUTO/`GROUP_TESTS`, current file already registered |
| TC-265-11 | Delivery plus rotation degradation preserves both dimensions without raw-text overwrite | `test/features/groups/application/voluntary_leave_prework_degradation_test.dart::PB265-11 delivery and rotation faults retain the accepted combined outcome` | Host; inbox failure followed by rotation null and throw; exact accepted outcome constants | Residual RED if rotation overwrites delivery or arbitrary text is accepted -> GREEN exposes the handoff-approved composite or explicit precedence semantics, preserves both required facts through its typed observation seam, and leaves once. | Assign the later rotation code over delivery or persist exception text -> PB265-11 red | `flutter test test/features/groups/application/voluntary_leave_prework_degradation_test.dart --plain-name 'PB265-11 delivery and rotation faults retain the accepted combined outcome'`; AUTO + same registration |
| TC-265-12 | Last-admin/pending/exact-membership guards, restart, native ambiguity, and cleanup remain authoritative | `test/features/groups/application/member_removal_integration_test.dart::GM-015 blocked creator leave keeps remaining-member sends healthy`; `test/features/groups/application/group_exit_intent_runner_test.dart::PB264-09 signed leave notice is watermark-newer, stable, and atomically handed off`; `::PB264-10 process recreation at every durable phase never repeats an earlier side effect`; `::PB264-12 confirmed cleanup is atomic and membership-generation safe` | Host; accepted 264 fixtures plus current last-admin fixture | GREEN sentinels -> guarded exits emit zero leave; sign/publish/inbox/rotation never repeat after durable completion/claim; native may retry only while `native_leave_pending` remains ambiguous and never after `cleanup_pending`; cleanup is exact-membership atomic. | Bypass authority, retry an earlier phase, suppress permitted ambiguous native retry, or clean a rejoin -> named sentinel red | Exact GM-015 and PB264-09/10/12 commands in Acceptance Gates; member-removal runs directly; accepted runner file occurs once in `GROUP_TESTS` |

### Test Notes

- PB265 fixtures must prove the mandatory checkpoint before injecting a degradable
  failure: exact intent id/revision and stable signed source/time are persisted, and
  the command log shows the signed transition exists. A test that merely returns
  `left` can pass through a skip/not-found branch and is vacuous.
- Command-indexed faults distinguish the first `payload.sign` (mandatory transition)
  from the second sign (best-effort replay envelope). Repository/key/identity/CAS faults
  use separate fakes and may never share the degradable catch.
- PB265-05 locks the chosen no-custody policy using the existing zero-peer publish fake.
  A local `left` result is not proof that any peer observed the notice or rotated key.
- PB265-09 treats the bridge/Go result as aggregate and asserts the explicit-recipient
  preservation flag. Internal relay recovery/retry is not observable as one request.
- PB265-11 must use the immutable handoff's exact allowlisted constants. A test that
  merely accepts any bounded-looking string is insufficient.
- Native leave may retry during `native_leave_pending` commit ambiguity; “no repeat”
  applies to earlier durable phases and to native leave after `cleanup_pending`.
- Accepted PB264 selectors must be re-anchored from the immutable handoff. Renaming is
  allowed only with equivalent causal assertions and literal replacement commands in
  this plan.

## Implementation Steps

1. **Prerequisite handoff.** The accepted Plan 264 implementation establishes DB v103,
   the durable runner, PB264-09/PB264-10/PB264-12, bounded outcome storage, and gate
   registration. Before future Plan 265 execution, freeze/re-verify its scoped ref,
   snapshot `git status --short`, and re-run the compact Graphify query with the exact
   accepted symbols. Stop if ownership becomes shared again or the ref is not stable.
2. **Residual RED preflight.** Branch B is selected but paused for contract
   reconciliation. Map every TC-265 row to the post-264 source and tests.
   Run direct equivalent selectors, record each mapping, and choose one literal branch:
   (A) every row is causal and green -> change classification to
   `stale-already-covered`, record exact verification, and make no test/production/
   registration change; or (B) record the first uncovered selector in Handoff, create
   only residual tests, and run that selector to causal RED before any production edit.
   Do not default to PB265-01 when another row is the first residual gap.
3. **Validate the handoff boundary.** Prove repository/key/identity/sender-binding and
   completion-CAS failures remain blocking, exact recipients are explicitly preserved,
   and the accepted outcome vocabulary can retain delivery plus rotation. If any check
   fails, stop/replan; do not widen a transport catch or improvise a persisted code.
4. Patch only residual typed branches in the post-264 signed-notice delivery/rotation
   classifier. Isolate the named live/crypto/inbox operations after pinned inputs and
   isolate rotation only after its durable claim. Reuse Plan 264's state machine and
   bounded outcome; introduce no schema, second runner, or per-recipient loop. Stop and
   replan if this requires DB shape, wire/relay/native code, or changed at-most-once
   ordering.
5. Add `voluntary_leave_prework_degradation_test.dart` once to `GROUP_TESTS` only if the
   file is created; AUTO feature-host registration needs no other wiring. Keep all
   upstream registrations single-entry.
6. After one coherent application-code change, run
   `./graphify-arch/refresh_arch_graph.sh --incremental` once. Skip it for a
   `stale-already-covered` close with no app-owned code change.
7. Run focused GREEN, representative mutation re-red for each distinct classifier
   branch, exact PB264/current preservation selectors, groups, and—only when production
   application code changed—`feature-host-all`. Run analyzer and diff hygiene.

Stop-if conditions:

- The accepted Plan 264 ref or PB264-09/PB264-10/PB264-12 evidence is missing, active
  edits resume on the same runner/test/gate lines, or its bounded outcome contract is
  no longer stable.
- The post-264 state machine does not durably separate mandatory preparation from
  best-effort delivery/rotation, so a local catch would permit unsigned or uncommitted
  leave progress.
- The accepted runner does not send matching signed/outer recipients with
  `preserveRecipientPeerIds: true`, or delivery plus rotation cannot be represented
  honestly through its accepted typed observation seam.
- Correctness requires DB v104+, wire/relay/native changes, per-recipient claims, or a
  post-leave custody queue. Those are new plans/review decisions, not silent expansion.

## Risks And Blind Spots

- Catch-all false success -> PB265-03, PB265-06, and PB265-07 place crypto/transport,
  mandatory preparation, and repository/CAS faults on distinct sides of the boundary.
- Wrong event/skip-path pass -> every causal test asserts exact intent/source/revision,
  positive degradation code, negative downstream commands where blocking, and exact
  command counts.
- Double side effects after degradation/restart -> PB265-08 plus accepted PB264-10;
  PB265-12 separately preserves the permitted native retry while commit is ambiguous.
- Aggregate relay response misreported as one peer's failure or one relay request ->
  PB265-09, the explicit-recipient flag assertion, and the hard no-attribution guard.
- Later degradation overwrites an earlier fact -> PB265-11 requires exact accepted
  composite/precedence semantics rather than arbitrary bounded text.
- Production-critical end-to-end transport leg: N/A — 265 changes only the local
  post-checkpoint classification and preserves the existing aggregate call shape; it
  makes no real-delivery claim. Any wire, relay, custody, or recipient-observation
  change triggers a new boundary plan instead of substituting this host proof.
- Lifecycle / derived-state durability -> inherited PB264-10/12/18 plus PB265-07; 265
  changes no lifecycle trigger or persistence shape.
- Sibling-surface consistency -> Plan 264 PB264-16 must prove Group Info/List/Orbit use
  the same coordinator before 265 starts; dissolve and role-change remain out of scope.
- Destructive-action side effects -> PB265-06/07/08 and PB264-12 prove no cleanup before
  native authority and no repeated cleanup across restart.
- Invariant re-verification under new transitions -> exact membership/last-admin/
  pending-role guards are re-run through PB264-06/07/13/14/19, not weakened here.

## Gate Cadence

- Per-plan closure: focused PB265 tests (if residual), exact PB264/current sentinels,
  one `groups` curated gate, and `feature-host-all` only if 265 changes production
  application code. No `core-host-all`: 265 adds no DB/core surface.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the Plans 263-267 group-exit
  reliability dependency wave is complete, and once at final rollout/release closure.
- Shared tests outside feature/core globs: N/A — all planned Dart tests are under
  `test/features/**`; no Go/native test is claimed by 265.

## Acceptance Gates

```bash
# Prerequisite snapshot; record unrelated changes and confirm 264 ownership is closed.
git status --short

# Re-ground against the accepted post-264 symbols before writing tests.
python3 graphify-arch/tdd_context.py query "Plan 265 post-264 GroupExitIntentRunner signed leave notice delivery degradation live publish offline replay rotation exact tests GROUP_TESTS" --profile tdd --budget 700

# Branch B only: after mapping, replace this guarded value and this comment with the
# literal first-uncovered selector from TC-265-01..12; expect non-zero for that reason.
PB265_FIRST_UNCOVERED_SELECTOR='REPLACE_AFTER_IMMUTABLE_264_HANDOFF'
test "$PB265_FIRST_UNCOVERED_SELECTOR" != 'REPLACE_AFTER_IMMUTABLE_264_HANDOFF'
flutter test test/features/groups/application/voluntary_leave_prework_degradation_test.dart --plain-name "$PB265_FIRST_UNCOVERED_SELECTOR"

# Branch B focused GREEN; omit both commands when Branch A stale-closes with no file.
flutter test test/features/groups/application/voluntary_leave_prework_degradation_test.dart

# Current preservation baselines; re-anchor only if 264 replaces them with equivalents.
flutter test test/features/groups/application/group_exit_actions_test.dart --plain-name 'active exit completes durable prework before native leave and target cleanup'
flutter test test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-015 blocked creator leave keeps remaining-member sends healthy'

# Run accepted PB264-09/PB264-10/PB264-12 exact selectors from the immutable handoff.
flutter test test/features/groups/application/group_exit_intent_runner_test.dart --plain-name 'PB264-09 signed leave notice is watermark-newer, stable, and atomically handed off'
flutter test test/features/groups/application/group_exit_intent_runner_test.dart --plain-name 'PB264-10 process recreation at every durable phase never repeats an earlier side effect'
flutter test test/features/groups/application/group_exit_intent_runner_test.dart --plain-name 'PB264-12 confirmed cleanup is atomic and membership-generation safe'

# Branch B registration and affected curated lane; count only the GROUP_TESTS array.
test "$(awk '/^readonly GROUP_TESTS=\(/,/^\)/' scripts/run_test_gates.sh | rg -c '^  "test/features/groups/application/voluntary_leave_prework_degradation_test\.dart"$')" -eq 1
./scripts/run_test_gates.sh groups

# Only after a coherent 265 app-owned code edit; run incremental refresh exactly once.
./graphify-arch/refresh_arch_graph.sh --incremental

# Only when 265 lands a production application edit; expect exit 0 and zero failures.
./scripts/run_host_test_gates.sh feature-host-all --batch-flutter --concurrency 4 --reporter failures-only

# Hygiene; expect no new analyzer issues and no whitespace errors attributable to 265.
flutter analyze
git diff --check
```

For Branch A `stale-already-covered`, remove the unresolved-selector guard from the
handoff, omit the absent PB265 file/registration/Graphify-refresh/feature-family
commands, run every mapped equivalent selector plus `groups`, and record why no causal
RED, production edit, or mutation applies. For Branch B, replace the guard with the
literal selected command only after TC-265-09/11 reconciliation and full residual
mapping have been re-reviewed.

## Execution Interpretation And Done Criteria

- Expected RED: after Plan 264's handoff, the first uncovered PB265 selector—not
  automatically PB265-01—must fail because its exact boundary is missing or
  misclassified. The pre-264 baseline is planning evidence only.
- Green sentinels: successful/non-OK live-publish exit, mandatory signing/authority,
  repository/CAS fail-closed behavior, exact recipient preservation, last-admin/
  pending-role guards, PB264 stable notice/restart/cleanup, and bounded combined outcome.
- Pre-existing dirty tree / known failure: the 2026-07-21 tree contained extensive
  unrelated Plan 263/264 work. Execution must snapshot and attribute it; do not absorb
  those files.
- Environment blocker: none for host closure. Unavailable mobile targets are N/A; no
  simulator/device claim exists.
- Scope drift: any schema, relay/wire/native, per-recipient, UI, or parallel-264 edit
  blocks completion and requires replan/review.

- [ ] The immutable Plan 264 handoff is recorded and every PB264 dependency re-anchored.
- [ ] Every residual behavior has causal RED, GREEN, and representative mutation
      re-red, or all rows have a source-backed `stale-already-covered` disposition.
- [ ] Exact preservation selectors, registration (if any), groups, conditional
      `feature-host-all`, analyzer, and diff hygiene pass with semantic outcomes.
- [ ] No error before durable signed-notice authority is downgraded, and no aggregate
      response is reported as a peer-specific fact.
- [ ] Zero-peer live publish plus failed inbox is reported as no delivery custody; the
      plan makes no eventual-convergence or forward-secrecy claim.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: intentionally unresolved pending reconciliation of
  TC-265-09 and TC-265-11 plus mapping of the remaining fault matrix. Replace the
  guarded selector with the exact first uncovered PB265 row only after re-review;
  PB265-01 is valid only if it is actually first.
- Preservation command:
  `flutter test test/features/groups/application/group_exit_actions_test.dart --plain-name 'active exit completes durable prework before native leave and target cleanup'`;
  re-anchor to its accepted PB264 equivalent if removed.
- Manual registration: add the PB265 file exactly once to `GROUP_TESTS` only when it is
  created; AUTO feature-host glob otherwise applies. No simulator dispatcher entry.
- Migration: none. The accepted Plan 264 DB v103 is an inherited prerequisite and
  must not be changed by 265.
- Boundary closure: host-only decision proof with command-indexed fake bridge; no real
  crypto/relay/device claim and no mobile topology.
- Residual evidence: explicit-recipient behavior is currently per-recipient salvage,
  not the aggregate-only TC-265-09 contract; a later rotation outcome can overwrite
  delivery degradation for TC-265-11; remaining rows and the first causal selector are
  not yet mapped. No PB265 file or registration is authorized before re-review.

## Reviewer Findings

- Initial review date/profile: 2026-07-21, Graphify `review` profile plus targeted
  source and test/gate verification. That historical review correctly treated the
  then-in-flight Plan 264 implementation as transient; the post-264 audit above now
  governs the residual disposition.
- Initial verdict: `not-ready`. Blocking findings were an over-broad offline-preparation
  catch that could launder key/identity/CAS ambiguity, and an unsupported implication
  that failed delivery would retain eventual custody.
- Required tightenings applied: typed crypto/transport-only boundaries; a distinct
  post-checkpoint state/CAS sentinel; explicit `preserveRecipientPeerIds` handoff guard;
  zero-peer plus inbox-failure no-custody policy; returned-non-OK live coverage; exact
  delivery-plus-rotation outcome semantics; residual-first RED branching; permitted
  native retry wording; PB264-12/GM-015 preservation; array-bounded gate registration;
  conditional incremental Graphify refresh.
- Post-264 verdict: Branch B residual, paused before implementation. Reconcile
  TC-265-09/11, map every remaining row, select the first literal causal RED, and
  re-review before editing production or creating/registering a PB265 test file.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-21 | post-264 residual audit | plan only | Refreshed Graphify review query plus accepted PB264 selectors/source inspected; no PB265 command, test file, registration, or production edit run | TC-265-09 aggregate-only semantics conflict with current per-recipient salvage; TC-265-11 combined degradation can be overwritten; remaining rows unmapped | Branch B selected but blocked on contract reconciliation and re-review | Reconcile 09/11, map all rows, then choose the first causal RED |
