# Mknoon Visual Direction — Critical Review and Candidate Final

Date: 2026-08-26  
Status: Visual validation only. No production Flutter UI was changed.  
Verdict: **READY FOR SMALL PROTOTYPE** — the corrected direction is strong enough for one isolated Orbit experiment, but not yet for design-system-wide implementation.

This document supersedes the first V2 proposal where the two disagree. The first proposal was cleaner than the current app, but it over-corrected: it removed too much of Mknoon’s celestial atmosphere and replaced it with a polished but generic graphite/violet social-app language.

> **Scope correction:** An earlier revision incorrectly labelled a conventional conversation-list proposal as “Orbit.” That conflated two existing Mknoon modes and would have replaced the product’s defining spatial relationship canvas. Those files are now explicitly labelled **Chat List only**. The corrected Orbit evidence preserves the central self node, concentric relationship rings, orbital nodes, mode switch, online/create controls, floating search, and interaction model. Only visual treatment changes.

## Evidence index

| ID | Label | Evidence |
|---|---|---|
| E01 | CURRENT APP | [Live Orbit landing, Pixel 6](CURRENT-APP-orbit-live.png) |
| E02 | CURRENT APP | [Live Orbit / Chat List, Pixel 6](CURRENT-APP-orbit-chat-list-live.png) |
| E03 | CURRENT APP | [Live Intros](CURRENT-APP-orbit-intros-live.png), [Archived](CURRENT-APP-orbit-archived-live.png), [search active](CURRENT-APP-orbit-search-live.png) |
| E04 | CURRENT APP | [Live direct conversation with voice message, keyboard hidden](CURRENT-APP-conversation-voice-keyboard-hidden.png) |
| E05 | CURRENT APP | [Live direct conversation, keyboard visible](CURRENT-APP-live-start.png) |
| E06 | CURRENT APP | [Earlier light conversation](../signal-theme-ui-audit-2026-07-09/08-signal-conversation.png), [earlier light list](../signal-theme-ui-audit-2026-07-09/05-signal-all-chats.png) |
| E07 | PROPOSED MOCKUP | [Orbit alternatives A/B/C](ALTERNATIVES-ABC-orbit.png) |
| E08 | PROPOSED MOCKUP | [Conversation alternatives A/B/C](ALTERNATIVES-ABC-conversation.png) |
| E09 | PROPOSED MOCKUP | [Candidate Orbit dark](PROPOSED-MOCKUP-final-orbit-dark.png), [light](PROPOSED-MOCKUP-final-orbit-light.png) |
| E10 | PROPOSED MOCKUP | [Candidate Conversation dark](PROPOSED-MOCKUP-final-conversation-dark.png), [light](PROPOSED-MOCKUP-final-conversation-light.png) |
| E11 | PROPOSED MOCKUP | [Composer five-state comparison](PROPOSED-MOCKUP-final-composer-states-dark.png), [light typing](PROPOSED-MOCKUP-final-composer-light.png) |
| E12 | PROPOSED MOCKUP | [42-message stress sample](VALIDATION-long-conversation-dark.png) |
| E13 | PROPOSED MOCKUP | [RTL, mixed-script, 100/130/160% validation](VALIDATION-real-content-rtl-scaling.png) |
| E14 | PROPOSED MOCKUP | Orbit comparisons: [current → corrected dark](COMPARISON-current-final-orbit-dark.png), [corrected dark ↔ light](COMPARISON-final-orbit-dark-light.png) |
| E15 | CHAT LIST ONLY | Earlier rectangular work, correctly relabelled: [dark](PROPOSED-MOCKUP-chat-list-dark.png), [light](PROPOSED-MOCKUP-chat-list-light.png), [A/B/C](ALTERNATIVES-ABC-chat-list.png), [dark/light](COMPARISON-chat-list-dark-light.png) |
| E16 | PROPOSED MOCKUP | Other dark/light comparisons: [Conversation](COMPARISON-final-conversation-dark-light.png), [Composer typing](COMPARISON-final-composer-dark-light.png) |

## 1. Visual Evidence Inventory

“Available” means a useful rendered image exists. It does not mean every interaction or accessibility condition has been runtime-tested.

| Screen / state | Current screenshot available? | Proposal available? | Missing evidence | Priority |
|---|---|---|---|---|
| Orbit landing / rings | Yes — E01 | Yes — E07/E09/E14; original spatial model preserved | Runtime motion and gesture transitions | Critical |
| Orbit unread relationship | Partial | Yes — E09, badge plus bright relationship arc | Runtime read transition and accessibility semantics | High |
| Orbit selected/focused node | Partial | Active arc represented — E07/E09 | Press, drag, focus, and open-conversation frames | High |
| Orbit many relationships | No dense current capture | Five-node visual stress sample — E07/E09 | Actual collision/zoom behavior at 10+ relationships | High |
| Orbit empty/new | Current sparse state only — E01 | No final empty state | Empty, first connection, and intro affordance | Medium |
| Orbit search active | Yes — E03 | Closed action preserved — E09 | Results/no-results/RTL keyboard without replacing canvas | High |
| Chat List normal | Yes — E02/E06 | Yes — E15; explicitly separate from Orbit | Runtime pressed/swipe state | High |
| Chat List unread | Partial; no strong live sample | Yes — E15/E13 | Current app with 3+ unread rows | High |
| Chat List long names | No | Yes — E15/E13 | Actual Flutter truncation/semantics | High |
| Chat List groups | Yes — E02 | Yes — E15/E13 | Muted/failed/leaving states | Medium |
| Chat List Intros | Yes, empty — E03/E06 | No final content mock | Intro row with long sender + unread | High |
| Chat List Archived | Yes, empty — E03/E06 | No final archived-row mock | Group plus restore action | Medium |
| Chat List 50 conversations | Yes — E06 | Represented — E15/E13 | Runtime scroll density | Medium |
| Direct normal text | Yes — E04/E06 | Yes — E10 | Incoming-heavy live chat | High |
| Direct long messages | No strong current sample | Yes — E12/E13 | Runtime wrapping/selection | High |
| Direct grouped messages | Yes — E04 | Yes — E10/E12 | Full corner matrix | High |
| Direct images | No useful current capture | Yes — E10 | Current image/caption/failure | High |
| Direct videos | No | No final playing-video mock | Active playback, keyboard closed | High |
| Direct voice messages | Yes — E04 | Yes — E10 | Playing/paused/2×/unavailable | High |
| Direct reactions | No useful current capture | Yes — E10 | Many/selected-own reactions | Medium |
| Direct replies | No | Composer reply only — E11 | Reply displayed in bubble | High |
| Direct failed message | No | No final mock | Retryable vs terminal | Critical |
| Direct sending state | No | No final mock | Upload/encryption/relay states | High |
| Direct unread divider | No | No final mock | Large text + RTL | High |
| Direct intro banner | Yes — E06 | Yes — E10 | Long translated copy | Medium |
| Direct very long conversation | Partial — E04 | Yes — E12 | Runtime 30–50 items | High |
| Direct empty/new | Yes — older capture | No candidate-final state | Light/dark parity | Medium |
| Group conversation, senders | No useful capture | Partial grammar only | Three senders + repeated runs | Critical |
| Group system messages | No | No | Join/leave/name/pin rows | Critical |
| Composer idle | Yes — E04 | Yes — E11 | Disabled/read-only | High |
| Composer typing | Keyboard yes, typed no — E05 | Yes — E11 | IME action/draft | High |
| Composer multiline | No | Represented — E11 | 4–8 lines at 130/160% | High |
| Composer reply | No | Yes — E11 | RTL/unavailable original | High |
| Composer edit | No | No | Cancel/save/failure | High |
| Composer image attachment | Sheet only | Yes — E11 | Current staged row | High |
| Composer multiple attachments | No | Yes — E11 | 5+ mixed files | High |
| Composer upload progress | No | No | Per-file/aggregate progress | Critical |
| Composer upload failed | No | No | Retry/delete without jump | Critical |
| Composer protected media | No useful current capture | Yes — E11 | Picker/failure explanation | Critical |
| Composer voice recording | No | Yes — E11 | Actual hold/slide frames | Critical |
| Composer voice review | No | No | Playback/discard/send | Critical |
| Composer keyboard hidden | Yes — E04 | Yes — E11 | Rotation/fold/safe area | Medium |
| Composer keyboard visible | Yes — E05 | Yes — E11 | iOS and RTL IME | High |
| Feed / Letters | Yes — captures 17/18 | No candidate-final proposal | Normal/focused/empty, light/dark | High |
| Posts | Yes — Posts contact sheet | No candidate-final proposal | Dark/light, long media | High |
| Settings | Yes — captures 01/03/26 | No candidate-final proposal | Large text/destructive | Medium |
| Contact Profile | Yes — capture 11 | No candidate-final proposal | Long/no-mutuals/blocked | Medium |
| QR Display | Yes — capture 19 | No candidate-final proposal | Light/dark brightness | Medium |
| QR Scanner | Yes — captures 20/21 | No candidate-final proposal | Denied/success | Medium |
| Sheets | Yes — captures 10/22 | No candidate-final proposal | Tall/keyboard/destructive | High |
| Dialogs | Partial | No candidate-final proposal | Error/confirm/large text | Medium |
| Context menus | Yes — capture 09 | No candidate-final proposal | Translation/edge/RTL | High |
| Empty states | Partial | Partial | Loading-to-empty/retry | Medium |
| Loading states | No useful set | No | Pagination/sync/processing | High |
| Error states | No useful set | No | Network/crypto/media/permission | Critical |

## 2. Critique of Existing V2 Proposal

### Dark surfaces — modify

Deep dark surfaces suit Mknoon because the live app is built around a night-sky/orbital world (E01–E05), not because dark automatically looks premium. The first V2 gained hierarchy but lost character. Keep a night-sky canvas, reduce star contrast, create quiet reading zones, and reserve graphite surfaces for content (E07 B, E09, E10).

### Violet — reject as global primary

Universal `#6045B6` made the proposal contemporary but Discord-adjacent and overloaded one color across send, create, unread, selection, and navigation. Violet may remain one relationship’s orbit color; it is not the system primary. Compare E07 A→B and E08 A→C.

### Green — keep narrowly

Green already reads as connected/live in the current app. Restrict it to presence, successful connection, secure/protected confirmation, and positive completion. Do not use it as a generic CTA.

### Teal — reject as another global accent

The first V2’s teal reply/focus/read family did not add enough semantic value. Use celestial blue for global focus/read/send. Reply edges inherit the referenced sender’s relationship color where possible.

### Contrast — increase

The first V2’s `#777483` metadata was too quiet. Candidate muted text is `#8A96A0`: 6.56:1 on the dark canvas and 6.06:1 on a dark surface. Light muted `#66747F` is 4.81:1 on white. Metadata may be subordinate, not difficult.

### Density — modify selectively

The first V2’s 84–88px **Chat List** rows remained presentation-like. Candidate list rows target 76–80px at 100%, grow with content, and do not force 160% text into a fixed height (E15/E13). Orbit itself has no rows; its density problem is node collision and ring legibility, which requires a runtime spatial stress prototype. Conversation density remains calm at normal size and content-first under scaling (E12/E13).

### Surface layering — keep principle, reject overuse

Replacing every outline with a filled rounded rectangle is not enough. Candidate rules:

- Canvas separates the world.
- Headers/composer/sheets are structural surfaces.
- Normal list rows are flat.
- Unread or pressed content may receive a quiet field.
- Message bubbles remain filled for ownership/readability.
- Spacing and type perform most grouping.

### Rounded containers — reduce

The first V2 still had an online pill, segmented-control pill, selected card, search field, bottom navigation, reactions, composer, and circular controls. Candidate removes the online capsule, full filter capsule, persistent search field, invented bottom navigation, and persistent selected-row treatment.

### Branding — substantially modify

Without orbital avatars, the first V2 could belong to another premium messenger. Candidate identity also appears in a restrained celestial canvas, dashed circular line grammar, relationship-colored message signatures, orbital active markers, celestial-blue global action, and motion based on orbit completion/halo/drift.

## 3. Missing Screens / States

The most decision-critical current screenshots still needed are specific:

1. **CURRENT APP — Group conversation with three visible senders and one system message, keyboard closed.** Sender identity/system hierarchy cannot be validated from direct-chat captures.
2. **CURRENT APP — Direct conversation while a video is playing, keyboard closed.** Media chrome/background competition is unknown.
3. **CURRENT APP — Composer during a failed attachment upload with Retry/Delete visible.** This is the highest-risk density state.
4. **CURRENT APP — Composer with protected media selected and one image staged.** Policy/attachment hierarchy is unknown.
5. **CURRENT APP — Voice recording while held, plus voice review after release.** Live affordance and transition remain unproven.
6. **CURRENT APP — Editing a long multiline RTL message.** Direction, save/cancel, and scaling remain unknown.
7. **CURRENT APP — Unread divider between dense runs.** Contrast and anchoring remain unknown.
8. **CURRENT APP — Sync/loading banner and terminal failed message together.** Error hierarchy needs real evidence.

Capture these through test fixtures or a visual harness, not by manufacturing history in a user’s live conversations.

## 4. Alternative Visual Directions

All three Orbit alternatives preserve the same spatial product model. They vary atmosphere and emphasis, not layout, navigation, or interaction.

### A — Refined Original

Closest to today’s visual language: visible stars, bright node glow, and stronger colored rings. It is recognizably Mknoon and highly faithful, but glow can compete with unread/selected state. **Keep as a fidelity boundary, not the final intensity.** E01/E07 A.

### B — Orbital Quiet

Night-sky canvas, quieter neutral orbit paths, relationship color localized to nodes and active arcs, celestial-blue global actions, and green connection semantics. It remains unmistakably orbital while allowing state changes to become meaningful. **Recommended candidate.** E07 B/E09/E14.

### C — Cosmic Signature

The same rings and controls with more atmospheric arcs and depth. This extends the Mknoon identity beyond avatars, but risks making the background compete with relationships. **Keep as an upper boundary for brand expression.** E07 C.

The Conversation A/B/C comparison in E08 still tests graphite/violet, neutral, and orbital-signature treatments for messaging. The rectangular alternatives in E15 apply only to the existing Chat List mode.

## 5. Orbit Comparison

The Orbit is not a decorative avatar treatment on a list. It is the product’s relationship-navigation model. Replacing it with rows is rejected regardless of how polished those rows appear.

### Orbit canvas

| Question | Decision | Evidence |
|---|---|---|
| Replace rings with a list? | Reject. This changes Mknoon’s concept and navigation model. | E01/E14/E15 |
| Central self/connection node? | Keep its position and meaning; refine contrast and halo only. | E01/E09 |
| Relationship nodes on rings? | Keep. Relationship color belongs to each node; unread adds a badge plus brighter arc. | E01/E07/E09 |
| Ring geometry? | Keep concentric spatial hierarchy. Reduce line contrast and use selective active arcs rather than making every ring luminous. | E01/E07/E09 |
| Star field? | Keep as identity, reduce density/contrast around controls and nodes. | E01/E09 |
| Filled violet create button? | Reject; preserve its circular position with an outlined celestial action. | E01/E07/E09 |
| Online pill? | Modify visual treatment to dot + plain status while preserving placement and behavior. | E01/E09 |
| Mode-switch control? | Keep the existing circular List/Orbit switch and its location. | E01/E02/E09 |
| Floating search? | Keep its position and action model; refine surface/contrast only. | E01/E03/E09 |
| Light mode? | Use a cool celestial chart with the identical ring/node hierarchy, not a mechanical inversion. | E09/E14 |
| More relationships? | Add nodes only through the existing ring-placement logic; validate collision, scale, and accessibility at runtime. | E07/E09 |

### Chat List only

| Question | Decision | Evidence |
|---|---|---|
| Is the Maya row too dominant? | Yes. Use a quiet unread field, not a persistent selected card. | E02/E15 |
| Violet leading bar? | Reject; desktop-like and duplicates badge/field. | E15 |
| Filter capsule? | Reject; use a flat rail with a clear active marker. | E03/E15 |
| Separators? | Keep inset from the text column, never full width. | E02/E15 |
| 84px rows? | Modify to 76–80px at 100%, content-driven above. | E15/E13 |
| Persistent search field? | Reject; retain the existing floating action until search opens. | E02/E03/E15 |
| Invented bottom navigation? | Reject; it is not part of the current navigation model. | E02/E15 |
| Avatar dominance? | Reduce dense-list outer footprint to approximately 44px without weakening orbital marks. | E02/E15 |

## 6. Conversation Comparison

The V2 violet outgoing bubble is rejected. Candidate conversations use neutral tones with small relationship signatures:

- incoming: contact color at the speaker edge of the run;
- outgoing: own/celestial edge at the speaker edge;
- neutral fill preserves calm over long threads;
- repeated bubbles tighten corners without becoming pill stacks;
- signatures appear only where structurally useful, not necessarily every bubble.

Maximum width is roughly 76–78% at normal type, wider only when dynamic type requires it. Metadata is 10.5–11.5px at 100% with compliant contrast and moves to its own line at 160%. The introduction remains as a subordinate inline system surface. Media leads inside the bubble; caption/status follow. Ambient stars stay fixed and subtle. See E08/E10/E12/E13.

## 7. Composer State Comparison

The previous complex-state mock is rejected as the composer’s defining design. It unfairly stacked reply, attachments, add-media, multiline input, privacy pill, close, and keyboard.

| State | Candidate behavior |
|---|---|
| Idle | One 58px field; attach/mic share the surface instead of three outlined widgets. |
| Typing | Field grows; send becomes the only filled action. No permanent counter. |
| Reply | Thin context strip above field; close is a plain icon with 44px hit target. |
| Attachment | 72px thumbnails above; no permanent Add-media card. Privacy status is contextual. |
| Voice recording | Same seat transforms to timer/waveform/stop; keyboard absent and footprint stable. |

See E11. Edit, upload progress/failure, and voice review remain blocking gaps for the full composer family.

## 8. Light Mode Validation

Reject the warm beige V2 palette: it felt editorial rather than celestial and weakened parity. Candidate light mode is cool pearl, not a mechanical inversion:

- canvas `#F2F6F8` with faint celestial-chart lines;
- structural/incoming `#FFFFFF`;
- outgoing `#E7EEF3`;
- unread `#E6F0F6`;
- primary text `#14202A`;
- secondary `#4E5C66`;
- muted `#66747F`;
- action blue `#176B93`;
- connected green `#1D7447`.

Dark and light share shape, spacing, relationship placement, and orbit markers. Dark uses stars/luminous arcs; light uses chart lines/cool depth. See E09–E11.

## 9. Real-Content / RTL / Scaling Validation

E12/E13 are mockups, not runtime proof. They establish these rules:

- Long names get two lines at 130%, not tiny type.
- At 160%, rows grow and previews truncate before names.
- Message text never shrinks to preserve bubble silhouette.
- Metadata gets its own line at 160%.
- RTL alignment follows content direction while ownership stays in sender lane.
- Mixed Arabic/Latin names and URLs use Unicode bidi handling, not one forced direction.
- Unread counts retain 24–26px visual seats and appropriate semantics.

The evidence covers one-word messages, paragraphs, URL, emoji, Arabic, English, mixed names, groups, and unread density. Actual Flutter screenshots at 130/160% remain a prototype gate.

## 10. Accessibility Findings

| Pair | Contrast |
|---|---:|
| Dark primary `#F3F6F8` / `#070A0F` | 18.26:1 |
| Dark secondary `#B6C0C8` / `#070A0F` | 10.73:1 |
| Dark muted `#8A96A0` / `#070A0F` | 6.56:1 |
| Dark muted / `#10151D` | 6.06:1 |
| Dark blue `#7CC8F5` / `#10151D` | 9.97:1 |
| Dark green `#53D184` / `#10151D` | 9.43:1 |
| Light primary `#14202A` / `#F2F6F8` | 15.21:1 |
| Light secondary `#4E5C66` / white | 6.89:1 |
| Light muted `#66747F` / white | 4.81:1 |
| Light blue `#176B93` / white | 5.90:1 |
| Light green `#1D7447` / white | 5.77:1 |

Additional findings:

- Orbit rings cannot be the only state signal; pair with text/dot/badge/semantics.
- Unread combines weight + count/dot + optional field, never color alone.
- Error/success/privacy use icon + text, not red/green alone.
- Visual controls may be smaller, but hit targets remain at least 44×44 logical px.
- At 160%, composer/context/list rows grow; clipping is unacceptable.
- Reduce Motion stops orbit drift, avatar breathing, stagger, scale, and parallax.
- Stars/chart lines stay below content contrast and are masked under dense text as needed.

## 11. Flutter-vs-Design Classification

| Finding | Classification | Why |
|---|---|---|
| Too many outlines/cards/pills | DESIGN SYSTEM ISSUE | Token/component decisions. |
| Violet for every action/state | DESIGN SYSTEM ISSUE | Semantic palette choice. |
| Composer feels assembled | COMPONENT IMPLEMENTATION ISSUE | One Flutter component can hold a stable footprint. |
| Bubble grouping inconsistent | COMPONENT IMPLEMENTATION ISSUE | Flutter can render exact run radii. |
| Low-contrast metadata | DESIGN SYSTEM ISSUE | Color-role choice. |
| Muddy/slow blur | COMPONENT IMPLEMENTATION ISSUE | Tune blur scope/raster fallback. |
| Keyboard differs by device | PLATFORM-SPECIFIC EXPECTATION | IME is user/platform controlled. |
| Text selection/cursor/menu | PLATFORM-SPECIFIC EXPECTATION | Validate adaptive Flutter controls before custom work. |
| Haptics differ by OS | PLATFORM-SPECIFIC EXPECTATION | Use platform-appropriate haptics through Flutter. |
| Message context overlay | COMPONENT IMPLEMENTATION ISSUE | Flutter can render it; native only if parity fails. |
| Scanner preview/permissions | PLATFORM-SPECIFIC EXPECTATION | Native boundary; surrounding screen remains Flutter. |
| Video PiP/system controls | CONSIDER NATIVE COMPONENT | OS integration can improve reliability; no native screen needed. |
| “Flutter looks Flutter-like” | NOT A REAL PROBLEM | Causes are spacing, icons, borders, and decentralized tokens. |

No reviewed visual requires a native screen rewrite.

## 12. Decision Matrix

| Change | Keep / Modify / Reject | Why | Visual | UX | Cost | Confidence |
|---|---|---|---|---|---|---|
| Deep dark canvas | Modify | Keep celestial night; reduce contrast. | High | Medium | Medium | High |
| Warm beige light | Reject | Weak parity/character. | High | Low | Medium | High |
| Cool pearl light | Keep | Intentional daylight expression. | High | Medium | Medium | High |
| Universal violet | Reject | Generic/Discord-adjacent. | High | Medium | Medium | High |
| Celestial-blue action | Keep | Separates global action from relationships. | High | Medium | Low | Medium |
| Green semantic states | Keep | Matches current meaning/trust. | Medium | High | Low | High |
| Global teal | Reject | Unnecessary competition. | Medium | Medium | Low | High |
| Spatial Orbit canvas | Keep | Defining relationship-navigation concept. | High | High | Medium | High |
| Replace Orbit with Chat List | Reject | Structural product change, not visual refinement. | High | High | Medium | High |
| Quiet neutral orbit paths | Keep/validate | Preserves hierarchy while letting node state lead. | High | Medium | Medium | High |
| Relationship orbit colors | Keep | Strongest product-specific asset. | High | Medium | Medium | High |
| Colored outgoing bubble | Reject | Too saturated/borrowed. | High | Medium | Low | High |
| Relationship signature edge | Keep | Identity with low visual mass. | High | Medium | Medium | Medium |
| Chat List persistent selected row | Reject | Not useful after mobile navigation. | Medium | Medium | Low | High |
| Chat List quiet unread field | Keep | Clear without card repetition. | High | High | Low | High |
| Chat List violet leading bar | Reject | Duplicate/desktop-like. | Medium | Low | Low | High |
| Chat List flat normal rows | Keep | Density and meaningful state. | High | High | Low | High |
| Chat List persistent search field | Reject | Space cost/model change. | Medium | Medium | Low | High |
| Invented bottom nav | Reject | Structural change. | High | High | Medium | High |
| Compact intro banner | Keep/validate | Preserves feature quietly. | Medium | High | Medium | Medium |
| One-surface composer | Keep | Stable and intentional. | High | High | Medium | High |
| Permanent privacy pill | Reject | Contextual state, too heavy. | Medium | Medium | Low | High |
| Contextual privacy cue | Keep | Near relevant media. | Medium | High | Medium | Medium |
| Content-driven scale reflow | Keep | Accessibility-first. | High | High | High | Medium |
| Celestial motion | Modify | State/identity only; reduce-motion safe. | Medium | Medium | Medium | Medium |

Medium/low-confidence items need failed-upload, group-message, voice-review, and runtime dynamic-type evidence.

## 13. Candidate Final Mknoon Visual Direction

### Identity

Relationships in orbit: circular/dashed line grammar, person-specific orbit color, quiet celestial field, and connection-oriented motion. Without avatars, relationship signatures, orbit markers, atmosphere, and motion still carry identity.

### Color

Global action is celestial blue, not violet. Relationship colors belong to people/circles. Green means connected, secure, or complete. Error is coral/red; warning amber. No global teal family.

Dark core: `#070A0F`, `#10151D`, `#151B23`, `#1A222C`, `#202A36`, action `#7CC8F5`, connected `#53D184`.  
Light core: `#F2F6F8`, `#FFFFFF`, outgoing `#E7EEF3`, unread `#E6F0F6`, action `#176B93`, connected `#1D7447`.

### Surfaces

Canvas → structural → message/interactive → temporary floating. Normal rows are flat. Borders are hairlines/focus/semantic/media only. Shadows belong to floating actions/sheets, not every row.

### Typography

Small hierarchy: title, row/message body, preview, label, metadata. Metadata remains readable. Arabic requires a font with excellent shaping and comparable optical weight; Latin fallback is not enough.

### Spacing

4, 8, 12, 16, 24, 32. Screen gutter 16. Chat List rows are 76–80px at 100%, content-driven above. Orbit spacing follows ring geometry and collision-safe node zones rather than the list spacing scale. Bubble runs use 4–6px internal and 12–16px between speakers. Composer is 58px idle.

### Shape

People/orbital actions are circular. Message content uses 14–16px radii. Structural surfaces use 12–16px. Pills are for genuine compact metadata, not the default component shape.

### Icons

One rounded-line family, 1.75–2px optical stroke. Filled icons mean active/primary. Orbit-specific icons may use dashed circular construction; generic controls should not imitate the logo.

### Motion

Press 80–120ms; state 160–220ms; connection arc/halo 280–360ms once. No infinite breathing in dense screens. Reduce Motion disables drift/parallax/stagger/scale.

### Messaging

Neutral bubbles are the reading field. Relationship color appears at speaker edge/header orbit. Group sender name adds text to color. Media leads; reaction/status remain subordinate. Composer stays one stable system.

### Orbit

The spatial canvas is non-negotiable product structure: central self/connection node, concentric relationship rings, relationship nodes positioned on those rings, circular mode switch, online/create controls, and floating search all remain. V2 changes only canvas tone, star masking, orbit-line contrast, node rendering, state arcs/badges, control styling, and motion quality. See E01/E07/E09/E14.

The separate Chat List may feel like a projection of Orbit through avatars, active arcs, celestial depth, and relationship-aware unread states, but it does not replace Orbit. See E02/E15.

### Light mode

A daylight celestial chart, not beige inversion: cool pearl, subtle chart lines, preserved orbit colors, same hierarchy.

## 14. Things I Still Don't Like

- Celestial blue may still read as conventional tech blue; motion/orbit grammar must carry identity.
- Message signature edges are unresolved for long runs, media-only messages, and many group colors.
- Light mode is coherent but less emotionally distinctive; chart lines may become invisible or noisy.
- Orbit’s multi-ring stress behavior remains unresolved: five nodes look clear in a mockup, but 10+ relationships need actual collision/zoom testing.
- Orbit header still has three concepts—mode switch, online, and create—and needs runtime spacing validation.
- Floating search is faithful but may obscure bottom content.
- Five-plus attachments and upload failure may force another composer grammar.
- Voice recording is plausible, not interaction-proven.
- Typography is still generic; Arabic/Latin font pairing needs actual font testing.
- Error, loading, unread-divider, system-message, and group-sender systems remain under-designed.
- Star density/masking needs OLED and low-brightness testing.

## 15. Recommended Next Step

### READY FOR SMALL PROTOTYPE

Implement **one isolated Orbit prototype behind a non-production route or visual harness**, only after explicit approval. The prototype must reuse the current ring layout and interactions; it is a visual skin experiment, not a list replacement. Keep the Chat List as a separate comparison surface. Do not begin broad token refactoring because high-density Orbit behavior, group identity, composer failures/review, runtime RTL/type scaling, and other major surfaces remain unvalidated.

Prototype gate: same Pixel 6 plus one iOS simulator; dark/light; Reduce Motion on/off; 1/5/10+ relationship nodes; selected/unread/offline states; and current/candidate side by side. Test Chat List text scaling and Arabic/mixed names separately rather than treating list rows as Orbit evidence.

## External quality benchmarks — principles, not layouts

- Discord: consistent shape semantics, chat-bar prioritization, deliberate dark themes, accessibility controls—not blurple or server structure: [design-system update](https://discord.com/blog/improving-mobile-with-squircles-styles-and-spacing), [feedback revisions](https://discord.com/blog/refining-discords-mobile-experience-with-your-feedback).
- Signal: calm neutral fields and clear pinned/system/group identity without privacy chrome dominating every row: [pinned messages](https://signal.org/blog/pinned-messages/), [message requests](https://signal.org/blog/message-requests/).
- Telegram: branded backgrounds can coexist with readable messages; composer-to-message motion can be restrained: [animated backgrounds/send motion](https://telegram.org/blog/animated-backgrounds/ar?setln=en).
- WhatsApp: progressive disclosure across filters, attachment, reaction, voice, and media—not its colors/layout: [messaging](https://www.whatsapp.com/messaging).
- iMessage: sparse unread/list state and secondary capabilities behind Add—not blue bubbles: [Messages guide](https://support.apple.com/guide/iphone/send-and-reply-to-messages-iph82fb73ba3/ios).
