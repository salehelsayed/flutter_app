# 265 - Voluntary-Leave Prework Must Degrade, Not Abort

Status: evidence-gated (v2 planned 2026-07-21; blocked on Plan 264's immutable
accepted handoff; not executable concurrently)
Type: Bug (reliability hardening)
Spec: free-text intent from 2026-07-20 — an unambiguous voluntary leave must not be
vetoed by best-effort live delivery, offline replay, or key rotation
Classification: prerequisite-blocked
Closure tier: host (application/fake-bridge decision seam); no new real-crypto,
relay, simulator, device, or migration claim

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-20 | Planner | `broadcast_voluntary_leave_use_case.dart`, `leave_group_and_delete_local_history_use_case.dart`, bridge helpers | Drafted a non-durable per-leg tolerance outline | Re-ground after Plan 264 ownership decision |
| 2026-07-21 | Evidence Collector / Planner | Plan 264; voluntary-leave, replay-envelope, rotation, signed-transition, bridge, Go inbox, current tests, gates | Current aggregate inbox-store failure is causal; per-recipient-key premise is refuted; Plan 264 subsumes the durable leave phases | Resequence 265 after 264; audit this post-handoff contract |

## Problem And Evidence

- Behavior to improve: a member who has made a valid, authorized voluntary-leave
  choice can currently receive `preworkFailed` and never reach native leave because a
  secondary delivery leg throws.
- Impact: a relay/bridge outage can trap the user in a group even when the signed
  departure can be prepared and the native leave itself is available.
- Confirmed current root cause: `broadcastVoluntaryLeaveAndRotateKey` awaits
  `storeGroupOfflineReplayEnvelope` without a leg boundary at
  `lib/features/groups/application/broadcast_voluntary_leave_use_case.dart:164-192`;
  `callGroupInboxStore` throws on a non-OK response or timeout at
  `lib/core/bridge/bridge_group_helpers.dart:849-912`; the encompassing catch converts
  any such error to `preworkFailed` and suppresses `group:leave` at
  `lib/features/groups/application/leave_group_and_delete_local_history_use_case.dart:174-270`.
- Confirmed current RED behavior: on 2026-07-21,
  `group_exit_actions_test.dart::active exit distinguishes prework native and
  post-commit cleanup failures` passed while asserting inbox failure ->
  `preworkFailed`, zero `group:leave`, retained group, and rolled-back timeline.
- Existing GREEN behavior: the focused
  `group_exit_actions_test.dart::active exit completes durable prework before native
  leave and target cleanup` baseline passed on 2026-07-21 for both publish success and
  `group:publish` non-OK; the latter already records the non-OK map and continues.
- Additional throw surface: rotation returns `notRotated` for many expected failures,
  but repository calls such as `getGroup`, `getMember`, and `getMembers` remain outside
  local catches in `rotateAndDistributeGroupKey` at
  `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart:199-296`.
  The current caller has no rotation-leg catch. Treat the post-264 behavior as
  unresolved until TC-265-07 faults the final runner seam.
- Missing coverage: no current test proves that offline replay response failures,
  offline-envelope preparation failures, arbitrary publish throws, both delivery legs
  failing together, or a rotation throw cannot veto an already-durable signed leave.
- Refuted finding: v1 claimed one recipient could fail because that member lacked key
  material. The envelope is encrypted once with the group replay key and signs one
  normalized recipient set at
  `lib/features/groups/application/group_offline_replay_envelope.dart:87-169`; Go sends
  one aggregate relay request and receives one aggregate status at
  `go-mknoon/node/group_inbox.go:229-298`. Current code cannot identify a failed member.
- Refuted disposition: v1's inline "retry signing once, then fail" is incompatible
  with Plan 264. The primary signed `member_removed` notice is mandatory and durable;
  signing failure must retain retryable intent authority and issue no unsigned
  delivery or native leave.
- Unresolved finding: Plan 264 is being implemented in another session and explicitly
  owns the durable notice/rotation/native/cleanup state machine. Its accepted handoff
  may already satisfy some or all rows below. Execution must map equivalent proof first
  and close 265 as `stale-already-covered` if every row is directly causal.
- Affected files, conditional on that handoff: the post-264 exit runner/delivery seam,
  `test/features/groups/application/voluntary_leave_prework_degradation_test.dart`,
  and `scripts/run_test_gates.sh`. No Plan 264 file may be edited while its session is
  active.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `5e1d16f2b028fce7`; `current` when queried against
  repository HEAD `19dc1ca3a79277baa7079772352d77190d7c870b` (the wider worktree was dirty,
  while the cited current voluntary-leave sources/tests were not listed as modified).
- Query / profile:
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
- Reuse rule: review/execution may reuse these anchors, but must re-query and verify
  current source after Plan 264's immutable handoff.

## Scope Contract And Guard

In scope:

- Rebase on the accepted post-264 durable exit runner. Define one testable boundary:
  after exact membership authority and the stable signed `member_removed` notice,
  timeline, outbox identity, and intent phase are durably committed, failures inside
  live publish, offline replay preparation/store, or key rotation are cause-coded
  degradations and cannot veto progress toward native leave.
- Preserve one aggregate offline-replay attempt for the exact normalized recipient set.
  Record only bounded leg-level facts that the response can prove; reuse Plan 264's
  `last_error_code`/typed outcome rather than adding a schema column.
- Add only residual causal cases not already proven by Plan 264. Prefer its final
  runner seam; do not add a parallel leave engine or test-only production API.

Must preserve:

- Primary transition signing is mandatory: no unsigned `member_removed` publish,
  inbox envelope, rotation, native leave, or cleanup. Plan 264's stable source/time and
  retry contract remain authoritative -> TC-265-06 plus the accepted PB264-09/PB264-10
  sentinels.
- Identity, exact membership generation, last-admin, pending-role, self-removed,
  dissolved, durable-persistence, and native commit-unknown guards remain fail-closed
  -> TC-265-06/10 and Plan 264's PB264-06/07/12/13/14/19 sentinels.
- Successful delivery ordering, creator rotation, plain-member deferred rotation,
  at-most-once side effects, and exact cleanup remain unchanged -> TC-265-09/10.

Hard `Do not`:

- Do not implement 265 concurrently with Plan 264 or edit its dirty workspace before
  an immutable accepted handoff. Do not treat the current pre-264 RED as execution RED.
- Do not catch errors before the durable signed-notice checkpoint as degradation.
- Do not retry primary signing inline with a newly minted source/time, publish an
  unsigned transition, repeat rotation after its claim, or repeat native leave after a
  confirmed commit.
- Do not invent per-recipient failure attribution from an aggregate response or split
  the request into per-recipient transport calls under this plan.
- Do not change DB schema/version, wire payload, relay, Go/native handlers, crypto,
  dissolve/role-change policy, UI, or cross-device behavior.

Deferred / accepted difference:

- When both delivery legs fail, remaining peers may observe the departure only through
  later convergence. This plan guarantees local exit progress and honest bounded
  degradation, not eventual remote observation. A post-leave retry design requires a
  separately reviewed durable-custody contract; it must not be smuggled into Plan 264.
- User-visible diagnostics and persisted release evidence remain Plan 266's ownership;
  Plan 266 must rebase its `EX04 envelope-failed` assumption on this contract.
- Dissolve and role-change tolerance remain intentionally stricter sibling policies.

Dependencies:

- Hard prerequisite: Plan 264's immutable accepted implementation/proof handoff,
  including its final DB version, exit-runner API, PB264-09/PB264-10 names, gate
  registration, and no active edits to the same voluntary-leave seams.
- Plan 263 authority/terminalization remains inherited through Plan 264 and is not
  reopened here. Plan 266 consumes bounded outcomes after 265.

## Test Contract

The named PB265 file is created only when the post-264 preflight finds a residual gap.
For each causal row, execution HEAD must fail for the named reason before production
edits. If the equivalent post-264 assertion already passes, map its exact existing test;
if all causal rows are covered, reclassify `stale-already-covered` and do not fabricate
RED, production edits, or mutations.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-265-01 | Aggregate offline store non-OK cannot veto a durable signed leave | `test/features/groups/application/voluntary_leave_prework_degradation_test.dart::PB265-01 aggregate inbox non-ok advances signed leave with offline degradation` | Host application; post-264 runner/repository fakes; command-indexed `FakeBridge` | Current pre-264 baseline is `preworkFailed`/zero native leave. On execution HEAD, require causal RED or stale mapping -> GREEN advances the exact intent once, reaches native leave once, and exposes bounded `OFFLINE_REPLAY_DEGRADED` without raw error text. | Reclassify `BridgeCommandException(group:inboxStore)` as blocking -> PB265-01 red | `flutter test test/features/groups/application/voluntary_leave_prework_degradation_test.dart --plain-name 'PB265-01 aggregate inbox non-ok advances signed leave with offline degradation'`; new file AUTO (`feature-host-all`) and add once to `GROUP_TESTS` if created |
| TC-265-02 | Timeout and arbitrary throw at offline store have the same leg-local outcome | `test/features/groups/application/voluntary_leave_prework_degradation_test.dart::PB265-02 inbox timeout and throw degrade only after durable notice checkpoint` | Host; table of timeout/generic throw; repository phase spy | Execution HEAD must RED if either error escapes or is swallowed before the checkpoint -> GREEN proves checkpoint present, exact recipient attempt made, one native leave, and no raw exception persisted. | Move catch outside the checkpoint or omit generic throw -> PB265-02 red | `flutter test test/features/groups/application/voluntary_leave_prework_degradation_test.dart --plain-name 'PB265-02 inbox timeout and throw degrade only after durable notice checkpoint'`; AUTO (`feature-host-all`) + add file once to `GROUP_TESTS` if created |
| TC-265-03 | Offline-envelope encrypt/sign preparation is also best-effort after the primary signed notice is durable | `test/features/groups/application/voluntary_leave_prework_degradation_test.dart::PB265-03 replay envelope encrypt and second-sign failures degrade without unsigned transition` | Host; ordered bridge responses distinguish primary transition sign from replay-envelope `group.encrypt`/second `payload.sign` | Execution HEAD RED if replay preparation traps the intent -> GREEN records `OFFLINE_REPLAY_PREP_DEGRADED`, skips inbox store, preserves the already-signed transition identity, and continues once. | Catch the primary sign too, or require a built envelope to advance -> PB265-03 red | `flutter test test/features/groups/application/voluntary_leave_prework_degradation_test.dart --plain-name 'PB265-03 replay envelope encrypt and second-sign failures degrade without unsigned transition'`; AUTO + same one-time `GROUP_TESTS` registration |
| TC-265-04 | A malformed/throwing live-publish transport is best-effort and does not suppress the offline attempt | `test/features/groups/application/voluntary_leave_prework_degradation_test.dart::PB265-04 live publish throw still attempts offline replay and advances` | Host; command-specific throw/malformed response fake and ordered log | Current source lets arbitrary bridge/decode errors escape. Execution HEAD must causal-RED or stale-map -> GREEN attempts offline replay and records `LIVE_PUBLISH_DEGRADED`. | Remove the live-leg catch or return before inbox attempt -> PB265-04 red | `flutter test test/features/groups/application/voluntary_leave_prework_degradation_test.dart --plain-name 'PB265-04 live publish throw still attempts offline replay and advances'`; AUTO + same one-time `GROUP_TESTS` registration |
| TC-265-05 | Both delivery legs may fail without falsifying mandatory preparation | `test/features/groups/application/voluntary_leave_prework_degradation_test.dart::PB265-05 both delivery legs degraded still leave once with combined bounded cause` | Host; stable signed notice/outbox fixture; publish throw + inbox non-OK | Execution HEAD RED if an "all delivery failed" aggregate veto remains -> GREEN writes `ALL_NOTICE_DELIVERY_DEGRADED`, performs one rotation claim and one native leave, and makes no claim that a peer observed the event. | Add an `allFailed => block` branch or report delivered -> PB265-05 red | `flutter test test/features/groups/application/voluntary_leave_prework_degradation_test.dart --plain-name 'PB265-05 both delivery legs degraded still leave once with combined bounded cause'`; AUTO + same one-time `GROUP_TESTS` registration |
| TC-265-06 | Primary sign, exact-authority revalidation, and durable notice persistence remain mandatory | `test/features/groups/application/voluntary_leave_prework_degradation_test.dart::PB265-06 pre-checkpoint failures retain intent and emit zero delivery rotation native or cleanup` | Host; first `payload.sign` failure; identity/membership mismatch; repository commit throw | **GREEN sentinel** on current mandatory-sign behavior and accepted Plan 264 authority design -> remains GREEN by retaining retryable intent, not advancing the notice checkpoint, and issuing zero downstream commands. | Broaden degradation catch across signing/revalidation/commit -> PB265-06 red | `flutter test test/features/groups/application/voluntary_leave_prework_degradation_test.dart --plain-name 'PB265-06 pre-checkpoint failures retain intent and emit zero delivery rotation native or cleanup'`; AUTO + same registration; accepted PB264 authority selectors run directly |
| TC-265-07 | A rotation throw after its durable claim is deferred, at-most-once, and cannot veto native leave | `test/features/groups/application/voluntary_leave_prework_degradation_test.dart::PB265-07 rotation throw advances once and restart never rotates again` | Host; repository/bridge throw after `rotation_claimed`; recreated runner | Current caller has uncaught rotation throw sites; execution HEAD must causal-RED or stale-map -> GREEN records bounded rotation deferral, reaches native once, and a recreated runner performs zero sign/publish/inbox/rotation repeats. | Advance phase only on non-throw return or clear the claim on error -> PB265-07 red | `flutter test test/features/groups/application/voluntary_leave_prework_degradation_test.dart --plain-name 'PB265-07 rotation throw advances once and restart never rotates again'`; AUTO + same registration; PB264-10 runs directly |
| TC-265-08 | Aggregate recipient semantics remain honest | `test/features/groups/application/voluntary_leave_prework_degradation_test.dart::PB265-08 one aggregate attempt preserves exact recipient set without peer blame` | Host; three-member fixture and one aggregate bridge response | **GREEN sentinel** on current call shape -> remains GREEN with one exact normalized recipient-set attempt and no invented failed peer. | Split requests, drop/guess a recipient, or assign the aggregate failure to one member -> PB265-08 red | `flutter test test/features/groups/application/voluntary_leave_prework_degradation_test.dart --plain-name 'PB265-08 one aggregate attempt preserves exact recipient set without peer blame'`; AUTO + same one-time `GROUP_TESTS` registration |
| TC-265-09 | Successful delivery, live-publish non-OK, and permission-denied rotation remain non-regressed | `test/features/groups/application/voluntary_leave_prework_degradation_test.dart::PB265-09 successful and expected-degraded legs preserve ordering`; `test/features/groups/application/group_exit_actions_test.dart::active exit completes durable prework before native leave and target cleanup` | Host; current fakes plus post-264 runner fixture | **GREEN sentinel**: successful ordering is unchanged; publish non-OK and rotation null still reach native leave once with honest bounded state. | Treat publish non-OK or rotation null as blocking, or reorder native before notice -> PB265-09/current sentinel red | `flutter test test/features/groups/application/voluntary_leave_prework_degradation_test.dart --plain-name 'PB265-09 successful and expected-degraded legs preserve ordering'`; `flutter test test/features/groups/application/group_exit_actions_test.dart --plain-name 'active exit completes durable prework before native leave and target cleanup'`; PB265 AUTO/`GROUP_TESTS`, existing file already in `GROUP_TESTS` |
| TC-265-10 | Last-admin/pending/exact-membership guards, stable notice, restart, and cleanup stay authoritative | `test/features/groups/application/member_removal_integration_test.dart::GM-015 blocked creator leave keeps remaining-member sends healthy`; `test/features/groups/application/group_exit_intent_runner_test.dart::PB264-09 signed leave notice is watermark-newer, stable, and atomically handed off`; `test/features/groups/application/group_exit_intent_runner_test.dart::PB264-10 process recreation at every durable phase never repeats an earlier side effect` | Host; accepted Plan 264 fixtures plus current last-admin integration fixture | **GREEN sentinel**: guarded exits emit zero leave; stable notice/restart never repeat an earlier phase; cleanup stays exact-membership safe. | Bypass last-admin/authority or reset a durable phase after degradation -> named GM-015/PB264 selector red | `flutter test test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-015 blocked creator leave keeps remaining-member sends healthy'`; exact PB264-09/PB264-10 commands in Acceptance Gates; member-removal file AUTO (`feature-host-all`) and runs directly, accepted Plan 264 runner file must occur once in `GROUP_TESTS` |

### Test Notes

- PB265 fixtures must prove the mandatory checkpoint before injecting a degradable
  failure: exact intent id/revision and stable signed source/time are persisted, and
  the command log shows the signed transition exists. A test that merely returns
  `left` can pass through a skip/not-found branch and is vacuous.
- Command-indexed faults distinguish the first `payload.sign` (mandatory transition)
  from the second sign (best-effort replay envelope). Each test asserts positive and
  negative events/commands, exact phase identity, and one native leave.
- PB265-08 treats the bridge/Go result as aggregate. It may record the attempted set,
  but cannot assert that one member failed without a per-recipient response.
- Accepted PB264 selectors must be re-anchored from the immutable handoff. Renaming is
  allowed only with equivalent causal assertions and literal replacement commands in
  this plan.

## Implementation Steps

1. **Prerequisite handoff.** Do nothing to production while Plan 264 is active. Receive
   its immutable accepted diff/commit and proof summary; snapshot `git status --short`;
   confirm the final DB version, runner files, PB264-09/PB264-10, and registrations.
   Re-run the compact Graphify TDD query with those exact symbols. Stop if ownership is
   still shared or the handoff is not stable.
2. **Stale-or-RED preflight.** Map every TC-265 row to the post-264 source and tests.
   Run direct equivalent selectors. If every row is already causal and green, change
   classification to `stale-already-covered`, record exact verification, and make no
   test/production/registration change. Otherwise add only the missing PB265 cases and
   record a causal RED on execution HEAD before any production edit.
3. Patch only the post-264 signed leave-notice delivery/rotation classifier. The catch
   boundary begins after stable signed-notice persistence and exact authority
   revalidation. Reuse Plan 264's state machine and bounded `last_error_code`; introduce
   no schema, second runner, or per-recipient transport loop. Stop and replan if this
   cannot be done without changing DB shape, wire/relay/native code, or Plan 264's
   at-most-once ordering.
4. Add `voluntary_leave_prework_degradation_test.dart` once to `GROUP_TESTS` only if the
   file is created; AUTO feature-host registration needs no other wiring. Keep all
   upstream registrations single-entry.
5. Run focused GREEN, representative mutation re-red for each distinct classifier
   branch, exact PB264/current preservation selectors, groups, and—only when production
   application code changed—`feature-host-all`. Run analyzer and diff hygiene.

Stop-if conditions:

- Plan 264 is still active, its handoff lacks PB264-09/PB264-10 evidence, or another
  session owns the same runner/test/gate lines.
- The post-264 state machine does not durably separate mandatory preparation from
  best-effort delivery/rotation, so a local catch would permit unsigned or uncommitted
  leave progress.
- Correctness requires DB v104+, wire/relay/native changes, per-recipient claims, or a
  post-leave custody queue. Those are new plans/review decisions, not silent expansion.

## Risks And Blind Spots

- Catch-all false success -> PB265-03 and PB265-06 place faults on opposite sides of the
  durable checkpoint.
- Wrong event/skip-path pass -> every causal test asserts exact intent/source/revision,
  positive degradation code, negative downstream commands where blocking, and exact
  command counts.
- Double side effects after degradation/restart -> PB265-07 plus accepted PB264-10.
- Aggregate relay response misreported as one peer's failure -> PB265-08 and the hard
  no-per-recipient-attribution guard.
- Production-critical end-to-end transport leg: N/A — 265 changes only the local
  post-checkpoint classification and preserves the existing aggregate call shape; it
  makes no real-delivery claim. Any wire, relay, custody, or recipient-observation
  change triggers a new boundary plan instead of substituting this host proof.
- Lifecycle / derived-state durability -> inherited PB264-10/12/18; 265 changes no
  lifecycle trigger or persistence shape.
- Sibling-surface consistency -> Plan 264 PB264-16 must prove Group Info/List/Orbit use
  the same coordinator before 265 starts; dissolve and role-change remain out of scope.
- Destructive-action side effects -> PB265-06/07 and PB264-12 prove no cleanup before
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

# First causal RED after the 264 handoff; expect non-zero for the inbox-veto reason.
# If the exact assertion is already green, perform the documented stale-coverage audit.
flutter test test/features/groups/application/voluntary_leave_prework_degradation_test.dart --plain-name 'PB265-01 aggregate inbox non-ok advances signed leave with offline degradation'

# Focused GREEN; expect exit 0 and zero failed tests.
flutter test test/features/groups/application/voluntary_leave_prework_degradation_test.dart

# Current preservation baselines; re-anchor only if 264 replaces them with equivalents.
flutter test test/features/groups/application/group_exit_actions_test.dart --plain-name 'active exit completes durable prework before native leave and target cleanup'
flutter test test/features/groups/application/member_removal_integration_test.dart --plain-name 'non-creator writer voluntary leave broadcasts member_removed and does NOT throw'

# Run accepted PB264-09/PB264-10 exact selectors from the immutable handoff.
flutter test test/features/groups/application/group_exit_intent_runner_test.dart --plain-name 'PB264-09 signed leave notice is watermark-newer, stable, and atomically handed off'
flutter test test/features/groups/application/group_exit_intent_runner_test.dart --plain-name 'PB264-10 process recreation at every durable phase never repeats an earlier side effect'

# Registration and affected curated lane; target must occur exactly once and be selected.
test "$(rg -c 'test/features/groups/application/voluntary_leave_prework_degradation_test.dart' scripts/run_test_gates.sh)" -eq 1
./scripts/run_test_gates.sh groups

# Only when 265 lands a production application edit; expect exit 0 and zero failures.
./scripts/run_host_test_gates.sh feature-host-all --batch-flutter --concurrency 4 --reporter failures-only

# Hygiene; expect no new analyzer issues and no whitespace errors attributable to 265.
flutter analyze
git diff --check
```

For a `stale-already-covered` disposition, omit the absent PB265 file and registration
commands, run the mapped equivalent selectors plus `groups`, and record why no causal
RED, production edit, or mutation applies.

## Execution Interpretation And Done Criteria

- Expected RED: after Plan 264's handoff, the first uncovered PB265 case must fail
  because a post-checkpoint delivery/rotation fault still blocks or is misclassified;
  the pre-264 baseline is planning evidence only.
- Green sentinels: successful/non-OK live-publish exit, mandatory signing/authority,
  last-admin/pending-role guards, PB264 stable notice/restart, and rotation/cleanup
  preservation.
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
- [ ] Scope Contract And Guard is respected.

## Handoff

- First causal RED command:
  `flutter test test/features/groups/application/voluntary_leave_prework_degradation_test.dart --plain-name 'PB265-01 aggregate inbox non-ok advances signed leave with offline degradation'`;
  N/A only after a source-backed all-rows stale audit of the accepted Plan 264 handoff.
- Preservation command:
  `flutter test test/features/groups/application/group_exit_actions_test.dart --plain-name 'active exit completes durable prework before native leave and target cleanup'`;
  re-anchor to its accepted PB264 equivalent if removed.
- Manual registration: add the PB265 file exactly once to `GROUP_TESTS` only when it is
  created; AUTO feature-host glob otherwise applies. No simulator dispatcher entry.
- Migration: none. DB v103 (or Plan 264's final reserved version) is an inherited
  prerequisite and must not be changed by 265.
- Boundary closure: host-only decision proof with command-indexed fake bridge; no real
  crypto/relay/device claim and no mobile topology.
- Unresolved evidence: final post-264 runner symbols, exact accepted PB264 selectors,
  and which PB265 rows remain causal. These are handoff-gated, not permission to edit
  concurrently.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | Current pre-264 baseline only | Awaiting immutable Plan 264 handoff | Re-anchor, then stale-or-RED preflight |
