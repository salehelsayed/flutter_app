# FDC-14 — Self "online" dot also expresses "directly reachable" + badge anti-flap  (New Feature)

Status: ✅ IMPLEMENTED — host-green, committed in `5f21d790` ("P0 complete — fast-direct-connection epic"). Render + anti-flap landed (39/39 tests, all 10 plan mutations re-redded); the `directReady` producer (**FDC-14b**) is still unwired, so `onlineDirect` is renderable-from-injected-state but **unreachable in production** (by design). See **§Implementation Status (as-built)** and **§Open Issues**.
Spec: Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md (§6.3 "online-ish never foreground", §6.5 LAN-direct end-state, §7 per-peer/app state machine) + FDC-00 "Known gaps from the design Q&A review" → **GAP — the self "online" green dot** (FDC-00-roadmap.md self-online-dot gap)

> **DRAFT for the signal wiring.** The new-tier *rendering* + *anti-flap* tests are concrete and
> host-testable NOW against an injected `NodeState`. The **direct-ready signal SOURCE** (`directReady`)
> is **PROVISIONAL `<from FDC-02 / FDC-11>`** — FDC-02 lands the ranked-race "LAN/direct leg is live"
> notion and FDC-11 lands the bonsoir-fed libp2p LAN-direct dial's LAN address. **Caveat (verified
> 2026-06-26):** those two plans land the *upstream raw signal* but **neither currently defines, emits,
> or schedules a `NodeState.directReady` producer** (zero `directReady`/`onlineDirect`/`NodeState`
> mentions in either; FDC-02 emits only per-message transport *labels* + `relayLiveSendCount`). So the
> producer wiring is an **UNOWNED follow-on** — call it **FDC-14b** — that must *derive* `directReady`
> from whatever FDC-02/FDC-11 expose. Until it ships, `directReady`
> has no production producer and the new tier is **unreachable in production but fully renderable from
> an injected state**. This plan locks the *contract* (a new input + a new tier + a distinct label +
> the anti-flap invariant); the producer wiring is a follow-on stop-if (Step 9).

---

## Implementation Status (as-built — 2026-06-27)

> **This plan was reviewed (2026-06-26, ~16 edits) and then IMPLEMENTED & committed.** The sections
> below the line remain the original pre-implementation design record; this block + the marked
> **POST-IMPL CORRECTION** in §Blind-Spot Sweep + the enriched §Open Issues fold back what the build
> actually discovered (some of which the original blind-spot sweep undercounted).

**Landed and committed** in `5f21d790`. 5 files, ≈ +430 / −6. Host-green: **39/39** new tests (20 in
`node_state_test.dart`, 19 in `connection_status_indicator_test.dart`); all **10 plan mutations**
re-redded then reverted; `flutter analyze` **0-new** (after the integration-test fix called out below);
`p2p_service_impl_test` green (84 — no exhaustive `switch` there, so the Step-0 arm was NOT needed).

**As-built values (resolving the plan's implementer-pick slots):**
- **Visible label `'Online ✦'`** — `Online` + U+2726 BLACK FOUR POINTED STAR
  (`connection_status_indicator.dart:58`). Distinct from BOTH `'Online.'` and plain `'Online'`.
- **Semantics label `'online, send and inbox ready, directly reachable'`** (`:72-73`) — the **binding**
  distinctness (T7); contains `'directly reachable'`, not `'relay reservation'`.
- **Computation is the BARE `if (directReady) return BadgeReadinessState.onlineDirect;`** at
  `node_state.dart:167`, placed **immediately after** the `if (!usabilityReady) return connecting;`
  early return (`:163`). So the `usabilityReady` gate is enforced by **control-flow order**, NOT by the
  compound `if (usabilityReady && directReady)` the plan's INV-1 / Step-4 phrased — behaviourally
  identical here, but **do not "tidy" it into the compound form without preserving the `:163` early
  return**: that ordering is load-bearing for INV-1 (T5 list-2 proves `directReady` never bypasses the
  gate).
- `toJson` is **Pattern B** (unconditional `result['directReady'] = directReady;` at `:111`); field +
  FDC-14b doc comment at `node_state.dart:23-28` (ctor default `false` at `:44`).

**Anchor refresh (plan cite → as-built on HEAD; positional drift only — every code site is present and intact):**

| Symbol | Plan cites | As-built on HEAD |
|---|---|---|
| `BadgeReadinessState` enum (+`onlineDirect`) | `node_state.dart:3` | `:3` ✓ accurate |
| `badgeReadinessState` getter / `onlineDirect` arm | `:136-153` | getter `:161-171`, arm `:167` (**drift ~+25**) |
| `toString` `directReady` fragment | `:155-161` | `:173-180`, fragment `:179` (**drift ~+18**) |
| `_isReadyBadgeState` / `_legacyHealthForBadgeState` | `:34-46` | `:34-38` / `:40-48` ✓ accurate |
| `_labelForBadgeState` onlineDirect arm | `:48-66` | `:58` (in range) |
| `_semanticsLabelForBadgeState` onlineDirect arm | `:48-66` | `:72-73` (**now BELOW the cited range**) |
| colour switch onlineDirect case | `:147-164` | switch `:157-175`, case `:160` (**drift ~+10**) |
| `_onState` emit gate | `:100-130` | `:110-140` (**drift ~+10**) |

**Test strengthenings landed (stronger than the plan text — keep them):**
- **T6** asserts the label `isNot 'Online.'` **AND** `isNot 'Online'` (plan required only `≠ 'Online.'`).
- **T9** locks BOTH the label **Text** colour **and** the **status-DOT `Container`** colour
  (`BoxShape.circle` `baseColor == Colors.green`, via a `_dotColor` helper that uniquely selects the
  circle decoration) — a dot-only colour mutation (dot red / text green) slips past the original
  text-only T9.
- **T8 harness gotcha (REQUIRED, was not in the plan).** The indicator is pumped with **no `Key`**, so
  re-pumping reuses the same `Element`/`State` and `initState` does **not** re-run (it stays subscribed
  to the prior, now-disposed `StreamController`). The two-sub-case T8 therefore **unmounts between
  sub-cases** with `await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink())); await tester.pump();`
  (`connection_status_indicator_test.dart:519-520`) so the `connecting→direct` first-ready emit fires on
  a **fresh** State. Without it, sub-case B asserts against stale state and the count is wrong.

---

## Source Of Truth

- **Design**: `Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md` — §6.3 (presence is
  "online-ish, TTL-lagged, NEVER foreground"), §6.5 (LAN-direct over libp2p, the relay→direct upgrade
  DCUtR cannot deliver under `ForceReachabilityPrivate`), §7 (`HOT_LAN | HOT_DIRECT | HOT_RELAY`
  per-peer states). The "directly reachable" axis is **self-reachability** (can *I* be reached / do *I*
  hold a non-relay path), distinct from peer-presence.
- **Roadmap gap**: `FDC-00-roadmap.md` self-online-dot gap — "GAP — the self 'online' green dot": the dot is
  driven by `NodeState.badgeReadinessState` (grey=offline / amber=connecting / green=send+inbox-ready /
  green-dot=also relay-reserved), is **untouched by any plan**, yet FDC-05/06/07 move the very
  lifecycle timings that drive it. Two asks: **(a)** anti-flap note on FDC-05/06/07; **(b)** a NEW
  "reachable for a direct connection" tier = **this plan (FDC-14)**, sequenced after FDC-02/FDC-11.
  "Peer-presence (FDC-08/09) is a **different** axis and never feeds this dot."
- **Live code (verified by Read this session)**:
  - `lib/features/p2p/domain/models/node_state.dart:3` — `enum BadgeReadinessState { offline, connecting, online, onlineDotted }`.
  - `node_state.dart:136-142` — `relayReady` = `isStarted && (relayState != null ? relayState=='online' : circuitAddresses.isNotEmpty)` — a **guarded branch** (circuit consulted only when `relayState` is null, behind an `!isStarted` gate), NOT a flat OR.
  - `node_state.dart:144-145` — `usabilityReady = isStarted && sendCapabilityReady && inboxCapabilityReady`.
  - `node_state.dart:147-153` — `badgeReadinessState`: `!isStarted`→offline; `!usabilityReady`→connecting; else `relayReady ? onlineDotted : online`.
  - `lib/features/p2p/presentation/widgets/connection_status_indicator.dart:48-66` — `_labelForBadgeState` / `_semanticsLabelForBadgeState` (exhaustive switches over the 4 tiers); `:147-164` colour switch; `:34-46` `_isReadyBadgeState` / `_legacyHealthForBadgeState`; `:100-130` `_onState` (applies downgrades immediately).
  - Mount sites: `lib/features/feed/presentation/widgets/feed_header.dart:48`; `lib/features/home/presentation/screens/first_time_experience_screen.dart:146`.
- **Existing tests**: `test/features/p2p/domain/models/node_state_test.dart`;
  `test/features/p2p/presentation/widgets/connection_status_indicator_test.dart`.

## Session Classification

New Feature (additive `BadgeReadinessState` tier + a `NodeState` input) carrying a **lifecycle
durability/anti-flap** invariant. Pure-Dart, host-testable. Tiers: unit (`node_state.dart` tier
computation) + widget (indicator renders the new tier + distinct label/semantics) + an anti-flap
unit-or-widget test. No relay/Go deploy. No migration.

## Exact Problem Statement

**What's missing / who feels it / why.** The self-status dot (top of Feed header, FTE screen) tops
out at "Online." = *send+inbox+relay-reserved*. The Fast-Direct-Connection design introduces a path
the dot **cannot express**: the node is **directly reachable** (a LAN/mDNS address is being advertised
and/or a non-relay reachable address exists) — strictly "more connected" than relay-reserved. A user
on the same WiFi as their peer, whose node holds a live direct/LAN path, sees the identical "Online."
badge they'd see when only the relay is reserved. The *road-taken* for the headline feature
("same-WiFi → talk directly", proposal §1) is invisible at the self-status level.

Separately, FDC-05/06/07 **re-time** resume / pause / cold-start — the exact transitions that drive
`badgeReadinessState`. If a resume momentarily reports `sendCapabilityReady=false` (mid re-prime), the
badge **flaps green→amber("connecting")→green**, which reads as "it disconnected." There is no test
guarding that the dot does NOT spuriously drop to `connecting` on these transitions.

**What must improve.**
1. A NEW `BadgeReadinessState.onlineDirect` tier **above** `onlineDotted`, computed from a NEW
   `NodeState.directReady` input, rendered by `ConnectionStatusIndicator` with **its own distinct
   visible label + distinct semantics label** (a screen reader must hear "directly reachable", not the
   relay-reservation phrasing).
2. A locked **anti-flap** assertion: a ready badge (`online`/`onlineDotted`/`onlineDirect`) does NOT
   transition to `connecting` across a resume/pause/cold-start emission sequence **unless** the node
   genuinely lost send-or-inbox capability.

**What must stay unchanged → preserved sentinels.**
- **PS-1** Existing 4 tiers' visible text: `'Offline'` / `'Connecting'` / `'Online'` / `'Online.'`
  (`connection_status_indicator.dart:48-55`) — byte-identical.
- **PS-2** Existing semantics labels for the 4 tiers (`:57-66`) — byte-identical.
- **PS-3** `usabilityReady`, `relayReady` semantics and the `online`/`onlineDotted` computation
  (`node_state.dart:136-153`) — unchanged; `onlineDirect` is a **strictly higher** branch that only
  fires when `directReady` is true *on top of* `usabilityReady`.
- **PS-4** `TIME_TO_ONLINE_BADGE_WIDGET` emission contract (`:113-124`) — still fires exactly once on
  the first not-ready→ready transition; `onlineDirect` counts as ready, and online↔dotted↔direct moves
  do NOT re-emit (the §24 "does not emit between Online and Online." invariant generalizes).
- **PS-5** `ConnectionHealth` legacy mapping (`:39-46`, `healthFromState :26-32`) keeps mapping every
  ready badge → `ConnectionHealth.online` (no new legacy enum value).
- **PS-6** Default `directReady=false` ⇒ every existing `NodeState(...)` literal and the live bridge
  (which does not yet emit the field) keeps producing the SAME badge it does today (no silent
  promotion). FDC-00: "Keeping the dot inbox/relay-based is fine."

## Root Cause (verify→refute confirmed — file:line)

Not a bug — a **deliberate scope boundary**. The badge enum is closed at 4 values
(`node_state.dart:3`) and `badgeReadinessState` (`:147-153`) has no branch above `onlineDotted`; the
`NodeState` model carries relay/circuit/capability inputs but **no direct/LAN-reachability input** (no
`directReady`/`lanReady` field anywhere in `node_state.dart:6-37`). Confirmed by Read: the indicator's
two label switches (`connection_status_indicator.dart:48-66`) are exhaustive over exactly the 4 tiers,
so adding a 5th enum value will **fail to compile** until both are extended — the compiler enforces the
render-completeness this plan needs (a useful RED for the widget tier). **Refute check**: there is no
pre-existing `NodeState.directReady` field, `onlineDirect` enum, or `lanReady` token anywhere — nothing
to reuse; this is genuinely additive. (Precision: a `directReady` *identifier* does exist in lib/ as an
unrelated **posts-feature local var** — `post_follow_on_delivery.dart:116,121`,
`post_delivery_runner.dart:661,666` — a different namespace, not the `NodeState` field; don't be misled
by a bare `grep directReady`.)

The anti-flap gap: `_onState` (`:100-130`) **applies ready→not-ready downgrades immediately** (locked
by the existing test "applies ready-state downgrades immediately", indicator_test:365-384). That is
correct *when the node truly lost capability*, but means the **producer** (NodeState emission sequence
from FDC-05/06/07) is the only place a spurious dip can be prevented — the widget intentionally does
not debounce. So the anti-flap invariant must be asserted at the **NodeState computation tier** (a
sequence of states whose `badgeReadinessState` never dips to `connecting`) and re-asserted as a
producer-side acceptance note inside FDC-05/06/07 (see §Open Issues — already mirrored there).

## Real Scope (In / Out → owning FDC-xx)

**In (this plan):**
- `node_state.dart`: NEW `directReady` field (default false; json/copyWith/toString plumbing) + NEW
  `onlineDirect` enum value + the `badgeReadinessState` branch (`usabilityReady && directReady` →
  `onlineDirect`, ranked above `onlineDotted`).
- `connection_status_indicator.dart`: extend both label switches + the colour switch + `_isReadyBadgeState`
  + `_legacyHealthForBadgeState` to cover `onlineDirect`; render distinct visible + semantics label.
- Tests: unit tier computation + ordering, widget render + distinct-label discriminator, anti-flap.

**Out:**
- The **`directReady` producer / signal source** — PROVISIONAL `<from FDC-02 (ranked race "LAN/direct
  leg live") / FDC-11 (libp2p LAN-direct dial, bonsoir-fed LAN address)>`. FDC-02/FDC-11 land the
  *upstream* signal, but **neither schedules a `NodeState.directReady` producer** (verified 2026-06-26 —
  see DRAFT caveat). Wiring the bridge/`p2p_service_impl` to *derive and emit* `directReady=true` is an
  **UNOWNED follow-on (FDC-14b)**, gated on FDC-02/FDC-11 but not owned by them (Step 9 stop-if). This
  plan defines the field; it does not connect a live producer.
- **Peer-presence** ("is the *other* peer reachable") — a DIFFERENT axis, **owned by FDC-08 / FDC-09**.
  It must **NEVER** feed this self-dot (FDC-00 self-online-dot gap). Belt: an explicit test asserts peer-presence-style
  inputs (e.g. a presence cache / a peer connection) do NOT flip `onlineDirect`.
- Per-message transport "upgraded" badge — owned by **FDC-13** (different surface: `letter_card.dart`).
- Anti-flap producer re-timing itself — owned by **FDC-05 / FDC-06 / FDC-07** (this plan supplies the
  paste-ready assertion; see §Open Issues).

## Files To Inspect Next

- `lib/features/p2p/domain/models/node_state.dart` (model + enum + computation).
- `lib/features/p2p/presentation/widgets/connection_status_indicator.dart` (3 switches + readiness helpers).
- `lib/features/feed/presentation/widgets/feed_header.dart:48` and
  `lib/features/home/presentation/screens/first_time_experience_screen.dart:146` (mount sites — confirm
  no caller branches on the enum value; both just pass `p2pService`).
- `lib/core/services/p2p_service_impl.dart` (FUTURE producer of `directReady`; **read-only here** —
  do not edit; that is FDC-02/FDC-11).
- `test/features/p2p/domain/models/node_state_test.dart` and
  `test/features/p2p/presentation/widgets/connection_status_indicator_test.dart` (extend in place).

## Existing Tests Covering This Area (named; gate family)

All AUTO-glob into **`feature-host-all`** (`run_host_test_gates.sh:167` = `rg --files test/features`).
**Neither is in `ONE_TO_ONE_TESTS`** (`run_test_gates.sh:17-72`) — confirmed by grep this session; so
no edit to `run_test_gates.sh` is required for these two files.

- `test/features/p2p/domain/models/node_state_test.dart` — fromJson/toJson round-trip, copyWith,
  toString, `NodeState.stopped`. (Does NOT currently test `badgeReadinessState` — that coverage lives
  in the indicator test's helpers.)
- `test/features/p2p/presentation/widgets/connection_status_indicator_test.dart` — "renders the exact
  visible text for all four badge states" (:205), "Online and Online. expose distinct semantics labels"
  (:237), "Online and Online. keep the same green text styling" (:266), the §24
  `TIME_TO_ONLINE_BADGE_WIDGET` group (:288-385) incl. "applies ready-state downgrades immediately"
  (:365), and the legacy `healthFromState` group (:104-202).
- `test/core/services/p2p_service_impl_test.dart` references `BadgeReadinessState` (grep hit) — it is in
  `ONE_TO_ONE_TESTS` (`run_test_gates.sh:48`). **Read it before landing** to confirm it does not switch
  exhaustively over the enum (an exhaustive `switch` there would also need the new arm). If it does, the
  new arm is a one-line addition; if not, no change. (Listed as a Step-0 read.)

## RED Test Catalog (BEFORE prod code)

Each test is written and RED **before** the corresponding production edit.

**T1 — unit: directReady promotes the tier to onlineDirect**
- file::name: `node_state_test.dart::badgeReadinessState is onlineDirect when usabilityReady and directReady`
- Tier: unit (lowest that fails for the real reason — pure computation).
- Shape/setup: `NodeState(isStarted: true, sendCapabilityReady: true, inboxCapabilityReady: true, relayState: 'online', directReady: true)`.
- RED-on-HEAD-because: `directReady` is not a constructor param (compile error) AND `BadgeReadinessState.onlineDirect` does not exist (compile error). After the enum+field exist but before the computation branch, it returns `onlineDotted` (assertion fail).
- GREEN-asserts: `state.badgeReadinessState == BadgeReadinessState.onlineDirect`.
- Mutation-that-re-reds: in `badgeReadinessState`, drop the `directReady` branch (revert to `relayReady ? onlineDotted : online`) → T1 RED again.
- Distinct-event discriminator: paired with T2 to prove ranking (onlineDirect ABOVE onlineDotted), not a relabel.

**T2 — unit: onlineDirect outranks onlineDotted AND does not require relayReady**
- file::name: `node_state_test.dart::onlineDirect ranks above onlineDotted and holds without relay reservation`
- Tier: unit.
- Shape/setup: two states — (a) `directReady:true, relayState:'online'` (both true) → expect `onlineDirect`; (b) `directReady:true, relayState:'degraded', circuitAddresses:[]` (relay NOT ready) → expect `onlineDirect` (direct path is enough). Both `usabilityReady:true`.
- RED-on-HEAD-because: enum/field absent (compile) then returns `onlineDotted`/`online`.
- GREEN-asserts: both → `onlineDirect`.
- Mutation: gate the branch behind `relayReady && directReady` instead of just `directReady` → case (b) RED.
- Discriminator: case (b) is the one that distinguishes "direct outranks/decouples from relay" from "direct is just a stricter relay".

**T3 — unit: directReady defaults false and does not promote (preserved sentinel PS-3/PS-6)**
- file::name: `node_state_test.dart::directReady defaults false so existing states keep their badge`
- Tier: unit.
- Shape/setup: `NodeState(isStarted:true, sendCapabilityReady:true, inboxCapabilityReady:true, relayState:'online')` (no `directReady`) → expect `onlineDotted`; same with `relayState:'degraded'` → expect `online`; `fromJson` of a JSON map WITHOUT `directReady` key → `directReady` is false.
- RED-on-HEAD-because: compile (field referenced in fromJson assert) — and guards against an over-eager default.
- GREEN-asserts: badge unchanged; `NodeState.fromJson({...}).directReady == false`.
- Mutation: change the field default to `true` → T3 RED (and many existing tests flip).
- Discriminator: locks "no silent promotion of the live bridge".

**T4 — unit: directReady round-trips through json/copyWith/toString**
- file::name: `node_state_test.dart::directReady survives fromJson/toJson and copyWith`
- Tier: unit.
- Shape/setup: build with `directReady:true`, `toJson()`→`fromJson()` round-trip; `copyWith(directReady:false)`; `copyWith()` preserves it; `toString()` includes a `directReady` marker only when true (mirror the `relayState` conditional at `node_state.dart:160`).
- RED-on-HEAD-because: field absent (compile).
- GREEN-asserts: round-trip preserves `directReady`; copyWith overrides/preserves; toString contains `directReady: true`.
- Mutation: omit `directReady` from `toJson` (or from `copyWith`) → round-trip/preserve assertion RED.

**T5 — unit (ANTI-FLAP): a ready sequence never dips to connecting unless capability is truly lost**
- file::name: `node_state_test.dart::ready badge does not flap to connecting across a resume-style sequence`
- Tier: unit (computation over a list of states — the producer contract FDC-05/06/07 must honour).
  **Framing: this is a computation-threshold *preservation* lock (the `badgeReadinessState` threshold
  never yields `connecting` while capability holds), NOT the binding anti-flap guard. The real flap
  origin is producer *re-timing* — asserted producer-side in FDC-05/06/07, which already carry the
  matching preservation rows (see §Open Issues).**
- Shape/setup: a list modelling a resume/cold-start emission order, e.g.
  `[onlineDotted, online(relayState:'degraded', directReady:false), onlineDirect(directReady:true), onlineDotted, onlineDirect]`
  — i.e. relay/direct inputs wobble **including a plain-`online` beat where BOTH relay and direct are
  absent** while `sendCapabilityReady && inboxCapabilityReady` stay TRUE throughout. **That plain-`online`
  beat is load-bearing**: without it, the named mutation (`!relayReady && !directReady → connecting`) has
  no element to flip and T5 cannot re-red (it would pass trivially). Map each to `badgeReadinessState`.
  Assert NONE equals `BadgeReadinessState.connecting`. A SECOND list where one state genuinely has
  `sendCapabilityReady:false` **AND `directReady:true`** asserts that one (and only that one) IS
  `connecting` — proving both that the test discriminates real loss from cosmetic wobble (not a
  tautology) **and** that `directReady` never bypasses the `usabilityReady` gate (closes the INV-1
  isolation gap).
- RED-on-HEAD-because: `onlineDirect`/`directReady` absent (compile). Conceptually also guards the
  computation: if the new branch mistakenly required `relayReady`, an `onlineDirect`-input state with
  relay degraded would fall to `online` (still not connecting — so this test is robust) — the real flap
  protection is "capability-true never yields connecting", which holds by `:148-149`.
- GREEN-asserts: no `connecting` in the capability-stable sequence; exactly one `connecting` in the
  capability-lost sequence.
- Mutation: change `badgeReadinessState` so that `!relayReady && !directReady` (but usabilityReady)
  returns `connecting` instead of `online` → the first sequence gets a spurious `connecting` → RED.
- Discriminator: the two-list shape is the distinct-event guard (cosmetic wobble vs real capability loss
  return the *same enum family* only if buggy).

**T6 — widget: indicator renders onlineDirect with a DISTINCT visible label**
- file::name: `connection_status_indicator_test.dart::renders the onlineDirect tier with a distinct visible label`
- Tier: widget (icon/label render — per the rule "widget tier for label render + a11y").
- Shape/setup: pump indicator with an injected `onlineDirect` state (extend the helper
  `_stateForBadgeState` with the `onlineDirect` case: `isStarted:true, send+inbox ready, directReady:true`).
  Assert the visible label is the new string AND `find.text('Online.')` (the onlineDotted label)
  findsNothing while onlineDirect is shown.
- RED-on-HEAD-because: `_stateForBadgeState` switch is exhaustive (compile error adding the case) and
  `_labelForBadgeState` lacks the arm (compile error) — once added wrong (reusing 'Online.') the
  `findsNothing` discriminator fails.
- GREEN-asserts: `find.text('<onlineDirect visible label>')` findsOneWidget; `find.text('Online.')` findsNothing.
- Mutation: make `_labelForBadgeState(onlineDirect)` return `'Online.'` → discriminator RED.
- **Distinct-event discriminator (REQUIRED): assert onlineDirect renders a label NOT equal to onlineDotted's `'Online.'`** — this is the headline acceptance.

**T7 — widget: onlineDirect exposes a DISTINCT semantics label ("directly reachable")**
- file::name: `connection_status_indicator_test.dart::onlineDirect exposes a distinct directly-reachable semantics label`
- Tier: widget (a11y).
- Shape/setup: pump `onlineDotted`, read `getSemantics(...).label`; push `onlineDirect`, pump×2, read
  again. Assert the two labels differ AND the onlineDirect label contains `'directly reachable'` (or the
  chosen phrasing) and does NOT contain `'relay reservation'`.
- RED-on-HEAD-because: `_semanticsLabelForBadgeState` switch lacks the arm (compile); wrong arm fails
  the contains/!= asserts.
- GREEN-asserts: `directLabel != dottedLabel`; `directLabel.contains('directly reachable')`;
  `!directLabel.contains('relay reservation')`.
- Mutation: make the onlineDirect semantics arm reuse the onlineDotted string → `!=` assert RED.
- Discriminator: the `!=` against the onlineDotted semantics is the screen-reader-level distinctness lock.

**T8 — widget: onlineDirect is a ready state → no TIME_TO_ONLINE_BADGE re-emit on dotted→direct (PS-4)**
- file::name: `connection_status_indicator_test.dart::no badge timing re-emit moving between Online. and onlineDirect`
- Tier: widget.
- Shape/setup: start `onlineDotted`, capture flow events while pushing `onlineDirect` (pump×2). Assert
  zero `TIME_TO_ONLINE_BADGE_WIDGET` events (generalizes the §24 "does not emit between Online and
  Online." test). Then a second case: start `connecting`, push `onlineDirect`, assert exactly ONE emit
  (first-ready transition still counts).
- RED-on-HEAD-because: enum/helper absent (compile); `_isReadyBadgeState` not extended ⇒ onlineDirect
  treated as not-ready ⇒ dotted→direct would (wrongly) be a ready→not-ready→... mismatch and the
  connecting→direct case would NOT emit.
- GREEN-asserts: 0 emits for dotted→direct; 1 emit for connecting→direct.
- Mutation: omit `onlineDirect` from `_isReadyBadgeState` (`:34-37`) → **connecting→direct emits 0 instead
  of 1 → RED**. (Under the mutation, dotted→direct still emits 0 — `wasReady=true, isReady=false` makes
  `isReady && !wasReady` false either way — so the dotted→direct sub-case does NOT discriminate; the
  load-bearing assertion is the connecting→direct count. Make the connecting→direct sub-case **mandatory**,
  not optional.)
- Discriminator: separates "ready-tier reshuffle" (no emit) from "first reach ready" (one emit).
- **As-built harness note (REQUIRED — added post-impl):** the two sub-cases must run on a **fresh widget
  State**. The indicator is pumped with **no `Key`**, so a second `pumpWidget` reuses the same
  `Element`/`State` and `initState` does not re-run (stale subscription to the disposed `StreamController`).
  **Unmount between sub-cases** with `await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink())); await tester.pump();`
  (landed at `connection_status_indicator_test.dart:519-520`); otherwise the `connecting→direct` emit
  fires against stale state and the count is wrong.

**T9 — widget: onlineDirect keeps green styling + colour (PS-1 family, belt)**
- file::name: `connection_status_indicator_test.dart::onlineDirect keeps the green ready styling`
- Tier: widget.
- Shape/setup: pump `online`, read the text colour; push `onlineDirect`, assert the `Text` colour equals
  the online/dotted green (mirrors :266 "keep the same green text styling"); assert the colour switch arm
  (`:147-150`) treats onlineDirect as green (no compile gap).
- RED-on-HEAD-because: colour switch (`:147-164`) is exhaustive ⇒ missing arm = compile error.
- GREEN-asserts: onlineDirect text colour == online text colour.
- Mutation: give onlineDirect a non-green `baseColor` → colour-equality RED.

**T10 — unit (SCOPE GUARD): peer-presence-style inputs do NOT promote the self-dot**
- file::name: `node_state_test.dart::peer connections and presence do not set onlineDirect`
- Tier: unit.
- Shape/setup: `NodeState(isStarted:true, send+inbox ready, relayState:'online', connections:[<a connected peer>], directReady:false)` → expect `onlineDotted`, NOT `onlineDirect`. (Having peer connections / a relay socket must not imply direct-self-reachability.)
- RED-on-HEAD-because: compile (enum). Conceptually locks FDC-00 self-online-dot gap ("peer-presence is a different axis").
- GREEN-asserts: badge is `onlineDotted`.
- Mutation: make `badgeReadinessState` treat `connections.isNotEmpty` as `directReady` → T10 RED.
- Discriminator: proves onlineDirect is gated ONLY by the `directReady` input, never by peer/connection state.

## Test Coverage Matrix (zero empty cells)

| Spec case | Behavior props | Tier | Test file::name | RED reason | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| New tier from directReady | onlineDirect computed | unit | node_state_test::badgeReadinessState is onlineDirect... | enum+field absent (compile) | drop directReady branch | `flutter test test/features/p2p/domain/models/node_state_test.dart` | AUTO-glob feature-host-all |
| Ranking + relay-decouple | onlineDirect > onlineDotted; holds w/o relay | unit | node_state_test::onlineDirect ranks above onlineDotted... | enum/field absent | gate behind `relayReady && directReady` | same | AUTO-glob feature-host-all |
| Default safe | directReady=false ⇒ unchanged badge | unit | node_state_test::directReady defaults false... | compile / over-eager default | default→true | same | AUTO-glob feature-host-all |
| Serialization | json/copyWith/toString | unit | node_state_test::directReady survives fromJson/toJson and copyWith | field absent | omit from toJson/copyWith | same | AUTO-glob feature-host-all |
| ANTI-FLAP | no connecting dip on stable-capability seq | unit | node_state_test::ready badge does not flap to connecting... | enum absent / computation | usabilityReady&&!relay&&!direct→connecting | same | AUTO-glob feature-host-all |
| Distinct visible label | label != 'Online.' | widget | indicator_test::renders the onlineDirect tier with a distinct visible label | switch exhaustive (compile) | label→'Online.' | `flutter test test/features/p2p/presentation/widgets/connection_status_indicator_test.dart` | AUTO-glob feature-host-all |
| Distinct a11y label | "directly reachable", not "relay reservation" | widget | indicator_test::onlineDirect exposes a distinct directly-reachable semantics label | switch exhaustive | semantics arm reuse dotted | same | AUTO-glob feature-host-all |
| Timing emit contract | 0 re-emit dotted→direct; 1 connecting→direct | widget | indicator_test::no badge timing re-emit moving between Online. and onlineDirect | enum/helper absent | drop onlineDirect from _isReadyBadgeState | same | AUTO-glob feature-host-all |
| Ready styling | green colour preserved | widget | indicator_test::onlineDirect keeps the green ready styling | colour switch exhaustive | non-green baseColor | same | AUTO-glob feature-host-all |
| SCOPE GUARD (peer axis) | peer connections ≠ onlineDirect | unit | node_state_test::peer connections and presence do not set onlineDirect | enum absent | connections.isNotEmpty⇒directReady | same | AUTO-glob feature-host-all |

## Blind-Spot Sweep

- **Lifecycle/derived-state durability**: T5 anti-flap locks the badge across resume/pause/cold-start
  emission ordering at the producer-contract tier (the tier FDC-05/06/07 must honour). The widget itself
  applies downgrades immediately by design (indicator_test:365), so durability is enforced on the
  NodeState sequence, not the widget — correct seam.
- **Sibling-surface consistency**: both mount sites (feed_header.dart:48, FTE:146) construct the SAME
  `ConnectionStatusIndicator` and branch on nothing — one render path, so no per-surface divergence.
  Belt: no new test needed (justified — identical widget, identical input contract).
- **Destructive side-effects**: none — additive enum value + nullable-defaulted field; PS-6 guards no
  silent promotion of existing states/bridge output.
- **Invariant re-verification**: PS-4 (timing emit) re-verified by T8. **PS-5 (`ConnectionHealth`
  legacy mapping) caveat — DO NOT author an onlineDirect legacy-health assertion, it cannot be exercised:**
  `_legacyHealthForBadgeState` is a switch expression, so the compiler *forces* an `onlineDirect` arm to
  **exist**, but its **value is unobservable by test** — the function is library-private (a unit test in a
  separate library cannot call it) and it is only ever invoked on the *previous* state inside the
  `if (isReady && !wasReady)` emit gate (`:113-124`), i.e. always on a **not-ready** state, so the
  `onlineDirect` arm is a dead path. `healthFromState` (`:26-32`) does not read the badge enum at all. ⇒
  PS-5 for `onlineDirect` is locked by **compiler (arm must exist) + convention (map it alongside
  `online`/`onlineDotted` → `ConnectionHealth.online`)**, NOT by a runtime assert.
- **Exhaustiveness compile-guard**: in `lib/`, **FOUR** sites become compile errors on the new enum value —
  the three switch *expressions* (`_labelForBadgeState`, `_semanticsLabelForBadgeState`, `_legacyHealthForBadgeState`)
  and the colour switch *statement* (its `final baseColor`/`textColor` go unassigned → a definite-assignment
  compile error, not a non-exhaustive-statement warning). **`_isReadyBadgeState` (`:34-37`) is NOT
  compiler-guarded** — it is a boolean `==` expression (`state == online || state == onlineDotted`), so
  adding `onlineDirect` **silently compiles** and treats it as **not-ready** (the exact bug T8 catches).
  That one helper is the lone *silent* gap in `lib/p2p`: the implementer must extend it by hand (Step 5)
  and only T8 proves it was done.
- **POST-IMPL CORRECTION (verified 2026-06-27) — this sweep UNDERCOUNTED by 9 sites; it scoped only
  `lib/`/`lib/p2p`.** The true badge-enum surface is:
  1. **A 5th exhaustive `switch` lives OUTSIDE `lib/`** — `integration_test/background_reconnect_test.dart:48-56`
     (`_badgeLabel`). Adding `onlineDirect` made it `non_exhaustive_switch_expression` — a **compile error**
     that broke the full-project `flutter analyze` (it fires regardless of the out-of-scope producer). The
     fix was a one-line arm `onlineDirect => 'Online ✦'` (now present at `:55`). **Lesson: when adding an
     enum value, grep the WHOLE repo incl. `integration_test/` and run a FULL `flutter analyze`, not a
     changed-files-only analyze** — Step 8's "anywhere in lib/" catch-all was too narrow.
  2. **A class of bare `==` comparisons silently compiles** (they do NOT break compile, so no guard catches
     them): **2 in `lib/`** (`p2p_service_impl.dart:3185`, `:3219`) **+ 6 in `integration_test/`**
     (`_support/node_readiness.dart:51-52,:56,:60`; `background_reconnect_test.dart:35-36,:40,:44`). The
     undercount itself is real (the sweep scoped only `lib/`). **But re-grounding (2026-06-27) refuted the
     "all 8 are hazards to fix" reading:** only the `isSendable*` predicate (×2) is a genuine fix; the
     relay-ready / plain-online predicates and the `p2p_service_impl` `TIME_TO_RELAY_READY_BADGE` gate are
     **correct as-is** (onlineDirect ≠ relay-ready). See the corrected breakdown in **§Open Issues → FDC-14b
     PRE-WORK** and the dedicated `FDC-14b-directready-producer-tdd-plan.md`.
  So the real tally: **5 compiler-caught switches (4 in `lib/` + 1 in `integration_test/`) + 1 test-caught
  `lib/` `==` helper (`_isReadyBadgeState`, T8) + 8 silent `==` hazards (2 `lib/`, 6 `integration_test/`)
  deferred to FDC-14b.**
- **p2p_service_impl_test exhaustive-switch risk**: Step-0 read confirms whether that ONE_TO_ONE test
  switches over `BadgeReadinessState`; if so add the arm (one line). Row justified by Step 0.

## Invariants (locked by tests)

- INV-1 `onlineDirect` is computed iff `usabilityReady && directReady`, ranked **above** `onlineDotted`,
  and does **not** require `relayReady` (T1, T2). `directReady` never bypasses the `usabilityReady` gate:
  `sendCapabilityReady:false` + `directReady:true` ⇒ `connecting`, not `onlineDirect` (T5 list-2).
- INV-2 `directReady` defaults false; absent-in-json ⇒ false; no existing state/badge changes (T3, T4, PS-6).
- INV-3 A capability-stable resume/pause/cold-start sequence never yields `connecting`; real capability
  loss still does (T5).
- INV-4 `onlineDirect` visible label ≠ `'Online.'` and semantics ≠ the onlineDotted phrasing; says
  "directly reachable", not "relay reservation" (T6, T7) — **the distinct discriminator**.
- INV-5 `onlineDirect` is a ready state for timing + colour + legacy-health purposes (T8, T9, PS-4, PS-5).
- INV-6 Peer-presence / peer-connection inputs never set `onlineDirect` (T10; FDC-00 self-online-dot gap).

## Step-By-Step Implementation Plan (RED first; name the seam)

0. **Read** `test/core/services/p2p_service_impl_test.dart` for an exhaustive `switch` over
   `BadgeReadinessState`; note if a one-line arm is needed (it is in ONE_TO_ONE_TESTS).
1. **RED** — write T1–T5, T10 in `node_state_test.dart` and T6–T9 in `connection_status_indicator_test.dart`
   (extend `_stateForBadgeState` with the `onlineDirect` case). Confirm they fail to COMPILE (enum/field
   absent) — the RED checkpoint.
2. **Seam: enum** — add `onlineDirect` to `BadgeReadinessState` (`node_state.dart:3`), placed LAST
   (ranked highest).
3. **Seam: model input** — add `final bool directReady;` (default `false`) to `NodeState`
   (`:20-21` neighbourhood), plumb through the constructor (`:23-37`), `fromJson` (`:42-77`,
   `json['directReady'] == true`), `toJson` (**always emit — Pattern B**, like the unconditional
   `sendCapabilityReady`/`inboxCapabilityReady` at `:98-99`; NOT the nullable omit-when-null Pattern A used
   by `relayState` et al.), `copyWith` (`:104-134`), and `toString` (`:155-161`, conditional
   marker like `relayState`). → GREEN T3, T4.
4. **Seam: computation** — in `badgeReadinessState` (`:147-153`), insert the top branch:
   `if (usabilityReady && directReady) return BadgeReadinessState.onlineDirect;` ABOVE the
   `relayReady ? onlineDotted : online` return. → GREEN T1, T2, T5, T10.
5. **Seam: indicator readiness helpers** — extend `_isReadyBadgeState` (`:34-37`) and
   `_legacyHealthForBadgeState` (`:39-46`) to include `onlineDirect` (ready / →`ConnectionHealth.online`).
   → unblocks T8, PS-5.
6. **Seam: indicator labels** — add the `onlineDirect` arm to `_labelForBadgeState` (`:48-55`, a NEW
   distinct visible string, e.g. `'Online··'` — NOT `'Online.'`) and `_semanticsLabelForBadgeState`
   (`:57-66`, e.g. `'online, send and inbox ready, directly reachable'`). → GREEN T6, T7.
7. **Seam: indicator colour** — add the `onlineDirect` case alongside `online`/`onlineDotted` in the
   build colour switch (`:147-150`) → green. → GREEN T9.
8. **Run** the two files + `flutter analyze`; if Step-0 found an exhaustive switch in p2p_service_impl_test
   (or anywhere in lib/), add the one-line arm. Re-run gates.
9. **STOP-IF (producer wiring is OUT of scope)** — do NOT edit `p2p_service_impl.dart` / the bridge to
   set `directReady=true`. The producer is an **unowned follow-on (FDC-14b)**, gated on (not owned by)
   FDC-02/FDC-11. Leave a one-line code comment at the `directReady` field: `// directReady producer = FDC-14b follow-on (derives from FDC-02 ranked-race live LAN/direct + FDC-11 libp2p LAN-direct dial); default false until then.`
10. **Mutation pass** — apply each row's mutation, confirm the named test re-reds, revert.

## Risks And Edge Cases (each pinned by a test)

- **Silent promotion of the live bridge** (bridge emits no `directReady`) → would flip every node to
  onlineDirect. Pinned: T3 (default false) + PS-6.
- **onlineDirect collapsing into onlineDotted's label** (a relabel, not a new tier) → pinned by the
  T6/T7 `!=` discriminators (INV-4).
- **Treating onlineDirect as not-ready** → breaks the timing emit + colour. Pinned T8, T9.
- **Anti-flap false-positive** (a test that passes trivially because nothing ever returns connecting) →
  defused by T5's second, capability-lost list asserting connecting DOES appear.
- **Peer-presence leakage** into the self-dot → pinned T10 (INV-6).
- **Exhaustive-switch compile breakage elsewhere** → Step 0 + analyze in Step 8.

## Device/Relay Proof Profile

- Host-only for what this plan ships (enum + computation + render + anti-flap) — fully injected-state
  testable; **no device proof required for FDC-14 itself**.
- The `directReady` PRODUCER (FDC-02/FDC-11) is where device-proof lands: those plans must show a real
  LAN/direct path producing `directReady=true` on a real two-device pair (FDC-11 is device-only — iOS
  sim shares the host mDNS stack → `DISABLE_LOCAL_DISCOVERY`, proposal §6.5). When that wiring lands,
  a sims/device smoke should observe the badge actually reaching `onlineDirect` (not just delivery) —
  the host-fake false-positive caveat (FDC-00 Closure) applies to the producer, not to this render plan.

## Acceptance Gates (LITERAL cmds + expected counts as TODO)

> **As-built results (2026-06-27, committed `5f21d790`)** annotated inline below.
- [x] `flutter test test/features/p2p/domain/models/node_state_test.dart` — **GREEN**, +T1–T5,T10 (20 tests in this file).
- [x] `flutter test test/features/p2p/presentation/widgets/connection_status_indicator_test.dart` — **GREEN**, +T6–T9 (19 tests). Combined FDC-14 = **39/39**.
- [x] `flutter analyze` — **0-new** (after the `integration_test/background_reconnect_test.dart` 5th-switch arm; a changed-files-only analyze MISSED it — see §Blind-Spot Sweep POST-IMPL CORRECTION).
- [x] `./scripts/run_test_gates.sh 1to1` — `p2p_service_impl_test.dart` **GREEN (84)**; no exhaustive `switch` there ⇒ the Step-0 arm was not needed.
- [~] `./scripts/run_host_test_gates.sh core-host-all` — **120 PASS / 1 FAIL**, where the 1 FAIL is the **KNOWN pre-existing `transport_metrics_privacy_test` (FDC-S0 `sinceProcessStartMs` allowlist), NOT FDC-14**. ⚠ Run host gates ONE AT A TIME — concurrent `core-host-all` + `feature-host-all` race on `build/native_assets/macos/objective_c.dylib` (spurious `install_name_tool` FAIL).
- [x] `git diff --check` — clean.

## Known-Failure Interpretation

- A compile error in `connection_status_indicator.dart` switches right after adding the enum value is
  EXPECTED at the RED checkpoint (Step 1) — it is the render-completeness signal, resolved by Steps 5–7.
- If `p2p_service_impl_test` (1to1 gate) goes RED on an unhandled enum case, that is the Step-0 arm — a
  one-line addition, not a regression.
- onlineDirect never appearing in a live-app smoke is EXPECTED until FDC-02/FDC-11 wire the producer
  (Step 9 stop-if) — not a failure of this plan.

## Done Criteria (checkbox)

> **✅ All criteria met as-built and committed in `5f21d790` (2026-06-27)** — except the Step-9 producer
> stop-if, which remains correctly UNMET by design (producer = FDC-14b, unwired). The boxes below stay
> unchecked as the original design record; treat this banner as the verdict.

- [ ] `BadgeReadinessState.onlineDirect` exists, ranked above `onlineDotted`.
- [ ] `NodeState.directReady` (default false) plumbed through ctor/json/copyWith/toString.
- [ ] `badgeReadinessState` returns `onlineDirect` iff `usabilityReady && directReady`.
- [ ] Indicator renders onlineDirect with a DISTINCT visible label (≠ `'Online.'`) and DISTINCT
      "directly reachable" semantics label; green styling preserved; timing/legacy-health treat it ready.
- [ ] T5 anti-flap green (no connecting dip on capability-stable sequence; connecting on real loss).
- [ ] T10 scope-guard green (peer inputs do not promote).
- [ ] All RED tests mutation-verified; PS-1..PS-6 preserved; analyze 0-new; gates green.
- [ ] Step-9 producer stop-if respected (no `p2p_service_impl.dart` producer edit).

## Scope Guard (hard Do-not)

- Do NOT wire a `directReady` producer (no `p2p_service_impl.dart` / bridge edit) — owned by FDC-02/FDC-11.
- Do NOT feed peer-presence (FDC-08/09) into this dot.
- Do NOT touch the per-message transport badge (`letter_card.dart` — FDC-13).
- Do NOT change PS-1 visible texts or PS-2 semantics of the existing 4 tiers.
- Do NOT add a new `ConnectionHealth` legacy enum value (keep ready→online mapping).
- Do NOT debounce downgrades in the widget (anti-flap lives in the producer/NodeState sequence).

## Accepted Differences

- onlineDirect is **unreachable in production** until FDC-02/FDC-11 land the producer — intentional; the
  contract + render + anti-flap are locked now, the signal is wired later (DRAFT).
- Visible label choice (`'Online··'` vs another distinct string) is the implementer's pick provided it
  is **not equal** to `'Online.'`; the test asserts inequality, not a literal, to avoid bikeshedding the
  glyph while still locking distinctness. **As-built (2026-06-27): resolved to `'Online ✦'` (U+2726 BLACK
  FOUR POINTED STAR)** — a non-linear star cue rather than a third stacked punctuation dot (per the Axis
  note above), distinct from BOTH `'Online.'` and plain `'Online'` (T6 locks both).
- **Axis note (design):** "directly reachable" is a *partially-orthogonal* axis, NOT a strict rank above
  relay-reservation — per **T2 case (b)**, `onlineDirect` can hold with the **relay NOT ready**. So a
  sighted-user encoding that implies a linear "more dots = more connected" ladder (`'Online'` → `'Online.'`
  → `'Online··'`) is misleading: an `onlineDirect` node may have *no* relay reservation. The **binding**
  distinctness is therefore the a11y semantics ("directly reachable", locked by T7); the visible glyph is a
  secondary, non-load-bearing cue. Prefer a clearer non-linear cue over stacking a third punctuation-only
  variant on the same green if one is cheap.

## Open Issues

- **Producer-side anti-flap assertion (feeds FDC-05/06/07).** Paste-ready acceptance note for the three
  re-timing plans: *"A resume / graceful-pause / cold-start emission sequence must NEVER emit an
  intermediate `NodeState` whose `badgeReadinessState == BadgeReadinessState.connecting` (or `offline`)
  while send-AND-inbox capability is genuinely retained throughout the transition."* **Status: already
  landed** as preservation rows in FDC-05 (`:264-268`), FDC-06 (`:287-290`), FDC-07 (`:238-241`), each of
  which also explicitly cedes the new `onlineDirect` tier to this plan. T5 here is the *computation-tier*
  half of the same invariant; FDC-05/06/07 own the *emission-order* half.
- **`directReady` producer (FDC-14b).** Unowned follow-on (see DRAFT caveat + §Dependency Impact): wire a
  `NodeState.directReady` producer that derives the field from FDC-02's ranked-race live-LAN/direct
  outcome and/or FDC-11's bonsoir-fed libp2p LAN address. Until it lands, `onlineDirect` is renderable
  from injected state but unreachable in production. Track FDC-14b in `FDC-00-roadmap.md`.
- **FDC-14b PRE-WORK — the real picture (re-grounded 2026-06-27 via verify→refute; CORRECTS an earlier
  overstatement that called all 8 `==` sites "hazards to fix").** Of the badge-enum `==` sites, only **ONE
  predicate (×2 surfaces) genuinely needs changing**; the rest are **correct as-is**. Full plan:
  `FDC-14b-directready-producer-tdd-plan.md`.
  - **FIX (load-bearing): `isSendableBadgeState` (`integration_test/_support/node_readiness.dart:51-52`) +
    its private twin `_isSendable` (`integration_test/background_reconnect_test.dart:35-36`)** — `onlineDirect`
    IS sendable, so these must add `|| == onlineDirect`, else `waitForSendableBadge()` hangs once a producer
    flips `directReady` (FDC-14b F-1).
  - **CORRECT AS-IS — do NOT add onlineDirect:** the relay-ready (`isRelayReadyBadgeState` `:60` /
    `_isRelayReady` `:44`, `== onlineDotted`) and plain-online (`isPlainOnlineBadgeState` `:56` /
    `_isPlainOnline` `:40`, `== online`) predicates SHOULD exclude `onlineDirect` — it is direct-ready, not
    relay-ready or plain. Adding it would be a bug (FDC-14b F-2 guards this).
  - **CORRECT AS-IS (prod): `p2p_service_impl.dart:3185/:3219`** gating `TIME_TO_RELAY_READY_BADGE`
    (`:3248-3252`). `onlineDirect` correctly does NOT fire the relay-ready telemetry (FDC-14b P-6 locks this).
    The earlier "the telemetry never fires (bug)" framing was an **overstatement**. The one genuine subtlety
    is *both-ready lossiness*: when relay AND direct are both ready the badge collapses to `onlineDirect`, so a
    badge-based relay-ready read is lossy — an **Accepted Difference** in FDC-14b, not a required fix.
  - **Blind-spot value retained:** the original point — that these sites exist and the FDC-14 sweep's "all in
    `lib/`" was too narrow — stands; only the *fix-everything* prescription was wrong.

## Dependency Impact

- **gatedBy**: FDC-02 / FDC-11 for the `directReady` *upstream signal* — but the producer that derives
  `NodeState.directReady` from it is an **unowned follow-on (FDC-14b)**, scheduled by neither sibling
  (verified). Render + anti-flap are ungated and host-testable now.
- **Sequenced after**: FDC-02 (ranked race) and FDC-11 (libp2p LAN-direct dial, bonsoir-fed) — the two `directReady` signal sources (matches **gatedBy** above + the roadmap's `FDC-14←FDC-02/11` spike-gate line); can be
  AUTHORED/landed (render-only) before them, with the **FDC-14b** producer connected when they ship.
- **Collision**: none with the Phase-0 send-path collision file (`send_chat_message_use_case.dart`).
  Touches only `node_state.dart` + `connection_status_indicator.dart` + their two tests — no overlap
  with FDC-01..04. **Verified vs the closest-coupled siblings FDC-05/06/07:** they do NOT edit
  `node_state.dart` — they only *assert* preservation against `badgeReadinessState` (FDC-05:264-268,
  FDC-06:287-290, FDC-07:238-241) and each explicitly cedes the `onlineDirect` tier to this plan. So no
  model collision; if landed concurrently, FDC-14's enum/field should land **first** so those preservation
  rows compile against the new tier. Safe to land independently.
- **Feeds**: the anti-flap acceptance one-liner (§Open Issues) into FDC-05/FDC-06/FDC-07 — **already
  landed** there as preservation rows (FDC-05:264-268, FDC-06:287-290, FDC-07:238-241).
</content>
</invoke>
