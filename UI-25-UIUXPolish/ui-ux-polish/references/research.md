# Research Basis: Whole-App UI/UX Polish

Researched 2026-09-11. These sources inform a **whole-interface** review: usability, navigation, component states, feedback, recovery, accessibility, appearance, and input reliability. They do not establish any defect in Mknoon. The component checklist, test matrices, severity scheme, and reporting workflow are this skill's engineering synthesis rather than quotations or a formal standard.

Use current project requirements and the installed framework version when running the skill. Recheck a source when a proposed change depends on version-sensitive behavior. Official guidance, informative standards explanations, and heuristic recommendations have different authority; do not collapse them into one compliance claim.

## 1. Broad Usability, Not Just Gestures

Nielsen's usability heuristics cover system-status visibility, familiar language, user control, consistency, error prevention, recognition rather than recall, efficiency, minimalism, error recovery, and help.[17]

**Audit implication:** inspect every discovered component and journey through these lenses. A beautiful screen may still hide its primary action, lose a draft, trap navigation, or communicate the wrong state. A heuristic observation is a hypothesis about usability until supported by actual interface evidence; representative user observation is needed to claim people understand or discover an interaction.

Apple's feedback guidance recommends accessible feedback, status near the relevant interface item, explanations when a command cannot run, and interruption proportional to the significance of the information.[18]

**Audit implication:** distinguish pressed feedback, pending work, completed work, and failed work. Don't add a modal confirmation or toast to every routine action. Verify the user can understand and recover from a failed action without relying solely on color, haptics, or sound.

Apple's modality guidance emphasizes a clear benefit for taking people out of context, obvious dismissal, protection against unsaved-content loss, and avoiding confusing stacks of modal views.[20]

**Audit implication:** test dialogs, sheets, popovers, and temporary full-screen experiences with back, cancel, keyboard, focus, unsaved data, and return-to-origin behavior—not just their opening screenshot.

## 2. Touch Targets: Preserve Units and Scope

Android's touch-target guidance recommends at least 48 by 48 dp and suggests 8 dp or more separation, while explicitly distinguishing the visible icon from its padded touch area and noting overlap problems in dense layouts.[8]

Apple's button guidance gives a general hit-region recommendation of at least 44 by 44 pt for easy selection.[6]

Flutter's accessibility-testing documentation provides Android and iOS target guidelines with 48 by 48 and 44 by 44 thresholds respectively, alongside label and text-contrast checks.[4]

**Working mobile polish baseline:** use Android 48 dp and iOS 44 pt as practical target goals for ordinary touch controls, represented through the project's density-independent framework layout and checked against actual rendered/hit geometry. Preserve larger established product targets. Do not describe these as one universal statutory minimum or treat screenshot pixels as native points/dp. Apple guidance can distinguish control defaults/minima in other contexts; recheck the applicable component/platform guidance rather than claiming every Apple control has a universal 44 pt rule.

WCAG 2.2 SC 2.5.8 is **Level AA**, with a 24 by 24 **CSS pixel** target criterion and exceptions for spacing, equivalent controls, inline text, user-agent controls, and essential presentation.[12]

WCAG SC 2.5.5 is **Level AAA**, with a 44 by 44 **CSS pixel** target criterion and its own equivalent, inline, user-agent, and essential exceptions.[11]

The 24 CSS-pixel spacing exception is geometric: a circle centered on an undersized target's bounding box must not intersect another target or an equivalent circle around another undersized target; the size test requires an axis-aligned solid square inside the actual target.[12]

**Audit implication:** a circular bounding box is not automatically a passing square target. Do not count overlap belonging to a different action as usable target area. Do not use WCAG's web minimum as the recommended size for primary native mobile controls, or label a native app legally noncompliant from this checklist. Apply formal conformance only with its full scope and exceptions established.

## 3. Gestures: Shortcuts, Not Hidden Requirements

Apple recommends familiar gesture meanings, responsive feedback, understandable unavailable states, and custom gestures that are discoverable, distinct, straightforward, and not the only way to perform an important action.[5]

**Audit implication:** keep a visible, accessible way to perform important long-press/double-tap/drag actions. A tooltip explaining a gesture is not equivalent functionality. Check button/menu alternatives and actual screen-reader/keyboard operation. Avoid teaching an action only after the user has already discovered the hidden gesture.

For custom gestures, measure recognizer latency, false activations, cancellation, and conflicts using the current implementation; the source guidance does not prescribe one universal double-tap delay or long-press threshold.

## 4. Flutter: Hit Testing and Gesture Recognition Are Distinct

Flutter dispatches pointer events along the hit-test path, while recognizers use the gesture arena to resolve competing gestures.[1]

The `GestureDetector` documentation explicitly states that changing `behavior` to `opaque` or `translucent` does not change parent-child gesture-arena competition; it also distinguishes provisional callbacks such as `onTapDown` from the winning gesture.[2]

The `onTap` callback occurs when the tap gesture wins; losing recognition instead leads to cancellation.[13]

`RenderBox.hitTest` evaluates positions in the box's local coordinate system and checks its bounds.[3]

`Transform.transformHitTests` controls transformation of hit coordinates; its documentation notes that transformed children still cannot receive events outside parent bounds in the described RenderBox path.[14]

**Audit implication:** inspect visual position, effective hit geometry, recognizer resolution, state guards, and the final destination separately. Enlarging paint, removing clipping, changing hit-test behavior, or moving an operation into a pointer-down handler are not universal fixes. Verify the actual ancestor hierarchy and SDK behavior. Pointer feedback must cleanly cancel; irreversible work should not be speculatively triggered just to make the UI feel faster.

## 5. Visual Readability and Accessibility

WCAG SC 1.4.3 specifies text contrast of at least 4.5:1, with a 3:1 threshold for qualifying large text and exceptions for incidental text and logotypes; its explanation identifies 18 pt regular or 14 pt bold as large text.[15]

WCAG SC 1.4.11 addresses meaningful non-text component/state indicators and graphics with a 3:1 contrast requirement against adjacent colors, with scope and exceptions; it does not require every decorative border or hover effect to meet that ratio.[16]

**Audit implication:** inspect actual foreground/background composition in light/dark, disabled, focused, selected, busy, and error states. Calculate contrast using tooling, not visual guesswork. Do not apply web point-size thresholds blindly to Flutter logical font sizes or treat every boundary as a required indicator. Use project/platform typography guidance and label the standard applied.

Apple's accessibility guidance addresses text enlargement, assistive input including keyboard and Switch Control, and reducing automatic/repetitive animation when Reduce Motion is active.[7]

**Audit implication:** exercise enlarged text/display, focus navigation, speech/semantic labels, reduced motion, and state announcements. Preserve access and information rather than hiding overflow or disabling scaling. Moving decorative content must not make controls hard to target or flood assistive output.

Flutter's Guideline API checks target size, labels, and text contrast; the documentation also describes platform assistive-technology testing.[4]

**Audit implication:** a passing Guideline API result is one evidence layer, not proof of non-overlapping hit regions, gesture reliability, comprehensive screen-reader access, or actual user understanding. Combine source, widget tests, rendered inspection, available native targets, and user observations where present.

## 6. Evidence Boundaries

- **Primary platform/framework guidance:** Apple, Android, Flutter. Apply to the relevant component, input, and installed version.
- **WCAG Understanding pages:** informative explanations of specified success criteria, not a complete conformance audit or legal opinion.
- **NN/g heuristics:** useful evaluation lenses, not deterministic acceptance tests or proof of user behavior.
- **Skill-specific synthesis:** the breadth-first inventory, component/scene/state ledger, spatial and temporal probes, severity rubric, and cross-journey preservation checks.
- **Project policy:** Mknoon graph navigation, test selection, device availability, and Multica lifecycle come from supplied project/user instructions, not these public sources. Read their current versions at execution time.
- **Research limitations:** some initial extraction responses were partial; key Apple gesture and W3C target guidance was recovered through another retrieval provider. A local browser attempt required remote-debugging consent and was not used as evidence. No app code audit, mobile test, screen-reader test, or usability study was performed while authoring this skill.

## Sources

[1] https://docs.flutter.dev/ui/interactivity/gestures
[2] https://api.flutter.dev/flutter/widgets/GestureDetector-class.html
[3] https://api.flutter.dev/flutter/rendering/RenderBox/hitTest.html
[4] https://docs.flutter.dev/ui/accessibility/accessibility-testing
[5] https://developer.apple.com/design/human-interface-guidelines/gestures
[6] https://developer.apple.com/design/human-interface-guidelines/buttons
[7] https://developer.apple.com/design/human-interface-guidelines/accessibility
[8] https://support.google.com/accessibility/android/answer/7101858?hl=en
[11] https://www.w3.org/WAI/WCAG22/Understanding/target-size-enhanced.html
[12] https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html
[13] https://api.flutter.dev/flutter/widgets/GestureDetector/onTap.html
[14] https://api.flutter.dev/flutter/widgets/Transform/transformHitTests.html
[15] https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html
[16] https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html
[17] https://www.nngroup.com/articles/ten-usability-heuristics
[18] https://developer.apple.com/design/human-interface-guidelines/feedback
[20] https://developer.apple.com/design/human-interface-guidelines/modality
