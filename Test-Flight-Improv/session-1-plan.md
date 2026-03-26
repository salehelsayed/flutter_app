# Session 1 Plan: Formalize Baseline + Subsystem Gates

**Date:** 2026-03-25
**Status:** Plan only — do not implement yet

---

## 1. Scope

Turn the gate definitions already described in `14-regression-test-strategy.md` into **one canonical, runnable source of truth** — a shell script (`scripts/run_test_gates.sh`) plus a reference checklist — so that every future session can say "run the 1:1 Reliability Gate" and mean the same exact `flutter test` invocation.

Secondary: reconcile the gate membership lists against the **actual** test files that now exist in the repo (several tests have been added since report 14 was written and are not assigned to any gate).

**Out of scope:**
- No new test files
- No test-architecture redesign
- No CI workflow changes (CI is session-level future work)
- No large smoke matrix

---

## 2. Files to Inspect Next (Before Implementation)

These don't need reading during planning — they need reading at implementation time to confirm each test file referenced in the gates still compiles and its description matches the gate's intent.

| File | Why |
|------|-----|
| `test/features/conversation/integration/emoji_reaction_exchange_test.dart` | Not in any gate — evaluate for 1:1 Reliability |
| `test/features/conversation/integration/quote_reply_thread_test.dart` | In report 14 coverage table but NOT in the gate run command |
| `test/features/groups/integration/group_edge_cases_smoke_test.dart` | Not in any gate — evaluate for Group Messaging |
| `test/features/groups/integration/group_membership_smoke_test.dart` | Not in any gate — evaluate for Group Messaging |
| `test/features/groups/integration/group_startup_rejoin_smoke_test.dart` | Not in any gate — evaluate for Group Messaging or Startup/Transport |
| `test/features/groups/integration/invite_round_trip_test.dart` | Not in any gate — evaluate for Group Messaging |
| `test/features/feed/integration/feed_color_smoke_test.dart` | Not in any gate — evaluate for Feed/Surface |
| `test/features/contact_request/integration/key_exchange_retry_flow_test.dart` | Not in any gate — evaluate for Contact/Onboarding or 1:1 Reliability |
| `integration_test/posts_phase2_fake_test.dart` through `posts_phase5_fake_test.dart` | Not in any gate — evaluate for Posts/Privacy or release gate |
| `integration_test/bidi_text_smoke_test.dart` | Not in any gate — evaluate for Baseline |
| `integration_test/smoke_test.dart` | Not in any gate — evaluate for Baseline |
| `integration_test/soak_e2e_test.dart` | Not in any gate — evaluate for nightly/release only |
| `integration_test/multi_relay_failover_test.dart` | Not in any gate — evaluate for Startup/Transport |
| `integration_test/relay_chaos_soak_test.dart` | Not in any gate — nightly/release only |

---

## 3. Existing Tests Covering This Area

Session 1 is about organizing existing tests, not about code under test. The tests themselves ARE the subject. All of the following exist and are confirmed present on disk:

### Baseline Gate Candidates (from report 14)
| Test | Path | Confirmed |
|------|------|-----------|
| `startup_router_recovery_test` | `test/features/identity/presentation/screens/` | YES |
| `qr_scanner_wired_test` | `test/features/qr_code/presentation/screens/` | YES |
| `offline_inbox_roundtrip_test` | `test/features/conversation/integration/` | YES |
| `loading_states_smoke_test` | `integration_test/` | YES |
| `posts_phase1_fake_test` | `integration_test/` | YES |
| `group_messaging_smoke_test` | `test/features/groups/integration/` | YES |

### 1:1 Reliability Gate Candidates (from report 14)
| Test | Path | Confirmed |
|------|------|-----------|
| `two_user_message_exchange_test` | `test/features/conversation/integration/` | YES |
| `offline_inbox_roundtrip_test` | `test/features/conversation/integration/` | YES |
| `media_attachment_flow_test` | `test/features/conversation/integration/` | YES |
| `media_retry_smoke_test` | `test/features/conversation/integration/` | YES |
| `voice_message_exchange_test` | `test/features/conversation/integration/` | YES |
| `incomplete_upload_recovery_test` | `test/features/conversation/integration/` | YES |
| `send_then_lock_delivery_test` | `test/features/conversation/integration/` | YES |
| `stuck_sending_recovery_test` | `test/features/conversation/integration/` | YES |

### Feed / Surface Gate Candidates (from report 14)
| Test | Path | Confirmed |
|------|------|-----------|
| `feed_card_flow_test` | `test/features/feed/integration/` | YES |
| `expanded_collapsed_card_test` | `test/features/feed/integration/` | YES |

### Group Messaging Gate Candidates (from report 14)
| Test | Path | Confirmed |
|------|------|-----------|
| `group_messaging_smoke_test` | `test/features/groups/integration/` | YES |
| `group_resume_recovery_test` | `test/features/groups/integration/` | YES |
| `contact_request_flow_test` | `test/features/contact_request/integration/` | YES |

### Posts / Privacy Gate Candidates (from report 14)
| Test | Path | Confirmed |
|------|------|-----------|
| `posts_phase1_fake_test` | `integration_test/` | YES |
| `post_presence_listener_test` | `test/features/posts/phase3/` | YES |

### Startup / Transport Gate Candidates (from report 14)
| Test | Path | Confirmed |
|------|------|-----------|
| `background_reconnect_test` | `integration_test/` | YES |
| `wifi_relay_fallback_smoke_test` | `integration_test/` | YES |
| `transport_e2e_test` | `integration_test/` | YES |
| `media_stable_id_smoke_test` | `integration_test/` | YES |

---

## 4. Regressions / Tests to Add First

**None.** Session 1 is documentation/script-only. No new test code is required.

The one pre-condition is: **verify every test file in the gate lists actually passes** before declaring the gates canonical. If any test is currently broken, note it as a known failure — don't block the gate definition on fixing it.

---

## 5. Step-by-Step Implementation Plan

### Step 1: Run every Baseline Gate test to confirm green
```bash
flutter test \
  test/features/identity/presentation/screens/startup_router_recovery_test.dart \
  test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart \
  test/features/conversation/integration/offline_inbox_roundtrip_test.dart \
  integration_test/loading_states_smoke_test.dart \
  integration_test/posts_phase1_fake_test.dart \
  test/features/groups/integration/group_messaging_smoke_test.dart
```
Record pass/fail. If any fail, document the known failure but keep moving.

### Step 2: Run each subsystem gate and record results
Run the 5 remaining gates (1:1 Reliability, Feed/Surface, Group Messaging, Posts/Privacy, Startup/Transport) individually. For each, record pass/fail status.

### Step 3: Evaluate unassigned tests
Read the 14 unassigned test files listed in Section 2. For each, decide:
- Which gate it belongs in (if any)
- Whether it's nightly/release only
- Whether it's intentionally standalone

### Step 4: Write the gate runner script
Create `scripts/run_test_gates.sh` with one subcommand per gate:

```bash
./scripts/run_test_gates.sh baseline
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh feed
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh posts
./scripts/run_test_gates.sh transport
./scripts/run_test_gates.sh all        # baseline + all subsystem gates
```

Each subcommand runs exactly the `flutter test` invocation for that gate. No flags, no tiers — one gate = one command.

### Step 5: Write the reference checklist
Create `Test-Flight-Improv/test-gates-reference.md` with:
- Exact file list per gate
- When to run each gate (trigger rules from report 14)
- Known failures as of Session 1 (if any)
- The single command to run it

### Step 6: Validate round-trip
Run `./scripts/run_test_gates.sh all` end-to-end to confirm the script works and matches the reference doc.

---

## 6. Risks and Edge Cases

| Risk | Mitigation |
|------|------------|
| **Some tests may currently fail** | Document known failures in the reference. Don't block gate definition on fixing them — that's future sessions' work. |
| **`integration_test/` files require a device/simulator** (`-d` flag) | Startup/Transport Gate tests live in `integration_test/` and need `-d <device>`. The script must handle this — either accept a `--device` arg or document that Transport Gate is run separately on device. |
| **Unassigned tests may not fit any gate cleanly** | It's fine to leave some tests outside gates. Not every test needs a gate — gates are for shared-pipeline protection. Standalone feature tests run via their own `flutter test test/features/X` path. |
| **Gate definitions drift as new tests are added** | The reference doc should include a rule: "When adding a new integration test, assign it to a gate or note it as standalone." |
| **Script vs. documentation disagreement** | The script IS the source of truth. The reference doc explains when to run each gate. If they diverge, the script wins. |

---

## 7. Exact Tests to Run After Implementation

Since Session 1 produces a script and a doc (no code changes), the verification is:

1. **Run the script itself:** `./scripts/run_test_gates.sh all`
2. **Spot-check each gate individually:**
   - `./scripts/run_test_gates.sh baseline`
   - `./scripts/run_test_gates.sh 1to1`
   - `./scripts/run_test_gates.sh feed`
   - `./scripts/run_test_gates.sh groups`
   - `./scripts/run_test_gates.sh posts`
3. **Startup/Transport Gate** requires a running simulator:
   - `./scripts/run_test_gates.sh transport` (or manual `flutter test -d <device>` commands)
4. **Confirm no test files are accidentally omitted:** diff the script's file lists against the actual test directories

---

## 8. Subsystem Gates and Whether Startup/Transport Tests Are Needed

| Gate | Needed for Session 1? | Reason |
|------|----------------------|--------|
| Baseline | YES — must run to confirm gate definition is correct | Validation |
| 1:1 Reliability | YES — must run to confirm gate definition is correct | Validation |
| Feed / Surface | YES — must run to confirm gate definition is correct | Validation |
| Group Messaging | YES — must run to confirm gate definition is correct | Validation |
| Posts / Privacy | YES — must run to confirm gate definition is correct | Validation |
| Startup / Transport | PARTIAL — only if a simulator is available during the session | These tests require `-d <device>` and may not run in a headless session. If unavailable, document the gate definition and defer validation to first device session. |

---

## 9. Done Criteria

- [ ] Every gate has one canonical `flutter test` command
- [ ] `scripts/run_test_gates.sh` exists and is executable
- [ ] Running `./scripts/run_test_gates.sh baseline` executes exactly the Baseline Gate tests
- [ ] `Test-Flight-Improv/test-gates-reference.md` documents: file list, trigger rules, known failures, and run command per gate
- [ ] Every test file from the 6 gates has been confirmed to exist on disk
- [ ] Unassigned integration tests have been evaluated and either added to a gate or documented as standalone/nightly
- [ ] Future sessions can say "run the 1:1 Reliability Gate" and mean exactly one command

---

## Staleness Assessment

**The session is NOT stale.** Report 14 already defines the gate contents well, but:

1. **8+ tests exist that aren't assigned to any gate** — these need evaluation (listed in Section 2)
2. **No runnable script exists** — the `scripts/` dir only has Go build and iOS deploy scripts
3. **Report 14's "suggested run commands" use shorthand** like `flutter test test/features/conversation/integration` which runs ALL integration tests in that dir, not just the gate members — this is imprecise and the script should be explicit
4. **The report's 1:1 Reliability shorthand (`flutter test test/features/conversation/integration`)** currently runs 10 test files, but only 8 are in the gate definition. The other 2 (`emoji_reaction_exchange_test`, `quote_reply_thread_test`) may belong but haven't been evaluated.

**Adjustment before implementation:** Read the 14 unassigned test files (Section 2) before writing the script, so the gate definitions are complete from day one.
