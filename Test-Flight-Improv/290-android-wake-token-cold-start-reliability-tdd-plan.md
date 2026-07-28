# 290 - Android Wake-Token Cold-Start Reliability

Status: Wave-accepted — implementation-complete, Plan-green, and closed 2026-07-28
Type: Bug
Spec: free-text follow-up from DTR-13 live closure
Classification: implementation-complete; Plan-green / Wave-accepted
Closure tier: device
Owner authorization: `W4A-BLOCKERS-AUTH-01`

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-27 | Planner | `lib/core/debug/wake_token_directionality_e2e.dart`; `integration_test/scripts/android_wake_token_directionality_campaign.dart`; bridge wake-token tests | Confirmed cold-start race: inbox arrives 8–56 ms after bridge init and existing observer throws `StateError` | Add causal host seam tests, then paired Android proof |
| 2026-07-27 | Implementer | `P2PServiceImpl.storeInInboxDetailed`; node-state stream/disposal; exact readiness test | The shared inbox-store seam, not the debug observer, owns the race. Token-bearing stores now await node start inside the caller's original timeout; tokenless stores remain immediate, and disposal/closed-stream exits fail without bridge dispatch. | Rerun the exact live row against the final coherent source, then run affected gates. |
| 2026-07-28 | Historical live closer — point-in-time | Pixel 6 `21071FDF600CSC`; API-35 `emulator-5560`; final Sims report and proof artifact | The then-current coherent-source build and `android.wake_token_directionality` row passed both assertions at source digest `e2ab677e61688505cf0af0a1b3b3d5e62c4a7fc9fb94cc549b0c6bc0c0237f8e` | At this point, retain Plan-green as pending until `core-host-all`, final diff hygiene, Graphify, and Wave aggregate `host-all` finish |
| 2026-07-28 | Terminal closer | independently reverified final Sims report/proof; late wake-fixture RED/GREEN; `core-host-all`; strict analysis; Graphify; Wave 4A aggregate and tested-tree archive | A later order-dependent fixture failure was proven test-only and corrected without changing production readiness behavior; the final coherent source, all closure gates, and the full Wave aggregate passed | Plan 290 is Plan-green and Wave-accepted; no remaining blocker |

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
  snapshot; the final Wave 4A Graphify refresh remained pending at this
  point-in-time and is superseded by the terminal receipt below.
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
  [x] `core-host-all`, final diff hygiene, Graphify, and Wave aggregate
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
| 2026-07-27 | RED — causal shared-store semantics | new `test/core/debug/wake_token_directionality_readiness_test.dart`; intermediate shared-store implementation | Exact three-test path was non-green: forwarded timeout was not reduced, tokenless stores incorrectly waited/timed out, and disposal surfaced a stream `StateError` | The RED distinguishes true shared readiness/deadline/disposal ownership from a short reread or unconditional retry | causal RED; no environment blocker | implement token-bearing-only wait with one budget and safe closure |
| 2026-07-27 | GREEN — readiness/deadline/disposal | `lib/core/services/p2p_service_impl.dart`; exact readiness test; wake sentinels and campaign host contract | Combined focused set -> 17 pass; targeted analysis -> zero issues | Token-bearing stores await node start, dispatch once with remaining time, tokenless stores remain immediate, and disposal/closed-stream returns classified failure without dispatch | focused-host-green | run final coherent-source Sims row and affected gates |
| 2026-07-27 | Historical live PASS — superseded as closure evidence by later source changes | physical Android `21071FDF600CSC`; emulator `emulator-5560`; `build/sims/operator-inputs/wave4a-wake-token-pass-report.json` | build plus live scenario PASS; two assertions; report SHA-256 `1b958612b7eb1c30c5806654c79fafed2ba7dac3e943c93112953b89aa2bccb4` | A coherent intermediate snapshot proved the relay registration, receiver store, and accepted attachment shared one digest | not final current-source evidence because source changed afterward | rerun the same exact row on the final coherent source |
| 2026-07-28 | Historical point-in-time coherent-source live PASS | Pixel 6 `21071FDF600CSC`; API-35 `emulator-5560`; `build/sims/operator-inputs/wave4a-wake-token-final-pass-report.json` | build PASS plus `android.wake_token_directionality` PASS with two assertions; report SHA-256 `7da2c832c98e9954580c46c1244fe5123869ae31083bea6cbcba1257d63d9557`; proof-artifact SHA-256 `fe2721f78e75be0adba8a1320ada3840276cbee12de43fe807abfd07013180b2` | Report and proof share coherent source digest `e2ab677e61688505cf0af0a1b3b3d5e62c4a7fc9fb94cc549b0c6bc0c0237f8e`; the then-current cold-start/re-entry boundary was green | live-green, not yet Plan-green at this point | finish the explicitly pending closure gates |
| 2026-07-28 | Historical point-in-time focused and shared gate PASS | five exact wake commands; adapter/runner contracts; Wave 4A shared gates; strict analysis | wake-focused total 140/140; relevant adapter/runner contracts PASS; `runtime-roots` 20/20 over 1,026 files with trustworthy/no-drift result in 79.75 s; completeness 1,346/1,346; `1to1` 2,441 Flutter plus relay Go gates in 185.83 s; `intro` 300 in 21.10 s; `groups` 3,239 Flutter plus 13 focused Go tests and relay toolchain in 322.03 s; architecture boundaries six tests over 1,026 sources with the 182-dependency/24-placement baseline and zero issues; Sims contracts 38/38 in 1,296.64 s; `./scripts/check_flutter_analyze_strict.sh` exited 0 in 405.8 s with zero errors, warnings, or infos and three reviewed suppression occurrences across three package roots; no causal failure | Available focused, family, inventory, architecture, Sims-contract, and strict-analysis evidence was green | Plan-green remained withheld at this point | await `core-host-all`, final `git diff --check`, Graphify, and Wave aggregate `host-all` |
| 2026-07-28 | Later causal RED — legacy fixture order leak | standalone legacy wake-attachment fixture | Standalone execution failed 0/2 with `INBOX_STARTUP_NOT_READY`: the fixture never started services, so predecessor ordering had hidden the missing lifecycle setup | This was a fixture defect, not a regression in `storeInInboxDetailed`; production readiness behavior remained unchanged | causal test-only fixture defect; no production blocker | correct only the fixture lifecycle |
| 2026-07-28 | Superseding fixture/focused GREEN | legacy wake attachment fixture; readiness fixture; predecessor pair; final focused set | The corrected fixture returned the full started-node response, explicitly started all four services, and registered disposal; readiness plus fixture passed 5/5, standalone passed 2/2, the predecessor pair passed 125/125, and the final focused combined set passed 14/14 | The order leak is closed without a production behavior change | focused-green; no blocker | rerun the final coherent Sims receipt |
| 2026-07-28 | Superseding final coherent-source live PASS | Pixel 6 `21071FDF600CSC`; API-35 `emulator-5560`; `build/sims/operator-inputs/wave4a-wake-final-coherent-report.json`; `build/sims/proofs/android.wake_token_directionality/android.wake_token_directionality-1785201503190901-53950.json` | build PASS and both `android.wake_token_directionality` assertions PASS; report SHA-256 `0a286828746388173e6c489b864cad57b1defda10f17fffb889b7577556827e2`; proof SHA-256 `f5067faf9b1bdca64480fb39fca44fd4c295f8ff87e848aab55998dcf0771bc5` | Report and proof were independently reverified against final coherent Sims source digest `73f4339412d85b7846f45894a122aa174f87141771fa121666a3ff06a3f0e825` | live boundary accepted | close the terminal host/graph/Wave receipts |
| 2026-07-28 | Plan-green / Wave acceptance | final coherent tested tree; core family; strict analysis; Graphify; full Wave 4A `host-all`; evidence archive | `core-host-all` passed all 362 items and 2,825 Flutter tests plus both renderer modes; strict analysis and diff hygiene passed; Graphify refreshed; the full aggregate passed 1,265 items with 12,798 pass, one skip, zero failures, and all eight Go legs PASS | The accepted evidence is bound to tested tree `14a72da9b5b702b37466e155a77007e0335d0559` and archived under `Test-Flight-Improv/evidence/dtr-wave4a/README.md` | Plan-green / Wave-accepted; no blocker | Complete |

## Terminal Current-Source And Wave-Acceptance Evidence

- Final live receipt:
  `build/sims/operator-inputs/wave4a-wake-final-coherent-report.json`,
  SHA-256
  `0a286828746388173e6c489b864cad57b1defda10f17fffb889b7577556827e2`;
  proof
  `build/sims/proofs/android.wake_token_directionality/android.wake_token_directionality-1785201503190901-53950.json`,
  SHA-256
  `f5067faf9b1bdca64480fb39fca44fd4c295f8ff87e848aab55998dcf0771bc5`.
  The build and both assertions passed at final coherent Sims source digest
  `73f4339412d85b7846f45894a122aa174f87141771fa121666a3ff06a3f0e825`;
  report and proof were independently reverified.
- The late standalone-fixture 0/2 RED was caused by omitted service startup,
  not production readiness behavior. The corrected fixture returns the full
  started-node response, starts all four services, and registers disposal.
  Readiness plus fixture is 5/5, standalone is 2/2, the predecessor pair is
  125/125, and the final focused combined set is 14/14.
- Exact `core-host-all`: 362 items (361 Dart plus the renderer manifest),
  2,825 Flutter tests PASS, renderer profile/release PASS, final PASS in about
  428 seconds; log SHA-256
  `b99f1c1989e01429f0fe846c8f0bd46c1bf30478e1d3c97cf2e6db2747e92440`.
- `./scripts/check_flutter_analyze_strict.sh`: PASS, exit 0, zero diagnostics,
  three suppressions across three roots, 306.8 seconds; log SHA-256
  `196b51c6554d0235ee187117f529daf6dab39fed469f61b11b7afa22637d656b`.
  Final `git diff --check` also passed.
- Incremental Graphify: 13 changed, 2,869 unchanged, zero deleted; 62,934
  nodes / 94,552 edges; overlay 1,447 files / 14,171 tests / 1,087 production
  targets. Graph SHA-256
  `af9593753ea0236ca568db561d8d6af2c0eacefb2ac7689b073483037c080b53`;
  overlay SHA-256
  `fc87b54355ea8eea9fb9b726cbd50c088c3c0d805da065c8c2acfa2d45cbe7cb`.
- Wave aggregate command
  `./scripts/run_host_test_gates.sh host-all --continue-on-failure --batch-flutter --concurrency 4 --reporter failures-only`
  passed 1,265 items (1,257 Flutter paths plus eight Go legs): 12,798 pass,
  one skip, zero fail; all eight Go legs PASS; final PASS, exit 0, 1,136
  seconds.
- Tested-tree identity: base `765be74523b25ce592ff200ff435653b35c66b4d`;
  tree `14a72da9b5b702b37466e155a77007e0335d0559`; synthetic commit
  `669c7039846f321a8171b63df09e087e43b1f319`; tag
  `dtr-wave4a-tested-tree-20260728`. The shared index remained unchanged at
  SHA-256
  `9aa55ac41a8db648ae4a8eb12a95820c0d3882ce09a01d1fa94ead8ef1c670dc`.
  The companion iOS report is also green on the same Sims digest, SHA-256
  `1dae730ef1a55c9328ad922b9fa95b68804ffa8ce667652bfbb627e149cee5fa`.
- Wave archive: `Test-Flight-Improv/evidence/dtr-wave4a/README.md`; original
  aggregate host log SHA-256
  `d61df5a5ab9949f44887bcf32c1e877dcc39a10ef110682e066bfb6cbbb4f899`;
  gzip SHA-256
  `428e449eabfabda52828461df64badee532c6905673375017745c3b5280a7434`.
  Terminal verdict: **Plan-green / Wave-accepted**.

## Reviewer Findings

Historical verdict: **plan-fixes-required** (revised to address proof ownership
and exact source registration); **resolved** by the required updates below.
The terminal receipts above supersede the prior pending closure state; no
Plan-290 or Wave-4A blocker remains.

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
