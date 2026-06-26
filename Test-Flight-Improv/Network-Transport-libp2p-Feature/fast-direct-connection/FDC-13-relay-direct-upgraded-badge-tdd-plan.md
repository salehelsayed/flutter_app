# FDC-13 — Make a relay→direct UPGRADE visible as a per-message transport badge (1:1 only)  (New Feature)

Status: awaiting-review
Spec: Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md (§6.5 relay→direct upgrade / §8 P2-3 / §12 punchr) + FDC-00 "Known gaps from the design Q&A review" → **"GAP — relay→direct 'upgraded' badge"**

---

## Source Of Truth

- **Design:** `Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md` §6.5 ("the relay→direct upgrade DCUtR cannot deliver under `ForceReachabilityPrivate`"), §8 P2-3 (DCUtR upgrade hands a *second* connection), §12 (punchr ~70%±7.1%, config-OFF not capability-failed).
- **Roadmap gap entry:** `FDC-00-roadmap.md` Known-gaps entry (relay→direct 'upgraded' badge) — *"a relay→direct upgrade currently folds into the plain `\"direct\"` badge (`_inferTransportForPeer` → `\"direct\"`); the upgrade is only counted in the debug diagnostics card. To let users see 'upgraded to direct,' a small follow-on (FDC-13) must add an `\"upgraded\"` transport value + glyph + `message_*_via_upgraded` a11y. Otherwise road-taken surfacing for the upgrade stays debug-only. (Pairs with FDC-12.)"*
- **Live code anchors (all verified by Read on branch `new-orbit`):**
  - `lib/features/conversation/presentation/widgets/letter_card.dart:1037-1053` `_transportIcon` (wifi/local→`Icons.wifi`, direct/reuse→`Icons.device_hub`, relay→`Icons.cell_tower`, inbox→`Icons.inbox`, default→`Icons.help_outline:1051`).
  - `letter_card.dart:1127-1139` `_resolvedStatusIcon` (OUTGOING; reached → `_transportIcon(transport)` at :1136-1137); `:1144-1156` `_resolvedStatusSemantic`; `:1165-1179` `_sentViaSemantic` (relay/direct/reuse/wifi/local/inbox cases); `:1181-1195` `_receivedViaSemantic`.
  - `letter_card.dart:176-182` `_showsIncomingTransportGlyph`; `:1159-1162` `_resolvedIncomingSemantic`. Render sites: `:607-609`/`:615-618` (one layout) and `:668-670`/`:676-679` (the other branch).
  - `conversation_screen.dart:633` `transportStatusGlyph: true` — the **only** enabling site (1:1 conversation screen).
  - `lib/core/services/p2p_service_impl.dart:296-297` incoming transport = `msg.transport ?? _inferTransportForPeer(msg.from) ?? 'unknown'`; `:2991-3012` `_inferTransportForPeer`; **`:2996-2998` upgraded-set branch returns `'direct'` ← THE SEAM**; `:2978-2989` `transport:upgraded` → `recordRelayToDirectUpgrade` + `_recordPeerUpgrade` → `_peersUpgradedToDirect.add(remotePeerShort)`; `:2956` `_shortId` (last 8 chars).
  - `lib/core/database/migrations/012_transport_column.dart:28` `ALTER TABLE messages ADD COLUMN transport TEXT` — free-text values `wifi/local/direct/reuse/relay/inbox/NULL`.
  - `lib/l10n/app_en.arb:451-458` (8 `message_sent_via_*` / `message_received_via_*` keys); mirrored in `app_ar.arb` / `app_de.arb`.

## Session Classification

New Feature (additive, user-visible). Pure Dart + l10n. No Go/relay change. No DB migration. UI-isolated from the FDC Phase-0 collision file (`send_chat_message_use_case.dart`).

## Exact Problem Statement

**What's missing / who feels it / why.** When DCUtR upgrades a live relay connection to a direct one (the §6.5/P2-3 road, config-OFF today via `ForceReachabilityPrivate`), the message that travels post-upgrade is *more* direct than a native-direct send — but the per-message badge (plan-155) collapses it into the **same `device_hub` "direct" glyph** as a native-direct message, because `_inferTransportForPeer:2996-2998` knows the peer is in `_peersUpgradedToDirect` yet still returns the plain string `'direct'`. The only place the upgrade is currently surfaced is the **debug** `settings_transport_diagnostics_card` (`transport_metrics._relayToDirectUpgrades`). A user who started on relay and got upgraded cannot *see* the win.

**What must improve.** An upgraded message must render a **distinct glyph** (`Icons.upgrade`) and a **distinct a11y label** (`message_sent_via_upgraded` / `message_received_via_upgraded`), so the upgrade is visible on the 1:1 conversation screen — not just in a debug card.

**What must stay unchanged → preserved sentinels.**
- **PS-1** Native-direct messages (no upgrade) still render `Icons.device_hub` + "via direct" — `letter_card_test.dart:484-486` ("shows direct icon when transport is direct"), `:489-493` (legacy `reuse`→device_hub).
- **PS-2** Relay/wifi/local/inbox/null/unrecognized glyphs unchanged — `letter_card_test.dart:469-513` (incl. `:510-513` unrecognized→`help_outline`).
- **PS-3** A **non-upgraded** incoming peer still infers `'direct'` (live non-circuit conn) or `'unknown'` (no conn) — `p2p_service_inbound_transport_test.dart:241-274` (T4), `:347-352` (DCUTR-002 non-upgraded peer arm).
- **PS-4** Group / legacy (`transportStatusGlyph:false`) path keeps the v1 `_statusIcon`/`_statusSemantic` and shows **no** transport glyph — `letter_card_test.dart` group/legacy cases.
- **PS-5** Transport metrics counters (`relayToDirectUpgrades`, hole-punch counts) unchanged — `p2p_service_inbound_transport_test.dart:316-319`.

## Root Cause (verify→refute confirmed — file:line)

`p2p_service_impl.dart:2996-2998`:
```dart
if (_peersUpgradedToDirect.contains(_shortId(peerId))) {
  return 'direct';   // ← the upgrade is KNOWN here but flattened to plain direct
}
```
The upgraded-peer set is populated correctly at `:2987` from the `transport:upgraded` tracer event (`:2978-2981`), and `_inferTransportForPeer` is consulted for incoming messages at `:296-297`. The function therefore *has* the discriminating fact (this peer upgraded) but discards it. **Verified:** `_inferTransportForPeer`'s only caller is `:297` (incoming `msg.from`); `grep` shows references only at `:297`, `:319` (comment), `:2991` (def). The badge then loses the upgrade because `letter_card.dart:1042-1045` maps both `'direct'` and `'reuse'` to `device_hub` and there is no `'upgraded'` arm anywhere. **Refute check:** could the upgrade instead surface via the OUTGOING send transport? No — outgoing 1:1 transport comes from the Go stream label (`response['transport']`, `p2p_service_impl.dart:1992`,`:2010`) resolved by `send_chat_message_use_case.dart:1255-1266` `_resolveGoSendTransport` → `actualTransport` or `_inferDirectVsRelayForConnectedPeer:1252` (returns `'direct'`/`'relay'`, **never** consults `_peersUpgradedToDirect`). So OUTGOING data cannot be `'upgraded'` without a Go label change (FDC-12) or a collision-file edit — see Real Scope / Open Issues.

## Real Scope (In / Out → owning FDC-xx)

**In:**
1. Add an `'upgraded'` transport value rendering: `_transportIcon('upgraded') → Icons.upgrade`, `_sentViaSemantic`/`_receivedViaSemantic` → new `message_*_via_upgraded` keys (`letter_card.dart`). Widget supports it for **both** OUTGOING (`_resolvedStatusIcon`/`_resolvedStatusSemantic`) and INCOMING (`_showsIncomingTransportGlyph`/`_resolvedIncomingSemantic`) so it is direction-symmetric and future-proof.
2. Stop `_inferTransportForPeer` flattening an upgraded peer to `'direct'` — return `'upgraded'` for set members (`p2p_service_impl.dart:2996-2998`). This is the **INCOMING data path** (the only producer of `'upgraded'` today).
3. New l10n keys `message_sent_via_upgraded` + `message_received_via_upgraded` in `app_en.arb`/`app_ar.arb`/`app_de.arb` + regenerate `app_localizations*.dart`.

**Out (named owner):**
- Real-wire firing of `transport:upgraded` (DCUtR under a flag) → **FDC-12** (itself gated by **FDC-S2** QUIC-identify re-validation). FDC-13 drives the event **synthetically** on host.
- Surfacing `'upgraded'` on the **OUTGOING** send badge from production data (the Go stream returns `'direct'`) → needs a Go `'upgraded'` label (**FDC-12**) or a `send_chat_message_use_case.dart` reconciliation (the **Phase-0 collision file**, FDC-01..04) → **deferred** (Open Issue O1). FDC-13 ships the OUTGOING *widget render* (testable) but not the OUTGOING *data wiring*.
- Group surface / `message_bubble` → **N/A**: the feed "Letters" surface (`LetterBubble`, 134) renders **no** status/transport glyph; there is no feed transport-badge twin (Open Issue O2 corrects the prompt premise).
- Backfilling pre-existing persisted `'direct'` rows that were actually upgrades → out (only new receives after the fix carry `'upgraded'`; acceptable).

## Files To Inspect Next

- `lib/features/conversation/presentation/widgets/letter_card.dart` (`_transportIcon`, `_resolvedStatusIcon`, `_sentViaSemantic`, `_receivedViaSemantic`, `_resolvedIncomingSemantic`, `_showsIncomingTransportGlyph`).
- `lib/core/services/p2p_service_impl.dart:2956-3012` (`_shortId`, `_recordPeerUpgrade`, `_inferTransportForPeer`).
- `lib/l10n/app_en.arb` / `app_ar.arb` / `app_de.arb` + `l10n.yaml` regen.
- Tests: `test/features/conversation/presentation/widgets/letter_card_test.dart` (transport-icon group `:468-513`; "155 transport status glyph" group `:2265-2356`); `test/core/services/p2p_service_inbound_transport_test.dart` (DCUTR-002 `:276-356`, T4 `:241-274`).

## Existing Tests Covering This Area (named; which gate arrays list them)

- `test/features/conversation/presentation/widgets/letter_card_test.dart` — **in `ONE_TO_ONE_TESTS`** (`scripts/run_test_gates.sh`, 1to1 gate) and AUTO-globbed by `feature-host-all`. Owns the transport-icon + 155-status-glyph groups.
- `test/core/services/p2p_service_inbound_transport_test.dart` — **NOT** in any curated array; covered only by `core-host-all` glob (`test/core/**`). DCUTR-002 (`:276-356`) is the existing lock on `_inferTransportForPeer`'s upgraded-peer behavior; **its `:348` assertion `transport == 'direct'` is the exact lock FDC-13 flips.** → Plan adds this file to `ONE_TO_ONE_TESTS` so the flip is a 1:1 headline gate.
- `test/features/conversation/presentation/screens/conversation_screen_test.dart` / `conversation_wired_test.dart` — in `ONE_TO_ONE_TESTS`; exercise the `transportStatusGlyph:true` wiring (PS-4 group-vs-1:1 boundary).

## RED Test Catalog (BEFORE prod code)

> Distinct-event discriminator rule: every `'upgraded'` assertion **also** asserts the message does **NOT** render the plain `'direct'` glyph/label (`Icons.device_hub` / `message_sent_via_direct`) **and not** the `help_outline` fallback — proving the new value is mapped, not falling through.

**Widget tier — `letter_card_test.dart` (transport-icon group `:468-513`):**

- **RT-W1** `letter_card_test.dart::"shows upgrade icon when transport is upgraded"`
  - Tier: widget. Shape: `buildTestWidget(transport: 'upgraded')` (the existing helper at `:23/:43/:59/:79`, with `transportStatusGlyph` default per group).
  - RED-on-HEAD-because: `_transportIcon` has no `'upgraded'` arm → falls to `default → Icons.help_outline:1051`.
  - GREEN-asserts: `find.byIcon(Icons.upgrade)` findsOneWidget; **AND** `find.byIcon(Icons.device_hub)` findsNothing; **AND** `find.byIcon(Icons.help_outline)` findsNothing.
  - Mutation-that-re-reds: change the new arm `case 'upgraded': return Icons.upgrade;` → `return Icons.device_hub;` (re-reds on device_hub-findsNothing).

**Widget tier — `letter_card_test.dart` ("155 transport status glyph" group `:2265-2356`, `transportStatusGlyph:true`):**

- **RT-W2 (OUTGOING glyph)** `::"TC-13 outgoing reached via upgraded → upgrade icon (not device_hub, not inbox)"`
  - Shape: `buildTransportGlyph(status: 'delivered', transport: 'upgraded')` (helper `:2278`).
  - RED-because: `_resolvedStatusIcon:1136-1137` calls `_transportIcon` which lacks the arm → `help_outline`.
  - GREEN: `Icons.upgrade` findsOneWidget; `Icons.device_hub` findsNothing; `Icons.inbox_rounded` findsNothing.
  - Mutation: as RT-W1.
- **RT-W3 (OUTGOING a11y)** `::"TC-13 outgoing upgraded a11y → message_sent_via_upgraded (not via_direct)"`
  - Shape: same widget; read `Semantics` label via the status-glyph semantics node.
  - RED-because: `_sentViaSemantic:1165-1179` returns `null` for `'upgraded'` → `_resolvedStatusSemantic:1152-1153` falls back to the generic `message_status_semantics` label, never the new string.
  - GREEN: label == `l10n.message_sent_via_upgraded`; **AND** label != `l10n.message_sent_via_direct`.
  - Mutation: drop the `case 'upgraded':` from `_sentViaSemantic` → re-reds.
- **RT-W4 (INCOMING glyph)** `::"TC-13 incoming via upgraded shows the incoming upgrade glyph"`
  - Shape: `buildTransportGlyph(isIncoming:true, transport:'upgraded')` (incoming path; `_showsIncomingTransportGlyph:176-182` already fires for any non-system/non-unknown transport — `'upgraded'` qualifies).
  - RED-because: incoming glyph uses `_resolvedIncomingSemantic`/`_transportIcon`; `_transportIcon('upgraded')` → `help_outline`.
  - GREEN: `Icons.upgrade` findsOneWidget; `Icons.device_hub` findsNothing.
  - Mutation: as RT-W1.
- **RT-W5 (INCOMING a11y)** `::"TC-13 incoming upgraded a11y → message_received_via_upgraded (not via_direct)"`
  - Shape: incoming `'upgraded'`; read `_resolvedIncomingSemantic:1159-1162` label.
  - RED-because: `_receivedViaSemantic:1181-1195` returns `null` for `'upgraded'` → falls back to generic.
  - GREEN: label == `l10n.message_received_via_upgraded`; **AND** != `l10n.message_received_via_direct`.
  - Mutation: drop the `case 'upgraded':` from `_receivedViaSemantic` → re-reds.

**Service tier — `p2p_service_inbound_transport_test.dart` (the `_inferTransportForPeer` seam):**

- **RT-S1 (flip DCUTR-002 upgraded arm)** modify the existing `::"DCUTR-002: transport diagnostics drive exact counters and upgrade inference"` (`:276-356`).
  - Shape: already emits `transport:upgraded` for `remotePeerShort:'abc12345'` (`:309-314`), then delivers an incoming `ChatMessage(from: upgradedPeerId='...abc12345', transport:null)` (`:324-333`) and a non-upgraded incoming (`:334-343`). `_shortId` keeps the last 8 chars (`:2956`), so `upgradedPeerId` ends in `abc12345` → set hit.
  - RED-because: `_inferTransportForPeer:2997` returns `'direct'`; current asserts `received[0].transport == 'direct'` (`:348`).
  - GREEN-asserts (the flip): `received[0].transport == 'upgraded'`; `metrics.transportMix()['upgraded'] == 1`; `metrics.transportMix()['direct'] == 0`. **Discriminator / PS-3 preserved:** `received[1].transport == 'unknown'` (non-upgraded peer unchanged), `metrics.relayToDirectUpgrades == 1` (PS-5).
  - Mutation-that-re-reds: revert `:2997` `return 'upgraded';` → `return 'direct';` (re-reds on `received[0]=='upgraded'`).
  - distinct-event discriminator: the **upgraded** peer and the **non-upgraded** peer yield different strings (`'upgraded'` vs `'unknown'`) in the *same* test — proves the set membership, not a blanket relabel.
- **RT-S2 (preservation: live non-circuit conn still `direct`)** keep/extend T4 (`:241-274`): a peer with a `/ip4/.../tcp/` conn but **not** in the upgraded set → `received.single.transport == 'direct'` (PS-3). Already green; pin it as a regression floor (assert it stays green post-change).

**Integration tier — receiver flow-event readout (same file, new test):**

- **RT-I1** `p2p_service_inbound_transport_test.dart::"DCUTR-013: synthetic upgrade event surfaces 'upgraded' on the receiver readout"`
  - Shape: capture `emitFlowEvent` (the test harness already observes flow events for `MSG_RECEIVED_TRANSPORT`, `p2p_service_impl.dart:302-309`); emit `transport:upgraded` for a peer, deliver an incoming `transport:null` message from it, then assert the captured `MSG_RECEIVED_TRANSPORT` detail `transport == 'upgraded'` **and** the streamed `ChatMessage.transport == 'upgraded'`.
  - RED-because: pre-fix the readout is `'direct'`.
  - GREEN: both readouts `'upgraded'`.
  - Mutation: as RT-S1 (`:2997`).
  - distinct-event discriminator: this locks the **end-to-end persisted/streamed + greppable** path (`copyWith(transport:)` at `:310`), distinct from RT-S1 which locks the `transportMix` census — same result, two different observation channels.

**RED count: 7** (RT-W1..W5, RT-S1, RT-I1; RT-S2 is a preservation pin, not a new RED).

## Test Coverage Matrix (zero empty cells)

| Spec case | Behavior props | Tier | Test file::name | RED reason | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| `_transportIcon('upgraded')` maps to a distinct glyph | glyph=upgrade, not device_hub/help_outline | widget | `letter_card_test.dart::shows upgrade icon when transport is upgraded` (RT-W1) | no `'upgraded'` arm → help_outline | `case 'upgraded'→Icons.device_hub` | `./scripts/run_test_gates.sh 1to1` | in `ONE_TO_ONE_TESTS` (already) + `feature-host-all` glob |
| OUTGOING reached upgraded → upgrade glyph | `_resolvedStatusIcon` routes upgraded | widget | `letter_card_test.dart::TC-13 outgoing reached via upgraded → upgrade icon` (RT-W2) | `_transportIcon` lacks arm | as RT-W1 | `1to1` | same |
| OUTGOING upgraded a11y | `message_sent_via_upgraded`, not via_direct | widget+a11y | `letter_card_test.dart::TC-13 outgoing upgraded a11y` (RT-W3) | `_sentViaSemantic` returns null | drop `_sentViaSemantic` upgraded case | `1to1` | same |
| INCOMING upgraded → glyph | `_showsIncomingTransportGlyph` + glyph | widget | `letter_card_test.dart::TC-13 incoming via upgraded shows the incoming upgrade glyph` (RT-W4) | `_transportIcon` lacks arm | as RT-W1 | `1to1` | same |
| INCOMING upgraded a11y | `message_received_via_upgraded`, not via_direct | widget+a11y | `letter_card_test.dart::TC-13 incoming upgraded a11y` (RT-W5) | `_receivedViaSemantic` returns null | drop `_receivedViaSemantic` upgraded case | `1to1` | same |
| `_inferTransportForPeer` upgraded peer → `'upgraded'` data | upgraded peer relabel; non-upgraded unchanged | service | `p2p_service_inbound_transport_test.dart::DCUTR-002 …` (RT-S1, flip `:348`) | `:2997` returns `'direct'` | revert `:2997`→`'direct'` | `core-host-all` + add to `1to1` | **ADD file to `ONE_TO_ONE_TESTS`** |
| Non-upgraded peer still `'direct'` (PS-3) | preservation floor | service | `p2p_service_inbound_transport_test.dart::T4 …` (RT-S2) | n/a (stays green) | n/a (regression pin) | `core-host-all` + `1to1` | same add |
| End-to-end synthetic event → receiver readout `'upgraded'` | streamed + `MSG_RECEIVED_TRANSPORT` flow event | integration | `p2p_service_inbound_transport_test.dart::DCUTR-013 …` (RT-I1) | readout is `'direct'` pre-fix | revert `:2997` | `core-host-all` + `1to1` | same add |
| New l10n keys resolve | `message_*_via_upgraded` exist in en/ar/de | (covered by RT-W3/W5 via `l10n.message_*_via_upgraded`) | — | key absent → compile/lookup fail | remove key from arb | `flutter analyze` + `1to1` | l10n auto-gen |

## Blind-Spot Sweep

- **Lifecycle / derived-state durability:** `'upgraded'` is persisted into the existing TEXT `transport` column via `copyWith(transport:)` (`p2p_service_impl.dart:310`) → durable across reloads exactly like `'direct'`. Old `'direct'` rows are not retroactively rewritten (Open Issue O3) — acceptable; new receives carry the value. Row: covered by RT-I1 (streamed/persisted readout).
- **Sibling-surface consistency:** within `letter_card.dart` the badge has **two** render paths — OUTGOING (`_resolvedStatusIcon`/`_resolvedStatusSemantic`) and INCOMING (`_showsIncomingTransportGlyph`/`_resolvedIncomingSemantic`); **both** must map `'upgraded'`. Locked by RT-W2/W3 (outgoing) + RT-W4/W5 (incoming). **Feed twin:** N/A — verified `LetterBubble` (`lib/features/feed/presentation/widgets/letter_bubble.dart`) is a pure leaf with **no** status/transport glyph (134 "Letters" dropped status ticks); `feed_screen.dart` uses `LetterCardOneToOne/Group/System` (→ `LetterBubble`), **not** the conversation `LetterCard`. So there is **no** feed sibling to keep in sync (corrects the prompt's "feed message_bubble parallel mapping" premise — Open Issue O2).
- **Destructive side-effects:** none — additive new value + new l10n keys; no existing arm changed except `_inferTransportForPeer:2997` (a single string, guarded by an already-correct set membership).
- **Invariant re-verification:** PS-1/PS-2 (existing glyph map) untouched — only a new arm added; pinned by the unchanged `letter_card_test.dart:469-513` cases. PS-4 (group/legacy shows no glyph) untouched — `transportStatusGlyph` gate unchanged; pinned by existing group/legacy cases. PS-5 (metrics) pinned by RT-S1's `relayToDirectUpgrades==1`.

## Invariants (locked by tests)

- **INV-1** An upgraded peer's incoming message persists/streams `transport == 'upgraded'`, never `'direct'` (RT-S1, RT-I1).
- **INV-2** `'upgraded'` renders `Icons.upgrade` on both directions, never `device_hub`/`help_outline` (RT-W1/W2/W4).
- **INV-3** `'upgraded'` a11y reads "via upgraded", never "via direct" or the generic status fallback (RT-W3/W5).
- **INV-4** A non-upgraded peer is unaffected: native-direct stays `'direct'`/`device_hub`/"via direct"; no-conn stays `'unknown'` (PS-1/PS-3; RT-S1 discriminator, RT-S2, existing `:484-486`).
- **INV-5** Group/legacy (`transportStatusGlyph:false`) shows no transport glyph (PS-4, unchanged gate).

## Step-By-Step Implementation Plan (RED first; name the seam)

1. **RED** — add RT-W1 (transport-icon group) + RT-W2..W5 (155 group) in `letter_card_test.dart`; flip RT-S1 (DCUTR-002 `:348`) + add RT-I1 in `p2p_service_inbound_transport_test.dart`. Run `1to1` + `core-host-all` → confirm all 7 RED for the stated reasons (W: help_outline/null-label; S/I: `'direct'`).
2. **l10n seam** — add `message_sent_via_upgraded` ("Upgraded to direct connection") + `message_received_via_upgraded` ("Received via upgraded direct connection") to `app_en.arb`, `app_ar.arb`, `app_de.arb`; regenerate `app_localizations*.dart` (`flutter gen-l10n` / build runner per `l10n.yaml`).
3. **Widget seam** — in `letter_card.dart`: add `case 'upgraded': return Icons.upgrade;` to `_transportIcon` (`:1037-1053`); add `case 'upgraded': return l10n.message_sent_via_upgraded;` to `_sentViaSemantic` (`:1165-1179`); add `case 'upgraded': return l10n.message_received_via_upgraded;` to `_receivedViaSemantic` (`:1181-1195`). (`_resolvedStatusIcon`/`_showsIncomingTransportGlyph` need no change — they already route any non-null transport through `_transportIcon` and fire for non-system/unknown transports.) → RT-W1..W5 GREEN.
4. **Service seam** — in `p2p_service_impl.dart:2996-2998` change `return 'direct';` → `return 'upgraded';`. → RT-S1, RT-I1 GREEN; RT-S2/PS-3 stays green.
5. **Harness** — append `test/core/services/p2p_service_inbound_transport_test.dart` to `ONE_TO_ONE_TESTS` in `scripts/run_test_gates.sh`.
6. **Mutation pass** — apply each "Mutation-that-re-reds" (RT-W1, RT-W3, RT-W5, RT-S1) and confirm RED; revert.
7. **Gates** — `flutter analyze` (0 new), `git diff --check`, `1to1`, `feature-host-all`, `core-host-all`.

## Risks And Edge Cases (each pinned by a test)

- **Unrecognized value falls to help_outline** (if a typo'd value reaches the badge) — already-correct fallback preserved (`:510-513`); RT-W1 explicitly asserts `'upgraded'` is **not** help_outline.
- **Set membership uses `_shortId` (last 8 chars)** — a collision would mislabel a different peer. Pinned by RT-S1: the upgraded peer (`...abc12345`) labels `'upgraded'` while the unrelated `'not-upgraded-peer'` labels `'unknown'`.
- **OUTGOING data still `'direct'`** (Go label) — RT-W2/W3 prove the *widget* renders upgraded, but no service test asserts an *outgoing* `'upgraded'` persistence (it can't be produced yet); documented as O1, not silently masked.
- **l10n key missing in ar/de** — `flutter analyze` + generated-getter usage in RT-W3/W5 fail if any locale lacks the key.

## Device/Relay Proof Profile

Host-testable **now** end-to-end via the synthetic `transport:upgraded` event (RT-I1) — no device needed for the badge. **Real-wire** firing of `transport:upgraded` only occurs once DCUtR is enabled (**FDC-12**, gated by **FDC-S2** QUIC-identify re-validation, device-only because the iOS sim shares a host mDNS stack → `DISABLE_LOCAL_DISCOVERY`, §6.5). Device-proof of an *actual* upgrade→badge is therefore **deferred to FDC-12's device profile**; FDC-13 closes on host gates for the value/glyph/a11y/infer logic.

## Acceptance Gates (LITERAL cmds + expected counts as TODO)

```
# RED first (expect 7 new failures), then GREEN after steps 2-5:
./scripts/run_test_gates.sh 1to1                 # baseline 1226 (FDC-S0) → +N green
./scripts/run_host_test_gates.sh core-host-all   # 0 fail (249/249 core files PASS, 0 fail) (p2p_service_inbound_transport_test green)
./scripts/run_host_test_gates.sh feature-host-all# 0 fail (files auto-glob into 1to1/feed/groups; full feature-host sweep deferred) (letter_card_test green)
flutter analyze                                  # TODO: 0 new
git diff --check                                 # TODO: clean (no whitespace errors)
```
No `transport` integration gate change needed (badge is unit/widget/service-tier). Re-run `1to1` after the l10n regen so the generated `app_localizations*.dart` is exercised.

## Known-Failure Interpretation

- If RT-S1 still asserts `'direct'` post-change, the `_shortId` of the test's `upgradedPeerId` did not end in the emitted `remotePeerShort` — check the `:281-282` constants align (last-8 rule).
- A `help_outline` in RT-W1/W4 after step 3 means the `_transportIcon` arm was added below the `default` or the value string differs (`'upgraded'` exact).
- A generic "Message status: …" label in RT-W3/W5 means `_sentViaSemantic`/`_receivedViaSemantic` returned null (missing case) or the l10n key wasn't regenerated.

## Done Criteria

- [ ] RT-W1..W5 + RT-S1 + RT-I1 GREEN; RT-S2/PS-3 still GREEN.
- [ ] Each mutation re-reds its test; reverted.
- [ ] `message_sent_via_upgraded` + `message_received_via_upgraded` in en/ar/de + regenerated getters.
- [ ] `_transportIcon`/`_sentViaSemantic`/`_receivedViaSemantic` have an `'upgraded'` arm; `_inferTransportForPeer:2997` returns `'upgraded'`.
- [ ] `p2p_service_inbound_transport_test.dart` added to `ONE_TO_ONE_TESTS`.
- [ ] `1to1` / `core-host-all` / `feature-host-all` green; `flutter analyze` 0 new; `git diff --check` clean.
- [ ] Open Issues O1-O3 recorded in the FDC-00 gap entry / FDC-12 cross-link.

## Scope Guard (hard Do-not)

- Do **NOT** edit `lib/features/conversation/application/send_chat_message_use_case.dart` (the FDC-01..04 Phase-0 collision file). The OUTGOING data wiring is out of scope (O1).
- Do **NOT** add a DB migration or bump the schema version (existing TEXT column).
- Do **NOT** touch the group / feed surfaces (no transport glyph there).
- Do **NOT** change any existing `_transportIcon`/semantic arm except adding the new `'upgraded'` cases; do not alter the `transportStatusGlyph` gate (PS-4).
- Do **NOT** rebuild or rename transport metrics counters (PS-5).

## Accepted Differences

- The OUTGOING badge will render `'upgraded'` only once upstream data supplies it (FDC-12 / a future reconciliation). The widget support shipped now is intentional and inert for outgoing until then.
- Pre-fix persisted `'direct'` rows that were genuinely upgrades stay `'direct'` (no backfill).
- `Icons.upgrade` chosen as the distinct glyph (an up-arrow badge), free of collision with `device_hub`/`cell_tower`/`wifi`/`inbox`/`help_outline`.

## Dependency Impact

- **Pairs with FDC-12** (real-wire firing; FDC-12 gated by FDC-S2). FDC-13 is **ungated** for host badge tests.
- **Secondary collision:** `p2p_service_impl.dart` is also edited by **FDC-04** (`warmPeer`/`discoverLocalPeer`/`isLocalPeer`, `:4097/:4132`) and **FDC-08** (presence cache, `:4074-4089`) — but FDC-13 touches a **disjoint region** (`:2996-2998`). If co-scheduled with FDC-04/08, serialize (different lines, low risk).
- `letter_card.dart` is **UI-isolated**: no FDC plan (FDC-01..04 edit `send_chat_message_use_case.dart`, not UI). No collision there.
- Adds one entry to `scripts/run_test_gates.sh ONE_TO_ONE_TESTS` (read-only array).
