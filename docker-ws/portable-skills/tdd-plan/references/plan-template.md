# Compact TDD Plan Skeleton

Read this before emitting a plan. Replace every placeholder. Core sections are
mandatory; conditional sections appear only when triggered. Save at the Step 0
resolved path, normally `<repository-root>/docs/tdd/`.

````markdown
# <Stable identifier or date-slug stem> - <Title>

Status: <planning-draft | evidence-gated | execution-ready>
Type: <Bug | Feature Improvement | New Feature | Modification | Migration | Reliability>
Source intent: <issue/spec path, identifier, or free-text intent>
Classification: <implementation-ready | evidence-gated | acceptance-only | stale-already-covered | prerequisite-blocked>
Highest proof boundary: <repository-specific test level or boundary>

## Problem And Evidence

- Behavior to improve: <observable behavior and affected user/system>.
- Impact: <why it matters>.
- Confirmed cause/current gap: `<symbol>` at `<file:line>` - <mechanism>;
  or `N/A - source proves stale/already-covered`.
- Existing coverage: `<test/gate>` proves <behavior>.
- Missing coverage: <causal gap, or N/A with source evidence>.
- Refuted findings: <finding plus contradictory evidence, or N/A>.
- Unresolved findings: <thin evidence plus required proof, or N/A>.
- Affected production, test, manifest, and gate files: <small concrete list>.

## Project Convention Snapshot

- Instructions consulted: <files>.
- Repository root / revision / working-tree state: <root, revision, summary>.
- Stack / package scope: <language, framework, module, working directory>.
- Test levels and discovery: <actual project names and rules>.
- Focused selector: `<literal command shape>`.
- Affected-suite gate: `<literal command>`.
- Broad-suite owner/cadence: <command plus per-change/CI/batch/release owner>.
- Static-quality commands: <literal commands>.
- Boundary fixtures: <available fixtures and policy>.
- Plan path / identifier rule: <rule used>.
- Unresolved conventions: <items or none>.

## Graph Grounding Snapshot

- Graph / freshness: <identity/freshness, or N/A - unauthorized/unavailable>.
- Query or tool operation: <exact operation, or N/A plus source fallback>.
- Exact anchors: <node/symbol/id -> source file, or N/A>.
- Surfaced production, test, and gate files: <graph or targeted-source files>.
- Graph gaps: <items, not-used reason, or none>.
- Verification rule: graph anchors are navigation; current source and commands
  remain authoritative.

## Scope Contract And Guard

In scope:
- <concrete seam or behavior>.

Must preserve:
- <adjacent behavior> -> `<named sentinel>`; or `N/A - <reason>`.

Hard `Do not`:
- Do not <scope boundary>.

Deferred / accepted difference:
- <item> -> owner <issue/work>, because <reason>; or N/A.

Dependencies:
- <upstream/downstream contract>; or N/A.

## Test Contract

Use zero empty cells. Write `N/A - <reason>` when a field truly does not apply.

| Case | Behavior / invariant | Named test or proof | Level / fixture | Baseline -> GREEN | Counterfactual / mutation | Command or proof procedure / discovery / registration |
|---|---|---|---|---|---|---|
| TC-01 | <causal behavior> | `<file-or-target>::<test-or-scenario>` | <actual level / fake-or-real fixture> | <real baseline failure> -> <GREEN observable> | alter/revert <seam> -> TC-01 red | `<literal focused command or reproducible procedure>`; <verified discovery/registration or N/A> |

### Test Notes

Include only when needed:

- <case>: setup <non-obvious fixture>; discriminator <A present and B absent>;
  fault/compatibility direction <details>.

## Implementation Steps

1. Snapshot repository state when version-controlled; add causal tests and
   sentinels before production edits, or run source-backed verification for
   stale/acceptance-only work.
2. Change `<symbol/seam>` in `<file>` to <specific behavior>; or
   `N/A - no production edit required`. Stop-if: <replan condition>.
3. Implement the exact discovery/registration changes in the Test Contract.
4. Run focused GREEN, preservation, affected-suite, static-quality, and
   conditional boundary proof in the stated order.

## Risks And Blind Spots

- <risk> -> guarded by <case/test>.
- Lifecycle / derived-state durability: <case or N/A with reason>.
- Bypassing callers / sibling consistency: <case or N/A with reason>.
- Destructive effects / atomicity / concurrency: <case or N/A with reason>.
- Invariant re-verification under new transitions: <case or N/A with reason>.
- Compatibility / rollback / fallback: <case or N/A with reason>.

## Gate Strategy

- Focused causal proof: <literal commands>.
- Preservation: <exact sentinels and commands>.
- Affected suite/lane/package: <literal command and semantic success>.
- Broad suite: <per-plan command, or named CI/batch/release owner and cadence>.
- Static/build/package checks: <literal commands>.
- Tests outside ordinary discovery: <direct command and registration, or N/A>.

## Acceptance Commands

Include only applicable commands, each with its working directory and semantic
outcome. A stale/already-covered or acceptance-only plan uses exact verification
commands and states why no causal RED exists.

```bash
# Repository-state snapshot when applicable
<literal status command>

# Causal baseline before production edits; expect failure for the documented reason
<literal focused command>

# Focused GREEN; expect intended test selected, success exit, and no failures
<literal focused command>

# Representative counterfactual after GREEN; safely apply the scoped mutation,
# expect the named test to re-red, restore only that executor-owned mutation,
# then rerun GREEN
<literal safe mutation/revert procedure and focused commands>

# Preservation and affected suite; expect intended targets selected and no failures
<literal commands>

# Conditional migration/compatibility/boundary/benchmark proof
<literal discovery and execution commands>

# Repository-required static/build/package hygiene
<literal commands>
```

## Execution Interpretation And Done Criteria

- Expected causal baseline: <test and reason, or source-backed N/A>.
- GREEN sentinel: <test and preserved behavior>.
- Pre-existing repository state / known failure: <baseline or none>.
- Environment limitation: <interpretation under repository policy or none>.
- Scope drift: <change/failure that blocks completion>.

- [ ] Every behavior has a named causal test or justified proof.
- [ ] Causal baseline, focused GREEN, and representative counterfactual re-red
      are recorded during execution, or a stale/acceptance-only disposition is
      source-proven.
- [ ] Preservation, affected-suite, and any per-plan required broader gates
      pass; deferred aggregate gates have a named owner/cadence and are recorded
      at that later closure.
- [ ] Discovery/registration is implemented and verified.
- [ ] Conditional migration, compatibility, quantitative, or real-boundary
      proof passes when applicable.
- [ ] Repository-required quality checks pass with no new relevant issues.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First expected causal command: `<command>`; or `N/A - <source-backed reason>`.
- Preservation command: `<command>`.
- Registration changes: <rows/actions or none>.
- Migration/compatibility: <versions/directions/tests, or none>.
- Boundary closure: <lowest sufficient level or exact real-boundary proof>.
- Unresolved evidence: <items or none>.
````

## Conditional: Boundary Proof Profile

Add only when the Test Contract includes a real environment, external system,
compatibility matrix, process/runtime, native/OS, device/hardware, or justified
manual proof.

```markdown
## Boundary Proof Profile

- Boundary being proven: <real behavior lower levels cannot prove>.
- Availability policy / live targets: <repository policy plus discovered fixtures>.
- Required setup: <versions, identities, services, targets, data, environment>.
- Automation: <harness/registration, or infeasibility/disproportionality under policy>.
- Discovery: <literal command, or N/A for justified manual proof> -> <selection>.
- Closure: <literal command or reproducible procedure> -> <semantic outcome>.
- Evidence capture: <artifact/log/report and retention location>.
- Deferred boundary work: <owner/reason, or none>.
```

## Conditional: Migration Or Compatibility Profile

Add only when stored data, schema, file/API/wire format, build artifact, or
version interoperability changes.

```markdown
## Migration Or Compatibility Profile

- Supported starting states / versions: <fixtures>.
- Target state / version: <expected result>.
- Directions and round trips: <old->new, new restart, coexistence, downgrade>.
- Atomicity / partial failure / concurrency: <cases>.
- Idempotency / replay: <case>.
- Rollback, recovery, backup, or one-way release strategy: <contract/owner>.
- Real engine/codec/service fixture: <setup>.
```

## Conditional: Quantitative Profile

Add only for a genuinely quantitative goal.

```markdown
## Quantitative Profile

- Metric and user-visible meaning: <metric>.
- Comparable baseline: <command, environment, data, sample method>.
- Decision threshold: <repository- or user-owned threshold>.
- Variance controls: <warmup, repetitions, percentile/statistic, noise policy>.
- Regression gate: <literal standing command and registration>.
```

Append reviewer findings or execution results only after those phases run.
