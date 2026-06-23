# 136 - Consecutive-Message Bubble Grouping for 1:1 & Group Chat  (New Feature / Modification)

Status: awaiting-review
Spec: free-text intent (no formal spec) — design decisions locked with the user 2026-06-21 (see "Locked Design Decisions" below)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-21 | Evidence Collector | letter_card.dart, conversation_screen.dart, group_conversation_screen.dart, conversation_message.dart, group_message.dart, group_membership_timeline_message.dart, group_message_ordering.dart, feed letter_bubble/letter_card_* family, run_test_gates.sh, run_host_test_gates.sh | Architecture mapped via 2 graphify workflows + 5-agent verify→refute; all anchors confirmed on live `new-feed` tree | build matrix |
| 2026-06-21 | Planner | (above) | EXTEND `LetterCard` (feed bubbles not reusable — FeedTokens + 6-param role surface); shared pure run helper under conversation/domain/utils; host-only closure | emit RED catalog + matrix |
| 2026-06-21 | Reviewer (sufficiency) | this plan | Every TC mapped to a tiered, mutation-verifiable test; zero empty matrix cells; no migration/device-proof required (pure UI) | see Reviewer Findings |
| 2026-06-21 | Arbiter | this plan | No structural blockers; avatar-position (top vs bottom of run) defaulted to TOP and recorded as an Accepted Difference | hand off to execution |

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
- Spec / intent: this file + locked design decisions below (memory: `project_chat_bubble_grouping_design_decisions`)
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose) + `scripts/run_host_test_gates.sh`
- Discovery/registration: n/a (no simulator/device scenarios — pure presentation)
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (next-free = 136; index stale, highest on disk = 135)

## Session Classification
implementation-ready (host-only; no DB migration, no Go bridge, no relay, no OS boundary)

## Locked Design Decisions (user-chosen — do NOT re-litigate)
1. **TRUE left/right bubbles** — incoming LEFT-aligned, outgoing RIGHT-aligned, narrower (max-width ~78% of viewport). Authorship moves from the full-width accent-edge styling to **alignment + bubble fill color**.
2. **1:1 drops avatars entirely** (both directions). **Groups** keep ONE avatar + sender name per run, on the **incoming** side only; outgoing never shows an avatar in either surface.
3. **Own runs group too + swipe on ALL** — outgoing consecutive messages also collapse chrome; swipe-to-reply enabled on EVERY balloon in BOTH directions (today: incoming-only). Intentional behavior change.
4. **Run-break rule** — a new run starts when: sender changes, OR a date separator intervenes, OR a system/membership row intervenes, OR the gap from the previous message exceeds **5 minutes** (named constant `kMessageRunGapThreshold`).

## Exact Problem Statement
Every chat message currently renders as a full-width `LetterCard` (`lib/features/conversation/presentation/widgets/letter_card.dart:18`) with the sender avatar + name repeated in a header (`:193-225`) on *every* message. When one sender posts several messages in a row (the common case — see the user's group screenshot: Charlie ×2, Bob ×2, each a full card with a repeated avatar), this wastes vertical space and reads as N disconnected cards rather than one conversation turn. Authorship today is signalled by a full-width accent edge (`:116-187`), not by left/right alignment, so the surface does not read like WhatsApp/Signal.

**What must improve:** consecutive same-sender messages group into a *run*; the avatar/name appears once per run (groups) or never (1:1); each message becomes a narrower, side-aligned **balloon** (incoming left / outgoing right) with stacked corner radii; each balloon remains independently reactable, swipe-to-reply-able (both directions now), and long-pressable.

**What must stay unchanged (→ preserved-green sentinels):** per-balloon reaction targeting by message id; per-balloon long-press context overlay with a correct anchor and a matching lifted snapshot; system/membership rows never absorbed into a run; date separators still break runs; per-message `ValueKey`s and scroll-to-highlight; the Feed surface (uses its own `LetterBubble`/`LetterCard*` widgets — must not regress); the default (flag-less) `LetterCard` render used by `letter_card_test.dart`.

## Root Cause (verify → refute confirmed)
Not a bug — a missing capability. Confirmed on HEAD (`new-feed`):
- `LetterCard` has **no** alignment / max-width / grouping / conditional-header parameter; header `:193-225` is unconditional; alignment is hardcoded full-width via `isIncoming` accent edge `:116-187`; corners are a flat `BorderRadius.circular(24)` (`:103`,`:108`). (verify-letter-card)
- Neither `conversation_screen._buildDisplayItems` (`conversation_screen.dart:621-655`) nor `group_conversation_screen._buildGroupDisplayItems` (`group_conversation_screen.dart:689-710`) does any consecutive-sender run detection; there is **no shared helper** between them; both build forward then `.reversed` (`:654` / `:709`). (verify-assembly)
- Swipe-to-reply is gated `message.isIncoming && !message.isDeleted && onQuoteReply!=null` in 1:1 (`conversation_screen.dart:600-602`) and `!isSent && canWrite && onQuoteReply!=null` in group (`group_conversation_screen.dart:658`) — i.e. outgoing has no swipe today. (verify-assembly)

**Refuted / do-NOT-re-introduce:**
- ✗ "Feed `LetterBubble`/`LetterCardOneToOne/Group/System` are drop-in reusable for conversation." **Refuted** — they use `FeedTokens` (conversation uses `BackgroundReadableColors`), are role-enum-driven, and lack reactions/status/timestamp/edited/deleted/retry/quote/long-press/reaction-tap (≈40 params). They are 100% feed-only (`feed_screen.dart:16-19`); zero usage elsewhere. → **EXTEND `LetterCard`**, keep feed widgets feed-only. (adopt-vs-extend-fork)
- ✗ "`feed_screen.dart:598` is a third base-`LetterCard` call site." **Refuted** — it returns the `LetterCard*` wrappers, not base `LetterCard`. Base `LetterCard` has exactly **two** prod call sites (1:1 + group). (verify-letter-card)
- ✗ "Timestamps are nullable / epoch ints." **Refuted** — `ConversationMessage.timestamp` is a **non-null String (ISO-8601)** (`conversation_message.dart:21`); `GroupMessage.timestamp` is a **non-null DateTime** (`group_message.dart:26`). The shared helper takes `DateTime`; the 1:1 caller parses the String first (the existing parse has a catch→"Today" fallback at `conversation_screen.dart:~825`). (verify-model-inputs)
- ✗ "Group has a system-message branch / renders system rows specially." **Refuted** — group system rows are ordinary `GroupMessage`s with `sys-*` id prefixes rendered as normal `LetterCard`s; only the `id.startsWith('sys-')` prefix distinguishes them. (verify-model-inputs)
- ✗ "`-j1` and `FLUTTER_DEVICE_ID` are required for the 1to1/groups/feed gates." **Refuted** — host gates run parallel, no device id. (test-inventory-and-gates)

## Real Scope
**In scope:**
1. New shared pure helper `lib/features/conversation/domain/utils/message_run_grouping.dart`: `bool messageRunStartsNewRun({...})` + `MessageRunChrome messageRunChrome({...})` + `const kMessageRunGapThreshold = Duration(minutes: 5)`.
2. `LetterCard` (`letter_card.dart`): add OPTIONAL params (defaults preserve current look) — `bubbleLayout` (bool, default `false`), `isFirstInGroup` (bool, default `true`), `isLastInGroup` (bool, default `true`), `showAvatar` (bool, default `true`), `showSenderName` (bool, default `true`). Implement: side-aligned narrow bubble + max-width + position-aware corner radii + conditional header + incoming avatar gutter spacer + continuation `Semantics`, ALL guarded by `bubbleLayout`.
3. `conversation_screen.dart`: add run flags to `_DisplayItem`, compute them in `_buildDisplayItems` (forward, before `.reversed`), thread to `buildLetterCard` with `bubbleLayout: true`, **never** show avatar/name (1:1 decision), enable swipe both directions.
4. `group_conversation_screen.dart`: add run flags to `_GroupDisplayItem`, compute in `_buildGroupDisplayItems` (respecting `sys-` breaks + non-monotonic adjacency), thread to `buildLetterCard` with `bubbleLayout: true`, avatar/name on incoming-first only, enable swipe both directions (keep `canWrite`), build the lifted long-press snapshot with matching flags.

**Out of scope (owner):**
- Feed bubble redesign — owned by 134/135 (`feed_*` widgets); this plan must not touch them.
- Avatar **bottom-of-run** placement (Signal-exact) — defaulted to TOP; see Accepted Differences.
- Timestamp-only-on-last-in-run collapse — keep per-balloon timestamp (default); deferred.
- Any transport/crypto/DB/relay change — none required.

## Files To Inspect Next
Production (entry/use-case, models, helpers):
- `lib/features/conversation/presentation/widgets/letter_card.dart` (ctor `:49-77`; onLongPress `:100-101`; header `:193-225`; accent glow `:116-158`; accent border `:160-187`; radius `:103`,`:108`; body+padding `:265-294`; footer `:370-422`)
- `lib/features/conversation/presentation/screens/conversation_screen.dart` (`_ItemType:982`, `_DisplayItem:984-1014`, `_buildDisplayItems:621-655`, itemBuilder `:412-615`, system `:441-447`, `buildLetterCard:530-576`, long-press Builder `:578-588`, `_AnimatedLetterCard:591-598`/def `:908-980`, swipe `:600-607`, key+padding `:609-613`)
- `lib/features/groups/presentation/screens/group_conversation_screen.dart` (`_GroupItemType:1003`, `_GroupDisplayItem:1006-1018`, `_buildGroupDisplayItems:689-710`, itemBuilder `:551-675`, `buildLetterCard:588-640`, `isSent:558`, long-press Builder `:645-655`, swipe `:658-663`, key+padding `:642-656`, highlight cue `:665-672`)
- `lib/features/conversation/domain/models/conversation_message.dart` (id `:9`, senderPeerId `:15`, timestamp String `:21`, isIncoming `:28`, transport `:56`)
- `lib/features/groups/.../group_message.dart` (id `:8`, senderPeerId `:14`, timestamp DateTime `:26`, parse `:119`)
- `lib/features/groups/application/group_membership_timeline_message.dart` (`sys-*` prefixes `:43,78,125,184,220,251`; senderPeerId==actor)
- `lib/features/groups/application/group_message_ordering.dart` (`orderGroupMessagesForTimeline:15-56`, non-monotonic reply reordering)
Direct tests + integration tests:
- `test/features/conversation/presentation/widgets/letter_card_test.dart`, `.../screens/conversation_screen_test.dart`, `.../screens/conversation_wired_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`, `.../group_conversation_wired_test.dart`
- NEW `test/features/conversation/domain/utils/message_run_grouping_test.dart`
Dependency-only context:
- `lib/features/feed/presentation/widgets/letter_bubble.dart` + `letter_card_one_to_one.dart` / `letter_card_group.dart` / `letter_card_system.dart` (prior-art "SenderRun" grouping — reference only, do NOT reuse)
- `swipe_to_quote_bubble.dart`, `message_context_overlay.dart`, `date_separator.dart`, `intro_system_message.dart`

## Existing Tests Covering This Area
- `letter_card_test.dart` — covers status/reactions/media/deleted/edited render (EXISTS; AUTO-glob). Preservation sentinel for the flag-less default.
- `conversation_screen_test.dart` — message list / compose / attachments / quotes (EXISTS; AUTO-glob).
- `conversation_wired_test.dart` / `conversation_wired_bg_task_test.dart` — integration wiring (EXISTS).
- `group_conversation_screen_test.dart` / `group_conversation_wired_test.dart` / `..._bg_task_test.dart` (EXIST).
- `date_separator_test.dart`, `message_context_overlay_test.dart`, feed `swipe_to_quote_bubble_test.dart` (EXIST).
Missing coverage gaps: **no** run-grouping helper test (file does not exist yet); no bubble-layout / alignment / corner-radius / conditional-header / per-balloon-swipe-both-directions assertions anywhere.
Already in curated family arrays?: `ONE_TO_ONE_TESTS` (42, `run_test_gates.sh:17-60`), `GROUP_TESTS` (11, `:111-123`), `FEED_TESTS` (30, `:62-93`). Confirm during execution that `letter_card_test.dart` + `conversation_screen_test.dart` are in `ONE_TO_ONE_TESTS` and `group_conversation_screen_test.dart` is in `GROUP_TESTS`; **add any missing path**. Host-all auto-globs `test/features/**` (`run_host_test_gates.sh:167`).

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

**Helper unit tests** — NEW `test/features/conversation/domain/utils/message_run_grouping_test.dart`:
1. `messageRunStartsNewRun returns true when sender changes`
   - Tier: unit. Setup: prev senderId="A", current senderId="B", 1-min gap, no separator/system.
   - RED on HEAD: file/function does not exist → compile failure.
   - GREEN asserts: `true`.
   - Mutation re-red: change the sender-comparison branch to `==` → flips RED.
2. `messageRunStartsNewRun returns false for same sender within threshold`
   - prev=current sender, gap = 4 min 59 s. GREEN: `false`. Mutation: invert the gap comparison → RED.
3. `messageRunStartsNewRun breaks at exactly/over 5 minutes` (boundary table 4:59→false, 5:00→true, 5:01→true)
   - GREEN: boundary at `>= kMessageRunGapThreshold`. Mutation: change `>=` to `>` → 5:00 case flips RED.
4. `messageRunStartsNewRun returns true after a date separator` (`prevBreaks=true`)
   - GREEN: `true` even when sender unchanged & gap small. Mutation: drop the `prevBreaks` short-circuit → RED.
5. `messageRunStartsNewRun returns true for/after a system row` (current `isSystemRow=true`, and prev `isSystemRow=true`)
   - GREEN: both directions break. Mutation: ignore `isSystemRow` → RED.
6. `messageRunChrome: group incoming first-in-run shows avatar+name; non-first hides both; outgoing hides both; 1:1 hides both`
   - Tier: unit. Inputs: `surface`, `isOutgoing`, `isFirstInGroup`. GREEN: group∧!outgoing∧first → (avatar true, name true); else both false; 1:1 → both false always. Mutation: drop the `surface==group` guard → 1:1 case flips RED.
7. `messageRunGapThreshold constant equals 5 minutes`
   - GREEN: `kMessageRunGapThreshold == Duration(minutes:5)`. Mutation: change constant → RED.

**LetterCard widget tests** — add to `test/features/conversation/presentation/widgets/letter_card_test.dart`:
8. `bubbleLayout aligns incoming left and outgoing right`
   - Tier: widget. Pump `LetterCard(bubbleLayout:true, isIncoming:true/false)`. RED on HEAD: param doesn't exist → compile failure. GREEN: the bubble's `Align.alignment` is `centerLeft` (incoming) / `centerRight` (outgoing). Mutation: hardcode `centerLeft` → outgoing case RED.
9. `bubbleLayout constrains bubble max width`
   - GREEN: a `ConstrainedBox`/`maxWidth` ≤ ~78% of the pumped width wraps the bubble. Mutation: remove the `ConstrainedBox` → RED.
10. `bubble corner radii stack by first/middle/last per side`
    - GREEN: incoming first → bottom-left squared (`kBubbleStackRadius`), others `kBubbleRadius`; middle → top-left+bottom-left squared; last → top-left squared; mirror for outgoing on the right edge. Mutation: revert corner logic to `circular(24)` → RED.
11. `bubbleLayout with showAvatar=false & showSenderName=false hides header and grows body top padding`
    - GREEN: no `UserAvatar`, no sender-name `Text`; body top padding increased. Mutation: keep header unconditional → RED.
12. `group incoming non-first balloon keeps a left avatar gutter spacer`
    - GREEN: with `bubbleLayout, isIncoming:true, showAvatar:false`, a fixed-width (~42px) leading `SizedBox` spacer is present so the bubble stays aligned under the run's avatar. Mutation: drop the spacer → RED (left edge shifts; assert the SizedBox width).
13. `default (no new flags) renders unchanged full-width card` — **preservation sentinel**
    - GREEN: with no new params, header present, no `Align`, `BorderRadius.circular(24)` intact. Mutation: make `bubbleLayout` default `true` → RED (proves defaults preserve old look).
14. `bubble balloon still fires onLongPress`
    - GREEN: long-press the bubble → callback invoked. Mutation: drop `onLongPress` from the bubble branch → RED.
15. `bubble balloon still fires onReactionTap for its message`
    - GREEN: tapping a rendered reaction chip invokes `onReactionTap` with the chip emoji (reaction targeting intact). Mutation: detach reactions in bubble branch → RED.
16. `chrome-hidden bubble exposes a continuation Semantics label naming the sender`
    - Tier: widget (a11y). GREEN: a `Semantics` label containing the sender name is present even when the visual header is hidden. Mutation: drop the `Semantics` → RED (find by semantics label fails).

**1:1 screen assembly tests** — add to `test/features/conversation/presentation/screens/conversation_screen_test.dart` (and/or `conversation_wired_test.dart`):
17. `1:1 consecutive same-sender incoming messages render no avatar on any balloon`
    - Tier: widget. Two incoming messages, same sender, 1-min apart. GREEN: zero `UserAvatar` in the list (1:1 drops avatars). RED on HEAD: today every card shows an avatar → finds ≥1. Mutation: pass `showAvatar:true` from 1:1 → RED.
18. `1:1 own consecutive messages group (second balloon is not first-in-run)`
    - GREEN: the second outgoing balloon receives `isFirstInGroup:false` (assert via tighter top spacing / squared top corner). Mutation: force `isFirstInGroup:true` always → RED.
19. `1:1 outgoing balloon is now swipe-to-reply enabled and quotes the correct id`  **(behavior change)**
    - Tier: widget. GREEN: an OUTGOING message is wrapped in `SwipeToQuoteBubble`; swiping triggers `onQuoteReply(outgoingMessage.id)`. RED on HEAD: gating `message.isIncoming && …` (`:600-602`) excludes outgoing → no `SwipeToQuoteBubble`, callback never fires. Mutation: revert the gating to incoming-only → RED.
20. `1:1 system message breaks the run` — neighbors around `transport=='system'` are first-in-run
    - GREEN: message after an `IntroSystemMessage` is `isFirstInGroup:true` even if same sender as before it. Mutation: ignore separator/system break in the assembly → RED.
21. `1:1 date separator breaks the run`
    - GREEN: first message after a `DateSeparator` is first-in-run with appropriate top corner. Mutation: drop `prevBreaks` wiring → RED.
22. `1:1 per-message ValueKey('msg-<id>') preserved` — **preservation sentinel**
    - GREEN: each balloon still has `ValueKey('msg-<id>')`. Mutation: hoist key to run level → RED.

**Group screen assembly tests** — add to `test/features/groups/presentation/group_conversation_screen_test.dart` (and/or `group_conversation_wired_test.dart`):
23. `group consecutive same-sender incoming messages show avatar+name once`
    - Tier: widget. Three incoming same-sender messages within threshold. GREEN: exactly ONE `UserAvatar` + ONE sender-name `Text` for the run; balloons 2–3 hide both. RED on HEAD: three avatars + three names. Mutation: pass `showAvatar:true` for non-first → RED.
24. `group outgoing run groups and never shows an avatar`
    - GREEN: outgoing run → zero `UserAvatar`; second balloon `isFirstInGroup:false`. Mutation: show avatar for outgoing → RED.
25. `group system row (sys- prefix) breaks the run and never shows run chrome`
    - GREEN: a `sys-member_joined:` message is its own run (first&last), and the same-`senderPeerId` text message after it is `isFirstInGroup:true`. RED on HEAD: no break logic → it would merge. Mutation: drop the `id.startsWith('sys-')` system detection → RED.
26. `group swipe-to-reply enabled both directions, preserving canWrite`  **(behavior change)**
    - GREEN: an OUTGOING (own) group message with `canWrite:true` is wrapped in `SwipeToQuoteBubble` and quotes its id; with `canWrite:false` no swipe. RED on HEAD: `!isSent && canWrite` excludes own. Mutation: revert gating to `!isSent && canWrite` → outgoing case RED. Distinct-state discriminator: assert swipe present for `(isSent:true, canWrite:true)` AND absent for `(isSent:true, canWrite:false)`.
27. `group run detection uses rendered list adjacency (reply-reordered, non-monotonic)`
    - Tier: widget/integration. Feed messages whose `orderGroupMessagesForTimeline` output interleaves senders (a reply pulled under its parent). GREEN: run flags computed on adjacency-as-rendered (the reordered neighbor breaks/continues the run by position, not by raw timestamp). Mutation: re-sort by timestamp before run detection → RED.
28. `group per-message ValueKey('grp-msg-<id>') + scroll-to-highlight anchor preserved` — **preservation sentinel**
    - GREEN: keys intact; highlight cue still targets the right message. Mutation: hoist key/anchor to run level → RED.
29. `group long-press lifted snapshot built with matching grouping flags`
    - GREEN: the `selectedMessage` `LetterCard` passed to `MessageContextOverlay` carries the SAME `showAvatar`/`isFirstInGroup` as the live balloon (no visual jump). RED on HEAD param-absent; Mutation: build the snapshot with default flags → RED (snapshot shows avatar while live balloon hid it).

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 sender-change break | pure logic | unit | message_run_grouping_test.dart::`...sender changes` | fn absent → compile fail | sender cmp `!=`→`==` | `flutter test test/features/conversation/domain/utils/message_run_grouping_test.dart` | AUTO (glob `test/features/**`); add path to `ONE_TO_ONE_TESTS`+`GROUP_TESTS` |
| TC-02 same-sender continue | pure logic | unit | "::`...within threshold` | fn absent | invert gap cmp | (as above) | AUTO + arrays |
| TC-03 5-min boundary | pure logic | unit | "::`...over 5 minutes` | fn absent | `>=`→`>` | (as above) | AUTO + arrays |
| TC-04 date-separator break | pure logic | unit | "::`...after a date separator` | fn absent | drop `prevBreaks` | (as above) | AUTO + arrays |
| TC-05 system-row break | pure logic | unit | "::`...system row` | fn absent | ignore `isSystemRow` | (as above) | AUTO + arrays |
| TC-06 chrome policy | pure logic | unit | "::`messageRunChrome...` | fn absent | drop `surface==group` guard | (as above) | AUTO + arrays |
| TC-07 threshold constant | pure logic | unit | "::`...equals 5 minutes` | const absent | change constant | (as above) | AUTO + arrays |
| TC-08 alignment | UI/widget | widget | letter_card_test.dart::`...aligns incoming left and outgoing right` | param absent → compile fail | hardcode `centerLeft` | `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart` | AUTO (glob); confirm in `ONE_TO_ONE_TESTS` |
| TC-09 max-width | UI/widget | widget | "::`...constrains bubble max width` | param absent | remove `ConstrainedBox` | (as above) | AUTO; `ONE_TO_ONE_TESTS` |
| TC-10 corner stacking | UI/widget | widget | "::`...corner radii stack...` | param absent | revert to `circular(24)` | (as above) | AUTO; `ONE_TO_ONE_TESTS` |
| TC-11 conditional header | UI/widget | widget | "::`...hides header and grows body top padding` | param absent | header unconditional | (as above) | AUTO; `ONE_TO_ONE_TESTS` |
| TC-12 avatar gutter | UI/widget | widget | "::`...left avatar gutter spacer` | param absent | drop spacer | (as above) | AUTO; `ONE_TO_ONE_TESTS` |
| TC-13 default unchanged | UI/regression | widget | "::`default ... renders unchanged full-width card` | (passes today) | default `bubbleLayout=true` | (as above) | AUTO; `ONE_TO_ONE_TESTS` |
| TC-14 long-press intact | UI/gesture | widget | "::`...still fires onLongPress` | param absent | drop onLongPress in bubble branch | (as above) | AUTO; `ONE_TO_ONE_TESTS` |
| TC-15 reaction targeting | UI/gesture | widget | "::`...still fires onReactionTap...` | param absent | detach reactions in bubble branch | (as above) | AUTO; `ONE_TO_ONE_TESTS` |
| TC-16 a11y continuation | UI/a11y | widget | "::`...continuation Semantics label...` | param absent | drop Semantics | (as above) | AUTO; `ONE_TO_ONE_TESTS` |
| TC-17 1:1 no avatars | UI/assembly | widget | conversation_screen_test.dart::`1:1 ...no avatar on any balloon` | every card shows avatar today | pass `showAvatar:true` | `./scripts/run_test_gates.sh 1to1` | AUTO; confirm path in `ONE_TO_ONE_TESTS` |
| TC-18 1:1 own runs group | UI/assembly | widget | "::`1:1 own consecutive messages group` | no run logic today | force `isFirstInGroup:true` | (as above) | AUTO; `ONE_TO_ONE_TESTS` |
| TC-19 1:1 swipe both dirs | UI/gesture (behavior change) | widget | "::`1:1 outgoing ... swipe-to-reply ... correct id` | gating incoming-only `:600-602` | revert gating to incoming-only | (as above) | AUTO; `ONE_TO_ONE_TESTS` |
| TC-20 1:1 system breaks run | UI/assembly | widget | "::`1:1 system message breaks the run` | no break logic | ignore separator/system break | (as above) | AUTO; `ONE_TO_ONE_TESTS` |
| TC-21 1:1 date sep breaks run | UI/assembly | widget | "::`1:1 date separator breaks the run` | no break logic | drop `prevBreaks` wiring | (as above) | AUTO; `ONE_TO_ONE_TESTS` |
| TC-22 1:1 keys preserved | UI/regression | widget | "::`1:1 per-message ValueKey ... preserved` | (passes today) | hoist key to run level | (as above) | AUTO; `ONE_TO_ONE_TESTS` |
| TC-23 group avatar once | UI/assembly | widget | group_conversation_screen_test.dart::`group ...avatar+name once` | 3 avatars+names today | `showAvatar:true` non-first | `./scripts/run_test_gates.sh groups` | AUTO; confirm path in `GROUP_TESTS` |
| TC-24 group own run no avatar | UI/assembly | widget | "::`group outgoing run ...never shows an avatar` | no run logic | show avatar for outgoing | (as above) | AUTO; `GROUP_TESTS` |
| TC-25 group sys- breaks run | UI/assembly | widget | "::`group system row (sys-) breaks the run...` | no break logic | drop `sys-` detection | (as above) | AUTO; `GROUP_TESTS` |
| TC-26 group swipe both dirs | UI/gesture (behavior change) | widget | "::`group swipe ... both directions, preserving canWrite` | gating `!isSent && canWrite` | revert gating | (as above) | AUTO; `GROUP_TESTS` |
| TC-27 group non-monotonic adjacency | UI/assembly | widget/integration | group_conversation_wired_test.dart::`group run detection uses rendered list adjacency` | no run logic | re-sort by timestamp before detection | (as above) | AUTO; `GROUP_TESTS` |
| TC-28 group keys+highlight | UI/regression | widget | "::`group per-message ValueKey ... + scroll-to-highlight ... preserved` | (passes today) | hoist key/anchor to run level | (as above) | AUTO; `GROUP_TESTS` |
| TC-29 group lifted snapshot | UI/overlay | widget | "::`group long-press lifted snapshot ... matching grouping flags` | param absent | snapshot built with default flags | (as above) | AUTO; `GROUP_TESTS` |

## Invariants (locked by tests)
- INV-1 per-balloon reaction targeting by message id → TC-15.
- INV-2 per-balloon swipe-to-reply BOTH directions, correct id → TC-19, TC-26.
- INV-3 per-balloon long-press + matching lifted snapshot → TC-14, TC-29.
- INV-4 system/membership rows never absorbed into a run → TC-05, TC-20, TC-25.
- INV-5 date separators break runs → TC-04, TC-21.
- INV-6 run detection on rendered list adjacency (non-monotonic safe) → TC-27.
- INV-7 per-message keys + scroll-to-highlight preserved → TC-22, TC-28.
- INV-8 1:1 shows no avatars; groups show avatar/name once per incoming run; outgoing never → TC-06, TC-17, TC-23, TC-24.
- INV-9 flag-less `LetterCard` default render is byte-unchanged → TC-13.
- INV-10 accessibility: chrome-hidden balloons still attribute the sender → TC-16.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. **Snapshot tree:** `git status --short` → record the (large) pre-existing `new-feed` dirty set so unrelated files are never reverted.
2. **RED first — helper:** add `message_run_grouping_test.dart` (TC-01..07); run it → fails to compile (function/const absent). 
3. **Create helper** `lib/features/conversation/domain/utils/message_run_grouping.dart`:
   - `const Duration kMessageRunGapThreshold = Duration(minutes: 5);`
   - `enum MessageRunSurface { oneToOne, group }`
   - `bool messageRunStartsNewRun({required String senderPeerId, required DateTime timestamp, required bool isSystemRow, String? prevSenderPeerId, DateTime? prevTimestamp, required bool prevBreaks, Duration gapThreshold = kMessageRunGapThreshold})` — returns true when `prevSenderPeerId==null || prevBreaks || isSystemRow || prevSenderPeerId!=senderPeerId || prevTimestamp==null || timestamp.difference(prevTimestamp).abs() >= gapThreshold`. (`prevBreaks` is set by the caller when the previous emitted row is a separator OR a system row.)
   - `class MessageRunChrome { final bool showAvatar; final bool showSenderName; }` + `MessageRunChrome messageRunChrome({required MessageRunSurface surface, required bool isOutgoing, required bool isFirstInGroup})` — avatar/name only when `surface==group && !isOutgoing && isFirstInGroup`.
   - Run helper test → GREEN.
4. **RED — LetterCard widget** (TC-08..16) in `letter_card_test.dart`; run → compile-fails on new params.
5. **Extend `LetterCard`** (`letter_card.dart`): add the 5 optional params (`bubbleLayout=false`, `isFirstInGroup=true`, `isLastInGroup=true`, `showAvatar=true`, `showSenderName=true`). Add `const kBubbleRadius=18.0; const kBubbleStackRadius=6.0;`.
   - When `bubbleLayout==false`: **return the exact current tree** (guard so TC-13 stays green).
   - When `bubbleLayout==true`: wrap in `Align(alignment: isIncoming ? centerLeft : centerRight)` + `ConstrainedBox(maxWidth: constraints*0.78)`; replace the full-width accent edge (`:116-187`) with a direction fill color; position-aware `BorderRadius` from `isFirstInGroup`/`isLastInGroup`/`isIncoming`; render header (`:193-225`) only if `showAvatar || showSenderName`, gating avatar by `showAvatar` and name by `showSenderName`; when header hidden, bump body top padding (`:267`); for incoming `bubbleLayout && !showAvatar`, prepend a ~42px `SizedBox` gutter; add a continuation `Semantics(label: senderName)` when the header is hidden. Keep `GestureDetector(onLongPress)`, footer reactions/timestamp/status, and `onReactionTap` wiring inside the bubble branch.
   - Run `letter_card_test.dart` → GREEN; confirm TC-13 still green.
6. **RED — 1:1 assembly** (TC-17..22); run → fail for stated reasons.
7. **Wire 1:1** (`conversation_screen.dart`): add `isFirstInGroup`/`isLastInGroup` (+ derived chrome) fields to `_DisplayItem` (`:984-1014`); in `_buildDisplayItems` (`:621-655`, forward, BEFORE `.reversed`) track previous emitted **message** row + whether a separator/system row intervened (`prevBreaks`), call `messageRunStartsNewRun`, set `isFirstInGroup`; second pass / lookahead sets `isLastInGroup = nextMessageRow.isFirstInGroup || noNextMessageRow`. In `buildLetterCard` (`:530-576`) pass `bubbleLayout:true, isFirstInGroup, isLastInGroup, showAvatar:false, showSenderName:false` (1:1 decision). Change swipe gating (`:600-602`) to drop `isIncoming` (keep `!isDeleted && onQuoteReply!=null`) so OUTGOING balloons get `SwipeToQuoteBubble` too. Keep `transport=='system'`→`IntroSystemMessage` path (`:441-447`) and per-message key (`:609-613`) unchanged. Run → GREEN.
8. **RED — group assembly** (TC-23..29); run → fail.
9. **Wire group** (`group_conversation_screen.dart`): mirror step 7 on `_GroupDisplayItem` (`:1006-1018`) + `_buildGroupDisplayItems` (`:689-710`); compute `isSystemRow = message.id.startsWith('sys-')` and force it to break (`prevBreaks` for the next row, and the system row itself is first&last with no chrome). In `buildLetterCard` (`:588-640`) pass `bubbleLayout:true, isFirstInGroup, isLastInGroup` + `messageRunChrome(surface: group, isOutgoing: isSent, isFirstInGroup)` for `showAvatar`/`showSenderName`. Change swipe gating (`:658`) from `!isSent && canWrite` to `canWrite && !isDeleted && onQuoteReply!=null` (both directions, keep `canWrite`). Build the long-press lifted snapshot (`:645-655`) with the SAME flags (TC-29). Keep `grp-msg-<id>` key + highlight cue. Run → GREEN.
   - Stop-if: any required-param compile break at the Feed wrappers → STOP; the params must be optional (Feed must not need changes). Replan, do not hack.
10. **Rerun** direct → preservation → named gates (below). `flutter analyze` 0 new; `git diff --check`.

## Risks And Edge Cases
- **Reversed-list off-by-one** — compute run flags in the FORWARD list before `.reversed` (`:654`/`:709`); the "previous message" is the prior forward message row, the "next" is the following one → pinned by TC-18/TC-20/TC-23.
- **Non-monotonic group order** — `orderGroupMessagesForTimeline` reorders replies (`group_message_ordering.dart:33-41`); detect on adjacency-as-rendered, never re-sort → TC-27.
- **`sys-` rows share senderPeerId with the joiner** → would merge without explicit `id.startsWith('sys-')` break → TC-25.
- **Lifted long-press snapshot jump** — snapshot must mirror live flags → TC-29.
- **1:1 timestamp parse** — `ConversationMessage.timestamp` is a String; reuse the existing parse (catch→"Today" `:~825`); if parse fails, treat the gap as a break (fail-safe = show chrome) — assert in helper test path.
- **Feed regression** — Feed uses `LetterBubble`/wrappers, not base `LetterCard`; new params are optional → Feed untouched (preservation gate `feed`).
- **Rollback** — no feature flag; the natural rollback is to stop passing `bubbleLayout:true` (defaults restore the old full-width card). Recorded as Accepted Difference.

## Device/Relay Proof Profile
**host-only for closure.** Pure presentation — no transport, crypto, DB migration, or OS boundary, so the tier matrix requires no simulator/device-proof. Closure = host widget + unit gates below.
Non-gated visual confirmation (recommended, not a gate): run the app and eyeball a multi-message run in both 1:1 and a group (e.g. `/run` or `/verify`), or capture a screenshot, to confirm the WhatsApp/Signal look.

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# 0. Snapshot dirty tree (do NOT revert unrelated new-feed changes)
git status --short > /tmp/136_pre.txt

# 1. RED (before production edits) — must FAIL for the documented reason
flutter test test/features/conversation/domain/utils/message_run_grouping_test.dart            # compile-fail: helper absent
flutter test test/features/conversation/presentation/widgets/letter_card_test.dart             # compile-fail: new params absent
flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart     # new 1:1 cases fail
flutter test test/features/groups/presentation/group_conversation_screen_test.dart             # new group cases fail

# 2. Direct GREEN (after fix)
flutter test test/features/conversation/domain/utils/message_run_grouping_test.dart
flutter test test/features/conversation/presentation/widgets/letter_card_test.dart
flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart
flutter test test/features/groups/presentation/group_conversation_screen_test.dart

# 3. Named curated gates (preservation + new) — expect prior counts + the new tests, 0 regressions
./scripts/run_test_gates.sh 1to1          # was 42 host tests → expect 42 + new, all pass
./scripts/run_test_gates.sh groups        # was 11 host tests → expect 11 + new, all pass
./scripts/run_test_gates.sh feed          # 30/30 UNCHANGED (no Feed edits — pure preservation)

# 4. Full host floor (auto-glob catches the new helper + widget tests)
./scripts/run_host_test_gates.sh feature-host-all     # 0 regressions vs pre-change baseline

# 5. Hygiene
flutter analyze            # 0 new issues
git diff --check
```
Registration note: after adding the new test files/cases, confirm `letter_card_test.dart` + `conversation_screen_test.dart` are in `ONE_TO_ONE_TESTS` and `group_conversation_screen_test.dart` is in `GROUP_TESTS` in `scripts/run_test_gates.sh`; add the new `message_run_grouping_test.dart` path to both `ONE_TO_ONE_TESTS` and `GROUP_TESTS`. (All are also auto-globbed by `feature-host-all`.)

## Known-Failure Interpretation
- Expected RED: the four §RED commands before the fix (helper/param absent; 1:1+group new cases).
- Pre-existing dirty: the large uncommitted `new-feed` tree (feed redesign 134/135, graphify-arch artifacts) — leave untouched; not this plan's.
- Environment blocker (NOT product): none expected (host-only).
- Scope drift (BLOCKING): any failure in the `feed` gate, any required-param break at a Feed wrapper, or any change to transport/DB/crypto.

## Done Criteria
- [ ] RED added first, failed for the expected reason (helper/param absent; gating incoming-only; no run logic).
- [ ] Mutation-verified — each fix has the named re-red revert (matrix column).
- [ ] Direct GREEN + `1to1`/`groups` gates + `feed` preservation + `feature-host-all` all pass, 0 regressions.
- [ ] No DB migration (confirmed pure UI); no device-proof required (confirmed no boundary).
- [ ] Every new test auto-globbed AND present in its curated family array; verified by a gate run.
- [ ] `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violations.
- [ ] (Recommended) visual confirmation in-app for a multi-message run in 1:1 + group.

## Scope Guard (hard "Do not")
- Do NOT edit any `lib/features/feed/**` widget (134/135 own the Feed bubbles).
- Do NOT rename/remove the existing `isIncoming` param or change the flag-less default render (TC-13 locks it).
- Do NOT make any new `LetterCard` param required (Feed wrappers + `letter_card_test` must compile unchanged).
- Do NOT touch transport/DB/crypto/relay/Go bridge — none are needed.
- Do NOT re-sort group messages for run detection (use rendered adjacency).

## Accepted Differences / Intentionally Out Of Scope
- **Avatar at TOP of the run** (first balloon), not Signal's bottom-of-run. Simpler with `reverse:true` and matches the existing header-at-top layout; flip later by attaching `showAvatar` to `isLastInGroup`.
- **Per-balloon timestamp** kept (not collapsed to last-in-run). Deferred — needs an extra flag.
- **No feature flag** — rollback is to stop passing `bubbleLayout:true` (defaults restore the card look).
- **Tail/notch on bubbles** not drawn (rounded-rect stacking only).

## Dependency Impact
- None downstream. This is a leaf presentation change; the new helper is additive and self-contained under `conversation/domain/utils`.

## Reviewer Findings
Sufficiency PASS: every TC-ID has ≥1 tiered row; every INV-* is locked; every production edit has a named re-red mutation; RED reasons are concrete (compile-fail for new params/helper, or the live gating/missing-run-logic); the shared-result discriminator is asserted for swipe gating (TC-26: present for `canWrite:true` AND absent for `canWrite:false`); preservation sentinels (TC-13/22/28 + `feed` gate) are named with commands; matrix has zero empty cells in tier/mutation/gate/registration. No migration row required (verified pure UI — no `DB v##`); no OS-boundary/crypto/multi-device row required (verified). Thin-evidence note: exact membership of `letter_card_test.dart`/`conversation_screen_test.dart`/`group_conversation_screen_test.dart` in the curated arrays is to be confirmed at execution (registration note + step covers add-if-missing).

## Arbiter Decision
Structural blockers: none. Deferred details: avatar bottom-of-run, timestamp collapse, bubble tails (Accepted Differences). Accepted differences: TOP avatar, no flag, per-balloon timestamp. Hand off to execution: start at Acceptance Gate step 1 (RED), implement steps 3/5/7/9, then gates.

## Final Execution Verdict
Verdict: (pending execution) | Files changed: … | Tests run (+counts): … | Blocking: … | QA verdict: … | Non-blocking follow-ups (owner): …
