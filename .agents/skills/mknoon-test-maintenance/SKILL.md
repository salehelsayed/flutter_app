---
name: mknoon-test-maintenance
description: "Maintain Mknoon's test inventory, deterministic mappings, and verified testing memory when tests, infrastructure, or confirmed regressions change. Activate only when explicitly requested by name."
---

# Mknoon test maintenance

## Prerequisites

Work from the repository root. Read `AGENTS.md`, applicable overrides,
`docs/testing/TESTING.md`, and `tool/testing/selection.json`. Start from the changed
tests, fixtures, runner configuration, dependency, or confirmed regression and its
evidence. Do not invoke other skills without a separate explicit user request.

## Workflow

1. Run `python3 scripts/mknoon_checks.py discover --list-runners --output .codex-test-logs/inventory-review` to refresh the generated
   inventory. Distinguish discovered files/suites from inspected assertions and
   actual runner-reported cases; generated cases cannot be counted from names.
2. Inspect the affected assertions, shared helpers, production boundaries, and
   existing diagnostics using targeted source searches and the document-memory policy.
   Reuse relevant prior evidence before adding logging. Widen inspection when
   shared dependency impact demands it; avoid an unrelated whole-repo reaudit.
3. Reuse or strengthen an existing test first. Add application tests only for a
   demonstrated gap; document the missing observable behavior. Do not weaken
   assertions, silently skip, or quarantine a critical failing check.
4. Update executable mappings only in `tool/testing/selection.json`. Handle added,
   removed, and renamed selectors explicitly. Narrow mappings or mandatory
   coverage only with reviewed evidence, never because a check is slow or failed.
5. Update the existing relevant knowledge entry with:
   symptom → confirmed cause or first failing boundary → affected behavior →
   regression test → mapping change → evidence. Label hypotheses and unknown
   runtimes explicitly; keep raw artifacts outside tracked memory.
6. Run `python3 scripts/mknoon_checks.py validate --inventory .codex-test-logs/inventory-review/inventory.json` and the workflow's own tests:
   `python3 -m unittest discover -s scripts/test -p '*checks_test.py'` and
   `python3 -m unittest discover -s scripts/test -p 'testing_inventory_test.py'`.
7. Preview and execute the affected selection against a verified explicit base:
   `python3 scripts/mknoon_checks.py plan --mode change --base "$BASE_REF" --local`
   followed by the identical command with `run` replacing `plan`.

## Failure handling and outputs

Stale/missing selectors, unexpected empty execution, unmapped behavior changes,
and runner failures must remain visible and non-green. Retain first-attempt
results after reruns. Complete available independent validation and name blocked
requirements. Do not automatically launch the full regression suite.

Return the inspected scope, verified lesson, changed rules/knowledge, discovery
and validation artifacts, commands/results, and unresolved coverage/reliability
limitations. Do not commit generated run artifacts or let CI rewrite memory.
