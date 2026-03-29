# Session 33 Plan — 1:1 Messaging Test Matrix Orchestrator

## Real Scope

What changes in this session:

- create one compact 1:1 messaging test matrix that maps existing tests to the
  combinations they already cover
- separate the matrix into:
  - deterministic two-user / fake-network coverage
  - real simulator or emulator + Go CLI peer coverage
  - device or nightly-only coverage
- add only the smallest missing high-value cells that are not already covered
  well enough by the current matrix
- keep the matrix explicit enough that future changes can pick the right direct
  suites and avoid re-discovering the same coverage questions

What does not change in this session:

- no generic Cartesian-product test generator
- no new parallel test app or alternate harness architecture
- no attempt to automate every manual/device-heavy scenario
- no reopening of group or announcement test programs here
- no product-scope chat feature work

---

## Closure Bar

This session is sufficient when all of the following are true:

- the current 1:1 messaging coverage is mapped into one explicit matrix
- it is clear which cells are already covered by deterministic tests
- it is clear which cells are already covered by simulator/emulator + CLI
  real-stack tests
- only the genuinely missing, high-value cells remain in execution scope
- voice/device-heavy and background/device-heavy cells are intentionally
  classified as manual or nightly if automation would be disproportionately
  expensive

This is a planning/coverage-closure session, not a promise to automate every
possible combination.

---

## Source of Truth

Authoritative sources for this session:

- current 1:1 closure bar:
  `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- regression policy:
  `Test-Flight-Improv/14-regression-test-strategy.md`
- named gate membership:
  `Test-Flight-Improv/test-gate-definitions.md`
- current deterministic 1:1 integration tests under
  `test/features/conversation/integration/`
- current real-stack and device-backed tests under `integration_test/`

Conflict rules:

- current code and tests beat stale prose
- `test-gate-definitions.md` and `scripts/run_test_gates.sh` win on named-gate
  membership
- this plan is the active execution contract unless repo evidence proves a cell
  already covered or a proposed new cell too expensive for the value

---

## Session Classification

`implementation-ready`

Why:

- the matrix can be built from existing repo evidence now
- the likely missing cells are already narrow enough to describe concretely
- most of the work is test classification and at most one or two focused
  additions, not a new subsystem

---

## Exact Problem Statement

The repo already has strong 1:1 coverage, but it is spread across different
layers:

- deterministic two-user fake-network tests
- optional/manual cross-feature tests
- simulator/emulator + Go CLI real-stack tests
- device/nightly tests

Because that coverage is not mapped in one place, it is easy to ask for “all
possible combinations” even when many important cells already exist. That
creates two risks:

1. we miss a real high-value gap because the current coverage map is unclear
2. we overengineer a giant new harness to solve a classification problem

What must improve:

- make the current matrix explicit
- identify only the real missing cells
- add only the smallest missing cells worth automating now

What must stay unchanged:

- reuse the current test layers
- keep fake-network tests as the fast matrix backbone
- keep device-heavy scenarios manual/nightly unless they are truly missing and
  worth the cost

---

## Files and Repos to Inspect Next

Primary docs:

- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`

Deterministic 1:1 coverage:

- `test/features/conversation/integration/two_user_message_exchange_test.dart`
- `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
- `test/features/conversation/integration/media_attachment_flow_test.dart`
- `test/features/conversation/integration/media_retry_smoke_test.dart`
- `test/features/conversation/integration/voice_message_exchange_test.dart`
- `test/features/conversation/integration/send_then_lock_delivery_test.dart`
- `test/features/conversation/integration/stuck_sending_recovery_test.dart`
- `test/features/conversation/integration/quote_reply_thread_test.dart`

Optional/manual 1:1 direct suites:

- `test/integration/onboarding_golden_path_test.dart`
- `test/integration/rapid_lock_unlock_integration_test.dart`
- `test/integration/relay_down_degradation_integration_test.dart`

Real-stack / device-backed coverage:

- `integration_test/transport_e2e_test.dart`
- `integration_test/scripts/run_transport_e2e.dart`
- `integration_test/soak_e2e_test.dart`
- `integration_test/voice_message_e2e_test.dart`
- `integration_test/wifi_transport_test.dart`
- `integration_test/conversation_bridge_test.dart`

Reference only:

- `integration_test/group_recovery_cli_e2e_test.dart`
  - useful as a pattern for CLI-coordinated recovery, but group-specific

---

## Existing Tests Covering This Area

### Current Matrix

| Cell | Current coverage | Status |
|------|------------------|--------|
| 1:1 text live bidirectional, deterministic | `two_user_message_exchange_test.dart` | covered |
| 1:1 text offline inbox, deterministic | `offline_inbox_roundtrip_test.dart` | covered |
| 1:1 media live flow, deterministic | `media_attachment_flow_test.dart` | covered |
| 1:1 media retry / interrupted upload, deterministic | `media_retry_smoke_test.dart`, `incomplete_upload_recovery_test.dart` via named gate | covered |
| 1:1 voice live send/receive, deterministic | `voice_message_exchange_test.dart` | covered |
| 1:1 send-then-lock / background interruption, deterministic | `send_then_lock_delivery_test.dart` | covered |
| 1:1 failed send during transport loss -> user keeps app open -> online-transition retry heals same row exactly once, deterministic | `relay_down_degradation_integration_test.dart` | covered as optional/manual direct suite |
| 1:1 failed send during transport loss -> user locks/pauses after failure -> resume heals same row exactly once, deterministic | `send_then_lock_delivery_test.dart` | covered |
| 1:1 rapid pause/resume / lock-unlock, deterministic | `rapid_lock_unlock_integration_test.dart` | covered as optional/manual direct suite |
| 1:1 relay-down degradation / exact-once recovery, deterministic | `relay_down_degradation_integration_test.dart` | covered as optional/manual direct suite |
| 1:1 onboarding-first-message confidence | `onboarding_golden_path_test.dart` | covered as optional/manual direct suite |
| Flutter simulator/emulator ↔ CLI text via relay/inbox | `transport_e2e_test.dart` + `run_transport_e2e.dart` | covered |
| Flutter simulator/emulator ↔ CLI degraded / CLI-down inbox fallback | `transport_e2e_test.dart` | covered |
| Flutter simulator/emulator ↔ CLI media send + receiver-side download verification | `transport_e2e_test.dart` Phase `E8` + `run_transport_e2e.dart` | covered |
| Flutter simulator/emulator ↔ CLI voice send/receive | no current real two-peer voice test | manual/nightly by design |
| Real device local WiFi text/media transport | `wifi_transport_test.dart` | covered at transport layer |
| Device-backed voice record/send surface | `voice_message_e2e_test.dart` | only local-record smoke |
| Long-running real-stack churn | `soak_e2e_test.dart` | covered nightly |

### What the matrix already tells us

- text coverage is strong across deterministic and real-stack layers
- background/degradation coverage already exists in deterministic form and does
  not justify a second large harness by default
- the network-switch failure seam that shows a visible failed state before
  later foreground or resume-time recovery is now pinned in deterministic
  regression coverage without creating a second harness
- richer payload proof on the simulator↔CLI path is now closed inside the
  existing `transport_e2e` orchestrator without adding a second harness
- the remaining real-stack 1:1 gap is voice, and it stays manual/nightly until
  a concrete product bug justifies automation

### Remaining intentionally deferred cell

1. real simulator/emulator ↔ CLI **voice send/receive**
   - still deferred to manual/nightly because the current repo only has
     device-backed local-record smoke, and the automation cost is still higher
     than the current risk signal

---

## Regression / Tests to Add First

Add or tighten only these proofs first:

1. `integration_test/transport_e2e_test.dart`
   - add one explicit receiver-side media verification cell on the
     simulator/emulator ↔ CLI path
   - keep it within the existing `transport_e2e` orchestrator instead of
     creating a new top-level harness
2. if the receiver-side media cell cannot be expressed cleanly in the current
   `transport_e2e` orchestration, document it as the one remaining missing cell
   rather than broadening scope

Do **not** add a real two-peer voice E2E by default in this session. That is
the first candidate to leave manual/nightly unless a real product bug proves it
worth the cost.

---

## Step-by-Step Implementation Plan

1. Create the compact matrix table in this session doc from the files listed
   above.
2. Mark every current cell as one of:
   - covered
   - partially covered
   - missing
   - manual/nightly by design
3. Keep the matrix focused on the axes that matter for 1:1 trust:
   - payload: text / media / voice
   - state: live / inbox / retry-recovery / interruption
   - environment: deterministic fake network / simulator-emulator + CLI /
     device-nightly
4. Confirm that deterministic coverage already closes most high-value cells.
5. Reuse `integration_test/transport_e2e_test.dart` and
   `run_transport_e2e.dart` for the one remaining high-value real-stack cell:
   receiver-side media verification.
6. Explicitly classify real two-peer voice E2E as manual/nightly unless current
   repo evidence shows an easy extension path with low complexity.
7. Stop after the matrix is explicit and the smallest missing real-stack cell is
   identified for automation.

Stop rule inside implementation:

- if a proposed new cell requires building a second orchestrator, multi-device
  fleet management, or a generic matrix generator, stop and leave it manual or
  nightly

---

## Risks and Edge Cases

- the matrix can become too broad if it mixes 1:1, groups, announcements, and
  posts in one session
- `transport_e2e_test.dart` is already large; adding more than one new cell can
  make it harder to maintain
- a real two-peer voice E2E may require more device/plugin stability than this
  session should take on
- background/lock behavior on real devices is valuable, but deterministic
  coverage already exists; duplicating it in the simulator↔CLI layer may be
  low signal

---

## Exact Tests and Gates to Run

Direct evidence / planning checks:

- inspect the files listed in this plan and ensure the matrix mapping matches
  actual coverage

If a receiver-side media cell is implemented in `transport_e2e_test.dart`:

- `dart run integration_test/scripts/run_transport_e2e.dart -d <simulator-id>`

If the orchestrator script is edited:

- rerun the same command above; do not substitute a smaller command

Named gates:

- `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport`
  - only if the real-stack transport integration files are changed
- `./scripts/run_test_gates.sh completeness-check`
  - only if a new test file is added or `test-gate-definitions.md` is changed

Not required by default:

- `./scripts/run_test_gates.sh 1to1`
- `./scripts/run_test_gates.sh baseline`
- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh feed`

Reason:

- this session is primarily test-matrix and integration-test orchestration work,
  not a shared production-code change

---

## Known-Failure Interpretation

- use `Test-Flight-Improv/test-gate-definitions.md` as the source of truth for
  current gate status
- `transport` is currently documented as green after Session 27 revalidation
- if `transport_e2e_test.dart` fails only in the newly added media-receive
  cell, treat that as the target regression
- do not classify unrelated device boot / debug-connection instability as a new
  chat-matrix regression unless the same scenario is reproducibly broken

---

## Done Criteria

- this session doc contains the explicit matrix table above
- the matrix clearly shows what is already covered vs what is still missing
- only the smallest high-value missing real-stack cell remains in execution
  scope
- real two-peer voice is intentionally classified as manual/nightly or
  separately justified before any automation is attempted
- no generic matrix generator or second orchestrator has been introduced

---

## Scope Guard

- do NOT create a brand-new harness when `transport_e2e_test.dart` already
  exists
- do NOT automate every possible payload/state/environment combination
- do NOT pull groups or announcements into this session’s execution scope
- do NOT broaden into product telemetry or benchmarking work
- do NOT turn this into a full QA framework project

---

## Accepted Differences / Intentionally Out of Scope

- deterministic fake-network tests remain the primary fast matrix backbone
- real two-peer voice can stay manual/nightly if the automation cost is too high
- real background/lock flows can remain covered by deterministic tests plus
  optional/manual suites unless a real escaped bug justifies simulator/CLI
  automation

---

## Dependency Impact

- future 1:1 reliability work should use this matrix to choose the smallest
  direct suites and real-stack checks instead of adding ad hoc tests blindly
- the exact "failed during network switch, later heals" seam now belongs to the
  deterministic matrix and should not trigger a new device-harness discussion
  unless a real device-only bug escapes those regressions
- if a later session adds a new 1:1 send surface or payload type, this matrix
  should be extended rather than replaced
- if a future real-stack voice bug appears, that is the justified trigger to
  reopen the currently deferred voice simulator↔CLI cell
