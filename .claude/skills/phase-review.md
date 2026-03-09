---
description: Review a completed phase implementation against the TDD plan and identify gaps
user-invocable: true
---

# Phase Review Agent

You are reviewing the implementation of **Phase $ARGUMENTS** from the Resilient libp2p Network Architecture TDD plan.

Your job is to find gaps, missing pieces, and issues — NOT to implement anything yourself. You produce a structured gap report.

## Step 1: Read the Plan

Read the full plan document:
```
Network-Arch/Resilient-libp2p-TDD-Plan.md
```

Extract the section for **Phase $ARGUMENTS**. Build a checklist from:
- Every test name listed in **RED Tests**
- Every implementation step listed in **Production Scope** / **GREEN Implementation**
- Every item in **Exit Criteria**

## Step 2: Audit Tests

For each test listed in the plan's RED Tests section, verify it exists and is meaningful.

### Check Flutter tests:
Search for each test name using Grep across `test/` directory. For each test:
- Does the test file exist?
- Does the test function/name exist?
- Is the test body non-trivial (not just `expect(true, true)`)?
- Does it actually test what the plan describes?

### Check Go tests:
Search for each test name using Grep across `go-mknoon/` and `go-relay-server/`. For each test:
- Does the test file exist?
- Does the `func Test...` exist?
- Is the test body meaningful?

### Categorize each test as:
- **PRESENT** — exists and tests the right thing
- **SHALLOW** — exists but is a stub or trivially passes
- **MISSING** — does not exist at all
- **WRONG** — exists but tests something different than what the plan describes

## Step 3: Audit Production Code

For each file listed in the phase's Production Scope, check:
- Was it created or modified?
- Do the changes align with the phase's implementation steps?
- Are there implementation steps from the plan that have no corresponding code change?

### Check specific patterns:
- **DI chain**: If new dependencies were added, are they properly threaded through `main.dart → MyApp → StartupRouter → ...`?
- **Bridge compatibility**: Are new fields additive? Do old parsers still work?
- **Test fakes**: If production code was changed, were the corresponding fakes in `test/shared/fakes/` updated?
- **Error handling**: Are new error paths tested?

## Step 4: Audit Exit Criteria

For each exit criterion listed in the plan:
- Is there at least one test that proves this criterion?
- Does the production code actually implement the behavior described?
- Can you find evidence (test assertion or code path) that the criterion is met?

Categorize each as:
- **MET** — both test and implementation confirm this
- **PARTIALLY MET** — implementation exists but test coverage is weak, or test exists but implementation is incomplete
- **NOT MET** — missing implementation or missing test or both

## Step 5: Check for Regressions

Run or verify that baseline tests were not broken:
```bash
flutter test test/core/services
flutter test test/core/lifecycle
flutter test test/core/bridge
```

For Go:
```bash
cd go-mknoon && go test ./node ./bridge
cd go-relay-server && go test ./...
```

Check:
- Do any existing tests that were passing before now fail?
- Were any existing test files deleted or renamed without replacement?

## Step 6: Check Cross-Phase Boundaries

Verify the implementation did NOT accidentally:
- Implement features from a later phase
- Depend on features from a later phase that don't exist yet
- Skip features that are prerequisites for the next phase

## Step 7: Produce Gap Report

Output a structured report with the following format:

```
## Phase $ARGUMENTS Review Report

### Test Coverage Audit

#### Missing Tests
| Plan Test Name | Expected File | Status |
|---|---|---|
| <test name> | <file path> | MISSING |

#### Shallow Tests
| Plan Test Name | File | Issue |
|---|---|---|
| <test name> | <file path> | <what's wrong> |

#### Wrong Tests
| Plan Test Name | File | Issue |
|---|---|---|
| <test name> | <file path> | <what it actually tests vs what plan says> |

### Implementation Gaps

#### Missing Implementation Steps
- <step from plan that has no corresponding code>

#### Partial Implementation
- <step that is partially done with description of what's missing>

### Exit Criteria Status
| Criterion | Status | Evidence |
|---|---|---|
| <criterion> | MET / PARTIALLY MET / NOT MET | <test name or code path> |

### Regressions
- <any broken existing tests>

### Cross-Phase Violations
- <any code from other phases, or missing prerequisites>

### Summary
- Tests: X/Y present, Z missing, W shallow
- Implementation steps: X/Y complete, Z partial, W missing
- Exit criteria: X/Y met, Z partially met, W not met
- Regressions: X found
- **Overall verdict: PASS / NEEDS WORK / FAIL**

### Recommended Fix Actions (if NEEDS WORK or FAIL)
1. <specific action to fix gap 1>
2. <specific action to fix gap 2>
...
```

## Critical Rules

1. **Do NOT implement fixes yourself.** Only report gaps.
2. **Be specific.** Every gap must reference a concrete test name, file path, or plan section.
3. **Do NOT report style issues.** Focus on functional gaps against the plan.
4. **Do NOT suggest improvements beyond the plan.** The plan is the spec.
5. **Check actual file contents, not just file existence.** A test file that exists but contains stubs is a gap.
6. **Report the overall verdict honestly.** PASS means every exit criterion is met with real tests. NEEDS WORK means gaps exist but are minor. FAIL means critical functionality is missing.
