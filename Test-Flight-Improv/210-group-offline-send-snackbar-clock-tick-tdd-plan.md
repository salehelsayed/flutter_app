# 210 - Group Offline-Send: No-Internet Snackbar + Clock-Not-Tick While Queued  (Bug)

Status: implemented (host-green 2026-07-05) + **210b result-contract fix (2026-07-05)** — the original closure did not work on device; see the 210b Addendum at the end of this doc for the corrected root cause (a real offline send returns `success`/'pending' via publish-without-custody, so the `!relayReady` failure branch never ran) and the result-contract re-key.
Spec: free-text intent (no formal spec) — user bug report, product decisions captured inline below

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-04 | Evidence Collector | group_conversation_wired.dart, letter_card.dart, group_conversation_screen.dart, group_message.dart, node_state.dart, send_group_message_use_case.dart, conversation_wired.dart (1:1 ref), recover_stuck_sending_group_messages_use_case.dart, group_message_repository_impl.dart, main.dart:1498/3018, handle_app_resumed/paused | Two root-cause gaps confirmed via 3-agent verify→refute; both SURVIVE (nothing already-fixed) | Build matrix |
| 2026-07-04 | Planner | (this doc) | Design = new `queued_offline` status → clock; snackbar mirrors 1:1; recovery SQL extended to preserve re-send; test default flipped online | Emit RED catalog + matrix |
| | Reviewer (sufficiency) | | | |
| | Arbiter | | (final structural verdict) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-07-05 | contract extraction | (git status --short) | dirty tree = docs only (00-INDEX, 209-*, 210 plan) — preserved | scope confirmed | RED |
| 2026-07-05 | RED tests added | letter_card_test, group_conversation_wired_test (+_GatedReliableFailBridge, online setUp flip), group_conversation_screen_test, group_message_repository_impl_test | #1 schedule_rounded found 0; #3/#5 "back online" found 0; #4/#10 no clock; #8 found 0; #9 recovered Expected 1 Actual 0; guards #2/#6/#7 GREEN | RED for expected reason | implement |
| 2026-07-05 | implementation | group_message.dart (const), letter_card.dart (icon/color/semantic), group_conversation_wired.dart (text+voice optimistic ternary, text+voice offline branch, `_markOutgoingMessageQueuedOffline`, `_showOfflineQueuedSnackBar`), send_group_message_use_case.dart (reuse whitelist +queued_offline), group_messages_db_helpers.dart (`dbTransitionGroupSendingToFailed` predicate) | scoped files only | direct GREEN | |
| 2026-07-05 | direct GREEN | (above) | letter_card 114✓; screen 64✓; repo 49✓; wired 174✓ (167 baseline + 6 new + coalesced) | reds now green | preservation |
| 2026-07-05 | preservation GREEN | — | `run_test_gates.sh 1to1` 1486✓ (no 1:1 regression from shared letter_card); `groups` 1118✓ | sentinels green | named gates |
| 2026-07-05 | named gates | scripts/run_test_gates.sh (GROUP_TESTS += repo impl test) | send_use_case 144✓; recover_stuck use_case 4✓; group_resume_recovery 92✓; `feature-host-all` (636 files) running | gate green | QA |
| 2026-07-05 | QA (independent) | — | flutter analyze: 0 NEW (6 pre-existing infos/1 pre-existing unused import, all on HEAD); git diff --check clean | blocking: none | verdict |
| 2026-07-05 | **210b device failure diagnosed** | (read-only workflow `wf_deb5e88a-74a`, 4 traces + 4 adversarial verifiers, 0 refuted) | real offline send ⇒ `ok:true/publishSucceeded:true/inboxStored:false/topicPeers:0` ⇒ use case `success`/'pending' ⇒ happy branch (tick, no snackbar); NETWORK_DOWN test stub shape does not exist in go-mknoon; GIRD-001 already pinned the contradiction | 210 snackbar branch unreachable on device | 210b RED |
| 2026-07-05 | 210b RED | send_group_message_use_case_test (GIRD-001 zero-peers re-pinned to queuedOffline/'queued_offline'), group_conversation_wired_test (+210b group, realistic no-custody bridge), group_message_repository_impl_test (+repush-selection lock, +fixture wiring of dbLoadGroupMessagesWithFailedInboxStore), retry_failed_group_inbox_stores_use_case_test (+queued_offline promote) | GIRD Expected queuedOffline Actual success; wired 210b-1/2/4 snackbar found 0 (guard 210b-3 GREEN); repo ids empty; repush retried 0 | RED for expected reasons | implement |
| 2026-07-05 | 210b implementation | send_group_message_use_case.dart (enum `queuedOffline`, in-doubt arm split), group_conversation_wired.dart (text+voice `queuedOffline` branches, snackbar copy keyed on relayReady per 192), group_messages_db_helpers.dart + in_memory fake (repush predicate += 'queued_offline'), retry_failed_group_inbox_stores_use_case.dart (doc), share_batch_delivery_coordinator.dart (queuedOffline arms) | direct GREEN: GIRD✓ repo✓ repush✓ wired 210b 4/4✓ | reds now green | full-file regression + gates |
| 2026-07-05 | 210b completeness sweep | (grep every group-message status predicate) | 2 gaps found+RED-first fixed: `_canReconcileOutgoingSelfEchoStatus` (handle_incoming_group_message_use_case.dart) now reconciles `queued_offline` on self echo (DE-005/210b test); migration pending-work classifiers `_isGroupMessageRetryStatus`/`_isGroupInboxRetryStatus` now include `queued_offline` (builder test pin; not yet wired into live Move — contract fix). `dbLoadRetryableOutgoingGroupMessages` deliberately NOT extended (repush lane owns live reconnect; double-drive avoided) | echo 69✓ migration 8✓ | gates |
| 2026-07-05 | 210b gates | scripts/run_test_gates.sh (GROUP_TESTS += retry_failed_group_inbox_stores_use_case_test) | `groups` gate 1131✓ (was 1118); wired 178✓ use_case 144✓ repo 50✓ repush 16✓ share 10✓; flutter analyze: 0 NEW on touched files | gate green | adversarial review + commit |
| 2026-07-05 | 210b adversarial review | (read-only workflow `wf_be0f1253-4ba`, 3 dimensions → per-finding refuters; 14 agents) | 10 confirmed (2 dup): **F1 major** sweep runs BEFORE repush in every live wiring (retrier :563→:593, resume 3d→8g, pause) and flipped ALL queued_offline→'failed' → repush lane dead + dishonest red bubble on pause/resume; **F2 major** feed `_sendGroupComposerReply` treated queuedOffline as failure → false red + duplicate mint on retry (no messageId reuse); **F3 major** retry lane STILL_FAILED mislabel + backoff no-op on conversion; minors: upload-retry mislabel, wired settled-row regress guard, staging-dir leak, share arms unpinned, stale interface doc | all real | fix round |
| 2026-07-05 | 210b review fixes (RED-first where lane-testable) | group_messages_db_helpers.dart (sweep transitions queued_offline ONLY when `inbox_retry_payload IS NULL`, both branches), feed_wired.dart (queuedOffline accepted), retry_failed_group_messages_use_case.dart (QUEUED_OFFLINE conversion branch, retried:true, no backoff), retry_incomplete_group_uploads_use_case.dart (queuedOffline = completed upload work), group_conversation_wired.dart (settled-row guard in `_markOutgoingMessageQueuedOffline`; staging-dir cleanup in both queuedOffline branches), group_message_repository.dart (doc) | RED: sweep recovered Expected 1 Actual 2; retry count Expected 1 Actual 0 → both GREEN post-fix; share pin GREEN (locks arms) | feed composer queuedOffline lane has NO widget test (no group-composer harness exists in feed_wired_test — accepted residual debt) | full regression + commit |

## Source Of Truth
- Spec / intent: inline below (user bug report + confirmed product decisions)
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose)
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh` (host-only plan; no sim rows)
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (210 = next free after 205–209)

## Session Classification
implementation-ready

## Exact Problem Statement
In a **group** chat, when the user sends a message with **no internet**, the message is correctly persisted and later auto-sends when connectivity returns. But two things are wrong versus the **1:1** chat experience:

1. **No "no internet" snackbar.** The group send path never reads any connectivity signal and never surfaces the informational snackbar that 1:1 shows. Confirmed: `lib/features/groups/presentation/screens/group_conversation_wired.dart` reads `p2pService.currentState` exactly once (line 319, only for `.peerId`); `relayReady` has **zero** occurrences in the file. The failure branches either write a terminal `send_failed` row (no snackbar, by design comment at ~2197) or silently call `_restoreComposerSnapshot` whose `showSnackBar` param defaults `false` and is never passed `true` by any send caller.
2. **A single delivery tick appears immediately, even though the message never left the device.** The optimistic bubble is inserted with `status: 'sending'` (line 1972-1983 text, 3845-3856 voice) and shown *before* the awaited `sendGroupMessage()` resolves. The shared `LetterCard` legacy path maps `'sending'`/`'pending'`/`'sent'` all to a single `Icons.done_rounded` tick (`letter_card.dart` `_statusIcon` 1059-1079); the group screen never sets `transportStatusGlyph`, so it uses that legacy path.

**What must improve:**
- Offline group send shows the same informational snackbar as 1:1 — copy **"Will send when you're back online"**, `Icons.wifi_off_rounded`, blueGrey/slate floating (not error-red).
- While the message is queued offline, a **clock** (pending) glyph shows next to it — **not** a tick.
- When the message **actually sends** (connectivity returns and it settles to a genuine sent status), the single tick appears, replacing the clock.
- The composer is **not** restored to a failed/Retry state for a purely-offline send (message stays queued, self-healing).

**What must stay unchanged (→ preserved-green sentinels):**
- **1:1 chat behavior** — out of scope entirely (1:1 intentionally shows a single "sent" tick offline via a `'failed'→'sent'` override; leave it).
- **Online success** — a group send with relay reachable shows a tick, no snackbar (current behavior).
- **Online in-flight `'pending'`** (in-doubt / inbox-unconfirmed) — still a single tick (the `'pending'` value stays a tick; we do **not** touch it).
- **Terminal group-lifecycle failures** (`groupNotFound` / `groupDissolved` / `unauthorized`) — still `send_failed` + read-only composer + error glyph, no offline snackbar.
- **Re-send when connectivity returns** — the message must still auto-send (currently works via app-resume recovery); the new status must not strand it.

## Root Cause (verify → refute confirmed)
Both gaps SURVIVED a 3-agent adversarial refute pass (all claims `SURVIVES`, no pre-existing offline handling on the group send path).

- **GAP 1 (no snackbar):** `group_conversation_wired.dart` `_onSend` (1903-2238) and `_onRecordStop` voice path (3782-4106) have no connectivity read and no offline snackbar. `_restoreComposerSnapshot` (2553-2603) / `_markFailedTextMessageWithoutComposerRestore` (2528-2551) default `showSnackBar:false`; callers (2040, 2116, 2222, 2230) never pass it true. `successNoPeers` (relay-inbox custody, i.e. **online** with offline recipients) is handled identically to `success` (2163-2193) → status `'sent'`, correctly, and is **not** the sender-offline case.
- **GAP 2 (premature tick):** optimistic rows hardcode `status:'sending'`; `group_conversation_screen.dart` builds `LetterCard` without `transportStatusGlyph` (defaults `false`, `letter_card.dart:114/152`), so `_resolvedStatusIcon` (1131-1151) short-circuits at line 1132 to `_statusIcon`, where `'sending'` falls through to `Icons.done_rounded` (1078). No clock glyph exists for any in-flight group state (the `'184' clock→tick` change deliberately removed it for `'sending'`/`'pending'`).
- **Status-model gap:** `GroupMessage.status` is a plain String (`group_message.dart:44`, default `'sent'` :98, only named const `statusSendFailed='send_failed'` :49). `'pending'` is **overloaded** (online in-doubt AND inbox-unconfirmed) and is written by the use case at multiple points — so it cannot be repurposed as the offline-queued glyph without breaking the online in-doubt tick. There is **no** distinct offline-queued value today.
- **1:1 reference (mirror the snackbar, NOT the tick override):** `conversation_wired.dart:2514` `senderOffline = !p2pService.currentState.relayReady`; hardcoded const `senderOfflineCopy = "Will send when you're back online"` at 2585; snackbar built 2651-2658 with `Icons.wifi_off_rounded` (2634-2635), blueGrey[700] (2610-2612), floating. **The copy is a hardcoded const, NOT an l10n key.**
- **Re-send seam:** group re-send runs on **app-resume** (`handle_app_resumed.dart:471` → `recoverStuckSendingGroupMessages` → `groupMsgRepo.recoverStuckSendingMessages(olderThan:)` → injected `dbRecoverStuckSendingGroupMessagesFn` wired at `main.dart:1498`; the real SQL matches `status='sending'`, analogous to the 1:1 helper `messages_db_helpers.dart:764/906`). There is **no** foreground connectivity-restore re-drive for groups (unlike 1:1's `pending_message_retrier`). ⇒ a new `'queued_offline'` status **must** be added to that recovery predicate or the queued message is stranded.

Refuted / do-NOT-re-introduce:
- "Maybe an offline clock/queued affordance already exists on the group path" — **REFUTED**; every `offline`/`queued` match in `lib/features/groups/` is receive-side inbox convergence (drain, key-repair), not an outgoing-send affordance. The only send-side single-tick "offline peer rests here" note is `letter_card.dart:1141`, gated behind `transportStatusGlyph` (1:1 ONLY), never reached by group.
- "Mirror 1:1 exactly (single tick offline)" — **deliberately NOT chosen.** Product decision is the stricter clock-not-tick for group; 1:1 stays as-is (see Scope).

## Real Scope
**In scope:**
1. New `GroupMessage.statusQueuedOffline = 'queued_offline'` constant.
2. `LetterCard` legacy `_statusIcon` / `_statusColor` / `_resolvedStatusSemantic`: `'queued_offline'` → `Icons.schedule_rounded` (clock), muted tone, "waiting to send" semantics. (Legacy path only; `transportStatusGlyph==true` 1:1 branch untouched.)
3. `group_conversation_wired.dart` — **text/image** path (`_onSend`) and **voice** path (`_onRecordStop`): (a) optimistic insert uses `'queued_offline'` when `!relayReady`; (b) post-await, on a non-terminal non-success result while `!relayReady`, persist `'queued_offline'`, do **not** restore composer, show the offline snackbar.
4. New `group_conversation_wired.dart` snackbar helper mirroring 1:1 (wifi-off icon + blueGrey[700] + "Will send when you're back online", floating).
5. Extend the group stuck-sending recovery SQL (`dbRecoverStuckSendingGroupMessagesFn`, wired `main.dart:1498`; group DB helper) so `'queued_offline'` rows are re-driven → the existing retry pipeline re-sends them → they settle to `'sent'` (tick). While still offline, a re-attempt keeps them `'queued_offline'` (clock persists), never terminal `'failed'`.
6. Flip the **shared** group widget-test `setUp` `p2pService` default to an **online** `NodeState` (preservation — see Root Cause note that the current default `FakeP2PService()` is `relayReady==false`).

**Out of scope (owning work):**
- 1:1 chat (any change) — owned by the 185/192 offline-truthfulness family; explicitly frozen here.
- 192-style **online-glitch** group snackbar ("Delivery delayed — retrying automatically") — a separate reliability item; online transient errors keep today's silent `'failed'` behavior.
- **Foreground** connectivity-restore group re-drive (a group equivalent of `pending_message_retrier`) — re-send timing stays app-resume-based as today.
- Localizing the offline copy into `app_*.arb` — mirrors 1:1's hardcoded const; l10n-debt for **both** paths is a follow-up (see Accepted Differences).

## Files To Inspect Next
Production (entry/use-case, models, repos, helpers):
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` — `_onSend` (1903-2238), optimistic insert (1972-1983), awaited send (2143-2161), failure branches (2194-2223), composer-restore helpers (2528-2603), `_showFloatingSnackBar` (2637-2646), voice `_onRecordStop` (3782-4106; optimistic 3845-3856, send+failure 4020-4097).
- `lib/features/conversation/presentation/widgets/letter_card.dart` — `_statusIcon` (1059-1079), `_resolvedStatusIcon` gate (1131-1132), `_statusColor` (1081-1103), `_resolvedStatusSemantic`, render blocks (604-614 footer, 665-675 inline meta — the inline one renders group text bubbles).
- `lib/features/groups/presentation/screens/group_conversation_screen.dart` — `LetterCard` build (675-719), `status:` arg (698).
- `lib/features/groups/domain/models/group_message.dart` — status field (44), consts (49), default (98).
- `lib/features/p2p/domain/models/node_state.dart` — `relayReady` (150-156).
- `lib/core/database/helpers/` group DB helper backing `dbRecoverStuckSendingGroupMessagesFn` (wired `main.dart:1498`; find the group analog of `messages_db_helpers.dart:764/906` `WHERE status='sending'`) + `group_message_repository_impl.dart:272`.
- `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart` (24) + retry-failed pipeline it feeds.

Direct tests + integration tests:
- `test/features/conversation/presentation/widgets/letter_card_test.dart` (glyph mapping; buildTestWidget 16-84; `find.byIcon(IconData)` pattern; existing `'sending'`/`'pending'`→done_rounded at 219-233/316-337).
- `test/features/groups/presentation/group_conversation_wired_test.dart` (setUp 948-976, buildWidget 984-1050, `p2pService` 963/1028, FakeBridge `group:publish` 957-961; group('GroupConversationWired') 937).
- `test/features/groups/presentation/group_conversation_screen_test.dart` (buildTestWidget injects `messages` with per-message `status:` — durability/reconstruction seam).
- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart` + `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart` + `test/features/groups/integration/group_resume_recovery_test.dart` (recovery predicate; real-DB).
- `test/features/conversation/presentation/screens/conversation_wired_offline_send_ux_test.dart` (1:1 template: `find.text("Will send when you're back online")` 797, `backgroundColor==Colors.blueGrey[700]` 801-803, `find.byIcon(Icons.wifi_off_rounded)` descendant of SnackBar 806-812).

Dependency-only context:
- `test/core/services/fake_p2p_service.dart` — `currentState` (111-112), ctor `initialState` (91-106), `emitState` (121-124). `NodeState.stopped` → relayReady false; `const NodeState(isStarted:true, peerId:'me', relayState:'online')` → relayReady true.

## Existing Tests Covering This Area
- `letter_card_test.dart` — covers the shared status-glyph map (EXISTS; passes). No `'queued_offline'` case (MISSING).
- `group_conversation_wired_test.dart` — 168-test group send suite (EXISTS; passes). **Zero** relayReady / offline / wifi_off / snackbar assertions (MISSING — the whole 185/192 family is absent for group).
- `group_conversation_screen_test.dart` — dumb-screen render incl. per-message status (EXISTS; passes). No `'queued_offline'` reconstruction case (MISSING).
- `group_message_repository_impl_test.dart` / `recover_stuck_sending_group_messages_use_case_test.dart` / `group_resume_recovery_test.dart` — recovery of stuck `'sending'` (EXISTS; passes). No `'queued_offline'` inclusion case (MISSING).
- `conversation_wired_offline_send_ux_test.dart` — the 1:1 offline template (EXISTS; passes) — **not** group; reference only.

Missing coverage gaps: group offline snackbar; group offline clock-not-tick; group offline composer-not-restored; `'queued_offline'`→clock render + reconstruction; recovery includes `'queued_offline'`; clock→tick transition; voice-path parity; online/terminal guards.

Already in curated family arrays?: `run_test_gates.sh` — `letter_card_test.dart` in **ONE_TO_ONE_TESTS:73 + GROUP_TESTS:224**; `group_conversation_screen_test.dart` **GROUP_TESTS:225**; `group_conversation_wired_test.dart` **GROUP_TESTS:226**. Verify (grep) whether `group_message_repository_impl_test.dart` / `recover_stuck_sending_group_messages_use_case_test.dart` are in `GROUP_TESTS`; if absent, append (they still auto-glob into `feature-host-all`).

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

1. `test/features/conversation/presentation/widgets/letter_card_test.dart`::`queued_offline renders a clock (schedule) glyph, not a tick`
   - Tier: **widget**
   - Shape/setup: `buildTestWidget(status: 'queued_offline', isIncoming: false)`; pump.
   - RED on HEAD because: `'queued_offline'` is unknown to `_statusIcon` → falls through to `Icons.done_rounded`; `find.byIcon(Icons.schedule_rounded)` finds nothing.
   - GREEN after fix asserts: `find.byIcon(Icons.schedule_rounded) findsOneWidget`; `find.byIcon(Icons.done_rounded) findsNothing`; `find.byIcon(Icons.error_outline_rounded) findsNothing`; `find.byIcon(Icons.done_all_rounded) findsNothing`.
   - Mutation that re-reds: revert the `if (status == 'queued_offline') return Icons.schedule_rounded;` branch → red.

2. `test/features/conversation/presentation/widgets/letter_card_test.dart`::`pending and sending still render a single tick (guard — unchanged)`
   - Tier: **widget** (may already exist at 219-233/316-337 — reuse/extend as a preservation sentinel)
   - Shape/setup: status `'sending'` then `'pending'`.
   - RED on HEAD because: N/A — GREEN on HEAD; this is a **guard** that the `'queued_offline'` addition doesn't broaden the clock.
   - GREEN after fix asserts: `'sending'`→`done_rounded` findsOneWidget + `schedule_rounded` findsNothing; `'pending'`→`done_rounded` findsOneWidget + `schedule_rounded` findsNothing.
   - Mutation that re-reds: if the fix mistakenly maps `'sending'`/`'pending'`→`schedule_rounded` → red.
   - Distinct-event discriminator: assert `schedule_rounded` **AND NOT** for `'pending'`/`'sending'`; assert `schedule_rounded` **only** for `'queued_offline'`.

3. `test/features/groups/presentation/group_conversation_wired_test.dart`::`offline text send shows wifi-off snackbar + clock, no tick, no Retry`
   - Tier: **widget (wired)**
   - Shape/setup: build with `p2pService = FakeP2PService(initialState: const NodeState(isStarted:true, peerId:'me'))` (relayReady **false**); FakeBridge `group:publish` → failure (`{'ok': false, ...}`) so the use case returns `error`. Enter text, tap send, `pumpFrames`.
   - RED on HEAD because: no offline branch — bubble shows `Icons.done_rounded`; `find.text("Will send when you're back online")` finds nothing; composer is restored (text refilled) via `_restoreComposerSnapshot`.
   - GREEN after fix asserts: `find.text("Will send when you're back online") findsOneWidget`; `find.descendant(of: find.byType(SnackBar), matching: find.byIcon(Icons.wifi_off_rounded)) findsOneWidget`; snackbar `backgroundColor == Colors.blueGrey[700]`; bubble `find.byIcon(Icons.schedule_rounded) findsOneWidget` + `find.byIcon(Icons.done_rounded) findsNothing` + `find.byIcon(Icons.error_outline_rounded) findsNothing`; composer TextField empty (not restored); no Retry affordance.
   - Mutation that re-reds: revert the `!relayReady` offline branch in `_onSend` → red.

4. `test/features/groups/presentation/group_conversation_wired_test.dart`::`optimistic offline bubble shows clock immediately (no tick flash)`
   - Tier: **widget (wired)**
   - Shape/setup: relayReady false; tap send; `pump()` **one frame** (before the awaited send resolves — use a gated/slow FakeBridge response or pump exactly one frame).
   - RED on HEAD because: optimistic status is hardcoded `'sending'` → `done_rounded` shows on the first frame.
   - GREEN after fix asserts: on the first post-tap frame `find.byIcon(Icons.schedule_rounded) findsOneWidget` and `find.byIcon(Icons.done_rounded) findsNothing`.
   - Mutation that re-reds: revert the optimistic-insert `relayReady ? 'sending' : statusQueuedOffline` → red.

5. `test/features/groups/presentation/group_conversation_wired_test.dart`::`voice/audio offline send shows wifi-off snackbar + clock (path parity)`
   - Tier: **widget (wired)**
   - Shape/setup: relayReady false; drive the voice send path (`_onRecordStop`) with FakeBridge failure.
   - RED on HEAD because: voice path is a separate copy with no connectivity read; bubble `done_rounded`, no snackbar.
   - GREEN after fix asserts: same as #3 for the voice message row.
   - Mutation that re-reds: revert the voice-path offline branch → red.

6. `test/features/groups/presentation/group_conversation_wired_test.dart`::`online success shows tick and NO offline snackbar (guard)`
   - Tier: **widget (wired)**
   - Shape/setup: relayReady **true** (online NodeState); FakeBridge `group:publish` → ok.
   - RED on HEAD because: N/A — GREEN on HEAD; guards that the offline branch does not fire when online.
   - GREEN after fix asserts: bubble `find.byIcon(Icons.done_rounded) findsOneWidget`; `find.byIcon(Icons.schedule_rounded) findsNothing`; `find.text("Will send when you're back online") findsNothing`.
   - Mutation that re-reds: if the offline branch keys on the wrong condition (fires while online) → red.

7. `test/features/groups/presentation/group_conversation_wired_test.dart`::`terminal group failure while offline still shows error + read-only, no offline snackbar (ordering guard)`
   - Tier: **widget (wired)**
   - Shape/setup: relayReady false; use case returns a terminal result (`groupDissolved`/`unauthorized`).
   - RED on HEAD because: N/A — GREEN on HEAD; guards branch ordering (terminal checks precede the offline branch).
   - GREEN after fix asserts: bubble `find.byIcon(Icons.error_outline_rounded) findsOneWidget`; `find.byIcon(Icons.schedule_rounded) findsNothing`; read-only banner present; `find.text("Will send when you're back online") findsNothing`.
   - Mutation that re-reds: reorder the offline branch before the terminal checks → red.
   - Distinct-event discriminator: assert **error glyph** AND NOT **clock** AND NOT **offline snackbar** for the terminal-offline case.

8. `test/features/groups/presentation/group_conversation_screen_test.dart`::`a persisted queued_offline message reconstructs a clock on remount (durability)`
   - Tier: **widget (screen)**
   - Shape/setup: `buildTestWidget(messages: [GroupMessage(..., status: 'queued_offline', isIncoming:false)])`; mount fresh.
   - RED on HEAD because: `'queued_offline'`→`done_rounded`; asserting a clock fails.
   - GREEN after fix asserts: `find.byIcon(Icons.schedule_rounded) findsOneWidget` (derived UI reconstructs purely from the persisted status).
   - Mutation that re-reds: revert the `_statusIcon` clock branch → red.

9. `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`::`recoverStuckSendingMessages re-drives queued_offline rows`
   - Tier: **integration / repo-host (real SQLCipher)** — `sqfliteFfiInit()` + `databaseFactoryFfi.openDatabase(inMemoryDatabasePath)` with the group-messages migration(s) in `setUp`.
   - Shape/setup: insert an outgoing row `status='queued_offline'` (and a control `status='sent'` row); call `recoverStuckSendingMessages(olderThan:)`.
   - RED on HEAD because: the DB `WHERE` matches only `status='sending'` → the `queued_offline` row is untouched → recovered-count / row-status assertion fails.
   - GREEN after fix asserts: the `queued_offline` row is picked up (transitioned into the retry lane); the `'sent'` control row is untouched; run-twice is idempotent (no double count).
   - Mutation that re-reds: revert the `WHERE status IN ('sending','queued_offline')` extension → red.
   - Distinct-event discriminator: assert the `queued_offline` row changed AND the `'sent'` control row did NOT.

10. `test/features/groups/presentation/group_conversation_wired_test.dart`::`queued_offline settles to a tick when the message actually sends (clock→tick transition)`
    - Tier: **widget (wired)**
    - Shape/setup: reach the offline clock state (as #3); then simulate the re-send completing — push an updated `GroupMessage(status:'sent')` for that id via the test's `messageStreamController` (the screen's `FakeGroupMessageListener` stream), optionally after `p2pService.emitState(onlineState)`; `pumpFrames`.
    - RED on HEAD because: there is no `'queued_offline'` state to transition from (feature absent); once the fix exists, this asserts the FULL post-transition state.
    - GREEN after fix asserts: bubble `find.byIcon(Icons.done_rounded) findsOneWidget`; `find.byIcon(Icons.schedule_rounded) findsNothing`; no error glyph; composer still clear; screen not read-only; exactly one bubble for that id (no duplicate).
    - Mutation that re-reds: if the clock glyph is not keyed on the same status the stream update overwrites, the transition fails → red.

## Test Coverage Matrix  (zero empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| Clock glyph for queued_offline | UI render (pure status→icon) | widget | letter_card_test.dart::`queued_offline renders a clock…` | unknown status → done_rounded | revert `_statusIcon` clock branch | `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart` | AUTO (glob) + curated ONE_TO_ONE:73 / GROUP:224 (no new reg) |
| pending/sending stay a tick | UI guard (no broadening) | widget | letter_card_test.dart::`pending and sending still render a single tick…` | GREEN on HEAD (guard) | map sending/pending→schedule → red | same as above | AUTO + curated (no new reg) |
| Offline text send: snackbar+clock+no-restore | wired UI + connectivity read | widget | group_conversation_wired_test.dart::`offline text send shows wifi-off snackbar + clock…` | no offline branch → tick, no snackbar | revert `_onSend` offline branch | `./scripts/run_test_gates.sh groups` | AUTO + curated GROUP:226 (add tests to existing file; no new reg) |
| No tick flash | optimistic insert timing | widget | group_conversation_wired_test.dart::`optimistic offline bubble shows clock immediately…` | optimistic hardcodes 'sending'→tick | revert optimistic ternary | `./scripts/run_test_gates.sh groups` | AUTO + curated GROUP:226 |
| Voice-path parity | wired UI (2nd send path) | widget | group_conversation_wired_test.dart::`voice/audio offline send…` | voice path has no offline read | revert voice offline branch | `./scripts/run_test_gates.sh groups` | AUTO + curated GROUP:226 |
| Online success unchanged | preservation guard | widget | group_conversation_wired_test.dart::`online success shows tick and NO offline snackbar` | GREEN on HEAD (guard) | offline branch fires while online → red | `./scripts/run_test_gates.sh groups` | AUTO + curated GROUP:226 |
| Terminal failure unchanged | ordering guard | widget | group_conversation_wired_test.dart::`terminal group failure while offline…` | GREEN on HEAD (guard) | reorder offline before terminal → red | `./scripts/run_test_gates.sh groups` | AUTO + curated GROUP:226 |
| Durability / reconstruction | derived-state reopen | widget | group_conversation_screen_test.dart::`…reconstructs a clock on remount` | 'queued_offline'→done_rounded | revert `_statusIcon` clock branch | `./scripts/run_test_gates.sh groups` | AUTO + curated GROUP:225 |
| Re-send not stranded | repo + DB state | integration (real SQLCipher) | group_message_repository_impl_test.dart::`recoverStuckSendingMessages re-drives queued_offline rows` | WHERE matches only 'sending' | revert `IN ('sending','queued_offline')` | `flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart` | AUTO (glob); verify/append to GROUP_TESTS |
| Clock→tick transition | new state transition (full post-state) | widget | group_conversation_wired_test.dart::`queued_offline settles to a tick…` | feature absent | glyph not keyed to updated status → red | `./scripts/run_test_gates.sh groups` | AUTO + curated GROUP:226 |

## Blind-Spot Sweep  (evergreen classes — row added OR justified N/A)
- **Lifecycle / derived-state durability:** **Covered — TC #8.** The clock is derived purely from the persisted `'queued_offline'` String; #8 remounts the screen from a seeded persisted row and asserts the clock reconstructs (no in-memory-only latch). #10 asserts the transition target. (No DB migration — status is an existing opaque TEXT column; the new value round-trips with no serialization logic to break.)
- **Sibling-surface consistency:** **Covered — TC #3 (text/image, shared `_onSend`) + #5 (voice `_onRecordStop`).** These are the only two send surfaces that create an outgoing message row with a delivery glyph. Reactions, quotes, edits, and attach-sheet actions do not create a ticked message and are **N/A** (deliberate — they have no delivery-tick surface). Retry affordance: an offline row is queued (not `'failed'`) so no Retry is offered — asserted absent in #3.
- **Destructive-action side-effects:** **N/A** — no delete/cleanup/cancel path is added or changed. The offline branch deliberately does **not** restore the composer (message stays durably queued); #3 asserts the composer is empty (nothing lost, nothing spuriously restored).
- **Invariant re-verification under new transitions:** **Covered — TC #10.** The new clock→tick transition asserts the FULL post-transition state (tick present, clock gone, no error glyph, composer clear, not read-only, exactly one bubble). Guards #6/#7 ensure the new offline branch does not perturb the online-success and terminal-failure invariants.

## Invariants (locked by tests)
- **INV-1:** A group message sent while `!relayReady` renders a clock (`schedule_rounded`), never `done_rounded` or `error_outline_rounded`, and the composer is not restored to failed. → TC #3, #5.
- **INV-2:** The offline snackbar exactly matches 1:1 — text "Will send when you're back online", `wifi_off_rounded`, blueGrey[700], floating. → TC #3.
- **INV-3:** `'pending'` and `'sending'` still render a single tick (online in-doubt / 1:1 legacy unchanged); `transportStatusGlyph==true` (1:1) branch untouched. → TC #2 + existing letter_card sentinels.
- **INV-4:** A `'queued_offline'` row is re-driven by recovery and is never stranded; on success it settles to `'sent'` (tick). → TC #9, #10.
- **INV-5:** Terminal group-lifecycle failures still show error + read-only, no offline snackbar, even while offline. → TC #7.
- **INV-6:** `'queued_offline'` persists and the clock reconstructs on remount. → TC #8.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. **Snapshot** `git status --short` (dirty-tree baseline; the tree already has unrelated modified files — do not revert them). Record the current `groups` gate counts and the `group_conversation_wired_test.dart` test count (~168) as the preservation baseline.
2. **Add all RED tests (#1–#10)** first. Run focused commands; confirm each fails for its documented reason (guards #2/#6/#7 are GREEN-on-HEAD sentinels — note them as such).
3. **Model:** add `static const String statusQueuedOffline = 'queued_offline';` to `GroupMessage` (`group_message.dart`), documented alongside `statusSendFailed`.
4. **Glyph (`letter_card.dart`):** in `_statusIcon`, add `if (status == 'queued_offline') return Icons.schedule_rounded;` **before** the `done_rounded` fallthrough; add the matching `_statusColor` (muted/neutral) and `_resolvedStatusSemantic` ("Message status: waiting to send") cases. Do **not** touch `_resolvedStatusIcon`'s `transportStatusGlyph==true` branch.
5. **Snackbar helper (`group_conversation_wired.dart`):** add `_showOfflineQueuedSnackBar()` building the 1:1 content — `Row` of `Icon(Icons.wifi_off_rounded)` + `Text("Will send when you're back online")`, `backgroundColor: Colors.blueGrey[700]`, `behavior: floating` (mirror `conversation_wired.dart:2610-2658`; keep the copy a hardcoded const to match 1:1). Reuse/extend `_showFloatingSnackBar` only if it cleanly accepts a leading icon.
6. **Text/image path (`_onSend`):** (a) at optimistic insert (1972-1983), set status `widget.p2pService.currentState.relayReady ? 'sending' : GroupMessage.statusQueuedOffline`; (b) in the result handler, **after** the terminal `SendGroupMessageResult` branches (keep their order), add: `else if (!widget.p2pService.currentState.relayReady) { persist statusQueuedOffline; update the in-memory row; _showOfflineQueuedSnackBar(); /* do NOT restore composer */ }`; the existing online-error `_restoreComposerSnapshot` path stays for the `relayReady==true` case.
7. **Voice path (`_onRecordStop`):** mirror step 6 at the voice optimistic insert (3845-3856) and its result handler (4020-4097).
8. **Recovery SQL:** extend the group stuck-sending DB function backing `dbRecoverStuckSendingGroupMessagesFn` (locate via `main.dart:1498`; group analog of `messages_db_helpers.dart:764/906`) so its predicate is `status IN ('sending','queued_offline')` (queued_offline re-driven regardless of age; keep the `'sending'` age cutoff). Ensure a still-offline re-attempt returns the row to `'queued_offline'` (not terminal `'failed'`) so the clock persists across resume cycles.
   - Stop-if: extending the predicate can't be done without also re-driving `'queued_offline'` through the retry-failed pipeline → trace `retryFailedGroupMessages` and include `'queued_offline'` there; if the retry pipeline is 1:1-shared or structurally resists this, **replan** (do not hack a parallel re-sender).
9. **Preservation:** flip the shared `group_conversation_wired_test.dart` `setUp` `p2pService` default to an online `NodeState` (`const NodeState(isStarted:true, peerId:'me', relayState:'online')`) so the ~168 existing sends stay online (tick, unchanged). New offline tests construct their own offline `FakeP2PService`.
10. **Harness registration:** grep `GROUP_TESTS` for `group_message_repository_impl_test.dart` / `recover_stuck_sending_group_messages_use_case_test.dart`; append any missing one (they still auto-glob into `feature-host-all`). letter_card / screen / wired files already curated — no new registration for new test methods in them.
11. Rerun **direct → preservation → named gates** (Acceptance Gates below). Confirm each RED is now GREEN and each guard/sentinel stayed GREEN.

## Risks And Edge Cases
- **Preservation landmine (default offline test state):** the current shared `FakeP2PService()` is `relayReady==false`; adding a `!relayReady` branch would flip existing sends to offline. → pinned by step 9 + the full `groups` gate staying at baseline count.
- **Over-broadening the clock:** mapping `'sending'`/`'pending'` to the clock would break online in-doubt + 1:1. → pinned by TC #2.
- **Branch ordering:** the offline branch must sit **after** terminal `SendGroupMessageResult` handling. → pinned by TC #7.
- **Stranded queued message (re-send regression):** the new status must be in the recovery predicate. → pinned by TC #9; transition proven by TC #10.
- **Resume while still offline:** a re-attempt must re-queue (`'queued_offline'`, clock) rather than terminalize to `'failed'` (error glyph). → step 8 rule; if the retry pipeline can't honor this cleanly, it is called out as an Accepted Difference below rather than silently regressing.
- **Voice vs text drift:** two separate code paths must both get the branch. → TC #3 (text) + #5 (voice).

## Device/Relay Proof Profile
**host-only for closure.** Every behavior is deterministic at host tier: the glyph is a pure `status→IconData` map (widget), the snackbar + branch logic is wired-widget with `FakeP2PService`/`FakeBridge`, and the recovery predicate is real-SQLCipher repo state. No OS boundary, no real ML-KEM convergence, no cross-device, no real relay is exercised — so no `integration_test/` simulator scenario or device-proof is required for closure.
- **No PROD-CRITICAL wire/transport leg in this change.** The transport / send-over-relay path is **unchanged** — this plan only alters local UI state (glyph + snackbar) and a local recovery predicate. The nearest-to-critical path is "a queued-offline row is re-driven, not stranded," which is proven for real at repo tier by TC #9 (real SQLCipher) + the transition at TC #10. Do NOT treat the widget guards alone as sufficient for that leg — #9 is its anchor.
- Optional manual confidence (not a gate): on a real device, enable airplane mode, send a group message → expect the wifi-off snackbar + clock; restore connectivity + background/foreground → expect the tick. (No feature flag involved.)
- Deferred device/foreground-retrier work → future session (see Accepted Differences).

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# Dirty-tree baseline (do NOT revert pre-existing unrelated changes)
git status --short

# RED (before production edits) — must FAIL for the documented reason
flutter test test/features/conversation/presentation/widgets/letter_card_test.dart --plain-name 'queued_offline renders a clock'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'offline text send shows wifi-off snackbar'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'voice/audio offline send'
flutter test test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'reconstructs a clock on remount'
flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name 're-drives queued_offline rows'

# Direct GREEN (after fix)
flutter test test/features/conversation/presentation/widgets/letter_card_test.dart
flutter test test/features/groups/presentation/group_conversation_wired_test.dart      # expect: baseline(≈168)+5 pass
flutter test test/features/groups/presentation/group_conversation_screen_test.dart
flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart

# Preservation sentinels (must stay green) + named gate for the touched subsystem
./scripts/run_test_gates.sh groups            # expect: baseline count + new group tests, 0 fail
./scripts/run_test_gates.sh 1to1              # expect: unchanged (1:1 untouched) — proves no 1:1 regression
./scripts/run_host_test_gates.sh feature-host-all   # expect: all green incl. auto-globbed repo/use-case tests

# (No DB migration — status is an existing TEXT column; no test/core/database/migrations/0NN_* added.)

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- **Expected RED:** TC #1, #3, #4, #5, #8, #9, #10 before the fix (documented reasons above). Guards #2, #6, #7 are GREEN-on-HEAD sentinels (not expected-RED).
- **Pre-existing dirty:** the working tree already has unrelated modified files (l10n, graphify-arch, orbit/group_list wired, info.plist, etc.) — leave them; they are not part of this change.
- **Environment blocker (NOT product):** none — host-only plan; no simulator/device required.
- **Scope drift (BLOCKING):** any failure in the `1to1` gate, or any change to `conversation_wired.dart` / 1:1 tests, is a scope violation → stop and revert.

## Done Criteria
- [ ] RED added first (#1,#3,#4,#5,#8,#9,#10), failed for the expected reason; guards (#2,#6,#7) green on HEAD.
- [ ] Mutation-verified (each fix has a re-red revert per the matrix).
- [ ] Direct GREEN + preservation sentinels (`groups` at baseline+new, `1to1` unchanged) + `feature-host-all` pass.
- [ ] No DB migration needed (opaque TEXT column) — confirmed; recovery-predicate change covered by a real-SQLCipher repo test.
- [ ] Host-only closure justified; no OS-boundary/multi-device/crypto/relay path faked.
- [ ] Every new test's harness-registration verified in a gate run (curated files auto; repo/use-case appended to GROUP_TESTS if missing).
- [ ] `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violations.

## Scope Guard (hard "Do not")
- Do **not** modify `conversation_wired.dart` or any 1:1 test/behavior (1:1 offline tick stays; owned by the 185/192 family).
- Do **not** touch the `transportStatusGlyph==true` branch of `LetterCard._resolvedStatusIcon`.
- Do **not** repurpose `'pending'` for the offline clock (it must stay a tick).
- Do **not** add a foreground connectivity-restore group retrier here (out of scope).
- Do **not** localize the copy in this session (mirror 1:1's hardcoded const).

## Accepted Differences / Intentionally Out Of Scope
- **Resume-while-still-offline polish:** if the retry-failed pipeline cannot cleanly re-queue a still-offline `'queued_offline'` row without a transient `'failed'`/error glyph, the message follows today's stuck-send behavior on that rare path (background the app while offline). The primary scenario (send offline → stay foreground → reconnect) is fully covered (clock→tick). Owner: a future group send-reliability session.
- **Foreground auto-resend on connectivity restore** (a group equivalent of `pending_message_retrier`): 1:1 has it, group does not; re-send timing stays app-resume-based. Owner: group transport-reliability session.
- **l10n of "Will send when you're back online"** for both 1:1 and group: mirrors 1:1's current hardcoded const; a combined l10n-debt cleanup is a follow-up.
- **192-style online-glitch group snackbar:** online transient errors keep today's silent `'failed'`; owner: the 192 family.

## Dependency Impact
- None outward. This is a self-contained group-presentation + one recovery-predicate change. The new `GroupMessage.statusQueuedOffline` constant is additive; any code that switches on status must treat unknown values as before (verified: `_statusIcon` has a `done_rounded` fallthrough; recovery now includes it explicitly).

## Reviewer Findings
<pending sufficiency review>

## Arbiter Decision
<pending>

## Final Execution Verdict
**IMPLEMENTED — host-green (2026-07-05).** All 10 RED tests added first and confirmed failing for their documented reasons (guards #2/#6/#7 green-on-HEAD); production implemented in the 6 scoped files; every RED now GREEN; preservation sentinels held (`1to1` 1486 unchanged — proves the shared `letter_card` change did not touch 1:1; `groups` 1118 incl. the 6 new wired tests + newly-registered repo test). `flutter analyze` 0 new; `git diff --check` clean. Host-only closure justified per the Device/Relay Proof Profile (pure status→glyph, wired snackbar with fakes, real-SQLCipher recovery predicate — no OS/crypto/relay boundary).

Notes for the record:
- **Reuse-whitelist addition (`send_group_message_use_case._canReuseOutgoingMessageId`):** required beyond the plan's literal scope — the media/voice paths pre-persist the optimistic row, so an offline pre-save (`queued_offline`) would otherwise mint a duplicate on the use case's id-collision resolve. Provably a no-op for all existing (non-`queued_offline`) data.
- **Branch placement:** offline branch guarded `!relayReady && message != null`, ordered AFTER terminal and BEFORE `message == null`, so terminal wins (TC #7), a durable offline row queues (TC #3/#5), and a null-row offline bail still restores the composer (unchanged).
- **Recovery:** only `dbTransitionGroupSendingToFailed` extended (byte-equivalent for existing statuses); `dbLoadStuckSendingGroupMessages` is dead code (0 callers) and `_canReconcileOutgoingSelfEchoStatus` never sees `queued_offline` (transient send-side status), so neither needed a change. Still-offline re-queue stays 'failed' (Accepted Difference).

## 210b Addendum (2026-07-05) — device failure, corrected root cause, result-contract fix

**Field result of the original 210 closure:** on a real offline device the snackbar never appeared and the bubble still settled to a tick. User-reported; root-caused via a 4-trace + adversarial-verify workflow (`wf_deb5e88a-74a`, 0/4 findings refuted).

**Corrected root cause (supersedes this plan's Root Cause §"successNoPeers … is not the sender-offline case" reasoning):**
1. A real offline group send does NOT return an error. Go `SendGroupMessageReliable` (pubsub.go) folds errors into flags: the gossipsub publish "succeeds" locally with 0 topic peers (`publishErr == nil` on an empty mesh) and only the relay-inbox custody fails (`group_inbox.go` connect), so the bridge answers `ok:true / publishSucceeded:true / inboxStored:false / topicPeerCount:0`. The use case mapped that to `SendGroupMessageResult.success` + status `'pending'` (`live_publish_without_custody`), so the wired screen took the happy branch: 'pending' (amber tick) overwrote the optimistic clock and the 210 `!relayReady` failure branch was **unreachable** for a plain offline send.
2. The 210 wired tests stubbed `{'ok':false,'errorCode':'NETWORK_DOWN'}` — an error shape that does not exist anywhere in go-mknoon. GIRD-001 (use-case suite) already pinned the realistic offline shape as (success,'pending'); the two tiers contradicted each other and both were green.
3. Secondary: `relayReady` stays stale-TRUE ~15-30s after losing internet (QUIC keepalive 15s / idle timeout 30s; no OS connectivity source is wired), so even the optimistic-insert clock gate misses a send tapped right after going offline. 1:1 is immune by design — its lane keys off the awaited result's failure class (185/192), with relayReady only picking the copy.

**210b design — key the lane off the RESULT CONTRACT, not relayReady:**
- New `SendGroupMessageResult.queuedOffline`: `publishSucceeded && !inboxStored && expectedRecipients > 0 && topicPeers <= 0` (the existing `_reliablePublishSucceededWithoutCustody` geometry). The use case persists **`'queued_offline'`** (was 'pending') with the repush payload retained and returns the new result. `BRIDGE_TIMEOUT` stays (success,'pending') — genuinely in-doubt. Live-peers-without-custody stays 'pending' (some recipients may have received the live publish).
- Wired screen (text + voice): a `queuedOffline` branch (before terminal checks; enum values are mutually exclusive) re-affirms the clock via `_markOutgoingMessageQueuedOffline` and shows `_showOfflineQueuedSnackBar()`. The 210 `!relayReady && message != null` branch remains as the fallback for outright `error` while offline.
- Snackbar copy now mirrors 1:1's 192 exactly: lane from the contract; `relayReady` only picks the copy — offline → wifi-off + "Will send when you're back online"; stale-online window → schedule-send + 'Delivery delayed — retrying automatically'.
- Self-heal: repush lane (`dbLoadGroupMessagesWithFailedInboxStore` + in-memory fake mirror) now selects `'queued_offline'` too; `retryFailedGroupInboxStores` settles it to `'sent'` on reconnect (the live-app clock→tick). The app-resume sweep (`dbTransitionGroupSendingToFailed`, unchanged from 210) remains the no-payload fallback. `queued_offline` is deliberately NOT added to the retry-message lane (`dbLoadRetryableOutgoingGroupMessages`) — the repush lane owns the live reconnect and adding both would double-drive the same row.
- Share coordinator: explicit `queuedOffline` arms (status `queued`, detail "Stored — will send when you're back online.").

**210b test locks (RED-first, all failed for the expected reason before the fix):**
- use case: GIRD-001 zero-peers re-pinned → `queuedOffline` + `'queued_offline'` (payload retained, non-failed); BRIDGE_TIMEOUT test untouched (guard).
- wired `210b` group: realistic-contract offline text (snackbar+clock+row), stale-online copy variant (192), live-peers guard (tick, no snackbar — GREEN throughout), voice parity. The old NETWORK_DOWN tests stay as the error-fallback lane locks (comment corrected).
- repo (real SQLCipher): repush selection includes `queued_offline` (+ fixture now wires the real `dbLoadGroupMessagesWithFailedInboxStore`); repush use case promotes `queued_offline` → `'sent'`.

**Adversarial review round (`wf_be0f1253-4ba`) — all confirmed findings fixed:** the recovery sweep now transitions `queued_offline` ONLY when `inbox_retry_payload IS NULL` (payload-armed rows are repush-lane-owned; the sweep precedes the repush pass in every live wiring, so the old unconditional flip made the repush self-heal dead code and showed a red bubble after pause/resume while offline); feed group-composer replies accept `queuedOffline` (was: false red + duplicate mint on manual retry); the retry-message lane logs a distinct QUEUED_OFFLINE conversion (retried, no backoff) instead of STILL_FAILED; the incomplete-uploads pass counts `queuedOffline` as completed upload work (staging dir cleaned); `_markOutgoingMessageQueuedOffline` guards against regressing an echo-settled row; both wired queuedOffline branches clean the pending_uploads staging dir; the repo interface doc matches the new predicate.

**Residual (accepted):** the first ~15-30s stale window can still flash 'sending' (tick) at optimistic insert until the send resolves (~O(seconds) offline) and the contract flips it to the clock; eliminating the flash entirely needs an OS connectivity source (out of scope, tracked as the p2p_service_impl.dart:176 follow-up). The feed group-composer queuedOffline lane is fixed but has no widget-tier lock (feed_wired_test has no group-composer harness — debt). Device-proof of the full offline→snackbar→reconnect→tick journey remains pending (host-only closure again — flagged for the next device campaign).
