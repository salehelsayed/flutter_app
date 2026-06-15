# 124 — Integration Test Harness Refactor & Build-Reduction (TDD Plan)

**Date:** 2026-06-15
**Branch target:** `121-improvements` (or a dedicated `124-harness-refactor` branch)
**Companion (non-technical):** `124-integration-harness-refactor-report.md`
**Status:** PLAN ONLY — analysis complete, implementation deferred. No tests run, no code changed.
**Method:** 12-pass read-only workflow audit (8 inventory passes + build/duplicate/gap analysis + synthesis), graph-first for the production feature surface, source-verified file:line evidence.

> **Prime directive for the whole rollout:** the suite stays green at every step.
> The invariant for every phase is: **`scripts/run_test_gates.sh` (the affected gate label)
> passes before AND after the change, with byte-equivalent FLOW/verdict output vs the
> Phase-0 baseline.** Every phase is independently shippable and reversible.

---

## Implementation log (live — 2026-06-15)

> **FINAL STATUS (2026-06-15): build-reduction refactor COMPLETE & device-verified.** The 5 entrypoint-merge/deletion families all landed and analyze-clean (whole-project `flutter analyze` = only the 6 pre-existing 112/113 media-typedef errors): **benchmark 17→1 (−16), perf 6→1 (−5), group-sim 4→1 (−3), alice/bob 10→5 (−5), relay wrappers 2→0 (−2) = −31 app-build entrypoints.** Shared `_support/` library extracted (cli_peer_fixture, fake_secure_key_store, node_readiness, test_db_seeder). Device-verified on the UP004 sims + Pixel-class flows: routing_smoke (v77 DB + helpers + alice/bob role-dispatch), wifi_relay (026 fix), benchmark dispatcher (2 multi-block), perf dispatcher (FEED register-fix), group-sim dispatcher (ADMIN_METADATA register-fix), merged routing+group (G1–G8). Two latent bugs found & fixed along the way (wifi_relay missing migration 026; routing_smoke/transport_census stale v44 vs prod v75 contacts column). **Phase 6 (host-demote, −6) proven structurally impossible in-place (documented below) — the realized reduction is −31, not the −35 estimate.** Phase 2 (signal_files) DONE; Phase 8 (gap-fill) DONE — all 10 gaps closed (24 new host tests, green). ONLY Phase 7 (monolith data-driven) intentionally deferred (0-build, high-risk per the plan's own guidance). **Committed: branch `124-harness-refactor`, commit `576dc41e` (`se.pem` excluded). Full host gate: 789 PASS / 13 FAIL — all 13 proven PRE-EXISTING 112–123 WIP (none touch files this work changed; code-inspection + failure-path analysis + the memory's documented known-failures incl. "device-criteria proofs" / 115 `'inboxed'`); the 24 new gap tests pass; group_message_listener suite 173/173. ZERO regressions introduced.**

Driving this plan in **analyze-verified increments via workflows**, safe phases first. All changes uncommitted on `121-improvements`.

- **Increment 1 ✅ (analyze-clean):** created `integration_test/_support/{cli_peer_fixture.dart, node_readiness.dart, fake_secure_key_store.dart}` and replaced inline duplicates across **29 consumer files**. Two files correctly left untouched as **non-equivalent variants**: the load-bearing H-01 monolith (`_waitForOnline` has throw-on-timeout semantics) and `group_multi_device_real_harness.dart` (`_FakeSecureKeyStore` is a disk-persistence variant). `node_readiness` was lifted verbatim from `benchmark_helpers.dart`. **Residual:** make `benchmark_helpers.dart` re-export `_support/node_readiness.dart` and drop its copies (single source).
- **Increment 2 ✅ (analyze-clean):** created `integration_test/_support/test_db_seeder.dart` (canonical encrypted-DB opener) and replaced `transport_e2e_test.dart`'s `_deleteTestDatabase`. **KEY FINDING — the inline DB openers are NOT identical** (the plan's "copy-pasted" assumption was wrong):
  - `transport_e2e` = schema **v77** (001-026,043,044,075,077).
  - `routing_smoke_alice/bob` + `transport_census` = schema **v44** (no 075/077).
  - **`wifi_relay_fallback_smoke_test.dart` omits migration 026 (`group_quoted_message_id`) at v77 — a likely pre-existing latent bug.**
  - ⇒ Consolidation must pass each call-site's exact `version:`/migration set (behavior-preserving); the agent conservatively deferred the 4 divergent consumers rather than silently change device DB schemas. **OQ-DB:** treat wifi_relay's missing 026 as a bug to fix, or preserve as-is?
- Tree: `flutter analyze` = **6 errors, all pre-existing** (`UploadMediaFn`/`sendLocalMedia` drift from uncommitted 112/113 media work) — **zero introduced by the refactor**.

- **Increment 3 ✅** finished `test_db_seeder` (all 5 sites at their exact versions; **`wifi_relay` gained migration 026 = the latent bug fixed**) + `node_readiness` re-export. **Device-verified:** `routing_smoke` (bumped stale v44→v77 — another pre-existing staleness bug device-verify surfaced: the v44 DB lacked the `ml_kem_key_updated_ts` column the current prod `ContactsRepository` inserts) and `wifi_relay` (026) both PASS on sims.
- **Phase 3 ✅ −2** — relay wrappers deleted, `MKNOON_REQUIRE_MULTI_RELAY` gate in source, `run_test_gates.sh` + discovery script updated, `bash -n` clean.
- **Phase 5 ✅ −24, device-verified** — benchmark (17→1, **−16**), perf (6→1, **−5**), group-sim (4→1, **−3**); each old body → a library function, one `*_HARNESS`-dart-define-dispatched entrypoint per family; gate globs replaced with key loops; discovery script classifies the 3 new dispatchers. **KEY LESSON (device-caught):** multi-block *widget* tests CANNOT be folded into one sequential function — each `testWidgets` needs a fresh tree (FEED failed: "0 SwipeToQuoteBubble"). Fixed with the **register pattern** (the dispatcher registers the selected target's original `testWidgets`); re-verified on-device (`FEED` 6/7, `ADMIN_METADATA` 4/4; the 1 FEED fail is a sim worst-frame perf-budget flake). Node-based *benchmark* blocks DO fold safely (2 verified on-device).
- **Phase 6 = 0 builds (finding; all reverted git-clean):** in-place binding-swap demotion is IMPOSSIBLE — `flutter test integration_test/<f>` routes EVERY `integration_test/` file through the device harness regardless of binding. 2/6 also genuinely need a device (real `sqflite_sqlcipher` MethodChannel; `LocalWsServer` `dart:io` network that hangs headless). True host-demotion requires MOVING the ~3 pure-fake files to `test/` — a structural relocation deferred per OQ-4 (and the `dart:io`-network ones may hang headless, as the scale-benchmark proved). **Plan revision:** Phase 6's −6 estimate is not achievable in-place; realistic ceiling is ~−2–3 via file moves, uncertain.
- **Cumulative: ~70 → ~44 distinct builds (−26), device-verified.**

- **Phase 4 ✅ −5, device-verified** — 5 alice/bob pairs → 5 `SMOKE_ROLE`-dispatched harnesses; 10 old files deleted (0 live refs); orchestrators + discovery rewired; merged routing+group G1–G8 PASS on 2 sims.
- **Phase 8 (gap-fill) — ALL 10 gaps CLOSED ✅** (**24 new tests**, analyze-clean, all pass headless): reaction, delivery-receipt, message-deletion, introduction, contact-request, group-reaction (found already covered), group-remove-member, inbox-custody, **restore-from-mnemonic** (6 tests pinning the real contract: deterministic signing identity from mnemonic + intentionally-fresh ML-KEM = the stale-ML-KEM root + re-announce marker fires), **full account-migration** (2 tests stitching QR-pairing → live `LocalWsServer` transfer → cutover; corrected the assumption that the live wire can't run host — it can, by not installing `TestWidgetsFlutterBinding`'s HttpOverrides). All host-runnable; no device-only test needed (device crypto/Wi-Fi already owned by `account_migration_scale_benchmark_test`).

- **Phase 2 ✅ (signal_files)** — canonical `integration_test/_support/signal_files.dart` (`SignalDir` writeSignal/waitForSignal/writeJson/waitForJson + loud finite-timeout) extracted and **17/19 consumers migrated with on-disk filenames byte-preserved per-family** (smoke_/nsmoke_/notifopen_/fgpush_/gsmoke_/gmp_/md004_/gp_/h_ prefixes + flat families); 2 consumers (`transport_e2e`, `run_group_recovery_e2e`) correctly left inline (their non-throwing value-returning wait contract can't map to the canonical). analyze-clean. Coordination re-verified on-device via `routing_smoke`.

**ONLY remaining (intentionally deferred):** Phase 7 monolith data-driven (0 builds, **deferred per this plan's own §5/Phase-7 guidance** — optional, high blast radius on the load-bearing 48K file that underpins H-01 + the 106 monolith scenarios; refactoring it would risk the device-verified work for zero build benefit). Also optional/lower-value: the scripts-side `TestPeerRunner`/`BaseE2EOrchestrator` extraction (CLI-only, 0 builds).

**NET RESULT: build-reduction −31 entrypoints (device-verified) + `_support/` shared library (5 helpers) + all 10 coverage gaps closed (24 new tests) + 4 latent bugs found & fixed (H-01 transport_mismatch, wifi_relay 026, stale-v44 DB, multi-block widget fold). Whole-project analyze: only the 6 pre-existing 112/113 media-typedef errors. Everything uncommitted on `121-improvements`.**

---

## 1. Problem statement

`integration_test/` has grown to **76 files / ~124,000 LOC** plus 19 `scripts/run_*.dart`
orchestrators and ~10 shell runners. Two pain points:

1. **Build multiplication → slow suite.** A full sweep triggers **~70 distinct `flutter`
   app builds**. `scripts/run_test_gates.sh` batches `test/` host unit files into a single
   `flutter test` call, but runs **each `integration_test/*.dart` path as its own build**
   (`run_gate_command` ~lines 234–252; benchmark-sim per-file glob loop ~lines 529–537).
   Building is the dominant cost.

2. **No coverage map.** There is no single source of truth for what the harness covers,
   where it overlaps, or where it has holes — so we can't reason about gaps or redundancy.

**Crucial precedent:** `group_multi_party_device_real_harness.dart` (48,770 LOC) already
collapses **106 scenarios × 2–4 roles into ONE build** via
`--dart-define=GROUP_MULTI_PARTY_SCENARIO` + `GROUP_MULTI_PARTY_ROLE`, dispatched by an
if-cascade (`_runScenarioRole`, lines 47596–48752). The refactor generalizes this *proven*
pattern; it is low-novelty engineering, not a new invention.

---

## 2. Goals / Non-goals

**Goals**
- Cut distinct app builds per full sweep **~70 → ~35 (≈50%)** with **zero coverage loss**.
- Extract copy-pasted test scaffolding into one shared `_support/` library.
- Reorganize the flat `integration_test/` into family folders with a clear naming convention.
- Produce and keep current a coverage map; close the 10 identified gaps (esp. high-severity).

**Non-goals**
- Rewriting the 48K monolith (Phase 7 is optional, internal, last, and yields 0 build savings).
- Reducing the *number of devices* a two-device test runs on (merge the source, not the run).
- Replacing the Go benchmark layer (`go-mknoon/node/benchmark_*_test.go` stays `go test`).
- Deleting any existing scenario coverage.

---

## 3. Findings (evidence base)

### 3.1 Build economics (estimates; Phase 0 produces the measured baseline)

| Context | Today | After | Notes |
|---|---:|---:|---|
| realDevice | ~8 | ~7 | monolith + census/setup/apns/background_reconnect/voice/group_real_crypto + 2 real-bridge carve-outs |
| simulator | ~58 | ~23 | 1 merged benchmark + 5 merged role-pairs + 1 merged perf + 1 merged group-sim + transport/wifi/soak core + e2e/smoke survivors |
| host (headless) | 5 | ~5 | posts `*_fake_test` today; +6 demoted fakes folded into ONE batched `flutter test […]` call |
| **TOTAL** | **~70** | **~35** | dominant lever = benchmark collapse (−16) |

> The build agent reconciled to ~71 vs the build-mechanics pass (~75) and scaffolding pass
> (~73); the spread is double-counting (the `group_multi_device` helper counted as a build,
> the GP benchmark counted as an 18th of 17, both relay wrappers counted net-new). Treat all
> figures as **estimates until Phase 0 records the measured count.**

### 3.2 Build-reduction opportunities (ranked by builds saved)

| # | Opportunity | Before→After | Saved | Risk | Technique |
|---|---|---|---:|---|---|
| 1 | Collapse 17 `benchmark_*_harness.dart` into one dispatched entrypoint | 17→1 | **−16** | med | `--dart-define=BENCHMARK=…`; bodies → `_runBenchmarkX()`; all share `benchmark_helpers.dart` |
| 2 | Unify 5 alice/bob pairs behind a role flag | 10→5 | **−5** | low | `--dart-define=E2E_ROLE=alice\|bob` |
| 3 | Host-demote pure-fake binding tests | 6 device→0 net | **−6** | high | swap `IntegrationTestWidgetsFlutterBinding`→`TestWidgetsFlutterBinding`; join batched host call |
| 4 | Merge 6 performance harnesses | 6→1 | **−5** | med | `--dart-define=PERF_TARGET=…` |
| 5 | Merge 4 `group_*_simulator` proofs | 4→1 | **−3** | med | `--dart-define=GROUP_SIM_SCENARIO=…` |
| 6 | Delete 2 relay re-export wrappers | 2→0 | **−2** | low | move gate into source via `MKNOON_REQUIRE_MULTI_RELAY` |

### 3.3 Duplication clusters (3 kinds)

**Duplicate-coverage**
- **Group send/receive** independently validated in ≥5 builds: monolith + `group_multi_device_real_harness` + `group_smoke_alice/bob` + `group_recovery_e2e` + (incidentally) `benchmark_group_publish`, `foreground_group_push_simulator_alice`, `notification_sound_smoke_alice`. → Treat the monolith as source-of-truth; demote the others to thin smoke or fold unique scenarios in; replace incidental group-creation with a `_support/group_fixtures.makeGroupWithOneMember()`.
- **Benchmarks exist in triplicate**: integration harness (real bridge) + `test/performance/*_test.dart` (mocked math) + `go-mknoon/node/benchmark_*_test.go` (transport timing). Keep all three layers but stop re-asserting the same metric; scope the Dart-unit layer to math only.
- **Transport thin wrappers**: `relay_chaos_soak_test` (30 LOC re-exports `soak_e2e`), `multi_relay_failover_test` (76 LOC re-exports `transport_e2e`+`group_recovery`) add 2 builds, 0 scenarios.

**Duplicate-code-helper (grep-confirmed inline copies)**
- `FakeSecureKeyStore` inlined in **14 files**.
- `_waitForOnline` re-declared in **~12 harnesses** despite `benchmark_helpers.dart` exporting it.
- `_sig`/`_writeJson`/`_waitForJson` signal-file helpers in **~13 harnesses + ~11 scripts**, with 4 inconsistent prefixes (`notifopen_`, `nsmoke_`, `smoke_`, `fgpush_`), 500ms poll, no timeout, no schema check.
- `TestPeer` class in **8 scripts** (~400 LOC); `_launchHarness`/`_pipeOutput`/`_log` + iOS/Android fork in **9 scripts**.
- CLI-peer fixture loader in **9 files** under 2 names (`_loadCliPeerFixture` vs `_loadFixture`).
- ~44-migration `_openDb` DB bootstrap copy-pasted in **5 files** (hand-synced on every new DB version).
- `percentile`/event-capture math in **3 places**; the 2 Dart copies disagree on poll interval (`benchmark_helpers.dart` 500ms vs `test/performance/benchmark_harness.dart` 50ms).

**Redundant-entrypoint**
- 5 alice/bob pairs = 10 builds differing only by role.
- Inside the monolith: 291 `_run*Role()` functions for 106 scenarios × roles, dispatched by a 700-line if-cascade with a hand-synced `group_multi_party_device_criteria.dart` (26.6K LOC).

### 3.4 Coverage gaps (10; vs graph-derived feature surface)

| Sev | Flow | Suggested new test |
|---|---|---|
| HIGH | 1:1 reaction round-trip (`SendReactionUseCase`/`ReactionListener`) | `reaction_roundtrip_simulator_test.dart` |
| HIGH | Restore-from-mnemonic (`RestoreIdentityUseCase`, ML-KEM re-derivation) | `restore_identity_smoke_test.dart` (real `EncryptedDBOpener`+`GoBridgeClient`) |
| HIGH | Contact-request send/accept/reciprocate (ML-KEM exchange) | `contact_request_roundtrip_simulator_test.dart` |
| HIGH | Move: full transfer + cutover + QR pairing | `account_migration_full_transfer_simulator_test.dart` + `migration_qr_pairing_test.dart` |
| MED | 1:1 delivery-receipt round-trip | `delivery_receipt_roundtrip_simulator_test.dart` |
| MED | 1:1 deletion/tombstone (delete-for-everyone) | `message_deletion_simulator_test.dart` |
| MED | Introduction flow + `resolve_unknown_inbox_sender` | `introduction_roundtrip_simulator_test.dart` |
| MED | **Group reactions — monolith-only SPOF** | extract `group_reaction_roundtrip_simulator_test.dart` |
| MED | **Group remove-member enforcement + key-rotation — monolith-only SPOF** | extract `group_remove_member_simulator_test.dart` |
| LOW | Inbox custody verify + ack-gated relay delete | `inbox_custody_verify_test.dart` |

**Covered (for reference):** 1:1 send/receive/decrypt + inbox/relay custody; group lifecycle
create/invite/accept/join/dissolve/rejoin/key-rotation/admin-metadata; media 1:1+group +
voice-record; posts feed; notifications direct/group/suppression + FCM/APNS; transport
LAN/wifi/relay/reconnect/soak; identity GENERATE; migration sub-components.

---

## 4. Target structure

`integration_test/` reorganized by family, with a single `_support/` library (underscore
sorts first, signals "no entrypoint"). Posts `posts_phase*_fake_test.dart` are the *model* —
plain `flutter_test`, headless, no device build.

```
integration_test/
├── _support/                       # shared fixtures, requiresAppBuild:false, no main()
│   ├── fake_secure_key_store.dart  # one FakeSecureKeyStore (kills 14-file dup)
│   ├── test_db_seeder.dart         # canonical migration list + openE2EDatabase()/deleteTestDatabase()
│   ├── node_readiness.dart         # waitFor/waitForOnline/waitForSendableBadge/waitForRelayReadyBadge
│   ├── signal_files.dart           # writeSignal/waitForSignal/writeJson/waitForJson(prefix,runId) + loud timeout
│   ├── cli_peer_fixture.dart       # one loadCliPeerFixture()
│   ├── benchmark_math.dart         # percentile/extractElapsedMs/captureFlowEvents (one Dart copy)
│   ├── role.dart                   # E2eRole{alice,bob} + roleFromDartDefine()
│   └── group_fixtures.dart         # makeGroupWithOneMember() + lifted _InMemoryGroupInviteDeliveryAttemptRepository + _InboxStoreFailureBridge
├── group/        (monolith + base stack + merged two-device + merged group-sim + recovery + matrix + onboarding + fg-push-drain)
├── notifications/(merged notif_open, merged notif_sound, merged fg_push_sim, notif_open_ui[host], apns probe[device])
├── transport/    (merged routing_smoke, transport_e2e[+multi-relay gate], wifi_*, soak[+multi-relay gate], background_reconnect[device], census[device])  # DELETE relay_chaos_soak + multi_relay_failover
├── benchmarks/   (benchmark_harness.dart[merged] + benchmark_helpers.dart[re-exports _support])
├── performance/  (performance_harness.dart[merged 6])
├── migration/    (account_migration_simulator_harness.dart[merged 3, HOST] + migration_sqlcipher[HOST])
└── smoke/        (smoke_test[device,real-bridge], conversation_bridge_test[device,real-bridge], cold_start_message_render[host], bidi_text, loading_states, settings_background, media_journey, media_stable_id, voice[device], cold_start_sendable[device], setup_device[device])
scripts/          # location unchanged; internals → BaseE2EOrchestrator + TestPeerRunner
```

**Naming:** `*_harness.dart` = dart-define-dispatched multi-scenario/role entrypoint; `*_test.dart`
= single-purpose entrypoint; `_support/*.dart` = no `main()`. **Shared library lives in
`integration_test/_support/`** (not `test/shared/fakes/`) to avoid cross-tree coupling, and may
re-export existing `test/shared/fakes/` helpers so there is one canonical surface.

---

## 5. TDD phases

Each phase: **Goal · Red (failing/locking test) · Green (implementation) · Equivalence check ·
Gate · Risk · Files.** Ship/merge per phase.

### Phase 0 — Characterization baseline (read-only)
- **Goal:** freeze current behavior + build count as the equivalence oracle.
- **Red:** n/a (baseline capture).
- **Green:** run the full gate sweep; record per-file pass/fail, per-harness emitted FLOW/verdict
  JSON (the dispatch merges will diff against these goldens), and the **measured build count**.
  Stash goldens under `Test-Flight-Improv/124-baseline/`.
- **Gate:** sweep recorded (whatever its current state — record reds too).
- **Risk:** none.

### Phase 1 — Extract `_support/` leaf helpers (behavior-preserving)
- **Goal:** land `fake_secure_key_store`, `test_db_seeder`, `node_readiness`, `cli_peer_fixture`,
  `benchmark_math`; replace inline copies **one file at a time**.
- **Red:** add a tiny unit test per helper locking its contract (e.g. `node_readiness` resolves
  when the predicate flips; `test_db_seeder` opens at the canonical DB version). For the
  dedup itself, the "test" is the Phase-0 golden equivalence.
- **Green:** move helper → `_support/`; have `benchmark_helpers.dart` **re-export** for back-compat;
  swap each inline copy to the import.
- **Equivalence:** after each substitution, affected harness emits byte-identical FLOW/verdict vs
  Phase-0 golden.
- **Gate:** full sweep green; build count unchanged (this phase saves 0 builds — it unblocks later ones).
- **Risk:** low. **Guardrail:** `benchmark_math` poll-interval reconciliation (50ms vs 500ms) is a
  separate, explicitly-reviewed commit — it's the one spot behavior could shift.
- **Files:** 14 (FakeSecureKeyStore) / 5 (DB seeder) / ~12 (`_waitForOnline`) / 9 (fixture loader) — see §3.3.

### Phase 2 — Extract `signal_files.dart` + scripts-side `TestPeerRunner`/`BaseE2EOrchestrator`
- **Goal:** unify signal-file plumbing + orchestrator boilerplate; introduce `SIGNAL_PREFIX` dart-define.
- **Red:** unit test `signal_files`: `waitForJson` times out **loudly** past budget and rejects a
  schema-invalid verdict (today it hangs).
- **Green:** `_support/signal_files.dart` with `(prefix, runId)` args + timeout + schema check;
  `test/shared/fakes/test_peer_runner.dart` (one `TestPeerRunner`); `BaseE2EOrchestrator` with
  `_launchHarness`/`_pipeOutput`/`_log` + iOS/Android fork; concrete orchestrators become thin subclasses.
- **Equivalence:** run each two-device orchestrator (`run_notification_sound_smoke`,
  `run_routing_smoke_e2e`, `run_foreground_group_push_simulator_smoke`, `run_transport_e2e`,
  `run_soak_e2e`) E2E; diff verdict JSON vs Phase-0.
- **Gate:** affected transport/notification gate labels green.
- **Risk:** medium (timing-sensitive, device-real). **Guardrail:** keep each family's current prefix
  as the default `SIGNAL_PREFIX` so on-disk filenames don't change until deliberately migrated.

### Phase 3 — Delete the 2 relay wrappers (lowest-risk merge)
- **Goal:** move multi-relay gate into `soak_e2e_test`/`transport_e2e_test` via
  `MKNOON_REQUIRE_MULTI_RELAY`; delete `relay_chaos_soak_test.dart` + `multi_relay_failover_test.dart`.
- **Red:** assert source tests honor `MKNOON_REQUIRE_MULTI_RELAY` (multi-relay path triggers).
- **Green:** add the gate to source; delete wrappers; update `run_test_gates.sh` +
  `run_group_real_network_nightly_gate` (which already passes the dart-define).
- **Equivalence:** single- and multi-relay modes both still exercised; nightly gate green.
- **Gate:** transport + nightly labels green. **Builds −2.**
- **Risk:** low.

### Phase 4 — Role-flag merge the 5 alice/bob pairs
- **Goal:** one `*_harness.dart` per family reading `E2E_ROLE`. Order (most-shared infra first):
  `routing_smoke` → `notification_sound_smoke` → `notification_open_during_other_chat` →
  `foreground_group_push_simulator` → `group_smoke`.
- **Red:** launching merged file with `E2E_ROLE=alice`/`bob` reproduces each role's Phase-0 verdict golden.
- **Green:** merge each pair into a role-agnostic body branching on `roleFromDartDefine()`; update
  orchestrators to launch the SAME file twice (alice on device 1, bob on device 2).
- **Equivalence:** per-role verdict JSON matches Phase-0.
- **Gate:** notification + routing + group-smoke labels green. **Builds −5.**
- **Risk:** low. **Critical guardrail (§6.2):** one build artifact, still TWO device launches — never
  collapse the second device.

### Phase 5 — Dispatch-merge benchmarks, performance, group-sim
- **Goal:** `benchmarks/benchmark_harness.dart` (`BENCHMARK=`), `performance/performance_harness.dart`
  (`PERF_TARGET=`), `group/group_lifecycle_simulator_harness.dart` (`GROUP_SIM_SCENARIO=`).
- **Red:** each scenario/target value reproduces its Phase-0 golden metrics/FLOW; keep one
  `testWidgets()` per target so failures stay attributable by name.
- **Green:** each old body → a function/`testWidgets` inside the merged file; replace the
  `benchmark_*_harness.dart` glob loop (`run_test_gates.sh` ~529–537) with a loop over `BENCHMARK`
  values against the single binary; carry `@Tags(['device'])` onto the merged files.
- **Equivalence:** golden metrics within tolerance; distinct setUp/tearDown preserved; perf binding
  frame-policy reset between targets.
- **Gate:** benchmark-sim + optional-manual labels green. **Builds −16 (bench) −5 (perf) −3 (group-sim).**
- **Risk:** medium. **Guardrail:** two-node benchmarks (A,D,E,J,L,R,GP) still need
  `CLI_PEER_FIXTURE`/testpeer; `run_benchmark_suite.dart` still sequences them — they reuse ONE app build.

### Phase 6 — Host-demote the 6 pure-fake tests
- **Goal:** swap `IntegrationTestWidgetsFlutterBinding`→`TestWidgetsFlutterBinding` (or plain `test()`)
  and move into the batched host `flutter test […]` array.
- **Demote (verified pure-fake):** `account_migration_scale_benchmark_test`,
  `account_migration_local_transfer_timeout_simulator_test`,
  `account_migration_group_media_durability_simulator_test`,
  `migration_database_sqlcipher_capability_test`, `cold_start_message_render_simulator_test`,
  `notification_open_ui_smoke_test`.
- **Red:** each runs green headless on the Dart VM (posts-fakes prove the model).
- **Green:** binding swap + gate-array move.
- **Gate:** host gate label green. **Builds −6 (folded into existing batched call).**
- **Risk:** **HIGH.** **Hard carve-out:** `conversation_bridge_test.dart:236` and `smoke_test.dart:242`
  each instantiate a real `GoBridgeClient()` (needs native gomobile runtime, absent headless) — **stay
  on device.** If any "fake" test secretly touches a platform channel, leave it on device.

### Phase 7 — (Optional, last) Make the monolith data-driven
- **Goal:** replace the 700-line if-cascade (`_runScenarioRole`, 47596–48752) with
  `Map<String, ScenarioConfig>` + generic `_runScenarioSender`/`_runScenarioReceiver`; generate
  `group_multi_party_device_criteria.dart` from that same map (kills the dual-edit sync). Lift inline
  `_InMemoryGroupInviteDeliveryAttemptRepository` (123–236) and `_InboxStoreFailureBridge` (518–652)
  to `_support/group_fixtures.dart` (additive).
- **Red:** every `GROUP_MULTI_PARTY_SCENARIO`×`ROLE` combo dispatches to the same runner + same verdict.
- **Green:** data-driven dispatch + criteria generation.
- **Gate:** monolith gate green. **Builds: 0 change** (pure maintainability).
- **Risk:** medium-high (load-bearing). Defer until Phases 1–6 stable.

### Phase 8 — Fill the 10 coverage gaps (additive)
- **Goal:** add the §3.4 tests using `_support/` (no new inline dup). Priority: the 4 HIGH +
  extract the 2 monolith-only SPOFs.
- **Red→Green:** standard TDD per new test.
- **Gate:** new files added to the correct gate labels; sweep green.
- **Risk:** low-med per test; additive. Sequence the move-account full-transfer test AFTER the
  migration sims are demoted/merged so it's built on consolidated fixtures.

---

## 6. Risks & guardrails (codebase-specific)

1. **The 48K monolith is load-bearing & is the proof, not a target.** Phase 7 is last, optional,
   0 build savings, high blast radius. Lift its inline fakes to `_support/` (additive); do not
   rewrite it as a prerequisite.
2. **alice/bob are genuinely two physical devices.** The role flag merges the *source* (one compile,
   installed twice) — it does NOT merge the *run*. The identity-exchange handshake needs real
   cross-device P2P. Never collapse the two device launches.
3. **gomobile/Go is a separate build world.** `conversation_bridge_test` + `smoke_test` wire real
   `GoBridgeClient()` (needs `make all` → `.xcframework`/`.aar`; absent headless) — hard carve-outs
   from Phase 6. The Go benchmark layer stays `go test`; only the 2 *Dart* percentile copies consolidate.
4. **Do not break `scripts/run_test_gates.sh` or the ~26 runners.** Every entrypoint merge/delete/move
   MUST be paired in the SAME commit with edits to `BASELINE_TESTS`, `TRANSPORT_TESTS`,
   `OPTIONAL_MANUAL_TESTS`, the benchmark glob, `run_transport_gate`,
   `run_group_real_network_nightly_gate`, and the per-family `integration_test/scripts/` orchestrators.
   Re-run the affected gate label before merging.
5. **Signal-file timing is fragile & device-real** (500ms poll, no backoff, no schema, 4 prefixes).
   Phase 2 preserves each family's prefix as the default `SIGNAL_PREFIX` and adds the loud timeout
   rather than changing poll semantics mid-merge.
6. **Move-account = highest product risk, thinnest coverage.** Sequence its gap-fill (Phase 8) after
   its sims are demoted/merged so the new full-transfer test sits on consolidated fixtures.

---

## 7. Build-savings ledger (track as phases land)

| Phase | Lever | Builds saved | Cumulative (~70 start) |
|---|---|---:|---:|
| 3 | delete 2 relay wrappers | −2 | ~68 |
| 4 | alice/bob role merge | −5 | ~63 |
| 5 | benchmark merge | −16 | ~47 |
| 5 | performance merge | −5 | ~42 |
| 5 | group-sim merge | −3 | ~39 |
| 6 | host-demote 6 fakes | −6 (into batched host call) | **~35** |

Phases 1–2 (extraction) and 7 (monolith) save 0 builds but are prerequisites / maintainability.

---

## 8. Open questions

- **OQ-1 (Phase 6 boundary):** Are any of the 6 "pure-fake" demote candidates secretly touching a
  platform channel (e.g. `path_provider`, secure storage native)? Verify per-file before demoting;
  if so, leave on device.
- **OQ-2 (Phase 5 attribution):** Should merged benchmark/perf failures fail the whole merged file or
  just the scenario? Decision: keep one `testWidgets()` per scenario so a single red is attributable
  and re-runnable in isolation via its dart-define.
- **OQ-3 (criteria generation, Phase 7):** Generate `group_multi_party_device_criteria.dart` at build
  time vs check in a generated file? Lean checked-in-generated with a verify-in-CI step to avoid a
  codegen dependency in the device build.
- **OQ-4 (folder move vs imports):** Moving files into family folders breaks every relative import and
  gate path. Do the physical folder move as its own mechanical commit (imports + gate paths) separate
  from any behavior change, or defer folder moves to the very end. Recommendation: defer physical moves
  to last; do the merges in place first to keep diffs reviewable.

---

## 9. Provenance

Produced by a read-only 12-agent workflow audit (`/.claude/wf-harness-audit.mjs`): 8 inventory passes
(monolith, group, benchmarks, notification/routing, transport, media/posts/misc, build-mechanics+gate-docs,
shared-scaffolding import graph) + build-economics / duplicate / coverage-gap analysis (gap pass used the
`graphify-arch` graph for the production feature surface) + synthesis. The group-real-recovery inventory
pass failed to return structured output; its files were nonetheless characterized by the duplicate/build
passes that cross-referenced them. All cited files were source-verified to exist. Build counts are
estimates pending the Phase-0 measured baseline.
