# Interaction Reliability and Microinteraction Protocol

Apply this protocol to buttons, rows, inputs, menus, sliders, media controls, overlays, custom canvases, and other interactive components. Orbit is **one worked scenario**, not the scope of the skill. Source-backed technical distinctions and platform target guidance are in `references/research.md`.

## 1. Record an Interaction Contract

For each interactive surface make a table:

| Surface/entity | Input and start state | Intended result | Must not happen | Visible/accessible alternative | Feedback and cancel path | Evidence |
|---|---|---|---|---|---|---|
| Actual discovered control | Actual supported action | Verified intent or proposed contract | Wrong entity, duplicate action, conflicting action | Actual control/action | Observable state | Source/test/runtime reference |

List primary tap/click, long press, double tap, drag/scroll, secondary click, keyboard activation, and accessibility actions **only where relevant**. Discover actual gesture meanings from code and product evidence. If meanings conflict, state the conflict; do not silently invent a new product interaction.

Separate:

- Visual/painted shape, including border, badge, label, and shadow.
- Layout bounds and ancestor bounds.
- Effective pointer hit region after clipping, transforms, overlays, and overlap arbitration.
- Accessible/semantic/focus bounds and supported actions.

A large bounding rectangle is not proof that every point inside activates the control. A circular visual can have a larger rectangular touch region; invisible enlargement must not steal input from a neighbor or an intentionally empty surface.

## 2. Make a Spatial Probe Map

Use the real rendered coordinate system, with logical dimensions, device-pixel ratio, viewport, orientation, and any scroll/transform offsets recorded.

1. Test center; cardinal and diagonal points just inside the **intended hit region**; visual edge; intended padded halo; and just outside the hit region.
2. For circles or irregular shapes, classify points by the actual intended shape. Bounding-box corners are not automatically required to activate a circular hit region. Keep visual shape and effective target contract distinct.
3. Test labels, badges, status dots, borders, shadows, and blank row padding. Decide whether each is part of the primary action, a separate action, or decorative; verify that contract.
4. Test boundaries shared with neighbors, nested controls, behind/above overlays, at viewport/safe-area edges, and where transformed content extends past ancestors.
5. For crowded components, probe the real overlap and adjacency boundaries. Never count the same shared area as independently reliable for two conflicting actions.
6. For intermittent or moving failures, run a declared finite coordinate grid or radial sweep over the affected region, plus selected animation/layout phases. Keep point generation deterministic and record the seed if randomized sampling is used.
7. Reset to a known equivalent state after navigation. Recompute coordinates after layout changes; do not tap stale screenshot coordinates. Keep a separate fixed-screen-coordinate experiment if movement under the pointer is the behavior under test.

For every attempt record: state/build/device, point/input sequence, intended target/action, actual target/action, timestamps if measured, and evidence. Retain misses, wrong targets, duplicate activations, and cancellations. Compute counts from records; no invented success rates. A finite sampled pass is not proof for all coordinates.

Acceptance is **correct target and correct action exactly once** for each expected-active probe, and no unintended action for expected-inactive probes. The expected outcome of empty background may be a legitimate screen action; assert the contract rather than forcing every empty point to do nothing.

## 3. Exercise Gesture Arbitration and Cancellation

For each relevant control, test a finite, declared set of:

- Ordinary single tap, slow tap, repeated independent taps, and tap while prior navigation/work is pending.
- Double tap within the actual recognizer's timing/spatial tolerances; two taps outside that window; taps on different neighboring entities. Do not hardcode a universal double-tap timeout.
- Long press just below/at/above the configured threshold, slight finger drift, movement that becomes a scroll/drag, release, and cancellation.
- Scroll beginning on a tappable child; tap during/after scroll deceleration; nested horizontal/vertical gestures if present.
- Pointer down followed by leaving/cancelling, app interruption, overlay appearance, removal/reorder of the entity, or widget disposal.
- Menu/sheet opening without accidentally selecting its first item or activating the background; dismissal without click-through.
- Keyboard and semantic activation of primary and secondary actions independently of pointer gesture recognition.

Log the **resolved action** separately from pointer-down/pressed feedback. Provisional feedback may begin before recognition, but must clear on cancellation. Do not move navigation or irreversible work into a down-event merely to make taps feel faster.

Where tap and double tap compete, measure the latency and exclusivity trade-off. If primary navigation feels delayed, consider an explicit secondary control or a distinct interaction region as a product proposal. Do not shorten thresholds indiscriminately or fire the primary action speculatively when it conflicts with the secondary action.

Prefer the framework's recognizers and cancellation behavior over unverified bespoke timers. Inspect actual installed versions and code before recommending an API change.

## 4. Make Actions Discoverable and Accessible

- Primary/common actions should have an obvious, easy input path.
- Long press, double tap, drag, or hover can supplement visible controls; they must not be the only route to important functionality.
- A hint can teach a shortcut, but it is not an alternative action. Offer a real button/menu/row/picker path where needed.
- Put explanations where users need them; make them dismissible and later discoverable. Do not put the only explanation behind the gesture it teaches.
- Test screen-reader focus and activation with the screen reader actually enabled. Its activation gestures are not equivalent to raw app double taps. Expose semantic actions rather than requiring pointer choreography.
- Avoid repeated announcements of decorative movement, presence changes, or countdowns. Keep meaningful state changes perceivable without flooding speech.
- Test pointer, keyboard, switch, and touch paths only on supported available targets; label unexecuted assistive-technology checks.

## 5. Feedback, Motion, and Timing

- Verify pressed/focused/selected/disabled/busy states and clear cancellation/reset behavior.
- Separate input acknowledgment, recognition, route/operation start, and final content readiness. Measure with one consistent clock and explicit start/end definitions.
- A press animation is not proof of navigation; navigation is not proof of network success. Record the boundary actually tested.
- Show truthful local pending/loading status for slow actions with safe recovery. Do not block local navigation on unrelated remote availability without an established product requirement.
- Haptics and sound are optional reinforcement, not the sole feedback. Respect system settings and quiet/reduced-motion modes.
- Test while entities animate, move, reorder, resize, load, or change identity. Check that the destination remains tied to the intended entity across pointer down/up and asynchronous completion.
- Performance thresholds are project acceptance criteria or explicit proposals, not invented universal UX laws. Report real sample counts and raw measurements before percentiles.

## 6. Diagnostic Candidates, Not Automatic Fixes

| Observed pattern | Competing explanations to investigate |
|---|---|
| Center works, edge fails | Small/irregular hit region, ancestor bounds, clip, overlapping sibling, decorative child interception |
| Same screen region fails for different controls | Invisible/stale overlay, system edge interaction, native view layering, viewport coordinate mismatch |
| Callback fires but destination never appears | State guard, stale entity, reentrancy lock, asynchronous error, routing/context disposal, disabled-state mismatch |
| First tap feels ignored, second works | Gesture ambiguity, startup/busy guard, late hit registration, animation timing, first-tap focus behavior |
| Long press opens both menu and chat | Premature down-event side effect, competing handlers, custom timer cancellation, duplicate listener |
| A setting changes twice or returns to old value | Row/control double handling, stale async response, persistence failure, optimistic rollback |
| Sending/retrying creates duplicates | Non-idempotent operation, duplicate handlers, race through busy guard; not merely a visual problem |
| Works with mouse, fails on phone/screen reader | Touch slop/arena differences, system gesture, semantics mismatch, input mode differences |

Trace evidence to the root cause. Don't automatically prescribe `HitTestBehavior.opaque`, no clipping, larger invisible targets, debounce, or a redesign.

## 7. Worked Scenarios for Later Audits

These are **test ideas**, not findings about the current app:

### A. Friends shown in Orbit circles

- The user reported that some areas of friend circles sometimes fail to open chat; this has not been independently reproduced by skill creation.
- Discover the actual avatar widget, parent layout/recognizers, badges/labels, action handlers, guards, and chat navigation path.
- Map sparse and dense layouts, all supported positions/rings, viewport edges, identity/status changes, and animated phases.
- Probe effective targets and neighbor gaps; verify destination identity and one route/action. Discover what screen/background long press and double tap actually do before asserting exclusivity.
- If dense targets cannot be made reliable together, propose spacing/layout adjustments or an optional alternative browsing mode. Do not replace Orbit or silently change gesture meanings.

### B. Form or message composer

- Focus a field, type with IME, grow multiline content, show/hide keyboard, and activate submit/send near its edge.
- Verify no keyboard occlusion, no submit during composition, correct destination/content, retained draft on failure, and safe retry/cancel.

### C. List row with nested action

- Tap text, whitespace, trailing icon, and the gap between targets; start scrolling from each.
- Verify row action and nested action are exclusive, stable after reorder, and accessible separately when they perform distinct tasks.

### D. Settings toggle inside a sheet

- Activate via label/row/control/keyboard/semantics, dismiss via available paths, then reopen.
- Verify one state transition, correct persisted value, no background action, and restored focus/context.

Apply the same evidence discipline to every other discovered interaction family.
