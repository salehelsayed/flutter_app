# Session 12 Plan: Wire Named Test Gates Into CI / Release Automation

**Date:** 2026-03-26
**Status:** Plan only

## 1. Real Scope

Turn the named gates already frozen in this Flutter repo into an actually enforced CI / release contract without inventing a new gate layer.

Repo-local facts already in place:
- `scripts/run_test_gates.sh` is the canonical command surface for the named gates.
- `Test-Flight-Improv/test-gate-definitions.md` is the canonical gate membership and classification artifact.
- `Test-Flight-Improv/test-gates-reference.md` is the lighter checklist/reference artifact.
- `scripts/check_push_release_gate.sh` plus `test/features/push/application/ios_push_project_config_test.dart` already define the push release hardening contract.

This session stays narrow:
- do not redesign test architecture
- do not expand the gate matrix
- do not replace canonical scripts with retyped `flutter test` file lists
- do not assume the real CI host is GitHub Actions or lives in this tree

This session is repo-local plus external-owner coordination work. If the actual CI / release config path is not accessible from this workspace, the correct outcome is External Handoff Mode, not roadmap failure.

## 2. Session Classification

`cross-tree`

Why:
- the canonical gate runner and gate docs are in this Flutter tree
- no repo-local CI workflow was found under this tree or nearby workspace roots
- the real CI / release owner path is therefore unconfirmed from current repo-local evidence and must be recorded as either reachable, unknown, or unreachable during execution

## 3. Files and Repos to Inspect Next

Inspect these repo-local artifacts first:
- `Test-Flight-Improv/16-session-todo-roadmap-2.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/15-session-todo-roadmap.md`
- `Test-Flight-Improv/session-1-plan.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/test-gates-reference.md`
- `scripts/run_test_gates.sh`
- `scripts/check_push_release_gate.sh`
- `dart_test.yaml`
- `Network-Arch/Push-Notifications-Phase6-Hardening-Gate.md`
- `test/features/push/application/ios_push_project_config_test.dart`

Then inspect the real CI / release owner path if it is reachable from the current workspace.

Record explicitly:
- external repo name if known
- external path if known
- external owner/team if known
- whether the path is inaccessible from the current workspace

Preferred handoff artifact if the external path is not reachable:
- `Test-Flight-Improv/ci-gate-handoff.md`

## 4. Existing Tests Covering This Area

Existing coverage and contract artifacts already available:
- `scripts/run_test_gates.sh` defines the canonical commands for `baseline`, `1to1`, `feed`, `groups`, `posts`, `transport`, `all`, and `completeness-check`
- `Test-Flight-Improv/test-gate-definitions.md` freezes exact gate membership and currently known failures
- `Test-Flight-Improv/test-gates-reference.md` provides the lighter trigger/command checklist
- `test/features/push/application/ios_push_project_config_test.dart` validates the repo-side iOS push project contract
- `scripts/check_push_release_gate.sh` validates repo-side push release config and optional service-account matching
- `Network-Arch/Push-Notifications-Phase6-Hardening-Gate.md` documents the exact push hardening invocation and manual release checks

Important current evidence:
- several named gates are intentionally documented as red or partially red in `Test-Flight-Improv/test-gate-definitions.md`
- Session 12 must preserve those known failures as truth, not weaken or hide them to make CI wiring look green

## 5. Regression / Tests To Add First

None in the Flutter product tree by default.

Only add a minimal config-side validation change if the reachable external CI / release path needs a tiny wrapper to invoke the canonical shell commands without retyping file lists.

## 6. Evidence To Capture First

Capture this before editing any reachable external workflow:
- whether the actual CI / release repo or owner path is reachable from the current workspace
- whether the external system can invoke shell scripts directly
- the exact command string it should use for:
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh feed`
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh posts`
  - `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport`
- the exact command string for push hardening:
  - `flutter test --no-pub test/features/push/application/ios_push_project_config_test.dart`
  - `./scripts/check_push_release_gate.sh`
  - optional `FIREBASE_SERVICE_ACCOUNT=... ./scripts/check_push_release_gate.sh --require-service-account`
- whether any stale `startup_transport` naming exists outside this tree and must be mapped to `transport`
- the exact searched roots/command used to confirm that no repo-local workflow files were found if the external path remains unknown or unreachable
- the companion trigger rules that must remain preserved alongside the named gate commands:
  - feed changes that enter the 1:1 send path must also run `1to1`
  - group invite/contact-entry work may also require `test/features/contact_request/integration/contact_request_flow_test.dart`
  - feed-originated 1:1 behavior still requires its direct companion regression coverage in `test/features/feed/presentation/screens/feed_wired_test.dart`
- the current known-red named gates from fresh execution evidence that must stay documented truthfully
  - Posts / Privacy Gate
  - Startup / Transport Gate
- the boundary between repo-side automated push checks and the full release gate:
  - repo-side automated checks are `ios_push_project_config_test.dart` plus `./scripts/check_push_release_gate.sh`
  - full release gate still includes `--require-service-account` where available, Firebase/APNs console state, relay-host checks, and physical-device/TestFlight/manual smoke

## 7. Step-by-Step Implementation Or Evidence-Collection Plan

1. Reconfirm the repo-local source of truth:
   - `scripts/run_test_gates.sh`
   - `Test-Flight-Improv/test-gate-definitions.md`
   - `Test-Flight-Improv/test-gates-reference.md`
   - push hardening commands in `Network-Arch/Push-Notifications-Phase6-Hardening-Gate.md`
2. Search for the real CI / release owner path from the current workspace.
3. If the external path is reachable:
   - patch only the smallest relevant workflow/wrapper entry point
   - make it invoke the canonical repo-local commands directly
   - normalize any stale `startup_transport` label to `transport`
   - use `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport` for the named transport gate instead of tag-filtering shortcuts
   - keep push hardening separate from named regression gates
4. If the external path is not reachable:
   - switch immediately to External Handoff Mode
   - create or update `Test-Flight-Improv/ci-gate-handoff.md`
   - record the exact canonical commands, invocation points, required device note for transport, companion trigger rules, push hardening commands, current known-red gates, the missing external repo/path/owner, and the exact search command/result showing no repo-local workflow target was found
5. In either path, validate command parity against the repo-local script/docs instead of inventing a new definition.
6. Preserve the current known-failure truth from fresh execution evidence while keeping `Test-Flight-Improv/test-gate-definitions.md` as the canonical gate-definition artifact; do not claim that wiring CI means the gates are green.
7. Keep push hardening split explicitly:
   - repo-side automated checks can be validated locally from this tree
   - full release-gate proof may remain external follow-up if service-account access, Firebase/APNs console access, relay logs, or TestFlight/manual validation are not reachable here
8. Capture fresh Session 12 evidence for every command run in this session instead of copying Session 1 status text forward.

External Handoff Mode is sufficient for this session when:
- no more repo-local work can reduce uncertainty
- the canonical command surface is defined
- the exact external invocation contract is documented
- the missing external repo/path/owner is recorded explicitly

## 8. Risks And Edge Cases

- No repo-local CI workflow exists, so the real edit target may be external and inaccessible.
- Older roadmap/report wording may still say `startup_transport`, but `transport` is the canonical name in current repo-local artifacts.
- Transport gate validation may require `FLUTTER_DEVICE_ID`; CI might need a device-backed job or a documented manual/release step.
- Named gates are not all green today; Session 12 must wire the real command surface without hiding current failures.
- Push release hardening is a separate release-config gate and must not be folded into the named regression gate taxonomy.

## 9. Exact Tests To Run After Implementation

Repo-local validation to run in either path:

```bash
./scripts/run_test_gates.sh completeness-check
./scripts/run_test_gates.sh baseline
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh feed
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh posts
FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport
flutter test --no-pub test/features/push/application/ios_push_project_config_test.dart
./scripts/check_push_release_gate.sh
```

If the external CI / release system is reachable and has its own validation command, run that exact validation too.

If the external path is not reachable, validate that `Test-Flight-Improv/ci-gate-handoff.md` matches:
- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/test-gates-reference.md`
- `dart_test.yaml`
- `Network-Arch/Push-Notifications-Phase6-Hardening-Gate.md`
- `scripts/check_push_release_gate.sh`
- companion trigger rules from `Test-Flight-Improv/test-gates-reference.md`
- the searched workflow-path roots/command and empty result evidence

Push hardening validation rule:
- if the execution context has `FIREBASE_SERVICE_ACCOUNT`, validate the strict form `FIREBASE_SERVICE_ACCOUNT=... ./scripts/check_push_release_gate.sh --require-service-account`
- if it does not, record explicitly that the full Phase 6 release gate remains an external/manual follow-up and that repo-side automated checks alone are not proof that the full release gate landed
- for the named transport gate, do not rely on `dart_test.yaml` `device` tags; the canonical contract is the script command with `FLUTTER_DEVICE_ID` when needed

## 10. Subsystem Gate(s)

No feature-specific subsystem gate beyond validating the gate runner and push hardening contract themselves.

This session is about automation wiring, not adding new coverage buckets.

## 11. Whether Baseline Gate Is Required

Yes.

Reason:
- Session 12 is the canonicalization/enforcement session for the named gate surface
- validation is about the exact command contract, not about forcing every gate green
- known-red gate results remain acceptable evidence if they are unchanged and explicitly recorded

## 12. Whether Startup / Transport Gate Is Required

Yes, for invocation-path validation.

Use the canonical `transport` command. If a device-specific run is needed, pass `FLUTTER_DEVICE_ID=<device-id>` rather than retyping the file list.

## 13. Done Criteria

This session is complete when one of these two outcomes is true:

1. The actual reachable CI / release owner path now invokes the canonical repo-local command surface directly, and naming is consistent with:
   - `scripts/run_test_gates.sh`
   - `Test-Flight-Improv/test-gate-definitions.md`
   - `Test-Flight-Improv/test-gates-reference.md`
   - push hardening commands in `Network-Arch/Push-Notifications-Phase6-Hardening-Gate.md`

2. External Handoff Mode has been completed, meaning:
   - `Test-Flight-Improv/ci-gate-handoff.md` exists or is updated
   - it names the exact canonical commands
   - it preserves the documented companion trigger rules, not just the raw named-gate commands
   - it records transport device requirements
   - it records the repo-side push hardening invocation contract
   - it distinguishes repo-side automated push checks from the full external release gate
   - it records the missing external repo/path/owner explicitly
   - it preserves the current known-red gate status instead of masking it

In either outcome:
- no larger CI matrix was introduced
- no ad hoc file-list duplication replaced the canonical script
- `transport` is the canonical transport gate name
- Session 12 contains fresh command/output evidence for the repo-local validation it actually ran

## 14. Scope Guard

- Do not invent a larger CI matrix.
- Do not replace named gates with broad directory sweeps unless the gate definition itself is intentionally changing.
- Do not silently assume GitHub Actions if the team’s real CI lives elsewhere.
- Do not mark the session failed solely because the external CI / release host is inaccessible once the repo-local command surface and handoff package are complete.
- Do not broaden into fixing the currently red named gates in this session.
