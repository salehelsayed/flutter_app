# Whole-App Component and Journey Checklist

This checklist applies to **every discovered component family**, not just circles, gestures, or custom canvases. The families below are discovery prompts; do not claim an app implements them without evidence. Add any family the app actually contains that is missing here. Principles and source-backed thresholds are in `references/research.md`; the checks here are an operational synthesis, not a formal compliance standard.

## A. Coverage Model

Maintain two linked inventories:

1. **Surface/journey inventory:** screen or overlay, purpose, entry points, exit/return paths, significant states, dependent surfaces, evidence, and coverage status.
2. **Component inventory:** component family, each usage context, actual source anchor, supported actions and inputs, visual/semantic/hit bounds, state variants, representative samples, evidence, and coverage status.

A reusable button test does not prove its behavior under every parent overlay or constraint. Conversely, do not create separate duplicate findings for every consumer of the same defective shared component: record one cause with all affected contexts.

Use explicit statuses: `planned`, `inspected-source`, `tested-runtime`, `failed`, `blocked`, `deferred`, `not-applicable`. Record evidence dimensions separately if a row has both source and runtime coverage. Explain every exclusion; `not discovered` is not a proven absence. Keep failed observations visible after a successful rerun.

For whole-app scope, give every discovered family and journey a first-pass review before concentrating all effort on one area. If a time budget limits coverage, deliver the remaining ledger rather than silently narrowing the request.

## B. Component Families

| Family | Inspect and exercise | Often-missed details |
|---|---|---|
| App shell and navigation | Tabs, drawer, bottom/top bars, back, deep links, entry from notifications, nested routes | Current location, selected state, repeated-tap behavior, back vs dismiss vs exit, safe-area clipping, return-to-origin, no duplicate routes |
| Buttons and action controls | Text/icon/FAB controls, chips, links, disabled and busy states | Visible purpose, actual target and focus area, hover/press/focus consistency, duplicate activation, disabled reason, neighboring accidental action, label/icon alignment |
| Lists, cards, grids, avatars, custom layouts | Whole-row action vs nested buttons, pagination, refresh, expansion, sorting, selection, reordering | Stale identity after reorder, visible item vs actual destination, hit overlap, scroll stealing taps, separators, blank padding, high-density layouts, restored scroll/selection |
| Text inputs, forms, search | Field labels, validation, keyboard type, focus traversal, clear/reveal controls, submit/search | IME composition, paste/autofill, Unicode/emoji, whitespace rules, multiline growth, keyboard covering CTA, retained values after failure, empty vs no-results, stale search results, errors not relying on color |
| Menus, context actions, tooltips | Overflow menus, long-press actions, submenu/popup placement, selected state | Visible alternative to hidden gestures, first-item accidental activation, clipped last item, dismiss on outside/back/Escape, focus restoration, tooltip not the only accessible name |
| Sheets, dialogs, popovers, drawers | Open/close routes, drag-to-dismiss if supported, barrier, back, focus, keyboard | No click-through to background, no focus behind modal, unsaved-content loss, nested modal confusion, scroll vs drag conflict, content reachable at enlarged text |
| Onboarding, authentication, permissions | First-run entry, explanations, account/session state, deny/skip/retry, OS-settings return | Don't pre-empt OS prompts unnecessarily, no forced loops, truthful capability status, field recovery, accessible legal links, preserve entered data, graceful denial and cancellation |
| Settings and selection controls | Switches, checkboxes, radio groups, segmented controls, sliders, pickers, dates/times | Row and control not toggling twice, save vs immediate effect, current value persists after reload, units/range/timezone clarity, dependent disabled states, non-drag alternatives |
| Feedback and async states | Loading, refreshing, optimistic updates, progress, success, retry, errors, toasts/snackbars, banners | Actual vs optimistic outcome, indefinite spinner exit, dismiss/retry accessible, stale error not overwriting new success, feedback near action, no announcement spam or unnecessary alerts |
| Text, icons, badges, status | Titles, body, timestamps, unread/presence badges, identity labels, symbols, explanatory copy | Truncation hides important distinctions, numeric overflow, locale formatting, contrast on real backgrounds, color-only meaning, decorative semantics, ambiguous icons, changing status distracts focus |
| Media, attachment and viewer controls | Select, preview, upload/download, progress, cancel/retry, zoom, playback, seek, fullscreen | Missing/slow assets, aspect ratio/layout shift, crop hides meaning, picker cancellation, repeated uploads, visible playback state, seek alternative, orientation/back restoration, accessible media information where supported |
| Conversation and composer controls | Draft, send, pending/failed messages, reply/edit/delete, attachments, unread navigation, scroll-to-latest | Correct recipient, no duplicate send, preserve draft on navigation/retry, send vs newline/IME behavior, recording lock/cancel, incoming content not hijacking reading position, distinguish local pending from delivery |
| Calling and live-session controls | Join/leave, mute, camera, speaker/route, reconnect, interruptions, permission state | Actual device state vs icon, accidental hangup, controls during transition, audio-route names, interrupted session recovery, readable duration/status, privacy-sensitive camera/mic feedback |
| Empty, unavailable, restricted and edge surfaces | No content, no matches, offline, disconnected peer, denied permission, expired session, deleted content | Distinguish reasons, actionable recovery, truthful status, no dead ends, no disappearing essential actions, no assumption that unavailable remote content must block local navigation |
| Embedded/native/custom components | WebViews, OS pickers, native views, charts/canvases, custom gesture surfaces | Focus and back crossing boundaries, coordinate/scale changes, native vs app theme, semantics exposed, safe-area/inset handling, system gesture conflicts, overlay ordering |

## C. Apply These Lenses to Each Family

### 1. Clarity and discoverability

- Is the primary next action apparent without instructions? Can a new user explain a control's purpose from visible information?
- Are names, icons, and placement consistent across screens and states? Distinguish actions like Back, Close, Cancel, Save, Done, Retry, and Discard.
- Are secondary actions available through an obvious control, not just an undocumented gesture or hover?
- Does help appear in context, remain dismissible, and remain available later? Do not add persistent tutorial clutter as the default solution.
- Automated inspection can identify hidden affordances; only actual user observation can establish whether people discover or understand them.

### 2. Interaction reliability

- Exercise all supported actions and input methods, including edges, padding, nested targets, rapid repeats, cancellations, and motion.
- Verify the correct action and correct entity exactly once. An animation or callback firing is not proof of the intended outcome.
- Check children, parents, siblings, overlays, gesture competition, and async state guards before attributing a missed action.
- See `references/interaction-protocol.md` for the reusable probe matrix.

### 3. Visual quality and hierarchy

- Compare rendered screens against actual theme tokens/components: typography scale, line height, baseline, icon weight, radius, elevation, spacing rhythm, alignment, and content density.
- Inspect visual balance, meaningful grouping, primary/secondary emphasis, consistent insets, and enough breathing room without excessive empty space.
- Check avatar/media fallback, clipping, ellipsis, badges, dividers, loading placeholders, image crop, long titles, and visual jumps as data arrives.
- Evaluate rest, press, focus, selected, disabled, loading, error, and success in supported themes. Do not treat low contrast as an aesthetic choice when it obscures function.
- Use restrained before/after proposals grounded in the current product. A screenshot comparison is required for an implemented visual change; do not approve golden changes blindly.

### 4. Accessibility and diverse input

- Inspect accessible name, role, value, selected/disabled/busy state, available actions, reading order, grouping, and redundant announcements.
- Exercise screen-reader activation, focus return, keyboard/switch navigation where supported, and alternatives to complex gestures.
- Test enlarged text and display settings without hiding essential information or disabling scaling; verify actual wrapping, scrolling, and reachability.
- Check text and meaningful non-text contrast using actual computed/composited colors; do not estimate ratios by eye. Use the research reference for thresholds and exceptions.
- Don't encode meaning only through color, location, sound, vibration, or motion. Feedback should remain understandable when these are unavailable.

### 5. Timing, responsiveness, and motion

- Separate input acknowledgment, gesture resolution, navigation/start, and completed result. Record each instead of saying the app is generically slow.
- Check double-action races, pending-state lockouts, slow responses, background/resume, and interruption during animation or submission.
- Test reduced-motion behavior, continuous movement, moving targets, and excessive bounce/zoom. Important controls must remain reachable and stable enough to operate.
- Measure performance on representative available targets in an appropriate build mode. Debug jank is not release-performance proof. Use project budgets or label new targets as proposals.

### 6. Content and localization

- Use plain, specific, consistent, action-oriented language; errors explain what happened and a realistic next step.
- Test supported languages, LTR/RTL, long names, script mixtures, emoji, pluralization, large counts, dates, times, and timezones where relevant.
- Mirror directional layout appropriately but do not blindly mirror logos, media controls, or content with an intrinsic direction.
- Preserve the user's language and terminology; avoid technical state names presented as user-facing explanations.

### 7. Recovery and trust

- Cancel/back must not accidentally commit, send, place a call, or discard unsaved work.
- Retry should be safe for the operation; validate deduplication and actual resulting state rather than merely disabling a button.
- Prefer undo where appropriate; use confirmation for consequential loss, not every routine action.
- Verify privacy-sensitive choices, correct identity, and truthful pending/delivered/saved states. Run these checks with controlled fixtures, not real contacts.

## D. Cross-Journey Pass

Walk actual supported end-to-end goals, adapting rather than assuming examples exist:

- Launch/onboard -> grant or deny permission -> reach first useful action.
- Browse/search -> inspect/select -> act -> return without lost context.
- Compose/edit -> submit -> slow/failure/retry -> confirm the real outcome.
- Open menu/sheet -> interact with keyboard or assistive input -> cancel/save -> restore focus.
- Change setting -> leave/relaunch -> verify effective state and dependent screens.
- Open media or live session -> interrupt/background -> resume/exit safely.
- Follow an external/deep-link entry -> complete or reject action -> recover navigation.

For each, cover normal, empty/error, back/cancel, and interrupted/restored variants where applicable. Use risk-based combinations for large matrices and list unsampled combinations; do not multiply every possible state into an unbounded test campaign.
