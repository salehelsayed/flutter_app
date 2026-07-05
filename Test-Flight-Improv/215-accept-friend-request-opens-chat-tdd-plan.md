# 215 - Accepting a Friend Request Opens the 1:1 Chat  (Modification)

Status: awaiting-review
Spec: free-text intent (no formal spec) — "When a user receives a friend request and accepts it, the app should immediately open the main chat window (1:1 conversation screen) of the newly accepted user."

Grounding vehicle: verify→refute Workflow `wf_d419ce11-c6b` (5 agents; 4 confirmed, 1 non-critical agent — the intro-out-of-scope claim — died on a StructuredOutput retry-cap and was verified by hand instead). Findings survived the adversarial refute pass.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| t0 | Evidence Collector | orbit_wired.dart, feed_wired.dart, first_time_experience_wired.dart, contact_request_notification_materializer.dart, accept_and_reciprocate_use_case.dart, accept_contact_request_use_case.dart, contact_request_dialog.dart, the 3 wired test files | "friend request" == contact_request feature (dialog text "wants to connect with you"); intro (3-party) is a different feature | Ground the seam |
| t1 | Planner (verify→refute wf) | 3 in-app accept handlers + notification materializer + 2 debug runners | GAP confirmed: 3 in-app accept handlers don't open the chat; only the notification-tap materializer does | Build matrix |
| t2 | Reviewer (refute) | same, adversarial | FTE must land Feed→then push chat (not replace with chat); 3 test pitfalls (pre-seed request, drain 5s timer, orbit lacks ConversationWired import) | Emit plan |
| t3 | Arbiter | — | Host-only closure; 3 production edits + shared helper extraction; all-widget-tier coverage | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | orbit_wired_test.dart, feed_wired_test.dart, first_time_experience_wired_test.dart | (cmds below) | RED for expected reason | |
| | implementation | orbit_wired.dart, feed_wired.dart, first_time_experience_wired.dart | | scoped files only | |
| | direct GREEN | | | reds now green | |
| | preservation GREEN | | | sentinels green | |
| | named gates | | | gate green | |
| | QA (independent) | | | blocking: none/list | verdict |

## Source Of Truth
- Spec / intent: inline (free-text above)
- Gate definitions: `scripts/run_test_gates.sh` + `scripts/run_host_test_gates.sh` (script wins over prose)
- Discovery/registration: n/a (host-only; no simulator scenarios)
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (this plan = 215, next-free after 214)

## Session Classification
implementation-ready

## Exact Problem Statement
When a peer sends a **contact request** ("friend request"), the recipient sees a `ContactRequestDialog` ("<name> wants to connect with you", Accept / Decline). Today, tapping **Accept** adds + reciprocates the contact and then leaves the user exactly where they were — Orbit refreshes its list, Feed inserts a connection card, and onboarding drops into the Feed. The user has to *find* the new friend and tap in to start chatting. The desired behavior is that accepting a friend request **immediately opens the 1:1 conversation screen** (`ConversationWired`) for the newly-accepted user, so the natural next action (say hi) is one tap, not three.

The pattern already exists in exactly one surface: the **notification-tap** accept path (`ContactRequestNotificationMaterializer.acceptRequest`, `contact_request_notification_materializer.dart:96-102`) already does `getContact(peerId) ?? request.toContactModel()` → `openConversation(...)`. The three **in-app dialog** accept handlers do not. This makes the in-app accept behavior inconsistent with the notification behavior.

What must improve: the three in-app `_acceptRequest` handlers (Orbit, Feed, first-time-experience) open the 1:1 chat for the accepted peer on a `success`/`notPending` result — mirroring the materializer contract.
What must stay unchanged (→ preserved-green sentinels): the notification-tap materializer path (already opens chat); Orbit's post-accept `_markContactChanged`+`_refreshOrbitFriend`; Feed's `ConnectionFeedItem` upsert (so popping back from the chat still shows the connection); FTE's Feed-shell establishment (`pushReplacement(FeedWired)`) + `settleShareIntentFlow` share replay; the accept use-cases + reciprocal key-exchange behavior (unchanged); the 3-party **introduction** flow (out of scope entirely).

## Root Cause (verify → refute confirmed)
Three in-app contact-request accept handlers reach a `success`/`notPending` result and stop short of opening the conversation:
- `lib/features/orbit/presentation/screens/orbit_wired.dart:1930-1950` — `_acceptRequest`: `Navigator.pop(ctx)` → `await acceptAndReciprocateContactRequest(...)` → on success/notPending only `_markContactChanged(peerId)` + `await _refreshOrbitFriend(peerId)`. **No `ConversationWired` push.**
- `lib/features/feed/presentation/screens/feed_wired.dart:1351-1389` — `_acceptRequest`: on success/notPending upserts a `ConnectionFeedItem` (else error snackbar). **No push.**
- `lib/features/home/presentation/screens/first_time_experience_wired.dart:217-306` — `_acceptRequest`: on success/notPending `navigator.pushReplacement(buildFeedSlideUpRoute(FeedWired(...)))` + `settleShareIntentFlow(...)`. **Navigates to the Feed shell, not the 1:1 chat.**

The mirror-target contract (already correct): `lib/features/contact_request/application/contact_request_notification_materializer.dart:96-102`. `request.toContactModel()` exists (`contact_request_model.dart:122`). Conversation-open helper pattern: `buildConversationRoute(builder: (_) => ConversationWired(contact: <ContactModel>, ...deps))` — Orbit `_onFriendTap` (`orbit_wired.dart:2136-2177`, guarded by `_openingFriendPeerIds`), Feed `_onSendMessage`/`_onReplyToMessage` (`feed_wired.dart:1588-1652`).

Refuted / do-NOT-re-introduce:
- **"Some HEAD in-app path already opens the chat, change is redundant."** REFUTED. The contact-update stream listeners (`orbit_wired.dart:1862-1871`, `feed_wired.dart:1562-1586`) only refresh state; `main.dart:3198-3213` re-broadcasts; the only auto-open is the notification materializer. Change is genuinely needed.
- **"Make FTE open the chat via `pushReplacement`."** REFUTED (would break onboarding). FTE's `pushReplacement(FeedWired)` intentionally establishes the app home-shell and is followed by `settleShareIntentFlow`. Replacing the onboarding route with a chat would leave a chat with no shell behind it (broken back-nav) and skip the share-intent settle. Correct design: keep `pushReplacement(FeedWired)`, then **`navigator.push(ConversationWired)` on top** (back-stack `[FeedWired, ConversationWired]`), then `settleShareIntentFlow` last.
- **"Interpret 'friend request' as the 3-party introduction accept."** REFUTED (out of scope). Introductions require **mutual** acceptance before a 1:1 peer exists, and the intro UI already exposes a distinct post-`mutualAccepted` "Send message" affordance (`intro_row.dart:145-175`, `onSendMessage`). The contact-request dialog is the literal "wants to connect with you" friend request. (This is the claim whose grounding agent died on a schema retry-cap; verified by hand.)

## Real Scope
In scope: add a 1:1 `ConversationWired` open to the three in-app `_acceptRequest` handlers (Orbit, Feed, FTE) on `success`/`notPending`, mirroring the materializer contract; extract a small `_openConversationForContact(ContactModel)` helper in Orbit and Feed (reused by the existing friend-tap / send-message openers) to avoid duplicating the deps block.
Out of scope (owning work): the 3-party introduction accept flow (its own feature); any redesign of `acceptAndReciprocateContactRequest` / reciprocal key exchange; consolidating the in-app dialog path onto the `ContactRequestNotificationMaterializer` (possible future DRY, not here); the debug/E2E runners (`intro_e2e_runner`, `smoke_test_runner`) which are headless and intentionally do not navigate.

## Files To Inspect Next
Production (entry/use-case, models, helpers):
- `lib/features/orbit/presentation/screens/orbit_wired.dart` — `_acceptRequest` (1930), `_onFriendTap`/push block (2136-2177), guard `_openingFriendPeerIds` (296)
- `lib/features/feed/presentation/screens/feed_wired.dart` — `_acceptRequest` (1351), `_onSendMessage` push block (1588-1625)
- `lib/features/home/presentation/screens/first_time_experience_wired.dart` — `_acceptRequest` (217-306); add imports for `ConversationWired` + `buildConversationRoute` (currently only imports `feed_wired.dart:50`)
- `lib/features/contact_request/application/contact_request_notification_materializer.dart:96-102` — the contract to mirror (unchanged)
- `lib/features/contact_request/domain/models/contact_request_model.dart:122` — `toContactModel()`
Direct tests:
- `test/features/orbit/presentation/screens/orbit_wired_test.dart` (dialog-appears test at 1731; `_RecordingNavigatorObserver` at 5182; **does NOT import `ConversationWired`**)
- `test/features/feed/presentation/screens/feed_wired_test.dart` (dialog test at 594; already imports + asserts `find.byType(ConversationWired)` at 20/525)
- `test/features/home/presentation/screens/first_time_experience_wired_test.dart` (accept→Feed tests at 538/591/657; `buildFTE`, `contactRequestRepo.seed`, `_FakeContactRequestListener(requestStream:)`)
Dependency-only context:
- `test/features/contact_request/domain/repositories/fake_contact_request_repository.dart` (`.seed([...])`, `getRequest`), `test/features/contacts/domain/repositories/fake_contact_repository.dart` (`throwOnAddContact`, `getContact`)
- `test/features/contact_request/application/contact_request_notification_materializer_test.dart` (preservation sentinel)

## Existing Tests Covering This Area
- `orbit_wired_test.dart` "…contact request dialog on incoming request" (≈1731) — asserts the **dialog appears**; does NOT tap Accept or assert navigation. (exists; coverage gap = no accept-nav assertion)
- `feed_wired_test.dart` "shows contact request dialog on incoming request" (594) — same; dialog-only. (exists; gap)
- `first_time_experience_wired_test.dart` "5o: accept success…lands on the Orbit surface" (591) + "accept success forwards nearby dependencies into feed" (657) + "notPending still settles and replays a buffered share" (538) — assert accept → `FeedWired`/share-settle; do NOT assert a chat opens. (exists; gap)
- `contact_request_notification_materializer_test.dart` — asserts notification-accept → `openConversation`. (exists; this is the contract we mirror + a preservation sentinel)
- `accept_and_reciprocate_use_case_test.dart`, `contact_request_flow_test.dart`, `contact_request_one_scan_mutual_test.dart` — cover the accept/reciprocate/key-exchange semantics (unchanged; preservation)

Missing coverage gaps: no test asserts that the **in-app dialog** Accept opens the 1:1 chat (Orbit/Feed/FTE), nor the failure/`notPending` branches for navigation.
Already in curated family arrays?: `feed_wired_test.dart` → `FEED_TESTS` (`run_test_gates.sh:182`, runs under `feed`); `orbit_wired_test.dart` → `GROUP_TESTS` (`run_test_gates.sh:230`, runs under `groups`); `first_time_experience_wired_test.dart` → not curated → AUTO glob `feature-host-all` only.

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

1. `test/features/orbit/presentation/screens/orbit_wired_test.dart` :: `'accepting a contact request opens the 1:1 conversation for the new contact'`
   - Tier: widget
   - Shape/setup: `identityRepo.seed(testIdentity)`; build a **pending** `ContactRequestModel(peerId:'requester-peer-id', …, status: ContactRequestStatus.pending)`; **PRE-SEED** `contactRequestRepo.seed([request])` (else `getRequest`→`notFound`→neither success nor notPending→push branch never runs→false-negative RED); `bridge.responses['payload.sign']={ok:true,signature:'s'}` and `bridge.responses['contactrequest.encrypt']={ok:true,ephemeralPublicKey:'e',ciphertext:'c',nonce:'n'}` (reciprocal send helper); `_FakeContactRequestListener(requestRepo:contactRequestRepo, contactRepo:contactRepo, bridge:bridge)`; `buildOrbitWired(contactRequestListener: fakeRequestListener)`. **Add `import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart' show ConversationWired;`** to this test (it currently lacks it) so `find.byType(ConversationWired)` compiles — OR assert via the existing `_RecordingNavigatorObserver.lastPushedRoute`.
   - Drive: `emitRequest(request)` → 2×`pump(100ms)` (dialog appears) → `tester.tap(find.text('Accept'))` → `pump()` → **`pump(const Duration(seconds:6))`** (DRAIN the 5s profile-download retry timer at `accept_and_reciprocate_use_case.dart:57`; also flushes the async push — else teardown dies "A Timer is still pending").
   - RED on HEAD because: `orbit_wired.dart:1945-1949` only refreshes; no `ConversationWired` is pushed → `find.byType(ConversationWired)` is `findsNothing`.
   - GREEN after fix asserts: `find.byType(ConversationWired)` `findsOneWidget` AND `tester.widget<ConversationWired>(...).contact.peerId == 'requester-peer-id'`.
   - Mutation that re-reds: revert the `_openConversationForContact(contact)` call added to `_acceptRequest` → `findsNothing` → RED.

2. `test/features/orbit/presentation/screens/orbit_wired_test.dart` :: `'accept failure (addContact error) does NOT open a conversation'`
   - Tier: widget (branch guard)
   - Shape/setup: as (1) but `contactRepo.throwOnAddContact = true` → `acceptContactRequest` returns `addContactError`.
   - RED on HEAD because: GREEN on HEAD (no nav today) — this is a **guard** locking "navigate only on success/notPending". It goes RED against a *wrong fix*.
   - GREEN after fix asserts: `find.byType(ConversationWired)` `findsNothing`.
   - Mutation that re-reds: make the push unconditional (drop the `success||notPending` guard) → RED.
   - Distinct-event discriminator: assert `findsNothing` for `ConversationWired` AND that the dialog is dismissed (`find.text('Accept')` `findsNothing`) — proves accept *ran* but did not navigate, distinguishing "no-nav" from "accept never fired".

3. `test/features/feed/presentation/screens/feed_wired_test.dart` :: `'accepting a contact request opens the 1:1 conversation'`
   - Tier: widget
   - Shape/setup: clone the dialog test at 594 + PRE-SEED `contactRequestRepo.seed([request])` + `bridge.responses` as in (1). `feed_wired_test` **already imports** `ConversationWired` (20) and uses `find.byType(ConversationWired)` (525) — reuse.
   - Drive: emit → dialog → tap Accept → `pump()` + `pump(seconds:6)`.
   - RED on HEAD because: `feed_wired.dart:1369-1379` upserts a `ConnectionFeedItem` only; no push.
   - GREEN after fix asserts: `find.byType(ConversationWired)` `findsOneWidget` AND `.contact.peerId == 'requester-peer-id'`.
   - Mutation that re-reds: revert the `_openConversationForContact(contact)` call in feed `_acceptRequest` → RED.

4. `test/features/feed/presentation/screens/feed_wired_test.dart` :: `'accept keeps the connection in the feed after popping the chat'`
   - Tier: widget (preservation of the upsert under the new nav — INV)
   - Shape/setup: as (3); after the chat opens, `Navigator.of(...).pop()` (or `tester.pageBack()`) → `pumpAndSettle`.
   - RED on HEAD because: GREEN on HEAD path-wise (upsert exists) — locks that adding nav does NOT remove the `_feedStore.upsertConnection` call.
   - GREEN after fix asserts: after popping, the connection for `requester-peer-id` is present (connection card `findsWidgets` / `find.textContaining('Charlie')`).
   - Mutation that re-reds: delete the `ConnectionFeedItem` upsert while adding nav → RED.

5. `test/features/feed/presentation/screens/feed_wired_test.dart` :: `'accept failure shows error and does NOT open a conversation'`
   - Tier: widget (branch guard + snackbar preservation)
   - Shape/setup: as (3) but `contactRepo.throwOnAddContact = true`.
   - GREEN after fix asserts: error snackbar present (`find.text(l10n.error_add_contact)`/red SnackBar) AND `find.byType(ConversationWired)` `findsNothing`.
   - Mutation that re-reds: make push unconditional → RED.

6. `test/features/home/presentation/screens/first_time_experience_wired_test.dart` :: `'accepting the first request lands on Feed AND opens the new contact chat on top'`
   - Tier: widget
   - Shape/setup: mirror test 591 — PRE-SEED `contactRequestRepo.seed([pending request])`; `bridge.responses` as in (1); `buildFTE(overrideListener: customListener)`; emit; tap Accept; `pump()` + `pump(const Duration(milliseconds:400))` + `pump(const Duration(seconds:5))`. **Add `ConversationWired` import** to this test if absent.
   - RED on HEAD because: `first_time_experience_wired.dart:243` only `pushReplacement(FeedWired)`; no `ConversationWired`.
   - GREEN after fix asserts: `find.byType(FeedWired)` `findsOneWidget` (shell preserved) AND `appShellController.activeTab == AppShellTab.orbit` AND `find.byType(ConversationWired)` `findsOneWidget` AND `.contact.peerId == request.peerId`.
   - Mutation that re-reds: revert the FTE `navigator.push(buildConversationRoute(ConversationWired(...)))` → RED (existing FeedWired assertion stays green, isolating the new behavior).
   - Distinct-event discriminator: assert `FeedWired` findsOneWidget AND `ConversationWired` findsOneWidget together — proves the chat rides **on top of** the shell (two-push), not a shell-replacing chat.

7. `test/features/home/presentation/screens/first_time_experience_wired_test.dart` :: existing `'notPending still settles and replays a buffered share'` (538) — **preservation sentinel** (must stay green)
   - Tier: widget
   - Assertion (unchanged): `shareIntentService.isSettled` true, `find.text('Share with...')` + `find.text('already added')` present. Because the plan pushes the chat **before** `settleShareIntentFlow`, the share sheet stays on top → these assertions hold. Also proves the `notPending` branch opens the chat under the sheet without breaking share replay.
   - Mutation that would re-red: pushing the chat *after* the share settle (wrong order) covering the sheet, or breaking `settleShareIntentFlow` → RED.

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 Orbit success→chat | widget nav on success | widget | orbit_wired_test.dart::`accepting a contact request opens the 1:1 conversation for the new contact` | orbit `_acceptRequest` only refreshes (`:1945-1949`) | revert `_openConversationForContact` call in orbit `_acceptRequest` | `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart` | AUTO glob + already in `GROUP_TESTS` (`run_test_gates.sh:230`) → `run_test_gates.sh groups`; **needs new `ConversationWired` import in the test file** |
| TC-02 Orbit failure→no chat | branch guard | widget | orbit_wired_test.dart::`accept failure (addContact error) does NOT open a conversation` | (guard; green on HEAD) | drop `success||notPending` guard → nav unconditional | `flutter test test/features/orbit/.../orbit_wired_test.dart` | AUTO glob + `groups` |
| TC-03 Feed success→chat | widget nav on success | widget | feed_wired_test.dart::`accepting a contact request opens the 1:1 conversation` | feed `_acceptRequest` upserts only (`:1369-1379`) | revert `_openConversationForContact` call in feed `_acceptRequest` | `flutter test test/features/feed/presentation/screens/feed_wired_test.dart` | AUTO glob + already in `FEED_TESTS` (`run_test_gates.sh:182`) → `run_test_gates.sh feed` |
| TC-04 Feed upsert preserved | invariant under new nav | widget | feed_wired_test.dart::`accept keeps the connection in the feed after popping the chat` | (preservation; green path) | delete `_feedStore.upsertConnection` while adding nav | `flutter test test/features/feed/.../feed_wired_test.dart` | AUTO glob + `feed` |
| TC-05 Feed failure→no chat + snackbar | branch guard + snackbar | widget | feed_wired_test.dart::`accept failure shows error and does NOT open a conversation` | (guard; green on HEAD) | make push unconditional | `flutter test test/features/feed/.../feed_wired_test.dart` | AUTO glob + `feed` |
| TC-06 FTE success→Feed+chat-on-top | two-push nav | widget | first_time_experience_wired_test.dart::`accepting the first request lands on Feed AND opens the new contact chat on top` | FTE only `pushReplacement(FeedWired)` (`:243`) | revert FTE `navigator.push(ConversationWired)` | `flutter test test/features/home/presentation/screens/first_time_experience_wired_test.dart` | AUTO glob `feature-host-all` (not curated) |
| TC-07 FTE buffered-share still settles | preservation sentinel | widget | first_time_experience_wired_test.dart::`notPending still settles and replays a buffered share` (existing 538) | (preservation) | push chat AFTER `settleShareIntentFlow` (wrong order) | `flutter test test/features/home/.../first_time_experience_wired_test.dart` | AUTO glob |
| TC-08 notPending→chat | OR-branch | widget | folded into TC-01/03 variant with `status: accepted` request (→ `notPending`) OR FTE 538 | on HEAD notPending also doesn't open chat (in-app) | revert push (same as TC-01/03) | same file cmds above | AUTO glob + family |
| INV-MAT notification-accept still opens chat | unchanged contract | widget/unit | contact_request_notification_materializer_test.dart (existing, unchanged) | n/a (preservation) | (do not edit materializer) | `flutter test test/features/contact_request/application/contact_request_notification_materializer_test.dart` | AUTO glob `feature-host-all` |

## Blind-Spot Sweep  (evergreen classes — row added OR justified N/A)
- **Lifecycle / derived-state durability** (reopen/restart reconstructs derived UI): **N/A** — the change adds no persisted derived state; opening a chat is a transient navigation. The contact row itself persists and is already covered by `accept_and_reciprocate_use_case_test.dart` + repo tests. There is no reopen-reconstruct obligation.
- **Sibling-surface consistency** (apply the change across every parallel surface): **THE headline of this plan.** The four contact-request accept surfaces are `{orbit_wired, feed_wired, first_time_experience_wired, notification_materializer}`. Three are changed (TC-01/03/06); the materializer already conforms and is locked as a preservation sentinel (INV-MAT). Debug runners (`intro_e2e_runner`, `smoke_test_runner`) are deliberately excluded (headless, non-nav) and named in Scope Guard.
- **Destructive-action side-effects** (delete/cleanup asserts removed + preserved): **N/A** — no delete/cleanup/cancel path is added or changed. The only preservation risk is dropping Feed's `ConnectionFeedItem` upsert (TC-04) or Orbit's refresh; both are test-locked.
- **Invariant re-verification under new transitions** (new transition re-checks pre-transition invariants): the new transition "accept → open chat" must not clobber existing post-accept side-effects. Locked: Orbit `_markContactChanged`+`_refreshOrbitFriend` still run before nav (TC-01 leaves them intact; observe list refresh is preserved by re-running the orbit suite); Feed upsert preserved (TC-04); FTE Feed-shell + `activeTab==orbit` + share-settle preserved (TC-06 asserts `FeedWired`+`activeTab`; TC-07 asserts share replay). FTE ordering invariant: push chat **before** `settleShareIntentFlow` so a buffered share sheet stays on top (TC-07 mutation).

## Invariants (locked by tests)
- INV-1: Accepting a contact request via the in-app dialog opens `ConversationWired` for the accepted peer on `success` **or** `notPending` → TC-01/03/06/08.
- INV-2: Navigation happens **only** on success/notPending; a failed accept opens no chat → TC-02/05.
- INV-3: Existing post-accept side-effects survive the new nav (Feed upsert; FTE Feed-shell + share replay) → TC-04/06/07.
- INV-4: The notification-tap accept contract is unchanged → INV-MAT.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. Snapshot the dirty tree: `git status --short` (there are pre-existing unrelated modifications on `new-orbit` — do not revert them).
2. Add RED tests TC-01…TC-06 (+ TC-08 variant) to the three wired test files; add the `ConversationWired` import where missing (orbit + FTE test files). Run the focused RED cmds; confirm TC-01/03/06 FAIL with `find.byType(ConversationWired) → findsNothing` (the documented reason), and that TC-02/04/05/07 pass (guards/preservation).
3. **Orbit** (`orbit_wired.dart`): extract the `ConversationWired` push from `_onFriendTap` (2142-2177) into `void _openConversationForContact(ContactModel contact)` (keep the `_openingFriendPeerIds` guard keyed on `contact.peerId`, same deps block, same return cleanup). Point `_onFriendTap` at it (`_openConversationForContact(friend.contact)`). In `_acceptRequest`, after `_markContactChanged`+`await _refreshOrbitFriend`, add: `final contact = await widget.contactRepo.getContact(request.peerId) ?? request.toContactModel(); if (!mounted) return; _openConversationForContact(contact);`.
4. **Feed** (`feed_wired.dart`): extract the `ConversationWired` push from `_onSendMessage` (1595-1624) into `void _openConversationForContact(ContactModel contact)` (same deps). In `_acceptRequest`, **after** the existing `ConnectionFeedItem` upsert, add: `final contact = await widget.contactRepository.getContact(request.peerId) ?? request.toContactModel(); if (!mounted) return; _openConversationForContact(contact);`.
5. **FTE** (`first_time_experience_wired.dart`): add imports for `ConversationWired` + `conversation_route_transition.dart` (`buildConversationRoute`). In `_acceptRequest`, keep `navigator.pushReplacement(buildFeedSlideUpRoute(FeedWired(...)))` unchanged, then add `navigator.push(buildConversationRoute(builder: (_) => ConversationWired(contact: contact, identityRepo: widget.repository, messageRepo: widget.messageRepository, chatMessageListener: widget.chatMessageListener, p2pService: widget.p2pService, bridge: widget.bridge, contactRepo: widget.contactRepository, /* + optional deps FTE holds: mediaAttachmentRepo, mediaFileManager, imageProcessor, conversationTracker, audioRecorderService, reactionRepo, reactionListener, introductionRepository, appShellController, transportMetrics */)))` where `contact = await widget.contactRepository.getContact(request.peerId) ?? request.toContactModel()` (capture `navigator` before the await; re-check `mounted`). Keep `settleShareIntentFlow(...)` **last** so a buffered share sheet stays on top.
   - Stop-if: FTE lacks a required `ConversationWired` dep as a widget field → replan (fall back to `request.toContactModel()` for the contact and pass only the 5 required + the optional deps FTE actually holds; `ConversationWired`'s only *required* params are `contact/identityRepo/messageRepo/chatMessageListener/p2pService`, all present).
6. Rerun direct RED cmds → now GREEN. Run preservation sentinels + named gates. Run `flutter analyze` + `git diff --check`.

## Risks And Edge Cases
- **Pending 5s timer in widget tests** (fire-and-forget profile download always schedules `Future.delayed(5s)` because `getApplicationDocumentsDirectory` throws `MissingPluginException` under fakes and returns null): every new accept test MUST `pump(const Duration(seconds:6))` (FTE: `seconds:5` per existing pattern) or teardown fails "A Timer is still pending". No injection point on the handlers. → pinned by the pump in TC-01/03/06.
- **Un-seeded request → false-negative RED**: `emitRequest` drives only the *stream* (dialog); `acceptContactRequest` reads `contactRequestRepo.getRequest`. Without `contactRequestRepo.seed([request])` the result is `notFound` and the push branch never runs — the test would go red for the wrong reason. → every accept test pre-seeds.
- **Reciprocal `sendContactRequest`**: safe no-op in tests (`nodeNotRunning`, no timer) because fake `p2pService.currentState.isStarted == false`. No handling needed.
- **Double-push / navigator race**: `Navigator.pop(ctx)` is synchronous and the `await acceptAndReciprocate...` yields before any push, so no pop-vs-push lock; `barrierDismissible:false` + synchronous pop prevent re-entry. Orbit reuses `_openingFriendPeerIds` for belt-and-suspenders. → covered by TC-01 (single `ConversationWired`, `findsOneWidget` not `findsWidgets`).
- **FTE share-intent ordering**: push chat before `settleShareIntentFlow` so the share sheet lands on top. → pinned by TC-07.

## Device/Relay Proof Profile
**host-only for closure.** This is pure in-app Flutter navigation — no OS boundary, no ML-KEM convergence, no relay custody. The accept/reciprocate/key-exchange semantics are unchanged and already covered by existing integration/simulator tests (`contact_request_flow_test.dart`, `contact_request_one_scan_mutual_test.dart`) which stay green as preservation sentinels. No new `integration_test/` scenario, no `classify_path`/dart-define, no device-proof. `/sims` is not involved.

## Acceptance Gates  (literal — copy/paste)
```bash
# 0. Dirty-tree snapshot (do not revert pre-existing new-orbit edits)
git status --short

# 1. RED (BEFORE production edits) — must FAIL with find.byType(ConversationWired)==findsNothing
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name 'accepting a contact request opens the 1:1 conversation for the new contact'
flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name 'accepting a contact request opens the 1:1 conversation'
flutter test test/features/home/presentation/screens/first_time_experience_wired_test.dart --plain-name 'accepting the first request lands on Feed AND opens the new contact chat on top'

# 2. Direct GREEN (AFTER fix) — whole files, all cases incl. guards/preservation
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart
flutter test test/features/feed/presentation/screens/feed_wired_test.dart
flutter test test/features/home/presentation/screens/first_time_experience_wired_test.dart

# 3. Preservation sentinels (must stay green)
flutter test test/features/contact_request/application/contact_request_notification_materializer_test.dart
flutter test test/features/contact_request/application/accept_and_reciprocate_use_case_test.dart
flutter test test/features/contact_request/integration/contact_request_flow_test.dart

# 4. Named curated gates for the touched surfaces
./scripts/run_test_gates.sh feed        # feed_wired_test.dart is in FEED_TESTS
./scripts/run_test_gates.sh groups      # orbit_wired_test.dart is in GROUP_TESTS

# 5. Full host feature gate (globs FTE + everything)
./scripts/run_host_test_gates.sh feature-host-all

# 6. Hygiene
flutter analyze          # 0 new issues
git diff --check
```
Expected: step 1 all FAIL (documented reason); steps 2-5 all pass (0 failures; new cases GREEN, sentinels unchanged); step 6 clean.

## Known-Failure Interpretation
- Expected RED: TC-01/03/06 before the fix (`ConversationWired` not pushed).
- Pre-existing dirty: `new-orbit` has unrelated modified files (211/212 orbit-chrome work, graph regen, etc. per `git status`) — leave them; do not treat as regressions.
- Environment blocker (NOT product): none — host-only, no simulator/device.
- Scope drift (BLOCKING): any failure outside these three test files + the named sentinels, or any change to the introduction feature / the accept use-cases.

## Done Criteria
- [ ] RED added first (TC-01/03/06), failed for `findsNothing` on `ConversationWired`.
- [ ] Mutation-verified: each of the 3 pushes has a documented re-red revert; the 3 guards/preservation cases re-red against a wrong (unconditional / upsert-dropping / mis-ordered) fix.
- [ ] Direct GREEN + preservation sentinels (materializer, accept use-cases, flow) + `feed`/`groups` gates + `feature-host-all` pass.
- [ ] Migration: none (no schema change).
- [ ] OS-boundary/multi-device: N/A (host-only) — justified.
- [ ] Every new test runs in a gate (orbit→groups, feed→feed, FTE→feature-host-all glob) — verified in a gate run.
- [ ] `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violations.

## Scope Guard (hard "Do not")
- Do not modify `ContactRequestNotificationMaterializer` — it already opens the chat (only lock it as a sentinel).
- Do not change `acceptAndReciprocateContactRequest` / `acceptContactRequest` / reciprocal key exchange.
- Do not make the introduction (3-party) accept flow open a chat — different feature, needs mutual acceptance, already has its own "Send message" affordance.
- Do not add navigation to the debug/E2E runners (`intro_e2e_runner`, `smoke_test_runner`).
- Do not convert FTE's `pushReplacement(FeedWired)` into a chat-replace — keep the Feed shell, push the chat on top.

## Accepted Differences / Intentionally Out Of Scope
- Consolidating the three in-app `_acceptRequest` handlers onto a shared `ContactRequestNotificationMaterializer`-style abstraction (DRY) — possible future refactor; here each handler keeps its own surface-specific post-accept side-effects and just gains the chat-open.
- Freshest-avatar timing: the auto-opened chat uses `getContact ?? toContactModel` at accept-time; the profile picture arrives asynchronously via the existing contact-update stream and refreshes `ConversationWired` live (no extra work).

## Dependency Impact
- None outward. This aligns the in-app accept behavior with the already-shipped notification-tap behavior; no contract other surfaces depend on changes.

## Reviewer Findings
(to be filled at review)

## Arbiter Decision
(to be filled at review)

## Final Execution Verdict
(to be filled at execution)
