# Session 12 CI Gate Handoff

**Date:** 2026-03-26  
**Mode:** External Handoff Mode  
**Scope:** named gate wiring and push hardening invocation contract only

## Status

Session 12 did not locate a repo-local or nearby workspace CI/release workflow target to patch from the current workspace.

Workflow search command used:

```bash
find /Users/I560101/Project-Sat/mknoon-2 -maxdepth 4 \
  \( -path '*/.github/workflows/*' -o -name '.gitlab-ci.yml' -o -path '*/.circleci/*' -o -name 'azure-pipelines*.yml' -o -name 'Jenkinsfile' -o -path '*/bitrise*' -o -path '*/fastlane/*' \) \
  -print
```

Workflow search result:

```text
<empty>
```

Missing external owner record:

- External repo: unknown from current workspace evidence
- External workflow path: unknown from current workspace evidence
- External owner/team: unknown from current workspace evidence
- Current blocker: no reachable CI/release config file was found to patch

## Canonical Named Gate Contract

The external workflow must invoke the repo-local gate runner directly. Do not retype file lists in CI.

Required commands:

```bash
./scripts/run_test_gates.sh baseline
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh feed
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh posts
FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport
./scripts/run_test_gates.sh completeness-check
```

Command source of truth:

- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/test-gates-reference.md`

Canonical transport name:

- Use `transport`
- Do not introduce or preserve `startup_transport`

## Companion Trigger Rules

These rules stay paired with the canonical commands:

- Feed changes that can enter the 1:1 send path must run both `./scripts/run_test_gates.sh feed` and `./scripts/run_test_gates.sh 1to1`.
- Group invite or contact-entry work may also require `flutter test test/features/contact_request/integration/contact_request_flow_test.dart`.
- Feed-originated 1:1 behavior still requires its direct companion regression coverage in `test/features/feed/presentation/screens/feed_wired_test.dart`.
- Do not use `dart_test.yaml` tag filtering as the transport gate contract. The canonical transport contract is the script command plus `FLUTTER_DEVICE_ID` when needed.

## Push Hardening Split

Repo-side automated checks to wire separately from the named regression gates:

```bash
flutter test --no-pub test/features/push/application/ios_push_project_config_test.dart
./scripts/check_push_release_gate.sh
```

Optional strict form when the service account is available:

```bash
FIREBASE_SERVICE_ACCOUNT=/etc/mknoon/firebase-service-account.json \
  ./scripts/check_push_release_gate.sh --require-service-account
```

What this repo can prove locally:

- iOS project config contract
- repo-side push release config contract
- optional service-account project match if `FIREBASE_SERVICE_ACCOUNT` is available

What still remains external/manual even after CI wiring:

- Firebase Console APNs key state
- relay-host `FIREBASE_SERVICE_ACCOUNT` deployment state
- relay log markers
- physical iPhone/TestFlight smoke from `Network-Arch/Push-Notifications-Phase6-Hardening-Gate.md`

## Transport Device Note

Session 12 local evidence confirmed that `flutter devices --machine` found `macos` plus iPhone physical/simulator devices.

External invocation rule:

- If multiple targets are attached or a specific integration target is required, set `FLUTTER_DEVICE_ID=<device-id>`.
- Raw equivalent when the workflow cannot use the script wrapper:

```bash
flutter test -d <device-id> \
  integration_test/background_reconnect_test.dart \
  integration_test/wifi_relay_fallback_smoke_test.dart \
  integration_test/transport_e2e_test.dart \
  integration_test/media_stable_id_smoke_test.dart
```

The script form remains canonical.

## Fresh Session 12 Execution Evidence

- `./scripts/run_test_gates.sh completeness-check` => `PASS` with `574/574` test files classified
- `flutter test --no-pub test/features/push/application/ios_push_project_config_test.dart` => `PASS` with `4 tests`
- `./scripts/check_push_release_gate.sh` => `PASS` with `1 warning`: `FIREBASE_SERVICE_ACCOUNT is not set`
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` => `PASS`
- `./scripts/run_test_gates.sh 1to1` => `PASS`
- `./scripts/run_test_gates.sh feed` => `PASS`
- `./scripts/run_test_gates.sh groups` => `PASS`
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh posts` => `FAIL`
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport` => `FAIL`

## Current Known-Red Status

Current Session 12 local status is:

- Baseline Gate: passing in this workspace
- 1:1 Reliability Gate: passing in this workspace
- Feed / Surface Gate: passing in this workspace
- Group Messaging Gate: passing in this workspace
- Posts / Privacy Gate: red in this workspace
- Startup / Transport Gate: red in this workspace

Exact current red details:

- Posts / Privacy Gate:
  - `test/features/posts/phase3/post_presence_listener_test.dart` passed
  - `integration_test/posts_phase1_fake_test.dart` passed
  - `integration_test/posts_phase2_fake_test.dart` passed
  - `integration_test/posts_phase3_fake_test.dart` passed
  - `integration_test/posts_phase4_fake_test.dart` passed
  - `integration_test/posts_phase5_fake_test.dart` failed at `integration_test/posts_phase5_fake_test.dart:122`
  - failing test: `receiver dismiss stays local while sender edits update the feed snapshot`
  - failure text: `Expected: empty / Actual: [Instance of 'PostModel']`
- Startup / Transport Gate:
  - `integration_test/background_reconnect_test.dart` failed because node did not reach `Online` within `30s`
  - `integration_test/wifi_relay_fallback_smoke_test.dart:197` failed to build because `MessageRepositoryImpl` now requires `dbRecoverStuckSendingMessages`
  - `integration_test/transport_e2e_test.dart:240` failed to build because `MessageRepositoryImpl` now requires `dbRecoverStuckSendingMessages`
  - `integration_test/media_stable_id_smoke_test.dart` failed to start app on macOS with debug connection/startup issue

Important handling rule:

- Wire the real workflow to the canonical commands as they are.
- Do not weaken or relabel the gates to make them appear green.
- If the external workflow is intended to block merges/releases, the current red status above must be accounted for explicitly by the external owner.

## External Invocation Contract

Minimum required wiring shape:

1. Run `./scripts/run_test_gates.sh completeness-check` to protect classification drift.
2. Run named gates by script command, not by folder shorthand or copied file list.
3. Pass `FLUTTER_DEVICE_ID=<device-id>` for the transport gate when the runner needs a specific target.
4. Keep push hardening as a separate release-config lane from the named regression gates.
5. Preserve companion trigger rules from `Test-Flight-Improv/test-gates-reference.md`.
6. Preserve current red/green truth from fresh evidence instead of assuming Session 1 status is still current.

Not acceptable:

- Retyping gate membership in CI
- Creating a new gate taxonomy
- Using stale `startup_transport` naming
- Folding push hardening into the named gate list

## Acceptance Note

Session 12 is acceptable as `accepted_with_external_follow_up` if:

- the canonical repo-local invocation contract is documented here
- the missing external repo/path/owner is recorded explicitly
- the exact workflow search command and empty result are preserved
- the current local red/green status is preserved truthfully
- external owner follow-up is limited to wiring the real CI/release path

Remaining external follow-up:

- identify the real CI/release owner path
- patch that external workflow to invoke the commands listed here
- decide how the external system will handle the currently red `posts` and `transport` gates
- run the full push Phase 6 release gate where service-account, relay, console, and TestFlight access exist
