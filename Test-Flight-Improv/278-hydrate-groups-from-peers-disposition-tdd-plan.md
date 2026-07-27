# 278 - `hydrateGroupsFromPeers` Evidence-Led Removal

Status: Plan-green / implementation-complete (2026-07-26)
Type: Modification
Spec: free-text DTR-10 disposition — verify production topic rejoin/inbox recovery sufficiency; remove the dormant wrapper only if that evidence is sufficient, otherwise require a separately authorized wiring plan
Classification: implementation-complete
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-26 | Evidence Collector | dormant hydrate source/tests, startup router, resume lifecycle, pending retrier wiring, rejoin and drain primitives/tests | Confirmed the wrapper has no `lib/` caller and only composes already-live primitives over already-local groups | Challenge whether it supplies any missing peer-state behavior |
| 2026-07-26 | Independent Refute Pass | restored-device announce/admission/key-distribution sources; exact hydrate implementation | Refuted “hydrate pulls group state from peers”: it fetches no remote roster/config/key and cannot materialize a missing local group | Compare its actual behavior with production recovery |
| 2026-07-26 | Baseline Verifier | hydrate suite; cold-start, resume, rejoin-outcome, batch-drain, and self-removed lifecycle selectors | All focused selectors passed. Production cold start and resume perform real rejoin then richer inbox drain; the dormant wrapper adds no unique recovery mechanism | Plan exact leaf/test cleanup |
| 2026-07-26 | Planner / Sufficiency Check | TDD tier/template/checklist, runtime-root manifest, group gate | Evidence is sufficient for removal of the duplicate wrapper. No production wiring is authorized or needed for its actual behavior | Ready for optional independent review, then execution |

## Authorization Receipt

- Receipt: `DTR10-AUTH-02`.
- Authority/date: current authenticated project owner, 2026-07-26.
- Authorized decision: verify whether live recovery already performs the
  wrapper's real reconnection/inbox contract; remove the wrapper only if it
  does, otherwise stop and require a separate wiring plan.
- Guard: this receipt does not authorize claiming or implementing fresh-device
  group/member/config/key acquisition. The evidence below is sufficient only
  for already-local groups with usable key material.

## Problem And Evidence

- Behavior to improve: retire the unused `hydrateGroupsFromPeers` composition
  after proving that real production recovery already rejoins stored group
  topics and drains their relay inboxes.
- Impact: wiring this wrapper would create a second recovery orchestration with
  fewer dependencies and weaker recovery semantics than the current cold-start,
  resume, and retrier paths. Retaining it makes a local rejoin/drain wrapper look
  like peer-state hydration even though it does not fetch peer state.
- Confirmed dormant shape:
  `hydrateGroupsFromPeers` at
  `lib/features/groups/application/hydrate_groups_from_peers_use_case.dart:27-104`
  calls `rejoinGroupTopics` at `:49-54`, enumerates already-local groups at
  `:57`, and calls `drainGroupOfflineInboxForGroup` at `:71-79`. It has no
  production importer/caller.
- Confirmed test-only consumers: three calls in
  `hydrate_groups_from_peers_use_case_test.dart:44-83` and one preservation
  call in `self_removed_group_lifecycle_guard_test.dart:274-283`.
- Confirmed production replacement:
  - cold startup calls `rejoinGroupTopics` and then the richer batch
    `drainGroupOfflineInbox` with listener, media, reaction, key-repair,
    history-gap, and identity dependencies at
    `startup_router.dart:760-805`;
  - resume calls rejoin, dissolve reconciliation, a bounded first-page batch
    drain, recovery acknowledgement, and cursor-backed continuation at
    `handle_app_resumed.dart:345-494`;
  - the pending retrier receives live rejoin and batch-drain callbacks at
    `main.dart:4486-4546`;
  - the primitives themselves cover full-config topic resubscription
    (`rejoin_group_topics_use_case.dart:90-105,208-219`) and cursor-paginated
    all-group drain (`drain_group_offline_inbox_use_case.dart:72-208`).
- Planning baseline evidence passed:
  - all three dormant wrapper tests;
  - `startup_router_recovery_test.dart::PB264-18 cold startup recovers exits
    after rejoin and inbox drain without resume`;
  - `handle_app_resumed_group_recovery_test.dart::NW-004 relay reconnect resume
    rejoins all groups drains replay then acknowledges recovery`;
  - `rejoin_group_topics_use_case_test.dart::PB264-11 every visited rejoin
    outcome advances durable exit work but only joined drains`;
  - `drain_group_offline_inbox_use_case_test.dart::resume drains group inbox for
    every joined group`;
  - the existing marked-shell lifecycle selector.
- Confirmed conclusion: production recovery is sufficient for the dormant
  wrapper's actual contract—rejoin and inbox drain for groups already present
  locally with usable key material. The live paths are richer and more
  completely tested.
- Confirmed support boundary: `kMultiDeviceSyncEnabled` remains default-off,
  `group_multi_device_policy.dart` reports membership/metadata/history
  convergence unimplemented in the default build, and
  `mnemonic_input_wired.dart` tells a fresh restore with zero local groups that
  groups remain device-local. This is positive evidence that fresh-device state
  acquisition is still missing, not evidence that startup/rejoin supplies it.
- Missing coverage: no causal test currently requires the duplicate wrapper,
  dedicated suite, manifest record, and remaining test-only call/import to be
  absent while preserving direct live primitives. TC-HYDRATE-01 supplies it.
- Refuted findings:
  - “Connect the existing hydrate tests to production” is refuted for this
    contract: production already invokes the underlying real primitives, and
    wiring the wrapper would duplicate startup/resume work.
  - “The wrapper recovers a fresh device with no group rows or keys” is refuted:
    it reads only `groupRepo.getAllGroups()` and existing keys through rejoin;
    it has no peer-pull/materialization protocol.
- Unresolved findings: whether a freshly restored device that lacks local
  group/member/key state needs a new remote state-acquisition feature is not
  proven here. That question does not block this deletion because the dormant
  wrapper cannot provide that behavior. If Product/Groups wants it, create a
  new top-level, separately authorized TDD plan; Plan 278 is not wiring
  authority.
- Affected production, test, and bookkeeping files:
  `hydrate_groups_from_peers_use_case.dart`,
  `hydrate_groups_from_peers_use_case_test.dart`,
  `self_removed_group_lifecycle_guard_test.dart`,
  `hydrate_groups_from_peers_removal_contract_test.dart` (new),
  `group_multi_device_policy_contract_test.dart`,
  `tool/runtime_roots/runtime_roots.json`, the DTR roadmap, and `00-INDEX.md`.

## Graph Grounding Snapshot

- Graph fingerprint / freshness:
  `b04644b8f017826a`; `freshness=current` at the independent review.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "Verify GroupRepositoryImpl.hydrateGroupsFromPeers production recovery topic reconnection and group inbox drain sufficiency, or identify production wiring gap" --profile tdd --budget 700`
  returned `confidence=broad`; the single allowed refinement
  `python3 graphify-arch/tdd_context.py query "hydrateGroupsFromPeers group_repository_impl.dart group recovery inbox topic" --profile tdd --budget 700`
  returned `confidence=anchored`.
- Independent review query / profile:
  `python3 graphify-arch/tdd_context.py query "counterexample audit hydrateGroupsFromPeers hydrate_groups_from_peers_use_case.dart actual contract missing local group fresh-device acquisition startup resume rejoin inbox recovery" --profile review --budget 800`
  returned `confidence=anchored` with the same current fingerprint.
- Anchors:
  `hydrateGroupsFromPeers` ->
  `lib/features/groups/application/hydrate_groups_from_peers_use_case.dart:27`;
  repository anchor ->
  `lib/features/groups/domain/repositories/group_repository_impl.dart`.
- Surfaced proof/gate files:
  `group_repository_impl_test.dart`,
  `hydrate_groups_from_peers_use_case_test.dart`, group repository/listener
  production files.
- Graph gaps requiring source search: exact production/caller census; cold
  startup, resume, retrier, restore admission, direct rejoin/drain tests, and
  gate registration.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Delete only the dormant hydrate source and its dedicated three-test suite.
- Remove its import and single call from the broader self-removed lifecycle
  sentinel while keeping that test's direct `rejoinGroupTopics` and
  `drainGroupOfflineInboxForGroup` assertions.
- Rename that sentinel to remove the stale word `hydrate`.
- Remove only the matching runtime-root declaration; add the causal removal
  contract, make the existing default-off policy sentinel unconditional, and
  update current DTR/index bookkeeping.

Must preserve:

- Cold-start rejoin-before-inbox-drain and exit recovery ->
  `PB264-18 cold startup recovers exits after rejoin and inbox drain without
  resume`.
- Resume rejoin/drain/ack ordering, full config, latest key epochs, and
  no-ack-on-drain-failure ->
  `NW-004 relay reconnect resume rejoins all groups drains replay then
  acknowledges recovery`.
- Exit-in-progress, dissolved, self-removed, no-key, deferred, and error
  outcomes -> `PB264-11 every visited rejoin outcome advances durable exit work
  but only joined drains`.
- All-group real inbox application -> `resume drains group inbox for every
  joined group`.
- Cursor-complete recovery and the online retrier ->
  `Phase 2: first-page drain reports hasMorePages and a continuation drains the
  remaining pages from the persisted cursor (no page-1 re-process)` and
  `NW-004 reconnect recovery sweep rejoins drains and acks before retries`.
- Marked-shell lifecycle exclusion -> the renamed direct rejoin/drain/announce/
  dissolve/pending-send sentinel.
- Fresh-device honesty -> `GUARD: with the flag off, NO convergence facet may
  claim implemented` and
  `shows the honest notice when restore hydrates zero groups`.

Hard `Do not`:

- Do not wire `hydrateGroupsFromPeers` into startup, resume, pending retrier,
  restored-device admission, key listener, or UI.
- Do not change `rejoinGroupTopics`, `drainGroupOfflineInbox`,
  `drainGroupOfflineInboxForGroup`, recovery acknowledgement, cursors, relay
  commands, group/member/key persistence, multi-device flags, native/Go code,
  or schemas.
- Do not claim that this plan proves or implements missing-group peer-state
  acquisition.
- Do not enable `kMultiDeviceSyncEnabled`, mark a convergence facet
  implemented, or remove the zero-group restore notice.
- Do not delete the broader self-removed lifecycle test or weaken its direct
  rejoin/drain/announce/dissolve/pending-work assertions.

Deferred / accepted difference:

- Fresh-device acquisition of group/member/config/key state when no usable
  local row exists -> owner Product + Groups + security, through a new
  separately authorized TDD plan if requested. It needs a real state-source,
  trust, persistence, replay/rollback, and availability-bounded device proof;
  simply wiring this wrapper is prohibited.
- The wrapper-only `GROUP_HYDRATE_FROM_PEERS_*` diagnostic events and returned
  count disappear. No production observer exists because there is no production
  caller.

Rollback:

- Restore only the deleted wrapper, its dedicated suite, its runtime-root row,
  and the broader sentinel import/call if this removal must be reverted.
- Do not roll back or alter live startup, resume, retrier, rejoin, drain,
  acknowledgement, cursor, group/member/key, native, or wire behavior.

Dependencies:

- `DTR10-AUTH-02`: the user's current instruction authorizes evidence-led
  disposition and removal only when replacement sufficiency is proven.
  Source/test evidence above satisfies that condition. The receipt does not
  authorize production wiring or the deferred fresh-device feature.
- DTR-03's retained live full-config/rejoin floor and all current recovery
  contracts remain prerequisites.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-HYDRATE-01 | The dormant hydrate source, dedicated suite, runtime-root row, and broader-test import/call are absent; the lifecycle selector is renamed and named live rejoin/drain source/test files remain. | `test/features/groups/application/hydrate_groups_from_peers_removal_contract_test.dart::DTR10-HYDRATE-01 duplicate hydrate wrapper and bookkeeping are absent` | Host source/API contract / real repository tree | Scaffolded causal RED: HEAD contains the source, suite, manifest row, import, call, and stale selector name -> GREEN after exact removal while required live source/test files remain. | Restore the file/manifest/import/call through a package or relative URI, restore the stale selector name, or remove a named live source/test file -> TC-HYDRATE-01 red. | `flutter test --no-pub test/features/groups/application/hydrate_groups_from_peers_removal_contract_test.dart --plain-name 'DTR10-HYDRATE-01 duplicate hydrate wrapper and bookkeeping are absent'`; AUTO (`test/features/**`) for `feature-host-all`. |
| TC-HYDRATE-02 | Exact current-source evidence shows no production caller/export; test-only calls are fully enumerated before deletion and zero afterward. | `DTR10-HYDRATE-CALLER-01` fail-closed census in Acceptance Gates | Host source evidence / all owned Dart roots, including `scripts`, plus root Dart files | HEAD evidence: one declaration, three dedicated-suite calls, one broader sentinel call, zero production/other callers -> GREEN final census: zero symbol/import. | Add a production call, tear-off, import, or export in any owned Dart root -> census fails and execution stops. | Literal `rg`/count commands below; MANUAL source registration, followed by TC-HYDRATE-01 and `runtime-roots`. |
| TC-HYDRATE-03 | Cold startup performs full-config group topic rejoin before real batch inbox drain and still advances exit recovery. | `test/features/identity/presentation/screens/startup_router_recovery_test.dart::PB264-18 cold startup recovers exits after rejoin and inbox drain without resume` | Widget/application host / repository, P2P, and bridge fakes | GREEN sentinel on HEAD -> `group:join` precedes cursor inbox retrieval and startup exit recovery remains isolated after deletion. | Remove/reorder startup rejoin or batch drain -> selector red. | Exact command below; suite is in `BASELINE_TESTS` and AUTO feature-host. |
| TC-HYDRATE-04 | Resume recovery rejoins every stored keyed group with latest config/key epoch, drains replay, acknowledges only after success, and withholds acknowledgement on drain failure. | `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart::NW-004 relay reconnect resume rejoins all groups drains replay then acknowledges recovery` | Core/application host integration / P2P, repository, and bridge fakes | GREEN sentinel on HEAD -> full ordered success/failure contract stays green after deletion. | Skip one group, use stale config/key, acknowledge early, or acknowledge after failed drain -> selector red. | Exact direct command below; explicitly in `GROUP_TESTS` and AUTO core-host. |
| TC-HYDRATE-05 | The live rejoin primitive processes every exit/lifecycle outcome but joins/drains only eligible groups. | `test/features/groups/application/rejoin_group_topics_use_case_test.dart::PB264-11 every visited rejoin outcome advances durable exit work but only joined drains` | Application host / repository and selective bridge fakes | GREEN sentinel on HEAD -> joined/exit/dissolved/self-removed/no-key/deferred/error outcome map and drain discriminator remain green. | Rejoin or broadcast-drain an ineligible group, or stop processing its durable exit work -> selector red. | Exact direct command below; explicitly in `GROUP_TESTS` and AUTO feature-host. |
| TC-HYDRATE-06 | Live batch inbox recovery applies every local group's messages, drains cursor pages without replaying page 1, and the online retrier runs rejoin then drain before acknowledgement/retries. | `drain_group_offline_inbox_use_case_test.dart::{resume drains group inbox for every joined group, Phase 2: first-page drain reports hasMorePages and a continuation drains the remaining pages from the persisted cursor (no page-1 re-process)}`; `test/core/services/pending_message_retrier_test.dart::{NW-004 reconnect recovery sweep rejoins drains and acks before retries, NW-004 reconnect recovery sweep does not acknowledge failed drain}` | Application/core host / repositories, cursor bridge, and retrier fakes | GREEN sentinels on HEAD -> all local groups/pages persist exactly once and retrier ordering/failure refusal remain green after wrapper deletion. | Drain only one group/page, restart at page 1, acknowledge a failed drain, or retry before recovery -> a named selector red. | Exact direct commands below; drain suite is in `GROUP_TESTS`/AUTO feature; retrier suite is AUTO core and run directly. |
| TC-HYDRATE-07 | Marked self-removed shells still perform zero topic join, inbox retrieval, announce, dissolve reconciliation, or pending send after the hydrate-specific call is removed. | `test/features/groups/application/self_removed_group_lifecycle_guard_test.dart::marked shells and loaded membership work perform zero join inbox announce dissolve or pending sends` | Application host / lifecycle lock, repositories, and bridge fakes | HEAD predecessor selector is GREEN and includes a redundant hydrate call -> GREEN renamed selector preserves direct rejoin/drain and all other lifecycle leaves without importing/calling the deleted wrapper. | Remove a lifecycle guard from direct rejoin/drain/announce/dissolve/pending work -> selector red. | Exact post-edit command below; explicitly in `GROUP_TESTS` and AUTO feature-host. |
| TC-HYDRATE-08 | Runtime-root inventory matches the final tree and the new causal test is discoverable. | `test/unit/runtime_root_inventory_test.dart::repository manifest accounts for current non-main sources and keeps known candidates advisory`; `feature-host-all --list` discovery | Tool/unit host + real Git-visible tree | Causal inventory RED after the manifest expectation changes while source remains -> GREEN: no drift and new contract auto-discovered. | Restore the manifest/source or omit the new test from discovery -> inventory/discovery proof red. | Isolated-index `./scripts/run_test_gates.sh runtime-roots`; `./scripts/run_host_test_gates.sh feature-host-all --list`; `./scripts/run_test_gates.sh groups`. |
| TC-HYDRATE-09 | Removing the incapable wrapper does not silently claim fresh-device convergence: the feature flag remains default-off, shared facets remain unimplemented, and a zero-group restore keeps its honest notice. | `test/features/groups/domain/models/group_multi_device_policy_contract_test.dart::GUARD: with the flag off, NO convergence facet may claim implemented`; `test/features/identity/presentation/screens/mnemonic_input_wired_restore_notice_test.dart::shows the honest notice when restore hydrates zero groups` | Host domain/widget / compile-time default flag and empty group repository | GREEN sentinels on HEAD -> remain GREEN after deletion. | Enable the flag by default, mark convergence implemented, or suppress the empty-group notice -> a named selector red. | Two exact commands below; both AUTO under `test/features/**` for `feature-host-all` and run directly for this plan. |

### Test Notes

- TC-HYDRATE-01 constructs the retired filename and camel-case identifier from
  fragments so the contract is not counted as a caller. Its basename census
  catches both package and relative import/export URIs, and it locks the
  renamed lifecycle selector so the focused preservation command cannot drift.
- TC-HYDRATE-03/04 are the production wiring proof. TC-HYDRATE-05/06 prove the
  underlying decisions and inbox application. Together they are stronger than
  the deleted wrapper test, whose “drain” assertion only checks a non-empty
  bridge command log.
- TC-HYDRATE-07 keeps the direct primitive calls as the meaningful lifecycle
  preservation proof; only the redundant wrapper import/call is removed.
- Production-critical device/relay leg: N/A for deletion. No live transport,
  wire, crypto, cursor, or production orchestration code changes. A future
  missing-state acquisition feature would require its own real boundary proof.

## Implementation Steps

1. Snapshot `git rev-parse HEAD`, `git status --short`, and the current index.
   Require the removal/test-bookkeeping paths and all TC-HYDRATE-03 through
   TC-HYDRATE-07 preservation paths to have a trustworthy baseline.
2. Run and record `DTR10-HYDRATE-CALLER-01`. Stop if the exact shape is not one
   declaration, three dedicated-suite calls, one broader sentinel call, and
   zero production/other calls or imports.
3. Add TC-HYDRATE-01 first and run its causal RED. It must fail only because
   the exact dormant artifacts still exist.
4. Delete the hydrate source and dedicated suite. Remove only its manifest row.
   Remove its import and call from the broader lifecycle test, rename that test
   without `hydrate`, and keep its direct rejoin/drain/announce/dissolve/pending
   leaves unchanged.
5. Make the existing TC-HYDRATE-09 guard assert the default flag is off before
   checking every convergence facet, so enabling the flag cannot skip the
   contract.
6. Update current DTR-10 decision/compatibility/index bookkeeping: record the
   evidence-led removal, the already-live cold-start/resume/retrier mechanisms,
   the prohibition on wiring, rollback, and the separately authorized trigger
   for any future missing-state acquisition plan.
7. Run TC-HYDRATE-01 GREEN, final negative census, renamed lifecycle sentinel,
   cold-start/resume/rejoin/drain/retrier and fresh-device-honesty proofs,
   `runtime-roots`, `groups`, and the justified `feature-host-all` sweep.
8. Run strict analysis, completeness, incremental Graphify refresh, and diff
   hygiene. Stop-if any production recovery primitive or native/Go/schema/key
   behavior changed.

## Risks And Blind Spots

- A production caller missed by casual search -> TC-HYDRATE-02 fail-closed
  whole-owned-source census.
- Removing the wrapper could accidentally weaken marked-shell coverage ->
  TC-HYDRATE-07 preserves direct live leaves.
- A plan might mistake local catch-up for fresh-device peer-state acquisition
  -> explicit refutation, hard wiring prohibition, and separate-plan trigger.
- Cold-start and resume could look equivalent while differing in ack/paging ->
  TC-HYDRATE-03 and TC-HYDRATE-04 preserve both distinct orchestrations.
- Lifecycle / derived-state durability: cold-start/restart and persisted inbox
  cursor behavior are exercised by TC-HYDRATE-03/04/06.
- Sibling-surface consistency: startup, resume, and direct primitive seams have
  separate named sentinels rather than a proxy wrapper test.
- Destructive-action side effects: only two isolated files, one import/call,
  one test name, and one manifest row may change; direct recovery paths are
  preservation-only.
- Invariant re-verification under new transitions: N/A — no new transition is
  added.

## Gate Cadence

- Per-plan closure: causal removal contract, exact pre/final census, cold-start,
  resume, rejoin, cursor-complete drain, retrier, lifecycle, and fresh-device
  honesty sentinels, isolated `runtime-roots`, `groups`, and the justified
  `feature-host-all` sweep because an app-owned feature source/test island is
  removed and a curated group test is edited.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the DTR-10/Wave-3
  dependency batch is complete, and once at final DTR rollout/release closure.
- Shared tests outside feature/core globs: `runtime-roots` is run through its
  exact isolated-index command; no device or relay command applies.

## Acceptance Gates

Run from the repository root. Every non-RED command must exit `0` with zero
failed tests or new issues.

```bash
# Snapshot before execution; preserve unrelated work
git rev-parse HEAD
git status --short
git diff --cached --name-status

# Pre-edit DTR10-HYDRATE-CALLER-01; expect exact test-only shape
test "$(rg -o '\bhydrateGroupsFromPeers\b' \
  lib/features/groups/application/hydrate_groups_from_peers_use_case.dart |
  wc -l | tr -d ' ')" -eq 1
test "$(rg -o '\bhydrateGroupsFromPeers\b' \
  test/features/groups/application/hydrate_groups_from_peers_use_case_test.dart |
  wc -l | tr -d ' ')" -eq 3
test "$(rg -o '\bhydrateGroupsFromPeers\b' \
  test/features/groups/application/self_removed_group_lifecycle_guard_test.dart |
  wc -l | tr -d ' ')" -eq 1
if rg -n \
  --glob '*.dart' \
  --glob '!lib/features/groups/application/hydrate_groups_from_peers_use_case.dart' \
  --glob '!test/features/groups/application/hydrate_groups_from_peers_use_case_test.dart' \
  --glob '!test/features/groups/application/self_removed_group_lifecycle_guard_test.dart' \
  '\bhydrateGroupsFromPeers\b' \
  lib test integration_test test_driver scripts tool packages ./*.dart; then
  exit 1
else
  DTR10_HYDRATE_RG_STATUS=$?
  test "$DTR10_HYDRATE_RG_STATUS" -eq 1
fi
if rg -n --glob '*.dart' \
  --glob '!test/features/groups/application/hydrate_groups_from_peers_use_case_test.dart' \
  --glob '!test/features/groups/application/self_removed_group_lifecycle_guard_test.dart' \
  'hydrate_groups_from_peers_use_case\.dart' \
  lib test integration_test test_driver scripts tool packages ./*.dart; then
  exit 1
else
  DTR10_HYDRATE_IMPORT_STATUS=$?
  test "$DTR10_HYDRATE_IMPORT_STATUS" -eq 1
fi

# Causal RED after scaffolding TC-HYDRATE-01, before deletion:
# expect non-zero only because the dormant source/test/records remain
flutter test --no-pub \
  test/features/groups/application/hydrate_groups_from_peers_removal_contract_test.dart \
  --plain-name \
  'DTR10-HYDRATE-01 duplicate hydrate wrapper and bookkeeping are absent'

# Focused GREEN after exact removal/bookkeeping update
flutter test --no-pub \
  test/features/groups/application/hydrate_groups_from_peers_removal_contract_test.dart
test ! -e \
  lib/features/groups/application/hydrate_groups_from_peers_use_case.dart
test ! -e \
  test/features/groups/application/hydrate_groups_from_peers_use_case_test.dart
if rg -n --glob '*.dart' \
  '\bhydrateGroupsFromPeers\b|hydrate_groups_from_peers_use_case\.dart' \
  lib test integration_test test_driver scripts tool packages ./*.dart; then
  exit 1
else
  DTR10_HYDRATE_FINAL_STATUS=$?
  test "$DTR10_HYDRATE_FINAL_STATUS" -eq 1
fi

# Production cold-start and resume recovery preservation
flutter test --no-pub \
  test/features/identity/presentation/screens/startup_router_recovery_test.dart \
  --plain-name \
  'PB264-18 cold startup recovers exits after rejoin and inbox drain without resume'
flutter test --no-pub \
  test/core/lifecycle/handle_app_resumed_group_recovery_test.dart \
  --plain-name \
  'NW-004 relay reconnect resume rejoins all groups drains replay then acknowledges recovery'

# Direct live primitive and lifecycle preservation
flutter test --no-pub \
  test/features/groups/application/rejoin_group_topics_use_case_test.dart \
  --plain-name \
  'PB264-11 every visited rejoin outcome advances durable exit work but only joined drains'
flutter test --no-pub \
  test/features/groups/application/drain_group_offline_inbox_use_case_test.dart \
  --plain-name 'resume drains group inbox for every joined group'
flutter test --no-pub \
  test/features/groups/application/drain_group_offline_inbox_use_case_test.dart \
  --plain-name \
  'Phase 2: first-page drain reports hasMorePages and a continuation drains the remaining pages from the persisted cursor (no page-1 re-process)'
flutter test --no-pub test/core/services/pending_message_retrier_test.dart \
  --plain-name 'NW-004 reconnect recovery sweep rejoins drains and acks before retries'
flutter test --no-pub test/core/services/pending_message_retrier_test.dart \
  --plain-name \
  'NW-004 reconnect recovery sweep does not acknowledge failed drain'
flutter test --no-pub \
  test/features/groups/application/self_removed_group_lifecycle_guard_test.dart \
  --plain-name \
  'marked shells and loaded membership work perform zero join inbox announce dissolve or pending sends'

# Fresh-device convergence stays explicitly unsupported in the default build.
flutter test --no-pub \
  test/features/groups/domain/models/group_multi_device_policy_contract_test.dart \
  --plain-name \
  'GUARD: with the flag off, NO convergence facet may claim implemented'
flutter test --no-pub \
  test/features/identity/presentation/screens/mnemonic_input_wired_restore_notice_test.dart \
  --plain-name 'shows the honest notice when restore hydrates zero groups'

# Protected production recovery paths must be byte-for-byte unchanged
git diff HEAD --quiet -- \
  lib/features/identity/presentation/startup_router.dart \
  lib/core/lifecycle/handle_app_resumed.dart \
  lib/main.dart \
  lib/features/groups/application/rejoin_group_topics_use_case.dart \
  lib/features/groups/application/drain_group_offline_inbox_use_case.dart \
  lib/features/groups/application/announce_restored_device_use_case.dart \
  lib/features/groups/application/admit_sibling_device_use_case.dart \
  lib/features/groups/application/group_key_update_listener.dart \
  lib/core/config/multi_device_sync_flag.dart \
  lib/features/groups/domain/models/group_multi_device_policy.dart \
  lib/features/identity/presentation/screens/mnemonic_input_wired.dart

# Real final-tree runtime-root gate without touching the user's real index.
# HEAD predates the already Plan-green Plan 277 work, while the shared manifest
# contains both removals, so stage that exact accepted predecessor slice too.
DTR10_HYDRATE_INDEX_DIR="$(
  mktemp -d "${TMPDIR:-/tmp}/dtr10-hydrate-index.XXXXXX"
)"
trap 'rm -rf -- "${DTR10_HYDRATE_INDEX_DIR:?}"' EXIT
GIT_INDEX_FILE="$DTR10_HYDRATE_INDEX_DIR/index" git read-tree HEAD
GIT_INDEX_FILE="$DTR10_HYDRATE_INDEX_DIR/index" git add -A -- \
  lib/features/groups/application/join_group_use_case.dart \
  lib/features/groups/domain/repositories/group_repository.dart \
  lib/features/groups/domain/repositories/group_repository_impl.dart \
  test/features/groups/application/join_group_use_case_test.dart \
  test/features/groups/application/old_join_group_removal_contract_test.dart \
  test/features/groups/application/delete_self_removed_group_shell_use_case_test.dart \
  test/features/groups/domain/repositories/group_repository_impl_test.dart \
  test/shared/fakes/in_memory_group_repository.dart \
  scripts/run_test_gates.sh \
  lib/features/groups/application/hydrate_groups_from_peers_use_case.dart \
  test/features/groups/application/hydrate_groups_from_peers_use_case_test.dart \
  test/features/groups/application/self_removed_group_lifecycle_guard_test.dart \
  test/features/groups/application/hydrate_groups_from_peers_removal_contract_test.dart \
  test/features/groups/domain/models/group_multi_device_policy_contract_test.dart \
  tool/runtime_roots/runtime_roots.json
GIT_INDEX_FILE="$DTR10_HYDRATE_INDEX_DIR/index" \
  ./scripts/run_test_gates.sh runtime-roots

# Discovery, affected curated lane, and justified feature sweep
./scripts/run_host_test_gates.sh feature-host-all --list |
  rg -nF \
  'test/features/groups/application/hydrate_groups_from_peers_removal_contract_test.dart'
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh feature-host-all \
  --continue-on-failure \
  --batch-flutter \
  --concurrency 1 \
  --reporter failures-only

# Hygiene and graph refresh
./scripts/check_flutter_analyze_strict.sh
./scripts/run_test_gates.sh completeness-check
./graphify-arch/refresh_arch_graph.sh --incremental
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-HYDRATE-01 exits non-zero only because the exact dormant
  source/test/import/call/manifest artifacts remain.
- Green sentinels: TC-HYDRATE-03 through TC-HYDRATE-07 preserve the real
  cold-start, resume, rejoin, drain, and lifecycle behavior.
- Pre-existing dirty tree / known failure: snapshot and preserve it. Any dirty
  protected production-recovery file must be baselined or treated as scope
  drift, not silently absorbed.
- Concurrent unrelated Plan 280/285/286 edits invalidated the first shared-tree
  `feature-host-all` batch. That red result is not counted: the exact gate was
  rerun against a detached `HEAD + Plan 278 only` worktree, with the repository's
  ignored local iOS Firebase fixture attached, and passed 821 paths with zero
  failures.
- Environment blocker: none; this is host-only removal with no real relay,
  crypto, SQLCipher, simulator, or device claim.
- Scope drift: any production caller, recovery-path edit, schema/key/wire
  change, or sentinel failure blocks completion.

- [x] Every behavior has a named test or justified proof.
- [x] Causal RED, focused GREEN, and representative restore/import mutation
      re-red are recorded.
- [x] Cold-start, resume, primitive, lifecycle, and named gates pass.
- [x] AUTO registration and final runtime-root inventory are verified.
- [x] `flutter analyze` strict wrapper has no new issues; `git diff --check` is
      clean.
- [x] Scope Contract And Guard is respected.

## Handoff

- First causal RED command:
  `flutter test --no-pub test/features/groups/application/hydrate_groups_from_peers_removal_contract_test.dart --plain-name 'DTR10-HYDRATE-01 duplicate hydrate wrapper and bookkeeping are absent'`.
- Preservation command:
  `flutter test --no-pub test/features/identity/presentation/screens/startup_router_recovery_test.dart --plain-name 'PB264-18 cold startup recovers exits after rejoin and inbox drain without resume'`.
- Manual registration: new removal contract is AUTO feature-host; the edited
  lifecycle suite remains explicitly in `GROUP_TESTS`. Caller census and
  isolated-index `runtime-roots` are manual exact proofs.
- Migration: none.
- Boundary closure: host-only; no production relay/native/crypto/wire behavior
  changes.
- Unresolved evidence: fresh-device acquisition of missing group/member/key
  state is outside this wrapper's capability and outside this plan. A future
  wiring/state-acquisition plan needs new explicit authorization and a new
  top-level number.

## Reviewer Findings

- `$tdd-review` verdict: `ready`; classification `implementation-ready`; core
  bet confirmed; disposition `execute`. The fresh audit first found bounded
  gate and causal-test defects and tightened them in place before restoring
  this verdict.
- Five lenses: evidence truth, Test Contract causality, bypass/scope safety,
  and gate integrity are clear; production boundary/reversibility is N/A
  except for the explicit independent rollback boundary above.
- Blind-spot sweep: B-2/B-3/B-4/B-9 are covered by the fail-closed census,
  causal removal test, focused preservation sentinels, and fresh-device
  honesty tests. B-1/B-5/B-6/B-8/B-10 are N/A because no persisted data,
  schema, wire, native, crypto, platform, or cross-device behavior changes.
- Verdict remains sufficient and execution-ready for removal of the wrapper's
  actual already-local-group contract under `DTR10-AUTH-02`.
- Counterexample census confirmed one declaration, three dedicated-suite calls,
  one broader test call, and no production caller/export. Source inspection
  confirmed the wrapper cannot acquire a missing group, roster, config, or key.
- Material fix: added cursor-complete drain and pending-retrier ordering/failure
  sentinels so “rejoin plus inbox recovery elsewhere” is not inferred from a
  one-page proxy.
- Material fix: added default-off policy and zero-group restore-notice
  sentinels. Fresh-device convergence remains confirmed missing and requires a
  separately authorized plan before the flag or product claim can change.
- Material fix: the isolated `runtime-roots` gate now stages the exact
  Plan-green Plan 277 predecessor slice. Reconstructing only Plan 278 on `HEAD`
  was proven to fail on the phantom tracked
  `join_group_use_case.dart`; the revised literal command passes 16/16.
- Material fix: TC-HYDRATE-01 now rejects package and relative import/export
  residue and locks the renamed lifecycle selector, closing the smallest
  source-census and selector-drift counterexamples.
- Material fix: the owned-Dart census now includes `scripts/test`, and the
  default-off policy guard asserts the flag state unconditionally instead of
  silently doing no work when the flag is enabled.
- Review wording fix: TC-HYDRATE-01 claims file-presence mutations only;
  TC-HYDRATE-03 through TC-HYDRATE-07 remain the semantic live-symbol proof.
- No status, closure-tier, or cadence change is required.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-26 | independent review and plan repair | Plan 278; dormant wrapper; recovery callers/tests; removal contract; gate scripts | `$tdd-review` confirmed the core deletion bet and first returned bounded plan fixes: the original isolated runtime-root reconstruction failed on Plan 277's unstaged predecessor, TC-HYDRATE-01 under-counted relative/script residue and overstated its semantic mutation, and TC-HYDRATE-09 skipped itself when the flag was enabled | One declaration, three dedicated-suite calls, one broader test call, two test imports, and zero production caller/export; wrapper reads only local groups and cannot acquire missing group/member/config/key state | All source-backed deltas applied; verdict `ready`, disposition `execute`; no user or device blocker | Execute exact removal |
| 2026-07-26 | causal implementation | Deleted hydrate source/suite; lifecycle sentinel; new removal contract; policy guard; runtime-root/DTR bookkeeping | Detached `HEAD + contract` TC-HYDRATE-01 RED on the present source; final-tree TC-HYDRATE-01 GREEN; flag-on dart-define mutation re-red; final owned-Dart census exited 0 | Package/relative imports, scripts, and root Dart files are covered; lifecycle selector is locked; default build must remain flag-off; protected production recovery/native/schema/key paths have zero diff in the detached Plan-278 snapshot | Exact 195-line dormant source/test island retired; scope contract held | Run preservation and closure gates |
| 2026-07-26 | preservation and closure | TC-HYDRATE-03 through TC-HYDRATE-09 surfaces; runtime roots; groups/feature families; analysis; Graphify | All focused selectors GREEN; isolated `runtime-roots` 16/16; `groups` Flutter `+3297` plus four Go package legs; exact isolated `feature-host-all` 821 paths, `+8548 ~1`, zero failures; strict analysis 0 issues; completeness 1354/1354; incremental graph 62,599 nodes / 94,442 edges; final detached Plan-278 diff/scope checks clean | Cold-start, resume, rejoin outcomes, cursor continuation, retrier ordering/failure refusal, marked-shell exclusion, and fresh-device honesty preserved. The first shared-tree feature batch was discarded after concurrent Plan 280/285/286 edits; its unrelated failures did not reproduce in the detached Plan-278-only retry | `Plan-green`; aggregate `host-all` remains owned by Wave 3 and final rollout, not this plan | Keep future missing-state acquisition under separate authorization |

Post-closure Graphify caveat (2026-07-26): current source, manifest, and
runtime-root inventory contain no retired hydrate source/suite, but the compact
graph still exposes a source-less zero-degree AST node for the old package URI.
Treat filesystem/manifest absence as authoritative; prune/rebuild the generated
graph in a separate Graphify maintenance change rather than hand-editing JSON.
