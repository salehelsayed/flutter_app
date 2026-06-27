# FDC-13 — Make a relay→direct UPGRADE visible as a per-message transport badge (1:1 only)  (New Feature)

Status: IMPLEMENTED + **COMMITTED in `5f21d790`** ("checkpoint(new-orbit): P0 complete — fast-direct-connection epic + 1:1 send reliability"; one commit behind HEAD `a32454c2`) — landed 2026-06-26, committed 2026-06-27. RT-W1..W5 + RT-S1 + RT-I1 green; RT-S1a/RT-S2/PS-3 preserved; all 5 mutations re-red; `1to1` gate full pass; `flutter analyze` 0-new; `git diff --check` clean. `core-host-all`/`feature-host-all` blockers are PRE-EXISTING (privacy-allowlist `sinceProcessStartMs`, proven disjoint via stash-revert) / a transient native-asset codesign flake (passes standalone), not FDC-13. **NB: `git status` no longer lists the FDC-13 files — they are in history (5f21d790), NOT lost/uncommitted. The exact `1to1` pass count was printed inconsistently below ("+1250" vs "~+13 over the 1226 FDC-S0 baseline" ⇒ ~1239); re-run `./scripts/run_test_gates.sh 1to1` to confirm the absolute number.**
Spec: Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md (§6.5 relay→direct upgrade / §8 P2-3 / §12 punchr) + FDC-00 "Known gaps from the design Q&A review" → **"GAP — relay→direct 'upgraded' badge"**

> **Review revision (2026-06-26):** re-anchored every `p2p_service_impl.dart` line ref to the live `new-orbit` tree (the file is the documented +drift hazard — upgraded-set/diagnostic region was ~+29, receive/constructor region ~+7); corrected a metrics-census **blocker** (the headline service test asserted a `transportMix()['upgraded']` bucket that does not exist → added **step 4a**, an additive `'upgraded'→'direct'` canonicalization alias that keeps the census stable); fixed RT-W3/W5 a11y assertions from unsatisfiable `label ==` equality to `RegExp` substring (the bubble merges sender+time+status into one Semantics node); corrected the `1to1` green-delta framing (~+13, not the RED count of 7); renumbered the four new 155-group tests off the overloaded `TC-13` to `TC-19..TC-22`.

> **Re-anchor revision (2026-06-27) — drift correction + committed status.** Implemented then **committed in `5f21d790`** (the header "uncommitted" wording is now stale — `git status` omits the FDC-13 files because they are in history, not lost). Since the 2026-06-26 review, concurrent edits to `p2p_service_impl.dart` (FDC-04/08/09/11) drifted **every** anchor in that file downward: ~**+64 lines** in the receive/constructor region, ~**+381 lines** in the helper/seam region (`letter_card.dart` / `transport_metrics.dart` drifted only +1..+12). **All printed line numbers in the sections below are STALE — locate by SYMBOL.** Current-HEAD anchors (verified by Read + git blame on `5f21d790`):
>
> | Symbol | Plan-stated | Current HEAD |
> |---|---|---|
> | `_inferTransportForPeer` (def) | :3020-3041 | **:3401-3426** |
> | upgraded-set **SEAM** (`return 'upgraded'`) | :3025-3027 (:3026) | **:3406-3412 (return :3411)** |
> | `case 'transport:upgraded'` | :3007-3010 | **:3388-3391** |
> | `_recordPeerUpgrade` (`.add`) | :3014-3018 (.add :3016) | **:3395-3399 (.add :3397)** |
> | `case 'holepunch:success'` call | :3002 | **:3381-3384 (call :3383)** |
> | `recordHolePunchAttempt()` (do-NOT-edit warning anchor) | :2997 | **:3378** |
> | `_shortId` (last 8) | :2985-2986 | **:3366-3367** |
> | `_peersUpgradedToDirect` field decl | (n/a) | **:133** |
> | incoming `transport = msg.transport ?? _inferTransportForPeer(…) ?? 'unknown'` | :303-304 | **:367-368** |
> | `recordTransport(transport)` (receive) | :305 | **:369** |
> | `MSG_RECEIVED_TRANSPORT` emit (event str) | :309-316 | **:373-380 (str :375)** |
> | `copyWith(transport:)` (receive) | :317 | **:381** |
> | `letter_card._transportIcon` (+`'upgraded'`→`Icons.upgrade`) | :1037-1053 | **:1037-1056 (arm :1046-1049)** |
> | `_transportIcon` default→`help_outline` | :1050-1051 | **:1054-1055** |
> | `_sentViaSemantic` `'upgraded'` arm | :1165-1179 | **arm :1176-1177** |
> | `_receivedViaSemantic` `'upgraded'` arm | :1181-1195 | **arm :1194-1195** |
> | `_resolvedStatusSemantic` generic fallback | :1155 | **:1159** |
> | `_resolvedIncomingSemantic` | :1159-1162 | **:1163-1167** |
> | `transport_metrics._canonicalTransport` (+`'upgraded'`→`'direct'`) | :123-138 | **:123-145 (alias :130-136)** |
> | `transport_metrics.recordTransport` | :161-165 | **:168-172** |
> | `letter_card_test` RT-W1 (group opener :468) | :468-513 | **:520-527** |
> | `letter_card_test` `buildTransportGlyph` / TC-19..22 block | :2275 / :2274-2356+ | **:2287 / :2627-2708** |
> | `p2p_service_inbound_transport_test` DCUTR-002 | :276-356 | **:276-366 (asserts :352-353, :360-362)** |
> | `…` DCUTR-013 (RT-I1) | (no plan ref) | **:373-424** |
>
> **⚠️ FDC-12 consumes these same anchors** and currently cites the *also-stale* `:3290-3293` / `:3303-3314` / `:4431` / `:4456` — re-ground FDC-12 to HEAD **:3388** (case) / **:3401** (infer) / **:4577** (`lastKnownGoodTransport`) / **:4602** (`recordSuccessfulTransport`) before its implementation.

---

## Source Of Truth

- **Design:** `Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md` §6.5 ("the relay→direct upgrade DCUtR cannot deliver under `ForceReachabilityPrivate`"), §8 P2-3 (DCUtR upgrade hands a *second* connection), §12 (punchr ~70%±7.1%, config-OFF not capability-failed).
- **Roadmap gap entry:** `FDC-00-roadmap.md` Known-gaps entry (relay→direct 'upgraded' badge) — *"a relay→direct upgrade currently folds into the plain `\"direct\"` badge (`_inferTransportForPeer` → `\"direct\"`); the upgrade is only counted in the debug diagnostics card. To let users see 'upgraded to direct,' a small follow-on (FDC-13) must add an `\"upgraded\"` transport value + glyph + `message_*_via_upgraded` a11y. Otherwise road-taken surfacing for the upgrade stays debug-only. (Pairs with FDC-12.)"*
- **Live code anchors (re-verified by Read on branch `new-orbit`, this revision):**
  - `lib/features/conversation/presentation/widgets/letter_card.dart:1037-1053` `_transportIcon` (wifi/local→`Icons.wifi`, direct/reuse→`Icons.device_hub:1042-1045`, relay→`Icons.cell_tower`, inbox→`Icons.inbox`, default→`Icons.help_outline:1050-1051`).
  - `letter_card.dart:1127-1139` `_resolvedStatusIcon` (OUTGOING; reached → `_transportIcon(transport)` at :1136-1137); `:1144-1156` `_resolvedStatusSemantic` (generic fallback `message_status_semantics` at `:1155`); `:1165-1179` `_sentViaSemantic` (relay/direct/reuse/wifi/local/inbox cases, `null` default); `:1181-1195` `_receivedViaSemantic`.
  - `letter_card.dart:176-182` `_showsIncomingTransportGlyph`; `:1159-1162` `_resolvedIncomingSemantic`. Render sites: `:607-609`/`:615-618` (one layout) and `:668-670`/`:676-679` (the other branch).
  - `conversation_screen.dart:633` `transportStatusGlyph: true` — the **only** enabling site (1:1 conversation screen).
  - **`lib/core/services/p2p_service_impl.dart` (⚠️ documented `new-orbit` line-drift hazard — anchors below are current as of this revision but DRIFT; always locate by SYMBOL, never by line number) → as of 2026-06-27 HEAD every line below is STALE by ~+381 lines; see the Re-anchor table above for current lines (seam now :3406-3412, receive path :367-381):**
    - `:303-304` incoming transport = `msg.transport ?? _inferTransportForPeer(msg.from) ?? 'unknown'`, then `_transportMetrics?.recordTransport(transport)` at `:305` and `msg.copyWith(transport: transport)` at `:317`.
    - `:3020-3041` `_inferTransportForPeer`; **`:3025-3027` upgraded-set branch returns `'direct'` ← THE SEAM** (the `return 'direct';` is on `:3026`).
    - `:3007-3010` `case 'transport:upgraded'` → `recordRelayToDirectUpgrade` + `_recordPeerUpgrade`; the `_peersUpgradedToDirect.add(remotePeerShort)` lives in the `_recordPeerUpgrade` helper `:3014-3018` (`.add` at `:3016`). (NB: `_recordPeerUpgrade` is **also** called from the `holepunch:success` arm at `:3002`, so the upgraded set is populated by both events.)
    - `:2985-2986` `_shortId` (last 8 chars).
  - **`lib/core/debug/transport_metrics.dart`** — `kTransportBuckets` (`:4-10`: direct/relay/wifi/inbox/unknown — **no `upgraded`**), `_canonicalTransport` (`:123-138`: aliases `'reuse'→'direct'`, `'local'→'wifi'`, default → `'unknown'`), `recordTransport` (`:161-165`), `transportMix()` (returns a `Map.from(_transportCounts)` keyed only by `kTransportBuckets`). **Load-bearing for step 4a / RT-S1.**
  - `lib/core/database/migrations/012_transport_column.dart:28` `ALTER TABLE messages ADD COLUMN transport TEXT` — free-text values `wifi/local/direct/reuse/relay/inbox/NULL` (no CHECK/enum → `'upgraded'` persists fine).
  - `lib/l10n/app_en.arb` (`message_sent_via_*` / `message_received_via_*` keys, e.g. `..._via_direct` = "Sent/Received via direct connection", `..._via_relay` = "Sent/Received via cellular relay"); mirrored in `app_ar.arb` / `app_de.arb`. Keys carry **no** `@`-metadata block (match that convention).

## Session Classification

New Feature (additive, user-visible). Pure Dart + l10n. No Go/relay change. No DB migration. UI-isolated from the FDC Phase-0 collision file (`send_chat_message_use_case.dart`). One additive line in `transport_metrics.dart` (step 4a canonicalization alias — no counter rebuild/rename).

## Exact Problem Statement

**What's missing / who feels it / why.** When DCUtR upgrades a live relay connection to a direct one (the §6.5/P2-3 road, config-OFF today via `ForceReachabilityPrivate`), the message that travels post-upgrade is *more* direct than a native-direct send — but the per-message badge (plan-155) collapses it into the **same `device_hub` "direct" glyph** as a native-direct message, because the `_inferTransportForPeer` upgraded-set branch knows the peer is in `_peersUpgradedToDirect` yet still returns the plain string `'direct'`. The only place the upgrade is currently surfaced is the **debug** `settings_transport_diagnostics_card` (`transport_metrics._relayToDirectUpgrades`). A user who started on relay and got upgraded cannot *see* the win.

**What must improve.** An upgraded message must render a **distinct glyph** (`Icons.upgrade`) and a **distinct a11y label** (`message_sent_via_upgraded` / `message_received_via_upgraded`), so the upgrade is visible on the 1:1 conversation screen — not just in a debug card.

**What must stay unchanged → preserved sentinels.**
- **PS-1** Native-direct messages (no upgrade) still render `Icons.device_hub` + "via direct" — `letter_card_test.dart:484-486` ("shows direct icon when transport is direct"), `:489-493` (legacy `reuse`→device_hub).
- **PS-2** Relay/wifi/local/inbox/null/unrecognized glyphs unchanged — `letter_card_test.dart:469-513` (incl. `:510-513` unrecognized→`help_outline`).
- **PS-3** A **non-upgraded** incoming peer still infers `'direct'` (live non-circuit conn) or `'unknown'` (no conn) — `p2p_service_inbound_transport_test.dart:241-274` (T4), DCUTR-002 non-upgraded peer arm (`received[1].transport == 'unknown'`).
- **PS-4** Group / legacy (`transportStatusGlyph:false`) path keeps the v1 `_statusIcon`/`_statusSemantic` and shows **no** transport glyph — `letter_card_test.dart` group/legacy cases (TC-18).
- **PS-5** Transport metrics counters (`relayToDirectUpgrades`, hole-punch counts) and the existing **mix census** (`transportMix()`) are unchanged — `p2p_service_inbound_transport_test.dart` DCUTR-002 `metrics.relayToDirectUpgrades==1` + `transportMix()['direct']==1`/`['unknown']==1`/`['relay']==0`. (The step-4a alias is what KEEPS the census identical — see Blind-Spot Sweep.)

## Root Cause (verify→refute confirmed — file:line)

`p2p_service_impl.dart` `_inferTransportForPeer` upgraded-set branch (HEAD **:3406-3412**, was :3025-3027 — *locate by symbol, this file drifts ~+381 lines*). **PRE-fix snapshot** (the bug this plan removed):
```dart
if (_peersUpgradedToDirect.contains(_shortId(peerId))) {
  return 'direct';   // pre-fix; the upgrade was KNOWN here but flattened to plain direct
}
```
> **HEAD (post-fix, committed 5f21d790):** the return is now `return 'upgraded';` at **:3411** (with an FDC-13 rationale comment at :3407-3410). The block above is retained as the historical root cause, **not current code**.
The upgraded-peer set is populated at `:3016` (inside the `_recordPeerUpgrade` helper) from the `transport:upgraded` tracer event (`:3007-3010`; the same helper also runs on `holepunch:success` at `:3002`), and `_inferTransportForPeer` is consulted for incoming messages at `:303-304`. The function therefore *has* the discriminating fact (this peer upgraded) but discards it. **Verified:** `_inferTransportForPeer`'s only caller is `:304` (incoming `msg.from`); `grep` shows references only at `:304`, `:326` (comment), `:3020` (def). The badge then loses the upgrade because `letter_card.dart:1042-1045` maps both `'direct'` and `'reuse'` to `device_hub` and there is no `'upgraded'` arm anywhere. **Refute check:** could the upgrade instead surface via the OUTGOING send transport? No — outgoing 1:1 transport comes from the Go stream label (`response['transport']`, a single read at `p2p_service_impl.dart:2021`) resolved by `send_chat_message_use_case.dart:1255-1266` `_resolveGoSendTransport` → `actualTransport` or `_inferDirectVsRelayForConnectedPeer:1252` (returns `'direct'`/`'relay'`, **never** consults `_peersUpgradedToDirect`). So OUTGOING data cannot be `'upgraded'` without a Go label change (FDC-12) or a collision-file edit — see Real Scope / Open Issues.

## Real Scope (In / Out → owning FDC-xx)

**In:**
1. Add an `'upgraded'` transport value rendering: `_transportIcon('upgraded') → Icons.upgrade`, `_sentViaSemantic`/`_receivedViaSemantic` → new `message_*_via_upgraded` keys (`letter_card.dart`). Widget supports it for **both** OUTGOING (`_resolvedStatusIcon`/`_resolvedStatusSemantic`) and INCOMING (`_showsIncomingTransportGlyph`/`_resolvedIncomingSemantic`) so it is direction-symmetric and future-proof.
2. Stop `_inferTransportForPeer` flattening an upgraded peer to `'direct'` — return `'upgraded'` for set members (`p2p_service_impl.dart:3025-3027`, the `return` on `:3026`). This is the **INCOMING data path** (the only producer of `'upgraded'` today). Pair with step 4a (the `_canonicalTransport` `'upgraded'→'direct'` census alias) so the debug mix card and its existing asserts are unchanged.
3. New l10n keys `message_sent_via_upgraded` + `message_received_via_upgraded` in `app_en.arb`/`app_ar.arb`/`app_de.arb` + regenerate `app_localizations*.dart`.
4. Additive census alias in `transport_metrics.dart` `_canonicalTransport` (`'upgraded' → 'direct'`) — see step 4a. No bucket/counter rebuilt or renamed.

**Out (named owner):**
- Real-wire firing of `transport:upgraded` (DCUtR under a flag) → **FDC-12** (itself gated by **FDC-S2** QUIC-identify re-validation). FDC-13 drives the event **synthetically** on host.
- Surfacing `'upgraded'` on the **OUTGOING** send badge from production data (the Go stream returns `'direct'`) → needs a Go `'upgraded'` label (**FDC-12**) or a `send_chat_message_use_case.dart` reconciliation (the **Phase-0 collision file**, FDC-01..04) → **deferred** (Open Issue O1). FDC-13 ships the OUTGOING *widget render* (testable) but not the OUTGOING *data wiring*.
- A **dedicated `'upgraded'` census bucket** (so the mix card shows upgrades as a distinct row instead of folding into `direct`) → **out / optional future enhancement** (Open Issue O4). FDC-13 deliberately keeps the upgrade in the `direct` mix bucket (step 4a) to avoid touching `kTransportBuckets` / the card layout / the latency maps; the dedicated `relayToDirectUpgrades` counter already surfaces the upgrade count.
- Group surface / `message_bubble` → **N/A**: the feed "Letters" surface (`LetterBubble`, 134) renders **no** status/transport glyph; there is no feed transport-badge twin (Open Issue O2 corrects the prompt premise).
- Backfilling pre-existing persisted `'direct'` rows that were actually upgrades → out (only new receives after the fix carry `'upgraded'`; acceptable — Open Issue O3).

## Files To Inspect Next

- `lib/features/conversation/presentation/widgets/letter_card.dart` (`_transportIcon`, `_resolvedStatusIcon`, `_sentViaSemantic`, `_receivedViaSemantic`, `_resolvedIncomingSemantic`, `_showsIncomingTransportGlyph`).
- `lib/core/services/p2p_service_impl.dart:2985-3041` (`_shortId` `:2985-2986`, `_recordPeerUpgrade` `:3014-3018`, `_inferTransportForPeer` `:3020-3041` incl. the upgraded-set seam `:3025-3027`) — **drift hazard: locate by symbol.**
- `lib/core/debug/transport_metrics.dart` (`_canonicalTransport` `:123-138`, `kTransportBuckets` `:4-10`, `recordTransport` `:161-165`) — step 4a census alias.
- `lib/l10n/app_en.arb` / `app_ar.arb` / `app_de.arb` + `l10n.yaml` regen.
- Tests: `test/features/conversation/presentation/widgets/letter_card_test.dart` (transport-icon group `:468-513`; "155 transport status glyph" group `:2274-2356+`, helper `buildTransportGlyph` `:2275`, a11y idiom TC-17 `:2543-2583`); `test/core/services/p2p_service_inbound_transport_test.dart` (DCUTR-002 `:276-356`, T4 `:241-274`); `test/core/debug/transport_metrics_test.dart` (canonicalization asserts — check step 4a doesn't flip an existing case).

## Existing Tests Covering This Area (named; which gate arrays list them)

- `test/features/conversation/presentation/widgets/letter_card_test.dart` — **in `ONE_TO_ONE_TESTS`** (`scripts/run_test_gates.sh`, 1to1 gate) and AUTO-globbed by `feature-host-all`. Owns the transport-icon + 155-status-glyph groups. (a11y assertions in the 155 group use `find.bySemanticsLabel(RegExp(...))` because the bubble merges sender+time+status into one Semantics node — see TC-17 `:2543-2583`.)
- `test/core/services/p2p_service_inbound_transport_test.dart` — **NOT** in any curated array; covered only by `core-host-all` glob (`test/core/**`). DCUTR-002 (`:276-356`) is the existing lock on `_inferTransportForPeer`'s upgraded-peer behavior; **its `received[0].transport == 'direct'` DATA assertion is the exact lock FDC-13 flips.** The test ALSO pins `transportMix()['direct']==1` / `['unknown']==1` / `['relay']==0` immediately below — under the step-4a census alias these stay GREEN **unchanged** (a *naive* flip without 4a would break them to 0/2). → Plan adds this file to `ONE_TO_ONE_TESTS` so the flip is a 1:1 headline gate.
- `test/features/conversation/presentation/screens/conversation_screen_test.dart` / `conversation_wired_test.dart` — in `ONE_TO_ONE_TESTS`; exercise the `transportStatusGlyph:true` wiring (PS-4 group-vs-1:1 boundary).

## RED Test Catalog (BEFORE prod code)

> Distinct-event discriminator rule: every `'upgraded'` glyph assertion **also** asserts the message does **NOT** render the plain `'direct'` glyph (`Icons.device_hub`) **and not** the `help_outline` fallback — proving the new value is mapped, not falling through. Every `'upgraded'` a11y assertion uses `find.bySemanticsLabel(RegExp(...))` substring (the bubble merges status into one node) and **also** asserts the corresponding "via direct connection" phrase findsNothing.

**Widget tier — `letter_card_test.dart` (transport-icon group `:468-513`):**

- **RT-W1** `letter_card_test.dart::"shows upgrade icon when transport is upgraded"`
  - Tier: widget. Shape: `buildTestWidget(transport: 'upgraded')` (the existing helper at `:23/:43/:59/:79`, with `transportStatusGlyph` default per group).
  - RED-on-HEAD-because: `_transportIcon` has no `'upgraded'` arm → falls to `default → Icons.help_outline:1050-1051`.
  - GREEN-asserts: `find.byIcon(Icons.upgrade)` findsOneWidget; **AND** `find.byIcon(Icons.device_hub)` findsNothing; **AND** `find.byIcon(Icons.help_outline)` findsNothing.
  - Mutation-that-re-reds: change the new arm `case 'upgraded': return Icons.upgrade;` → `return Icons.device_hub;` (re-reds on device_hub-findsNothing).

**Widget tier — `letter_card_test.dart` ("155 transport status glyph" group `:2274-2356+`, `transportStatusGlyph:true`):**

- **RT-W2 (OUTGOING glyph)** `::"TC-19 outgoing reached via upgraded → upgrade icon (not device_hub, not inbox)"`
  - Shape: `buildTransportGlyph(status: 'delivered', transport: 'upgraded')` (helper `:2275`).
  - RED-because: `_resolvedStatusIcon` calls `_transportIcon` which lacks the arm → `help_outline`.
  - GREEN: `Icons.upgrade` findsOneWidget; `Icons.device_hub` findsNothing; `Icons.help_outline` findsNothing; `Icons.inbox_rounded` findsNothing.
  - Mutation: as RT-W1.
- **RT-W3 (OUTGOING a11y)** `::"TC-20 outgoing upgraded a11y → message_sent_via_upgraded (not via_direct)"`
  - Shape: same widget (`buildTransportGlyph(status:'delivered', transport:'upgraded')`). The bubble folds sender+time+status into ONE merged `Semantics` node (e.g. "You\n3:30 PM\nSent via cellular relay"), so there is **no isolated status node to read by `==`** — assert via `find.bySemanticsLabel(RegExp(...))` substring, mirroring the file's own TC-17 (`:2543-2583`).
  - RED-because: `_sentViaSemantic` returns `null` for `'upgraded'` → `_resolvedStatusSemantic` (`via==null`) falls through to the generic `message_status_semantics` label at `letter_card.dart:1155`, never the new string.
  - GREEN: `find.bySemanticsLabel(RegExp(<message_sent_via_upgraded wording>))` findsWidgets; **AND** `find.bySemanticsLabel(RegExp('Sent via direct connection'))` findsNothing. (Substring-collision guard: the new `message_sent_via_upgraded` string must NOT contain the contiguous phrase "Sent via direct connection" — e.g. "Upgraded to direct connection" is safe.)
  - Mutation: drop the `case 'upgraded':` from `_sentViaSemantic` → re-reds.
- **RT-W4 (INCOMING glyph)** `::"TC-21 incoming via upgraded shows the incoming upgrade glyph"`
  - Shape: `buildTransportGlyph(isIncoming:true, transport:'upgraded')` (incoming path; `_showsIncomingTransportGlyph:176-182` already fires for any non-system/non-unknown transport — `'upgraded'` qualifies).
  - RED-because: incoming glyph uses `_resolvedIncomingSemantic`/`_transportIcon`; `_transportIcon('upgraded')` → `help_outline`.
  - GREEN: `Icons.upgrade` findsOneWidget; `Icons.device_hub` findsNothing; `Icons.help_outline` findsNothing.
  - Mutation: as RT-W1.
- **RT-W5 (INCOMING a11y)** `::"TC-22 incoming upgraded a11y → message_received_via_upgraded (not via_direct)"`
  - Shape: incoming `'upgraded'` (`buildTransportGlyph(isIncoming:true, transport:'upgraded')`); same merged-node caveat as RT-W3 — assert via `find.bySemanticsLabel(RegExp(...))`.
  - RED-because: `_receivedViaSemantic` returns `null` for `'upgraded'` → `_resolvedIncomingSemantic` falls back to the generic label.
  - GREEN: `find.bySemanticsLabel(RegExp(<message_received_via_upgraded wording>))` findsWidgets; **AND** `find.bySemanticsLabel(RegExp('Received via direct connection'))` findsNothing. (Collision guard: the new string must NOT contain the contiguous phrase "Received via direct connection" — "Received via upgraded direct connection" is safe, since "via" is followed by "upgraded".)
  - Mutation: drop the `case 'upgraded':` from `_receivedViaSemantic` → re-reds.

**Service tier — `p2p_service_inbound_transport_test.dart` (the `_inferTransportForPeer` seam + census alias):**

- **RT-S1 (flip DCUTR-002 upgraded arm)** modify the existing `::"DCUTR-002: transport diagnostics drive exact counters and upgrade inference"` (`:276-356`).
  - Shape: already emits `transport:upgraded` for `remotePeerShort:'abc12345'`, then delivers an incoming `ChatMessage(from: upgradedPeerId='...abc12345', transport:null)` and a non-upgraded incoming (`from:'not-upgraded-peer'`, no conn). `_shortId` keeps the last 8 chars (`p2p_service_impl.dart:2985-2986`), so `upgradedPeerId` ends in `abc12345` → set hit.
  - RED-because: the `_inferTransportForPeer` upgraded-set branch (`:3025-3027`) returns `'direct'`; current asserts `received[0].transport == 'direct'`.
  - GREEN-asserts (the flip — **DATA channel is the lock**): `received[0].transport == 'upgraded'`; **discriminator / PS-3 preserved:** `received[1].transport == 'unknown'` (non-upgraded, no-conn peer unchanged); `metrics.relayToDirectUpgrades == 1` (PS-5). **Census preserved by step 4a — the three existing `transportMix()` asserts stay GREEN unchanged:** `['direct'] == 1`, `['unknown'] == 1`, `['relay'] == 0`. (`recordTransport(transport)` at `p2p_service_impl.dart:305` is fed the SAME `'upgraded'` string that becomes the message transport; step 4a teaches `_canonicalTransport` to alias `'upgraded' → 'direct'`, so the upgraded receive still counts in the `direct` bucket.) **Do NOT assert `transportMix()['upgraded']`** — there is deliberately no `'upgraded'` census bucket; the upgrade is observable on the DATA channel (`received[0].transport`) and via the dedicated `relayToDirectUpgrades` counter, not the mix census.
  - Mutation-that-re-reds: revert the seam `:3026` `return 'upgraded';` → `return 'direct';` (re-reds on `received[0]=='upgraded'`).
  - distinct-event discriminator: the **upgraded** peer and the **non-upgraded** peer yield different DATA strings (`'upgraded'` vs `'unknown'`) in the *same* test — proves set membership, not a blanket relabel.
- **RT-S1a (census-alias preservation lock)** in the SAME DCUTR-002 test, the `transportMix()['direct']==1` / `['unknown']==1` asserts double as the lock on step 4a.
  - RED-able via step-4a mutation: drop the `case 'upgraded': return 'direct';` from `_canonicalTransport` → the upgraded receive folds to `'unknown'`, so `['direct']` 1→0 and `['unknown']` 1→2 → re-reds. Confirms the alias is load-bearing (not dead).
- **RT-S2 (preservation: live non-circuit conn still `direct`)** keep/extend T4 (`:241-274`): a peer with a `/ip4/.../tcp/` conn but **not** in the upgraded set → `received.single.transport == 'direct'` (PS-3). Already green; pin it as a regression floor (assert it stays green post-change).

**Integration tier — receiver flow-event readout (same file, new test):**

- **RT-I1** `p2p_service_inbound_transport_test.dart::"DCUTR-013: synthetic upgrade event surfaces 'upgraded' on the receiver readout"`
  - Shape: capture `emitFlowEvent` (the production handler emits `MSG_RECEIVED_TRANSPORT` at `p2p_service_impl.dart:309-316`; the test harness already observes flow events); emit `transport:upgraded` for a peer, deliver an incoming `transport:null` message from it, then assert the captured `MSG_RECEIVED_TRANSPORT` detail `transport == 'upgraded'` **and** the streamed `ChatMessage.transport == 'upgraded'`.
  - RED-because: pre-fix the readout is `'direct'`.
  - GREEN: both readouts `'upgraded'`.
  - Mutation: as RT-S1 (seam `:3026`).
  - distinct-event discriminator: this locks the **end-to-end streamed + greppable flow-event** path (`copyWith(transport:)` at `:317`, `MSG_RECEIVED_TRANSPORT` detail), distinct from RT-S1's `messageStream` + census observation — same result, different observation channels.

**RED count: 7** (RT-W1..W5, RT-S1, RT-I1; RT-S1a and RT-S2 are preservation pins, not new REDs).

## Test Coverage Matrix (zero empty cells)

| Spec case | Behavior props | Tier | Test file::name | RED reason | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| `_transportIcon('upgraded')` maps to a distinct glyph | glyph=upgrade, not device_hub/help_outline | widget | `letter_card_test.dart::shows upgrade icon when transport is upgraded` (RT-W1) | no `'upgraded'` arm → help_outline | `case 'upgraded'→Icons.device_hub` | `./scripts/run_test_gates.sh 1to1` | in `ONE_TO_ONE_TESTS` (already) + `feature-host-all` glob |
| OUTGOING reached upgraded → upgrade glyph | `_resolvedStatusIcon` routes upgraded | widget | `letter_card_test.dart::TC-19 outgoing reached via upgraded → upgrade icon` (RT-W2) | `_transportIcon` lacks arm | as RT-W1 | `1to1` | same |
| OUTGOING upgraded a11y | `message_sent_via_upgraded`, not via_direct (RegExp substring) | widget+a11y | `letter_card_test.dart::TC-20 outgoing upgraded a11y` (RT-W3) | `_sentViaSemantic` null → generic label `:1155` | drop `_sentViaSemantic` upgraded case | `1to1` | same |
| INCOMING upgraded → glyph | `_showsIncomingTransportGlyph` + glyph | widget | `letter_card_test.dart::TC-21 incoming via upgraded shows the incoming upgrade glyph` (RT-W4) | `_transportIcon` lacks arm | as RT-W1 | `1to1` | same |
| INCOMING upgraded a11y | `message_received_via_upgraded`, not via_direct (RegExp substring) | widget+a11y | `letter_card_test.dart::TC-22 incoming upgraded a11y` (RT-W5) | `_receivedViaSemantic` null → generic label | drop `_receivedViaSemantic` upgraded case | `1to1` | same |
| `_inferTransportForPeer` upgraded peer → `'upgraded'` data | upgraded peer relabel; non-upgraded unchanged | service | `p2p_service_inbound_transport_test.dart::DCUTR-002 …` (RT-S1, flip the `received[0]` data assert) | seam `:3025-3027` returns `'direct'` | revert seam `:3026`→`'direct'` | `core-host-all` + add to `1to1` | **ADD file to `ONE_TO_ONE_TESTS`** |
| `_canonicalTransport('upgraded')` aliases to `'direct'` bucket | census/card stable; no `'upgraded'` bucket | service | `p2p_service_inbound_transport_test.dart::DCUTR-002 …` (RT-S1a — census asserts `['direct']==1`/`['unknown']==1` stay GREEN) | preservation (naive flip → 1→0 / 1→2) | drop `case 'upgraded'→'direct'` alias → `['direct']` 1→0 re-reds | `core-host-all` + `1to1` | same add |
| Non-upgraded peer still `'direct'` (PS-3) | preservation floor | service | `p2p_service_inbound_transport_test.dart::T4 …` (RT-S2) | n/a (stays green) | n/a (regression pin) | `core-host-all` + `1to1` | same add |
| End-to-end synthetic event → receiver readout `'upgraded'` | streamed + `MSG_RECEIVED_TRANSPORT` flow event | integration | `p2p_service_inbound_transport_test.dart::DCUTR-013 …` (RT-I1) | readout is `'direct'` pre-fix | revert seam `:3026` | `core-host-all` + `1to1` | same add |
| New l10n keys resolve | `message_*_via_upgraded` exist in en/ar/de | (covered by RT-W3/W5 via `l10n.message_*_via_upgraded`) | — | key absent → compile/lookup fail | remove key from arb | `flutter analyze` + `1to1` | l10n auto-gen |

## Blind-Spot Sweep

- **Lifecycle / derived-state durability:** `'upgraded'` is persisted into the existing TEXT `transport` column via `copyWith(transport:)` (HEAD `p2p_service_impl.dart:381`) → durable across reloads exactly like `'direct'` (migration 012 column is free-text, no CHECK/enum). Old `'direct'` rows are not retroactively rewritten (Open Issue O3) — acceptable; new receives carry the value. **Reconstruct proof = RT-W2/W4** (corrected: RT-I1 is stream-only — it proves the value is *produced/persistable*, not that the badge reconstructs from a stored row). On fresh mount, `conversation_screen.dart` feeds the **stored** `message.transport` straight to `LetterCard.transport` (`letter_card.dart:46`); `_inferTransportForPeer` is **not** consulted for persisted rows, so RT-W2/W4 (mounting a `LetterCard` with literal `transport:'upgraded'`) are the actual fresh-mount-reconstruct lock. A DB write→read round-trip test is a justified N/A (free-text column; `copyWith` does not validate). **In-memory caveat:** the `_peersUpgradedToDirect` set itself is in-memory only (decl `:133`, repopulated solely by live tracer events) — after a cold restart, *new* receives from a peer that upgraded in a prior session infer relay/direct from live connections, not `'upgraded'`, until the tracer re-fires `transport:upgraded`. Persisted rows keep their stored `'upgraded'`. Acceptable (mirrors O3 no-backfill).
- **Sibling-surface consistency:** within `letter_card.dart` the badge has **two** render paths — OUTGOING (`_resolvedStatusIcon`/`_resolvedStatusSemantic`) and INCOMING (`_showsIncomingTransportGlyph`/`_resolvedIncomingSemantic`); **both** must map `'upgraded'`. Locked by RT-W2/W3 (outgoing) + RT-W4/W5 (incoming). **Feed twin:** N/A — verified `LetterBubble` (`lib/features/feed/presentation/widgets/letter_bubble.dart`) is a pure leaf with **no** status/transport glyph (134 "Letters" dropped status ticks); `feed_screen.dart` uses `LetterCardOneToOne/Group/System` (→ `LetterBubble`), **not** the conversation `LetterCard`. So there is **no** feed sibling to keep in sync (corrects the prompt's "feed message_bubble parallel mapping" premise — Open Issue O2).
- **Destructive side-effects:** one, neutralized by step 4a. Returning `'upgraded'` from `_inferTransportForPeer` flows into `recordTransport(transport)` at `p2p_service_impl.dart:305` (the SAME string that becomes the message transport). `TransportMetrics._canonicalTransport` (`transport_metrics.dart:123-138`) has no `'upgraded'` case, so a *naive* flip would canonicalize the upgraded receive to the `'unknown'` bucket — silently moving it out of the `'direct'` row into the `'unknown'` row of the debug diagnostics card (`settings_transport_diagnostics_card.dart`, which iterates `kTransportBuckets`) — the SAME surface the Problem Statement cites — AND breaking the existing DCUTR-002 census asserts (`['direct']` 1→0, `['unknown']` 1→2). **Step 4a removes this** by aliasing `'upgraded' → 'direct'` in `_canonicalTransport` (an upgrade IS direct transport for the aggregate mix; mirrors the existing `'reuse'→'direct'` / `'local'→'wifi'` aliases), so the census row stays exactly as today and the upgrade remains separately counted by `relayToDirectUpgrades` (PS-5). Net: the ONLY behavior change a user sees is the message badge.
- **Invariant re-verification:** PS-1/PS-2 (existing glyph map) untouched — only a new arm added; pinned by the unchanged `letter_card_test.dart:469-513` cases. PS-4 (group/legacy shows no glyph) untouched — `transportStatusGlyph` gate unchanged; pinned by existing group/legacy cases (TC-18). PS-5 (metrics + census) pinned by RT-S1's `relayToDirectUpgrades==1` and the unchanged `transportMix()` asserts (RT-S1a). **Unguarded transition (NEW — see INV-7/O5):** FDC-13 introduces a `set-membership → 'upgraded'` *latch* with **no inverse transition** — `_peersUpgradedToDirect` is add-only (add `:3397`, read `:3406`, **never removed/cleared**; grep confirms zero `.remove`/`.clear`/`transport:downgraded`). The "upgraded" invariant therefore holds only while the direct connection is alive; a real direct→relay **downgrade is an untested transition that breaks INV-1** (the badge keeps reading `'upgraded'` on new receives). Dormant today (DCUtR is config-OFF, so no producer fires) and correctly **owned by FDC-12 (TC-12-09b)** — flagged here, not silently masked.

## Invariants (locked by tests)

- **INV-1** An upgraded peer's incoming message persists/streams `transport == 'upgraded'`, never `'direct'` (RT-S1, RT-I1).
- **INV-2** `'upgraded'` renders `Icons.upgrade` on both directions, never `device_hub`/`help_outline` (RT-W1/W2/W4).
- **INV-3** `'upgraded'` a11y reads "via upgraded", never "via direct" or the generic status fallback (RT-W3/W5, RegExp substring).
- **INV-4** A non-upgraded peer is unaffected: native-direct stays `'direct'`/`device_hub`/"via direct"; no-conn stays `'unknown'` (PS-1/PS-3; RT-S1 discriminator, RT-S2, existing `:484-486`).
- **INV-5** Group/legacy (`transportStatusGlyph:false`) shows no transport glyph (PS-4, unchanged gate).
- **INV-6** The aggregate transport-mix census is unchanged: an upgraded receive still counts in the `'direct'` bucket (step 4a), so `transportMix()` and the diagnostics card behave exactly as before (RT-S1a, PS-5).
- **INV-7 (cross-cut — owned by FDC-12, NOT locked here)** `_peersUpgradedToDirect` is **add-only** (decl `:133`, add `:3397`, read `:3406`; HEAD has **no** `.remove`/`.clear`/`transport:downgraded`). Once set, `_inferTransportForPeer` labels every subsequent receive from that peer `'upgraded'` indefinitely — so after a true direct→relay **downgrade the badge lies** (violates INV-1 for new receives). FDC-13 ships this latch knowingly: the only producers (`transport:upgraded`/`holepunch:success`, `:3381-3391`) require DCUtR, which is config-OFF today, so the latch is dormant. FDC-12 both enables the producers **and** must add the removal (TC-12-09b). Recorded as **O5**.

## Step-By-Step Implementation Plan (RED first; name the seam)

1. **RED** — add RT-W1 (transport-icon group) + RT-W2..W5 (155 group, named TC-19..TC-22) in `letter_card_test.dart`; flip RT-S1's `received[0]` data assert in DCUTR-002 + add RT-I1 in `p2p_service_inbound_transport_test.dart`. Run `1to1` + `core-host-all` → confirm all 7 RED for the stated reasons (W: help_outline / generic-label fallthrough; S/I: `'direct'`).
2. **l10n seam** — add `message_sent_via_upgraded` ("Upgraded to direct connection") + `message_received_via_upgraded` ("Received via upgraded direct connection") to `app_en.arb`, `app_ar.arb`, `app_de.arb` (key + value, matching the no-`@`-metadata convention of the sibling `message_*_via_*` keys); regenerate `lib/l10n/app_localizations*.dart` via `flutter gen-l10n` (pubspec `generate: true`; **no** build_runner/intl_utils in this repo). Neither new string may contain the contiguous phrase "Sent via direct connection" / "Received via direct connection" (RT-W3/W5 negative guards) — the chosen wordings satisfy this.
3. **Widget seam** — in `letter_card.dart`: add `case 'upgraded': return Icons.upgrade;` to `_transportIcon` (`:1037-1053`); add `case 'upgraded': return l10n.message_sent_via_upgraded;` to `_sentViaSemantic` (`:1165-1179`); add `case 'upgraded': return l10n.message_received_via_upgraded;` to `_receivedViaSemantic` (`:1181-1195`). (`_resolvedStatusIcon`/`_showsIncomingTransportGlyph` need no change — they already route any non-null transport through `_transportIcon` and fire for non-system/unknown transports.) → RT-W1..W5 GREEN.
4. **Service seam** — in `p2p_service_impl.dart` `_inferTransportForPeer` upgraded-set branch (HEAD **:3406-3412**, was :3025-3027 — **locate by symbol; this file drifts ~+381 lines**) change `return 'direct';` → `return 'upgraded';` (now at **:3411**). → RT-I1 GREEN + RT-S1 DATA assert GREEN; RT-S2/PS-3 stays green. ⚠️ Do **NOT** edit the `recordHolePunchAttempt()` line (HEAD **:3378**, was the plan's old :2997 / :3378-region warning) inside the `holepunch:attempt` arm; editing it corrupts hole-punch and never fixes the badge.
4a. **Census-alias seam** — in `transport_metrics.dart` `_canonicalTransport` (`:123-138`) add `case 'upgraded': return 'direct';` (alongside the existing `'reuse'→'direct'` alias). This keeps the upgraded receive in the `'direct'` mix bucket (card unchanged; DCUTR-002 census asserts stay GREEN) while the message/badge still carry the distinct `'upgraded'` value. Additive — no bucket/counter renamed or removed (PS-5 intact). Check `test/core/debug/transport_metrics_test.dart` for any "`'upgraded'`→unknown / unrecognized→unknown" assert that this alias would flip.
5. **Harness** — append `test/core/services/p2p_service_inbound_transport_test.dart` to `ONE_TO_ONE_TESTS` in `scripts/run_test_gates.sh`.
6. **Mutation pass** — apply each "Mutation-that-re-reds" (RT-W1, RT-W3, RT-W5, RT-S1 seam `:3026`, and the step-4a alias drop → DCUTR-002 census `['direct']` 1→0 / `['unknown']` 1→2 re-reds) and confirm RED; revert.
7. **Gates** — `flutter analyze` (0 new), `git diff --check`, `1to1`, `feature-host-all`, `core-host-all`.

## Risks And Edge Cases (each pinned by a test)

- **Unrecognized value falls to help_outline** (if a typo'd value reaches the badge) — already-correct fallback preserved (`:510-513`); RT-W1 explicitly asserts `'upgraded'` is **not** help_outline.
- **Census re-bucketing if step 4a is skipped** — without the `'upgraded'→'direct'` alias, an upgraded receive censuses as `'unknown'`, breaking DCUTR-002's `transportMix()` asserts and moving the upgrade out of the card's `'direct'` row. Pinned by RT-S1/RT-S1a (`['direct']==1`/`['unknown']==1` only pass WITH step 4a).
- **Set membership uses `_shortId` (last 8 chars)** — a collision would mislabel a different peer. Pinned by RT-S1: the upgraded peer (`...abc12345`) labels `'upgraded'` while the unrelated `'not-upgraded-peer'` labels `'unknown'`.
- **OUTGOING data still `'direct'`** (Go label) — RT-W2/W3 prove the *widget* renders upgraded, but no service test asserts an *outgoing* `'upgraded'` persistence (it can't be produced yet); documented as O1, not silently masked.
- **l10n key missing in ar/de** — `flutter analyze` + generated-getter usage in RT-W3/W5 fail if any locale lacks the key.

## Device/Relay Proof Profile

Host-testable **now** end-to-end via the synthetic `transport:upgraded` event (RT-I1) — no device needed for the badge. **Real-wire** firing of `transport:upgraded` only occurs once DCUtR is enabled (**FDC-12**, gated by **FDC-S2** QUIC-identify re-validation, device-only because the iOS sim shares a host mDNS stack → `DISABLE_LOCAL_DISCOVERY`, §6.5). Device-proof of an *actual* upgrade→badge is therefore **deferred to FDC-12's device profile**; FDC-13 closes on host gates for the value/glyph/a11y/infer/census logic.

## Acceptance Gates (LITERAL cmds + expected counts as TODO)

```
# RED first (expect 7 new failures), then GREEN after steps 2-5:
./scripts/run_test_gates.sh 1to1                 # baseline 1226 (FDC-S0) → ~+13 green (confirm once measured), NOT +7: +5 new widget tests in letter_card_test.dart (already in 1to1) + the ENTIRE p2p_service_inbound_transport_test.dart suite (7 pre-existing — incl. flipped RT-S1/DCUTR-002 and pinned RT-S2/T4 — plus new RT-I1 = 8) which step 5 newly adds to ONE_TO_ONE_TESTS. The RED count of 7 is NOT the 1to1 green delta.
./scripts/run_host_test_gates.sh core-host-all   # 0 fail (249/249 core files PASS) (p2p_service_inbound_transport_test + transport_metrics_test green)
./scripts/run_host_test_gates.sh feature-host-all# 0 fail (files auto-glob into 1to1/feed/groups; full feature-host sweep deferred) (letter_card_test green)
flutter analyze                                  # TODO: 0 new
git diff --check                                 # TODO: clean (no whitespace errors)
```
No `transport` integration gate change needed (badge is unit/widget/service-tier). Re-run `1to1` after the l10n regen so the generated `app_localizations*.dart` is exercised.

## Known-Failure Interpretation

- If RT-S1 still asserts `'direct'` post-change, the `_shortId` of the test's `upgradedPeerId` did not end in the emitted `remotePeerShort` — check the `'abc12345'` constants align (last-8 rule).
- If DCUTR-002's `transportMix()['direct']` reads 0 (not 1) and `['unknown']` reads 2, **step 4a's `'upgraded'→'direct'` alias is missing** from `_canonicalTransport` — the upgraded receive is folding into the `'unknown'` bucket.
- A `help_outline` in RT-W1/W4 after step 3 means the `_transportIcon` arm was added below the `default` or the value string differs (`'upgraded'` exact).
- A generic "Message status: …" label (no RegExp match) in RT-W3/W5 means `_sentViaSemantic`/`_receivedViaSemantic` returned null (missing case) or the l10n key wasn't regenerated.

## Done Criteria

- [x] RT-W1..W5 + RT-S1 + RT-I1 GREEN; RT-S1a/RT-S2/PS-3 still GREEN.
- [x] Each mutation re-reds its test (incl. the step-4a alias-drop → census re-red); reverted.
- [x] `message_sent_via_upgraded` ("Upgraded to direct connection") + `message_received_via_upgraded` ("Received via upgraded direct connection") in en/ar/de + regenerated getters.
- [x] `_transportIcon`/`_sentViaSemantic`/`_receivedViaSemantic` have an `'upgraded'` arm; `_inferTransportForPeer` upgraded-set branch returns `'upgraded'` (HEAD :3411, located by symbol; `recordHolePunchAttempt` at HEAD :3378 left untouched); `_canonicalTransport` aliases `'upgraded'→'direct'` (step 4a, HEAD :130-136).
- [x] `p2p_service_inbound_transport_test.dart` added to `ONE_TO_ONE_TESTS`.
- [x] `1to1` full pass (absolute count printed inconsistently — see Status note; ~1239 = 1226 FDC-S0 baseline + ~13 green; re-measure to confirm); `flutter analyze` 0-new; `git diff --check` clean. `core-host-all`/`feature-host-all` blockers PRE-EXISTING (privacy `sinceProcessStartMs` proven disjoint via stash-revert; transient native-asset codesign flake passes standalone) — affected files green standalone + via 1to1.
- [x] **COMMITTED in `5f21d790`** (one commit behind HEAD `a32454c2`) — supersedes the stale "uncommitted" wording; all anchors re-grounded to 2026-06-27 HEAD (see Re-anchor table).
- [x] Open Issues O1-O4 recorded in the FDC-00 gap entry / FDC-12 cross-link.

## Scope Guard (hard Do-not)

- Do **NOT** edit `lib/features/conversation/application/send_chat_message_use_case.dart` (the FDC-01..04 Phase-0 collision file). The OUTGOING data wiring is out of scope (O1).
- Do **NOT** add a DB migration or bump the schema version (existing TEXT column).
- Do **NOT** touch the group / feed surfaces (no transport glyph there).
- Do **NOT** change any existing `_transportIcon`/semantic arm except adding the new `'upgraded'` cases; do not alter the `transportStatusGlyph` gate (PS-4).
- Do **NOT** rename or remove existing transport-metrics counters/buckets (PS-5). Adding the additive `'upgraded'→'direct'` **canonicalization alias** to `_canonicalTransport` (step 4a) IS in-scope and required — it routes the new value into the existing `'direct'` bucket without touching any counter and does not add an `'upgraded'` bucket. (A dedicated `'upgraded'` bucket is the deferred O4 enhancement.)

## Accepted Differences

- The OUTGOING badge will render `'upgraded'` only once upstream data supplies it (FDC-12 / a future reconciliation). The widget support shipped now is intentional and inert for outgoing until then.
- Pre-fix persisted `'direct'` rows that were genuinely upgrades stay `'direct'` (no backfill — O3).
- The aggregate transport-mix census counts an upgrade as `'direct'` (step 4a alias), not as a distinct `'upgraded'` row — same as today's behavior. A distinct census row is deferred (O4); the per-upgrade count remains visible via `relayToDirectUpgrades`.
- `Icons.upgrade` chosen as the distinct glyph (an up-arrow badge), free of collision with `device_hub`/`cell_tower`/`wifi`/`inbox`/`help_outline`.

## Open Issues

- **O1** OUTGOING data path cannot produce `'upgraded'` without a Go `'upgraded'` stream label (FDC-12) or a `send_chat_message_use_case.dart` reconciliation (Phase-0 collision file). FDC-13 ships the inert OUTGOING widget render only.
- **O2** No feed transport-badge twin exists (`LetterBubble` is glyph-free) — corrects the prompt's "feed `message_bubble` parallel mapping" premise.
- **O3** No backfill of historical `'direct'` rows that were actually upgrades.
- **O4** (new, this revision) No dedicated `'upgraded'` mix-census bucket — upgrades fold into `'direct'` (step 4a). Adding `'upgraded'` to `kTransportBuckets` + a distinct `_canonicalTransport` case + a diagnostics-card row is a possible future enhancement, but it ripples into `kTransportBuckets`-keyed maps (`_transportCounts`/`_latency`/`_latencyWriteIndex`) and the card layout; out of scope for the badge feature. (Verified: the same `_canonicalTransport` alias also choke-points `recordSendLatency`→`_latency` (kTransportBuckets-keyed), so latency stats fold `'upgraded'`→`'direct'` identically — no separate latency test needed.)
- **O5** (new, 2026-06-27) **Downgrade-clears-set / "badge lies" debt.** `_peersUpgradedToDirect` has **no** removal path (add-only — decl `:133`, add `:3397`, read `:3406`), so a relay→direct→relay peer keeps the `'upgraded'` badge for every new receive. FDC-13 introduces this latch but ships no clear (no downgrade-event source exists until DCUtR/FDC-12). **Owned by FDC-12 (TC-12-09b: a new `case 'transport:downgraded'` removes the peer).** Justified N/A for FDC-13's RED tests — DCUtR is config-OFF so the latch is dormant; documented here (INV-7) so the risk is not silently masked.
- **O6** (new, 2026-06-27) **`'upgraded'` is non-stickifiable.** The `case 'transport:upgraded'` arm (HEAD `:3388-3391`) writes only the badge set — never the FDC-04 sticky cache (`_learnedTransport` `:142` / `lastKnownGoodTransport` `:4577-4604`); and `recordSuccessfulTransport` (`:4602-4604`) allowlists only `local`/`direct`/`relay`, so if O1 ever makes the OUTGOING transport `'upgraded'` (`send_chat_message_use_case.dart` calls `recordSuccessfulTransport(peer,'upgraded')`), it is silently **dropped** and sticky reuse never learns the peer is direct-reachable. Graceful today (no crash; outgoing is never `'upgraded'` per O1) but a real reuse-penalty the moment O1 lands. **Owned by FDC-12 (TC-12-09: record `'direct'`, not `'upgraded'`, to the sticky cache).** N/A for FDC-13.

## Dependency Impact

- **Pairs with FDC-12** (real-wire firing; FDC-12 gated by FDC-S2). FDC-13 is **ungated** for host badge tests. **FDC-12 inherits three FDC-13-introduced debts** beyond O1 (outgoing data): O5/INV-7 downgrade-clears-set (TC-12-09b), O6 sticky-cache reconciliation (TC-12-09), and the **stale shared anchors** — FDC-12 still cites the seam at `:3290-3293`/`:3303-3314` and the sticky cache at `:4431`/`:4456`; re-ground to HEAD `:3388`/`:3401`/`:4577`/`:4602` (verified 2026-06-27) before FDC-12 implementation.
- **Secondary collision:** `p2p_service_impl.dart` is also edited by **FDC-04** (`warmPeer`/`discoverLocalPeer`/`isLocalPeer`) and **FDC-08** (presence cache) — but FDC-13 touches a **disjoint region** (`_inferTransportForPeer` upgraded-set branch `:3025-3027` + `transport_metrics.dart`). If co-scheduled with FDC-04/08, serialize (different regions, low risk). (FDC-04/08's own line anchors also drift on `new-orbit` — verify by symbol.)
- `letter_card.dart` is **UI-isolated**: no FDC plan (FDC-01..04 edit `send_chat_message_use_case.dart`, not UI). No collision there.
- Adds one entry to `scripts/run_test_gates.sh ONE_TO_ONE_TESTS` (read-only array) and one additive `case` to `transport_metrics.dart` `_canonicalTransport`.
