# Session 02 Plan: Relay Device Startup Diagnosis

## Final verdict

`evidence-gated`.

This session is safe to execute as a bounded diagnosis and fix-or-blocker pass. It is not safe to assume a repo-local code bug until emulator-side relay reachability, node startup events, and the transport gate are rerun after Session 01's readiness proof fix.

## Session 02 execution evidence - 2026-04-27 21:52 CEST

Terminal execution verdict: `blocked_external_preflight`.

Selected device: `emulator-5554`.

Preflight evidence:

- `flutter devices`: found `emulator-5554` and `emulator-5556`; `emulator-5554` selected per plan preference.
- `adb devices`: failed with `zsh:1: command not found: adb`; full SDK path `/Users/I560101/Library/Android/sdk/platform-tools/adb devices` showed `emulator-5554 device` and `emulator-5556 device`.
- `/Users/I560101/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell getprop sys.boot_completed`: returned `1`.
- `nc -vz mknoun.xyz 4001`: passed with `Connection to mknoun.xyz port 4001 [tcp/newoak] succeeded!`.
- `nc -vz mknoun.xyz 4002`: failed with TCP `Connection refused`; this does not prove QUIC/UDP reachability because the relay default uses UDP/QUIC on port 4002.
- `/Users/I560101/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell getent hosts mknoun.xyz || /Users/I560101/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell ping -c 1 mknoun.xyz`: `getent` was absent and the fallback failed with `ping: unknown host mknoun.xyz`.
- `/Users/I560101/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell ping -c 1 8.8.8.8`: passed with `0% packet loss`, proving the emulator has generic IP connectivity while DNS resolution for `mknoun.xyz` fails.
- `/Users/I560101/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell toybox nc -vz mknoun.xyz 4001`: failed because Android `toybox nc` does not support `-vz`.
- `/Users/I560101/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell toybox timeout 5 toybox nc mknoun.xyz 4001`: timed out with no output.

Configuration inspection:

- `lib/core/bridge/p2p_bridge_client.dart` still sends both default relay multiaddrs when no override is configured: WSS `/dns/mknoun.xyz/tcp/4001/wss/...` and QUIC `/dns/mknoun.xyz/udp/4002/quic-v1/...`.
- `go-mknoon/node/config.go` still defines matching WSS and QUIC defaults.
- `go-mknoon/node/node.go` merges relay addresses for the same peer ID into one `peer.AddrInfo`, so WSS and QUIC can both be attempted by `host.Connect()`.

Direct tests and gate status:

- `flutter test integration_test/background_reconnect_test.dart -d emulator-5554`: not run because emulator-side relay DNS preflight failed.
- `flutter test integration_test/cold_start_sendable_no_user_action_test.dart -d emulator-5554`: not run because emulator-side relay DNS preflight failed.
- `FLUTTER_DEVICE_ID=emulator-5554 ./scripts/run_test_gates.sh transport`: not run because transport gate evidence would be invalid against a known emulator DNS blocker.

No product code or integration test contract was changed. The next retry should start by restoring emulator DNS resolution for `mknoun.xyz` or selecting an emulator/network where `mknoun.xyz` resolves from inside Android, then rerun the direct tests and transport gate.

## Final plan

### 1. real scope

Diagnose why device-backed startup does not reach relay-ready:

- verify host and emulator reachability to `mknoun.xyz`
- verify the app starts the node with the expected relay multiaddrs
- rerun the direct failing startup tests on one selected emulator
- rerun the `transport` gate when the direct preflight is healthy
- fix only a proven repo-local bridge/node startup issue
- otherwise document an external emulator/relay/network blocker with exact evidence

Do not change message retry UX, feed performance, aggregate feature tests, relay architecture, or full-regression scripts in this session.

### 2. closure bar

The session is complete when one of these is true:

- `integration_test/background_reconnect_test.dart` and `integration_test/cold_start_sendable_no_user_action_test.dart` pass on a single selected emulator and the transport gate passes or has only unrelated known failures.
- A repo-local startup defect is fixed and verified by the same direct tests plus `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport`.
- The session is explicitly blocked by external preflight evidence, such as emulator DNS/connectivity failure to `mknoun.xyz`, relay endpoint refusal/timeout outside app code, or no available booted device.

### 3. source of truth

- `Test-Flight-Improv/79-full-regression-failure-fix-plan.md`
- `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-breakdown.md`
- `.full_regression_logs/20260427_185248/summary.tsv`
- `.full_regression_logs/20260427_185248/016_integration_test_background_reconnect_test.dart.log`
- `.full_regression_logs/20260427_185248/018_integration_test_cold_start_sendable_no_user_action_test.dart.log`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `lib/core/bridge/p2p_bridge_client.dart`
- `lib/core/services/p2p_service_impl.dart`
- `go-mknoon/node/config.go`
- `go-mknoon/node/node.go`

Current code and rerun evidence beat stale prose. If gate docs and `scripts/run_test_gates.sh` disagree, the script wins.

### 4. session classification

`evidence-gated`.

The source failure is device-backed and depends on relay/network reachability. Session 01 removed a false-positive inbox proof, so reruns may look worse in a truthful way; that is expected and should not be treated as a new Session 02 regression by itself.

### 5. exact problem statement

Historical logs show the node starts but never becomes relay-ready:

- `node:status` reports `isStarted=true`, `circuitAddresses=0`, `connections=0`, `relayState=starting`.
- `inbox:store_timing` and `inbox:retrieve_pending` fail with relay dial deadline errors.
- `circuit_address:timing` times out around 10 seconds.
- `relay:warm_timing` fails after the 15 second dial timeout.
- `background_reconnect_test.dart` times out waiting for initial `Online.`.
- `cold_start_sendable_no_user_action_test.dart` times out waiting for a sendable badge.

The user-visible risk is that the app can remain stuck connecting on cold start/resume because the emulator cannot establish a relay path.

### 6. files and repos to inspect next

- `lib/core/bridge/p2p_bridge_client.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/features/p2p/domain/models/node_state.dart`
- `go-mknoon/node/config.go`
- `go-mknoon/node/node.go`
- `go-mknoon/node/relay_session_manager.go`
- `integration_test/background_reconnect_test.dart`
- `integration_test/cold_start_sendable_no_user_action_test.dart`
- `integration_test/wifi_relay_fallback_smoke_test.dart`
- `integration_test/transport_e2e_test.dart`
- `integration_test/media_stable_id_smoke_test.dart`
- `scripts/run_test_gates.sh`

### 7. existing tests covering this area

- `integration_test/background_reconnect_test.dart` covers user-visible online transition after startup/resume.
- `integration_test/cold_start_sendable_no_user_action_test.dart` covers cold-start sendable readiness without user action.
- The `transport` gate runs `background_reconnect_test.dart`, `wifi_relay_fallback_smoke_test.dart`, `transport_e2e_test.dart`, and `media_stable_id_smoke_test.dart`.
- Session 01 direct P2P tests now ensure failed inbox retrieve cannot fake inbox readiness.

Missing evidence before this session executes:

- current `flutter devices` / booted emulator state
- emulator-side DNS lookup and TCP/UDP reachability for `mknoun.xyz`
- direct rerun logs after Session 01
- whether the default WSS/QUIC relay addresses both fail or only one transport path fails

### 8. regression/tests to add first

Do not add a new regression before the preflight. The failing integration tests already define the behavioral regression. Add new code-level tests only if execution proves a repo-local bug, for example:

- relay address selection drops the WSS/QUIC fallback unexpectedly
- node startup reports `relayState=starting` forever after a recoverable relay-session event
- Flutter readiness maps a truthful Go startup state incorrectly

### 9. step-by-step implementation plan

1. Select one device. Prefer `emulator-5554` if booted; otherwise record the actual device id from `flutter devices`.
2. Record tool/device preflight:
   - `flutter devices`
   - `adb devices` if Android tooling is available
   - `adb -s <device-id> shell getprop sys.boot_completed` for Android emulators
3. Verify host reachability:
   - `nc -vz mknoun.xyz 4001`
   - `nc -vz mknoun.xyz 4002` if TCP probing is meaningful in the environment; record that QUIC/UDP cannot be proven by TCP alone.
4. Verify emulator-side reachability:
   - `adb -s <device-id> shell getent hosts mknoun.xyz || adb -s <device-id> shell ping -c 1 mknoun.xyz`
   - `adb -s <device-id> shell toybox nc -vz mknoun.xyz 4001` when available
   - record if Android shell lacks `nc` or UDP probing.
5. Inspect current default relay address configuration in `p2p_bridge_client.dart` and `go-mknoon/node/config.go`; confirm Flutter sends both WSS and QUIC defaults unless overridden.
6. Rerun direct failing tests on the selected device:
   - `flutter test integration_test/background_reconnect_test.dart -d <device-id>`
   - `flutter test integration_test/cold_start_sendable_no_user_action_test.dart -d <device-id>`
7. If direct tests pass, run:
   - `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport`
8. If tests fail with emulator relay reachability failure, record `blocked_external_preflight` and do not edit product code.
9. If tests fail despite healthy emulator reachability, inspect the newest logs for:
   - wrong relay multiaddr passed to Go
   - WSS/QUIC fallback not attempted
   - relay session manager state stuck after a successful connection
   - circuit address wait using the wrong readiness signal
10. Fix only a proven repo-local bug, then rerun the direct tests and the transport gate.
11. Update source doc 79 and the breakdown with the pass/fix/blocker classification. Do not close the overall doc.

### 10. risks and edge cases

- Host reachability does not prove emulator reachability.
- TCP probing port 4002 does not prove QUIC/UDP reachability.
- Multiple booted emulators can compete for resources; use one selected device for classification.
- Session 01 may make readiness stricter by preventing failed inbox retrieve from counting as ready.
- Relay startup can be externally red while other integration tests pass through fake/local paths.
- Do not skip transport tests to make the rollout green.

### 11. exact tests and gates to run

Preflight:

```bash
flutter devices
adb devices
adb -s <device-id> shell getprop sys.boot_completed
nc -vz mknoun.xyz 4001
nc -vz mknoun.xyz 4002
adb -s <device-id> shell getent hosts mknoun.xyz || adb -s <device-id> shell ping -c 1 mknoun.xyz
adb -s <device-id> shell toybox nc -vz mknoun.xyz 4001
```

Direct tests:

```bash
flutter test integration_test/background_reconnect_test.dart -d <device-id>
flutter test integration_test/cold_start_sendable_no_user_action_test.dart -d <device-id>
```

Named gate:

```bash
FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport
```

### 12. known-failure interpretation

- Relay/device startup failures before `Online.` remain Session 02 failures or external blockers.
- Failed inbox retrieve no longer proves inbox readiness after Session 01; that is correct behavior.
- Aggregate `test/features` failures belong to Session 03.
- Feed P99 failures belong to Session 04.
- Full regression closure belongs to Session 05.
- Generated build/index artifacts are not evidence for this session.

### 13. done criteria

- One selected device is recorded.
- Host and emulator relay preflight evidence is recorded.
- Direct rerun outcomes are recorded.
- The transport gate is run when preflight is healthy, or skipped only with explicit preflight blocker evidence.
- Any code change is tied to a proven repo-local startup defect and has direct test/gate evidence.
- Source doc 79 and the breakdown record Session 02's terminal state without claiming full doc closure.

### 14. scope guard

Do not:

- redesign relay or AutoRelay architecture
- add a new relay session manager
- change message retry UX
- change feed UI or performance thresholds
- edit aggregate feature tests
- change full-regression scripts
- weaken direct integration assertions
- treat host-only reachability as enough to close emulator readiness

### 15. accepted differences / intentionally out of scope

- QUIC/UDP reachability may require indirect app/Go evidence if shell tooling cannot probe UDP.
- External relay downtime or emulator network failure may block this session without repo code changes.
- Multi-relay architecture and shared relay backend rollout remain outside doc 79.

### 16. dependency impact

Session 05 cannot close full-regression confidence until this session either passes the device-backed readiness tests/transport gate or records a concrete external blocker. Session 04 feed performance and Session 03 feature flake work do not depend on this session unless they need the same emulator.

## Structural blockers remaining

None for execution planning. The session remains evidence-gated by device/emulator availability and relay reachability.

## Incremental details intentionally deferred

- New unit tests are deferred until execution proves a repo-local defect.
- QUIC-specific probing is deferred to app/Go event evidence if Android shell tools cannot probe UDP.

## Accepted differences intentionally left unchanged

- Session 01 readiness correctness is accepted and not reopened here.
- Transport gate membership remains unchanged.

## Exact docs/files used as evidence

- `/Users/I560101/.codex/skills/implementation-plan-orchestrator/SKILL.md`
- `/Users/I560101/.codex/skills/mobile-network-resilience-qa/SKILL.md`
- `/Users/I560101/.codex/skills/mobile-network-resilience-qa/references/device-scenarios.md`
- `Network-Arch/Resilient-libp2p-TDD-Plan.md`
- `Test-Flight-Improv/79-full-regression-failure-fix-plan.md`
- `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `.full_regression_logs/20260427_185248/summary.tsv`
- `.full_regression_logs/20260427_185248/016_integration_test_background_reconnect_test.dart.log`
- `.full_regression_logs/20260427_185248/018_integration_test_cold_start_sendable_no_user_action_test.dart.log`
- `lib/core/bridge/p2p_bridge_client.dart`
- `go-mknoon/node/config.go`
- `go-mknoon/node/node.go`

## Why the plan is safe to execute now

The plan starts with environment and emulator reachability proof, preserves the existing failing integration tests as the behavioral contract, and only allows code changes after current rerun evidence proves a repo-local startup defect.
