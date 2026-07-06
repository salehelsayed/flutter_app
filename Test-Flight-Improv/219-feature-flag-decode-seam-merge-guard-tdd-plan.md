# 219 - Feature-Flag Decode-Seam Merge Guard (partial map ⇒ silent-false)  (Modification)

Status: **execution-ready** (RE-REVIEWED 2026-07-06 via 10-agent `/tdd-review` — B04 promoted to MANDATORY + own `./bridge` pinned branch; core bet source-confirmed SOUND [bridge.go FeatureFlags read only at :592, config.go replace+nil-contract, 9 struct fields, testpeer 5/9, addr-vis pinned template all re-verified exact]; host-only, ships now — **land BEFORE 217** per shared-harness coordination)
Spec: free-text intent (no formal spec) — split out of 217 per the 217 review fix-list §E1 (the two slices are orthogonal: Part A sends no featureFlags; Part A edits no `bridge.go`). This closes **host-side today**, independent of 217's dark multi-slice rollout + device campaign.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-06 | Evidence Collector | bridge.go:572/592, config.go:206-210, feature_flags.go:80, feature_flags_runtime.go, p2p_bridge_client.dart:32-91, cmd/testpeer/commands.go:257 | replace-not-merge at a presence-blind struct; decode seam is the only observable layer | design verify→refute (done, wf_3aa586b1-383) |
| 2026-07-06 | Planner | 217 review fix-list §D4/§E1/§E2 | Go merge-at-decode + Dart pin; testpeer out of scope | emit matrix |
| 2026-07-06 | Reviewer (sufficiency) | this doc vs references/sufficiency-checklist.md | see self-check | — |
| 2026-07-06 | Arbiter | — | structurally sufficient; host-only | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | (cmd proving they FAIL) | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | (exact cmd) | reds now green | |
| | preservation GREEN | | (exact cmd) | sentinels green | |
| | named gates | | (exact cmd + counts) | gate green | |
| | QA (independent) | | (re-run cmds) | blocking: none/list | verdict |

## Source Of Truth
- Spec / intent: inline below (go-libp2p connectivity survival audit landmine #1).
- Gate definitions: `scripts/run_host_test_gates.sh` (Go node synthetic-path branches + Dart globs).
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (this is #219; 218 = SQLCipher).
- Go toolchain: **all Go commands require `GOTOOLCHAIN=go1.25.0`** (local default 1.26.4 panics quic-go).

## Session Classification
implementation-ready — fully live, host-only closure (no sim, no device, no DB migration).

## Exact Problem Statement
The Go bridge decodes the Dart feature-flags map into `*node.FeatureFlags` **wholesale** (`bridge.go:572,592`); `EffectiveFlags` (`config.go:206-210`) returns it verbatim (replace, not merge). A **partial** map ⇒ any omitted key unmarshals to the Go zero-value **`false`** — not the Go default — so e.g. a dropped `enableLibp2pLANDial` silently darkens LAN-direct dial fleet-wide. Safe *today* only because `defaultResilienceFeatureFlags()` (`p2p_bridge_client.dart:32-91`) always emits all 9 keys; there is **no** key-presence guard and **no** test pinning the Dart-map production defaults (`feature_flags_runtime_test.go` pins only the Go **fallback** `DefaultFeatureFlags()`). A regression flipping `p2p_bridge_client.dart:70` to `false`, or dropping a key, passes every Go test and surfaces only on-device.

What must improve: make "partial map ⇒ silent false" **structurally impossible** at the production decode seam, and pin the Dart-map defaults host-side so producer drift reds a test.
What must stay unchanged: the live full-map path (Dart always sends 9 keys) — merge ≡ replace there, **zero** behaviour change; explicit `false` overrides still win.

## Root Cause (verify → refute confirmed)
`bridge.go:572` decodes into `*node.FeatureFlags`, whose plain-`bool` fields cannot distinguish absent-from-false; `config.go:206` returns it wholesale. The decode seam is the **only** layer where key-presence is observable, so the merge fix belongs there — not in `EffectiveFlags` (which operates on a struct that already lost presence). The existing Dart assert `p2p_bridge_client_test.dart:162-165` is **tautological** (`payload == defaultResilienceFeatureFlags()`) — both sides share a dropped key, so it cannot catch producer drift. Blast radius = a single decode site: grep shows `params.FeatureFlags` is read only at `bridge.go:592` (no other reader relies on replace semantics; no bridge test references `featureFlags`).

Refuted / do-NOT-re-introduce: ✗ "fix it in `EffectiveFlags`" (presence already lost there); ✗ "the Dart tautology test already guards it" (it cannot see a dropped key).

## Real Scope
In scope: `bridge.go:572` field type → `map[string]bool`; new `MergeFeatureFlagsOverDefaults(present map[string]bool) node.FeatureFlags` in `feature_flags.go` (start from `DefaultFeatureFlags()`, overwrite only present keys); `bridge.go:592` nil→leave `nil` (preserves the `nil→DefaultFeatureFlags` contract via `EffectiveFlags`), else `&merged`; a behavioural switch/merge-completeness guard test; a Dart independent-literal 9-key polarity pin.
Out of scope (owner):
- **`cmd/testpeer/commands.go:257` `boolFromMap` reads only 5/9 keys** ⇒ sim-harness silently darkens `enableLibp2pLANDial`/`enableDeferredDirectAck`/`enableDcutrUpgrade`/`enableLibp2pLANMedia` → *sim-harness follow-up* (route testpeer through the same `MergeFeatureFlagsOverDefaults` helper). Not production; note so a sim run's darkened LAN-dial is not misread as a regression.
- **Dart↔Go default lockstep on future flag graduation** — a manual sync obligation (the Dart pin here + `feature_flags_runtime_test.go TestFeatureFlags_FdcTransportFlagsShipDarkUntilDeviceProof` must move together whenever a flag graduates).

## Files To Inspect Next
Production: `go-mknoon/bridge/bridge.go` (:572 field, :592 assignment), `go-mknoon/node/feature_flags.go` (:80 `DefaultFeatureFlags`), `go-mknoon/node/config.go` (:206-210 `EffectiveFlags` — read-only, unchanged), `lib/core/bridge/p2p_bridge_client.dart` (:32-91).
Tests: `go-mknoon/node/feature_flags_runtime_test.go` (Go fallback pins — preservation), `test/core/bridge/p2p_bridge_client_test.dart` (:162-165 weak assert), **NEW** `go-mknoon/node/feature_flags_merge_test.go`.
Harness: `scripts/run_host_test_gates.sh` (Go synthetic-path branches: addr-visibility template carries the `GOTOOLCHAIN` pin).

## Existing Tests Covering This Area
- `go-mknoon/node/feature_flags_runtime_test.go` — pins Go **fallback** `DefaultFeatureFlags()`/`EffectiveFlags` with **explicit full structs** (**exists**; does NOT exercise a partial map).
- `test/core/bridge/p2p_bridge_client_test.dart:162-165` — tautological payload==default assert (**exists, weak**); `:226-248` the only partial-`featureFlags:` caller.
- `go-mknoon/node/config_test.go` — timeout profiles only, **not** flags.
Missing gaps: partial-map darkening; independent 9-key Dart-map pin; merge-completeness.

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

1. `go-mknoon/node/feature_flags_merge_test.go`::**`TestMergeFeatureFlagsOverDefaults_OmittedKeyKeepsDefaultNotZeroValue`**
   - Tier: Go node unit (`GOTOOLCHAIN=go1.25.0`). RED on HEAD: `MergeFeatureFlagsOverDefaults` does not exist (compile-RED-by-absence).
   - GREEN asserts: `Merge(map{"enableMultiRelayRouting":false})` ⇒ `EnableLibp2pLANDial==true` AND `EnableSharedRelayBackend==true` (omitted ⇒ **default**, not false), `EnableMultiRelayRouting==false` (present override wins), `EnableDcutrUpgrade==false`/`EnableLibp2pLANMedia==false`.
   - Mutation that re-reds: start the helper from `FeatureFlags{}` (zero-value) instead of `DefaultFeatureFlags()` — reproduces HEAD's silent-false — flips `EnableLibp2pLANDial` to false.

2. `go-mknoon/node/feature_flags_merge_test.go`::**`TestMergeFeatureFlags_EveryStructFieldIsMergeable`** (behavioural completeness — §E2)
   - Tier: Go node unit. RED on HEAD: helper absent.
   - GREEN asserts (impl-agnostic — passes for a map-driven OR switch merge): iterate the `FeatureFlags` struct fields **by their json tag** via `reflect`; for each field, drive `Merge` with a single-key override map `{jsonTag: !defaultValue}` and assert **that field flips** in the result. So a field that no merge path handles (a future 10th flag added to the struct but not the merge) fails.
   - Mutation: add a struct field the merge does not handle → that field's single-key override does not flip → red. *(Do NOT assert "switch-case count == field count" — `reflect` cannot count source switch cases; assert the behaviour.)*

3. `test/core/bridge/p2p_bridge_client_test.dart`::**"defaultResilienceFeatureFlags pins exactly the 9 canonical keys with intended polarity"**
   - Tier: Dart core-host unit. On HEAD it **passes** (green drift-sentinel, not RED-by-absence).
   - GREEN asserts (against an **independent literal**, NOT the function): `keys.toSet()` == the literal 9-key set; `enableLibp2pLANDial==true`, `enableDcutrUpgrade==false`, `enableLibp2pLANMedia==false`, other six `==true`.
   - Mutation that re-reds: drop any key from `p2p_bridge_client.dart:33-90` (set/length mismatch — the exact landmine) OR flip any `defaultValue` (value mismatch).

4. **(MANDATORY — the ONLY behavioural test on the real `bridge.go` decode seam)** `go-mknoon/bridge/feature_flags_partial_map_test.go`::**`TestStartNode_PartialFeatureFlagsMap_KeepsGoDefaults`**
   - Tier: Go bridge integration (real node w/ fake relay addr, `GOTOOLCHAIN=go1.25.0`). RED on HEAD (real behaviour): drive `node:start` with a partial `featureFlags` JSON (omit `enableLibp2pLANDial`), assert `Status()["featureFlags"]["enableLibp2pLANDial"]==true` — fails on HEAD (`node.go:682` serializes via `featureFlagsStatusMap`; HEAD unmarshals the omitted key to false).
   - Mutation: revert the `bridge.go` merge → reds.
   - **Why mandatory (NOT belt-and-braces):** B01/B02 test the extracted pure helper `MergeFeatureFlagsOverDefaults` in ISOLATION; B04 is the only test that exercises the actual risky edit — the `bridge.go:572` field-type change AND the `:592` nil→`nil` / else `&merged` wiring — through a real partial-JSON decode. The `*node.FeatureFlags`→`map[string]bool` field-type change is compiler-enforced (an executor cannot silently keep wholesale-replace), but the nil-branch logic (does `nil` still preserve the `nil→DefaultFeatureFlags` contract?) and the real JSON decode stay ungated without B04. Host-only, no sim/device cost.

## Test Coverage Matrix  (zero empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| B01 merge keeps defaults | decode-seam merge | Go node unit | feature_flags_merge_test.go::TestMergeFeatureFlagsOverDefaults_OmittedKeyKeepsDefaultNotZeroValue | helper absent (compile-RED) | start from `FeatureFlags{}` | `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'FeatureFlag' -count=1)` | **Go synthetic-path, GOTOOLCHAIN-PINNED** — 5 edit sites in run_host_test_gates.sh (see below), addr-visibility template |
| B02 merge covers every field | behavioural reflection | Go node unit | feature_flags_merge_test.go::TestMergeFeatureFlags_EveryStructFieldIsMergeable | helper absent | add struct field w/o merge path | (same Go cmd as B01) | same pinned synthetic-path entry |
| B03 Dart 9-key polarity pin | producer-drift sentinel | Dart core-host unit | p2p_bridge_client_test.dart::"pins exactly 9 keys with polarity" | green pin (drift sentinel) | drop key / flip value at :33-90 | `flutter test test/core/bridge/p2p_bridge_client_test.dart` | AUTO (core glob); already in `ONE_TO_ONE_HOST_TESTS:46` |
| B04 partial-map behavioural (**MANDATORY**) | real node decode seam | Go bridge integration | feature_flags_partial_map_test.go::TestStartNode_PartialFeatureFlagsMap_KeepsGoDefaults | wholesale decode → false | revert bridge merge | `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run 'PartialFeatureFlags' -count=1)` | Go synthetic-path — its OWN `./bridge` const+branch `GO_BRIDGE_FEATUREFLAGS` (NOT the `./node` addr-visibility template reuse — B04 lives in `go-mknoon/bridge`), GOTOOLCHAIN-pinned |

**Go synthetic-path registration — enumerate ALL FIVE edit sites** (per fix-list §D4; the addr-visibility target at `run_host_test_gates.sh:81/185/276-277` is the template and is the only branch that carries `GOTOOLCHAIN=go1.25.0` — do NOT reuse the unpinned keyrotation `-run` alternation at `:273/:290`):
1. a `readonly GO_NODE_FEATUREFLAGS=...` **path const**;
2. a `readonly GO_NODE_FEATUREFLAGS_RUN='FeatureFlag'` **RUN-pattern const**;
3. an `is_go_node_featureflags()` **matcher**;
4. a `print_command_for_path` branch **and** a `run_path` branch (BOTH carry `GOTOOLCHAIN=go1.25.0 go test ./node -run "$GO_NODE_FEATUREFLAGS_RUN"`);
5. append the path to the **host-all plan block** (`:181-186`).
> `-run 'FeatureFlag'` sweeps the existing `TestFeatureFlags_*` superset for free (bonus preservation of the Go fallback pins).
>
> **B04 (`./bridge`) registers SEPARATELY (a SIXTH edit site, different package):** it lives in `go-mknoon/bridge`, not `./node`, so it needs its OWN path const `GO_BRIDGE_FEATUREFLAGS='go-mknoon/bridge/feature_flags_partial_map_test.go'` + `is_go_bridge_featureflags()` matcher + a print/run branch running `GOTOOLCHAIN=go1.25.0 go test ./bridge -run 'PartialFeatureFlags' -count=1` + a host-all line. Do NOT fold it into the `./node` FeatureFlag branch (different package AND different `-run` pattern).

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** N/A — a stateless pure decode/merge; no persisted or derived state.
- **Sibling-surface consistency:** the merge is the single decode site (`bridge.go:592`); `testpeer` is the parallel decode site and is explicitly out-of-scope (follow-up) — asymmetry named, not silent.
- **Destructive-action side-effects:** N/A — no delete/cleanup path.
- **Invariant re-verification under new transitions:** N/A — no new runtime transition; the merge changes only decode, and the live full-map path is behaviour-identical (merge ≡ replace when all keys present), locked by B01 (present override wins) + the preserved Go fallback pins.

## Invariants (locked by tests)
- **INV-B1 (merge-not-replace):** a partial feature-flags map keeps omitted keys at the Go default, never zero-value false → **B01** (+ behavioural **B04**).
- **INV-B2 (completeness):** every `FeatureFlags` field is reachable by the merge → **B02**.
- **INV-B3 (producer no-drift):** the Dart map ships exactly 9 keys with intended polarity → **B03**.
- INV-RED-FIRST + INV-MUTATION-VERIFIED apply to every row.

## Step-By-Step Implementation Plan
1. Add RED tests B01/B02 (compile-RED) + B03 (green pin) + **B04 (MANDATORY behavioural-RED on the real bridge seam)**; run focused cmds; confirm expected states.
2. Add `MergeFeatureFlagsOverDefaults(present map[string]bool) FeatureFlags` to `feature_flags.go` (start from `DefaultFeatureFlags()`; overwrite each present json-tagged key).
3. Change `bridge.go:572` field `FeatureFlags *node.FeatureFlags` → `FeatureFlags map[string]bool json:"featureFlags"`; at `:592`: `nil`⇒leave `cfg.FeatureFlags=nil` (EffectiveFlags→DefaultFeatureFlags), else `merged := node.MergeFeatureFlagsOverDefaults(params.FeatureFlags); cfg.FeatureFlags = &merged`. Leave `config.go:206 EffectiveFlags` untouched.
4. Add the Dart independent-literal pin to `p2p_bridge_client_test.dart`.
5. Register the Go merge test via the pinned synthetic-path (5 sites). Rerun direct → preservation → host-all. **Stop-if:** any caller relied on replace-wholesale (none found) → replan.

## Risks And Edge Cases
- **Cross-language default drift:** after the merge, omitted keys resolve to `DefaultFeatureFlags()`, which mirrors Dart intent **today** (verified key-for-key). If a flag graduates in Dart but the Go default lags and a partial map omits it, the merge yields the stale Go default and masks Dart intent — neither B01 nor B03 catches Dart↔Go default drift alone → documented manual lockstep obligation (Accepted Differences).
- **testpeer** silently darkens 4/9 keys (`commands.go:257`) — sim-harness only; out of scope; flagged so a darkened-LAN-dial sim run isn't misread.

## Device/Relay Proof Profile
host-only for closure. No sim, no device, no DB migration.

## Acceptance Gates  (literal — copy/paste)
```bash
# RED (before edits)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'MergeFeatureFlagsOverDefaults' -count=1)   # compile-RED (helper absent)
# Direct GREEN
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'FeatureFlag' -count=1)                      # expect: ok (merge + existing TestFeatureFlags_* superset)
flutter test test/core/bridge/p2p_bridge_client_test.dart                                              # expect: all pass
# Behavioural (MANDATORY — the real bridge decode seam; RED on HEAD before the merge)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run 'PartialFeatureFlags' -count=1)                # expect: ok
# Preservation sentinels
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestFeatureFlags_' -count=1)                # Go fallback pins unchanged
./scripts/run_host_test_gates.sh core-host-all                                                         # Dart pin runs in-gate
# Hygiene
flutter analyze            # 0 new
git diff --check
```

## Known-Failure Interpretation
- Expected RED: B01/B02 (compile-RED), B04 (behavioural RED on HEAD).
- Green sentinel: B03 (Dart pin — green until future drift).
- Scope drift (BLOCKING): any change to `config.go EffectiveFlags`, or editing `testpeer` here (follow-up owns it), or any Part A / wake-token edit.

## Done Criteria
- [ ] RED added first; B01/B02 compile-RED, B04 behavioural-RED for the documented reason.
- [ ] Mutation-verified (start-from-`FeatureFlags{}` re-reds B01; add-field re-reds B02; drop-key/flip re-reds B03).
- [ ] Direct GREEN + Go fallback pins preserved + core-host-all pass.
- [ ] Go merge test (B01/B02, `./node`) registered via the **pinned** synthetic-path (verified `GOTOOLCHAIN=go1.25.0` in both print/run branches); **B04 registered via its OWN `./bridge` pinned const+branch**.
- [ ] B04 (mandatory) RED on HEAD, green after the bridge merge; both print/run branches carry `GOTOOLCHAIN=go1.25.0`.
- [ ] `flutter analyze` 0 new; `git diff --check` clean.

## Scope Guard (hard "Do not")
- **Do not** touch `config.go EffectiveFlags` (presence already lost there — wrong layer).
- **Do not** edit `cmd/testpeer/commands.go` here (sim-harness follow-up owns it).
- **Do not** register the Go merge test on the **unpinned** keyrotation `-run` branch (`:273/:290`) — a FeatureFlag test that ever starts a node panics under Go 1.26.4 there.
- **Do not** touch any Part A / wake-token code.

## Accepted Differences / Intentionally Out Of Scope
- `testpeer` 5/9-key partial-map darkening — sim-harness follow-up (route through `MergeFeatureFlagsOverDefaults`).
- Dart↔Go default lockstep on flag graduation — manual sync obligation (B03 + `TestFeatureFlags_FdcTransportFlagsShipDarkUntilDeviceProof` move together). *(Optional hardening, not required for this slice: a single cross-parity assertion that the Dart 9-key set == the Go `FeatureFlags` json-tag set would red on graduation drift instead of relying on manual lockstep — B03 and `feature_flags_runtime_test.go` currently pin the two sides independently, so neither catches a divergence between them.)*

## Dependency Impact
- None inbound. Unblocks nothing in 217 (verified orthogonal — Part A sends no featureFlags). Ships independently, host-provable today.
- **Shared-file coordination with 217:** BOTH 219 and 217 add Go synthetic-path blocks to `scripts/run_host_test_gates.sh` (219 → `GO_NODE_FEATUREFLAGS` + `GO_BRIDGE_FEATUREFLAGS`; 217 → `GO_NODE_WAKETOKEN`) and BOTH append to the same host-all plan block. The consts/matchers/branches are disjoint, but the host-all block is a shared region. **Sequence: land 219 first** (host-only, ships now); 217 then re-reads the host-all block before appending its line. Same for the shared dirty `new-orbit` worktree — snapshot `git status --short` first.

## Reviewer Findings
From 217 review fix-list §E1 (split), §E2 (B02 behavioural not "switch-count reflection"), §D4 (pin Go registration + 5 edit sites). Design workflow `wf_3aa586b1-383` verified: `map[string]bool` change breaks no other reader (`params.FeatureFlags` read only at `bridge.go:592`); merge-at-decode is the only release-safe layer; B01 reproduces HEAD's silent-false; B04 is a genuine behavioural RED on unmodified HEAD.

## Arbiter Decision
Structural blockers: none. Host-only, fully live, immediately shippable. Verdict: **structurally sufficient — ready for execution.**

## Final Execution Verdict
Verdict: (pending execution) | Files changed: … | Tests run (+counts): … | Blocking: … | QA verdict: … | Non-blocking follow-ups (owner): testpeer merge-routing (sim-harness).
