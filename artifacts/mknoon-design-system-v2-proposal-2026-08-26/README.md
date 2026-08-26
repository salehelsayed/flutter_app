# Mknoon Design System v2 — Three-Screen Visual Proposal

Date: 2026-08-26  
Status: Visual validation only; no production Flutter code changed.

This proposal applies the audit’s main recommendation: preserve Mknoon’s product model and orbital identity, but replace the current mix of pale outlined widgets and local colors with one layered, restrained consumer-app system.

The mockups show dark mode because its layers expose the proposed hierarchy most clearly. The same component roles should map to the light palette rather than being independently restyled.

## Shared visual language

### Core colors

| Role | Dark proposal | Light parity | Use |
|---|---:|---:|---|
| App background | `#090A10` | `#F3F0EA` | Screen canvas |
| Primary surface | `#11131B` | `#FAF8F3` | Header, bottom dock, sheets |
| Elevated surface | `#191C26` | `#FFFFFF` | Incoming messages, selected rows, input |
| Interactive surface | `#202431` | `#ECE8F4` | Icon buttons, secondary controls |
| Relationship primary | `#6045B6` | `#6045B6` | Send, selected state, unread count |
| Presence / success | `#39C67A` | `#237B4B` | Online state, connected ring, success |
| Interaction accent | `#4ECDC4` | `#0F766E` | Reply edge, delivery/read details, focus |
| Text primary | `#F4F3F8` | `#17151C` | Titles and main content |
| Text secondary | `#A4A1AF` | `#625E69` | Previews and supporting copy |
| Text muted | `#777483` | `#817C87` | Time, metadata, placeholders |
| Hairline | white at 5.5% | `#DDD8E1` | Inset separators only |

Color behavior is semantic. Green is no longer a generic primary button color; it means connected, live, protected, or successful. Violet owns relationship actions and selection. Teal is a small focus/read/reply accent.

### Type and rhythm

- Screen title: 20/24, weight 740.
- Conversation title: 17/21, weight 700.
- Row title: 15.5/20, weight 650–700.
- Message/body: 15/21, weight 400–500.
- Secondary body: 13/18, weight 400–500.
- Label: 12/16, weight 650–700.
- Metadata: 10.5–11.5/14, weight 500–650.
- Base spacing scale: 4, 8, 12, 16, 20, 24, 32.
- Screen gutter: 16; dense list text inset after avatar: 14–16.
- Component radii: 12 controls, 16 compact media, 18 bubbles, 20 rows, 22–24 composer/dock.

## 1. Direct Conversation

### CURRENT

The current screen preserves a recognizable Mknoon avatar and connection state, groups messages into bubbles, and keeps the header, messages, introduction prompt, and composer in the expected places.

### PROBLEM

- The near-white canvas, white bubbles, violet outlines, outlined composer, and large introduction card all compete at roughly the same visual level.
- Bubble ownership is communicated mainly by outline and alignment; the bubble fill itself carries little hierarchy.
- The introduction prompt dominates the conversation, even though it is secondary to the chat.
- Timestamps and delivery state are attached to message text without enough typographic separation.
- The header and composer look like independent Flutter regions rather than the top and bottom layers of one conversation surface.
- Mknoon’s orbital identity appears in the avatar but does not influence the rest of the composition.

### PROPOSED VISUAL DIRECTION

Keep the existing header, introduction action, grouped bubbles, reactions, media, and bottom composer. Move the screen to a deep layered canvas where incoming and outgoing messages are differentiated by tone rather than outlines.

The orbital avatar remains the strongest branded element. A very restrained violet/teal ambient field behind content connects that identity to the whole screen without turning the chat into a decorative space scene.

### SPECIFIC DESIGN CHANGES

- Canvas: `#090A10` → `#10121B` subtle diagonal tonal shift; no visible full-screen card.
- Header: `#11131B` at approximately 92% opacity with one 5.5% white hairline. Back and overflow controls use 38px `#191C26` circles.
- Conversation avatar: 44px ring mark; green dashed connection ring, violet core. Keep tap behavior.
- Introduction prompt: reduce to a 78px compact elevated banner. Use `#151923`, 18px radius, green border at 24% opacity, and one 38px action. “Maybe later” can remain in overflow or as a quiet text action when space allows.
- Incoming bubbles: `#191C26`, no border, 18px outer corners and 6px grouped corners.
- Outgoing bubbles: `#30294A`; add only a 1px violet speaker-edge accent where it helps ownership. Do not use a bright saturated fill.
- Message text: 15/21, primary text. Timestamp: 10.5/14, muted. Delivery/read glyph: teal, 12–14px.
- Media: 6px inset within its bubble, 15–16px media radius. Captions stay part of the message bubble.
- Reactions: 30px-high `#1F2230` pills with hairline only; selected reaction uses a violet-tinted surface.
- Composer: one 72px `#151820` dock with a 24px radius. Secondary attach control is 40px; primary mic/send is 48px violet. Remove the three strong violet outlines.
- Vertical rhythm: 8px within a speaker run, 12–16px between runs, 20–24px around separators and banners.

### BEFORE / AFTER

- [Current capture](../signal-theme-ui-audit-2026-07-09/08-signal-conversation.png)
- [Proposed mockup](direct-conversation-after.png)
- [Side-by-side comparison](direct-conversation-comparison.png)

### DO NOT CHANGE

- Header placement and navigation behavior.
- Existing message ordering, grouping logic, ownership alignment, long-press actions, reaction behavior, status semantics, media behavior, and introduction feature.
- Composer position and attachment/voice/send capabilities.

### IMPACT

Visual impact: High  
Implementation cost: Medium  
Risk: Low–Medium; most risk is message-state contrast and regression across message variants.

## 2. Message Composer

### CURRENT

The current composer already supports attachments, text, voice recording, sending, replies, edits, upload states, protected media, and review flows. Its placement and interaction model are appropriate and should remain.

### PROBLEM

- The attach button, text field, and microphone are three separately outlined shapes, so the control reads as assembled rather than designed as one system.
- All controls have similar emphasis even though send/record is primary and attach is secondary.
- Local violet, teal, green, and white treatments vary between composer states.
- Reply, attachment, private-media, upload, and recording states can stack into visually unrelated mini-widgets.
- The field’s generous outline and placeholder sizing produce a generic Flutter `TextField` appearance.
- State changes can alter the composer’s silhouette more than necessary, making the bottom of the screen feel unstable.

### PROPOSED VISUAL DIRECTION

Keep the exact functional states but give them one stable bottom-sheet/dock grammar. The composer has three layers:

1. Context layer — reply/edit/attachment previews.
2. Input layer — text plus secondary controls and primary send/record action.
3. Status layer — protected media, upload, recording duration, or validation.

The focused mockup deliberately shows a complex state—reply plus attachment plus protected media—to prove the system remains coherent under real product complexity.

### SPECIFIC DESIGN CHANGES

- Collapsed dock: 72px minimum height, `#151820`, 24px radius, 12px screen inset.
- Focused/expanded surface: `#11131B`, 28px top radius, low black shadow; maintain keyboard and safe-area behavior.
- Reply preview: no card. Use a 3px teal vertical edge, 11.5px uppercase sender label, and 13px one-line excerpt.
- Attachment tile: 104×92, 16px radius. Removal action is a 28px dark floating control. “Add media” uses a quiet dashed hairline, never a full-accent border.
- Input: `#191C26`, 22px radius, 16px horizontal padding, 12px vertical padding. No outline in rest state; show a 1px teal focus ring only for accessibility/focus feedback.
- Text: 15/22. Placeholder: `#777483`. Counter: 11px muted and hidden until useful.
- Attach/utility buttons: 32–40px `#232734` circles. Keep at least a 44px hit target through invisible padding.
- Primary send: 44–48px violet `#6045B6`, white icon. Sending state becomes an inline progress treatment inside the same circle, preserving its footprint.
- Voice state: the same primary-action seat transforms from mic to stop/send; duration and waveform occupy the input layer rather than creating a new unrelated card.
- Protected-media state: 34px semantic green pill `#15241F` with `#A9F0C4` text. It is status, not a second CTA.
- Motion: 160–220ms shape/color transitions, spring only for the send/mic swap, selection haptic on protected-media mode change, and reduced-motion parity.

### BEFORE / AFTER

- [Current capture](../signal-theme-ui-audit-2026-07-09/08-signal-conversation.png)
- [Proposed focused-state mockup](message-composer-after.png)
- [Side-by-side comparison](message-composer-comparison.png)

### DO NOT CHANGE

- Bottom placement, keyboard relationship, text drafting, send behavior, voice hold/record behavior, attachment access, reply/edit semantics, protected-media choices, progress states, or safe-area handling.
- Do not turn the composer into a Discord-style toolbar or expose every action permanently.

### IMPACT

Visual impact: High  
Implementation cost: Medium  
Risk: Medium; the component has many functional states and needs visual regression coverage.

## 3. Orbit / Chat List

### CURRENT

The screen has a strong product-specific foundation: orbital avatars, presence, All/Intros/Archived filtering, search, unread counts, create action, and a recognizable relationship metaphor. The current list is readable and its major controls are easy to find.

### PROBLEM

- Every conversation is a large pale outlined card. Repetition makes the list heavy, increases vertical cost, and gives normal rows the same prominence as unread/selected rows.
- The segmented control uses another strong outline, creating a stack of boxes before content begins.
- The large purple create button, green online pill, violet borders, multicolor avatars, and white canvas compete without a clear accent hierarchy.
- Chevron icons add noise while row tap behavior is already conventional.
- Preview, time, badge, and name spacing feels widget-based rather than tuned as a dense messaging list.
- The orbital identity is present in every avatar but is weakened by the surrounding generic cards.

### PROPOSED VISUAL DIRECTION

Keep Orbit’s structure, filters, add action, rows, search dock, and navigation. Let the orbital avatars carry identity while list hierarchy comes from typography, spacing, and selective surfaces.

Normal rows become mostly flat on the app canvas with inset separators. Only a selected/unread/recently active row receives an elevated surface and a slim violet relationship edge. This makes active state unmistakable and improves density without making the screen feel utilitarian.

### SPECIFIC DESIGN CHANGES

- Canvas: `#090A10` with extremely subtle violet/teal ambient glows; no decorative cards behind sections.
- Header: title 20/24 weight 740, supporting line 12.5/18. The self-orbit remains 48px. Online pill uses semantic green only. Create button remains violet and 48px.
- Filter: `#141720` container, 46px height, 14px radius, no border. Active segment uses `#252536`; count badge uses violet. Inactive labels use muted text.
- Section label: 11px uppercase, 1.1px tracking, muted.
- Normal row: 84px target height, transparent background, 16px screen inset. Avatar 50px; name 15.5/20; preview 13/18; time 11.5/14. Use a hairline from the text inset, not edge to edge.
- Selected/unread row: 88px `#191C26`, 20px radius, 3px violet leading edge, no full outline. Unread count is a 24px violet circle.
- Remove chevrons from standard chat rows. Keep explicit accessory icons only when the row has a nonstandard destination or status.
- Orbit avatars: 50px outer footprint, 2px dashed status ring, 34px colored core. The ring color communicates relationship/presence; the core may retain individual color identity.
- Search: one 58px dock in `#151820`, 22px radius, placed in the existing lower navigation band.
- Bottom navigation: a quiet `#151820` capsule with one violet-tinted selected seat. Preserve the app’s current destinations and swipe behavior.
- Motion: 120ms pressed-surface tint, 180ms active-filter slide/fade, restrained row insertion, and existing reduced-motion behavior.

### BEFORE / AFTER

- [Current capture](../signal-theme-ui-audit-2026-07-09/05-signal-all-chats.png)
- [Proposed mockup](orbit-chat-list-after.png)
- [Side-by-side comparison](orbit-chat-list-comparison.png)

### DO NOT CHANGE

- Orbit/List view model, All/Intros/Archived filtering, add/create entry point, conversation destinations, avatar-to-profile action, swipe/archive behavior, search behavior, unread semantics, or app-level navigation model.
- Do not introduce Discord server/channel rails or nested navigation.

### IMPACT

Visual impact: High  
Implementation cost: Low–Medium  
Risk: Low; changes are predominantly tokens, row decoration, icon removal, and spacing.

## Validation recommendation

Validate the proposal with five static states before implementation:

1. Direct conversation with text, media, reaction, failed message, and grouped bubbles.
2. Composer idle, typing, reply/edit, attachment upload, and recording/review.
3. Orbit list with unread, selected, intro, archived, group, long names, RTL previews, and large text scaling.
4. Light-mode parity using the same semantic roles.
5. Contrast and dynamic-type checks at 100%, 130%, and 160% text scaling.

The best first production experiment, after visual approval, is Orbit / Chat List. It has high perceived impact, the smallest state matrix, and establishes the shared surface/type/spacing tokens needed by conversation and composer.
