# Lean Audit Workflow And Output

Read this during review Steps 2, 4, 5, and 6.

## Bounded Audit Topology

Default to one fresh factual/counterexample verifier plus main-agent synthesis.
This preserves an independent angle without recreating a review committee.

Add specialists only on a real trigger:

- **Domain specialist:** uncertain dependency, provider, platform, protocol,
  security, or external technical bet.
- **Boundary/reversibility specialist:** migration, one-way/destructive data,
  rollback, compatibility, process/runtime, native/OS, browser, device,
  hardware, distributed system, or external-environment proof.

Use at most three audit workers total: the core verifier plus the two
conditional specialists. If agents are unavailable, run the same passes
sequentially. Separate the fresh counterexample pass from synthesis so the
planner's framing does not silently become the reviewer's conclusion.

Common worker prompt:

```text
Audit this existing TDD plan before execution. Work from current source, tests,
manifests, and gates; the plan and graph are claims/navigation, not ground
truth. Try to construct a wrong implementation that still passes the Test
Contract. Verify only load-bearing facts and plausible bypass sites. Return
structured findings with plan row/section, current file:line or durable-symbol
evidence, consequence, and smallest sufficient plan delta. Do not edit files,
refresh graphs, execute tests/gates/benchmarks/environment campaigns, or write
a fix-list.
```

When a technical bet cannot be verified locally, a domain specialist may use
authoritative version-matched primary documentation if browsing is available
and permitted. If it remains ambiguous, return `unresolved`; do not guess.

## Finding Schema

Use this internal shape:

```text
FINDING = {
  plan_target,                 # section or Test Contract row
  claim,
  evidence_state: confirmed | refuted | unresolved,
  counterexample,
  evidence,
  severity: blocker | plan-fix | note,
  smallest_sufficient_delta
}
```

Severity meanings:

- `blocker`: core direction, required boundary, compatibility/release decision,
  or load-bearing evidence is unsafe/unresolved and requires replanning or a
  user decision.
- `plan-fix`: a bounded correction is known and must land before execution.
- `note`: useful tightening that does not make execution unsafe.

The main agent deduplicates findings, resolves contradictions, applies all five
lenses, runs the evergreen sweep, and self-verifies every blocker and plan-fix
linchpin in current evidence.

## Verdict Contract

- `ready`: begin the declared execution or verification as written; only
  optional notes remain.
- `plan-fixes-required`: the direction is viable, but exact plan corrections
  must land first.
- `not-ready`: a blocker remains, including a refuted/unresolved core bet,
  absent real-boundary strategy, incompatible rollback/release contract,
  required user decision, or need to replan.

State the core bet as `confirmed`, `refuted`, `unresolved`, or `N/A`.

Also state one disposition: `execute`, `apply-plan-fixes`,
`verify-and-close-stale`, or `replan`.

Map the synthesis deterministically:

- any self-verified `blocker` finding or `block` lens -> `not-ready`;
- otherwise any `plan-fix` finding or `tighten` lens ->
  `plan-fixes-required`;
- only `clear`/`N/A` lenses and optional notes -> `ready`.

Use `execute` with `ready`, `apply-plan-fixes` with
`plan-fixes-required`, `verify-and-close-stale` for an obsolete implementation
plan, and `replan` for other `not-ready` results.

For stale/already-covered and acceptance-only plans, evaluate the verification
contract rather than demanding implementation work. If review proves an
implementation-ready plan obsolete, use `not-ready` plus
`verify-and-close-stale`; obsolete production steps are unsafe. If the plan was
already classified correctly, `ready` means its declared verification may run.
In that case `execute` means execute verification only, never production edits.

## Default Chat Report

Present findings before background. Omit empty sections.

```markdown
# Review: <plan>

Verdict: **<ready | plan-fixes-required | not-ready>**
Plan classification: <classification>; core bet: <confirmed | refuted | unresolved | N/A>.
Disposition: <execute | apply-plan-fixes | verify-and-close-stale | replan>.

## Evidence Grounding / Limitations

- Repository revision/state: <revision and material dirty state>.
- Graphify: <identity/query/gaps, or N/A plus targeted-source fallback>.
- Live commands: <not run by default, or separately authorized evidence and artifacts>.

## Required Before Execution

1. **[<blocker | plan-fix>] <short finding>.**
   - Plan target: <section / Test Contract row>.
   - Evidence: `<file:line or durable symbol>` - <fact>.
   - Counterexample/consequence: <how the wrong plan can pass or fail>.
   - Smallest sufficient delta: <exact plan correction>.

## Non-Blocking Tightenings

- <note, only when useful>.

## What Remains Sound

- <verified design worth preserving>.

## Lens Summary

- L1 Evidence: <clear | tighten | block | N/A>.
- L2 Causality: <clear | tighten | block | N/A>.
- L3 Bypasses/scope: <clear | tighten | block | N/A>.
- L4 Commands/gates: <clear | tighten | block | N/A>.
- L5 Boundary/reversibility: <clear | tighten | block | N/A>.

## Blind-Spot Sweep

- Hits: <B-N findings, or none>.
- Remaining classes: <clear/N/A summary with noteworthy reasons>.

## User Decisions

- <only decisions that block or materially alter the contract>.
```

Do not include numeric scores by default. For a concise report, list blind-spot
hits and summarize the clear/N/A classes in one line. Emit a full B-1 through
B-10 table only for a requested thorough report or fix-list.

## Fix-List Template

Write a fix-list only when explicitly requested. Unless the repository defines
another convention, place it beside the plan as
`<plan-stem>-review-fixlist.md`.

```markdown
# Review Fix-List - <Plan Identifier>

Plan: `<plan path>`
Verdict: <plan-fixes-required | not-ready>
Core bet: <confirmed | refuted | unresolved | N/A>
Disposition: <apply-plan-fixes | verify-and-close-stale | replan>

## Verified Facts

- <claim> - `<file:line or durable symbol>`.

## Required Plan Deltas

1. **R1 - <theme>**
   - Target: <Test Contract row / plan section>.
   - Evidence: `<file:line or durable symbol>` - <fact>.
   - Change: <exact edit, without re-deriving>.
   - Completion check: <what the revised plan must contain>.

## Optional Tightenings

- <non-blocking item, if any>.

## User Decisions

- <locked decision or unresolved blocker, if any>.

## Apply Order

1. <core/boundary/compatibility corrections>
2. <causal-test and gate corrections>
3. <scope and clarity tightenings>
```

Every required item needs current evidence and the smallest sufficient delta.
Reference Test Contract row IDs when available; use plan line numbers as
support, not as the only durable locator.

## User-Owned Decisions

Report the audit first, then ask only choices source cannot answer:

- rollback/release strategy for a genuinely one-way change;
- product-owned behavior, compatibility promise, or de-scope;
- a quantitative threshold when several risk tolerances are valid.

Do not ask for a number for ordinary binary behavior. Do not ask the user to
choose obvious factual corrections or the output format; default output is the
read-only chat report.

## Read-Only Boundary

- Do not edit the plan, Graphify output, memory, indexes, or review files by
  default.
- Statically inspect command definitions, selectors, discovery, registration,
  source, tests, manifests, and gates. Do not execute tests, gates, benchmarks,
  builds, Graphify builds/updates, or environment scenarios unless live proof
  is explicitly requested or that diagnostic execution is separately
  authorized.
- When live proof is authorized, report it separately from source-review
  evidence and disclose caches, snapshots, reports, artifacts, external state,
  or other side effects it touched.
- Write a fix-list or revise the plan only with explicit authorization.
- After a revise-in-place request, patch only verified deltas and rerun all five
  lenses plus every triggered blind-spot class.
