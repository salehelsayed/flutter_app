# 184 - Optimistic 2-tick send-status progression for 1:1 messages  (Feature Improvement)

Status: IMPLEMENTED + DEVICE-CONFIRMED (TC-184-30 PASS) — executed + device-confirmed 2026-06-30
Spec: `Test-Flight-Improv/184-optimistic-2tick-send-status-progression-spec.md`

> **One-line:** today the ~110 ms relay-custody ACK only records a metric and the bubble's status flips once at the end (~1.8 s offline). This plan surfaces an honest **custody-confirmed milestone mid-send** — `sending`(1 tick) → `inboxed`(2 ticks, ~110 ms) → transport glyph (live) / error — via **one new status persist at the inbox ACK** + **one glyph mapping change**, reusing the existing `messageChanges` re-render channel. Status-surfacing only; no transport/race/inbox-mechanics change.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-30 | Evidence Collector | send_chat_message_use_case.dart:712-751, letter_card.dart:1037-1143, conversation_wired.dart:1529-1606/2144-2165/2410-2480, message_repository_impl.dart:141, conversation_screen.dart:633, letter_card_test.dart:219-446, conversation_wired_sending_to_failed_test.dart | Seam confirmed: `.then` at :733 records metric only; `messageChanges` gate already admits `'inboxed'`; 1:1 path = `_resolvedStatusIcon` (transportStatusGlyph true) | hand to Planner |
| 2026-06-30 | Planner | tier-matrix.md, sufficiency-checklist.md, plan-template.md | Two prod edits (one persist, one glyph) + flow-event discriminator + test-surface rewrites | emit matrix + plan |
| 2026-06-30 | Reviewer (sufficiency) | this plan | see Reviewer Findings | — |
| 2026-06-30 | Arbiter | this plan | see Arbiter Decision | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-06-30 | contract extraction | git status --short | working tree carries uncommitted 500ms-budget + clock→tick experiments + 181/182/183/184 docs | scope confirmed — leave the two experiments | RED-first |
| 2026-06-30 | RED tests added | letter_card_test, send_presence_emphasis, conversation_wired_sending_to_failed | baseline run: 3 files = `+114 -6` (the 6 = clock→tick `schedule_rounded` stragglers); after adding new tests = `+121 -5` (TC-184-02/21/10/13/22 FAIL for documented reasons; guard locks 12/14 PASS) | RED confirmed | implement |
| 2026-06-30 | implementation | send_chat_message_use_case.dart (`.then` → `updateMessageStatus(id,'inboxed')` + `CHAT_MSG_SEND_CUSTODY_CONFIRMED`, `liveDelivered` guard); letter_card.dart (`_resolvedStatusIcon` inboxed→`done_all_rounded`) | status-only update chosen over saveMessage (plan-sanctioned) so the `saved` append-list — and thus the preservation sentinel — stays untouched | scoped files only | GREEN |
| 2026-06-30 | direct GREEN | letter_card_test, send_presence_emphasis (9/9), conversation_wired_sending_to_failed, conversation_wired_test (105/105) | each file → All tests passed | reds now green | preservation |
| 2026-06-30 | preservation GREEN | send_chat_message_use_case_test.dart | only 6 FDC budget/timing tests fail; **proven pre-existing** — same 6 fail with 184 fully reverted (the uncommitted 500ms experiment, Scope-Guard out-of-scope). 184 adds 0 sentinel regressions | sentinels green (mod pre-existing) | gates |
| 2026-06-30 | named gates | feature-host-all (fail-fast aborts at the pre-existing 500ms file #109; all 184-affected files run individually = green), completeness-check = PASS (1000/1000), flutter analyze = 0 NEW (3 pre-existing info/warn), git diff --check = clean | blast-radius swept exhaustively: Edit-2 only `conversation_wired_test:7762` (fixed) + 4 clock→tick `schedule_rounded` (cleaned up); Edit-1 callers (offline_inbox_roundtrip, p2p_service_transport_census) green | gate green (mod pre-existing experiments) | QA |
| 2026-06-30 | QA (mutation-verified) | — | Mutation A (drop `!liveDelivered`)→TC-184-12 RED; Mutation B (drop `ok`)→TC-184-14 RED; glyph/custody RED-on-HEAD already proven | blocking: none | accepted |

## Source Of Truth
- Spec / intent: `Test-Flight-Improv/184-optimistic-2tick-send-status-progression-spec.md`
- Gate definitions: `scripts/run_test_gates.sh` (script wins) → `scripts/run_host_test_gates.sh`
- Discovery/registration: `scripts/run_test_gates.sh completeness-check`
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (reuses spec NN=184)

## Session Classification
implementation-ready (fully host-closable — widget + application/integration tiers; an optional single-device UX proof confirms the perceived timing but is NOT a boundary host cannot test).

## Exact Problem Statement

A 1:1 send confirms its status **late and all-at-once**. The message is durably safe at the ~110 ms concurrent-inbox ACK, but that ACK currently **only records a transport metric** (`send_chat_message_use_case.dart:733-736`) — it does not change the message status. The visible status therefore flips **once, at the end** of the live race: ~150–350 ms for a live peer and **~1.8 s for an offline peer**. Between tap and that flip the bubble shows only the optimistic single tick (the just-landed clock→tick change), with **no honest "the system has it" milestone**.

**What must improve:** a progressive, honest, instant-feeling confirmation —
`tap → 1 tick (sending) → 2 ticks (relay custody, ~110 ms) → transport glyph (live delivery) / error (true fail)`. For an **offline** peer the bubble rests at **2 ticks** (custody) instead of sitting on a single optimistic tick until the ~1.8 s race timeout.

**What must stay unchanged (→ preserved-green sentinels):**
- Send transport/race/budgets/inbox mechanics — untouched (`send_chat_message_use_case_test.dart`, `send_presence_emphasis_test.dart` C5/C6/C7).
- Group/legacy status glyphs — the v1 `_statusIcon` (`inbox_rounded` for inboxed) is unchanged; the 2-tick is **1:1 only** (`transportStatusGlyph==true`).
- The `failed`/`send_failed` error glyph and the `delivered`+transport→transport-glyph reached behavior.

## Root Cause (verify → refute confirmed)

Confirmed first-hand on HEAD (working tree):
1. **Mid-send status is never surfaced.** The concurrent durable inbox (`send_chat_message_use_case.dart:717-737`, gated on `unknownPresence` `:718`) resolves its `.then((ok){...})` at **`:733-736`** doing ONLY `transportMetrics?.recordAttempt(leg:'inbox', succeeded:ok)`. No `saveMessage`, no status change, no flow event. Status is written only at the terminal `saveMessage` (`_persistOutgoingSendResult` `:2012`, `persistInboxAccepted` `:1119`).
2. **The re-render channel already exists and already admits `'inboxed'`.** `MessageRepositoryImpl.saveMessage` emits on `messageChanges` (`message_repository_impl.dart:141`); the screen gate `_shouldRefreshFromRepositoryChange` admits `sent||delivered||failed||inboxed` (`conversation_wired.dart:1602-1606`). So a mid-send `saveMessage(status:'inboxed')` re-renders the bubble with **no screen-code change**.
3. **The 1:1 glyph path renders `inboxed` as the transport (inbox) glyph, not two ticks.** `_resolvedStatusIcon` (`letter_card.dart:1131-1143`, active when `transportStatusGlyph==true`, set `conversation_screen.dart:633`): reached (`sent/delivered/inboxed/queued`) → `_transportIcon(transport)` if non-null. `'inboxed'` carries `transport:'inbox'` → `Icons.inbox`. The two-tick `done_all` is RETIRED (`:1062-1064`).

**Refuted / do-NOT-re-introduce:**
- *"The status stream needs new wiring":* refuted — `messageChanges` already admits `'inboxed'`; no screen subscription change is needed.
- *"2-tick means delivered-to-recipient-device":* refuted/out-of-scope — here 2 ticks = **relay custody**, NOT recipient receipt. (`done_all` is borrowed as the glyph; the read-receipt meaning the model reserves it for is not claimed.)
- *"Connected/reuse sends also get a mid-send 2-tick":* refuted — the concurrent inbox is gated on `unknownPresence` (`:718`); a connected peer (reuse fast-path) has no concurrent inbox and delivers live → it shows the transport glyph directly (correct; no spinner to fix there).

## Real Scope

**In scope (TWO production edits + their tests):**
1. `lib/features/conversation/application/send_chat_message_use_case.dart` — inside the concurrent-inbox `.then` at `:733`, on `ok==true` AND only while the message is not already terminally `delivered` (ordering guard): **persist a `status:'inboxed', transport:'inbox'` update for `resolvedMessageId`** (same `messageRepo` channel the terminal saves use) and emit a NEW discriminator flow event **`CHAT_MSG_SEND_CUSTODY_CONFIRMED`** (`{id, targetPeerId}`). This is the custody milestone.
2. `lib/features/conversation/presentation/widgets/letter_card.dart` — in `_resolvedStatusIcon` (1:1 path), return `Icons.done_all_rounded` for `status=='inboxed'` (BEFORE the reached/transport-glyph fallback). `delivered`+transport keeps `_transportIcon`; legacy `_statusIcon` unchanged. (Color: `_statusColor` already returns the neutral muted color for `inboxed` `:1099-1102` — no color change needed; the 2-tick is neutral, not amber.)

**Out of scope (owning work):**
- Send transport/race/**budgets** (the uncommitted 500 ms experiment in this same file) — **do NOT touch/revert/bundle**; it is a separate experiment.
- The keepalive (`183`), connectivity-restore drain (`182`).
- Group/legacy glyphs; read receipts; the incoming-message transport glyph.

## Files To Inspect Next
- Production (edit): `send_chat_message_use_case.dart` (`:733` persist+event), `letter_card.dart` (`_resolvedStatusIcon` `:1131-1143`).
- Production (read-only, assert unchanged): `conversation_wired.dart:1602-1606` (stream gate already admits `inboxed`), `conversation_screen.dart:633` (`transportStatusGlyph:true`), `message_repository_impl.dart:141`.
- Direct tests: `test/features/conversation/presentation/widgets/letter_card_test.dart`, `test/features/conversation/application/send_presence_emphasis_test.dart`, `test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart`.

## Existing Tests Covering This Area
- `letter_card_test.dart` — per-status glyph/color/a11y; `done_all findsNothing` anti-regression sweep (`:357-383`) + six per-status asserts. **`buildTestWidget` defaults `transportStatusGlyph=false`** (`:43`) → most cases exercise the LEGACY `_statusIcon`; new 2-tick cases must pass `transportStatusGlyph:true`. **TC-08 (`:417-446`) is BROKEN on HEAD** (`find.byIcon(Icons.schedule_rounded)` after the clock→tick removed it).
- `send_presence_emphasis_test.dart` — the `_PresenceFake` harness exercising the `unknownPresence` concurrent-inbox + presence path; C5/C6/C7 EXIST. **Already in `ONE_TO_ONE_TESTS`** → runs in the curated `1to1` gate; auto-globs into `feature-host-all`.
- `conversation_wired_sending_to_failed_test.dart` — drives the `messageChanges` stream sending→{failed,sent,delivered}; asserts single-tick `done_rounded`.
- **MISSING (this plan fills):** the mid-send `inboxed` persist+event; the 2-tick `done_all` glyph for 1:1 `inboxed`; the ordering guard; the broken-TC-08 fix; the rewritten `done_all` contract.

## RED Test Catalog  (add BEFORE production code — INV-RED-FIRST)

1. `letter_card_test.dart`::**TC-184-02 — 1:1 `inboxed` renders two ticks (`done_all`)**
   - Tier: widget. Setup: `buildTestWidget(isIncoming:false, status:'inboxed', transport:'inbox', transportStatusGlyph:true)`; assert `find.byIcon(Icons.done_all_rounded)` findsOneWidget AND `find.byIcon(Icons.inbox_rounded)` findsNothing.
   - RED on HEAD: `_resolvedStatusIcon('inboxed', transport:'inbox')` → `_transportIcon('inbox')` → `Icons.inbox`; `done_all_rounded` is absent → fails.
   - GREEN: `_resolvedStatusIcon` returns `done_all_rounded` for `inboxed`.
   - Mutation that re-reds: revert the `if (status=='inboxed') return Icons.done_all_rounded;` line → red.

2. `send_presence_emphasis_test.dart`::**TC-184-10 — concurrent-inbox ACK persists `inboxed` mid-send + emits `CHAT_MSG_SEND_CUSTODY_CONFIRMED`**
   - Tier: integration/application (reuse `_PresenceFake`). Setup: `unknownPresence` send; `storeInInbox` resolves `true` (ACK) while the live legs are slow/fail; capture `messageRepo.saveMessage` calls + flow events.
   - RED on HEAD: `.then` at `:733` only records a metric → NO `saveMessage(status:'inboxed')` before the terminal save, and NO `CHAT_MSG_SEND_CUSTODY_CONFIRMED` → assertions fail.
   - GREEN: a `status:'inboxed', transport:'inbox'` save AND `CHAT_MSG_SEND_CUSTODY_CONFIRMED` fire at the ACK.
   - Mutation: remove the persist+emit at `:733` → red.
   - **Distinct-event discriminator:** assert `CHAT_MSG_SEND_CUSTODY_CONFIRMED` is emitted AND it precedes `CHAT_MSG_SEND_TIMING` (the terminal) — distinguishes the mid-send custody bump from the terminal `inboxed` save (both yield `status=='inboxed'`).

3. `send_presence_emphasis_test.dart`::**TC-184-12 — live ack before inbox ack does NOT regress to two ticks (ordering guard)**
   - Tier: integration. Setup: live leg wins (`delivered`, transport set) before the inbox ACK resolves; then the inbox ACK fires.
   - RED on HEAD: passes vacuously (no mid-send save exists) → this is a **guard lock for the new code**, mutation-verified.
   - GREEN asserts: final persisted status is `delivered` (transport glyph) and the late inbox ACK does NOT overwrite it with `inboxed`.
   - Mutation: drop the "not already delivered" guard in the `:733` persist → a late `inboxed` overwrites `delivered` → red.

4. `letter_card_test.dart`::**TC-184-20 — fix the already-broken TC-08 (`pending`→single tick)**
   - Tier: widget. Setup: `buildTestWidget(status:'pending')` (legacy, `transportStatusGlyph` default false); assert `find.byIcon(Icons.done_rounded)` findsOneWidget (was `schedule_rounded`).
   - RED on HEAD: the current TC-08 calls `tester.widget<Icon>(find.byIcon(Icons.schedule_rounded))` which **throws** (icon removed by clock→tick).
   - GREEN: assert the single tick + its (now neutral, not amber) color.
   - Mutation: revert letter_card `pending → done_rounded` back to `schedule_rounded` → the updated assert reds.

5. `letter_card_test.dart`::**TC-184-21 — `done_all` contract rewrite (expected for 1:1 `inboxed`, absent elsewhere)**
   - Tier: widget. Setup: re-scope the TC-04 sweep (`:357-383`) and the six per-status `done_all findsNothing` asserts: `done_all` is the EXPECTED glyph for `status:'inboxed', transportStatusGlyph:true`, and still `findsNothing` for `sending`/`sent`/`delivered`/`failed`/legacy-`inboxed`(false).
   - RED on HEAD: the current sweep asserts `done_all findsNothing` for ALL statuses incl. 1:1 inboxed — fails once 1:1 inboxed renders `done_all`. (Re-scoping the assertion IS the change.)
   - Mutation: revert the glyph change → the new "1:1 inboxed → done_all" assert reds.

6. `conversation_wired_sending_to_failed_test.dart`::**TC-184-11/22 — stream transition `sending → inboxed(2-tick) → delivered(transport glyph)`**
   - Tier: widget/integration (drives `messageChanges`). Setup: emit `status:'inboxed'` then `status:'delivered',transport:'direct'` for the same id; assert the bubble shows single tick → `done_all` → `device_hub` in order.
   - RED on HEAD: emitting `inboxed` shows the inbox glyph (not `done_all`) at the 1:1 surface → fails on the 2-tick assertion.
   - GREEN: 1-tick → 2-tick → transport glyph.
   - Mutation: revert the glyph change → 2-tick step reds.

## Test Coverage Matrix  (zero empty cells)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-184-01 | sending→1 tick | widget | letter_card_test.dart::"1:1 sending one tick" (NEW, transportStatusGlyph:true) | passes on HEAD (clock→tick) — lock | revert pending/sending→done_rounded | `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart` | AUTO (feature-host-all) |
| TC-184-02 | inboxed 1:1→2 ticks | widget | letter_card_test.dart::"1:1 inboxed two ticks" (NEW) | inboxed→inbox glyph, not done_all → RED | revert `inboxed→done_all` | same file | AUTO (feature-host-all) |
| TC-184-03 | delivered+transport→transport glyph | widget | letter_card_test.dart::"1:1 delivered shows transport glyph" (EXISTS/extend) | covered (reached fallback) | route delivered→done_all | same file | AUTO |
| TC-184-04 | failed→error | widget | letter_card_test.dart::failed/send_failed (EXISTS) | covered | failed→done_all | same file | AUTO |
| TC-184-05 | legacy inboxed→inbox glyph (NOT done_all) | widget | letter_card_test.dart::"legacy inboxed inbox glyph" (EXISTS, transportStatusGlyph false) | covered | make legacy inboxed→done_all | same file | AUTO |
| TC-184-10 | mid-send inboxed persist + event | integration | send_presence_emphasis_test.dart::"custody-confirmed persists inboxed mid-send" (NEW) | `.then` only records metric → RED | remove persist+emit at :733 | `flutter test test/features/conversation/application/send_presence_emphasis_test.dart` | AUTO + in ONE_TO_ONE_TESTS |
| TC-184-11 | mid-send re-render to 2-tick | widget/integration | conversation_wired_sending_to_failed_test.dart::"sending→inboxed shows two ticks" (NEW) | inboxed renders inbox glyph at 1:1 → RED | revert inboxed→done_all | `flutter test test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart` | AUTO |
| TC-184-12 | ordering guard (no delivered→inboxed regress) | integration | send_presence_emphasis_test.dart::"live ack before inbox ack no regress" (NEW) | guard lock (passes on HEAD) | drop the not-already-delivered guard | same file | AUTO + ONE_TO_ONE_TESTS |
| TC-184-13 | offline rests at 2-tick | integration | send_presence_emphasis_test.dart::"offline send rests inboxed→two ticks" (NEW) | final inboxed→inbox glyph (not 2-tick) → RED | revert inboxed→done_all | same file | AUTO + ONE_TO_ONE_TESTS |
| TC-184-14 | inbox-store fail → stays 1-tick | integration | send_presence_emphasis_test.dart::"inbox store fail keeps one tick" (NEW) | guard lock — passes on HEAD | persist inboxed even on ok==false | same file | AUTO + ONE_TO_ONE_TESTS |
| TC-184-20 | fix broken TC-08 | widget | letter_card_test.dart::TC-08 (MODIFY) | throws (schedule_rounded gone) → RED | revert pending→done_rounded | same file | AUTO |
| TC-184-21 | done_all contract rewrite | widget | letter_card_test.dart::TC-04 sweep (MODIFY) | sweep asserts done_all absent for inboxed → RED after glyph change | revert inboxed→done_all | same file | AUTO |
| TC-184-22 | stream sending→inboxed→delivered | widget/integration | conversation_wired_sending_to_failed_test.dart::"...→delivered upgrade" (NEW) | 2-tick step absent on HEAD → RED | revert glyph change | same file | AUTO |
| TC-184-30 | offline→2-tick ~100-200ms; online→transport glyph (perceived) | device-proof (UX, NOT a host gate) | 184 device-proof runsheet::TC-184-30 (NEW) | n/a (visual) | n/a | two-phone rig | device-proof runsheet (host tests carry correctness) |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** the mid-send `inboxed` is **persisted** (`saveMessage` writes the DB row), so it improves durability — if the app is killed after the inbox ACK but before the terminal save, the message reloads as `inboxed`→2-tick (custody was real). **Row:** TC-184-13 (offline rests `inboxed`) + the glyph is a **pure function of the persisted status** (TC-184-02 renders from status), so the 2-tick reconstructs from the DB row on reopen — no separate in-memory derived-state to lose. Add an explicit reopen assertion (a reloaded `inboxed` message renders `done_all`) as part of TC-184-02.
- **Sibling-surface consistency:** the change is in the shared status→glyph function (`_resolvedStatusIcon`) and the shared send path, so **all 1:1 outgoing surfaces** (text AND media/`hasAttachments`) get the same progression uniformly. **Justified uniform — no asymmetry.** (Reactions/edits use their own surfaces, out of scope; not regressed since `_statusIcon`/legacy is untouched.)
- **Destructive-action side-effects:** **N/A** — no delete/cleanup/cancel added; the change adds a status write + a glyph, removes nothing.
- **Invariant re-verification under new transitions:** the new `…→inboxed→delivered` transition must not let `delivered` regress to `inboxed` (the ordering invariant). **Row:** TC-184-12 (live-ack-before-inbox-ack guard) + TC-184-14 (no false 2-tick when custody not secured).

## Invariants (locked by tests)
- **INV-1 (custody milestone):** a successful concurrent-inbox ACK persists `status:'inboxed'` and emits `CHAT_MSG_SEND_CUSTODY_CONFIRMED` mid-send → TC-184-10.
- **INV-2 (2-tick glyph, 1:1 only):** 1:1 `inboxed` → `done_all_rounded`; legacy `inboxed` → `inbox_rounded` → TC-184-02, TC-184-05, TC-184-21.
- **INV-3 (no regression):** a live `delivered` is never overwritten by a late `inboxed` → TC-184-12.
- **INV-4 (truthful tick):** the 2-tick fires only when custody is actually secured (`ok==true`); a failed store keeps the single tick → TC-184-14.
- INV-RED-FIRST + INV-MUTATION-VERIFIED apply to every NEW row; the guard/coverage locks (TC-184-12/14) pass on HEAD by design and are mutation-verified.

## Step-By-Step Implementation Plan
1. Snapshot tree: `git status --short` (record the uncommitted 500 ms budgets + clock→tick + the 182/183 specs + the 184 spec — do NOT revert/bundle).
2. **Add RED tests first** (TC-184-02/10/12/13/14/20/21/22 + the 1:1 sending/delivered cases). Run the focused cmds; confirm TC-184-02/10/11/13/20/21/22 FAIL for the documented reasons and the guard locks (12/14) pass.
3. **Edit 1 — the custody milestone** (`send_chat_message_use_case.dart` `.then` at `:733`): after `recordAttempt`, on `ok==true` AND the message not already terminally `delivered`, persist `status:'inboxed', transport:'inbox'` for `resolvedMessageId` via `messageRepo` (build the minimal `ConversationMessage` from the in-scope payload/ids the terminal path already uses, or a status-only repo update if one exists), and `emitFlowEvent(CHAT_MSG_SEND_CUSTODY_CONFIRMED)`. Stop-if: the use case lacks a clean handle to persist a status-only update for the id → add a thin `messageRepo` status-update helper rather than reconstructing a partial message ad-hoc.
4. **Edit 2 — the glyph** (`letter_card.dart` `_resolvedStatusIcon`): add `if (status == 'inboxed') return Icons.done_all_rounded;` before the reached/transport-glyph fallback. Leave `_statusIcon` (legacy) and `_transportIcon` untouched.
5. Rerun direct → preservation → named gates. Then `graphify update .` + `./graphify-arch/refresh_arch_graph.sh` (lib/ changed; never cwd inside graphify-arch/).

## Risks And Edge Cases
- **Live ack beats the inbox ack** (delivered < 110 ms) → the guard must skip the `inboxed` write; pinned by TC-184-12.
- **Inbox store fails** (`ok==false`) → no 2-tick (truthful); TC-184-14.
- **Double re-render churn** — the extra mid-send `saveMessage` adds one `messageChanges` emit per `unknownPresence` send; the screen already coalesces per-frame (`_enqueueCoalescedUpsert` `conversation_wired.dart:1586`). Pinned by the stream-transition test (TC-184-22) showing a single clean 1→2→glyph progression.
- **Connected/reuse sends** have no concurrent inbox → no mid-send 2-tick (they show the transport glyph directly) — intended; asserted by leaving the reuse path untested-for-2-tick and TC-184-03.

## Device/Relay Proof Profile
**host-closable for correctness** (widget + integration carry it). TC-184-30 is an **optional single-device UX confirmation** (perceived timing), not a boundary host can't test — create `Test-Flight-Improv/184-2tick-device-proof-runsheet.md` only for the visual sign-off.
- Rig: Pixel 6 `adb -s 21071FDF600CSC` (already has the clock→tick build). Build `flutter build apk --profile --dart-define=FDC_FLOW_LOG=1 --dart-define=MKNOON_ENABLE_NATIVE_MDNS=true`.
- TC-184-30: send to an **offline** peer → bubble shows 1 tick → **2 ticks within ~100–200 ms** (look for `CHAT_MSG_SEND_CUSTODY_CONFIRMED` before `CHAT_MSG_SEND_TIMING`), rests at 2 ticks. Send to an **online** peer → 1 tick → transport glyph on live delivery. No clock anywhere. Do NOT flip any feature-flag default.

**Device-proof RESULT — TC-184-30 PASS (2026-06-30, Pixel 6 `21071FDF600CSC` → offline iPhone 11 `00008030`):** the offline send captured `CHAT_MSG_SEND_START` (21:35:49.569) → `CHAT_MSG_SEND_CUSTODY_CONFIRMED` (**+215 ms**) → `CHAT_MSG_SEND_TIMING{sendPath:"inbox", via:"inbox", elapsedMs:741}` — the custody 2-tick landed **~525 ms before** the send settled, on the `unknownPresence` path. User-confirmed visual: the bubble went **1 tick → 2 ticks (~instant) → rest at 2 ticks** (offline). Build carried `FDC_FLOW_LOG=1 + MKNOON_ENABLE_NATIVE_MDNS=true` plus the uncommitted 500 ms-budget experiment (hence the 741 ms terminal vs the ~1.8 s original budgets — the 215 ms custody milestone is budget-independent). Closure: host-green + device-confirmed.

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# RED (before production edits) — must FAIL for the documented reason
flutter test test/features/conversation/presentation/widgets/letter_card_test.dart
#   expect: TC-184-02/20/21 FAIL (inboxed→inbox glyph; TC-08 throws on schedule_rounded; done_all sweep)
flutter test test/features/conversation/application/send_presence_emphasis_test.dart
#   expect: TC-184-10/13 FAIL (no mid-send inboxed save / CUSTODY_CONFIRMED event)
flutter test test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart
#   expect: TC-184-11/22 FAIL (no 2-tick on inboxed)

# Direct GREEN (after both edits)
flutter test test/features/conversation/presentation/widgets/letter_card_test.dart        # all pass
flutter test test/features/conversation/application/send_presence_emphasis_test.dart       # all pass (C5/C6/C7 + new)
flutter test test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart  # all pass

# Preservation sentinels (must stay green)
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart   # transport/race/inbox unchanged

# Named gate(s)
./scripts/run_test_gates.sh 1to1            # send_presence_emphasis + (auto) letter_card; expect: <NNN>/<NNN>
./scripts/run_test_gates.sh feature-host-all # globs the widget + application tests; expect: <NNNN>/<NNNN>
./scripts/run_test_gates.sh completeness-check  # all touched test files classify

# Hygiene
flutter analyze            # 0 new issues
git diff --check
# Post-change graph refresh (lib/ changed):
graphify update . && ./graphify-arch/refresh_arch_graph.sh
```
> Replace `<NNN>`/`<NNNN>` with the observed pre-edit baseline counts (record pre-edit, assert +N).

**Harness registration:** all touched test files are under `test/features/**` → AUTO-globbed into `feature-host-all`. `send_presence_emphasis_test.dart` is ALREADY in `ONE_TO_ONE_TESTS` (no array edit needed). No new test file is created (all changes extend existing files), so no `classify_path`/array additions are required; `completeness-check` confirms.

## Known-Failure Interpretation
- **Expected RED:** TC-184-02/10/11/13/20/21/22 before the edits.
- **Guard/coverage locks** (TC-184-12/14, the 1:1 sending/delivered/legacy cases): pass on HEAD by design; each mutation-verified.
- **Pre-existing dirty (NOT this plan):** the uncommitted 500 ms send budgets (`send_chat_message_use_case.dart`), the clock→tick (`letter_card.dart` — load-bearing for this plan), the 181/182/183/184 docs. Leave them.
- **TC-08 is broken on HEAD right now** (working-tree breakage from the clock→tick experiment) — TC-184-20 fixes it; not an environment blocker.
- **Scope drift (BLOCKING):** any change to the transport/race/budgets/inbox mechanics, the group/legacy glyphs, or a revert of the 500 ms budget experiment.

## Done Criteria
- [ ] RED added first (TC-184-02/10/11/13/20/21/22), failed for the documented reasons.
- [ ] Mutation-verified (each edit has a named re-red revert).
- [ ] Direct GREEN + preservation (`send_chat_message_use_case_test.dart`) + `1to1`/`feature-host-all` gates pass.
- [ ] No `DB v##` change (status column already exists; no schema change).
- [ ] `CHAT_MSG_SEND_CUSTODY_CONFIRMED` discriminator asserted distinct from the terminal save.
- [ ] `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violations; graph refreshed.
- [x] Device UX sign-off TC-184-30 — PASS (2026-06-30, Pixel 6 → offline iPhone 11): `CHAT_MSG_SEND_CUSTODY_CONFIRMED` at +215 ms vs `CHAT_MSG_SEND_TIMING` +741 ms; user-confirmed visual 1 tick → 2 ticks → rest.

## Scope Guard (hard "Do not")
- Do NOT touch send transport/race/**budgets** (incl. the uncommitted 500 ms experiment — out of scope, do not bundle/revert), inbox mechanics, or the presence/race ladder.
- Do NOT change group/legacy glyphs (`_statusIcon`) or the incoming-message transport glyph.
- Do NOT add a DB migration (no schema change — `status`/`transport` columns exist).
- Do NOT add a new `messageChanges` subscription or screen-side status plumbing — the existing gate already admits `'inboxed'`.

## Accepted Differences / Intentionally Out Of Scope
- **Connected/reuse sends show the transport glyph directly** (no mid-send 2-tick) — intended; their fast live delivery needs no custody milestone.
- **2-tick = relay custody, NOT recipient receipt** — read-receipt semantics deferred.
- **Device UX proof is optional** — the change is fully host-closable; TC-184-30 only confirms the perceived timing.

## Dependency Impact
- None depend on this. It composes cleanly with 181 (presence) and is orthogonal to 182/183 (connection plumbing).

## Reviewer Findings
Sufficiency: every TC-184-XX maps to ≥1 tiered row (matrix has zero empty cells). The two production edits are each RED-first and mutation-verified (TC-184-02 glyph, TC-184-10 persist+event). The mid-send custody bump uses a distinct flow-event discriminator (`CHAT_MSG_SEND_CUSTODY_CONFIRMED`) so it can't be confused with the terminal `inboxed` save. The ordering invariant + the no-false-2-tick invariant are guard-locked (TC-184-12/14). Test-surface debt is explicitly handled (the broken TC-08 + the `done_all` contract rewrite). Preservation sentinel named; literal gates with count guidance; harness registration is AUTO with no array edits. No DB migration. Blind-spot sweep: durability locked (persisted status reconstructs the glyph), sibling-surface uniform, destructive N/A, transition invariant locked.

## Arbiter Decision
Structural blockers: none. Implementation-ready: two small, scoped edits + their RED-first tests, reusing the existing re-render channel. Deferred: literal gate counts (fill from pre-edit baseline); the optional device UX proof. Accepted differences: connected-peer direct-glyph, custody≠receipt. Hand off to execution.

## Final Execution Verdict
Verdict: **DONE (host-closed)** | Files changed: `send_chat_message_use_case.dart` (custody milestone + `liveDelivered` guard) + `letter_card.dart` (`done_all` for 1:1 inboxed) + 4 extended test files (`letter_card_test`, `send_presence_emphasis`, `conversation_wired_sending_to_failed`, `conversation_wired_test`) + `send_chat_message_use_case_test` (added a `statusUpdates` spy to `FakeMessageRepository`) | Implementation note: the mid-send persist is a **status-only `updateMessageStatus(id,'inboxed')`** (plan-sanctioned alternative), NOT a full `saveMessage` — it advances the existing optimistic row's status column, re-renders via the same `messageChanges` emit (real impl emits, `message_repository_impl.dart:172-181`), keeps the terminal full-custody save as the source of truth, and leaves the preservation sentinel's `saved` append-list untouched. | Tests run (+counts): letter_card_test ✓, send_presence_emphasis 9/9 ✓, conversation_wired_sending_to_failed ✓, conversation_wired_test 105/105 ✓, offline_inbox_roundtrip ✓, p2p_service_transport_census ✓; completeness-check 1000/1000 PASS; analyze 0 new; git diff --check clean. Mutation-verified: TC-184-12 (drop `!liveDelivered`→RED), TC-184-14 (drop `ok`→RED), glyph+custody RED-on-HEAD proven. | Blocking: none. | Pre-existing (NOT 184, left per Scope Guard): 6 FDC budget/timing failures in `send_chat_message_use_case_test` (the uncommitted 500 ms experiment — proven by reverting 184 and reproducing the identical 6); clock→tick `schedule_rounded` stragglers in `group_conversation_wired_test`/`conversation_wired_offline_send_ux_test` (the uncommitted clock→tick experiment, untouched by 184). | QA verdict: ACCEPTED — 184 adds zero regressions; both production invariants (INV-3 ordering, INV-4 truthful tick) mutation-locked. | Non-blocking follow-ups (owner): read-receipt two-tick semantics (future); 2-tick color tuning if amber preferred (UX); optional single-device UX proof TC-184-30 (perceived ~110 ms timing — correctness is fully host-closed).
