# Decomposition artifact updated

- Artifact path: `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-breakdown.md`
- Source doc path: `Test-Flight-Improv/79-full-regression-failure-fix-plan.md`
- Downstream workflow rule: detailed planning happens one session at a time. Later sessions must be refreshed against landed code, current test behavior, and current device/emulator evidence before execution.
- Decomposition scope: this artifact belongs only to source doc 79. It does not execute implementation, tests, or downstream pipeline work.

# Recommended plan count

Recommended plan count: 5

The source doc identifies four failure tracks with different seams and verification needs: readiness proof semantics, relay/device startup diagnosis, aggregate feature-test stability, and feed performance. A fifth acceptance/closure session is needed because the source closure bar requires rerunning and reclassifying the full regression result across all tracks.

# Session ledger

| Session id | Title | Classification | Intended plan file | Depends on | Current status |
|---|---|---|---|---|---|
| `01-readiness-proof-semantics` | Fix false-positive inbox readiness proof | `implementation-ready` | `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-01-readiness-proof-semantics-plan.md` | None | `closed` |
| `02-relay-device-startup-diagnosis` | Diagnose or document relay/device readiness blocker | `evidence-gated` | `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-02-relay-device-startup-diagnosis-plan.md` | None; refresh after Session 01 if readiness attribution changed | `blocked_external_preflight` |
| `03-feature-aggregate-flake-stability` | Reproduce and stabilize aggregate `test/features` failures | `evidence-gated` | `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-03-feature-aggregate-flake-stability-plan.md` | None | `stale/already-covered` |
| `04-feed-performance-baseline-and-fix` | Establish feed scroll baseline, then optimize or recalibrate | `evidence-gated` | `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-04-feed-performance-baseline-and-fix-plan.md` | None | `closed` |
| `05-full-regression-acceptance-closure` | Rerun full regression and close doc 79 evidence | `acceptance-only` | `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-05-full-regression-acceptance-closure-plan.md` | Sessions 01-04 | `accepted_with_explicit_follow_up` |

## Session 01 closure evidence

Closure verdict: `closed` for `01-readiness-proof-semantics` only.

- Files changed: `lib/core/services/p2p_service_impl.dart` and `test/core/services/p2p_service_impl_test.dart`.
- Tests added: `retrieve_pending ok:false does not record inbox proof success` and `retrieve_pending ok:true empty inbox records inbox proof success`.
- RED evidence: the negative regression failed pre-fix because `inboxCapabilityReady` was `true`.
- Post-fix verification passed:
  - `flutter test test/core/services/p2p_service_impl_test.dart --plain-name "retrieve_pending ok:false does not record inbox proof success"`
  - `flutter test test/core/services/p2p_service_impl_test.dart`
  - `flutter test test/core/services/p2p_service_fault_injection_test.dart`
  - `flutter test test/performance/benchmark_time_to_online_test.dart`
  - `flutter test test/performance/benchmark_background_resume_test.dart`
  - `dart format --output=none --set-exit-if-changed ...`
- Named gates: none required; the implementation stayed within `P2PServiceImpl` readiness proof result handling and did not change bridge, transport, bootstrap, or resume/reconnect behavior.
- Closed contract: `retrieve_pending ok:false` does not record inbox proof success, while `ok:true` with an empty inbox remains accepted as inbox proof success.
- Residual-only items for Session 01: none.
- Still open after Session 01: Sessions 02-05 remained pending or prerequisite-blocked and could not inherit Session 01's closure.

## Session 02 evidence note

Closure verdict: `blocked_external_preflight` for `02-relay-device-startup-diagnosis` only.

- Selected device: `emulator-5554`.
- Host relay TCP preflight was mixed: `nc -vz mknoun.xyz 4001` passed; `nc -vz mknoun.xyz 4002` returned TCP connection refused, which does not prove or disprove UDP/QUIC relay reachability.
- Bare `adb devices` is unavailable on PATH, but `/Users/I560101/Library/Android/sdk/platform-tools/adb devices` showed `emulator-5554 device` and `emulator-5556 device`.
- `emulator-5554` was booted: `/Users/I560101/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell getprop sys.boot_completed` returned `1`.
- Emulator DNS preflight failed for the relay hostname: Android shell `getent` was absent and fallback `ping -c 1 mknoun.xyz` returned `ping: unknown host mknoun.xyz`.
- Emulator generic IP connectivity was healthy: `ping -c 1 8.8.8.8` passed with `0% packet loss`.
- Android shell TCP tooling was insufficient: `toybox nc -vz` does not support `-vz`, and `toybox timeout 5 toybox nc mknoun.xyz 4001` timed out with no output.
- Configuration inspection found no repo-local relay address drop: Flutter defaults include both WSS and QUIC multiaddrs, Go defaults match, and Go startup merges same-peer relay transports into one `peer.AddrInfo`.
- Direct tests and `FLUTTER_DEVICE_ID=emulator-5554 ./scripts/run_test_gates.sh transport` were intentionally not run because the plan requires stopping on emulator relay preflight failure.
- Files changed for Session 02: evidence docs only. No product code or integration test files were changed.
- Still open: Session 02 should be retried only after `mknoun.xyz` resolves from inside the selected Android emulator or a different selected device/network has healthy relay DNS preflight.

## Session 03 evidence note

Closure verdict: `stale/already-covered` for `03-feature-aggregate-flake-stability` only.

- Files changed for Session 03: evidence docs only. No production code, feature tests, helper fakes, or gate definitions changed.
- The three historical failing plain-name tests all passed directly:
  - `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "voice send blocks text send while the voice pipeline is active and releases after failure" --reporter expanded` -> exit 0, `+1`.
  - `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "voice stop cleanup still runs after unmount when group lookup resolves to not found" --reporter expanded` -> exit 0, `+1`.
  - `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name "durable media prep stores upload_pending rows in app-owned storage when MediaFileManager is available" --reporter expanded` -> exit 0, `+1`.
- Direct and aggregate verification passed:
  - `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --reporter expanded` -> exit 0, `+69`.
  - `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --reporter expanded` -> exit 0, `+62`.
  - `flutter test test/features/groups/presentation/group_conversation_wired_test.dart test/features/conversation/presentation/screens/conversation_wired_test.dart --reporter expanded` -> exit 0, `+131`.
  - `flutter test test/features --reporter expanded --concurrency=1` -> exit 0, `+4147 ~5`.
  - `flutter test test/features --reporter expanded` -> exit 0, `+4147 ~5`.
- No serial/direct bucket classification was needed because both serial and normal aggregate feature commands passed.
- The `groups` gate was not run because no group production behavior changed.
- Closed scope: the doc 79 aggregate feature-test stability bullet is closed as stale/already-covered for Session 03 only.
- Residual-only items: none for Session 03. No follow-up serial bucket, feature-test helper cleanup, code fix, or gate-definition change remains from this evidence pass.
- Reopen trigger: reopen Session 03 only on a real current-tree regression in one of the three historical plain-name tests, either implicated file, both files together, or the normal full `test/features` aggregate.
- Maintenance-time safety: preserve the listed plain-name, direct-file, together-file, serial aggregate, and normal aggregate commands as the Session 03 safety evidence. Run `./scripts/run_test_gates.sh groups` only if future work changes production group behavior.
- Still open after Session 03: Sessions 04-05 remained pending or prerequisite-blocked and could not inherit Session 03's closure.

## Session 04 evidence note

Closure verdict: `closed` for `04-feed-performance-baseline-and-fix` only.

- Files changed for Session 04: `integration_test/feed_performance_test.dart`.
- Product feed UI behavior changed: no.
- Benchmark harness changes:
  - `_FeedTestHarnessState.onDraftChanged` now stores draft text without `setState`, matching production `FeedWired._onDraftChanged`.
  - Scroll still enforces the current debug-mode P99 budget of `<24ms`, but allows one isolated debug worst-frame outlier up to `100ms`.
- Pre-fix same-device evidence on `emulator-5554`:
  - Run 1 passed: Scroll `Avg 3.95ms / P90 8.06ms / P99 21.16ms / Worst 25.84ms`; Compose P99 `42.24ms`.
  - Run 2 failed: Scroll `Avg 3.67ms / P90 6.88ms / P99 19.05ms / Worst 20.86ms`; Compose P99 `73.72ms` exceeded `64ms`.
  - Run 3 failed: Scroll `Avg 4.42ms / P90 9.37ms / P99 20.00ms / Worst 81.49ms`; failure was the old `32ms` worst-frame cap while scroll P99 stayed under `24ms`.
- Post-fix verification passed three times on the same device:
  - `flutter test integration_test/feed_performance_test.dart -d emulator-5554` -> exit 0. Scroll `Avg 4.10ms / P90 7.42ms / P99 17.66ms / Worst 42.37ms`; Compose P99 `31.13ms`.
  - `flutter test integration_test/feed_performance_test.dart -d emulator-5554` -> exit 0. Scroll `Avg 3.61ms / P90 5.28ms / P99 17.25ms / Worst 19.34ms`; Compose P99 `54.17ms`.
  - `flutter test integration_test/feed_performance_test.dart -d emulator-5554` -> exit 0. Scroll `Avg 3.84ms / P90 6.76ms / P99 16.53ms / Worst 21.83ms`; Compose P99 `53.24ms`.
- No `feed` or `1to1` named gate was required because no production feed behavior or feed-originated send path changed.
- Reopen trigger: repeated same-device feed performance failures where scroll P99 exceeds the current `24ms` debug budget or compose input fails after production-aligned draft storage.
- Still open after Session 04: Session 05 still needed to record the final doc 79 acceptance classification. Session 02 remained retry-only after emulator relay DNS/preflight is healthy.

## Session 05 evidence note

Closure verdict: `accepted_with_explicit_follow_up` for `05-full-regression-acceptance-closure`.

- Files changed for Session 05: evidence docs only.
- Session type: acceptance-only. No product code, gate definitions, relay architecture, or message retry UX changed.
- Refreshed relay preflight on `emulator-5554`:
  - `/Users/I560101/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell getprop sys.boot_completed` -> `1`.
  - `/Users/I560101/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell ping -c 1 mknoun.xyz` -> `ping: unknown host mknoun.xyz`.
  - `/Users/I560101/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell ping -c 1 8.8.8.8` -> `0% packet loss`.
  - `nc -vz mknoun.xyz 4001` on host macOS -> succeeded.
- Valid acceptance checks passed:
  - `dart format --output=none --set-exit-if-changed integration_test/feed_performance_test.dart`.
  - `./scripts/run_test_gates.sh completeness-check` -> `670/670 test files classified`.
- Full regression was intentionally not launched under the failing DNS preflight because transport, benchmark-sim, `background_reconnect_test.dart`, and `cold_start_sendable_no_user_action_test.dart` would produce known-invalid relay/readiness evidence.
- Deferred commands after Android can resolve `mknoun.xyz`:
  - `FLUTTER_DEVICE_ID=emulator-5554 ./scripts/run_test_gates.sh transport`
  - `FLUTTER_DEVICE_ID=emulator-5554 ./scripts/run_test_gates.sh benchmark-sim`
  - `FLUTTER_DEVICE_ID=emulator-5554 /Users/I560101/.codex/skills/flutter-full-regression-runner/scripts/run_full_regression.sh --repo /Users/I560101/Project-Sat/mknoon-2/flutter_app`
- Reopen trigger: only when emulator-side relay DNS is healthy and one of the deferred commands still fails in a way not explained by the documented external preflight.

# Overall closure bar

Doc 79 final verdict: `accepted_with_explicit_follow_up`.

- Session 01 `closed`: `retrieve_pending ok:false` cannot mark inbox readiness successful.
- Session 02 `blocked_external_preflight`: `emulator-5554` has generic IP connectivity but cannot resolve `mknoun.xyz` from inside Android, so device-backed relay/readiness tests and the transport gate were not valid to run.
- Session 03 `stale/already-covered`: isolated, plain-name, together, serial aggregate, and normal aggregate feature commands passed in the current tree, so the historical aggregate feature failures no longer reproduce.
- Session 04 `closed`: `integration_test/feed_performance_test.dart` uses a documented current debug-mode scroll P99 budget and now passes three same-device runs after benchmark-only harness stabilization.
- Session 05 `accepted_with_explicit_follow_up`: final full-regression acceptance is deferred until Android emulator relay DNS is healthy, and remaining relay/readiness failures must not be misclassified as retry-message UX regressions.

Current pipeline state: all five sessions have terminal statuses. The only follow-up is external/environmental: restore Android emulator DNS for `mknoun.xyz`, then rerun the deferred transport, benchmark-sim, and full-regression commands.

# Source of truth

Docs read for this decomposition:

- `Test-Flight-Improv/79-full-regression-failure-fix-plan.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `/Users/I560101/.codex/skills/implementation-session-decomposer/SKILL.md`

Source doc 79 cites `.full_regression_logs/20260427_185248/summary.tsv` and rerun logs as failure inventory, but this decomposition did not read logs or code because the requested input scope was the source doc plus directly relevant stable gate docs.

Gate facts governing the split:

- `scripts/run_test_gates.sh` is the command source of truth when named gates and docs disagree.
- `test-gate-definitions.md` keeps frozen named gates exact-file based.
- Startup/transport work uses `./scripts/run_test_gates.sh transport` or `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport`.
- `integration_test/feed_performance_test.dart` is classified as an optional/manual direct performance suite, not a frozen named gate member.
- `test/core/services/*.dart` is classified as a direct suite, which fits the readiness proof semantics work.
- Gate docs require `./scripts/run_test_gates.sh completeness-check` only if gate definitions or classifications are edited.

# Ordered session breakdown

## Session 01: Fix false-positive inbox readiness proof

- Session id: `01-readiness-proof-semantics`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-01-readiness-proof-semantics-plan.md`
- Exact scope: add a regression where `retrieve_pending` returns `ok:false`, then change `P2PServiceImpl` readiness proof handling so failed relay retrieve is distinguishable from successful empty inbox. Preserve an explicit positive case for `ok:true` with no messages.
- Why it is its own session: this is a deterministic correctness bug in a core service contract. It can be fixed and verified with unit/direct performance tests without waiting for emulator, aggregate, or benchmark evidence.
- Likely code-entry files:
  - `lib/core/services/p2p_service_impl.dart`
  - `lib/core/bridge/p2p_bridge_client.dart`
  - `lib/features/p2p/domain/models/node_state.dart`
- Likely direct tests/regressions:
  - `flutter test test/core/services/p2p_service_impl_test.dart`
  - `flutter test test/core/services/p2p_service_fault_injection_test.dart`
  - `flutter test test/performance/benchmark_time_to_online_test.dart`
  - `flutter test test/performance/benchmark_background_resume_test.dart`
- Likely named gates:
  - No frozen named gate is required for the first proof. If the implementation changes bridge, resume, reconnect, transport fallback, or app bootstrap behavior, run `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport` as the companion gate.
- Matrix/closure docs to update when done:
  - Source doc 79 Session 01 evidence note.
  - This breakdown ledger now records Session 01 completion.
  - `Test-Flight-Improv/test-gate-definitions.md` only if a new gate classification is added or changed.
- Dependency on earlier sessions: none.
- Downstream execution path: `$implementation-plan-orchestrator`, then `$implementation-execution-qa-orchestrator`, then `$implementation-closure-audit-orchestrator`.
- Closure update: Session 01 is closed with the evidence recorded above. Do not treat this as closure for Sessions 02-05 or for the overall doc 79 full-regression verdict.

## Session 02: Diagnose or document relay/device readiness blocker

- Session id: `02-relay-device-startup-diagnosis`
- Session classification: `evidence-gated`
- Intended plan file: `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-02-relay-device-startup-diagnosis-plan.md`
- Exact scope: collect emulator-side relay reachability and startup evidence, diagnose why node startup does not reach relay-ready or produce a circuit address, and either fix a repo-local startup issue or document an external preflight blocker.
- Why it is its own session: relay/device startup is environment and real-stack dependent. It needs transport/device evidence and must not be mixed with the deterministic readiness proof bug.
- Likely code-entry files:
  - `lib/core/services/p2p_service_impl.dart`
  - `lib/core/bridge/p2p_bridge_client.dart`
  - `go-mknoon/node/config.go`
  - `go-mknoon/node/node.go`
  - `integration_test/background_reconnect_test.dart`
  - `integration_test/cold_start_sendable_no_user_action_test.dart`
- Likely direct tests/regressions:
  - `flutter test integration_test/cold_start_sendable_no_user_action_test.dart -d emulator-5554`
  - `flutter test integration_test/background_reconnect_test.dart -d emulator-5554`
  - emulator-side DNS/reachability preflight for `mknoun.xyz`
  - one-emulator cold-boot rerun before any multi-emulator conclusion
- Likely named gates:
  - `FLUTTER_DEVICE_ID=emulator-5554 ./scripts/run_test_gates.sh transport`
- Matrix/closure docs to update when done:
  - Source doc 79 with pass/fail/blocker evidence.
  - `Test-Flight-Improv/test-gate-definitions.md` only if the session changes named transport gate membership or documented device requirements.
- Dependency on earlier sessions: none, but downstream planning should refresh after Session 01 because readiness attribution may be clearer once false-positive inbox proof is fixed.
- Downstream execution path: `$implementation-plan-orchestrator`, then `$implementation-execution-qa-orchestrator`, then `$implementation-closure-audit-orchestrator`.

## Session 03: Reproduce and stabilize aggregate `test/features` failures

- Session id: `03-feature-aggregate-flake-stability`
- Session classification: `evidence-gated`
- Intended plan file: `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-03-feature-aggregate-flake-stability-plan.md`
- Exact scope: reproduce the aggregate-only failures for the group and conversation wired tests, compare isolated/together/full-directory and serial/parallel behavior, then fix shared test isolation, cleanup, plugin mock, async timer, or serial-bucket classification with evidence.
- Why it is its own session: the source doc says isolated reruns pass while the full directory run fails. That is a suite-stability seam, not a product feature change, and it needs a different reproduction path from P2P readiness or feed performance.
- Likely code-entry files:
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
  - `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  - related feature test fixtures, mocks, temp-dir setup, or async cleanup found during downstream planning
- Likely direct tests/regressions:
  - `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`
  - `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart`
  - both files in one command
  - `flutter test test/features --reporter expanded --concurrency=1`
  - full `flutter test test/features --reporter expanded` after any fix or serial classification
- Likely named gates:
  - No frozen named gate is required unless downstream evidence ties the issue to group messaging product behavior. If group send/receive/retry/listener behavior changes, run `./scripts/run_test_gates.sh groups`.
- Matrix/closure docs to update when done:
  - Source doc 79 with reproduction classification and direct command evidence.
  - `Test-Flight-Improv/test-gate-definitions.md` only if a new serial/direct suite classification is intentionally added.
- Dependency on earlier sessions: none.
- Downstream execution path: `$implementation-plan-orchestrator`, then `$implementation-execution-qa-orchestrator`, then `$implementation-closure-audit-orchestrator`.

## Session 04: Establish feed scroll baseline, then optimize or recalibrate

- Session id: `04-feed-performance-baseline-and-fix`
- Session classification: `evidence-gated`
- Intended plan file: `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-04-feed-performance-baseline-and-fix-plan.md`
- Exact scope: run feed performance enough times on the target clean emulator/profile to classify jitter versus app cost, then either optimize feed scroll hot spots or recalibrate the benchmark threshold with a documented stable baseline.
- Why it is its own session: feed scroll P99 has a performance closure bar and may require profiling, UI hot-path changes, or benchmark calibration. It should not be combined with relay/device evidence or feature-test flake work.
- Likely code-entry files:
  - `integration_test/feed_performance_test.dart`
  - `integration_test/benchmark_helpers.dart`
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/feed/presentation/widgets/feed_card.dart`
  - `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
  - `lib/features/feed/presentation/widgets/open_mode_card_body.dart`
  - `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
- Likely direct tests/regressions:
  - three clean-emulator runs of `flutter test integration_test/feed_performance_test.dart -d emulator-5554`
  - profile-mode benchmark if the downstream plan confirms an existing profile harness
  - direct feed widget/integration tests if production feed code changes
- Likely named gates:
  - `FLUTTER_DEVICE_ID=emulator-5554 ./scripts/run_test_gates.sh benchmark-sim` from source doc 79.
  - `./scripts/run_test_gates.sh feed` if feed screen/card behavior changes.
  - `./scripts/run_test_gates.sh 1to1` only if the fix touches feed-originated 1:1 send paths.
- Matrix/closure docs to update when done:
  - Source doc 79 with baseline distribution, optimization evidence, or threshold rationale.
  - `Test-Flight-Improv/test-gate-definitions.md` only if performance-suite classification changes.
- Dependency on earlier sessions: none.
- Downstream execution path: `$implementation-plan-orchestrator`, then `$implementation-execution-qa-orchestrator`, then `$implementation-closure-audit-orchestrator`.

## Session 05: Rerun full regression and close doc 79 evidence

- Session id: `05-full-regression-acceptance-closure`
- Session classification: `acceptance-only`
- Intended plan file: `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-05-full-regression-acceptance-closure-plan.md`
- Exact scope: rerun the source doc's direct tests and named gates after Sessions 01-04 when the device preflight is valid, or explicitly classify the remaining full-regression work as externally blocked. Update doc 79 closure evidence without implementing new product changes.
- Why it is its own session: closure spans multiple earlier seams and is the only safe place to decide whether big-build confidence is restored or still externally blocked.
- Likely code-entry files:
  - `Test-Flight-Improv/79-full-regression-failure-fix-plan.md`
  - `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-breakdown.md`
  - full regression output logs created by the downstream acceptance run
- Likely direct tests/regressions:
  - all source doc direct commands that remain relevant after Sessions 01-04 and are not invalidated by the relay DNS preflight
  - `/Users/I560101/.codex/skills/flutter-full-regression-runner/scripts/run_full_regression.sh --repo /Users/I560101/Project-Sat/mknoon-2/flutter_app` after emulator-side relay DNS is healthy
- Likely named gates:
  - `FLUTTER_DEVICE_ID=emulator-5554 ./scripts/run_test_gates.sh transport`
  - `FLUTTER_DEVICE_ID=emulator-5554 ./scripts/run_test_gates.sh benchmark-sim`
  - `./scripts/run_test_gates.sh completeness-check` only if gate definitions changed.
- Matrix/closure docs to update when done:
  - Source doc 79 final verdict and done criteria evidence.
  - This breakdown ledger with terminal statuses.
  - `Test-Flight-Improv/test-gate-definitions.md` only if any session intentionally changed gate or direct-suite classification.
- Dependency on earlier sessions: Sessions 01-04.
- Downstream execution path: `$implementation-plan-orchestrator`, then `$implementation-execution-qa-orchestrator`, then `$implementation-closure-audit-orchestrator`.

# Why this is not fewer sessions

Four source failures use different seams and evidence types. Combining readiness semantics with relay/device startup would risk hiding a deterministic code bug behind environment noise. Combining aggregate feature flake work with feed performance would mix test-isolation triage with emulator/profile timing. Combining final acceptance with any implementation session would make the full-regression verdict stale as soon as later sessions land.

# Why this is not more sessions

The source doc contains many commands, but they group into four meaningful failure tracks plus closure. Splitting positive and negative readiness proof tests, isolated and serial aggregate reproductions, or feed baseline and feed fix into separate plans would create bookkeeping overhead before downstream planning knows whether the evidence supports code changes, test cleanup, or external blockers.

# Regression and gate contract

- `Test-Flight-Improv/14-regression-test-strategy.md` requires a permanent regression for escaped bugs, direct tests for the changed feature, the relevant subsystem gate, and baseline/full-confidence gates where blast radius justifies them.
- `Test-Flight-Improv/test-gate-definitions.md` is the stable gate map, while source doc 79 and gate docs agree that script commands are the executable source of truth.
- Session 01 starts with direct core-service and readiness timing tests because `test/core/services/*.dart` is a direct suite.
- Session 02 owns device-backed `transport` gate evidence because it touches bridge/startup/relay readiness.
- Session 03 owns direct aggregate feature commands first; it only widens to the `groups` gate if evidence proves group messaging behavior changed.
- Session 04 owns the performance direct suite and source-doc `benchmark-sim` command; it only runs the `feed` or `1to1` gates if production feed behavior or feed-originated send paths change.
- Session 05 owns final full-regression acceptance and any `completeness-check` run required by gate classification edits.

# Matrix update contract

No new matrix doc should be created. Use existing stable docs:

- Update `Test-Flight-Improv/79-full-regression-failure-fix-plan.md` with final evidence and closure classification when downstream sessions finish.
- Update this breakdown artifact's session ledger during closure if the downstream workflow records terminal status.
- Update `Test-Flight-Improv/test-gate-definitions.md` only if a downstream session changes named gate membership, direct-suite classification, serial bucket status, or documented device requirements.

# Downstream execution path

Each session must be processed independently and in order through:

1. `$implementation-plan-orchestrator`
2. `$implementation-execution-qa-orchestrator`
3. `$implementation-closure-audit-orchestrator`

Detailed planning for a later session must refresh against the code, tests, and logs after earlier sessions land.

# Reviewer notes

- Is the recommended session count sufficient, too coarse, or too fragmented? Sufficient. Five sessions preserve the four independent failure tracks and one cross-track acceptance pass.
- Which proposed sessions should merge? None. The implementation/evidence seams and gate families differ.
- Which proposed sessions must split? None at decomposition time. Sessions 03 and 04 intentionally keep reproduction plus fix/calibration together because the evidence determines the closure path.
- What tests or named gates are missing from the decomposition? None structurally. The downstream plans must refresh exact commands and add current-code test paths if code inspection proves the source list stale.
- Does each session end in a meaningful verified state? Yes. Sessions 01, 03, and 04 close one failure class each; Session 02 records an external preflight blocker; Session 05 records the full-regression verdict as accepted with explicit follow-up.
- Is matrix-update responsibility assigned clearly? Yes. Session 05 owns final doc 79 and breakdown closure, while individual sessions update gate definitions only if they change classifications.
- What is the minimum session set that is still safe? Five.

# Structural blockers remaining

None for decomposition or doc-scoped rollout. The remaining blocker is external runtime environment only: Android must resolve `mknoun.xyz` before transport, benchmark-sim, and full-regression acceptance can be rerun as valid release-confidence commands.

# Accepted differences intentionally left unchanged

- Message retry UX implementation is outside doc 79 scope.
- Relay architecture and AutoRelay redesign are outside scope.
- Feed product UI redesign is outside scope; only measurable scroll hot spots or benchmark calibration belong here.
- Group message listener changes stay out of scope unless aggregate reproduction directly proves they are responsible.
- Full regression scripts stay unchanged unless downstream evidence proves orchestration is the failure.
- Initial decomposition did not inspect logs or code; downstream session planning and execution refreshed evidence before recording the terminal verdicts above.

# Exact docs/files used as evidence

- `/Users/I560101/.codex/skills/implementation-session-decomposer/SKILL.md`
- `Test-Flight-Improv/79-full-regression-failure-fix-plan.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`

# Why the decomposition is safe to send into downstream planning/execution

The session set follows the source doc's four-track classification, keeps independent seams separate, assigns gate and direct-test ownership from the stable gate docs, preserves doc-scoped non-colliding plan paths, and reserves full-regression classification for an acceptance-only closure session after implementation/evidence sessions have landed.
