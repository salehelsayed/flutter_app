---
name: mknoon-change-check
description: "Run Mknoon's deterministic fast-plus-affected checks after code changes and before claiming validation. Activate only when the user explicitly requests mknoon-change-check by name."
---

# Mknoon change check

## Prerequisites

Work from the repository root. Read `AGENTS.md` and applicable overrides,
`docs/testing/TESTING.md`, and the relevant rules in
`tool/testing/selection.json`. Use a verified explicit comparison revision;
for a pull request use its merge base with the intended target branch.
Do not invoke other skills without a separate explicit user request.

## Workflow

1. Inspect the complete relevant diff, including staged, unstaged, untracked,
   renamed, and deleted files. Use the project Graphify policy to inspect shared
   consumers and assertions when an executable mapping needs review.
2. Run `python3 scripts/mknoon_checks.py validate`.
3. Preview local changes with
   `python3 scripts/mknoon_checks.py plan --mode change --base "$BASE_REF" --local`.
   `BASE_REF` must be the verified revision from the prerequisites. Omit `--local`
   only when intentionally validating a clean committed candidate.
4. Inspect reasons, unknown impact, untested areas, prerequisites, and runtime
   unknowns. Correct demonstrated stale mappings before claiming validation;
   never narrow a mapping merely to avoid a slow or failing check.
5. Execute the same selection with
   `python3 scripts/mknoon_checks.py run --mode change --base "$BASE_REF" --local`.
   Use only isolated fixtures/accounts/services. Required device evidence must
   use explicit IDs from the current live device matrix.
6. Explain failures using the first observed failed boundary and retained
   evidence. Keep the first attempt visible if a diagnostic rerun passes.
   Distinguish product assertion failures, harness failures, unavailable
   prerequisites, and unexecuted checks.
7. Update existing knowledge entries when evidence establishes a new dependency,
   regression, runtime, or reliability limitation. Keep executable selection
   changes in the manifest and raw artifacts outside tracked memory.

## Failure handling and outputs

An invalid plan, stale selector, zero executed tests, required blocked check, or
nonzero runner result is not validation success. Complete independent checks and
report outstanding requirements. Do not run the entire long suite for every edit
or repair unrelated application behavior under this skill.

Return the baseline/candidate identity, selection/report paths, selected versus
executed checks, measured elapsed time, first-attempt failures and reruns, and
unexecuted requirements. State whether the change checks passed; they do not
certify a signed release artifact.
