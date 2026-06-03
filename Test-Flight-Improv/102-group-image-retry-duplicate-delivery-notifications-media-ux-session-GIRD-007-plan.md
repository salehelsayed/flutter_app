Status: accepted with residual-only APNs follow-up

# GIRD-007 - Incident Acceptance, Simulator/Device Evidence, Gates, and Closure Docs Plan

## Scope

Close only the final acceptance/doc gap owned by `GIRD-007`:

- validate the accepted `GIRD-001` through `GIRD-006` slices together against the reported group image retry duplicate incident
- run the source-required host and group reliability simulator gates with fix-as-you-go
- record whether the narrow real APNs background/terminated iOS device-context path is closed, residual-only, or blocked with evidence
- update the source spec, this breakdown, and stable matrix/closure docs with each listed acceptance gap classified as `closed`, `residual-only`, or `blocked`

Out of scope:

- no new sender/retry/recipient/relay/media/notification implementation unless a final gate exposes a real regression in the accepted scope
- no broad physical-device/manual verification beyond the spec's narrow iOS APNs background/terminated device-context item
- no redesign of notification, media, group, or relay behavior

## Current Dependency State

- `GIRD-001`: accepted sender in-doubt classification and same-id reconciliation.
- `GIRD-002`: accepted retry ownership across composer, failed-card, upload-pending, and resume.
- `GIRD-003`: accepted recipient logical media retry dedupe.
- `GIRD-004`: accepted relay/native group inbox idempotency and duplicate push fanout suppression.
- `GIRD-005`: accepted retryable media loading versus terminal unavailable UI.
- `GIRD-006`: accepted notification identity/suppression/fallback/tap repo-level proof.

## Device And Gate Profile

- Host gate skill used: `$run-flutter-host-gates`.
- Reliability simulator skill used: `$run-flutter-reliability-sims`.
- `feature-host-all --list` discovered `484` host feature commands.
- Initial `group --list` reliability discovery resolved:
  - one-device simulator: `38FECA55-03C1-4907-BD9D-8E64BF8E3469`
  - two-device simulator pair: `38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`
  - Android serial exported by the resolver: `21071FDF600CSC`
  - relay addresses exported by the resolver from the skill defaults
- Final resumed group reliability device set resolved:
  - one-device simulator: `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
  - two-device simulator pair: `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9`
  - role devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, Dana `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`
- Real iOS hardware is visible to Flutter (`00008030-001A6D2801BB802E`, `00008110-00184D622289801E`), but repo evidence found no local non-interactive script that can send a production APNs background/terminated push through the provider path to those devices. The simulator APNs tap and push-decrypt smokes remain repo/simulator evidence only.

## TDD / Acceptance Plan

1. Run host final gates fail-fast:
   - `./scripts/run_test_gates.sh groups` if not already fresh after `GIRD-006`
   - `$run-flutter-host-gates` `feature-host-all`
   - `./scripts/run_test_gates.sh completeness-check`
2. Run final Go preservation for accepted relay/native changes:
   - `cd go-relay-server && go test ./...`
   - `cd go-mknoon && go test ./node ./bridge ./internal`
3. Run group reliability simulator final scope fail-fast:
   - `$run-flutter-reliability-sims` `group`
4. Run final hygiene:
   - `dart format --set-exit-if-changed` on touched Dart files if code changes
   - `gofmt -w` on touched Go files if code changes
   - `git diff --check`
5. If any command fails, classify root cause as product, test, harness, or environment; fix only the correct layer; rerun the failed command by number where the helper supports it; resume from the next command; rerun the full requested scope once at the end.
6. Update docs with final classifications and evidence:
   - `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md`
   - this breakdown
   - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
   - `Test-Flight-Improv/52-notification-journey-test-matrix.md`
   - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
   - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` only if row-level group matrix classifications change
   - `Test-Flight-Improv/test-gate-definitions.md` only if a new durable gate classification is added

## Execution Progress

- Host final gate evidence:
  - `feature-host-all --list` discovered `484` commands.
  - `feature-host-all` passed as an ordered fail-fast/resume sweep from `#1` through `#484` after isolated host test repairs.
  - `./scripts/run_test_gates.sh groups` passed with `313` tests.
  - `./scripts/run_test_gates.sh completeness-check` initially found `761/767` classified test files; after adding direct-suite classifications for `test/core/debug/*.dart`, `test/l10n/*.dart`, and `test/shared/fakes/*.dart`, it passed with `767/767`.
- Go preservation evidence:
  - `cd go-relay-server && go test ./...` passed.
  - `cd go-mknoon && go test ./node ./bridge ./internal` passed.
- Group reliability simulator evidence:
  - `group --list` discovered `122` commands.
  - The dry-run/list pass confirmed command `#49` maps to `integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_never_member_publish_rejected`.
  - Initial `group` execution passed `#1` through `#7`.
  - `#8` failed in `integration_test/group_recovery_e2e_test.dart` because the test MaterialApp omitted localization delegates for `GroupInfoScreen`; harness-only l10n wiring fixed it, and `group --only 8` passed.
  - Resume from `#9` passed `#9` and `#10`.
  - `#11` first exposed the four-device precondition for the invite-status matrix, then failed on the same harness-localization class in `integration_test/group_invite_status_matrix_harness.dart`; booting the fourth simulator and adding harness-only l10n wiring fixed it, and `group --only 11` passed.
  - Resume from `#12` passed `#12` through `#48`, including `MD-004`, multi-party scenarios `ge001` through `ge024`, `go001` through `go003`, `gm001`, `de002`, `de003`, `de007`, `de017`, `ir001`, `ir015`, `ir016`, `pl002`, `pl012`, `private_abc_create`, `private_reaction_roundtrip`, and `private_removed_reaction_rejected`.
  - `#49` originally failed on the Dana role on simulator `38FECA55-03C1-4907-BD9D-8E64BF8E3469`: Dana never reached online state while Alice/Bob/Charlie stayed healthy; Dana stayed `relayState=recovering` with zero circuit addresses, zero connections, relay peer connect/disconnect loops, and inbox stream connection failures. Exit `143` was cleanup after `TimeoutException: dana did not reach online state`, not the root cause.
  - Triage compared the previous accepted `private_never_member_publish_rejected` proof at `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_never_member_publish_rejected_z2Oq7f`, rotated Dana to other booted simulators during later scenarios, and found stale repo-owned transport census/testpeer processes consuming relay capacity and polluting transport state. Classification: environment/harness preflight fixture issue, not Dana-role, scenario/member logic, group-image behavior, or product transport.
  - The stale repo-owned transport/testpeer processes were removed, then `group --only 49` passed for `private_never_member_publish_rejected` with shared artifact dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_never_member_publish_rejected_K8Q6OU`, run id `1780323563475`; captured role logs: `alice.log`, `bob.log`, `charlie.log`, and `dana.log`, plus all role verdict JSON.
  - The later full group reliability sweep re-ran `#49` and passed again with artifact `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_never_member_publish_rejected_YwrP1Q`, run id `1780357563278`; this artifact also contains all four role logs and verdict JSON.
  - Fix type for the original #49 blocker: harness/environment preflight. `scripts/run_reliability_simulations.sh` now rejects stale repo-owned `run_transport_census_cli.dart`, `transport_census_harness.dart`, and `go-mknoon/bin/testpeer` processes before actual reliability execution. The online assertion was not weakened.
  - Minimal product transport hardening was added without changing group-image behavior: startup relay recovery/diagnostics in `lib/core/services/p2p_service_impl.dart`, bounded explicit relay reservation and `relay:reservation_timing` diagnostics in `go-mknoon/node/*`, and Flutter bridge passthrough for that diagnostic event.
  - Resume `group --start-at 50` exposed and fixed two harness issues: `#68 private_max_group_size_churn` stale membership fixture (`/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_max_group_size_churn_zGiKBv`, run id `1780330114687`) and `#72 private_same_user_multi_device_readd` verdict JSON read/write race (`/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_same_user_multi_device_readd_KuV7Mm`, run id `1780364707205`). Both were harness fixes, not product behavior changes.
  - The final full group reliability fail-fast/resume sweep completed all `122` commands. Environment-only interruptions were classified and rerun at the failed command: `#43` disk-full `Flutter.lipo` failure, then rerun pass at `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ir016_ZmVdIL`; `#86` disk-full/no-verdict stall, then rerun pass at `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_admin_demotion_enforcement_vhCFri`, run id `1780370097229`.
  - Final tail evidence passed: `#87` through `#114` multi-party scenarios, `#115` group recovery, `#116` media delivery UI smoke, `#117` media stable-id smoke, `#118` notification-open UI smoke, `#119` notification sound smoke, `#120` routing + group smoke (`26/26`), `#121` iOS notification tap UI smoke (`build/ios-notification-tap-ui-smoke/20260602T052947Z`), and `#122` push-decrypt simulator smoke. The wrapper ended with `PASS: reliability simulations completed for scope: group`.
- Narrow iOS APNs device-context classification:
  - Real iOS hardware is visible to Flutter, but no repo-local non-interactive provider APNs sender harness was found for a production/TestFlight background-or-terminated group image push to those devices.
  - Repo-level iOS evidence remains closed through Go APNs payload tests, NSE duplicate preview tests, simulator tap/open coverage, and push-decrypt simulator smoke coverage. The production/provider APNs background/terminated device-context path is `residual-only with explicit follow-up`: add and run a provider-backed physical-device/TestFlight harness for canonical same-id and re-minted group image pushes, proving visible notification, NSE preview/fallback, OS coalescing, tap route, and group catch-up.

## Final GIRD-007 Verdict

- Verdict: `accepted with residual-only APNs follow-up`.
- Closed within `GIRD-007`: final host coverage, `groups`, `completeness-check`, Go relay/native preservation, and the full `group` reliability simulator scope are green after fix-as-you-go classification and targeted reruns.
- Blocked within `GIRD-007`: none. The former `#49` Dana online-readiness blocker is classified as environment/harness preflight and is now closed with passing `group --only 49`, later full-sweep `#49`, and full group reliability evidence.
- Residual-only within `GIRD-007`: the narrow real iOS provider APNs background/terminated device-context proof remains unavailable in the repo and needs a provider-backed physical-device/TestFlight follow-up.

## Done Criteria

- Every final command is recorded as passed, residual-only, or blocked with exact evidence.
- Every source acceptance gap family is classified as `closed`, `residual-only with explicit follow-up`, or `blocked with evidence`.
- The final verdict does not claim real APNs background/terminated device-context proof unless that exact provider/device path is actually executed.
- Source and stable matrix docs point to the permanent regression tests and accepted session evidence rather than only this transient plan.
