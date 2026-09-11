---
name: mknoon-release-check
description: "Run Mknoon's mandatory-plus-affected release checks, verify candidate and published baseline identities, and collect outstanding device/manual evidence. Activate only when explicitly requested by name; never publishes a build."
---

# Mknoon release check

## Prerequisites

Work from the repository root. Read `AGENTS.md`, applicable overrides,
`docs/testing/TESTING.md`, and `tool/testing/selection.json`. Obtain the actual
previous published revision from distribution records and identify the exact
candidate source, configuration, bundled JavaScript, and signed artifact. An
unverified latest tag or last commit is not a release baseline. Do not invoke
other skills without a separate explicit user request.

## Workflow

1. Verify `PUBLISHED_REF` against the actual distribution record. Missing or
   unverifiable release identity is BLOCKED; still finish independent validation.
2. Run `python3 scripts/mknoon_checks.py validate`, then
   `python3 scripts/mknoon_checks.py plan --mode release --base "$PUBLISHED_REF"`.
   The default candidate is clean HEAD. Use `--local` only to assess an explicitly
   identified working-tree candidate; it cannot silently stand in for a signed
   distribution artifact.
3. Review the complete diff and shared dependencies, mandatory checks, additional
   affected checks, unmapped changes, runtime unknowns, and device/manual needs.
   Essential checks remain selected regardless of diff size or runtime target.
4. Run available automated checks with
   `python3 scripts/mknoon_checks.py run --mode release --base "$PUBLISHED_REF" --device-config "$DEVICE_CONFIG"`.
   Inexpensive prerequisites precede device work. Use isolated accounts/services
   and the availability-bounded device topology in `AGENTS.md`; pin target IDs.
5. Complete the signed-candidate checklist in the testing knowledge file, retain
   redacted evidence, and supply the wrapper's documented evidence schema with
   `--evidence "$EVIDENCE_FILE" --candidate-artifact "$CANDIDATE_ARTIFACT"`.
   Repeat `--candidate-artifact` for multiple platform artifacts and record the
   intended version with `--build-label`; a label alone is not artifact proof.
   Evidence must identify this source/configuration and artifact. Source, bundle,
   configuration, or artifact changes require new affected candidate evidence.
6. Review outstanding full-regression failures at the tested revision. Never
   combine unrelated revisions into a full-suite PASS. Preserve first failures
   and distinguish diagnostic reruns from first-attempt success.
7. Update confirmed knowledge and report automated status separately from overall
   release-check status. Name missing checks and external setup precisely.

## Failure handling and outputs

Missing required manual/device evidence remains incomplete. A host test cannot
prove an untested signed artifact, notification OS effect, media recipient open,
upgrade, or old/new-peer journey. Do not substitute unrelated passing tests.
Unavailable version-specific optional hardware is N/A under project policy;
missing evidence for the essential behavior remains outstanding.

Return verified identities, selection fingerprint, commands/devices, durations,
report/evidence paths, first observed failed checkpoints, coverage gaps, and both
automated and overall statuses. Do not publish, push commits, change remote
settings, or describe a candidate as release ready without required evidence.
