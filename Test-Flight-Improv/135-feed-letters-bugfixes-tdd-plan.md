# 135 - Feed "Letters" Bug Batch (avatar photo · back affordance · open-conv placement · leave-thread model · QR crash)  (Bug)

Status: awaiting-review
Spec: free-text intent — the user's **mknoon Feed bug report** (6 items, against `FEED_SPEC.md` §1/§4/§5/§6). `FEED_SPEC.md` is the user's external redesign spec and is **not in the repo**; the bug report quotes the expected behavior per section in enough detail to serve as the spec source. These are defects in the just-shipped **134 Feed redesign** ("Letters" pending-reply inbox) — see `134-feed-redesign-pending-reply-inbox-tdd-plan.md`. Branch `new-feed` (uncommitted).

Grounding artifact (5-agent verify→refute workflow `wf_f02acbed-704`, 2026-06-20): `/private/tmp/claude-501/-Users-I560101-Project-Sat-mknoon-2-flutter-app/90fd8635-fdf2-49f9-9e00-2eba3ba433c6/tasks/wenwdbj3p.output` — every root cause below carries `file:line` evidence that survived an adversarial refute pass.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-20 | Evidence Collector | feed_screen.dart, feed_wired.dart, feed_swipe_card.dart, feed_composer.dart, letter_card_{one_to_one,group,system}.dart, feed_ring_avatar.dart, user_avatar.dart, ring_avatar.dart, feed_letter.dart, feed_item.dart, group_sender_runs.dart, feed_pending_projection.dart, feed_store.dart, qr_scanner_wired.dart, orbit_wired.dart, main.dart, mark_conversation_read_use_case.dart (+ all feed/qr tests) via 5-slice graphify→source workflow | 5 bugs CONFIRMED + 1 sub-claim (cross-cutting residue) REFUTED; bugs 2/4/5 are ONE coupled leave-thread change; no DB migration; host-closable | emit matrix + RED catalog |
| 2026-06-20 | Planner | tier-matrix.md, run_test_gates.sh (FEED_TESTS, ~25 entries), 00-INDEX (next-free 135) | all rows widget/host tier; QR row is widget-tier; host-only closure | this doc |
| 2026-06-20 | Reviewer (sufficiency) | this doc vs sufficiency-checklist.md | (pending self-check) | re-verify totality |
| | Arbiter | | | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | (cmd proving FAIL) | RED for expected reason | |
| | implementation (B1→B6) | | | scoped files only | |
| | direct GREEN | | | reds now green | |
| | preservation GREEN | | | sentinels green | |
| | named gates | | `./scripts/run_test_gates.sh feed` | gate green | |
| | QA (independent) | | | blocking: none/list | verdict |

## Source Of Truth
- Spec / intent: the bug report (inline expected-behavior per §) — `FEED_SPEC.md` is external/not-in-repo.
- Gate definitions: `scripts/run_test_gates.sh` — `FEED_TESTS` array (~25 entries, P8-rebuilt). `qr_scanner_wired_test.dart` is NOT in `FEED_TESTS` (QR family) — see §Harness registration.
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh` (no new simulator scenario — host-closable).
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (next-free **135**). **No migration** (no schema change; DB stays v92).

## Session Classification
**implementation-ready** — host-closable (widget + wiring tests). No ML-KEM/relay/multi-device/SQLCipher-migration → **no device-proof is the closure gate**. Optional on-device smoke of avatar-photo refresh + swipe feel is polish, not a gate.

---

## Exact Problem Statement

Six defects in the 134 "Letters" Feed against `FEED_SPEC.md`:

1. **Avatar never shows a friend's real / updated profile photo** (§4) — the feed letter cards render only the deterministic generated `RingAvatar` glyph; a real uploaded photo never appears and never updates live. Every user, every incoming message.
2. **No back affordance while replying** (§5/§6) — a focused thread has no tappable control to return to the Feed; the only escapes are an undiscoverable empty-area tap and the right-swipe gesture.
3. **"Open full conversation" is in the wrong place** (§1/§3-of-report) — it sits at the bottom (inside the floating composer) instead of at the top of the focused thread's message column (the "scroll up into history" position).
4. **Right-swipe-to-go-back is wrong** (§6) — a right-swipe on the focused thread currently **commits+removes** the card unconditionally; per spec it should **go back** (close the thread, card stays) when no reply was sent, and commit+remove only when replies were sent.
5. **Incoming messages vanish from the thread after sending a reply** (§1/§6) — sending a successful reply marks the conversation read, which empties the focused card's incoming bubbles; the user loses sight of what they are answering. Per spec, incoming must stay visible the whole time in-thread; send only appends; the feed card is removed (and read-marked) only on **leave-thread**.
6. **QR scan → Feed crash** (§5) — `Bad state: QRScannerWired requires feedClearedRepository before navigating to FeedWired` the moment a user scans a contact QR from Orbit and taps OK; the scan→Feed handoff never completes.

**What must improve:** real-photo avatars w/ live refresh (1); a discoverable back control (2); top-of-thread history link (3); right-swipe = go-back-or-commit (4); incoming-stays + leave-thread removal (5); a crash-free scan→Feed handoff (6).

**What must stay unchanged (→ preserved-green sentinels):**
- The 134 invariants that are still correct: pending-only projection / cleared-overlay / re-surface (`feed_pending_projection_test`), cleared-repo + migration 092 (`feed_cleared_repository_test`, `092_*_test`), focus-collapse + nav-fade + composer append-stay + never-silent retry (`feed_focus_test` TC-19/19b/21/22/30), gesture-arena + dismiss-isolation + Undo (`feed_swipe_test` TC-24/25/26a/26c/26d/33/35*/37), caught-up + reduced-motion, shared-widget survival, l10n parity.
- `UserAvatar` priority ladder + `invalidatePeer` cache-bust (`user_avatar_test`) — reuse, do not modify.
- The FTE / StartupRouter `feedClearedRepository` threading (already correct) — bug 6 only adds the **Orbit** branch.
- Conversation/posts/notification routing — untouched.

---

## Root Cause (verify → refute confirmed)

**BUG 1 — avatar drops real photo (CONFIRMED).** All three letter cards wire the photo-less glyph: `LetterCardOneToOne` (`letter_card_one_to_one.dart:45` `FeedRingAvatar(peerId: letter.peerId, size:40)`), `LetterCardGroup` per run (`letter_card_group.dart:71` size 32), `LetterCardSystem` (`letter_card_system.dart:67` size 40). `FeedRingAvatar` (`feed_ring_avatar.dart:10-27`) just returns `RingAvatar(peerId,size)` (`ring_avatar.dart:18-45`) which paints a CustomPaint glyph and accepts **no** photo. The real photo widget `UserAvatar` (`user_avatar.dart:113-167`) already implements the full ladder (bytes → file `{docs}/media/avatars/{peerId}.jpg` via `ValueListenableBuilder` → `RingAvatar` fallback → icon) AND live cache-bust (`download_profile_picture_use_case.dart:81-82` / `upload_profile_picture_use_case.dart:79-80` call `FileImage().evict()` + `UserAvatar.invalidatePeer(peerId)` → bumps `_generation`/`?v=N` → new `ValueKey` reloads `Image.file`). The feed **header** already uses `UserAvatar` (`feed_header.dart:53`); only the cards diverged. *Refute failed:* no photo-capable avatar exists in any `letter_card_*`; cache-bust is NOT missing (it's wired) — the cards simply never mount a `UserAvatar`.

**BUG 2 — no back affordance (CONFIRMED).** Focused render adds no chevron/IconButton: cards render no header (`letter_card_one_to_one.dart:42-56` is `Row(avatar, Column(bubbles))`, name header intentionally absent per 134 TC-16); `feed_screen.dart` `_buildLetterCard`/`_buildFeedItemWidget` forward only `focused:true`. The only escapes are the empty-area background tap (`feed_screen.dart:179-184` → `onClearFocus`) and the right-swipe commit. *Refute failed:* grep for `arrow_back|chevron|IconButton|Icons.close` in feed presentation → only the composer send / quote close / swipe indicator, none a back-to-feed control.

**BUG 3 — open-conv link at bottom (CONFIRMED).** The affordance (`ValueKey('feed-open-full-conversation')`, `feed_composer.dart:112-130`) lives only inside the bottom-anchored `FeedComposer` (`feed_screen.dart:303-310` positions the composer at `bottom: 12+viewInsets`; `_buildComposer` :315-350 passes `openConversationLabel`/`onOpenConversation` into it; composer Column :189 puts it above the input). Relative to the incoming bubbles (higher in the scroll), it is below them. *Refute failed:* the only render site is the composer; no top path. Existing tests assert presence-by-key only, never position.

**BUG 4 — right-swipe commits unconditionally (CONFIRMED; spec divergence).** `FeedSwipeCard.confirmDismiss` (`feed_swipe_card.dart:89-104`): `startToEnd && focused → onCommit()` with no replies-sent branch; `onCommit` → `_onSwipeCommit` (`feed_wired.dart:1879-1909`) which `_endFocusSessionForThread` + `markClearedLocally` + `markCleared(markRead:true)` + DB read-mark + store-removal. The gesture **is** reachable (arena gate `_SwipeStartEndTracker` claims at ≥6px before the host's ~12px, `feed_swipe_card.dart:144-184`; tap GestureDetector is tap-only). *Refute:* the current unconditional commit is intentionally locked by `feed_swipe_test.dart` **TC-23** (`:262-309`) — so bug 4 is a deliberate behavior change requiring a test revision, not a latent gap.

**BUG 5 — incoming vanishes on successful send (CONFIRMED).** Chain: `_sendContactComposerReply` success branch calls `markConversationRead(messageRepo, contactPeerId)` (`feed_wired.dart:1778-1782`); group twin `markAsRead(groupId)` (`:1841`) → `_refreshContactFeedItem` re-projects → `ThreadMessage.isUnread = !deleted && incoming && readAt==null` (`group_messages_into_threads.dart:77`) now false → `CardThreadFeedItem.unreadMessages` (`feed_item.dart:152-154`) EMPTY → `OneToOneLetter.fromThread` `texts = unreadMessages.map(text)` (`feed_letter.dart:32`) / `GroupLetter` `runs = groupSenderRuns(unreadMessages)` (`:60`) EMPTY → `LetterCardOneToOne` renders zero incoming bubbles; only the appended outgoing session bubble remains. *Refute:* the focus PIN (`feed_store.dart:77-101`) is NOT the culprit — it re-inserts the answered item, keeping the card mounted (just empty-of-incoming). The bug fires **only on send SUCCESS**; current tests never hit it because `FakeP2PService` defaults to a failing send (`feed_focus_test.dart:364-365`). **Read-marking already happens correctly on commit** (`_onSwipeCommit:1895-1907`, 134 REG-INV3) — so the fix is to STOP marking read on send.

**BUG 6 — QR scan crash (CONFIRMED).** 134 P5 made `feedClearedRepository` a required, non-nullable `FeedWired` dep (`feed_wired.dart:176/:218`). `QRScannerWired` holds it nullable with a throwing fallback (`qr_scanner_wired.dart:94` field, `:424-426` `feedClearedRepository ?? _missingFeedClearedRepository()`, `:580-584` `Never { throw StateError(...) }`). The real defect is upstream: **`OrbitWired` has no `feedClearedRepository` field at all** (`orbit_wired.dart` :97-142 — none) and constructs `QRScannerWired` without it (:1828-1890). Both `OrbitWired` construction sites omit it: `main.dart:3958-3998` (intro-notification path) and `feed_wired.dart:2169-2211` (embedded AppShell). Reachable on the live happy path: orbit scan → `_handleScanned` → `_handleValidContact` → `addContact` success → `_showSuccessDialog` OK → `Navigator.pushAndRemoveUntil(FeedWired(...))` (`qr_scanner_wired.dart:382-432`) → null repo → throw. *Refute:* FTE path is unaffected (`first_time_experience_wired.dart:98/:584` threads it; StartupRouter threads it). `feedClearedRepository` IS available in both Orbit parents (`main.dart:3288/:3377/:4557` MyApp; `feed_wired.dart:176`) — pure plumbing add, no new provider.

**Refuted / do-NOT-re-introduce:**
- **Cross-cutting "residue" sub-claim** (timestamps / "You replied" / per-card composer / expand toggles still showing) — **REFUTED** against current source: grep over the 3 letter cards shows no timestamp/status/"you replied"; exactly one screen-level `FeedComposer` (`feed_screen.dart:341`); the only `Expanded` are layout flex, no expand/collapse toggle. The bug report's screenshot is from a pre-134 build. Do **not** chase phantom residue (optional regression-lock only — TC-13).
- **Cache-bust/eviction is NOT missing** for bug 1 (fully wired in `UserAvatar.invalidatePeer` + the upload/download use-cases) — do not add a second eviction mechanism.
- **A captured incoming "snapshot" at focus time is NOT needed** for bug 5 — once `markConversationRead` is removed from the send path, `unreadMessages` stays populated and the pin keeps the card; a snapshot adds staleness risk. Do not build one.

---

## Real Scope

**In scope:**
- **B1:** `letter_card_one_to_one.dart` / `letter_card_group.dart` / `letter_card_system.dart` — replace `FeedRingAvatar` with `UserAvatar(peerId: …, size: …, showGlow:false, showPhotoFrame:false)` (decision G1: bare look preserved). Group uses `run.senderPeerId`. Keep `FeedRingAvatar` file (it may still be used elsewhere / as the explicit no-photo case) — verify; delete only if zero refs.
- **B2+B4+B5 (one coupled change):** a **unified leave-thread** path. (a) Add a focused-state **header** in `feed_screen.dart` (back chevron `ValueKey('feed-focused-back')` + sender identity) shown only when focused. (b) New `_leaveFocusedThread(threadId)` in `feed_wired.dart`: capture `repliesSent = _feedSessionOutgoing[focusKey]?.isNotEmpty ?? false` **before** clearing → if replied: commit (`markClearedLocally` + `markCleared(markRead:true)` + DB read-mark + remove); else: defocus only (card stays, no markCleared, no read-mark). (c) Wire back-button, right-swipe (`_onSwipeCommit` → `_leaveFocusedThread`), and tap-outside (`_onClearFocus` call site) to the SAME handler. (d) **Remove** `markConversationRead` (`feed_wired.dart:1778-1782`) and `markAsRead` (`:1841`) from the send-success paths.
- **B3:** Move the open-conv affordance to the **top** focused header (same widget as B2); remove it from `FeedComposer` (or stop passing `onOpenConversation`). Preserve the `ValueKey` + per-kind routing (`onOpenFullConversation` / `onGroupTap`).
- **B6:** Add `final FeedClearedRepository feedClearedRepository` + `required this.feedClearedRepository` to `OrbitWired`; pass it to the `QRScannerWired` construction (`orbit_wired.dart` ~:1860) and from both `OrbitWired` sites (`main.dart:3958`, `feed_wired.dart:2169`).

**Out of scope (named owner):**
- Conversation-view / posts / notification routing changes (no owner needed — untouched).
- Group sender-run avatar when `senderPeerId` is null → falls back to glyph keyed on username (cosmetic edge; **Accepted Difference**, not fixed here).
- Android system-back (`PopScope`) handling of the focused thread — there is no `PopScope` today; the explicit back chevron (B2) is the planned affordance. A system-back leave-handler is a **follow-up** (note in Dependency Impact); not required by the bug report.
- Re-authoring `feed_performance_test.dart` (134 residual TC-36) — unrelated.

---

## Files To Inspect Next
**Production — widgets/screen/wiring:** `lib/features/feed/presentation/widgets/{letter_card_one_to_one,letter_card_group,letter_card_system,feed_ring_avatar,feed_composer}.dart`; `lib/features/feed/presentation/screens/{feed_screen,feed_wired}.dart`; `lib/features/feed/presentation/widgets/feed_swipe_card.dart`; `lib/features/home/presentation/widgets/user_avatar.dart` (READ-ONLY — reuse); `lib/features/orbit/presentation/screens/orbit_wired.dart`; `lib/features/qr_code/presentation/screens/qr_scanner_wired.dart`; `lib/main.dart` (OrbitWired sites :3958, MyApp field :3288/:4557).
**Domain (read-only context):** `lib/features/feed/domain/models/{feed_letter,feed_item}.dart`, `domain/utils/group_sender_runs.dart`, `application/{feed_pending_projection,feed_store}.dart`.
**Direct tests:** `test/features/feed/presentation/widgets/letter_card_{one_to_one,group,system}_test.dart`; `test/features/feed/presentation/screens/{feed_focus,feed_swipe}_test.dart`; `test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart`; `test/features/orbit/presentation/screens/orbit_wired_test.dart`.

## Existing Tests Covering This Area
- `letter_card_one_to_one_test.dart` — asserts `RingAvatar size==40` (**LOCKS the no-photo bug**; rewrite is the RED step for B1). `letter_card_group_test.dart` / `letter_card_system_test.dart` similar.
- `feed_focus_test.dart` — TC-19/19b/21/22/30 + REG-LEAVE-SURFACE. **Gaps:** no back affordance (B2); open-conv asserted by-key only, never position (B3); TC-22 hits only the send-FAILURE path so the incoming-vanish (B5) is invisible.
- `feed_swipe_test.dart` — TC-23 **LOCKS unconditional right-swipe commit** (must be revised for B4); TC-24/25/26*/33/35*/37 stay. REG-INV3 (commit marks read) → reframe as reply-then-leave.
- `qr_scanner_wired_test.dart` — **5q (`:291`) / 5p (`:257`) are the BUG-6 reproducer: RED on HEAD** (`Found 0 widgets FeedWired`, the `Bad state` throw); their `buildWired` (:153) does not pass `feedClearedRepository`.
- `user_avatar_test.dart` (priority ladder + cache-bust), upload/download use-case tests — prove the B1 infrastructure; reuse, don't modify.

**Missing coverage gaps:** real-photo render in feed cards + live `invalidatePeer` refresh; focused back affordance; open-conv top placement (geometry); right-swipe no-reply=defocus vs reply=commit; incoming-survives-successful-send; Orbit→QR→Feed `feedClearedRepository` wiring.

**Already in curated family arrays?:** all feed tests are in `FEED_TESTS` (~25). **`qr_scanner_wired_test.dart` is NOT** (QR family) — see Harness registration on TC-12.

---

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

> Wired-feed tests reuse the local `buildWired({feedClearedRepository})` closure + `seedPendingThread` + bounded `pumpFrames` (never `pumpAndSettle` — `AmbientBackground.repeat()` hangs it). To exercise **send SUCCESS** (B5/B4b) seed a live connection: `p2pService.emitState(NodeState(isStarted:true, connections:[p2p.ConnectionState(peerId:'p1', multiaddrs:['/dns4/relay/tcp/443'], direction:'outbound', status:'connected')]))` before sending (proven in grounding). Avatar file fixture: write `{docs}/media/avatars/<peerId>.jpg` via the path_provider mock + a tiny PNG.

1. `letter_card_one_to_one_test.dart::renders the contact photo when present, RingAvatar fallback when absent` (B1)
   - Tier: widget. Setup: mount `LetterCardOneToOne` with a seeded `{docs}/media/avatars/<peerId>.jpg`; second case no file.
   - RED on HEAD because: the card wires `FeedRingAvatar` (glyph only); current test asserts `RingAvatar size==40`.
   - GREEN asserts: `find.byType(UserAvatar)` with the contact peerId; an `Image`/`Image.file` is shown when the file exists; `RingAvatar` shows when absent. (Also `showGlow:false, showPhotoFrame:false`.)
   - Mutation that re-reds: revert the card to `FeedRingAvatar` → no `UserAvatar` → red.
2. `letter_card_group_test.dart::each sender run renders UserAvatar keyed on the run's senderPeerId` (B1)
   - Tier: widget. RED: per-run `FeedRingAvatar` size 32. GREEN: per run `UserAvatar(peerId: run.senderPeerId, size:32)`; seeded sender photo shown. Mutation: revert to `FeedRingAvatar` → red.
3. `letter_card_system_test.dart::system card renders UserAvatar (photo when present)` (B1)
   - Tier: widget. RED: `FeedRingAvatar` size 40. GREEN: `UserAvatar(peerId: contactPeerId, size:40)`. Mutation: revert → red.
4. `feed_focus_test.dart::a focused card photo refreshes live when UserAvatar.invalidatePeer fires` (B1 live-update)
   - Tier: widget. Setup: mount a 1:1 card with photo file; replace the file bytes; call `UserAvatar.invalidatePeer(peerId)`; pump.
   - RED on HEAD: card has no `UserAvatar`, nothing reloads.
   - GREEN asserts: the `Image.file` `ValueKey` (the `?v=N` suffix) changed → new photo loaded without remount.
   - Mutation: revert card to `FeedRingAvatar` (or stub `invalidatePeer`) → no reload → red.
5. `feed_focus_test.dart::focused thread shows a back affordance that returns to Feed without committing (no reply)` (B2)
   - Tier: widget. RED: no `ValueKey('feed-focused-back')` exists. GREEN: before focus `findsNothing`; after tapping a card it appears with the sender identity; tapping it → `FeedComposer` gone + the 3 sibling cards reappear (`findsNWidgets(3)`); **asserts `FEED_CLEAR_COMMIT` NOT emitted** (distinct from commit) and `feedClearedRepository.markCalls` empty.
   - Mutation: remove the back-header branch → red; OR wire back to commit → `FEED_CLEAR_COMMIT` fires → discriminator red.
6. `feed_focus_test.dart::open-full-conversation link sits ABOVE the incoming bubbles and above the composer` (B3)
   - Tier: widget (geometry). RED on HEAD: the link is inside the bottom composer → `link.dy > bubble.dy`. GREEN: `getTopLeft(find.byKey('feed-open-full-conversation')).dy < getTopLeft(find.text('hi from ann')).dy` AND `< getTopLeft(find.byKey('feed-composer-field')).dy`; tapping still invokes `onOpenFullConversation` (1:1) / `onGroupTap` (group).
   - Mutation: leave the link in the composer → position assertion red.
7. `feed_swipe_test.dart::right-swipe on a focused card with NO reply returns to Feed and KEEPS the card` (B4a) — **revises TC-23**
   - Tier: widget gesture. RED on HEAD: TC-23 proves the card is REMOVED + `markCleared(markRead:true)`. GREEN: focus, right-swipe past threshold WITHOUT sending → card still present (`find.text('hi from ann') findsOneWidget`), `markCalls` empty, **`FEED_CLEAR_COMMIT` NOT emitted**, focus cleared (composer gone).
   - Mutation: make `_onSwipeCommit` commit unconditionally (HEAD behavior) → card removed → red.
8. `feed_swipe_test.dart::right-swipe on a focused card AFTER sending a reply commits and removes the card` (B4b)
   - Tier: widget gesture. Setup: seed live connection (success send). RED on HEAD: the *no-reply* contract doesn't exist yet, but this asserts the reply→commit half; on HEAD it passes for the wrong reason (unconditional commit) — so pair it with the **ordering** mutation below. GREEN: focus, SEND a reply, right-swipe → card removed + `markCleared(markRead:true)` + `FEED_CLEAR_COMMIT`.
   - Mutation that re-reds: capture `repliesSent` AFTER `_endFocusSessionForThread` (so it always reads empty) → a replied thread mis-classifies as no-reply → 8 red. (Order trap from grounding.)
9. `feed_focus_test.dart::a successful 1:1 reply send KEEPS the incoming bubbles visible` (B5) — **PROD-CRITICAL**
   - Tier: widget (success path). Setup: seed pending 1:1 incoming 'hi from ann'; **seed live connection so the send SUCCEEDS**. RED on HEAD: success branch calls `markConversationRead` → incoming gone (`find.text('hi from ann')` → 0). GREEN: after send, `find.text('hi from ann') findsOneWidget` (incoming survives) AND the outgoing 'on my way' present.
   - Mutation: re-add `markConversationRead(...)` at `feed_wired.dart:1779` → incoming vanishes → red.
   - Companion assert: `getUnreadCountForContact('p1')` stays 1 after a successful SEND (read deferred to leave).
10. `feed_focus_test.dart::a successful GROUP reply send keeps the incoming run visible` (B5 group)
    - Tier: widget. RED: group success calls `markAsRead`. GREEN: group incoming run survives a `successNoPeers` send. Mutation: re-add `markAsRead` → red.
11. `feed_focus_test.dart::leaving a thread that received a reply commits+removes the card and marks it read` (B2/B4/B5 unified leave)
    - Tier: widget. RED on HEAD: send doesn't defer read; back affordance absent. GREEN: focus, SEND a reply (success), tap the back affordance → card removed from feed + `markCleared(markRead:true)` + `FEED_CLEAR_COMMIT` + `getUnreadCountForContact` drops to 0 (read happens on LEAVE). If it was the last card → caught-up empty state.
    - Mutation: make leave-with-reply defocus-only (skip commit) → card stays / unread stays → red. Distinct discriminator: leave-WITH-reply emits `FEED_CLEAR_COMMIT`; leave-WITHOUT-reply (TC-5/TC-7) emits it NOT.
12. `qr_scanner_wired_test.dart::scanning a contact navigates to FeedWired without StateError` (B6) — **revives the RED 5q reproducer**
    - Tier: widget. Setup: build the Orbit→QRScanner harness; drive `ParseQRResult.success` + `AddContactResult.success`; tap success-dialog OK. RED on HEAD: `Bad state: QRScannerWired requires feedClearedRepository…` thrown → `find.byType(FeedWired)` finds 0 / `tester.takeException()` non-null. GREEN: `FeedWired` mounts, no exception.
    - Plus `orbit_wired_test.dart::OrbitWired forwards feedClearedRepository to QRScannerWired and the embedded FeedWired` (tier-1 wiring-lock).
    - Mutation: revert `OrbitWired`'s `feedClearedRepository:` pass-through (or remove the field) → `_missingFeedClearedRepository()` throws → red.
13. (Optional regression-lock — REFUTED residue) `letter_card_one_to_one_test.dart::renders no timestamp / "You replied" / per-card composer` + `feed_screen_test.dart::exactly one FeedComposer`
    - Tier: widget. GREEN (already true): no time-pattern `Text`, no "You replied", `find.byType(FeedComposer)` ≤ 1 within the feed. Mutation: re-introduce old chrome → red. (Locks against regression; not a behavior change.)

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| B1 1:1 photo+fallback | widget render | widget | letter_card_one_to_one_test::renders contact photo / fallback | card wires FeedRingAvatar (no photo); test locks `RingAvatar size==40` | revert to FeedRingAvatar | `flutter test test/features/feed/presentation/widgets/letter_card_one_to_one_test.dart` | in `FEED_TESTS` (AUTO glob too) |
| B1 group photo | widget render | widget | letter_card_group_test::UserAvatar per run senderPeerId | per-run FeedRingAvatar 32 | revert to FeedRingAvatar | `flutter test …/letter_card_group_test.dart` | in `FEED_TESTS` |
| B1 system photo | widget render | widget | letter_card_system_test::system UserAvatar | FeedRingAvatar 40 | revert to FeedRingAvatar | `flutter test …/letter_card_system_test.dart` | in `FEED_TESTS` |
| B1 live refresh | widget + cache-bust | widget | feed_focus_test::photo refreshes on invalidatePeer | no UserAvatar mounted → no reload | revert card / stub invalidatePeer | `flutter test …/screens/feed_focus_test.dart` | in `FEED_TESTS` |
| B2 back affordance | widget gesture | widget | feed_focus_test::back returns without committing | no `feed-focused-back` key | remove header / wire to commit | `flutter test …/screens/feed_focus_test.dart` | in `FEED_TESTS` |
| B3 link placement | widget geometry | widget | feed_focus_test::open-conv link above bubbles+composer | link inside bottom composer (dy>bubble) | leave link in composer | `flutter test …/screens/feed_focus_test.dart` | in `FEED_TESTS` |
| B4a no-reply swipe | widget gesture | widget | feed_swipe_test::right-swipe no-reply keeps card | TC-23 locks unconditional commit-remove | commit unconditionally | `flutter test …/screens/feed_swipe_test.dart` | in `FEED_TESTS` |
| B4b reply→swipe commit | widget gesture | widget | feed_swipe_test::right-swipe after reply commits | (ordering) repliesSent read after clear = empty | capture repliesSent AFTER clear | `flutter test …/screens/feed_swipe_test.dart` | in `FEED_TESTS` |
| B5 1:1 incoming survives | widget success-path | widget | feed_focus_test::successful reply keeps incoming **(PROD-CRITICAL)** | success branch markConversationRead empties unreadMessages | re-add markConversationRead | `flutter test …/screens/feed_focus_test.dart` | in `FEED_TESTS` |
| B5 group incoming survives | widget success-path | widget | feed_focus_test::group reply keeps incoming run | group success markAsRead | re-add markAsRead | `flutter test …/screens/feed_focus_test.dart` | in `FEED_TESTS` |
| B2/4/5 unified leave | widget | widget | feed_focus_test::leave-with-reply commits+marks read | send doesn't defer read; no back affordance | leave-with-reply defocus-only | `flutter test …/screens/feed_focus_test.dart` | in `FEED_TESTS` |
| B6 scan→feed | widget wiring | widget | qr_scanner_wired_test::scan navigates to FeedWired no error | OrbitWired/QR lacks feedClearedRepository → StateError | revert OrbitWired pass-through | `flutter test test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart` + `flutter test test/features/orbit/` | **add `qr_scanner_wired_test.dart` to a curated gate** (it is NOT in `FEED_TESTS`) — run via QR/orbit host glob; verify under `run_host_test_gates.sh feature-host-all` |
| B6 wiring-lock | unit/widget | widget | orbit_wired_test::forwards feedClearedRepository | OrbitWired has no field | remove field/pass-through | `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart` | AUTO (glob) |
| residue (REFUTED) | widget regression-lock | widget | letter_card_one_to_one_test::no timestamp/composer; feed_screen_test::one FeedComposer | (already green) | re-add old chrome | `flutter test …/widgets/ …/screens/feed_screen_test.dart` | in `FEED_TESTS` |

## Invariants (locked by tests)
- **INV-A (real photo precedence + live refresh):** every feed avatar shows the uploaded photo when present, the `RingAvatar` glyph only as fallback, and refreshes on `invalidatePeer` → TC-1/2/3/4.
- **INV-B (discoverable neutral back):** a focused thread always exposes a tappable back affordance that returns to Feed WITHOUT committing when no reply was sent → TC-5 (discriminator: `FEED_CLEAR_COMMIT` NOT emitted).
- **INV-C (history at top):** the open-conversation entry point sits above the incoming bubbles, never below the composer → TC-6 (geometry).
- **INV-D (leave-thread is the only commit/removal/read-mark):** sending only appends; the card is removed + the conversation read-marked **only** on leave-with-reply (back / right-swipe / tap-outside); leave-without-reply keeps the card → TC-7/8/9/10/11.
- **INV-E (incoming immutable in-thread):** incoming bubbles stay visible for the whole focus session, before/during/after send → TC-9/10.
- **INV-F (scan→feed wiring):** `OrbitWired` provides `feedClearedRepository` to both `QRScannerWired` and the embedded `FeedWired`; scan→Feed never throws → TC-12.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
Land in this order; add the row's RED tests at the START of each step and confirm they fail for the documented reason.

**P0 — Snapshot.** `git status --short` (record the uncommitted 134 tree). Pin baselines: `./scripts/run_test_gates.sh feed` and `flutter test test/features/qr_code/` (note 5q/5p already RED = the B6 reproducer).

**P1 — B1 avatar (RED: TC-1/2/3/4).** In the 3 letter cards replace `FeedRingAvatar(peerId,size)` with `UserAvatar(peerId: …, size: …, showGlow:false, showPhotoFrame:false)` (group: `run.senderPeerId`). Rewrite the 3 card tests' `RingAvatar size==N` assertions to the photo/fallback contract; add the live-refresh test. Stop-if: a card lacks a real peerId in hand → it always has one (`letter.peerId`/`run.senderPeerId`/`letter.contactPeerId`).

**P2 — B3 + B2 focused header (RED: TC-5/6).** Add a focused-only header in `feed_screen.dart` (`_buildLetterCard`/`_buildFeedItemWidget`, ~:455/530), rendered ABOVE the card body when `focused`: `[back IconButton key 'feed-focused-back' → leave handler] + sender identity (_displayNameFor) + open-conversation affordance key 'feed-open-full-conversation' (Icon north_east + label, onOpen routing)`. Remove the open-conv affordance from `FeedComposer` (drop `onOpenConversation` wiring in `_buildComposer`). Factor `onOpen` into a shared helper used by the header.

**P3 — B5 stop read-marking on send (RED: TC-9/10).** Remove `markConversationRead` (`feed_wired.dart:1778-1782`) and `markAsRead` (`:1841`) from the send-success branches; keep `_refreshContactFeedItem`/`_refreshGroupFeedItem` + `_loadTotalUnreadCount`. Verify the focused card keeps showing incoming (pin + populated `unreadMessages`).

**P4 — B2/B4 unified leave-thread (RED: TC-7/8/11).** Add `_leaveFocusedThread(String threadId)` to `feed_wired.dart`: `final focusKey = strip 'connection:' prefix; final repliesSent = _feedSessionOutgoing[focusKey]?.isNotEmpty ?? false;` (capture BEFORE clearing) → if `repliesSent`: existing commit body (markClearedLocally + markCleared(markRead:true) + DB read-mark + `_loadTotalUnreadCount`) ; else: defocus only (`_focusedId=null`, `_feedSessionOutgoing.remove(focusKey)`, `_feedStore.setPinnedThread(null)`), no markCleared/read. Re-point `_onSwipeCommit` (right-swipe) AND the back-button AND the tap-outside (`feed_screen.dart:179-184`) at `_leaveFocusedThread`. **Order trap:** capture `repliesSent` before `_endFocusSessionForThread`. Revise `feed_swipe_test.dart` TC-23 to the no-reply=defocus contract; reframe REG-INV3 as reply-then-leave. Stop-if: the gesture-arena/Dismissible store-driven-removal contract breaks → keep `confirmDismiss → false` (removal stays store-driven).

**P5 — B6 QR wiring (RED: TC-12).** Add `feedClearedRepository` field + `required` ctor arg to `OrbitWired`; pass `feedClearedRepository: widget.feedClearedRepository` into its `QRScannerWired` construction (~:1860) and from both OrbitWired sites (`main.dart:3958`, `feed_wired.dart:2169`). Update `qr_scanner_wired_test.dart` `buildWired` (:153) + `orbit_wired_test.dart` to pass a fake repo; assert the scan→FeedWired handoff + the wiring-lock. Stop-if: a site lacks the repo in scope → it's available (`main.dart:4557`, `feed_wired.dart:176`).

**P6 — residue regression-lock (optional, TC-13) + gates.** Add the no-residue locks. Rerun direct → preservation → `run_test_gates.sh feed` → `flutter analyze` → `git diff --check`. Run `graphify update .` from repo root (the arch graph is stale for the new feed handlers).

## Risks And Edge Cases
- **Read-mark relocation:** removing read-mark from send while the badge source (`_loadTotalUnreadCount` → `getTotalUnreadCountExcludingArchived`) reads DB state — correct: badge clears on leave-commit, not send → pinned by TC-9 companion + TC-11.
- **Order trap (repliesSent capture):** `_endFocusSessionForThread`/`_onClearFocus` clear `_feedSessionOutgoing`; capture `repliesSent` first → pinned by TC-8 ordering mutation.
- **connection-card leave:** the focus id is bare but the swipe id is `connection:<peerId>` — `_leaveFocusedThread` must strip the prefix (reuse the existing `_endFocusSessionForThread` normalization) → covered by reusing the 134 fix path; add a connection-card leave assertion if cheap.
- **Group avatar with null senderPeerId:** falls back to glyph keyed on username (cosmetic) — Accepted Difference.
- **TC-23 revision is a behavior change, not a regression:** documented; the new no-reply=defocus contract supersedes it.
- **QR "already exists" path** also navigates to FeedWired (`qr_scanner_wired.dart`) — the wiring fix covers both success and already-exists.

## Device/Relay Proof Profile
**host-only for closure.** No ML-KEM/relay/multi-device/SQLCipher-migration. All six bugs are provable at the widget/wiring tier with fakes (`FakeP2PService` driven to success for B5/B4b). Optional polish (NOT a gate): on-device smoke of (1) a friend's photo updating live in the feed after they change it, and (2) swipe-back + back-button feel. No `classify_path`/dart-define/`--scenario` registration (no `integration_test/` simulator scenario added).

## Acceptance Gates  (literal — copy/paste, with expected counts)
> **Count protocol:** at P0 run each preservation gate once and pin the real baseline in place of `<pin@P0>`.
```bash
# --- RED (before production edits) — must FAIL for the documented reason ---
flutter test test/features/feed/presentation/widgets/letter_card_one_to_one_test.dart   # B1: RingAvatar→UserAvatar rewrite
flutter test test/features/feed/presentation/screens/feed_focus_test.dart --plain-name 'successful reply keeps incoming'   # B5 PROD-CRITICAL
flutter test test/features/feed/presentation/screens/feed_swipe_test.dart --plain-name 'right-swipe no-reply keeps card'   # B4a
flutter test test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart --plain-name 'navigates to feed'        # B6 reproducer (already RED on HEAD)

# --- Direct GREEN (after each phase) ---
flutter test test/features/feed/presentation/widgets/letter_card_one_to_one_test.dart test/features/feed/presentation/widgets/letter_card_group_test.dart test/features/feed/presentation/widgets/letter_card_system_test.dart
flutter test test/features/feed/presentation/screens/feed_focus_test.dart test/features/feed/presentation/screens/feed_swipe_test.dart
flutter test test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart test/features/orbit/presentation/screens/orbit_wired_test.dart

# --- Preservation sentinels (must stay green — pin at P0) ---
./scripts/run_test_gates.sh feed                       # expect: <pin@P0> passed / 0 fail (134 invariants intact)
flutter test -j 1 test/features/feed/                  # expect: <pin@P0+new> passed / 0 fail
flutter test test/features/conversation/               # expect: <pin@P0> passed (read-mark relocation must not regress 1:1 read semantics)
./scripts/run_host_test_gates.sh feature-host-all      # expect: <pin@P0> passed / 0 fail (broad sweep; QR + orbit rows visible here)

# --- Hygiene ---
flutter analyze            # 0 new issues (2 pre-existing dbExistsMessageByContent integration errors are baseline)
git diff --check
```

## Known-Failure Interpretation
- **Expected RED:** every RED-catalog test before its phase. **B6's `qr_scanner_wired_test` 5q/5p are ALREADY RED on HEAD** (the live reproducer) — they go green when P5 lands; do not treat their current red as pre-existing-dirty.
- **Pre-existing dirty:** the uncommitted 134 tree + `graphify-arch/*` churn + the 2 `dbExistsMessageByContent` integration-harness analyze errors (NOT in scope). `feed_performance_test.dart` minimal-compile-fix (134 residual).
- **Environment blocker (NOT product):** none (host-only).
- **Scope drift (BLOCKING):** any failure in conversation/posts/notification/orbit-non-QR suites from the read-mark relocation or the OrbitWired ctor change → fix in scope, do not suppress. Revising 134 TC-23 is expected (B4), NOT scope drift.

## Done Criteria
- [ ] RED added first per bug, failed for the expected reason.
- [ ] Mutation-verified (each fix has a re-red revert per the matrix).
- [ ] Direct GREEN + `run_test_gates.sh feed` + `feature-host-all` + conversation preservation pass.
- [ ] B5 PROD-CRITICAL success-path test drives `FakeP2PService` to success and asserts incoming survives.
- [ ] 134 TC-23 revised to the no-reply=defocus contract; REG-INV3 reframed as reply-then-leave.
- [ ] `qr_scanner_wired_test` 5q/5p GREEN; `OrbitWired` wiring-lock added.
- [ ] No DB migration (DB stays v92); no new simulator scenario.
- [ ] `flutter analyze` 0 new; `git diff --check` clean; `graphify update .` run; no Scope Guard violations.

## Scope Guard (hard "Do not")
- Do **not** modify `UserAvatar` / `RingAvatar` / the upload-download cache-bust use-cases (reuse as-is).
- Do **not** add a second image-eviction mechanism (cache-bust is already wired).
- Do **not** build a captured incoming "snapshot" for B5 (removing read-mark-on-send is sufficient).
- Do **not** resurrect a resting-card name header (134 TC-16) — identity goes in the FOCUSED-only header.
- Do **not** mark read or remove the card on SEND — only on leave-with-reply.
- Do **not** change `FeedWired`/`QRScannerWired` ctors for B6 (the fix is the `OrbitWired` field + threading).
- Do **not** change conversation/posts/notification routing or `glowColorForPeerId`.

## Accepted Differences / Intentionally Out Of Scope
- Group sender-run avatar when `senderPeerId` is null → glyph keyed on username (cosmetic edge).
- Android system-back (`PopScope`) as a leave-thread trigger → follow-up (the back chevron is the planned affordance).
- Re-authoring `feed_performance_test.dart` (134 TC-36 residual).

## Dependency Impact
- A follow-up may add a `PopScope` leave-handler routing Android system-back through `_leaveFocusedThread` (same commit-if-replied semantics) — depends on this plan's `_leaveFocusedThread` existing.

## Reviewer Findings
Sufficiency self-check (sufficiency-checklist.md) — **PASS**. Spec-case totality: all 6 bugs + unified-leave have ≥1 named test at the right tier (13 RED entries / 14 matrix rows). Every INV-A..F is locked. Every fix is mutation-verified with a named re-red (incl. the B4b order-trap and the B5 read-mark re-add). No vacuous coverage — leave-with-reply vs leave-without-reply are distinguished by the `FEED_CLEAR_COMMIT` emitted/NOT discriminator, and the B5 RED is non-trivial only because it drives `FakeP2PService` to SUCCESS (the existing suite is blind to it). Literal gates with `<pin@P0>` counts + `analyze` + `git diff --check`. Harness-registration concrete per row (feed rows in `FEED_TESTS`; `qr_scanner_wired_test`/`orbit_wired_test` AUTO-globbed → visible under `feature-host-all`). No migration (correctly N/A — DB stays v92). No OS-boundary/crypto/relay/multi-device path → host-only closure justified (not a faked-boundary gap). Refuted findings recorded as do-NOT-re-introduce (cross-cutting residue; redundant cache-bust; incoming snapshot).
Verdict: **structurally sufficient**.

## Arbiter Decision
Structural blockers: **none**. Deferred details: group null-`senderPeerId` glyph fallback (cosmetic Accepted Difference); Android `PopScope` leave-trigger (follow-up); `feed_performance_test` re-author (134 residual). Accepted differences as listed. Note for execution: B4 **requires revising 134 `feed_swipe_test` TC-23** (unconditional-commit → no-reply=defocus) and reframing REG-INV3 as reply-then-leave — this is expected behavior change, not scope drift. **Verdict: ready for execution hand-off.**

## Final Execution Verdict
**EXECUTED — host-green, all 6 bugs landed TDD (RED→GREEN→mutation), 2026-06-20.** Branch `new-feed`, uncommitted.

Landing order honored P1→P6. Per-bug RED-first confirmed for the documented reason; mutations re-red verified (B1 swap-back, B2/B3 header-absent + link-in-composer, B5 re-add markConversationRead/markAsRead, B4 **order-trap** capture-after-clear re-reds TC-8/TC-11/REG-INV3). Implementation deltas, all in `feed_wired.dart`/`feed_screen.dart`/`feed_composer.dart`/3 letter cards/`orbit_wired.dart`/`main.dart`:
- **B1** — 3 cards `FeedRingAvatar`→`UserAvatar(showGlow:false, showPhotoFrame:false)`; card tests rewritten to the photo/fallback + live-`invalidatePeer` contract.
- **B2/B3** — focused-only header in `feed_screen.dart` (`_buildFocusedHeader`): back chevron `feed-focused-back` + identity + open-conv `feed-open-full-conversation` moved to TOP; open-conv removed from `FeedComposer` (shared `_onOpenConversationFor` helper).
- **B5** — removed `markConversationRead` (contact) + `markAsRead` (group) from the send-success branches; read deferred to leave.
- **B2/B4/B5** — unified `_leaveFocusedThread(threadId)` (commit-if-replied / defocus-if-not, `repliesSent` captured BEFORE `_endFocusSessionForThread`); back + tap-outside via `_onClearFocus`, right-swipe via `onSwipeCommit`, all → `_leaveFocusedThread`.
- **B6** — `OrbitWired` gained required `feedClearedRepository`, threaded to `QRScannerWired` + both OrbitWired sites; qr reproducer 3-RED→7/7 green; orbit wiring-lock added.

**Plan under-counts caught & fixed** (test follow-ons, expected per Arbiter): B1 also broke `feed_swipe_test`'s `FeedRingAvatar` tap (→`UserAvatar`); B4 affected **4** swipe tests (plan named 2) — TC-23→TC-7, REG-INV3 reply-then-leave, REG-CONN-FOCUS no-reply=defocus, TC-35a arena-defocus — all reframed to lock real invariants.

**Gates:** feed gate **210/0** (×5 stable); `qr_scanner_wired_test` **7/7**; `orbit_wired_test` B6 lock green; conversation preservation **1264/0**; `flutter analyze` **0 errors / 0 new issues in edited files**; `git diff --check` clean; `graphify update .` run (full graph rebuilt). No migration (DB stays v92); no simulator scenario. 5-dimension adversarial review: **0 confirmed real bugs** (refuted the connection-card commit-kind concern: a reply persists the optimistic msg → ConnectionFeedItem is suppressed into a ThreadFeedItem → bare contact key is correct).

**Closed an adjacent pre-existing 134-residual** (same `feedClearedRepository`-threading class as B6, test-only): `first_time_experience_wired_test` omitted `feedClearedRepository` → `FirstTimeExperienceWired requires feedClearedRepository` throw; fixed harness → 15/15.

**Pre-existing failures NOT owned by 135 (surfaced, not fixed):** (a) `ambient_background_test` "no Test-Flight-Improv import" guard — 4 non-feed lib files (`bonsoir_discovery_service`, `migration_breadcrumb`, `conversation_route_transition`, `send_delivery_receipt_use_case`) contain the string from concurrent uncommitted migration/conversation work; (b) 3 `orbit_wired_test` group-invite tests (A2/EK011/cursor-backlog) — state-sensitive (pass in the full feature-host-all sweep, fail when the file runs alone), from uncommitted 08-invite work; (c) 2 `dbExistsMessageByContent` integration analyze errors (plan-noted baseline). All render-neutral to the 135 diff.

Verdict: **all 6 bugs CLOSED host-side; ready for commit + optional on-device polish smoke (avatar live-refresh + swipe/back feel).**
