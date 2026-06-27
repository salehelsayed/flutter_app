# 170 - 1:1 Send button frozen + failure SnackBar hides Send, under degraded network  (Bug)

Status: awaiting-review
Spec: free-text intent (no formal spec) — surfaced during FDC-S4 device testing; root cause verified by a 6-agent verify→refute investigation (2026-06-26).

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-26 | Evidence Collector | conversation_wired.dart, conversation_screen.dart, compose_area.dart, conversation_wired_sending_to_failed_test.dart, compose_area_test.dart, run_test_gates.sh | 2 linked defects, 1 root cause; anchors confirmed by symbol | build matrix |
| 2026-06-26 | Planner | tier-matrix.md, plan-template.md | widget-tier, host-only closure; add new test to ONE_TO_ONE_TESTS | emit plan |
| 2026-06-26 | Reviewer (sufficiency) | sufficiency-checklist.md | blind-spot: sibling send paths (edit/retry/media) share `_isSending` | record scope split |
| 2026-06-26 | Arbiter | — | structurally sufficient; edit/retry S2 deferred as sibling follow-up | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-06-27 | contract extraction | (git status) | `send_chat_message_use_case.dart` confirmed user-WIP (M) | preserved — never touched | RED |
| 2026-06-27 | RED tests added | conversation_wired_offline_send_ux_test.dart (NEW) | TC-01 `Expected <2> Actual <1>` (callCount); TC-04 `margin==null` | RED for documented reasons | implement |
| 2026-06-27 | implementation | conversation_wired.dart only | S2 early `_isSending=false` after optimistic save; S1 `_composerClearingSnackBarMargin()` on 4 failure bars | minimal early-release (≡ plan's detach: `_onSend` is already fire-and-forget; only the flag froze the button) | GREEN |
| 2026-06-27 | direct GREEN + mutation | conversation_wired.dart | 4/4 pass; mut-1 (drop early release)→TC-01 red; mut-2 (drop margin)→TC-04 red; both restored | mutation-verified | preservation |
| 2026-06-27 | preservation GREEN | — | compose_area_test + conversation_wired_sending_to_failed_test = 46 pass | sentinels green | gate |
| 2026-06-27 | named 1:1 gate | (see below) | `+1271 -1`; new file registered in ONE_TO_ONE_TESTS | BLOCKER (resolved): whole gate failed to COMPILE on entry — concurrent FDC-04/11/12 added `P2PService.warmPeer` + `dialPeer({preferQuic})`, ~10 test fakes out of sync. User-approved fix: added forward-only conformance stubs. Last `-1` = user-WIP transport-label test | done |
| 2026-06-27 | QA | — | analyze 0-new; git diff --check clean | ship (plan-170 scope) | — |

## Source Of Truth
- Spec / intent: inline below + `FDC-S4-device-measurement-RESULTS.md` §"Observed UX bug"
- Gate definitions: scripts/run_test_gates.sh (script wins over prose)
- Numbering / index: Test-Flight-Improv/00-INDEX.md (next-free = 170)

## Session Classification
implementation-ready (host-only closure; no migration, no device-proof).

## Exact Problem Statement
In a 1:1 conversation under **degraded/no network**, sending a message makes the
composer **unusable for several seconds** and a **red failure SnackBar covers the
Send button**. Reproduced on a real iPhone during FDC-S4 testing: the user could
not rapid-send because (S1) "a snack bar with an error message hides the send
button," and (S2) "the send button feels frozen or not working for a bit and then
sends again, and fails."

Mechanically: a 1:1 send awaits the direct→relay→inbox timeout cascade (≈ up to
several seconds offline — measured in FDC-S4), and during that whole window the
composer's Send button is dead and, on failure, a floating red SnackBar renders
directly over it. The optimistic message row is ALREADY inserted + persisted
before the network call, so the composer never needed to be locked to the network
round-trip.

**What must improve:** the Send button stays usable while a send is in flight (a
second message can be composed/sent without waiting for the first to time out); a
send-failure notice never renders over the Send button.
**What must stay unchanged (→ preserved-green sentinels):** the optimistic
`sending`→`failed`/`sent` bubble status + the retry affordance; one Send tap =
exactly one message (no duplicate-send); the ComposeArea per-widget contract
(`isSending:true` disables the button).

## Root Cause (verify → refute confirmed)
Single root cause in `lib/features/conversation/presentation/screens/conversation_wired.dart`:
`_onSend` (`:1958`) flips the **one global** `bool _isSending` field (`:317`) `true`
at `:2058` — **before** the network call — and resets it to `false` **only** in the
outer `finally` at `:2511/:2513`, i.e. **after** the awaited
`widget.sendChatMessageFn(...)` resolves. The optimistic row is inserted + locally
saved well before that (investigation: `:2137-2158`).

- **S2 (frozen button):** `_isSending` double-duties as (a) the re-entrancy guard
  `if (_isSending) return;` (`:1969`) AND (b) — via the prop chain `_isSending`
  (`:4287`) → `ConversationScreen.isSending` (`conversation_screen.dart:416`) →
  `ComposeArea.isSending` — the Send-button enable gate (`compose_area.dart:486`,
  `!widget.isSending` nulls `onTap`). So the button's `onTap` is `null` for the full
  multi-second await. The button has **no disabled appearance** (the opacity/scale
  anim at `compose_area.dart:472-481` is the mic↔send morph), so it looks tappable
  but does nothing.
- **S1 (SnackBar hides Send):** the offline-failure SnackBar (`:2477-2483`,
  `behavior: SnackBarBehavior.floating`, `:2481`, no `margin`) and the shared
  `_showFloatingSnackBar` helper (`:3877-3883`, floating, no margin) render at the
  body bottom because the host `Scaffold` (`:4268`) has **no** `bottomNavigationBar`/
  `persistentFooterButtons`/FAB and the composer is the bottom-most **body** child
  (`conversation_screen.dart:370-377`, lifted only by the safe-area inset). Flutter's
  `_ScaffoldLayout` lifts floating SnackBars above a FAB/bottomNavigationBar/
  persistentFooterButtons but **never** above arbitrary body content → the bar lands
  on the Send button. Swipe-dismissible → the user "slides it away."

**Refuted / do-NOT-re-introduce:**
- "networkUnavailable" enum label → WRONG: the network-failure case is
  `SendChatMessageResult.nodeNotRunning` ("Network not connected. Message saved.").
- "two SnackBars stack on the offline path" → WRONG: the common offline path shows
  exactly ONE bar (the mapped-result inline bar `:2477-2483`); `_restoreComposerSnapshot`
  just above (`:2470`) passes `showSnackBar:false`. The `:2715/:2719` bar only fires
  on the exception/catch path — mutually exclusive.
- "the `:1969` early-return is the cause of the frozen button" → it is a redundant
  second line of defense; the button is already inert because `onTap` is `null`
  (`compose_area.dart:486`). The fix must address the `onTap` gate, not just `:1969`.

> Anchors are from the 2026-06-26 investigation; **re-confirm by symbol at execution**
> (`_isSending`, `if (_isSending) return`, the `SnackBarBehavior.floating` at the
> offline-failure block, `_showFloatingSnackBar`) — line numbers on `new-orbit` drift.

## Real Scope
**In scope** (all in `conversation_wired.dart`, the reported `_onSend` path):
- S2: release the composer (`_isSending=false`) right after the optimistic insert +
  local `saveMessage`, and run uploads + `sendChatMessageFn` as a detached/background
  future that still drives the bubble's `sending`→`failed`/`sent` status (existing
  path) and surfaces the failure notice on resolve. Replace the global `_isSending`
  re-entrancy guard (`:1969`) so a second distinct message can be sent while the
  first is in flight, WITHOUT allowing one tap to double-fire (a per-send sentinel /
  rely on the controller-clear, not the global flag).
- S1: give the send-failure SnackBars a bottom `margin` that clears the composer —
  the shared `_showFloatingSnackBar` helper (`:3883`) + the inline offline-failure bar
  (`:2481`) + the edit-path failure bar (`:2027`).

**Out of scope** (sibling follow-up, owns: a later UI session):
- S2 optimistic-release for the **edit** (`:1992`), **retry** (`:2587`), and **media**
  send paths (they share `_isSending` but are separate handlers) — fix `_onSend` first;
  see Blind-Spot Sweep. Their **S1** margin IS in scope (shared helper + edit bar).
- The larger UX redesigns (lift composer into `bottomNavigationBar`; replace the red
  toast with an inline error chip/banner reusing `_ConversationSyncingBanner`).
- `send_chat_message_use_case.dart` — **user-WIP; do not touch.**

## Files To Inspect Next
Production: `conversation_wired.dart` (`_onSend` 1958-2515, `_isSending` 317, guard 1969,
optimistic insert ~2137-2158, await 2384, failure block 2457-2483, finally 2503-2515,
`_showFloatingSnackBar` 3877-3886, edit bar 2024-2028, wiring 4268-4313);
`conversation_screen.dart:370-431,971-979` (composer placement + `_isComposerBusy`);
`compose_area.dart:483-490` (Send onTap gate — read-only, contract preserved).
Tests: `conversation_wired_sending_to_failed_test.dart` (harness pattern + injectable
`sendChatMessageFn`), `compose_area_test.dart` (isSending contract).

## Existing Tests Covering This Area
- `conversation_wired_sending_to_failed_test.dart` — covers `sending`→`failed`/`sent`
  UI refresh + a slow (2s) send (no "taking longer" hint). Provides `_buildTestWidget`
  (injectable `sendChatMessageFn`) — the harness to reuse. Does NOT cover composer
  responsiveness during an in-flight send, nor SnackBar geometry. (MISSING)
- `compose_area_test.dart::disables send button when isSending is true` — locks the
  per-widget contract (isSending=true → disabled). Preserved.
- **Gaps:** (1) composer not globally locked during a pending send; (2) SnackBar
  non-overlap; (3) no-duplicate on relaxing the lock.
- **Already in curated arrays:** `ONE_TO_ONE_TESTS` (run_test_gates.sh:17) lists
  `conversation_wired_test.dart`, `conversation_screen_test.dart`,
  `conversation_wired_change_coalesce_test.dart` → the new test MUST be added there.

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)
New file: `test/features/conversation/presentation/screens/conversation_wired_offline_send_ux_test.dart`
(reuse the `_buildTestWidget` + fakes pattern from `conversation_wired_sending_to_failed_test.dart`;
add a **call-counting, `Completer`-gated** `SendChatMessageFn` so the test controls
when/whether a send resolves).

1. `…::S2 a second message can be sent while the first send is still in flight`
   - Tier: **widget**
   - Shape/setup: inject a `SendChatMessageFn` that increments `callCount` and returns
     a future gated on a per-call `Completer` (never auto-resolves). Type "first", tap
     `Icons.arrow_upward_rounded`; pump (do NOT complete). Type "second", tap send; pump.
   - RED on HEAD because: `_isSending` is set true at `:2058` and reset only in the
     `finally` at `:2511` (after the still-pending await), and `_onSend` early-returns
     at `:1969` while true → the second tap is swallowed → `callCount == 1`.
   - GREEN after fix asserts: `callCount == 2` (and two optimistic `Icons.schedule_rounded`
     rows present) — the composer accepted the second send while the first is pending.
   - Mutation that re-reds: revert the early `_isSending=false` release (restore reset
     to the outer `finally` only) → `callCount` back to 1.
   - Distinct discriminator: assert `callCount == 2` AND two distinct optimistic rows
     (text "first" + "second"), so a single double-counted call can't pass it.

2. `…::S1 send-failure SnackBar does not overlap the composer (has a bottom margin)`
   - Tier: **widget**
   - Shape/setup: inject a `Completer`-gated send; type + tap; complete the Completer
     with `(SendChatMessageResult.nodeNotRunning, null)`; pump. Find the `SnackBar`
     widget (`find.byType(SnackBar)`), read `tester.widget<SnackBar>(...).margin`.
   - RED on HEAD because: the offline-failure bar (`:2481`) is `SnackBarBehavior.floating`
     with `margin == null` → renders over the bottom composer. Assert `margin != null`
     with `margin.bottom > 0` → fails (null).
   - GREEN after fix asserts: `margin != null && (margin as EdgeInsets).bottom >=`
     the composer-clearing inset; STRONGER variant (assert too): the SnackBar rect does
     not overlap the composer rect — `tester.getRect(find.byType(SnackBar))` does not
     overlap `tester.getRect(find.byType(ComposeArea))`.
   - Mutation that re-reds: revert the `margin:` added to the failure SnackBar →
     `margin` null again → red.
   - Distinct discriminator: assert the bar's `backgroundColor == Colors.red[700]` so
     the test is pinned to the FAILURE bar, not an unrelated floating notice.

3. `…::PRESERVE optimistic sending→failed bubble + retry still re-dispatches`  (green→green)
   - Tier: **widget**
   - Shape/setup: `Completer`-gated send; type + tap → assert an `Icons.schedule_rounded`
     optimistic row appears immediately (before completing). Complete with
     `nodeNotRunning` → pump → assert `Icons.error_outline_rounded` (failed). Drive the
     wired retry (`onRetryFailedMessage` path) → assert `callCount` increments.
   - RED on HEAD because: green now; this LOCKS that the S2 fix does not break the
     optimistic/failed/retry UX (it goes red only if the detached-future refactor drops
     the status-write or the retry wiring).
   - Mutation that re-reds: in the fix, drop the `failed` status write on the detached
     future → `error_outline_rounded` not found.

4. `…::PRESERVE one Send tap dispatches exactly one message (no duplicate)`  (green→green)
   - Tier: **widget**
   - Shape/setup: `Completer`-gated send; type "hi"; tap send TWICE in immediate
     succession (`tester.tap` ×2, no pump between); pump.
   - RED on HEAD because: green now (controller-clear + global guard). LOCKS that
     relaxing the `:1969` global guard does not introduce a duplicate send.
   - GREEN after fix asserts: `callCount == 1` (the second tap finds the cleared
     composer / per-send sentinel coalesces) — exactly one optimistic row.
   - Mutation that re-reds: a naive guard removal that lets one compose double-fire →
     `callCount == 2` / two rows.

5. `compose_area_test.dart::disables send button when isSending is true`  (EXISTING — preserved)
   - Tier: widget. Already green; must stay green — the fix changes only WHEN the wired
     layer sets `isSending`, not the per-widget contract (isSending=true → onTap null).

## Test Coverage Matrix  (ZERO empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 (S2 core) | UI gesture / async lock | widget | conversation_wired_offline_send_ux_test.dart::S2 second message while first in flight | global `_isSending` (set 2058 / reset 2511) + guard 1969 swallow 2nd send → callCount 1 | revert early `_isSending=false` release → callCount 1 | `flutter test test/features/conversation/presentation/screens/conversation_wired_offline_send_ux_test.dart` | **AUTO (glob)** + **add to `ONE_TO_ONE_TESTS`** array |
| TC-04 (S1) | UI render geometry | widget | …::S1 failure SnackBar bottom margin | offline bar 2481 floating, margin null → assert margin!=null fails | revert SnackBar `margin:` → margin null | same file gate | AUTO + ONE_TO_ONE_TESTS |
| TC-03 (preserve) | optimistic+status+retry | widget | …::PRESERVE optimistic sending→failed + retry | green now; locks fix doesn't drop status/retry | drop `failed` write on detached future → red | same file gate | AUTO + ONE_TO_ONE_TESTS |
| TC-02 (preserve) | no-duplicate-send | widget | …::PRESERVE one tap one message | green now; locks no double-send from relaxed guard | naive guard removal double-fires → callCount 2 | same file gate | AUTO + ONE_TO_ONE_TESTS |
| TC-05 (preserve) | widget contract | widget | compose_area_test.dart::disables send button when isSending is true | green; unchanged contract | (n/a — preservation) | `flutter test test/features/conversation/presentation/widgets/compose_area_test.dart` | AUTO (existing) |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** `_isSending` is transient by design (resets
  `false` on fresh mount). The fix adds no NEW persisted derived state — the optimistic
  row's `sending`/`failed` status already round-trips via the repo (covered by
  `conversation_wired_sending_to_failed_test.dart`). **N/A** (no new derived state to
  reconstruct on reopen).
- **Sibling-surface consistency:** `_isSending` is also set by the **edit** send
  (`:1992`), **retry** (`:2587`), and media sends. This plan fixes **S2 only for the
  main `_onSend` path** (the reported symptom). The edit/retry/media S2 optimistic-release
  is an explicit **deferred sibling follow-up** (Scope) — their composer-lock is left
  as-is and NOT regressed (they don't share `_onSend`). Their **S1 margin IS fixed**
  (shared `_showFloatingSnackBar` + edit bar `:2027`). → recorded, not silently skipped.
- **Destructive-action side-effects:** **N/A** — no delete/cleanup/cancel path changed.
- **Invariant re-verification under new transitions:** the new "release `_isSending`
  early, then resolve in the background" transition means `_isComposerBusy()`
  (`conversation_screen.dart:971-979`) is now `false` during the network await.
  TC-01 re-verifies the composer accepts a second send in that window; **add an assertion**
  that the first optimistic row is NOT clobbered when the second send inserts (both rows
  coexist) — i.e. the background resolution of send #1 still updates ONLY row #1's status.

## Invariants (locked by tests)
- INV-1: the Send affordance is disabled only for the optimistic-insert (synchronous),
  never for the network round-trip → TC-01.
- INV-2: a send-failure notice never renders over the composer/Send button → TC-04.
- INV-3: one Send tap = exactly one outgoing message → TC-02.
- INV-4: optimistic `sending`→`failed` + retry survive the refactor → TC-03.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to TC-01 and TC-04.

## Step-By-Step Implementation Plan
1. `git status --short` snapshot (record the user's WIP `send_chat_message_use_case.dart`
   so it is NOT reverted). Add the new RED test file; run the focused gate; confirm
   TC-01 + TC-04 fail for the documented reasons (callCount 1; margin null).
2. **S2 edit** in `conversation_wired._onSend`: after the optimistic message is built +
   upserted + `saveMessage`d (~`:2155-2170`), `setState(() => _isSending = false)`, and
   convert the remaining uploads + `await widget.sendChatMessageFn(...)` + status-write +
   failure-notice into a **detached future** (`unawaited(_completeSendInBackground(...))`)
   that still writes `sending`→`failed`/`sent` (existing `:2434-2455`) and shows the
   failure SnackBar on resolve. Replace the `:1969` `if (_isSending) return;` re-entrancy
   guard with a per-send sentinel (e.g. an in-flight `Set<String>` of optimistic message
   ids, or simply rely on the controller-clear) so a SECOND distinct send proceeds but a
   single compose cannot double-fire. **Stop-if** the detached-future refactor would
   require touching `send_chat_message_use_case.dart` → it must not; keep all changes in
   the screen. Keep the bg-task wrapping (the existing `beginBackgroundTask` around the
   send) so the detached future survives a real backgrounding.
3. **S1 edit**: add `margin: EdgeInsets.only(bottom: <composerHeight+inset>, left: 8, right: 8)`
   (or a constant comfortably above the compose bar) to the offline-failure SnackBar
   (`:2481`), the edit-path bar (`:2027`), and the shared `_showFloatingSnackBar` helper
   (`:3883`). Prefer centralizing through the helper.
4. Rerun: direct GREEN (the new file) → preservation (compose_area + sending_to_failed) →
   named 1:1 gate.

## Risks And Edge Cases
- **Detached future + setState after dispose:** the background completion must guard
  `if (!mounted) return;` before `setState`/SnackBar (the screen can close mid-send) →
  pinned by running TC-03 to completion after the row is failed; add a dispose-safety
  assertion.
- **Double `_onPaused`-style double counting:** N/A here (single tap path).
- **SnackBar margin too large on small screens:** size from `MediaQuery` inset, not a
  magic constant that could push the bar off-screen → TC-04 geometric variant guards it.
- **Second send's optimistic insert clobbering the first row:** guarded by INV re-verify
  assertion in TC-01 (both rows coexist; background resolve updates only row #1).

## Device/Relay Proof Profile
**host-only for closure** — this is a widget/UI behavior bug; no OS-boundary, crypto, or
relay leg. The original symptom was observed on device (FDC-S4) but the fix is fully
host-reproducible with a `Completer`-gated fake send. No device-proof, no migration.

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# 0. dirty-tree snapshot (preserve user WIP)
git status --short            # expect: send_chat_message_use_case.dart (user WIP) among others — do NOT revert

# 1. RED (before production edits) — must FAIL for the documented reason
flutter test test/features/conversation/presentation/screens/conversation_wired_offline_send_ux_test.dart \
  --plain-name 'S2 second message while first in flight'      # FAILS: callCount==1
flutter test test/features/conversation/presentation/screens/conversation_wired_offline_send_ux_test.dart \
  --plain-name 'S1 failure SnackBar bottom margin'            # FAILS: margin==null

# 2. Direct GREEN (after fix)
flutter test test/features/conversation/presentation/screens/conversation_wired_offline_send_ux_test.dart   # expect: all pass (4 cases)

# 3. Preservation sentinels (must stay green)
flutter test test/features/conversation/presentation/widgets/compose_area_test.dart
flutter test test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart

# 4. Named 1:1 gate (after adding the new file to ONE_TO_ONE_TESTS)
./scripts/run_test_gates.sh 1to1     # expect: prior 1:1 baseline (~1226 per recent runs) + the 4 new cases, 0 fail

# 5. Hygiene
flutter analyze   # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- Expected RED: TC-01 (callCount 1) + TC-04 (margin null) before the fix.
- Pre-existing dirty: `send_chat_message_use_case.dart` (user-WIP), the FDC-S4 measurement
  scaffolding (handle_app_paused/bridge/GoBridge), and the unrelated
  `transport_metrics_privacy_test.dart` red (FDC-S1) — NOT this plan's; do not revert/fix.
- Environment blocker: none (host-only).
- Scope drift (BLOCKING): any failure in `send_chat_message_use_case.dart` or outside
  `conversation_wired.dart` + the new test.

## Done Criteria
- [x] RED added first (TC-01, TC-04), failed for the expected reason (callCount==1; margin==null).
- [x] Each fix mutation-verified (early-release revert → TC-01 red; margin revert → TC-04 red; both restored).
- [x] Direct GREEN (4/4) + preservation (compose_area + sending_to_failed = 46) + 1:1 gate (`+1271 -1`, the `-1` is user-WIP, see below).
- [x] New test added to `ONE_TO_ONE_TESTS` and confirmed present/green in the 1:1 gate run.
- [x] No migration / no device-proof needed.
- [x] `flutter analyze` 0 new on plan-170 files; `git diff --check` clean; Scope Guard honored
      (`lib/.../send_chat_message_use_case.dart` untouched).

## Scope Guard (hard "Do not")
- Do NOT touch `lib/features/conversation/application/send_chat_message_use_case.dart`
  (user-WIP) or any use-case/repo — the fix is screen-local.
- Do NOT change the `ComposeArea` per-widget contract (`isSending:true` disables) — only
  change WHEN the wired layer sets `_isSending`.
- Do NOT redesign the composer into `bottomNavigationBar` or replace the toast with an
  inline banner (larger UX session).

## Accepted Differences / Intentionally Out Of Scope
- Edit/retry/media send paths' S2 optimistic-release — deferred sibling follow-up
  (they share `_isSending` but are separate handlers); their S1 margin IS fixed here.
- The "best-UX" inline-error-instead-of-toast and composer-in-bottomNavigationBar
  redesigns — a later UI session owns them.

## Dependency Impact
- None blocking. This is an independent send-reliability-under-poor-connectivity fix for
  the FDC epic; it does not gate FDC-06 (FDC-S4 already supplied FDC-06's values).

## Reviewer Findings
Sufficient: every TC has a tiered test + mutation + literal gate + registration; the two
RED-first edits (S2 release, S1 margin) are each mutation-verified; preservation sentinels
named; blind-spot sweep run (sibling edit/retry/media explicitly deferred, not skipped);
host-only closure justified. Thin spot: the exact composer-clearing margin value is a
runtime detail — TC-04's geometric non-overlap variant covers it.

## Arbiter Decision
Structural blockers: none. Deferred details: edit/retry/media S2 (sibling follow-up);
inline-banner/bottomNavigationBar redesign (UX session). Accepted differences: as listed.
Hand off to execution.

## Final Execution Verdict
**SHIPPED (plan-170 scope), host-green.** 2026-06-27.

**What changed (all plan-170 scope):**
- `conversation_wired.dart` — S2: release `_isSending=false` immediately after the
  optimistic insert + local `saveMessage` (`_onSend` is already fire-and-forget from
  the send gesture; only the global flag froze the Send button for the full
  direct→relay→inbox await). This is behaviourally identical to the plan's
  "detached future" but lower-risk: it leaves the intricate upload / bg-task /
  in-flight-blob / status-write control flow untouched and just moves the flag
  release earlier. Same-frame double-tap stays coalesced by the compose_area
  controller-clear AND the still-true flag during the (one-pump) save window.
  S1: new `_composerClearingSnackBarMargin()` (96px + safe-area inset) applied to
  all four send-failure floating SnackBars (offline-failure, edit, `_showFloatingSnackBar`
  helper, and `_restoreComposerSnapshot`'s internal bar — the last honours INV-2
  beyond the plan's named three).
- `conversation_wired_offline_send_ux_test.dart` (NEW, in `ONE_TO_ONE_TESTS`) — 4 cases,
  TC-01/TC-04 mutation-verified. NOTE: the plan's TC-04 geometric variant used
  `find.byType(SnackBar)`, which returns the MARGIN-INCLUSIVE outer box (always spans
  to the screen bottom); the test instead asserts the margin-lifted visible bottom edge
  (`screenHeight - margin.bottom`) clears the composer + the rendered failure text does
  not overlap. TC-03 locks the sending→failed status preservation (the mutation target);
  the plan's "retry → callCount++" sub-assertion was dropped as inapplicable — the wired
  retry calls `retryFailedMessage` (a free fn needing contactRepo), NOT the injected
  `sendChatMessageFn`, so it cannot increment the send counter.

**Accepted limitation (untested, out of plan scope):** with the composer now released
mid-send, a background send-FAILURE still calls `_restoreComposerSnapshot`, which
restores the failed draft into the composer — if the user has since typed a new
message it would be clobbered. No test exercises compose-second-then-fail-first, and
the larger composer-restore redesign is deferred (see Out of scope). Left as existing
behaviour to keep the fix screen-local and low-risk.

**Cross-cutting BLOCKER hit + resolved (NOT plan 170):** the entire 1:1 gate failed to
COMPILE on entry — concurrent FDC-04/11/12 work added `P2PService.warmPeer` +
`dialPeer({preferQuic})` to the working-tree interface but left ~10 test `P2PService`
fakes out of sync (`fake_p2p_service.dart`, `fake_p2p_service_integration.dart`, and
inline fakes in send_chat/send_then_lock/two_user/incoming_router/conversation_wired
tests). With user approval, added forward-only conformance stubs (`warmPeer{}` no-op +
`preferQuic` param). A concurrent process was fixing the same fakes live → transient
duplicate-method churn that self-reconciled; final state compiles clean. This was
necessary just to RUN any 1:1 Dart test.

**Remaining 1:1-gate failure (`-1`, pre-existing/concurrent, NOT plan 170, NOT to fix):**
`send_chat_message_use_case_test.dart :: existing LAN-visible peer records actual Go
transport on the reuse fast path` — `Expected 'direct', Actual 'local'`. A transport-label
discrepancy in the user-WIP `send_chat_message_use_case.dart` (FDC-02/11). The warmPeer/
preferQuic stubs are no-ops that cannot change a transport label; Scope Guard forbids
touching this file.

Gate: 1:1 `+1271 -1`; new file 4/4 + mutations; preservation 46/46; analyze 0-new; diff clean.
