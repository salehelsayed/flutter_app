---
name: ui-ux-polish
description: "Use when auditing UI/UX polish across an entire app."
version: 0.1.1
author: Mknoon team, Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [ux, ui, usability, accessibility, visual-design, interaction, Flutter, audit]
---

# UI/UX Polish

Audit how an app looks, feels, communicates, and responds across **all discovered components and user journeys**. Find small details that cause hesitation, missed actions, mistakes, lost context, or inaccessible workflows; connect each finding to evidence and a testable improvement. This is not a screenshot-only redesign or a gesture-only audit.

## When to Use

- Reviewing the whole app for UI/UX polish, usability friction, visual consistency, and accessibility.
- Examining navigation, controls, forms, lists, messaging, media, settings, dialogs, feedback, and unusual/custom components.
- Investigating details such as unreliable taps, hidden actions, awkward keyboard behavior, confusing states, or inconsistent spacing.
- Verifying an approved polish batch without changing the product's identity.

An example named by the user is a motivating case, **not a scope restriction**. Orbit, avatars, and gestures are examples alongside other component families. Narrow scope only when the user explicitly requests it.

Do not use as a substitute for a formal accessibility certification, representative user study, security assessment, or release certification.

## Prerequisites and Modes

- Discover the actual repository/app, project instructions, supported platforms, design system, test tooling, and live tool inventory. Do not invent paths, commands, widget names, or APIs.
- **Audit mode is the default:** read source, execute existing safe tests, explore the app with test data, and write findings. Do not change production code, dependencies, product behavior, or repository test suites.
- **Fix mode requires explicit permission:** implement agreed findings with focused regression tests and verify the affected journeys. Permission to create this skill is not permission to run an audit or change the app.
- Separate missing source, missing runtime, missing authentication, and unavailable device evidence. Continue safe independent work and state the limits.
- Use sandbox/test accounts. Do not message real contacts, place real calls, upload private media, delete user data, or change privacy settings without specific authorization. Stop at login walls; never inspect credentials.

## How to Run

The user can ask: **Use ui-ux-polish to audit the whole app. Include every discovered component family and journey; report findings without changing code.**

For a later approved batch: **Use ui-ux-polish in fix mode for these finding IDs, preserving existing design and behavior elsewhere.**

Use Hermes `terminal` for real commands, `read_file`/`search_files` for evidence, and `write_file`/`patch` for authorized artifacts/edits. Use the discovered native harness for mobile. Browser automation is suitable for web, not proof of native mobile touch or assistive-technology behavior.

## Procedure

### 1. Establish scope, baseline, and tracking

1. Read project instructions. Discover branch, revision, dirty state, app/build identity, technology stack, and test-account constraints. For Flutter, load `references/flutter-mknoon.md` now, before any source inventory or test selection, and apply its indexed-navigation prerequisites. Keep pre-existing edits intact.
2. Where Multica is required, list current issues/projects before substantive work, reuse the matching active issue, and read back the exact issue after each write. Never call tracking successful if unavailable. See the Mknoon adapter when applicable.
3. Record mode, user goals, platforms actually available, exclusions, and artifact directory. Use a project-approved ignored directory; otherwise write under the active profile's cache. Do not put private screenshots in tracked files.
4. Create a task list. A whole-app request begins with a breadth pass, not an open-ended investigation of the first example.

**Complete when:** the scope and baseline are explicit and safe runtime access is established or its absence is recorded.

### 2. Inventory the whole interface before prioritizing

1. Reconcile current route/navigation definitions, shared components/theme tokens, feature entry points, and the live interface. Include conditional, secondary, empty, error, and permission-gated surfaces; runtime-hidden does not mean absent.
2. Load `references/component-checklist.md`. For every discovered screen/surface, list its user goal, component instances, implementation family, supported actions, significant states, entry/exit paths, and existing evidence.
3. Map reusable families to consuming screens. Include custom-painted, overlaid, native, and embedded controls; a route list alone is incomplete.
4. Give every discovered component family and journey a coverage row and a checklist item. Repeated identical instances may share core tests, but inspect contextual differences: constraints, parent recognizers, theme, disabled state, data, scroll containers, and overlays. Record exactly which instances were sampled.
5. A component type in the reference is a discovery prompt, not proof that the app contains it. Add unlisted components found in the app. Absence claims need source/runtime evidence; otherwise use `not discovered`.

**Complete when:** all discovered surfaces map to a family/journey and each is scheduled, explicitly deferred, or out of scope with a reason. Do not equate an inventory with an audit pass.

### 3. Define the experience contract

For each family/journey record:

- What the user sees, understands, tries, and expects to happen.
- Visible affordance and accessible name/role/state; pointer target and semantic/focus target.
- Primary action, secondary actions, keyboard/assistive equivalents, feedback, cancellation, recovery, and return destination.
- Resting, pressed, focused, selected, disabled, pending, successful, empty, failed, interrupted, and restored states **where applicable**.
- Layout/data variants: small viewport, enlarged text/display, supported LTR/RTL, short/long content, light/dark themes, keyboard/safe areas, reduced motion, and realistic density.

Separate **verified current behavior**, **documented intent**, **user-reported symptoms**, and **proposed changes**. Do not invent what an existing long press, toggle, or menu item does.

**Complete when:** expected outcomes can be asserted without guessing product semantics.

### 4. Execute breadth-first, then deepen by risk

1. Walk every in-scope discovered family/journey once across its meaningful states. Assess clarity, consistency, reachability, predictability, reversibility, accessibility, and appearance using the checklist.
2. For interactions, load `references/interaction-protocol.md`. Test target edges and neighbors, timing, cancellation, repeated input, changing state, and non-touch alternatives, not just center clicks.
3. For each journey include success, back/cancel, failure/retry, and interruption/resume where meaningful. Test cross-screen continuity: drafts, selection, scroll position, focus, pending work, and destination identity.
4. Capture screenshots of actual rendered states for visual review, and input/result evidence for behavior. Inspect images with available vision tools; inspect browser screenshots directly when the browser tool attaches them.
5. Deepen high-impact findings after breadth coverage: blocked common tasks, accidental/irreversible actions, accessibility barriers, confusing state, then visual refinements. A serious finding may interrupt breadth work, but resume the remaining inventory afterward.
6. For Flutter, load `references/flutter-mknoon.md` before source investigation or selecting tests. Other stacks use their actual framework and project gates; do not force Flutter tooling on them.
7. When runtime is unavailable, continue a source-backed audit but label every runtime-dependent check `not run` or `blocked`. Never fabricate repros, screenshots, timings, or user observations.

**Complete when:** every coverage row has an honest status and evidence appropriate to the claim, not just a recommendation.

### 5. Diagnose and prioritize improvements

1. Trace each observed defect from input/layout/state through handler, validation/guard, navigation or service boundary, to the visible result. A missed action may be gesture recognition, state gating, async delay, or routing—not necessarily a small target.
2. Separate `runtime-confirmed`, `source-confirmed`, `hypothesis`, and `design recommendation`. A screenshot confirms visible geometry, not touch reliability; a source match does not prove runtime behavior.
3. Group shared causes but retain every affected surface and repro. Check sibling call paths before proposing a local patch.
4. Severity: **critical** for privacy exposure, wrong-recipient actions, or irreversible unintended loss; **high** for blocked core tasks or assistive-access barriers; **medium** for recoverable recurring friction; **low** for cosmetic inconsistency. Explain frequency, reach, confidence, and recovery cost separately—no invented numeric UX score.
5. Recommend the smallest coherent improvement using existing tokens, components, platform conventions, and product language. Preserve professional visual identity. Treat redesigned navigation, changed gesture meanings, new onboarding, and alternative layouts as product proposals requiring approval.
6. Define acceptance checks and preservation sentinels before fixing. Distinguish must-fix defects, usability improvements, and subjective visual options.

**Complete when:** each actionable finding has reproducible evidence or a clearly bounded hypothesis, impact, a proposed remedy, and a verification method.

### 6. Fix only in authorized mode

1. Confirm the approved finding IDs. Add a focused failing regression test before the production change when practical; disclose boundaries that cannot be reproduced automatically.
2. Match existing code patterns; edit only the necessary production/test/docs files. Avoid bulk reformatting or replacing distinctive components merely to simplify testing.
3. Verify original repro, nearby controls, alternative inputs, cancellation, and dependent journeys. Apply project impact analysis and test selection, then inspect actual before/after rendering.
4. Keep first-attempt failures visible. Restore temporary debug overlays/settings and isolate or remove debug-only instrumentation. Do not commit, push, or deploy unless asked.

**Complete when:** approved fixes have actual execution evidence, preservation checks pass, and any remaining gaps are explicit.

### 7. Deliver and close honestly

Use `templates/audit-report.md`. Deliver a concise executive summary plus the complete coverage ledger, interaction/state observations, prioritized findings, artifact links, source/test anchors, and exact executed commands/results.

- Compute counts from the ledger with `execute_code` or `terminal`; distinguish discovered, inspected, tested, failed, deferred, blocked, and not-applicable rows.
- A sampled pass applies only to the named samples/configurations. Do not claim exhaustive combinations, user-study validation, or zero defects from a clean automated test run.
- An audit can be delivered with transparent gaps; the product is not thereby certified or fixed.
- Update the authoritative issue with material evidence and the actual deliverable. Unresolved required dependencies remain blocked; completion of an audit does not close unimplemented fixes.

## Pitfalls

- Spending the whole run on Orbit, gestures, or the first reported bug while missing other components.
- Judging only resting screenshots; ignoring keyboard, focus, animation, failure, and restoration states.
- Treating a larger hitbox, tooltip, haptic, animation, or debounce as a universal fix.
- Replacing visible controls with hidden shortcuts or making help discoverable only through the gesture it explains.
- Calling aesthetic preferences defects without showing a user consequence or design-system inconsistency.
- Treating CSS pixels, Flutter logical pixels, native points/dp, and screenshot/device pixels as interchangeable.
- Claiming accessibility from semantic bounds alone, or claiming user discoverability without observing users.
- Escalating all feedback to alerts, all ambiguity to confirmation dialogs, or all visual polish to a redesign.

## References and Verification

- `references/component-checklist.md`: all-component and cross-journey inspection matrix.
- `references/interaction-protocol.md`: hit geometry, gestures, timing, feedback, and input alternatives; Orbit is one example.
- `references/flutter-mknoon.md`: framework-specific diagnostic candidates and repository-aware gates.
- `references/research.md`: cited design/engineering guidance, thresholds, caveats, and research provenance.
- `templates/audit-report.md`: coverage, findings, evidence, and honest closure.

A run succeeds when the requested scope is accounted for, conclusions match their evidence, and the report exists. Fix-mode success additionally requires real targeted tests and runtime checks for the approved changes. Skill installation/validation alone proves neither an app audit nor an app fix.
