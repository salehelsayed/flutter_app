# 155 - 1:1 transport status glyph — OUTGOING + INCOMING (relay/direct/wifi/inbox), group keeps v1  (Modification — UI)

Status: awaiting-review (v1 status-glyph already landed; this plan is the transport v2 + incoming extension)
Spec: free-text intent (no formal spec) — owner: on **1:1** chats the inline status glyph should reflect the **transport** a message travelled (relay→cell_tower, direct→device_hub, wifi→wifi, inbox→inbox), for the user's own **outgoing** messages AND **received** (incoming) messages; the delivered ✓✓ stays hidden (status `delivered` preserved in the model). **1:1 ONLY — group keeps the already-shipped v1 status glyph.**

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-23 | Evidence Collector | letter_card.dart (_statusIcon 1014-1034 [v1 landed], _transportIcon 996-1012, inline gates 583/635 icons 590/642, ctor 40-144, header 318-326), conversation_screen.dart (LetterCard 540-579, status :578 transport :579, system :473/:701, header hidden :573-577/:686), group_conversation_screen.dart (647-690: status :673, NO transport), handle_incoming_chat_message_use_case.dart (:504/:506), inbox_staging_entry.dart (:103 transport 'inbox'), letter_card_test.dart (:18/:23/:58/:192-198) | v1 (`_statusIcon`→inbox_rounded, done_all retired) ALREADY committed + UNCONDITIONAL (1:1+group); `transportStatusGlyph` does NOT exist; incoming carries real transport; offline-relay incoming = `'inbox'`→Icons.inbox NOT cell_tower | Build matrix |
| 2026-06-23 | Planner | tier-matrix.md, plan-template.md | ADDITIVE: new `transportStatusGlyph` (default false) + transport-aware OUTGOING resolver + NEW INCOMING branch; 1:1 opts in, group keeps v1. 21 TCs (all widget/host). Files already in `ONE_TO_ONE_TESTS`+group arrays → AUTO | Emit plan |
| 2026-06-23 | Reviewer (sufficiency) | sufficiency-checklist.md | zero-empty-cell matrix; 1:1-only locked by group-preservation (now v1 baseline) + screen-wiring tests; blind-spot sweep run (single renderer, header hidden in 1:1, pure render of persisted status+transport) | — |
| 2026-06-23 | Arbiter | — | host-only; no device/sim; no migration; offline-relay→inbox-glyph documented as accepted | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-06-23 | contract extraction | git status --short | baseline letter_card 87, conversation_screen 70 | scope confirmed; v1 found UNCOMMITTED not committed (HEAD letter_card still returns done_all) | RED |
| 2026-06-23 | l10n + RED tests added | 3 arb + gen-l10n; letter_card_test.dart (+18 TC), conversation_screen_test.dart (TC-19) | `155 transport status glyph` → +6 -12 (12 RED for expected reasons; TC-07/12-15/18 green-on-HEAD) | RED confirmed | impl |
| 2026-06-23 | implementation | letter_card.dart (param+`_showsIncomingTransportGlyph`+`_resolvedStatusIcon/Semantic`+incoming branch ×2 gates); conversation_screen.dart (`transportStatusGlyph: true`) | direct files green: letter_card 105, conversation_screen 71 | scoped; TC-17 needed RegExp semantics match (bubble merges labels) | mutation |
| 2026-06-23 | mutation pass | (5 transient reverts) | M1 outgoing-reached fallthrough→TC-01/04 RED; M2 incoming-branch-off→6 RED; M3 drop !=unknown→TC-13 RED; M4 ignore-flag→TC-18 RED; M5 screen flag false→TC-19 RED | all re-red, reverted | preservation/gates |
| 2026-06-23 | wired-test fallout (v1+v2) | conversation_wired_test.dart (6 tests) | sending→clock, delivered/inboxed null→done_rounded, inbox-transport→Icons.inbox; wired 96 green | **scope+1 file**: v1 (uncommitted) left these red; v2 changes same surface → updated to final behavior | gates |
| 2026-06-23 | named gates (1to1 + groups) | — | **1to1 +1190 ALL PASS**; groups +687 -2 (2 pre-existing media: MissingPluginException audio + image-refresh count, NOT status-glyph) | gates green (groups 2 pre-existing per memory baseline) | QA |
| 2026-06-23 | QA (hygiene) | — | delivered_status_minting green; analyze 0-new (2 pre-existing); git diff --check clean | blocking: none | ship |

## Source Of Truth
- Spec / intent: inline below (owner request + screenshots).
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose)
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh` (NOT used — no sim/device rows)
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (this UPDATES 155; no new number)

## Session Classification
implementation-ready

---

## Current State (HEAD baseline — read first)
**v1 of 155 already landed (committed `e1d2edae`) and is UNCONDITIONAL (1:1 AND group):** `_statusIcon` (`letter_card.dart:1014-1034`) returns `Icons.inbox_rounded` for `delivered`/`queued`/`inboxed` (the two-tick `done_all` is RETIRED), `Icons.error_outline_rounded` for `failed`/`send_failed`, `Icons.schedule_rounded` for `pending` only, `Icons.done_rounded` default; `_statusColor` neutral for reached, amber for pending; `_statusSemantic` → `message_status_inbox` for reached. `transportStatusGlyph` does **not** exist (0 hits). So today every reached message (1:1 + group, outgoing) shows the **same inbox glyph**, and incoming shows **no** glyph. This plan ADDS a transport-aware path for 1:1 only and leaves group on v1.

## Exact Problem Statement
On 1:1 the inline status glyph is the same `inbox_rounded` for every reached message and the user has no signal for *how* a message travelled. The owner wants, **1:1 only**, the inline glyph to show the **transport** (via the existing `_transportIcon`): for their **own outgoing** messages (relay/direct/wifi/inbox) AND for **received** messages (the channel it arrived on). The ✓✓ stays hidden (already retired in v1; the transport path also never draws it). The `delivered` status + receipt logic (146) are untouched.

**What must improve (1:1 only, behind a new `transportStatusGlyph` opt-in):**
- OUTGOING reached (`sent`/`delivered`/`inboxed`/`queued`) → `_transportIcon(transport)`: `relay`→`Icons.cell_tower`, `direct`→`Icons.device_hub`, `wifi`→`Icons.wifi`, `inbox`→`Icons.inbox`; in-flight (`pending`/`sending`) → clock; `failed`/`send_failed` → error; reached-with-null-transport → single-check fallback; never `done_all`.
- INCOMING → `_transportIcon(transport)` for `inbox`/`direct`/`relay`/`wifi`; nothing for null/`unknown`/`system`/deleted. Incoming has no status states (model `delivered`, screen forces status null), so the incoming glyph is **transport-or-nothing**.

**What must stay unchanged (→ preserved-green sentinels):** GROUP and legacy keep the already-live **v1** `_statusIcon` (reached → `inbox_rounded`, NO transport glyph, NO ✓✓) — the change is gated behind `transportStatusGlyph`, set only by the 1:1 screen. The header transport icon (`:318-326`, hidden in 1:1) is untouched. Message status enum/strings, send/receive use-cases, delivery-receipt logic (146), DB, wire, and `inbox_staging_entry.dart:103`'s `'inbox'` transport are untouched — render-only, read-only consumer of `transport`. `delivered` still minted.

## Root Cause / Evidence (verified)
- `_transportIcon` (`letter_card.dart:996-1012`) already maps `wifi`/`local`→`Icons.wifi`, `direct`/`reuse`→`Icons.device_hub`, `relay`→`Icons.cell_tower`, `inbox`→`Icons.inbox`, default→`Icons.help_outline`.
- Inline status glyph at TWO gates, both `if (!isIncoming && status != null)`: footer-meta `:583` (Icon `:590`, deleted/media-only path) and 137 `_InlineMetaWidgetSpan` `:635` (Icon `:642`, normal-text path; 1:1 uses `bubbleLayout`).
- 1:1 `conversation_screen.dart`: `status: message.isIncoming ? null : message.status` (`:578`), `transport: message.transport` UNCONDITIONAL incl. incoming (`:579`), `showAvatar:false`+`showSenderName:false` (`:573-577`) → header hidden (`:686`). 1:1 system rows are `transport == 'system'` (`:473`, `:701`).
- Group `group_conversation_screen.dart:673`: `status: isSent ? message.status : null`, **no `transport:`** → group LetterCard gets `transport: null` and never sets the flag → the new branch is doubly inert for group.
- INCOMING transport persisted at `handle_incoming_chat_message_use_case.dart:506` (`transport: transport`), `status: 'delivered'` (`:504`), durable + re-read. Enumerated values: **offline relay-inbox drain → `'inbox'`** (`inbox_staging_entry.dart:103`, hardcoded) → `Icons.inbox`; **live direct → `'direct'`**; **live relay-circuit → `'relay'`**; **LAN → `'wifi'`** (never 'lan'/'local'); defensive **`'unknown'`** → help_outline (rare). The `direct:`/`lan:` staged-entry-id prefix does NOT change transport.

Refuted / do-NOT-re-introduce:
- "`avatarOutsideBubble` gates 1:1" — **rejected** (false for outgoing group rows too). Use the explicit `transportStatusGlyph`.
- "Edit `inbox_staging_entry.dart:103` so offline-relay incoming shows cell_tower" — **rejected**: `'inbox'` transport is load-bearing for `deliveryReceiptMintDecision` (`handle_incoming…:105-121`) + retry/send paths. The glyph is read-only; offline-relay → inbox glyph is the correct "received-while-away" indicator (Accepted Difference).
- "Group still shows ✓✓" — **false now**: v1 already retired ✓✓ group-wide; group baseline is `inbox_rounded`. (Supersedes the prior 155 TC-09.)
- "Show on incoming via the existing status block" — **rejected**: incoming `status` is forced null by the screen, so a status-gated glyph can never fire for incoming → drive the incoming glyph off `transport` in a separate branch.

## Real Scope
**In scope (render-only, additive):**
- `letter_card.dart`: add `final bool transportStatusGlyph;` (default **false**) to ctor (`:108-144`).
- OUTGOING: at the two existing gates (`:583`,`:635`) choose the icon/color/semantic via a transport-aware resolver when `transportStatusGlyph`, else the v1 `_statusIcon`/`_statusColor`/`_statusSemantic` (group/legacy). Resolver: failed→error; pending/sending→schedule; reached→`_transportIcon(transport)` or `done_rounded` if transport null; never done_all.
- INCOMING: add a SEPARATE conditional at each of the two sites, appended after the existing block:
  `if (transportStatusGlyph && isIncoming && transport != null && !isDeleted && transport != 'system' && transport != 'unknown') ...[ SizedBox(width:4), Semantics(label: <"received via X">, child: Icon(_transportIcon(transport!), size:14, color: readableColors.textMuted)) ]`. Use an `Icon` (not Text) in the inline variant (137 U+FFFC concern). Gate on `isIncoming` so outgoing (handled by the existing block) never double-renders.
- `conversation_screen.dart:540-579` (1:1): pass `transportStatusGlyph: true`. Group untouched.
- l10n: outgoing `message_sent_via_relay`/`_direct`/`_wifi`/`_inbox` and incoming `message_received_via_relay`/`_direct`/`_wifi`/`_inbox` (or one parameterized pair) in en/ar/de; `flutter gen-l10n`.

**Out of scope:** GROUP rendering (keeps v1); the header transport icon; message status/transitions, send/receive, 146 receipt logic, DB/wire, `inbox_staging_entry.dart`; a future user-visible read receipt; making offline-relay incoming show a per-link icon.

## Files To Inspect Next
Production: `letter_card.dart` (ctor 40-144; gates 583/635, icons 590/642; `_statusIcon` 1014-1034, `_transportIcon` 996-1012, `_statusColor` 1036-1058, `_statusSemantic` 1060+); `conversation_screen.dart` (540-579); `lib/l10n/app_en.arb`/`app_ar.arb`/`app_de.arb`.
Direct tests: `letter_card_test.dart` (`buildTestWidget` :18/:23/:58 — add `transportStatusGlyph`; incoming "no delivery note" :192-198 STAYS GREEN); `conversation_screen_test.dart` (wiring).
Preservation: `delivered_status_minting_sites_test.dart`; the `groups` gate.

## Existing Tests Covering This Area
- `letter_card_test.dart` (in `ONE_TO_ONE_TESTS:61` + group `:129`) — status cases run with the flag DEFAULT FALSE → now exercise the **group/v1** path and STAY GREEN (delivered→inbox_rounded, etc.). Incoming "does not show delivery note" (`:192-198`, no flag/no transport) stays green (new glyphs distinct). `buildTestWidget` lacks `transportStatusGlyph` → add it.
- `conversation_screen_test.dart` (in `ONE_TO_ONE_TESTS:62`) — add the wiring lock.
- `delivered_status_minting_sites_test.dart` (in `ONE_TO_ONE_TESTS`) — delivered still minted.
Missing coverage gaps: the entire `transportStatusGlyph` path (outgoing transport glyphs + incoming transport glyphs + negatives), the 1:1-screen wiring, the group-on-v1 scoping lock.
Already in curated family arrays?: yes — all target files. No array edit.

---

## RED Test Catalog  (add BEFORE production code — INV-RED-FIRST). All `letter_card_test.dart` unless noted, via `buildTestWidget(transportStatusGlyph: true, …)`.

### OUTGOING (1:1, transportStatusGlyph: true)
1. `::1:1 outgoing reached via 'relay' → cell_tower (not inbox_rounded, not done_all)` — `isIncoming:false, status:'delivered', transport:'relay'`; assert `Icons.cell_tower` findsOne; `Icons.inbox_rounded`/`Icons.done_all_rounded` findsNothing. RED: param absent / v1 shows inbox_rounded. Mutation: fall through to `_statusIcon` for reached → inbox_rounded → re-red.
2. `::1:1 outgoing 'direct' → device_hub` — `status:'sent', transport:'direct'`; `Icons.device_hub` findsOne. RED: param absent. Mutation: ignore transport → re-red.
3. `::1:1 outgoing 'wifi' → wifi` — `status:'delivered', transport:'wifi'`; `Icons.wifi` findsOne. RED: param absent. Mutation: map wifi elsewhere → re-red.
4. `::1:1 outgoing 'inbox' → inbox glyph` — `status:'inboxed', transport:'inbox'`; `Icons.inbox` findsOne; `Icons.schedule_rounded` findsNothing. RED: param absent / v1 inboxed→inbox_rounded (rounded). Mutation: inboxed→schedule in transport path → re-red.
5. `::1:1 outgoing reached + null transport → single check fallback` — `status:'delivered', transport:null`; `Icons.done_rounded` findsOne; `Icons.help_outline`/`Icons.done_all_rounded` findsNothing. RED: param absent. Mutation: fallback to help_outline/done_all → re-red.
6. `::1:1 outgoing in-flight pending/sending → clock` — `status:'pending', transport:'relay'` (+`'sending'`); `Icons.schedule_rounded` findsOne; `Icons.cell_tower` findsNothing. RED: param absent. Mutation: show transport for pending → re-red.
7. `::1:1 outgoing failed/send_failed → error` — `status:'failed', transport:'relay'`; `Icons.error_outline_rounded` findsOne. RED: param absent. Mutation: drop failed branch → re-red.

### INCOMING (1:1, transportStatusGlyph: true) — `isIncoming:true, status:null`
8. `::1:1 incoming via 'inbox' → inbox glyph (the offline "arrived while away" case)` — `transport:'inbox'`; `Icons.inbox` findsOne. RED: param absent / incoming shows nothing today. Mutation: drop the incoming branch → re-red.
9. `::1:1 incoming 'direct' → device_hub` — `transport:'direct'`; `Icons.device_hub` findsOne. RED: param absent. Mutation: gate incoming branch off → re-red.
10. `::1:1 incoming 'relay' → cell_tower` — `transport:'relay'`; `Icons.cell_tower` findsOne. RED: param absent. Mutation: drop branch → re-red.
11. `::1:1 incoming 'wifi' → wifi` — `transport:'wifi'`; `Icons.wifi` findsOne. RED: param absent. Mutation: drop branch → re-red.
12. `::1:1 incoming null transport → no glyph` — `transport:null`; no transport glyph (assert `Icons.inbox`/`cell_tower`/`device_hub`/`wifi` all findsNothing). RED: param absent (after scaffold locks the `transport != null` guard). Mutation: render for null → re-red.
13. `::1:1 incoming 'unknown' → no glyph (not help_outline)` — `transport:'unknown'`; `Icons.help_outline` findsNothing. RED: param absent. Mutation: drop the `!= 'unknown'` guard → help_outline appears → re-red.
14. `::1:1 incoming 'system' → no glyph` — `transport:'system'`; no glyph. RED: param absent. Mutation: drop the `!= 'system'` guard → re-red.
15. `::1:1 incoming deleted row → no glyph` — `isIncoming:true, isDeleted:true, transport:'relay'`; no transport glyph. RED: param absent. Mutation: drop the `!isDeleted` guard → re-red.
16. `::1:1 incoming transport glyph renders in BOTH footer and inline variants` — drive the inline (normal text) and footer (media-only/deleted-empty) paths with `transport:'relay'`; both show `Icons.cell_tower`. RED: param absent / only one site branched. Mutation: add the branch to one site only → re-red on the other.

### a11y / scoping / preservation
17. `::1:1 incoming uses "received via X" a11y label; outgoing uses "sent via X"` — incoming `transport:'relay'` → `message_received_via_relay`; outgoing `status:'delivered', transport:'relay'` → `message_sent_via_relay`; assert distinct, not `message_status_inbox`. RED: new l10n keys absent (compile). Mutation: reuse one key both ways / revert → re-red.
18. `::GROUP/legacy (flag false) keeps v1 — reached → inbox_rounded, NOT transport glyph, NOT done_all; incoming → nothing` — `buildTestWidget(isIncoming:false, status:'delivered')` (flag omitted) → `Icons.inbox_rounded` findsOne, `Icons.cell_tower` findsNothing; `isIncoming:true, transport:'relay'` (flag omitted) → no transport glyph. RED: n/a (HEAD green = v1). **Scoping lock.** Mutation: make the transport branches unconditional (ignore the flag) → group delivered shows cell_tower / group incoming shows glyph → re-red.
19. `conversation_screen_test.dart::1:1 conversation passes transportStatusGlyph: true` — pump 1:1 with an outgoing `delivered`/`transport:'relay'` message; assert `Icons.cell_tower` rendered (screen opted in). RED: screen omits the param → v1 inbox_rounded shows, cell_tower findsNothing. Mutation: remove `transportStatusGlyph: true` from `conversation_screen.dart` → re-red. Registration: `ONE_TO_ONE_TESTS:62`.
20. `letter_card_test.dart::(existing) incoming "does not show delivery note" still green` — `:192-198`, no flag/no transport → no glyph. Preservation (unedited). Mutation: n/a.
21. `delivered_status_minting_sites_test.dart::(existing) delivered still minted` — render-only guarantee; green-on-HEAD lock. Mutation: any transition edit → reds → scope stop.

## Test Coverage Matrix  (ZERO empty cells)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 out relay | transport render | widget | letter_card_test.dart::outgoing relay → cell_tower | param absent / v1 inbox_rounded | fall through to _statusIcon | `./scripts/run_test_gates.sh 1to1` | AUTO + `ONE_TO_ONE_TESTS`(:61)+group(:129) |
| TC-02 out direct | transport render | widget | letter_card_test.dart::outgoing direct → device_hub | param absent | ignore transport | `./scripts/run_test_gates.sh 1to1` | AUTO + arrays |
| TC-03 out wifi | transport render | widget | letter_card_test.dart::outgoing wifi → wifi | param absent | map wifi elsewhere | `./scripts/run_test_gates.sh 1to1` | AUTO + arrays |
| TC-04 out inbox | transport render | widget | letter_card_test.dart::outgoing inbox → inbox | param absent / v1 inbox_rounded | inboxed→schedule | `./scripts/run_test_gates.sh 1to1` | AUTO + arrays |
| TC-05 out null fallback | render fallback | widget | letter_card_test.dart::outgoing null transport → single check | param absent | help_outline/done_all | `./scripts/run_test_gates.sh 1to1` | AUTO + arrays |
| TC-06 out in-flight | render mapping | widget | letter_card_test.dart::outgoing pending/sending → clock | param absent | transport for pending | `./scripts/run_test_gates.sh 1to1` | AUTO + arrays |
| TC-07 out failed | render mapping | widget | letter_card_test.dart::outgoing failed → error | param absent | drop failed branch | `./scripts/run_test_gates.sh 1to1` | AUTO + arrays |
| TC-08 in inbox | transport render | widget | letter_card_test.dart::incoming inbox → inbox | param absent / incoming shows nothing | drop incoming branch | `./scripts/run_test_gates.sh 1to1` | AUTO + arrays |
| TC-09 in direct | transport render | widget | letter_card_test.dart::incoming direct → device_hub | param absent | gate branch off | `./scripts/run_test_gates.sh 1to1` | AUTO + arrays |
| TC-10 in relay | transport render | widget | letter_card_test.dart::incoming relay → cell_tower | param absent | drop branch | `./scripts/run_test_gates.sh 1to1` | AUTO + arrays |
| TC-11 in wifi | transport render | widget | letter_card_test.dart::incoming wifi → wifi | param absent | drop branch | `./scripts/run_test_gates.sh 1to1` | AUTO + arrays |
| TC-12 in null | render guard | widget | letter_card_test.dart::incoming null → no glyph | param absent | render for null | `./scripts/run_test_gates.sh 1to1` | AUTO + arrays |
| TC-13 in unknown | render guard | widget | letter_card_test.dart::incoming unknown → no glyph | param absent | drop !=unknown guard | `./scripts/run_test_gates.sh 1to1` | AUTO + arrays |
| TC-14 in system | render guard | widget | letter_card_test.dart::incoming system → no glyph | param absent | drop !=system guard | `./scripts/run_test_gates.sh 1to1` | AUTO + arrays |
| TC-15 in deleted | render guard | widget | letter_card_test.dart::incoming deleted → no glyph | param absent | drop !isDeleted guard | `./scripts/run_test_gates.sh 1to1` | AUTO + arrays |
| TC-16 in both variants | render coverage | widget | letter_card_test.dart::incoming glyph in footer+inline | param absent / one site only | branch one site only | `./scripts/run_test_gates.sh 1to1` | AUTO + arrays |
| TC-17 a11y labels | a11y/l10n | widget | letter_card_test.dart::received-via vs sent-via labels | new l10n keys absent | reuse one key both ways | `./scripts/run_test_gates.sh 1to1` | AUTO + arrays |
| TC-18 group on v1 | 1:1-only scoping lock | widget | letter_card_test.dart::group reached→inbox_rounded, incoming→nothing | n/a (HEAD green = v1) | make branches unconditional | `./scripts/run_test_gates.sh groups` | AUTO + group array(:129) |
| TC-19 1:1 screen wiring | source-wiring | widget | conversation_screen_test.dart::passes transportStatusGlyph true | screen omits param → v1 inbox_rounded | remove the param from screen | `./scripts/run_test_gates.sh 1to1` | AUTO + `ONE_TO_ONE_TESTS`(:62) |
| TC-20 incoming-none preserved | preservation | widget | letter_card_test.dart::(existing :192-198) no flag → no glyph | n/a (HEAD green) | n/a | `./scripts/run_test_gates.sh 1to1` | AUTO + arrays |
| TC-21 delivered minted | no-behavior-change | unit/app | delivered_status_minting_sites_test.dart::(existing) | n/a (HEAD green) | any transition edit → reds (scope stop) | `./scripts/run_test_gates.sh 1to1` | AUTO + `ONE_TO_ONE_TESTS` |

## Invariants (locked by tests)
- INV-1: 1:1 OUTGOING reached → `_transportIcon` glyph; in-flight → clock; failed → error; null → single-check; never done_all → TC-01..07.
- INV-2: 1:1 INCOMING → `_transportIcon` glyph for inbox/direct/relay/wifi; nothing for null/unknown/system/deleted → TC-08..16.
- INV-3: incoming glyph renders in BOTH render variants → TC-16.
- INV-4: a11y distinguishes received-via / sent-via → TC-17.
- INV-5 (scoping): GROUP/legacy stays on v1 (`inbox_rounded`, no transport glyph, no ✓✓); incoming group shows nothing — gated by `transportStatusGlyph`, set only by 1:1 → TC-18, TC-19.
- INV-6 (no-behavior-change): `delivered` still minted; `'inbox'` transport untouched; no status/transition/DB/wire change → TC-21 + diff confined to `letter_card.dart` + `conversation_screen.dart` + l10n.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row.

## Blind-Spot Sweep (evergreen classes)
- **Sibling-surface consistency:** `LetterCard` is the SOLE per-message status renderer; the header transport icon (`:318-326`) is HIDDEN in 1:1 (`conversation_screen.dart:573-577/:686`) → no double indicator. Group keeps v1 and is proven by the `groups` gate (TC-18). The feed `caught_up_empty_state.dart` `done_all` is decorative, untouched.
- **Lifecycle / derived-state durability:** glyph is a PURE function of persisted `status`+`transport`; reopen/restart re-renders identically; no new persisted state → **N/A (justified)**.
- **Destructive-action side-effects:** **N/A** — render-only.
- **Invariant re-verification under new transitions:** v1's "done_all retired" holds (transport path never draws done_all); offline-relay → inbox glyph documented (Accepted Difference) → TC-08, TC-18.

## Step-By-Step Implementation Plan
1. **RED first.** Add `transportStatusGlyph` to `buildTestWidget`; add TC-01..17, TC-19; TC-18/20/21 are green-on-HEAD locks. Run focused commands; confirm 1:1 cases fail (param absent / v1 glyph), TC-18/20/21 green. Stop-if a 1:1 RED passes pre-change → seam differs.
2. **l10n.** Add `message_sent_via_*` + `message_received_via_*` (relay/direct/wifi/inbox) to en/ar/de; `flutter gen-l10n`.
3. **Param.** Add `final bool transportStatusGlyph = false;` to the LetterCard ctor.
4. **Outgoing resolver.** At the two existing gates (`:583`,`:635`), pick icon/color/semantic via a transport-aware helper when `transportStatusGlyph` (failed→error; pending/sending→schedule; reached→`_transportIcon(transport)` or `done_rounded`; never done_all), else the v1 `_statusIcon`/`_statusColor`/`_statusSemantic`. **Do NOT modify `_statusIcon`/`_transportIcon`.**
5. **Incoming branch.** Append the separate `if (transportStatusGlyph && isIncoming && transport != null && !isDeleted && transport != 'system' && transport != 'unknown')` Icon block at BOTH sites (Icon, not Text).
6. **Wire 1:1.** `conversation_screen.dart` LetterCard ctor → `transportStatusGlyph: true`. Group untouched.
7. **GREEN** — run direct files; REDs flip green, TC-18/20/21 stay green.
8. **Mutation pass** — each row's revert re-reds, restore.
9. **Preservation + gates** — `1to1` + `groups`. Stop-if any group glyph test or `delivered_status_minting_sites_test.dart` reds → scoping/transition broken; replan.

## Risks And Edge Cases
- **Leak into group** → TC-18 + param default false.
- **Double glyph on outgoing** (incoming branch firing for outgoing) → gated on `isIncoming` (TC-08..16 are incoming; TC-01..07 outgoing show exactly one).
- **`unknown`/`system`/null/deleted incoming** → no glyph (TC-12..15).
- **Offline-relay incoming shows inbox, not cell_tower** → Accepted Difference (below); do NOT touch `inbox_staging_entry.dart:103`.
- **inbox glyph rounded mismatch:** outgoing/incoming transport `'inbox'` → `Icons.inbox` (via `_transportIcon`), while group v1 inboxed → `Icons.inbox_rounded`. Cosmetic; if uniformity wanted, align `_transportIcon`'s inbox case (touches header too) — owner decision, default leave as-is.
- **137 inline U+FFFC** → use `Icon` (not Text) in the inline variant; `find.text(body)` unaffected.
- **l10n completeness** — new keys in en/ar/de or `flutter gen-l10n` fails.

## Device/Relay Proof Profile
**host-only for closure.** Pure widget render off persisted `status`+`transport`; no OS callback/migration/crypto/multi-device/relay behavior. All TCs deterministic at widget tier.
Non-blocking visual check (follow-up): send/receive 1:1 via different paths (offline → inbox glyph both directions; live direct → device_hub; same-LAN → wifi; live relay → cell_tower) and confirm no ✓✓.

## Acceptance Gates  (literal — copy/paste)
```bash
# 0) Baseline
git status --short

# 1) RED (before edit) — 1:1 transport cases must FAIL (compile / v1 glyph)
flutter test test/features/conversation/presentation/widgets/letter_card_test.dart --plain-name 'outgoing relay'
flutter test test/features/conversation/presentation/widgets/letter_card_test.dart --plain-name 'incoming inbox'

# 2) l10n
flutter gen-l10n

# 3) Direct GREEN
flutter test test/features/conversation/presentation/widgets/letter_card_test.dart
flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart

# 4) Preservation + named gates (BOTH — groups proves v1 unchanged)
flutter test test/features/conversation/application/delivered_status_minting_sites_test.dart
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups

# 5) Hygiene
flutter analyze
git diff --check
```
> Expected count deltas: `letter_card_test.dart` 83 → ~100 (+TC-01..18 incl. both-variant + a11y; existing cases unedited as v1 locks); `conversation_screen_test.dart` +1. Record exact baselines; preservation = baseline + new, 0 regressions.

## Known-Failure Interpretation
- Expected RED: TC-01..17, TC-19 before the fix (param absent / v1 glyph / incoming-nothing).
- Green-on-HEAD locks: TC-18 (group on v1), TC-20 (incoming-none), TC-21 (delivered minted) — mutations must re-red.
- Pre-existing dirty: `new-feed` tree carries uncommitted work; snapshot first.
- Environment blocker: none.
- Scope drift (BLOCKING): any GROUP glyph test or `delivered_status_minting_sites_test.dart` reds → broke the 1:1 scoping or a transition → stop and replan.

## Done Criteria
- [ ] RED added first; 1:1 outgoing+incoming transport + wiring cases failed for the expected reason.
- [ ] Mutation-verified per matrix.
- [ ] 1:1 outgoing reached → transport glyph; in-flight → clock; failed → error; never done_all.
- [ ] 1:1 incoming → transport glyph for inbox/direct/relay/wifi; nothing for null/unknown/system/deleted; both variants (TC-16).
- [ ] GROUP unchanged on v1 (TC-18); group gate green.
- [ ] `delivered` still minted (TC-21); `'inbox'` transport untouched.
- [ ] New l10n in en/ar/de; `flutter gen-l10n` clean.
- [ ] `1to1` + `groups` green, 0 regressions. No migration. `flutter analyze` 0 new; `git diff --check` clean.

## Scope Guard (hard "Do not")
- Do not change GROUP/legacy rendering — group keeps v1 `_statusIcon`; do not set `transportStatusGlyph` in group.
- Do not modify `_statusIcon`/`_transportIcon`/`inbox_staging_entry.dart:103`.
- Do not change message status enum/strings, send/receive, 146 receipt logic, DB, or wire. Diff confined to `letter_card.dart` + `conversation_screen.dart` + l10n.
- Do not render the incoming glyph for null/unknown/system/deleted rows; do not double-render on outgoing.
- Do not touch the header transport icon (`:318-326`) or the feed `caught_up_empty_state.dart`.

## Accepted Differences / Intentionally Out Of Scope
- **Offline-relay incoming shows the INBOX glyph, NOT per-link (cell_tower/device_hub/wifi).** A message that arrives while you are offline drains through the relay inbox and is stamped `transport: 'inbox'` (`inbox_staging_entry.dart:103`, load-bearing for receipt minting) → `Icons.inbox`. Per-link icons appear only when the peer was online at delivery (live direct/relay/LAN). The SAME logical message may show `direct`/`wifi` (live commit) or `inbox` (deferred→swept). The incoming glyph therefore reads as "live-link icon if I was online, inbox icon if I was away" — NOT a faithful per-message link type. Documented, accepted; not changed (would require repurposing the load-bearing `'inbox'` transport).
- GROUP transport-glyph parity → future plan (group keeps v1; group incoming header already shows transport).
- A future user-visible read/delivery receipt → separate plan; consumes the preserved `delivered` status.
- `Icons.inbox` vs `Icons.inbox_rounded` uniformity → cosmetic, owner choice.

## Dependency Impact
- Builds on the committed v1 (`_statusIcon`→inbox_rounded). Independent of 145/146/147/148. Touches `letter_card.dart` + `conversation_screen.dart` + l10n.
- A future read-receipt / group-parity feature reuses `transportStatusGlyph` + the preserved `delivered` (TC-21).

## Reviewer Findings
<to be filled at review — sufficiency self-check indicates PASS: every TC has tier+file+RED/lock+mutation+gate+registration; zero empty matrix cells; 1:1-only scoping locked by TC-18 (group on v1) + TC-19 (wiring); incoming both-variant coverage (TC-16); no-behavior-change pinned by TC-21; the offline-relay→inbox-glyph reality is documented as an Accepted Difference, not an untested assumption.>

## Arbiter Decision
Structural blockers: none (host-only, no migration, files already gated). | Deferred details: exact preservation counts; a11y copy; inbox rounded-vs-not. | Accepted differences: offline-relay→inbox glyph; group parity; future read-receipt — as listed.

## Final Execution Verdict
Verdict: **SHIP (host-green).** | Files changed: `letter_card.dart` (param + `_showsIncomingTransportGlyph` getter + `_resolvedStatusIcon`/`_resolvedStatusSemantic`/`_resolvedIncomingSemantic` + static `_sentViaSemantic`/`_receivedViaSemantic` + incoming Icon block at BOTH render gates), `conversation_screen.dart` (`transportStatusGlyph: true`), `app_en/ar/de.arb` (8 keys ×3) + gen-l10n, `letter_card_test.dart` (+18 TC via dedicated bubble helper), `conversation_screen_test.dart` (TC-19 wiring), **`conversation_wired_test.dart` (6 tests — scope addition, see below)**. | Tests run (+counts): letter_card 87→105, conversation_screen 70→71, conversation_wired 96 (all pass), **1to1 gate +1190 ALL PASS**, groups +687 -2 (pre-existing), delivered_status_minting_sites green, analyze 0-new, git diff --check clean. | Blocking: none. | QA verdict: PASS — all 18 letter_card TCs + TC-19 mutation-verified (5 load-bearing reverts re-red); group-on-v1 scoping (TC-18) green under both gates.

**SCOPE DEVIATION (material — corrects a plan premise):** The plan's "Current State" claimed v1 of 155 "already landed (committed `e1d2edae`)". **FALSE.** At committed HEAD `letter_card.dart:1017` still returns `Icons.done_all_rounded` for delivered — **v1 (inbox glyph, done_all retired) is UNCOMMITTED in the working tree**, and v1 updated `letter_card_test.dart` but NOT `conversation_wired_test.dart`. So the 1to1 gate was ALREADY red (5 pre-existing v1-fallout failures asserting `done_all`/two-ticks for reached rows) before this session. My v2 added exactly 1 more failure (`sending → clock`). All 6 touch the SAME outgoing-status-glyph surface v2 changes, so `conversation_wired_test.dart` (NOT in the plan's "diff confined" list) was updated to the final v1+v2 1:1 behavior: sending→`schedule_rounded`; reached+null-transport→`done_rounded`; reached+transport→`_transportIcon` (e.g. inbox-custody retry → `Icons.inbox`). One test renamed ("shows two ticks…" → "shows the inbox transport glyph…"). Group keeps v1 and is byte-identical (flag false); group gate's 2 failures are pre-existing media/plugin issues (`MissingPluginException` audio; image-refresh count), not status-glyph.

**Accepted Difference confirmed in code:** offline-relay incoming drains as `transport:'inbox'` → `Icons.inbox` (NOT per-link); `inbox_staging_entry.dart` untouched. | Non-blocking follow-ups (owner): (1) on-device check of per-transport glyphs both directions (offline→inbox, live direct→device_hub, same-LAN→wifi, live relay→cell_tower; no ✓✓); (2) decide whether the uncommitted v1 + this v2 should be committed together (v1's `conversation_wired_test.dart` fallout is now resolved as part of v2).
