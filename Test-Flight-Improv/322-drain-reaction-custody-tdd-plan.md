# 322 - Drain Reaction Custody (D4 resolution)

Status: execution-ready
Type: Bug
Spec: free-text intent — D4 deferred from plan 309 (`309-…:127,144`); no formal spec
Classification: implementation-ready
Closure tier: host (Dart feature tier; no OS boundary — the notification half of D4 is explicitly NOT built, see Scope Contract)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-02 | Evidence Collector | `drain_group_offline_inbox_use_case.dart`, `group_message_listener_reaction_ingress_processor.dart`, `handle_incoming_group_reaction_use_case.dart`, `show_notification_use_case.dart`, `group_reaction_notification_pipeline_test.dart`, 8 drain construction sites | D4's notify half REFUTED by the shipped drain-persists/push-presents contract; a real custody defect found underneath | Plan the custody fix only |
| 2026-08-02 | Planner | `handle_app_resumed.dart`, `startup_router.dart`, `application_root.dart`, `production_application_bootstrap.dart` | `pendingReactionRepo` already threaded to `ApplicationRoot` as a required field ⇒ fix is call-site wiring | Emit contract |

## Problem And Evidence

- **Behavior to improve:** a group reaction recovered by the offline inbox drain is **permanently discarded** when its target message has not landed yet, on 5 of the 8 production drain entry points — including the app-resume drain, the highest-traffic one. The reaction never appears in the timeline, on any device, ever.
- **Impact:** silent reaction-state loss after any offline period. Unlike a missed notification this is unrecoverable — the relay entry is consumed by the drain that dropped it, and there is no group ack/delete verb, so nothing re-delivers it.
- **Confirmed root cause:** `handleIncomingGroupReaction` buffers a validated reaction whose target is absent **only when `pendingReactionRepo != null`** (`handle_incoming_group_reaction_use_case.dart:182-202`); otherwise it emits `GROUP_REACTION_RECEIVE_UNKNOWN_MESSAGE` and returns `unknownMessage` with no persistence (`:203-214`). The drain forwards whatever it was constructed with (`drain_group_offline_inbox_use_case.dart:664`), and five call sites pass nothing.

  | # | Call site | `pendingReactionRepo` |
  |---|---|---|
  | 1 | `production_application_bootstrap.dart:3826/:3833` (dispatcher-overflow recovery) | yes |
  | 2 | `production_application_bootstrap.dart:4475/:4482` (retrier) | yes |
  | 3 | `handle_app_resumed.dart:403` (resume, first page) | **NO** |
  | 4 | `handle_app_resumed.dart:482` (resume continuation) | **NO** |
  | 5 | `startup_router.dart:965` (startup network recovery) | **NO** |
  | 6 | `application_root.dart:1930/:1937` (foreground push) | yes |
  | 7 | `prepare_notification_route_target_use_case.dart:58` (notif tap) | **NO** |
  | 8 | `accept_pending_group_invite_use_case.dart:1230` (post-accept) | **NO** |

- **Existing coverage:** `drain_group_offline_inbox_use_case_test.dart:13340` (`INV-R4 buffers a drained reaction whose target message is absent`) proves the buffer works **when the repo is supplied**. No test supplies the *production* wiring, so the five unwired sites are invisible.
- **Missing coverage:** no test asserts that a production drain entry point buffers rather than drops; `hasFreshRouteAuthority` (`:657`) has zero test coverage.
- **Refuted findings (do NOT re-introduce):**
  - *"The drain should emit a notification for group reactions"* (D4 as filed) — **refuted**. The architecture is deliberate and pinned: `group_reaction_notification_pipeline_test.dart:25` (`display must follow inbox drain`) and `:100` (`real live listener and remote drain share one atomic transition claim`). The push path both invokes the drain and presents (`application_root.dart:1930-1943`, `:1968-1990`). A drain-side notify would be a **third** producer arbitrated only by the durable claim, which fails OPEN on storage error (`show_notification_use_case.dart:171-181`), evicts past 256 entries with a 48h TTL over a namespace shared with `group_message`/`new_message` (`durable_notification_tone_lease.dart:166-169`, `:813-880`), and has no live-wins marker on the reaction lane.
  - *"Route the drained reaction through the listener's reaction ingress"* — **refuted**. `_handleReaction` calls `handleIncomingGroupReaction` **without** `senderPublicKey` (`group_message_listener_reaction_ingress_processor.dart:245-257`) because the live bridge event never carries it (`go-mknoon/node/pubsub.go:1707-1713`), whereas the drain extracts a real one from the signed replay envelope (`drain_…:2062-2069`, forwarded at `:672`). That field is a live comparand in `_isReactionSenderDeviceBound` (`handle_incoming_group_reaction_use_case.dart:322-339`) and absence **fails open** on the key dimension. Routing through the listener would silently weaken sender binding for the drain lane.
  - *"Buffered reactions already notify on drain, so the gap is partly closed"* — **refuted**. The flush notify additionally requires `targetMessage.senderPeerId == selfPeerId && !targetMessage.isIncoming` (`…_processor.dart:345-350`); a freshly drained *incoming* message can never satisfy it.
- **Unresolved findings:** none.
- **Affected production / test / gate files:** `handle_app_resumed.dart`, `startup_router.dart`, `prepare_notification_route_target_use_case.dart`, `accept_pending_group_invite_use_case.dart`, `application_root.dart`, `production_application_bootstrap.dart`; `drain_group_offline_inbox_use_case_test.dart`; `scripts/run_test_gates.sh` (already registered).

## Graph Grounding Snapshot
- Graph fingerprint / freshness: `a5d1d9254ab1fe95`, `stale:scripts/test/probe_relay_live_digest_321.sh` (script-only drift; no production topology change).
- Query / profile: `python3 graphify-arch/tdd_context.py query "drain_group_offline_inbox_use_case reaction branch notification emission group reaction drain" --profile tdd --budget 700`.
- Anchors: `drain_group_offline_inbox_use_case.dart`, `group_message_listener.dart`, `handle_incoming_group_reaction_use_case.dart`, `group_offline_replay_envelope.dart`.
- Surfaced proof/gate files: `drain_group_offline_inbox_use_case_test.dart`, `group_message_listener_test.dart`, `group_reaction_notification_pipeline_test.dart`.
- Graph gaps that required raw source search: the 8-site construction census and the `pendingReactionRepo` column (graph returned `confidence=broad` for call-site wiring).
- Reuse rule: anchors are search starting points; every conclusion above is re-verified in current source.

## Scope Contract And Guard

In scope:
- Pass `pendingReactionRepo` at the five unwired production drain entry points so a drained reaction whose target is absent is durably buffered instead of dropped.

Must preserve:
- The drain emits **no** notifications → `drain_group_offline_inbox_use_case_test.dart` reaction tests assert `notifications.shown` empty; new TC-322-04 GREEN sentinel.
- `senderPublicKey` continues to reach `handleIncomingGroupReaction` from the drain → TC-322-05 GREEN sentinel.
- Buffer bounds (TTL + per-group oldest-first cap) still apply → `handle_incoming_group_reaction_use_case.dart:349-381` unchanged; TC-322-06 sentinel.
- Push-path presentation unchanged → `group_reaction_notification_pipeline_test.dart` (3 tests) untouched and green.

Hard `Do not`:
- **Do not add any notification emission to the drain** (D4's notify half is closed WON'T-BUILD — see Refuted findings). This is the plan's hard scope guard.
- Do not route the drain's reaction branch through `GroupMessageListener`; do not add a public reaction-replay seam.
- Do not modify `handle_incoming_group_reaction_use_case.dart` behavior, the buffer bounds, or the relay.

Deferred / accepted difference:
- **Group reactions lack exact-replay idempotency** — `_isStaleComparedToCurrent` (`handle_incoming_group_reaction_use_case.dart:386-397`) uses `isBefore`, so an identical re-delivery re-saves and re-emits `ReactionChange.upsert`, unlike the 1:1 lane (`handle_incoming_reaction_use_case.dart:296-309`, `ReactionAddApplyResult.exactReplay`) and unlike group messages (`group_message_listener.dart:1090-1109`). **Latent today** because `saveReaction` is id-idempotent and the notify it would double-fire is not built by this plan. Ready-made fix shape: the shared `ReactionRepository.applyIncomingAdd` (`reaction_repository.dart:40-56`) already returns `exactReplay`. Owner: notification-reliability wave. Not built here because it changes live-path emission and would move existing pins (e.g. `group_message_listener_test.dart:14776` asserts `saveReactionCallCount == 2`).
- `hasFreshRouteAuthority` (`:657`) remains untested beyond TC-322-03's indirect path. Owner: same wave.

Dependencies:
- None. No relay change, no migration, no deploy.

## Test Contract
Zero empty cells.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| TC-322-01 | The resume drain buffers a target-absent reaction instead of dropping it | `drain_group_offline_inbox_use_case_test.dart::D4-322 resume-wired drain buffers a target-absent reaction` | unit / fakes + recording `GroupPendingReactionRepository` | causal RED (HEAD drops it: `pendingReactions` empty, `GROUP_REACTION_RECEIVE_UNKNOWN_MESSAGE` emitted) → 1 buffered row with matching `id`/`messageId`, and NO `…UNKNOWN_MESSAGE` event | remove `pendingReactionRepo:` from `handle_app_resumed.dart:403` → TC-322-01 red | `flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`; AUTO (already in `GROUP_TESTS` `:569`) |
| TC-322-02 | Every production drain entry point forwards the repo (census, not one instance) | `drain_group_offline_inbox_use_case_test.dart::D4-322 all production drain entry points forward pendingReactionRepo` | unit / source-census over the 5 call sites via a shared wiring helper | causal RED (5 of 8 sites omit it) → all 8 forward a non-null repo | drop the argument at any one site → TC-322-02 red naming that site | same as TC-322-01 |
| TC-322-03 | A buffered drained reaction replays onto the timeline when its target later drains | `drain_group_offline_inbox_use_case_test.dart::D4-322 buffered drained reaction flushes when the target message arrives` | unit / fakes + listener | causal RED (nothing was buffered on HEAD, so nothing flushes: `saveReactionCallCount == 0`) → reaction persisted exactly once after the message lands | revert the wiring → TC-322-03 red | same as TC-322-01 |
| TC-322-04 | The drain still emits ZERO notifications for reactions (D4 notify stays unbuilt) | `drain_group_offline_inbox_use_case_test.dart::D4-322 drain reaction path shows no notification` | unit / `FakeNotificationService` + tracker + `getSelfPeerId`, self-authored non-incoming target | GREEN sentinel (passes today) → `notifications.shown` empty with a fully notification-wired drain | add any `maybeShowNotification` call to the drain reaction branch → TC-322-04 red | same as TC-322-01 |
| TC-322-05 | `senderPublicKey` still reaches the reaction handler from the drain | `drain_group_offline_inbox_use_case_test.dart::D4-322 drain forwards senderPublicKey to reaction sender binding` | unit / envelope with a mismatched sender key | GREEN sentinel → mismatched key ⇒ rejected (`senderMismatch`, no save) | drop `senderPublicKey:` at `drain_…:672` → the mismatched key is accepted ⇒ TC-322-05 red | same as TC-322-01 |
| TC-322-06 | Buffer bounds still apply to drain-buffered reactions | `handle_incoming_group_reaction_use_case_test.dart::(existing per-group cap + TTL tests)` | unit / fakes | GREEN sentinel → cap/TTL unchanged | raise `kMaxBufferedGroupReactionsPerGroup` → existing cap test reds | `flutter test test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`; AUTO (`GROUP_TESTS` `:535`) |
| TC-322-07 | Push-path reaction presentation is unchanged | `group_reaction_notification_pipeline_test.dart` (all 3 tests) | integration / fakes + real `DurableNotificationToneLease` | GREEN sentinel → 3/3 pass unchanged | add a drain-side notify (the refuted design) → `:100` claim test reds on a second banner | `flutter test test/features/groups/integration/group_reaction_notification_pipeline_test.dart`; AUTO (`GROUP_TESTS` `:526`) |

### Test Notes
- TC-322-01: discriminator is event-based — assert the buffered row **AND** absence of `GROUP_REACTION_RECEIVE_UNKNOWN_MESSAGE`. Both paths otherwise return `success`-shaped drain results, so the row alone does not distinguish drop from buffer.
- TC-322-02: assert the relationship (each site's drain invocation receives the *same* non-null repo instance the bootstrap constructed), not eight independent non-null checks.
- TC-322-04: the fixture must satisfy every gate the live notify path requires (self-authored, non-incoming, ordinary policy, unmuted, unarchived, resolvable `selfPeerId`) — otherwise it passes for the wrong reason and would not catch a real drain-side notify.

## Implementation Steps
1. Snapshot `git status --short`. Add TC-322-01..05 first (INV-RED-FIRST); confirm 01/02/03 red for the documented reasons and 04/05 green.
2. Thread `pendingReactionRepo` to the five sites. `ApplicationRoot` already holds `groupPendingReactionRepository` as a required non-nullable field (`application_root.dart:236,348`) and already uses it at `:1937`, so:
   - `handle_app_resumed.dart` — add a `GroupPendingReactionRepository?` parameter; pass at `:403` and `:482`.
   - `startup_router.dart` — add the field/parameter; pass at `:965`.
   - `prepare_notification_route_target_use_case.dart` — pass through the injected drain closure (`:58`).
   - `accept_pending_group_invite_use_case.dart` — pass at `:1230` from its existing caller wiring.
   - Update `application_root.dart` / `production_application_bootstrap.dart` call sites to supply it.
   Stop-if: any site cannot reach the repo without widening a public API beyond one nullable parameter → stop and replan the seam rather than constructing a second repository instance.
3. No harness registration needed — all four touched test files are already in `GROUP_TESTS` (`:526`, `:535`, `:569`, plus `:566`). Grep-verify anyway.
4. Run focused GREEN → sentinels → graph-affected → the `groups` lane.

## Risks And Blind Spots
- Threading a parameter through `startup_router.dart` touches a widely-constructed widget → guarded by TC-322-02 plus the existing startup-router suites in the `groups` lane.
- Lifecycle / derived-state durability: buffered rows are durable (SQLCipher-backed `GroupPendingReactionRepository`) and bounded by TTL + per-group cap → TC-322-06.
- Sibling-surface consistency: the census IS the fix → TC-322-02.
- Destructive-action side effects: none — the change only *adds* a durable write on a path that previously discarded. No deletion, no schema change.
- Invariant re-verification under new transitions: INV-R4 (buffer-then-replay) now applies on five previously-unbuffered lanes → TC-322-03.
- Construction/call-site census: `grep -rn 'drainGroupOfflineInbox' lib` → 8 production sites + 1 debug (`debug_e2e_composition_root.dart:1035`, reuses the retrier fn, no change) → covered by TC-322-02.
- Build-artifact provenance: N/A — no native artifact.
- Notification storm: N/A by construction — this plan emits no notifications (TC-322-04 locks it).

## Gate Cadence
- Per-plan closure: TC-322-01..05 focused + TC-322-06/07 sentinels + the `groups` curated lane. No `feature-host-all` — the changed files are group/app-lifecycle wiring already covered by `groups`.
- Graph-affected first: after the production edits and BEFORE the lane, run `tdd_context.py affected …` and execute the test files it names directly.
- Full `host-all` is **not** a per-plan gate. It is owned by the notification-reliability wave closure (after plan 323) and again at final rollout.
- Shared tests outside the feature/core globs: N/A — no `test/unit`, `test/integration`, `test/shared`, or `test/l10n` file is touched.

## Acceptance Gates  (literal — copy/paste)
```bash
git status --short

# Causal RED (before production edits) — must FAIL for the documented reason
flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart \
  --plain-name 'D4-322 resume-wired drain buffers a target-absent reaction'

# Focused GREEN (after the fix) — exit 0, zero failures
flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart

# Preservation sentinels — exit 0
flutter test test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart
flutter test test/features/groups/integration/group_reaction_notification_pipeline_test.dart

# Graph-affected dependents BEFORE the lane
python3 graphify-arch/tdd_context.py affected \
  lib/app/lifecycle/handle_app_resumed.dart \
  lib/features/identity/presentation/startup_router.dart \
  lib/features/push/application/prepare_notification_route_target_use_case.dart \
  lib/features/groups/application/accept_pending_group_invite_use_case.dart \
  lib/app/application_root.dart --budget 600

# Curated lane — exit 0
./scripts/run_test_gates.sh groups

# Registration is grep-verified, never run-verified
grep -c 'test/features/groups/application/drain_group_offline_inbox_use_case_test.dart' scripts/run_test_gates.sh   # expect: 1
grep -c 'test/features/groups/integration/group_reaction_notification_pipeline_test.dart' scripts/run_test_gates.sh # expect: 1
./scripts/run_test_gates.sh completeness-check   # expect: PASS, 0 unmatched

# Hygiene
flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria
- Expected RED: TC-322-01/02/03 fail on HEAD — 01 because the reaction is dropped (`GROUP_REACTION_RECEIVE_UNKNOWN_MESSAGE`, zero buffered rows), 02 because 5 of 8 sites omit the argument, 03 because nothing was buffered to flush.
- GREEN sentinel: TC-322-04 (no drain notification), TC-322-05 (`senderPublicKey` still binds), TC-322-06/07.
- Pre-existing dirty tree / known failure: three user-owned files (`docker/claude-code/Dockerfile`, `scripts/run_claude_docker.sh`, `scripts/test/run_claude_docker_update_contract_test.sh`) — never staged.
- Environment blocker (NOT a product blocker): none — host-only closure.
- Scope drift (BLOCKING): any notification emitted from the drain; any change to `handle_incoming_group_reaction_use_case.dart` behavior; any relay change.

- [ ] Every behavior has a named test or a justified proof.
- [ ] Causal RED, focused GREEN, and representative mutation re-red are recorded.
- [ ] Preservation sentinels and named gates pass with semantic outcomes.
- [ ] Harness registration is implemented AND verified.
- [ ] Conditional migration / device / relay proof passes when applicable — N/A.
- [ ] `flutter analyze` has no new issues; `git diff --check` is clean.
- [ ] The Scope Contract And Guard is respected.

## Handoff
- First causal RED command: `flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'D4-322 resume-wired drain buffers a target-absent reaction'`.
- Preservation command: `flutter test test/features/groups/integration/group_reaction_notification_pipeline_test.dart`.
- Manual registration: none — all touched test files already in `GROUP_TESTS`.
- Migration: none.
- Boundary closure: host-only. No device leg — this plan emits nothing at the OS boundary.
- Unresolved evidence: none.

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | awaiting accepted plan | contract extraction |

## Reviewer Findings (2026-08-02, `wf_d8df3c95-e44`)
**Verdict: plan-fixes-required · disposition: apply-plan-fixes.** Core defect CONFIRMED; the fix's blast radius was understated.

1. **BLOCKER — site 8 (accept-invite) is not "one nullable parameter".** `accept_pending_group_invite_use_case.dart:1230` sits behind 6 private functions (`:1217`, `:1256`, `:823`, `:614`, `:129`, `:52`) and then 4 widget public APIs — `OrbitWired` (`orbit_wired.dart:1848`; built at `application_root.dart:1270` and `feed_wired.dart:2597`) → `FeedWired` (3 sites) → `FirstTimeExperienceWired`, `QrScannerWired`. The analogous `groupReactionReplayOutboxRepository` threading spans 10 lib files. The plan's own Stop-if fires. **Delta: drop site 8 from this plan** (own plan, or replace with a post-accept trigger of `_flushStartupDurablePendingReactions`, already wired at `group_message_listener.dart:468-472`).
2. **BLOCKER — missing call site.** `_buildRestartedStartupRouter` (`startup_router.dart:1365-1433`) hand-forwards 60+ fields; omitting the new one silently nulls the repo on the account-migration restart path, and an optional param keeps `flutter analyze` silent. Add it to the site list explicitly.
3. **PLAN-FIX — a buffer throw now aborts the whole group drain.** `processDecodedPayload` is called OUTSIDE the decode try/catch (`drain_…:942`, `:969`; the catch at `:938` wraps only `_decodeActiveGroupInboxMessage`). A throw reaches `drainNextGroup`'s catch at `:154` → `errorCount++` → `isSuccessful == false` → `callGroupAcknowledgeRecovery` skipped (`handle_app_resumed.dart:449-470`) and the cursor advance at `:974+` is missed. `dbUpsertGroupPendingReaction` is a non-transactional read-then-insert with `ConflictAlgorithm.abort` (`group_parent_write_guard.dart:41,57`), so two concurrent drains of one group collide on UNIQUE — newly reachable because this plan wires the unawaited resume continuation and the notif-tap drain, neither covered by the retrier's `_isExternalRecoveryInProgressFn` guard. **Delta: try/catch the reaction branch at `:658-674`, or use `ConflictAlgorithm.replace`; add a TC that a throwing repo does not raise `errorCount`.**
4. **BLOCKER — TC-322-06 cites tests that do not exist.** No cap/TTL tests exist in `handle_incoming_group_reaction_use_case_test.dart`. Cap is per-group (50 × groupCount, unbounded in group count); the TTL delete is unindexed for a bare `received_at <` predicate (only `(group_id, received_at)` exists, `migrations/081…:28-31`) so every buffer write full-scans. Rewrite the row against real tests or write them.
5. **PLAN-FIX — TC-322-02 as specified is not a unit test.** Use the established source-census shape: `group_media_reliability_wiring_test.dart` `_balancedInvocations` / `_compactDart` (`:186-200`), already `GROUP_TESTS`-registered.
6. **Recorded, not fixed:** `received_at` is refreshed on every re-buffer (`group_pending_reactions_db_helpers.dart:52`), and eviction keeps the newest (`ORDER BY received_at DESC … OFFSET`, `:114-127`), so a repeatedly re-drained reaction never TTLs while once-seen newer rows evict first. Pre-existing; amplified by this plan.
7. **CLEAR:** PK dedupe across lanes (deterministic reaction id, `migrations/081…:9`); ADD/REMOVE distinct ids with an LWW comparand (`handle_incoming_group_reaction_use_case.dart:240-266`); left-group rows blocked on write and hidden on read (`group_parent_write_guard.dart:37-68`, `:134-145`); deleted-target discarded before buffering (`:162-177`).
