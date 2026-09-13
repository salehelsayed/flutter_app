# UI/UX Polish Audit — <app / scope>

> Template: fill placeholders with verified evidence. Example categories and statuses are not findings. Audit completion does not mean every issue has been fixed or the product is certified.

## Executive Summary

- Mode: <audit / authorized fix IDs>
- Requested scope: <whole app unless explicitly narrowed>
- App/build/revision and dirty baseline: <verified values>
- Runtime and test targets: <exact discovered IDs and configurations>
- Design-system baseline: <actual tokens/components/reference>
- Overall result: <delivered with coverage limits / blocked / verified fix batch>
- Highest-impact findings: <concise user consequences>
- Tracking: <read-back-verified issue handle, or unavailable>

## Coverage and Counts

Counts are computed from the detailed ledger, not estimated. Define whether counting families, surfaces, cases, or findings; don't mix denominators.

| Coverage dimension | Discovered/in scope | Inspected source | Executed runtime | Failed | Blocked/deferred | Not applicable |
|---|---|---|---|---|---|---|
| Component families | | | | | | |
| User journeys | | | | | | |
| Declared test cases | | | | | | |

Columns may overlap (a failed runtime case is still executed); state the counting rule. Report unique finding counts separately from affected components and failing attempts.

### Component Ledger

| ID | Family and actual component | Consuming surfaces | Relevant actions/states | Context variants | Samples inspected/tested | Status | Evidence / reason |
|---|---|---|---|---|---|---|---|
| <ID> | <verified> | <actual routes/overlays> | <supported only> | <layout/input/data/theme> | <specific instances> | <honest status> | <artifact/source/test> |

### Journey Ledger

| ID | User goal and start -> result | Actual surfaces/components | Success | Cancel/back | Failure/retry | Interrupt/restore | Evidence / gaps |
|---|---|---|---|---|---|---|---|
| <ID> | <actual supported journey> | <component IDs> | | | | | |

### Exclusions and Sampling

- Not discovered vs verified absent: <evidence or unknown>
- Unavailable target legs: <policy-specific N/A, not invented device failures>
- Supported available targets not tested: <actual reason and remaining check>
- Runtime unavailable: <all affected claims stay source-only/not run>
- Sampled combinations and untested combinations: <explicit list/criteria>
- Remaining breadth work: <no silent omission of non-example components>

## Prioritized Findings

| ID | User consequence | Severity | Evidence class | Affected surfaces | Recommendation | Verification / issue |
|---|---|---|---|---|---|---|
| <ID> | <what users cannot do, misunderstand, or risk> | <critical/high/medium/low> | <runtime-confirmed/source-confirmed/hypothesis/design recommendation> | <specific> | <smallest coherent change> | <test/handle> |

### Finding <ID>: <outcome-based title>

- **Category:** <interaction / navigation / visual / accessibility / content / state / recovery / performance>
- **User impact:** <goal blocked or friction; frequency/reach if actually known; recovery cost>
- **Expected behavior and its authority:** <current product contract / documented intent / proposal>
- **Observed behavior:** <what actually happened; no invented repro>
- **Evidence class and confidence:** <including limits>
- **Baseline/preconditions:** <build, target, viewport, text/display scale, locale/direction, theme, state, test data>
- **Exact reproduction:** <ordered inputs, coordinates/timing when relevant, reset procedure>
- **Attempts/results:** <successes/misses/wrong target/duplicates/cancellations; raw artifact link>
- **Visual evidence:** <real before/state screenshots or not captured>
- **Behavioral evidence:** <recording/log/assertion and tested boundary>
- **Current source and tests:** <path:line, exact symbol and assertion; hypothesis if untraced>
- **Cause and alternatives considered:** <evidence-based distinction>
- **Affected siblings/contexts:** <actual consumers; not assumed all instances>
- **Proposed improvement:** <minimal remedy and any product decision required>
- **Acceptance checks:** <observable outcome and actual execution layer>
- **Preservation checks:** <neighbor controls, inputs, state, back/cancel, identity, accessible alternative>
- **Fix authorization/status:** <not authorized / approved / implemented / verified / incomplete>

## Interaction and State Evidence

| Case ID | Component/entity/state | Input method | Point/sequence and clock units | Expected action/target | Actual action/target | Count/latency if measured | Evidence |
|---|---|---|---|---|---|---|---|
| <ID> | <real values> | <touch/keyboard/semantics/etc.> | <coordinate space and conditions> | | | <no fabricated metrics> | |

## Execution Receipt

| Exact command/harness action | Build/revision/target | Boundary asserted | First result | Diagnostic rerun | Artifact |
|---|---|---|---|---|---|
| <executed command only> | <verified> | <what it proves> | <actual> | <if any> | <existing path> |

- Required checks not executed: <check, reason, consequence>
- Automated checks vs actual human usability observations: <keep separate>
- Temporary debug/settings cleanup: <verified or outstanding>
- Actual changed files in fix mode: <scope and tests>

## Recommendations and Next Decisions

1. Must-fix defects: <evidence-backed>
2. Usability improvements: <proposals, rationale, acceptance>
3. Visual refinements: <design-system inconsistency vs subjective option>
4. Product decisions requiring approval: <behavior/navigation/gesture/onboarding changes>
5. Remaining validation: <specific available boundaries, not unspecified future hardware>

## Closure

- Every discovered in-scope component family/journey accounted for: <yes/no with ledger>
- Requested audit artifact delivered: <path>
- Approved fixes actually verified: <IDs or not in scope>
- Product-wide reliability/accessibility/release claim: **not implied by this audit**
- Multica exact issue/comments read back: <handle and outcome, or tracking blocked>

## Sources and Evidence Boundaries

Link applicable primary guidance from the skill's `references/research.md` plus current source, test, and runtime artifacts. Standards support evaluation criteria; they do not prove this app violates or satisfies them.
