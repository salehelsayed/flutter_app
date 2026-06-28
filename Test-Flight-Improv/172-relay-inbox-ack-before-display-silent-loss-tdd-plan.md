# 172 - Relay-inbox drain: acked-then-silently-rejected 1:1 message loss  (Bug)

Status: awaiting-review
Spec: free-text intent (no formal spec) — derived from the 2026-06-28 live-relay incident postmortem (see project memory `project_old_build_msg_download_incident_2026_06_28`). Builds on landed work in `111-one-to-one-p0-silent-message-loss-tdd-plan.md`.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-28 | Evidence Collector | p2p_service_impl.dart, recovered_inbox_chat_disposition.dart, chat_message_listener.dart, main.dart, inbox_staging_db_helpers.dart, 111/114/141/147/146/48/115 docs | Bug LIVE at HEAD (5d54c028); only 111 Part A (decryptionFailed→quarantine) landed | Build matrix |
| 2026-06-28 | Planner | (above + tier-matrix/sufficiency refs) | Design B+C (NOT ack-after-commit — relay INBOX_FULL back-pressure) | Emit plan |
| | Reviewer (sufficiency) | | | |
| | Arbiter | | (final structural verdict) | hand off to execution |

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
- Spec / intent: this doc (incident postmortem) + `111-one-to-one-p0-silent-message-loss-tdd-plan.md` (INV-1)
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose), `scripts/run_host_test_gates.sh`
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh`
- Numbering / index: `Test-Flight-Improv/00-INDEX.md`

## Session Classification
implementation-ready (host-only for closure; reliability-sim 1:1 leg is the end-to-end closure gate)

## Exact Problem Statement
The 1:1 relay-inbox drain is **stage → ACK → replay** (`lib/core/services/p2p_service_impl.dart:1859` `stageEntries` → `:1887` `callP2PInboxAck` deletes the relay copy → `:1916` `_replayStagedInboxEntries` decrypts/persists/displays). After the ACK the relay copy is gone, so the local `inbox_staging_entries` row is the only surviving copy. `_applyRecoveredInboxOutcome` (`:1656-1734`) maps each replayed entry to `committed` (delete + display), `retryable` (kept, re-driven), `quarantined` (kept, **never displayed**), or `rejected` (`markRejected` — kept-as-row but **never written to the messages DB, never displayed, never re-queried**; emits only an internal flow event). Six outcomes still map to `rejected` (`lib/features/conversation/application/recovered_inbox_chat_disposition.dart`): `blockedSender:56`, `notChatMessage:62`, `unknownSender:68`, `duplicate:74`, `ignoredEdit:80`, `editMissingOriginal:86`. Because custody already transferred at the ACK, a **transient or false** rejection (e.g. a contact-row race making a real sender look `unknownSender`; an edit whose original arrives in a later relay page reported `editMissingOriginal`; a false `duplicate`) is **permanent, invisible message loss with zero user-visible signal** — exactly the 2026-06-28 incident (build-106 retrieved+ACKed 5 messages, chat showed nothing). `quarantined` rows (the landed 111 Part A `decryptionFailed` fix) survive the ACK but are *also* never surfaced, so even that mitigation reproduces the "acked, kept, invisible" symptom.

What must improve:
1. No 1:1 inbound message may be permanently dropped by a **recoverable/transient** replay rejection after custody transfer (INV-1: "rejected after custody transfer is forbidden").
2. A staged entry that genuinely cannot be displayed yet (quarantined, or a hard-rejected-but-recoverable class) must be **user-visibly surfaced**, not silently invisible.

What must stay unchanged (→ preserved-green sentinels):
- The `stage → ACK → replay` ordering and the local-stage-before-ACK custody guarantee (do NOT convert to ack-after-commit — see Root Cause).
- `committed` still deletes+displays; the four content-safe/policy drops that are genuinely safe to never display stay terminal.
- 111 Part A `decryptionFailed → quarantined`; all landed inbox tests (37/37 per the test inventory).

## Root Cause (verify → refute confirmed)
Confirmed at HEAD `5d54c028` by a 6-agent verify→refute workflow:
- Ack-before-display is **unchanged from build 106**: `p2p_service_impl.dart:1859` (stage) → `:1887` (`callP2PInboxAck`, deletes relay copy) → `:1914-1916` (replay). 
- `rejected` is terminal+silent: `:1707-1723` `repo.markRejected` + flow event only; `getRecoverableEntries`/`...ByIds` read only `pending`+`retryable` (`inbox_staging_db_helpers.dart:5` `const _recoverableInboxStagingStatuses`), so `rejected` AND `quarantined` are never re-queried/displayed.
- Residual live surface = the six `rejected`-class outcomes, of which `unknownSender`, `duplicate`, `editMissingOriginal` are **recoverable/transient** yet permanently dropped post-ACK.

**Refuted / do-NOT-re-introduce:**
- **Design A (ack-after-commit for the relay drain) — REJECTED.** The deployed relay now returns `INBOX_FULL`/`rejected_full` and fires **no push** when a peer's inbox hits 100 (`go-relay-server/inbox.go:878-885,1613-1620`). Holding the relay copy until after local commit lengthens relay-side residency for every drained entry, raising occupancy and making `INBOX_FULL` more likely — which drops *new inbound sends at the relay* (a worse, sender-side silent loss). Ack-after-commit back-pressures the relay into the exact failure it prevents, and discards the already-landed stage-before-ACK durability for no gain. (114 ack-after-commit is **LAN-only**: `p2p_service_impl.dart:3946-3947`.)
- 147/146 are pure perf and preserve the disposition machine — no #172 effect.
- 48 GAP-3 removed the destructive `inbox:retrieve` fallback (a precondition: stage-before-ACK), not the post-ack disposition.
- 141 fixed only the drain-**never-ran** case; #172 is the drain-**ran-then-rejected** case (incident relay logs prove the drain ACKed).
- 115 is the SENDER-side false-`delivered` custody bug (CLOSED+DEPLOYED), a different loss class.
- `decryptionFailed` is already `quarantined` (NOT `rejected`) — do not re-reclassify it as retryable (key may never arrive); instead **surface** it (B2).

## Real Scope
In scope (client only; no relay change):
- **B1 — reclassify recoverable rejections as `retryable`-with-cap:** `unknownSender` (when the `main.dart:2065-2076` resolver did not return a hard `rejected`), `editMissingOriginal`, and `duplicate`-when-the-prior-copy-is-not-actually-persisted → `retryable`; bounded by `maxInboxReplayAttempts` then → `quarantined` (never infinite retry, never silent drop). Generalize the `unknownSender` retryable guarantee from the `main.dart` pre-step into `recovered_inbox_chat_disposition.dart` so it does not depend on the resolver firing first.
- **C — keep content-safe/policy drops terminal:** `blockedSender`, `notChatMessage`, `ignoredEdit` stay `rejected` (intentional non-display, not loss) — test-locked against over-reclassification.
- **B2 — surface the invisible:** a counted, user-reachable "couldn't display N messages" affordance keyed off `dbCountQuarantinedInboxStagingEntries` + a new rejected-recoverable count, so a kept-but-undisplayed entry is never silently invisible.
- **Sibling-surface parity:** audit the inline replay-disposition mappings for reaction/deletion/introduction/contact_request (`main.dart:2095-2275`) for the same post-ACK silent-rejected-drop; apply the same recoverable→retryable parity or test-lock the asymmetry.
- **Neutralize the regression-masking sentinel:** `test/core/resilience/c4_partial_drain_test.dart:392` asserts permanent loss is acceptable on the legacy `FakeP2PService.drainOfflineInboxCount` path (auto-globbed into the resilience gate). Update it so it does not assert "loss is fine" on a path adjacent to this fix.

Out of scope (owning work named):
- Any ack-after-commit / relay custody change (refuted above; relay capacity is plan **#173**'s subject).
- Deep quarantine **repair** (auto re-decrypt of a `decryptionFailed` quarantine on ML-KEM key arrival) → follow-up session "inbox-quarantine-repair" (B2 here only *surfaces*; it does not auto-heal decrypt).
- Retroactive recovery of the already-acked-and-dropped build-106 incident message (impossible — relay copy gone; only a sender resend recovers it).

## Files To Inspect Next
Production: `lib/features/conversation/application/recovered_inbox_chat_disposition.dart` (the mapper), `lib/core/services/p2p_service_impl.dart:1656-1734` (`_applyRecoveredInboxOutcome`, the retryable attempt-cap at `:1681`), `lib/main.dart:2065-2076` (unknownSender pre-step) + `:2095-2275` (sibling replay mappings), `lib/core/database/helpers/inbox_staging_db_helpers.dart` (`_recoverableInboxStagingStatuses:5`, `dbCountQuarantinedInboxStagingEntries`), `lib/features/conversation/application/chat_message_listener.dart:27-40` (`ChatMessageProcessState` enum), `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart` (produces the states; trace which branch emits `duplicate`/`unknownSender`/`editMissingOriginal`).
Direct tests + integration tests: `test/features/conversation/application/recovered_inbox_chat_disposition_test.dart`, `test/core/services/p2p_service_impl_test.dart` (disposition guards `:2471/2531/2592`), `test/core/services/p2p_service_contact_request_inbox_replay_test.dart`, `test/core/inbox/inbox_round_trip_test.dart:394`, `test/core/resilience/c4_partial_drain_test.dart:392`.
Dependency-only context: `lib/core/database/migrations/045_inbox_staging_entries.dart` (has `status`, `reject_reason_code`, `reject_reason_detail` already), `test/features/p2p/inbox_custody_verify_test.dart` (strongest ack-gated-delete proof; in NO gate).

## Existing Tests Covering This Area
- `recovered_inbox_chat_disposition_test.dart` — locks the disposition mapping (incl. `decryptionFailed→quarantined`). PURE UNIT mapping; passes today. (ONE_TO_ONE array, run_test_gates.sh `:42`)
- `p2p_service_impl_test.dart` (`:2471/2531/2592`) — quarantined/rejected/retryable dispositions keep/mark the staged row; **inject SYNTHETIC dispositions** via the replay closure, not the real listener. Passes. (ONE_TO_ONE `:52`)
- `p2p_service_contact_request_inbox_replay_test.dart` — durable persist before `deleteEntry` (INV-1). Passes.
- `inbox_round_trip_test.dart:394` — asserts unknown-sender messages are **dropped** (documents the rejection as intended; does NOT guard a FALSE unknownSender). Passes. (ONE_TO_ONE `:33`)
- `inbox_custody_verify_test.dart:251` — relay deletes the entry ONLY after stage+ack. Strongest custody proof. **Not in any gate array.**

Missing coverage gaps:
- No test proves a `rejected`-class classification is **correct vs a transient upstream cause** (the incident class).
- No test runs the **real** `handle_incoming_chat_message` → mapper → disposition wiring end-to-end through the staged drain (all guards inject synthetic dispositions).
- No test proves a quarantined/rejected entry is ever **surfaced** to the user (no-silent-loss is proven only at DB-durability, not visibility).
- No reliability-sim covers "1:1 drain → ACK → message MUST appear in the UI."
- `c4_partial_drain_test.dart:392` asserts loss-is-acceptable on a legacy path = **regression-masking hazard.**

Already in curated family arrays?: ONE_TO_ONE_TESTS lists `inbox_round_trip:33`, `handle_incoming_chat_message:38`, `recovered_inbox_chat_disposition:42`, `verify_inbox_custody_use_case:49`, `inbox_staging_db_helpers:50`, `inbox_staging_repository_impl:51`, `p2p_service_impl_test:52`, `handle_incoming_message:64`, `contact_request_one_scan_mutual:70`; `offline_inbox_roundtrip` in BASELINE `:11` + ONE_TO_ONE `:19`. `inbox_custody_verify_test.dart` and `c4_partial_drain_test.dart` are NOT in any array (c4 auto-globs into the core-resilience gate).

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)
1. `test/features/conversation/application/recovered_inbox_chat_disposition_test.dart`::`unknownSender maps to retryable (recoverable), not rejected`
   - Tier: unit/application
   - Shape/setup: call `mapChatReplayOutcomeToDisposition(ChatMessageProcessState.unknownSender)` (no resolver context).
   - RED on HEAD because: it returns `rejected` (`:68`).
   - GREEN after fix asserts: returns `retryable` (with a recoverable reason code).
   - Mutation that re-reds: revert `unknownSender` mapping back to `rejected` → this test red.
   - Distinct-event discriminator: assert reason code `unknown_sender_recoverable` AND NOT a terminal `markRejected`.
2. same file::`editMissingOriginal maps to retryable (original may arrive later)`
   - Tier: unit/application; RED: returns `rejected` (`:86`); GREEN: `retryable`; mutation: revert → red.
3. same file::`duplicate stays rejected only when the prior message is actually persisted`
   - Tier: unit/application (mapper takes a `priorMessageVisible` signal); RED: `duplicate` unconditionally `rejected` (`:74`); GREEN: `rejected` iff prior row exists+visible, else `retryable`; mutation: drop the `priorMessageVisible` guard → red. Discriminator: `duplicate_confirmed_visible` vs `duplicate_unverified_retry`.
4. same file::`content-safe drops stay terminal rejected`  (lock against over-reclassification)
   - Tier: unit/application; asserts `blockedSender`/`notChatMessage`/`ignoredEdit` → `rejected`. RED on HEAD: passes today → this is a **preservation lock** (goes RED only if the fix over-reclassifies). Mutation: reclassify any of the three to retryable → red.
5. `test/core/services/p2p_service_impl_test.dart`::`recoverable rejection retried past cap transitions to quarantined, never deleted`
   - Tier: integration (real staged drain over fakes + real SQLCipher); RED on HEAD: a recoverable outcome never becomes retryable so the cap path is unreached / entry is `markRejected`; GREEN: after `maxInboxReplayAttempts` the row is `quarantined` (kept), never `deleteEntry`, never `markRejected`. Mutation: revert the retryable reclassification (TC-01..03) → red. (`p2p_service_impl.dart:1681`)
6. `test/core/services/p2p_service_impl_test.dart`::`unknownSender on drain N becomes displayed on drain N+1 after contact materializes`  (the direct #172 reproduction — drives the REAL mapper, not a synthetic disposition)
   - Tier: integration (two-party fakes + real migrations); RED on HEAD: drain-N maps `unknownSender→rejected→markRejected`, drain-N+1 finds no recoverable row → message never persisted (`messageRepo` empty). GREEN: drain-N keeps it `retryable`; after the contact row materializes, a re-prime re-drives it → `committed` → `messageRepo` has the row. Mutation: revert reclassification → red. PROD-CRITICAL repro.
7. `test/core/database/helpers/inbox_staging_db_helpers_test.dart`::`needs-attention surface counts quarantined + recoverable-exhausted rows`
   - Tier: integration / repo-host (real SQLCipher); RED on HEAD: no such count/query exists (only `dbCountQuarantinedInboxStagingEntries`); GREEN: a query returns quarantined + capped-recoverable counts for the surfacing affordance. Mutation: revert the query → red. (gate: core-host-all auto-glob; also add to ONE_TO_ONE)
8. `test/features/conversation/presentation/<undelivered_messages_banner>_test.dart`::`shows "couldn't display N messages" when quarantined/recoverable-exhausted entries exist`
   - Tier: widget; RED on HEAD: no such affordance widget; GREEN: banner renders count from TC-07's query; tapping offers retry/resend. Mutation: hide the affordance → red. SYNC teardown for any IO.
9. `test/core/resilience/c4_partial_drain_test.dart`::`partial drain does NOT permanently lose messages on the staged path`  (replace/neutralize the masking assertion at `:392`)
   - Tier: integration; RED on HEAD: current test asserts `expect(secondDrain, 0)` = loss-is-fine on the legacy `drainOfflineInboxCount` path; GREEN (rewrite): on the staged path a partially-failed drain leaves the entry recoverable (re-driven next drain), asserting no permanent loss. Mutation: revert reclassification → red. (Marks the legacy at-most-once doc as legacy-only; not the staged path.)
10. reliability-sim 1:1 closure scenario `1to1 inbox drain → ACK → message appears`
    - Tier: simulator E2E (`integration_test/`, real bridge); RED on HEAD: a 1:1 message sent while the receiver has not yet materialized the sender contact is acked then never shown; GREEN: it becomes visible after intro/contact recovery, never silently lost. Mutation: revert reclassification → sim red. Closure gate.

## Test Coverage Matrix  (ZERO empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 unknownSender recoverable | pure logic (mapper) | unit/application | recovered_inbox_chat_disposition_test.dart::unknownSender maps to retryable | maps to `rejected` (:68) | revert mapping→rejected | `./scripts/run_test_gates.sh 1to1` | AUTO (glob) + already in ONE_TO_ONE :42 |
| TC-02 editMissingOriginal recoverable | pure logic | unit/application | recovered_inbox_chat_disposition_test.dart::editMissingOriginal maps to retryable | maps to `rejected` (:86) | revert→rejected | `./scripts/run_test_gates.sh 1to1` | AUTO + ONE_TO_ONE :42 |
| TC-03 duplicate guarded by prior-visible | pure logic + discriminator | unit/application | recovered_inbox_chat_disposition_test.dart::duplicate stays rejected only when prior persisted | `duplicate` unconditionally rejected (:74) | drop priorVisible guard | `./scripts/run_test_gates.sh 1to1` | AUTO + ONE_TO_ONE :42 |
| TC-04 content-safe stays terminal | preservation lock | unit/application | recovered_inbox_chat_disposition_test.dart::content-safe drops stay terminal rejected | (lock; reds only if over-reclassified) | reclassify any→retryable | `./scripts/run_test_gates.sh 1to1` | AUTO + ONE_TO_ONE :42 |
| TC-05 attempt-cap→quarantine | repo+DB state | integration | p2p_service_impl_test.dart::recoverable rejection retried past cap → quarantined | cap path unreached; entry markRejected | revert TC-01..03 | `./scripts/run_test_gates.sh 1to1` | already in ONE_TO_ONE :52 |
| TC-06 incident reproduction | two-party, real mapper | integration | p2p_service_impl_test.dart::unknownSender drain N → displayed drain N+1 | drain-N rejects→never persisted | revert reclassification | `./scripts/run_test_gates.sh 1to1` | ONE_TO_ONE :52 |
| TC-07 surfacing query | repo+DB | integration/repo-host (real SQLCipher) | inbox_staging_db_helpers_test.dart::needs-attention surface counts | no such query exists | revert query | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (core/**) + add to ONE_TO_ONE |
| TC-08 surfacing UI | widget | widget | undelivered_messages_banner_test.dart::shows "couldn't display N messages" | no affordance widget | hide affordance | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| TC-09 anti-mask | integration | integration | c4_partial_drain_test.dart::partial drain does NOT permanently lose (staged path) | current asserts loss-OK (:392) | revert reclassification | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (core/resilience glob) |
| TC-10 E2E closure | real bridge/relay | simulator | reliability-sim `1to1` drain→ack→appears | acked then never shown | revert reclassification | `./scripts/run_test_gates.sh reliability-sim` then `/sims 1to1 --only N` | classify_path() case in check_reliability_simulation_discovery.sh + `--scenario` |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** TC-05 + TC-07 — assert a recoverable/quarantined row **survives a process restart** (real SQLCipher) and the surfacing count **reconstructs** on reopen (not just that the row persists). Add a reopen assertion to TC-07.
- **Sibling-surface consistency:** the inline replay-disposition mappings for reaction/deletion/introduction/contact_request (`main.dart:2095-2275`) — add TC-11 (unit) asserting each either applies the same recoverable→retryable parity OR its `rejected`-class is genuinely content-safe (test-locked asymmetry). NOT N/A — the grounding flagged this path as un-cross-checked.
- **Destructive-action side-effects:** `markRejected` is the destructive terminal here — TC-05/TC-09 assert what is **preserved** (the staged row + ciphertext) and that no `deleteEntry` fires for a recoverable outcome, not merely that a flow event emits.
- **Invariant re-verification under new transitions:** TC-05 — the new `retryable→quarantine` cap transition re-verifies INV-1 (post-transition the entry is still kept + now surfaced, never silently dropped); assert the full post-transition row state (status, reason code, attempt count).

## Invariants (locked by tests)
- INV-1 (from 111): "rejected after custody transfer is forbidden" for recoverable causes → TC-01/02/03/05/06.
- INV-2: every kept-but-undisplayed entry (quarantined or recoverable-exhausted) is user-visibly surfaced → TC-07/08.
- INV-3: content-safe/policy drops (blocked/notChat/ignoredEdit) remain terminal (no retry storm) → TC-04.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row.

## Step-By-Step Implementation Plan
1. Snapshot `git status --short`; add RED tests TC-01..TC-09 (host) and confirm each fails for the documented reason.
2. Edit `recovered_inbox_chat_disposition.dart`: reclassify `unknownSender`/`editMissingOriginal`→`retryable` (recoverable reason codes); add a `priorMessageVisible` parameter so `duplicate`→`rejected` only when the prior copy is actually persisted, else `retryable`. Keep `blockedSender`/`notChatMessage`/`ignoredEdit`→`rejected`. Keep `decryptionFailed`→`quarantined`.
3. In `p2p_service_impl.dart` `_applyRecoveredInboxOutcome`: thread the `priorMessageVisible` signal; ensure the existing `maxInboxReplayAttempts` cap (`:1681`) routes an exhausted *recoverable* entry to `quarantined` (not `rejected`/delete). Stop-if: the cap path also catches genuine content-safe rejections → keep them terminal (re-check TC-04).
4. Add the surfacing query (`inbox_staging_db_helpers.dart`) for quarantined + recoverable-exhausted counts (TC-07) and the banner affordance (TC-08).
5. Apply sibling-surface parity in `main.dart:2095-2275` (TC-11) or test-lock the asymmetry.
6. Rewrite `c4_partial_drain_test.dart:392` to assert no-permanent-loss on the staged path (TC-09); keep the legacy at-most-once note scoped to the legacy fake path.
7. Rerun direct → preservation → named gates → reliability-sim 1:1 (TC-10).

## Risks And Edge Cases
- **Retry storm:** a genuinely-undeliverable recoverable entry must hit the cap → quarantine, not loop forever → pinned by TC-05.
- **Duplicate double-loss:** reclassifying `duplicate` must not resurrect a truly-already-shown message → pinned by TC-03 discriminator.
- **Relay back-pressure:** do NOT hold the relay copy (no ack-after-commit) — keeps relay occupancy low so #173's `INBOX_FULL` path is not aggravated.
- **Sibling drift:** reaction/deletion/contact_request replay could silently drop too → TC-11.

## Device/Relay Proof Profile
host-only for closure of TC-01..09; **reliability-sim 1:1 (TC-10) is the end-to-end closure gate.**
Closure scenario: `/sims 1to1 --only N` (no feature flag flip needed; behavior-on by default — guard behind `FDC_INBOX_RECLASSIFY_DISABLE=1` kill-switch per prior FDC ship-on-with-disable pattern).
Deferred device work → none (no OS-boundary change). Relay defaults if needed: `/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1…` (see `/sims`).

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# RED (before production edits) — must FAIL for the documented reason
flutter test test/features/conversation/application/recovered_inbox_chat_disposition_test.dart --plain-name 'unknownSender maps to retryable'
flutter test test/core/services/p2p_service_impl_test.dart --plain-name 'unknownSender drain N'

# Direct GREEN (after fix)
flutter test test/features/conversation/application/recovered_inbox_chat_disposition_test.dart
flutter test test/core/services/p2p_service_impl_test.dart
flutter test test/core/database/helpers/inbox_staging_db_helpers_test.dart
flutter test test/core/resilience/c4_partial_drain_test.dart

# Preservation sentinels (must stay green) — expect prior baseline count, 0 fail
./scripts/run_test_gates.sh 1to1            # expect: prior 1to1 total + new TCs, 0 fail
./scripts/run_host_test_gates.sh core-host-all
./scripts/run_host_test_gates.sh feature-host-all

# Simulator discovery + run (TC-10)
./scripts/check_reliability_simulation_discovery.sh   # new 1:1 drain→appears scenario MUST list
# /sims 1to1 --list  → note --only N  → /sims 1to1 --only N   (resume: --start-at N)

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```
(No `DB v##` migration expected — the fix reuses existing `inbox_staging_entries.status`/`reject_reason_code`. If B2 adds a `needs_attention`/`surfaced_at` column, allocate **DB v095** — latest is `094_group_messages_group_ts_index.dart` — and add `test/core/database/migrations/095_*_test.dart` with real SQLCipher PRAGMA + run-twice idempotency.)

## Known-Failure Interpretation
- Expected RED: TC-01..03,05..09 before fix.
- Pre-existing dirty: the shared tree has concurrent WIP (e.g. `contact_request_listener.dart`, `node.go`) — snapshot `git status --short` first; do not revert others' files.
- Environment blocker (NOT product): missing simulator for TC-10 → run host gates; defer sim to a machine with a booted device.
- Scope drift (BLOCKING): any failure outside the inbox-drain/disposition files, or any relay (`go-relay-server/`) change (that is #173).

## Done Criteria
- [ ] RED added first, failed for the expected reason.
- [ ] Each fix mutation-verified (revert re-reds).
- [ ] Direct GREEN + 1to1/core-host/feature-host sentinels + reliability-sim 1:1 pass.
- [ ] No new migration, OR a real-DB migration test if a column was added.
- [ ] TC-10 proven on a sim (the wire/transport leg), not a fake.
- [ ] Every new test's harness-registration done & verified in a gate run (classify_path for TC-10; ONE_TO_ONE array for TC-07).
- [ ] flutter analyze 0 new; git diff --check clean; no Scope Guard violations.

## Scope Guard (hard "Do not")
- Do not change `go-relay-server/` (relay capacity/push = plan **#173**).
- Do not convert the relay drain to ack-after-commit (refuted; back-pressures `INBOX_FULL`).
- Do not reclassify `decryptionFailed` (stays quarantined) or the content-safe set.
- Do not delete the `RejectedFull`/INBOX_FULL client parser.

## Accepted Differences / Intentionally Out Of Scope
- Auto-repair of `decryptionFailed` quarantines on ML-KEM key arrival → follow-up "inbox-quarantine-repair" (this plan only surfaces).
- Retroactive recovery of the build-106 incident message → impossible (sender resend only).

## Dependency Impact
- Independent of #173 (client vs relay). Both close the same incident from opposite sides; neither blocks the other.

## Reviewer Findings
<verbatim sufficiency / missing-coverage / scope-risk verdict — fill at review>

## Arbiter Decision
Structural blockers: … | Deferred details: … | Accepted differences: …

## Final Execution Verdict
Verdict: … | Files changed: … | Tests run (+counts): … | Blocking: … | QA verdict: … | Non-blocking follow-ups (owner):
