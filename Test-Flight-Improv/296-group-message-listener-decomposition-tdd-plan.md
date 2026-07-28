# 296 - DTR-16 GroupMessageListener responsibility decomposition

Status: Plan-green; implementation-complete 2026-07-28
Type: Modification
Spec: `Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md`
(`DTR-16`)
Classification: Plan-green
Closure tier: host
Roadmap ID / wave: `DTR-16` / Wave 4C — Listener, transport, and layering
decomposition
Owner authorization: `DTR16-AUTH-01`; the current project owner explicitly
requested `$tdd-plan`, a critical `$tdd-review` with only necessary plan
repairs, and implementation of DTR-16.
Date: 2026-07-28

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-28 CEST | Evidence Collector — graph | `graphify-arch/tdd_context.py`; architecture graph | The required TDD query returned `confidence=anchored`, `freshness=current`, and fingerprint `4a6dc01007486bc2`; it surfaced the listener and group gate but not the complete caller/test topology. | Verify the facade, responsibilities, callers, tests, and registrations in current source. |
| 2026-07-28 CEST | Evidence Collector — production | listener; production bootstrap/application root; replay, invite, lifecycle, debug, Feed, Orbit, and group-conversation callers | The 6,378-line listener owns four separable state machines plus a load-bearing ingress/ordering seam. One production constructor and all live public entrypoints require the existing facade and constructor defaults to remain source-compatible and subclassable. | Extract only the four safe collaborators; retain ingress/lifecycle and `_handleMessage` in the facade. |
| 2026-07-28 CEST | Evidence Collector — proof | listener, media-task, device-announce, reaction-pipeline tests; gate scripts | Existing coverage is broad preservation evidence but no test requires decomposition or prevents ceremonial files/mixins. A representative 12-test probe passed with zero failures across signed transitions, dispatcher coalescing, stop ordering, membership ordering, reaction serialization, and media-task ownership. | Add one causal structural contract and retain the smallest exact behavior sentinels. |
| 2026-07-28 CEST | Planner | roadmap; tier matrix; plan template; sufficiency checklist; dirty-tree snapshot | Host closure is sufficient: this is an internal Dart ownership extraction with no schema, wire, native callback, crypto algorithm, relay, or OS behavior change. | Run the requested independent `$tdd-review`, patch only verified blockers, then execute RED/GREEN/mutation proof. |
| 2026-07-28 CEST | Reviewer | plan; current listener and constructor; lifecycle and media-reservation tests; gate registration | Core bet confirmed; initial verdict `plan-fixes-required`. Plan 295 collided with DTR-17. Exact ownership/lifetime ports, same-instance restart, and one direct outside-glob media wiring proof were under-specified; a separate diagnostic-stop test and device campaign were not justified. | Renumber DTR-16 to Plan 296, make only the three proof repairs, re-run the review lenses, then execute. |
| 2026-07-28 CEST | Planner + Reviewer | repaired Plan 296; index; roadmap | Required deltas are incorporated without widening production scope. Final review verdict: `ready`. | Write TC-296-01/07 and the lifecycle sentinel before production edits. |

## Problem And Evidence

- Behavior to improve: `GroupMessageListener` must remain the stable public
  group-ingress facade while four independently named internal components own
  signed system transitions, durable membership-dependent buffering, incoming
  reactions, and automatic group-media receive work.
- Impact: the current class spans 6,378 lines and combines subscriptions,
  lifecycle, account gating, message ordering, durable buffers, signed
  membership/config authorization, reaction notification, native background
  task leasing, and output streams. A change to one responsibility must
  currently reason across the whole object.
- Confirmed current gap:
  - `GroupMessageListener` begins at
    `lib/features/groups/application/group_message_listener.dart:175`;
  - subscriptions/controllers/shared queues and lifecycle state are co-owned at
    `:211-235`;
  - pending-reaction work is implemented at `:497-652,5120-5301`;
  - durable membership-dependent buffering is implemented at
    `:1542-2040`;
  - group-media recovery and the shared native critical-task lease machine are
    implemented at `:2042-2341`;
  - signed system parsing, authorization, mutation, and config helpers are
    implemented at `:2348-5119,5302-6328`;
  - none has a separately owned collaborator or causal decomposition contract.
- Confirmed facade contract:
  - public streams/getter/replay/start are at `group_message_listener.dart:330-469`;
  - accepted-invite flush and key-retry entrypoints are at `:1466-1503`;
  - foreground media reservation is at `:2050-2095`;
  - stop/dispose are at `:6328-6377`;
  - the sole production construction, replay wiring, and start remain at
    `lib/app/bootstrap/production_application_bootstrap.dart:3728-3846,3865-3868,4828-4833`;
  - application-root disposal remains at
    `lib/app/application_root.dart:1532-1544`;
  - tests subclass the listener, so the class must not become `final` and its
    overridable stream getters must remain.
- Confirmed load-bearing ordering:
  - message and reaction streams use separate `asyncMap` serialization while
    diagnostics may overlap (`group_message_listener.dart:411-459,654-695`);
  - user content serializes per message ID, while system mutation serializes
    per group only after authorization/audit (`:755-814,2470-2906,5302-5316`);
  - delivery is persist -> emit -> exact pending-reaction claim/flush ->
    placeholder supersession -> key repair -> notification -> tracked media
    recovery (`:1220-1393`);
  - membership replay preserves `membershipPhaseHeld` to avoid re-entering a
    non-reentrant group lifecycle phase (`:1708-1866`);
  - media reservation is registered as in-flight before acquisition and
    `stop()` waits for idempotent release (`:2055-2094,2189-2253`);
  - startup durable flushes remain unawaited and must not silently become stop
    obligations (`:462-468,629-652,1942-1978`).
- Existing coverage:
  - `group_message_listener_test.dart` covers schema/admission, replay,
    dispatcher recovery, stop/dispose, membership/config ordering, signed
    audit, notifications, pending reactions, and dissolve/removal;
  - `group_message_listener_media_background_task_test.dart` covers grant,
    refusal, overlap, foreground handoff, idempotent release, and stop wait;
  - `group_message_listener_device_announce_test.dart` covers signed sibling
    device admission/refusal;
  - `group_reaction_notification_pipeline_test.dart` covers drained reaction
    notification and unread preservation;
  - `GROUP_TESTS` already includes the main listener, media-task, and reaction
    pipeline suites; all feature tests auto-enter `feature-host-all`.
- Missing coverage: no test requires real state-owning collaborators, proves
  their exact method/state ownership, forbids a facade back-reference or
  cosmetic mixin/extension split, freezes every public facade signature, or
  requires the new structural contract and device-announce sentinel in
  `GROUP_TESTS`.
- Confirmed findings:
  - DTR-15 is Plan-green/Wave-accepted, so the roadmap dependency is cleared;
  - four component boundaries are source-coherent when the central ingress and
    lifecycle seam remains in the facade;
  - the existing behavior probe passed 12/12 on the dirty-tree baseline.
- Refuted findings:
  - a wholesale extraction of `_handleMessage`, subscriptions, account gate,
    identity cache, in-flight tracker, or stop ownership is not necessary for
    DTR-16 and would obscure the current ordering contract;
  - file-only extensions or mixins would not create state-owning components and
    are insufficient;
  - a device/relay closure is not triggered because no native implementation,
    OS callback, crypto/wire format, relay, or cross-device behavior changes.
- Unresolved findings: none.
- Affected production, test, and gate files:
  `group_message_listener.dart`; four new private component part files beside
  it; a new decomposition contract test; `scripts/run_test_gates.sh`; this
  plan, the index, and the DTR roadmap.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `4a6dc01007486bc2`;
  `freshness=current`.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "DTR-16 decompose GroupMessageListener behind existing facade in lib/features/groups/application/group_message_listener.dart after DTR-15; preserve crypto background notifications media group state; tests GROUP_TESTS feature-host-all performance-host registration" --profile tdd --budget 700`.
- Anchors:
  `GROUP_TESTS -> scripts/run_test_gates.sh:360`;
  `groupMessageListener -> test/shared/fakes/group_test_user.dart:68`;
  production file
  `lib/features/groups/application/group_message_listener.dart`.
- Surfaced proof/gate files:
  `group_info_wired_test.dart`, `orbit_wired_test.dart`,
  `scripts/run_test_gates.sh`; targeted current-source verification added the
  direct listener, media-task, device-announce, reaction-pipeline, bootstrap,
  application-root, invite, replay, and lifecycle anchors above.
- Graph gaps requiring source search: the query did not enumerate the sole
  production constructor, public replay/flush/reservation callers, or the
  direct listener preservation suites.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Keep `GroupMessageListener` as the public, subclassable ingress/lifecycle
  facade and preserve its constructor parameters/defaults and public members.
- Add four library-private, actual collaborator objects in `part` files:
  `_GroupMessageSystemTransitionProcessor`,
  `_GroupMembershipDependentMessageBuffer`,
  `_GroupReactionIngressProcessor`, and
  `_GroupMediaReceiveCoordinator`.
- Move each collaborator's complete mutable state with its methods:
  system config queue plus signed-audit hash state; membership pending map;
  media lease/acquisition/end state; reaction durable claim/flush ownership.
- Store the four collaborators in facade-owned `late final` fields and
  construct each exactly once in the listener constructor; never recreate one
  lazily, per call, or in `start()`.
- Inject only component-specific repositories and typed callback ports.
  Components must not receive the facade instance or a shared aggregate
  god-context. Cyclic handoffs must remain typed callbacks whose ordering is
  pinned by existing sentinels.
- Give collaborators a live stop/disposed predicate callback, never a captured
  boolean. Keep raw nullable `_getSelfPeerId` and cached
  `_resolveSelfPeerId` as distinct typed identity ports.
- Keep public flush/retry/reservation methods on the facade as exact delegates
  where ownership moves.

Must preserve:

- every public constructor parameter, default, public getter/method, class
  subclassability, and getter overridability -> `TC-296-01`;
- separate stream serialization, message-ID queueing, account gate, recovery
  coalescing, in-flight tracking, idempotent start, same-instance restart, and
  terminal dispose semantics ->
  `TC-296-02`;
- signed authorization, audit-before-mutation, group-scoped mutation ordering,
  self-removal/dissolve atomicity, and raw-versus-cached identity behavior ->
  `TC-296-03`;
- durable membership buffer replay flags, lifecycle-phase exclusion, deferred
  key repair, and exact deletion/preservation behavior -> `TC-296-04`;
- exact pending-reaction claim-before-emit, serial live apply, contextual
  notification, and unread preservation -> `TC-296-05`;
- shared media-task participant accounting, foreground handoff, refusal/error
  behavior, tracked fire-and-forget recovery, and stop wait -> `TC-296-06`.

Hard `Do not`:

- Do not extract the central `_handleMessage` sequencing seam, subscriptions,
  stream controllers, account gate, cached identity, message work queue,
  in-flight tracker, or stop/dispose ownership in this plan.
- Do not implement components as mixins/extensions, pass the facade into a
  collaborator, add public collaborator injection, make the facade `final`, or
  weaken public source/API locks.
- Do not recreate collaborators in `start()` or per call, capture the current
  stopping flag as a boolean, collapse raw/cached identity resolution, or move
  the reaction subscription out of the facade.
- Do not split system authorization/audit from its mutation queue, split
  self-removal/dissolve lifecycle bodies across callbacks, or merge message,
  reaction, and diagnostic scheduling.
- Do not change repositories, DB schema/migrations, bridge/native/Go code,
  payloads, crypto/signature policy, notifications, media policy, relay
  behavior, DTR-12 exceptions, DTR-17, or DTR-18.

Deferred / accepted difference:

- `_handleMessage` remains a deliberately broad orchestration adapter -> owner
  DTR-18 or a separately planned later slice after these component ports prove
  stable.
- P2P decomposition and layering relocation -> DTR-17 and DTR-18.
- No LOC target is a gate; ownership and preservation are the gate.

Dependencies:

- DTR-15 is Plan-green/Wave-accepted.
- DTR-18 remains blocked on Plan-green DTR-16 and DTR-17 facades.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-296-01 | Four real state-owning collaborators sit behind the unchanged public/subclassable facade; exact methods, helper models, and mutable state move once; `_shouldBufferPreJoinSystemMessage` moves with system parsing; the facade retains `_handleMessage`, subscriptions, queues, identity cache, tracking, and lifecycle | `test/features/groups/application/group_message_listener_decomposition_contract_test.dart::DTR-16 extracts four state-owning collaborators behind the stable facade` | Host analyzer AST/source contract / real repository | causal RED: four files/classes/owned-state fields are absent and the facade still declares every implementation -> GREEN: four facade `late final` fields are initialized exactly once in the constructor; system owns `_groupConfigWorkQueue`, signed-audit hash state, `_SignedTransitionAuditActorBinding`, `_shouldBufferPreJoinSystemMessage`, and the full system family; membership owns its pending model/map and buffer/flush/delete family; reaction owns `_samePendingReaction` and durable claim/flush/apply/derivative family without a new queue/subscription; media owns its internal lease plus acquire/release/recovery family while the public reservation wrapper remains on the facade | delete/rename/recreate a collaborator; leave/duplicate an owned declaration; use mixin/extension; pass `GroupMessageListener`/aggregate context; capture a stop boolean; collapse distinct raw `_getSelfPeerId` and cached `_resolveSelfPeerId` ports; move `_handleMessage`, subscriptions, queue/cache/tracking/lifecycle; or alter the complete public fingerprint (non-final class, constructor/defaults, four getters, replay/start/flush/retry/reserve/stop/dispose) -> TC-296-01 red | `flutter test --no-pub test/features/groups/application/group_message_listener_decomposition_contract_test.dart --plain-name 'DTR-16 extracts four state-owning collaborators behind the stable facade'`; AUTO `feature-host-all`; add to `GROUP_TESTS` |
| TC-296-02 | Ingress keeps separate message/reaction serialization, per-message queueing, dispatcher recovery coalescing, account gating, stop waits without late emission, idempotent start, awaited same-instance restart, and terminal dispose | `group_message_listener_test.dart::{DTR-16 facade start is idempotent, awaited stop permits one clean restart, and dispose is terminal, DE-012 dispatcher overflow triggers one replay recovery and coalesces duplicates, PGC-008 stop awaits cancellation and late message handler does not emit, PGC-008 stop guards late reaction stream emission, migration-blocked account suppresses live group message before persistence or notification}` | Host application / real facade with controlled streams, contended repositories, fake gate | new lifecycle sentinel is GREEN on HEAD before extraction; all sentinels remain GREEN after extraction | recreate/dispose a component across `start`/`stop`, capture stale stopping state, replace either `asyncMap`, merge queues, stop tracking a handler, emit while stopping, or bypass the account gate -> named selector red | exact regex command below; existing `GROUP_TESTS` + AUTO feature |
| TC-296-03 | Signed system transitions authorize/audit before mutation, remain group-serialized, preserve raw/cached identity distinctions, and keep self-removal/dissolve ordering | `group_message_listener_test.dart::{valid signed transition applies live and duplicate replay is idempotent while tampered replay is blocked, DB002 logs membership and metadata events and blocks changed replay before mutation, ST-002 permutes remove re-add key config and message ordering, ML-017 self-removal serializes native leave and atomic authority commit before terminal key teardown}` plus `group_message_listener_device_announce_test.dart::an account-signed device_announce HOLDS the sibling device pending` | Host application / fake repositories plus signed-audit bridge fixture | GREEN sentinel -> unchanged durable state, event log, native-call order, and rejection behavior | move audit inside/after mutation, split the config queue, collapse raw/cached identity ports, or emit before durable authority -> selector red | exact signed/system command below; add device-announce file to `GROUP_TESTS`; AUTO feature |
| TC-296-04 | Membership-dependent messages retain bounded durable buffering, phase-held replay, deferred repair, restart flush, and removal-window preservation | `group_message_listener_test.dart::{DE-017 content before member add is buffered then respects joined interval, marked shell startup skips loaded pending membership and reaction replay leaves, DE-017 member removal repairs post-removal content while preserving prior content}` | Host application / fake durable pending repository | GREEN sentinel -> exact buffer/flush/delete and preservation assertions remain | drop `membershipPhaseHeld`, request repair inside the held phase, emit before durable delete, or discard preserved pre-removal content -> selector red | exact membership command below; existing `GROUP_TESTS` + AUTO feature |
| TC-296-05 | Reaction processor claims/deletes exact pending rows before emit, serializes live reactions, preserves contextual notification and unread state | `group_message_listener_test.dart::{INV-R6 serializes live reactions so handlers do not interleave, INV-R4/R5 buffers a reaction-before-message then flushes it exactly once}` plus `group_reaction_notification_pipeline_test.dart::{foreground drained reaction still runs contextual notification gate, chat and announcement reactions leave message unread state unchanged}` | Host application/integration / fake repos and notification seams | GREEN sentinel -> same one-emit, ordering, notification, and unread assertions | emit before exact claim/delete, overlap handlers, await/change the notification scheduling contract incorrectly, or mutate unread state -> selector red | exact reaction command below; existing `GROUP_TESTS` + AUTO feature |
| TC-296-06 | Media coordinator owns the whole shared native-task lease machine and automatic recovery; handoff/overlap/refusal/error/idempotent release, stop wait, and production reservation wiring remain exact | `group_message_listener_media_background_task_test.dart::{P269 foreground handoff reservation shares one task with background receive, P269 stop waits for an idempotently released foreground reservation, P269 two overlapping background media messages share one critical task and stop waits, P269 background group media receive balances grant refusal success throw and stop wait}` plus `test/integration/group_media_ios_background_recovery_test.dart::P269 production entry causally wires observation acceptance and the shared receive-task reservation` | Host application/source wiring / injected native begin/end callbacks, fake coordinator, real production composition source | GREEN sentinel -> same begin/end balance, participant count, tracked completion, failure behavior, and production reservation delegate | split lease state, acquire after untracked work, end with live participants, double-end, let stop complete before release, or bypass the facade reservation in production -> selector red | media suite exact; production source-contract selector exact because it is outside feature/core globs; both already enter `GROUP_TESTS`, media suite AUTO feature |
| TC-296-07 | Causal and signed-device tests occur exactly once in the curated group lane; new part files remain reachable and add no architecture exception | `group_message_listener_decomposition_contract_test.dart::TC-296-07 keeps DTR-16 registration and architecture scope exact`; `runtime-roots`; `architecture-boundaries`; `completeness-check` | Host source/tool / real scripts and repository | causal registration RED until both paths are exact `GROUP_TESTS` members -> GREEN with AUTO feature discovery, reachable `part` files, no exception/count drift | omit/duplicate either array entry, orphan a part, add an architecture exception, or register only under host discovery -> TC-296-07/tool red | direct contract; `./scripts/run_test_gates.sh runtime-roots`; `./scripts/run_test_gates.sh architecture-boundaries`; `./scripts/run_test_gates.sh completeness-check`; exact `GROUP_TESTS` + AUTO feature |

## Implementation Steps

1. Snapshot `git status --short`. Add the decomposition contract and
   same-instance lifecycle sentinel before production edits. Run the lifecycle
   sentinel GREEN, then TC-296-01 and TC-296-07 for causal RED before adding
   the exact `GROUP_TESTS` registrations.
2. Create the four private component `part` files. Move complete component
   state and methods without rewriting their internal ordering or behavior.
3. Construct component-specific collaborators privately inside the existing
   constructor. Preserve all public parameters/defaults and delegate only the
   public flush/reservation seams whose ownership moved.
4. Run focused GREEN and the exact sentinel bundles. Stop-if: any extraction
   requires a public API change, facade/component back-reference, aggregate
   god-context, changed scheduling, changed durable/native ordering, schema,
   wire/native/Go change, or DTR-12 rebaseline; replan instead.
5. Run representative mutation re-reds for collaborator ownership/public API,
   signed audit-before-mutation, reaction claim-before-emit, and media lease
   participant accounting; restore each mutation and rerun its selector.
6. Run the curated group gate, feature family, policy gates, strict analysis,
   diff hygiene, and one incremental Graphify refresh.

## Risks And Blind Spots

- Cosmetic file split -> TC-296-01 requires actual classes, moved state, exact
  method ownership, typed component-specific ports, and forbids
  mixin/extension/facade-context shortcuts.
- Async semantic drift while moving code -> TC-296-02 through TC-296-06 pin
  queue, await/unawait, durable commit, notification, and native-task ordering.
- Lifecycle / derived-state durability: TC-296-03/04/05 cover restart/replay and
  durable pending state; no new derived state is introduced.
- Sibling-surface consistency: Feed, Orbit, group conversation, replay, invite,
  and debug callers continue through the unchanged public facade; TC-296-01
  freezes the API and production callsites.
- Destructive-action side effects: TC-296-03/04 preserve self-removal,
  dissolve, pending-row deletion, message deletion windows, and retained
  history; no new destructive behavior is introduced.
- Invariant re-verification under new transitions: TC-296-03/04 cover re-add,
  removal, replay, restart, and lifecycle phase re-entry.
- Collaborator lifetime drift: TC-296-01 requires constructor-once fields and
  live stop predicates; TC-296-02 proves an awaited same-instance restart and
  terminal dispose. Diagnostics stay facade-owned, so a separate diagnostic
  stop test is intentionally not added.
- Device/OS boundary: N/A — injected native callbacks and their production
  implementation are unchanged; the plan claims only Dart ownership and host
  ordering preservation.
- Performance: N/A per-plan — no algorithm, rebuild surface, queue cardinality,
  or performance threshold changes. Wave 4C decides its conditional aggregate
  `performance-host` obligation after DTR-17/DTR-18.

## Gate Cadence

- Per-plan closure: causal decomposition/registration tests; exact ingress,
  system, membership, reaction, and media sentinels; `groups`;
  `feature-host-all`; `runtime-roots`, `architecture-boundaries`, and
  `completeness-check`; strict analysis and diff hygiene.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the Wave 4C dependency
  batch (DTR-16, DTR-17, and DTR-18) is Plan-green, and once at final
  rollout/release closure.
- Shared tests outside feature/core globs:
  `test/integration/group_media_ios_background_recovery_test.dart` is run by
  exact selector for production reservation wiring and remains registered in
  `GROUP_TESTS`; policy gates are invoked directly.

## Acceptance Gates

```bash
# Snapshot before execution; preserve unrelated Wave 4A/4B dirty-tree work.
git status --short

# Causal RED before production edits; expect non-zero because the four
# collaborators do not exist and ownership remains in the facade.
flutter test --no-pub \
  test/features/groups/application/group_message_listener_decomposition_contract_test.dart \
  --plain-name 'DTR-16 extracts four state-owning collaborators behind the stable facade'

# Registration RED before script edit, then GREEN; expect exact one-time
# GROUP_TESTS membership and zero failures.
flutter test --no-pub \
  test/features/groups/application/group_message_listener_decomposition_contract_test.dart \
  --plain-name 'TC-296-07 keeps DTR-16 registration and architecture scope exact'

# New preservation sentinel before and after production edits; expect exit 0.
flutter test --no-pub \
  test/features/groups/application/group_message_listener_test.dart \
  --plain-name 'DTR-16 facade start is idempotent, awaited stop permits one clean restart, and dispose is terminal'

# Focused GREEN; expect exit 0 and zero failed tests.
flutter test --no-pub \
  test/features/groups/application/group_message_listener_decomposition_contract_test.dart

# Ingress/lifecycle sentinels; expect exit 0 and all selected tests green.
flutter test --no-pub \
  test/features/groups/application/group_message_listener_test.dart \
  --name='DE-012 dispatcher overflow|PGC-008 stop awaits cancellation|PGC-008 stop guards late reaction|migration-blocked account suppresses live group message'

# Signed system + membership sentinels; expect exit 0 and no state/order drift.
flutter test --no-pub \
  test/features/groups/application/group_message_listener_test.dart \
  test/features/groups/application/group_message_listener_device_announce_test.dart \
  --name='valid signed transition applies|DB002 logs membership|ST-002 permutes|ML-017 self-removal serializes|account-signed device_announce|DE-017 content before member add|marked shell startup skips|DE-017 member removal repairs'

# Reaction sentinels; expect exact-once/order/notification/unread assertions.
flutter test --no-pub \
  test/features/groups/application/group_message_listener_test.dart \
  test/features/groups/integration/group_reaction_notification_pipeline_test.dart \
  --name='INV-R6 serializes|INV-R4/R5 buffers|foreground drained reaction|chat and announcement reactions leave message unread'

# Media/native-task policy sentinels; injected callbacks, zero failures.
flutter test --no-pub \
  test/features/groups/application/group_message_listener_media_background_task_test.dart

# Production media-reservation wiring is outside feature/core auto globs.
flutter test --no-pub \
  test/integration/group_media_ios_background_recovery_test.dart \
  --plain-name 'P269 production entry causally wires observation acceptance and the shared receive-task reservation'

# Curated and affected family closure; expect target tests selected, exit 0,
# and zero failed tests.
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh feature-host-all

# Policy/discovery; expect PASS with no new roots, exceptions, or omissions.
./scripts/run_test_gates.sh runtime-roots
./scripts/run_test_gates.sh architecture-boundaries
./scripts/run_test_gates.sh completeness-check

# Hygiene; expect no diagnostics attributable to DTR-16 and no whitespace
# errors. The whole dirty tree remains visible.
flutter analyze
git diff --check

# One coherent app-owned refresh after implementation; expect exit 0.
./graphify-arch/refresh_arch_graph.sh --incremental
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-296-01 reports absent collaborator files/classes and
  facade-owned methods/state; TC-296-07 reports absent curated registrations.
- Green sentinels: TC-296-02 through TC-296-06 remain green on HEAD and after
  extraction; they are preservation evidence, not fabricated REDs.
- Pre-existing dirty tree / known failure: the Wave 4A/4B plans, production
  refactors, tests, gate scripts, roadmap/index, Graphify output, and evidence
  archives are user-owned baseline. No DTR-16 focused baseline failure was
  observed; the representative probe passed 12/12.
- Environment blocker: none; closure is host-only.
- Scope drift: any public API, behavior, schema, bridge/native/Go, DTR-12
  exception, DTR-17/DTR-18, or unrelated dirty-tree edit blocks completion.

- [x] Every behavior has a named test or justified proof.
- [x] Causal RED, focused GREEN, and representative mutation re-red are
      recorded.
- [x] Preservation and named gates pass with semantic outcomes.
- [x] Harness registration is implemented and verified.
- [x] `groups` and `feature-host-all` pass with semantic outcomes.
- [x] `runtime-roots`, `architecture-boundaries`, and `completeness-check`
      pass.
- [x] `flutter analyze` has no DTR-16 issue; `git diff --check` is clean.
- [x] The architecture graph is incrementally refreshed once.
- [x] Scope Contract And Guard is respected.

## Handoff

- First causal RED command:
  `flutter test --no-pub test/features/groups/application/group_message_listener_decomposition_contract_test.dart --plain-name 'DTR-16 extracts four state-owning collaborators behind the stable facade'`.
- Preservation command:
  `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart test/features/groups/application/group_message_listener_media_background_task_test.dart test/features/groups/application/group_message_listener_device_announce_test.dart test/features/groups/integration/group_reaction_notification_pipeline_test.dart --name='valid signed transition applies|DE-012 dispatcher overflow|PGC-008 stop awaits cancellation|ST-002 permutes|INV-R6 serializes|P269 foreground handoff|P269 stop waits|P269 two overlapping|P269 background group media|account-signed device_announce|foreground drained reaction'`.
- Manual registration: add the new decomposition contract and existing
  device-announce sentinel exactly once to `GROUP_TESTS`; feature-family
  registration is AUTO.
- Migration: none.
- Boundary closure: host-only; no simulator/device/relay profile is triggered.
- Gate cadence: focused + `groups` + `feature-host-all` now; aggregate
  `host-all` after Wave 4C and at final release closure.
- Confirmed findings: four safe collaborators; stable live facade/callers;
  DTR-15 dependency green; representative preservation probe green.
- Refuted findings: wholesale ingress extraction, cosmetic mixin/file split,
  plan-level full `host-all`, and device/performance closure.
- Closure evidence: the stale exact-file ownership inventories were retargeted
  to the two DTR-16 part files that now own the same behavior; their exact
  selectors passed `2/2` and `1/1`, and the complete conversation family then
  passed `2001/2001`. The serialized `groups` gate passed all 3,265 Flutter
  tests and every Go/relay tail. `feature-host-all` passed 8,441 tests with one
  declared skip across 811 paths. The final expanded focused set passed
  `28/28`, whole-tree `flutter analyze` reported no issues, and no unresolved
  DTR-16 evidence remains.

## Reviewer Findings

- Initial verdict: `plan-fixes-required`; core bet confirmed.
- Required and applied:
  - renumbered the colliding DTR-16 artifact and cases from 295 to fresh 296;
  - made TC-296-01 exact about constructor-once collaborator lifetime,
    complete ownership, pre-join system parsing, live stop predicates, distinct
    raw/cached identity ports, and the full public facade fingerprint;
  - added one HEAD-green same-instance start/stop/restart/dispose sentinel;
  - added the exact outside-glob production media-reservation wiring command.
- Rejected as unnecessary: a separate diagnostic-stop test and any
  device/relay campaign; those surfaces do not move.
- Final five-lens verdict after the repairs: `ready`; execute Plan 296 without
  widening scope.
- Post-implementation critical audit found five proof-only gaps: parse
  diagnostics were not rejected, the live lifecycle callback was not proven
  stored, facade delegates were name-only, gate registration could match dead
  text, and the facade's existing DTR-18 exception was not pinned. TC-296-01/07
  now close those gaps exactly, without a production-scope change; independent
  re-review found no further necessary repair.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-28 CEST | reviewed / ready | plan, index, roadmap | `$tdd-review`: initial fixes required; repaired Plan 296 ready | core bet confirmed; only required deltas applied | none | lifecycle GREEN, contract/registration RED |
| 2026-07-28 CEST | causal RED | decomposition contract; listener lifecycle test; group gate script | lifecycle sentinel `1/1` GREEN; ownership contract RED on four absent parts; registration contract RED first on absent paths and then absent live part directives | the new tests distinguish the required extraction and live registration from HEAD | none | extract only the four reviewed owners |
| 2026-07-28 CEST | implementation GREEN | stable facade; four private part files; decomposition/lifecycle tests; group registration | structural contract `2/2`; focused bundles `1/1`, `5/5`, `8/8`, `4/4`, and `6/6`; final combined sentinel rerun `25/25` | constructor-once collaborators own system transitions, membership buffering, reaction ingress, and media receive leasing while the facade API/lifecycle/ingress seam stays stable | none | mutation proof and independent audit |
| 2026-07-28 CEST | mutation proof | facade; system, reaction, and media collaborators | four representative mutations each re-red: non-final collaborator lifetime, audit after mutation, skipped pending-reaction delete, and zero media participant accounting; every mutation was restored and its selector returned GREEN | ownership, authorization ordering, exact reaction claim, and lease accounting are causally protected | none | closure gates |
| 2026-07-28 CEST | implementation review | decomposition contract | independent audit identified five proof gaps; exact contract hardening passed `2/2`; re-review found no further necessary repair | parse diagnostics, stored live lifecycle ports, exact delegates, executable gate selection, and the sole pre-existing facade exception are pinned | none | run policy, static, and aggregate gates |
| 2026-07-28 CEST | closure repair | delivered-status minting inventory; forwarding-marker boundary inventory | exact ownership selectors passed `2/2` and `1/1`; full conversation family passed `2001/2001` | the three delivered writes and membership-buffer forwarding marker remain semantically unchanged at their new DTR-16 owners; no production change was required | none | rerun required aggregate lanes |
| 2026-07-28 CEST | aggregate verification | curated groups and feature family | `groups`: 3,265 Flutter tests plus all Go/relay tails passed; `feature-host-all`: 8,441 pass / 1 declared skip / 0 fail across 811 paths | both required per-plan aggregate lanes exited 0 on the stabilized integrated tree | none | final focused, policy, static, hygiene, and graph receipts |
| 2026-07-28 CEST | Plan-green closure | DTR-16 focused set; policy tools; whole tree; Graphify | expanded focused set `28/28`; `runtime-roots` `20/20`; architecture boundaries `6/6` with zero issues; completeness `1357/1357`; `flutter analyze` no issues; format and `git diff --check` clean; incremental architecture refresh exited 0 | implementation and every Plan 296 closure obligation are green; the public facade and exact four-collaborator scope remain unchanged | Plan 296 none; Wave 4C acceptance remains separate | run Wave 4C `host-all` only after DTR-16, DTR-17, and DTR-18 are Plan-green |
| 2026-07-28 CEST | integrated closure repair | system-transition processor; decomposition contract; focused lifecycle callers; affected aggregate lanes | strengthened structural contract produced a causal RED on the stored-but-unused lifecycle port, then passed `2/2`; combined system/lifecycle selectors passed `11/11`; suppression ratchet and strict analysis passed at three reviewed generated-l10n identities with zero issues; `groups` passed `+3265` plus all Go/relay tails; `feature-host-all` passed `+8441 ~1` across 811 paths; architecture `6/6`, completeness `1357/1357`, and refreshed Graphify fingerprint `5f2656692cadb1f9` are current | `_isStoppingOrDisposed` now fences only processor-to-facade message/removal emissions; accepted durable transition work remains in flight through stop, matching the pre-existing facade no-op boundary while eliminating the dormant callback/suppression | none; Plan 296 remains Plan-green and this narrow repair also clears Plan 295's integrated strict/core blocker | Wave 4C/full `host-all` remains later |
