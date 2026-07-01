# 185 - Offline-send failure truthfulness: keep offline sends in the self-healing lane + name the real cause  (Bug)

Status: IMPLEMENTED (host-verified 2026-07-01); device-proof TC-185-04/22 deferred (no two-phone rig)
Spec: `Test-Flight-Improv/185-offline-send-failure-truthfulness-spec.md`

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-01 | Evidence Collector | handle_delivery_receipt_use_case.dart, retry_unacked_messages_use_case.dart, messages_db_helpers.dart, conversation_wired.dart, node_state.dart, letter_card/conversation_screen, delivered_status_minting_sites_test.dart | Root cause device-proven + workflow-refuted; existing lane found | build matrix |
| 2026-07-01 | Planner | plan-template, tier-matrix | 3-part fix at 2 seams, no migration | emit plan |
| 2026-07-01 | Reviewer (sufficiency) | — | pending | run checklist |
| 2026-07-01 | Arbiter | — | pending | hand off |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-07-01 | source verification | conversation_wired.dart, send_chat_message_use_case.dart, handle_delivery_receipt_use_case.dart, messages_db_helpers.dart, node_state.dart, message_repository_impl.dart | traced all seams | **Plan site 2461 imprecise:** prod `peerNotFound`/`dialFailed` return a NON-NULL `failedMessage` (use_case:1305-1345, envelope preserved) → they flow through the `message!=null` branch (2449), NOT the `else` (2461). Widget-test fakes return null → the `else` branch. **BOTH need the gate.** Also found a THIRD status writer: `_restoreComposerSnapshot` (2751) unconditionally re-stamps `'failed'`. | gate both branches + skip restore |
| 2026-07-01 | RED tests added | handle_delivery_receipt_use_case_test.dart (TC-185-10/11/12/31/32), conversation_wired_offline_send_ux_test.dart (TC-185-01/01b/02/20/21 + harness), conversation_wired_test.dart (TC-185-30 extend :7140, TC-185-33) | TC-185-10 RED (status stays failed); TC-185-01/01b RED (failed not sent); TC-185-20 RED (no honest copy); S1 RED (renamed copy) | RED for documented reasons | implement |
| 2026-07-01 | implementation | handle_delivery_receipt_use_case.dart (failed→delivered arm), conversation_wired.dart (senderOffline gate on BOTH branches + snackbar + skip composer-restore when retriable), delivered_status_minting_sites_test.dart (2→3) | — | `dbUpdateMessageStatus` is status-only (envelope preserved) — no migration; literal snackbar copy (matches existing literal switch, l10n deferred per arbiter) | direct GREEN |
| 2026-07-01 | direct GREEN | — | offline_send_ux +9 all pass; handle_delivery_receipt +10 all pass; delivered_status_minting +2; TC-185-30/33 pass; `flutter analyze` 0 issues | green | preservation |
| 2026-07-01 | preservation GREEN | — | `1to1` +1436 all pass (one flake on run 1, clean on re-run); `feature-host-all` 193 PASS + 1 unrelated flake (`feed/domain/models/feed_item_test.dart` — no dep on the change; passes clean standalone +57; gate exit 0); `core-host-all` running | — | mutation-verify |
| 2026-07-01 | mutation verified | — | via RED-first capture: TC-185-10 RED on HEAD (status stayed 'failed', no arm) → GREEN after arm; TC-185-01/01b/20 + S1 RED on HEAD → GREEN after the conversation_wired gate; census RED-if-not-bumped. Each production edit has a documented re-red (the diff vs HEAD IS the mutation). | satisfied | QA |
| 2026-07-01 | QA (independent) | — | adversarial multi-lens review workflow (`wf_6e1bee82`): prod-correctness, preservation, receipt-arm, test-sufficiency, scope-fidelity + verify pass | see Reviewer Findings addendum | finalize |

## Source Of Truth
- Spec: `Test-Flight-Improv/185-offline-send-failure-truthfulness-spec.md`
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose)
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh`
- Numbering / index: `Test-Flight-Improv/00-INDEX.md`

## Session Classification
implementation-ready.

## Exact Problem Statement
When the sender's connection is down, a 1:1 send is stamped terminal `failed` (`conversation_wired.dart:2461-2463`: any non-success → `'failed'`). This (a) shows a red Retry that never clears even after the message is delivered, and (b) raises a snackbar blaming the *contact* ("Contact appears offline"). Device-captured (Pixel on degraded mobile → iPhone on WiFi, 2026-07-01): `DELIVERY_RECEIPT_NO_TRANSITION status:"failed"` ×6 for a message the peer actually received, while 17 `sent`/`inboxed` rows converged normally.

**What must improve:** an offline send must stay in the **existing, still-wired self-healing lane** (`retryUnacked` picks up `status='sent'` rows → `inboxed`, then the receipt → `delivered`) instead of dropping to terminal `failed`; and the failure snackbar must name the real cause (sender offline).

**What must stay unchanged (→ preserved-green sentinels):** a *genuinely* failed send (bad payload, unsupported encryption, or **online**-but-recipient-unreachable) still surfaces `failed`/Retry; the existing `inboxed→delivered` / `sent→delivered` receipt arms and the 17-happy-path still fire; no row ever reaches `delivered` without a receiver receipt.

## Root Cause (verify → refute confirmed)
Two production seams, both survived the workflow's adversarial refute pass (`wf_249ee5db`):

1. **Eviction from the lane** — `conversation_wired.dart:2461-2463` stamps *any* non-success `SendChatMessageResult` as `'failed'`. An offline sender's FDC race returns `peerNotFound` (`send_chat_message_use_case.dart:2096-2101` maps reason `'peer_not_found'`), so it's stamped `failed`. The row already carries its wire envelope (Section-4 contract, `send_chat_message_use_case.dart:507`), so it is eligible for `getUnackedOutgoingMessages` (`messages_db_helpers.dart:645-666`: `status='sent' AND wire_envelope IS NOT NULL`) on **every count except its status**. `retryUnacked` (`retry_unacked_messages_use_case.dart:43-108`, wired `handle_app_resumed.dart:672` + connectivity) and `handleDeliveryReceipt` (`handle_delivery_receipt_use_case.dart:63-88`, arms `inboxed→delivered`/`sent→delivered` only) both skip `failed`.
2. **No sync sender-offline consult** — the snackbar switch (`conversation_wired.dart:2483-2495`) keys only off the result. **Refuted alternatives:** `peerNotFound` is *not* always sender-offline (it legitimately fires when the recipient has no relay reservation while the sender is online — `send_chat_message_use_case.dart:2096`), so a blanket reclassify is wrong. The connectivity_plus (182) signal is **edge-only async** (`connectivity_signal.dart:21` `Stream<void>`, no `isOffline` getter, not injected into the screen) — it **cannot** answer "am I offline now." The available **synchronous** sender-offline proxy is `widget.p2pService.currentState.relayReady` (`p2p_service.dart:131` sync getter, already injected; `node_state.dart:150-156` `relayReady = relayState=='online' OR circuitAddresses nonempty`).

Refuted / do-NOT-re-introduce: `failed` is **not** deliberately excluded from the receipt handler for a documented safety reason — the "terminal failed" comments in the tree are the **media-download** status axis (`download_media_use_case.dart:369`), unrelated; adding `failed→delivered` is safe because a receipt is receiver-minted and peer-authenticated (`handle_delivery_receipt_use_case.dart:55`).

## Real Scope
**In scope:**
- `conversation_wired.dart:2461-2495` — one connectivity-gated predicate `senderOffline = !widget.p2pService.currentState.relayReady` that (i) lands a connectivity-class failure in retriable `'sent'` (keep the row in the lane, wire envelope preserved) instead of `'failed'`, and (ii) selects the honest snackbar copy.
- `handle_delivery_receipt_use_case.dart` — add the defensive 3rd arm `conditionalTransitionStatus(id, from:'failed', to:'delivered')`.
- `delivered_status_minting_sites_test.dart` — bump the census for that file `2 → 3`.
- l10n copy for the sender-offline snackbar (reuse/rename "Network not connected. Message saved." → "No internet connection. Message will send when you're back online.").

**Out of scope (owned elsewhere):** cross-network reachability (DCUtR/relay-outage recovery); transport budgets / the send race (warm-send-budget investigation closed — LAN ~170 ms, cross-network 6 s was a relay outage); the long-press context-overlay frozen-snapshot second-half (below — flagged, scoped to a follow-up unless trivial).

## Files To Inspect Next
Production: `conversation_wired.dart:2455-2530` (fallbackStatus + snackbar), `handle_delivery_receipt_use_case.dart:63-98`, `node_state.dart:150-159`, `retry_unacked_messages_use_case.dart:43-108`, `messages_db_helpers.dart:645-666`, `conversation_screen.dart:568-574` (failed→Retry mapping), `letter_card.dart:486-509,1070-1088`.
Direct tests: `conversation_wired_offline_send_ux_test.dart`, `conversation_wired_test.dart:7140`, `handle_delivery_receipt_use_case_test.dart`, `delivered_status_minting_sites_test.dart`, `retry_unacked_messages_use_case_test.dart`.
Dependency-only: `message_repository_impl.dart:399-418` (conditionalTransitionStatus CAS + stream emit), `fake_message_repository.dart:223-237`, `fake_p2p_service.dart` (currentState).

## Existing Tests Covering This Area
- `conversation_wired_offline_send_ux_test.dart` — send-failure UX at this exact site (4 tests). In `ONE_TO_ONE_TESTS[85]`. **Builds `FakeP2PService()` with default `currentState` (NodeState.stopped)** — the new RED tests set `currentState` explicitly.
- `conversation_wired_test.dart:7140` — `'repository change updates failed outgoing reply status in place'`: already drives `failed→delivered` through the real `messageChanges` path; asserts only the error glyph clears, **NOT** the Retry button. In `ONE_TO_ONE_TESTS[75]`.
- `handle_delivery_receipt_use_case_test.dart` — the receipt arms (inboxed/sent→delivered, foreign-peer, idempotent). Auto-glob `feature-host-all`.
- `delivered_status_minting_sites_test.dart` — census pinning `toStatus:'delivered'` writes per file (`handle_delivery_receipt_use_case.dart == 2`). Auto-glob.
- `retry_unacked_messages_use_case_test.dart` — the `sent→inboxed` convergence. Auto-glob.

Missing coverage gaps: no test asserts the offline send lands `sent` (not `failed`); no test asserts the Retry *affordance* clears on `failed→delivered`; no test asserts the `peerNotFound→"Contact appears offline"` branch or its offline flip; no test that `failed`+receipt→`delivered`.

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

1. `conversation_wired_offline_send_ux_test.dart`::`TC-185-01 offline send (relay down) lands retriable 'sent', not 'failed'`
   - Tier: widget (testWidgets + FakeP2PService with `currentState` = not-relayReady + injected send recorder returning `peerNotFound`).
   - RED on HEAD because: `fallbackStatus` maps `peerNotFound→'failed'` unconditionally → persisted status `failed` (assert `sent`).
   - GREEN after fix asserts: persisted/rendered status is `'sent'` (single tick), `find` of the Retry chip `findsNothing`; wire_envelope preserved on the row.
   - Mutation that re-reds: revert the `senderOffline` branch → `'failed'` → red.

2. `conversation_wired_offline_send_ux_test.dart`::`TC-185-02 online peerNotFound still fails (no over-correction)`
   - Tier: widget (FakeP2PService `currentState` = relayReady=true, send → `peerNotFound`).
   - RED on HEAD because: N/A on HEAD (already `failed`) — this is the **gating lock**; RED against a *naive* fix. Documented mutation: make the fix ignore `relayReady` (blanket reclassify) → status becomes `sent` → red.
   - GREEN asserts: status `failed`, Retry chip present, snackbar "Contact appears offline."

3. `handle_delivery_receipt_use_case_test.dart`::`TC-185-10 a receipt lifts a 'failed' row to 'delivered'`
   - Tier: application (fake MessageRepository seeded with a `failed` outgoing row + peer-authenticated `delivery_receipt`).
   - RED on HEAD because: no `failed→delivered` arm → `DELIVERY_RECEIPT_NO_TRANSITION`, status stays `failed`.
   - GREEN asserts: status `delivered`, `DELIVERY_RECEIPT_APPLIED` emitted (AND NOT `DELIVERY_RECEIPT_NO_TRANSITION`).
   - Mutation that re-reds: remove the 3rd `conditionalTransitionStatus(from:'failed')` arm → red.
   - Distinct-event discriminator: assert `DELIVERY_RECEIPT_APPLIED` AND NOT `DELIVERY_RECEIPT_NO_TRANSITION`.

4. `handle_delivery_receipt_use_case_test.dart`::`TC-185-11 foreign-peer receipt does NOT lift a 'failed' row`
   - Tier: application. RED-able via mutation: drop the `:55` peer guard → red. GREEN asserts status stays `failed`, `DELIVERY_RECEIPT_FOREIGN_PEER` emitted.

5. `conversation_wired_offline_send_ux_test.dart`::`TC-185-20 offline failure snackbar names the sender's connection`
   - Tier: widget (currentState not-relayReady, `peerNotFound`).
   - RED on HEAD because: shows "Contact appears offline. Message saved."
   - GREEN asserts: snackbar text is the sender-offline copy (no-internet), NOT "Contact appears offline."
   - Mutation that re-reds: revert the snackbar `senderOffline` branch → red.

6. `conversation_wired_test.dart`::`TC-185-30 Retry affordance clears when a failed reply flips to delivered` (extend the `:7140` test)
   - Tier: widget (existing harness: seed `failed` id `failed-retry` outgoing text → `showFailedTextRetry` true; flip to `delivered` via `messageChanges`).
   - RED on HEAD because: `:7140` never asserts the Retry control; add `expect(find.byX(retry), findsOneWidget)` BEFORE and `findsNothing` AFTER — passes today for the glyph but the **new assertion pair is the lock**; RED against a regression that keeps Retry.
   - Mutation that re-reds: make `_shouldRefreshFromRepositoryChange` drop the delivered emit (or LetterCard cache status) → Retry persists → red.

7. `delivered_status_minting_sites_test.dart` (census update, not a behavior test) — bump expected `handle_delivery_receipt_use_case.dart` from `2 → 3`. Without this edit the whole file goes RED once arm #3 lands (documented expected-RED that the fix commit resolves).

## Test Coverage Matrix
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-185-01 | UI status decision | widget | conversation_wired_offline_send_ux_test::TC-185-01 | peerNotFound→'failed' unconditional | revert senderOffline branch | `./scripts/run_test_gates.sh 1to1` | in `ONE_TO_ONE_TESTS[85]` (exists) |
| TC-185-02 | gating (no over-correct) | widget | conversation_wired_offline_send_ux_test::TC-185-02 | (lock vs naive fix) | ignore relayReady→sent | `./scripts/run_test_gates.sh 1to1` | `ONE_TO_ONE_TESTS[85]` |
| TC-185-03 | lane eligibility | integration (real DB) | `test/core/database/helpers/messages_db_helpers_test.dart`::TC-185-03 | kept-'sent'+wire_envelope row picked by dbLoadUnackedOutgoingMessages | mark 'failed'→excluded (real SQL) | `flutter test test/core/database/helpers/messages_db_helpers_test.dart --plain-name TC-185-03` | AUTO (core-host-all glob) |
| TC-185-04 | end-to-end recover (**PROD-CRITICAL**) | device-proof | 185 runsheet TC-185-04 | (device-only: real relay outage→recover; unit coverage NOT sufficient) | n/a | two-phone rig (below) | runsheet |
| TC-185-10 | receipt lifts failed | application | handle_delivery_receipt_use_case_test::TC-185-10 | no failed→delivered arm | remove 3rd arm | `flutter test .../handle_delivery_receipt_use_case_test.dart` | AUTO (feature glob) |
| TC-185-11 | peer-auth preserved | application | handle_delivery_receipt_use_case_test::TC-185-11 | drop :55 guard → red | remove peer guard | same | AUTO |
| TC-185-12 | failed+no receipt stays | application | handle_delivery_receipt_use_case_test::TC-185-12 | (invariant lock) | blanket clear failed | same | AUTO |
| TC-185-13 | census + happy-path | scan gate | delivered_status_minting_sites_test (2→3) | file RED once arm lands | keep count at 2 | `flutter test .../delivered_status_minting_sites_test.dart` | AUTO |
| TC-185-20 | honest snackbar | widget | conversation_wired_offline_send_ux_test::TC-185-20 | shows "Contact appears offline" | revert snackbar branch | `./scripts/run_test_gates.sh 1to1` | `ONE_TO_ONE_TESTS[85]` |
| TC-185-21 | online → contact copy | widget | conversation_wired_offline_send_ux_test::TC-185-21 | (lock vs naive) | ignore relayReady | `./scripts/run_test_gates.sh 1to1` | `ONE_TO_ONE_TESTS[85]` |
| TC-185-22 | offline snackbar | device-proof | 185 runsheet TC-185-22 | device-only | n/a | two-phone rig | runsheet |
| TC-185-30 | Retry clears | widget | conversation_wired_test::TC-185-30 (extend :7140) | no Retry-control assertion exists | drop delivered emit / cache status | `./scripts/run_test_gates.sh 1to1` | `ONE_TO_ONE_TESTS[75]` |
| TC-185-31 | never falsely delivered | application | handle_delivery_receipt_use_case_test::TC-185-31 | (invariant) | any auto-deliver w/o receipt | same | AUTO |
| TC-185-32 | atomic/CAS transition | application | handle_delivery_receipt_use_case_test::TC-185-32 | (invariant lock) | replace CAS with unconditional saveMessage → concurrent-downgrade red | `flutter test .../handle_delivery_receipt_use_case_test.dart` | AUTO |
| TC-185-33 | reopen durability | widget/repo | conversation_wired_test::TC-185-33 | (lifecycle lock) | flip only in-memory (skip persist) → reopen shows failed/Retry | `./scripts/run_test_gates.sh 1to1` | `ONE_TO_ONE_TESTS[75]` |
| TC-185-34 | long-press overlay sibling | widget | conversation_screen_test::TC-185-34 (or scoped follow-up) | overlay snapshot frozen at failed | overlay re-reads status | `./scripts/run_test_gates.sh 1to1` | curated 1to1 (or DEFERRED — see Blind-Spot) |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability** — reopen the conversation / restart after `failed→delivered`: status must reconstruct as `delivered` (persisted, not the in-memory flip). → **Add TC-185-33** (widget/repo: re-load messages → status delivered, no Retry). The offline-`sent` row must also survive restart and still be lane-eligible.
- **Sibling-surface consistency** — the **long-press context overlay** holds a **frozen LetterCard snapshot** (`conversation_screen.dart:676-685,681`) that does not react to `messageChanges`, so it can keep showing Retry after `delivered`. → **Flagged second-half.** Add TC-185-34 (widget: overlay reflects post-flip status) IF the overlay is trivially made to re-read; otherwise scope to a follow-up and record it here (do not leave as an untested "stays unchanged" claim).
- **Destructive-action side-effects** — N/A: 185 introduces no delete/cleanup path.
- **Invariant re-verification under new transitions** — the new `offline→sent` and `failed→delivered` transitions re-assert "never delivered without a receipt" (TC-185-31) and "genuine failures stay failed" (TC-185-02/12).

## Invariants (locked by tests)
- INV-1: an offline send is retriable (`sent`, wire envelope kept), never terminal `failed` → TC-185-01, TC-185-03.
- INV-2: a genuine/online failure stays `failed` (Retry) → TC-185-02, TC-185-12.
- INV-3: a receiver-authenticated receipt is the ONLY thing that lifts `failed`; nothing auto-delivers → TC-185-10/11/31.
- INV-4: the UI Retry affordance is a pure function of persisted status via `messageChanges` (no stale cache) → TC-185-30, TC-185-33.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row.

## Step-By-Step Implementation Plan
1. Add the RED tests (catalog 1–6) + set the census to 3 (7). Run the focused cmds; confirm each fails for its documented reason.
2. `conversation_wired.dart:2461` — compute `final senderOffline = !widget.p2pService.currentState.relayReady;` once. In the `fallbackStatus` switch, when the result is a connectivity-class failure (`peerNotFound`/`dialFailed`/`nodeNotRunning`) **and** `senderOffline`, land status `'sent'` (retriable, wire envelope preserved) instead of `'failed'`. Stop-if: `_persistMessageStatus`/`_updateLocalMessageStatus` clears the wire envelope → keep the persisted envelope (persist status only) or route through the use-case status writer; do not hack around it.
3. `conversation_wired.dart:2484-2494` — same `senderOffline` gate selects the honest snackbar copy (no-internet) over the contact-offline copy; keep the contact copy when online.
4. `handle_delivery_receipt_use_case.dart:80` — after the `sent→delivered` arm and before `NO_TRANSITION`, add `conditionalTransitionStatus(id, from:'failed', to:'delivered')`; on flip, the existing `saveMessage(...wireEnvelope:null)` + `DELIVERY_RECEIPT_APPLIED` path runs unchanged.
5. `delivered_status_minting_sites_test.dart` — expected map `handle_delivery_receipt_use_case.dart: 3`.
6. l10n: rename/add the sender-offline snackbar string across `app_en.arb` (+ ar/de) and regenerate `app_localizations`.
7. Rerun direct → preservation (`1to1`, `feature-host-all`) → named gates. Then the device-proof (TC-185-04/22).

## Risks And Edge Cases
- **`relayReady` TTL lag (~30 s)** — a just-went-offline sender may briefly read `relayReady==true` and stamp `failed`. Acceptable: the defensive receipt arm (TC-185-10) still recovers such a row to `delivered` when it later delivers. Documented, pinned by TC-185-10.
- **Double status writer** — the send use case and `conversation_wired` both write status; the UI write is last. Verify (step 2) the use case doesn't independently re-stamp `failed` after; if it does, move the gate into the use case. Pinned by TC-185-01 asserting the *persisted* status.
- **Wire-envelope loss on the status write** — if setting `'sent'` via the UI path nulls the envelope, the lane can't pick it up. Pinned by TC-185-01 (assert envelope present) + TC-185-03 (lane picks it up).

## Device/Relay Proof Profile
Requires the two-phone rig for closure (TC-185-04, TC-185-22) — the real relay-outage → recover flow is device-only. Runsheet: `185-offline-send-truthfulness-device-proof-runsheet.md` (to author). Rig: Pixel 6 `21071FDF600CSC` (offline via WiFi-off with bad/absent mobile) + iPhone 11 `00008030`, `FDC_FLOW_LOG=1` builds; grep `CHAT_MSG_SEND_TIMING`, `DELIVERY_RECEIPT_APPLIED` / `DELIVERY_RECEIPT_NO_TRANSITION`, `INBOX_STORE`. PASS = offline send shows single tick (no Retry) + honest snackbar; on reconnect the row converges to `delivered` with `DELIVERY_RECEIPT_APPLIED` and no lingering `NO_TRANSITION status:"failed"`. No feature flag, no DB migration.

## Acceptance Gates  (literal)
```bash
# RED (before production edits) — must FAIL for the documented reason
flutter test test/features/conversation/presentation/screens/conversation_wired_offline_send_ux_test.dart --plain-name 'TC-185-01'
flutter test test/features/conversation/application/handle_delivery_receipt_use_case_test.dart --plain-name 'TC-185-10'
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'TC-185-30'

# Direct GREEN (after fix)
flutter test test/features/conversation/presentation/screens/conversation_wired_offline_send_ux_test.dart
flutter test test/features/conversation/application/handle_delivery_receipt_use_case_test.dart
flutter test test/features/conversation/application/delivered_status_minting_sites_test.dart

# Preservation sentinels (must stay green)
./scripts/run_test_gates.sh 1to1                 # expect: all pass (incl ONE_TO_ONE_TESTS[75],[85])
./scripts/run_test_gates.sh feature-host-all     # expect: all files pass

# Named gate for the touched subsystem
./scripts/run_test_gates.sh core-host-all        # message repo / db helpers

# Device-proof discovery/run
# (manual two-phone runsheet — no /sims scenario; see Device/Relay Proof Profile)

# Hygiene
flutter analyze          # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- Expected RED: TC-185-01/10/20/30 before fix; `delivered_status_minting_sites_test` file RED after arm #3 until the census is bumped (same commit).
- Pre-existing dirty: `info.plist`, `ios/Podfile.lock`, `ios/Runner.xcodeproj/project.pbxproj` (iOS build drift, not this change).
- Environment blocker (NOT product): no two-phone rig available → device rows deferred, host rows still gate.
- Scope drift (BLOCKING): any failure outside the Scope Guard.

## Done Criteria
- [x] RED added first, failed for the expected reason (TC-185-01/01b/10/20 + S1 RED on HEAD).
- [x] Mutation-verified (RED-first captures; dialFailed arms looped; real-DB TC-185-03; census 2→3).
- [x] Direct GREEN + `1to1` (+1436) + `feature-host-all` (193, +1 unrelated flake, passes standalone) + `core-host-all` (273) green.
- [x] No DB migration (reuses `sent`/`failed`/`delivered` + existing columns; `dbUpdateMessageStatus` is status-only).
- [ ] **Device-proof TC-185-04/22** PASS on the two-phone rig (closure gate) — DEFERRED (no rig in this environment).
- [x] Long-press-overlay second-half recorded as a scoped follow-up (TC-185-34); review confirmed the overlay is `IgnorePointer`/non-interactive (cosmetic-only), so no duplicate-send trap.
- [x] `flutter analyze` 0 new (7 changed files clean); `git diff --check` clean.

## Scope Guard (hard "Do not")
- Do not build a new retry/reconcile mechanism — reuse `retryUnacked` + the receipt lane.
- Do not reclassify `peerNotFound` blindly — gate on `!relayReady` (else TC-185-02/21 red).
- Do not touch transport budgets / the send race / DCUtR / relay-outage recovery.
- Do not introduce a new message status (reuse `sent`) — no migration.

## Accepted Differences / Intentionally Out Of Scope
- The `relayReady` proxy is not OS-truth connectivity (no sync OS signal exists at the site); the defensive receipt arm covers the lag-window miss. A true injected `isOffline` predicate is a possible later refinement (owns: a future connectivity-plumbing slice).
- Cross-network deliverability (relay outage, DCUtR) is unchanged — 185 makes the UX truthful, not the network faster.

### Execution-time decisions (adaptations to plan)
- **`nodeNotRunning` EXCLUDED from the status reclassify** (plan listed it as connectivity-class). It early-returns *before* the wire envelope is persisted (`send_chat_message_use_case.dart:374`), so a kept-`sent` row would NOT be `getUnackedOutgoingMessages`-eligible (no envelope) — a silent stuck single-tick. It stays `failed` (the `retryFailedMessages` lane re-sends from plaintext). The existing "PRESERVE nodeNotRunning→failed" sentinel (offline fake) is the guard that forced this. nodeNotRunning still gets the honest *snackbar* copy (it is inherently sender-side).
- **Gate lives at BOTH result branches in `conversation_wired`** (not only 2461). The `message!=null` branch (2449) reclassifies + persists `sent`; the `else` branch (2461) sets `fallbackStatus`; the snackbar block skips `_restoreComposerSnapshot` when retriable (that method was the real terminal `failed` stamper + composer-draft restorer — restoring both would resurrect Retry and invite a duplicate send). **Added TC-185-01b** to lock the `message!=null` production path (envelope preserved + `getUnacked` picks it up) that the plan left device-only.
- **Snackbar copy is a literal**, matching the existing literal `switch` at the same site (all sibling failure snackbars are literals). Full l10n (`app_en.arb`+ar/de + regen) would introduce one l10n branch into an otherwise-literal switch (inconsistent, higher-risk, generated-file churn) — the arbiter deferred exact wording to execution. Copy: `"No internet connection. Message will send when you're back online."` (renamed from the old nodeNotRunning `"Network not connected. Message saved."`).
- **TC-185-34 (long-press overlay) → scoped follow-up, NOT fixed.** `conversation_screen.dart:675-685` passes a pre-built `selectedMessage: buildLetterCard()` **frozen widget snapshot** into `_showMessageContextOverlay`; the overlay is a separate route holding that snapshot and does not subscribe to `messageChanges`. It is NOT "trivially made to re-read" (would require re-plumbing the overlay to rebuild from the live message stream). Recorded here as an explicit follow-up per the plan's Blind-Spot rule — the main-thread bubble (LetterCard in the list) DOES react to `messageChanges` (locked by TC-185-30/33); only the transient long-press overlay can show a stale Retry until dismissed.

## Dependency Impact
- None inbound. Reinforces the 114–116 send-truthfulness invariants; composes with 182 (connectivity) and 183 (keepalive) without touching them.

## Reviewer Findings
Sufficiency checklist run. **Spec-case totality:** all 13 spec IDs (01–04, 10–13, 20–22, 30–32) have matrix rows + a named test at the right tier; plan adds TC-185-33/34 for the blind-spot classes. **Mutation-verifiable:** every production edit (offline→sent gate, snackbar gate, failed→delivered arm, census bump) has a named re-red revert. TC-185-02/21 are **gating/preservation locks** (green on HEAD; red against a *naive* fix that ignores `relayReady`) — documented as such, not RED-first. **No vacuous coverage:** TC-185-10 asserts `DELIVERY_RECEIPT_APPLIED` AND NOT `DELIVERY_RECEIPT_NO_TRANSITION`. **No migration** (reuses `sent` status + existing columns) — the DB-migration gate is a justified N/A. **PROD-CRITICAL leg named:** TC-185-04 (real relay-outage→recover; unit coverage explicitly insufficient). **Preservation sentinels:** `1to1`, `feature-host-all`, `core-host-all` with commands. **Refuted findings recorded** in Root Cause (peerNotFound ≠ always-offline; connectivity_plus async/edge-only; `failed` not deliberately excluded). Matrix has zero empty cells in tier/mutation/gate/registration.
Open item (non-blocking): TC-185-34 (long-press overlay frozen snapshot) is a genuine sibling-surface second-half — planned as either a widget test or an explicitly-recorded scoped follow-up; execution decides based on whether the overlay is trivially made to re-read `messageChanges`.

## Arbiter Decision
Structural blockers: none. Deferred details: TC-185-34 fix-vs-follow-up (execution-time call); exact l10n string wording. Accepted differences: `relayReady` is a relay-reachability proxy, not OS-truth connectivity (covered by the defensive receipt arm for the TTL-lag miss). **Verdict: structurally sufficient — hand off to execution.**

## Post-Implementation Adversarial Review (workflow wf_6e1bee82 — 5 lenses × verify)
13 agents, 5 lenses (prod-correctness, preservation, receipt-arm, test-sufficiency, scope-fidelity) + adversarial verify. **5 confirmed, 3 refuted.**

**Confirmed → acted on in this change:**
- **[high] `dialFailed` had no test.** `keepRetriableOffline` + the snackbar include `dialFailed`, but every 185 test used `peerNotFound` → an arm-specific revert survived green. **Fixed:** the offline-reclassify test (TC-185-01b) and the snackbar tests (TC-185-20/21) now loop over `{peerNotFound, dialFailed}`, guarding both `||` arms + both `switch` arms.
- **[med] TC-185-01 modelled a production-impossible shape** (null-message `peerNotFound`) and pinned the else-branch `keepRetriableOffline?'sent'` which is unreachable in prod (real `peerNotFound`/`dialFailed` are non-null → 2449 branch). **Fixed:** corrected TC-185-01's comment to label it a *synthetic defensive* else-branch test (the real production path is locked by TC-185-01b, which now also covers `dialFailed`).
- **[med] TC-185-03 was a phantom** in the matrix (cited a real-DB integration test never written; TC-185-01b uses a fake mirror that diverged from the SQL). **Fixed:** added a real in-memory-DB TC-185-03 in `messages_db_helpers_test.dart` asserting `dbLoadUnackedOutgoingMessages` picks a kept-`sent`+wire_envelope row and **excludes** it after `dbUpdateMessageStatus(...,'failed')` — exercising the actual SQL predicate + the named mutation.
- **[nit] Stale class-doc invariant** in `handle_delivery_receipt_use_case.dart` ("a late receipt can never resurrect a row that already settled") now contradicts the intentional `failed→delivered` arm. **Fixed:** doc updated.

**Confirmed → recorded as follow-ups (NOT fixed here — see Follow-ups):** the fast-reconnect self-heal latency and the offline-edit path.

**Refuted (verified not-real):**
- *Unconditional `sent` write downgrades a concurrent `delivered`/`inboxed`* — refuted: the write window (send-return → status write) is microtask-scale with no network wait; a receipt is network-round-trip-scale, and a `keepRetriableOffline` send by definition did NOT deliver (no receipt yet). The eventual receipt lands on the `sent→delivered` arm, not `failed→delivered`.
- *else-branch fabricates an envelope-less `sent` that never converges* — refuted: prod-unreachable (`peerNotFound`/`dialFailed` are always non-null → never hit the else branch); the real path is guarded by TC-185-01b (envelope + `getUnacked` assertions).
- *Long-press overlay stale Retry invites a duplicate send* — refuted: the overlay wraps the frozen `selectedMessage` in an `IgnorePointer` (`message_context_overlay.dart`), so the Retry glyph is non-interactive and transient (dismissed with the menu). Cosmetic-only; TC-185-34 stays a documented follow-up.

## Follow-ups (recorded, out of scope for this change)
- **FU-185-A [med] Fast-reconnect self-heal latency — IMPLEMENTED (2026-07-01) in `186-reconnect-latency-tightening-tdd-plan.md`.** Device-confirmed (Pixel capture 19:01): on WiFi-restore the queued messages re-inboxed ~20s later (relay re-dial ~15s + the retrier's 5s debounce), and a <60s-old offline row would have waited up to the 5-min periodic (the 60s age gate). **Fix shipped:** `retryUnackedMessages` gained an `olderThan` param; the retrier's first post-online (reconnect) retry now passes `Duration.zero` (drops the age gate → 5-min worst case becomes ~one debounce), while the periodic pass keeps 60s (anti-race). TDD reconsidered the "drop the 5s debounce / fire immediately" part: it broke the `debounce cancels previous timer on rapid state changes` flap-coalescing guard, and the dominant delay is the transport-level relay re-dial, so the debounce is retained. See 186 for the RED catalog + gates.
- **FU-185-B [med] Offline 1:1 EDIT path not gated.** Editing a delivered/sent message while offline flips the row to terminal `failed` (no honest snackbar) via the ungated edit branch (`conversation_wired.dart:2001-2043`). **Pre-existing** (unchanged by 185), **out of the send-path spec scope**, and **self-heals** (`retryFailedMessages` + `deriveRetryAction==edit`); the new `failed→delivered` arm also lifts an edit row that reaches the peer. Apply the same `senderOffline` classification + honest snackbar to the edit branch in a follow-up.
- **FU-185-C [low] Offline VOICE send** lands terminal `failed`+Retry with contact-neutral copy (voice path `conversation_wired.dart:3268-3333` is ungated). Same treatment as FU-185-B.
- **Accepted:** `nodeNotRunning` shows a `failed`/Retry bubble alongside the "will send when you're back online" snackbar — the promise is truthful (`retryFailedMessages` re-sends `failed` rows on resume/reconnect); the Retry is an optional manual accelerator, not a contradiction. Kept `failed` (no wire envelope → not `getUnacked`-eligible; belongs in the `retryFailedMessages` lane).

## Final Execution Verdict
**Implemented + host-verified.** Direct GREEN (offline_send_ux, handle_delivery_receipt, delivered_status_minting, conversation_wired TC-185-30/33) + preservation gates (`1to1` +1436; `feature-host-all` 193 PASS + 1 unrelated flake passing standalone; `core-host-all` green) + `flutter analyze` 0 new. Mutation-verifiability established via RED-first captures and hardened after review (dialFailed arms + real-DB TC-185-03 now locked). Root-cause discovery during execution corrected two plan imprecisions (the 2449 non-null branch + the `_restoreComposerSnapshot` third status-writer), both handled. **Device-proof (TC-185-04 / TC-185-22) remains the closure gate** — deferred (no two-phone rig in this environment). Three follow-ups recorded above.
