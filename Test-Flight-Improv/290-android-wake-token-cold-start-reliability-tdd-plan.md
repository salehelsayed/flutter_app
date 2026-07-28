# 290 - Android Wake-Token Cold-Start Reliability

Status: implementation-complete / focused-host-green / coherent-source live-green; remaining closure gates pending
Type: Bug
Spec: free-text follow-up from DTR-13 live closure
Classification: implemented; closure pending
Closure tier: device
Owner authorization: `W4A-BLOCKERS-AUTH-01`

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-27 | Planner | `lib/core/debug/wake_token_directionality_e2e.dart`; `integration_test/scripts/android_wake_token_directionality_campaign.dart`; bridge wake-token tests | Confirmed cold-start race: inbox arrives 8–56 ms after bridge init and existing observer throws `StateError` | Add causal host seam tests, then paired Android proof |
| 2026-07-27 | Implementer | `P2PServiceImpl.storeInInboxDetailed`; node-state stream/disposal; exact readiness test | The shared inbox-store seam, not the debug observer, owns the race. Token-bearing stores now await node start inside the caller's original timeout; tokenless stores remain immediate, and disposal/closed-stream exits fail without bridge dispatch. | Rerun the exact live row against the final coherent source, then run affected gates. |
| 2026-07-28 | Live closer | Pixel 6 `21071FDF600CSC`; API-35 `emulator-5560`; final Sims report and proof artifact | The final coherent-source build and `android.wake_token_directionality` row passed both assertions at source digest `e2ab677e61688505cf0af0a1b3b3d5e62c4a7fc9fb94cc549b0c6bc0c0237f8e` | Retain Plan-green as pending until `core-host-all`, final diff hygiene, Graphify, and Wave aggregate `host-all` finish |

## Problem And Evidence

- Behavior: a cold-start Android receiver must accept an inbox `store` carrying a wake token while bridge readiness is still settling.
- Impact: current behavior returns `INBOX_ERROR` and loses the notification path.
- Confirmed root cause: the shared `P2PServiceImpl.storeInInboxDetailed`
  path could dispatch a token-bearing `inbox:store` before node startup
  completed. `WakeTokenDirectionalityE2E` surfaced the resulting
  `INBOX_ERROR`/`StateError`; it was not the correct repair owner.
- Existing coverage: `test/core/bridge/p2p_bridge_client_wake_attach_test.dart` proves token attachment only; it does not prove cold-start readiness ordering.
- Added coverage: deterministic token-bearing readiness waiting, preservation
  of immediate tokenless dispatch, one original deadline across readiness plus
  bridge dispatch, and closed-stream/disposal completion without dispatch.
  Final coherent-source Android cold-start delivery now passes both live
  assertions on the available Android pair.
- Refuted: missing relay/provider inputs; live EC2 and campaign evidence are available.
- Resolved ownership: the shared `P2PServiceImpl` store seam owns the wait.
  It uses the caller's existing timeout as one absolute budget and forwards
  only the remaining milliseconds to the bridge; there is no new independent
  retry window.

## Graph Grounding Snapshot

- Graph fingerprint / freshness at planning: `d4a9a72d5be10723`, current at that
  snapshot; the final Wave 4A Graphify refresh remains pending.
- Query / profile: `python3 graphify-arch/tdd_context.py query "android_wake_token_directionality_campaign.dart WakeTokenDirectionalityE2E" --profile tdd --budget 700`.
- Anchors: `android_wake_token_directionality_campaign.dart`; `lib/core/debug/wake_token_directionality_e2e_protocol.dart`.
- Surfaced proof/gate files: `integration_test/scripts/android_wake_token_directionality_campaign.dart`; `test/integration/android_wake_token_directionality_campaign_test.dart`.
- Graph gaps: readiness implementation requires targeted source verification.

## Scope Contract And Guard

In scope:
- readiness ordering and a bounded wait for token-bearing inbox delivery in
  the shared store seam;
- one timeout budget spanning readiness and bridge dispatch;
- safe node-state stream closure and service disposal.

Must preserve:
- `test/core/bridge/p2p_bridge_client_wake_attach_test.dart` token byte contract; GREEN sentinel.
- normal inbox delivery without wake tokens; GREEN sentinel.

Hard `Do not`:
- Do not change relay protocol, token schema, build profiles, or DTR-13 composition-root boundaries.

Deferred / accepted difference:
- None; product owner follow-up required for behavior change.

Dependencies: existing Android relay campaign and current wake-token bridge contract.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-01 | Wait to dispatch a token-bearing inbox store until the node is ready, exactly once and inside the original timeout | `test/core/debug/wake_token_directionality_readiness_test.dart::buffers store until ready` | host integration, fake bridge and node-state transition | RED: the original implementation had no shared wait; an intermediate attempt forwarded a fresh timeout -> GREEN dispatches once after readiness and gives the bridge less than the original timeout | remove the readiness wait or reset the bridge timeout -> TC-01 red | `flutter test test/core/debug/wake_token_directionality_readiness_test.dart`; AUTO core |
| TC-02 | Preserve token attachment and null omission | `test/core/bridge/p2p_bridge_client_wake_attach_test.dart` | host sentinel | GREEN sentinel | include empty token field -> sentinel red | exact test; AUTO core |
| TC-03 | Cold-start real delivery and re-entry | `integration_test/scripts/android_wake_token_directionality_campaign.dart` scenario `android.wake_token_directionality` | paired device: physical Android + Android emulator, automated | original device proof failed `INBOX_ERROR`; an intermediate coherent snapshot passed two assertions -> final coherent source again observed one stored message after cold start/re-entry without `StateError` or duplicate claim | bypass readiness wait -> device proof red | `./scripts/run_test_gates.sh sims major --only android.wake_token_directionality`; `classify_path`/scenario |
| TC-04 | Tokenless stores do not inherit the wake-token startup wait | `test/core/debug/wake_token_directionality_readiness_test.dart::normal tokenless store dispatches without waiting for startup` | host integration, fake bridge | an intermediate wait applied to every store and timed out -> tokenless store dispatches immediately and omits `wakeToken` | wait unconditionally -> TC-04 red | exact readiness test path; AUTO core |
| TC-05 | Disposal or node-state stream closure completes a buffered store as a classified failure without dispatch or `StateError` | `test/core/debug/wake_token_directionality_readiness_test.dart::disposal completes a buffered store as failed without dispatch` | host integration, fake bridge | intermediate implementation surfaced stream `StateError` -> failed outcome and zero bridge calls | remove stream-close/disposal handling -> TC-05 red | exact readiness test path; AUTO core |

## Implementation Steps

1. Snapshot dirty tree and add TC-01 before production edits.
2. Implement the bounded readiness wait in the shared
   `P2PServiceImpl.storeInInboxDetailed` seam; preserve exactly-once delivery,
   tokenless behavior, one original timeout, and classified failure diagnostics.
3. Run focused GREEN, sentinels, device campaign, analysis, and hygiene.

## Risks And Blind Spots

- Duplicate delivery -> TC-01 asserts exactly once.
- Retry/send sibling asymmetry -> TC-02 preserves existing attachment.
- Re-entry after process restart -> TC-03 cold-start proof.
- Double timeout -> TC-01 asserts that bridge dispatch receives only the
  remaining original budget.
- Disposal race -> TC-05 requires failed completion without dispatch.

## Gate Cadence

- Per-plan: TC-01/02, affected core family, strict analysis, and the Android device scenario.
- Full `host-all` is deferred to the dependency wave and final release closure.
- Shared path: direct `flutter test test/integration/android_wake_token_directionality_campaign_test.dart`.

## Acceptance Gates

```bash
git status --short
flutter test test/core/debug/wake_token_directionality_readiness_test.dart --plain-name 'buffers store until ready' # expected RED pre-edit
flutter test test/core/debug/wake_token_directionality_readiness_test.dart
flutter test test/core/services/p2p_service_impl_test.dart
flutter test test/core/bridge/p2p_bridge_client_wake_attach_test.dart
flutter test test/core/debug/wake_token_directionality_e2e_test.dart
flutter test test/integration/android_wake_token_directionality_campaign_test.dart
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh runtime-roots
./scripts/run_test_gates.sh sims major --only android.wake_token_directionality
./scripts/run_host_test_gates.sh core-host-all --batch-flutter --concurrency 4 --reporter failures-only
./scripts/check_flutter_analyze_strict.sh
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-01 fails on pre-ready observer `StateError`.
- Availability note: an unavailable Android target or version is N/A under
  repository policy, not an environment blocker; the required live pair was
  available for the recorded run.
- [x] causal RED/GREEN recorded; [x] final coherent-source paired proof passes;
  [x] focused and affected shared gates recorded; [x] strict analysis;
  [ ] `core-host-all`, final diff hygiene, Graphify, and Wave aggregate
  `host-all`.

## Handoff

- First causal RED: `flutter test test/core/debug/wake_token_directionality_readiness_test.dart --plain-name 'buffers store until ready'`.
- Preservation: `flutter test test/core/bridge/p2p_bridge_client_wake_attach_test.dart`.
- Manual registration: existing `android.wake_token_directionality`; no new scenario.
- Migration: none.
- Boundary closure: physical Android + Android emulator.

## Exact Inverse Rollback Contract

Restore only the Plan-290 execution-start
`storeInInboxDetailed`/node-readiness/deadline/disposal hunks in
`lib/core/services/p2p_service_impl.dart`, and remove only
`test/core/debug/wake_token_directionality_readiness_test.dart`. Do not restore
the shared service file wholesale. Preserve wake-token bytes/null omission,
bridge APIs, the `android.e2e.wake_token` profile and defines, DTR-13
composition, issuer/observer behavior, relay/native code, schemas, and every
unrelated dirty-tree edit.

After the inverse, run exactly:

```bash
flutter test test/core/services/p2p_service_impl_test.dart
flutter test test/core/bridge/p2p_bridge_client_wake_attach_test.dart
flutter test test/core/debug/wake_token_directionality_e2e_test.dart
flutter test test/integration/android_wake_token_directionality_campaign_test.dart
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh runtime-roots
./scripts/run_host_test_gates.sh core-host-all --batch-flutter --concurrency 4 --reporter failures-only
./scripts/check_flutter_analyze_strict.sh
git diff --check
```

The same rollback must withdraw Plan 290's focused-host/Plan-green status and
any current-source wake live-row claim from Plan 289, the roadmap, and the
index. An archived PASS remains historical evidence only for its recorded
source digest.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-27 | RED — causal shared-store semantics | new `test/core/debug/wake_token_directionality_readiness_test.dart`; intermediate shared-store implementation | Exact three-test path was non-green: forwarded timeout was not reduced, tokenless stores incorrectly waited/timed out, and disposal surfaced a stream `StateError` | The RED distinguishes true shared readiness/deadline/disposal ownership from a short reread or unconditional retry | implement token-bearing-only wait with one budget and safe closure |
| 2026-07-27 | GREEN — readiness/deadline/disposal | `lib/core/services/p2p_service_impl.dart`; exact readiness test; wake sentinels and campaign host contract | Combined focused set -> 17 pass; targeted analysis -> zero issues | Token-bearing stores await node start, dispatch once with remaining time, tokenless stores remain immediate, and disposal/closed-stream returns classified failure without dispatch | focused-host-green | run final coherent-source Sims row and affected gates |
| 2026-07-27 | Historical live PASS — superseded as closure evidence by later source changes | physical Android `21071FDF600CSC`; emulator `emulator-5560`; `build/sims/operator-inputs/wave4a-wake-token-pass-report.json` | build plus live scenario PASS; two assertions; report SHA-256 `1b958612b7eb1c30c5806654c79fafed2ba7dac3e943c93112953b89aa2bccb4` | A coherent intermediate snapshot proved the relay registration, receiver store, and accepted attachment shared one digest | not final current-source evidence because source changed afterward | rerun the same exact row on the final coherent source |
| 2026-07-28 | Final coherent-source live PASS | Pixel 6 `21071FDF600CSC`; API-35 `emulator-5560`; `build/sims/operator-inputs/wave4a-wake-token-final-pass-report.json` | build PASS plus `android.wake_token_directionality` PASS with two assertions; report SHA-256 `7da2c832c98e9954580c46c1244fe5123869ae31083bea6cbcba1257d63d9557`; proof-artifact SHA-256 `fe2721f78e75be0adba8a1320ada3840276cbee12de43fe807abfd07013180b2` | Report and proof share coherent source digest `e2ab677e61688505cf0af0a1b3b3d5e62c4a7fc9fb94cc549b0c6bc0c0237f8e`; the final current-source cold-start/re-entry boundary is green | live-green, not yet Plan-green | finish the explicitly pending closure gates |
| 2026-07-28 | Focused and shared gate PASS | five exact wake commands; adapter/runner contracts; Wave 4A shared gates; strict analysis | wake-focused total 140/140; relevant adapter/runner contracts PASS; `runtime-roots` 20/20 over 1,026 files with trustworthy/no-drift result in 79.75 s; completeness 1,346/1,346; `1to1` 2,441 Flutter plus relay Go gates in 185.83 s; `intro` 300 in 21.10 s; `groups` 3,239 Flutter plus 13 focused Go tests and relay toolchain in 322.03 s; architecture boundaries six tests over 1,026 sources with the 182-dependency/24-placement baseline and zero issues; Sims contracts 38/38 in 1,296.64 s; `./scripts/check_flutter_analyze_strict.sh` exited 0 in 405.8 s with zero errors, warnings, or infos and three reviewed suppression occurrences across three package roots; no causal failure | Available focused, family, inventory, architecture, Sims-contract, and strict-analysis evidence is green | Plan-green remains withheld | await `core-host-all`, final `git diff --check`, Graphify, and Wave aggregate `host-all` |

## Current-Source Evidence And Remaining Placeholders

- Final live receipt: `build/sims/operator-inputs/wave4a-wake-token-final-pass-report.json`,
  SHA-256 `7da2c832c98e9954580c46c1244fe5123869ae31083bea6cbcba1257d63d9557`;
  proof-artifact SHA-256
  `fe2721f78e75be0adba8a1320ada3840276cbee12de43fe807abfd07013180b2`;
  coherent source digest
  `e2ab677e61688505cf0af0a1b3b3d5e62c4a7fc9fb94cc549b0c6bc0c0237f8e`.
- Focused/current shared receipts are PASS with the exact counts and durations
  recorded in the 2026-07-28 progress row above.
- `./scripts/check_flutter_analyze_strict.sh`: **PASS** — exit 0 in 405.8 s;
  zero errors, warnings, or infos; three reviewed suppression occurrences
  across three package roots; no causal failure.
- Remaining placeholders; no Plan-green claim is made:
  - `./scripts/run_host_test_gates.sh core-host-all --batch-flutter --concurrency 4 --reporter failures-only`: **running/pending**.
  - Final `git diff --check`: **pending**.
  - Final Wave 4A Graphify refresh: **pending**.
  - Wave 4A aggregate `host-all`: **pending centrally in Plan 289 and the roadmap**.

## Reviewer Findings

Historical verdict: **plan-fixes-required** (revised to address proof ownership
and exact source registration); **resolved** by the required updates below.
Current closure remains pending only on the explicitly named final gates.

- L1 clear: the DTR-13 campaign evidence and current wake-token sources support
  the cold-start race classification.
- L2 tighten: TC-01 must assert exactly one durable inbox application and no
  `StateError`, not merely eventual readiness.
- L3 tighten: implementation must cover both foreground startup and notification
  callback entrypoints; the shared bridge seam is the only acceptable owner.
- L4 clear: the existing Sims scenario is registered; the new host test is
  AUTO under `test/core`.
- L5 tighten: TC-03 must include restart/re-entry and duplicate suppression.

Required updates applied: TC-01's assertion and TC-03's restart/duplicate
acceptance are now explicit implementation obligations; no production scope
or device topology changed.
