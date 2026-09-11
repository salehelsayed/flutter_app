# Mknoon regression checks and testing knowledge

Last reviewed: 2026-09-11 against `f1761aa17e782283f734200f969a9622f3f837ce`
plus the explicitly recorded local workflow changes. This file records verified
testing lessons and limitations. It is not a release approval or a run ledger.

## Current architecture and build boundary

The current application uses Flutter with native Go, not the earlier QuickJS
core. `lib/app/bootstrap/production_application_bootstrap.dart:5296` constructs `GoBridgeClient` over method/event
channels. Android's `android/app/build.gradle.kts:431` connects `buildGoAar` to
`preBuild`; `ios/Podfile:63` ensures the GoMknoon/NSE frameworks. `pubspec.yaml`
currently declares `1.0.1+117`, and its bundled asset entries contain icons,
JPEGs and MP4s; no JavaScript asset or QuickJS dependency was found in the
current pubspec/lockfile. Keep JavaScript test/tooling discovery and bundle
identity handling because retained tooling and future bundled assets can still
change; do not assume the old runtime architecture is active.

The existing App Store artifact entry point is
`scripts/build_ios_appstore_ipa.sh --build-number=117`; it applies
`tool/build/voice_call_release_defines.json`. This implementation did not build
or distribute an IPA. Candidate evidence must bind the actual selected build
configuration and signed artifact, not just the Dart revision or version label.

## Sources of truth

- `tool/testing/selection.json` owns check selectors, requirements, timeouts,
  affected-area mappings, and mandatory membership. Edit executable mappings
  there; do not maintain a second selection list in this document or skills.
- `python3 scripts/mknoon_checks.py discover` generates the inventory from the
  existing runners/files. Its output distinguishes file/suite discovery from
  runner-reported test cases. Discovery does not establish assertion coverage.
- `scripts/run_test_gates.sh`, `scripts/run_host_test_gates.sh`, and
  `scripts/run_flutter_full_regression.sh` retain their existing gate/full-runner
  responsibilities. The wrapper adds deterministic change/release selection and
  evidence checks; it does not replace Flutter, Go, native, or JavaScript runners.
- Wrapper reports default to ignored `.codex-test-logs/checks-*/` directories;
  use that ignored directory for raw runs; arbitrary `artifacts/` paths are not automatically ignored. Legacy
  full runs retain `.full_regression_logs/`. Keep tokens, keys, personal data, and private
  message content out of shared reports. Use synthetic fixture content.
- `docs/**/*.md` is already indexed by `codex-memory/config.json`. No new memory
  database or service is required. Read this file before selecting tests; use
  Codex document recall for focused prior decisions and targeted source searches
  for code impact in Codex. Claude's separate navigation configuration is unchanged.

Codex's Graphify integration was removed on 2026-09-11. Document-memory
advisories use source searches for code questions, checkpoints accept absent
legacy graph metadata, and every document-memory experiment profile keeps the
retired Codex graph gates off. The `codex-tooling` selection runs the host
contracts for this boundary. Historical graph telemetry remains readable;
Claude's graph tooling and generated graphs remain installed. An already
running Codex session may retain previously loaded agent/skill instructions
until a new session starts.
Verified evidence: `.codex-test-logs/codex-graphify-removal-checks/results.json`
records 247 passing Codex host tests plus passing fast/workflow/schema checks.
Python check selectors must enumerate files: wildcard expansion is implemented
for Flutter selectors, while the Python runner forwards paths to `unittest`.

## Daily commands

Run from the repository root. `BASE_REF` must name the verified intended
comparison revision. For a pull request, resolve the merge base against its
actual target branch; do not assume the previous commit is the baseline.

```bash
python3 scripts/mknoon_checks.py discover --list-runners
python3 scripts/mknoon_checks.py validate
python3 scripts/mknoon_checks.py plan --mode change --base "$BASE_REF" --local
python3 scripts/mknoon_checks.py run --mode change --base "$BASE_REF" --local
```

`--local` includes staged, unstaged, and untracked changes as well as the committed
comparison. Review both sides of renames/deletions. Omit it only for a clean
committed candidate. Plans report selection reasons, unmapped impact, requirements,
and unknown runtimes. An unmapped behavior change widens checks and remains a
visible gap; unknown does not mean safe.

For a release, resolve `PUBLISHED_REF` from the actual distribution record for
the previous published build. An operator-provided reference is an attestation
that it identifies that build; a newest tag alone is not verification.

```bash
python3 scripts/mknoon_checks.py validate
python3 scripts/mknoon_checks.py plan --mode release --base "$PUBLISHED_REF"
python3 scripts/mknoon_checks.py run --mode release --base "$PUBLISHED_REF" --device-config "$DEVICE_CONFIG"
```

The release selection always retains mandatory checks, including on a
documentation-only diff. Required manual/device evidence is additional work;
passing automated checks alone does not complete release acceptance. Supply
reviewed evidence and the exact distribution artifact with
`--evidence "$EVIDENCE_FILE" --candidate-artifact "$CANDIDATE_ARTIFACT"`.
Repeat `--candidate-artifact` for multiple signed platform artifacts; the optional
`--build-label '1.0.1(117)'` records an intended version, not proof of its contents.
Never use real user conversations, production identities, or production service
credentials for these checks.

The initial routine release target is approximately 20–40 minutes, including
build/setup and tests. Current unknown runtimes remain unknown until measured.
Do not omit essential or high-risk checks to meet the target. Broad affected
directories can legitimately take longer; optimize from measured reports.

An executable run writes `plan.json`, `results.json`, and `summary.txt` in its
new ignored artifact directory (or the explicit `--output` directory). Invalid
plans/prerequisites write `error.json`; discovery writes `inventory.json`.
Keep the files for a run together.
Results separate selected paths, actual completed counts, skips, commands,
duration, exit status, first attempt and diagnostic rerun. Flutter reports its
observed test-event span separately from SDK startup/compilation/shutdown time;
verified SIMS reports supply build durations. Unexecuted builds remain unknown. `PASS`, `FAIL`,
`BLOCKED`, and `NOT RUN` differ; non-success results have nonzero exit codes.
`--only bootstrap,contacts` is a diagnostic subset: omitted selected requirements
stay NOT RUN and cannot produce an overall green result. `--rerun-failed` permits
one diagnostic rerun and preserves the original failure. Shared reports retain
allowlisted completion facts and raw-output hashes, not arbitrary private logs;
use existing redacted AppDiagnostics/SIMS receipts for product checkpoints.

## Device configuration and evidence

Keep `DEVICE_CONFIG` in an ignored local artifact path. It is an operator
attestation of isolated fixtures, accounts and services, with live discovered
IDs; it must never contain tokens or production credentials. Example structure
(replace the example IDs and fixture reference with actual isolated setup):

```json
{
  "isolated_test_environment": true,
  "fixture_reference": "artifacts/release-fixtures/setup-receipt.json",
  "devices": {
    "android_physical": "discovered-usb-id",
    "android_emulator": "discovered-emulator-id"
  }
}
```

Add `ios_simulator` or `ios_physical` only for applicable available platform
checks. `python3 scripts/mknoon_checks.py devices` records discovery; the raw
platform commands in the signed checklist remain useful for setup.

The evidence JSON uses `baseline` equal to the resolved baseline in the current
plan, `source_sha256` and `rules_sha256` from that plan's `identity`, an
`artifact_sha256` mapping of each signed artifact basename
to SHA-256, and `checks` keyed by the manifest's manual check ID. Each check
record contains `status` (`PASS`, `FAIL`, or `BLOCKED`), `reviewer`, `observed_at`,
`assertions_observed` (the exact assertion IDs from the selected check), and
`receipts` containing `{ "path": "artifacts/...", "sha256": "..." }`.
An early manual failure may record `failed_assertion` naming a required assertion
and a receipt without inventing results for the subsequent assertions. A PASS
still requires all required assertion IDs. Use
`shasum -a 256 "$CANDIDATE_ARTIFACT"` and the same command for each receipt
to calculate hashes. The wrapper verifies identity, required assertion IDs and
receipt bytes; it does not independently interpret a screenshot or establish
that an operator's attestation is true. Retain the reviewed original receipts.
Do not fabricate evidence merely to fill the schema.

## Full regression and CI

Preview without running the long suite, then run only when explicitly intended:

```bash
python3 scripts/mknoon_checks.py full --plan
python3 scripts/mknoon_checks.py full --base "$BASE_REF" --device-config "$DEVICE_CONFIG"
```

Use a clean isolated checkout; add `--local` only for an intentionally recorded
working-tree candidate. Existing full entry points remain intact. The wrapper
serializes their configured commands and retains one source identity. Never
merge green partitions from different commits into a full-suite PASS. Keep
failed or unfinished full runs visible to release reviewers. Full regression
is not the default after each small change or individual TDD plan; follow the
wave/release cadence in `AGENTS.md`.

`.github/workflows/mknoon-checks.yml` configures a hosted metadata job and the
same wrapper for change/release checks and serialized weekly full execution.
Test execution is opt-in through `MKNOON_TEST_RUNNER_ENABLED` and requires an
appropriately isolated self-hosted runner carrying the `mknoon-test` label,
device/service setup, and release-baseline inputs. Full jobs disable active-run
cancellation and allow 4,320 minutes (three days). An unfinished campaign remains
BLOCKED; if measurement exceeds that bound, implement tracked partitions at one
revision before claiming the cadence can complete. A committed workflow file
does not prove the schedule is active or that branch protection requires it.
No actual remote CI run, schedule activation, or merge-blocking rule has been
verified by this implementation. Do not publish or change remote repository
settings without explicit authorization.

## What the inspected checks establish

The manifest labels inspected checks separately from discovered directory
selections and records limitations alongside every proposed release check.
Representative assertions were inspected; the entire inventory was not audited.

| Boundary | Verified assertion scope | Remaining device/artifact proof |
| --- | --- | --- |
| Bootstrap/returning identity | Phase order, error propagation, identity routing and awaited direct/group recovery | Actual launch, secure storage, preserved contacts/groups/history |
| Contact and direct chat | Mutual contact rows without reciprocal loop; received content, status, order, duplicate counts in both directions | Real QR/camera, real crypto/transport path, disk persistence after restart |
| Offline/group | Fake inbox drain/deduplication; selected three-member fanout, truthful sent state, route-away persistence and fallback recovery | Physical disconnection, live group offline catch-up and path evidence |
| Media | Transformed ciphertext differs; receiver file bytes equal original; separate widget test opens typed received-media viewer | Received transfer and native decode/open in the same real peer journey |
| Notifications | Foreground/background policy and warm/cold payload route callbacks | OS tray/effect, muted conversation, real tap navigation and platform background limits |
| Migration | Real host SQLite FFI schema/data preservation and post-migration writes | Actual previous-published signed build upgraded in place with native secure storage |
| Bridge/call | Dart method/event channel contracts and signaling/mailbox convergence | Native binding, actual bidirectional audible audio and end-call cleanup |

Exact selectors and paths are in the manifest. Useful assertion anchors include
`two_user_message_exchange_test.dart` (bidirectional exchange),
`one_to_one_media_encryption_round_trip_test.dart` (receiver byte equality),
`conversation_received_media_actions_test.dart` (typed viewer opening), and
`full_migration_chain_test.dart` (seeded data preservation). The legacy media
envelope fixture proves a format fixture, not communication with an old binary.

Initial static discovery found 1,959 candidate test files across Flutter
host/device, Go modules, Python unittest, shell contracts, Node JavaScript, JVM
JUnit, Android instrumentation, XCTest and XCTest UI. A further 343 files were
classified as helpers/fixtures/generated support rather than test files. These
are a dated discovery snapshot; use the generated inventory for current counts.
The existing host runner listed 1,496 planned items, SIMS listed 32 capabilities,
and its contracts runner listed 54 command groups. The completeness gate
classified 1,583/1,583 Dart test files. None is an actual test-case count.
The legacy full script's “95-case” label refers to runner items, some containing
whole suites. Generated/parameterized counts must come from runner output;
do not count `test(...)` strings as executions. Runner listings took about
1.55s, 0.51s and 0.02s respectively and executed no assertions.

## Shared dependency lessons

- Bridge/event and transport/lifecycle changes affect direct messages, groups,
  media, notification consumers, and calls. A bridge-only unit test cannot
  establish that these consumers still behave correctly.
- Identity/contact/key authority and storage/migration state feed all peer
  communication and restart recovery. Select dependent feature checks as well
  as the changed subsystem's tests.
- Notification visibility, mute, canonical read state and tap routing cross
  conversation/group boundaries. Foreground fake-policy tests and native final
  effect tests establish different facts and must not be substituted for each
  other.
- A media delivery receipt does not prove receiver bytes can be opened. Preserve
  both receiver-byte and viewer tests and require their real-device conjunction
  for a signed release.
- Test helpers, runner configuration, dependencies, native permissions/build
  configuration, bundled assets and selector changes can affect consumers far
  beyond nearby tests. Keep conservative mappings until evidence supports
  narrower impact.

## Signed-candidate checklist

Use isolated accounts and disposable fixture data on discovered targets. Run
`flutter devices --machine`, `adb devices`, and, when relevant,
`xcrun simctl list devices available`; pin every command to the returned IDs.
The default non-iOS-specific two-peer topology is a USB Android phone plus an
available Android emulator. Use available iOS targets for iOS boundaries or an
explicit Android/iOS parity claim. An unavailable OS/model-specific optional
leg is `N/A (target unavailable by project policy)`; do not invent a required
hardware matrix. Essential journey evidence still needs an available topology.

Record signed artifact hash/build number, source/configuration and bundled
JavaScript identities, distribution-record baseline, target IDs/OS versions,
isolated service configuration, observed results and redacted evidence paths.
Use the manifest's required evidence IDs when recording the following journeys:

1. Launch with existing identity; verify contacts, groups, and history. Add a
   contact through the supported QR flow and start a conversation.
2. Exchange distinct synthetic content in both directions; verify received
   content, truthful state, no duplicates, then reopen and verify persistence.
   Exercise representative direct and relay/inbox paths and record the actual
   observed path; fallback cannot prove the requested path.
3. Send to a small group; disconnect one member and verify that member catches
   up without missing/duplicate content after reconnecting.
4. Transfer representative media and have the recipient open/play the received
   file. Record the content identity/open outcome, not only a delivery badge.
5. Verify background notification, tap to the intended conversation, foreground
   behavior, and a muted conversation on applicable candidate platforms.
   On iOS, correlate notification lock ownership with background/suspension
   and resume, and preserve the existing-installation notification ledger.
   An unidentified suspension lock remains an open release investigation.
6. Interrupt connectivity during a pending send, reconnect, and verify recovery,
   final state, content and duplicate counts.
7. Install the actual previous published build with fixture data, upgrade in
   place to the signed candidate, and verify retained data. Separately exchange
   messages between old-build and new-build peers in both directions.
8. When audio calling is included, connect, verify audible audio in both
   directions, end the call, and verify both endpoints leave the call.
   Include a cold VoIP wake while capability is disabled and queued/coalesced
   pushes; verify each required CallKit report completes. A retained PushKit
   receiver and fake provider tests do not alone certify the OS boundary.

Source/configuration/bundle/artifact changes invalidate prior candidate evidence.
Host-source tests never certify an untested signed artifact. Missing evidence is
incomplete; a failed first attempt followed by a passing diagnostic rerun remains
visible and cannot become an ordinary first-attempt PASS.

## Diagnostics and confirmed lessons

- **Voice-upload incident boundary:** a 2026-09-10 iPhone incident showed
  “Uploading media” from about 18:56 until 19:10 Berlin. The relay received only
  131,072 of 670,610 bytes before a stream reset; the phone then disconnected
  for 10m43s and retried after the user returned to the app. The retry completed
  in 322ms, followed by relay message storage in about 114ms. This establishes
  failed transfer plus delayed client retry, not a long relay delivery queue.
  The user observed the initial stall before leaving the app. Generic iOS
  `operation=other` bridge failures do not identify its precise cause, and the
  displayed upload label does not prove transfer liveness. Preserve event
  occurrence versus later diagnostic receipt timestamps, and distinguish relay
  storage/push success from recipient acknowledgment. Read-only evidence and
  remaining attribution limits are under ignored
  `.codex-test-logs/voice-upload-delay-20260910-1856/report.md`.
- **Voice-upload stall recovery:** an idle timer around local file reads
  cannot interrupt a blocked network write or final receipt. Upload streams
  now apply the 10-second idle budget to network reads/writes, including
  READY and same-relay custody probes, while retaining the absolute ceiling
  and phase-aware custody rules. Local libp2p stall tests first reproduced
  the missing deadline, then verified complete byte-identical retry and
  same-relay duplicate-proof recovery; race checks also pass. A foreground
  voice failure releases its lease and composer activity before requesting
  one debounced media retry through the existing connectivity/lease checks.
  It adds no idle polling and does not bypass stored retry limits. Pending
  attachment metadata alone renders a waiting label/icon; completed uploads
  waiting for message delivery do not claim upload activity. Widget tests
  cover queued and thrown voice sends, retained recordings, and cleared
  activity. These source fixes do not identify the original network reset
  cause or certify an installed iPhone build. Red/green evidence is retained
  under `.codex-test-logs/voice-upload-delay-20260910-1856/`.
- **Upload feature parity:** the same native upload stream serves direct and
  group photo/video/GIF/voice attachments, posts/pass-along, and group avatars;
  profile pictures use `profile_upload`, which has the same network idle guard.
  The follow-up audit reproduced missing foreground retry hints for retained
  direct photos and group media, plus a group voice projection exception that
  left the composer busy. All retained direct-media branches now request retry
  after releasing their leases. Group media does likewise, with a separate
  debounced hint that preserves network-restored priority, account/connectivity
  checks, and the group recovery gate. Each hint causes one pass; automatic
  failure does not create a new hint or an idle polling loop. Group voice
  cleanup also clears activity after exceptions without deleting the recording
  or touching a newly bound conversation. These host regressions establish
  source behavior; they do not certify a signed iPhone build. Audit evidence
  is under `.codex-test-logs/upload-feature-audit-20260910/`.
  Group pending-card tests must expect the waiting label without active upload
  progress. The background-task unmount fixture must await the native begin
  signal after durable file work; a fixed real-time delay followed only by
  fake-time widget pumps does not establish that boundary. Preserve initial
  broad-run failures when recording diagnostic or corrected-file reruns.
- **Relay payload coverage:** the obsolete empty top-level-notification
  placeholder was retired only after the five existing chat builder tests all
  rejected an injected top-level notification. Existing reaction serialization
  controls remain. The restored final payload selection passes on Go 1.25.0;
  this proves payload construction, not live FCM/APNs delivery. Private mutation
  and restoration evidence is in the crash investigation's
  `release-followup-20260911/go-relay-review/`.
- **Go failure evidence:** the check wrapper retains hashes of the package,
  full test name and top-level test name, including dynamic subtests, without
  copying raw labels or logs. Use `go list` and `go test -list` with the same
  canonical digest to identify a focused rerun. Package-only process failure
  is not invented as a failed test. The original build-118 broad run predates
  this capture and retains only its failed count/output hash; later diagnostic
  failures must not be silently attributed to that unnamed first failure.

- **TestFlight termination evidence:** the four reports investigated in
  [the 2026-09-10 record](testflight-crashes-2026-09-10.md) contain one
  `0xbaadca11` call-report enforcement termination and three `0xdead10cc`
  suspension-with-lock terminations. Allocator, regexp and GC frames in these
  SIGKILL snapshots are not proof of memory corruption or an engine defect.
  The committed PushKit receiver-retention correction is verified in matching
  distributed 115 and 117 binaries; 115 is the earliest established inclusion.
  The notification coordination lock can still span awaited work. Its existing
  same-isolate contention queue addresses a different condition and must not
  be claimed as a suspension fix. R4's ledger stack supports a probable owner;
  R2/R3 do not identify the locked file. Keep candidate background/CallKit
  evidence incomplete until the manifest's added iOS assertions are observed.
  Scoped iOS background admission now encloses notification BSD locks, rejects
  refused/already-expired grants before action admission. On normal completion,
  Dart ends the assertion after unlock/close; native expiration may end it while
  admitted work remains pending. Existing direct-outbox retry preserves work
  refused admission.
  Native registry tests and three physical iPhone 13/iOS 26.5 Release AOT
  private-container transactions passed with an existing record preserved.
  A controlled 70-second owner outlived its grant at 27.68 seconds and remained
  held through suspension; resume preserved the record. This is a demonstrated
  limit, not a complete `0xdead10cc` fix or signed App Group/NSE proof. Protect
  admission/error/cleanup order with the mandatory notification-lock check and
  native `GoBridgeCriticalTaskTests`; retain expiration and signed-candidate
  evidence separately. Bounded snapshots add local lifecycle/owner-count
  evidence. Counts exclude
  acquisitions before observation/consent, other isolates and native/SQLite
  owners. Uploads use the previous closed-schema aggregate shape while local
  exports retain the new operation/lifecycle fields, so an older receiver does
  not reject an ordinary mixed batch. Inspect the local export for attribution.
  Four real `CXProvider` component runs (two foreground/two background) also
  preserve per-report completion ordering and terminal cleanup; these are
  separate from unexecuted live PushKit delivery. Six real notification-registry
  operations preserve seeded rows and bracket actual UN publication/removal
  with lock ownership and unlock-before-lease-end. These private-container
  component runs do not establish App Group/NSE or expiration safety.
- **Historical native badge ownership:** six supplemental iPhone reports sample
  a badge writer waiting in `flock`; a waiter does not identify the held file's
  owner. The old writer retained its descriptor through the asynchronous badge
  callback and could block the serial queue needed to release it. Commit
  `a9ec8e12d` releases the descriptor after synchronous submission and preserves
  bounded revision repair. This exact condition fails two existing native tests
  on the historical implementation and passes all seven on the current one;
  matching binary disassembly verifies inclusion in distributed 115/117,
  earliest established 115. Keep those seven methods in the existing
  `run_ios_nse_native_373.sh` selection. This does not prove that synchronous
  badge/state I/O cannot outlive background execution. Private causal evidence:
  crash investigation `remaining-20260911/native-badge-writer/`.
- **Debug crash provenance:** supplemental 107/110 reports match the Flutter
  3.41.4 debug engine, including distinct debug dylibs sharing build 110.
  Matched binary instructions establish allocation-failure aborts in two
  compiler incidents and rejected execution of the generated JIT capability
  probe in one signing incident. They do not establish a leak, jetsam, bad
  application signing, or an upstream fixing version. Eight anonymous executable
  page faults remain unresolved; native dSYMs do not identify their generated
  Dart functions. A retained Release/AOT configuration establishes a different
  execution mode, not a general memory-safety verdict. Keep these separate from
  the supplied TestFlight suspension reports and retain exact UUID matching.
- **Native visibility read admission:** Runner's shared visibility file lock is
  separate from the Dart notification ledger. Its read now holds an existing
  native background assertion and checks liveness after coordinator queue
  admission and again after acquiring the file lock, before reading state.
  A refused read returns unavailable and clears Dart suppression authority;
  it must not skip lifecycle writes or change NSE read behavior. Six native
  behavior regressions join the two existing privacy/lifecycle tests in
  `run_app_visibility_native_371.sh`; they exercise real flock ownership,
  controlled queue/file contention, retained entered-operation ownership and
  unchanged incumbent/future-schema data. The MethodChannel authority regression
  protects null-read notification policy. The visibility suite passes eight
  tests without Go; the combined real-module registry/visibility suite passes
  20, and focused Dart tests pass 12. An optimized, debugger-free iPhone 11
  component also passes foreground/background/resume reads with the real UIKit
  registry, actual flock ordering and seeded bytes preserved. Pre-change and
  queue-only failures remain in `remaining-20260911/visibility-review/`; the
  physical receipt is in `visibility-physical/`. This private-container proof
  does not certify App Group/NSE or a signed candidate. Already-entered I/O may
  still outlive expiration; admission protection is not complete suspension
  safety.
  New build retention stores
  exact IPA/archive/dSYMs, input hashes, filtered binary patches and untracked
  source archives. Excluded credential/configuration inputs remain hash-only;
  older captures and compilation-time transient changes remain explicit gaps.
  Keep source and distribution evidence separate even when labels agree.

- **Android reconnect harness admission:** `am start -W` can return exit zero
  with `Status: timeout` while Flutter is still completing first-run migrations.
  The reconnect runner accepts that status only with the requested component,
  no launch error and a live PID, then retains its bounded identity-readiness
  check. The old launcher failed before the device journey; the corrected
  phone/emulator campaign passed queued-message drain and reconnection checks.
  Keep the exact host contract and real device proof separate, and retain
  initial failures when a harness correction enables a subsequent pass.

- **Group media proof schema:** endpoint admission, Android receipts, shared
  criteria and iOS boundary validation must require exactly
  `currentIdentityDatabaseVersion`. Literal schema 104 checks rejected the
  current schema 118; actual phone/emulator PRAGMA receipts confirmed 118 after
  the correction. Tests accept the current schema and reject obsolete/future
  versions while preserving cipher, role and path checks. Passing this setup
  boundary is separate from successful media transfer. The subsequent P269
  control proved a distinct-device fixture with no signed creation/genesis/
  completion rows; the production authority resolver correctly refused it.
  Do not fabricate proof rows or weaken authority admission to turn that
  fixture green. Authenticated linked-bootstrap media proof is a separate leg.
  The pinned libp2p 0.39.1 client filters private-IP relay addresses before
  circuit advertisement; a warm connection alone does not establish readiness.
  A DNS4 name verified to resolve to the same local fixture on both devices
  restores the unchanged circuit-readiness assertion. Keep its local-network
  scope explicit. The shared linked-device harness also requires the four
  strict-reaction staging/ownership/terminalization callbacks already wired in
  production, and must pass its group message repository to strict REMOVE.
  Missing dependencies produced `unauthorizedSenderKey` and `notMember` in the
  device fixture. Real SQLite tests now exercise that fixture's constructor;
  authorization checks and all reaction assertions remain intact.

- **Group media proof authority modes:** the retained distinct-primary P269
  setup declared an initialized device identity without authenticated linked
  bootstrap. That fixture is not evidence of a production authorization defect.
  The explicit Android `accountBoundLegacy` proof mode now uses normal node
  startup and the existing create/invite/accept use cases. Account and transport
  IDs must match within each ordinary primary, and the two accounts must differ.
  The default remains `distinctAccountAndTransport`; iOS keeps that mode. Build,
  endpoint, runner and artifact declarations must agree. Absent legacy mode is
  compatible only with the default; null, malformed, mismatched and old-APK
  receipts are refused. Real SQLCipher/schema, media/render, ACL, retry and reset
  assertions remain required. Host fixture tests do not certify native crypto.
  The separate linked-group B1b pass covers its actual linked bootstrap scope.
  The invite-accept wiring sentinel checks both branches: legacy mode omits
  device/transport/key-package IDs, while distinct mode supplies the complete
  tuple; both retain the account and ML-KEM material. Its former unconditional
  tuple assertion rejected the intentional legacy branch. Preserve these
  authority checks when changing the proof composition.

- **Strict forwarded-media fixture consistency:** prepared group-media staging
  writes its parent and attachments into the same database. Pairing it with an
  unrelated in-memory message repository hides that durable parent and omits
  strict prepared-content capability, so a refused send can invoke new-message
  rollback. A queued presentation result alone does not prove dispatch. The
  strict forwarding regression must use the real group-message repository over
  the media fixture database and its secure-key/lifecycle scope, and assert
  actual dispatch plus retained attachment/custody and forward provenance.

- **Bootstrap fingerprint review:** DTR-18 is a structural ownership contract,
  not a runtime crash test. The secure-key scope and direct/group retry bindings
  add dependencies at the existing app bootstrap; they do not move an owner.
  Rebaseline the two bootstrap fingerprints only after checking the exact diff
  and reconstructing the old identities. Keep the notification callback count,
  URI rewrites, import sets and relocation assertions intact. The September 11
  review demonstrates three stale-fingerprint failures and a four-test pass;
  behavior remains covered by the separate startup and media tests.

- **Linked-group terminal verdict capture:** Flutter may uninstall a completed
  endpoint before the host retains its app-private verdict. Both B1b roles now
  opt into the existing group multi-party capture handshake. Publish the linked
  completion signal before waiting, because the sibling needs it to finish.
  Capture both original verdicts, synchronize held roles, stop the broker, then
  deliver target-only capture acknowledgements. An acknowledgement attests
  captured bytes, never application success. Controlled tests cover immediate
  uninstall, dependent sibling completion, captured false verdicts and refusal
  to acknowledge missing/conflicting capture. Keep the original application
  criteria and completion deadline. The existing launch-spec suite is included
  in `group-harness-contract`; native device evidence remains separate.

- **Strict group media waveform canonicalization:** an ordinary image has a
  nullable attachment waveform, while its protected manifest canonicalizes
  absence to an empty list. Comparing these with the generic null-sensitive
  waveform predicate rejected a valid image as
  `strict_group_media_manifest_mismatch` on the Android phone/emulator pair.
  Normalize absence only at this local attachment-to-manifest boundary. Leave
  signed bytes/hash checks, nonempty sample equality and durable-row equality
  unchanged. The existing send-use-case suite protects absent/empty image,
  matching voice, different samples, missing committed samples and uncommitted
  samples; its absent-image case fails before the correction. This is a
  separate feature-preservation defect, not an established iOS crash cause.
  The mandatory `strict-group-media-manifest` check pairs those cases with the
  existing TC-365-02a upload descriptor sentinel. Its fixture/host limits stay
  separate from native device custody and ACK evidence.

- **Strict group media secure-key ownership:** SQL stores a canonical secure
  key reference while the signed media commitment contains the resolved key.
  Raw string comparison rejects valid persisted media. Resolve exact canonical
  references before entering SQLite, under the existing media lifecycle lock's
  exclusive scope, and hold ownership through commit or rollback. The immutable
  proof is bound to its database, attachment, message and reference and becomes
  unusable when its callback ends. Never persist the resolved key as a repair.
  Canonical absence also admits either SQL null or an empty waveform array;
  changed nonempty samples remain invalid. Twenty-four existing real-database
  fixture cases cover legacy and secure rows, reopened data, recipient shrink,
  completion, malformed references, key-read failure, stale/cross-database
  proofs and actual key-mutation exclusion. Removing ownership permits the key
  to change during SQL in the controlled RED test. Foreground and headless
  compositions pass this scope explicitly; protected reconciliation obtains it
  before the page transaction and releases it after commit or rollback.
  TC-364-03a protects that page boundary and exact ACK ordering. These cases
  join `strict-group-media-manifest`; the existing repository and recovery
  suites form `group-media-storage-preservation`. Fake secure storage and host
  SQLite do not establish native keychain or iOS suspension safety. This is a
  separate confirmed storage defect, not an attributed TestFlight crash cause.

- **Incoming group key representations and ACK:** protected receive inserts
  its attachment projection directly, so existing incoming rows can contain
  the legacy key value inside encrypted SQL. Outbound staging's canonical
  secure-reference expectation must not be applied unconditionally to those
  rows. Under the existing attachment lock, the two incoming-group commit and
  local-deletion callbacks now verify the actual stored representation before
  SQL: exact legacy equality, or canonical per-attachment reference plus exact
  secure-store value. Only the proven key field changes in the expected map;
  stale nonce, size, hash, waveform, owner, message, fingerprint and custody
  still refuse promotion. Key-read failure propagates and releases ownership.
  Keyless local deletion remains valid because it does not decrypt. The
  existing real-database download and deletion tests now cover both persisted
  key representations; deletion also retains its keyless case. Reopened legacy
  data, secure-read ordering, unchanged storage and no ACK before durable
  commit are protected. Direct/outbound producers retain their existing
  canonical staging path. These source/database regressions are distinct from
  native crash attribution; device and signed-candidate evidence stays in the
  investigation record.

- **Direct-media contact handoff:** generic intro commands are consumed before
  awaited work completes. Staging both commands and then cold-relaunching each
  app lets the old receiver consume its command before the host kills it;
  the replacement has no command and the old receipt appears stalled. Stop
  and verify both previous processes absent before staging either command,
  then start both without another force-stop. Controlled old-poller and failed
  stop-verification regressions protect this handoff. Initial custody actions
  also stop before staging: retaining their config until completion did not
  prevent an old process from starting effects or deleting a failed request.
  Resume/reopen paths already used the correct order and remain unchanged.

- **Remote ICE drain capacity:** authenticated ICE can overtake its earlier
  SDP within the existing 64-sequence reordering window. The executor could
  retain 64 candidates but submitted them as one batch to a WebRTC wrapper
  limited to eight; nine or 64 ended negotiation. The executor now reads the
  engine's batch capacity, preserves order and future generations, and fences
  each batch against closure, call replacement and generation changes. A later
  partially applied batch terminalizes through existing cleanup without replay;
  answer delivery now shares the coordinator's hangup interruption fence.
  `call_remote_ice_drain_test.dart` covers authenticated admission through the
  real executor and wrapper, including 0/1/8/9/64, overflow, configured capacity,
  deduplication, malformed material, relay policy, restart and controlled waits.
  It is registered in `call-signaling` in the existing selection manifest.
  `.codex-test-logs/remote-ice-drain/red-reordered.log` retains the failing
  single-batch counterexample; `focused.log` records the passing regression and
  preservation suites. Crypto primitives and native WebRTC remain fakes, so this
  evidence establishes the application boundary, not live audio or device RTP.
- **Mixed ICE policies and media privacy:** relay-only is a local gathering and
  transport policy. Authenticated remote host, server-reflexive, peer-reflexive
  and relay candidates must pass the same structural/native validation under
  either local policy. Applying the local relay filter to remote trickle ICE or
  embedded SDP terminated otherwise valid mixed-policy negotiation. The engine
  now separates common fingerprint/video/candidate validation from local SDP
  privacy validation; local trickle and SDP also reject unsanitized TURN `raddr`
  and `rport`. Native `iceTransportPolicy=relay` remains the primary control at
  creation and server replacement/restart; filtering SDP alone does not prevent
  direct connectivity checks. No SDP rewriting or policy downgrade is used.
  The locked `flutter_webrtc` 1.6.0 Android dependency is WebRTC SDK 144.7559.09.
  Its M144 source maps relay to `CF_RELAY`, sanitizes TURN related addresses when
  reflexive candidates are forbidden, and skips remote DNS/mDNS resolution in
  relay mode. The stats sampler follows `localCandidateId`; a remote relay with
  an ordinary local host/reflexive candidate cannot prove local compliance.
  Native testing also caught M144 changing a TURN candidate to `prflx` after
  address remapping while retaining its TURN port. `RTCStatsCollector` exposes
  `relayProtocol` for exactly that local case. The sampler now recognizes only
  known local UDP/TCP/TLS relay protocols on `prflx`; generic `protocol`, URLs,
  remote relay fields and missing/unrecognized local evidence cannot certify it.
  See the SDK's [stats collector](https://github.com/webrtc-sdk/webrtc/blob/30d5e63ae91da483e06577b5c35ee91cc5e5c3db/pc/rtc_stats_collector.cc#L1037)
  and [candidate remapping](https://github.com/webrtc-sdk/webrtc/blob/30d5e63ae91da483e06577b5c35ee91cc5e5c3db/p2p/base/connection.cc#L1812).
  Host regressions cover all four policy combinations in both directions,
  embedded/trickle ICE before and after restart, egress, and late negotiation
  work after hangup. Existing fingerprint, sender, size/capacity and generation
  sentinels remain required. Red/green and separate native evidence are retained
  under `.codex-test-logs/mixed-call-policy/`. The optional existing real-adapter
  integration test extension audits raw native candidates, wrapper egress,
  gathered SDP address fields, selected local native statistics and advancing
  bidirectional RTP. Its local broker bypasses production signaling and cannot
  prove authenticated libp2p delivery, audible audio, or signed/iOS parity.
  The Pixel 6 (API 37) / Android emulator (API 35) TCP run passed all eight
  policy/direction cases and their restarts: 32 endpoint observations, including
  16 protected observations with sanitized native egress and selected local TURN.
  The final receipt records 6 or 8 real host candidates plus 2 relay candidates
  from normal peers, and exactly 2 relay candidates from protected peers. Thus
  the native mixed-policy cases exercised remote non-relay ingress explicitly.
  One normal endpoint selected a local host candidate while the protected peer
  selected its local relay, establishing an actual direct/TURN media pairing.
  The initial UDP attempt failed reverse all/all negotiation because the proof
  delayed SDP publication until full candidate gathering. The physical answerer
  failed ICE before its late answer was sent; a repeat also exhausted the proof's
  gathering deadline before sending the reverse offer. Production already sends
  SDP promptly. The proof now matches that ordering and exchanges bounded,
  generation-specific candidate batches while both endpoints gather. It accepts
  gathering completion only after a current-generation candidate, then audits
  native gathered SDP separately. That bounded audit allows 60 seconds because
  native UDP gathering was observed near 40 seconds even with working media;
  it does not gate SDP publication or extend production call deadlines.
  The current native run exercises remote
  trickle ICE; embedded remote SDP remains covered by the host regressions and
  earlier full-gather TCP evidence. This changes the proof, not media policy or
  production signaling. The test relay port range also stays below this macOS
  host's ephemeral UDP range after an observed startup bind conflict.
  The corrected UDP matrix passed all eight policy/direction cases and restarts:
  32 endpoint observations, including 16 protected observations (12 local relay
  and 4 local TURN-backed `prflx`). SDP acknowledgment took 24–317 ms while the
  longest gathering observation took about 40 seconds. The red/green receipts
  and scoped checks are retained under `.codex-test-logs/mixed-call-udp/`.
  The same final APK also passed the complete TCP preservation matrix.
  Earlier fixture failures and the native selected-pair regression remain in
  the evidence directory; a later passing run does not erase them. The runner
  requires explicit endpoint receipts because this Flutter driver was observed
  exiting zero even when its device log reported failed integration tests.
  Direct libp2p signaling can independently reveal an address; this media policy
  does not make all application traffic anonymous.
- **Readiness observation exceptions:** native snapshot reads can throw
  `WebRtcAdapterException(other)` after recording a fixed WebRTC read stage.
  The real engine wrapper now translates this to `observationUnavailable`;
  readiness retries it and `notReady` on the existing cadence/sample cap without
  resetting the canonical setup/reconnect deadline or reusing successful media
  evidence. Per-read timeouts return the same conservative snapshot as the
  aggregate deadline; partial transceiver/statistics reads cannot certify
  readiness. Explicit transport/configuration/relay-policy failures and
  unexpected exceptions request one exact-call canonical failure. Closed or
  replaced work is fenced before dispatch; successful cleanup still belongs to
  the coordinator/audio owner. Executor diagnostics retain only fixed stages,
  codes and counts; native stage diagnostics retain the failing read boundary.
  `call_readiness_exception_test.dart` uses the real coordinator, executor,
  audio controller and engine wrapper with fake platform/signaling ports and
  captures unhandled asynchronous errors. It checks initial/later observation,
  bounded retry, terminal cleanup, dispatch errors and subsequent-call isolation.
  Engine tests additionally cover native stats failure, incomplete reads and
  optional diagnostic sink failure. Red/green evidence is retained under
  `.codex-test-logs/readiness-exceptions/`. These are host lifecycle and ownership
  proofs, not live microphone, libp2p, audible audio or signed-device evidence.
- **TURN availability and frozen call policy:** normal (`all`) setup and restart
  may attempt direct media after a five-second credential timeout or a typed
  transient service failure. Preserve the approved STUN entries supplied by the
  production build configuration; direct host candidates alone do not prove
  LAN or arbitrary-NAT reachability. Relay-only still requires unexpired TURN.
  Invalid/expired bundles,
  unsupported responses, explicit authorization rejections and unknown errors
  fail closed. Legacy native `UNAVAILABLE` responses are also ambiguous and
  fail closed: only the new classified `TRANSIENT` native code is eligible for
  fallback. Go preserves non-transient rejections across relay attempts;
  connection errors before authentication are conservative unless a deadline is
  proven. One validated bundle is retained per call, reused only while unexpired
  on transient refresh failure, and cleared on close. There is no persistent
  storage or background retry loop.
  Initial preparation and restart recheck exact call ownership after awaiting
  credentials. Late results never install credentials or trigger a restart;
  a later canonical restart fetches again with the call's frozen policy and
  replaces old ICE servers, including clearing TURN on a transient outage.
  `call_turn_policy_test.dart` exercises the real coordinator, preparer, provider,
  executor and WebRTC wrapper using a virtual clock and controlled futures.
  It also caught reconnect timer scheduling after the credential wait; scheduling
  now precedes restart so retrieval consumes the existing 15-second window.
  Focused bridge/provider tests preserve strict validation and coarse diagnostics.
  The production composition test preserves native audio-failure diagnostics
  after startup cleanup ends the call; stale success remains fenced so it cannot
  notify native readiness for a retired call.
  These host tests model selected direct/TURN routes; they do not prove live
  Wi-Fi calling, TURN allocation or audible device media. Red/green evidence is
  retained under `.codex-test-logs/turn-policy/`.
- **Saved call privacy and rollout policy:** availability of **Always relay
  calls** no longer selects a transport. Its stable secure-store preference is
  independent of `VOICE_CALL_FORCE_RELAY_ENABLED`; the release defines disable
  that restriction for normal calls after the mixed-policy proofs below, while
  the production-audio Sims profile explicitly retains it for its TURN oracle. No build
  flag seeds or overwrites the preference. An absent value permits normal mode;
  read errors, a two-second read timeout and unknown values resolve relay-only.
  The settings sheet waits for durable writes, reports failures and disables
  changes when a read fails. The production composition captures the policy at
  the coordinator's first admitted session, before ringing/native adoption or
  media allocation, and retains it in that call's executor for ICE restarts.
  Later preference changes affect subsequent calls, including when the settings
  feature is hidden. Approved STUN comes from the operator's build configuration
  and is kept alongside the existing authenticated TURN provider.
  Production composition, secure-storage MethodChannel, settings-sheet and real
  WebRTC-adapter configuration tests cover these boundaries. They do not prove
  native persistent storage across an actual installed upgrade.
  The current Pixel 6/API 37 and API 35 emulator native media proof passed the
  eight policy/direction cases plus restarts over UDP and TCP: 64 endpoint
  observations, with local TURN and sanitized egress on all 32 protected
  observations. Normal/all peers selected direct routes on Wi-Fi and TURN/TCP
  when physical Wi-Fi was disabled and TURN remained reachable over USB; the
  original Wi-Fi setting was restored. Evidence is retained under
  `.codex-test-logs/call-transport-settings/`. This local-broker proof does not
  exercise production signaling, the settings-to-native wake journey, audible
  media, iOS parity or signed artifacts. Opening the direct-first source default
  does not certify publication of a signed release. Direct libp2p signaling may
  independently reveal an address.
  The mixed-policy driver must be classified as a support wrapper in reliability
  simulation discovery. An unclassified driver also fails the global discovery
  assertion used by the PiP native contract; it does not indicate a PiP failure.
  Pin the SDK resolved by this checkout's package configuration: using the
  shell's Flutter 3.41.4 with these Flutter 3.47.2 packages failed native-asset
  kernel loading and Flutter UI compilation; the pinned 3.47.2 build passed.
- **Sustained call-event delivery:** adapter and engine history capacity is not
  a lifetime callback quota. The old delivered-event totals fabricated overflow
  once capacity was reached, even with synchronous consumers keeping up. Both
  layers now keep delivering while evicting old diagnostic history. The native
  emitter handles reentrant callbacks with at most a disconnect edge plus the
  latest event. The executor likewise retains one coalesced record (at most two
  pending events) behind one asynchronous drain; failure supersedes ordinary
  updates, and a disconnect cannot hide the latest recovery state. Production
  consumers keep stream subscriptions unpaused and coalesce awaited work in the
  executor. This does not bound buffers created by arbitrary paused subscribers.
  Candidate queues, batch capacities and the coordinator's pending-event limit
  remain independent and enforced. ICE restart still advances generation; it
  does not reset an event-delivery quota. `call_engine_event_delivery_test.dart`
  drives a fake native peer through both real emitters and the real executor and
  coordinator, checking 65/256/1,000 consumed callbacks, slow readiness, priority,
  reentrancy, close and stale callbacks. The build contract now asserts complete
  delivery and bounded history rather than the defective lifetime cutoff.
  `.codex-test-logs/event-delivery/` retains red/green evidence. These deterministic
  host tests establish application queue and cleanup behavior, not native callback
  frequency, long-duration device memory usage or live call quality.
- **Local Android audio isolation:** the existing production-call journey now
  fixes its build/cache/driver identity to `com.mknoon.sims.productionaudio`.
  Its activity class remains `com.mknoon.app.MainActivity`. Keep native calls
  enabled and Google Services disabled only for this local relay/coturn proof;
  the FCM profile must retain its provider configuration. Assert resolved build
  arguments and semantic owners, rather than global source-text occurrence
  counts. The exact system-owned Answer, RTP/oracle and cleanup assertions
  remain required; host contracts cannot certify actual audio or publication.
  UIAutomator reads must be coalesced per device: concurrent Connected/control
  assertions otherwise compete for Android's UiAutomation connection. Treat a
  missing-file message from `adb exec-out cat` as an unavailable capture even
  when its host exit code is zero; it never proves that a control is absent.
  Retry only inside the existing semantic deadline and reopen the native shade
  for each Answer attempt because an incoming window may replace it. The
  foreground WebRTC harness uses the same current-call guard and per-call TURN
  provider lifecycle as production; its importing readiness test belongs in the
  call-signaling gate so preparer API changes cannot leave it uncompilable.
  The foreground relay campaign's three-second p95 gate remains independent of
  transport success: a typed latency failure reports the measured p95 after
  valid direct/UDP/TCP media and cleanup legs, rather than hiding it as an
  unexpected malformed-evidence exception. A latency failure is still FAIL and
  produces no passing campaign artifact.
  The Pixel 6/API 35 emulator run passed all 27 actual audio assertions with
  both native call resources released and original app state restored.

- **iOS build identity:** device-profile cache arguments must include the same
  `SWIFT_ACTIVE_COMPILATION_CONDITIONS` supplied to Xcode. The production
  receiver-bootstrap flag was used by the builder but omitted by the pure
  fingerprint helper; the regression now fails on that omission and preserves
  Release/no-DEBUG arguments. This protects artifact identity, not native
  termination behavior. Shared NSE sources compiled in RunnerTests require the
  target-only test marker in Debug, Release and Profile. Keep that marker
  independent of global Swift condition overrides and avoid making test-only
  imports depend on DEBUG. The same Release app/NSE/test build now compiles;
  the five existing native configuration assertions preserve target isolation.

Reuse `AppDiagnostics` and `docker-ws/app_diagnostics.py` before adding logging.
Their existing schema/privacy tests constrain bounded structured diagnostics.
Observed receive/decrypt/store/media events may locate a failed boundary; endpoint
correlation alone does not prove custody, displayed content, or recipient open.
Only report a checkpoint that the retained instrumentation actually observes.
State an investigation area separately from a proven root cause.

- **Confirmed diagnostic performance regression:** recording app/call events
  could synchronously scan and JSON-encode the retained archive on Flutter's
  UI isolate despite `unawaited` persistence; native collectors also queued
  unbounded per-event archive rewrites. A multi-megabyte settings export was
  laid out as one selectable text widget. Collection now uses indexed admission,
  coalesced persistence, background serialization, bounded native queues/batches,
  and an 8,192-character visible preview while preserving full copy/export.
  Moving a full snapshot to `Isolate.run` was insufficient: a physical Pixel 6
  profile with a 3.8 MB archive still showed periodic frame gaps up to 94 ms.
  The shared persistent archive worker therefore receives changed rows only;
  ordinary retention checks skip the archive walk until expiration is due.
  Preserve this distinction when adding diagnostic work: asynchronous disk I/O
  or background encoding alone does not prove a nonblocking foreground path.
  The one-second Dart write window can lose the newest diagnostic observations
  on abrupt termination; explicit flush, lifecycle, clear and consent boundaries
  bypass that window. This never changes the underlying message/call outcome.
  App/call diagnostic and settings regressions cover blocked/failed writers,
  explicit-flush joining, consent races, quotas, terminal preservation and full
  clipboard export. The `diagnostics` selector now includes those consumers.
  An earlier physical Pixel 6 profile compared disabled, original and updated
  collection in three rotated repetitions with 9,760 retained events and 600
  new observations. Ten-event admission median fell from 69.35 ms to 3.42 ms;
  frame total-span p95 was 8.37 ms versus 8.22 ms with diagnostics disabled.
  The updated collector had no ticker gaps over two 90 Hz frame intervals,
  but small additional jitter remained. This isolated Android profile used
  the actual Dart collector with native collection and transport disabled;
  it does not certify whole-app behavior, physical iOS, battery or a signed
  release. Exact inputs, source identities and repeated results are under
  ignored `.codex-test-logs/diagnostics-ux/device-iterations/02-incremental-writer/`;
  the earlier full-snapshot iteration and its residual pauses remain alongside
  it. Red/green logs are retained under `.codex-test-logs/diagnostics-ux/`.
  Follow-up CPU profiling attributed most residual admission time to secure ID
  generation, validation and duplicate JSON byte encoding. UUID generation now
  requests the same 16 secure bytes in four 32-bit draws, preserving all 122
  random UUIDv4 bits. Closed schema membership is cached. Exact quota counting
  avoids allocating event JSON buffers; its cache contains only fixed schema
  strings and cannot grow with runtime IDs. Preserve differential coverage
  against Dart's JSON encoder, including Unicode/surrogates, escaping, integer
  limits, finite doubles, mutable containers and quota boundaries when changing
  this counter or upgrading the SDK. Worker persistence also caches encoded
  event rows; unchanged history is copied into the atomic file without repeated
  JSON traversal. An intermediate host writer benchmark reduced median 64-row saves
  from 22.366 ms to 2.804 ms with identical output bytes; filesystem write volume
  is unchanged. Evidence is under `writer-fragment-benchmark/` and
  `device-iterations/03-residual-profile/` within the ignored diagnostics run.
  Large private binding and upload-acknowledgment indexes also caused periodic
  pauses when copied, transferred and encoded in full on every save. Ordinary
  saves now transfer individual binding and acknowledgment changes; the worker
  retains encoded metadata entries as well as rows. Bindings use a cached expiry
  deadline, so fresh entries are not rescanned on each save. The first commit,
  clear/opt-out and failure retry still supply full sanitized metadata. Preserve
  synchronous snapshot ownership before awaiting, removal-before-reinsertion
  ordering for binding eviction, ACK removal on event expiry/eviction, and full
  reset semantics. Real-file regressions cover those boundaries and restart.
  File assembly uses a reusable 64 KiB buffer; its intermediate host benchmark
  increased write latency by roughly 2–2.5 ms and did not by itself remove the
  phone's metadata-rich save pauses. Do not attribute a frame improvement to
  buffering alone. A separate GC trace associated only some pauses with garbage
  collection; synchronous metadata work remained another candidate. All phone
  acceptance comparisons exclude VM sampling and GC polling. Full intermediate
  results, including worse tails, are retained in
  `device-iterations/performance-review.md` within the ignored diagnostics run.
  With metadata deltas, three physical Pixel 6 repetitions using 1,000 bindings,
  9,760 acknowledged seed events and 600 new observations each had zero frame
  spans or ticker gaps over 16.7 ms, matching the disabled control. The preceding
  metadata-rich version had seven long frame spans and nine long ticker gaps,
  reaching 46.176 ms. All retained IDs, bindings, ACKs and queued-event assertions
  passed. Evidence is under `device-iterations/07-metadata-deltas/metadata-rich/`;
  this remains a bounded isolated Android workload, with the limits above.
  A newly added joining-flush regression first failed, then passed after the
  flush also waited for newly admitted state.
- **Confirmed widget teardown race:** `conversation_wired_test.dart`
  `TC-366-01b` waits for the initial loading shell to disappear, which does not
  join the unawaited `_recoverVisibleMedia` database query. A curated run left
  sqflite's 10-second lock-acquisition warning timer pending at widget teardown;
  the exact case passed unchanged in isolation. Neither diagnostics collector
  is active in that case. Do not treat a disappearing loading indicator or a
  passing isolated repeat as proof that background database work has completed.
  Preserve the initial failure separately from any diagnostic rerun. The stack,
  source audit and both execution results are under ignored
  `.codex-test-logs/diagnostics-ux/device-iterations/07-metadata-deltas/`.
- **Confirmed runner hazard, prior evidence:**
  `artifacts/phantom-notification-20260910/host-runner-audit.md` records a
  222-path 1:1 Flutter invocation with 3,747 passes and four skips in about
  157 seconds, followed by an in-flight shell edit causing an unbound status
  and exit zero. These are historical results, not validation of this candidate.
  Lesson: preserve runner status independently, reject zero/incomplete execution,
  record skips, and do not edit a running runner. The new workflow's failure
  tests reproduce the exit-zero/unbound-variable mechanism in a disposable shell
  fixture and verify its corrected control. The historical runner itself was
  not executed.
- **Confirmed shared build hazard, prior evidence:** the same audit records
  parallel native manifest checks writing the same gomobile AAR and corrupting
  it; sequential checks restored it (about 18 seconds plus six seconds).
  Keep shared native artifact mutations serialized or use isolated outputs.
- **Historical product counterexample:**
  `artifacts/phantom-notification-20260910/predeployment_reproduction.md` records
  an intentionally failing old-notification-history Go overlay and a passing
  retained-history control. This is prior evidence, not an old-worktree test
  performed during this implementation. Do not claim all selected checks have
  demonstrated sensitivity to historical broken versions.
- **Documented acceptance limitation:**
  `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md`
  (§ GAP-N05) separates bounded Dart/native final-effect proofs from outstanding
  physical Apple, activation/operations and release acceptance. Preserve that
  distinction; host success cannot close those conditions.

For a newly confirmed regression, update the relevant entry using:
**symptom → cause or first confirmed failing boundary → affected behavior →
regression test → selection-rule update → evidence**. Mark hypotheses explicitly.
Preserve unresolved failures until a same-revision result and explanation resolve
them; do not hide them through quarantine or overwritten rerun records.

## Skill use and maintenance

Explicit invocations in a new Codex session opened at this repository are:

```text
Use $mknoon-change-check with base <verified-ref> for my local changes.
Use $mknoon-release-check with previous published revision <verified-ref>.
Use $mknoon-test-maintenance for the changed tests and confirmed regression.
```

The skills live in `.agents/skills/<name>/SKILL.md` with name/description
frontmatter. Start a new session if this running session's skill catalog predates
their creation; no plugin installation is required. The AGENTS skill invocation
policy still requires an explicit request by name. Ordinary coding work uses the
same scripts directly, without invoking a skill automatically.

Existing `run-flutter-host-gates`, `flutter-test-orchestrator`, and
`flutter-full-regression-runner` were inspected as prior art. They provide host
execution, advisory selection, or full sweeps; they lack this baseline-aware
release evidence contract. The three new skills are small adapters over one
wrapper, not copies of selector logic or a new orchestration system.

When tests, runners, fixtures, shared dependencies, configuration or confirmed
regressions change, refresh discovery, inspect the affected assertions, update
the manifest and this knowledge, and validate before claiming completion.
Deleted/renamed tests must not leave stale green references. CI must report gaps
and preserve artifacts, never rewrite tracked rules or testing memory.

To refresh and validate a saved inventory snapshot, then test the workflow:

```bash
python3 scripts/mknoon_checks.py discover --list-runners --output .codex-test-logs/inventory-review
python3 scripts/mknoon_checks.py validate --inventory .codex-test-logs/inventory-review/inventory.json
python3 -m unittest discover -s scripts/test -p '*checks_test.py'
python3 -m unittest discover -s scripts/test -p 'testing_inventory_test.py'
```

The saved-inventory check rejects missing entries and a changed discovery
fingerprint; refresh and inspect the difference rather than accepting stale
metadata. Do not commit generated inventory/run artifacts into testing memory.


## Implementation validation and open failures (2026-09-10)

The final inventory refresh discovers 1,960 candidate test files across ten runner
families, with 343 helper/fixture/generated files distinguished. Dynamic test-case
counts remain unknown until execution. Safe listings measured 2.284 seconds total:
1,496 host commands, 32 SIMS full capabilities, 54 orchestration contract groups and
95 legacy full routes. These are separate counts and overlapping inventories.

The workflow itself has 32 selector/runner contracts and five inventory contracts.
They pass, including Git rename/delete/local-diff fixtures, mandatory selection,
real isolated Python processes, SDK mismatch, zero/skipped execution, the
historical exit-zero shell-error mechanism, strict SIMS receipts, timeout cleanup,
manual evidence and preserved first failures. No application test was added or
weakened by this implementation.

A real wrapper diagnostic selection executed all 13 mandatory host groups plus
workflow, existing Python diagnostic and Node provider checks: **432 passed,
2 failed, zero skipped, 65.035 seconds total**. The report retains every omitted
changed-area/device check as NOT RUN and reports overall FAIL; this was a bounded
workflow validation, not validation of the entire pre-existing working-tree diff.
The measured per-group values (including failures) are in each check's
`runtime_basis`; estimates do not imply success or include unknown device builds.
Evidence: `.codex-test-logs/workflow-compatible-host/results.json` and
`summary.txt`; source fingerprint and commands are retained there.

Two earlier failures remain in the retained evidence and mandatory selections:

- Attachment long-press action context: the case declared at
  `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart:250`.
  Investigate context-overlay action wiring and the widget fixture; exact cause
  is unproven. The `media-viewer` selection retains this failure.
- Migrated-out erase preserving delivered notifications while clearing iOS
  recovery: the case declared at
  `test/features/identity/presentation/screens/startup_router_recovery_test.dart:508`.
  Investigate migration erase/recovery sequencing and the fixture; exact cause
  is unproven. The `startup` selection retains this failure.

The later crash-investigation run passed both complete suites (19 media-viewer
and 26 startup tests) without modifying their production paths or tests. The
difference in outcomes remains unexplained; those passes do not establish a
fix for the earlier failures. The retained first failures remain authoritative
for their own run. See the focused investigation record and
`artifacts/testflight-crash-investigation-20260910/check-final/results.json`.

A two-file diagnostic rerun reproduced both failures (43 passed, two failed,
9.470 seconds); focused failed-case reruns also failed. Sanitized follow-up
receipts live in `.codex-test-logs/workflow-diagnostic-followup/`. The exact failed
assertion was not exposed by the machine errors. Flutter's reported line 174
belongs to its `testWidgets` wrapper, not either suite; current reports retain the
reported location URL to avoid attributing framework lines to app tests.

The first attempt with the default PATH was BLOCKED before Flutter cases ran:
Flutter 3.41.4 was selected while `.dart_tool/package_config.json` resolved Flutter
3.47.2. `.codex-test-logs/workflow-real-host/` preserves that 124.066-second attempt.
Use the SDK matching the candidate's package configuration (3.47.2 in this
checkout); the new preflight rejects a mismatch without repeating every suite.
The compatible SDK was selected only for the test process; no SDK or production
configuration was repaired during this task.

The release preview without a published baseline correctly returned BLOCKED
(exit 2), recorded in `.codex-test-logs/workflow-missing-release-baseline/`.
No actual previous published revision or signed AAB/IPA was supplied for build
1.0.1(117). Device campaigns, signed upgrade/compatibility/audio checks and full
regression were not executed. The inventory found a USB Pixel, USB iPhones and
available iOS simulators; Android AVDs Codex_API35 and Pixel_7 exist but were not
running. Disposable device identities/services were not established, so existing
apps/data were not touched. Unavailable version-specific hardware is N/A under
project policy; this does not turn missing essential journey evidence into PASS.

CI YAML was parsed locally and its commands/metadata validated. No remote CI run,
schedule activation, runner provisioning, branch protection or distribution
artifact validation occurred. Existing full entry points have some inherited
coverage overlap; do not sum their counts as unique cases. Weekly execution has a
three-day job budget and does not cancel an active run; queued runs use `queue: max`.
Measure the first full run before claiming the cadence is sufficient. If it hits
its budget, retain its incomplete report and divide the existing routes into
same-revision partitions before relying on scheduled completion. GitHub's
[self-hosted execution limit](https://docs.github.com/en/enterprise-cloud%40latest/actions/reference/limits)
is five days; the full-run command retains its own bounded process timeouts.

`prior_full_failures` exposes known local full-run failures without replacing them
with unrelated green runs. The mandatory `signed-full-review` evidence records
review of unresolved failures, revision consistency and untested conditions.
Legacy/SIMS raw nested logs remain private local evidence. CI exports only the
wrapper's restricted plan/result/partial/error/summary files; inspect and redact
any additional screenshots or diagnostic artifacts before sharing them.

The local Git exclude file ignored AGENTS.md and .agents/. Narrow tracked
.gitignore exceptions now expose AGENTS.md and the three Mknoon skills while
leaving other local skill directories excluded. Their instructions and adapters
can therefore travel with the repository instead of remaining machine-only.


Final preservation checks ran through the real wrapper in 14.810 seconds:
workflow contracts, Flutter bootstrap, Python diagnostics and Node provider
checks all passed. The omitted worktree checks remained NOT RUN and unresolved
mappings kept overall status BLOCKED, as intended. See
`.codex-test-logs/workflow-final-sentinels/results.json`. Final metadata,
byte-compilation, skill references, YAML parsing and whitespace validation passed.
The last focused contract run passed all 32 wrapper and five inventory tests.
The final inventory and its validation are in
`.codex-test-logs/workflow-final-inventory/`.

Graphify's separate process audit reported historical navigation cadence/handoff
violations and classified the new tooling files as pending impact work. This is
not a product-test result. No app-owned production code changed; the project
explicitly excludes tooling-only edits from the post-edit affected/refresh step.
No claim of passing that process audit or token savings is made.
