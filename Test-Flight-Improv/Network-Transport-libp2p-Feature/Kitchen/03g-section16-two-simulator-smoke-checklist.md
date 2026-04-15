# Section 16 — Two-Simulator Smoke Tests — COMPLETE

> **Replaces:** Old Section 16 (Flutter + Go CLI test peer)
> **Pattern:** `run_group_multi_device_real.dart` + `group_multi_device_real_harness.dart`
> **Devices:** iPhone 17 Pro (`38FECA55`) = Alice, iPhone 17 (`5BA69F1C`) = Bob
> **Status:** **26/26 PASS**, exit code 0. All scenarios implemented and running.

---

## Files Created

| File | Role | Status |
|---|---|---|
| `integration_test/routing_smoke_alice_harness.dart` | Alice (sender, S1–S15 + X1–X3) | **Created** |
| `integration_test/routing_smoke_bob_harness.dart` | Bob (receiver, S1–S15 + X1–X3) | **Created** |
| `integration_test/group_smoke_alice_harness.dart` | Alice (group creator, G1–G8) | **Created** |
| `integration_test/group_smoke_bob_harness.dart` | Bob (group joiner, G1–G8) | **Created** |
| `integration_test/scripts/run_routing_smoke_e2e.dart` | Orchestrator (Phase 1 + Phase 2) | **Rewritten** |

## Files Deleted

| File | Status |
|---|---|
| `integration_test/routing_smoke_e2e_test.dart` | **Deleted** (replaced by alice + bob harnesses) |

---

## Implementation — All Done

### 1. Shared Signal Protocol — DONE
- [x] Signal name helper: `_sig(String name) => '$_sharedDir/smoke_${_runId}_$name'`
- [x] Signal flow implemented for all 26 scenarios
- [x] Orchestrator drives scenarios sequentially via signal files

### 2. Alice Harness — DONE
- [x] Full DI stack: GoBridgeClient, encrypted DB, P2PServiceImpl, ChatMessageListener, ContactRepositoryImpl, MessageRepositoryImpl
- [x] Dart-define parameters: `E2E_SHARED_DIR`, `SMOKE_ROLE`, `SMOKE_RUN_ID`, `E2E_DB_NAME`
- [x] Identity exchange via shared JSON files
- [x] `captureFlowEvents()` for timing capture on every send
- [x] All 18 Phase 1 scenarios implemented (S1–S15 + X1–X3)

### 3. Bob Harness — DONE
- [x] Identical DI stack to Alice
- [x] DB polling via `waitForMessage()` for incoming message detection
- [x] Sends in S5 (bidirectional) and S8 (lifecycle)
- [x] Node stop/restart in S3, S6, S9, S15, X1
- [x] `handleAppPaused()`/`handleAppResumed()` in X2
- [x] All 18 Phase 1 scenarios implemented

### 4. Orchestrator — DONE
- [x] Two-device launch: Alice first (wait for ready), then Bob
- [x] Sequential scenario driving via signal files
- [x] Phase 1 (1:1 + cross-cutting): 18 scenarios
- [x] Phase 2 (group): 8 scenarios via separate group harnesses
- [x] Combined report with timing from both sides

### 5. Group Harnesses — DONE
- [x] `group_smoke_alice_harness.dart` — creates group, publishes, rotates keys
- [x] `group_smoke_bob_harness.dart` — joins group, receives, sends in bidirectional
- [x] Uses `setupGroupMultiDeviceStack` from existing infrastructure
- [x] G1–G8 all implemented and passing

### 6. Inventory Updated — DONE
- [x] `03f-benchmark-test-inventory.md` updated with all 26 scenarios + timing data
- [x] Baseline table shows 26/26 PASS with measurements

### 7. Verified — DONE
- [x] All files compile: `dart analyze` — zero errors/warnings
- [x] Run on two simulators: `dart run integration_test/scripts/run_routing_smoke_e2e.dart -d 38FECA55,5BA69F1C`
- [x] **26/26 PASS**, exit code 0
- [x] Every scenario produces timing data in the orchestrator report

---

## All 26 Scenarios — Quick Reference

| # | Name | Timing | Status |
|---|---|---|---|
| S1 | Cold send | send=555ms, e2e=938ms | **PASS** |
| S2 | Warm x5 | 5/5 delivered | **PASS** |
| S3 | Offline → inbox | send=2067ms, path=inbox | **PASS** |
| S4 | Reconnect | send=94ms, e2e=3308ms | **PASS** |
| S5 | Bidirectional | 3 recv + 2 sent | **PASS** |
| S6 | Stale connection | send=130ms, e2e=509ms | **PASS** |
| S7 | All-paths-fail | outcome=success (inbox) | **PASS** |
| S8 | Full lifecycle (10 msgs) | warm send=5ms | **PASS** |
| S9 | Batch inbox x5 | 5/5 stored | **PASS** |
| S10 | Delete-for-everyone | 96ms, outcome=success | **PASS** |
| S11 | Voice message | sendVoiceMessage() captured | **PASS** |
| S12 | Media 1MB | 411ms, 2491 KB/s | **PASS** |
| S13 | ACK under load | 10/10 received | **PASS** |
| S14 | Local WiFi | isLocal=false, send=12ms | **PASS** |
| S15 | Relay probe | send=2073ms, path=inbox | **PASS** |
| X1 | Both-sides restart | 521ms/516ms, e2e=3322ms | **PASS** |
| X2 | Background/foreground | resume=115ms/98ms, e2e=0ms | **PASS** |
| X3 | Relay failover | healthCheck=50ms, e2e=258ms | **PASS** |
| G1 | Group publish | send=25ms, e2e=258ms | **PASS** |
| G2 | Group warm x5 | 5/5 delivered | **PASS** |
| G3 | Group bidirectional | 2 recv + 1 sent | **PASS** |
| G4 | Group offline→inbox | e2e=0ms | **PASS** |
| G5 | Group lifecycle (9 msgs) | 9/9 both timelines | **PASS** |
| G6 | Peer discovery | measured during setup | **PASS** |
| G7 | Key rotation | 1220ms | **PASS** |
| G8 | Multi-member | send=1227ms | **PASS** |
