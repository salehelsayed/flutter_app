> Part of the **[Group Chat Improvement Review](./README.md)** · Cross-plan **implementation-completeness audit** of six landed TDD plans.

---

# Gap-closure TDD plan — residual gaps found auditing the 6 in-flight plans (2026-06-17)

**Status: PLAN ONLY.** Produced by a 20-agent verify→refute→consistency workflow against the working tree on `124-harness-refactor`, then every headline finding re-confirmed by hand. Scope = the six plans the audit covered:

- `03-P0-removal-rotation-fails-closed-TDD-plan.md` (Slice 1)
- `03-P0-removal-rotation-slice2-deferred-distribution-TDD-plan.md` (Slice 2)
- `02-P0-undecryptable-messages-self-heal-TDD-plan.md` (Slice 1)
- `02-P0-undecryptable-messages-self-heal-SLICE-2-TDD-plan.md` (Slice 2)
- `12-P2-PartB-TDD-plan.md` and `12-P2-PartB-REMAINING-TDD-plan.md`

## 0. Verdict per plan (what's actually landed)

| Plan | Verdict | Notes |
|---|---|---|
| **03 Slice 1** (removal fails-closed) | ✅ **COMPLETE** | `RotateGroupKeyOutcome`, both abort gates removed (promote-then-defer), `removalBroadcast`-guarded rollback (INV-R2), partial l10n, INV-R1..R5 host tests, real-Go device proof. No gaps. |
| **03 Slice 2** (deferred distribution) | 🟡 **MOSTLY** | Table (mig 078), helpers, model, repo, runner (cap/monotonic/finalize-once), resume-sweep, sink-wired across all 3 rotate paths — all real. **Gaps: G-A** (primary key-arrival trigger never wired at config-apply receive sites), **G-G** (INV-D5 throw untested). |
| **02 Slice 1** (self-heal quartet) | 🟡 **MOSTLY** | UDM-A/B/C/D all real + wired + tested (mig 080). Session-0 partial extraction is **justified** (documented tech-debt note + compiler-enforced). **Gap: G-F** (resume Step-3c→8i ordering not locked). |
| **02 Slice 2** (Go grace/ring + pull) | 🟡 **MOSTLY — memory was STALE** | Memory said "PENDING"; in fact **UDM-E + UDM-F + UDM-G are all implemented** and `go test ./node` UDM-E/F passes (verified: `ok 4.46s`). **Gaps: G-B** (no integrated UDM-G round-trip sim), **G-C** (`go test ./node` in no gate), **G-H** (clamp doc), device matrix external-only. |
| **12-P2 Part B + REMAINING** | 🟡 **MOSTLY** | Waves 1-3/5, R1, R2 (trust gate **fail-closed, verified**), R3 (mig 084), R4, R5-lock all real + flag default-OFF. **Gap: R6** (`b1b_sibling_device_convergence` device scenario never registered — blocks R7 flag-flip; external). |
| **Cross-cutting** | 🟡 | Migrations 075-090 clean, no collisions, all wired onCreate+onUpgrade, DB v90; seams coherent. **Gaps: G-D** (proof tests orphaned → `completeness-check` is RED), **G-E** (chain test omits 084/085/087/088/089). |

**No DEFERRED_LAZY implementation was found.** The single genuine implementation shortfall is **G-A** (a silent scope reduction of the plan's "both triggers" decision). Everything else is **test/gate-coverage** that the plans explicitly promised, or honestly-disclosed external device work.

### Justified deferrals — confirmed fine, no action

- **02 Slice 1, Session 0** — only 2/6 repair-fake copies migrated to the shared fake. The plan made full extraction *Optional*; the shared fake (`test/shared/fakes/in_memory_group_pending_key_repair_repository.dart:5-16`) carries the required tech-debt note naming all 4 divergent copies, and `implements GroupPendingKeyRepairRepository` compiler-enforces that new methods reach every copy (all 4 were correctly hand-patched for the 3 Slice-1 methods). **Not a gap.**
- **12-P2 R5.1 / R5.3** — explicitly skipped as low-value; the real admit→hydrate path is covered by `group_sibling_device_admission_test.dart`. **Not a gap.**
- **All `@Tags(['device'])` proof PASS results** are doc-asserted (in `test-gate-definitions.md`), not host-reproducible — inherent to a device matrix.

---

## Severity-ordered sessions

Order: **G-A → G-B → G-C → G-D → G-E → G-F → G-G** (then doc notes G-H + the cross-finding heads-up). Each is RED-then-GREEN, independently shippable, Dart/Go/shell-host only — no migration, no device gate except where noted.

---

### Session G-A — wire the PRIMARY key-arrival drain trigger at the config-apply RECEIVE sites (03 Slice 2, P2)

**Confirmed gap.** `triggerDeferredDistributionDrainForPeer(` is consumed at exactly one production site — `lib/features/groups/application/add_group_member_use_case.dart:332` (the *local admin add* path) — plus the resume catch-all `groupPendingKeyDistributionRunner.drainAllPending` (`main.dart:4118`). It is wired at **none** of the plan's named primary RECEIVE sites: `group_message_listener.dart` has 4 `saveMember` sites (≈`:3111/:3266/:4165/:5251`) and **zero** drain triggers; `handle_incoming_group_invite_use_case.dart:943` `saveMember` has none. (Verified by `grep -a` — these files contain a non-UTF8 byte that makes plain `grep` silently emit nothing; use `grep -a`.)

Effect: when the **queue owner** (the admin who deferred a keyless member) learns that member's regained ML-KEM key via a *received* verified config, no prompt drain fires — convergence waits for the next app-resume. This is the plan's OQ-2 "both triggers" decision (`03-...slice2...:162`, `:234`) silently narrowed to "add-path + resume" with no stated justification. Degraded **promptness** of a best-effort convergence feature only; the removed-member security boundary (Slice 1) is untouched, and resume backstops eventual convergence — hence P2, not P0.

**RED tests first:**
1. `handle_incoming_group_invite_use_case_test.dart` — seed a `pending` `GroupPendingKeyDistribution` row for a previously-keyless peer Y; deliver a verified config-apply whose `GroupMember.fromConfigMap` gives Y a *usable* `mlKemPublicKey`/`devices` differing from the prior persisted member; assert the drain sink is invoked for `(groupId, Y)`. Negative twin: a **username-only** `saveMember` (no key/device change) does **not** fire it.
2. `group_message_listener_test.dart` — same assertion at the `member_added`/config-apply branch (≈`:3111`); audit `:3266/:4165/:5251` and apply the trigger **only** where a remote member's key first lands, never on username-only refreshes.
3. Restore the plan's `group_membership_smoke_test.dart` integration assertion (`03-...slice2...:186`): "remove with a keyless bystander → bystander converges after key-updated drain" — pending row finalizes `distributed` after the config-apply trigger, and Y decrypts at the current epoch.

**GREEN edits:**
- Reuse the already-wired process-wide sink (`setDeferredDistributionDrainSink`, `main.dart:2516` → `triggerDeferredDistributionDrainForPeer`). Thread a `drainDeferredDistributionsForPeer(groupId, peerId)`-style callback into `handle_incoming_group_invite_use_case.dart` and the listener's config-apply branch.
- Fire it **after** the key-bearing `saveMember`, gated by a key-changed delta computed against the pre-save member — mirror `_sameDeviceSet` (`add_group_member_use_case.dart:57-105`) so username-only writes don't trigger it.

**Migration:** none. **Risk:** must use the `_sameDeviceSet` guard or the trigger fires on every benign roster refresh.

---

### Session G-B — integrated UDM-G pull round-trip sim + GroupTestUser admin-responder hook (02 Slice 2, P1)

**Confirmed gap.** UDM-G's sender (`GroupKeyRepairRequestSender`) and responder (`GroupKeyRepairResponderListener`) are both real, prod-wired (`main.dart:2560-2573` / `:2651-2680`, started `:2943`), and each **unit-tested in isolation**. But the plan's promised **end-to-end** proof (`02-...SLICE-2...:116`, `:125`) was never built: **no single test imports both seams** (verified: 0 files), and `test/shared/fakes/group_test_user.dart` has **no admin-responder hook** (verified: no `responder` reference). The closest integration test (`group_resume_recovery_test.dart` DE-014) only *collects* the request then **hand-crafts** the re-delivery — the request→responder→re-deliver→repair seam is faked by the test, not exercised. Since the Slice-2 device proof is also PENDING, UDM-G — the largest, most protocol-invasive piece, the residual the whole finding closes — currently has **zero integrated coverage**: envelope-shape drift, admin-transport resolution, or placeholder-supersede regressions pass both isolated suites green.

**RED test first** — new `test/features/groups/integration/group_key_repair_pull_roundtrip_test.dart` (or extend `group_resume_recovery_test.dart`), wired into the host gate (see G-D):
- Two `GroupTestUser`s over `FakeGroupPubSubNetwork`: admin holds epoch N; behind-epoch Bob holds N-1.
- Trigger Bob's `group:decryption_failed` → assert Bob's **real** `GroupKeyRepairRequestSender` fires one signed `group_key_repair_request` (payload has `requesterPeerId/requesterDeviceId/keyEpoch` + non-empty signature) → routed over the network to the admin.
- Assert the admin **responder** receives it, passes sig-verify + member-at-epoch authz + rate-limit, and re-delivers the **exact** epoch N via `getKeyByGeneration` (never `getLatestKey`, never `group:updateKey`/mint) → Bob's `group_key_update` listener applies N → the `pending_key` placeholder flips off pending, with **no test-crafted replay envelope**.
- Adversarial cases the isolated suites can't catch: non-member request rejected; duplicate request rate-limited; the re-delivery audit binds device/transport fields (guards the B4-dissolve `device/transport_mismatch` trap).

**GREEN edits:**
- Extend `test/shared/fakes/group_test_user.dart` with an admin-responder seam: instantiate `GroupKeyRepairResponderListener` (mirror `main.dart:2651` wiring — bridge, group/key repos, `getKeyByGeneration`-backed single-device re-delivery, authz, per-`(requester,groupId,epoch)` rate-limit) subscribed to that user's incoming `group_key_repair_request` stream; route the requester's emitted request through the network (replace the bare `repairRequests.add` collector with a network publish).

**Migration:** none. **Device matrix:** the real-ML-KEM 2-device UDM-G/E/F run stays the remaining external proof (no host substitute).

---

### Session G-C — wire the `go test ./node` UDM-E/F closure gate (02 Slice 2, P1)

**Confirmed gap.** The plan makes `go test ./node -run 'GroupTopicValidator|HandleGroupSubscription|GroupKey|KeyRotation'` a **mandatory** closure gate (`02-...SLICE-2...:33`, `:137`). The tests exist and pass (`go-mknoon/node/pubsub_key_rotation_grace_udme_test.go`, `pubsub_udmf_emit_test.go`; verified `go test ./node -run "UDME|UDMF|FutureEpoch|..." → ok 4.46s`). But **no script gate runs `./node`** — the only `go test` in `scripts/` is the single hardcoded `go test ./bridge -run TestGroupSendReliable_...` (`run_host_test_gates.sh:231/:240`). `go-mknoon/Makefile:45` `test: go test ./...` is manual-only and too broad (pulls vendored `third_party`). So the entire UDM-E/F crypto/security posture change (held-key ring, Reject→Ignore split) has **no automated regression catcher**.

**RED-then-GREEN (the gate itself):**
- **GREEN — `scripts/run_host_test_gates.sh`:** generalize the special-cased `GO_BRIDGE_CONNECTED_PEER_TEST` constant (`:55`) into a small list of Go gate commands, or add a second constant (e.g. `GO_NODE_KEYROTATION_TEST`), and have `print_command_for_path`/`run_path` (`:228-244`) emit `(cd go-mknoon && go test ./node -run 'GroupTopicValidator|HandleGroupSubscription|GroupKey|KeyRotation' -count=1)`. Add it to the `host-all` scope so the default host gate runs it.
- **Verify (RED):** `./scripts/run_host_test_gates.sh host-all --dry-run` now prints the `go test ./node -run '...KeyRotation'` command. Then mutation-verify: temporarily shrink `RetainedEpochKeys` or flip the UDM-F Reject→Ignore branch in `go-mknoon/node/pubsub.go`, confirm the gate **fails**, revert.

**Migration:** none. **Note:** do not substitute the Makefile `./...` target — it doesn't satisfy the targeted `-run` closure gate and includes vendor.

---

### Session G-D — register the device/sim proofs so `completeness-check` is GREEN (cross-cutting, P2)

**Confirmed gap — and it makes a repo gate currently RED.** `scripts/run_test_gates.sh classify_path` only matches `^test/...` paths; every `integration_test/*_proof_test.dart` falls through to `return 1`. The 7 group device proofs — including the two keyless proofs (`group_removal_rotation_keyless_proof_test.dart`, `..._converge_proof_test.dart`, the latter also hosting the folded Finding-02 self-heal proof) — are referenced by **no** gate (verified: only a comment mentions any proof file). Two audit agents independently ran `bash scripts/run_test_gates.sh completeness-check` and it **reports `893/913 classified` and exits 1**, listing all 7 proofs (plus ~13 other recent group proofs) under "Unmatched test files". So the plans' "add both proofs to the gate list" requirement (`03-...slice2...:216`) was never done, and the completeness gate is red from accumulated proof-registration debt.

**Also fold in** the minor named-gate items the audit confirmed:
- UDM-G unit tests (`group_key_repair_request_sender_test.dart`, `group_key_repair_responder_listener_test.dart`, `group_key_repair_wiring_test.dart`) run under `run_host_test_gates.sh host-all` dir-sweep but are **absent** from the focused `GROUP_TESTS` list (`run_test_gates.sh:83-91`).

**RED-then-GREEN:**
1. **GREEN (recommended, fixes all proofs at once) — `scripts/run_test_gates.sh classify_path`:** add a branch recognizing manual device proofs, e.g. after the existing `integration_test` performance branch: `if [[ "$path" =~ ^integration_test/.*_proof_test\.dart$ ]]; then printf 'optional / manual device-proof suite'; return 0; fi`. This classifies the proofs as an explicit manual category.
2. **Verify (RED→GREEN):** add a focused shell/`bats` assertion (or a Dart test reading the script output) that `classify_path` returns 0 for each of the 7 `*_proof_test.dart` paths, and that `bash scripts/run_test_gates.sh completeness-check` prints "Completeness check PASS." (exit 0) with no proof in the unmatched list. Confirm RED on HEAD first.
3. **GREEN (named-gate coverage):** add the 3 UDM-G test paths to `GROUP_TESTS` (`run_test_gates.sh:83-91`) — or add a registration-completeness meta-test asserting every `test/features/groups/**/*_test.dart` is present in some gate array (the gate is hand-curated with no dir sweep).

**Migration:** none. **Note:** option (1) clears the completeness gate for all 7 sibling proofs in one branch; registering only the keyless two leaves the gate red.

---

### Session G-E — add 084/085/087/088/089 to `full_migration_chain_test` fresh-install (cross-cutting, P2)

**Confirmed gap.** `test/core/database/integration/full_migration_chain_test.dart` `runFreshInstallMigrations` (`:118-185`) claims to match `main.dart` `onCreate` but **omits five runners** (verified: each `grep -c` = 0): `runGroupMemberDeviceSnapshotsMigration` (084), `runPendingSiblingDevicesMigration` (085), `runGroupMessageRetryBackoffColumnsMigration` (087), `runGroupRejoinStateMigration` (088), `runMediaAttachmentDownloadRetryColumnMigration` (089). `main.dart` `onCreate` (`:499-511`) + `onUpgrade` (`:741-788`) are correct, so this is a **fresh-install schema coverage hole**, not a prod defect — but it means the canonical chain guard never exercises the 5 most recent tables/columns.

**RED-then-GREEN:**
1. **RED:** add the 5 missing tables/columns to the chain test's post-fresh-install schema assertions (`PRAGMA table_info` for `group_member_device_snapshots`, `pending_sibling_devices`, the retry-backoff columns, `group_rejoin_state`, the media `download_retry` column) — fails today because the runners aren't invoked.
2. **GREEN:** append the 5 runners (imports + calls) to `runFreshInstallMigrations` in `main.dart` `onCreate` order, and to `buildAllMigrations`/the explicit chain block if the file mirrors them.

**Migration:** none (the migrations exist and are prod-wired — this is test reconciliation only).

---

### Session G-F — lock the resume Step-3c → Step-8i ordering (02 Slice 1, P2/cleanup)

**Confirmed gap.** `02 Slice 1` requires the pending-repair sweep to run **after** the Step-3c `drainGroupOfflineInbox` ("sweep must be after drain or it re-creates the bug"). Source is correct (`handle_app_resumed.dart` Step 3c `:248-249` precedes Step 8i `:693-701`), but the only ordering test (`handle_app_resumed_pending_key_repair_sweep_test.dart:47`) asserts solely the `['8h_drain','8i_sweep']` relationship — the **3c-relative** ordering is unguarded against a future reorder. (Step 3c calls the real `drainGroupOfflineInbox` directly, not an injectable `Fn`, and is gated on `needsGroupRecovery`, so the runtime order-recorder can't capture it without a source change.)

**RED-then-GREEN — source-order lock (mirrors `handle_app_resumed_phase2_continuation_wiring_test.dart:52`):**
- **RED:** read `lib/core/lifecycle/handle_app_resumed.dart` source text and assert `source.indexOf('drainGroupOfflineInbox(') < source.indexOf('retryAllPendingGroupKeyRepairsFn')` (or the `Step 3c` / `Step 8i` markers). Mutation-verify by swapping the two blocks → test goes RED.
- **GREEN:** keep the order. Place the test in `handle_app_resumed_pending_key_repair_sweep_test.dart` (dir-swept by the lifecycle gate; no new registration).

**Migration:** none.

---

### Session G-G — INV-D5 unit test: an enqueue throw never aborts rotation (03 Slice 2, P2)

**Confirmed gap.** INV-D5 is implemented — the per-peer `await deferredSink(...)` is wrapped in try/catch emitting `GROUP_ROTATE_KEY_DEFERRED_ENQUEUE_ERROR` (`rotate_and_distribute_group_key_use_case.dart:562-578`), and rotation still returns the promoted outcome (`:648-652`). But **no test throws** from the enqueue closure (verified: all 4 enqueue closures in the test only record; `grep GROUP_ROTATE_KEY_DEFERRED_ENQUEUE_ERROR test/` = 0). A regression moving the await outside its try/catch would stay green.

**RED-then-GREEN:**
- **RED** — in `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart` (sibling to the existing "falls back to the process-wide sink" case ≈`:2515`): one keyless deferred member; pass `enqueueDeferredDistribution: (...) async { throw Exception('enqueue boom'); }`. Assert rotation does **not** throw, `result.rotated` is true, epoch advanced, and `deferredPeerIds` is preserved. Optionally assert `GROUP_ROTATE_KEY_DEFERRED_ENQUEUE_ERROR` via an injected flow sink.
- **GREEN:** none — implementation already satisfies it; the test pins it.

**Migration:** none. Pure unit test, auto dir-swept.

---

## Doc-only items (no code/test change)

- **G-H (02 Slice 2):** the future-epoch Ignore clamp is `maxFutureKeyEpochIgnoreWindow = 1024` (`go-mknoon/node/pubsub.go:1805`), ~200× the plan's suggested `N+1..N+K` (K=5). Behavior is security-equivalent (Ignore grants no traffic/credit; only the penalty-dodge window widens, which the plan's threat model already accepts) and self-justified in-code. Add **one line** to the constant comment (or the slice-2 closure log) acknowledging the intentional departure from the plan's K=5.

## Heads-up — outside these 6 plans, surfaced by the consistency pass

- **`kOnJoinMetadataResyncEnabled` now defaults `true`** (`lib/core/config/on_join_metadata_resync_flag.dart:19-23`, flipped in commit `ba0d331d` "08(D): default on-join metadata resync ON for prod"). This contradicts the finding-08 memory note that 08-D "ships dark behind the flag." This is **finding-08**, not one of the six audited plans — flagged only so you confirm the flip was intentional and that 08-D had its device proof before going default-ON. (The other two flags, `kMultiDeviceSyncEnabled` and `kForwardRotateOnAddEnabled`, remain default-OFF as documented.)

## External-only (cannot run on host — genuinely open, no TDD action here)

- **12-P2 R6** — `b1b_sibling_device_convergence` is registered in **no** harness/criteria/runner (verified: 0 hits in `group_multi_party_device_criteria.dart`, `run_group_multi_party_device_real.dart`, `group_multi_device_real_harness.dart`; no `_runB1b*` handlers). The role-handler code was intentionally not written blind into the 27k-line harness. It is a **real open gate** that blocks the **R7** `kMultiDeviceSyncEnabled` flag-flip — per-device ML-KEM key separation is unproven (host sims use passthrough `FakeBridge`). Closing it needs a real two-target run (iPhone-sim + Pixel, real Go bridge, `--dart-define=MKNOON_ENABLE_MULTI_DEVICE_SYNC=true`) where the sibling obtains the key only via the live announce→admit→redistribute path (never `importJoinedGroupFixture`). Keep the feature default-OFF until that run is green.
- **02 Slice 2 device matrix** and the **03 / 02-Slice1 keyless/self-heal device proofs** — `make all` + `pod install` + iPhone/Pixel runs; honestly disclosed as PENDING in `test-gate-definitions.md`.

## Rollout

P1 first (G-B, G-C — UDM-G integrated coverage + the Go closure gate), then the implementation fix G-A, then the host-test-infra hygiene cluster (G-D, G-E, G-F, G-G), then the doc note. All host-runnable; none carries a migration. Re-run `bash scripts/run_test_gates.sh completeness-check` after G-D to confirm it returns 0.
