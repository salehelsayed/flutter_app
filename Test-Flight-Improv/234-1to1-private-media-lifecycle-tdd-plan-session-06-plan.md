# Plan 234 Session 06 — Cross-session acceptance, device-local proof, and closure

Status: accepted
Source: `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-breakdown.md` Session 06
Run mode: acceptance-only + non-production proof harness + program closure
Dependencies: Plan 234 Sessions 01–05 and Plan 247 Sessions 01–04/overall are accepted; the bounded Session-02 iOS NSE repair is accepted
Migration owner: none; Plan 234 retains landed DB v100 exclusively and Plan 238 retains sequential DB v101

## Planning Grounding

- `AGENTS.md` governs this plan. The shared dirty worktree must be preserved:
  no reset, stash, checkout, revert, broad reformat, or overwrite of unrelated
  work is permitted.
- The architecture Graphify planning query was run with the TDD profile and
  exact anchors `PrivateMediaProtectionCoordinator` and
  `DirectPrivateMediaViewerController`. It returned current,
  `confidence=anchored` context and surfaced the direct private route,
  lifecycle, central action decision, ordinary/shared typed viewers, and
  platform-protection proof candidates. Current source and literal gate
  registrations remain the execution authority.
- Sessions 01–05 are accepted and stay closed unless this session produces a
  concrete executable regression in their owned boundary.
- The later concrete iOS Notification Service Extension leak is already
  repaired and reclosed under Session 02. Accepted repair evidence is the
  causal compile RED, exact GREEN `1/1`, full
  `NotificationPreviewResolverTests` `30/30`, Dart preview preservation
  `55/55`, independent QA at `post_closure_fix_passes=1`, Graphify
  `affected`, and exactly one additional post-QA incremental refresh.
- Plan 247 is accepted and closed. Session 06 therefore evaluates Plan 234
  against the current additive shared-viewer action contract rather than the
  pre-Plan-247 viewer snapshot.
- Planning-time availability on 2026-07-12 included physical Android
  `21071FDF600CSC`, Android emulator `emulator-5554`, and available iOS
  simulators. These are observations, not immutable gate inputs. Execution
  must discover and pin the then-live IDs.

## Objective And Acceptance Boundary

Close Plan 234 only if fresh current-tree evidence proves the accepted
D-234-01..08 device-local contract as one coherent system:

1. Eligible direct private image/video policy is carried only inside encrypted
   v2 content; missing policy remains ordinary and unknown/malformed private
   policy fails closed.
2. The receiver commits current private policy/lifecycle authority before any
   preview or download decision. Foreground, Dart push, and iOS NSE private
   previews expose only the localized meaning `Private media`.
3. Private media never auto-downloads. A still-available private parent may use
   only the existing guarded manual in-app download into canonical app-owned
   storage.
4. View Once has one successful reveal, terminal cleanup converges, and reopen
   cannot resurrect bytes or authority. Disappearing expiry and monotonic
   high-water behavior survive restart. Protected media remains repeat
   viewable until another accepted terminal event.
5. Save/Files/Share, Forward, bookmark, Shared Media/batch, ordinary viewers,
   and typed PiP eligibility all fail closed from one freshly loaded exact
   direct parent/attachment decision. Reply/Info remain generic and
   Delete-for-me remains safe.
6. Android protection is route-scoped and restored. iOS detects/obscures and
   never claims screenshot prevention. No private content enters actual PiP.
7. Ordinary and legacy direct media retain send/receive, notification,
   download, viewer, action, Forward, bookmark/library, retry, and delete
   behavior. Same-ID group and unresolved siblings remain untouched.
8. DB v100 passes host and real SQLCipher upgrade/fresh/reopen/rerun evidence
   on each applicable available platform.
9. A fully automated physical-Android + Android-emulator run supplies honest,
   correlated, deterministic app-layer evidence. It is not represented as a
   real relay journey, account-wide convergence, a consume receipt, or remote
   revocation.
10. Current named gates, static checks, scope guards, independent QA, and
    synchronized closure documents all pass without a Session-06 production
    delta.

Session 06 may add proof code, exact registrations, and closure documentation.
It does not own product implementation. If a current executable counterexample
requires production to change, stop Session 06, reopen the owning accepted
session with a causal regression, run that owner's focused/QA/Graphify/closure
workflow, and then restart Session 06 from a fresh baseline.

## Source Of Truth

Use these authorities in descending order:

1. `AGENTS.md`, especially Graphify, availability-bounded device policy, and
   per-session gate cadence.
2. The accepted D-234-01..08 contract in
   `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan.md`.
3. Accepted Plan-234 Session-01..05 Execution Results, repair amendments, QA
   verdicts, and Closure Audits.
4. Accepted Plan-247 source/session closure for the current additive
   shared-viewer action.
5. Current production, tests, native projects, and exact executable gate
   arrays.
6. This Session-06 plan for the acceptance harness, evidence interpretation,
   and final closure workflow.

A historical blocked/evidence-gated paragraph or old count does not supersede
an accepted later ledger. Current command counts must be recorded from
execution and must not be copied from an earlier session.

## Exact Session Scope

### New non-production proof files

- `test/integration/direct_private_media_device_local_journey_criteria_test.dart`
- `integration_test/scripts/direct_private_media_device_local_journey_criteria.dart`
- `integration_test/direct_private_media_device_local_journey_harness.dart`
- `integration_test/scripts/run_direct_private_media_device_local_journey.dart`

### Registration and executable documentation

- `scripts/run_test_gates.sh`
- `scripts/run_host_test_gates.sh`
- `scripts/check_reliability_simulation_discovery.sh`
- `Test-Flight-Improv/test-gate-definitions.md`

The pure host criteria test is pinned in both `ONE_TO_ONE_TESTS` and
`ONE_TO_ONE_HOST_TESTS`. The criteria module, device harness, and runner are
recorded exactly in `test-gate-definitions.md` and classified by reliability
discovery; the integration files remain exact device commands rather than
being broadened into a host family.

### Closure documents

- this Session-06 plan;
- `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan.md`;
- `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-breakdown.md`;
- `Test-Flight-Improv/00-INDEX.md`; and
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`.

### Read-only acceptance surfaces

Session 06 reads and tests, but does not edit:

- all Plan-234 production, existing host tests, native owners/tests, SQLCipher
  proof, and platform-protection proof;
- the repaired iOS NSE resolver and its full test suite;
- Plan-247 production/tests and accepted documents;
- DB version/migration/registry state;
- Go/libp2p/relay, group, and announcement trees; and
- every excluded-plan artifact.

## Strict Non-Goals

- No migration, schema, DB v101, or migration-registry change.
- No group, discussion, or announcement behavior.
- No Go, libp2p, relay, protocol, receipt, custody, or revocation behavior.
- No native production/channel/project change.
- No actual Picture in Picture implementation or Plan-243 edit.
- No account-wide/global consume, cross-install convergence, or uninstall
  recovery claim.
- No real-relay or real cross-device transport claim from the deterministic
  Android pair.
- No iPhone substituted as the second endpoint of the generic Android pair.
- No manual tap, operator navigation, or user-assisted assertion.
- No `core-host-all`, `feature-host-all`, or full `host-all`. Full `host-all`
  remains owned by the final included Wave-1 aggregate, not this session.
- No work on Plans 241, 242, 243, 248, 253, or 254. Plans 242, 243, 248, 254,
  241, and 253 remain excluded from this rollout.
- No Plan-238 or other later-session implementation.

## Execution Preflight And Immutable Scope

Before the first RED:

1. Confirm every dependency status and accepted repair in the current files.
2. Confirm no Flutter test, Gradle test, `xcodebuild`, device runner, analyzer,
   or Graphify refresh is active. Do not terminate an unrelated process.
3. Wait for unrelated writers touching any scoped test/gate/closure file to
   finish; then capture status plus hashes. A moving baseline is not valid.
4. Re-resolve the live matrix with `flutter devices --machine`,
   `adb devices -l`, and `xcrun simctl list devices available`. Pin all device
   commands to explicit IDs.
5. Capture an immutable manifest for all production/native/existing-test and
   protected-plan paths. The manifest may be non-clean; equality, not
   cleanliness, is the guard.
6. Capture individual hashes and one aggregate hash for every Session-06
   proof/registration/closure file, recording absent new files explicitly.

Dependency gate:

```bash
for plan_file in \
  Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-01-plan.md \
  Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-02-plan.md \
  Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-03-plan.md \
  Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-04-plan.md \
  Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-05-plan.md \
  Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan.md
do
  rg -x 'Status: accepted' "$plan_file"
done

rg -q 'post_closure_fix_passes=1' \
  Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-02-plan.md
rg -q 'full resolver.*30/30|NotificationPreviewResolverTests.*30/30' \
  Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-02-plan.md
rg -q '^\| 02 .*accepted.*accepted' \
  Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-breakdown.md
rg -q '^## Closure Audit$' \
  Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-04-plan.md
```

Use a temporary evidence directory outside the repository. Persist its path,
manifest hashes, and final redacted artifact hash in Execution Progress:

```bash
export S06_EVIDENCE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/plan234-s06.XXXXXX")"

snapshot_scope() {
  local output_file="$1"
  shift
  {
    git status --porcelain=v1 -- "$@"
    git diff --binary -- "$@"
    git diff --cached --binary -- "$@"
    git ls-files -co --exclude-standard -- "$@" |
      LC_ALL=C sort |
      while IFS= read -r file_path
      do
        if [[ -e "$file_path" ]]; then
          printf 'WORKTREE %s %s\n' \
            "$(git hash-object -- "$file_path")" "$file_path"
        else
          printf 'MISSING %s\n' "$file_path"
        fi
      done
  } > "$output_file"
  shasum -a 256 "$output_file"
}

PROTECTED_SCOPE=(
  lib android ios go-mknoon go-relay-server
  pubspec.yaml pubspec.lock
  test integration_test
  ':(exclude)test/integration/direct_private_media_device_local_journey_criteria_test.dart'
  ':(exclude)integration_test/scripts/direct_private_media_device_local_journey_criteria.dart'
  ':(exclude)integration_test/direct_private_media_device_local_journey_harness.dart'
  ':(exclude)integration_test/scripts/run_direct_private_media_device_local_journey.dart'
  Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-01-plan.md
  Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-02-plan.md
  Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-03-plan.md
  Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-04-plan.md
  Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-05-plan.md
  'Test-Flight-Improv/238-*'
  'Test-Flight-Improv/241-*'
  'Test-Flight-Improv/242-*'
  'Test-Flight-Improv/243-*'
  'Test-Flight-Improv/247-*'
  'Test-Flight-Improv/248-*'
  'Test-Flight-Improv/249-*'
  'Test-Flight-Improv/253-*'
  'Test-Flight-Improv/254-*'
)

snapshot_scope "$S06_EVIDENCE_DIR/protected.before" "${PROTECTED_SCOPE[@]}"
git status --short
flutter devices --machine | tee "$S06_EVIDENCE_DIR/flutter-devices.json"
adb devices -l | tee "$S06_EVIDENCE_DIR/adb-devices.txt"
xcrun simctl list devices available | tee "$S06_EVIDENCE_DIR/ios-devices.txt"
```

At the final scope gate, recapture `protected.after`, compare it byte-for-byte
with `protected.before`, and do not revert a mismatch. Investigate ownership.
If an unrelated writer moved a protected path, wait for that work to settle,
capture a fresh baseline, and rerun every acceptance command invalidated by the
movement. If Session 06 caused the mismatch, the session is out of scope.

## RED-First Proof-Machinery Contract

The first Session-06 change is the pure criteria test. Add the test before the
criteria implementation and run:

```bash
flutter test \
  test/integration/direct_private_media_device_local_journey_criteria_test.dart
```

The accepted RED is a compile/API failure for the absent pure evaluator after
the test file exists. A file-not-found invocation, malformed test, missing
package dependency, device failure, or intentionally failing `expect(false)`
is not causal RED evidence.

The test must define the complete positive evidence fixture and fail-closed
mutants before the evaluator exists. It must reject at least:

- missing, implicit, duplicate, swapped, or wrong-class Android IDs in the
  combined record; live/offline discovery remains a runner responsibility;
- missing physical-sender or emulator-recipient child evidence;
- a mismatched role, child device identity, observation source, schema, or
  generator discriminator;
- a boolean-only or predeclared `passed: true` artifact with no ordered
  observations;
- an absent encrypted-v2 codec observation or any clear outer policy field;
- preview/download ordering that precedes durable parent commit;
- non-generic notification copy, an auto-download call, or an unguarded/manual
  non-canonical download;
- zero or multiple View Once first-raster events, incomplete cleanup, or a
  reopen grant/file after terminalization;
- disappearing post-expiry access or protected repeat-view failure;
- ordinary control failure, private ordinary-viewer/PiP authorization, or
  missing policy application;
- any consume-receipt count or account-wide/relay-authoritative claim;
- forbidden key/value material including fixture plaintext/caption, media
  bytes, MIME/kind, absolute/relative path, size/dimensions/duration, key,
  nonce, policy payload, or lifecycle internals; and
- unknown top-level/observation fields capable of smuggling unreviewed data.

After the RED is recorded, implement only the pure evaluator and the
non-production harness/runner. The same exact test must turn GREEN before any
device command.

## Device-Local Journey Design

### Honest proof profile

The runner proves `device_install_local_app_layer`, not real transport:

- one explicitly selected USB physical Android is the sender role;
- one explicitly selected Android emulator is the recipient role;
- the runner executes the integration harness in a fresh child process on each
  exact ID with explicit role and device-ID `--dart-define`s;
- both roles use one deterministic fixture contract and production
  policy/codec/application/lifecycle/action seams with deterministic in-process
  repositories, file storage, clock, notification spy, and transport adapter;
- correlation is by runner-owned live child processes, exact role/device
  identity, and a strict combined schema, never by a claim that the devices
  exchanged data over relay/network;
- the physical role supplies sender/inner-only/ordinary-control observations;
  the emulator role supplies durable receive, preview/download order,
  lifecycle, action/viewer/PiP, cleanup/reopen, and local-authority
  observations;
- existing host encryption, real SQLCipher, and platform/native proofs remain
  separate required commands and are not replaced by this harness.

The harness must drive setup, permissions needed by the test process,
application calls, lifecycle events, clock movement, reopen, and assertions
programmatically. It must not pause for a tap, ask the user to navigate, use an
iPhone as the recipient, or pass because an operator supplied prose.

### Required live observations

The retained evidence schema is versioned, strict, and redacted. It contains
explicit target IDs/classes/roles, fixed automation/source discriminators,
ordered receive/policy/preview/download ordinals, bounded lifecycle/download
counters, fixed local-only negative claims, and only the generic notification
and quote body. Child success and marker freshness are runner preconditions;
they are not copied into a self-declared retained success field.

The two live child records together must demonstrate:

- an encrypted-v2 private send projection, a present encrypted-inner private
  policy, and zero private-policy fields in the clear outer projection;
- durable current-parent commit ordinal before preview decision and before
  download decision;
- exact generic `Private media` notification output with the forbidden fixture
  marker absent;
- zero automatic download calls;
- exactly one explicit-download qualification plus one canonical app-owned
  file result, without retaining or logging the path; the complete existing
  download suite separately proves the Session-03 guarded transport path;
- one View Once first-frame observation, completed terminal cleanup, no
  attachment after cleanup, and no available grant after simulated reopen;
- one disappearing terminal expiry with no post-expiry availability;
- two protected open decisions with the parent still available afterward;
- an ordinary media control that retains ordinary preview and manual-download
  eligibility;
- the current private policy/action decision applied successfully, including
  the harness's internal egress and typed-PiP denials;
- consume-receipt count zero plus fixed false account-wide and
  relay-authoritative claims. Same-ID group/unresolved preservation and
  backward-clock high-water remain required focused-host evidence rather than
  theatrical device-artifact fields.

### Anti-theatrical runner requirements

`run_direct_private_media_device_local_journey.dart` must:

1. require `--sender <physical-android-id>`,
   `--recipient <android-emulator-id>`, and `--artifact-dir <directory>`;
   there are no implicit or stale device defaults;
2. verify both IDs are distinct and currently online through fresh
   `flutter devices --machine` discovery, require Android, require the sender's
   `emulator=false`, require the recipient's `emulator=true` plus an exact
   `emulator-<port>` ID, and reject a mislabeled target; the preflight retains
   independent `adb devices -l` evidence;
3. refuse an existing final artifact path in the requested directory;
4. start both exact `flutter test ... -d <id>` child commands itself and
   capture stdout/stderr rather than accepting user-supplied JSON;
5. require exactly one bounded base64-JSON marker from each successful child,
   matching role, explicit device ID, and `instrumented_app` source;
6. scan raw child output for fixed fixture-secret sentinels and use the strict
   evaluator's recursive sensitive-field/extra-field rejection on the combined
   artifact before writing anything retained;
7. pass the combined live record through the same pure evaluator covered by the
   host criteria test;
8. write only the strict redacted artifact via an exclusively created,
   fully-flushed same-directory temporary file and atomic no-clobber POSIX
   hard-link publication, print a bounded summary plus SHA-256, and retain no
   raw media/envelope/key/path material; a non-POSIX runner host fails closed;
   and
9. fail non-zero for missing evidence, extra fields, stale files, subprocess
   failure, target churn, redaction failure, or criteria failure. It may never
   synthesize a passing record after a child failure.

The Execution Result must call this proof exactly what it is: deterministic
two-target app-layer evidence. It may not say the physical device sent through
a real relay to the emulator, that recipient consumption converged to the
sender/account, or that bytes were remotely revoked.

## Test And Evidence Contract

| ID | Required behavior | Evidence |
|---|---|---|
| S06-RED-01 | Pure evidence evaluation fails closed before implementation and against every listed mutant | criteria host RED/GREEN |
| S06-DEV-01 | Explicit current physical-Android sender plus Android-emulator recipient, distinct and correctly classified | runner discovery + strict artifact |
| S06-DEV-02 | Encrypted-v2 inner-only private projection is observed without logging policy/plaintext/secrets | sender codec/inner/outer observations |
| S06-DEV-03 | Durable policy precedes preview/download; notification is exactly generic; auto-download stays zero | ordered ordinals + notification/call counters |
| S06-DEV-04 | Available private manual download remains qualified and writes only to canonical app-owned storage; the complete focused suite proves the guarded transport path | live qualification/file result + focused download suite |
| S06-DEV-05 | View Once reveals exactly once, cleans, and does not resurrect on reopen | CAS/raster/terminal/cleanup/reopen counters |
| S06-DEV-06 | Disappearing expiry completes and protected media remains repeat-viewable; backward-clock high-water remains focused-host evidence | expiry and protected-open observations + focused lifecycle/restart tests |
| S06-DEV-07 | Ordinary control remains ordinary; current private policy/action evaluation retains egress/PiP denial | control observations + applied-policy result + focused viewer/action suites |
| S06-DEV-08 | State is explicitly local: no consume receipt and no relay-authoritative/account-wide claim | zero consume counter + fixed false claims + scope guard |
| S06-DB-01 | v99→v100/fresh/reopen/rerun/wrong-password/downgrade SQLCipher behavior remains valid | existing exact Android/iOS proof |
| S06-NATIVE-01 | Android secure ownership and truthful iOS protection/NSE redaction remain valid | existing Kotlin/XCTest/platform proofs |
| S06-REG-01 | New criteria proof is in both 1:1 arrays and every new file has exact gate documentation | registration search + named gates |
| S06-CLOSE-01 | Plan 234 closes without production/native/schema/transport drift or evidence overclaim | manifests + QA + closure review |

The pure criteria negative cases are the Session-06 representative mutation
campaign. Do not mutate accepted production merely to repeat Sessions 01–05
mutation histories.

## Literal Acceptance Gates

Run from the repository root in this order. No failure is pre-authorized.

### 1. RED then proof-machinery GREEN

```bash
# Run once immediately after adding only the criteria test: causal RED.
flutter test \
  test/integration/direct_private_media_device_local_journey_criteria_test.dart

# Run again after implementing the pure evaluator, harness, and runner: GREEN.
flutter test \
  test/integration/direct_private_media_device_local_journey_criteria_test.dart
```

### 2. Policy, codec, model, and v100 host proof

```bash
flutter test \
  test/features/conversation/domain/models/private_media_policy_test.dart \
  test/features/conversation/domain/models/message_payload_test.dart \
  test/features/conversation/domain/models/conversation_message_test.dart \
  test/core/database/helpers/messages_db_helpers_test.dart \
  test/core/database/migrations/100_direct_private_media_lifecycle_test.dart \
  test/core/database/integration/full_migration_chain_test.dart
```

### 3. Compose, ingress, notification, and encryption proof

```bash
flutter test \
  test/features/conversation/presentation/screens/conversation_private_media_composer_test.dart \
  test/features/conversation/application/send_chat_message_use_case_test.dart \
  test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart \
  test/features/conversation/application/chat_message_listener_test.dart \
  test/features/push/application/show_notification_use_case_test.dart \
  test/features/push/application/push_decrypt_preview_test.dart \
  test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart
```

### 4. Lifecycle, cleanup, restart, and fresh complete download proof

```bash
flutter test \
  test/core/database/helpers/messages_db_helpers_private_media_lifecycle_test.dart \
  test/features/conversation/application/consume_private_media_use_case_test.dart \
  test/features/conversation/application/private_media_expiry_scheduler_test.dart \
  test/features/conversation/integration/private_media_restart_replay_test.dart \
  test/features/conversation/application/private_media_cleanup_race_test.dart \
  test/core/lifecycle/private_media_lifecycle_recovery_wiring_test.dart \
  test/core/media/media_storage_manager_test.dart \
  test/features/conversation/application/delete_message_use_case_test.dart

# Mandatory fresh complete suite. An exact-name rerun never replaces this.
flutter test \
  test/features/conversation/application/download_media_use_case_test.dart
```

### 5. Current action, Forward, library, viewer, and PiP-denial proof

```bash
flutter test \
  test/features/conversation/application/private_media_action_eligibility_test.dart \
  test/features/conversation/application/direct_private_media_boundary_test.dart \
  test/features/conversation/application/received_media_action_controller_test.dart \
  test/features/conversation/application/received_media_action_transport_boundary_test.dart \
  test/features/conversation/application/build_received_media_forward_test.dart \
  test/features/conversation/application/direct_media_forward_transport_boundary_test.dart \
  test/features/conversation/application/direct_media_library_batch_actions_test.dart \
  test/features/conversation/application/direct_media_library_batch_delete_test.dart \
  test/features/conversation/application/direct_media_library_boundary_test.dart

flutter test \
  test/core/database/helpers/media_library_db_helpers_test.dart \
  test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart \
  test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart \
  test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart \
  test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart \
  test/features/conversation/presentation/screens/conversation_shared_media_go_to_message_test.dart

flutter test \
  test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart \
  test/core/media/private_media_protection_coordinator_test.dart \
  test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  test/shared/widgets/media/media_viewer_boundary_test.dart
```

### 6. Native unit/NSE and native project proof

Resolve an available iOS simulator ID first. If an iOS simulator is available,
run both exact XCTest suites on it. If none is available, record each leg
exactly as `N/A (target unavailable by project policy)`; do not substitute a
stale ID.

```bash
./android/gradlew -p android app:testDebugUnitTest \
  --tests 'com.mknoon.app.PrivateMediaProtectionNativeTest'
./android/gradlew -p android app:compileDebugKotlin

if [[ -n "$IOS_XCTEST_SIMULATOR_ID" ]]; then
  xcodebuild test \
    -workspace ios/Runner.xcworkspace \
    -scheme Runner \
    -destination "platform=iOS Simulator,id=$IOS_XCTEST_SIMULATOR_ID" \
    CODE_SIGNING_ALLOWED=NO \
    -only-testing:RunnerTests/NotificationPreviewResolverTests
  xcodebuild test \
    -workspace ios/Runner.xcworkspace \
    -scheme Runner \
    -destination "platform=iOS Simulator,id=$IOS_XCTEST_SIMULATOR_ID" \
    CODE_SIGNING_ALLOWED=NO \
    -only-testing:RunnerTests/PrivateMediaProtectionCoordinatorTests
else
  printf '%s\n' \
    'N/A (target unavailable by project policy): iOS NotificationPreviewResolverTests'
  printf '%s\n' \
    'N/A (target unavailable by project policy): iOS PrivateMediaProtectionCoordinatorTests'
fi

xcodebuild -list -workspace ios/Runner.xcworkspace
plutil -lint ios/Runner.xcodeproj/project.pbxproj
```

### 7. Real SQLCipher and platform-protection proof

Select `ANDROID_PROOF_ID` from fresh discovery, preferring the available
physical Android. Select one available iOS simulator for the iOS-specific
proofs. Every command uses an explicit ID.

```bash
if [[ -n "$ANDROID_PROOF_ID" ]]; then
  flutter test \
    integration_test/direct_private_media_lifecycle_sqlcipher_proof_test.dart \
    -d "$ANDROID_PROOF_ID"
  flutter test \
    integration_test/direct_private_media_platform_protection_proof_test.dart \
    -d "$ANDROID_PROOF_ID"
else
  printf '%s\n' \
    'N/A (target unavailable by project policy): Android SQLCipher proof'
  printf '%s\n' \
    'N/A (target unavailable by project policy): Android platform-protection proof'
fi

if [[ -n "$IOS_FLUTTER_DEVICE_ID" ]]; then
  flutter test \
    integration_test/direct_private_media_lifecycle_sqlcipher_proof_test.dart \
    -d "$IOS_FLUTTER_DEVICE_ID"
  flutter test \
    integration_test/direct_private_media_platform_protection_proof_test.dart \
    -d "$IOS_FLUTTER_DEVICE_ID"
else
  printf '%s\n' \
    'N/A (target unavailable by project policy): iOS SQLCipher proof'
  printf '%s\n' \
    'N/A (target unavailable by project policy): iOS platform-protection proof'
fi
```

An assertion/build failure on an available target is blocking and is never
converted to N/A. Native unit success does not replace an applicable Flutter
device proof.

### 8. Automated physical-Android + emulator app-layer journey

The runner must receive IDs from the fresh matrix. With both target classes
available:

```bash
dart run \
  integration_test/scripts/run_direct_private_media_device_local_journey.dart \
  --sender "$ANDROID_PHYSICAL_ID" \
  --recipient "$ANDROID_EMULATOR_ID" \
  --artifact-dir "$S06_EVIDENCE_DIR"

shasum -a 256 \
  "$S06_EVIDENCE_DIR/plan234-direct-private-media-device-local-journey.json"
```

If either target class is unavailable after fresh discovery, record the
paired command exactly as
`N/A (target unavailable by project policy): physical-Android + Android-emulator device-local journey`,
retain the pure host criteria and every applicable single-platform proof, and
do not wait for hardware or substitute an iPhone. Because both classes were
available at planning time, a currently available pair that fails is a
blocker, not N/A.

### 9. Exact registration and named gates

```bash
rg -n \
  'direct_private_media_device_local_journey_criteria_test.dart' \
  scripts/run_test_gates.sh \
  scripts/run_host_test_gates.sh \
  Test-Flight-Improv/test-gate-definitions.md

rg -n \
  'direct_private_media_device_local_journey_(criteria|harness)|run_direct_private_media_device_local_journey' \
  Test-Flight-Improv/test-gate-definitions.md

./scripts/check_reliability_simulation_discovery.sh
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh 1to1 --list
./scripts/run_test_gates.sh completeness-check
```

The host command is discovery-only because of `--list`. Do not remove it and
do not turn it into per-session `host-all`.

### 10. Scoped format, analysis, syntax, diff, and immutable scope

```bash
dart format --output=none --set-exit-if-changed \
  test/integration/direct_private_media_device_local_journey_criteria_test.dart \
  integration_test/scripts/direct_private_media_device_local_journey_criteria.dart \
  integration_test/direct_private_media_device_local_journey_harness.dart \
  integration_test/scripts/run_direct_private_media_device_local_journey.dart

dart analyze \
  test/integration/direct_private_media_device_local_journey_criteria_test.dart \
  integration_test/scripts/direct_private_media_device_local_journey_criteria.dart \
  integration_test/direct_private_media_device_local_journey_harness.dart \
  integration_test/scripts/run_direct_private_media_device_local_journey.dart

bash -n scripts/run_test_gates.sh scripts/run_host_test_gates.sh \
  scripts/check_reliability_simulation_discovery.sh
git diff --check

snapshot_scope "$S06_EVIDENCE_DIR/protected.after" "${PROTECTED_SCOPE[@]}"
cmp "$S06_EVIDENCE_DIR/protected.before" \
  "$S06_EVIDENCE_DIR/protected.after"

git status --short -- \
  test/integration/direct_private_media_device_local_journey_criteria_test.dart \
  integration_test/scripts/direct_private_media_device_local_journey_criteria.dart \
  integration_test/direct_private_media_device_local_journey_harness.dart \
  integration_test/scripts/run_direct_private_media_device_local_journey.dart \
  scripts/run_test_gates.sh \
  scripts/run_host_test_gates.sh \
  scripts/check_reliability_simulation_discovery.sh \
  Test-Flight-Improv/test-gate-definitions.md \
  Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-06-plan.md \
  Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan.md \
  Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-breakdown.md \
  Test-Flight-Improv/00-INDEX.md \
  Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md
```

Record exact current test counts, host inventory count, completeness count,
device IDs/classes, N/A legs, artifact SHA-256, analyzer output, and manifest
SHA-256 values. Do not silently reuse a count from Sessions 01–05 or Plan 247.

## Failure Ledger And Interpretation

Every non-zero required command is entered before any retry:

| ID | Command/phase | Exact signature | Initial classification | Owner | Evidence invalidated | Disposition/final state |
|---|---|---|---|---|---|---|
| _fill during execution_ | | | | | | |

Allowed initial classifications are:

- `causal_red` — only the intended missing pure evaluator/API after the test
  exists;
- `pending_triage` — default for every test, analyzer, native, device, named
  gate, or scope failure;
- `environment_interruption` — proven tooling/network/device-transfer
  interruption with no assertion or source change;
- `N/A (target unavailable by project policy)` — only a whole required target
  class/platform unavailable in the fresh matrix; and
- `production_regression` — executable current behavior violates an accepted
  owner-session contract and Session 06 must stop.

Rules:

- No product/test/native failure is pre-accepted as flaky or known.
- An exact-name rerun may classify a timing symptom, but it never replaces a
  fresh complete required suite. In particular the complete download file must
  pass after any focused rerun.
- An infrastructure interruption is recorded honestly. Resume support may be
  used only where the owning script supports it; partial evidence is not
  described as one uninterrupted pass.
- Any proof-file, registration, or script change invalidates its exact test,
  scoped static checks, named `1to1`, host inventory, completeness, diff, and
  QA evidence.
- Any accepted production-owner repair invalidates the entire Session-06
  baseline and requires a fresh Session-06 run after that owner is reclosed.
- Do not fix failures by weakening criteria, deleting assertions, changing the
  local-only truth profile, synthesizing artifacts, skipping available
  targets, or broadening scope.

## Graphify Contract

- The planning query is sufficient for this test/docs-only session.
- If the final Session-06 delta contains only the four proof files, the two
  gate arrays, reliability-discovery script, gate-definition documentation,
  and closure documents, do not run
  Graphify `affected` and do not run an incremental refresh. Test/docs/script
  registration does not justify an architecture refresh.
- If a concrete regression requires any app-owned production file to change,
  Session 06 stops. The reopened owning session must run:

  ```bash
  python3 graphify-arch/tdd_context.py affected \
    <actual-attributable-production-files...> --budget 600
  ```

  It must then complete fresh independent QA and exactly one post-QA
  `./graphify-arch/refresh_arch_graph.sh --incremental` before reclosure.
- After that owner is accepted, restart Session 06 from a new immutable
  baseline. The resumed tests/docs-only Session 06 still performs no refresh.
- The final Wave-1 architecture refresh remains later Wave-level work. Session
  06 must not consume or duplicate it.

## Independent QA And Bounded Fix Passes

After every literal gate passes, freeze the proof/registration files and hand
fresh independent QA:

- this plan and accepted Sessions 01–05/Plan-247 closure records;
- the immutable before/after protected manifests;
- RED and GREEN output for the pure criteria;
- every focused/native/SQLCipher/platform/named/static result;
- fresh device discovery and selected explicit IDs/classes;
- raw child-output redaction result, strict redacted artifact, and SHA-256;
- the failure ledger, including N/A or interruption classification;
- final diffs and registration evidence; and
- the exact statement that the pair is deterministic app-layer proof only.

QA independently checks:

1. criteria mutants fail for causal reasons and the positive fixture contains
   ordered observations rather than theatrical booleans;
2. the runner cannot accept stale/user-supplied/synthesized artifacts or leak
   forbidden data;
3. the harness actually calls current production seams and does not duplicate
   their decisions in a test-only implementation;
4. local-only, SQLCipher, Android, iOS, notification, ordinary-preservation,
   and no-sibling-mutation claims match the evidence boundary;
5. no production/native/schema/transport/group/announcement/PiP change is
   hidden in the shared dirt;
6. every new proof is registered exactly and current named gates are complete;
   and
7. closure wording makes no relay, remote-consume, account-wide, screenshot-
   proof iOS, unavailable-hardware, or actual-PiP claim.

At most two Session-06 fix passes are permitted. A proof/runner behavior fix
starts with a new failing pure criterion or demonstrated live-run
counterexample and reruns every invalidated gate before fresh QA. A
documentation-only correction must not touch frozen proof/registration files.
Production findings are never repaired inside this pass budget; they trigger
the owner-session stop/reopen rule. If a blocking Session-06 finding remains
after two bounded passes, verdict is `still_open`.

QA acceptance authorizes closure writing, not a Graphify refresh.

## Closure Workflow

Only after fresh independent QA returns `accepted` with no blocker:

1. Add the exact evidence, failure dispositions, live matrix, N/A legs,
   `fix_passes`, proof artifact hash, manifest equality, and final verdict to
   `## Execution Result` in this plan.
2. Change this plan to `Status: accepted` only when every Done Criterion is
   evidenced.
3. Synchronize the Plan-234 source:
   - mark Session 06 accepted and overall Plan 234 accepted/closed;
   - reconcile D-234-01..08 and every source-wide done criterion;
   - record the current focused/native/SQLCipher/device/named/static evidence;
   - retain historical RED/repair chronology while removing only stale
     current-state wording that still calls accepted decisions unresolved; and
   - state explicitly that the accepted guarantee is device/install-local.
4. Synchronize the breakdown:
   - set Session 06 accepted;
   - set the six-session Plan-234 ledger accepted/closed;
   - record no residual, blocker, or hidden follow-up; and
   - preserve Plan 238's sequential v101 ownership.
5. Update `Test-Flight-Improv/00-INDEX.md` to the actual accepted Plan-234
   status and remove stale current wording that says Plan 234 lacks approved
   lifecycle closure.
6. Extend
   `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md` with
   the stable private-media maintenance contract, evidence boundary, exact
   local-only limitations, and reopen triggers.
7. Keep `test-gate-definitions.md` and both executable 1:1 arrays synchronized.
8. Run documentation searches, `git diff --check`, and recapture the immutable
   protected manifest. Closure docs must not change proof/registration or
   production bytes.
9. Obtain a separate read-only Closure Reviewer. The reviewer reconciles every
   criterion, count, device/N/A claim, artifact hash, fix-pass entry, manifest,
   registration, local-only wording, overall Plan-234 status, and downstream
   DB v101 ownership.
10. Permit at most two documentation-only correction passes. Re-review after
    each. Any proof/script/test change restarts affected gates and independent
    QA; any production change invokes the owner-session reopen rule.
11. Add `## Closure Audit` only after the separate reviewer accepts. Do not run
    Graphify refresh for closure-document edits.

Plan 234 is not closed by a green runner alone. It closes only when the fresh
evidence, independent QA, synchronized durable records, and separate Closure
Review all accept with no unresolved Plan-234-owned item.

## Done Criteria

- [x] Sessions 01–05, the Session-02 NSE repair, and Plan 247 remain accepted
      with no concrete regression evidence.
- [x] A current stable dirty-tree baseline and immutable protected manifest are
      recorded without resetting or overwriting unrelated work.
- [x] The pure criteria test is causally RED before its evaluator and GREEN
      afterward; every required fail-closed mutant is covered.
- [x] The four Session-06 proof files are the only new proof machinery and
      contain no duplicated product authority.
- [x] One explicit physical Android plus one explicit Android emulator run
      fully automatically when both are available; unavailable target classes
      use only the approved N/A wording.
- [x] The runner rejects stale, implicit, duplicate, wrong-class,
      boolean-only, synthesized, secret-bearing, or incomplete evidence.
- [x] Live evidence covers encrypted-v2 inner-only send projection,
      policy-before-preview/download, exact generic notification, zero
      auto-download, and guarded canonical manual download.
- [x] Live evidence covers one View Once reveal, cleanup/reopen
      non-resurrection, disappearing expiry, protected repeat viewing,
      ordinary preservation, and private viewer/PiP denial; focused
      lifecycle/restart evidence separately covers backward-clock high-water.
- [x] Live evidence records zero consume receipt and fixed false
      relay-authoritative/account-wide claims; scope evidence confirms no
      Session-06 transport or remote-authority change.
- [x] The runner/artifact is described only as deterministic app-layer,
      device-local proof and never as real relay/cross-device convergence.
- [x] All literal policy/codec/v100, ingress/notification, lifecycle/download,
      action/Forward/library/viewer, and ordinary preservation suites pass on
      current code.
- [x] Full iOS `NotificationPreviewResolverTests`, Android native protection,
      iOS native protection, and native project checks pass or an actually
      unavailable iOS leg is recorded N/A.
- [x] Real SQLCipher and platform-protection proofs pass on explicit applicable
      available Android/iOS targets; an available assertion failure is never
      called N/A.
- [x] The criteria host test is in both 1:1 arrays, all four proof files have
      exact gate-definition records, and reliability discovery classifies the
      runner/support files.
- [x] The user-directed gate exception is recorded without invented evidence:
      `./scripts/run_test_gates.sh 1to1` completed successfully in a different
      session according to the user, but its exact count/log is unavailable and
      was not observed by this QA; no `run_test_gates.sh` command, including
      `completeness-check`, was rerun here. The independently observed
      `./scripts/run_host_test_gates.sh 1to1 --list` inventory is `90`, and the
      exact registration/reliability-discovery checks passed.
- [x] Scoped formatter/analyzer, gate-script syntax, `git diff --check`, and
      immutable scope comparison pass.
- [x] No production/native/schema/v101/group/announcement/Go/relay/actual-PiP,
      excluded-plan, or later-session delta is attributable to Session 06.
- [x] Graphify `affected`/incremental refresh are skipped for the
      tests/docs-only Session-06 delta; the final Wave refresh remains pending.
- [x] Fresh independent QA accepts after the honest bounded `fix_passes` count.
- [x] Source, breakdown, index, closure reference, gate definitions, arrays,
      final Plan-234 verdict, and Plan-238 v101 ownership are synchronized.
- [x] A separate read-only Closure Reviewer accepts with no residual, blocker,
      follow-up, overclaim, or dependency error.

## Arbiter Decision And Stop Rule

- Verdict: `accepted`; independent QA found zero blocking findings. Stable
  closure still requires the separately recorded Closure Audit below.
- Structural blocker: none. The accepted owner sessions and Plan 247 satisfy
  the dependencies.
- This plan authorizes only non-production proof machinery, exact registration,
  acceptance execution, and closure synchronization.
- A production regression stops this session and reopens its owner; unavailable
  hardware is availability-bounded N/A; a failing available target is blocking.
- Full host-all and the final Graphify refresh remain Wave-level work.
- No additional Session-06 proof or production work is authorized. The only
  remaining action is the separate read-only Closure Review and its durable
  audit record.

## Execution Progress

- Execution began on 2026-07-12 against the accepted Sessions 01--05,
  accepted Plan 247, and the accepted bounded Session-02 NSE repair. No
  accepted owner session has been reopened because no production regression
  has been found.
- The evidence root is `/tmp/plan234-s06.20260712`. The protected manifest was
  captured after the original causal evaluator RED and before any
  Session-06-attributable protected-scope edit. Its current byte hash is
  `ddba3605c7206704c831d8749c96760e663b7afde29028ac0c69b7e1dff09551`
  (`1,758,622` bytes). This timing is retained rather than being described as
  a pre-RED snapshot.
- Discovery snapshots were retained with SHA-256 values
  `874183ee9fd279308658c0ba82050fda5f7fc355f21025445322326404484571`
  (`flutter devices --machine`),
  `07244188185e60b69a376dfbdc7bc7a5d427d50d479fb6907898c4dabe6188d8`
  (`adb devices -l`), and
  `171b25d560b811df5150740118c5165277626b40b7291123be2853a5884f0cef`
  (available iOS devices).
- The original criteria test was added before its evaluator and produced the
  intended missing-URI/missing-API compile RED. That output was observed in
  the executor console but was not retained as a separate evidence file; this
  record does not manufacture a retroactive raw log. The implemented criteria
  subsequently passed `59/59` before the first device attempt.
- Fresh host acceptance batches already completed on the current protected
  production snapshot: policy/codec/model/v100 `167/167`,
  compose/ingress/notification/encryption `327/327`,
  lifecycle/cleanup/restart/storage/delete `72/72`, and the mandatory complete
  download suite `68/68`.
- The first automated Android pair used physical sender `21071FDF600CSC` and
  emulator recipient `emulator-5554` and emitted artifact SHA-256
  `334dcc440d7448294c4812648cc50905cbe7d53205ebd74914068a98b809fe5d`.
  Independent plan review rejected that proof as theatrical: its two role
  fixtures were not correlated, persistence/download/cleanup did not traverse
  the claimed real seams, criteria accepted swapped topology and sensitive
  values, and runner hardening was incomplete. The artifact is superseded and
  contributes no closure evidence.
- Session-06 proof repair pass 1 replaced the rejected theatrical seams with
  fixture correlation, real SQLCipher v100 close/reopen, production
  `downloadMedia` plus `MediaFileManager`, production lifecycle cleanup of the
  actual canonical bytes, a second durable reopen, strict role orientation,
  and hardened no-clobber runner behavior. Backward-clock high-water remains
  assigned to focused host evidence; it is not claimed from the device
  artifact.
- The repair criteria produced a causal `58 passed / 7 failed` RED against the
  pre-repair evaluator, including unexpected/missing digest, correlation,
  swapped-role, and sensitive-value failures. Honest protected-observation
  field renaming then produced `63 passed / 2 failed`. The repaired evaluator
  and exact tests pass `65/65`; scoped analysis, format, and diff checks are
  green.
- The hardened runner now refuses stale output before device work, caps each
  encoded marker at 16 KiB, scans non-marker output plus marker-line
  prefix/suffix, revalidates both live target snapshots after the children,
  and publishes through exclusive staging plus an atomic no-clobber POSIX hard
  link. Its scoped analysis, format, help-path compile, and diff checks pass.
  It deliberately fails closed on a non-POSIX host.
- A subsequent adversarial static review found remaining proof-only bypasses:
  USB/ADB provenance was not enforced, three explicit private denial
  observations were absent, sensitive values and rejected-key diagnostics
  could leak, and `LineSplitter` could buffer an unbounded marker line. These
  findings opened repair pass 2; no production file or accepted product gate
  was invalidated.
- Pass 2 produced an exact criteria RED of `62 passed / 22 failed`, then GREEN
  `84/84`. The final schema requires private egress denial, legacy ordinary-
  viewer-entry denial, and typed-PiP denial; covers missing-child,
  boolean-only, reserved-selector, full sensitive-value, and redacted-error
  mutants. The runner now requires attached Flutter targets plus fresh exact
  pre/post `adb devices -l` USB/device provenance, uses 32 KiB per-line and
  4 MiB aggregate byte-level parsing, retains no raw child output, and emits
  only opaque bounded failures. Independent pass-2 re-review found no
  remaining concrete runner blocker.
- The four frozen proof files pass joint scoped formatting, analysis, and diff
  checks. Harness SHA-256 is
  `640f53a2b3655e3f4018a8efdfdf0d963df7ed28e8420227eff04ed12da02a4b`;
  criteria SHA-256 is
  `ca942f89031dafd4a696416c54b96a091e7c2d2e7036040122b2d317d9b600cb`;
  criteria-test SHA-256 is
  `abad4c9dc60e28657e0de2103a16504c8b8c01e47258191af5f165ca2256a991`;
  runner SHA-256 is
  `1fb26b29784b9e09d45320435045901bb8cc13ad6fb72abbde825b38b60b32dd`.
  Independent harness review accepted the real seam usage with no blocker.
  Its bounded interpretation is: zero auto-download covers the driven local
  sequence, protected evidence is two central open decisions rather than two
  rendered sessions, and the zero consume count is command-name based. Host,
  viewer, and native suites retain the broader boundary proof.
- The proof machinery is now frozen at the permitted `fix_passes=2`. A fresh
  replacement Android-pair artifact and all still-pending literal gates must
  pass before independent QA; any further proof blocker yields `still_open`
  under this plan rather than an unrecorded third repair.
- Fresh pass-2 discovery is retained under
  `/tmp/plan234-s06-fix2.xOVLiQ`: Flutter SHA-256
  `417c760b0b462406cd989d022914b5c57c61f13372c938d1cec15958c12bfac4`,
  ADB SHA-256
  `07244188185e60b69a376dfbdc7bc7a5d427d50d479fb6907898c4dabe6188d8`,
  and iOS-availability SHA-256
  `171b25d560b811df5150740118c5165277626b40b7291123be2853a5884f0cef`.
  The selected targets remained USB physical Android `21071FDF600CSC` and
  Android emulator `emulator-5554` before and after the final run.
- The first pass-2 pair attempt correctly failed closed with no artifact when
  the recipient exited 1. Bounded direct triage localized the failure to the
  disappearing terminal claim: the proof fixture used unsupported one-second
  policy input, so production correctly hydrated it as `unsupported` and
  returned zero expiry claims. The harness was corrected to the supported
  3,600-second policy with consistent `1,000 -> 3,601,000 -> 3,601,001`
  received/deadline/sample arithmetic. The exact recipient then passed; the
  final formatted harness received a fresh independent blocker-only review at
  SHA-256 `640f53a2b3655e3f4018a8efdfdf0d963df7ed28e8420227eff04ed12da02a4b`
  and was accepted.
- The final fully automated pair passed from the frozen files. The runner
  accepted 5,101 bounded sender-output bytes / 102 lines and 18,533 bounded
  recipient-output bytes / 171 lines, revalidated Flutter plus ADB topology,
  and atomically published only the strict 2,238-byte artifact at
  `/tmp/plan234-s06-fix2.xOVLiQ/device-final/plan234-direct-private-media-device-local-journey.json`.
  Its SHA-256 is
  `85423546027053fe3d44da0f2cb46660ef997fc02ceda76fa3f9fd6a8dfb6233`.
  Recursive sentinel search is clean. Raw diagnostic child logs and the
  pre-format artifact were removed; only discovery snapshots and the final
  redacted artifact remain in the pass-2 evidence root.
- Fresh current-tree acceptance after unrelated Plan-257 movement passed the
  policy/codec/model/v100 batch `167/167`, ingress/notification/encryption batch
  `332/332`, lifecycle/cleanup/restart/storage/delete batch `72/72`, mandatory
  complete download suite `68/68`, and action/Forward/library/viewer batches
  `31/31`, `68/68`, and `33/33`.
- Native and device evidence passed: Android protection `5/5` plus
  `compileDebugKotlin`; full iOS `NotificationPreviewResolverTests` `30/30`,
  coordinator `4/4`, and project checks; Android SQLCipher `1/1` and platform
  protection `1/1` on physical target `21071FDF600CSC`; iOS SQLCipher `1/1`
  and platform protection `1/1` on simulator
  `674DFFF6-5F38-4235-93F6-AF7FBF86AE65`.
- The final registration and hygiene pass found current 1:1 inventory `90`,
  reliability-discovery inventories `43` 1:1 entrypoints / `35` group / `36`
  support, four proof files format-clean, no scoped analyzer issues, clean
  `bash -n` for the three gate/discovery scripts, and clean `git diff --check`.
  The user expressly directed this continuation not to invoke
  `run_test_gates.sh`; the external `1to1` success is therefore recorded only
  as user-attested, with no invented count/log, and `completeness-check` was
  not rerun here.
- Earlier protected-manifest mismatches were traced to unrelated concurrent
  Plan-257 movement and are not Session-06 fix passes. The final stable pair
  `/tmp/plan234-s06.20260712/protected.final2.before` and
  `/tmp/plan234-s06.20260712/protected.final2.after` is byte-identical
  (`cmp=0`): SHA-256
  `9fa73691afcc5772d083423a46a7def50d1742cf097cce11877f1c7641208a13`,
  `2,069,571` bytes each.
- Fresh independent QA returned `ACCEPTED` with zero blocking findings and
  authorized closure writing. It retained `fix_passes=2`, rejected all credit
  for the theatrical artifact and unsupported one-second disappearing fixture,
  and accepted only the final artifact SHA-256
  `85423546027053fe3d44da0f2cb46660ef997fc02ceda76fa3f9fd6a8dfb6233`.
  The first iOS command that found an available but shut-down simulator ran no
  test; after the same target was booted, both required iOS device proofs
  passed. This is setup history, not an N/A or a passed first attempt.

## Execution Result

Verdict: `accepted`; Plan-234 Session 06 has no production regression, no
unresolved Session-06-owned item, and no hidden implementation follow-up.

- The causal proof evaluator finishes `84/84`, the final physical-Android plus
  Android-emulator artifact is intact at SHA-256
  `85423546027053fe3d44da0f2cb46660ef997fc02ceda76fa3f9fd6a8dfb6233`,
  and all independently observed focused, native, device, registration, static,
  and protected-scope evidence listed above is green.
- The Android pair is deterministic device/install-local app-layer evidence.
  The sender records an encrypted-v2 envelope projection, not live relay
  transport. Protected evidence is two central open decisions, not two rendered
  sessions; zero auto-download covers the driven sequence; consume count is
  bridge-command-name based; and egress/viewer/PiP fields are eligibility
  decisions. It proves no relay/account/global consume, remote revocation,
  cross-install convergence, actual PiP, or screenshot-proof iOS behavior.
- `fix_passes=2`. The rejected theatrical artifact and the unsupported
  one-second disappearing fixture are superseded history with no closure
  credit. Protected scope is byte-identical at SHA-256
  `9fa73691afcc5772d083423a46a7def50d1742cf097cce11877f1c7641208a13`
  (`2,069,571` bytes; `cmp=0`); earlier mismatches were unrelated Plan-257
  movement, not Session-06 repair passes.
- The user-attested external `1to1` success is accepted only as an explicit
  user-directed evidence exception. This QA did not observe it, its exact
  count/log is unavailable, and no `run_test_gates.sh` command was rerun.
- Session 06 added no attributable production, native, schema/v101,
  transport, Go/relay, group, announcement, excluded-plan, or actual-PiP delta.
  Its attributable change is proof/tests/registration/docs only, so Graphify
  `affected` and incremental refresh are intentionally skipped. The final Wave
  refresh remains pending.
- Independent QA: `ACCEPTED`, zero blocking findings. The synchronized durable
  records and separate read-only Closure Review also accepted; the stable
  verdict is recorded in `## Closure Audit`.

## Closure Audit

- Verdict: `closed`; the separate read-only Closure Reviewer returned
  `ACCEPTED` with zero blocking and zero nonblocking findings. All Session-06
  done criteria are satisfied, and Plan 234 has no owned residual, blocker,
  hidden follow-up, or dependency error.
- The reviewer independently reconciled the Session-06 plan, Plan-234 source,
  session breakdown, `00-INDEX`, stable 1:1 closure reference, final artifact,
  evidence limitations, DB ownership, exclusions, and protected manifests.
  `closure_doc_fix_passes=0`; proof `fix_passes=2` remains unchanged.
- The earlier valid execution pair remains
  `/tmp/plan234-s06.20260712/protected.final2.before` / `.after`, SHA-256
  `9fa73691afcc5772d083423a46a7def50d1742cf097cce11877f1c7641208a13`,
  `2,069,571` bytes each, `cmp=0`.
- Concurrent Plan-256/257 proof-file edits later moved the shared protected
  scope. Closure attempts 2, 3, and 4 are superseded moving-scope records, not
  Session-06 repair passes or regressions. After those writers settled, the
  current closure pair
  `/tmp/plan234-s06.20260712/protected.closure5.before` / `.after` is
  byte-identical: SHA-256
  `907c42294072e56a59f81c4fe1a2dd23b51c3bcf67890aa8eb761d238be36562`,
  `2,072,461` bytes each, `cmp=0`.
- The final Android artifact remains bounded device/install-local app-layer
  proof with SHA-256
  `85423546027053fe3d44da0f2cb46660ef997fc02ceda76fa3f9fd6a8dfb6233`.
  It proves none of live relay transport, account/global consume, remote
  revocation, cross-install convergence, two rendered protected sessions,
  actual PiP, or screenshot-proof iOS behavior.
- The external `1to1` success remains user-attested evidence with unavailable
  exact count/log and was not observed by QA. The user's instruction not to
  invoke `run_test_gates.sh` was honored; no result or count was invented.
- No production/native/schema/v101/transport/Go/relay/group/announcement/
  actual-PiP delta is attributable to Session 06. Its tests/proof/docs-only
  delta required no Graphify `affected` or incremental refresh. Full
  `host-all` and the final Graphify refresh remain final included-Wave-1 work.
- Plan 234 exclusively retains landed DB v100 and is accepted/closed. Plan 238
  is now unblocked and exclusively retains sequential DB v101. Plans 242, 243,
  248, 254, 241, and 253 remain excluded and are not dependencies.
